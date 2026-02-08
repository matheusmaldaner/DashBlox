--!strict

-- server-authoritative mystery box system
-- handles coin deduction, weapon selection, teddy bear relocate,
-- ammo refill on duplicate, and ProximityPrompt interaction

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local MysteryBoxConfig = require(ReplicatedStorage.Modules.MysteryBoxConfig)
local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)
local CoinUtility = require(ServerScriptService.CoinUtility)

--------------------------------------------------
-- Remotes
--------------------------------------------------

local MysteryBoxOpenedRemote = RemoteService.GetRemote("MysteryBoxOpened") :: RemoteEvent
local MysteryBoxResultRemote = RemoteService.GetRemote("MysteryBoxResult") :: RemoteEvent
local MysteryBoxPickedUpRemote = RemoteService.GetRemote("MysteryBoxPickedUp") :: RemoteEvent
local MysteryBoxExpiredRemote = RemoteService.GetRemote("MysteryBoxExpired") :: RemoteEvent
local MysteryBoxRelocateRemote = RemoteService.GetRemote("MysteryBoxRelocate") :: RemoteEvent
local MysteryBoxReappearRemote = RemoteService.GetRemote("MysteryBoxReappear") :: RemoteEvent
local GiveLoadoutRemote = RemoteService.GetRemote("GiveLoadout") :: RemoteEvent

--------------------------------------------------
-- State
--------------------------------------------------

-- box locations (tagged parts in workspace)
local boxLocations: { Instance } = {} -- can be BasePart or Model
local activeLocationIndex: number = 1

-- the physical box model
local boxModel: Model? = nil
local boxPrompt: ProximityPrompt? = nil

-- usage tracking
local usesAtCurrentLocation: number = 0
local isBoxInUse: boolean = false
local isBoxRelocating: boolean = false

-- pending weapon pickup (one per box use)
local pendingPickup: {
	player: Player,
	gunName: string,
	isDuplicate: boolean,
	expiresAt: number,
}? = nil

--------------------------------------------------
-- Weapon Selection
--------------------------------------------------

local function PickRandomWeapon(): (string, string)
	local pool = MysteryBoxConfig.WeaponPool
	local totalWeight = 0
	for _, entry in pool do
		totalWeight += entry.weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in pool do
		cumulative += entry.weight
		if roll <= cumulative then
			return entry.gunName, entry.rarity
		end
	end

	-- fallback
	return pool[1].gunName, pool[1].rarity
end

local function PlayerOwnsWeapon(player: Player, gunName: string): boolean
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, tool in backpack:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("GunName") == gunName then
				return true
			end
		end
	end

	local character = player.Character
	if character then
		for _, tool in character:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("GunName") == gunName then
				return true
			end
		end
	end

	return false
end

local function ShouldTeddyBear(): boolean
	local chance = MysteryBoxConfig.TeddyBearBaseChance
		+ (usesAtCurrentLocation * MysteryBoxConfig.TeddyBearChancePerUse)
	chance = math.min(chance, MysteryBoxConfig.TeddyBearMaxChance)
	return math.random() < chance
end

--------------------------------------------------
-- Give Weapon / Refill Ammo
--------------------------------------------------

local function GiveWeaponOrRefill(player: Player, gunName: string, isDuplicate: boolean)
	if isDuplicate then
			local reloadBindable = ServerScriptService:FindFirstChild("RefillAmmoBindable") :: BindableFunction?
		if reloadBindable then
			pcall(function()
				reloadBindable:Invoke(player, gunName)
			end)
		end
		return
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return
	end

	local slotIndex = 1
	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and tool:GetAttribute("SlotIndex") then
			local idx = tool:GetAttribute("SlotIndex")
			if typeof(idx) == "number" and idx >= slotIndex then
				slotIndex = idx + 1
			end
		end
	end

	local character = player.Character
	if character then
		for _, tool in character:GetChildren() do
			if tool:IsA("Tool") and tool:GetAttribute("SlotIndex") then
				local idx = tool:GetAttribute("SlotIndex")
				if typeof(idx) == "number" and idx >= slotIndex then
					slotIndex = idx + 1
				end
			end
		end
	end

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = gunName
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	tool:SetAttribute("GunName", gunName)
	tool:SetAttribute("SlotIndex", slotIndex)
	tool.Parent = backpack
end

--------------------------------------------------
-- Box Location Management
--------------------------------------------------

local function DiscoverLocations()
	boxLocations = CollectionService:GetTagged("MysteryBoxLocation") :: { BasePart }
	if #boxLocations == 0 then
		warn("[MysteryBox] no parts tagged 'MysteryBoxLocation' found")
	end
end

