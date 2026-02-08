--!strict

-- server coin service: sets up leaderstats, creates AddCoinsEvent bindable,
-- handles coin changes and notifies clients

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local GiveTestCoinsRemote = RemoteService.GetRemote("GiveTestCoins") :: RemoteEvent
local CoinsChangedRemote = RemoteService.GetRemote("CoinsChanged") :: RemoteEvent

local TEST_COIN_AMOUNT = 1000
local STARTING_COINS = 0

--------------------------------------------------
-- Leaderstats Setup
--------------------------------------------------

local function SetupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = STARTING_COINS
	coins.Parent = leaderstats

	-- notify client of initial coin count
	CoinsChangedRemote:FireClient(player, { coins = STARTING_COINS })

	-- listen for changes to sync to client
	coins.Changed:Connect(function(newValue: number)
		CoinsChangedRemote:FireClient(player, { coins = newValue })
	end)
end

--------------------------------------------------
-- AddCoinsEvent Bindable (used by ZombieDamage)
--------------------------------------------------

local function CreateAddCoinsBindable()
	-- remove existing if any
	local existing = ServerScriptService:FindFirstChild("AddCoinsEvent")
	if existing then
		existing:Destroy()
	end

	local addCoinsEvent = Instance.new("BindableEvent")
	addCoinsEvent.Name = "AddCoinsEvent"
	addCoinsEvent.Parent = ServerScriptService

	addCoinsEvent.Event:Connect(function(player: Player, amount: number)
		if not player or not player.Parent then
			return
		end

		local leaderstats = player:FindFirstChild("leaderstats")
		if not leaderstats then
			return
		end

		local coins = leaderstats:FindFirstChild("Coins")
		if coins and coins:IsA("IntValue") then
			coins.Value += amount
		end
	end)
end

--------------------------------------------------
-- Test Coins Remote (temporary, for dev testing)
--------------------------------------------------

local function SetupTestCoins()
	GiveTestCoinsRemote.OnServerEvent:Connect(function(player: Player)
		local leaderstats = player:FindFirstChild("leaderstats")
		if not leaderstats then
			return
		end

		local coins = leaderstats:FindFirstChild("Coins")
		if coins and coins:IsA("IntValue") then
			coins.Value += TEST_COIN_AMOUNT
		end
	end)
end

--------------------------------------------------
-- Initialize
--------------------------------------------------

CreateAddCoinsBindable()
SetupTestCoins()

-- setup for players already in game
for _, player in Players:GetPlayers() do
	if not player:FindFirstChild("leaderstats") then
		SetupLeaderstats(player)
	end
end

-- setup for future players
Players.PlayerAdded:Connect(SetupLeaderstats)
