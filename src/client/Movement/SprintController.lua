--!strict
-- SprintController.lua
-- handles sprint mechanics: hold Left Shift to sprint
-- fortnite-style restrictions: cannot sprint while ADS, shooting, or crouching

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputManager = require(ReplicatedStorage:WaitForChild("Modules").InputManager)

local player = Players.LocalPlayer

-- Import AnimationService (wait for it to be available)
local AnimationService = nil
task.spawn(function()
	local AnimationFolder = script.Parent.Parent:WaitForChild("Animation", 10)
	if AnimationFolder then
		AnimationService = require(AnimationFolder:WaitForChild("AnimationService"))
	end
end)

-- sprint configuration
local SPRINT_SPEED = 22 -- studs/s when sprinting
local NORMAL_SPEED = 16 -- default walk speed

-- state
local isSprinting = false
local isShiftHeld = false
local originalWalkSpeed = NORMAL_SPEED

-- module for external access
local SprintController = {}

-- returns whether the player is currently sprinting
function SprintController.IsSprinting(): boolean
	return isSprinting
end

-- returns the sprint spread multiplier for weapons (worse accuracy)
function SprintController.GetSpreadMultiplier(): number
	return if isSprinting then 1.3 else 1.0
end

-- get humanoid from character
local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- check if player is moving forward (not backwards or sideways only)
local function isMovingForward(): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude < 0.1 then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end

	-- get forward direction (where the character is facing)
	local forwardDirection = rootPart.CFrame.LookVector
	-- flatten to XZ plane
	local flatForward = Vector3.new(forwardDirection.X, 0, forwardDirection.Z).Unit
	local flatMove = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit

	-- dot product > 0.5 means moving mostly forward (within ~60 degrees)
	return flatForward:Dot(flatMove) > 0.5
end

-- apply sprint state
local function applySprintState(sprinting: boolean)
	if isSprinting == sprinting then
		return
	end

	isSprinting = sprinting
	local humanoid = getHumanoid()

	if not humanoid then
		return
	end

	if sprinting then
		-- entering sprint: speed up
		originalWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = SPRINT_SPEED

		-- update animation state
		if AnimationService then
			AnimationService.SetMovementState("Sprint")
		end
	else
		-- exiting sprint: restore speed
		humanoid.WalkSpeed = originalWalkSpeed

		-- update animation state
		if AnimationService then
			AnimationService.SetMovementState("Idle")
		end
	end
end

-- cancel sprint (called by other systems like GunController or CrouchController)
function SprintController.CancelSprint()
	if isSprinting then
		applySprintState(false)
	end
end

-- check if sprint can be activated (external systems can block it)
local canSprintCallback: (() -> boolean)? = nil

function SprintController.SetCanSprintCallback(callback: () -> boolean)
	canSprintCallback = callback
end

-- update sprint based on inputs and conditions
local function updateSprintState()
	-- can only sprint if shift is held and moving forward
	local shouldSprint = isShiftHeld and isMovingForward()

	-- check external conditions (ADS, shooting, etc.)
	if shouldSprint and canSprintCallback then
		shouldSprint = canSprintCallback()
	end

	applySprintState(shouldSprint)
end

-- input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- hold Left Shift to sprint
	if input.KeyCode == Enum.KeyCode.LeftShift then
		isShiftHeld = true
		updateSprintState()
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	-- release Left Shift
	if input.KeyCode == Enum.KeyCode.LeftShift then
		isShiftHeld = false
		updateSprintState()
	end
end)

-- continuously check sprint conditions (movement direction can change)
RunService.RenderStepped:Connect(function(_deltaTime)
	if isShiftHeld then
		-- re-evaluate sprint conditions every frame
		updateSprintState()
	end
end)

-- store original values when character spawns
local function onCharacterAdded(character: Model)
	isSprinting = false
	isShiftHeld = false

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	originalWalkSpeed = humanoid.WalkSpeed
end

-- reset sprint when character respawns
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

-- Sprint (L3 on gamepad - left stick click)
InputManager.BindAction("Sprint", function(_actionName, inputState, _inputObject)
	if inputState == Enum.UserInputState.Begin then
		isShiftHeld = true
		updateSprintState()
	elseif inputState == Enum.UserInputState.End then
		isShiftHeld = false
		updateSprintState()
	end
	return Enum.ContextActionResult.Sink
end, false)

print("[SprintController] Initialized - Hold Shift to sprint")

return SprintController
