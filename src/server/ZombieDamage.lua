--!strict

-- server module: zombie health, damage processing, death handling, rewards
-- bridge between GunServer and zombie system via BindableFunction

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieConfig = require(ReplicatedStorage.Modules.Zombies.ZombieConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local ZombieDamage = {}

-- remotes (lazy loaded)
local ZombieDiedRemote: RemoteEvent? = nil
local DamageDealtRemote: RemoteEvent? = nil
local GunHitRemote: RemoteEvent? = nil
local PlayerDamagedRemote: RemoteEvent? = nil

local initialized = false

--------------------------------------------------
-- Initialization
--------------------------------------------------

-- creates the bindable function that GunServer calls when a bullet hits a zombie
function ZombieDamage.Initialize()
	if initialized then
		return
	end
	initialized = true

	ZombieDiedRemote = RemoteService.GetRemote("ZombieDied") :: RemoteEvent
	DamageDealtRemote = RemoteService.GetRemote("DamageDealt") :: RemoteEvent
	GunHitRemote = RemoteService.GetRemote("GunHit") :: RemoteEvent
	PlayerDamagedRemote = RemoteService.GetRemote("PlayerDamaged") :: RemoteEvent

	-- create bindable for GunServer to invoke on zombie hits
	local existing = ServerScriptService:FindFirstChild("ZombieDamageBindable")
	if existing then
		existing:Destroy()
	end

	local damageBindable = Instance.new("BindableFunction")
	damageBindable.Name = "ZombieDamageBindable"
	damageBindable.Parent = ServerScriptService

	damageBindable.OnInvoke = function(
		attacker: Player,
		zombieModel: Model,
		damage: number,
		isHeadshot: boolean,
		hitPosition: Vector3
	): number
		return ZombieDamage.ApplyDamage(attacker, zombieModel, damage, isHeadshot, hitPosition)
	end
end

--------------------------------------------------
-- Damage Application
--------------------------------------------------

-- check if Insta-Kill powerup is active (via PowerupService bindable)
local function IsInstaKillActive(): boolean
	local bindable = ServerScriptService:FindFirstChild("PowerupQueryBindable") :: BindableFunction?
	if not bindable then
		return false
	end
	local success, result = pcall(function()
		return bindable:Invoke("IsInstaKill")
	end)
	return success and result == true
end

-- check if Double Points powerup is active
local function IsDoublePointsActive(): boolean
	local bindable = ServerScriptService:FindFirstChild("PowerupQueryBindable") :: BindableFunction?
	if not bindable then
		return false
	end
	local success, result = pcall(function()
		return bindable:Invoke("IsDoublePoints")
	end)
	return success and result == true
end

-- apply damage to a zombie, returns remaining health
function ZombieDamage.ApplyDamage(
	attacker: Player,
	zombieModel: Model,
	damage: number,
	isHeadshot: boolean,
	hitPosition: Vector3
): number
	local humanoid = zombieModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	-- Insta-Kill: any hit kills the zombie instantly
	if IsInstaKillActive() then
		damage = humanoid.Health + 1
	end

	humanoid:TakeDamage(damage)
	local remainingHealth = humanoid.Health

	-- update healthbar
	local healthbarGui = zombieModel:FindFirstChild("HealthbarGui") :: BillboardGui?
	if healthbarGui then
		local maxHP = healthbarGui:GetAttribute("MaxHealth") or humanoid.MaxHealth
		local ratio = math.clamp(remainingHealth / maxHP, 0, 1)
		local bg = healthbarGui:FindFirstChild("Background")
		if bg then
			local fill = bg:FindFirstChild("Fill") :: Frame?
			if fill then
				fill.Size = UDim2.new(ratio, 0, 1, 0)
			end
		end
	end

	-- send hit confirmation to attacker (reuses existing gun hit marker system)
	if GunHitRemote then
		(GunHitRemote :: RemoteEvent):FireClient(attacker, {
			damage = damage,
			killed = remainingHealth <= 0,
			headshot = isHeadshot,
		})
	end

	-- send floating damage number to attacker
	if DamageDealtRemote then
		(DamageDealtRemote :: RemoteEvent):FireClient(attacker, {
			damage = damage,
			position = hitPosition,
			isHeadshot = isHeadshot,
			isCritical = false,
			isZombie = true,
		})
	end

	return remainingHealth
end

--------------------------------------------------
-- Ragdoll
--------------------------------------------------

-- converts a zombie to ragdoll: destroys Motor6Ds, replaces with
-- BallSocketConstraints so limbs go limp, enables CanCollide on all parts
local function RagdollZombie(zombieModel: Model)
	for _, descendant in zombieModel:GetDescendants() do
		if descendant:IsA("Motor6D") then
			-- replace with BallSocketConstraint for floppy ragdoll
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 and part1 then
				local att0 = Instance.new("Attachment")
				att0.Name = "RagdollAtt0_" .. descendant.Name
				att0.CFrame = descendant.C0
				att0.Parent = part0

				local att1 = Instance.new("Attachment")
				att1.Name = "RagdollAtt1_" .. descendant.Name
				att1.CFrame = descendant.C1
				att1.Parent = part1

				local constraint = Instance.new("BallSocketConstraint")
				constraint.Name = "RagdollConstraint_" .. descendant.Name
				constraint.Attachment0 = att0
				constraint.Attachment1 = att1
				constraint.LimitsEnabled = true
				constraint.UpperAngle = 45
				constraint.Parent = part0
			end

			descendant:Destroy()
		end
	end

	-- enable CanCollide on all parts so the body rests on the ground
	for _, descendant in zombieModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = true
		end
	end
end

--------------------------------------------------
-- Death Handling
--------------------------------------------------

-- connect death handler for a zombie, calls onDeathCallback when zombie dies
function ZombieDamage.ConnectZombieDeath(
	zombieModel: Model,
	zombieType: string,
	onDeathCallback: () -> ()
)
	local humanoid = zombieModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local stats = ZombieConfig.Zombies[zombieType]
	if not stats then
		return
	end

	humanoid.Died:Connect(function()
		-- find who killed this zombie via creator tag (set by GunServer)
		local creator = humanoid:FindFirstChild("creator")
		local killer: Player? = nil
		if creator and creator:IsA("ObjectValue") and creator.Value then
			killer = creator.Value :: Player
		end

		-- award coins to killer (Double Points doubles reward)
		if killer then
			local coinReward = stats.CoinReward
			if IsDoublePointsActive() then
				coinReward *= 2
			end

			local coinEvent = ServerScriptService:FindFirstChild("AddCoinsEvent") :: BindableEvent?
			if coinEvent then
				coinEvent:Fire(killer, coinReward)
			end
		end

		-- notify PowerupService for potential drop
		local dropEvent = ServerScriptService:FindFirstChild("PowerupDropEvent") :: BindableEvent?
		if dropEvent then
			local deathPos = Vector3.zero
			if zombieModel.PrimaryPart then
				deathPos = zombieModel.PrimaryPart.Position
			end
			dropEvent:Fire(deathPos)
		end

		-- handle exploder AoE
		if stats.ExplodesOnDeath then
			ZombieDamage.HandleExplosion(zombieModel, stats)
		end

		-- ragdoll: break joints so body goes limp and flops over
		RagdollZombie(zombieModel)

		-- notify all clients for fade-out effect
		if ZombieDiedRemote then
			local position = Vector3.zero
			if zombieModel.PrimaryPart then
				position = zombieModel.PrimaryPart.Position
			end

			(ZombieDiedRemote :: RemoteEvent):FireAllClients({
				zombieModel = zombieModel,
				zombieType = zombieType,
				position = position,
				exploded = stats.ExplodesOnDeath,
			})
		end

		-- callback to spawner for wave tracking + pool return
		onDeathCallback()
	end)
end

--------------------------------------------------
-- Exploder AoE
--------------------------------------------------

-- damages nearby players when an exploder dies
function ZombieDamage.HandleExplosion(zombieModel: Model, stats: ZombieConfig.ZombieStats)
	local rootPart = zombieModel.PrimaryPart
	if not rootPart then
		return
	end

	local position = rootPart.Position
	local radius = stats.ExplosionRadius or 15
	local explosionDamage = stats.ExplosionDamage or 50

	-- damage nearby players with linear falloff
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		-- skip downed players (invulnerable while downed)
		if player:GetAttribute("IsDowned") then
			continue
		end

		local playerRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not playerRoot then
			continue
		end

		local dist = (playerRoot.Position - position).Magnitude
		if dist > radius then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		-- linear falloff: full damage at center, 0 at edge
		local damageFactor = 1 - (dist / radius)
		local finalDamage = math.floor(explosionDamage * damageFactor)

		humanoid:TakeDamage(finalDamage)

		-- notify the damaged player
		if PlayerDamagedRemote then
			(PlayerDamagedRemote :: RemoteEvent):FireClient(player, {
				damage = finalDamage,
				source = "Exploder",
				zombieType = "Exploder",
			})
		end
	end

	-- visual explosion (physics disabled, damage handled above)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
end

return ZombieDamage
