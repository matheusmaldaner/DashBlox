--!strict

-- server module: centralized zombie AI with direct chase, optimized for performance
-- single heartbeat loop processes all zombies; no PathfindingService dependency
-- required by ZombieSpawner.server.lua

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieConfig = require(ReplicatedStorage.Modules.Zombies.ZombieConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local ZombieAI = {}

--------------------------------------------------
-- Constants
--------------------------------------------------

local TARGET_REVAL_FRAMES = 6 -- re-evaluate nearest player every 6 frames (~0.1s at 60fps)
local JUMP_RAY_DISTANCE = 3.0 -- forward raycast distance for wall detection
local JUMP_RAY_HEIGHT_OFFSET = 1.0 -- ray origin offset above rootpart center (knee height)

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

-- single shared raycast params (filter swapped per zombie)
local jumpRayParams = RaycastParams.new()
jumpRayParams.FilterType = Enum.RaycastFilterType.Exclude

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
-- Touch Damage (unchanged from original)
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

		-- step 2: no alive players — idle all zombies
		if cachedPlayerCount == 0 then
			for i = 1, registryCount do
				local zd = registry[i]
				if zd.aiState ~= "dying" then
					local rp = zd.model.PrimaryPart
					if rp then
						zd.humanoid:MoveTo(rp.Position)
					end
				end
			end
			return
		end

		-- step 3: process each zombie
		local currentBucket = frameCounter % TARGET_REVAL_FRAMES

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

			-- staggered target re-evaluation
			if currentBucket == zd._staggerBucket then
				zd.targetPlayer = ZombieAI.GetNearestPlayer(zombiePos)
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

			-- direct chase
			zd.humanoid:MoveTo(targetRoot.Position)

			-- raycast-based jump detection
			local moveDirection = zd.humanoid.MoveDirection
			if moveDirection.Magnitude > 0.1 then
				local rayOrigin = zombiePos + Vector3.new(0, JUMP_RAY_HEIGHT_OFFSET, 0)
				local rayDirection = moveDirection.Unit * JUMP_RAY_DISTANCE

				jumpRayParams.FilterDescendantsInstances = { zd.model }
				local result = workspace:Raycast(rayOrigin, rayDirection, jumpRayParams)
				if result then
					zd.humanoid.Jump = true
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
