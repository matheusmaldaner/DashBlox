--!strict

-- mystery box configuration: costs, weapon weights, teddy bear odds,
-- timing constants for the COD-style random weapon box

local MysteryBoxConfig = {}

--------------------------------------------------
-- Costs
--------------------------------------------------

MysteryBoxConfig.Cost = 0 -- TODO: restore to 950 after testing
MysteryBoxConfig.FireSaleCost = 10

--------------------------------------------------
-- Timing
--------------------------------------------------

MysteryBoxConfig.CyclingDuration = 4.5    -- seconds of weapon cycling animation
MysteryBoxConfig.PickupWindow = 12.0      -- seconds player has to grab the weapon
MysteryBoxConfig.CooldownAfterUse = 1.0   -- seconds before another player can use it
MysteryBoxConfig.RelocateDelay = 3.0      -- seconds before box reappears at new location
MysteryBoxConfig.LightBeamDuration = 5.0  -- seconds the light beam stays at new location

--------------------------------------------------
-- Teddy Bear (Box Relocate)
--------------------------------------------------

MysteryBoxConfig.TeddyBearBaseChance = 0.05  -- 5% starting chance
MysteryBoxConfig.TeddyBearChancePerUse = 0.03 -- +3% per use at this location
MysteryBoxConfig.TeddyBearMaxChance = 0.50   -- cap at 50%

--------------------------------------------------
-- Weapon Pool & Weights
--------------------------------------------------

-- weapons available in the box, weighted by rarity
-- higher weight = more likely to appear
-- pistol excluded (starter weapon)
MysteryBoxConfig.WeaponPool = {
	{ gunName = "SMG", weight = 30, rarity = "Uncommon" },
	{ gunName = "AR", weight = 25, rarity = "Rare" },
	{ gunName = "TacticalShotgun", weight = 20, rarity = "Rare" },
	{ gunName = "PumpShotgun", weight = 15, rarity = "Epic" },
	{ gunName = "Sniper", weight = 10, rarity = "Legendary" },
}

--------------------------------------------------
-- Cycling Animation
--------------------------------------------------

-- how many weapons flash through during the cycling animation
MysteryBoxConfig.CyclingFlashCount = 20
-- cycling speed: starts fast, slows down near the end
MysteryBoxConfig.CyclingStartInterval = 0.08  -- seconds between flashes at start
MysteryBoxConfig.CyclingEndInterval = 0.4     -- seconds between flashes at end

--------------------------------------------------
-- Visual Constants
--------------------------------------------------

MysteryBoxConfig.LightBeamColor = Color3.fromRGB(0, 150, 255)
MysteryBoxConfig.LightBeamHeight = 100
MysteryBoxConfig.BoxPromptText = "Mystery Box"
MysteryBoxConfig.BoxActionText = "Open"
MysteryBoxConfig.BoxMaxDistance = 8

--------------------------------------------------
-- Rarity Colors (for cycling display)
--------------------------------------------------

MysteryBoxConfig.RarityColors = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(30, 200, 30),
	Rare = Color3.fromRGB(50, 120, 255),
	Epic = Color3.fromRGB(180, 50, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
}

return MysteryBoxConfig