local function DiscoverBoxModel()
	local boxes = CollectionService:GetTagged("MysteryBox")
	if #boxes == 0 then
		warn("[MysteryBox] no instance tagged 'MysteryBox' found")
		return
	end

	local tagged = boxes[1]
	print("[MysteryBox] found tagged instance:", tagged.Name, "class:", tagged.ClassName)

	-- wrap single BasePart in a pseudo-model reference
	if tagged:IsA("Model") then
		boxModel = tagged :: Model
	elseif tagged:IsA("BasePart") then
		-- tagged instance is a Part, not a Model - still usable
		boxModel = tagged :: any
	else
		warn("[MysteryBox] tagged instance is not a Model or BasePart:", tagged.ClassName)
		return
	end

	-- find existing ProximityPrompt anywhere in the box
	boxPrompt = tagged:FindFirstChildWhichIsA("ProximityPrompt", true)

	if boxPrompt then
		print("[MysteryBox] found existing ProximityPrompt in", boxPrompt.Parent.Name)
		return
	end

	-- determine where to parent the new prompt (must be a BasePart)
	local promptParent: BasePart? = nil
	if tagged:IsA("BasePart") then
		promptParent = tagged :: BasePart
	elseif tagged:IsA("Model") then
		promptParent = (tagged :: Model).PrimaryPart
			or tagged:FindFirstChildWhichIsA("BasePart")
	end

	if not promptParent then
		warn("[MysteryBox] cannot find BasePart for ProximityPrompt")
		return
	end

	print("[MysteryBox] creating ProximityPrompt on", promptParent.Name)

	boxPrompt = Instance.new("ProximityPrompt")
	local prompt = boxPrompt :: ProximityPrompt
	prompt.ObjectText = MysteryBoxConfig.BoxPromptText
	prompt.ActionText = MysteryBoxConfig.BoxActionText
		.. " [" .. tostring(MysteryBoxConfig.Cost) .. "]"
	prompt.MaxActivationDistance = MysteryBoxConfig.BoxMaxDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptParent
end

-- move the box model to a specific location
local function MoveBoxToLocation(locationIndex: number)
	if not boxModel then
		return
	end

	local location = boxLocations[locationIndex]
	if not location then
		return
	end

	-- position above the location (works for both Models and BaseParts)
	local locationCF: CFrame
	if location:IsA("Model") then
		locationCF = location:GetPivot()
	else
		locationCF = (location :: BasePart).CFrame
	end
	local targetCF = locationCF + Vector3.new(0, 2, 0);
	(boxModel :: Model):PivotTo(targetCF)
	activeLocationIndex = locationIndex
	usesAtCurrentLocation = 0
end

