--!strict
-- CameraController - Fortnite-style over-the-shoulder camera with cursor lock
-- Active in both Gun and Build modes
-- Supports mouse, gamepad (Xbox/PlayStation), and touch input
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ADSState = require(Modules.Guns.ADSState)
local MatchStateClient = require(Modules.MatchStateClient)
local PlatformDetection = require(Modules.PlatformDetection)
local Settings = require(Modules.Settings)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera :: Camera

-- Camera settings (Fortnite-style over-the-shoulder)
local CAMERA_OFFSET = Vector3.new(2.5, 1.5, 8) -- Right, Up, Back from character
local BASE_CAMERA_SENSITIVITY = Vector2.new(0.3, 0.3) -- Base mouse sensitivity (multiplied by player's setting)
local MIN_PITCH = -75 -- Look down limit (degrees)
local MAX_PITCH = 75 -- Look up limit (degrees)

-- Get effective camera sensitivity (base * player setting * Roblox native sensitivity)
local function getCameraSensitivity(): Vector2
	-- Read player's custom sensitivity setting (0.1 to 2.0, default 0.5 = 1x multiplier)
	local customSens = Settings.Get("sensitivity") or 0.5
	-- Normalize so 0.5 = 1x, 0.1 = 0.2x, 1.0 = 2x, 2.0 = 4x
	local sensMultiplier = customSens * 2

	-- Read Roblox's native sensitivity from ESC menu (0-4, default ~1)
	local robloxSens = UserSettings():GetService("UserGameSettings").MouseSensitivity or 1
	-- Normalize so Roblox 1.0 = 1x multiplier
	local robloxMultiplier = robloxSens

	local finalMultiplier = sensMultiplier * robloxMultiplier
	return Vector2.new(
		BASE_CAMERA_SENSITIVITY.X * finalMultiplier,
		BASE_CAMERA_SENSITIVITY.Y * finalMultiplier
	)
end

-- Check if Y axis should be inverted
local function shouldInvertY(): boolean
	return Settings.Get("invertY") or false
end

-- Gamepad camera settings
local GAMEPAD_SENSITIVITY = Vector2.new(3.5, 2.5) -- Degrees per frame at max deflection
local GAMEPAD_DEADZONE = 0.15 -- Stick deadzone (0-1)
local GAMEPAD_ACCELERATION = 2.0 -- Exponential acceleration curve
local GAMEPAD_ADS_SENSITIVITY_MULT = 0.6 -- Additional sensitivity reduction when ADS on gamepad

-- Touch camera settings
local TOUCH_SENSITIVITY = Vector2.new(0.4, 0.3) -- Touch drag sensitivity
local TOUCH_CAMERA_ZONE = 0.35 -- Right portion of screen for camera (0.35 = rightmost 65%)

-- State
local isEnabled = false
local cameraYaw = 0 -- Horizontal rotation (radians)
local cameraPitch = 0 -- Vertical rotation (radians)
local renderConnection: RBXScriptConnection? = nil
local inputConnection: RBXScriptConnection? = nil

-- Gamepad stick state
local rightStickInput = Vector2.new(0, 0)

-- Touch camera state
local activeCameraTouches: { [InputObject]: Vector2 } = {} -- Maps touch -> last position
local touchConnections: { RBXScriptConnection } = {}

-- Convert degrees to radians
local function degToRad(deg: number): number
	return deg * math.pi / 180
end

-- Apply deadzone and acceleration curve to stick input
local function processStickInput(value: number): number
	-- Apply deadzone
	if math.abs(value) < GAMEPAD_DEADZONE then
		return 0
	end

	-- Normalize to 0-1 range after deadzone
	local sign = if value > 0 then 1 else -1
	local normalized = (math.abs(value) - GAMEPAD_DEADZONE) / (1 - GAMEPAD_DEADZONE)

	-- Apply acceleration curve (exponential response)
	local accelerated = math.pow(normalized, GAMEPAD_ACCELERATION)

	return sign * accelerated
end

-- Process gamepad right stick for camera rotation
local function processGamepadCamera()
	if not isEnabled then
		return
	end

	-- check if gamepad is connected and being used
	if not PlatformDetection.IsGamepad() then
		return
	end

	-- get gamepad state
	local gamepads = UserInputService:GetConnectedGamepads()
	if #gamepads == 0 then
		return
	end

	local gamepadState = UserInputService:GetGamepadState(gamepads[1])

	for _, input in gamepadState do
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then -- Right stick
			rightStickInput = Vector2.new(input.Position.X, input.Position.Y)
			break
		end
	end

	-- process stick input with deadzone and acceleration
	local processedX = processStickInput(rightStickInput.X)
	local processedY = processStickInput(rightStickInput.Y)

	-- only apply if there's actual input
	if processedX == 0 and processedY == 0 then
		return
	end

	-- apply sensitivity and ADS reduction
	local sensitivityMultiplier = ADSState.GetSensitivityMultiplier()

	-- additional sensitivity reduction for gamepad when ADS
	if ADSState.IsADS() then
		sensitivityMultiplier = sensitivityMultiplier * GAMEPAD_ADS_SENSITIVITY_MULT
	end

	-- apply player's custom sensitivity setting (0.5 default = 1x, range 0.1-2.0)
	local customSens = (Settings.Get("sensitivity") or 0.5) * 2
	sensitivityMultiplier = sensitivityMultiplier * customSens

	local deltaX = processedX * GAMEPAD_SENSITIVITY.X * sensitivityMultiplier
	local deltaY = processedY * GAMEPAD_SENSITIVITY.Y * sensitivityMultiplier

	-- apply invert Y setting
	if shouldInvertY() then
		deltaY = -deltaY
	end

	-- update yaw (horizontal) - right stick right turns camera right
	cameraYaw = cameraYaw - degToRad(deltaX)

	-- update pitch (vertical) - right stick up looks up (inverted Y)
	cameraPitch = cameraPitch + degToRad(deltaY)

	-- clamp pitch to prevent flipping
	cameraPitch = math.clamp(cameraPitch, degToRad(MIN_PITCH), degToRad(MAX_PITCH))
end

--------------------------------------------------
-- Touch Camera Controls
--------------------------------------------------

-- Check if a touch position is in the camera control zone (right side of screen)
local function isTouchInCameraZone(position: Vector2): boolean
	local screenSize = camera.ViewportSize
	local cameraZoneStart = screenSize.X * TOUCH_CAMERA_ZONE
	return position.X > cameraZoneStart
end

-- Handle touch started
local function onTouchStarted(touch: InputObject, gameProcessed: boolean)
	if not isEnabled then
		return
	end

	-- Skip if touch is on a GUI element
	if gameProcessed then
		return
	end

	-- Only track touches in the camera zone (right side)
	if isTouchInCameraZone(Vector2.new(touch.Position.X, touch.Position.Y)) then
		activeCameraTouches[touch] = Vector2.new(touch.Position.X, touch.Position.Y)
	end
end

-- Handle touch moved
local function onTouchMoved(touch: InputObject, gameProcessed: boolean)
	if not isEnabled then
		return
	end

	-- Check if this touch is being tracked for camera
	local lastPosition = activeCameraTouches[touch]
	if not lastPosition then
		return
	end

	-- Skip if now on GUI (finger dragged onto a button)
	if gameProcessed then
		activeCameraTouches[touch] = nil
		return
	end

	local currentPosition = Vector2.new(touch.Position.X, touch.Position.Y)
	local delta = currentPosition - lastPosition

	-- Apply sensitivity and ADS reduction
	local sensitivityMultiplier = ADSState.GetSensitivityMultiplier()
	-- Apply player's custom sensitivity setting (0.5 default = 1x, range 0.1-2.0)
	local customSens = (Settings.Get("sensitivity") or 0.5) * 2
	sensitivityMultiplier = sensitivityMultiplier * customSens

	local deltaX = delta.X * TOUCH_SENSITIVITY.X * sensitivityMultiplier
	local deltaY = delta.Y * TOUCH_SENSITIVITY.Y * sensitivityMultiplier

	-- Apply invert Y setting
	if shouldInvertY() then
		deltaY = -deltaY
	end

	-- Update camera angles (same as mouse, inverted for natural feel)
	cameraYaw = cameraYaw - degToRad(deltaX)
	cameraPitch = cameraPitch - degToRad(deltaY)

	-- Clamp pitch
	cameraPitch = math.clamp(cameraPitch, degToRad(MIN_PITCH), degToRad(MAX_PITCH))

	-- Update last position
	activeCameraTouches[touch] = currentPosition
end

-- Handle touch ended
local function onTouchEnded(touch: InputObject, _gameProcessed: boolean)
	-- Remove from tracking
	activeCameraTouches[touch] = nil
end

-- Connect touch events
local function connectTouchEvents()
	-- Disconnect existing connections
	for _, connection in touchConnections do
		connection:Disconnect()
	end
	touchConnections = {}

	-- Only connect if on touch device
	if not PlatformDetection.IsTouch() then
		return
	end

	table.insert(touchConnections, UserInputService.TouchStarted:Connect(onTouchStarted))
	table.insert(touchConnections, UserInputService.TouchMoved:Connect(onTouchMoved))
	table.insert(touchConnections, UserInputService.TouchEnded:Connect(onTouchEnded))
end

-- Disconnect touch events
local function disconnectTouchEvents()
	for _, connection in touchConnections do
		connection:Disconnect()
	end
	touchConnections = {}
	activeCameraTouches = {}
end

-- Update the camera position and orientation
local function UpdateCamera()
	local character = player.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Character base position (at eye level approximately)
	local characterPos = humanoidRootPart.Position + Vector3.new(0, 1.5, 0)

	-- Calculate camera position with offset
	-- Offset is: right, up, back relative to camera direction
	local offsetCFrame = CFrame.new(characterPos) * CFrame.Angles(0, cameraYaw, 0)
	local rightOffset = offsetCFrame.RightVector * CAMERA_OFFSET.X
	local upOffset = Vector3.new(0, CAMERA_OFFSET.Y, 0)
	local backOffset = (CFrame.Angles(0, cameraYaw, 0) * CFrame.Angles(cameraPitch, 0, 0)).LookVector * -CAMERA_OFFSET.Z

	local cameraPos = characterPos + rightOffset + upOffset + backOffset

	-- Raycast to prevent camera clipping through walls
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayDirection = cameraPos - characterPos
	local rayResult = workspace:Raycast(characterPos, rayDirection, rayParams)

	if rayResult then
		-- Move camera closer if it would clip through geometry
		cameraPos = rayResult.Position + rayResult.Normal * 0.5
	end

	-- Look at point is in front of the character at the camera's pitch angle
	local lookDirection = (CFrame.Angles(0, cameraYaw, 0) * CFrame.Angles(cameraPitch, 0, 0)).LookVector
	local lookAtPoint = characterPos + lookDirection * 100

	-- Set camera CFrame
	camera.CFrame = CFrame.lookAt(cameraPos, lookAtPoint)

	-- Rotate character to face camera direction (horizontal only)
	humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position) * CFrame.Angles(0, cameraYaw, 0)
