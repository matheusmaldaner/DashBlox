--!strict
-- AudioService - Centralized audio playback service
-- Provides functions to play sounds with proper 3D spatialization

local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local AudioConfig = require(script.Parent.AudioConfig)

local AudioService = {}

-- Track if sounds have been preloaded
local soundsPreloaded = false

--------------------------------------------------
-- Sound Pool Management
--------------------------------------------------

-- Pool of reusable Sound instances to prevent memory leaks
local soundPool: { Sound } = {}
local MAX_POOL_SIZE = 50
local inPool: { [Sound]: boolean } = {}

-- Active sounds (for stopping)
local activeSounds: { [string]: Sound } = {}

-- Get a sound from pool or create new
local function getPooledSound(): Sound
	if #soundPool > 0 then
		local sound = table.remove(soundPool) :: Sound
		inPool[sound] = nil
		return sound
	end
	return Instance.new("Sound")
end

-- Return sound to pool
local function returnToPool(sound: Sound)
	if inPool[sound] then
		return
	end

	inPool[sound] = true
	local parent = sound.Parent
	sound:Stop()
	sound.Parent = nil
	sound.SoundId = ""
	sound.Volume = 1
	sound.PlaybackSpeed = 1
	sound.Looped = false

	if parent and parent:IsA("Attachment") then
		parent:Destroy()
	end

	if #soundPool < MAX_POOL_SIZE then
		table.insert(soundPool, sound)
	else
		inPool[sound] = nil
		sound:Destroy()
	end
end

--------------------------------------------------
-- Sound Variation Helpers
--------------------------------------------------

-- Add slight pitch variation for natural sound
local function getRandomPitch(): number
	return 0.95 + math.random() * 0.1 -- Range: 0.95 to 1.05
end

-- Add slight volume variation
local function getRandomVolumeVariation(): number
	return 0.9 + math.random() * 0.2 -- Range: 0.9 to 1.1 (±10%)
end

--------------------------------------------------
-- Sound Preloading
--------------------------------------------------

-- Collect all sound IDs from config for preloading
local function collectAllSoundIds(): { string }
	local soundIds: { string } = {}
	local seen: { [string]: boolean } = {}

	local function addSound(id: string)
		if id and id ~= "" and id ~= "rbxassetid://0" and not seen[id] then
			seen[id] = true
			table.insert(soundIds, id)
		end
	end

	-- Weapons
	for _, weaponSounds in AudioConfig.Weapons do
		for _, soundId in weaponSounds do
			addSound(soundId)
		end
	end

	-- Building
	for _, value in AudioConfig.Building do
		if type(value) == "string" then
			addSound(value)
		elseif type(value) == "table" then
			for _, soundId in value do
				addSound(soundId)
			end
		end
	end

	-- Movement
	for _, value in AudioConfig.Movement do
		if type(value) == "string" then
			addSound(value)
		elseif type(value) == "table" then
			for _, soundId in value do
				addSound(soundId)
			end
		end
	end

	-- Combat
	for _, soundId in AudioConfig.Combat do
		addSound(soundId)
	end

	-- UI
	for _, soundId in AudioConfig.UI do
		addSound(soundId)
	end

	-- Pickaxe
	for _, soundId in AudioConfig.Pickaxe do
		addSound(soundId)
	end

	-- Zombies
	for _, soundId in AudioConfig.Zombies do
		addSound(soundId)
	end

	return soundIds
end

