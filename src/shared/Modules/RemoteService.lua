--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = {}

-- Remote registry: name -> type
local remoteRegistry: { [string]: string } = {
	-- Gun system
	["FireGun"] = "RemoteEvent",
	["GunHit"] = "RemoteEvent",
	["EquipGun"] = "RemoteEvent",
	["UnequipGun"] = "RemoteEvent",
	["ReloadGun"] = "RemoteEvent",
	["GiveLoadout"] = "RemoteEvent",
	["GunFired"] = "RemoteEvent",
	["ReloadAllWeapons"] = "RemoteEvent", -- reset all weapon ammo to full (round start)

	-- Sound system
	["PlaySound"] = "RemoteEvent",

	-- Player stats system (runtime)
	["PlayerStatsChanged"] = "RemoteEvent",
	["PlayerDied"] = "RemoteEvent",

	-- Player data system (persistent)
	["PlayerDataLoaded"] = "RemoteEvent",
	["PlayerDataUpdated"] = "RemoteEvent",

	-- Settings persistence
	["SaveSettings"] = "RemoteEvent", -- client -> server: save settings to profile
	["SettingsLoaded"] = "RemoteEvent", -- server -> client: settings from profile on join

	-- Match system
	["MatchStateChanged"] = "RemoteEvent",
	["GetMatchState"] = "RemoteFunction",
	["MatchScoreChanged"] = "RemoteEvent",
	["MatchRoundChanged"] = "RemoteEvent",
	["PlayerKilled"] = "RemoteEvent",
	["MatchEnded"] = "RemoteEvent",
	["OvertimeStarted"] = "RemoteEvent", -- round timer expired, overtime begins
	["RequestRespawn"] = "RemoteEvent",
	["JoinQueue"] = "RemoteEvent",
	["LeaveQueue"] = "RemoteEvent",
	["QueueStatusChanged"] = "RemoteEvent",
	["MatchFound"] = "RemoteEvent",
	["Announcer"] = "RemoteEvent", -- kill announcements (first blood, multi-kill, etc.)

	-- Storm/zone system
	["StormUpdate"] = "RemoteEvent", -- periodic zone state updates
	["StormDamage"] = "RemoteEvent", -- when player takes storm damage

	-- Ranking system
	["RankUpdated"] = "RemoteEvent",
	["TitleUpdated"] = "RemoteEvent", -- win-based title progression
	["GetLeaderboard"] = "RemoteFunction",
	["GetPlayerRank"] = "RemoteFunction",

	-- Progression system
	["XPGained"] = "RemoteEvent",
	["LevelUp"] = "RemoteEvent",
	["ProgressionUpdated"] = "RemoteEvent",
	["GetProgression"] = "RemoteFunction",

	-- Quest system
	["GetQuests"] = "RemoteFunction",
	["QuestProgress"] = "RemoteEvent",
	["QuestCompleted"] = "RemoteEvent",
	["QuestRewardClaimed"] = "RemoteEvent",
	["QuestsUpdated"] = "RemoteEvent",
	["ClaimQuestReward"] = "RemoteEvent",
	["SkipQuest"] = "RemoteEvent",

	-- Achievement system
	["GetAchievements"] = "RemoteFunction",
	["AchievementUnlocked"] = "RemoteEvent",
	["AchievementProgress"] = "RemoteEvent",
	["NearCompletion"] = "RemoteEvent", -- fires on match end when >80% progress

	-- Item/consumable system
	["UseItem"] = "RemoteEvent",
	["ItemUsed"] = "RemoteEvent",
	["ItemUseProgress"] = "RemoteEvent",
	["ItemUseCancelled"] = "RemoteEvent",
	["GiveItem"] = "RemoteEvent",
	["InventoryChanged"] = "RemoteEvent", -- full inventory sync
	["CancelItemUse"] = "RemoteEvent", -- client requests cancel (weapon switch, etc.)

	-- Loot/pickup system
	["LootPickedUp"] = "RemoteEvent", -- notify client of successful pickup
	["LootSpawned"] = "RemoteEvent", -- notify clients of new loot (for effects)

	-- Unified inventory system
	["DropItem"] = "RemoteEvent", -- client requests to drop equipped item
	["EquipSlot"] = "RemoteEvent", -- client requests to equip a specific slot

	-- Combat feedback
	["KillFeed"] = "RemoteEvent",
	["DamageDealt"] = "RemoteEvent",
	["DamageTaken"] = "RemoteEvent",

	-- Team/party system
	["TeamAssigned"] = "RemoteEvent", -- sent to player when assigned to a team
	["TeammateStatsChanged"] = "RemoteEvent", -- teammate health/shield updates
	["GetTeammates"] = "RemoteFunction", -- get current teammates info

	-- Teleportation/matchmaking
	["TeleportingToMatch"] = "RemoteEvent",
	["TeleportFailed"] = "RemoteEvent",
	["TeleportingToLobby"] = "RemoteEvent",

	-- Zombie system
	["ZombieSpawned"] = "RemoteEvent",   -- server -> all clients: zombie spawned
	["ZombieDied"] = "RemoteEvent",      -- server -> all clients: zombie died (dissolve)
	["ZombieDamaged"] = "RemoteEvent",   -- server -> attacker: damage feedback
	["PlayerDamaged"] = "RemoteEvent",   -- server -> victim: zombie attacked you
	["WaveStarted"] = "RemoteEvent",     -- server -> all clients: new wave beginning
	["WaveCompleted"] = "RemoteEvent",   -- server -> all clients: wave cleared
	["WaveCountdown"] = "RemoteEvent",   -- server -> all clients: rest period timer
	["WaveStateSync"] = "RemoteFunction", -- client -> server: request current wave state

	-- Mystery Box system
	["MysteryBoxOpened"] = "RemoteEvent",     -- server -> all clients: box opened, start cycling anim
	["MysteryBoxResult"] = "RemoteEvent",     -- server -> all clients: cycling done, reveal weapon
	["MysteryBoxPickedUp"] = "RemoteEvent",   -- server -> all clients: player grabbed the weapon
	["MysteryBoxExpired"] = "RemoteEvent",    -- server -> all clients: weapon sank back (not picked up)
	["MysteryBoxRelocate"] = "RemoteEvent",   -- server -> all clients: teddy bear, box moving
	["MysteryBoxReappear"] = "RemoteEvent",   -- server -> all clients: box appeared at new location

	-- Coin system
	["GiveTestCoins"] = "RemoteEvent",        -- client -> server: dev testing, give coins
	["CoinsChanged"] = "RemoteEvent",         -- server -> client: coin count updated

	-- Cosmetics/Locker system
	["GetCosmetics"] = "RemoteFunction", -- get player's cosmetic data
	["EquipCosmetic"] = "RemoteFunction", -- equip item (returns success)
	["UnequipCosmetic"] = "RemoteFunction", -- unequip item
	["SaveLoadout"] = "RemoteFunction", -- save loadout preset
	["LoadLoadout"] = "RemoteFunction", -- apply saved loadout
	["DeleteLoadout"] = "RemoteFunction", -- remove saved loadout
	["AddToWishlist"] = "RemoteFunction", -- add item to wishlist
	["RemoveFromWishlist"] = "RemoteFunction", -- remove from wishlist
	["PurchaseCosmetic"] = "RemoteFunction", -- buy with coins
	["CosmeticsUpdated"] = "RemoteEvent", -- notify client of cosmetic changes
}

