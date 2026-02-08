--!strict

-- server-side downed/revive system: intercepts player death, manages downed state,
-- bleedout timer, teammate revive via ProximityPrompt, QuickRevive self-revive,
-- true death on bleedout, and round-end respawning

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

--------------------------------------------------
-- Constants
--------------------------------------------------

local BLEEDOUT_TIME = 30          -- seconds before true death
local REVIVE_HOLD_TIME = 3        -- seconds teammate must hold prompt
local QUICK_REVIVE_HOLD_TIME = 5  -- seconds for self-revive
local REVIVE_HEALTH_PERCENT = 0.5 -- revive at 50% max health
local REVIVE_RANGE = 8            -- studs for ProximityPrompt
local CRAWL_SPEED = 4             -- studs/sec while downed (normal ~16)

--------------------------------------------------
-- Remotes
--------------------------------------------------

local PlayerDownedRemote = RemoteService.GetRemote("PlayerDowned") :: RemoteEvent
local PlayerRevivedRemote = RemoteService.GetRemote("PlayerRevived") :: RemoteEvent
local PlayerDiedRemote = RemoteService.GetRemote("PlayerDied") :: RemoteEvent
local BleedoutUpdateRemote = RemoteService.GetRemote("BleedoutUpdate") :: RemoteEvent
local RequestSelfReviveRemote = RemoteService.GetRemote("RequestSelfRevive") :: RemoteEvent
local ReloadAllWeaponsRemote = RemoteService.GetRemote("ReloadAllWeapons") :: RemoteEvent

--------------------------------------------------
-- State
--------------------------------------------------

type DownedData = {
	bleedoutRemaining: number,
	originalWalkSpeed: number,
	originalJumpPower: number,
	revivePrompt: ProximityPrompt?,
	usedQuickRevive: boolean,
}

local downedPlayers: { [Player]: DownedData } = {}
local deadPlayers: { [Player]: boolean } = {}
local trueDeath: { [Player]: boolean } = {}
local healthConnections: { [Player]: RBXScriptConnection } = {}

--------------------------------------------------
-- Bindable Events (cross-service communication)
--------------------------------------------------

-- DownedService creates this; ZombieSpawner fires it at round end
local roundEndedEvent = Instance.new("BindableEvent")
roundEndedEvent.Name = "RoundEndedBindable"
roundEndedEvent.Parent = ServerScriptService

-- DownedService creates this; PerkService listens to remove a specific perk
local removePerkEvent = Instance.new("BindableEvent")
removePerkEvent.Name = "RemovePerkBindable"
removePerkEvent.Parent = ServerScriptService

-- rate limiter for self-revive requests
local checkSelfReviveLimit, cleanupSelfReviveLimit = RemoteService.CreateRateLimiter(1.0)

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function IsPlayerDowned(player: Player): boolean
	return downedPlayers[player] ~= nil
end

local function IsPlayerDead(player: Player): boolean
	return deadPlayers[player] == true
end

local function GetAlivePlayerCount(): number
	local count = 0
	for _, p in Players:GetPlayers() do
		if not IsPlayerDead(p) and not IsPlayerDowned(p) then
			count += 1
		end
	end
	return count
end

--------------------------------------------------
-- Revive Player
--------------------------------------------------

local function RevivePlayer(player: Player, reviver: Player?, fullHealth: boolean?)
	local data = downedPlayers[player]
	if not data then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- restore movement
	humanoid.WalkSpeed = data.originalWalkSpeed
	humanoid.JumpPower = data.originalJumpPower
	humanoid.PlatformStand = false

	-- restore health (full on round-end, 50% on mid-round revive)
	local reviveHealth = if fullHealth
		then humanoid.MaxHealth
		else humanoid.MaxHealth * REVIVE_HEALTH_PERCENT
	humanoid.Health = reviveHealth

	-- remove revive prompt
	if data.revivePrompt then
		data.revivePrompt:Destroy()
	end

	-- clear downed attribute
	player:SetAttribute("IsDowned", nil)

	-- clean up state
	downedPlayers[player] = nil

	-- notify all clients
	PlayerRevivedRemote:FireAllClients({
		playerId = player.UserId,
		reviverId = if reviver then reviver.UserId else nil,
	})
