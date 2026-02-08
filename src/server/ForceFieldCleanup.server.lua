--!strict

-- startup cleanup: finds all BaseParts using the ForceField material,
-- converts them into invisible walls, and assigns them to the "Barrier"
-- collision group so zombies can walk through but players cannot.

local PhysicsService = game:GetService("PhysicsService")

-- register collision groups
PhysicsService:RegisterCollisionGroup("Barrier")
PhysicsService:RegisterCollisionGroup("Zombie")

-- barriers block players (Default) but NOT zombies
PhysicsService:CollisionGroupSetCollidable("Barrier", "Zombie", false)
PhysicsService:CollisionGroupSetCollidable("Barrier", "Default", true)

-- convert ForceField-material parts into invisible barrier walls
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
