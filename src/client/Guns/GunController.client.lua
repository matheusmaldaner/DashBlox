--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local GunUtility = require(ReplicatedStorage.Modules.Guns.GunUtility)
local ADSState = require(ReplicatedStorage.Modules.Guns.ADSState)
local CrosshairController = require(script.Parent.CrosshairController)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)
local GameModeService = require(ReplicatedStorage.Modules.GameModeService)
local CrouchController = require(script.Parent.Parent.Movement.CrouchController)
local SprintController = require(script.Parent.Parent.Movement.SprintController)
local AudioService = require(ReplicatedStorage.Modules.Audio.AudioService)
local Keybinds = require(ReplicatedStorage.Modules.Keybinds)
local Settings = require(ReplicatedStorage.Modules.Settings)
local MatchStateClient = require(ReplicatedStorage.Modules.MatchStateClient)
local InputManager = require(ReplicatedStorage.Modules.InputManager)
local AimAssist = require(ReplicatedStorage.Modules.AimAssist)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera :: Camera

local DEFAULT_FOV = 70
local EQUIPPED_GUN_NAME = "EquippedGun"

-- AmmoUI/HotbarUI bridge (created by HotbarUI.client.lua)
local ammoUIEvent: BindableEvent? = nil

local function getAmmoUIEvent(): BindableEvent?
	if ammoUIEvent then
		return ammoUIEvent
	end

	local playerScripts = player:WaitForChild("PlayerScripts", 5)
	if not playerScripts then
		return nil
	end

	-- Wait for bridge to be created by HotbarUI
	local bridge = playerScripts:WaitForChild("AmmoUIBridge", 5)
	if not bridge then
		warn("[GunController] AmmoUIBridge not found")
		return nil
	end

	ammoUIEvent = bridge:WaitForChild("AmmoUIEvent", 5) :: BindableEvent?
	if not ammoUIEvent then
		warn("[GunController] AmmoUIEvent not found")
	end
	return ammoUIEvent
end

-- Initialize bridge early
task.spawn(function()
	getAmmoUIEvent()
end)

local function notifyAmmoUI(eventType: string, ...: any)
	local event = getAmmoUIEvent()
	if event then
		event:Fire(eventType, ...)
	else
		warn("[GunController] Failed to notify AmmoUI:", eventType)
	end
end

local function canUseCombat(): boolean
	return MatchStateClient.IsCombatEnabled()
end

-- Camera offset (must match GunCameraController exactly)
local CAMERA_OFFSET = Vector3.new(2.5, 1.5, 8) -- Right, Up, Back from character

-- Calculate the TRUE camera position and look direction
-- This replicates GunCameraController's calculation exactly to avoid timing issues
local function getTrueCameraRay(): (Vector3, Vector3)
	local character = player.Character
	if not character then
		return camera.CFrame.Position, camera.CFrame.LookVector
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return camera.CFrame.Position, camera.CFrame.LookVector
	end

	-- Extract yaw and pitch from current camera look vector
	local camLook = camera.CFrame.LookVector
	local cameraYaw = math.atan2(-camLook.X, -camLook.Z)
	local cameraPitch = math.asin(math.clamp(camLook.Y, -1, 1))

	-- Character base position (at eye level approximately)
	local characterPos = humanoidRootPart.Position + Vector3.new(0, 1.5, 0)

	-- Calculate camera position with offset (same as GunCameraController)
	local offsetCFrame = CFrame.new(characterPos) * CFrame.Angles(0, cameraYaw, 0)
	local rightOffset = offsetCFrame.RightVector * CAMERA_OFFSET.X
	local upOffset = Vector3.new(0, CAMERA_OFFSET.Y, 0)
	local backOffset = (CFrame.Angles(0, cameraYaw, 0) * CFrame.Angles(cameraPitch, 0, 0)).LookVector * -CAMERA_OFFSET.Z

	local cameraPos = characterPos + rightOffset + upOffset + backOffset

	-- Raycast to prevent camera clipping through walls (same as GunCameraController)
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayDirection = cameraPos - characterPos
	local rayResult = workspace:Raycast(characterPos, rayDirection, rayParams)

	if rayResult then
		cameraPos = rayResult.Position + rayResult.Normal * 0.5
	end

	-- Look direction (same as GunCameraController)
	local lookDirection = (CFrame.Angles(0, cameraYaw, 0) * CFrame.Angles(cameraPitch, 0, 0)).LookVector

	return cameraPos, lookDirection
end

-- DEBUG: Set to true to visualize raycast origin, direction, and hit point
local DEBUG_RAYCAST = false
local DEBUG_LINE_DURATION = 2.0 -- seconds to show debug visuals

local function createDebugLine(startPos: Vector3, endPos: Vector3, color: Color3)
	if not DEBUG_RAYCAST then return end

	local distance = (endPos - startPos).Magnitude
	if distance < 0.1 then return end

	local line = Instance.new("Part")
	line.Name = "DebugRayLine"
	line.Anchored = true
	line.CanCollide = false
	line.CanQuery = false
	line.CanTouch = false
	line.CastShadow = false
	line.Material = Enum.Material.Neon
	line.Color = color
	line.Size = Vector3.new(0.1, 0.1, distance)
	line.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance / 2)
	line.Transparency = 0.3
	line.Parent = workspace.Terrain

	task.delay(DEBUG_LINE_DURATION, function()
		if line.Parent then
			line:Destroy()
		end
	end)
end

local function createDebugDot(position: Vector3, color: Color3, size: number?)
	if not DEBUG_RAYCAST then return end

	local dot = Instance.new("Part")
	dot.Name = "DebugHitDot"
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CastShadow = false
	dot.Material = Enum.Material.Neon
	dot.Color = color
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(size or 0.5, size or 0.5, size or 0.5)
	dot.Position = position
	dot.Transparency = 0
	dot.Parent = workspace.Terrain

	task.delay(DEBUG_LINE_DURATION, function()
		if dot.Parent then
			dot:Destroy()
		end
	end)
end

local _TRACER_LIFETIME = 0.12 -- how long trail lingers after bullet arrives
local BULLET_SPEED = 1400 -- studs per second (visual only, hit is instant)
local WHIZ_DISTANCE = 6
local WHIZ_MIN_DISTANCE_FROM_START = 8
local WHIZ_COOLDOWN = 0.12
local WHIZ_VOLUME = 0.45

-- Bullet impact sound settings
local IMPACT_SOUND_MAX_DISTANCE = 50 -- max distance to hear bullet impacts nearby
local IMPACT_SOUND_MIN_VOLUME = 0.15 -- volume at max distance
local IMPACT_SOUND_MAX_VOLUME = 0.7 -- volume when hit directly or very close

type TracerStyle = {
	color: Color3,
	trailWidth: number,
	bulletSize: number,
	emission: number,
	speed: number, -- studs per second
}

local TRACER_STYLES: { [string]: TracerStyle } = {
	SMG = { color = Color3.fromRGB(255, 220, 50), trailWidth = 0.08, bulletSize = 0.15, emission = 1, speed = 1600 },
	Sniper = { color = Color3.fromRGB(255, 140, 20), trailWidth = 0.2, bulletSize = 0.3, emission = 1, speed = 2200 },
	AR = { color = Color3.fromRGB(255, 235, 170), trailWidth = 0.12, bulletSize = 0.2, emission = 0.9, speed = 1500 },
	PumpShotgun = { color = Color3.fromRGB(255, 190, 90), trailWidth = 0.15, bulletSize = 0.18, emission = 0.85, speed = 1200 },
	TacticalShotgun = { color = Color3.fromRGB(255, 180, 80), trailWidth = 0.14, bulletSize = 0.16, emission = 0.85, speed = 1200 },
	Pistol = { color = Color3.fromRGB(255, 245, 210), trailWidth = 0.1, bulletSize = 0.15, emission = 0.8, speed = 1400 },
}

