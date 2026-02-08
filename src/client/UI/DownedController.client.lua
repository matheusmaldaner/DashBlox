--!strict

-- client-side downed UI and visual effects: bleedout timer bar, screen desaturation,
-- self-revive prompt (QuickRevive), teammate downed indicators, death screen

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local player = Players.LocalPlayer

--------------------------------------------------
-- Remotes
--------------------------------------------------

local PlayerDownedRemote = RemoteService.GetRemote("PlayerDowned") :: RemoteEvent
local PlayerRevivedRemote = RemoteService.GetRemote("PlayerRevived") :: RemoteEvent
local PlayerDiedRemote = RemoteService.GetRemote("PlayerDied") :: RemoteEvent
local BleedoutUpdateRemote = RemoteService.GetRemote("BleedoutUpdate") :: RemoteEvent
local RequestSelfReviveRemote = RemoteService.GetRemote("RequestSelfRevive") :: RemoteEvent

--------------------------------------------------
-- State
--------------------------------------------------

local isDowned = false
local hasQuickRevive = false
local quickReviveHoldTime = 5
local selfReviveHoldStart: number? = nil
local selfReviveUsed = false
local bleedoutFraction = 1 -- 1 = full time, 0 = dead

--------------------------------------------------
-- Color Correction (desaturation when downed)
--------------------------------------------------

local colorCorrection: ColorCorrectionEffect? = nil

local function CreateColorCorrection()
	if colorCorrection then
		return
	end
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "DownedDesaturation"
	colorCorrection.Saturation = -0.8
	colorCorrection.TintColor = Color3.fromRGB(200, 180, 180)
	colorCorrection.Brightness = -0.05
	colorCorrection.Enabled = true
	colorCorrection.Parent = Lighting
end

local function RemoveColorCorrection()
	if colorCorrection then
		colorCorrection:Destroy()
		colorCorrection = nil
	end
end

--------------------------------------------------
-- UI Setup
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DownedUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = player.PlayerGui

-- red vignette overlay
local vignette = Instance.new("ImageLabel")
vignette.Name = "Vignette"
vignette.Size = UDim2.fromScale(1, 1)
vignette.Position = UDim2.fromScale(0, 0)
vignette.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
vignette.BackgroundTransparency = 0.7
vignette.BorderSizePixel = 0
vignette.Image = ""
vignette.Parent = screenGui

-- "YOU ARE DOWN" text
local downedText = Instance.new("TextLabel")
downedText.Name = "DownedText"
downedText.Size = UDim2.new(0.5, 0, 0.08, 0)
downedText.Position = UDim2.new(0.25, 0, 0.2, 0)
downedText.BackgroundTransparency = 1
downedText.Text = "YOU ARE DOWN"
downedText.TextColor3 = Color3.fromRGB(255, 60, 60)
downedText.TextScaled = true
downedText.Font = Enum.Font.GothamBold
downedText.Parent = screenGui

-- bleedout timer bar container
local barContainer = Instance.new("Frame")
barContainer.Name = "BleedoutBar"
barContainer.Size = UDim2.new(0.3, 0, 0.025, 0)
barContainer.Position = UDim2.new(0.35, 0, 0.3, 0)
barContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
barContainer.BackgroundTransparency = 0.3
barContainer.BorderSizePixel = 0
barContainer.Parent = screenGui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 4)
barCorner.Parent = barContainer

-- bleedout fill bar
local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
barFill.BackgroundTransparency = 0
barFill.BorderSizePixel = 0
barFill.Parent = barContainer

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 4)
fillCorner.Parent = barFill

-- bleedout timer text
local timerText = Instance.new("TextLabel")
timerText.Name = "TimerText"
timerText.Size = UDim2.new(0.3, 0, 0.03, 0)
timerText.Position = UDim2.new(0.35, 0, 0.33, 0)
timerText.BackgroundTransparency = 1
timerText.Text = "30s"
timerText.TextColor3 = Color3.fromRGB(255, 200, 200)
timerText.TextScaled = true
timerText.Font = Enum.Font.GothamMedium
timerText.Parent = screenGui

-- self-revive prompt (only visible with QuickRevive)
local selfReviveFrame = Instance.new("Frame")
selfReviveFrame.Name = "SelfRevivePrompt"
selfReviveFrame.Size = UDim2.new(0.25, 0, 0.06, 0)
selfReviveFrame.Position = UDim2.new(0.375, 0, 0.38, 0)
selfReviveFrame.BackgroundColor3 = Color3.fromRGB(50, 120, 200)
selfReviveFrame.BackgroundTransparency = 0.4
selfReviveFrame.BorderSizePixel = 0
selfReviveFrame.Visible = false
selfReviveFrame.Parent = screenGui

local selfReviveCorner = Instance.new("UICorner")
selfReviveCorner.CornerRadius = UDim.new(0, 6)
selfReviveCorner.Parent = selfReviveFrame

local selfReviveText = Instance.new("TextLabel")
selfReviveText.Name = "Text"
selfReviveText.Size = UDim2.fromScale(1, 0.5)
selfReviveText.Position = UDim2.fromScale(0, 0.05)
selfReviveText.BackgroundTransparency = 1
selfReviveText.Text = "Hold [F] to Self-Revive"
selfReviveText.TextColor3 = Color3.fromRGB(255, 255, 255)
selfReviveText.TextScaled = true
selfReviveText.Font = Enum.Font.GothamBold
selfReviveText.Parent = selfReviveFrame

