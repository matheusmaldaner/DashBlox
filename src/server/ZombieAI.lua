--!strict

-- server module: centralized zombie AI with pathfinding + barricade breaking
-- single heartbeat loop processes all zombies with staggered path recomputation
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

-- target evaluation
local TARGET_REVAL_FRAMES = 6 -- re-evaluate nearest player every 6 frames (~0.1s)
local DIRECT_CHASE_DISTANCE = 15 -- skip pathfinding when this close

-- pathfinding
local MAX_CONCURRENT_PATHS = 6 -- max simultaneous ComputeAsync calls
local PATH_RECOMPUTE_FRAMES = 60 -- request a new path every ~1 second
local WAYPOINT_REACH_DIST = 4 -- advance to next waypoint when this close

local AGENT_PARAMS = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	AgentCanClimb = false,
}

-- barricades
local BARRICADE_ATTACK_RANGE = 5 -- studs from barricade center to start attacking
local BARRICADE_ATTACK_COOLDOWN = 1.0 -- seconds between barricade hits
local BARRICADE_BROKEN_TRANSPARENCY = 0.5 -- transparency when a board is broken

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
	-- internal: managed by StartAI/StopAI
	_registryIndex: number?,
	_staggerBucket: number?,
	-- pathfinding state
	_waypoints: { PathWaypoint }?,
	_waypointIndex: number,
	_pathAge: number,
	_pathRequested: boolean,
	-- barricade state
	_targetBarricade: Model?,
	_lastBarricadeAttack: number,
}

--------------------------------------------------
-- Centralized Registry State
--------------------------------------------------

local registry: { ZombieData } = {}
local registryCount: number = 0
local frameCounter: number = 0

-- player position cache, rebuilt once per frame
local cachedPlayers: { { player: Player, rootPart: BasePart, position: Vector3 } } = {}
local cachedPlayerCount: number = 0

-- pathfinding concurrency control
local activePathComputations: number = 0

-- the one heartbeat connection for all zombies
local heartbeatConnection: RBXScriptConnection? = nil

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

--------------------------------------------------
-- Barricade System
--------------------------------------------------

-- check if a barricade still has any intact (CanCollide true) parts
local function IsBarricadeIntact(barricade: Model): boolean
	for _, child in barricade:GetChildren() do
		if child:IsA("BasePart") and child.CanCollide then
			return true
		end
	end
	return false
end

-- find the closest barricade that still has intact parts
local function FindClosestBarricade(position: Vector3): Model?
	local barricadesFolder = workspace:FindFirstChild("Map")
	if barricadesFolder then
		barricadesFolder = barricadesFolder:FindFirstChild("Barricades")
	end
	if not barricadesFolder then
		return nil
	end

	local closestBarricade: Model? = nil
	local closestDistSq = math.huge

	for _, barricade in barricadesFolder:GetChildren() do
		if not barricade:IsA("Model") then
			continue
		end

		-- skip barricades that are already fully broken
		if not IsBarricadeIntact(barricade) then
			continue
		end

		-- get barricade position from its PrimaryPart or first BasePart
		local barricadePos: Vector3?
		if barricade.PrimaryPart then
			barricadePos = barricade.PrimaryPart.Position
		else
			for _, child in barricade:GetChildren() do
				if child:IsA("BasePart") then
					barricadePos = child.Position
					break
				end
			end
		end

		if not barricadePos then
			continue
		end

		local delta = barricadePos - position
		local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
		if distSq < closestDistSq then
			closestDistSq = distSq
			closestBarricade = barricade
		end
	end

	return closestBarricade
end

-- get the center position of a barricade model
local function GetBarricadePosition(barricade: Model): Vector3?
	if barricade.PrimaryPart then
		return barricade.PrimaryPart.Position
	end
	for _, child in barricade:GetChildren() do
		if child:IsA("BasePart") then
			return child.Position
		end
	end
	return nil
end

-- attack a barricade: break one intact part per call
local function AttackBarricade(barricade: Model): boolean
	for _, child in barricade:GetChildren() do
		if child:IsA("BasePart") and child.CanCollide then
			child.CanCollide = false
			child.Transparency = BARRICADE_BROKEN_TRANSPARENCY
			return true -- broke a part
		end
	end
	return false -- nothing left to break
end

--------------------------------------------------
-- Player Position Cache
--------------------------------------------------