local DEFAULT_TRACER_STYLE: TracerStyle = {
	color = Color3.fromRGB(255, 220, 50),
	trailWidth = 0.1,
	bulletSize = 0.18,
	emission = 0.9,
	speed = BULLET_SPEED,
}

local lastWhizTime = 0

-- Remotes
local FireGunRemote = RemoteService.GetRemote("FireGun") :: RemoteEvent
local GunHitRemote = RemoteService.GetRemote("GunHit") :: RemoteEvent
local GunFiredRemote = RemoteService.GetRemote("GunFired") :: RemoteEvent
local EquipGunRemote = RemoteService.GetRemote("EquipGun") :: RemoteEvent
local UnequipGunRemote = RemoteService.GetRemote("UnequipGun") :: RemoteEvent
local ReloadGunRemote = RemoteService.GetRemote("ReloadGun") :: RemoteEvent
local GiveLoadoutRemote = RemoteService.GetRemote("GiveLoadout") :: RemoteEvent
local ReloadAllWeaponsRemote = RemoteService.GetRemote("ReloadAllWeapons") :: RemoteEvent

-- Player gun state
local state = {
	equipped = false,
	currentGun = nil :: string?,
	ammo = 0,
	isReloading = false,
	isADS = false,
	lastFireTime = 0,
	weaponModel = nil :: Model?,
	isFiring = false,
	currentRecoil = 0, -- accumulated recoil spread from sustained fire
}
local isAlive = true

-- Sniper scope UI state
local originalTransparencies: { [BasePart]: number } = {}

-- Get the sniper scope frame from FightGUI
local function GetSniperScopeFrame(): Frame?
	local playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		return nil
	end

	local fightGui = playerGui:FindFirstChild("FightGUI") :: ScreenGui?
	if not fightGui then
		return nil
	end

	return fightGui:FindFirstChild("SniperScope") :: Frame?
end

-- Show sniper scope overlay UI
local function ShowSniperScopeUI()
	local scopeFrame = GetSniperScopeFrame()
	if scopeFrame then
		scopeFrame.Visible = true
	end
end

-- Hide sniper scope overlay UI
local function HideSniperScopeUI()
	local scopeFrame = GetSniperScopeFrame()
	if scopeFrame then
		scopeFrame.Visible = false
	end
end

-- Set player character transparency
local function SetCharacterTransparency(transparency: number)
	local character = player.Character
	if not character then
		return
	end

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			-- Store original transparency on first call
			if transparency > 0 and originalTransparencies[part] == nil then
				originalTransparencies[part] = part.LocalTransparencyModifier
			end

			-- Apply transparency (1 = invisible)
			part.LocalTransparencyModifier = transparency

			-- Restore original when transparency is 0
			if transparency == 0 and originalTransparencies[part] ~= nil then
				part.LocalTransparencyModifier = originalTransparencies[part]
				originalTransparencies[part] = nil
			end
		end
	end
end

-- Get the equipped gun model from the player's character
local function GetEquippedGunModel(): Model?
	local character = player.Character
	if not character then
		return nil
	end

	local model = character:FindFirstChild(EQUIPPED_GUN_NAME)
	if model and model:IsA("Model") then
		return model
	end

	return nil
end

-- Set weapon model transparency
local function SetWeaponTransparency(transparency: number)
	local weaponModel = state.weaponModel
	if not weaponModel then
		weaponModel = GetEquippedGunModel()
	end

	if not weaponModel then
		return
	end

	for _, part in weaponModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = transparency
		end
	end
end

-- AnimationService (optional)
local AnimationService = nil
task.spawn(function()
	local animationFolder = script.Parent.Parent:WaitForChild("Animation", 10)
	if animationFolder then
		AnimationService = require(animationFolder:WaitForChild("AnimationService"))
		if state.equipped then
			AnimationService.SetActionState(if state.isADS then "ADS" else "HoldGun")
		end
	end
end)

local function SetGunActionState(actionState: "HoldGun" | "ADS" | "None")
	if AnimationService then
		AnimationService.SetActionState(actionState)
	end
end

-- Loadout inventory (sparse array: nil for empty/consumable slots)
local loadout: { string? } = {}
-- Tracks which slots have ANY content (weapons OR consumables) for scroll navigation
local occupiedSlots: { [number]: boolean } = {}
local currentSlot = 1

-- Per-weapon ammo persistence (keyed by WEAPON NAME, not slot index)
-- This ensures ammo persists even when weapons move between slots
local weaponAmmo: { [string]: number } = {}

-- forward declarations
local UpdateCrosshair: () -> ()
local SwitchToSlot: (slotIndex: number) -> ()

-- Get player's current movement speed
local function GetPlayerSpeed(): number
	local character = player.Character
	if not character then
		return 0
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return 0
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return 0
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	return horizontalVelocity.Magnitude
end

local function GetTracerStyle(gunName: string?): TracerStyle
	if gunName then
		local style = TRACER_STYLES[gunName]
		if style then
			return style
		end
	end

	return DEFAULT_TRACER_STYLE
end

local function GetClosestPointOnSegment(startPos: Vector3, endPos: Vector3, point: Vector3): (Vector3, number, number)
	local segment = endPos - startPos
	local segmentLength = segment.Magnitude
	if segmentLength <= 0 then
		return startPos, 0, 0
	end

	local direction = segment / segmentLength
	local projection = (point - startPos):Dot(direction)
	local distanceAlong = math.clamp(projection, 0, segmentLength)
	local closestPoint = startPos + direction * distanceAlong
	return closestPoint, distanceAlong, segmentLength
end

local function TryPlayBulletWhiz(startPos: Vector3, endPos: Vector3, hitPart: Instance?)
	local character = player.Character
	if hitPart and character and hitPart:IsDescendantOf(character) then
		return
	end

	local cameraPos = camera.CFrame.Position
	local closestPoint, distanceAlong, segmentLength = GetClosestPointOnSegment(startPos, endPos, cameraPos)
	if segmentLength <= WHIZ_MIN_DISTANCE_FROM_START then
		return
	end

	if distanceAlong < WHIZ_MIN_DISTANCE_FROM_START then
		return
	end

	if (cameraPos - closestPoint).Magnitude > WHIZ_DISTANCE then
		return
	end

	local now = tick()
	if now - lastWhizTime < WHIZ_COOLDOWN then
		return
	end
	lastWhizTime = now

	AudioService.PlaySound("Combat", "bulletWhiz", closestPoint, WHIZ_VOLUME)
end

-- Play weapon sound when bullet hits or lands near the local player
-- hitSelf: true if bullet hit the local player directly
-- impactPos: where the bullet landed
-- gunName: weapon that fired (for correct sound)
local function PlayBulletImpactSound(hitSelf: boolean, impactPos: Vector3, gunName: string?)
	if not gunName then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return
	end

	local playerPos = humanoidRootPart.Position
	local distance = (impactPos - playerPos).Magnitude

	-- If bullet hit us directly, play at max volume
	if hitSelf then
		AudioService.PlayWeaponFire(gunName, impactPos)
		return
	end

	-- If bullet landed nearby, scale volume by distance
	if distance <= IMPACT_SOUND_MAX_DISTANCE then
		-- Linear interpolation: closer = louder
		local distanceRatio = distance / IMPACT_SOUND_MAX_DISTANCE
		local volume = IMPACT_SOUND_MAX_VOLUME - (distanceRatio * (IMPACT_SOUND_MAX_VOLUME - IMPACT_SOUND_MIN_VOLUME))

		-- Play the weapon fire sound at the impact position with scaled volume
		local sound = AudioService.PlayWeaponFire(gunName, impactPos)
		if sound then
			sound.Volume = volume
		end
	end
end

