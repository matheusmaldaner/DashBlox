--!strict

-- Pack-a-Punch configuration: defines upgrade cost, multipliers,
-- and upgraded weapon names for the Pack-a-Punch machine

local PackAPunchConfig = {}

-- base cost to upgrade any weapon
PackAPunchConfig.Cost = 5000

-- damage multiplier when weapon is Pack-a-Punched
PackAPunchConfig.DamageMultiplier = 2.5

-- magazine size multiplier when weapon is Pack-a-Punched
PackAPunchConfig.MagazineSizeMultiplier = 2

-- upgraded weapon display names (fun renamed versions)
PackAPunchConfig.UpgradedNames = {
	["AR"] = "Augmented Reality",
	["PumpShotgun"] = "The Impeller",
	["SMG"] = "Shredder 9000",
	["TacticalShotgun"] = "Tactical Annihilator",
	["Sniper"] = "Penetrator X",
	["Pistol"] = "Mustang & Sally",
}

-- get display name for an upgraded weapon
function PackAPunchConfig.GetUpgradedName(gunName: string): string
	return PackAPunchConfig.UpgradedNames[gunName] or (gunName .. " MK II")
end

-- proximity prompt settings for the machine
PackAPunchConfig.PromptHoldDuration = 1.0
PackAPunchConfig.PromptMaxDistance = 8

-- upgrade animation duration (server waits this long before giving weapon back)
PackAPunchConfig.UpgradeDuration = 5.0

-- client VFX settings
PackAPunchConfig.FlashColor = { r = 255, g = 100, b = 0 } -- orange glow
PackAPunchConfig.UpgradedFlashColor = { r = 255, g = 50, b = 50 } -- red reveal
PackAPunchConfig.CyclingFlashCount = 30
PackAPunchConfig.CyclingStartInterval = 0.05
PackAPunchConfig.CyclingEndInterval = 0.25

return PackAPunchConfig
