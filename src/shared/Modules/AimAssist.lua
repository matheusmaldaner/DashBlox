--!strict
-- aim assist - provides aim assistance for gamepad and touch input
-- only active when using gamepad or touch controls

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PlatformDetection = require(Modules.PlatformDetection)

local AimAssist = {}

-- configuration
local CONFIG = {
	enabled = true,
	strength = 0.6, -- 0-1, how strong the pull toward targets is
	maxDistance = 100, -- max range to detect targets
	coneAngle = 15, -- degrees from crosshair center to check for targets
	slowdownMultiplier = 0.5, -- sensitivity reduction when near targets
	stickinessRadius = 3, -- studs around target where assist activates
	pullSpeed = 5, -- degrees per second of rotation pull
	targetUpdateRate = 0.1, -- seconds between target scans
}

-- state
local localPlayer = Players.LocalPlayer
local camera: Camera = workspace.CurrentCamera :: Camera
local currentTarget: Player? = nil
local lastTargetScan = 0

--------------------------------------------------
-- Target Detection
--------------------------------------------------

-- check if a player is a valid target
local function isValidTarget(targetPlayer: Player): boolean
	if targetPlayer == localPlayer then
		return false
	end

	local character = targetPlayer.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end

	-- check distance
	local cameraPos = camera.CFrame.Position
	local targetPos = hrp.Position
	local distance = (targetPos - cameraPos).Magnitude

	if distance > CONFIG.maxDistance then
		return false
	end

	-- check line of sight
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { localPlayer.Character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = workspace:Raycast(cameraPos, (targetPos - cameraPos).Unit * distance, rayParams)

	if rayResult then
		-- check if we hit the target or something in front of them
		local hitPart = rayResult.Instance
		if hitPart and hitPart:IsDescendantOf(character) then
			return true -- hit the target
		end
		-- hit something else (wall, object)
		return false
	end

	return true -- no obstruction
end

-- get the angle between camera look direction and target
local function getAngleToTarget(targetPlayer: Player): number
	local character = targetPlayer.Character
	if not character then
		return 180
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return 180
	end

	local cameraPos = camera.CFrame.Position
	local lookVector = camera.CFrame.LookVector
	local toTarget = (hrp.Position - cameraPos).Unit

	-- calculate angle using dot product
	local dot = lookVector:Dot(toTarget)
	local angleRad = math.acos(math.clamp(dot, -1, 1))

	return math.deg(angleRad)
end

-- find the best target within the aim cone
local function findBestTarget(): Player?
	local bestTarget: Player? = nil
	local bestAngle = CONFIG.coneAngle

	for _, targetPlayer in Players:GetPlayers() do
		if isValidTarget(targetPlayer) then
			local angle = getAngleToTarget(targetPlayer)
			if angle < bestAngle then
				bestAngle = angle
				bestTarget = targetPlayer
			end
		end
	end

	return bestTarget
end

-- update target periodically
local function updateTarget()
	local now = tick()
	if now - lastTargetScan < CONFIG.targetUpdateRate then
		return
	end

	lastTargetScan = now

	-- find new target if needed
	if currentTarget then
		-- validate current target
		if not isValidTarget(currentTarget) or getAngleToTarget(currentTarget) > CONFIG.coneAngle * 1.5 then
			currentTarget = findBestTarget()
		end
	else
		currentTarget = findBestTarget()
	end
end

--------------------------------------------------
-- Aim Assist Calculations
--------------------------------------------------

-- get the rotation adjustment to pull toward target
local function getRotationPull(deltaTime: number): (number, number)
	if not CONFIG.enabled or not currentTarget then
		return 0, 0
	end

	-- only active for gamepad/touch
	if not PlatformDetection.ShouldEnableAimAssist() then
		return 0, 0
	end

	local character = currentTarget.Character
	if not character then
		return 0, 0
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return 0, 0
	end

	local cameraPos = camera.CFrame.Position
	local toTarget = (hrp.Position - cameraPos).Unit

	local screenAngle = getAngleToTarget(currentTarget)

	if screenAngle > CONFIG.coneAngle then
		return 0, 0
	end

	-- calculate pull strength based on distance from target center
	local pullStrength = CONFIG.strength * (1 - screenAngle / CONFIG.coneAngle)

	-- calculate yaw and pitch adjustments
	-- project target onto camera plane
	local cameraRight = camera.CFrame.RightVector
	local cameraUp = camera.CFrame.UpVector

	-- horizontal difference (yaw)
	local horizontalDiff = toTarget:Dot(cameraRight)

	-- vertical difference (pitch)
	local verticalDiff = toTarget:Dot(cameraUp)

	-- calculate rotation pull (degrees)
	local maxPullPerFrame = CONFIG.pullSpeed * deltaTime
	local yawPull = math.clamp(horizontalDiff * pullStrength * 10, -maxPullPerFrame, maxPullPerFrame)
	local pitchPull = math.clamp(verticalDiff * pullStrength * 10, -maxPullPerFrame, maxPullPerFrame)

	return yawPull, pitchPull
end

-- get sensitivity multiplier (slowdown near targets)
local function getSensitivityMultiplier(): number
	if not CONFIG.enabled or not currentTarget then
		return 1.0
	end

	-- only active for gamepad/touch
	if not PlatformDetection.ShouldEnableAimAssist() then
		return 1.0
	end

	local character = currentTarget.Character
	if not character then
		return 1.0
	end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return 1.0
	end

	local screenAngle = getAngleToTarget(currentTarget)

	-- check if within stickiness zone
	if screenAngle <= CONFIG.coneAngle then
		-- gradually increase slowdown as we get closer to center
		local slowdownFactor = 1 - (1 - CONFIG.slowdownMultiplier) * (1 - screenAngle / CONFIG.coneAngle)
		return slowdownFactor
	end

	return 1.0
end

--------------------------------------------------
-- Public API
--------------------------------------------------

-- enable/disable aim assist
function AimAssist.SetEnabled(enabled: boolean)
	CONFIG.enabled = enabled
	if not enabled then
		currentTarget = nil
	end
end

-- check if aim assist is enabled
function AimAssist.IsEnabled(): boolean
	return CONFIG.enabled
end

-- set aim assist strength (0-1)
function AimAssist.SetStrength(strength: number)
	CONFIG.strength = math.clamp(strength, 0, 1)
end

-- get current strength
function AimAssist.GetStrength(): number
	return CONFIG.strength
end

-- get current target (for debugging/UI)
function AimAssist.GetCurrentTarget(): Player?
	return currentTarget
end

-- get if currently aiming at a target
function AimAssist.IsAimingAtTarget(): boolean
	return currentTarget ~= nil and getAngleToTarget(currentTarget) <= CONFIG.coneAngle
end

-- get sensitivity multiplier for camera
function AimAssist.GetSensitivityMultiplier(): number
	return getSensitivityMultiplier()
end

-- apply rotation assist (call from camera controller)
-- returns yaw and pitch adjustments in degrees
function AimAssist.ApplyRotationAssist(deltaTime: number): (number, number)
	updateTarget()
	return getRotationPull(deltaTime)
end

-- force target update (useful after respawn)
function AimAssist.ForceTargetUpdate()
	lastTargetScan = 0
	currentTarget = nil
end

-- get target in cone without setting as current
function AimAssist.GetTargetInCone(): Player?
	return findBestTarget()
end

-- configuration getters/setters
function AimAssist.SetConeAngle(angle: number)
	CONFIG.coneAngle = math.clamp(angle, 5, 45)
end

function AimAssist.GetConeAngle(): number
	return CONFIG.coneAngle
end

function AimAssist.SetSlowdownMultiplier(multiplier: number)
	CONFIG.slowdownMultiplier = math.clamp(multiplier, 0.1, 1.0)
end

function AimAssist.GetSlowdownMultiplier(): number
	return CONFIG.slowdownMultiplier
end

function AimAssist.SetMaxDistance(distance: number)
	CONFIG.maxDistance = math.clamp(distance, 10, 200)
end

function AimAssist.GetMaxDistance(): number
	return CONFIG.maxDistance
end

--------------------------------------------------
-- Initialization
--------------------------------------------------

-- update camera reference when it changes
RunService.RenderStepped:Connect(function()
	if workspace.CurrentCamera then
		camera = workspace.CurrentCamera
	end
end)

-- clear target when local player respawns
localPlayer.CharacterAdded:Connect(function()
	currentTarget = nil
	lastTargetScan = 0
end)

return AimAssist
