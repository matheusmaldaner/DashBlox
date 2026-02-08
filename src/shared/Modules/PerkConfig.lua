--!strict

-- defines all perk machine types, costs, and gameplay effects
-- perks are purchased from tagged machines and lost on death

local PerkConfig = {}

export type PerkStats = {
	Name: string,
	DisplayName: string,
	Cost: number,
	Description: string,
	Color: Color3,         -- HUD icon color
	IconText: string,      -- short text for HUD icon (emoji-free, 1-2 chars)
	AttributeName: string, -- player attribute set when perk is active

	-- effect fields (only the relevant one is non-nil per perk)
	MaxHealth: number?,
	ReloadMultiplier: number?,
	FireRateMultiplier: number?,
	SelfRevive: boolean?,
}

PerkConfig.Perks = {
	["Juggernog"] = {
		Name = "Juggernog",
		DisplayName = "Juggernog",
		Cost = 2500,
		Description = "Increases max health to 250",
		Color = Color3.fromRGB(255, 50, 50),
		IconText = "JG",
		AttributeName = "HasJuggernog",
		MaxHealth = 250,
	},

	["SpeedCola"] = {
		Name = "SpeedCola",
		DisplayName = "Speed Cola",
		Cost = 3000,
		Description = "Reload 2x faster",
		Color = Color3.fromRGB(50, 255, 50),
		IconText = "SC",
		AttributeName = "HasSpeedCola",
		ReloadMultiplier = 0.5,
	},

	["DoubleTap"] = {
		Name = "DoubleTap",
		DisplayName = "Double Tap",
		Cost = 2000,
		Description = "Double fire rate",
		Color = Color3.fromRGB(255, 200, 50),
		IconText = "DT",
		AttributeName = "HasDoubleTap",
		FireRateMultiplier = 2.0,
	},

	["QuickRevive"] = {
		Name = "QuickRevive",
		DisplayName = "Quick Revive",
		Cost = 1500,
		Description = "Allows self-revive when downed",
		Color = Color3.fromRGB(50, 150, 255),
		IconText = "QR",
		AttributeName = "HasQuickRevive",
		SelfRevive = true,
	},
}

-- max perks a player can hold at once
PerkConfig.MaxPerks = 4

-- proximity prompt settings for perk machines
PerkConfig.PromptHoldDuration = 0.5
PerkConfig.PromptMaxDistance = 8

return PerkConfig
