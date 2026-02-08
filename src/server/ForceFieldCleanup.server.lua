--!strict

-- startup cleanup and collision group setup:
-- 1. Barrier/Zombie collision groups (zombies pass through, players don't)
-- 2. ForceField-material parts → invisible barrier walls
-- 3. "Decoration" tagged parts → anchored, non-interactive (purely visual)

local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

--------------------------------------------------
-- Collision Groups
--------------------------------------------------

PhysicsService:RegisterCollisionGroup("Barrier")
PhysicsService:RegisterCollisionGroup("Zombie")
PhysicsService:RegisterCollisionGroup("Decoration")

-- barriers block players (Default) but NOT zombies
PhysicsService:CollisionGroupSetCollidable("Barrier", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("Barrier", "Default", true)

-- decoration doesn't collide with players or zombies
PhysicsService:CollisionGroupSetCollidable("Decoration", "Default", false)
PhysicsService:CollisionGroupSetCollidable("Decoration", "Zombie", false)

--------------------------------------------------
-- ForceField material → invisible barrier walls
--------------------------------------------------

for _, instance in game:GetDescendants() do
	if instance:IsA("BasePart") and instance.Material == Enum.Material.ForceField then
		instance.Transparency = 1
		instance.CanCollide = true
		instance.Anchored = true
		instance.Material = Enum.Material.SmoothPlastic
		instance.CastShadow = false
		instance.CollisionGroup = "Barrier"
	end
end

--------------------------------------------------
-- Decoration: tagged parts become non-interactive
-- (use "Trash" tag instead for pickable items)
--------------------------------------------------

local function SetupDecoration(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CollisionGroup = "Decoration"
	elseif instance:IsA("Model") then
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanTouch = false
				descendant.CanQuery = false
				descendant.CollisionGroup = "Decoration"
			end
		end
	end
end

for _, instance in CollectionService:GetTagged("Decoration") do
	SetupDecoration(instance)
end

CollectionService:GetInstanceAddedSignal("Decoration"):Connect(SetupDecoration)
