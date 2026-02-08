--!strict

-- server-side zone door system: discovers tagged doors,
-- adds ProximityPrompts with per-door prices, handles purchases,
-- opens doors permanently for all players
--
-- studio setup per door:
--   tag: "ZoneDoor" (CollectionService)
--   attribute: DoorPrice (number) - cost in coins
--   attribute: DoorLabel (string, optional) - prompt text

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZoneDoorConfig = require(ReplicatedStorage.Modules.ZoneDoorConfig)
local CoinUtility = require(script.Parent.CoinUtility)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local ZoneDoorOpenedRemote = RemoteService.GetRemote("ZoneDoorOpened") :: RemoteEvent

-- rate limiter for door purchases
local checkDoorLimit, _cleanupDoorLimit = RemoteService.CreateRateLimiter(1.0)

-- track which doors have been opened (Instance -> true)
local openedDoors: { [Instance]: boolean } = {}

--------------------------------------------------
-- Door Opening
--------------------------------------------------

local function GetAllDoorParts(door: Instance): { BasePart }
	local parts: { BasePart } = {}
	if door:IsA("BasePart") then
		table.insert(parts, door)
	elseif door:IsA("Model") then
		for _, descendant in door:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end
	return parts
end

local function OpenDoor(door: Instance)
	if openedDoors[door] then
		return
	end
	openedDoors[door] = true

	-- remove the ProximityPrompt so nobody else interacts
	for _, descendant in door:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end

	-- also check the door itself if it's a BasePart
	if door:IsA("BasePart") then
		local prompt = door:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end
	end

	-- fade out and disable collision on all parts
	local parts = GetAllDoorParts(door)
	local fadeDuration = ZoneDoorConfig.FadeDuration

	for _, part in parts do
		part.CanCollide = false
		part.Anchored = true

		local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(part, tweenInfo, {
			Transparency = 1,
		}):Play()
	end

	-- destroy the door after fade completes
	task.delay(fadeDuration + 0.1, function()
		if door and door.Parent then
			door:Destroy()
		end
	end)
end

--------------------------------------------------
-- Purchase Handling
--------------------------------------------------

local function HandleDoorPurchase(player: Player, door: Instance)
	if openedDoors[door] then
		return
	end

	if not checkDoorLimit(player) then
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

	-- get price from attribute or fallback
	local price = door:GetAttribute("DoorPrice")
	if not price or typeof(price) ~= "number" then
		price = ZoneDoorConfig.DefaultPrice
	end

	-- deduct coins
	if not CoinUtility.Deduct(player, price) then
		warn("[ZoneDoorService] Not enough coins:", player.Name, "| Has:", CoinUtility.GetCoins(player), "| Needs:", price)
		return
	end

	-- get label for client notification
	local label = door:GetAttribute("DoorLabel")
	if not label or typeof(label) ~= "string" then
		label = ZoneDoorConfig.DefaultLabel
	end

	print("[ZoneDoorService] Door opened by:", player.Name, "| Door:", door:GetFullName(), "| Cost:", price)

	-- open the door
	OpenDoor(door)

	-- notify all clients
	ZoneDoorOpenedRemote:FireAllClients({
		doorName = label,
		openedBy = player.Name,
	})
end

--------------------------------------------------
-- Door Discovery (CollectionService)
--------------------------------------------------

local function SetupZoneDoor(door: Instance)
	if not door:IsA("Model") and not door:IsA("BasePart") then
		return
	end

	-- skip if already opened
	if openedDoors[door] then
		return
	end

	-- find interaction part
	local interactPart: BasePart
	if door:IsA("BasePart") then
		interactPart = door
	else
		interactPart = (door :: Model).PrimaryPart
			or (door :: Model):FindFirstChildWhichIsA("BasePart") :: BasePart
	end

	if not interactPart then
		warn("[ZoneDoorService] No BasePart found in ZoneDoor:", door:GetFullName())
		return
	end

	-- skip if prompt already exists
	if interactPart:FindFirstChildOfClass("ProximityPrompt") then
		return
	end

	-- read per-door config from attributes
	local price = door:GetAttribute("DoorPrice")
	if not price or typeof(price) ~= "number" then
		price = ZoneDoorConfig.DefaultPrice
	end

	local label = door:GetAttribute("DoorLabel")
	if not label or typeof(label) ~= "string" then
		label = ZoneDoorConfig.DefaultLabel
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = label
	prompt.ObjectText = price .. " Coins"
	prompt.HoldDuration = ZoneDoorConfig.PromptHoldDuration
	prompt.MaxActivationDistance = ZoneDoorConfig.PromptMaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = interactPart

	prompt.Triggered:Connect(function(playerWhoTriggered: Player)
		HandleDoorPurchase(playerWhoTriggered, door)
	end)
end

--------------------------------------------------
-- Initialization
--------------------------------------------------

-- discover existing doors
for _, door in CollectionService:GetTagged("ZoneDoor") do
	SetupZoneDoor(door)
end

-- listen for new doors added at runtime
CollectionService:GetInstanceAddedSignal("ZoneDoor"):Connect(SetupZoneDoor)
