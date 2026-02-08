--!strict
-- DamageNumberController - arcade-style floating damage popups
-- listens to DamageDealt remote and renders numbers at hit positions
-- white for body hits, gold with glow for headshots, larger font for crits

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local DamageDealtRemote = RemoteService.GetRemote("DamageDealt") :: RemoteEvent

--------------------------------------------------
-- Configuration
--------------------------------------------------

local POOL_SIZE = 20
local FLOAT_DISTANCE = 4 -- studs upward
local DURATION = 0.9 -- seconds to fully fade
local POP_SCALE = 1.6 -- initial scale multiplier (pop big then shrink)
local POP_DURATION = 0.12 -- time to shrink from pop to normal
local X_SPREAD = 1.5 -- random horizontal spread (studs)
local MAX_DISPLAY_DISTANCE = 200 -- don't show numbers beyond this range

-- colors
local BODY_COLOR = Color3.fromRGB(255, 255, 255)
local HEADSHOT_COLOR = Color3.fromRGB(255, 215, 0) -- gold
local HEADSHOT_STROKE_COLOR = Color3.fromRGB(255, 140, 0) -- orange outline
local CRIT_COLOR = Color3.fromRGB(255, 80, 80) -- red for crits

-- sizes
local BODY_SIZE = 22
local HEADSHOT_SIZE = 30
local CRIT_SIZE = 34

--------------------------------------------------
-- Pool Management
--------------------------------------------------

local pool: { BillboardGui } = {}
local activeCount = 0

-- create a single pooled BillboardGui with TextLabel
local function createDamageNumber(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Size = UDim2.new(0, 100, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = MAX_DISPLAY_DISTANCE
	billboard.Active = false
	billboard.Enabled = false

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = BODY_COLOR
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = BODY_SIZE
	label.TextScaled = false
	label.Text = ""
	label.Parent = billboard

	-- glow effect for headshots (UIStroke for outer glow)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "GlowStroke"
	stroke.Color = HEADSHOT_STROKE_COLOR
	stroke.Thickness = 0
	stroke.Transparency = 1
	stroke.Parent = label

	return billboard
end

-- initialize pool
local function initPool()
	for _ = 1, POOL_SIZE do
		local gui = createDamageNumber()
		gui.Parent = nil
		table.insert(pool, gui)
	end
end

-- get a billboard from pool (or create if exhausted)
local function getFromPool(): BillboardGui
	if #pool > 0 then
		return table.remove(pool) :: BillboardGui
	end
	-- pool exhausted, create a new one
	return createDamageNumber()
end

-- return a billboard to pool
local function returnToPool(gui: BillboardGui)
	gui.Enabled = false
	gui.Parent = nil

	local label = gui:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.3
		label.TextSize = BODY_SIZE
		label.TextColor3 = BODY_COLOR

		local stroke = label:FindFirstChild("GlowStroke") :: UIStroke?
		if stroke then
			stroke.Thickness = 0
			stroke.Transparency = 1
		end
	end

	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.Size = UDim2.new(0, 100, 0, 50)

	if #pool < POOL_SIZE * 2 then
		table.insert(pool, gui)
	else
		gui:Destroy()
	end
end

--------------------------------------------------
-- Damage Number Animation
--------------------------------------------------

local function showDamageNumber(damage: number, position: Vector3, isHeadshot: boolean, isCritical: boolean)
	local gui = getFromPool()
	activeCount += 1

	local label = gui:FindFirstChild("Label") :: TextLabel
	local stroke = label:FindFirstChild("GlowStroke") :: UIStroke

	-- set text
	label.Text = tostring(damage)

	-- set color and size based on hit type
	if isCritical then
		label.TextColor3 = CRIT_COLOR
		label.TextSize = CRIT_SIZE
	elseif isHeadshot then
		label.TextColor3 = HEADSHOT_COLOR
		label.TextSize = HEADSHOT_SIZE
		-- enable glow for headshots
		stroke.Thickness = 2
		stroke.Transparency = 0.2
		stroke.Color = HEADSHOT_STROKE_COLOR
	else
		label.TextColor3 = BODY_COLOR
		label.TextSize = BODY_SIZE
	end

	-- random horizontal offset to prevent stacking
	local xOffset = (math.random() - 0.5) * 2 * X_SPREAD
	local zOffset = (math.random() - 0.5) * 2 * X_SPREAD

	-- create an anchor part at the hit position
	local anchor = Instance.new("Part")
	anchor.Name = "DmgAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position + Vector3.new(xOffset, 0, zOffset)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = workspace.Terrain

	gui.Adornee = anchor
	gui.StudsOffset = Vector3.new(0, 1, 0)
	gui.Enabled = true
	gui.Parent = anchor

	-- pop animation: start bigger, shrink to normal
	local startSize = if isHeadshot or isCritical
		then HEADSHOT_SIZE * POP_SCALE
		else BODY_SIZE * POP_SCALE
	local endSize = if isCritical
		then CRIT_SIZE
		elseif isHeadshot
		then HEADSHOT_SIZE
		else BODY_SIZE

	label.TextSize = math.floor(startSize)

	-- pop shrink tween
	local popTween = TweenService:Create(label, TweenInfo.new(
		POP_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	), {
		TextSize = endSize,
	})
	popTween:Play()

	-- float upward + fade out
	local floatTween = TweenService:Create(gui, TweenInfo.new(
		DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		StudsOffset = Vector3.new(0, 1 + FLOAT_DISTANCE, 0),
	})
	floatTween:Play()

	-- fade text
	local fadeTween = TweenService:Create(label, TweenInfo.new(
		DURATION * 0.4, -- fade starts after 60% of duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})

	-- fade glow stroke too
	local glowFadeTween = TweenService:Create(stroke, TweenInfo.new(
		DURATION * 0.4,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), {
		Transparency = 1,
	})

	-- delay the fade to happen in the last 40% of the animation
	task.delay(DURATION * 0.6, function()
		fadeTween:Play()
		glowFadeTween:Play()
	end)

	-- cleanup after animation
	task.delay(DURATION + 0.1, function()
		activeCount -= 1
		returnToPool(gui)
		anchor:Destroy()
	end)
end

--------------------------------------------------
-- Remote Handler
--------------------------------------------------

DamageDealtRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local damage = data.damage
	local position = data.position
	local isHeadshot = data.isHeadshot or false
	local isCritical = data.isCritical or false

	if not damage or not position then
		return
	end

	if typeof(position) ~= "Vector3" then
		return
	end

	if type(damage) ~= "number" or damage <= 0 then
		return
	end

	showDamageNumber(math.floor(damage), position, isHeadshot, isCritical)
end)

--------------------------------------------------
-- Initialize
--------------------------------------------------

initPool()