-- Create a dark gray beam from point A to B that fades quickly
local function CreateBulletBeam(startPos: Vector3, endPos: Vector3)
	local distance = (endPos - startPos).Magnitude
	if distance <= 0.01 then
		return
	end

	-- Create a thin part to represent the beam
	local beam = Instance.new("Part")
	beam.Name = "BulletBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(80, 80, 80) -- dark gray color
	beam.Size = Vector3.new(0.15, 0.15, distance) -- beam spanning full distance
	beam.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance / 2)
	beam.Transparency = 0.4
	beam.Parent = workspace.Terrain

	-- Fade out and destroy quickly
	task.spawn(function()
		local fadeTime = 0.25
		local startTime = tick()

		while true do
			local elapsed = tick() - startTime
			if elapsed >= fadeTime then
				break
			end

			-- Fade from 0.4 to 1 (fully transparent)
			local alpha = elapsed / fadeTime
			beam.Transparency = 0.4 + (0.6 * alpha)
			task.wait()
		end

		if beam.Parent then
			beam:Destroy()
		end
	end)
end

-- Create bullet tracer effect with flying part + trail
local function CreateTracer(
	startPos: Vector3,
	endPos: Vector3,
	gunName: string?,
	hitPart: Instance?,
	skipWhiz: boolean?
)
	local segment = endPos - startPos
	local distance = segment.Magnitude
	if distance <= 0.01 then
		return
	end

	-- Create gray beam showing bullet path (fades after 1 second)
	CreateBulletBeam(startPos, endPos)

	local style = GetTracerStyle(gunName)
	local direction = segment.Unit
	local travelTime = distance / style.speed
	local bulletLength = style.bulletSize * 3
	local bulletRadius = style.bulletSize * 0.4

	-- create the bullet body (cylindrical shape using a part with cylinder mesh)
	local bullet = Instance.new("Part")
	bullet.Name = "BulletTracer"
	bullet.Size = Vector3.new(bulletRadius * 2, bulletRadius * 2, bulletLength)
	bullet.CFrame = CFrame.lookAt(startPos, endPos)
	bullet.Color = Color3.fromRGB(180, 140, 60) -- brass/copper bullet color
	bullet.Material = Enum.Material.Metal
	bullet.Anchored = true
	bullet.CanCollide = false
	bullet.CanQuery = false
	bullet.CanTouch = false
	bullet.CastShadow = false
	bullet.Parent = workspace.Terrain

	-- add cylindrical mesh for proper bullet shape
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = bullet

	-- rotate so cylinder points forward (cylinder's axis is X by default)
	bullet.CFrame = bullet.CFrame * CFrame.Angles(0, 0, math.rad(90))

	-- create a glowing tip (the hot part of the bullet)
	local bulletTip = Instance.new("Part")
	bulletTip.Name = "BulletTip"
	bulletTip.Size = Vector3.new(bulletRadius * 1.5, bulletRadius * 1.5, bulletRadius * 2)
	bulletTip.Color = style.color
	bulletTip.Material = Enum.Material.Neon
	bulletTip.Transparency = 0.3
	bulletTip.Anchored = true
	bulletTip.CanCollide = false
	bulletTip.CanQuery = false
	bulletTip.CanTouch = false
	bulletTip.CastShadow = false
	bulletTip.Parent = bullet

	local tipMesh = Instance.new("SpecialMesh")
	tipMesh.MeshType = Enum.MeshType.Sphere
	tipMesh.Parent = bulletTip

	-- attachment at the back of the bullet for trails
	local trailAttachment = Instance.new("Attachment")
	trailAttachment.Name = "TrailAttachment"
	trailAttachment.Position = Vector3.new(bulletLength * 0.5, 0, 0) -- back of bullet
	trailAttachment.Parent = bullet

	-- attachment at front for trail origin
	local frontAttachment = Instance.new("Attachment")
	frontAttachment.Name = "FrontAttachment"
	frontAttachment.Position = Vector3.new(-bulletLength * 0.3, 0, 0) -- front of bullet
	frontAttachment.Parent = bullet

	-- main bright tracer trail (the hot streak)
	local tracerTrail = Instance.new("Trail")
	tracerTrail.Name = "TracerTrail"
	tracerTrail.Attachment0 = frontAttachment
	tracerTrail.Attachment1 = trailAttachment
	tracerTrail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, style.color),
		ColorSequenceKeypoint.new(0.3, style.color),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 50)), -- fade to orange/red
	})
	tracerTrail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.3),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	tracerTrail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	tracerTrail.Lifetime = 0.08
	tracerTrail.MinLength = 0.02
	tracerTrail.MaxLength = 50
	tracerTrail.LightEmission = style.emission
	tracerTrail.FaceCamera = true
	tracerTrail.Parent = bullet

	-- smoke/heat trail (wider, more transparent, gives depth)
	local smokeTrail = Instance.new("Trail")
	smokeTrail.Name = "SmokeTrail"
	smokeTrail.Attachment0 = frontAttachment
	smokeTrail.Attachment1 = trailAttachment
	smokeTrail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 180, 150)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 140, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 100)),
	})
	smokeTrail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.3, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeTrail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 1.5),
		NumberSequenceKeypoint.new(1, 2),
	})
	smokeTrail.Lifetime = 0.15
	smokeTrail.MinLength = 0.05
	smokeTrail.MaxLength = 40
	smokeTrail.LightEmission = 0
	smokeTrail.FaceCamera = true
	smokeTrail.Parent = bullet

	-- add point light for glow effect
	local light = Instance.new("PointLight")
	light.Color = style.color
	light.Brightness = 1.2
	light.Range = 6
	light.Shadows = false
	light.Parent = bullet

	if not skipWhiz then
		TryPlayBulletWhiz(startPos, endPos, hitPart)
	end

	-- animate the bullet flying from start to end
	task.spawn(function()
		local startTime = tick()
		local connection: RBXScriptConnection?

		connection = RunService.Heartbeat:Connect(function()
			local elapsed = tick() - startTime
			local alpha = math.min(elapsed / travelTime, 1)

			if alpha >= 1 then
				-- reached destination
				if connection then
					connection:Disconnect()
				end
				local finalCFrame = CFrame.lookAt(endPos - direction * 0.1, endPos) * CFrame.Angles(0, 0, math.rad(90))
				bullet.CFrame = finalCFrame
				bulletTip.CFrame = CFrame.lookAt(endPos - direction * 0.1, endPos)

				-- let trails fade out, then cleanup
				task.delay(0.2, function()
					if bullet.Parent then
						bullet:Destroy()
					end
				end)
			else
				-- move bullet along path
				local currentPos = startPos:Lerp(endPos, alpha)
				local moveCFrame = CFrame.lookAt(currentPos, endPos)
				bullet.CFrame = moveCFrame * CFrame.Angles(0, 0, math.rad(90))
				bulletTip.CFrame = moveCFrame * CFrame.new(0, 0, -bulletLength * 0.4)
			end
		end)
	end)
end

-- Create hit effect at impact point
local function CreateHitEffect(position: Vector3, normal: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	-- orient the attachment to face along the surface normal for directional sparks
	if normal.Magnitude > 0.01 then
		attachment.CFrame = CFrame.lookAt(position, position + normal)
	end
	attachment.Parent = workspace.Terrain

	-- bright spark particles (hot metal fragments)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 30)),
	})
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.3, 0.08),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.15, 0.35)
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(8, 25)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Acceleration = Vector3.new(0, -40, 0) -- gravity pulls sparks down
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Parent = attachment

	-- dust/debris particles
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(180, 170, 150))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.3, 0.6)
	dust.Rate = 0
	dust.Speed = NumberRange.new(2, 8)
	dust.SpreadAngle = Vector2.new(90, 90)
	dust.Acceleration = Vector3.new(0, -10, 0)
	dust.LightEmission = 0
	dust.Parent = attachment

	-- emit particles
	sparks:Emit(8)
	dust:Emit(4)

	-- brief flash of light at impact
	local impactLight = Instance.new("PointLight")
	impactLight.Color = Color3.fromRGB(255, 200, 100)
	impactLight.Brightness = 2
	impactLight.Range = 5
	impactLight.Parent = attachment

	-- fade out the light
	task.spawn(function()
		for i = 1, 5 do
			task.wait(0.02)
			impactLight.Brightness = 2 * (1 - i / 5)
		end
	end)

	task.delay(0.7, function()
		attachment:Destroy()
	end)
