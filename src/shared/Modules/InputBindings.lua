--!strict
-- input bindings - defines action bindings per platform
-- maps action names to input codes for each input method

local InputBindings = {}

-- types
export type InputMethodKey = "KeyboardMouse" | "Gamepad" | "Touch"

export type Binding = {
	KeyboardMouse: { Enum.KeyCode | Enum.UserInputType }?,
	Gamepad: { Enum.KeyCode }?,
	Touch: string?, -- "TouchButton", "TouchHold", "AutoSprint", or nil
}

export type ActionCategory = "Building" | "Combat" | "Movement" | "Weapons" | "UI" | "Edit"

-- all action bindings
local Bindings: { [string]: Binding } = {
	--------------------------------------------------
	-- Building Actions
	--------------------------------------------------
	BuildWall = {
		KeyboardMouse = { Enum.KeyCode.Q },
		Gamepad = { Enum.KeyCode.ButtonY }, -- Y on Xbox, Triangle on PS
		Touch = "TouchButton",
	},
	BuildFloor = {
		KeyboardMouse = { Enum.KeyCode.X },
		Gamepad = { Enum.KeyCode.ButtonX }, -- X on Xbox, Square on PS
		Touch = "TouchButton",
	},
	BuildRamp = {
		KeyboardMouse = { Enum.KeyCode.E },
		Gamepad = { Enum.KeyCode.ButtonB }, -- B on Xbox, Circle on PS
		Touch = "TouchButton",
	},
	BuildPyramid = {
		KeyboardMouse = { Enum.KeyCode.V },
		Gamepad = { Enum.KeyCode.ButtonA }, -- A on Xbox, Cross on PS
		Touch = "TouchButton",
	},
	PlaceBuilding = {
		KeyboardMouse = { Enum.UserInputType.MouseButton1 },
		Gamepad = { Enum.KeyCode.ButtonR2 }, -- Right trigger
		Touch = "TouchButton",
	},
	RotatePiece = {
		KeyboardMouse = { Enum.KeyCode.R },
		Gamepad = { Enum.KeyCode.ButtonR3 }, -- Right stick click
		Touch = nil, -- handled by swipe gesture
	},
	CycleMaterial = {
		KeyboardMouse = { Enum.UserInputType.MouseButton2 },
		Gamepad = { Enum.KeyCode.DPadRight },
		Touch = "TouchButton",
	},
	RepairBuilding = {
		KeyboardMouse = { Enum.KeyCode.F },
		Gamepad = { Enum.KeyCode.DPadDown },
		Touch = "TouchButton",
	},

	--------------------------------------------------
	-- Edit Actions
	--------------------------------------------------
	EditMode = {
		KeyboardMouse = { Enum.KeyCode.G },
		Gamepad = { Enum.KeyCode.ButtonR1 }, -- RB on Xbox, R1 on PS
		Touch = "TouchHold",
	},
	ConfirmEdit = {
		KeyboardMouse = { Enum.UserInputType.MouseButton1 },
		Gamepad = { Enum.KeyCode.ButtonR2 },
		Touch = "TouchButton",
	},
	ResetEdit = {
		KeyboardMouse = { Enum.UserInputType.MouseButton2 },
		Gamepad = { Enum.KeyCode.ButtonL2 },
		Touch = "TouchButton",
	},

	--------------------------------------------------
	-- Combat Actions
	--------------------------------------------------
	Fire = {
		KeyboardMouse = { Enum.UserInputType.MouseButton1 },
		Gamepad = { Enum.KeyCode.ButtonR2 }, -- Right trigger
		Touch = "TouchButton",
	},
	ADS = {
		KeyboardMouse = { Enum.UserInputType.MouseButton2 },
		Gamepad = { Enum.KeyCode.ButtonL2 }, -- Left trigger
		Touch = "TouchHold",
	},
	Reload = {
		KeyboardMouse = { Enum.KeyCode.R },
		Gamepad = { Enum.KeyCode.ButtonX }, -- X on Xbox, Square on PS
		Touch = "TouchButton",
	},

	--------------------------------------------------
	-- Mode Switching
	--------------------------------------------------
	ToggleMode = {
		KeyboardMouse = nil, -- uses Q/X/E/V directly
		Gamepad = { Enum.KeyCode.ButtonL1 }, -- LB on Xbox, L1 on PS
		Touch = "TouchButton",
	},
	ExitBuildMode = {
		KeyboardMouse = nil, -- press same piece key to exit
		Gamepad = { Enum.KeyCode.ButtonL1 }, -- LB again to exit
		Touch = "TouchButton",
	},

	--------------------------------------------------
	-- Weapon/Tool Slots
	--------------------------------------------------
	Pickaxe = {
		KeyboardMouse = { Enum.KeyCode.One },
		Gamepad = { Enum.KeyCode.DPadUp },
		Touch = "TouchButton",
	},
	PickaxeSwing = {
		KeyboardMouse = { Enum.UserInputType.MouseButton1 },
		Gamepad = { Enum.KeyCode.ButtonR2 }, -- Right trigger
		Touch = "TouchButton",
	},
	Weapon1 = {
		KeyboardMouse = { Enum.KeyCode.Two },
		Gamepad = { Enum.KeyCode.DPadLeft },
		Touch = "TouchButton",
	},
	Weapon2 = {
		KeyboardMouse = { Enum.KeyCode.Three },
		Gamepad = { Enum.KeyCode.DPadRight },
		Touch = "TouchButton",
	},
	Weapon3 = {
		KeyboardMouse = { Enum.KeyCode.Four },
		Gamepad = { Enum.KeyCode.DPadDown },
		Touch = "TouchButton",
	},
	Weapon4 = {
		KeyboardMouse = { Enum.KeyCode.Five },
		Gamepad = nil, -- use LB/RB to cycle
		Touch = "TouchButton",
	},
	NextWeapon = {
		KeyboardMouse = nil, -- mouse wheel
		Gamepad = { Enum.KeyCode.ButtonR1 },
		Touch = nil,
	},
	PrevWeapon = {
		KeyboardMouse = nil, -- mouse wheel
		Gamepad = { Enum.KeyCode.ButtonL1 },
		Touch = nil,
	},

	--------------------------------------------------
	-- Movement
	--------------------------------------------------
	Sprint = {
		KeyboardMouse = { Enum.KeyCode.LeftShift },
		Gamepad = { Enum.KeyCode.ButtonL3 }, -- Left stick click
		Touch = "AutoSprint", -- auto-sprint when moving forward
	},
	Crouch = {
		KeyboardMouse = { Enum.KeyCode.LeftControl },
		Gamepad = { Enum.KeyCode.ButtonR3 }, -- Right stick click
		Touch = "TouchButton",
	},
	CrouchToggle = {
		KeyboardMouse = { Enum.KeyCode.C },
		Gamepad = nil, -- use R3 as toggle on gamepad
		Touch = "TouchButton",
	},
	Jump = {
		KeyboardMouse = { Enum.KeyCode.Space },
		Gamepad = { Enum.KeyCode.ButtonA },
		Touch = "TouchButton",
	},

	--------------------------------------------------
	-- UI / Menus
	--------------------------------------------------
	OpenSettings = {
		KeyboardMouse = { Enum.KeyCode.Tab },
		Gamepad = { Enum.KeyCode.ButtonStart },
		Touch = "TouchButton",
	},
	OpenQuests = {
		KeyboardMouse = { Enum.KeyCode.J },
		Gamepad = { Enum.KeyCode.ButtonSelect },
		Touch = "TouchButton",
	},
	OpenInventory = {
		KeyboardMouse = { Enum.KeyCode.I },
		Gamepad = { Enum.KeyCode.ButtonSelect },
		Touch = "TouchButton",
	},
	Scoreboard = {
		KeyboardMouse = { Enum.KeyCode.Tab },
		Gamepad = { Enum.KeyCode.ButtonSelect },
		Touch = nil, -- swipe up gesture
	},

	--------------------------------------------------
	-- Pickaxe Actions
	--------------------------------------------------
	SwingPickaxe = {
		KeyboardMouse = { Enum.UserInputType.MouseButton1 },
		Gamepad = { Enum.KeyCode.ButtonR2 },
		Touch = "TouchButton",
	},
}

