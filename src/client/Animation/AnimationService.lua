--!strict
-- AnimationService.lua
-- Manages layered character animations for movement and combat.
--
-- LAYER SYSTEM (Roblox AnimationPriority):
--   Movement layer (full body):  Walk, Sprint, Idle      → Priority: Movement
--   Action layer (upper body):   HoldGun idle/sprint      → Priority: Action
--   Firing layer (upper body):   GunFire                  → Priority: Action (played on top, non-looped)
--
-- The firing animation is non-looped and plays at Action priority,
-- so it naturally overrides the hold pose while active, then the
-- hold pose resumes when it finishes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

------------------------------------------------------
-- Animation IDs (Roblox asset IDs)
------------------------------------------------------
local ANIM_IDS = {
	-- Full-body locomotion
	Walk     = "rbxassetid://88040472585441",
	Sprint   = "rbxassetid://134677963904217",

	-- Upper-body gun holds (just arms)
	HoldSprint = "rbxassetid://119287132358124",
	HoldIdle   = "rbxassetid://79200796379476",

	-- Firing (just arms, single shot)
	Fire     = "rbxassetid://86509179442283",
}

------------------------------------------------------
-- State
------------------------------------------------------

-- Cached references (reset on respawn)
local animator: Animator? = nil
local humanoid: Humanoid? = nil

-- Loaded AnimationTrack cache: { [animName]: AnimationTrack }
local tracks: { [string]: AnimationTrack } = {}

-- Current logical states
local currentMovementState: "Idle" | "Walk" | "Sprint" = "Idle"
local currentActionState: "None" | "HoldGun" | "ADS" = "None"

-- Track whether we are firing (to prevent overlapping fire anims)
local isFireAnimPlaying = false

------------------------------------------------------
-- Helpers
------------------------------------------------------

local function getAnimator(): Animator?
	if animator then
		return animator
	end

	local character = player.Character
	if not character then
		return nil
	end

	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	humanoid = hum

	local anim = hum:FindFirstChildOfClass("Animator")
	if not anim then
		-- Create one if it doesn't exist (Roblox sometimes delays this)
		anim = Instance.new("Animator")
		anim.Parent = hum
	end

	animator = anim
	return anim
end

-- Load (or retrieve cached) AnimationTrack by name
local function getTrack(name: string): AnimationTrack?
	if tracks[name] then
		return tracks[name]
	end

	local animId = ANIM_IDS[name]
	if not animId then
		warn("[AnimationService] Unknown animation name: " .. name)
		return nil
	end

	local anim = getAnimator()
	if not anim then
		return nil
	end

	local animInstance = Instance.new("Animation")
	animInstance.AnimationId = animId

	local ok, track = pcall(function()
		return anim:LoadAnimation(animInstance)
	end)

	if not ok or not track then
		warn("[AnimationService] Failed to load animation: " .. name)
		return nil
	end

	tracks[name] = track
	return track
end

-- Stop a track safely with optional fade time
local function stopTrack(name: string, fadeTime: number?)
	local track = tracks[name]
	if track and track.IsPlaying then
		track:Stop(fadeTime or 0.15)
	end
end

-- Play a track safely with optional fade time and priority
local function playTrack(name: string, fadeTime: number?, priority: Enum.AnimationPriority?, looped: boolean?): AnimationTrack?
	local track = getTrack(name)
	if not track then
		return nil
	end

	-- Set priority before playing
	if priority then
		track.Priority = priority
	end

	-- Set looped
	if looped ~= nil then
		track.Looped = looped
	end

	if not track.IsPlaying then
		track:Play(fadeTime or 0.15)
	end

	return track
end

------------------------------------------------------
-- Movement Layer (full-body locomotion)
------------------------------------------------------

local function updateMovementAnimation()
	local state = currentMovementState

	if state == "Sprint" then
		stopTrack("Walk", 0.2)
		playTrack("Sprint", 0.2, Enum.AnimationPriority.Movement, true)
	elseif state == "Walk" then
		stopTrack("Sprint", 0.2)
		playTrack("Walk", 0.2, Enum.AnimationPriority.Movement, true)
	else
		-- Idle: stop all movement anims, let Roblox default idle play
		stopTrack("Walk", 0.2)
		stopTrack("Sprint", 0.2)
	end
