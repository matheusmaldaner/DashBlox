--!strict

-- startup cleanup: converts ForceField parent parts into invisible walls
-- and removes the ForceField instances (which don't block movement)
-- safe to delete this file once you've cleaned up in Studio

for _, instance in game:GetDescendants() do
	if instance:IsA("ForceField") then
		local parent = instance.Parent
		if parent and parent:IsA("BasePart") then
			parent.Material = Enum.Material.Glass
			parent.CanCollide = true
			parent.Transparency = 1
			parent.Anchored = true
		end
		instance:Destroy()
	end
end
