--!strict

-- client-side powerup HUD: shows active powerup timers,
-- flash effects on collection, and pickup notifications

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PowerupConfig = require(ReplicatedStorage.Modules.PowerupConfig)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PowerupSpawnedRemote = RemoteService.GetRemote("PowerupSpawned") :: RemoteEvent
local PowerupCollectedRemote = RemoteService.GetRemote("PowerupCollected") :: RemoteEvent
local PowerupExpiredRemote = RemoteService.GetRemote("PowerupExpired") :: RemoteEvent
local PowerupActivatedRemote = RemoteService.GetRemote("PowerupActivated") :: RemoteEvent
local PowerupDeactivatedRemote = RemoteService.GetRemote("PowerupDeactivated") :: RemoteEvent

--------------------------------------------------
-- HUD Setup
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PowerupHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 6
screenGui.Parent = playerGui

-- timer container (top-center)
local timerContainer = Instance.new("Frame")
timerContainer.Name = "TimerContainer"
timerContainer.Size = UDim2.new(0, 300, 0, 200)
timerContainer.Position = UDim2.new(0.5, -150, 0, 80)
timerContainer.BackgroundTransparency = 1
timerContainer.Parent = screenGui

local timerLayout = Instance.new("UIListLayout")
timerLayout.FillDirection = Enum.FillDirection.Vertical
timerLayout.Padding = UDim.new(0, 4)
timerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
timerLayout.SortOrder = Enum.SortOrder.Name
timerLayout.Parent = timerContainer

-- notification container (center screen, for flash text)
local notifContainer = Instance.new("Frame")
notifContainer.Name = "NotifContainer"
notifContainer.Size = UDim2.new(1, 0, 0, 60)
notifContainer.Position = UDim2.new(0, 0, 0.35, 0)
notifContainer.BackgroundTransparency = 1
notifContainer.Parent = screenGui

--------------------------------------------------
-- Active Timer State
--------------------------------------------------

-- { [powerupName]: { frame: Frame, label: TextLabel, endTime: number } }
local activeTimers: { [string]: { frame: Frame, label: TextLabel, endTime: number } } = {}

--------------------------------------------------
-- Timer Management
--------------------------------------------------

local function CreateTimerBar(powerupName: string, duration: number)
	local stats = PowerupConfig.Powerups[powerupName]
	if not stats then
		return
	end

	-- remove existing timer for this powerup (refresh)
	local existing = activeTimers[powerupName]
	if existing then
		existing.frame:Destroy()
		activeTimers[powerupName] = nil
	end

	local frame = Instance.new("Frame")
	frame.Name = powerupName
	frame.Size = UDim2.new(1, 0, 0, 30)
	frame.BackgroundColor3 = stats.Color
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "TimerLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = stats.DisplayName .. " - " .. tostring(duration) .. "s"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = stats.Color
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = frame

	frame.Parent = timerContainer

	activeTimers[powerupName] = {
		frame = frame,
		label = label,
		endTime = tick() + duration,
	}
end

local function RemoveTimerBar(powerupName: string)
	local timer = activeTimers[powerupName]
	if not timer then
		return
	end

	activeTimers[powerupName] = nil

	-- fade out
	local tween = TweenService:Create(timer.frame, TweenInfo.new(0.3), {
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		timer.frame:Destroy()
	end)
end

--------------------------------------------------
-- Notification Flash
--------------------------------------------------

local function ShowPowerupNotification(powerupName: string)
	local stats = PowerupConfig.Powerups[powerupName]
	if not stats then
		return
	end

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = stats.DisplayName
	label.TextColor3 = stats.Color
	label.TextScaled = true
	label.TextTransparency = 0
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = notifContainer

	-- scale up then fade out
	task.delay(1.5, function()
		local tween = TweenService:Create(label, TweenInfo.new(0.5), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			label:Destroy()
		end)
	end)

	-- screen flash
	local flash = Instance.new("Frame")
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = stats.Color
	flash.BackgroundTransparency = 0.8
	flash.BorderSizePixel = 0
	flash.ZIndex = 100
	flash.Parent = screenGui

	local flashTween = TweenService:Create(flash, TweenInfo.new(0.4), {
		BackgroundTransparency = 1,
	})
	flashTween:Play()
	flashTween.Completed:Connect(function()
		flash:Destroy()
	end)
end

--------------------------------------------------
-- Timer Update Loop
--------------------------------------------------

RunService.Heartbeat:Connect(function()
	for powerupName, timer in activeTimers do
		local remaining = math.max(0, timer.endTime - tick())
		local stats = PowerupConfig.Powerups[powerupName]
		if stats then
			timer.label.Text = stats.DisplayName .. " - " .. tostring(math.ceil(remaining)) .. "s"
		end

		-- flash when about to expire
		if remaining <= 5 and remaining > 0 then
			local flash = math.sin(tick() * 8) > 0
			timer.frame.BackgroundTransparency = if flash then 0.3 else 0.7
		end

		if remaining <= 0 then
			RemoveTimerBar(powerupName)
		end
	end
end)

--------------------------------------------------
-- Event Listeners
--------------------------------------------------

PowerupActivatedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	ShowPowerupNotification(data.powerupName)

	if data.duration and data.duration > 0 then
		CreateTimerBar(data.powerupName, data.duration)
	end
end)

PowerupDeactivatedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	RemoveTimerBar(data.powerupName)
end)

PowerupCollectedRemote.OnClientEvent:Connect(function(_data: any)
	-- collection VFX handled by PowerupActivated
end)
