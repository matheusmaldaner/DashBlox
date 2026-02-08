--!strict

-- server-side Pack-a-Punch machine: discovers tagged machine,
-- handles weapon upgrade process, sets PackAPunched attribute on tools

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackAPunchConfig = require(ReplicatedStorage.Modules.Guns.PackAPunchConfig)
local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local CoinUtility = require(script.Parent.CoinUtility)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local PackAPunchStartedRemote = RemoteService.GetRemote("PackAPunchStarted") :: RemoteEvent
local PackAPunchCompletedRemote = RemoteService.GetRemote("PackAPunchCompleted") :: RemoteEvent
local PackAPunchFailedRemote = RemoteService.GetRemote("PackAPunchFailed") :: RemoteEvent

-- rate limiter to prevent spam
local checkPAPLimit, cleanupPAPLimit = RemoteService.CreateRateLimiter(2.0)

-- track players currently upgrading (prevent double-upgrade)
local upgrading: { [Player]: boolean } = {}

--------------------------------------------------
-- Upgrade Logic
--------------------------------------------------

local function GetEquippedGunTool(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	-- check character first (currently held tool)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("GunName") then
			return child
		end
	end

	return nil
end

local function HandlePackAPunch(player: Player)
	if not checkPAPLimit(player) then
		return
	end

	if upgrading[player] then
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

	-- find the player's currently equipped weapon
	local tool = GetEquippedGunTool(player)
	if not tool then
		PackAPunchFailedRemote:FireClient(player, { reason = "No weapon equipped" })
		return
	end

	local gunName = tool:GetAttribute("GunName") :: string?
	if not gunName then
		PackAPunchFailedRemote:FireClient(player, { reason = "Invalid weapon" })
		return
	end

	-- check if weapon exists in config
	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		PackAPunchFailedRemote:FireClient(player, { reason = "Unknown weapon" })
		return
	end

	-- check if already Pack-a-Punched
	if tool:GetAttribute("PackAPunched") then
		PackAPunchFailedRemote:FireClient(player, { reason = "Already upgraded" })
		return
	end

	-- deduct coins
	if not CoinUtility.Deduct(player, PackAPunchConfig.Cost) then
		PackAPunchFailedRemote:FireClient(player, { reason = "Not enough coins" })
		return
	end

	upgrading[player] = true

	-- notify all clients that upgrade started
	PackAPunchStartedRemote:FireAllClients({
		playerId = player.UserId,
		gunName = gunName,
	})

	-- simulate upgrade duration
	task.delay(PackAPunchConfig.UpgradeDuration, function()
		upgrading[player] = nil

		-- verify tool still exists
		if not tool or not tool.Parent then
			CoinUtility.Refund(player, PackAPunchConfig.Cost)
			PackAPunchFailedRemote:FireClient(player, { reason = "Weapon lost during upgrade" })
			return
		end

		-- apply Pack-a-Punch upgrade
		tool:SetAttribute("PackAPunched", true)

		-- set upgraded display name
		local upgradedName = PackAPunchConfig.GetUpgradedName(gunName)
		tool:SetAttribute("UpgradedName", upgradedName)

		-- notify all clients
		PackAPunchCompletedRemote:FireAllClients({
			playerId = player.UserId,
			gunName = gunName,
			upgradedName = upgradedName,
		})
	end)
end

--------------------------------------------------
-- Machine Discovery (CollectionService)
--------------------------------------------------

local function SetupPackAPunchMachine(machine: Instance)
	if not machine:IsA("Model") and not machine:IsA("BasePart") then
		return
	end

	local interactPart: BasePart
	if machine:IsA("BasePart") then
		interactPart = machine
	else
		interactPart = (machine :: Model).PrimaryPart
			or (machine :: Model):FindFirstChildWhichIsA("BasePart") :: BasePart
	end

	if not interactPart then
		warn("[PackAPunch] No BasePart found:", machine:GetFullName())
		return
	end

	if interactPart:FindFirstChildOfClass("ProximityPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pack-a-Punch"
	prompt.ObjectText = PackAPunchConfig.Cost .. " Coins"
	prompt.HoldDuration = PackAPunchConfig.PromptHoldDuration
	prompt.MaxActivationDistance = PackAPunchConfig.PromptMaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = interactPart

	prompt.Triggered:Connect(function(playerWhoTriggered: Player)
		HandlePackAPunch(playerWhoTriggered)
	end)
end

--------------------------------------------------
-- Initialization
--------------------------------------------------

for _, machine in CollectionService:GetTagged("PackAPunch") do
	SetupPackAPunchMachine(machine)
end

CollectionService:GetInstanceAddedSignal("PackAPunch"):Connect(SetupPackAPunchMachine)

Players.PlayerRemoving:Connect(function(player)
	upgrading[player] = nil
	cleanupPAPLimit(player)
end)
