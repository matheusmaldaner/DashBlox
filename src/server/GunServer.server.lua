--!strict

-- server-side gun combat: shot validation, raycasting, hit detection,
-- damage application for zombies and players
-- weapon model attachment and loadout management are in GunModelManager and GunLoadout

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local GunUtility = require(ReplicatedStorage.Modules.Guns.GunUtility)
local PackAPunchConfig = require(ReplicatedStorage.Modules.Guns.PackAPunchConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)
local GunModelManager = require(script.Parent.GunModelManager)
local GunDamageProcessor = require(script.Parent.GunDamageProcessor)

-- ZombieDamage bindable (created by ZombieSpawner/ZombieDamage)
local ZombieDamageBindable: BindableFunction? = nil

local function GetZombieDamageBindable(): BindableFunction?
	if ZombieDamageBindable then
		return ZombieDamageBindable
	end
	ZombieDamageBindable = ServerScriptService:FindFirstChild("ZombieDamageBindable") :: BindableFunction?
	return ZombieDamageBindable
end

-- Remotes
local FireGunRemote = RemoteService.GetRemote("FireGun") :: RemoteEvent
local GunFiredRemote = RemoteService.GetRemote("GunFired") :: RemoteEvent
local EquipGunRemote = RemoteService.GetRemote("EquipGun") :: RemoteEvent
local UnequipGunRemote = RemoteService.GetRemote("UnequipGun") :: RemoteEvent
local ReloadGunRemote = RemoteService.GetRemote("ReloadGun") :: RemoteEvent

local EQUIPPED_GUN_NAME = GunModelManager.EQUIPPED_GUN_NAME

-- Player states tracked on server
type PlayerGunState = {
	currentGun: string?,
	ammo: number,
	lastFireTime: number,
}

local PlayerStates: { [Player]: PlayerGunState } = {}

--------------------------------------------------
-- Player State Management
--------------------------------------------------

local function InitializePlayer(player: Player)
	PlayerStates[player] = {
		currentGun = nil,
		ammo = 0,
		lastFireTime = 0,
	}
end

local function CleanupPlayer(player: Player)
	PlayerStates[player] = nil
end

--------------------------------------------------
-- Gun State Handlers
--------------------------------------------------

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
	state.lastFireTime = 0

	-- Check if weapon is Pack-a-Punched (doubled mag)
	local magSize = gunStats.MagazineSize
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		local tool = backpack:FindFirstChild(gunName)
		if tool and tool:GetAttribute("PackAPunched") then
			magSize = magSize * PackAPunchConfig.MagazineSizeMultiplier
		end
	end
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("GunName") == gunName then
				if child:GetAttribute("PackAPunched") then
					magSize = magSize * PackAPunchConfig.MagazineSizeMultiplier
				end
				break
			end
		end
	end
	state.ammo = magSize

	GunModelManager.AttachGunModel(player, gunName)
end

local function HandleUnequipGun(player: Player)
	local state = PlayerStates[player]
	if not state then
		return
	end

	state.currentGun = nil
	state.ammo = 0

	local character = player.Character
	if character then
		GunModelManager.RemoveEquippedGun(character)
	end
end

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

	local magSize = gunStats.MagazineSize
	local character = player.Character
	if character then
		local equippedGun = character:FindFirstChild(EQUIPPED_GUN_NAME)
		if equippedGun and equippedGun:GetAttribute("PackAPunched") then
			magSize = magSize * PackAPunchConfig.MagazineSizeMultiplier
		end
	end
	state.ammo = magSize
end

--------------------------------------------------
-- Shot Validation
--------------------------------------------------

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

	local origin = data.origin
	if typeof(origin) ~= "Vector3" then
		return false, "Invalid origin"
	end

	local maxOriginDistance = 20
	if (origin - head.Position).Magnitude > maxOriginDistance then
		return false, "Origin too far from player"
	end

	-- Validate fire rate (DoubleTap perk doubles fire rate)
	local effectiveFireRate = gunStats.FireRate
	if player:GetAttribute("HasDoubleTap") then
		effectiveFireRate *= 2.0
	end
	local minFireInterval = 60 / effectiveFireRate
	local currentTime = tick()
	if currentTime - state.lastFireTime < minFireInterval * 0.9 then
		return false, "Firing too fast"
	end

	if state.ammo <= 0 then
		return false, "No ammo"
	end

	local direction = data.direction
	if typeof(direction) ~= "Vector3" then
		return false, "Invalid direction"
	end

	return true, nil
