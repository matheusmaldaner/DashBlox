--!strict
-- camera controller - uses roblox default camera with free mouse cursor
-- no locked view, no forced third-person offset
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchStateClient = require(ReplicatedStorage:WaitForChild("Modules").MatchStateClient)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera :: Camera

local function applyCombatState(enabled: boolean)
	if enabled then
		-- use default roblox camera, unlock cursor
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end

MatchStateClient.OnCombatChanged(function(enabled)
	applyCombatState(enabled)
end)

applyCombatState(MatchStateClient.IsCombatEnabled())

-- on respawn, re-apply default camera
player.CharacterAdded:Connect(function()
	task.wait(0.1)
	if MatchStateClient.IsCombatEnabled() then
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
end)