end

--------------------------------------------------
-- True Death (bleedout expired)
--------------------------------------------------

local function HandleTrueDeath(player: Player)
	local data = downedPlayers[player]

	-- remove revive prompt
	if data and data.revivePrompt then
		data.revivePrompt:Destroy()
	end

	-- clean up downed state
	downedPlayers[player] = nil
	player:SetAttribute("IsDowned", nil)

	-- mark as truly dead
	deadPlayers[player] = true
	trueDeath[player] = true

	-- kill the player for real (HealthChanged will allow it due to trueDeath flag)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end

	-- notify all clients
	PlayerDiedRemote:FireAllClients({
		playerId = player.UserId,
	})

	-- check if all players are dead (game over condition)
	local anyAlive = false
	for _, p in Players:GetPlayers() do
		if not IsPlayerDead(p) then
			anyAlive = true
			break
		end
	end

	if not anyAlive and #Players:GetPlayers() > 0 then
		-- all players dead - game over
		-- for now, just print; full game over flow can be added later
		warn("[DownedService] All players dead - game over")
	end
end

--------------------------------------------------
-- Enter Downed State
--------------------------------------------------

local function EnterDownedState(player: Player)
	if IsPlayerDowned(player) or IsPlayerDead(player) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- save original movement stats
	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower

	-- enter crawling state
	humanoid.WalkSpeed = CRAWL_SPEED
	humanoid.JumpPower = 0

	-- set downed attribute (used by ZombieAI and ZombieDamage to skip this player)
	player:SetAttribute("IsDowned", true)

	-- create revive ProximityPrompt on character for teammates
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local prompt: ProximityPrompt? = nil
	if rootPart then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Revive"
		prompt.ObjectText = player.DisplayName
		prompt.HoldDuration = REVIVE_HOLD_TIME
		prompt.MaxActivationDistance = REVIVE_RANGE
		prompt.RequiresLineOfSight = false
		prompt.Parent = rootPart

		prompt.Triggered:Connect(function(playerWhoTriggered: Player)
			-- prevent self-trigger (self-revive uses a different mechanism)
			if playerWhoTriggered == player then
				return
			end

			-- reviver must be alive and not downed
			if IsPlayerDowned(playerWhoTriggered) or IsPlayerDead(playerWhoTriggered) then
				return
			end

			local reviverChar = playerWhoTriggered.Character
			if not reviverChar then
				return
			end
			local reviverHumanoid = reviverChar:FindFirstChildOfClass("Humanoid")
			if not reviverHumanoid or reviverHumanoid.Health <= 0 then
				return
			end

			RevivePlayer(player, playerWhoTriggered)
		end)
	end

	-- store downed data
	local hasQuickRevive = player:GetAttribute("HasQuickRevive") == true

	downedPlayers[player] = {
		bleedoutRemaining = BLEEDOUT_TIME,
		originalWalkSpeed = originalWalkSpeed,
		originalJumpPower = originalJumpPower,
		revivePrompt = prompt,
		usedQuickRevive = false,
	}

	-- notify all clients
	PlayerDownedRemote:FireAllClients({
		playerId = player.UserId,
		bleedoutTime = BLEEDOUT_TIME,
		hasQuickRevive = hasQuickRevive,
		quickReviveHoldTime = QUICK_REVIVE_HOLD_TIME,
	})
end

--------------------------------------------------
-- Health Interception (per-character)
--------------------------------------------------