-- action categories for organization
local ActionCategories: { [string]: ActionCategory } = {
	BuildWall = "Building",
	BuildFloor = "Building",
	BuildRamp = "Building",
	BuildPyramid = "Building",
	PlaceBuilding = "Building",
	RotatePiece = "Building",
	CycleMaterial = "Building",
	RepairBuilding = "Building",

	EditMode = "Edit",
	ConfirmEdit = "Edit",
	ResetEdit = "Edit",

	Fire = "Combat",
	ADS = "Combat",
	Reload = "Combat",
	SwingPickaxe = "Combat",

	ToggleMode = "Weapons",
	ExitBuildMode = "Weapons",
	Pickaxe = "Weapons",
	Weapon1 = "Weapons",
	Weapon2 = "Weapons",
	Weapon3 = "Weapons",
	Weapon4 = "Weapons",
	NextWeapon = "Weapons",
	PrevWeapon = "Weapons",

	Sprint = "Movement",
	Crouch = "Movement",
	CrouchToggle = "Movement",
	Jump = "Movement",

	OpenSettings = "UI",
	OpenQuests = "UI",
	OpenInventory = "UI",
	Scoreboard = "UI",
}

-- priority levels for actions (higher = more priority)
local ActionPriorities: { [string]: number } = {
	-- Combat actions have highest priority
	Fire = 1000,
	ADS = 1000,
	SwingPickaxe = 1000,

	-- Building actions
	PlaceBuilding = 900,
	BuildWall = 850,
	BuildFloor = 850,
	BuildRamp = 850,
	BuildPyramid = 850,
	RotatePiece = 800,

	-- Edit actions
	EditMode = 750,
	ConfirmEdit = 750,
	ResetEdit = 750,

	-- Weapon switching
	Pickaxe = 500,
	Weapon1 = 500,
	Weapon2 = 500,
	Weapon3 = 500,
	Weapon4 = 500,
	ToggleMode = 500,

	-- Movement
	Sprint = 400,
	Crouch = 400,
	Jump = 400,

	-- UI (lowest priority - don't interfere with gameplay)
	OpenSettings = 100,
	OpenQuests = 100,
	Reload = 600,
}

--------------------------------------------------
-- Display Names (for UI)
--------------------------------------------------

local ActionDisplayNames: { [string]: string } = {
	BuildWall = "Wall",
	BuildFloor = "Floor",
	BuildRamp = "Ramp",
	BuildPyramid = "Pyramid",
	PlaceBuilding = "Place",
	RotatePiece = "Rotate",
	CycleMaterial = "Material",
	RepairBuilding = "Repair",

	EditMode = "Edit Mode",
	ConfirmEdit = "Confirm Edit",
	ResetEdit = "Reset Edit",

	Fire = "Fire",
	ADS = "Aim",
	Reload = "Reload",

	ToggleMode = "Switch Mode",
	ExitBuildMode = "Exit Build",
	Pickaxe = "Pickaxe",
	Weapon1 = "Weapon 1",
	Weapon2 = "Weapon 2",
	Weapon3 = "Weapon 3",
	Weapon4 = "Weapon 4",

	Sprint = "Sprint",
	Crouch = "Crouch",
	CrouchToggle = "Crouch (Toggle)",
	Jump = "Jump",

	OpenSettings = "Settings",
	OpenQuests = "Quests",
	SwingPickaxe = "Swing",
}

-- gamepad button display names
local GamepadButtonNames: { [Enum.KeyCode]: { Xbox: string, PlayStation: string } } = {
	[Enum.KeyCode.ButtonA] = { Xbox = "A", PlayStation = "X" },
	[Enum.KeyCode.ButtonB] = { Xbox = "B", PlayStation = "O" },
	[Enum.KeyCode.ButtonX] = { Xbox = "X", PlayStation = "▢" },
	[Enum.KeyCode.ButtonY] = { Xbox = "Y", PlayStation = "△" },
	[Enum.KeyCode.ButtonL1] = { Xbox = "LB", PlayStation = "L1" },
	[Enum.KeyCode.ButtonR1] = { Xbox = "RB", PlayStation = "R1" },
	[Enum.KeyCode.ButtonL2] = { Xbox = "LT", PlayStation = "L2" },
	[Enum.KeyCode.ButtonR2] = { Xbox = "RT", PlayStation = "R2" },
	[Enum.KeyCode.ButtonL3] = { Xbox = "LS", PlayStation = "L3" },
	[Enum.KeyCode.ButtonR3] = { Xbox = "RS", PlayStation = "R3" },
	[Enum.KeyCode.ButtonStart] = { Xbox = "☰", PlayStation = "OPTIONS" },
	[Enum.KeyCode.ButtonSelect] = { Xbox = "⧉", PlayStation = "SHARE" },
	[Enum.KeyCode.DPadUp] = { Xbox = "D↑", PlayStation = "D↑" },
	[Enum.KeyCode.DPadDown] = { Xbox = "D↓", PlayStation = "D↓" },
	[Enum.KeyCode.DPadLeft] = { Xbox = "D←", PlayStation = "D←" },
	[Enum.KeyCode.DPadRight] = { Xbox = "D→", PlayStation = "D→" },
}

--------------------------------------------------
-- Public API
--------------------------------------------------

-- get binding for an action
function InputBindings.GetBinding(actionName: string): Binding?
	return Bindings[actionName]
end

-- get all bindings
function InputBindings.GetAllBindings(): { [string]: Binding }
	return Bindings
end

-- get binding for specific input method
function InputBindings.GetBindingForMethod(
	actionName: string,
	inputMethod: InputMethodKey
): { Enum.KeyCode | Enum.UserInputType }? | string?
	local binding = Bindings[actionName]
	if not binding then
		return nil
	end

	if inputMethod == "KeyboardMouse" then
		return binding.KeyboardMouse
	elseif inputMethod == "Gamepad" then
		return binding.Gamepad
	elseif inputMethod == "Touch" then
		return binding.Touch
	end

	return nil
end

-- get action category
function InputBindings.GetCategory(actionName: string): ActionCategory?
	return ActionCategories[actionName]
end

-- get actions by category
function InputBindings.GetActionsByCategory(category: ActionCategory): { string }
	local actions = {}
	for actionName, actionCategory in ActionCategories do
		if actionCategory == category then
			table.insert(actions, actionName)
		end
	end
	return actions
end

-- get action priority
function InputBindings.GetPriority(actionName: string): number
	return ActionPriorities[actionName] or 500
end

-- get display name for action
function InputBindings.GetDisplayName(actionName: string): string
	return ActionDisplayNames[actionName] or actionName
end

-- get display name for gamepad button
function InputBindings.GetGamepadButtonName(keyCode: Enum.KeyCode, platform: "Xbox" | "PlayStation"): string
	local names = GamepadButtonNames[keyCode]
	if names then
		return names[platform]
	end
	return keyCode.Name
end

-- check if action has gamepad binding
function InputBindings.HasGamepadBinding(actionName: string): boolean
	local binding = Bindings[actionName]
	return binding ~= nil and binding.Gamepad ~= nil
end

-- check if action has touch binding
function InputBindings.HasTouchBinding(actionName: string): boolean
	local binding = Bindings[actionName]
	return binding ~= nil and binding.Touch ~= nil
end

-- get all action names
function InputBindings.GetAllActionNames(): { string }
	local names = {}
	for name in Bindings do
		table.insert(names, name)
	end
	return names
end

-- check if touch binding is a button type
function InputBindings.IsTouchButton(actionName: string): boolean
	local binding = Bindings[actionName]
	if not binding or not binding.Touch then
		return false
	end
	return binding.Touch == "TouchButton"
end

-- check if touch binding is a hold type
function InputBindings.IsTouchHold(actionName: string): boolean
	local binding = Bindings[actionName]
	if not binding or not binding.Touch then
		return false
	end
	return binding.Touch == "TouchHold"
end

-- check if touch binding is auto-sprint
function InputBindings.IsAutoSprint(actionName: string): boolean
	local binding = Bindings[actionName]
	if not binding or not binding.Touch then
		return false
	end
	return binding.Touch == "AutoSprint"
end

return InputBindings
