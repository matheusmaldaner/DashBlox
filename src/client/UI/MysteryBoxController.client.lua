--!strict

-- client-side mystery box visuals: weapon cycling animation,
-- light beam, teddy bear effect, and relocate VFX

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MysteryBoxConfig = require(ReplicatedStorage.Modules.MysteryBoxConfig)
local GunConfig = require(ReplicatedStorage.Modules.Guns.GunConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local player = Players.LocalPlayer

--------------------------------------------------
-- Remotes
--------------------------------------------------

local MysteryBoxOpenedRemote = RemoteService.GetRemote("MysteryBoxOpened") :: RemoteEvent
local MysteryBoxResultRemote = RemoteService.GetRemote("MysteryBoxResult") :: RemoteEvent
local MysteryBoxPickedUpRemote = RemoteService.GetRemote("MysteryBoxPickedUp") :: RemoteEvent
local MysteryBoxExpiredRemote = RemoteService.GetRemote("MysteryBoxExpired") :: RemoteEvent
local MysteryBoxRelocateRemote = RemoteService.GetRemote("MysteryBoxRelocate") :: RemoteEvent
local MysteryBoxReappearRemote = RemoteService.GetRemote("MysteryBoxReappear") :: RemoteEvent

--------------------------------------------------
-- State
--------------------------------------------------

local cyclingGui: BillboardGui? = nil
local cyclingLabel: TextLabel? = nil
local resultGui: BillboardGui? = nil
local lightBeamPart: Part? = nil

--------------------------------------------------
-- Helpers
--------------------------------------------------

-- find the mystery box model in workspace
local function GetBoxModel(): Model?
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and instance:GetAttribute("MysteryBox") then
			return instance :: Model
		end
	end
	-- fallback: find by CollectionService tag
	local CollectionService = game:GetService("CollectionService")
	local tagged = CollectionService:GetTagged("MysteryBox")
	if #tagged > 0 then
		return tagged[1] :: Model
	end
	return nil
end

-- get a random weapon name for cycling animation (visual only)
local function GetRandomWeaponName(): (string, string)
	local pool = MysteryBoxConfig.WeaponPool
	local entry = pool[math.random(1, #pool)]
	return entry.gunName, entry.rarity
end

--------------------------------------------------
-- Weapon Cycling Animation
--------------------------------------------------

-- creates a billboard gui above the box showing weapon names cycling
local function StartCyclingAnimation(boxModel: Model)
	-- cleanup any existing
	StopCyclingAnimation()

	-- create billboard above the box
	cyclingGui = Instance.new("BillboardGui")
	local gui = cyclingGui :: BillboardGui
	gui.Name = "MysteryBoxCycling"
	gui.Size = UDim2.new(0, 200, 0, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = boxModel.PrimaryPart or boxModel:FindFirstChildWhichIsA("BasePart")
	gui.Parent = player.PlayerGui

	cyclingLabel = Instance.new("TextLabel")
	local label = cyclingLabel :: TextLabel
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	-- cycling animation: flash through weapon names with decelerating speed
	local flashCount = MysteryBoxConfig.CyclingFlashCount
	local startInterval = MysteryBoxConfig.CyclingStartInterval
	local endInterval = MysteryBoxConfig.CyclingEndInterval

	task.spawn(function()
		for i = 1, flashCount do
			if not cyclingLabel then
				break
			end

			-- pick random weapon for display
			local gunName, rarity = GetRandomWeaponName()
			local gunStats = GunConfig.Guns[gunName]
			local displayName = if gunStats then gunStats.Name else gunName
			local rarityColor = MysteryBoxConfig.RarityColors[rarity]
				or Color3.fromRGB(255, 255, 255)

			(cyclingLabel :: TextLabel).Text = displayName
			(cyclingLabel :: TextLabel).TextColor3 = rarityColor

			-- decelerate: lerp from start interval to end interval
			local alpha = i / flashCount
			-- ease out quad for satisfying slowdown
			local easedAlpha = 1 - (1 - alpha) * (1 - alpha)
			local interval = startInterval + (endInterval - startInterval) * easedAlpha
			task.wait(interval)
		end
	end)
end

-- shows the teddy bear instead of a weapon
local function ShowTeddyBear(boxModel: Model)
	StopCyclingAnimation()

	cyclingGui = Instance.new("BillboardGui")
	local gui = cyclingGui :: BillboardGui
	gui.Name = "MysteryBoxTeddy"
	gui.Size = UDim2.new(0, 200, 0, 60)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = boxModel.PrimaryPart or boxModel:FindFirstChildWhichIsA("BasePart")
	gui.Parent = player.PlayerGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.Text = "BYE BYE!"
	label.TextColor3 = Color3.fromRGB(255, 80, 80)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	-- fade out after a moment
	task.delay(2.0, function()
		if gui and gui.Parent then
			local tween = TweenService:Create(label, TweenInfo.new(1.0), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
			tween:Play()
			task.delay(1.0, function()
				StopCyclingAnimation()
			end)
		end
	end)
end

local function StopCyclingAnimation()
	if cyclingGui then
		(cyclingGui :: BillboardGui):Destroy()
		cyclingGui = nil
		cyclingLabel = nil
	end
end

--------------------------------------------------
-- Result Display
--------------------------------------------------

-- shows the final weapon name floating above the box
local function ShowResult(boxModel: Model, gunName: string, rarity: string, isDuplicate: boolean)
	StopCyclingAnimation()

	resultGui = Instance.new("BillboardGui")
	local gui = resultGui :: BillboardGui
	gui.Name = "MysteryBoxResult"
	gui.Size = UDim2.new(0, 250, 0, 60)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = boxModel.PrimaryPart or boxModel:FindFirstChildWhichIsA("BasePart")
	gui.Parent = player.PlayerGui

	local gunStats = GunConfig.Guns[gunName]
	local displayName = if gunStats then gunStats.Name else gunName
	local rarityColor = MysteryBoxConfig.RarityColors[rarity] or Color3.fromRGB(255, 255, 255)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.6, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.Text = displayName
	label.TextColor3 = rarityColor
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	-- subtitle (duplicate indicator)
	if isDuplicate then
		local subtitle = Instance.new("TextLabel")
		subtitle.Size = UDim2.new(1, 0, 0.35, 0)
		subtitle.Position = UDim2.new(0, 0, 0.6, 0)
		subtitle.BackgroundTransparency = 1
		subtitle.TextScaled = true
		subtitle.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json")
		subtitle.Text = "AMMO REFILL"
		subtitle.TextColor3 = Color3.fromRGB(100, 255, 100)
		subtitle.TextStrokeTransparency = 0.5
		subtitle.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		subtitle.Parent = gui
	end
end

local function HideResult()
	if resultGui then
		(resultGui :: BillboardGui):Destroy()
		resultGui = nil
	end
end

--------------------------------------------------
-- Light Beam Effect
--------------------------------------------------

-- creates a tall blue light beam at a position to mark box location
local function CreateLightBeam(position: Vector3)
	DestroyLightBeam()

	lightBeamPart = Instance.new("Part")
	local beam = lightBeamPart :: Part
	beam.Name = "MysteryBoxBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = MysteryBoxConfig.LightBeamColor
	beam.Size = Vector3.new(0.5, MysteryBoxConfig.LightBeamHeight, 0.5)
	beam.Transparency = 0.5
	beam.CFrame = CFrame.new(
		position.X,
		position.Y + MysteryBoxConfig.LightBeamHeight / 2,
		position.Z
	)
	beam.Parent = workspace

	-- pulse animation
	task.spawn(function()
		while beam and beam.Parent do
			local tweenOut = TweenService:Create(beam, TweenInfo.new(1.0), {
				Transparency = 0.8,
			})
			tweenOut:Play()
			tweenOut.Completed:Wait()

			if not beam or not beam.Parent then
				break
			end

			local tweenIn = TweenService:Create(beam, TweenInfo.new(1.0), {
				Transparency = 0.4,
			})
			tweenIn:Play()
			tweenIn.Completed:Wait()
		end
	end)
end

local function DestroyLightBeam()
	if lightBeamPart then
		(lightBeamPart :: Part):Destroy()
		lightBeamPart = nil
	end
end

--------------------------------------------------
-- Event Listeners
--------------------------------------------------

MysteryBoxOpenedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local boxModel = GetBoxModel()
	if not boxModel then
		return
	end

	if data.isTeddyBear then
		-- start cycling then show teddy bear
		StartCyclingAnimation(boxModel)
		task.delay(MysteryBoxConfig.CyclingDuration * 0.8, function()
			ShowTeddyBear(boxModel)
		end)
	else
		StartCyclingAnimation(boxModel)
	end
end)

MysteryBoxResultRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local boxModel = GetBoxModel()
	if not boxModel then
		return
	end

	ShowResult(boxModel, data.gunName, data.rarity, data.isDuplicate or false)
end)

MysteryBoxPickedUpRemote.OnClientEvent:Connect(function(_data: any)
	HideResult()
end)

MysteryBoxExpiredRemote.OnClientEvent:Connect(function(_data: any)
	HideResult()
end)

MysteryBoxRelocateRemote.OnClientEvent:Connect(function(data: any)
	HideResult()
	StopCyclingAnimation()
	DestroyLightBeam()
end)

MysteryBoxReappearRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	if data.position and typeof(data.position) == "Vector3" then
		CreateLightBeam(data.position)

		-- auto-destroy beam after duration
		task.delay(MysteryBoxConfig.LightBeamDuration, function()
			DestroyLightBeam()
		end)
	end
end)