end

-- Handle mouse movement for camera rotation
local function OnInputChanged(input: InputObject, _gameProcessed: boolean)
	if not isEnabled then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		-- Get effective sensitivity (includes player setting + Roblox native)
		local cameraSensitivity = getCameraSensitivity()
		-- Apply ADS sensitivity reduction when aiming down sights
		local sensitivityMultiplier = ADSState.GetSensitivityMultiplier()
		local deltaX = input.Delta.X * cameraSensitivity.X * sensitivityMultiplier
		local deltaY = input.Delta.Y * cameraSensitivity.Y * sensitivityMultiplier

		-- Apply invert Y setting
		if shouldInvertY() then
			deltaY = -deltaY
		end

		-- Update yaw (horizontal) - inverted so moving mouse right turns camera right
		cameraYaw = cameraYaw - degToRad(deltaX)

		-- Update pitch (vertical) - inverted so moving mouse up looks up
		cameraPitch = cameraPitch - degToRad(deltaY)

		-- Clamp pitch to prevent flipping
		cameraPitch = math.clamp(cameraPitch, degToRad(MIN_PITCH), degToRad(MAX_PITCH))
	end
end

-- Enable the camera controller
local function Enable()
	if isEnabled then
		return
	end

	isEnabled = true

	-- Initialize camera angles from current camera
	local currentLookVector = camera.CFrame.LookVector
	cameraYaw = math.atan2(-currentLookVector.X, -currentLookVector.Z)
	cameraPitch = math.asin(currentLookVector.Y)

	-- Platform-specific mouse/cursor setup
	local inputMethod = PlatformDetection.GetInputMethod()

	if inputMethod == "Touch" then
		-- on touch, don't lock cursor but do use scriptable camera
		-- touch camera control is handled via touch drag or gyroscope
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = false
	else
		-- gamepad or keyboard/mouse - lock cursor to center
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end

	-- Set camera to scriptable so we control it
	camera.CameraType = Enum.CameraType.Scriptable

	-- Connect to render loop (process gamepad input before camera update)
	renderConnection = RunService.RenderStepped:Connect(function()
		processGamepadCamera()
		UpdateCamera()
	end)

	-- Connect to input for mouse movement
	inputConnection = UserInputService.InputChanged:Connect(OnInputChanged)

	-- Connect touch events for mobile camera control
	connectTouchEvents()
