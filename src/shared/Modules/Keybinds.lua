--!strict
-- simple keybind registry with change notification

local Keybinds = {}

local changedEvent = Instance.new("BindableEvent")
Keybinds.Changed = changedEvent

local keybinds: { [string]: Enum.KeyCode | string } = {
	-- weapons
	weapon1 = "One",
	weapon2 = "Two",
	weapon3 = "Three",
	weapon4 = "Four",
	weapon5 = "Five",
	-- actions
	reload = "R",
	sprint = "LeftShift",
	crouch = "LeftControl",
	crouchToggle = "C",
	dropItem = "Z",
	-- menus
	quests = "J",
	settings = "Tab",
	achievements = "U",
	queue = "M",
	locker = "L",
}

local displayMap = {
	LeftShift = "L-Shift",
	RightShift = "R-Shift",
	LeftControl = "L-Ctrl",
	RightControl = "R-Ctrl",
	LeftAlt = "L-Alt",
	RightAlt = "R-Alt",
	LeftSuper = "L-Super",
	RightSuper = "R-Super",
}

function Keybinds.Get(action: string): Enum.KeyCode?
	local value = keybinds[action]
	if typeof(value) == "EnumItem" then
		return value :: Enum.KeyCode
	end
	if type(value) == "string" then
		return Enum.KeyCode[value]
	end
	return nil
end

function Keybinds.GetDisplay(action: string): string
	local value = keybinds[action]
	local keyName = ""
	if typeof(value) == "EnumItem" then
		keyName = (value :: Enum.KeyCode).Name
	elseif type(value) == "string" then
		keyName = value
	end
	if keyName == "" then
		return ""
	end
	return displayMap[keyName] or keyName
end

function Keybinds.Set(action: string, key: Enum.KeyCode | string)
	keybinds[action] = key
	changedEvent:Fire(action, key)
end

function Keybinds.SetAll(newBindings: { [string]: Enum.KeyCode | string })
	for action, key in newBindings do
		keybinds[action] = key
	end
	changedEvent:Fire("all")
end

-- get all keybinds as a table (for settings UI)
function Keybinds.GetAll(): { [string]: Enum.KeyCode | string }
	return table.clone(keybinds)
end

-- get human-readable action name
local actionDisplayNames: { [string]: string } = {
	weapon1 = "Weapon 1",
	weapon2 = "Weapon 2",
	weapon3 = "Weapon 3",
	weapon4 = "Weapon 4",
	weapon5 = "Weapon 5",
	reload = "Reload",
	sprint = "Sprint",
	crouch = "Crouch (Hold)",
	crouchToggle = "Crouch (Toggle)",
	dropItem = "Drop Item",
	quests = "Quests",
	settings = "Settings",
	achievements = "Achievements",
	queue = "Queue/Match",
	locker = "Locker",
}

function Keybinds.GetActionDisplayName(action: string): string
	return actionDisplayNames[action] or action
end

-- get keybind categories for organized UI
function Keybinds.GetCategories(): { { name: string, actions: { string } } }
	return {
		{ name = "Combat", actions = { "weapon1", "weapon2", "weapon3", "weapon4", "weapon5", "reload", "dropItem" } },
		{ name = "Movement", actions = { "sprint", "crouch", "crouchToggle" } },
		{ name = "Menus", actions = { "quests", "settings", "achievements", "queue", "locker" } },
	}
end

return Keybinds