-- self-revive progress bar
local selfReviveBarBg = Instance.new("Frame")
selfReviveBarBg.Name = "ProgressBg"
selfReviveBarBg.Size = UDim2.new(0.9, 0, 0.25, 0)
selfReviveBarBg.Position = UDim2.new(0.05, 0, 0.6, 0)
selfReviveBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
selfReviveBarBg.BackgroundTransparency = 0.3
selfReviveBarBg.BorderSizePixel = 0
selfReviveBarBg.Parent = selfReviveFrame

local selfReviveBarBgCorner = Instance.new("UICorner")
selfReviveBarBgCorner.CornerRadius = UDim.new(0, 3)
selfReviveBarBgCorner.Parent = selfReviveBarBg

local selfReviveBarFill = Instance.new("Frame")
selfReviveBarFill.Name = "Fill"
selfReviveBarFill.Size = UDim2.fromScale(0, 1)
selfReviveBarFill.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
selfReviveBarFill.BackgroundTransparency = 0
selfReviveBarFill.BorderSizePixel = 0
selfReviveBarFill.Parent = selfReviveBarBg

local selfReviveBarFillCorner = Instance.new("UICorner")
selfReviveBarFillCorner.CornerRadius = UDim.new(0, 3)
selfReviveBarFillCorner.Parent = selfReviveBarFill

--------------------------------------------------
-- Show/Hide Downed UI
--------------------------------------------------

local function ShowDownedUI()
	screenGui.Enabled = true
	CreateColorCorrection()
	barFill.Size = UDim2.fromScale(1, 1)
	bleedoutFraction = 1
	selfReviveBarFill.Size = UDim2.fromScale(0, 1)
	selfReviveFrame.Visible = hasQuickRevive and not selfReviveUsed
end

local function HideDownedUI()
	screenGui.Enabled = false
	RemoveColorCorrection()
	selfReviveHoldStart = nil
end

--------------------------------------------------
-- Self-Revive Input (hold F)
--------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not isDowned or not hasQuickRevive or selfReviveUsed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		selfReviveHoldStart = tick()
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	if input.KeyCode == Enum.KeyCode.F then
		selfReviveHoldStart = nil
		selfReviveBarFill.Size = UDim2.fromScale(0, 1)
	end
end)

-- update self-revive progress bar each frame
RunService.RenderStepped:Connect(function()
	if not isDowned or not selfReviveHoldStart then
		return
	end

	local elapsed = tick() - selfReviveHoldStart
	local progress = math.clamp(elapsed / quickReviveHoldTime, 0, 1)
	selfReviveBarFill.Size = UDim2.fromScale(progress, 1)

	if progress >= 1 then
		-- self-revive complete
		selfReviveHoldStart = nil
		selfReviveUsed = true
		selfReviveFrame.Visible = false
		RequestSelfReviveRemote:FireServer()
	end
end)

--------------------------------------------------
-- Remote Handlers
--------------------------------------------------

PlayerDownedRemote.OnClientEvent:Connect(function(data)
	if not data or data.playerId ~= player.UserId then
		return
	end

	isDowned = true
	hasQuickRevive = data.hasQuickRevive or false
	quickReviveHoldTime = data.quickReviveHoldTime or 5
	selfReviveUsed = false
	selfReviveHoldStart = nil

	ShowDownedUI()
end)

PlayerRevivedRemote.OnClientEvent:Connect(function(data)
	if not data or data.playerId ~= player.UserId then
		return
	end

	isDowned = false
	HideDownedUI()
end)

PlayerDiedRemote.OnClientEvent:Connect(function(data)
	if not data or data.playerId ~= player.UserId then
		return
	end

	isDowned = false
	HideDownedUI()

	-- show brief death message (will be hidden on respawn via CharacterAdded)
	downedText.Text = "YOU DIED"
	downedText.TextColor3 = Color3.fromRGB(180, 30, 30)
	screenGui.Enabled = true
	vignette.BackgroundTransparency = 0.4
	barContainer.Visible = false
	timerText.Visible = false
	selfReviveFrame.Visible = false
	CreateColorCorrection()
end)

BleedoutUpdateRemote.OnClientEvent:Connect(function(data)
	if not data then
		return
	end

	local timeRemaining = data.timeRemaining or 0
	local totalTime = data.totalTime or 30

	bleedoutFraction = math.clamp(timeRemaining / totalTime, 0, 1)
	barFill.Size = UDim2.fromScale(bleedoutFraction, 1)
	timerText.Text = tostring(math.ceil(timeRemaining)) .. "s"

	-- shift bar color from red to dark red as time runs out
	local r = math.floor(255 * bleedoutFraction)
	barFill.BackgroundColor3 = Color3.fromRGB(r, 20, 20)
end)

--------------------------------------------------
-- Reset UI on respawn
--------------------------------------------------

player.CharacterAdded:Connect(function()
	isDowned = false
	selfReviveUsed = false
	selfReviveHoldStart = nil
	HideDownedUI()

	-- reset UI elements to default state
	downedText.Text = "YOU ARE DOWN"
	downedText.TextColor3 = Color3.fromRGB(255, 60, 60)
	vignette.BackgroundTransparency = 0.7
	barContainer.Visible = true
	timerText.Visible = true
end)

print("[DownedController] Initialized")
