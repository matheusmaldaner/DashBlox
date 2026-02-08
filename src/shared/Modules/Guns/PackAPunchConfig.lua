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
PackAPunchConfig.UpgradeDuration = 3.0

return PackAPunchConfig
