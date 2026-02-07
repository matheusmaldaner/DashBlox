--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local GunUtility = require(ReplicatedStorage.Modules.Guns.GunUtility)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

-- TakeDamage bindable (created by PlayerStatsService)
local TakeDamageBindable: BindableFunction? = nil

local function GetTakeDamageBindable(): BindableFunction?
	if TakeDamageBindable then
		return TakeDamageBindable
	end
	TakeDamageBindable = ServerScriptService:FindFirstChild("TakeDamageBindable") :: BindableFunction?
	return TakeDamageBindable
end

-- MatchDamageEvent bindable (created by MatchService) for stat tracking
local MatchDamageEvent: BindableEvent? = nil

local function GetMatchDamageEvent(): BindableEvent?
	if MatchDamageEvent then
		return MatchDamageEvent
	end
	MatchDamageEvent = ServerScriptService:FindFirstChild("MatchDamageEvent") :: BindableEvent?
	return MatchDamageEvent
end

-- Remotes
local FireGunRemote = RemoteService.GetRemote("FireGun") :: RemoteEvent
local GunHitRemote = RemoteService.GetRemote("GunHit") :: RemoteEvent
local GunFiredRemote = RemoteService.GetRemote("GunFired") :: RemoteEvent
local DamageDealtRemote = RemoteService.GetRemote("DamageDealt") :: RemoteEvent
local EquipGunRemote = RemoteService.GetRemote("EquipGun") :: RemoteEvent
local UnequipGunRemote = RemoteService.GetRemote("UnequipGun") :: RemoteEvent
local ReloadGunRemote = RemoteService.GetRemote("ReloadGun") :: RemoteEvent
local GiveLoadoutRemote = RemoteService.GetRemote("GiveLoadout") :: RemoteEvent
local PickaxePlayerDamageRemote = RemoteService.GetRemote("PickaxePlayerDamage") :: RemoteEvent

local EQUIPPED_GUN_NAME = "EquippedGun"
local PICKAXE_PLAYER_DAMAGE = 20 -- damage dealt to players with pickaxe
local PICKAXE_RANGE = 20 -- max distance for pickaxe hit validation

-- Match service bindable (for team checks)
local MatchServiceBindable: BindableFunction? = nil

local function GetMatchServiceBindable(): BindableFunction?
	if MatchServiceBindable then
		return MatchServiceBindable
	end
	MatchServiceBindable = ServerScriptService:FindFirstChild("MatchServiceBindable") :: BindableFunction?
	return MatchServiceBindable
end

-- Get player's team ID from match service (returns nil if not in match)
local function GetPlayerTeamId(player: Player): number?
	local bindable = GetMatchServiceBindable()
	if not bindable then
		return nil
	end

	local matchActive = bindable:Invoke("IsMatchActive")
	if not matchActive then
		return nil
	end

	-- Query team ID through GetPlayerTeamId action
	local teamId = bindable:Invoke("GetPlayerTeamId", player.UserId)
	return teamId
end

-- Check if two players are on the same team (for friendly fire prevention)
local function ArePlayersOnSameTeam(player1: Player, player2: Player): boolean
	local team1 = GetPlayerTeamId(player1)
	local team2 = GetPlayerTeamId(player2)

	-- If either player has no team, they're not on the same team (allow damage)
	if team1 == nil or team2 == nil then
		return false
	end

	return team1 == team2
end

-- Persistent stat tracking (from PlayerDataService)
local AddDamageDealtEvent: BindableEvent? = nil

local function GetAddDamageDealtEvent(): BindableEvent?
	if AddDamageDealtEvent then
		return AddDamageDealtEvent
	end
	AddDamageDealtEvent = ServerScriptService:FindFirstChild("AddDamageDealtEvent") :: BindableEvent?
	return AddDamageDealtEvent
end

-- Default loadout for free roam / testing
local DEFAULT_LOADOUT = { "AR", "PumpShotgun", "SMG", "Sniper" }

