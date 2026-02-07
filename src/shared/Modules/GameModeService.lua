--!strict
-- game mode service - manages global game mode state (gun, build, pickaxe, edit)

local GameModeService = {}

export type GameMode = "Gun" | "Build" | "Pickaxe" | "Edit"

local currentMode: GameMode = "Gun"
local modeChangedCallbacks: { (GameMode) -> () } = {}
local editModeChangedCallbacks: { (boolean) -> () } = {}

function GameModeService.GetMode(): GameMode
	return currentMode
end

function GameModeService.SetMode(mode: GameMode)
	if currentMode ~= mode then
		local wasEdit = currentMode == "Edit"
		local isEdit = mode == "Edit"

		currentMode = mode
		for _, callback in modeChangedCallbacks do
			callback(mode)
		end

		-- fire edit mode changed callbacks when transitioning in/out of Edit
		if wasEdit and not isEdit then
			for _, callback in editModeChangedCallbacks do
				callback(false)
			end
		elseif not wasEdit and isEdit then
			for _, callback in editModeChangedCallbacks do
				callback(true)
			end
		end
	end
end

function GameModeService.ToggleMode()
	-- toggle between Gun and Build (pickaxe/edit are separate)
	if currentMode == "Pickaxe" or currentMode == "Edit" then
		GameModeService.SetMode("Gun")
	else
		GameModeService.SetMode(currentMode == "Gun" and "Build" or "Gun")
	end
end

function GameModeService.OnModeChanged(callback: (GameMode) -> ())
	table.insert(modeChangedCallbacks, callback)
end

function GameModeService.IsBuildMode(): boolean
	return currentMode == "Build"
end

function GameModeService.IsGunMode(): boolean
	return currentMode == "Gun"
end

function GameModeService.IsPickaxeMode(): boolean
	return currentMode == "Pickaxe"
end

function GameModeService.IsEditMode(): boolean
	return currentMode == "Edit"
end

-- edit mode convenience (wraps SetMode for backward compat)
function GameModeService.SetEditMode(enabled: boolean)
	if enabled then
		GameModeService.SetMode("Edit")
	else
		-- return to Build mode when exiting edit
		GameModeService.SetMode("Build")
	end
end

function GameModeService.OnEditModeChanged(callback: (boolean) -> ())
	table.insert(editModeChangedCallbacks, callback)
end

return GameModeService
