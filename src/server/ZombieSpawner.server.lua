--!strict

-- main zombie system entry point: R6 model builder, object pooling,
-- spawn point management, and wave lifecycle controller

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local ZombieConfig = require(ReplicatedStorage.Modules.Zombies.ZombieConfig)
local WaveConfig = require(ReplicatedStorage.Modules.Zombies.WaveConfig)
local ZombieAI = require(ServerScriptService.ZombieAI)
local ZombieDamage = require(ServerScriptService.ZombieDamage)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

--------------------------------------------------
-- Remotes
--------------------------------------------------

local ZombieSpawnedRemote = RemoteService.GetRemote("ZombieSpawned") :: RemoteEvent
local WaveStartedRemote = RemoteService.GetRemote("WaveStarted") :: RemoteEvent
local WaveCompletedRemote = RemoteService.GetRemote("WaveCompleted") :: RemoteEvent
local WaveCountdownRemote = RemoteService.GetRemote("WaveCountdown") :: RemoteEvent
local WaveStateSyncRemote = RemoteService.GetRemote("WaveStateSync") :: RemoteFunction

--------------------------------------------------
-- State
--------------------------------------------------

local activeZombies: { [Model]: ZombieAI.ZombieData } = {}
local zombiePool: { [string]: { Model } } = {}
local allSpawnPoints: { BasePart } = {} -- every ZombieSpawn-tagged part
local spawnPoints: { BasePart } = {}   -- only the currently active ones
local unlockedZones: { [string]: boolean } = {}

local waveState: WaveConfig.WaveState = {
	round = 0,
	playerCount = 0,
	zombiesRemaining = 0,
	zombiesAlive = 0,
	zombiesSpawned = 0,
	totalZombiesForRound = 0,
	isActive = false,
	restPhase = true,
}

local gameStarted = false

--------------------------------------------------
-- Storage folder for pooled zombies
--------------------------------------------------

local ZombieStorage = ServerStorage:FindFirstChild("ZombiePool")
if not ZombieStorage then
	ZombieStorage = Instance.new("Folder")
	ZombieStorage.Name = "ZombiePool"
	ZombieStorage.Parent = ServerStorage
end

--------------------------------------------------
-- R6 Zombie Model Builder
--------------------------------------------------

-- r6 body part definitions (name, size, offset from torso center)
local R6_PARTS = {
	{ name = "Head", size = Vector3.new(2, 1, 1), offset = CFrame.new(0, 1.5, 0) },
	{ name = "Torso", size = Vector3.new(2, 2, 1), offset = CFrame.new(0, 0, 0) },
	{ name = "Left Arm", size = Vector3.new(1, 2, 1), offset = CFrame.new(-1.5, 0, 0) },
	{ name = "Right Arm", size = Vector3.new(1, 2, 1), offset = CFrame.new(1.5, 0, 0) },
	{ name = "Left Leg", size = Vector3.new(1, 2, 1), offset = CFrame.new(-0.5, -2, 0) },
	{ name = "Right Leg", size = Vector3.new(1, 2, 1), offset = CFrame.new(0.5, -2, 0) },
}

-- motor6d joint definitions connecting r6 parts
local R6_JOINTS = {
	{ name = "Neck", part0 = "Torso", part1 = "Head",
		c0 = CFrame.new(0, 1, 0), c1 = CFrame.new(0, -0.5, 0) },
	{ name = "Left Shoulder", part0 = "Torso", part1 = "Left Arm",
		c0 = CFrame.new(-1, 0.5, 0), c1 = CFrame.new(0.5, 0.5, 0) },
	{ name = "Right Shoulder", part0 = "Torso", part1 = "Right Arm",
		c0 = CFrame.new(1, 0.5, 0), c1 = CFrame.new(-0.5, 0.5, 0) },
	{ name = "Left Hip", part0 = "Torso", part1 = "Left Leg",
		c0 = CFrame.new(-1, -1, 0), c1 = CFrame.new(-0.5, 1, 0) },
	{ name = "Right Hip", part0 = "Torso", part1 = "Right Leg",
		c0 = CFrame.new(1, -1, 0), c1 = CFrame.new(0.5, 1, 0) },
}