-- Create or get Remotes folder
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

--------------------------------------------------
-- Remote Creation and Management
--------------------------------------------------
function RemoteService.GetRemote(remoteName: string): RemoteEvent | RemoteFunction
	local remoteType = remoteRegistry[remoteName]
	if not remoteType then
		error("Unknown remote: " .. remoteName)
	end

	local remote = Remotes:FindFirstChild(remoteName)
	if not remote then
		if remoteType == "RemoteEvent" then
			remote = Instance.new("RemoteEvent")
		elseif remoteType == "RemoteFunction" then
			remote = Instance.new("RemoteFunction")
		else
			error("Invalid remote type: " .. remoteType)
		end

		remote.Name = remoteName
		remote.Parent = Remotes
	end

	return remote :: RemoteEvent | RemoteFunction
end

function RemoteService.GetAllRemotes(): { [string]: RemoteEvent | RemoteFunction }
	local remotes = {}
	for remoteName, _ in pairs(remoteRegistry) do
		remotes[remoteName] = RemoteService.GetRemote(remoteName)
	end
	return remotes
end

-- Initialize all remotes at startup
function RemoteService.Initialize()
	for remoteName, _ in pairs(remoteRegistry) do
		RemoteService.GetRemote(remoteName)
	end
end

--------------------------------------------------
-- Rate Limiting Helper
--------------------------------------------------
function RemoteService.CreateRateLimiter(cooldownTime: number): ((Player) -> boolean, (Player) -> ())
	local debounceTable: { [string]: number } = {}

	local function checkLimit(player: Player): boolean
		local playerKey = tostring(player.UserId)
		local currentTime = tick()

		if debounceTable[playerKey] and (currentTime - debounceTable[playerKey]) < cooldownTime then
			return false -- Rate limited
		end

		debounceTable[playerKey] = currentTime
		return true -- Allowed
	end

	local function cleanup(player: Player)
		local playerKey = tostring(player.UserId)
		debounceTable[playerKey] = nil
	end

	return checkLimit, cleanup
end

-- Auto-initialize
RemoteService.Initialize()

return RemoteService
