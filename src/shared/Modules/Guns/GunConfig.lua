--!strict
local GunConfig = {}

export type GunStats = {
	Name: string,
	ModelName: string,
	Rarity: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary",

	-- Damage
	BaseDamage: number,
	HeadshotMultiplier: number,

	-- Fire Rate
	FireRate: number,
	FireMode: "Auto" | "Semi",

	-- Magazine
	MagazineSize: number,
	ReloadTime: number,

	-- Accuracy (spread values 0-1)
	BaseSpread: number,
	MovingSpreadMultiplier: number,
	ADSSpreadMultiplier: number,

	-- Recoil
	RecoilPerShot: number,
	RecoilDecayRate: number,
	MaxRecoilSpread: number,

	-- ADS
	ADSFOVMultiplier: number,
	ADSTransitionTime: number,
	ADSSensitivityMultiplier: number, -- Mouse sensitivity multiplier when ADS (lower = slower)

	-- Range
	MaxRange: number,
	DamageFalloffStart: number,
	MinDamageMultiplier: number,
}

GunConfig.Guns = {
	["AR"] = {
		Name = "Assault Rifle",
		ModelName = "Assault Rifle",
		Rarity = "Rare",

		BaseDamage = 30,
		HeadshotMultiplier = 1.5,

		FireRate = 600,
		FireMode = "Auto",

		MagazineSize = 30,
		ReloadTime = 2.2,

		BaseSpread = 0, -- 100% accurate first shot when standing still
		MovingSpreadMultiplier = 1.0, -- not used when BaseSpread is 0
		ADSSpreadMultiplier = 1.0, -- not used when BaseSpread is 0
		MovingSpread = 0.025, -- added spread when moving (hipfire)

		RecoilPerShot = 0.012, -- spread builds up per shot
		RecoilDecayRate = 0.1, -- decay rate per second (~0.6s to reset from max)
		MaxRecoilSpread = 0.06, -- max spread from recoil

		ADSFOVMultiplier = 0.75,
		ADSTransitionTime = 0.2,
		ADSSensitivityMultiplier = 0.6, -- moderate slowdown

		MaxRange = 500,
		DamageFalloffStart = 100,
		MinDamageMultiplier = 0.5,
	} :: GunStats,

	["PumpShotgun"] = {
		Name = "Pump Shotgun",
		ModelName = "Shotgun",
		Rarity = "Epic",

		BaseDamage = 9, -- per pellet, 12 pellets = 108 max
		HeadshotMultiplier = 2.0,

		FireRate = 70, -- slow pump action
		FireMode = "Semi",

		MagazineSize = 5,
		ReloadTime = 4.5, -- shell by shell

		BaseSpread = 0.08, -- shotgun spread
		MovingSpreadMultiplier = 1.2,
		ADSSpreadMultiplier = 0.7,

		RecoilPerShot = 0.04,
		RecoilDecayRate = 0.3,
		MaxRecoilSpread = 0.1,

		ADSFOVMultiplier = 0.85,
		ADSTransitionTime = 0.15,
		ADSSensitivityMultiplier = 0.7, -- slight slowdown (close range)

		MaxRange = 50,
		DamageFalloffStart = 15,
		MinDamageMultiplier = 0.2,
	} :: GunStats,

	["SMG"] = {
		Name = "Submachine Gun",
		ModelName = "SMG",
		Rarity = "Uncommon",

		BaseDamage = 17,
		HeadshotMultiplier = 1.5,

		FireRate = 900, -- very fast
		FireMode = "Auto",

		MagazineSize = 25,
		ReloadTime = 1.8,

		BaseSpread = 0.02, -- SMG always has some spread (never 100% accurate)
		MovingSpreadMultiplier = 1.5, -- 50% worse when moving
		ADSSpreadMultiplier = 0.7, -- ADS helps but doesn't give perfect accuracy
		MovingSpread = 0.015, -- additional spread when moving

		RecoilPerShot = 0.012, -- builds up per shot
		RecoilDecayRate = 0.12, -- decay rate per second
		MaxRecoilSpread = 0.08, -- max spread from recoil

		ADSFOVMultiplier = 0.85,
		ADSTransitionTime = 0.12,
		ADSSensitivityMultiplier = 0.7, -- slight slowdown (spray weapon)

		MaxRange = 150,
		DamageFalloffStart = 30,
		MinDamageMultiplier = 0.4,
	} :: GunStats,

	["TacticalShotgun"] = {
		Name = "Tactical Shotgun",
		ModelName = "Shotgun",
		Rarity = "Rare",

		BaseDamage = 7, -- per pellet, 10 pellets = 70 max
		HeadshotMultiplier = 1.75,

		FireRate = 120, -- faster than pump
		FireMode = "Semi",

		MagazineSize = 8,
		ReloadTime = 5.0, -- shell by shell

		BaseSpread = 0.09, -- wider spread
		MovingSpreadMultiplier = 1.3,
		ADSSpreadMultiplier = 0.75,

		RecoilPerShot = 0.03,
		RecoilDecayRate = 0.35,
		MaxRecoilSpread = 0.08,

		ADSFOVMultiplier = 0.85,
		ADSTransitionTime = 0.15,
		ADSSensitivityMultiplier = 0.7, -- slight slowdown (close range)

		MaxRange = 40,
		DamageFalloffStart = 12,
		MinDamageMultiplier = 0.15,
	} :: GunStats,

	["Sniper"] = {
		Name = "Sniper Rifle",
		ModelName = "Sniper",
		Rarity = "Legendary",

		BaseDamage = 105, -- body shot
		HeadshotMultiplier = 2.5, -- 262 headshot = instant kill with full shield

		FireRate = 33, -- bolt action, slow
		FireMode = "Semi",

		MagazineSize = 5,
		ReloadTime = 3.0,

		BaseSpread = 0.04, -- hipfire spread (inaccurate without scope)
		MovingSpreadMultiplier = 2.0, -- worse when moving
		ADSSpreadMultiplier = 0, -- 100% accurate when scoped and standing still

		RecoilPerShot = 0, -- no recoil spread accumulation (bolt action)
		RecoilDecayRate = 0.1,
		MaxRecoilSpread = 0,

		ADSFOVMultiplier = 0.35, -- high zoom
		ADSTransitionTime = 0.35,
		ADSSensitivityMultiplier = 0.3, -- very slow for precise aiming

		MaxRange = 1000,
		DamageFalloffStart = 500,
		MinDamageMultiplier = 0.8, -- minimal falloff
	} :: GunStats,

	["Pistol"] = {
		Name = "Pistol",
		ModelName = "Pistol",
		Rarity = "Common",

		BaseDamage = 24,
		HeadshotMultiplier = 2.0,

		FireRate = 400, -- semi-auto spam
		FireMode = "Semi",

		MagazineSize = 16,
		ReloadTime = 1.3,

		BaseSpread = 0.015,
		MovingSpreadMultiplier = 1.5,
		ADSSpreadMultiplier = 0.3,

		RecoilPerShot = 0.015,
		RecoilDecayRate = 0.25,
		MaxRecoilSpread = 0.06,

		ADSFOVMultiplier = 0.8,
		ADSTransitionTime = 0.1,
		ADSSensitivityMultiplier = 0.65, -- moderate slowdown

		MaxRange = 200,
		DamageFalloffStart = 50,
		MinDamageMultiplier = 0.5,
	} :: GunStats,
}

-- shotgun pellet count
GunConfig.ShotgunPellets = {
	["PumpShotgun"] = 12,
	["TacticalShotgun"] = 10,
}

GunConfig.DefaultGun = "AR"

return GunConfig