local function CreateZombieModel(zombieType: string): Model
	local stats = ZombieConfig.Zombies[zombieType]
	local scale = stats.Scale

	local model = Instance.new("Model")
	model.Name = "Zombie_" .. zombieType

	-- create humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = stats.WalkSpeed
	humanoid.MaxHealth = stats.Health
	humanoid.Health = stats.Health
	humanoid.Parent = model

	-- build body parts
	local parts: { [string]: BasePart } = {}
	for _, def in R6_PARTS do
		local part = Instance.new("Part")
		part.Name = def.name
		part.Size = def.size * scale
		part.Anchored = false
		part.CanCollide = (def.name == "Torso" or def.name == "Head")
		part.CollisionGroup = "Zombie"
		part.Material = Enum.Material.SmoothPlastic

		-- color: head + torso use primary, limbs use secondary
		if def.name == "Head" or def.name == "Torso" then
			part.Color = stats.BodyColor
		else
			part.Color = stats.SecondaryColor or stats.BodyColor
		end

		part.CFrame = def.offset
		part.Parent = model
		parts[def.name] = part
	end

	-- face decal on head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = ZombieConfig.FaceDecalId
	face.Parent = parts["Head"]

	-- eye glow point light
	if stats.EyeGlow then
		local eyeLight = Instance.new("PointLight")
		eyeLight.Color = stats.EyeGlow
		eyeLight.Brightness = 1.5
		eyeLight.Range = 4
		eyeLight.Parent = parts["Head"]
	end

	-- motor6d joints
	for _, jointDef in R6_JOINTS do
		local motor = Instance.new("Motor6D")
		motor.Name = jointDef.name
		motor.Part0 = parts[jointDef.part0]
		motor.Part1 = parts[jointDef.part1]
		motor.C0 = jointDef.c0
		motor.C1 = jointDef.c1
		motor.Parent = parts[jointDef.part0]
	end

	-- humanoid root part (required for pathfinding + MoveTo)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1) * scale
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.CollisionGroup = "Zombie"
	rootPart.Anchored = false
	rootPart.Parent = model

	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "RootJoint"
	rootJoint.Part0 = rootPart
	rootJoint.Part1 = parts["Torso"]
	rootJoint.Parent = rootPart

	model.PrimaryPart = rootPart

	-- accessories from config
	local accessories = ZombieConfig.Accessories[zombieType]
	if accessories then
		for _, accDef in accessories do
			local acc = Instance.new("Accessory")
			acc.Name = "ZombieAcc_" .. tostring(accDef.assetId)
			acc:SetAttribute("AssetId", accDef.assetId)
			acc.Parent = model
		end
	end

	-- identification tags
	model:SetAttribute("IsZombie", true)
	model:SetAttribute("ZombieType", zombieType)

	-- highlight: visible through walls
	local highlight = Instance.new("Highlight")
	highlight.FillColor = stats.BodyColor
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = stats.EyeGlow or stats.BodyColor
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model

	return model
end

--------------------------------------------------
-- Object Pooling
--------------------------------------------------

local function InitializePool()
	for typeName, _ in ZombieConfig.Zombies do
		zombiePool[typeName] = {}
		for _ = 1, ZombieConfig.PoolSizePerType do
			local model = CreateZombieModel(typeName)
			model.Parent = ZombieStorage
			table.insert(zombiePool[typeName], model)
		end
	end
end

local function AcquireZombie(zombieType: string): Model
	local pool = zombiePool[zombieType]
	if pool and #pool > 0 then
		return table.remove(pool) :: Model
	end
	-- pool exhausted, create on demand
	return CreateZombieModel(zombieType)
end

local function ReleaseZombie(model: Model, zombieType: string)
	activeZombies[model] = nil

	-- reset humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local stats = ZombieConfig.Zombies[zombieType]
		if stats then
			humanoid.MaxHealth = stats.Health
			humanoid.Health = stats.Health
			humanoid.WalkSpeed = stats.WalkSpeed
		end
	end

	-- remove creator tag if present
	if humanoid then
		local creator = humanoid:FindFirstChild("creator")
		if creator then
			creator:Destroy()
		end
	end

	model.Parent = ZombieStorage

	local pool = zombiePool[zombieType]
	if pool then
		table.insert(pool, model)
	end
