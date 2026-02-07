--!strict

-- server module: zombie pathfinding AI, target selection, touch damage
-- required by ZombieSpawner.server.lua

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieConfig = require(ReplicatedStorage.Modules.Zombies.ZombieConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local ZombieAI = {}

--------------------------------------------------
-- Constants
--------------------------------------------------

local PATH_RECOMPUTE_INTERVAL = 1.0
local DIRECT_CHASE_DISTANCE = 15
local STUCK_CHECK_INTERVAL = 3.0
local STUCK_DISTANCE_THRESHOLD = 2

-- reusable pathfinding agent params
local AGENT_PARAMS = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	AgentCanClimb = false,
}

--------------------------------------------------
-- Types
--------------------------------------------------

export type ZombieData = {
	model: Model,
	humanoid: Humanoid,
	zombieType: string,
	health: number,
	maxHealth: number,
	lastAttackTime: number,
	targetPlayer: Player?,
	connections: { RBXScriptConnection },
	aiState: string,
}

--------------------------------------------------
-- Helpers
--------------------------------------------------

-- check if a part belongs to a player character
local function GetPlayerFromPart(part: BasePart): Player?
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end
	for _, p in Players:GetPlayers() do
		if p.Character == character then
			return p
		end
	end
	return nil
end

-- find the nearest alive player to a world position
function ZombieAI.GetNearestPlayer(position: Vector3): Player?
	local nearestPlayer: Player? = nil
	local nearestDist = math.huge

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			continue
		end

		local dist = (rootPart.Position - position).Magnitude
		if dist < nearestDist then
			nearestDist = dist
			nearestPlayer = player
		end
	end

	return nearestPlayer
end

--------------------------------------------------
-- Pathfinding
--------------------------------------------------

-- compute a path from zombie to target, returns waypoints or nil
local function ComputePath(startPosition: Vector3, targetPosition: Vector3): { PathWaypoint }?
	local path = PathfindingService:CreatePath(AGENT_PARAMS)

	local success, err = pcall(function()
		path:ComputeAsync(startPosition, targetPosition)
	end)

	if not success then
		warn("[ZombieAI] path compute failed:", err)
		return nil
	end

	if path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	end

	return nil
end

--------------------------------------------------
-- Touch Damage
--------------------------------------------------

-- sets up touch damage on the zombie's torso
local function SetupTouchDamage(zombieData: ZombieData)
	local stats = ZombieConfig.Zombies[zombieData.zombieType]
	if not stats then
		return
	end

	local PlayerDamagedRemote = RemoteService.GetRemote("PlayerDamaged") :: RemoteEvent
	local torso = zombieData.model:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return
	end

	local connection = torso.Touched:Connect(function(hit: BasePart)
		if zombieData.aiState == "dying" then
			return
		end

		local player = GetPlayerFromPart(hit)
		if not player then
			return
		end

		-- attack cooldown check
		local currentTime = tick()
		if currentTime - zombieData.lastAttackTime < stats.AttackCooldown then
			return
		end
		zombieData.lastAttackTime = currentTime

		-- apply damage server-side
		local playerCharacter = player.Character
		if not playerCharacter then
			return
		end

		local playerHumanoid = playerCharacter:FindFirstChildOfClass("Humanoid")
		if not playerHumanoid or playerHumanoid.Health <= 0 then
			return
		end

		playerHumanoid:TakeDamage(stats.Damage)

		-- notify the player they took damage
		PlayerDamagedRemote:FireClient(player, {
			damage = stats.Damage,
			source = "Zombie",
			zombieType = zombieData.zombieType,
		})
	end)

	table.insert(zombieData.connections, connection)
end

--------------------------------------------------
-- Main AI Loop
--------------------------------------------------

-- starts the AI heartbeat loop for one zombie
function ZombieAI.StartAI(zombieData: ZombieData)
	zombieData.aiState = "chasing"
	zombieData.connections = zombieData.connections or {}

	-- set up touch damage
	SetupTouchDamage(zombieData)

	local lastPathTime = 0
	local currentWaypoints: { PathWaypoint } = {}
	local waypointIndex = 1
	local lastPosition = Vector3.zero
	local lastStuckCheck = tick()

	local aiConnection = RunService.Heartbeat:Connect(function()
		if zombieData.aiState == "dying" then
			return
		end

		local rootPart = zombieData.model.PrimaryPart
		if not rootPart then
			return
		end

		-- find target player
		local target = ZombieAI.GetNearestPlayer(rootPart.Position)
		if not target then
			zombieData.humanoid:MoveTo(rootPart.Position)
			return
		end

		zombieData.targetPlayer = target
		local targetCharacter = target.Character
		if not targetCharacter then
			return
		end

		local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not targetRoot then
			return
		end

		local distanceToTarget = (targetRoot.Position - rootPart.Position).Magnitude

		-- close enough: skip pathfinding, chase directly
		if distanceToTarget < DIRECT_CHASE_DISTANCE then
			zombieData.humanoid:MoveTo(targetRoot.Position)
			waypointIndex = 1
			currentWaypoints = {}
			return
		end

		-- stuck detection: if barely moved in 3 seconds, force recompute
		local currentTime = tick()
		if currentTime - lastStuckCheck > STUCK_CHECK_INTERVAL then
			local movedDist = (rootPart.Position - lastPosition).Magnitude
			if movedDist < STUCK_DISTANCE_THRESHOLD then
				-- stuck, force new path
				lastPathTime = 0
				waypointIndex = 1
				currentWaypoints = {}
			end
			lastPosition = rootPart.Position
			lastStuckCheck = currentTime
		end

		-- recompute path periodically
		if currentTime - lastPathTime > PATH_RECOMPUTE_INTERVAL then
			lastPathTime = currentTime
			local waypoints = ComputePath(rootPart.Position, targetRoot.Position)
			if waypoints then
				currentWaypoints = waypoints
				waypointIndex = 2 -- skip first waypoint (current position)
			end
		end

		-- follow waypoints
		if waypointIndex <= #currentWaypoints then
			local waypoint = currentWaypoints[waypointIndex]
			zombieData.humanoid:MoveTo(waypoint.Position)

			-- check if reached current waypoint
			local distToWaypoint = (waypoint.Position - rootPart.Position).Magnitude
			if distToWaypoint < 4 then
				waypointIndex += 1
			end

			-- handle jump waypoints
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				zombieData.humanoid.Jump = true
			end
		else
			-- no valid path, fall back to direct chase
			zombieData.humanoid:MoveTo(targetRoot.Position)
		end
	end)

	table.insert(zombieData.connections, aiConnection)
end

--------------------------------------------------
-- Cleanup
--------------------------------------------------

-- stops all AI behavior for a zombie
function ZombieAI.StopAI(zombieData: ZombieData)
	zombieData.aiState = "dying"

	for _, connection in zombieData.connections do
		connection:Disconnect()
	end
	zombieData.connections = {}
end

return ZombieAI