end

-- Create muzzle flash effect at weapon muzzle
local function CreateMuzzleFlash(muzzleAttachment: Attachment)
	-- Bright flash particle
	local flash = Instance.new("ParticleEmitter")
	flash.Name = "MuzzleFlash"
	flash.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 150)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 20)),
	})
	flash.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.2, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	flash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	flash.Lifetime = NumberRange.new(0.03, 0.06)
	flash.Rate = 0
	flash.Speed = NumberRange.new(0, 2)
	flash.SpreadAngle = Vector2.new(15, 15)
	flash.LightEmission = 1
	flash.LightInfluence = 0
	flash.Brightness = 3
	flash.Parent = muzzleAttachment

	-- Emit flash particles
	flash:Emit(8)

	-- Cleanup after effect completes
	task.delay(0.1, function()
		if flash.Parent then
			flash:Destroy()
		end
	end)
end

-- Equip a gun
local function EquipGun(gunName: string)
	if not canUseCombat() then
		return
	end
	if state.equipped then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		warn("Gun config not found: " .. gunName)
		return
	end

	-- Update state
	state.equipped = true
	state.currentGun = gunName
	state.weaponModel = nil
	state.lastFireTime = 0
	state.currentRecoil = 0 -- reset recoil when equipping new weapon

	-- Restore persisted ammo for this weapon, or use full magazine if not set
	if weaponAmmo[gunName] ~= nil then
		state.ammo = weaponAmmo[gunName]
	else
		state.ammo = gunStats.MagazineSize
		weaponAmmo[gunName] = state.ammo
	end

	-- Tell server we equipped
	EquipGunRemote:FireServer(gunName)

	-- Cache replicated weapon model (server-created)
	-- First, try to find it immediately (might already exist from server)
	local existingModel = character:FindFirstChild(EQUIPPED_GUN_NAME)
	if existingModel and existingModel:IsA("Model") then
		state.weaponModel = existingModel
	else
		-- Model not ready yet, wait for it asynchronously
		task.spawn(function()
			local model = character:WaitForChild(EQUIPPED_GUN_NAME, 2)
			if model and model:IsA("Model") then
				state.weaponModel = model
			end
		end)
	end

	-- Show crosshair
	CrosshairController.Show()
	UpdateCrosshair()

	-- Notify AmmoUI
	notifyAmmoUI("Equipped", gunName, state.ammo)

	-- Play upper-body hold gun animation
	SetGunActionState("HoldGun")
end

-- Unequip current gun
local function UnequipGun()
	if not state.equipped then
		return
	end

	-- Save current ammo for this weapon before unequipping
	if state.currentGun then
		weaponAmmo[state.currentGun] = state.ammo
	end

	-- Check if sniper scoped before resetting state
	local wasSniperScoped = state.isADS and state.currentGun == "Sniper"

	state.weaponModel = nil

	-- Reset ADS if active
	if state.isADS then
		state.isADS = false
		ADSState.SetADS(false, nil, 1.0)
		TweenService:Create(camera, TweenInfo.new(0.2), { FieldOfView = DEFAULT_FOV }):Play()

		-- Clean up sniper scope if it was active
		if wasSniperScoped then
			HideSniperScopeUI()
			SetCharacterTransparency(0)
			SetWeaponTransparency(0)
		end
	end

	-- Update state
	state.equipped = false
	state.currentGun = nil
	state.isFiring = false
	state.isReloading = false
	state.currentRecoil = 0 -- reset recoil when unequipping

	-- Tell server we unequipped
	UnequipGunRemote:FireServer()

	-- Hide crosshair
	CrosshairController.Hide()

	-- Notify AmmoUI
	notifyAmmoUI("Unequipped")

	-- Stop upper-body hold gun animation
	SetGunActionState("None")
end

-- Toggle equip/unequip
local function ToggleEquip()
	if state.equipped then
		UnequipGun()
	else
		EquipGun(GunConfig.DefaultGun)
	end
end

-- Keep ToggleEquip around for future input bindings.
local _ = ToggleEquip

-- Reload the current weapon
local function Reload()
	if not canUseCombat() then
		return
	end
	if not state.equipped or state.isReloading or not state.currentGun then
		return
	end

	local gunStats = GunConfig.Guns[state.currentGun]
	if not gunStats then
		return
	end

	-- Don't reload if already full
	if state.ammo >= gunStats.MagazineSize then
		return
	end

	state.isReloading = true
	state.isFiring = false -- stop firing during reload

	-- Exit ADS during reload
	if state.isADS then
		local wasSniper = state.currentGun == "Sniper"
		state.isADS = false
		ADSState.SetADS(false, nil, 1.0)
		TweenService:Create(camera, TweenInfo.new(0.2), { FieldOfView = DEFAULT_FOV }):Play()
		SetGunActionState("HoldGun")

		-- Clean up sniper scope if it was active
		if wasSniper then
			HideSniperScopeUI()
			SetCharacterTransparency(0)
			SetWeaponTransparency(0)
			CrosshairController.Show()
		end
	end

	-- Play reload sound
	AudioService.PlayWeaponReload(state.currentGun)

	-- Notify AmmoUI reload started
	notifyAmmoUI("ReloadStarted")

	-- Capture current gun name for the delayed callback
	local reloadingGun = state.currentGun

	-- Wait for reload time then refill ammo
	task.delay(gunStats.ReloadTime, function()
		-- Make sure we're still equipped with same gun
		if state.equipped and state.currentGun == reloadingGun then
			state.ammo = gunStats.MagazineSize
			weaponAmmo[reloadingGun] = state.ammo -- sync persisted ammo by weapon name
			state.isReloading = false

			-- Tell server we reloaded
			ReloadGunRemote:FireServer()

			-- Notify AmmoUI reload finished
			notifyAmmoUI("ReloadFinished", state.ammo)
		else
			-- Gun changed during reload, reset reload state
			state.isReloading = false
		end
	end)
end

-- Update crosshair spread based on current state
UpdateCrosshair = function()
	if not state.equipped or not state.currentGun then
		return
	end

	local gunStats = GunConfig.Guns[state.currentGun]
	if not gunStats then
		return
	end

	local playerState: GunUtility.PlayerState = {
		isMoving = GetPlayerSpeed() > 0.5,
		moveSpeed = GetPlayerSpeed(),
		isADS = state.isADS,
		isCrouching = CrouchController.IsCrouching(),
		isSprinting = SprintController.IsSprinting(),
	}

	local spread = GunUtility.CalculateSpread(gunStats, playerState)
	-- Add accumulated recoil to spread
	spread = spread + state.currentRecoil
	CrosshairController.SetSpread(spread)
end