-- pick a new location (different from current)
local function PickNewLocation(): number
	if #boxLocations <= 1 then
		return 1
	end

	local newIndex = activeLocationIndex
	while newIndex == activeLocationIndex do
		newIndex = math.random(1, #boxLocations)
	end
	return newIndex
end

--------------------------------------------------
-- Box Interaction (ProximityPrompt)
--------------------------------------------------

local function OnBoxTriggered(player: Player)
	print("[MysteryBox] triggered by", player.Name)

	-- guards
	if isBoxInUse or isBoxRelocating then
		warn("[MysteryBox] box is busy (inUse:", isBoxInUse, "relocating:", isBoxRelocating, ")")
		return
	end
	if not boxModel then
		warn("[MysteryBox] no box model found")
		return
	end

	-- check coins
	local cost = MysteryBoxConfig.Cost
	local playerCoins = CoinUtility.GetCoins(player)
	print("[MysteryBox]", player.Name, "has", playerCoins, "coins, cost is", cost)

	if not CoinUtility.Deduct(player, cost) then
		warn("[MysteryBox] not enough coins")
		return
	end

	print("[MysteryBox] coins deducted, starting roll")

	isBoxInUse = true
	usesAtCurrentLocation += 1

	-- disable prompt while in use
	if boxPrompt then
		local prompt = boxPrompt :: ProximityPrompt
		prompt.Enabled = false
	end

	-- check for teddy bear
	local isTeddyBear = ShouldTeddyBear()

	if isTeddyBear then
		-- teddy bear: refund coins, relocate box
		CoinUtility.Refund(player, cost)

		-- notify all clients: teddy bear animation
		MysteryBoxOpenedRemote:FireAllClients({
			playerId = player.UserId,
			isTeddyBear = true,
		})

		task.wait(MysteryBoxConfig.CyclingDuration)

		MysteryBoxRelocateRemote:FireAllClients({
			oldPosition = boxModel and (boxModel :: Model):GetPivot().Position or Vector3.zero,
		})

		isBoxRelocating = true

		if boxModel then
			local model = boxModel :: Model
			model:PivotTo(CFrame.new(0, -1000, 0))
		end

		task.wait(MysteryBoxConfig.RelocateDelay)

		local newLocation = PickNewLocation()
		MoveBoxToLocation(newLocation)

		local loc = boxLocations[newLocation]
		local newPosition = Vector3.zero
		if loc then
			newPosition = if loc:IsA("Model") then loc:GetPivot().Position else (loc :: BasePart).Position
		end
		MysteryBoxReappearRemote:FireAllClients({
			position = newPosition,
		})

		isBoxRelocating = false
		isBoxInUse = false

		if boxPrompt then
			local prompt = boxPrompt :: ProximityPrompt
			prompt.Enabled = true
		end

		return
	end

	-- normal weapon roll
	local gunName, rarity = PickRandomWeapon()
	local isDuplicate = PlayerOwnsWeapon(player, gunName)

	-- notify all clients: start cycling animation
	MysteryBoxOpenedRemote:FireAllClients({
		playerId = player.UserId,
		isTeddyBear = false,
	})

	-- wait for cycling animation
	task.wait(MysteryBoxConfig.CyclingDuration)

	-- reveal weapon
	MysteryBoxResultRemote:FireAllClients({
		playerId = player.UserId,
		gunName = gunName,
		rarity = rarity,
		isDuplicate = isDuplicate,
	})

	-- set up pending pickup
	pendingPickup = {
		player = player,
		gunName = gunName,
		isDuplicate = isDuplicate,
		expiresAt = tick() + MysteryBoxConfig.PickupWindow,
	}

	-- create a pickup prompt on the box for this player
	local pickupPrompt = Instance.new("ProximityPrompt")
	pickupPrompt.Name = "PickupPrompt"
	if isDuplicate then
		pickupPrompt.ObjectText = GunConfig.Guns[gunName].Name .. " (Ammo Refill)"
	else
		pickupPrompt.ObjectText = GunConfig.Guns[gunName].Name
	end
	pickupPrompt.ActionText = "Take"
	pickupPrompt.MaxActivationDistance = MysteryBoxConfig.BoxMaxDistance
	pickupPrompt.HoldDuration = 0
	pickupPrompt.RequiresLineOfSight = false
	if boxModel then
		pickupPrompt.Parent = boxModel
	end

	-- pickup handler
	local pickupConnection: RBXScriptConnection? = nil
	pickupConnection = pickupPrompt.Triggered:Connect(function(pickupPlayer: Player)
		if not pendingPickup then
			return
		end
		if pickupPlayer ~= pendingPickup.player then
			return
		end

		GiveWeaponOrRefill(pickupPlayer, pendingPickup.gunName, pendingPickup.isDuplicate)

		MysteryBoxPickedUpRemote:FireAllClients({
			playerId = pickupPlayer.UserId,
			gunName = pendingPickup.gunName,
			isDuplicate = pendingPickup.isDuplicate,
		})

		pendingPickup = nil
		if pickupConnection then
			pickupConnection:Disconnect()
		end
		pickupPrompt:Destroy()

		-- cooldown then re-enable
		task.wait(MysteryBoxConfig.CooldownAfterUse)
		isBoxInUse = false
		if boxPrompt then
			local prompt = boxPrompt :: ProximityPrompt
			prompt.Enabled = true
		end
	end)

	-- expiry timer: if player doesn't pick up in time
	task.spawn(function()
		task.wait(MysteryBoxConfig.PickupWindow)

		-- check if still pending (wasn't picked up)
		if pendingPickup and pendingPickup.gunName == gunName and pendingPickup.player == player then
			pendingPickup = nil
			if pickupConnection then
				pickupConnection:Disconnect()
			end
			pickupPrompt:Destroy()

			MysteryBoxExpiredRemote:FireAllClients({
				playerId = player.UserId,
				gunName = gunName,
			})

			task.wait(MysteryBoxConfig.CooldownAfterUse)
			isBoxInUse = false
			if boxPrompt then
				local prompt = boxPrompt :: ProximityPrompt
				prompt.Enabled = true
			end
		end
	end)
end

--------------------------------------------------
-- Initialization
--------------------------------------------------

local function Initialize()
	print("[MysteryBox] initializing...")
	DiscoverLocations()
	print("[MysteryBox] found", #boxLocations, "locations")
	DiscoverBoxModel()
	print("[MysteryBox] boxModel:", boxModel ~= nil, "boxPrompt:", boxPrompt ~= nil)

	-- move box to first location
	if boxModel and #boxLocations > 0 then
		activeLocationIndex = math.random(1, #boxLocations)
		MoveBoxToLocation(activeLocationIndex)
		print("[MysteryBox] moved to location", activeLocationIndex)
	else
		warn("[MysteryBox] cannot place box: model=", boxModel ~= nil, "locations=", #boxLocations)
	end

	-- connect proximity prompt
	if boxPrompt then
		local prompt = boxPrompt :: ProximityPrompt
		prompt.Triggered:Connect(OnBoxTriggered)
		print("[MysteryBox] prompt connected, ready for interaction")
	else
		warn("[MysteryBox] no prompt to connect!")
	end

	-- also watch for box model being added later (rojo sync)
	CollectionService:GetInstanceAddedSignal("MysteryBox"):Connect(function(instance)
		if not boxModel then
			boxModel = instance :: Model
			DiscoverBoxModel()
			if boxModel and #boxLocations > 0 then
				MoveBoxToLocation(activeLocationIndex)
			end
			if boxPrompt then
				local prompt = boxPrompt :: ProximityPrompt
				prompt.Triggered:Connect(OnBoxTriggered)
			end
		end
	end)

	CollectionService:GetInstanceAddedSignal("MysteryBoxLocation"):Connect(function(_instance)
		DiscoverLocations()
	end)
end

Initialize()
