--!strict
-- weapon setup - creates placeholder weapon models for testing
-- replace with real weapon models in Studio

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--------------------------------------------------
-- Setup Assets Folder Structure
--------------------------------------------------

local Assets = ReplicatedStorage:FindFirstChild("Assets")
if not Assets then
	Assets = Instance.new("Folder")
	Assets.Name = "Assets"
	Assets.Parent = ReplicatedStorage
end

local Weapons = Assets:FindFirstChild("Weapons")
if not Weapons then
	Weapons = Instance.new("Folder")
	Weapons.Name = "Weapons"
	Weapons.Parent = Assets
end

--------------------------------------------------
-- Placeholder Weapon Definitions
-- These are only used if real weapon models don't exist
--------------------------------------------------

-- Map from config ModelName to placeholder definitions
local weaponDefinitions = {
	["Assault Rifle"] = {
		color = Color3.fromRGB(80, 80, 90),
		size = Vector3.new(0.3, 0.4, 2.5),
		grip = Vector3.new(0, -0.1, -0.6),
	},
	["Shotgun"] = {
		color = Color3.fromRGB(60, 50, 40),
		size = Vector3.new(0.35, 0.35, 2.2),
		grip = Vector3.new(0, -0.1, -0.5),
	},
	["SMG"] = {
		color = Color3.fromRGB(50, 50, 60),
		size = Vector3.new(0.25, 0.3, 1.5),
		grip = Vector3.new(0, -0.1, -0.3),
	},
	["TacticalShotgun"] = {
		color = Color3.fromRGB(70, 60, 50),
		size = Vector3.new(0.3, 0.35, 1.8),
		grip = Vector3.new(0, -0.1, -0.4),
	},
	["Sniper"] = {
		color = Color3.fromRGB(50, 55, 50),
		size = Vector3.new(0.25, 0.4, 3.5),
		grip = Vector3.new(0, -0.1, -1.0),
	},
	["Pistol"] = {
		color = Color3.fromRGB(40, 40, 45),
		size = Vector3.new(0.15, 0.25, 0.8),
		grip = Vector3.new(0, -0.08, -0.15),
	},
}

--------------------------------------------------
-- Create Placeholder Weapons
--------------------------------------------------

local function createPlaceholderWeapon(name: string, definition: { color: Color3, size: Vector3, grip: Vector3 })
	-- check if weapon already exists (real model or previous placeholder)
	local existing = Weapons:FindFirstChild(name)
	if existing then
		-- Check if it has a Muzzle attachment (real weapon models have these)
		if existing:FindFirstChild("Muzzle", true) then
			print("[WeaponSetup] Using real weapon model:", name)
		end
		return
	end

	local model = Instance.new("Model")
	model.Name = name

	-- main body
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = definition.size
	body.Color = definition.color
	body.Material = Enum.Material.Metal
	body.CanCollide = false
	body.Massless = true
	body.Parent = model

	-- handle/grip
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.4, 0.15)
	handle.Color = Color3.fromRGB(40, 35, 30)
	handle.Material = Enum.Material.Plastic
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = body.CFrame * CFrame.new(definition.grip) * CFrame.Angles(math.rad(-20), 0, 0)
	handle.Parent = model

	-- weld handle to body
	local handleWeld = Instance.new("WeldConstraint")
	handleWeld.Part0 = body
	handleWeld.Part1 = handle
	handleWeld.Parent = handle

	-- muzzle attachment for effects
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, definition.size.Z / 2)
	muzzle.Parent = body

	-- set primary part
	model.PrimaryPart = body

	model.Parent = Weapons

	print("[WeaponSetup] Created placeholder:", name)
end

-- create all placeholder weapons
for name, definition in weaponDefinitions do
	createPlaceholderWeapon(name, definition)
end

print("[WeaponSetup] Placeholder weapons initialized")
