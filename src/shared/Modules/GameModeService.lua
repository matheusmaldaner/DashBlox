--!strict
-- game mode service - manages global game mode state (gun only, no building)

local GameModeService = {}

export type GameMode = "Gun"

local currentMode: GameMode = "Gun"
local modeChangedCallbacks: { (GameMode) -> () } = {}

function GameModeService.GetMode(): GameMode
	return currentMode
end

function GameModeService.SetMode(mode: GameMode)
	if currentMode ~= mode then
		currentMode = mode
		for _, callback in modeChangedCallbacks do
			callback(mode)
		end
	end
end

function GameModeService.OnModeChanged(callback: (GameMode) -> ())
	table.insert(modeChangedCallbacks, callback)
end

function GameModeService.IsGunMode(): boolean
	return currentMode == "Gun"
end

return GameModeService