-- Perform a single shot
local function Shoot()
	if not canUseCombat() then
		return
	end
	if not isAlive then
		return
	end
	if not state.equipped or state.isReloading or not state.currentGun then
		return
	end

	local gunStats = GunConfig.Guns[state.currentGun]
	if not gunStats then
		return
	end

	-- Fire rate check
	local minInterval = 60 / gunStats.FireRate
	local currentTime = tick()
	if currentTime - state.lastFireTime < minInterval then
		return
	end

	-- Ammo check - auto reload if empty
	if state.ammo <= 0 then
		-- Play empty click sound
		AudioService.PlayWeaponEmpty(state.currentGun)
		Reload()
		return
	end

	state.lastFireTime = currentTime
	state.ammo -= 1

	-- Play fire sound (optimized local version - no 3D positioning for own shots)
	AudioService.PlayWeaponFireLocal(state.currentGun)

	-- Notify AmmoUI of ammo change
	notifyAmmoUI("AmmoChanged", state.ammo)

	-- Auto-reload when magazine is empty
	if state.ammo <= 0 then
		task.defer(Reload)
	end

	-- Cancel sprint when shooting (Fortnite-style)
	SprintController.CancelSprint()

	-- Calculate spread (base + recoil)
	local playerState: GunUtility.PlayerState = {
		isMoving = GetPlayerSpeed() > 0.5,
		moveSpeed = GetPlayerSpeed(),
		isADS = state.isADS,
		isCrouching = CrouchController.IsCrouching(),
		isSprinting = SprintController.IsSprinting(),
	}
	local spread = GunUtility.CalculateSpread(gunStats, playerState) + state.currentRecoil

	-- STEP 1: Find the aim point (where crosshair points in 3D world)
	-- Use getTrueCameraRay() to calculate camera position exactly like GunCameraController
	-- This avoids timing issues where camera.CFrame might be stale
	local cameraPos, cameraLookDir = getTrueCameraRay()

	local aimRaycastParams = RaycastParams.new()
	if player.Character then
		aimRaycastParams.FilterDescendantsInstances = { player.Character }
	end
	aimRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local aimResult = workspace:Raycast(cameraPos, cameraLookDir * gunStats.MaxRange, aimRaycastParams)
	local aimPoint = aimResult and aimResult.Position or (cameraPos + cameraLookDir * gunStats.MaxRange)

	-- STEP 2: Get muzzle and back attachment positions from weapon model
	local muzzlePos = cameraPos -- fallback to camera if no muzzle
	local backPos = cameraPos -- fallback to camera if no back attachment
	local muzzleAttachment: Attachment? = nil
	local backAttachment: Attachment? = nil

	if not state.weaponModel or not state.weaponModel.Parent then
		state.weaponModel = GetEquippedGunModel()
	end
	if state.weaponModel then
		local muzzle = state.weaponModel:FindFirstChild("Muzzle", true)
		if muzzle and muzzle:IsA("Attachment") then
			muzzleAttachment = muzzle
			muzzlePos = muzzle.WorldPosition
		end

		local back = state.weaponModel:FindFirstChild("Back", true)
		if back and back:IsA("Attachment") then
			backAttachment = back
			backPos = back.WorldPosition
		end
	end

	-- STEP 3: Check if anything is between Back and Muzzle (weapon clipping through wall)
	-- If so, use Back attachment as the shot origin instead of Muzzle
	local useBackAttachment = false

	if backAttachment and muzzleAttachment then
		local backToMuzzle = muzzlePos - backPos
		local backToMuzzleDist = backToMuzzle.Magnitude

		if backToMuzzleDist > 0.1 then
			local backToMuzzleCheck = workspace:Raycast(backPos, backToMuzzle.Unit * backToMuzzleDist, aimRaycastParams)
			if backToMuzzleCheck then
				-- Something is between Back and Muzzle = weapon clipping through geometry
				useBackAttachment = true
			end
		end
	end

	-- Choose shot origin based on clipping check
	local shotOrigin = useBackAttachment and backPos or muzzlePos

	-- Check if this is a perfect accuracy shot (spread essentially zero)
	local isPerfectAccuracy = spread < 0.001

	local origin: Vector3
	local direction: Vector3
	local result: RaycastResult?

	if isPerfectAccuracy then
		-- PERFECT ACCURACY: Shot hits exactly where crosshair points
		-- Use camera ray directly - bullet goes precisely to aim point
		origin = shotOrigin
		direction = (aimPoint - shotOrigin).Unit

		-- The hit is whatever the camera was aiming at (aimResult from earlier)
		result = aimResult

		print("[GunController] PERFECT ACCURACY - using aimResult directly")
	else
		-- SPREAD ACTIVE: Calculate from muzzle with spread applied

		-- Calculate direction from shot origin to aim point
		local originToAim = aimPoint - shotOrigin
		local distanceToAim = originToAim.Magnitude
		local originToAimDir = distanceToAim > 0.01 and originToAim.Unit or cameraLookDir

		-- Check if aim point is behind the shot origin (dot product with camera look < 0)
		-- or if it's extremely close (< 1 stud)
		local isBehindOrigin = originToAimDir:Dot(cameraLookDir) < 0.1
		local isTooClose = distanceToAim < 1

		local baseDirection: Vector3

		if isBehindOrigin or isTooClose then
			-- Fallback: shoot from camera position in camera direction
			-- This prevents shooting yourself when gun is against a wall
			origin = cameraPos
			baseDirection = cameraLookDir
		else
			-- Check if there's geometry between shot origin and aim point
			local originToAimCheck = workspace:Raycast(shotOrigin, originToAimDir * distanceToAim, aimRaycastParams)

			if originToAimCheck then
				-- There's something between origin and aim point
				-- Shoot toward the obstruction (hit the wall)
				baseDirection = (originToAimCheck.Position - shotOrigin).Unit
			else
				-- Clear line of sight from origin to aim point
				baseDirection = originToAimDir
			end

			origin = shotOrigin
		end

		-- Apply spread to direction
		direction = GunUtility.ApplySpreadToDirection(baseDirection, spread)

		-- Raycast with spread-adjusted direction
		local raycastParams = RaycastParams.new()
		if player.Character then
			raycastParams.FilterDescendantsInstances = { player.Character }
		end
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		result = workspace:Raycast(origin, direction * gunStats.MaxRange, raycastParams)
	end

	-- DEBUG: Visualize the raycast
	if DEBUG_RAYCAST then
		local endPos = result and result.Position or (origin + direction * gunStats.MaxRange)

		-- Cyan dot at aim point (where crosshair points in 3D)
		createDebugDot(aimPoint, Color3.fromRGB(0, 255, 255), 0.4)

		-- Green dot at muzzle (shot origin)
		createDebugDot(origin, Color3.fromRGB(0, 255, 0), 0.3)

		-- Blue line from muzzle to aim point (base direction, no spread)
		createDebugLine(origin, aimPoint, Color3.fromRGB(0, 150, 255))

		-- Yellow line for actual shot direction (with spread applied)
		createDebugLine(origin, endPos, Color3.fromRGB(255, 255, 0))

		-- Red dot at final hit point
		createDebugDot(endPos, Color3.fromRGB(255, 0, 0), 0.4)

		-- White dot at exact hit if we hit something
		if result then
			createDebugDot(result.Position, Color3.fromRGB(255, 255, 255), 0.25)
		end
	end

	-- Update crosshair
	UpdateCrosshair()

	-- Send to server
	local hitData = nil
	if result then
		hitData = {
			position = result.Position,
			part = result.Instance,
			normal = result.Normal,
		}
	end

	FireGunRemote:FireServer({
		origin = origin,
		direction = direction,
		hitData = hitData,
	})

	-- Muzzle flash effect
	if muzzleAttachment then
		CreateMuzzleFlash(muzzleAttachment)
	end

	local endPos = result and result.Position or (origin + direction * gunStats.MaxRange)

	-- For shotguns, skip client-side tracers - server will send authoritative pellet positions
	-- This ensures visual tracers match actual damage (critical for competitive play)
	local isShotgun = GunConfig.ShotgunPellets[state.currentGun] and GunConfig.ShotgunPellets[state.currentGun] > 1
	if not isShotgun then
		CreateTracer(muzzlePos, endPos, state.currentGun, result and result.Instance or nil)
		if result then
			CreateHitEffect(result.Position, result.Normal)
		end
	end
	-- Shotgun tracers rendered when server responds via GunFiredRemote

	-- Accumulate recoil AFTER the shot (so first shot has 0 recoil)
	state.currentRecoil = math.min(state.currentRecoil + gunStats.RecoilPerShot, gunStats.MaxRecoilSpread)
end

