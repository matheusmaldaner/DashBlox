--!strict

-- client-side Pack-a-Punch VFX: light beam, particle glow, weapon name cycling,
-- upgraded name reveal with flash effect (mirrors mystery box animation style)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackAPunchConfig = require(ReplicatedStorage.Modules.Guns.PackAPunchConfig)
local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PackAPunchStartedRemote = RemoteService.GetRemote("PackAPunchStarted") :: RemoteEvent
local PackAPunchCompletedRemote = RemoteService.GetRemote("PackAPunchCompleted") :: RemoteEvent
local PackAPunchFailedRemote = RemoteService.GetRemote("PackAPunchFailed") :: RemoteEvent

--------------------------------------------------
-- State
--------------------------------------------------

local cyclingGui: BillboardGui? = nil
local cyclingLabel: TextLabel? = nil
local vfxBeam: Part? = nil
local vfxParticles: Part? = nil
local screenGui: ScreenGui? = nil

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function GetPAPMachine(): Instance?
	local tagged = CollectionService:GetTagged("PackAPunch")
	if #tagged > 0 then
		return tagged[1]
	end
	return nil
end

local function GetMachineAdornee(machine: Instance): BasePart?
	if machine:IsA("BasePart") then
		return machine
	elseif machine:IsA("Model") then
		return (machine :: Model).PrimaryPart
			or machine:FindFirstChildWhichIsA("BasePart") :: BasePart?
	end
	return nil
end

local function GetFlashColor(): Color3
	local c = PackAPunchConfig.FlashColor
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function GetUpgradedColor(): Color3
	local c = PackAPunchConfig.UpgradedFlashColor
	return Color3.fromRGB(c.r, c.g, c.b)
end

--------------------------------------------------
-- Screen GUI (for flash effects)
--------------------------------------------------

local function EnsureScreenGui(): ScreenGui
	if screenGui and screenGui.Parent then
		return screenGui :: ScreenGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PackAPunchHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 7
	gui.Parent = playerGui
	screenGui = gui
	return gui
end

--------------------------------------------------
-- VFX: Light Beam + Particles
--------------------------------------------------

local function CreateUpgradeVFX(adornee: BasePart)
	local pos = adornee.Position
	local flashColor = GetFlashColor()

	-- rising orange light beam
	vfxBeam = Instance.new("Part")
	local beam = vfxBeam :: Part
	beam.Name = "PAPBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = flashColor
	beam.Size = Vector3.new(0.4, 0, 0.4)
	beam.Transparency = 0.3
	beam.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
	beam.Parent = workspace

	local targetHeight = 50
	TweenService:Create(beam, TweenInfo.new(
		PackAPunchConfig.UpgradeDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Size = Vector3.new(0.4, targetHeight, 0.4),
		CFrame = CFrame.new(pos.X, pos.Y + targetHeight / 2, pos.Z),
	}):Play()

	-- particle container
	vfxParticles = Instance.new("Part")
	local particlePart = vfxParticles :: Part
	particlePart.Name = "PAPParticles"
	particlePart.Anchored = true
	particlePart.CanCollide = false
	particlePart.CanQuery = false
	particlePart.Transparency = 1
	particlePart.Size = Vector3.new(3, 3, 3)
	particlePart.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
	particlePart.Parent = workspace

	-- sparks emitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 60
	emitter.Lifetime = NumberRange.new(0.4, 1.0)
	emitter.Speed = NumberRange.new(4, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, flashColor),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 50, 0)),
	})
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = particlePart

	-- pulsing glow
	local glow = Instance.new("PointLight")
	glow.Color = flashColor
	glow.Brightness = 3
	glow.Range = 20
	glow.Parent = particlePart

	task.spawn(function()
		while particlePart and particlePart.Parent do
			TweenService:Create(glow, TweenInfo.new(0.3), { Brightness = 6 }):Play()
			task.wait(0.3)
			if not particlePart or not particlePart.Parent then
				break
			end
			TweenService:Create(glow, TweenInfo.new(0.3), { Brightness = 2 }):Play()
			task.wait(0.3)
		end
	end)
end