-- Player states tracked on server
type PlayerGunState = {
	currentGun: string?,
	ammo: number,
	lastFireTime: number,
}

local PlayerStates: { [Player]: PlayerGunState } = {}

-- Raycast params (excludes all characters, will be updated per-shot)
local function CreateRaycastParams(excludeCharacter: Model?, extraExcludes: { Instance }?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local filterList: { Instance } = {}
	if excludeCharacter then
		table.insert(filterList, excludeCharacter)
	end
	if extraExcludes then
		for _, instance in extraExcludes do
			table.insert(filterList, instance)
		end
	end
	params.FilterDescendantsInstances = filterList

	return params
end

-- Check if a part belongs to a player's character
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

-- Check if hit is a headshot
local function IsHeadshot(part: BasePart): boolean
	return part.Name == "Head"
end

-- Initialize player state
local function InitializePlayer(player: Player)
	PlayerStates[player] = {
		currentGun = nil,
		ammo = 0,
		lastFireTime = 0,
	}
end

local function GetRightHand(character: Model): BasePart?
	return (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
end

local function GetMuzzleWorldPosition(player: Player, fallbackOrigin: Vector3): Vector3
	local character = player.Character
	if not character then
		return fallbackOrigin
	end

	local gunModel = character:FindFirstChild(EQUIPPED_GUN_NAME)
	if gunModel then
		local muzzle = gunModel:FindFirstChild("Muzzle", true)
		if muzzle then
			if muzzle:IsA("Attachment") then
				return muzzle.WorldPosition
			elseif muzzle:IsA("BasePart") then
				return muzzle.Position
			end
		end
	end

	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		return head.Position
	end

	return fallbackOrigin
end

local function RemoveEquippedGun(character: Model)
	local existing = character:FindFirstChild(EQUIPPED_GUN_NAME)
	if existing then
		existing:Destroy()
	end
end

local function AttachGunModel(player: Player, gunName: string)
	local character = player.Character
	if not character then
		return
	end

	local rightHand = GetRightHand(character)
	if not rightHand then
		return
	end

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		return
	end

	local weaponsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not weaponsFolder then
		return
	end
	weaponsFolder = weaponsFolder:FindFirstChild("Weapons")
	if not weaponsFolder then
		return
	end

	local modelName = gunStats.ModelName or gunName
	local weaponAsset = weaponsFolder:FindFirstChild(modelName) :: Model?
	if not weaponAsset then
		warn("Weapon not found:", modelName)
		return
	end

	RemoveEquippedGun(character)

	local weaponModel = weaponAsset:Clone()
	weaponModel.Name = EQUIPPED_GUN_NAME
	weaponModel:SetAttribute("GunName", gunName)

	for _, descendant in weaponModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end

	local weaponPart = weaponModel.PrimaryPart or weaponModel:FindFirstChildWhichIsA("BasePart")
	if not weaponPart then
		weaponModel:Destroy()
		return
	end

	local weld = Instance.new("Motor6D")
	weld.Name = "WeaponWeld"
	weld.Part0 = rightHand
	weld.Part1 = weaponPart :: BasePart
	-- Offset positions gun in hand, rotate 90 degrees to the right so barrel faces forward
	weld.C0 = CFrame.new(0, -0.2, -0.5) * CFrame.Angles(math.rad(-90), math.rad(-90), math.rad(0))
	weld.Parent = rightHand

	weaponModel.Parent = character
end

-- Handle equip gun
local function HandleEquipGun(player: Player, gunName: string)
	local state = PlayerStates[player]
	if not state then
		InitializePlayer(player)
		state = PlayerStates[player]
	end

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		warn("Invalid gun:", gunName)
		return
	end

	state.currentGun = gunName
	state.ammo = gunStats.MagazineSize
	state.lastFireTime = 0

	AttachGunModel(player, gunName)
end

-- Handle unequip gun
local function HandleUnequipGun(player: Player)
	local state = PlayerStates[player]
	if not state then
		return
	end

	state.currentGun = nil
	state.ammo = 0

	local character = player.Character
	if character then
		RemoveEquippedGun(character)
	end
end

-- Handle reload gun
local function HandleReloadGun(player: Player)
	local state = PlayerStates[player]
	if not state then
		return
	end

	local gunName = state.currentGun
	if not gunName then
		return
	end

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		return
	end

	-- Refill ammo to magazine size
	state.ammo = gunStats.MagazineSize
end

-- Cleanup player state
local function CleanupPlayer(player: Player)
	PlayerStates[player] = nil
end

-- Validate a shot from client
local function ValidateShot(player: Player, data: any): (boolean, string?)
	local character = player.Character
	if not character then
		return false, "No character"
	end

	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return false, "No head"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "Player dead"
	end

	local state = PlayerStates[player]
	if not state then
		return false, "No player state"
	end

	local gunName = state.currentGun
	if not gunName then
		return false, "No gun equipped"
	end

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		return false, "Invalid gun"
	end

	-- Validate origin is near player's head (allow for third-person camera offset)
	local origin = data.origin
	if typeof(origin) ~= "Vector3" then
		return false, "Invalid origin"
	end

	local maxOriginDistance = 20 -- studs tolerance for third-person camera
	if (origin - head.Position).Magnitude > maxOriginDistance then
		return false, "Origin too far from player"
	end

	-- Validate fire rate
	local minFireInterval = 60 / gunStats.FireRate
	local currentTime = tick()
	if currentTime - state.lastFireTime < minFireInterval * 0.9 then -- 10% tolerance
		return false, "Firing too fast"
	end

	-- Validate ammo
	if state.ammo <= 0 then
		return false, "No ammo"
	end

	-- Validate direction
	local direction = data.direction
	if typeof(direction) ~= "Vector3" then
		return false, "Invalid direction"
	end

	return true, nil
end

-- Process a single pellet hit (used by both regular guns and shotguns)
local function ProcessPelletHit(
	player: Player,
	gunStats: GunConfig.GunStats,
	origin: Vector3,
	result: RaycastResult?,
	playerDamageAccumulator: { [Player]: { damage: number, headshot: boolean, position: Vector3 } }?,
	buildingDamageAccumulator: { [BasePart]: number }?
): (Player?, number, boolean)
	if not result then
		return nil, 0, false
	end

	local hitPart = result.Instance
	local hitPlayer = GetPlayerFromPart(hitPart)

	if not hitPlayer then
		-- Check if hit a building piece
		if buildingDamageAccumulator and hitPart:IsA("BasePart") then
			buildingDamageAccumulator[hitPart] = (buildingDamageAccumulator[hitPart] or 0) + gunStats.BaseDamage
		end
		return nil, 0, false
	end

	-- Don't allow self-damage
	if hitPlayer == player then
		return nil, 0, false
	end

	-- Don't allow friendly fire (same team)
	if ArePlayersOnSameTeam(player, hitPlayer) then
		return nil, 0, false
	end

	local hitCharacter = hitPlayer.Character
	if not hitCharacter then
		return nil, 0, false
	end

	local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, 0, false
	end

	-- Calculate damage for this pellet
	local distance = (result.Position - origin).Magnitude
	local isHeadshot = IsHeadshot(hitPart)
	local damage = GunUtility.CalculateDamage(gunStats, distance, isHeadshot)

	-- Accumulate damage if using accumulator (shotguns)
	if playerDamageAccumulator then
		local existing = playerDamageAccumulator[hitPlayer]
		if existing then
			existing.damage = existing.damage + damage
			-- Track if ANY pellet was a headshot
			if isHeadshot then
				existing.headshot = true
			end
		else
			playerDamageAccumulator[hitPlayer] = {
				damage = damage,
				headshot = isHeadshot,
				position = result.Position,
			}
		end
	end

	return hitPlayer, damage, isHeadshot
end

-- Apply accumulated damage to a player (handles kill attribution, damage events, etc.)
local function ApplyDamageToPlayer(
	attacker: Player,
	victim: Player,
	damage: number,
	isHeadshot: boolean,
	hitPosition: Vector3,
	gunName: string
): number
	local hitCharacter = victim.Character
	if not hitCharacter then
		return 0
	end

	local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	-- Set creator tag for kill attribution (used by MatchService)
	local existingCreator = humanoid:FindFirstChild("creator")
	if existingCreator then
		existingCreator:Destroy()
	end
	local creatorTag = Instance.new("ObjectValue")
	creatorTag.Name = "creator"
	creatorTag.Value = attacker
	creatorTag.Parent = humanoid

	-- Store weapon and headshot info for kill feed
	humanoid:SetAttribute("LastDamageWeapon", gunName)
	humanoid:SetAttribute("LastDamageHeadshot", isHeadshot)

	-- Auto-cleanup after 5 seconds (in case player doesn't die)
	task.delay(5, function()
		if creatorTag and creatorTag.Parent then
			creatorTag:Destroy()
		end
		if humanoid and humanoid.Parent then
			humanoid:SetAttribute("LastDamageWeapon", nil)
			humanoid:SetAttribute("LastDamageHeadshot", nil)
		end
	end)

	-- Apply damage through PlayerStatsService (shield absorbs first)
	local bindable = GetTakeDamageBindable()
	local remainingHealth = 0
	if bindable then
		remainingHealth = bindable:Invoke(victim, damage, attacker)
	else
		-- Fallback to direct damage if bindable not ready
		humanoid:TakeDamage(damage)
		remainingHealth = humanoid.Health
	end

	-- Notify attacker of hit (for hit markers)
	GunHitRemote:FireClient(attacker, {
		damage = damage,
		killed = remainingHealth <= 0,
		headshot = isHeadshot,
	})

	-- Send damage info for floating damage numbers
	DamageDealtRemote:FireClient(attacker, {
		damage = damage,
		position = hitPosition,
		isHeadshot = isHeadshot,
		isCritical = false,
		victimUserId = victim.UserId,
	})

	-- Track persistent damage stats
	local damageEvent = GetAddDamageDealtEvent()
	if damageEvent then
		damageEvent:Fire(attacker, damage)
	end

	-- Track match damage stats (for post-match UI)
	local matchDamageEvent = GetMatchDamageEvent()
	if matchDamageEvent then
		matchDamageEvent:Fire(attacker.UserId, damage)
	end

	return remainingHealth
end

-- Process a shot from client
local function ProcessShot(player: Player, data: any)
	-- Validate shot
	local valid, reason = ValidateShot(player, data)
	if not valid then
		warn("Invalid shot from", player.Name, ":", reason)
		return
	end

	local state = PlayerStates[player]
	local gunName = state.currentGun :: string
	local gunStats = GunConfig.Guns[gunName]

	-- Update state
	state.lastFireTime = tick()
	state.ammo -= 1

	local origin: Vector3 = data.origin
	local baseDirection: Vector3 = data.direction.Unit
	local raycastParams = CreateRaycastParams(player.Character)

	local accessoryExcludes: { Instance } = {}
	local accessoryResult = workspace:Raycast(origin, baseDirection * gunStats.MaxRange, raycastParams)
	while accessoryResult and accessoryResult.Instance do
		local accessory = accessoryResult.Instance:FindFirstAncestorOfClass("Accessory")
		if not accessory then
			break
		end
		table.insert(accessoryExcludes, accessory)
		raycastParams = CreateRaycastParams(player.Character, accessoryExcludes)
		accessoryResult = workspace:Raycast(origin, baseDirection * gunStats.MaxRange, raycastParams)
	end

	local startPos = GetMuzzleWorldPosition(player, origin)

	-- Check if this is a shotgun (has pellet count)
	local pelletCount = GunConfig.ShotgunPellets[gunName]

	if pelletCount and pelletCount > 1 then
		-- SHOTGUN: Fire multiple pellets with spread
		local playerDamageAccumulator: { [Player]: { damage: number, headshot: boolean, position: Vector3 } } = {}
		local buildingDamageAccumulator: { [BasePart]: number } = {}
		local tracerData: { { endPos: Vector3, hitPlayerId: number? } } = {}

		for _ = 1, pelletCount do
			-- Apply spread to each pellet (server-authoritative)
			local pelletDirection = GunUtility.ApplySpreadToDirection(baseDirection, gunStats.BaseSpread)
			local result = workspace:Raycast(origin, pelletDirection * gunStats.MaxRange, raycastParams)

			local endPos: Vector3
			local hitPlayerId: number? = nil

			if result then
				endPos = result.Position
				local hitPlayer = GetPlayerFromPart(result.Instance)
				if hitPlayer then
					hitPlayerId = hitPlayer.UserId
				end

				-- Process this pellet hit (accumulates damage)
				ProcessPelletHit(player, gunStats, origin, result, playerDamageAccumulator, buildingDamageAccumulator)
			else
				endPos = origin + pelletDirection * gunStats.MaxRange
			end

			table.insert(tracerData, { endPos = endPos, hitPlayerId = hitPlayerId })
		end

		-- Send all tracer data to clients (for visual feedback)
		GunFiredRemote:FireAllClients({
			shooterId = player.UserId,
			gunName = gunName,
			startPos = startPos,
			endPos = tracerData[1].endPos, -- Primary tracer
			hitPlayerId = tracerData[1].hitPlayerId,
			pelletTracers = tracerData, -- All pellet end positions
		})

		-- Apply accumulated damage to each hit player
		for hitPlayer, damageInfo in playerDamageAccumulator do
			ApplyDamageToPlayer(player, hitPlayer, damageInfo.damage, damageInfo.headshot, damageInfo.position, gunName)
		end

		-- Apply accumulated damage to buildings
		local DamageBuildingBindable = ServerScriptService:FindFirstChild("DamageBuildingBindable")
		if DamageBuildingBindable and DamageBuildingBindable:IsA("BindableFunction") then
			local totalBuildingDamage = 0
			for buildingPart, damage in buildingDamageAccumulator do
				local wasBuilding = DamageBuildingBindable:Invoke(buildingPart, damage)
				if wasBuilding then
					totalBuildingDamage = totalBuildingDamage + damage
				end
			end

			if totalBuildingDamage > 0 then
				GunHitRemote:FireClient(player, {
					damage = totalBuildingDamage,
					killed = false,
					headshot = false,
					hitBuilding = true,
				})
			end
		end
	else
		-- REGULAR GUN: Single raycast
		local result = workspace:Raycast(origin, baseDirection * gunStats.MaxRange, raycastParams)
		local endPos: Vector3
		if result then
			endPos = result.Position
		else
			endPos = origin + baseDirection * gunStats.MaxRange
		end

		local hitPlayerId: number? = nil
		if result and result.Instance then
			local hitPlayer = GetPlayerFromPart(result.Instance)
			if hitPlayer then
				hitPlayerId = hitPlayer.UserId
			end
		end

		GunFiredRemote:FireAllClients({
			shooterId = player.UserId,
			gunName = gunName,
			startPos = startPos,
			endPos = endPos,
			hitPlayerId = hitPlayerId,
		})

		if not result then
			return -- Missed
		end

		-- Check if hit a player
		local hitPart = result.Instance
		local hitPlayer = GetPlayerFromPart(hitPart)

		if not hitPlayer then
			-- Check if hit a building piece
			local DamageBuildingBindable = ServerScriptService:FindFirstChild("DamageBuildingBindable")
			if DamageBuildingBindable and DamageBuildingBindable:IsA("BindableFunction") and hitPart:IsA("BasePart") then
				local wasBuilding = DamageBuildingBindable:Invoke(hitPart, gunStats.BaseDamage)
				if wasBuilding then
					GunHitRemote:FireClient(player, {
						damage = gunStats.BaseDamage,
						killed = false,
						headshot = false,
						hitBuilding = true,
					})
				end
			end
			return -- Hit environment or building
		end

		-- Don't allow self-damage
		if hitPlayer == player then
			return
		end

		-- Don't allow friendly fire (same team)
		if ArePlayersOnSameTeam(player, hitPlayer) then
			return
		end

		local hitCharacter = hitPlayer.Character
		if not hitCharacter then
			return
		end

		local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return -- Already dead
		end

		-- Calculate and apply damage
		local distance = (result.Position - origin).Magnitude
		local isHeadshot = IsHeadshot(hitPart)
		local damage = GunUtility.CalculateDamage(gunStats, distance, isHeadshot)

		ApplyDamageToPlayer(player, hitPlayer, damage, isHeadshot, result.Position, gunName)
	end
end

--------------------------------------------------
-- Pickaxe Player Damage Handler
--------------------------------------------------

local function HandlePickaxePlayerDamage(attacker: Player, data: any)
	-- Validate attacker
	local attackerChar = attacker.Character
	if not attackerChar then
		return
	end

	local attackerHumanoid = attackerChar:FindFirstChildOfClass("Humanoid")
	if not attackerHumanoid or attackerHumanoid.Health <= 0 then
		return
	end

	local attackerHRP = attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not attackerHRP then
		return
	end

	-- Validate target
	local targetPlayer = data.targetPlayer
	if not targetPlayer or typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then
		return
	end

	-- Can't hit yourself
	if targetPlayer == attacker then
		return
	end

	-- Check if on same team (no friendly fire with pickaxe)
	local attackerTeam = GetPlayerTeamId(attacker)
	local targetTeam = GetPlayerTeamId(targetPlayer)
	if attackerTeam and targetTeam and attackerTeam == targetTeam then
		return -- same team, no damage
	end

	local targetChar = targetPlayer.Character
	if not targetChar then
		return
	end

	local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		return
	end

	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetHRP then
		return
	end

	-- Validate distance
	local distance = (attackerHRP.Position - targetHRP.Position).Magnitude
	if distance > PICKAXE_RANGE then
		return
	end

	-- Apply damage via TakeDamageBindable
	local takeDamage = GetTakeDamageBindable()
	if takeDamage then
		takeDamage:Invoke(targetPlayer, PICKAXE_PLAYER_DAMAGE, attacker, false)
	end

	-- Fire damage event for attacker feedback
	DamageDealtRemote:FireClient(attacker, {
		damage = PICKAXE_PLAYER_DAMAGE,
		isHeadshot = false,
		targetPlayer = targetPlayer,
	})
end

-- Connect events
FireGunRemote.OnServerEvent:Connect(ProcessShot)
EquipGunRemote.OnServerEvent:Connect(HandleEquipGun)
UnequipGunRemote.OnServerEvent:Connect(HandleUnequipGun)
ReloadGunRemote.OnServerEvent:Connect(HandleReloadGun)
PickaxePlayerDamageRemote.OnServerEvent:Connect(HandlePickaxePlayerDamage)

-- Give default loadout when character spawns (for free roam / testing)
local function OnCharacterAdded(player: Player)
	-- Wait a moment for character to fully load
	task.wait(0.5)

	-- Give default loadout if not in a match (MatchService will override if in match)
	GiveLoadoutRemote:FireClient(player, DEFAULT_LOADOUT)
end

Players.PlayerAdded:Connect(function(player)
	InitializePlayer(player)

	-- Listen for character spawns
	player.CharacterAdded:Connect(function()
		OnCharacterAdded(player)
	end)

	-- Handle already spawned character
	if player.Character then
		OnCharacterAdded(player)
	end
end)

Players.PlayerRemoving:Connect(CleanupPlayer)

-- Initialize existing players (for Studio testing)
for _, player in Players:GetPlayers() do
	InitializePlayer(player)

	-- Set up character listener
	player.CharacterAdded:Connect(function()
		OnCharacterAdded(player)
	end)

	-- Handle already spawned character
	if player.Character then
		OnCharacterAdded(player)
	end
end
