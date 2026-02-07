--!strict
-- CrouchController.lua
-- handles crouch mechanics: hold Left Ctrl or toggle C to crouch
-- note: Left Shift is now used for sprint (see SprintController)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputManager = require(ReplicatedStorage:WaitForChild("Modules").InputManager)

local player = Players.LocalPlayer

-- Import SprintController for mutual exclusivity
local SprintController = nil
task.spawn(function()
	local sprintModule = script.Parent:WaitForChild("SprintController", 10)
	if sprintModule then
		SprintController = require(sprintModule)
	end
end)

-- Import AnimationService (wait for it to be available)
local AnimationService = nil
task.spawn(function()
	local AnimationFolder = script.Parent.Parent:WaitForChild("Animation", 10)
	if AnimationFolder then
		AnimationService = require(AnimationFolder:WaitForChild("AnimationService"))
	end
end)

-- crouch configuration
local CROUCH_SPEED = 8 -- studs/s when crouching
local NORMAL_SPEED = 16 -- default walk speed
local CAMERA_CROUCH_OFFSET = -1.0 -- camera Y offset when crouching

-- state
local isCrouching = false
local isCtrlHeld = false
local isCToggled = false
local originalWalkSpeed = NORMAL_SPEED
local cameraYOffset = 0

-- module for external access
local CrouchController = {}

-- returns whether the player is currently crouching
function CrouchController.IsCrouching(): boolean
	return isCrouching
end

-- returns the crouch spread multiplier for weapons
function CrouchController.GetSpreadMultiplier(): number
	return if isCrouching then 0.7 else 1.0
end

-- get humanoid from character
local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- apply crouch state
local function applyCrouchState(crouching: boolean)
	if isCrouching == crouching then
		return
	end

	isCrouching = crouching
	local humanoid = getHumanoid()

	if not humanoid then
		return
	end

	if crouching then
		-- cancel sprint first (mutual exclusivity)
		if SprintController then
			SprintController.CancelSprint()
		end

		-- entering crouch: slow down and lower camera
		originalWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = CROUCH_SPEED
		cameraYOffset = CAMERA_CROUCH_OFFSET

		-- Update animation state
		if AnimationService then
			AnimationService.SetMovementState("Crouch")
		end
	else
		-- exiting crouch: restore speed and camera
		humanoid.WalkSpeed = originalWalkSpeed
		cameraYOffset = 0

		-- Update animation state
		if AnimationService then
			AnimationService.SetMovementState("Idle")
		end
	end
end

-- update crouch based on inputs
local function updateCrouchState()
	-- crouch if either Ctrl is held OR C is toggled on
	local shouldCrouch = isCtrlHeld or isCToggled
	applyCrouchState(shouldCrouch)
end

-- input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- hold Left Ctrl to crouch
	if input.KeyCode == Enum.KeyCode.LeftControl then
		isCtrlHeld = true
		updateCrouchState()
	end

	-- toggle C to crouch
	if input.KeyCode == Enum.KeyCode.C then
		isCToggled = not isCToggled
		updateCrouchState()
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	-- release Left Ctrl
	if input.KeyCode == Enum.KeyCode.LeftControl then
		isCtrlHeld = false
		updateCrouchState()
	end
end)

-- apply camera offset each frame
RunService.RenderStepped:Connect(function(_deltaTime)
	if cameraYOffset ~= 0 then
		local camera = workspace.CurrentCamera
		if camera then
			camera.CFrame = camera.CFrame + Vector3.new(0, cameraYOffset, 0)
		end
	end
end)

-- store original values when character spawns
local function onCharacterAdded(character: Model)
	isCrouching = false
	isCtrlHeld = false
	isCToggled = false
	cameraYOffset = 0

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	originalWalkSpeed = humanoid.WalkSpeed
end

-- reset crouch when character respawns
player.CharacterAdded:Connect(onCharacterAdded)

-- initialize with current character if exists
if player.Character then
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		originalWalkSpeed = humanoid.WalkSpeed
	end
end

--------------------------------------------------
-- InputManager Bindings (Gamepad/Touch Support)
--------------------------------------------------

-- Crouch (R3 on gamepad - right stick click)
InputManager.BindAction("Crouch", function(_actionName, inputState, _inputObject)
	if inputState == Enum.UserInputState.Begin then
		-- toggle crouch on gamepad (single press toggles)
		isCToggled = not isCToggled
		updateCrouchState()
	end
	return Enum.ContextActionResult.Sink
end, false)

print("[CrouchController] Initialized - Ctrl/C to crouch")

return CrouchController