end

--------------------------------------------------
-- Hit Processing
--------------------------------------------------

-- helper: apply PaP multiplier if equipped weapon is upgraded
local function GetPaPDamage(player: Player, baseDamage: number): number
	local character = player.Character
	if character then
		local equippedGun = character:FindFirstChild(EQUIPPED_GUN_NAME)
		if equippedGun and equippedGun:GetAttribute("PackAPunched") then
			return baseDamage * PackAPunchConfig.DamageMultiplier
		end
	end
	return baseDamage
end

-- helper: set creator tag on zombie for kill attribution
local function SetZombieCreator(zombieModel: Model, player: Player)
	local zombieHumanoid = zombieModel:FindFirstChildOfClass("Humanoid")
	if zombieHumanoid then
		local existingCreator = zombieHumanoid:FindFirstChild("creator")
		if existingCreator then
			existingCreator:Destroy()
		end
		local creatorTag = Instance.new("ObjectValue")
		creatorTag.Name = "creator"
		creatorTag.Value = player
		creatorTag.Parent = zombieHumanoid
	end
end

-- process a single pellet hit (used by both regular guns and shotguns)
local function ProcessPelletHit(
	player: Player,
	gunStats: GunConfig.GunStats,
	origin: Vector3,
	result: RaycastResult?,
	playerDamageAccumulator: { [Player]: { damage: number, headshot: boolean, position: Vector3 } }?
): (Player?, number, boolean)
	if not result then
		return nil, 0, false
	end

	local hitPart = result.Instance
	local hitPlayer = GunDamageProcessor.GetPlayerFromPart(hitPart)

	if not hitPlayer then
		-- check if pellet hit a zombie
		local hitModel = hitPart:FindFirstAncestorOfClass("Model")
		if hitModel and hitModel:GetAttribute("IsZombie") then
			local distance = (result.Position - origin).Magnitude
			local isHeadshot = GunDamageProcessor.IsHeadshot(hitPart)
			local damage = GunUtility.CalculateDamage(gunStats, distance, isHeadshot)
			damage = GetPaPDamage(player, damage)

			local zombieBindable = GetZombieDamageBindable()
			if zombieBindable then
				SetZombieCreator(hitModel, player)
				zombieBindable:Invoke(player, hitModel, damage, isHeadshot, result.Position)
			end
		end
		return nil, 0, false
	end

	if hitPlayer == player then
		return nil, 0, false
	end

	if GunDamageProcessor.ArePlayersOnSameTeam(player, hitPlayer) then
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

	local distance = (result.Position - origin).Magnitude
	local isHeadshot = GunDamageProcessor.IsHeadshot(hitPart)
	local damage = GunUtility.CalculateDamage(gunStats, distance, isHeadshot)

	if playerDamageAccumulator then
		local existing = playerDamageAccumulator[hitPlayer]
		if existing then
			existing.damage = existing.damage + damage
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

--------------------------------------------------
-- Shot Processing
--------------------------------------------------

