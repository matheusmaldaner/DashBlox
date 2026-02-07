--!strict
-- client-side match state tracker
-- simplified for pure pvp: combat is always enabled

local MatchStateClient = {}

local combatEnabled = true
local combatChanged = Instance.new("BindableEvent")

function MatchStateClient.GetState(): string?
	return "InProgress"
end

function MatchStateClient.IsCombatEnabled(): boolean
	return combatEnabled
end

function MatchStateClient.OnCombatChanged(callback: (boolean, string?) -> ()): RBXScriptConnection
	return combatChanged.Event:Connect(callback)
end

return MatchStateClient
