--!strict
-- AudioConfig - Centralized audio configuration for all game sounds
-- Sound IDs sourced from Roblox audio library

local AudioConfig = {}

--------------------------------------------------
-- Sound ID Types
--------------------------------------------------

export type SoundCategory = "Weapons" | "Building" | "Movement" | "Combat" | "UI" | "Zombies"

--------------------------------------------------
-- Weapon Sounds (per weapon type)
-- Sources: robloxsong.com, musiccoder.com, rtrack.social
--------------------------------------------------

AudioConfig.Weapons = {
	-- Assault Rifle
	AR = {
		fire = "rbxassetid://9113198012", -- Assault Rifle 1 (SFX)
		reload = "rbxassetid://4604186785", -- Gun Reload Sound For Game
		empty = "rbxassetid://154255000", -- Empty clip click
		switch = "rbxassetid://624706518", -- Whoosh sound
	},
	-- Pump Shotgun
	PumpShotgun = {
		fire = "rbxassetid://4804954860", -- Fortnite Pump Shotgun Shooting
		reload = "rbxassetid://4604186785", -- Gun Reload Sound
		empty = "rbxassetid://154255000", -- Empty clip click
		switch = "rbxassetid://624706518", -- Whoosh sound
		pump = "rbxassetid://254833653", -- Shotgun Pump
	},
	-- SMG
	SMG = {
		fire = "rbxassetid://6224645687", -- Submachine Gun Shot
		reload = "rbxassetid://4604186785", -- Gun Reload Sound
		empty = "rbxassetid://154255000", -- Empty clip click
		switch = "rbxassetid://624706518", -- Whoosh sound
	},
	-- Tactical Shotgun
	TacticalShotgun = {
		fire = "rbxassetid://6770924452", -- Shotgun sound
		reload = "rbxassetid://4604186785", -- Gun Reload Sound
		empty = "rbxassetid://154255000", -- Empty clip click
		switch = "rbxassetid://624706518", -- Whoosh sound
	},
	-- Sniper Rifle
	Sniper = {
		fire = "rbxassetid://405384967", -- Sniper Sound Effect
		reload = "rbxassetid://4604186785", -- Gun Reload Sound
		empty = "rbxassetid://154255000", -- Empty clip click
		switch = "rbxassetid://624706518", -- Whoosh sound
		boltAction = "rbxassetid://6755647594", -- Sniper Rifle Bolt
	},
	-- Pistol
	Pistol = {
		fire = "rbxassetid://1674017283", -- Gun Shot Sound Revolver
		reload = "rbxassetid://4604186785", -- Gun Reload Sound
		empty = "rbxassetid://154255000", -- Empty clip click
		switch = "rbxassetid://624706518", -- Whoosh sound
	},
}

--------------------------------------------------
-- Building Sounds (per material)
--------------------------------------------------

AudioConfig.Building = {
	-- Place sounds by material
	place = {
		Wood = "rbxassetid://507863457",
		Stone = "rbxassetid://9064853890",
		Metal = "rbxassetid://9064974448",
	},
	-- Edit sounds
	edit = {
		confirm = "rbxassetid://876939830", -- Click confirm
		cancel = "rbxassetid://876939830", -- Click cancel
		select = "rbxassetid://876939830", -- Tile select
	},
	-- Destroy sounds by material
	destroy = {
		Wood = "rbxassetid://3398628813", -- wood splintering
		Stone = "rbxassetid://9064853890", -- stone crumbling
		Metal = "rbxassetid://9064974448", -- metal clanging
	},
	-- UI feedback
	rotate = "rbxassetid://876939830",
	select = "rbxassetid://876939830",
	invalid = "rbxassetid://876939830",
	outOfMaterials = "rbxassetid://9118823805",
}

--------------------------------------------------
-- Movement Sounds
-- Sources: DevForum footstep modules, robloxsong.com
--------------------------------------------------