local function ProcessShot(player: Player, data: any)
	local valid, reason = ValidateShot(player, data)
	if not valid then
		warn("Invalid shot from", player.Name, ":", reason)
		return
	end

	local state = PlayerStates[player]
	local gunName = state.currentGun :: string
	local gunStats = GunConfig.Guns[gunName]

	state.lastFireTime = tick()
	state.ammo -= 1

	local origin: Vector3 = data.origin
	local baseDirection: Vector3 = data.direction.Unit
	local raycastParams = GunDamageProcessor.CreateRaycastParams(player.Character)

	-- skip accessories in raycast
	local accessoryExcludes: { Instance } = {}
	local accessoryResult = workspace:Raycast(origin, baseDirection * gunStats.MaxRange, raycastParams)
	while accessoryResult and accessoryResult.Instance do
		local accessory = accessoryResult.Instance:FindFirstAncestorOfClass("Accessory")
		if not accessory then break end
		table.insert(accessoryExcludes, accessory)
		raycastParams = GunDamageProcessor.CreateRaycastParams(player.Character, accessoryExcludes)
		accessoryResult = workspace:Raycast(origin, baseDirection * gunStats.MaxRange, raycastParams)
	end

	local startPos = GunModelManager.GetMuzzleWorldPosition(player, origin)
	local pelletCount = GunConfig.ShotgunPellets[gunName]

	if pelletCount and pelletCount > 1 then
		-- SHOTGUN: multiple pellets
		local playerDmgAcc: { [Player]: { damage: number, headshot: boolean, position: Vector3 } } = {}
		local tracerData: { { endPos: Vector3, hitPlayerId: number? } } = {}

		for _ = 1, pelletCount do
			local pelletDir = GunUtility.ApplySpreadToDirection(baseDirection, gunStats.BaseSpread)
			local result = workspace:Raycast(origin, pelletDir * gunStats.MaxRange, raycastParams)
			local endPos: Vector3
			local hitPlayerId: number? = nil

			if result then
				endPos = result.Position
				local hitPlayer = GunDamageProcessor.GetPlayerFromPart(result.Instance)
				if hitPlayer then hitPlayerId = hitPlayer.UserId end
				ProcessPelletHit(player, gunStats, origin, result, playerDmgAcc)
			else
				endPos = origin + pelletDir * gunStats.MaxRange
			end
			table.insert(tracerData, { endPos = endPos, hitPlayerId = hitPlayerId })
		end

		GunFiredRemote:FireAllClients({
			shooterId = player.UserId,
			gunName = gunName,
			startPos = startPos,
			endPos = tracerData[1].endPos,
			hitPlayerId = tracerData[1].hitPlayerId,
			pelletTracers = tracerData,
		})

		for hitPlayer, damageInfo in playerDmgAcc do
			GunDamageProcessor.ApplyDamageToPlayer(
				player, hitPlayer, damageInfo.damage, damageInfo.headshot, damageInfo.position, gunName
			)
		end
	else
		-- REGULAR GUN: single raycast
		local result = workspace:Raycast(origin, baseDirection * gunStats.MaxRange, raycastParams)
		local endPos = if result then result.Position else origin + baseDirection * gunStats.MaxRange
		local hitPlayerId: number? = nil
		if result then
			local hp = GunDamageProcessor.GetPlayerFromPart(result.Instance)
			if hp then hitPlayerId = hp.UserId end
		end

		GunFiredRemote:FireAllClients({
			shooterId = player.UserId, gunName = gunName,
			startPos = startPos, endPos = endPos, hitPlayerId = hitPlayerId,
		})

		if not result then return end

		local hitPart = result.Instance
		local hitPlayer = GunDamageProcessor.GetPlayerFromPart(hitPart)

		if not hitPlayer then
			local hitModel = hitPart:FindFirstAncestorOfClass("Model")
			if hitModel and hitModel:GetAttribute("IsZombie") then
				local zombieBindable = GetZombieDamageBindable()
				if zombieBindable then
					local distance = (result.Position - origin).Magnitude
					local isHeadshot = GunDamageProcessor.IsHeadshot(hitPart)
					local damage = GunUtility.CalculateDamage(gunStats, distance, isHeadshot)
					damage = GetPaPDamage(player, damage)
					SetZombieCreator(hitModel, player)
					zombieBindable:Invoke(player, hitModel, damage, isHeadshot, result.Position)
				end
			end
			return
		end

		if hitPlayer == player then return end
		if GunDamageProcessor.ArePlayersOnSameTeam(player, hitPlayer) then return end

		local hitCharacter = hitPlayer.Character
		if not hitCharacter then return end
		local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		local distance = (result.Position - origin).Magnitude
		local isHeadshot = GunDamageProcessor.IsHeadshot(hitPart)
		local damage = GunUtility.CalculateDamage(gunStats, distance, isHeadshot)

		GunDamageProcessor.ApplyDamageToPlayer(
			player, hitPlayer, damage, isHeadshot, result.Position, gunName
		)
	end
end

--------------------------------------------------
-- Event Connections
--------------------------------------------------

FireGunRemote.OnServerEvent:Connect(ProcessShot)
EquipGunRemote.OnServerEvent:Connect(HandleEquipGun)
UnequipGunRemote.OnServerEvent:Connect(HandleUnequipGun)
ReloadGunRemote.OnServerEvent:Connect(HandleReloadGun)

--------------------------------------------------
-- Player Lifecycle (state only, loadout is in GunLoadout.server.lua)
--------------------------------------------------

Players.PlayerAdded:Connect(function(player)
	InitializePlayer(player)
end)

Players.PlayerRemoving:Connect(CleanupPlayer)

for _, player in Players:GetPlayers() do
	InitializePlayer(player)
end
