--!strict

-- client-side perk HUD: shows icons for active perks,
-- purchase flash effects, and listens for perk gain/loss events

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PerkConfig = require(ReplicatedStorage.Modules.PerkConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PerkPurchasedRemote = RemoteService.GetRemote("PerkPurchased") :: RemoteEvent
local PerkLostRemote = RemoteService.GetRemote("PerkLost") :: RemoteEvent
local PerkSyncAllRemote = RemoteService.GetRemote("PerkSyncAll") :: RemoteEvent

--------------------------------------------------
-- HUD Setup
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PerkHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

-- container for perk icons (bottom-left corner)
local perkContainer = Instance.new("Frame")
perkContainer.Name = "PerkContainer"
perkContainer.Size = UDim2.new(0, 300, 0, 50)
perkContainer.Position = UDim2.new(0, 10, 1, -60)
perkContainer.BackgroundTransparency = 1
perkContainer.Parent = screenGui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.Name
listLayout.Parent = perkContainer

-- track active icon frames
local perkIcons: { [string]: Frame } = {}

--------------------------------------------------
-- Icon Management
--------------------------------------------------

local function CreatePerkIcon(perkName: string): Frame
	local stats = PerkConfig.Perks[perkName]
	if not stats then
		-- fallback
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(0, 40, 0, 40)
		return frame
	end

	local frame = Instance.new("Frame")
	frame.Name = perkName
	frame.Size = UDim2.new(0, 44, 0, 44)
	frame.BackgroundColor3 = stats.Color
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = stats.Color
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Icon"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = stats.IconText
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.Parent = frame

	return frame
end

local function AddPerkIcon(perkName: string)
	if perkIcons[perkName] then
		return
	end

	local icon = CreatePerkIcon(perkName)
	icon.Parent = perkContainer
	perkIcons[perkName] = icon

	-- pop-in animation
	icon.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(icon, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 44, 0, 44),
	}):Play()
end

local function RemovePerkIcon(perkName: string)
	local icon = perkIcons[perkName]
	if not icon then
		return
	end

	perkIcons[perkName] = nil

	-- shrink-out animation
	local tween = TweenService:Create(icon, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		icon:Destroy()
	end)
end

local function ClearAllIcons()
	for perkName, icon in perkIcons do
		icon:Destroy()
	end
	perkIcons = {}
end

--------------------------------------------------
-- Purchase Flash Effect (full-screen color flash)
--------------------------------------------------

local function PlayPurchaseFlash(perkName: string)
	local stats = PerkConfig.Perks[perkName]
	if not stats then
		return
	end

	local flash = Instance.new("Frame")
	flash.Name = "PerkFlash"
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = stats.Color
	flash.BackgroundTransparency = 0.7
	flash.BorderSizePixel = 0
	flash.ZIndex = 100
	flash.Parent = screenGui

	local tween = TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		flash:Destroy()
	end)
end

--------------------------------------------------
-- Event Listeners
--------------------------------------------------

PerkPurchasedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	if data.playerId == player.UserId then
		AddPerkIcon(data.perkName)
		PlayPurchaseFlash(data.perkName)
	end
end)

PerkLostRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	if data.playerId == player.UserId then
		-- lost all perks (death)
		if data.perksLost then
			for _, perkName in data.perksLost do
				RemovePerkIcon(perkName)
			end
		else
			ClearAllIcons()
		end
	end
end)

PerkSyncAllRemote.OnClientEvent:Connect(function(_data: any)
	-- on join, sync is mainly for showing other players' perks
	-- local player starts fresh (no perks on join)
end)

-- clear icons on death
player.CharacterAdded:Connect(function()
	ClearAllIcons()
end)
