--!strict

-- server script: weapon loadout management
-- creates weapon tools in player backpack on character spawn

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local GiveLoadoutRemote = RemoteService.GetRemote("GiveLoadout") :: RemoteEvent

local DEFAULT_LOADOUT = { "AR", "PumpShotgun", "SMG", "Sniper", "Pistol" }

local function CreateWeaponTool(player: Player, gunName: string, slotIndex: number)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return
	end

	local gunStats = GunConfig.Guns[gunName]
	if not gunStats then
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = gunName
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	tool:SetAttribute("GunName", gunName)
	tool:SetAttribute("SlotIndex", slotIndex)

	tool.Parent = backpack
end

local function OnCharacterAdded(player: Player)
	task.wait(0.5)

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("GunName") then
				child:Destroy()
			end
		end
	end

	for i, gunName in DEFAULT_LOADOUT do
		CreateWeaponTool(player, gunName, i)
	end

	GiveLoadoutRemote:FireClient(player, DEFAULT_LOADOUT)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		OnCharacterAdded(player)
	end)

	if player.Character then
		OnCharacterAdded(player)
	end
end)

for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function()
		OnCharacterAdded(player)
	end)

	if player.Character then
		OnCharacterAdded(player)
	end
end
