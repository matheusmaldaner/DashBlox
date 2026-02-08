--!strict

-- client-side mystery box visuals: weapon cycling animation,
-- light beam, teddy bear effect, and relocate VFX

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MysteryBoxConfig = require(ReplicatedStorage.Modules.MysteryBoxConfig)
local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local player = Players.LocalPlayer

--------------------------------------------------
-- Remotes
--------------------------------------------------

local MysteryBoxOpenedRemote = RemoteService.GetRemote("MysteryBoxOpened") :: RemoteEvent
local MysteryBoxResultRemote = RemoteService.GetRemote("MysteryBoxResult") :: RemoteEvent
local MysteryBoxPickedUpRemote = RemoteService.GetRemote("MysteryBoxPickedUp") :: RemoteEvent
local MysteryBoxExpiredRemote = RemoteService.GetRemote("MysteryBoxExpired") :: RemoteEvent
local MysteryBoxRelocateRemote = RemoteService.GetRemote("MysteryBoxRelocate") :: RemoteEvent
local MysteryBoxReappearRemote = RemoteService.GetRemote("MysteryBoxReappear") :: RemoteEvent

--------------------------------------------------
-- State
--------------------------------------------------

local cyclingGui: BillboardGui? = nil
local cyclingLabel: TextLabel? = nil
local resultGui: BillboardGui? = nil
local lightBeamPart: Part? = nil
local cyclingVFXBeam: Part? = nil
local cyclingVFXParticles: Part? = nil

--------------------------------------------------
-- Helpers
--------------------------------------------------

-- find the mystery box model in workspace
local function GetBoxModel(): Model?
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and instance:GetAttribute("MysteryBox") then
			return instance :: Model
		end
	end
	-- fallback: find by CollectionService tag
	local CollectionService = game:GetService("CollectionService")
	local tagged = CollectionService:GetTagged("MysteryBox")
	if #tagged > 0 then
		return tagged[1] :: Model
	end
	return nil
end

-- get a random weapon name for cycling animation (visual only)
local function GetRandomWeaponName(): (string, string)
	local pool = MysteryBoxConfig.WeaponPool
	local entry = pool[math.random(1, #pool)]
	return entry.gunName, entry.rarity
end

--------------------------------------------------
-- Cycling VFX (particle glow + light column)
--------------------------------------------------

-- creates particle glow and rising light column during weapon cycling
local function CreateCyclingVFX(boxModel: Model)
	local adornee = boxModel.PrimaryPart or boxModel:FindFirstChildWhichIsA("BasePart")
	if not adornee then
		return
	end

	local boxPos = adornee.Position

	-- rising light column (tweens upward over cycling duration)
	cyclingVFXBeam = Instance.new("Part")
	local beam = cyclingVFXBeam :: Part
	beam.Name = "CyclingBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(0, 150, 255)
	beam.Size = Vector3.new(0.3, 0, 0.3)
	beam.Transparency = 0.4
	beam.CFrame = CFrame.new(boxPos.X, boxPos.Y, boxPos.Z)
	beam.Parent = workspace

	local targetHeight = 40
	TweenService:Create(beam, TweenInfo.new(
		MysteryBoxConfig.CyclingDuration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		Size = Vector3.new(0.3, targetHeight, 0.3),
		CFrame = CFrame.new(boxPos.X, boxPos.Y + targetHeight / 2, boxPos.Z),
	}):Play()

	-- invisible container for particle emitters
	cyclingVFXParticles = Instance.new("Part")
	local particlePart = cyclingVFXParticles :: Part
	particlePart.Name = "CyclingParticles"
	particlePart.Anchored = true
	particlePart.CanCollide = false
	particlePart.CanQuery = false
	particlePart.Transparency = 1
	particlePart.Size = Vector3.new(2, 2, 2)
	particlePart.CFrame = CFrame.new(boxPos + Vector3.new(0, 2, 0))
	particlePart.Parent = workspace

	-- sparkle emitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 40
	emitter.Lifetime = NumberRange.new(0.5, 1.2)
	emitter.Speed = NumberRange.new(3, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 180, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 100, 255)),
	})
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Parent = particlePart

	-- point light for ambient glow around the box
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(0, 150, 255)
	glow.Brightness = 2
	glow.Range = 15
	glow.Parent = particlePart

	-- pulse the glow brightness
	task.spawn(function()
		while particlePart and particlePart.Parent do
			TweenService:Create(glow, TweenInfo.new(0.4), { Brightness = 4 }):Play()
			task.wait(0.4)
			if not particlePart or not particlePart.Parent then
				break
			end
			TweenService:Create(glow, TweenInfo.new(0.4), { Brightness = 1.5 }):Play()
			task.wait(0.4)
		end
	end)