end

-- Disable the camera controller
local function Disable()
	if not isEnabled then
		return
	end

	isEnabled = false

	-- Restore default mouse behavior
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	-- Show mouse cursor again
	UserInputService.MouseIconEnabled = true

	-- Restore default camera
	camera.CameraType = Enum.CameraType.Custom

	-- Disconnect connections
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end

	-- Disconnect touch events
	disconnectTouchEvents()
end

local function applyCombatState(enabled: boolean)
	if enabled then
		Enable()
	else
		Disable()
	end
end

MatchStateClient.OnCombatChanged(function(enabled)
	applyCombatState(enabled)
end)

applyCombatState(MatchStateClient.IsCombatEnabled())

-- Handle character respawning - reinitialize camera angles
player.CharacterAdded:Connect(function(_character)
	-- Wait for humanoid root part to exist
	local hrp = _character:WaitForChild("HumanoidRootPart", 5)
	if hrp and isEnabled then
		-- Small delay to let default camera settle
		task.wait(0.1)
		-- Reinitialize camera angles from new character facing direction
		cameraYaw = math.atan2(-hrp.CFrame.LookVector.X, -hrp.CFrame.LookVector.Z)
		cameraPitch = 0
	end
end)

-- Clean up on player leaving
Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		Disable()
	end
end)
