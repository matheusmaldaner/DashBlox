--!strict

-- server script: one-time trash pickup system
-- any Part or Model tagged "Trash" in Studio gets a ProximityPrompt.
-- each player can pick up each piece once for 2 coins, then it disappears
-- (for that player only — other players can still see & pick it up).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CoinUtility = require(ServerScriptService.CoinUtility)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local TrashPickedUpRemote = RemoteService.GetRemote("TrashPickedUp") :: RemoteEvent

local COINS_PER_TRASH = 2
local PROMPT_HOLD_DURATION = 0 -- instant press
local PROMPT_MAX_DISTANCE = 8
local PROMPT_TEXT = "Pick up"

-- track which players have picked up which trash (by instance)
-- trash id -> set of player userIds who already picked it up
local pickedUpMap: { [Instance]: { [number]: boolean } } = {}

--------------------------------------------------
-- Setup a single trash item
--------------------------------------------------

local function GetPromptParent(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") then
		local primary = instance.PrimaryPart
		if primary then
			return primary
		end
		return instance:FindFirstChildWhichIsA("BasePart") :: BasePart?
	end
	return nil
end

local function SetupTrash(instance: Instance)
	local promptParent = GetPromptParent(instance)
	if not promptParent then
		return
	end

	-- don't add duplicate prompts
	if promptParent:FindFirstChildOfClass("ProximityPrompt") then
		return
	end

	-- anchor all parts so trash doesn't move
	if instance:IsA("BasePart") then
		instance.Anchored = true
	elseif instance:IsA("Model") then
		for _, desc in instance:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored = true
			end
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = PROMPT_TEXT
	prompt.ObjectText = ""
	prompt.HoldDuration = PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = PROMPT_MAX_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptParent

	pickedUpMap[instance] = {}

	prompt.Triggered:Connect(function(player: Player)
		local pickupSet = pickedUpMap[instance]
		if not pickupSet then
			return
		end

		-- already picked up by this player
		if pickupSet[player.UserId] then
			return
		end

		-- mark as picked up
		pickupSet[player.UserId] = true

		-- award coins
		CoinUtility.Refund(player, COINS_PER_TRASH)

		-- send feedback to client
		local position = promptParent.Position
		TrashPickedUpRemote:FireClient(player, {
			coins = COINS_PER_TRASH,
			position = position,
		})

		-- hide for this player only by destroying the prompt visibility
		-- (we destroy the whole instance since each player should only see it once)
		-- check if all current players have picked it up
		local allPicked = true
		for _, p in Players:GetPlayers() do
			if not pickupSet[p.UserId] then
				allPicked = false
				break
			end
		end

		if allPicked then
			-- everyone got it, remove from world entirely
			pickedUpMap[instance] = nil
			instance:Destroy()
		end
	end)
end

local function CleanupTrash(instance: Instance)
	pickedUpMap[instance] = nil
end

--------------------------------------------------
-- Initialize all tagged trash
--------------------------------------------------

for _, instance in CollectionService:GetTagged("Trash") do
	SetupTrash(instance)
end

CollectionService:GetInstanceAddedSignal("Trash"):Connect(SetupTrash)
CollectionService:GetInstanceRemovedSignal("Trash"):Connect(CleanupTrash)
