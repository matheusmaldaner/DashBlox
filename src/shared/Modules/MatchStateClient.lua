--!strict
-- client-side match state tracker (combat UI/camera gating)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevMode = require(Modules.DevMode)

local MatchStateClient = {}

export type MatchState = "Waiting" | "Starting" | "InProgress" | "RoundEnd" | "MatchEnd" | "Cancelled"

local currentState: MatchState? = nil
-- initialize combatEnabled based on dev mode (so UI created before async check works)
local combatEnabled = DevMode.IsEnabled()

local combatChanged = Instance.new("BindableEvent")

local function isCombatState(state: string?): boolean
	-- in dev mode, combat is always enabled for testing
	if DevMode.IsEnabled() then
		return true
	end
	return state == "Starting" or state == "InProgress" or state == "RoundEnd"
end

local function setState(state: string?)
	currentState = state
	local enabled = isCombatState(state)
	if enabled ~= combatEnabled then
		combatEnabled = enabled
		combatChanged:Fire(combatEnabled, currentState)
	end
end

function MatchStateClient.GetState(): MatchState?
	return currentState
end

function MatchStateClient.IsCombatEnabled(): boolean
	return combatEnabled
end

function MatchStateClient.OnCombatChanged(callback: (boolean, MatchState?) -> ()): RBXScriptConnection
	return combatChanged.Event:Connect(callback)
end

if RunService:IsClient() then
	local RemoteService = require(Modules.RemoteService)
	local MatchStateChanged = RemoteService.GetRemote("MatchStateChanged") :: RemoteEvent
	local GetMatchState = RemoteService.GetRemote("GetMatchState") :: RemoteFunction

	MatchStateChanged.OnClientEvent:Connect(function(data)
		if data and data.state then
			setState(data.state)
		end
	end)

	-- request current match state on initialization (handles race condition with server events)
	task.spawn(function()
		local success, result = pcall(function()
			return GetMatchState:InvokeServer()
		end)

		if success and result and result.state then
			setState(result.state)
		else
			-- no match active - still call setState to trigger dev mode check
			setState(nil)
		end
	end)
end

return MatchStateClient
