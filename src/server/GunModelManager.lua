--!strict

-- server module: weapon model attachment to player characters
-- handles attaching/removing 3D weapon models, muzzle positions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)

local GunModelManager = {}

GunModelManager.EQUIPPED_GUN_NAME = "EquippedGun"

-- Per-weapon weld offset overrides (applied after the base C0)
-- Axes are post-rotation: X = forward/back, Y = left/right, Z = up/down
local WeaponOffsets: { [string]: CFrame } = {
	["PumpShotgun"] = CFrame.new(-1, 0, 0),     -- 2 studs forward
	["TacticalShotgun"] = CFrame.new(-1, 0, 0),  -- 2 studs forward
	["SMG"] = CFrame.new(-1, 0, 0),  -- 2 studs forward
	["Sniper"] = CFrame.new(-1, 0, 0),  -- 2 studs forward
	["Pistol"] = CFrame.new(-1, 0, 0),  -- 2 studs forward
	["AR"] = CFrame.new(-1, 0, 0),  -- 2 studs forward
}

local function GetRightHand(character: Model): BasePart?
	return (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
end

function GunModelManager.RemoveEquippedGun(character: Model)
	local existing = character:FindFirstChild(GunModelManager.EQUIPPED_GUN_NAME)
	if existing then
		existing:Destroy()
	end
end

function GunModelManager.GetMuzzleWorldPosition(player: Player, fallbackOrigin: Vector3): Vector3
	local character = player.Character
	if not character then
		return fallbackOrigin
	end

	local gunModel = character:FindFirstChild(GunModelManager.EQUIPPED_GUN_NAME)
	if gunModel then
		local muzzle = gunModel:FindFirstChild("Muzzle", true)
		if muzzle then
			if muzzle:IsA("Attachment") then
				return muzzle.WorldPosition
			elseif muzzle:IsA("BasePart") then
				return muzzle.Position
			end
		end
	end

	local head = character:FindFirstChild("Head") :: BasePart?
	if head then
		return head.Position
	end

	return fallbackOrigin
end

function GunModelManager.AttachGunModel(player: Player, gunName: string)
	print("[GunModelManager] AttachGunModel called for", player.Name, "gun:", gunName)

	local character = player.Character
	if not character then
		warn("[GunModelManager] FAILED: No character for", player.Name)
		return
	end

	local rightHand = GetRightHand(character)
	if not rightHand then
		warn("[GunModelManager] FAILED: No RightHand/Right Arm on", player.Name)
		-- List character children for debugging
		local childNames = {}
		for _, child in character:GetChildren() do
			table.insert(childNames, child.Name .. " (" .. child.ClassName .. ")")
		end
		warn("[GunModelManager] Character children:", table.concat(childNames, ", "))
		return
	end
	print("[GunModelManager] Found hand:", rightHand.Name)

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		warn("[GunModelManager] FAILED: No gun config for", gunName)
		return
	end
	print("[GunModelManager] Gun config found, ModelName:", gunStats.ModelName)

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		warn("[GunModelManager] FAILED: ReplicatedStorage.Assets folder NOT FOUND")
		-- List ReplicatedStorage children
		local children = {}
		for _, child in ReplicatedStorage:GetChildren() do
			table.insert(children, child.Name)
		end
		warn("[GunModelManager] ReplicatedStorage children:", table.concat(children, ", "))
		return
	end
	print("[GunModelManager] Assets folder found")

	local weaponsFolder = assetsFolder:FindFirstChild("Weapons")
	if not weaponsFolder then
		warn("[GunModelManager] FAILED: Assets.Weapons folder NOT FOUND")
		local children = {}
		for _, child in assetsFolder:GetChildren() do
			table.insert(children, child.Name)
		end
		warn("[GunModelManager] Assets children:", table.concat(children, ", "))
		return
	end
	print("[GunModelManager] Weapons folder found")

	-- List all available weapon models
	local availableModels = {}
	for _, child in weaponsFolder:GetChildren() do
		table.insert(availableModels, child.Name)
	end
	print("[GunModelManager] Available weapon models:", table.concat(availableModels, ", "))

	local modelName = gunStats.ModelName or gunName
	local weaponAsset = weaponsFolder:FindFirstChild(modelName) :: Model?
	if not weaponAsset then
		warn("[GunModelManager] FAILED: Weapon model not found:", modelName, "- available:", table.concat(availableModels, ", "))
		return
	end
	print("[GunModelManager] Found weapon asset:", modelName, "class:", weaponAsset.ClassName)

	GunModelManager.RemoveEquippedGun(character)

	local weaponModel = weaponAsset:Clone()
	weaponModel.Name = GunModelManager.EQUIPPED_GUN_NAME
	weaponModel:SetAttribute("GunName", gunName)

	-- Debug: list cloned model contents
	local partCount = 0
	for _, descendant in weaponModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
			partCount += 1
			print("[GunModelManager] Part:", descendant.Name, "Size:", descendant.Size, "Transparency:", descendant.Transparency)
		end
	end
	print("[GunModelManager] Cloned model has", partCount, "BaseParts")

	local weaponPart = weaponModel.PrimaryPart or weaponModel:FindFirstChildWhichIsA("BasePart")
	if not weaponPart then
		warn("[GunModelManager] FAILED: Cloned model has no PrimaryPart and no BasePart children")
		weaponModel:Destroy()
		return
	end
	print("[GunModelManager] Using weapon part:", weaponPart.Name, "as weld target (PrimaryPart:", tostring(weaponModel.PrimaryPart ~= nil), ")")

	local weld = Instance.new("Motor6D")
	weld.Name = "WeaponWeld"
	weld.Part0 = rightHand
	weld.Part1 = weaponPart :: BasePart
	local baseC0 = CFrame.new(0, -0.2, -0.5) * CFrame.Angles(math.rad(-90), math.rad(-90), math.rad(0))
	local offset = WeaponOffsets[gunName]
	weld.C0 = if offset then baseC0 * offset else baseC0
	weld.Parent = rightHand

	weaponModel.Parent = character

	-- Verify it actually parented
	local verify = character:FindFirstChild(GunModelManager.EQUIPPED_GUN_NAME)
	if verify then
		print("[GunModelManager] SUCCESS: Weapon model", modelName, "attached to", player.Name, "- parented to character")
	else
		warn("[GunModelManager] FAILED: Weapon model was parented but FindFirstChild can't find it!")
	end
end

return GunModelManager
