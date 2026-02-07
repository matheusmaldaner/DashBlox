--!strict
-- shared settings module - stores game settings that can be accessed by any script
-- settings are persisted to DataStore via PlayerDataService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Settings = {}

-- event for settings changes
local SettingsChanged = Instance.new("BindableEvent")
Settings.Changed = SettingsChanged.Event

-- menu state (so other scripts can check if menu is open)
local isMenuOpen = false

-- track if settings have been loaded from server
local settingsLoaded = false

-- debounce for saving (don't spam server)
local saveDebounce = false
local SAVE_DEBOUNCE_TIME = 1.0 -- seconds

-- settings data (defaults)
-- note: master volume is handled by Roblox's ESC menu (UserGameSettings.MasterVolume)
-- we only store category multipliers that stack on top of the player's system volume
local settings = {
	-- audio (category multipliers, not absolute volumes)
	musicVolume = 0.7,
	sfxVolume = 1.0,

	-- video
	showFPS = false,
	reducedEffects = false,
	cameraShake = true,
	hudScale = 1.0,
	colorblindMode = "Default", -- Default, Deuteranopia, Protanopia, Tritanopia, HighContrast
	colorblindIntensity = 1.0,

	-- crosshair
	crosshairColor = Color3.new(1, 1, 1), -- white
	crosshairSize = 10, -- bar length
	crosshairThickness = 2,
	crosshairGap = 4,
	crosshairDotEnabled = true,
	crosshairDotSize = 4,
	crosshairOutline = true,

	-- gameplay
	sensitivity = 0.5,
	invertY = false,
	autoSprint = false,
	editOnRelease = true,
	showCrosshair = true,
	showDamageNumbers = true,
	showKillFeed = true,

	-- accessibility
	accessibilityUIScale = "Normal",
	accessibilityFontSize = "Normal",
	hitMarkerShape = "Default",
	reducedMotion = false,
	flashingEffects = true,
	highContrastText = false,
}

function Settings.Get(name: string): any
	return (settings :: any)[name]
end

-- internal function to save settings to server (client only)
local function saveToServer()
	if not RunService:IsClient() then
		return
	end
	if saveDebounce then
		return
	end

	saveDebounce = true
	task.delay(SAVE_DEBOUNCE_TIME, function()
		saveDebounce = false

		-- prepare settings for DataStore (convert Color3 to RGB values)
		local saveData = {}
		for key, value in settings do
			if typeof(value) == "Color3" then
				-- store Color3 as separate R/G/B values
				saveData[key .. "R"] = value.R
				saveData[key .. "G"] = value.G
				saveData[key .. "B"] = value.B
			else
				saveData[key] = value
			end
		end

		-- get RemoteService and fire save event
		local Modules = ReplicatedStorage:FindFirstChild("Modules")
		if Modules then
			local RemoteService = require(Modules:WaitForChild("RemoteService"))
			local SaveSettings = RemoteService.GetRemote("SaveSettings") :: RemoteEvent
			SaveSettings:FireServer(saveData)
		end
	end)
end

function Settings.Set(name: string, value: any)
	(settings :: any)[name] = value
	print("[Settings] Set", name, "to", tostring(value))
	SettingsChanged:Fire(name, value)

	-- save to server (debounced)
	saveToServer()
end

-- menu state management
function Settings.SetMenuOpen(open: boolean)
	isMenuOpen = open
	SettingsChanged:Fire("_menuOpen", open)
end

function Settings.IsMenuOpen(): boolean
	return isMenuOpen
end

function Settings.GetAllCrosshairSettings(): {
	color: Color3,
	size: number,
	thickness: number,
	gap: number,
	dotEnabled: boolean,
	dotSize: number,
	outline: boolean,
}
	return {
		color = settings.crosshairColor,
		size = settings.crosshairSize,
		thickness = settings.crosshairThickness,
		gap = settings.crosshairGap,
		dotEnabled = settings.crosshairDotEnabled,
		dotSize = settings.crosshairDotSize,
		outline = settings.crosshairOutline,
	}
end

-- check if settings have been loaded from server
function Settings.IsLoaded(): boolean
	return settingsLoaded
end

-- load settings from server data (called when SettingsLoaded fires)
local function loadFromServerData(serverSettings: { [string]: any })
	if not serverSettings then
		return
	end

	-- cast to any to allow dynamic key assignment (selene workaround)
	local settingsTable = settings :: any

	for key, value in serverSettings do
		-- handle Color3 reconstruction (stored as separate R/G/B values)
		if string.match(key, "Color[RGB]$") then
			-- skip individual RGB components, handle them together
			local baseKey = string.gsub(key, "[RGB]$", "")
			if serverSettings[baseKey .. "R"] and serverSettings[baseKey .. "G"] and serverSettings[baseKey .. "B"] then
				local color = Color3.new(
					serverSettings[baseKey .. "R"],
					serverSettings[baseKey .. "G"],
					serverSettings[baseKey .. "B"]
				)
				settingsTable[baseKey] = color
			end
		elseif not string.match(key, "[RGB]$") then
			-- regular setting (not an RGB component)
			settingsTable[key] = value
		end
	end

	settingsLoaded = true
	print("[Settings] Loaded settings from server")

	-- fire changed events for all settings so UI updates
	SettingsChanged:Fire("_allLoaded", true)
end

-- connect to server settings on client
if RunService:IsClient() then
	task.spawn(function()
		local Modules = ReplicatedStorage:WaitForChild("Modules")
		local RemoteService = require(Modules:WaitForChild("RemoteService"))
		local SettingsLoaded = RemoteService.GetRemote("SettingsLoaded") :: RemoteEvent

		SettingsLoaded.OnClientEvent:Connect(function(serverSettings)
			loadFromServerData(serverSettings)
		end)
	end)
end

return Settings
