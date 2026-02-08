--!strict

-- defines all powerup drop types, durations, visuals, and drop chances
-- powerups spawn when zombies die and apply global or per-player effects

local PowerupConfig = {}

export type PowerupStats = {
	Name: string,
	DisplayName: string,
	Duration: number,    -- 0 = instant effect (Nuke, Max Ammo, Carpenter)
	Color: Color3,       -- glow color for the pickup part
	IconText: string,    -- short text shown on HUD timer
	Description: string,
	IsGlobal: boolean,   -- true = affects all players, false = collector only
}

PowerupConfig.Powerups = {
	["MaxAmmo"] = {
		Name = "MaxAmmo",
		DisplayName = "Max Ammo",
		Duration = 0,
		Color = Color3.fromRGB(50, 255, 50),
		IconText = "MA",
		Description = "Refills all players' ammo to full",
		IsGlobal = true,
	},

	["InstaKill"] = {
		Name = "InstaKill",
		DisplayName = "Insta-Kill",
		Duration = 30,
		Color = Color3.fromRGB(255, 255, 255),
		IconText = "IK",
		Description = "All zombie hits are instant kills for 30 seconds",
		IsGlobal = true,
	},

	["DoublePoints"] = {
		Name = "DoublePoints",
		DisplayName = "Double Points",
		Duration = 30,
		Color = Color3.fromRGB(255, 255, 50),
		IconText = "2X",
		Description = "Double coin rewards for 30 seconds",
		IsGlobal = true,
	},

	["Nuke"] = {
		Name = "Nuke",
		DisplayName = "Nuke",
		Duration = 0,
		Color = Color3.fromRGB(255, 200, 50),
		IconText = "NK",
		Description = "Kills all alive zombies, awards 400 coins each",
		IsGlobal = true,
	},

	["Carpenter"] = {
		Name = "Carpenter",
		DisplayName = "Carpenter",
		Duration = 0,
		Color = Color3.fromRGB(180, 120, 60),
		IconText = "CP",
		Description = "Repairs all barricades to full",
		IsGlobal = true,
	},

	["FireSale"] = {
		Name = "FireSale",
		DisplayName = "Fire Sale",
		Duration = 30,
		Color = Color3.fromRGB(255, 100, 50),
		IconText = "FS",
		Description = "Mystery Box cost reduced to 10 for 30 seconds",
		IsGlobal = true,
	},
}

-- chance to drop a powerup when a zombie dies (0.0 to 1.0)
PowerupConfig.DropChance = 0.03

-- weighted table for which powerup drops (higher = more likely)
PowerupConfig.DropWeights = {
	["MaxAmmo"] = 25,
	["InstaKill"] = 20,
	["DoublePoints"] = 25,
	["Nuke"] = 10,
	["Carpenter"] = 15,
	["FireSale"] = 5,
}

-- how long the pickup stays on the ground before despawning (seconds)
PowerupConfig.PickupLifetime = 30

-- visual settings for the pickup part
PowerupConfig.PickupSize = Vector3.new(2, 2, 2)
PowerupConfig.BobHeight = 1.5    -- studs to bob up and down
PowerupConfig.BobSpeed = 2.0     -- bobs per second
PowerupConfig.SpinSpeed = 90     -- degrees per second

-- pick a random powerup type based on weights
function PowerupConfig.PickRandomPowerup(): string
	local totalWeight = 0
	for _, weight in PowerupConfig.DropWeights do
		totalWeight += weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for name, weight in PowerupConfig.DropWeights do
		cumulative += weight
		if roll <= cumulative then
			return name
		end
	end

	-- fallback
	return "MaxAmmo"
end

return PowerupConfig
