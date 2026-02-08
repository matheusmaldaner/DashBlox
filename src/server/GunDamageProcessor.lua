--!strict

-- server module: player-vs-player damage application, team checks,
-- raycast helpers, and hit detection utilities

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local GunDamageProcessor = {}

-- lazy-loaded bindables
local TakeDamageBindable: BindableFunction? = nil
local MatchDamageEvent: BindableEvent? = nil
local AddDamageDealtEvent: BindableEvent? = nil
local MatchServiceBindable: BindableFunction? = nil

local function GetTakeDamageBindable(): BindableFunction?
	if TakeDamageBindable then return TakeDamageBindable end
	TakeDamageBindable = ServerScriptService:FindFirstChild("TakeDamageBindable") :: BindableFunction?
	return TakeDamageBindable
end

local function GetMatchDamageEvent(): BindableEvent?
	if MatchDamageEvent then return MatchDamageEvent end
	MatchDamageEvent = ServerScriptService:FindFirstChild("MatchDamageEvent") :: BindableEvent?
	return MatchDamageEvent
end

local function GetAddDamageDealtEvent(): BindableEvent?
	if AddDamageDealtEvent then return AddDamageDealtEvent end
	AddDamageDealtEvent = ServerScriptService:FindFirstChild("AddDamageDealtEvent") :: BindableEvent?
	return AddDamageDealtEvent
end

local function GetMatchServiceBindable(): BindableFunction?
	if MatchServiceBindable then return MatchServiceBindable end
	MatchServiceBindable = ServerScriptService:FindFirstChild("MatchServiceBindable") :: BindableFunction?
	return MatchServiceBindable
end

-- remotes for hit feedback
local GunHitRemote = RemoteService.GetRemote("GunHit") :: RemoteEvent
local DamageDealtRemote = RemoteService.GetRemote("DamageDealt") :: RemoteEvent

--------------------------------------------------
-- Team Checks
--------------------------------------------------

local function GetPlayerTeamId(player: Player): number?
	local bindable = GetMatchServiceBindable()
	if not bindable then return nil end
	local matchActive = bindable:Invoke("IsMatchActive")
	if not matchActive then return nil end
	return bindable:Invoke("GetPlayerTeamId", player.UserId)
end

function GunDamageProcessor.ArePlayersOnSameTeam(player1: Player, player2: Player): boolean
	local team1 = GetPlayerTeamId(player1)
	local team2 = GetPlayerTeamId(player2)
	if team1 == nil or team2 == nil then return false end
	return team1 == team2
end

--------------------------------------------------
-- Raycast + Hit Helpers
--------------------------------------------------

function GunDamageProcessor.CreateRaycastParams(
	excludeCharacter: Model?,
	extraExcludes: { Instance }?
): RaycastParams
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

function GunDamageProcessor.GetPlayerFromPart(part: BasePart): Player?
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then return nil end
	for _, p in Players:GetPlayers() do
		if p.Character == character then return p end
	end
	return nil
end

function GunDamageProcessor.IsHeadshot(part: BasePart): boolean
	return part.Name == "Head"
end

--------------------------------------------------
-- Apply Damage to Player (PvP)
--------------------------------------------------

function GunDamageProcessor.ApplyDamageToPlayer(
	attacker: Player,
	victim: Player,
	damage: number,
	isHeadshot: boolean,
	hitPosition: Vector3,
	gunName: string
): number
	local hitCharacter = victim.Character
	if not hitCharacter then return 0 end

	local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return 0 end

	-- kill attribution
	local existingCreator = humanoid:FindFirstChild("creator")
	if existingCreator then existingCreator:Destroy() end
	local creatorTag = Instance.new("ObjectValue")
	creatorTag.Name = "creator"
	creatorTag.Value = attacker
	creatorTag.Parent = humanoid

	humanoid:SetAttribute("LastDamageWeapon", gunName)
	humanoid:SetAttribute("LastDamageHeadshot", isHeadshot)

	task.delay(5, function()
		if creatorTag and creatorTag.Parent then creatorTag:Destroy() end
		if humanoid and humanoid.Parent then
			humanoid:SetAttribute("LastDamageWeapon", nil)
			humanoid:SetAttribute("LastDamageHeadshot", nil)
		end
	end)

	-- apply damage (shield system if available)
	local bindable = GetTakeDamageBindable()
	local remainingHealth = 0
	if bindable then
		remainingHealth = bindable:Invoke(victim, damage, attacker)
	else
		humanoid:TakeDamage(damage)
		remainingHealth = humanoid.Health
	end

	-- hit marker for attacker
	GunHitRemote:FireClient(attacker, {
		damage = damage,
		killed = remainingHealth <= 0,
		headshot = isHeadshot,
	})

	-- floating damage number
	DamageDealtRemote:FireClient(attacker, {
		damage = damage,
		position = hitPosition,
		isHeadshot = isHeadshot,
		isCritical = false,
		victimUserId = victim.UserId,
	})

	-- persistent stats
	local damageEvent = GetAddDamageDealtEvent()
	if damageEvent then damageEvent:Fire(attacker, damage) end

	-- match stats
	local matchDamageEvent = GetMatchDamageEvent()
	if matchDamageEvent then matchDamageEvent:Fire(attacker.UserId, damage) end

	return remainingHealth
end

return GunDamageProcessor