-- Preload all audio assets to prevent first-play delay
function AudioService.PreloadSounds()
	if soundsPreloaded then
		return
	end

	local soundIds = collectAllSoundIds()
	local assets: { Instance } = {}

	for _, soundId in soundIds do
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		table.insert(assets, sound)
	end

	-- Preload asynchronously
	task.spawn(function()
		ContentProvider:PreloadAsync(assets)
		soundsPreloaded = true
		print("[AudioService] Preloaded " .. #assets .. " sound assets")

		-- Cleanup temporary sound instances
		for _, asset in assets do
			asset:Destroy()
		end
	end)
end

--------------------------------------------------
-- Core Sound Functions
--------------------------------------------------

-- Play a non-positional (2D) sound - for UI and self-sounds
function AudioService.PlayLocalSound(category: string, soundName: string, volume: number?): Sound?
	local soundId: string?

	-- Resolve sound ID from category and name
	if category == "Weapons" then
		-- soundName format: "AR.fire" or just use direct lookup
		local parts = string.split(soundName, ".")
		if #parts == 2 then
			soundId = AudioConfig.GetWeaponSound(parts[1], parts[2])
		end
	elseif category == "Building" then
		local parts = string.split(soundName, ".")
		if #parts == 2 then
			soundId = AudioConfig.GetBuildingSound(parts[1], parts[2])
		else
			soundId = AudioConfig.GetBuildingSound(soundName, nil)
		end
	elseif category == "Movement" then
		soundId = AudioConfig.Movement[soundName]
	elseif category == "Combat" then
		soundId = AudioConfig.Combat[soundName]
	elseif category == "UI" then
		soundId = AudioConfig.UI[soundName]
	elseif category == "Pickaxe" then
		soundId = AudioConfig.Pickaxe[soundName]
	elseif category == "Zombies" then
		soundId = AudioConfig.Zombies[soundName]
	end

	if not soundId or soundId == "rbxassetid://0" then
		return nil -- Placeholder sound, skip
	end

	local sound = getPooledSound()
	sound.SoundId = soundId
	sound.Volume = volume or AudioConfig.DefaultVolumes[category] or 0.5
	sound.Parent = SoundService

	sound:Play()

	-- Auto-cleanup when done
	sound.Ended:Once(function()
		returnToPool(sound)
	end)

	return sound
end

-- Play a 3D positional sound at a specific position
function AudioService.Play3DSound(category: string, soundName: string, position: Vector3, range: number?): Sound?
	local soundId: string?

	-- Resolve sound ID
	if category == "Weapons" then
		local parts = string.split(soundName, ".")
		if #parts == 2 then
			soundId = AudioConfig.GetWeaponSound(parts[1], parts[2])
		end
	elseif category == "Building" then
		local parts = string.split(soundName, ".")
		if #parts == 2 then
			soundId = AudioConfig.GetBuildingSound(parts[1], parts[2])
		else
			soundId = AudioConfig.GetBuildingSound(soundName, nil)
		end
	elseif category == "Movement" then
		if soundName == "footstep" then
			-- Default footstep
			soundId = AudioConfig.Movement.footstep.Default
		else
			soundId = AudioConfig.Movement[soundName]
		end
	elseif category == "Combat" then
		soundId = AudioConfig.Combat[soundName]
	elseif category == "Pickaxe" then
		soundId = AudioConfig.Pickaxe[soundName]
	elseif category == "Zombies" then
		soundId = AudioConfig.Zombies[soundName]
	end

	if not soundId or soundId == "rbxassetid://0" then
		return nil -- Placeholder sound, skip
	end

	-- Create attachment at position for 3D audio
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	local sound = getPooledSound()
	sound.SoundId = soundId
	sound.Volume = AudioConfig.DefaultVolumes[category] or 0.5
	sound.RollOffMode = AudioConfig.SpatialSettings.rollOffMode
	sound.RollOffMinDistance = AudioConfig.SpatialSettings.rollOffMinDistance
	sound.RollOffMaxDistance = range or AudioConfig.SpatialSettings.rollOffMaxDistance
	sound.Parent = attachment

	sound:Play()

	-- Cleanup when done
	sound.Ended:Once(function()
		returnToPool(sound)
		if attachment.Parent then
			attachment:Destroy()
		end
	end)

	return sound
end

-- Generic play sound function with optional position
function AudioService.PlaySound(category: string, soundName: string, position: Vector3?, volume: number?): Sound?
	if position then
		local sound = AudioService.Play3DSound(category, soundName, position)
		if sound and volume then
			sound.Volume = volume
		end
		return sound
	else
		return AudioService.PlayLocalSound(category, soundName, volume)
	end
end

-- Play a sound directly from a sound ID
-- Set applyVariation to true for sounds that benefit from pitch/volume variation
function AudioService.PlaySoundId(
	soundId: string,
	position: Vector3?,
	volume: number?,
	range: number?,
	applyVariation: boolean?
): Sound?
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then
		return nil
	end

	local sound = getPooledSound()
	sound.SoundId = soundId

	-- Apply volume with optional variation
	local baseVolume = volume or 0.5
	if applyVariation then
		sound.Volume = baseVolume * getRandomVolumeVariation()
		sound.PlaybackSpeed = getRandomPitch()
	else
		sound.Volume = baseVolume
	end

	if position then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = position
		attachment.Parent = workspace.Terrain

		sound.RollOffMode = AudioConfig.SpatialSettings.rollOffMode
		sound.RollOffMinDistance = AudioConfig.SpatialSettings.rollOffMinDistance
		sound.RollOffMaxDistance = range or AudioConfig.SpatialSettings.rollOffMaxDistance
		sound.Parent = attachment

		sound.Ended:Once(function()
			returnToPool(sound)
			if attachment.Parent then
				attachment:Destroy()
			end
		end)
	else
		-- Non-positional: parent directly to SoundService for fastest playback
		sound.Parent = SoundService
		sound.Ended:Once(function()
			returnToPool(sound)
		end)
	end

	sound:Play()
	return sound
end

--------------------------------------------------
-- Named Sound Management (for stopping)
--------------------------------------------------

-- Play a sound with a unique key for later stopping
function AudioService.PlayNamedSound(
	key: string,
	category: string,
	soundName: string,
	looped: boolean?,
	volume: number?
): Sound?
	-- Stop existing sound with same key
	AudioService.StopNamedSound(key)

	local sound = AudioService.PlayLocalSound(category, soundName, volume)
	if sound then
		sound.Looped = looped or false
		activeSounds[key] = sound

		if not looped then
			sound.Ended:Once(function()
				if activeSounds[key] == sound then
					activeSounds[key] = nil
				end
			end)
		end
	end

	return sound
end

-- Play a sound by soundId with a unique key for later stopping
function AudioService.PlayNamedSoundId(
	key: string,
	soundId: string,
	position: Vector3?,
	volume: number?,
	range: number?,
	applyVariation: boolean?
): Sound?
	AudioService.StopNamedSound(key)

	local sound = AudioService.PlaySoundId(soundId, position, volume, range, applyVariation)
	if sound then
		activeSounds[key] = sound
		sound.Ended:Once(function()
			if activeSounds[key] == sound then
				activeSounds[key] = nil
			end
		end)
	end

	return sound
end

-- Stop a named sound
function AudioService.StopNamedSound(key: string)
	local sound = activeSounds[key]
	if sound then
		returnToPool(sound)
		activeSounds[key] = nil
	end
end

-- Stop sound by category and name (stops all matching)
function AudioService.StopSound(category: string, soundName: string)
	local key = category .. "." .. soundName
	AudioService.StopNamedSound(key)
end

--------------------------------------------------
-- Weapon Sound Helpers
--------------------------------------------------

-- Play weapon fire sound (for other players - 3D positioned)
function AudioService.PlayWeaponFire(weaponName: string, position: Vector3?): Sound?
	local soundId = AudioConfig.GetWeaponSound(weaponName, "fire")
	return AudioService.PlaySoundId(
		soundId,
		position,
		AudioConfig.DefaultVolumes.Weapons,
		AudioConfig.SpatialSettings.weaponRollOffMaxDistance,
		true -- apply pitch variation for natural sound
	)
end

-- Play weapon fire for local player (optimized - no 3D positioning)
function AudioService.PlayWeaponFireLocal(weaponName: string): Sound?
	local soundId = AudioConfig.GetWeaponSound(weaponName, "fire")
	return AudioService.PlaySoundId(
		soundId,
		nil, -- no position = direct to SoundService = faster
		AudioConfig.DefaultVolumes.Weapons,
		nil,
		true -- apply pitch variation
	)
end

-- Play weapon reload sound
function AudioService.PlayWeaponReload(weaponName: string): Sound?
	local soundId = AudioConfig.GetWeaponSound(weaponName, "reload")
	return AudioService.PlaySoundId(soundId, nil, AudioConfig.DefaultVolumes.Weapons, nil, false)
end

-- Play empty clip sound
function AudioService.PlayWeaponEmpty(weaponName: string): Sound?
	local soundId = AudioConfig.GetWeaponSound(weaponName, "empty")
	return AudioService.PlaySoundId(soundId, nil, AudioConfig.DefaultVolumes.Weapons * 0.7, nil, false)
end

-- Play weapon switch sound
function AudioService.PlayWeaponSwitch(weaponName: string): Sound?
	local soundId = AudioConfig.GetWeaponSound(weaponName, "switch")
	return AudioService.PlaySoundId(soundId, nil, AudioConfig.DefaultVolumes.Weapons * 0.1, nil, false)
end

--------------------------------------------------
-- Building Sound Helpers
--------------------------------------------------

-- Play building place sound
function AudioService.PlayBuildPlace(material: string, position: Vector3?): Sound?
	local soundId = AudioConfig.GetBuildingSound("place", material)
	return AudioService.PlaySoundId(soundId, position, AudioConfig.DefaultVolumes.Building, nil, false)
end

-- Play building destroy sound
function AudioService.PlayBuildDestroy(material: string, position: Vector3): Sound?
	local soundId = AudioConfig.GetBuildingSound("destroy", material)
	return AudioService.PlaySoundId(soundId, position, AudioConfig.DefaultVolumes.Building * 1.2, nil, false)
end

-- Play edit sound
function AudioService.PlayEditConfirm(): Sound?
	local soundId = AudioConfig.Building.edit.confirm
	return AudioService.PlaySoundId(soundId, nil, AudioConfig.DefaultVolumes.Building, nil, false)
end

--------------------------------------------------
-- Combat Sound Helpers
--------------------------------------------------

-- Play hit marker sound
function AudioService.PlayHitMarker(isHeadshot: boolean?): Sound?
	local soundName = isHeadshot and "headshot" or "hitMarker"
	return AudioService.PlayLocalSound("Combat", soundName, AudioConfig.DefaultVolumes.Combat)
end

-- Play kill sound
function AudioService.PlayKillSound(): Sound?
	return AudioService.PlayLocalSound("Combat", "kill", AudioConfig.DefaultVolumes.Combat)
end

-- Play low health heartbeat (looped)
function AudioService.StartLowHealthWarning(): Sound?
	return AudioService.PlayNamedSound(
		"lowHealthHeartbeat",
		"Combat",
		"lowHealthHeartbeat",
		true, -- looped
		AudioConfig.DefaultVolumes.Combat * 0.8
	)
end

-- Stop low health heartbeat
function AudioService.StopLowHealthWarning()
	AudioService.StopNamedSound("lowHealthHeartbeat")
end

--------------------------------------------------
-- Zombie Sound Helpers
--------------------------------------------------

-- play zombie hit sound at position (flesh impact or headshot)
function AudioService.PlayZombieHit(position: Vector3, isHeadshot: boolean?): Sound?
	local soundName = if isHeadshot then "hitHeadshot" else "hitFlesh"

	-- randomly use alternate flesh sound for variation
	if not isHeadshot and math.random() > 0.5 then
		soundName = "hitFleshAlt"
	end

	local soundId = AudioConfig.GetZombieSound(soundName)
	local range = AudioConfig.SpatialSettings.zombieRollOffMaxDistance

	local sound = AudioService.PlaySoundId(
		soundId,
		position,
		AudioConfig.DefaultVolumes.Zombies,
		range,
		true -- pitch/volume variation for natural feel
	)

	-- headshots get a higher pitch for a snappier feel
	if sound and isHeadshot then
		sound.PlaybackSpeed = 1.3 + math.random() * 0.2
	end

	return sound
end

-- play zombie death sound at position
function AudioService.PlayZombieDeath(position: Vector3, zombieType: string?): Sound?
	local soundName = "deathGroan"

	if zombieType == "Exploder" then
		soundName = "deathExploder"
	elseif zombieType == "Boss" then
		soundName = "deathBoss"
	end

	local soundId = AudioConfig.GetZombieSound(soundName)
	local range = AudioConfig.SpatialSettings.zombieRollOffMaxDistance

	local sound = AudioService.PlaySoundId(
		soundId,
		position,
		AudioConfig.DefaultVolumes.Zombies * 1.2, -- deaths are slightly louder
		range,
		false -- we apply custom pitch below
	)

	-- apply type-specific pitch to differentiate sounds
	if sound then
		if zombieType == "Boss" then
			sound.PlaybackSpeed = 0.55 -- very deep for boss
		elseif zombieType == "Exploder" then
			sound.PlaybackSpeed = 1.3 -- higher pitch for explosive feel
		elseif zombieType == "Fast" then
			sound.PlaybackSpeed = 1.15 -- slightly higher for fast zombies
		elseif zombieType == "Tank" then
			sound.PlaybackSpeed = 0.75 -- deeper for tanks
		else
			-- normal zombie: slight random variation
			sound.PlaybackSpeed = 0.85 + math.random() * 0.2
		end
	end

	return sound
end

--------------------------------------------------
-- Footstep Helpers
--------------------------------------------------

-- Play footstep based on floor material (for other players - 3D positioned)
-- Enemy footsteps are louder for competitive awareness
function AudioService.PlayFootstep(floorMaterial: Enum.Material, position: Vector3?, isSprinting: boolean?): Sound?
	local soundId = AudioConfig.GetFootstepSound(floorMaterial)
	local baseVolume = AudioConfig.DefaultVolumes.Movement
	local competitive = AudioConfig.CompetitiveSettings

	-- Apply competitive multipliers for enemy footsteps
	local volume = baseVolume * competitive.enemyFootstepVolumeMultiplier
	if isSprinting then
		volume = volume * competitive.sprintFootstepVolumeMultiplier
	end

	local sound = AudioService.PlaySoundId(
		soundId,
		position,
		volume,
		AudioConfig.SpatialSettings.footstepRollOffMaxDistance,
		true -- apply variation
	)

	-- Use the competitive min distance for clearer nearby footsteps
	if sound then
		sound.RollOffMinDistance = AudioConfig.SpatialSettings.footstepRollOffMinDistance or 5
	end

	return sound
end

-- Play footstep for local player (optimized - no 3D positioning needed)
function AudioService.PlayFootstepLocal(floorMaterial: Enum.Material): Sound?
	local soundId = AudioConfig.GetFootstepSound(floorMaterial)
	return AudioService.PlaySoundId(
		soundId,
		nil, -- no position = faster playback
		AudioConfig.DefaultVolumes.Movement,
		nil,
		true -- apply pitch/volume variation for natural sound
	)
end

--------------------------------------------------
-- Initialize
--------------------------------------------------

-- Auto-preload sounds when module loads
AudioService.PreloadSounds()

return AudioService
