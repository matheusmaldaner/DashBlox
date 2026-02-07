--!strict
-- input manager - central input abstraction layer using ContextActionService
-- provides unified input handling across all platforms

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PlatformDetection = require(Modules.PlatformDetection)
local InputBindings = require(Modules.InputBindings)

local InputManager = {}

-- types
export type ActionCallback = (
	actionName: string,
	inputState: Enum.UserInputState,
	inputObject: InputObject
) -> Enum.ContextActionResult?

export type BoundAction = {
	name: string,
	callback: ActionCallback,
	priority: number,
	createTouchButton: boolean,
	inputs: { Enum.KeyCode | Enum.UserInputType },
	isActive: boolean,
}

-- state
local boundActions: { [string]: BoundAction } = {}
local actionCallbacks: { [string]: ActionCallback } = {}
local contextGroups: { [string]: { string } } = {} -- group name -> action names
local activeContexts: { [string]: boolean } = {}
local touchButtonsEnabled = true

-- event for input method changes
local inputMethodChangedEvent = Instance.new("BindableEvent")
InputManager.InputMethodChanged = inputMethodChangedEvent.Event

--------------------------------------------------
-- Internal Helpers
--------------------------------------------------

-- get inputs for current platform
local function getInputsForCurrentPlatform(actionName: string): { Enum.KeyCode | Enum.UserInputType }
	local binding = InputBindings.GetBinding(actionName)
	if not binding then
		return {}
	end

	local inputMethod = PlatformDetection.GetInputMethod()
	local inputs: { Enum.KeyCode | Enum.UserInputType } = {}

	if inputMethod == "Gamepad" then
		if binding.Gamepad then
			for _, input in binding.Gamepad do
				table.insert(inputs, input)
			end
		end
	else
		-- KeyboardMouse or Touch (touch uses keyboard bindings for testing/fallback)
		if binding.KeyboardMouse then
			for _, input in binding.KeyboardMouse do
				table.insert(inputs, input)
			end
		end
	end

	return inputs
end

