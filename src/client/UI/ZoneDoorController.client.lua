--!strict

-- client-side zone door feedback: shows notification when a door is opened

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ZoneDoorOpenedRemote = RemoteService.GetRemote("ZoneDoorOpened") :: RemoteEvent

--------------------------------------------------
-- HUD Setup
--------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ZoneDoorHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 6
screenGui.Parent = playerGui

--------------------------------------------------
-- Notification
--------------------------------------------------

local function ShowDoorNotification(doorName: string, openedBy: string)
	local frame = Instance.new("Frame")
	frame.Name = "DoorNotif"
	frame.Size = UDim2.new(0, 400, 0, 60)
	frame.Position = UDim2.new(0.5, -200, 0, 100)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 200, 50)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -20, 0, 28)
	titleLabel.Position = UDim2.new(0, 10, 0, 4)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = doorName .. " Opened"
	titleLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
	titleLabel.TextSize = 20
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	titleLabel.Parent = frame

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.new(1, -20, 0, 20)
	subtitleLabel.Position = UDim2.new(0, 10, 0, 32)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = "Opened by " .. openedBy
	subtitleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	subtitleLabel.TextSize = 14
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
	subtitleLabel.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular)
	subtitleLabel.Parent = frame

	-- slide in from top
	frame.Position = UDim2.new(0.5, -200, 0, -70)
	TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -200, 0, 100),
	}):Play()

	-- fade out after delay
	task.delay(3, function()
		if frame and frame.Parent then
			local fadeOut = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, -200, 0, 70),
			})
			fadeOut:Play()

			-- fade child labels too
			for _, child in frame:GetChildren() do
				if child:IsA("TextLabel") then
					TweenService:Create(child, TweenInfo.new(0.5), {
						TextTransparency = 1,
					}):Play()
				elseif child:IsA("UIStroke") then
					TweenService:Create(child, TweenInfo.new(0.5), {
						Transparency = 1,
					}):Play()
				end
			end

			task.delay(0.6, function()
				if frame and frame.Parent then
					frame:Destroy()
				end
			end)
		end
	end)
end

--------------------------------------------------
-- Event Listener
--------------------------------------------------

ZoneDoorOpenedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local doorName = data.doorName or "Zone"
	local openedBy = data.openedBy or "Unknown"

	ShowDoorNotification(doorName, openedBy)
end)