local function SetupHealthInterception(player: Player, character: Model)
	-- disconnect previous connection
	if healthConnections[player] then
		healthConnections[player]:Disconnect()
		healthConnections[player] = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	-- clear any stale state from previous life
	trueDeath[player] = nil
	deadPlayers[player] = nil
	downedPlayers[player] = nil
	player:SetAttribute("IsDowned", nil)

	healthConnections[player] = humanoid.HealthChanged:Connect(function(newHealth: number)
		-- player is downed and invulnerable: keep health at 1
		if IsPlayerDowned(player) and not trueDeath[player] then
			if newHealth < 1 then
				humanoid.Health = 1
			end
			return
		end

		-- true death allowed (bleedout expired): let death proceed
		if trueDeath[player] then
			return
		end

		-- intercept lethal damage: enter downed state instead of dying
		if newHealth <= 0 then
			humanoid.Health = 1
			EnterDownedState(player)
		end
	end)
end

--------------------------------------------------
-- Self-Revive (QuickRevive perk)
--------------------------------------------------

RequestSelfReviveRemote.OnServerEvent:Connect(function(player: Player)
	if not checkSelfReviveLimit(player) then
		return
	end

	if not IsPlayerDowned(player) then
		return
	end

	local data = downedPlayers[player]
	if not data or data.usedQuickRevive then
		return
	end

	-- check for QuickRevive perk
	if player:GetAttribute("HasQuickRevive") ~= true then
		return
	end

	-- consume QuickRevive: one-time use per purchase
	data.usedQuickRevive = true
	removePerkEvent:Fire(player, "QuickRevive")

	RevivePlayer(player, nil)
end)

--------------------------------------------------
-- Bleedout Timer Loop
--------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)

		-- snapshot to avoid modifying table during iteration
		local snapshot: { Player } = {}
		for player in downedPlayers do
			table.insert(snapshot, player)
		end

		for _, player in snapshot do
			local data = downedPlayers[player]
			if not data then
				continue -- player was revived between snapshot and processing
			end

			data.bleedoutRemaining -= 1

			-- send timer update to downed player
			BleedoutUpdateRemote:FireClient(player, {
				timeRemaining = data.bleedoutRemaining,
				totalTime = BLEEDOUT_TIME,
			})

			-- bleedout expired: true death
			if data.bleedoutRemaining <= 0 then
				HandleTrueDeath(player)
			end
		end
	end
end)

--------------------------------------------------
-- Round End: Revive Downed + Respawn Dead
--------------------------------------------------

roundEndedEvent.Event:Connect(function()
	-- snapshot to avoid modifying tables during iteration
	local downedSnapshot: { Player } = {}
	for player in downedPlayers do
		table.insert(downedSnapshot, player)
	end

	local deadSnapshot: { Player } = {}
	for player in deadPlayers do
		table.insert(deadSnapshot, player)
	end

	-- revive all downed players with full health (round-end bonus)
	for _, player in downedSnapshot do
		if downedPlayers[player] then
			RevivePlayer(player, nil, true) -- fullHealth = true
		end
	end

	-- respawn all dead players (lose perks, already cleared by PerkService on Died)
	for _, player in deadSnapshot do
		trueDeath[player] = nil
		deadPlayers[player] = nil
		player:LoadCharacter()
	end

	-- reload all weapons for respawned players after a brief delay
	task.delay(1, function()
		ReloadAllWeaponsRemote:FireAllClients()
	end)
end)

--------------------------------------------------
-- Player Lifecycle
--------------------------------------------------

local function OnPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		SetupHealthInterception(player, character)
	end)

	if player.Character then
		SetupHealthInterception(player, player.Character)
	end
end

local function OnPlayerRemoving(player: Player)
	-- clean up all state
	if healthConnections[player] then
		healthConnections[player]:Disconnect()
		healthConnections[player] = nil
	end

	if downedPlayers[player] then
		local data = downedPlayers[player]
		if data.revivePrompt then
			data.revivePrompt:Destroy()
		end
		downedPlayers[player] = nil
	end

	deadPlayers[player] = nil
	trueDeath[player] = nil
	cleanupSelfReviveLimit(player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

for _, player in Players:GetPlayers() do
	OnPlayerAdded(player)
end

print("[DownedService] Initialized")
