--!strict
local CrosshairController = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Modules.Settings)
local MatchStateClient = require(ReplicatedStorage.Modules.MatchStateClient)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- create FightGUI and crosshair frame if they don't exist
local fightGui = playerGui:FindFirstChild("FightGUI") :: ScreenGui?
if not fightGui then
	fightGui = Instance.new("ScreenGui")
	fightGui.Name = "FightGUI"
	fightGui.ResetOnSpawn = false
	fightGui.IgnoreGuiInset = true
	fightGui.DisplayOrder = 10
	fightGui.Parent = playerGui
end

local crosshairFrame = fightGui:FindFirstChild("Crosshair") :: Frame?
if not crosshairFrame then
	crosshairFrame = Instance.new("Frame")
	crosshairFrame.Name = "Crosshair"
	crosshairFrame.Size = UDim2.new(1, 0, 1, 0)
	crosshairFrame.BackgroundTransparency = 1
	crosshairFrame.Active = false
	crosshairFrame.Parent = fightGui
end

-- create sniper scope overlay if it doesn't exist
if not fightGui:FindFirstChild("SniperScope") then
	local scope = Instance.new("Frame")
	scope.Name = "SniperScope"
	scope.Size = UDim2.new(1, 0, 1, 0)
	scope.BackgroundColor3 = Color3.new(0, 0, 0)
	scope.BackgroundTransparency = 0
	scope.BorderSizePixel = 0
	scope.Visible = false
	scope.ZIndex = 50
	scope.Parent = fightGui

	-- scope crosshair lines
	local lineH = Instance.new("Frame")
	lineH.Size = UDim2.new(1, 0, 0, 1)
	lineH.Position = UDim2.new(0, 0, 0.5, 0)
	lineH.BackgroundColor3 = Color3.new(0, 0, 0)
	lineH.BorderSizePixel = 0
	lineH.ZIndex = 51
	lineH.Parent = scope

	local lineV = Instance.new("Frame")
	lineV.Size = UDim2.new(0, 1, 1, 0)
	lineV.Position = UDim2.new(0.5, 0, 0, 0)
	lineV.BackgroundColor3 = Color3.new(0, 0, 0)
	lineV.BorderSizePixel = 0
	lineV.ZIndex = 51
	lineV.Parent = scope

	-- circular cutout effect (dark border with transparent center)
	local circle = Instance.new("Frame")
	circle.Name = "ScopeCircle"
	circle.Size = UDim2.new(0, 400, 0, 400)
	circle.Position = UDim2.new(0.5, -200, 0.5, -200)
	circle.BackgroundColor3 = Color3.new(0, 0, 0)
	circle.BackgroundTransparency = 1
	circle.BorderSizePixel = 0
	circle.ZIndex = 51
	circle.Parent = scope

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle
end

-- crosshair configuration (defaults, will be updated from settings)
local config = {
	barThickness = 2,
	barLength = 10,
	centerGap = 4,
	dotSize = 4,
	dotEnabled = true,
	color = Color3.new(1, 1, 1),
	outlineEnabled = true,
}

local MAX_SPREAD_PIXELS = 50
local SPREAD_SCALE = 500

-- Bar references
local bars: { [string]: Frame } = {}
local centerDot: Frame? = nil

local currentSpread = 0
local targetSpread = 0
local isVisible = false
local _isGunCrosshair = false -- true when gun is equipped

-- Create a single crosshair bar
local function createBar(name: string): Frame
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.BackgroundColor3 = config.color
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Visible = false
	bar.Active = false -- Don't absorb mouse input
	bar.Parent = crosshairFrame

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = config.outlineEnabled and 1 or 0
	stroke.Parent = bar

	return bar
end

-- update crosshair appearance from config
local function updateCrosshairAppearance()
	-- update bars
	for _, bar in bars do
		bar.BackgroundColor3 = config.color
		local stroke = bar:FindFirstChild("Outline") :: UIStroke?
		if stroke then
			stroke.Thickness = config.outlineEnabled and 1 or 0
		end
	end

	-- update bar sizes
	if bars.top then
		bars.top.Size = UDim2.new(0, config.barThickness, 0, config.barLength)
	end
	if bars.bottom then
		bars.bottom.Size = UDim2.new(0, config.barThickness, 0, config.barLength)
	end
	if bars.left then
		bars.left.Size = UDim2.new(0, config.barLength, 0, config.barThickness)
	end
	if bars.right then
		bars.right.Size = UDim2.new(0, config.barLength, 0, config.barThickness)
	end

	-- update center dot
	if centerDot then
		centerDot.BackgroundColor3 = config.color
		centerDot.Size = UDim2.new(0, config.dotSize, 0, config.dotSize)
		centerDot.Position = UDim2.new(0.5, -config.dotSize / 2, 0.5, -config.dotSize / 2)

		local dotStroke = centerDot:FindFirstChild("Outline") :: UIStroke?
		if dotStroke then
			dotStroke.Thickness = config.outlineEnabled and 1 or 0
		end
	end