AudioConfig.Movement = {
	-- Footstep sounds by surface material
	footstep = {
		Grass = "rbxassetid://9064714296", -- Grass footstep
		Wood = "rbxassetid://507863457", -- Wood impact
		Concrete = "rbxassetid://9064853890", -- Pebble/concrete footstep
		Metal = "rbxassetid://9064974448", -- Metal footstep
		Sand = "rbxassetid://9064714296", -- Similar to grass
		Fabric = "rbxassetid://9064714296", -- Soft footstep
		Plastic = "rbxasset://sounds/action_footsteps_plastic.mp3", -- Built-in plastic footstep
		Slate = "rbxassetid://9064853890", -- Stone-like
		Brick = "rbxassetid://9064853890", -- Hard surface
		Default = "rbxassetid://9064853890", -- Default footstep
	},
	-- Other movement sounds
	jump = "rbxassetid://8276741979", -- Woosh/Jump Sound Effect
	land = "rbxassetid://3626698892", -- Thud Sound Effect
	landHard = "rbxassetid://3626698892", -- Hard landing thud
	slide = "rbxassetid://2235655773", -- Swoosh Sound Effect
	crouch = "rbxassetid://624706518", -- Quiet whoosh
	sprint = "rbxassetid://0", -- placeholder (breathing)
}

--------------------------------------------------
-- Combat Sounds
-- Sources: robloxsong.com, musiccoder.com
--------------------------------------------------

AudioConfig.Combat = {
	hitMarker = "rbxassetid://5952120301", -- COD Hit Marker sound
	headshot = "rbxassetid://1129547534", -- MLG Hitmarker (distinct for headshot)
	kill = "rbxassetid://1507116849", -- Victory Sound Effect
	shieldBreak = "rbxassetid://3398628813", -- Breaking/shatter sound
	shieldHit = "rbxassetid://876939830", -- Shield absorb
	lowHealthHeartbeat = "rbxassetid://6724333590", -- Heartbeat Sound (Slow to fast)
	damaged = "rbxassetid://3626698892", -- Impact thud
	bulletWhiz = "rbxassetid://624706518", -- Bullet pass-by whoosh
}

--------------------------------------------------
-- Zombie Sounds
-- Hit feedback + death sounds for zombie combat
--------------------------------------------------

AudioConfig.Zombies = {
	-- hit feedback (3D at zombie position)
	hitFlesh = "rbxassetid://3626698892", -- meaty flesh impact thud
	hitFleshAlt = "rbxassetid://9064853890", -- alternate impact for variation
	hitHeadshot = "rbxassetid://3398628813", -- bone crack/crunch on headshot

	-- death sounds (3D at zombie position)
	deathGroan = "rbxassetid://1843977518", -- zombie groan/moan
	deathExploder = "rbxassetid://262562442", -- explosive death burst
	deathBoss = "rbxassetid://1843977518", -- deeper groan (pitched down via AudioService)

	-- headshot celebration (local, non-positional)
	headshotConfirm = "rbxassetid://1129547534", -- crisp ping for headshot kill
}

--------------------------------------------------
-- UI Sounds
--------------------------------------------------

AudioConfig.UI = {
	click = "rbxassetid://876939830",
	hover = "rbxassetid://876939830",
	queueStart = "rbxassetid://876939830",
	matchFound = "rbxassetid://1507116849", -- Victory fanfare for match found
	countdown = "rbxassetid://172905765", -- Short Beep - Heart rate Monitor
	roundStart = "rbxassetid://1507116849", -- Fanfare
	victory = "rbxassetid://1507116849", -- Victory Sound Effect
	defeat = "rbxassetid://876939830", -- Subdued click
	levelUp = "rbxassetid://1507116849", -- Celebration sound
	achievementUnlock = "rbxassetid://1507116849", -- Achievement jingle
	notification = "rbxassetid://876939830", -- Notification pop
}

--------------------------------------------------
-- Pickaxe Sounds
--------------------------------------------------

AudioConfig.Pickaxe = {
	swing = "rbxassetid://169380505", -- Whoosh swing
	hitWood = "rbxassetid://507863457", -- Wood hit
	hitStone = "rbxassetid://507863457", -- Stone hit
	hitMetal = "rbxassetid://507863457", -- Metal hit
	critical = "rbxassetid://3398628813", -- Critical hit impact
	equip = "rbxassetid://876939830", -- Equip click
}

--------------------------------------------------
-- Announcer Sounds (kill streaks, events)
--------------------------------------------------

AudioConfig.Announcer = {
	-- Kill streak sounds (Halo/CoD style)
	firstBlood = "rbxassetid://9118823805", -- First kill of the match
	elimination = "rbxassetid://1507116849", -- Standard kill notification
	headshot = "rbxassetid://1129547534", -- Headshot kill (crisp ping)
	doubleKill = "rbxassetid://9118823805", -- 2 kills quickly
	tripleKill = "rbxassetid://9118823805", -- 3 kills quickly
	multiKill = "rbxassetid://9118823805", -- 4+ kills quickly

	-- Match events
	matchStart = "rbxassetid://172905765", -- Match beginning
	roundStart = "rbxassetid://172905765", -- Round starting beep
	overtime = "rbxassetid://6724333590", -- Overtime warning (tense)
	victory = "rbxassetid://1507116849", -- You won
	defeat = "rbxassetid://876939830", -- You lost
}

