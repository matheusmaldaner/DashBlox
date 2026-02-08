--!strict

-- server-side perk machine system: discovers tagged perk machines,
-- adds ProximityPrompts, handles purchases, applies effects, clears on death

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerkConfig = require(ReplicatedStorage.Modules.PerkConfig)
local CoinUtility = require(script.Parent.CoinUtility)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local PerkPurchasedRemote = RemoteService.GetRemote("PerkPurchased") :: RemoteEvent
local PerkLostRemote = RemoteService.GetRemote("PerkLost") :: RemoteEvent
local PerkSyncAllRemote = RemoteService.GetRemote("PerkSyncAll") :: RemoteEvent

-- track active perks per player: { [Player]: { [perkName]: true } }
local playerPerks: { [Player]: { [string]: boolean } } = {}

-- rate limiter for perk purchases
local checkPerkLimit, cleanupPerkLimit = RemoteService.CreateRateLimiter(1.0)

--------------------------------------------------
-- Perk Application
--------------------------------------------------

local function ApplyPerkEffect(player: Player, perkName: string)
	local stats = PerkConfig.Perks[perkName]
	if not stats then
		return
	end

	-- set attribute on player for other systems to check
	player:SetAttribute(stats.AttributeName, true)

	-- apply direct effects
	if stats.MaxHealth then
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.MaxHealth = stats.MaxHealth
				humanoid.Health = stats.MaxHealth
			end
		end
	end
end

local function ClearAllPerks(player: Player)
	local perks = playerPerks[player]
	if not perks then
		return
	end

	local lostPerks: { string } = {}
	for perkName, _ in perks do
		local stats = PerkConfig.Perks[perkName]
		if stats then
			player:SetAttribute(stats.AttributeName, nil)
			table.insert(lostPerks, perkName)
		end
	end

	-- reset max health if had Juggernog
	if perks["Juggernog"] then
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.MaxHealth = 100
				if humanoid.Health > 100 then
					humanoid.Health = 100
				end
			end
		end
	end

	playerPerks[player] = {}

	if #lostPerks > 0 then
		PerkLostRemote:FireAllClients({
			playerId = player.UserId,
			perksLost = lostPerks,
		})
	end
end

local function GetPerkCount(player: Player): number
	local perks = playerPerks[player]
	if not perks then
		return 0
	end
	local count = 0
	for _ in perks do
		count += 1
	end
	return count
end

--------------------------------------------------
-- Purchase Handling
--------------------------------------------------

local function HandlePerkPurchase(player: Player, perkName: string)
	if not checkPerkLimit(player) then
		return
	end

	local stats = PerkConfig.Perks[perkName]
	if not stats then
		warn("[PerkService] Unknown perk:", perkName)
		return
	end

	-- check if player already has this perk
	local perks = playerPerks[player]
	if not perks then
		perks = {}
		playerPerks[player] = perks
	end

	if perks[perkName] then
		return -- already owned
	end

	-- check max perk limit
	if GetPerkCount(player) >= PerkConfig.MaxPerks then
		return
	end

	-- check if player is alive
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- deduct coins
	if not CoinUtility.Deduct(player, stats.Cost) then
		return
	end

	-- grant perk
	perks[perkName] = true
	ApplyPerkEffect(player, perkName)

	PerkPurchasedRemote:FireAllClients({
		playerId = player.UserId,
		perkName = perkName,
	})
end

--------------------------------------------------
-- Machine Discovery (CollectionService)
--------------------------------------------------

local function SetupPerkMachine(machine: Instance)
	if not machine:IsA("Model") and not machine:IsA("BasePart") then
		return
	end

	local perkName = machine:GetAttribute("PerkName")
	if not perkName or typeof(perkName) ~= "string" then
		warn("[PerkService] PerkMachine missing PerkName attribute:", machine:GetFullName())
		return
	end

	local stats = PerkConfig.Perks[perkName]
	if not stats then
		warn("[PerkService] Unknown perk on machine:", perkName)
		return
	end

	-- find or create interaction part
	local interactPart: BasePart
	if machine:IsA("BasePart") then
		interactPart = machine
	else
		interactPart = (machine :: Model).PrimaryPart
			or (machine :: Model):FindFirstChildWhichIsA("BasePart") :: BasePart
	end

	if not interactPart then
		warn("[PerkService] No BasePart found in PerkMachine:", machine:GetFullName())
		return
	end

	-- skip if prompt already exists
	if interactPart:FindFirstChildOfClass("ProximityPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy " .. stats.DisplayName
	prompt.ObjectText = stats.Cost .. " Coins"
	prompt.HoldDuration = PerkConfig.PromptHoldDuration
	prompt.MaxActivationDistance = PerkConfig.PromptMaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = interactPart

	prompt.Triggered:Connect(function(playerWhoTriggered: Player)
		HandlePerkPurchase(playerWhoTriggered, perkName)
	end)
end

--------------------------------------------------
-- Death Handling (clear perks)
--------------------------------------------------

local function OnCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	-- re-apply Juggernog if player still has it (respawn)
	local perks = playerPerks[player]
	if perks then
		for perkName in perks do
			ApplyPerkEffect(player, perkName)
		end
	end

	humanoid.Died:Connect(function()
		ClearAllPerks(player)
	end)
end

--------------------------------------------------
-- Player Lifecycle
--------------------------------------------------

local function OnPlayerAdded(player: Player)
	playerPerks[player] = {}

	player.CharacterAdded:Connect(function(character)
		OnCharacterAdded(player, character)
	end)

	if player.Character then
		OnCharacterAdded(player, player.Character)
	end

	-- sync current perks to joining player
	task.defer(function()
		local allPlayerPerks: { [number]: { string } } = {}
		for p, perks in playerPerks do
			if p ~= player then
				local perkList: { string } = {}
				for perkName in perks do
					table.insert(perkList, perkName)
				end
				if #perkList > 0 then
					allPlayerPerks[p.UserId] = perkList
				end
			end
		end
		PerkSyncAllRemote:FireClient(player, allPlayerPerks)
	end)
end

local function OnPlayerRemoving(player: Player)
	playerPerks[player] = nil
	cleanupPerkLimit(player)
end

--------------------------------------------------
-- Initialization
--------------------------------------------------

--------------------------------------------------
-- RemovePerk Bindable (used by DownedService to consume QuickRevive)
--------------------------------------------------

task.spawn(function()
	local removePerkBindable = ServerScriptService:WaitForChild("RemovePerkBindable", 10) :: BindableEvent?
	if removePerkBindable then
		removePerkBindable.Event:Connect(function(player: Player, perkName: string)
			local perks = playerPerks[player]
			if not perks or not perks[perkName] then
				return
			end

			local stats = PerkConfig.Perks[perkName]
			if stats then
				player:SetAttribute(stats.AttributeName, nil)
			end

			perks[perkName] = nil

			PerkLostRemote:FireAllClients({
				playerId = player.UserId,
				perksLost = { perkName },
			})
		end)
	end
end)

-- discover existing machines
for _, machine in CollectionService:GetTagged("PerkMachine") do
	SetupPerkMachine(machine)
end

-- listen for new machines added at runtime
CollectionService:GetInstanceAddedSignal("PerkMachine"):Connect(SetupPerkMachine)

-- player connections
Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

for _, player in Players:GetPlayers() do
	OnPlayerAdded(player)
end
