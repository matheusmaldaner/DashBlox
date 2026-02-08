--!strict

-- startup cleanup: finds all Parts named "ForceField" and turns them
-- into invisible walls (transparent, collidable, anchored)
-- safe to delete this file once you've cleaned up in Studio

for _, instance in game:GetDescendants() do
	-- match Parts named "ForceField" (case-insensitive check)
	if instance:IsA("BasePart") then
		local name = string.lower(instance.Name)
		if name == "forcefield" or name == "force field" or name == "force_field" then
			instance.Transparency = 1
			instance.CanCollide = true
			instance.Anchored = true
			instance.Material = Enum.Material.SmoothPlastic
			instance.CastShadow = false
		end
	end

	-- also remove any actual ForceField instances
	if instance:IsA("ForceField") then
		instance:Destroy()
	end
end
