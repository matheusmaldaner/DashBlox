--!strict

-- wave progression formulas adapted from call of duty zombies (black ops)
-- see: steamcommunity.com/sharedfiles/filedetails/?id=258783121

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ZombieConfig = require(ReplicatedStorage.Modules.Zombies.ZombieConfig)

local WaveConfig = {}

--------------------------------------------------
-- Types
--------------------------------------------------

export type WaveState = {
	round: number,
	playerCount: number,
	zombiesRemaining: number,
	zombiesAlive: number,
	zombiesSpawned: number,
	totalZombiesForRound: number,
	isActive: boolean,
	restPhase: boolean,
}

--------------------------------------------------
-- Zombie Count Per Round
--------------------------------------------------

-- rounds 1-4: scaled ramp from base of 6
-- rounds 5-9: flat 24 (matches COD solo cap)
-- rounds 10+: quadratic growth via round * 0.15 * 24
-- player scaling: +50% per additional player
function WaveConfig.GetZombieCount(round: number, playerCount: number): number
	local count: number
	if round <= 4 then
		count = math.ceil(6 * (round * 0.2 + 0.8))
	elseif round <= 9 then
		count = 24
	else
		count = math.ceil(round * 0.15 * 24)
	end
	-- scale for multiplayer
	count = math.ceil(count * (1 + (playerCount - 1) * 0.5))
	return count
end

--------------------------------------------------
-- Zombie Health Scaling
--------------------------------------------------

-- rounds 1-9: linear (50 + round * 100) / 150 multiplier on base health
-- round 10+: compound 1.1x growth per round from round 9 health
function WaveConfig.GetZombieHealth(round: number, baseHealth: number): number
	if round <= 9 then
		local roundMultiplier = (50 + round * 100) / 150
		return math.ceil(baseHealth * roundMultiplier)
	else
		local round9Multiplier = (50 + 9 * 100) / 150
		local round9Health = baseHealth * round9Multiplier
		return math.ceil(round9Health * (1.1 ^ (round - 9)))
	end
end

--------------------------------------------------
-- Spawn Timing
--------------------------------------------------

-- spawn delay decreases 5% per round, minimum 0.1 seconds
function WaveConfig.GetSpawnDelay(round: number): number
	return math.max(2 * (0.95 ^ (round - 1)), 0.1)
end

--------------------------------------------------
-- Max Alive Cap
--------------------------------------------------

-- base 15 + 6 per additional player
function WaveConfig.GetMaxAlive(playerCount: number): number
	return 15 + (playerCount - 1) * 6
end

--------------------------------------------------
-- Rest Period Between Rounds
--------------------------------------------------

function WaveConfig.GetRestDuration(round: number): number
	if round <= 3 then
		return 20
	elseif round <= 10 then
		return 15
	else
		return 10
	end
end

--------------------------------------------------
-- Zombie Type Selection
--------------------------------------------------

-- returns weighted distribution based on which types are unlocked at this round
function WaveConfig.GetZombieTypeWeights(round: number): { { zombieType: string, weight: number } }
	local weights: { { zombieType: string, weight: number } } = {}
	local unlocks = ZombieConfig.TypeUnlockRounds

	if round >= unlocks["Normal"] then
		table.insert(weights, { zombieType = "Normal", weight = 50 })
	end
	if round >= unlocks["Fast"] then
		table.insert(weights, { zombieType = "Fast", weight = 25 })
	end
	if round >= unlocks["Exploder"] then
		table.insert(weights, { zombieType = "Exploder", weight = 15 })
	end
	if round >= unlocks["Tank"] then
		table.insert(weights, { zombieType = "Tank", weight = 10 })
	end
	-- boss is handled separately in spawner (not via weights)

	return weights
end

-- weighted random selection from type weights table
function WaveConfig.PickZombieType(weights: { { zombieType: string, weight: number } }): string
	local totalWeight = 0
	for _, entry in weights do
		totalWeight += entry.weight
	end

	if totalWeight <= 0 then
		return "Normal"
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in weights do
		cumulative += entry.weight
		if roll <= cumulative then
			return entry.zombieType
		end
	end

	return "Normal"
end

return WaveConfig