-- rebuild the player cache once per frame (called at top of heartbeat)
local function CachePlayerPositions()
	cachedPlayerCount = 0

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

		cachedPlayerCount += 1
		local entry = cachedPlayers[cachedPlayerCount]
		if entry then
			entry.player = player
			entry.rootPart = rootPart
			entry.position = rootPart.Position
		else
			cachedPlayers[cachedPlayerCount] = {
				player = player,
				rootPart = rootPart,
				position = rootPart.Position,
			}
		end
	end
end

--------------------------------------------------
-- Target Selection (uses cache, squared distance)
--------------------------------------------------

-- find the nearest alive player to a world position
function ZombieAI.GetNearestPlayer(position: Vector3): Player?
	local nearestPlayer: Player? = nil
	local nearestDistSq = math.huge

	for i = 1, cachedPlayerCount do
		local entry = cachedPlayers[i]
		local delta = entry.position - position
		local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
		if distSq < nearestDistSq then
			nearestDistSq = distSq
			nearestPlayer = entry.player
		end
	end

	return nearestPlayer
end

--------------------------------------------------
-- Pathfinding (async, concurrency-limited)
--------------------------------------------------

-- request a path computation for a zombie (non-blocking)
local function RequestPath(zombieData: ZombieData, startPos: Vector3, targetPos: Vector3)
	if zombieData._pathRequested then
		return
	end
	if activePathComputations >= MAX_CONCURRENT_PATHS then
		return
	end

	zombieData._pathRequested = true
	activePathComputations += 1

	task.spawn(function()
		-- zombie may have died while we were queued
		if zombieData.aiState == "dying" then
			zombieData._pathRequested = false
			activePathComputations -= 1
			return
		end

		local path = PathfindingService:CreatePath(AGENT_PARAMS)
		local success = pcall(function()
			path:ComputeAsync(startPos, targetPos)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			if #waypoints > 1 then
				zombieData._waypoints = waypoints
				zombieData._waypointIndex = 2 -- skip first (current position)
				zombieData._pathAge = frameCounter
			end
		end

		zombieData._pathRequested = false
		activePathComputations -= 1
	end)
end

-- check if a zombie needs a new path (no path, or path is stale)
local function NeedsNewPath(zombieData: ZombieData): boolean
	if not zombieData._waypoints then
		return true
	end
	if zombieData._waypointIndex > #zombieData._waypoints then
		return true
	end
	if (frameCounter - zombieData._pathAge) > PATH_RECOMPUTE_FRAMES then
		return true
	end
	return false
end

-- clear a zombie's path data
local function ClearPath(zombieData: ZombieData)
	zombieData._waypoints = nil
	zombieData._waypointIndex = 1
	zombieData._pathAge = 0
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
-- Centralized Heartbeat Loop
--------------------------------------------------

local function EnsureHeartbeat()
	if heartbeatConnection then
		return
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if registryCount == 0 then
			return
		end

		frameCounter += 1

		-- step 1: cache all player positions once
		CachePlayerPositions()

		-- step 2: no alive players — idle all zombies (barricade zombies still attack)
		-- (handled per-zombie below)

		-- step 3: process each zombie
		local currentBucket = frameCounter % TARGET_REVAL_FRAMES
		local currentTime = tick()

		for i = 1, registryCount do
			local zd = registry[i]

			if zd.aiState == "dying" then
				continue
			end

			local rootPart = zd.model.PrimaryPart
			if not rootPart then
				continue
			end

			local zombiePos = rootPart.Position

			-- ==========================================
			-- BARRICADE PHASE: runs before player chase
			-- ==========================================
			local barricade = zd._targetBarricade
			if barricade then
				-- check if barricade is still intact
				if not IsBarricadeIntact(barricade) then
					-- barricade fully broken, switch to player targeting
					zd._targetBarricade = nil
					ClearPath(zd)
				else
					-- move toward the barricade
					local barricadePos = GetBarricadePosition(barricade)
					if barricadePos then
						local delta = barricadePos - zombiePos
						local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z

						if distSq < BARRICADE_ATTACK_RANGE * BARRICADE_ATTACK_RANGE then
							-- in range: stop moving and attack on cooldown
							zd.humanoid:MoveTo(zombiePos)

							if (currentTime - zd._lastBarricadeAttack) >= BARRICADE_ATTACK_COOLDOWN then
								zd._lastBarricadeAttack = currentTime
								local broke = AttackBarricade(barricade)
								if not broke then
									-- nothing left, barricade is done
									zd._targetBarricade = nil
									ClearPath(zd)
								end
							end
						else
							-- walk toward barricade
							zd.humanoid:MoveTo(barricadePos)
						end
					end

					-- skip player targeting while focused on barricade
					continue
				end
			end

			-- ==========================================
			-- PLAYER CHASE PHASE (normal behavior)
			-- ==========================================

			-- staggered target re-evaluation
			if currentBucket == zd._staggerBucket then
				local newTarget = ZombieAI.GetNearestPlayer(zombiePos)
				-- clear path if target changed
				if newTarget ~= zd.targetPlayer then
					ClearPath(zd)
				end
				zd.targetPlayer = newTarget
			end

			-- resolve target position
			local target = zd.targetPlayer
			if not target then
				zd.humanoid:MoveTo(zombiePos)
				continue
			end

			local targetCharacter = target.Character
			if not targetCharacter then
				zd.targetPlayer = nil
				zd.humanoid:MoveTo(zombiePos)
				continue
			end

			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not targetRoot then
				zd.targetPlayer = nil
				zd.humanoid:MoveTo(zombiePos)
				continue
			end

			local targetPos = targetRoot.Position
			local delta = targetPos - zombiePos
			local distSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z

			-- CLOSE RANGE: direct chase, no pathfinding needed
			if distSq < DIRECT_CHASE_DISTANCE * DIRECT_CHASE_DISTANCE then
				ClearPath(zd)
				zd.humanoid:MoveTo(targetPos)
			else
				-- FAR RANGE: use pathfinding

				-- request a new path if needed (stale, exhausted, or missing)
				if NeedsNewPath(zd) then
					RequestPath(zd, zombiePos, targetPos)
				end

				-- follow waypoints if we have them, otherwise direct chase as fallback
				local waypoints = zd._waypoints
				if waypoints and zd._waypointIndex <= #waypoints then
					local wp = waypoints[zd._waypointIndex]

					zd.humanoid:MoveTo(wp.Position)

					-- advance waypoint if close enough
					local wpDelta = wp.Position - zombiePos
					local wpDistSq = wpDelta.X * wpDelta.X + wpDelta.Y * wpDelta.Y + wpDelta.Z * wpDelta.Z
					if wpDistSq < WAYPOINT_REACH_DIST * WAYPOINT_REACH_DIST then
						zd._waypointIndex += 1
					end

					-- handle jump waypoints
					if wp.Action == Enum.PathWaypointAction.Jump then
						zd.humanoid.Jump = true
					end
				else
					-- no path yet (waiting for ComputeAsync), direct chase in the meantime
					zd.humanoid:MoveTo(targetPos)
				end
			end
		end
	end)