end

-- cleans up cycling VFX with fade-out
local function DestroyCyclingVFX()
	if cyclingVFXBeam then
		local beam = cyclingVFXBeam :: Part
		TweenService:Create(beam, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		task.delay(0.5, function()
			if beam and beam.Parent then
				beam:Destroy()
			end
		end)
		cyclingVFXBeam = nil
	end

	if cyclingVFXParticles then
		local part = cyclingVFXParticles :: Part
		-- stop emitting, let existing particles fade naturally
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
		cyclingVFXParticles = nil
	end
end

--------------------------------------------------
-- Weapon Cycling Animation
--------------------------------------------------

-- creates a billboard gui above the box showing weapon names cycling
local function StartCyclingAnimation(boxModel: Model)
	-- cleanup any existing
	StopCyclingAnimation()

	-- start particle glow and light column
	CreateCyclingVFX(boxModel)

	-- create billboard above the box
	cyclingGui = Instance.new("BillboardGui")
	local gui = cyclingGui :: BillboardGui
	gui.Name = "MysteryBoxCycling"
	gui.Size = UDim2.new(0, 200, 0, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = boxModel.PrimaryPart or boxModel:FindFirstChildWhichIsA("BasePart")
	gui.Parent = player.PlayerGui

	cyclingLabel = Instance.new("TextLabel")
	local label = cyclingLabel :: TextLabel
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	-- outer glow stroke that shifts color per weapon rarity
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(100, 180, 255)
	stroke.Transparency = 0.3
	stroke.Parent = label

	-- cycling animation: flash through weapon names with decelerating speed
	local flashCount = MysteryBoxConfig.CyclingFlashCount
	local startInterval = MysteryBoxConfig.CyclingStartInterval
	local endInterval = MysteryBoxConfig.CyclingEndInterval

	task.spawn(function()
		for i = 1, flashCount do
			if not cyclingLabel then
				break
			end

			-- pick random weapon for display
			local gunName, rarity = GetRandomWeaponName()
			local gunStats = GunConfig.Guns[gunName]
			local displayName = if gunStats then gunStats.Name else gunName
			local rarityColor = MysteryBoxConfig.RarityColors[rarity]
				or Color3.fromRGB(255, 255, 255)

			local label = cyclingLabel :: TextLabel
			label.Text = displayName
			label.TextColor3 = rarityColor

			-- sync glow stroke color to current weapon rarity
			local uiStroke = label:FindFirstChildOfClass("UIStroke")
			if uiStroke then
				uiStroke.Color = rarityColor
			end

			-- decelerate: lerp from start interval to end interval
			local alpha = i / flashCount
			-- ease out quad for satisfying slowdown
			local easedAlpha = 1 - (1 - alpha) * (1 - alpha)
			local interval = startInterval + (endInterval - startInterval) * easedAlpha
			task.wait(interval)
		end
	end)
end

-- shows the teddy bear instead of a weapon
local function ShowTeddyBear(boxModel: Model)
	StopCyclingAnimation()

	cyclingGui = Instance.new("BillboardGui")
	local gui = cyclingGui :: BillboardGui
	gui.Name = "MysteryBoxTeddy"
	gui.Size = UDim2.new(0, 200, 0, 60)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = boxModel.PrimaryPart or boxModel:FindFirstChildWhichIsA("BasePart")
	gui.Parent = player.PlayerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.Text = "BYE BYE!"
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	-- fade out after a moment
	task.delay(2.0, function()
		if gui and gui.Parent then
			local tween = TweenService:Create(label, TweenInfo.new(1.0), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
			tween:Play()
			task.delay(1.0, function()
				StopCyclingAnimation()
			end)
		end
	end)
end

local function StopCyclingAnimation()
	if cyclingGui then
		local gui = cyclingGui :: BillboardGui
		gui:Destroy()
		cyclingGui = nil
		cyclingLabel = nil
	end
	DestroyCyclingVFX()
end

--------------------------------------------------
-- Result Display
--------------------------------------------------

-- shows the final weapon name floating above the box
local function ShowResult(boxModel: Model, gunName: string, rarity: string, isDuplicate: boolean)
	StopCyclingAnimation()

	resultGui = Instance.new("BillboardGui")
	local gui = resultGui :: BillboardGui
	gui.Name = "MysteryBoxResult"
	gui.Size = UDim2.new(0, 250, 0, 60)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = boxModel.PrimaryPart or boxModel:FindFirstChildWhichIsA("BasePart")
	gui.Parent = player.PlayerGui

	local gunStats = GunConfig.Guns[gunName]
	local displayName = if gunStats then gunStats.Name else gunName
	local rarityColor = MysteryBoxConfig.RarityColors[rarity] or Color3.fromRGB(255, 255, 255)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.6, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.Text = displayName
	label.TextColor3 = rarityColor
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	-- subtitle (duplicate indicator)
	if isDuplicate then
		local subtitle = Instance.new("TextLabel")
		subtitle.Size = UDim2.new(1, 0, 0.35, 0)
		subtitle.Position = UDim2.new(0, 0, 0.6, 0)
		subtitle.BackgroundTransparency = 1
		subtitle.TextScaled = true
		subtitle.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
		subtitle.Text = "AMMO REFILL"
		subtitle.TextColor3 = Color3.fromRGB(100, 255, 100)
		subtitle.TextStrokeTransparency = 0.5
		subtitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		subtitle.Parent = gui
	end
end

local function HideResult()
	if resultGui then
		local gui = resultGui :: BillboardGui
		gui:Destroy()
		resultGui = nil
	end
end

--------------------------------------------------
-- Light Beam Effect
--------------------------------------------------

-- creates a tall blue light beam at a position to mark box location
local function CreateLightBeam(position: Vector3)
	DestroyLightBeam()

	lightBeamPart = Instance.new("Part")
	local beam = lightBeamPart :: Part
	beam.Name = "MysteryBoxBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = MysteryBoxConfig.LightBeamColor
	beam.Size = Vector3.new(0.5, MysteryBoxConfig.LightBeamHeight, 0.5)
	beam.Transparency = 0.5
	beam.CFrame = CFrame.new(
		position.X,
		position.Y + MysteryBoxConfig.LightBeamHeight / 2,
		position.Z
	)
	beam.Parent = workspace

	-- pulse animation
	task.spawn(function()
		while beam and beam.Parent do
			local tweenOut = TweenService:Create(beam, TweenInfo.new(1.0), {
				Transparency = 0.8,
			})
			tweenOut:Play()
			tweenOut.Completed:Wait()

			if not beam or not beam.Parent then
				break
			end

			local tweenIn = TweenService:Create(beam, TweenInfo.new(1.0), {
				Transparency = 0.4,
			})
			tweenIn:Play()
			tweenIn.Completed:Wait()
		end
	end)
end

local function DestroyLightBeam()
	if lightBeamPart then
		local beam = lightBeamPart :: Part
		beam:Destroy()
		lightBeamPart = nil
	end
end

--------------------------------------------------
-- Event Listeners
--------------------------------------------------

MysteryBoxOpenedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local boxModel = GetBoxModel()
	if not boxModel then
		return
	end

	if data.isTeddyBear then
		-- start cycling then show teddy bear
		StartCyclingAnimation(boxModel)
		task.delay(MysteryBoxConfig.CyclingDuration * 0.8, function()
			ShowTeddyBear(boxModel)
		end)
	else
		StartCyclingAnimation(boxModel)
	end
end)

MysteryBoxResultRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local boxModel = GetBoxModel()
	if not boxModel then
		return
	end

	ShowResult(boxModel, data.gunName, data.rarity, data.isDuplicate or false)
end)

MysteryBoxPickedUpRemote.OnClientEvent:Connect(function(_data: any)
	HideResult()
end)

MysteryBoxExpiredRemote.OnClientEvent:Connect(function(_data: any)
	HideResult()
end)

MysteryBoxRelocateRemote.OnClientEvent:Connect(function(data: any)
	HideResult()
	StopCyclingAnimation()
	DestroyLightBeam()
end)

MysteryBoxReappearRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	if data.position and typeof(data.position) == "Vector3" then
		CreateLightBeam(data.position)

		-- auto-destroy beam after duration
		task.delay(MysteryBoxConfig.LightBeamDuration, function()
			DestroyLightBeam()
		end)
	end
end)