-- Enter ADS (Aim Down Sights)
local function EnterADS()
	if not canUseCombat() then
		return
	end
	if not isAlive then
		return
	end
	if not state.equipped or state.isADS or not state.currentGun then
		return
	end

	local gunStats = GunConfig.Guns[state.currentGun]
	if not gunStats then
		return
	end

	-- Cancel sprint when entering ADS (Fortnite-style)
	SprintController.CancelSprint()

	state.isADS = true

	-- Update shared ADS state for camera sensitivity
	ADSState.SetADS(true, state.currentGun, gunStats.ADSSensitivityMultiplier)

	local targetFOV = DEFAULT_FOV * gunStats.ADSFOVMultiplier
	TweenService:Create(camera, TweenInfo.new(gunStats.ADSTransitionTime), { FieldOfView = targetFOV }):Play()

	-- Sniper-specific: show scope overlay and hide player/weapon
	if state.currentGun == "Sniper" then
		ShowSniperScopeUI()
		SetCharacterTransparency(1)
		SetWeaponTransparency(1)
		CrosshairController.ShowSniperDot() -- Show red dot when scoped
	end

	SetGunActionState("ADS")
	UpdateCrosshair()
end

-- Exit ADS
local function ExitADS()
	if not state.isADS or not state.currentGun then
		return
	end

	local gunStats = GunConfig.Guns[state.currentGun]
	if not gunStats then
		return
	end

	-- Check if we were using sniper before changing state
	local wasSniper = state.currentGun == "Sniper"

	state.isADS = false

	-- Update shared ADS state for camera sensitivity
	ADSState.SetADS(false, nil, 1.0)

	TweenService:Create(camera, TweenInfo.new(gunStats.ADSTransitionTime), { FieldOfView = DEFAULT_FOV }):Play()

	-- Sniper-specific: hide scope overlay and restore player/weapon visibility
	if wasSniper then
		HideSniperScopeUI()
		SetCharacterTransparency(0)
		SetWeaponTransparency(0)
		CrosshairController.HideSniperDot() -- Restore original crosshair
		CrosshairController.Show() -- Show crosshair again
	end

	SetGunActionState("HoldGun")
	UpdateCrosshair()
end

MatchStateClient.OnCombatChanged(function(enabled)
	if not enabled and state.equipped then
		UnequipGun()
	end
end)

-- Slot keybinds (dynamically read from Keybinds module)
local weaponSlotActions = { "weapon1", "weapon2", "weapon3", "weapon4", "weapon5" }

local function getSlotIndexForKey(keyCode: Enum.KeyCode): number?
	for slotIndex, action in weaponSlotActions do
		local boundKey = Keybinds.Get(action)
		if boundKey and keyCode == boundKey then
			return slotIndex
		end
	end
	return nil
end

-- Input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Don't process any gun input while settings menu is open
	if Settings.IsMenuOpen() then
		return
	end
	if not canUseCombat() then
		return
	end

	-- Slot keys - handle all slots uniformly (weapons, consumables, empty)
	-- These keys now ALWAYS work and auto-switch to Gun mode (Fortnite-style)
	if not gameProcessed then
		local slotIndex = getSlotIndexForKey(input.KeyCode)
		if slotIndex then
			SwitchToSlot(slotIndex)
		end
	end

	-- Left mouse button to shoot (allow even when camera is processing)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if state.equipped and isAlive then
			state.isFiring = true
			Shoot()
		end
	end

	-- Right mouse button to ADS (allow even when camera is processing)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		EnterADS()
	end

	-- R key to reload
	if input.KeyCode == Enum.KeyCode.R and not gameProcessed then
		if state.equipped then
			Reload()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	-- Stop firing
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		state.isFiring = false
	end

	-- Exit ADS
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		ExitADS()
	end
end)

-- Track delta time for recoil decay
local lastFrameTime = tick()

-- DEBUG: Persistent crosshair aim beam (updates every frame)
local debugAimBeam: Part? = nil
local debugAimDot: Part? = nil

local function updateDebugAimBeam()
	if not DEBUG_RAYCAST then
		-- Clean up if debug disabled
		if debugAimBeam then
			debugAimBeam:Destroy()
			debugAimBeam = nil
		end
		if debugAimDot then
			debugAimDot:Destroy()
			debugAimDot = nil
		end
		return
	end

	if not state.equipped then
		-- Hide when gun not equipped
		if debugAimBeam then
			debugAimBeam.Transparency = 1
		end
		if debugAimDot then
			debugAimDot.Transparency = 1
		end
		return
	end

	-- STEP 1: Find the aim point using TRUE camera position (matches GunCameraController)
	local cameraPos, cameraLookDir = getTrueCameraRay()

	local raycastParams = RaycastParams.new()
	if player.Character then
		raycastParams.FilterDescendantsInstances = { player.Character }
	end
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local maxRange = 500
	local aimResult = workspace:Raycast(cameraPos, cameraLookDir * maxRange, raycastParams)
	local aimPoint = aimResult and aimResult.Position or (cameraPos + cameraLookDir * maxRange)

	-- STEP 2: Get muzzle position
	local muzzlePos = cameraPos -- fallback
	if state.weaponModel then
		local muzzle = state.weaponModel:FindFirstChild("Muzzle", true)
		if muzzle and muzzle:IsA("Attachment") then
			muzzlePos = muzzle.WorldPosition
		end
	end

	-- Offset beam slightly to the right so it's visible (0.05 studs)
	local rightOffset = camera.CFrame.RightVector * 0.05
	local beamStart = muzzlePos + rightOffset
	local beamEnd = aimPoint + rightOffset

	local distance = (beamEnd - beamStart).Magnitude

	-- Create or update beam (from muzzle to aim point)
	if not debugAimBeam then
		debugAimBeam = Instance.new("Part")
		debugAimBeam.Name = "DebugAimBeam"
		debugAimBeam.Anchored = true
		debugAimBeam.CanCollide = false
		debugAimBeam.CanQuery = false
		debugAimBeam.CanTouch = false
		debugAimBeam.CastShadow = false
		debugAimBeam.Material = Enum.Material.Neon
		debugAimBeam.Color = Color3.fromRGB(0, 255, 255) -- Cyan
		debugAimBeam.Parent = workspace.Terrain
	end

	debugAimBeam.Size = Vector3.new(0.05, 0.05, distance)
	debugAimBeam.CFrame = CFrame.lookAt(beamStart, beamEnd) * CFrame.new(0, 0, -distance / 2)
	debugAimBeam.Transparency = 0.5

	-- Create or update dot at aim point (where crosshair hits)
	if not debugAimDot then
		debugAimDot = Instance.new("Part")
		debugAimDot.Name = "DebugAimDot"
		debugAimDot.Anchored = true
		debugAimDot.CanCollide = false
		debugAimDot.CanQuery = false
		debugAimDot.CanTouch = false
		debugAimDot.CastShadow = false
		debugAimDot.Material = Enum.Material.Neon
		debugAimDot.Color = Color3.fromRGB(0, 255, 255) -- Cyan
		debugAimDot.Shape = Enum.PartType.Ball
		debugAimDot.Size = Vector3.new(0.3, 0.3, 0.3)
		debugAimDot.Parent = workspace.Terrain
	end

	debugAimDot.Position = aimPoint
	debugAimDot.Transparency = 0
end

-- Update loop for recoil decay and continuous firing
RunService.RenderStepped:Connect(function()
	local currentTime = tick()
	local deltaTime = currentTime - lastFrameTime
	lastFrameTime = currentTime

	-- Always update debug aim beam when equipped
	updateDebugAimBeam()

	if not state.equipped or not state.currentGun then
		-- Reset recoil when not equipped
		state.currentRecoil = 0
		return
	end

	local gunStats = GunConfig.Guns[state.currentGun]
	if not gunStats then
		return
	end

	-- Decay recoil over time (faster decay when not firing)
	if state.currentRecoil > 0 then
		local decayRate = gunStats.RecoilDecayRate
		-- Decay faster when not actively firing
		if not state.isFiring then
			decayRate = decayRate * 2
		end
		state.currentRecoil = math.max(0, state.currentRecoil - decayRate * deltaTime)
	end

	-- Continuous firing for automatic weapons
	if state.isFiring and gunStats.FireMode == "Auto" then
		Shoot()
	end

	-- Update crosshair every frame
	UpdateCrosshair()
end)