end

--------------------------------------------------
-- Spawn Points (CollectionService tagged parts, zone-aware)
--------------------------------------------------

local function IsSpawnActive(spawn: BasePart): boolean
	local zone = spawn:GetAttribute("Zone")
	if not zone or typeof(zone) ~= "string" or zone == "" or zone == "Start" then
		return true -- no zone or "Start" = always active
	end
	return unlockedZones[zone] == true
end

local function RefreshActiveSpawns()
	spawnPoints = {}
	for _, spawn in allSpawnPoints do
		if IsSpawnActive(spawn) then
			table.insert(spawnPoints, spawn)
		end
	end
end

local function DiscoverSpawnPoints()
	allSpawnPoints = CollectionService:GetTagged("ZombieSpawn") :: { BasePart }
	RefreshActiveSpawns()
	if #spawnPoints == 0 then
		warn("[ZombieSpawner] no active ZombieSpawn points found, zombies will spawn at origin")
	end
end

local function GetRandomSpawnPoint(): CFrame
	if #spawnPoints == 0 then
		return CFrame.new(0, 10, 0)
	end

	local point = spawnPoints[math.random(1, #spawnPoints)]
	-- randomize within the part's surface area
	local size = point.Size
	local offset = Vector3.new(
		(math.random() - 0.5) * size.X,
		0,
		(math.random() - 0.5) * size.Z
	)
	return point.CFrame * CFrame.new(offset) + Vector3.new(0, 3, 0)
end

--------------------------------------------------
-- Forward Declarations
-- (SpawnZombie -> OnZombieDied -> EndRound call chain requires these)
--------------------------------------------------

local OnZombieDied: (model: Model, zombieType: string) -> ()
local EndRound: () -> ()
local StartRound: (round: number) -> ()

--------------------------------------------------
-- Spawn Single Zombie
--------------------------------------------------

local function SpawnZombie(zombieType: string, round: number)
	local model = AcquireZombie(zombieType)
	local stats = ZombieConfig.Zombies[zombieType]
	local spawnCF = GetRandomSpawnPoint()

	-- apply wave-scaled health
	local scaledHealth = WaveConfig.GetZombieHealth(round, stats.Health)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	if humanoid then
		humanoid.MaxHealth = scaledHealth
		humanoid.Health = scaledHealth
		humanoid.WalkSpeed = stats.WalkSpeed
	end

	model:PivotTo(spawnCF)
	model.Parent = workspace

	-- track this zombie
	local zombieData: ZombieAI.ZombieData = {
		model = model,
		humanoid = humanoid,
		zombieType = zombieType,
		health = scaledHealth,
		maxHealth = scaledHealth,
		lastAttackTime = 0,
		targetPlayer = nil,
		connections = {},
		aiState = "idle",
	}
	activeZombies[model] = zombieData

	-- start AI
	ZombieAI.StartAI(zombieData)

	-- connect death handler
	ZombieDamage.ConnectZombieDeath(model, zombieType, function()
		OnZombieDied(model, zombieType)
	end)

	waveState.zombiesAlive += 1
	waveState.zombiesSpawned += 1

	-- notify clients
	ZombieSpawnedRemote:FireAllClients({
		zombieType = zombieType,
		position = spawnCF.Position,
	})
end

--------------------------------------------------
-- Wave Lifecycle
--------------------------------------------------

OnZombieDied = function(model: Model, zombieType: string)
	-- stop AI
	local zombieData = activeZombies[model]
	if zombieData then
		ZombieAI.StopAI(zombieData)
	end

	waveState.zombiesAlive -= 1
	waveState.zombiesRemaining -= 1

	-- delayed release back to pool (gives time for dissolve effect)
	task.delay(ZombieConfig.DespawnDelay, function()
		ReleaseZombie(model, zombieType)
	end)

	-- check if round is complete
	if waveState.zombiesRemaining <= 0 and waveState.isActive then
		EndRound()
	end
end

EndRound = function()
	waveState.isActive = false
	waveState.restPhase = true
	local round = waveState.round

	WaveCompletedRemote:FireAllClients({
		round = round,
	})

	-- rest period with countdown
	local restDuration = WaveConfig.GetRestDuration(round)
	task.spawn(function()
		for remaining = restDuration, 1, -1 do
			WaveCountdownRemote:FireAllClients({
				secondsLeft = remaining,
				nextRound = round + 1,
			})
			task.wait(1)
		end
		StartRound(round + 1)
	end)
end

StartRound = function(round: number)
	-- refresh spawn points in case new ones were added
	DiscoverSpawnPoints()

	waveState.round = round
	waveState.playerCount = #Players:GetPlayers()
	waveState.totalZombiesForRound = WaveConfig.GetZombieCount(round, waveState.playerCount)
	waveState.zombiesRemaining = waveState.totalZombiesForRound
	waveState.zombiesAlive = 0
	waveState.zombiesSpawned = 0
	waveState.isActive = true
	waveState.restPhase = false

	WaveStartedRemote:FireAllClients({
		round = round,
		totalZombies = waveState.totalZombiesForRound,
	})

	-- spawn coroutine
	task.spawn(function()
		local spawnDelay = WaveConfig.GetSpawnDelay(round)
		local maxAlive = WaveConfig.GetMaxAlive(waveState.playerCount)
		local typeWeights = WaveConfig.GetZombieTypeWeights(round)

		-- boss logic: spawn one boss as last zombie on milestone rounds
		local shouldSpawnBoss = (round >= 10 and round % 5 == 0)

		while waveState.zombiesSpawned < waveState.totalZombiesForRound and waveState.isActive do
			-- wait if at max alive cap
			while waveState.zombiesAlive >= maxAlive and waveState.isActive do
				task.wait(0.5)
			end

			if not waveState.isActive then
				break
			end

			-- pick zombie type
			local zombieType: string
			local isLastZombie = waveState.zombiesSpawned == waveState.totalZombiesForRound - 1
			if shouldSpawnBoss and isLastZombie then
				zombieType = "Boss"
			else
				zombieType = WaveConfig.PickZombieType(typeWeights)
			end

			SpawnZombie(zombieType, round)
			task.wait(spawnDelay)
		end
	end)
end

--------------------------------------------------
-- WaveStateSync (client can request current state)
--------------------------------------------------

WaveStateSyncRemote.OnServerInvoke = function(_player: Player)
	return {
		round = waveState.round,
		zombiesRemaining = waveState.zombiesRemaining,
		zombiesAlive = waveState.zombiesAlive,
		totalZombiesForRound = waveState.totalZombiesForRound,
		isActive = waveState.isActive,
		restPhase = waveState.restPhase,
	}
end

--------------------------------------------------
-- Zone Unlock Listener
--------------------------------------------------

-- when a zone door is opened, activate spawn points in that zone
local function OnZoneUnlocked(zoneName: string)
	if typeof(zoneName) ~= "string" or zoneName == "" then
		return
	end
	unlockedZones[zoneName] = true
	RefreshActiveSpawns()
	print("[ZombieSpawner] Zone unlocked:", zoneName, "| Active spawns:", #spawnPoints)
end

-- listen for the ZoneUnlockedEvent (created by ZoneDoorService)
task.spawn(function()
	local zoneEvent = ServerScriptService:WaitForChild("ZoneUnlockedEvent", 10) :: BindableEvent?
	if zoneEvent then
		zoneEvent.Event:Connect(OnZoneUnlocked)
	end
end)

--------------------------------------------------
-- Game Start
--------------------------------------------------

-- initialize systems
ZombieDamage.Initialize()
InitializePool()
DiscoverSpawnPoints()

-- start the game when first player joins
Players.PlayerAdded:Connect(function(_player)
	if not gameStarted then
		gameStarted = true
		task.wait(5) -- grace period before first wave
		StartRound(1)
	end
end)

-- handle players already in game (studio testing)
if #Players:GetPlayers() > 0 and not gameStarted then
	gameStarted = true
	task.delay(5, function()
		StartRound(1)
	end)
end
