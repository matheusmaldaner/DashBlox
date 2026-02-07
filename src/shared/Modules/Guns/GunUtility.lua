--!strict
local GunUtility = {}

local GunConfig = require(script.Parent.GunConfig)

export type PlayerState = {
	isMoving: boolean,
	moveSpeed: number,
	isADS: boolean,
	isCrouching: boolean,
	isSprinting: boolean?,
}

-- crouch reduces spread by 30%
local CROUCH_SPREAD_MULTIPLIER = 0.7

-- sprint increases spread by 30%
local SPRINT_SPREAD_MULTIPLIER = 1.3

-- Calculate final spread based on player state
-- Returns spread value (0 = perfect accuracy, higher = more spread)
function GunUtility.CalculateSpread(gunStats: GunConfig.GunStats, playerState: PlayerState): number
	local spread = gunStats.BaseSpread

	-- Movement penalty - supports both multiplicative and additive modes
	if playerState.isMoving and playerState.moveSpeed > 0.1 then
		local speedFactor = math.min(playerState.moveSpeed / 16, 1)

		-- Check for additive MovingSpread (for weapons with BaseSpread = 0)
		local movingSpread = (gunStats :: any).MovingSpread
		if movingSpread and movingSpread > 0 then
			-- Additive: add spread based on movement speed
			spread = spread + (movingSpread * speedFactor)
		else
			-- Multiplicative: multiply base spread
			spread = spread * (1 + (gunStats.MovingSpreadMultiplier - 1) * speedFactor)
		end
	end

	-- ADS accuracy bonus (multiplicative)
	if playerState.isADS then
		spread = spread * gunStats.ADSSpreadMultiplier
	end

	-- Crouch accuracy bonus (30% reduction)
	if playerState.isCrouching then
		spread = spread * CROUCH_SPREAD_MULTIPLIER
	end

	-- Sprint accuracy penalty (30% increase)
	if playerState.isSprinting then
		spread = spread * SPRINT_SPREAD_MULTIPLIER
	end

	return spread
end

-- Apply random spread to a direction vector
function GunUtility.ApplySpreadToDirection(direction: Vector3, spreadRadians: number): Vector3
	local unitDirection = direction.Unit
	if spreadRadians <= 0 then
		return unitDirection
	end

	-- Uniformly distribute shots inside the spread circle.
	local randomAngle = math.random() * math.pi * 2
	local radius = math.sqrt(math.random()) * spreadRadians

	-- Create perpendicular vectors using a stable basis
	-- We need vectors that are perpendicular to the look direction
	local worldUp = Vector3.new(0, 1, 0)

	-- Handle edge case: looking straight up or down
	if math.abs(unitDirection:Dot(worldUp)) > 0.99 then
		worldUp = Vector3.new(0, 0, 1)
	end

	-- Calculate right vector (perpendicular to both direction and world up)
	-- Using up:Cross(direction) instead of direction:Cross(up) to get screen-right
	local right = worldUp:Cross(unitDirection).Unit
	-- Calculate the actual up vector perpendicular to both direction and right
	local perpUp = unitDirection:Cross(right).Unit

	local spreadOffset = (right * math.cos(randomAngle) + perpUp * math.sin(randomAngle)) * radius
	return (unitDirection + spreadOffset).Unit
end

-- Calculate damage with distance falloff and headshot
function GunUtility.CalculateDamage(gunStats: GunConfig.GunStats, distance: number, isHeadshot: boolean): number
	local damage = gunStats.BaseDamage

	-- Apply headshot multiplier
	if isHeadshot then
		damage = damage * gunStats.HeadshotMultiplier
	end

	-- Apply distance falloff
	if distance > gunStats.DamageFalloffStart then
		local falloffRange = gunStats.MaxRange - gunStats.DamageFalloffStart
		if falloffRange > 0 then
			local falloffProgress = math.min((distance - gunStats.DamageFalloffStart) / falloffRange, 1)
			local damageMultiplier = 1 - (1 - gunStats.MinDamageMultiplier) * falloffProgress
			damage = damage * damageMultiplier
		end
	end

	return math.floor(damage)
end

return GunUtility
