--!strict
-- ADSState - Shared state module for ADS (Aim Down Sights) communication
-- Allows GunController and GunCameraController to share ADS state

local ADSState = {}

-- Current ADS state
ADSState.isADS = false
ADSState.currentGun = nil :: string?
ADSState.sensitivityMultiplier = 1.0

-- Update ADS state (called by GunController)
function ADSState.SetADS(isADS: boolean, gunName: string?, sensitivityMultiplier: number?)
	ADSState.isADS = isADS
	ADSState.currentGun = gunName
	ADSState.sensitivityMultiplier = sensitivityMultiplier or 1.0
end

-- Get current sensitivity multiplier (called by GunCameraController)
function ADSState.GetSensitivityMultiplier(): number
	if ADSState.isADS then
		return ADSState.sensitivityMultiplier
	end
	return 1.0
end

return ADSState