end

--------------------------------------------------
-- Public API
--------------------------------------------------

-- registers a zombie into the centralized AI loop
function ZombieAI.StartAI(zombieData: ZombieData)
	zombieData.aiState = "chasing"
	zombieData.connections = zombieData.connections or {}

	-- initialize pathfinding state
	zombieData._waypoints = nil
	zombieData._waypointIndex = 1
	zombieData._pathAge = 0
	zombieData._pathRequested = false

	-- initialize barricade targeting: find closest intact barricade (checked once)
	zombieData._lastBarricadeAttack = 0
	local rootPart = zombieData.model.PrimaryPart
	if rootPart then
		zombieData._targetBarricade = FindClosestBarricade(rootPart.Position)
	else
		zombieData._targetBarricade = nil
	end

	-- set up touch damage
	SetupTouchDamage(zombieData)

	-- register in centralized registry
	registryCount += 1
	registry[registryCount] = zombieData
	zombieData._registryIndex = registryCount
	zombieData._staggerBucket = registryCount % TARGET_REVAL_FRAMES

	-- ensure the single heartbeat is running
	EnsureHeartbeat()
end

-- removes a zombie from the AI loop and cleans up connections
function ZombieAI.StopAI(zombieData: ZombieData)
	zombieData.aiState = "dying"

	-- clear path data
	ClearPath(zombieData)
	zombieData._pathRequested = false
	zombieData._targetBarricade = nil

	-- swap-and-pop removal from registry (O(1))
	local idx = zombieData._registryIndex
	if idx and idx <= registryCount then
		local lastEntry = registry[registryCount]
		registry[idx] = lastEntry
		lastEntry._registryIndex = idx
		registry[registryCount] = nil
		registryCount -= 1
	end
	zombieData._registryIndex = nil

	-- disconnect all stored connections (touch damage, etc.)
	for _, connection in zombieData.connections do
		connection:Disconnect()
	end
	zombieData.connections = {}

	-- stop heartbeat if no zombies remain
	if registryCount == 0 and heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

return ZombieAI
