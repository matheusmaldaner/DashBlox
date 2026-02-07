--!strict

local ZombieConfig = {}

--------------------------------------------------
-- Types
--------------------------------------------------

export type ZombieStats = {
	Name: string,
	-- combat
	Health: number,
	Damage: number,
	AttackCooldown: number,
	-- movement
	WalkSpeed: number,
	-- economy
	CoinReward: number,
	XPReward: number,
	-- appearance
	BodyColor: Color3,
	SecondaryColor: Color3?,
	EyeGlow: Color3?,
	Scale: number,
	-- special
	ExplodesOnDeath: boolean,
	ExplosionRadius: number?,
	ExplosionDamage: number?,
}

export type ZombieType = "Normal" | "Fast" | "Tank" | "Exploder" | "Boss"

--------------------------------------------------
-- Zombie Type Definitions
--------------------------------------------------

ZombieConfig.Zombies: { [string]: ZombieStats } = {
	["Normal"] = {
		Name = "Zombie",
		Health = 100,
		Damage = 20,
		AttackCooldown = 1.0,
		WalkSpeed = 12,
		CoinReward = 50,
		XPReward = 10,
		BodyColor = Color3.fromRGB(0, 170, 0),
		SecondaryColor = Color3.fromRGB(0, 130, 0),
		EyeGlow = nil,
		Scale = 1.0,
		ExplodesOnDeath = false,
	},
	["Fast"] = {
		Name = "Runner",
		Health = 60,
		Damage = 15,
		AttackCooldown = 0.8,
		WalkSpeed = 22,
		CoinReward = 75,
		XPReward = 15,
		BodyColor = Color3.fromRGB(200, 30, 30),
		SecondaryColor = Color3.fromRGB(150, 20, 20),
		EyeGlow = Color3.fromRGB(255, 80, 80),
		Scale = 0.9,
		ExplodesOnDeath = false,
	},
	["Tank"] = {
		Name = "Brute",
		Health = 400,
		Damage = 35,
		AttackCooldown = 1.5,
		WalkSpeed = 7,
		CoinReward = 150,
		XPReward = 30,
		BodyColor = Color3.fromRGB(120, 50, 170),
		SecondaryColor = Color3.fromRGB(90, 30, 130),
		EyeGlow = Color3.fromRGB(180, 80, 255),
		Scale = 1.3,
		ExplodesOnDeath = false,
	},
	["Exploder"] = {
		Name = "Bloater",
		Health = 120,
		Damage = 25,
		AttackCooldown = 1.0,
		WalkSpeed = 14,
		CoinReward = 100,
		XPReward = 20,
		BodyColor = Color3.fromRGB(230, 200, 30),
		SecondaryColor = Color3.fromRGB(200, 170, 20),
		EyeGlow = Color3.fromRGB(255, 230, 50),
		Scale = 1.0,
		ExplodesOnDeath = true,
		ExplosionRadius = 15,
		ExplosionDamage = 50,
	},
	["Boss"] = {
		Name = "Abomination",
		Health = 2000,
		Damage = 50,
		AttackCooldown = 2.0,
		WalkSpeed = 5,
		CoinReward = 500,
		XPReward = 100,
		BodyColor = Color3.fromRGB(30, 30, 30),
		SecondaryColor = Color3.fromRGB(50, 10, 10),
		EyeGlow = Color3.fromRGB(255, 0, 0),
		Scale = 1.8,
		ExplodesOnDeath = false,
	},
}

--------------------------------------------------
-- Accessories (Roblox catalog asset IDs)
--------------------------------------------------

ZombieConfig.Accessories: { [string]: { { assetId: number } } } = {
	["Normal"] = {
		{ assetId = 48474313 }, -- cap
	},
	["Fast"] = {},
	["Tank"] = {
		{ assetId = 48474313 },  -- cap
		{ assetId = 192557913 }, -- visor
	},
	["Exploder"] = {},
	["Boss"] = {
		{ assetId = 48474313 },  -- cap
		{ assetId = 192557913 }, -- visor
	},
}

--------------------------------------------------
-- Round Unlock Thresholds
--------------------------------------------------

-- which round each zombie type first appears
ZombieConfig.TypeUnlockRounds: { [string]: number } = {
	["Normal"] = 1,
	["Fast"] = 3,
	["Exploder"] = 5,
	["Tank"] = 7,
	["Boss"] = 10,
}

--------------------------------------------------
-- Constants
--------------------------------------------------

ZombieConfig.DissolveTime = 1.5
ZombieConfig.DespawnDelay = 3.0
ZombieConfig.FaceDecalId = "rbxassetid://36869983"
ZombieConfig.PoolSizePerType = 10

return ZombieConfig
