--!strict
-- platform detection - detects and tracks input device/platform changes

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local PlatformDetection = {}

-- types
export type Platform = "PC" | "Xbox" | "PlayStation" | "Touch"
export type InputMethod = "KeyboardMouse" | "Gamepad" | "Touch"

-- state
local currentPlatform: Platform = "PC"
local currentInputMethod: InputMethod = "KeyboardMouse"
local inputMethodChangedCallbacks: { (InputMethod, Platform) -> () } = {}

-- mapping of input types to input methods
local INPUT_TYPE_TO_METHOD: { [Enum.UserInputType]: InputMethod } = {
	[Enum.UserInputType.Keyboard] = "KeyboardMouse",
	[Enum.UserInputType.MouseButton1] = "KeyboardMouse",
	[Enum.UserInputType.MouseButton2] = "KeyboardMouse",
	[Enum.UserInputType.MouseButton3] = "KeyboardMouse",
	[Enum.UserInputType.MouseMovement] = "KeyboardMouse",
	[Enum.UserInputType.MouseWheel] = "KeyboardMouse",
	[Enum.UserInputType.Gamepad1] = "Gamepad",
	[Enum.UserInputType.Gamepad2] = "Gamepad",
	[Enum.UserInputType.Gamepad3] = "Gamepad",
	[Enum.UserInputType.Gamepad4] = "Gamepad",
	[Enum.UserInputType.Touch] = "Touch",
}

-- determine the console type based on button names
-- Xbox uses A/B/X/Y, PlayStation uses Cross/Circle/Square/Triangle
local function detectConsoleType(): "Xbox" | "PlayStation"
	-- use ten foot interface detection as primary method
	-- ten foot interface is enabled on consoles
	local isTenFoot = GuiService:IsTenFootInterface()

	if not isTenFoot then
		-- on PC with controller, default to Xbox style since it's more common
		return "Xbox"
	end

	-- on actual consoles, Roblox runs on Xbox and PlayStation
	-- we can try to detect based on button availability
	-- unfortunately there's no direct API, so we default to Xbox
	-- PlayStation-specific detection would require platform-specific APIs

	-- for now, check if we're in a console environment
	-- the actual console type detection is limited by Roblox APIs
	return "Xbox"
end

-- detect platform based on current input and device capabilities
local function detectPlatform(): Platform
	local touchEnabled = UserInputService.TouchEnabled
	local gamepadEnabled = UserInputService.GamepadEnabled
	local keyboardEnabled = UserInputService.KeyboardEnabled
	local isTenFoot = GuiService:IsTenFootInterface()

	-- ten foot interface indicates console (Xbox/PlayStation)
	if isTenFoot then
		return detectConsoleType()
	end

	-- if touch is the primary input and no keyboard (mobile device)
	if touchEnabled and not keyboardEnabled then
		return "Touch"
	end

	-- if gamepad is connected and being used
	if gamepadEnabled and currentInputMethod == "Gamepad" then
		return detectConsoleType()
	end

	-- default to PC
	return "PC"
end

-- get input method from UserInputType
local function getInputMethodFromType(inputType: Enum.UserInputType): InputMethod?
	return INPUT_TYPE_TO_METHOD[inputType]
end

-- update current input method based on last input
local function updateInputMethod(inputType: Enum.UserInputType)
	local newMethod = getInputMethodFromType(inputType)
	if not newMethod then
		return
	end

	local previousMethod = currentInputMethod
	local previousPlatform = currentPlatform

	currentInputMethod = newMethod
	currentPlatform = detectPlatform()

	-- notify if changed
	if previousMethod ~= currentInputMethod or previousPlatform ~= currentPlatform then
		for _, callback in inputMethodChangedCallbacks do
			task.spawn(callback, currentInputMethod, currentPlatform)
		end
	end
end

-- initialize detection
local function initialize()
	-- set initial state based on device capabilities
	local touchEnabled = UserInputService.TouchEnabled
	local keyboardEnabled = UserInputService.KeyboardEnabled
	local isTenFoot = GuiService:IsTenFootInterface()

	if isTenFoot then
		currentInputMethod = "Gamepad"
		currentPlatform = detectConsoleType()
	elseif touchEnabled and not keyboardEnabled then
		currentInputMethod = "Touch"
		currentPlatform = "Touch"
	else
		-- PC (with or without gamepad connected) - use keyboard/mouse as default
		currentInputMethod = "KeyboardMouse"
		currentPlatform = "PC"
	end

	-- listen for input type changes
	UserInputService.LastInputTypeChanged:Connect(function(lastInputType)
		updateInputMethod(lastInputType)
	end)
end

--------------------------------------------------
-- Public API
--------------------------------------------------

-- get current platform
function PlatformDetection.GetPlatform(): Platform
	return currentPlatform
end

-- get current input method
function PlatformDetection.GetInputMethod(): InputMethod
	return currentInputMethod
end

-- check if using keyboard/mouse
function PlatformDetection.IsKeyboardMouse(): boolean
	return currentInputMethod == "KeyboardMouse"
end

-- check if using gamepad
function PlatformDetection.IsGamepad(): boolean
	return currentInputMethod == "Gamepad"
end

-- check if using touch
function PlatformDetection.IsTouch(): boolean
	return currentInputMethod == "Touch"
end

-- check if on console (Xbox or PlayStation)
function PlatformDetection.IsConsole(): boolean
	return currentPlatform == "Xbox" or currentPlatform == "PlayStation"
end

-- check if on mobile (Touch platform)
function PlatformDetection.IsMobile(): boolean
	return currentPlatform == "Touch"
end

-- check if touch controls should be shown
function PlatformDetection.ShouldShowTouchControls(): boolean
	return currentInputMethod == "Touch"
end

-- check if aim assist should be enabled (gamepad or touch only)
function PlatformDetection.ShouldEnableAimAssist(): boolean
	return currentInputMethod == "Gamepad" or currentInputMethod == "Touch"
end

-- register callback for input method changes
function PlatformDetection.OnInputMethodChanged(callback: (InputMethod, Platform) -> ())
	table.insert(inputMethodChangedCallbacks, callback)
end

-- get device capabilities
function PlatformDetection.GetCapabilities(): {
	touchEnabled: boolean,
	gamepadEnabled: boolean,
	keyboardEnabled: boolean,
	accelerometerEnabled: boolean,
	gyroscopeEnabled: boolean,
	isTenFootInterface: boolean,
}
	return {
		touchEnabled = UserInputService.TouchEnabled,
		gamepadEnabled = UserInputService.GamepadEnabled,
		keyboardEnabled = UserInputService.KeyboardEnabled,
		accelerometerEnabled = UserInputService.AccelerometerEnabled,
		gyroscopeEnabled = UserInputService.GyroscopeEnabled,
		isTenFootInterface = GuiService:IsTenFootInterface(),
	}
end

-- force update (useful after settings change)
function PlatformDetection.ForceUpdate()
	local lastInputType = UserInputService:GetLastInputType()
	updateInputMethod(lastInputType)
end

-- initialize on module load
initialize()

return PlatformDetection