-- Handle hit confirmation from server
GunHitRemote.OnClientEvent:Connect(function(hitInfo)
	-- Play hit marker sound
	AudioService.PlayHitMarker(hitInfo.headshot)

	-- Play kill sound if eliminated
	if hitInfo.killed then
		AudioService.PlayKillSound()
		print("[Gun] Kill confirmed!")
	end
end)

local function bindCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		isAlive = humanoid.Health > 0
		humanoid.Died:Connect(function()
			isAlive = false
			state.isFiring = false
		end)
	else
		isAlive = true
	end
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

-- Render tracers from server-authoritative shot data
-- For shotguns, this includes local player to ensure visual tracers match actual damage
GunFiredRemote.OnClientEvent:Connect(function(data)
	if not data then
		return
	end

	local isLocalPlayer = data.shooterId == player.UserId
	local startPos = data.startPos
	if typeof(startPos) ~= "Vector3" then
		return
	end

	local gunName = if type(data.gunName) == "string" then data.gunName else nil

	-- Check if this is a shotgun with multiple pellet tracers
	if data.pelletTracers and type(data.pelletTracers) == "table" then
		-- Track if any pellet hit us (for impact sound) - only for other players' shots
		local hitUs = false
		local closestImpactPos: Vector3? = nil
		local closestDistance = math.huge

		-- Render all pellet tracers (server-authoritative positions)
		for _, pelletData in data.pelletTracers do
			if typeof(pelletData.endPos) == "Vector3" then
				local skipWhiz = isLocalPlayer or pelletData.hitPlayerId == player.UserId
				CreateTracer(startPos, pelletData.endPos, gunName, nil, skipWhiz)

				-- Create hit effects for local player's shotgun pellets
				if isLocalPlayer then
					CreateHitEffect(pelletData.endPos, Vector3.yAxis)
				end

				-- Check if this pellet hit us or is near us (only for other players' shots)
				if not isLocalPlayer then
					if pelletData.hitPlayerId == player.UserId then
						hitUs = true
						closestImpactPos = pelletData.endPos
					elseif not hitUs then
						-- Track closest impact for nearby sound
						local character = player.Character
						if character then
							local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
							if hrp then
								local dist = (pelletData.endPos - hrp.Position).Magnitude
								if dist < closestDistance then
									closestDistance = dist
									closestImpactPos = pelletData.endPos
								end
							end
						end
					end
				end
			end
		end

		-- Play impact sound for the closest pellet that hit us or landed nearby (other players only)
		if not isLocalPlayer and closestImpactPos then
			PlayBulletImpactSound(hitUs, closestImpactPos, gunName)
		end
	else
		-- Single tracer (regular gun) - skip for local player (already rendered client-side)
		if isLocalPlayer then
			return
		end

		local endPos = data.endPos
		if typeof(endPos) ~= "Vector3" then
			return
		end
		local skipWhiz = data.hitPlayerId == player.UserId
		CreateTracer(startPos, endPos, gunName, nil, skipWhiz)

		-- Play impact sound if bullet hit us or landed nearby
		local hitUs = data.hitPlayerId == player.UserId
		PlayBulletImpactSound(hitUs, endPos, gunName)
	end
end)

--------------------------------------------------
-- Loadout System
--------------------------------------------------

-- Helper to count weapons in loadout (sparse array safe)
local function getWeaponCount(): number
	local count = 0
	for i = 1, 5 do
		if loadout[i] then
			count += 1
		end
	end
	return count
end

-- Helper to count occupied slots (weapons + consumables) for scroll navigation
local function getOccupiedSlotCount(): number
	local count = 0
	for i = 1, 5 do
		if occupiedSlots[i] then
			count += 1
		end
	end
	return count
end

-- Helper to check if a slot has a weapon (kept for potential future use)
local function _slotHasWeapon(slotIndex: number): boolean
	return slotIndex >= 1 and slotIndex <= 5 and loadout[slotIndex] ~= nil
end

-- Switch to a specific weapon slot
function SwitchToSlot(slotIndex: number)
	if not canUseCombat() then
		return
	end
	if slotIndex < 1 or slotIndex > 5 then
		return
	end

	-- Check if this slot has a weapon
	local gunName = loadout[slotIndex]
	if not gunName then
		-- Slot is empty or has a consumable, just update current slot without equipping
		currentSlot = slotIndex
		if state.equipped then
			UnequipGun()
		end
		notifyAmmoUI("SlotChanged", slotIndex + 1, loadout)
		return
	end

	-- already on this slot with same weapon
	if currentSlot == slotIndex and state.equipped then
		return
	end

	-- unequip current weapon
	if state.equipped then
		UnequipGun()
	end

	-- equip weapon from slot
	currentSlot = slotIndex
	if GunConfig.Guns[gunName] then
		-- Play weapon switch sound
		AudioService.PlayWeaponSwitch(gunName)
		EquipGun(gunName)
	end

	-- notify hotbar of slot change
	notifyAmmoUI("SlotChanged", slotIndex + 1, loadout)
end

-- Switch to next slot (skips empty slots, includes consumables)
local function SwitchToNextWeapon()
	if getOccupiedSlotCount() == 0 then
		return
	end

	-- Find next occupied slot (weapon or consumable)
	local nextSlot = currentSlot
	for _ = 1, 5 do
		nextSlot = nextSlot + 1
		if nextSlot > 5 then
			nextSlot = 1
		end
		if occupiedSlots[nextSlot] then
			SwitchToSlot(nextSlot)
			return
		end
	end
end

-- Switch to previous slot (skips empty slots, includes consumables)
local function SwitchToPreviousWeapon()
	if getOccupiedSlotCount() == 0 then
		return
	end

	-- Find previous occupied slot (weapon or consumable)
	local prevSlot = currentSlot
	for _ = 1, 5 do
		prevSlot = prevSlot - 1
		if prevSlot < 1 then
			prevSlot = 5
		end
		if occupiedSlots[prevSlot] then
			SwitchToSlot(prevSlot)
			return
		end
	end
end

-- Handle receiving loadout from server
-- NOTE: weapons array preserves slot positions (nil for empty/consumable slots)
GiveLoadoutRemote.OnClientEvent:Connect(function(weapons: { string? })
	-- Clear existing loadout (but NOT weaponAmmo - ammo is keyed by weapon name and persists)
	loadout = {}

	-- NOTE: Don't call UnequipGun() here - InventoryChangedRemote will handle the
	-- equip/unequip sequence properly. Calling UnequipGun() here causes a race condition
	-- where state.weaponModel gets wiped before the new weapon can be cached.

	-- Store loadout preserving slot positions (max 5 slots now)
	-- weapons[1] = inventory slot 1, weapons[2] = inventory slot 2, etc.
	-- Server sends empty strings "" for non-weapon slots to preserve array structure
	for i = 1, 5 do
		local gunName = weapons[i]
		-- Check for valid weapon (not nil, not empty string, and exists in config)
		if gunName and gunName ~= "" and GunConfig.Guns[gunName] then
			loadout[i] = gunName
			-- Mark weapon slots as occupied for scroll navigation
			-- (InventoryChangedRemote will provide the full picture including consumables)
			occupiedSlots[i] = true
		else
			loadout[i] = nil -- empty or consumable slot
			-- Don't mark as unoccupied - consumables may be in this slot
			-- InventoryChangedRemote will set the correct value
		end
	end

	-- Build display string for logging (skip nils)
	local displayNames = {}
	for i = 1, 5 do
		if loadout[i] then
			table.insert(displayNames, i .. ":" .. loadout[i])
		end
	end
	print("[GunController] Received loadout:", table.concat(displayNames, ", "))

	-- Notify hotbar of new loadout
	notifyAmmoUI("LoadoutChanged", loadout)

	-- NOTE: We no longer auto-equip here. The server controls which slot is equipped
	-- via InventoryChangedRemote. This prevents conflicts between client and server state.
end)

-- Handle server-initiated slot changes (from pickup/drop auto-select)
-- NOTE: This handler directly updates GunController state without triggering
-- the bridge notification loop. HotbarUI handles its own visual updates via
-- its own InventoryChangedRemote listener.
local InventoryChangedRemote = RemoteService.GetRemote("InventoryChanged") :: RemoteEvent
InventoryChangedRemote.OnClientEvent:Connect(function(inventory)
	if not inventory or typeof(inventory) ~= "table" then
		return
	end

	-- Update occupiedSlots from full inventory data (for scroll navigation)
	-- This tracks BOTH weapons and consumables, unlike loadout which only tracks weapons
	if inventory.slots then
		for i = 1, 5 do
			local slotData = inventory.slots[tostring(i)]
			occupiedSlots[i] = slotData and slotData.slotType ~= "empty" and slotData.itemId ~= nil
		end
	end

	-- Check if server specified an equipped slot
	local equippedSlot = inventory.equippedSlot
	if not equippedSlot or equippedSlot < 1 or equippedSlot > 5 then
		return
	end

	-- Only switch if combat is enabled
	if not canUseCombat() then
		return
	end

	-- Check what weapon should be in this slot
	local expectedGun = loadout[equippedSlot]

	-- Determine if we need to update weapon state
	-- Case 1: Different slot - always need to switch
	-- Case 2: Same slot but weapon changed (e.g., auto-swap during pickup)
	local slotChanged = currentSlot ~= equippedSlot
	local weaponChanged = state.currentGun ~= expectedGun

	-- Skip if already on this slot with the same weapon (or both empty)
	if not slotChanged and not weaponChanged then
		return
	end

	-- Unequip current weapon first (saves ammo)
	if state.equipped then
		UnequipGun()
	end

	-- Update to new slot
	currentSlot = equippedSlot

	-- Check if new slot has a weapon
	if expectedGun and GunConfig.Guns[expectedGun] then
		-- Switch to gun mode and equip the weapon
		GameModeService.SetMode("Gun")
		-- Play weapon switch sound (only if slot changed, not just weapon swap)
		if slotChanged then
			AudioService.PlayWeaponSwitch(expectedGun)
		end
		EquipGun(expectedGun)
	end

	-- NOTE: Do NOT call notifyAmmoUI("SlotChanged") here to avoid feedback loop
	-- HotbarUI already receives InventoryChanged and updates its own state
end)

-- Scroll wheel to switch weapons
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not canUseCombat() then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		if GameModeService.IsGunMode() and getWeaponCount() > 1 then
			if input.Position.Z > 0 then
				SwitchToPreviousWeapon()
			else
				SwitchToNextWeapon()
			end
		end
	end
end)