--------------------------------------------------
-- Volume Defaults
--------------------------------------------------

AudioConfig.DefaultVolumes = {
	Weapons = 0.5,
	Building = 0.4,
	Movement = 0.35, -- base footstep volume
	Combat = 0.6,
	UI = 0.4,
	Pickaxe = 0.5,
	Announcer = 0.7, -- announcer should be clearly audible
	Zombies = 0.55, -- zombie hit/death sounds
}

-- Competitive audio settings for enemy awareness
AudioConfig.CompetitiveSettings = {
	-- Enemy footsteps are louder than your own for better awareness
	enemyFootstepVolumeMultiplier = 1.8,
	-- Sprint footsteps are louder (easier to hear rushing enemies)
	sprintFootstepVolumeMultiplier = 1.3,
}

--------------------------------------------------
-- 3D Audio Settings
--------------------------------------------------

AudioConfig.SpatialSettings = {
	-- Default rolloff for 3D sounds
	rollOffMode = Enum.RollOffMode.Linear,
	rollOffMinDistance = 10,
	rollOffMaxDistance = 150,

	-- Weapon-specific (louder, travels farther)
	weaponRollOffMaxDistance = 300,

	-- Footsteps - extended range for competitive awareness
	footstepRollOffMaxDistance = 80, -- hear enemies from farther
	footstepRollOffMinDistance = 5, -- close range stays loud

	-- Zombie sounds - moderate range
	zombieRollOffMaxDistance = 120,
	zombieRollOffMinDistance = 8,
}

--------------------------------------------------
-- Helper Functions
--------------------------------------------------

-- Get weapon sound ID
function AudioConfig.GetWeaponSound(weaponName: string, soundType: string): string
	local weaponSounds = AudioConfig.Weapons[weaponName]
	if weaponSounds and weaponSounds[soundType] then
		return weaponSounds[soundType]
	end
	-- Fallback to AR sounds
	return AudioConfig.Weapons.AR[soundType] or "rbxassetid://0"
end

-- Get material-based building sound
function AudioConfig.GetBuildingSound(soundType: string, material: string?): string
	local sounds = AudioConfig.Building[soundType]
	if type(sounds) == "table" and material then
		return sounds[material] or sounds.Wood or "rbxassetid://0"
	elseif type(sounds) == "string" then
		return sounds
	end
	return "rbxassetid://0"
end

-- Get footstep sound based on floor material
function AudioConfig.GetFootstepSound(floorMaterial: Enum.Material): string
	local footsteps = AudioConfig.Movement.footstep

	-- Map Roblox materials to our footstep categories
	local materialMap = {
		[Enum.Material.Grass] = "Grass",
		[Enum.Material.LeafyGrass] = "Grass",
		[Enum.Material.Ground] = "Grass",
		[Enum.Material.Wood] = "Wood",
		[Enum.Material.WoodPlanks] = "Wood",
		[Enum.Material.Concrete] = "Concrete",
		[Enum.Material.Pavement] = "Concrete",
		[Enum.Material.Cobblestone] = "Concrete",
		[Enum.Material.Metal] = "Metal",
		[Enum.Material.DiamondPlate] = "Metal",
		[Enum.Material.CorrodedMetal] = "Metal",
		[Enum.Material.Sand] = "Sand",
		[Enum.Material.Sandstone] = "Sand",
		[Enum.Material.Fabric] = "Fabric",
		[Enum.Material.Carpet] = "Fabric",
		[Enum.Material.Plastic] = "Plastic",
		[Enum.Material.SmoothPlastic] = "Plastic",
		[Enum.Material.Slate] = "Slate",
		[Enum.Material.Brick] = "Brick",
	}

	local category = materialMap[floorMaterial] or "Default"
	return footsteps[category] or footsteps.Default
end

-- Get zombie sound ID
function AudioConfig.GetZombieSound(soundType: string): string
	local sound = AudioConfig.Zombies[soundType]
	return sound or "rbxassetid://0"
end

return AudioConfig
