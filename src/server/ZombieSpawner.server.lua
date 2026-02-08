--!strict

-- main zombie system entry point: clone-based spawner, object pooling,
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
local spawnPoints: { BasePart } = {}

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
-- Zombie Model Templates (cloned from ReplicatedStorage.Assets.Zombies)
--------------------------------------------------

local ZombieAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Zombies")

--------------------------------------------------
-- Healthbar Creator
--------------------------------------------------

local function CreateHealthbar(model: Model, maxHealth: number): BillboardGui
	local bbGui = Instance.new("BillboardGui")
	bbGui.Name = "HealthbarGui"
	bbGui.Size = UDim2.new(2.5, 0, 0.3, 0)
	bbGui.StudsOffset = Vector3.new(0, 3.5, 0)
	bbGui.AlwaysOnTop = true
	bbGui.MaxDistance = 60
	bbGui.ResetOnSpawn = false

	-- background bar (dark)
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	bg.Parent = bbGui

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0.5, 0)
	bgCorner.Parent = bg

	-- fill bar (red gradient)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	-- subtle gradient on the fill
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 50, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 20, 20)),
	})
	gradient.Rotation = 90
	gradient.Parent = fill

	-- store max health for ratio calculation
	bbGui:SetAttribute("MaxHealth", maxHealth)

	-- attach to the model's head or primary part
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		bbGui.Adornee = head
	end
	bbGui.Parent = model

	return bbGui
end

--------------------------------------------------
-- Animation Setup
--------------------------------------------------

local function SetupAnimations(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- ensure Animator exists
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- load walk animation
	local walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = ZombieConfig.Animations.Walk

	local walkTrack = animator:LoadAnimation(walkAnim)
	walkTrack.Priority = Enum.AnimationPriority.Movement
	walkTrack.Looped = true
	walkTrack:Play()

	-- store attack animation for later use (touch damage triggers it)
	local attackAnim = Instance.new("Animation")
	attackAnim.AnimationId = ZombieConfig.Animations.Attack
	attackAnim.Name = "ZombieAttackAnim"
	attackAnim.Parent = model
end

--------------------------------------------------
-- Clone-based Zombie Model Builder
--------------------------------------------------

local function CreateZombieModel(zombieType: string): Model
	local stats = ZombieConfig.Zombies[zombieType]

	-- determine which template model to clone
	local modelName = ZombieConfig.ModelName[zombieType] or "Zombie Normal"
	local template = ZombieAssets:FindFirstChild(modelName)
	if not template then
		warn("[ZombieSpawner] missing zombie template: " .. modelName)
		-- fallback to any available template
		template = ZombieAssets:GetChildren()[1]
	end

	local model = template:Clone()
	model.Name = "Zombie_" .. zombieType

	-- configure humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.WalkSpeed = stats.WalkSpeed
		humanoid.MaxHealth = stats.Health
		humanoid.Health = stats.Health
	end

	-- set collision group and store original state for pool reset
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Zombie"
			descendant:SetAttribute("OriginalSize", descendant.Size)
			descendant:SetAttribute("OriginalTransparency", descendant.Transparency)
			descendant:SetAttribute("OriginalColor", descendant.Color)
			descendant:SetAttribute("OriginalCanCollide", descendant.CanCollide)
		elseif descendant:IsA("Decal") then
			descendant:SetAttribute("OriginalTransparency", descendant.Transparency)
		end
	end

	-- identification tags
	model:SetAttribute("IsZombie", true)
	model:SetAttribute("ZombieType", zombieType)

	-- highlight: red outline only, no fill
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(200, 30, 30)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model

	-- healthbar
	CreateHealthbar(model, stats.Health)

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

	-- ragdolled models have their Motor6Ds destroyed and BallSocketConstraints
	-- added, making them impractical to restore. destroy and replace with a
	-- fresh clone for the pool.
	model:Destroy()

	local fresh = CreateZombieModel(zombieType)
	fresh.Parent = ZombieStorage

	local pool = zombiePool[zombieType]
	if pool then
		table.insert(pool, fresh)
	end
end

--------------------------------------------------
-- Spawn Points (CollectionService tagged parts)
--------------------------------------------------

local function DiscoverSpawnPoints()
	spawnPoints = CollectionService:GetTagged("ZombieSpawn") :: { BasePart }
	if #spawnPoints == 0 then
		warn("[ZombieSpawner] no parts tagged 'ZombieSpawn' found, zombies will spawn at origin")
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

	-- update healthbar max health for this round's scaling
	local healthbarGui = model:FindFirstChild("HealthbarGui") :: BillboardGui?
	if healthbarGui then
		healthbarGui:SetAttribute("MaxHealth", scaledHealth)
		local bg = healthbarGui:FindFirstChild("Background")
		if bg then
			local fill = bg:FindFirstChild("Fill") :: Frame?
			if fill then
				fill.Size = UDim2.new(1, 0, 1, 0)
			end
		end
	end

	model:PivotTo(spawnCF)
	model.Parent = workspace

	-- set up walk/attack animations
	SetupAnimations(model)

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

		while waveState.zombiesSpawned < waveState.totalZombiesForRound and waveState.isActive do
			-- wait if at max alive cap
			while waveState.zombiesAlive >= maxAlive and waveState.isActive do
				task.wait(0.5)
			end

			if not waveState.isActive then
				break
			end

			-- pick zombie type: boss is always the last zombie of every round
			local zombieType: string
			local isLastZombie = waveState.zombiesSpawned == waveState.totalZombiesForRound - 1
			if isLastZombie then
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