end

------------------------------------------------------
-- Action Layer (upper-body gun hold / ADS)
------------------------------------------------------

local function updateActionAnimation()
	local action = currentActionState
	local movement = currentMovementState

	if action == "HoldGun" or action == "ADS" then
		-- Choose the correct hold animation based on movement
		if movement == "Sprint" then
			stopTrack("HoldIdle", 0.15)
			playTrack("HoldSprint", 0.15, Enum.AnimationPriority.Action, true)
		else
			stopTrack("HoldSprint", 0.15)
			playTrack("HoldIdle", 0.15, Enum.AnimationPriority.Action, true)
		end
	else
		-- Not holding gun: stop all upper-body overlays
		stopTrack("HoldIdle", 0.2)
		stopTrack("HoldSprint", 0.2)
	end
end

------------------------------------------------------
-- Firing (one-shot overlay on Action priority)
------------------------------------------------------

local function playFireAnimation()
	-- Don't stack multiple fire animations
	local track = getTrack("Fire")
	if not track then
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false

	-- If already playing, restart from the beginning for rapid fire
	if track.IsPlaying then
		track:Stop(0)
		task.wait() -- yield one frame so Roblox registers the stop
	end

	track:Play(0.05) -- very fast fade-in for snappy feel
	isFireAnimPlaying = true

	-- When the fire animation finishes, the hold animation underneath
	-- automatically shows through (it's still playing at Action priority
	-- but fire takes precedence while active)
	track.Stopped:Once(function()
		isFireAnimPlaying = false
	end)
end

------------------------------------------------------
-- Public API
------------------------------------------------------

local AnimationService = {}

-- Set movement state: "Idle" | "Walk" | "Sprint"
-- Called by SprintController and can be auto-detected
function AnimationService.SetMovementState(state: "Idle" | "Walk" | "Sprint")
	if currentMovementState == state then
		return
	end

	currentMovementState = state
	updateMovementAnimation()

	-- Also update action layer since hold animation depends on movement
	updateActionAnimation()
end

-- Set action state: "None" | "HoldGun" | "ADS"
-- Called by GunController on equip/unequip
function AnimationService.SetActionState(actionState: "HoldGun" | "ADS" | "None")
	if currentActionState == actionState then
		return
	end

	currentActionState = actionState
	updateActionAnimation()
end

-- Play the firing animation (one-shot, overlays on top of hold)
-- Called by GunController on each shot
function AnimationService.PlayFire()
	playFireAnimation()
end

-- Get current movement state (for external queries)
function AnimationService.GetMovementState(): string
	return currentMovementState
end

-- Get current action state (for external queries)
function AnimationService.GetActionState(): string
	return currentActionState
end

------------------------------------------------------
-- Auto-detect walk vs idle based on humanoid velocity
------------------------------------------------------

RunService.RenderStepped:Connect(function()
	-- Only auto-detect walk/idle if NOT sprinting
	-- (SprintController explicitly sets Sprint state)
	if currentMovementState == "Sprint" then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	local moveDir = hum.MoveDirection
	local isMoving = moveDir.Magnitude > 0.1

	local newState: "Idle" | "Walk" = if isMoving then "Walk" else "Idle"

	if newState ~= currentMovementState then
		currentMovementState = newState
		updateMovementAnimation()
		updateActionAnimation()
	end
end)

------------------------------------------------------
-- Character lifecycle: reset on respawn
------------------------------------------------------

local function onCharacterAdded(_character: Model)
	-- Clear cached references and tracks
	animator = nil
	humanoid = nil
	tracks = {}
	currentMovementState = "Idle"
	currentActionState = "None"
	isFireAnimPlaying = false
end

player.CharacterAdded:Connect(onCharacterAdded)

print("[AnimationService] Initialized")

return AnimationService