-- create the internal callback wrapper
local function createInternalCallback(actionName: string): (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
	return function(name: string, state: Enum.UserInputState, inputObject: InputObject): Enum.ContextActionResult
		local callback = actionCallbacks[actionName]
		if callback then
			local result = callback(name, state, inputObject)
			return result or Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Pass
	end
end

-- rebind action with current platform inputs
local function rebindAction(actionName: string)
	local action = boundActions[actionName]
	if not action or not action.isActive then
		return
	end

	-- unbind first
	ContextActionService:UnbindAction(actionName)

	-- get inputs for current platform
	local inputs = getInputsForCurrentPlatform(actionName)
	if #inputs == 0 then
		return
	end

	-- rebind with new inputs
	local createTouch = action.createTouchButton and touchButtonsEnabled and PlatformDetection.IsTouch()

	ContextActionService:BindActionAtPriority(
		actionName,
		createInternalCallback(actionName),
		createTouch,
		action.priority,
		table.unpack(inputs)
	)

	-- update stored inputs
	action.inputs = inputs
end

-- rebind all actions (called when input method changes)
local function rebindAllActions()
	for actionName, action in boundActions do
		if action.isActive then
			rebindAction(actionName)
		end
	end
end

--------------------------------------------------
-- Platform Change Handling
--------------------------------------------------

PlatformDetection.OnInputMethodChanged(function(inputMethod, platform)
	-- rebind all actions for new input method
	rebindAllActions()

	-- fire event for other systems to respond
	inputMethodChangedEvent:Fire(inputMethod, platform)
end)

--------------------------------------------------
-- Public API
--------------------------------------------------

-- bind an action with automatic platform detection
function InputManager.BindAction(
	actionName: string,
	callback: ActionCallback,
	createTouchButton: boolean?,
	customPriority: number?
)
	-- get priority from bindings or use custom
	local priority = customPriority or InputBindings.GetPriority(actionName)

	-- store callback
	actionCallbacks[actionName] = callback

	-- get inputs for current platform
	local inputs = getInputsForCurrentPlatform(actionName)

	-- create bound action record
	boundActions[actionName] = {
		name = actionName,
		callback = callback,
		priority = priority,
		createTouchButton = createTouchButton or false,
		inputs = inputs,
		isActive = true,
	}

	-- only bind if we have inputs
	if #inputs > 0 then
		local createTouch = (createTouchButton or false) and touchButtonsEnabled and PlatformDetection.IsTouch()

		ContextActionService:BindActionAtPriority(
			actionName,
			createInternalCallback(actionName),
			createTouch,
			priority,
			table.unpack(inputs)
		)
	end
end

-- bind action with explicit inputs (bypasses platform detection)
function InputManager.BindActionWithInputs(
	actionName: string,
	callback: ActionCallback,
	createTouchButton: boolean?,
	priority: number?,
	...: Enum.KeyCode | Enum.UserInputType
)
	local inputs = { ... }

	-- store callback
	actionCallbacks[actionName] = callback

	-- create bound action record
	boundActions[actionName] = {
		name = actionName,
		callback = callback,
		priority = priority or 500,
		createTouchButton = createTouchButton or false,
		inputs = inputs,
		isActive = true,
	}

	local createTouch = (createTouchButton or false) and touchButtonsEnabled and PlatformDetection.IsTouch()

	ContextActionService:BindActionAtPriority(actionName, createInternalCallback(actionName), createTouch, priority or 500, ...)
end

-- unbind an action
function InputManager.UnbindAction(actionName: string)
	ContextActionService:UnbindAction(actionName)
	actionCallbacks[actionName] = nil
	boundActions[actionName] = nil
end

-- temporarily disable an action (keeps binding but ignores input)
function InputManager.DisableAction(actionName: string)
	local action = boundActions[actionName]
	if action then
		action.isActive = false
		ContextActionService:UnbindAction(actionName)
	end
end

-- re-enable a disabled action
function InputManager.EnableAction(actionName: string)
	local action = boundActions[actionName]
	if action and not action.isActive then
		action.isActive = true
		rebindAction(actionName)
	end
end

-- check if action is bound
function InputManager.IsActionBound(actionName: string): boolean
	return boundActions[actionName] ~= nil
end

-- check if action is active
function InputManager.IsActionActive(actionName: string): boolean
	local action = boundActions[actionName]
	return action ~= nil and action.isActive
end

--------------------------------------------------
-- Context Groups
--------------------------------------------------

-- create a context group (e.g., "BuildMode", "CombatMode")
function InputManager.CreateContext(contextName: string, actionNames: { string })
	contextGroups[contextName] = actionNames
end

-- enable a context (enables all actions in the group)
function InputManager.EnableContext(contextName: string)
	local actions = contextGroups[contextName]
	if not actions then
		return
	end

	activeContexts[contextName] = true

	for _, actionName in actions do
		InputManager.EnableAction(actionName)
	end
end

-- disable a context (disables all actions in the group)
function InputManager.DisableContext(contextName: string)
	local actions = contextGroups[contextName]
	if not actions then
		return
	end

	activeContexts[contextName] = false

	for _, actionName in actions do
		InputManager.DisableAction(actionName)
	end
end

-- check if context is active
function InputManager.IsContextActive(contextName: string): boolean
	return activeContexts[contextName] or false
end

--------------------------------------------------
-- Platform Queries
--------------------------------------------------

-- get current platform
function InputManager.GetPlatform(): PlatformDetection.Platform
	return PlatformDetection.GetPlatform()
end

-- get current input method
function InputManager.GetInputMethod(): PlatformDetection.InputMethod
	return PlatformDetection.GetInputMethod()
end

-- check if using keyboard/mouse
function InputManager.IsKeyboardMouse(): boolean
	return PlatformDetection.IsKeyboardMouse()
end

-- check if using gamepad
function InputManager.IsGamepad(): boolean
	return PlatformDetection.IsGamepad()
end

-- check if using touch
function InputManager.IsTouch(): boolean
	return PlatformDetection.IsTouch()
end

-- check if on console
function InputManager.IsConsole(): boolean
	return PlatformDetection.IsConsole()
end

-- check if should enable aim assist
function InputManager.ShouldEnableAimAssist(): boolean
	return PlatformDetection.ShouldEnableAimAssist()
end

--------------------------------------------------
-- Touch Button Management
--------------------------------------------------

-- enable/disable touch buttons globally
function InputManager.SetTouchButtonsEnabled(enabled: boolean)
	touchButtonsEnabled = enabled
	rebindAllActions()
end

-- get touch button position (for custom positioning)
function InputManager.SetTouchButtonPosition(actionName: string, position: UDim2)
	ContextActionService:SetPosition(actionName, position)
end

-- set touch button title
function InputManager.SetTouchButtonTitle(actionName: string, title: string)
	ContextActionService:SetTitle(actionName, title)
end

-- set touch button image
function InputManager.SetTouchButtonImage(actionName: string, imageAssetId: string)
	ContextActionService:SetImage(actionName, imageAssetId)
end

--------------------------------------------------
-- Gamepad Helpers
--------------------------------------------------

-- get connected gamepads
function InputManager.GetConnectedGamepads(): { Enum.UserInputType }
	return UserInputService:GetConnectedGamepads()
end

-- check if gamepad is connected
function InputManager.IsGamepadConnected(): boolean
	return #UserInputService:GetConnectedGamepads() > 0
end

-- get gamepad state
function InputManager.GetGamepadState(gamepad: Enum.UserInputType?): { InputObject }
	local pad = gamepad or Enum.UserInputType.Gamepad1
	return UserInputService:GetGamepadState(pad)
end

-- check if a gamepad button is pressed
function InputManager.IsGamepadButtonDown(keyCode: Enum.KeyCode, gamepad: Enum.UserInputType?): boolean
	local pad = gamepad or Enum.UserInputType.Gamepad1
	return UserInputService:IsGamepadButtonDown(pad, keyCode)
end

--------------------------------------------------
-- Utility
--------------------------------------------------

-- get display string for an action's current binding
function InputManager.GetBindingDisplayString(actionName: string): string
	local binding = InputBindings.GetBinding(actionName)
	if not binding then
		return ""
	end

	local inputMethod = PlatformDetection.GetInputMethod()
	local platform = PlatformDetection.GetPlatform()

	if inputMethod == "KeyboardMouse" then
		if binding.KeyboardMouse and #binding.KeyboardMouse > 0 then
			local input = binding.KeyboardMouse[1]
			if typeof(input) == "EnumItem" then
				if input.EnumType == Enum.KeyCode then
					return (input :: Enum.KeyCode).Name
				elseif input.EnumType == Enum.UserInputType then
					local inputType = input :: Enum.UserInputType
					if inputType == Enum.UserInputType.MouseButton1 then
						return "LMB"
					elseif inputType == Enum.UserInputType.MouseButton2 then
						return "RMB"
					elseif inputType == Enum.UserInputType.MouseButton3 then
						return "MMB"
					end
				end
			end
		end
	elseif inputMethod == "Gamepad" then
		if binding.Gamepad and #binding.Gamepad > 0 then
			local consolePlatform: "Xbox" | "PlayStation" = if platform == "PlayStation" then "PlayStation" else "Xbox"
			return InputBindings.GetGamepadButtonName(binding.Gamepad[1], consolePlatform)
		end
	elseif inputMethod == "Touch" then
		if binding.Touch then
			return InputBindings.GetDisplayName(actionName)
		end
	end

	return ""
end

-- unbind all actions
function InputManager.UnbindAllActions()
	for actionName in boundActions do
		ContextActionService:UnbindAction(actionName)
	end
	boundActions = {}
	actionCallbacks = {}
end

-- force refresh bindings (useful after settings change)
function InputManager.RefreshBindings()
	rebindAllActions()
end

return InputManager
