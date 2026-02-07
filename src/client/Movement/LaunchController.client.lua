--!strict
-- LaunchController.client.lua
-- press P to launch the character into the air for 5 seconds

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- config
local LAUNCH_FORCE = 100 -- upward velocity on launch
local LAUNCH_DURATION = 5 -- seconds in the air
local FLOAT_FORCE = workspace.Gravity -- counteract gravity while airborne

-- state
local isLaunching = false
local launchConnection: RBPart.Connection? = nil

-- get humanoid root part
local function getRootPart(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- get humanoid
local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- launch the character
local function launch()
	if isLaunching then
		return
	end

	local rootPart = getRootPart()
	local humanoid = getHumanoid()
	if not rootPart or not humanoid then
		return
	end

	isLaunching = true

	-- create a BodyVelocity to launch upward
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(0, math.huge, 0)
	bodyVelocity.Velocity = Vector3.new(0, LAUNCH_FORCE, 0)
	bodyVelocity.Parent = rootPart

	-- after a short burst, switch to floating (counteract gravity)
	task.delay(0.3, function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity.Velocity = Vector3.new(0, 0, 0)
			bodyVelocity.MaxForce = Vector3.new(0, FLOAT_FORCE * 2, 0) -- hold in place
		end
	end)

	-- remove after duration
	task.delay(LAUNCH_DURATION, function()
		if bodyVelocity and bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
		isLaunching = false
	end)
end

-- input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.P then
		launch()
	end
end)

-- reset on respawn
player.CharacterAdded:Connect(function(_character)
	isLaunching = false
end)

print("[LaunchController] Initialized - Press P to launch")