end

-- load settings from shared Settings module
local function loadSettings()
	local crosshairSettings = Settings.GetAllCrosshairSettings()
	if crosshairSettings then
		config.color = crosshairSettings.color
		config.barLength = crosshairSettings.size
		config.barThickness = crosshairSettings.thickness
		config.centerGap = crosshairSettings.gap
		config.dotEnabled = crosshairSettings.dotEnabled
		config.dotSize = crosshairSettings.dotSize
		config.outlineEnabled = crosshairSettings.outline
		print("[CrosshairController] Loaded settings - color:", config.color, "size:", config.barLength)
		updateCrosshairAppearance()
	end
end

-- Initialize crosshair bars
function CrosshairController.Initialize()
	-- Make sure crosshair frame doesn't absorb mouse input
	crosshairFrame.Active = false

	-- Clear existing bar children
	for _, child in crosshairFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Center dot
	centerDot = Instance.new("Frame")
	centerDot.Name = "CenterDot"
	centerDot.BackgroundColor3 = config.color
	centerDot.BorderSizePixel = 0
	centerDot.Size = UDim2.new(0, config.dotSize, 0, config.dotSize)
	centerDot.Position = UDim2.new(0.5, -config.dotSize / 2, 0.5, -config.dotSize / 2)
	centerDot.Active = false
	centerDot.Visible = config.dotEnabled
	centerDot.Parent = crosshairFrame

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0) -- Make it circular
	dotCorner.Parent = centerDot

	local dotStroke = Instance.new("UIStroke")
	dotStroke.Name = "Outline"
	dotStroke.Color = Color3.new(0, 0, 0)
	dotStroke.Thickness = config.outlineEnabled and 1 or 0
	dotStroke.Parent = centerDot

	-- Top bar (portrait - vertical orientation)
	bars.top = createBar("TopBar")
	bars.top.Size = UDim2.new(0, config.barThickness, 0, config.barLength)

	-- Bottom bar (portrait - vertical orientation)
	bars.bottom = createBar("BottomBar")
	bars.bottom.Size = UDim2.new(0, config.barThickness, 0, config.barLength)

	-- Left bar (landscape - horizontal orientation)
	bars.left = createBar("LeftBar")
	bars.left.Size = UDim2.new(0, config.barLength, 0, config.barThickness)

	-- Right bar (landscape - horizontal orientation)
	bars.right = createBar("RightBar")
	bars.right.Size = UDim2.new(0, config.barLength, 0, config.barThickness)

	-- load settings immediately (Settings module is always available)
	loadSettings()

	-- listen for settings changes from shared Settings module
	Settings.Changed:Connect(function(settingName: string, _value: any)
		print("[CrosshairController] Settings.Changed fired:", settingName)
		-- check if it's a crosshair setting
		if string.find(settingName, "crosshair") then
			print("[CrosshairController] Reloading crosshair settings...")
			loadSettings()
		end
		-- check if showCrosshair toggle changed
		if settingName == "showCrosshair" then
			if _value == false then
				CrosshairController.HideAll()
			end
		end
		-- hide crosshair when menu is open (so it doesn't appear in center of menu)
		if settingName == "_menuOpen" then
			if _value == true then
				CrosshairController.HideAll()
			else
				-- restore crosshair when menu closes
				CrosshairController.ShowDot()
			end
		end
	end)

	print("[CrosshairController] Initialized and listening for settings changes")
end

-- Check if crosshair should be visible based on settings
local function isCrosshairEnabled(): boolean
	return Settings.Get("showCrosshair") ~= false
end

-- Set target spread value
function CrosshairController.SetSpread(spreadValue: number)
	targetSpread = spreadValue
end

-- Update bar positions (called every frame, follows mouse cursor)
function CrosshairController.Update(deltaTime: number)
	if not isVisible then
		return
	end

	-- smooth lerp towards target spread
	currentSpread = currentSpread + (targetSpread - currentSpread) * math.min(deltaTime * 15, 1)

	-- check if spread is essentially zero (100% accuracy)
	local isPerfectAccuracy = currentSpread < 0.001

	local spreadPixels: number
	local transparency: number

	if isPerfectAccuracy then
		spreadPixels = 0
		transparency = 0.5
	else
		spreadPixels = config.centerGap + (currentSpread * SPREAD_SCALE)
		spreadPixels = math.min(spreadPixels, config.centerGap + MAX_SPREAD_PIXELS)
		transparency = 0
	end

	-- get mouse position in screen pixels
	local mousePos = UserInputService:GetMouseLocation()
	local mx = mousePos.X
	local my = mousePos.Y

	-- update bar transparency
	for _, bar in bars do
		bar.BackgroundTransparency = transparency
	end

	-- position bars around mouse cursor using pixel offsets (no scale)
	local halfBarLength = config.barLength / 2
	bars.top.Position = UDim2.new(0, mx, 0, my - spreadPixels - halfBarLength)
	bars.bottom.Position = UDim2.new(0, mx, 0, my + spreadPixels + halfBarLength)
	bars.left.Position = UDim2.new(0, mx - spreadPixels - halfBarLength, 0, my)
	bars.right.Position = UDim2.new(0, mx + spreadPixels + halfBarLength, 0, my)

	-- update center dot position to follow mouse too
	if centerDot and centerDot.Visible then
		centerDot.Position = UDim2.new(0, mx - config.dotSize / 2, 0, my - config.dotSize / 2)
	end
end

-- Show gun crosshair (spread bars, hide dot)
function CrosshairController.Show()
	isVisible = true
	_isGunCrosshair = true
	crosshairFrame.Visible = true
	-- respect showCrosshair setting
	local shouldShow = isCrosshairEnabled()
	for _, bar in bars do
		bar.Visible = shouldShow
	end
	if centerDot then
		centerDot.Visible = false
	end
end

-- Hide crosshair entirely when no weapon is equipped
function CrosshairController.Hide()
	isVisible = false
	_isGunCrosshair = false
	crosshairFrame.Visible = false
	for _, bar in bars do
		bar.Visible = false
	end
	if centerDot then
		centerDot.Visible = false
	end
	currentSpread = 0
	targetSpread = 0
end

-- Completely hide all crosshair elements (for menus, etc.)
-- Does NOT change _isGunCrosshair so we can restore properly after menu closes
function CrosshairController.HideAll()
	isVisible = false
	crosshairFrame.Visible = false
	for _, bar in bars do
		bar.Visible = false
	end
	if centerDot then
		centerDot.Visible = false
	end
	currentSpread = 0
	targetSpread = 0
end

-- Restore crosshair after menu closes (only if gun was equipped before)
function CrosshairController.ShowDot()
	if not _isGunCrosshair then
		return
	end
	-- Gun is equipped, restore the gun crosshair
	isVisible = true
	crosshairFrame.Visible = true
	local shouldShow = isCrosshairEnabled()
	for _, bar in bars do
		bar.Visible = shouldShow
	end
end

-- Show red dot for sniper scope
local isSniperScoped = false
local originalDotColor: Color3? = nil
local originalDotZIndex: number? = nil

function CrosshairController.ShowSniperDot()
	isVisible = false
	_isGunCrosshair = false
	isSniperScoped = true

	-- Hide spread bars
	for _, bar in bars do
		bar.Visible = false
	end

	-- Show red dot
	if centerDot then
		-- Store original values to restore later
		if not originalDotColor then
			originalDotColor = config.color
		end
		if not originalDotZIndex then
			originalDotZIndex = centerDot.ZIndex
		end
		centerDot.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Red
		centerDot.Size = UDim2.new(0, 6, 0, 6) -- Slightly larger for visibility
		centerDot.Position = UDim2.new(0.5, -3, 0.5, -3)
		centerDot.ZIndex = 100 -- High ZIndex to render above scope overlay
		centerDot.Visible = true
	end
end

-- Hide sniper scope dot and restore original crosshair
function CrosshairController.HideSniperDot()
	if not isSniperScoped then
		return
	end
	isSniperScoped = false

	-- Restore original dot appearance
	if centerDot then
		if originalDotColor then
			centerDot.BackgroundColor3 = originalDotColor
		end
		if originalDotZIndex then
			centerDot.ZIndex = originalDotZIndex
		end
		centerDot.Size = UDim2.new(0, config.dotSize, 0, config.dotSize)
		centerDot.Position = UDim2.new(0.5, -config.dotSize / 2, 0.5, -config.dotSize / 2)
	end
end

local function applyCombatState(enabled: boolean)
	fightGui.Enabled = enabled
	if not enabled then
		CrosshairController.HideAll()
	end
end

-- Connect to render loop
RunService.RenderStepped:Connect(function(deltaTime)
	CrosshairController.Update(deltaTime)
end)

-- Initialize on load
CrosshairController.Initialize()

MatchStateClient.OnCombatChanged(function(enabled)
	applyCombatState(enabled)
end)

applyCombatState(MatchStateClient.IsCombatEnabled())

return CrosshairController
