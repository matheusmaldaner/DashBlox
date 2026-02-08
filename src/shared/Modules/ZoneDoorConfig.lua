--!strict

-- configures zone door behavior: default prices, prompt settings, open animation
-- doors are discovered via "ZoneDoor" CollectionService tag
-- per-door prices are set via DoorPrice attribute in studio

local ZoneDoorConfig = {}

-- fallback price if DoorPrice attribute is missing from a door
ZoneDoorConfig.DefaultPrice = 1000

-- prompt settings
ZoneDoorConfig.PromptHoldDuration = 0.8
ZoneDoorConfig.PromptMaxDistance = 10
ZoneDoorConfig.DefaultLabel = "Open Door"

-- open animation settings
ZoneDoorConfig.FadeDuration = 0.5 -- seconds to fade out door parts
ZoneDoorConfig.SoundEnabled = true

return ZoneDoorConfig
