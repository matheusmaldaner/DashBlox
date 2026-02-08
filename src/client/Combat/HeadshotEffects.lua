--!strict
-- HeadshotEffects - screen flash vignette + 3D particle burst for headshots
-- called from GunController when a headshot hit is confirmed

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HeadshotEffects = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--------------------------------------------------
-- Screen Flash Vignette
--------------------------------------------------

local FLASH_COLOR = Color3.fromRGB(255, 200, 50) -- warm gold
local FLASH_DURATION = 0.12 -- very brief
local FLASH_FADE = 0.2 -- fade out time
local FLASH_MAX_TRANSPARENCY = 0.4 -- how opaque the vignette gets at peak

-- create the vignette screen gui (4 edge gradients)
local vignetteGui: ScreenGui? = nil
local vignetteFrames: { Frame } = {}

local function createVignetteGui()
	if vignetteGui then
		return
	end

	vignetteGui = Instance.new("ScreenGui")
	vignetteGui.Name = "HeadshotVignette"
	vignetteGui.ResetOnSpawn = false
	vignetteGui.IgnoreGuiInset = true
	vignetteGui.DisplayOrder = 15 -- above crosshair
	vignetteGui.Parent = playerGui

	-- edge definitions: which side, gradient rotation
	local edges = {
		{ name = "Top", size = UDim2.new(1, 0, 0.15, 0), pos = UDim2.new(0, 0, 0, 0), rotation = 0 },
		{ name = "Bottom", size = UDim2.new(1, 0, 0.15, 0), pos = UDim2.new(0, 0, 0.85, 0), rotation = 180 },
		{ name = "Left", size = UDim2.new(0.12, 0, 1, 0), pos = UDim2.new(0, 0, 0, 0), rotation = 270 },
		{ name = "Right", size = UDim2.new(0.12, 0, 1, 0), pos = UDim2.new(0.88, 0, 0, 0), rotation = 90 },
	}

	for _, edge in edges do
		local frame = Instance.new("Frame")
		frame.Name = edge.name
		frame.Size = edge.size
		frame.Position = edge.pos
		frame.BackgroundColor3 = FLASH_COLOR
		frame.BackgroundTransparency = 1 -- fully invisible at start
		frame.BorderSizePixel = 0
		frame.Active = false
		frame.Parent = vignetteGui

		-- gradient fades from opaque at edge to transparent toward center
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), -- opaque at edge
			NumberSequenceKeypoint.new(0.6, 0.7), -- mostly transparent
			NumberSequenceKeypoint.new(1, 1), -- fully transparent at center
		})
		gradient.Rotation = edge.rotation
		gradient.Parent = frame

		table.insert(vignetteFrames, frame)
	end
end

-- flash the screen vignette
function HeadshotEffects.FlashScreen()
	createVignetteGui()

	-- flash in
	for _, frame in vignetteFrames do
		frame.BackgroundTransparency = FLASH_MAX_TRANSPARENCY
	end

	-- hold briefly then fade out
	task.delay(FLASH_DURATION, function()
		for _, frame in vignetteFrames do
			local fadeTween = TweenService:Create(frame, TweenInfo.new(
				FLASH_FADE,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			), {
				BackgroundTransparency = 1,
			})
			fadeTween:Play()
		end
	end)
end

--------------------------------------------------
-- 3D Particle Burst at Headshot Position
--------------------------------------------------

local PARTICLE_COUNT = 15
local PARTICLE_SPEED = NumberRange.new(8, 20)
local PARTICLE_LIFETIME = NumberRange.new(0.2, 0.5)

-- spawn a gold/yellow spark burst at the headshot position
function HeadshotEffects.SpawnParticleBurst(position: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 100)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 180, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 10)),
	})
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.3, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = PARTICLE_LIFETIME
	particles.Rate = 0 -- burst only, no continuous emission
	particles.Speed = PARTICLE_SPEED
	particles.SpreadAngle = Vector2.new(180, 180) -- omnidirectional burst
	particles.LightEmission = 1 -- glowing sparks
	particles.LightInfluence = 0
	particles.Drag = 5 -- sparks slow down quickly
	particles.Parent = attachment

	-- emit burst
	particles:Emit(PARTICLE_COUNT)

	-- cleanup after particles expire
	task.delay(1.0, function()
		if attachment.Parent then
			attachment:Destroy()
		end
	end)
end

--------------------------------------------------
-- Combined Headshot Effect
--------------------------------------------------

-- trigger both screen flash and particle burst
function HeadshotEffects.Play(hitPosition: Vector3?)
	HeadshotEffects.FlashScreen()

	if hitPosition then
		HeadshotEffects.SpawnParticleBurst(hitPosition)
	end
end

return HeadshotEffects
