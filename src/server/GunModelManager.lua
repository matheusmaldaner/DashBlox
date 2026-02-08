--!strict

-- server module: weapon model attachment to player characters
-- handles attaching/removing 3D weapon models, muzzle positions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)

local GunModelManager = {}

GunModelManager.EQUIPPED_GUN_NAME = "EquippedGun"

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
	local character = player.Character
	if not character then
		return
	end

	local rightHand = GetRightHand(character)
	if not rightHand then
		return
	end

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		return
	end

	local weaponsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not weaponsFolder then
		return
	end
	weaponsFolder = weaponsFolder:FindFirstChild("Weapons")
	if not weaponsFolder then
		return
	end

	local modelName = gunStats.ModelName or gunName
	local weaponAsset = weaponsFolder:FindFirstChild(modelName) :: Model?
	if not weaponAsset then
		warn("Weapon not found:", modelName)
		return
	end

	GunModelManager.RemoveEquippedGun(character)

	local weaponModel = weaponAsset:Clone()
	weaponModel.Name = GunModelManager.EQUIPPED_GUN_NAME
	weaponModel:SetAttribute("GunName", gunName)

	for _, descendant in weaponModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end

	local weaponPart = weaponModel.PrimaryPart or weaponModel:FindFirstChildWhichIsA("BasePart")
	if not weaponPart then
		weaponModel:Destroy()
		return
	end

	local weld = Instance.new("Motor6D")
	weld.Name = "WeaponWeld"
	weld.Part0 = rightHand
	weld.Part1 = weaponPart :: BasePart
	weld.C0 = CFrame.new(0, -0.2, -0.5) * CFrame.Angles(math.rad(-90), math.rad(-90), math.rad(0))
	weld.Parent = rightHand

	weaponModel.Parent = character
end

return GunModelManager
