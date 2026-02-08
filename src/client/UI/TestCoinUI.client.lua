--!strict

-- temporary dev UI: shows coin count and a button to give test coins
-- TODO: remove this file before release

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GiveTestCoinsRemote = RemoteService.GetRemote("GiveTestCoins") :: RemoteEvent
local CoinsChangedRemote = RemoteService.GetRemote("CoinsChanged") :: RemoteEvent

--------------------------------------------------
-- UI Construction
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TestCoinUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- container frame (top-left corner)
local container = Instance.new("Frame")
container.Name = "CoinContainer"
container.Size = UDim2.new(0, 220, 0, 80)
container.Position = UDim2.new(0, 15, 0, 15)
container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
container.BackgroundTransparency = 0.3
container.BorderSizePixel = 0
container.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = container

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 200, 0)
stroke.Thickness = 2
stroke.Transparency = 0.5
stroke.Parent = container

-- coin display label
local coinLabel = Instance.new("TextLabel")
coinLabel.Name = "CoinLabel"
coinLabel.Size = UDim2.new(1, -10, 0, 35)
coinLabel.Position = UDim2.new(0, 5, 0, 5)
coinLabel.BackgroundTransparency = 1
coinLabel.Text = "Coins: 0"
coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
coinLabel.TextSize = 22
coinLabel.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
coinLabel.TextXAlignment = Enum.TextXAlignment.Left
coinLabel.TextStrokeTransparency = 0.5
coinLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
coinLabel.Parent = container

-- give coins button
local giveButton = Instance.new("TextButton")
giveButton.Name = "GiveButton"
giveButton.Size = UDim2.new(1, -20, 0, 30)
giveButton.Position = UDim2.new(0, 10, 0, 42)
giveButton.BackgroundColor3 = Color3.fromRGB(40, 120, 40)
giveButton.Text = "+ 1000 Coins"
giveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
giveButton.TextSize = 16
giveButton.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
giveButton.BorderSizePixel = 0
giveButton.Parent = container

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 6)
buttonCorner.Parent = giveButton

--------------------------------------------------
-- Events
--------------------------------------------------

-- update display when coins change
CoinsChangedRemote.OnClientEvent:Connect(function(data: any)
	if data and data.coins ~= nil then
		coinLabel.Text = "Coins: " .. tostring(data.coins)
	end
end)

-- also poll leaderstats for initial value
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local coins = leaderstats:WaitForChild("Coins", 5)
		if coins and coins:IsA("IntValue") then
			coinLabel.Text = "Coins: " .. tostring(coins.Value)
		end
	end
end)

-- button click: request test coins from server
local debounce = false
giveButton.MouseButton1Click:Connect(function()
	if debounce then
		return
	end
	debounce = true

	-- flash button green
	giveButton.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
	GiveTestCoinsRemote:FireServer()

	task.wait(0.3)
	giveButton.BackgroundColor3 = Color3.fromRGB(40, 120, 40)
	debounce = false
end)