-- Set up sprint blocking callback (cannot sprint while ADS or firing)
SprintController.SetCanSprintCallback(function(): boolean
	-- Cannot sprint while ADS
	if state.isADS then
		return false
	end
	-- Cannot sprint while actively firing
	if state.isFiring then
		return false
	end
	return true
end)

--------------------------------------------------
-- InputManager Bindings (Gamepad/Touch Support)
--------------------------------------------------

-- Fire weapon (RT on gamepad)
InputManager.BindAction("Fire", function(_actionName, inputState, _inputObject)
	if not canUseCombat() then
		return Enum.ContextActionResult.Pass
	end
	if not state.equipped or not isAlive then
		return Enum.ContextActionResult.Pass
	end

	if inputState == Enum.UserInputState.Begin then
		state.isFiring = true
		Shoot()
	elseif inputState == Enum.UserInputState.End then
		state.isFiring = false
	end
	return Enum.ContextActionResult.Sink
end, false)

-- ADS (LT on gamepad)
InputManager.BindAction("ADS", function(_actionName, inputState, _inputObject)
	if not canUseCombat() then
		return Enum.ContextActionResult.Pass
	end

	if inputState == Enum.UserInputState.Begin then
		EnterADS()
	elseif inputState == Enum.UserInputState.End then
		ExitADS()
	end
	return Enum.ContextActionResult.Sink
end, false)

-- Reload (X button on gamepad)
InputManager.BindAction("Reload", function(_actionName, inputState, _inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not canUseCombat() then
		return Enum.ContextActionResult.Pass
	end
	if state.equipped then
		Reload()
	end
	return Enum.ContextActionResult.Sink
end, false)

-- Weapon slot switching (DPad on gamepad)
InputManager.BindAction("Weapon1", function(_actionName, inputState, _inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not canUseCombat() then
		return Enum.ContextActionResult.Pass
	end
	-- SwitchToSlot handles empty slots gracefully
	GameModeService.SetMode("Gun")
	SwitchToSlot(1)
	return Enum.ContextActionResult.Sink
end, false)

InputManager.BindAction("Weapon2", function(_actionName, inputState, _inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not canUseCombat() then
		return Enum.ContextActionResult.Pass
	end
	GameModeService.SetMode("Gun")
	SwitchToSlot(2)
	return Enum.ContextActionResult.Sink
end, false)

InputManager.BindAction("Weapon3", function(_actionName, inputState, _inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not canUseCombat() then
		return Enum.ContextActionResult.Pass
	end
	GameModeService.SetMode("Gun")
	SwitchToSlot(3)
	return Enum.ContextActionResult.Sink
end, false)

InputManager.BindAction("Weapon4", function(_actionName, inputState, _inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not canUseCombat() then
		return Enum.ContextActionResult.Pass
	end
	GameModeService.SetMode("Gun")
	SwitchToSlot(4)
	return Enum.ContextActionResult.Sink
end, false)

InputManager.BindAction("Weapon5", function(_actionName, inputState, _inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if not canUseCombat() then
		return Enum.ContextActionResult.Pass
	end
	GameModeService.SetMode("Gun")
	SwitchToSlot(5)
	return Enum.ContextActionResult.Sink
end, false)

-- Force aim assist target update on respawn
player.CharacterAdded:Connect(function()
	AimAssist.ForceTargetUpdate()
end)

-- Handle server request to reload all weapons (round start/respawn)
ReloadAllWeaponsRemote.OnClientEvent:Connect(function()
	-- Reset all weapon ammo to full magazine size
	for weaponName, _ in weaponAmmo do
		local gunStats = GunConfig.Guns[weaponName]
		if gunStats then
			weaponAmmo[weaponName] = gunStats.MagazineSize
		end
	end

	-- Also update current weapon's ammo if equipped
	if state.equipped and state.currentGun then
		local gunStats = GunConfig.Guns[state.currentGun]
		if gunStats then
			state.ammo = gunStats.MagazineSize
			weaponAmmo[state.currentGun] = state.ammo
			-- Notify UI of updated ammo
			notifyAmmoUI("Equipped", state.currentGun, state.ammo)
		end
	end

	print("[GunController] All weapons reloaded")
end)

--------------------------------------------------
-- Tool Equip/Unequip Bridge
-- when player equips a weapon tool from the backpack/hotbar,
-- route it through the existing EquipGun/UnequipGun flow
--------------------------------------------------

local function bindToolEvents(tool: Tool)
	local gunName = tool:GetAttribute("GunName")
	if not gunName or not GunConfig.Guns[gunName] then
		return
	end

	tool.Equipped:Connect(function()
		if state.equipped then
			UnequipGun()
		end
		EquipGun(gunName)
	end)

	tool.Unequipped:Connect(function()
		if state.equipped and state.currentGun == gunName then
			UnequipGun()
		end
	end)
end

-- bind tools already in backpack
local backpack = player:WaitForChild("Backpack", 10)
if backpack then
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") then
			bindToolEvents(child)
		end
	end

	-- bind tools added later (server creates them after character spawns)
	backpack.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindToolEvents(child)
		end
	end)
end

-- also bind tools that are already equipped (in character) on respawn
local function bindCharacterTools(character: Model)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") then
			bindToolEvents(child)
		end
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindToolEvents(child)
		end
	end)
end

player.CharacterAdded:Connect(function(character)
	bindCharacterTools(character)
end)

if player.Character then
	bindCharacterTools(player.Character)
end

print("[GunController] Initialized")