local function DestroyUpgradeVFX()
	if vfxBeam then
		local beam = vfxBeam :: Part
		TweenService:Create(beam, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		task.delay(0.5, function()
			if beam and beam.Parent then
				beam:Destroy()
			end
		end)
		vfxBeam = nil
	end

	if vfxParticles then
		local part = vfxParticles :: Part
		for _, child in part:GetChildren() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		task.delay(1.5, function()
			if part and part.Parent then
				part:Destroy()
			end
		end)
		vfxParticles = nil
	end
end

--------------------------------------------------
-- Billboard: Weapon Name Cycling
--------------------------------------------------

local function StartCyclingAnimation(adornee: BasePart, gunName: string)
	-- cleanup previous
	if cyclingGui then
		(cyclingGui :: BillboardGui):Destroy()
		cyclingGui = nil
		cyclingLabel = nil
	end

	cyclingGui = Instance.new("BillboardGui")
	local gui = cyclingGui :: BillboardGui
	gui.Name = "PAPCycling"
	gui.Size = UDim2.new(0, 250, 0, 50)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = adornee
	gui.Parent = playerGui

	cyclingLabel = Instance.new("TextLabel")
	local label = cyclingLabel :: TextLabel
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.TextColor3 = GetFlashColor()
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = "UPGRADING..."
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = GetFlashColor()
	stroke.Transparency = 0.3
	stroke.Parent = label

	-- cycle through random weapon names, then lock on the real one
	local flashCount = PackAPunchConfig.CyclingFlashCount
	local startInterval = PackAPunchConfig.CyclingStartInterval
	local endInterval = PackAPunchConfig.CyclingEndInterval

	-- collect all weapon display names for cycling
	local weaponNames: { string } = {}
	for _, stats in GunConfig.Guns do
		table.insert(weaponNames, stats.Name)
	end

	task.spawn(function()
		for i = 1, flashCount do
			if not cyclingLabel then
				break
			end

			local displayName = weaponNames[math.random(1, #weaponNames)]
			local currentLabel = cyclingLabel :: TextLabel
			currentLabel.Text = displayName

			-- flash color oscillation
			local alpha = i / flashCount
			local r = math.floor(255 - alpha * 100)
			local g = math.floor(100 + alpha * 100)
			local b = math.floor(0 + alpha * 50)
			currentLabel.TextColor3 = Color3.fromRGB(r, g, b)

			-- decelerate
			local easedAlpha = 1 - (1 - alpha) * (1 - alpha)
			local interval = startInterval + (endInterval - startInterval) * easedAlpha
			task.wait(interval)
		end
	end)
end

local function StopCyclingAnimation()
	if cyclingGui then
		(cyclingGui :: BillboardGui):Destroy()
		cyclingGui = nil
		cyclingLabel = nil
	end
end

--------------------------------------------------
-- Reveal: Upgraded Weapon Name
--------------------------------------------------

local function ShowUpgradeResult(adornee: BasePart, upgradedName: string)
	StopCyclingAnimation()

	-- billboard with upgraded name
	cyclingGui = Instance.new("BillboardGui")
	local gui = cyclingGui :: BillboardGui
	gui.Name = "PAPResult"
	gui.Size = UDim2.new(0, 300, 0, 60)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = adornee
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.Text = upgradedName
	label.TextColor3 = GetUpgradedColor()
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	local resultStroke = Instance.new("UIStroke")
	resultStroke.Thickness = 2
	resultStroke.Color = GetUpgradedColor()
	resultStroke.Transparency = 0.2
	resultStroke.Parent = label

	-- scale-in pop
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.2,
	}):Play()

	-- fade out after 3 seconds
	task.delay(3, function()
		if gui and gui.Parent then
			local fadeLabel = gui:FindFirstChildWhichIsA("TextLabel")
			if fadeLabel then
				TweenService:Create(fadeLabel, TweenInfo.new(1.0), {
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				}):Play()
			end
			task.delay(1.0, function()
				if gui and gui.Parent then
					gui:Destroy()
				end
				cyclingGui = nil
			end)
		end
	end)
end

--------------------------------------------------
-- Screen Flash
--------------------------------------------------

local function PlayUpgradeFlash()
	local gui = EnsureScreenGui()

	local flash = Instance.new("Frame")
	flash.Name = "PAPFlash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = GetUpgradedColor()
	flash.BackgroundTransparency = 0.6
	flash.BorderSizePixel = 0
	flash.ZIndex = 100
	flash.Parent = gui

	TweenService:Create(flash, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()

	task.delay(0.8, function()
		if flash and flash.Parent then
			flash:Destroy()
		end
	end)
end

--------------------------------------------------
-- Event Listeners
--------------------------------------------------

PackAPunchStartedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local machine = GetPAPMachine()
	if not machine then
		return
	end

	local adornee = GetMachineAdornee(machine)
	if not adornee then
		return
	end

	CreateUpgradeVFX(adornee)
	StartCyclingAnimation(adornee, data.gunName)
end)

PackAPunchCompletedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local machine = GetPAPMachine()
	local adornee = if machine then GetMachineAdornee(machine) else nil

	DestroyUpgradeVFX()

	if adornee then
		ShowUpgradeResult(adornee, data.upgradedName or "UPGRADED")
	end

	-- flash only for the player who upgraded
	if data.playerId == player.UserId then
		PlayUpgradeFlash()
	end
end)

PackAPunchFailedRemote.OnClientEvent:Connect(function(data: any)
	DestroyUpgradeVFX()
	StopCyclingAnimation()

	if data and data.reason then
		warn("[PackAPunch]", data.reason)
	end
end)
