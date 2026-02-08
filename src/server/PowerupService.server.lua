--!strict

-- server-side powerup system: spawns powerup pickups on zombie death,
-- handles collection, applies timed/instant effects, manages expiry

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PowerupConfig = require(ReplicatedStorage.Modules.PowerupConfig)
local CoinUtility = require(script.Parent.CoinUtility)
local RemoteService = require(ReplicatedStorage.Modules.RemoteService)

local PowerupSpawnedRemote = RemoteService.GetRemote("PowerupSpawned") :: RemoteEvent
local PowerupCollectedRemote = RemoteService.GetRemote("PowerupCollected") :: RemoteEvent
local PowerupExpiredRemote = RemoteService.GetRemote("PowerupExpired") :: RemoteEvent
local PowerupActivatedRemote = RemoteService.GetRemote("PowerupActivated") :: RemoteEvent
local PowerupDeactivatedRemote = RemoteService.GetRemote("PowerupDeactivated") :: RemoteEvent
local ReloadAllWeaponsRemote = RemoteService.GetRemote("ReloadAllWeapons") :: RemoteEvent

--------------------------------------------------
-- Active Powerup State
--------------------------------------------------

-- global active effects: { [powerupName]: expiryTick }
local activeEffects: { [string]: number } = {}

-- active pickup parts on the ground
local activePickups: { [BasePart]: { powerupName: string, expiryTime: number } } = {}

--------------------------------------------------
-- Public Query API (other server scripts check these)
--------------------------------------------------

-- create bindable for other scripts to check powerup state
local function CreateQueryBindable()
	local existing = ServerScriptService:FindFirstChild("PowerupQueryBindable")
	if existing then
		existing:Destroy()
	end

	local bindable = Instance.new("BindableFunction")
	bindable.Name = "PowerupQueryBindable"
	bindable.Parent = ServerScriptService

	bindable.OnInvoke = function(query: string): any
		if query == "IsInstaKill" then
			local expiry = activeEffects["InstaKill"]
			return expiry ~= nil and tick() < expiry
		elseif query == "IsDoublePoints" then
			local expiry = activeEffects["DoublePoints"]
			return expiry ~= nil and tick() < expiry
		elseif query == "IsFireSale" then
			local expiry = activeEffects["FireSale"]
			return expiry ~= nil and tick() < expiry
		end
		return false
	end
end

--------------------------------------------------
-- Effect Application
--------------------------------------------------

local function ApplyMaxAmmo()
	for _, player in Players:GetPlayers() do
		ReloadAllWeaponsRemote:FireClient(player)
	end
end

local function ApplyNuke()
	-- find all zombies and kill them
	local coinsPerZombie = 400
	local collector: Player? = nil

	-- find any alive player to attribute coins
	local players = Players:GetPlayers()
	if #players > 0 then
		collector = players[1]
	end

	local zombiesKilled = 0
	for _, model in workspace:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("IsZombie") then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
				zombiesKilled += 1
			end
		end
	end

	-- award coins to all players
	if zombiesKilled > 0 then
		local totalCoins = zombiesKilled * coinsPerZombie
		for _, player in players do
			CoinUtility.Refund(player, totalCoins)
		end
	end
end

local function ApplyCarpenter()
	-- repair all barricades (set all parts to CanCollide=true, Transparency=0)
	local barricadeFolder = workspace:FindFirstChild("Map")
	if barricadeFolder then
		barricadeFolder = barricadeFolder:FindFirstChild("Barricades")
	end

	if not barricadeFolder then
		return
	end

	for _, barricade in barricadeFolder:GetChildren() do
		if barricade:IsA("Model") then
			for _, part in barricade:GetDescendants() do
				if part:IsA("BasePart") and part.Name ~= "Repair" then
					part.CanCollide = true
					part.Transparency = 0
				end
			end
		end
	end
end

local function ActivateTimedEffect(powerupName: string)
	local stats = PowerupConfig.Powerups[powerupName]
	if not stats or stats.Duration <= 0 then
		return
	end

	activeEffects[powerupName] = tick() + stats.Duration

	PowerupActivatedRemote:FireAllClients({
		powerupName = powerupName,
		duration = stats.Duration,
	})

	-- schedule deactivation
	task.delay(stats.Duration, function()
		-- only deactivate if this is still the same activation
		local expiry = activeEffects[powerupName]
		if expiry and tick() >= expiry then
			activeEffects[powerupName] = nil
			PowerupDeactivatedRemote:FireAllClients({
				powerupName = powerupName,
			})
		end
	end)
end

local function ApplyPowerup(powerupName: string, _collector: Player)
	local stats = PowerupConfig.Powerups[powerupName]
	if not stats then
		return
	end

	if stats.Duration > 0 then
		-- timed effect (extends if already active)
		ActivateTimedEffect(powerupName)
	else
		-- instant effect
		if powerupName == "MaxAmmo" then
			ApplyMaxAmmo()
		elseif powerupName == "Nuke" then
			ApplyNuke()
		elseif powerupName == "Carpenter" then
			ApplyCarpenter()
		end

		-- still notify clients for flash/sound
		PowerupActivatedRemote:FireAllClients({
			powerupName = powerupName,
			duration = 0,
		})
	end
end

--------------------------------------------------
-- Pickup Spawning
--------------------------------------------------

local function CreatePickupPart(position: Vector3, powerupName: string): BasePart
	local stats = PowerupConfig.Powerups[powerupName]

	local part = Instance.new("Part")
	part.Name = "Powerup_" .. powerupName
	part.Size = PowerupConfig.PickupSize
	part.Anchored = true
	part.CanCollide = false
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = stats.Color
	part.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
	part:SetAttribute("PowerupName", powerupName)

	-- point light for glow
	local light = Instance.new("PointLight")
	light.Color = stats.Color
	light.Brightness = 3
	light.Range = 12
	light.Parent = part

	-- billboard label
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 150, 0, 40)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	label.Text = stats.DisplayName
	label.TextColor3 = stats.Color
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = gui

	part.Parent = workspace

	return part
end

local function SpawnPowerup(position: Vector3)
	local powerupName = PowerupConfig.PickRandomPowerup()
	local part = CreatePickupPart(position, powerupName)

	local expiryTime = tick() + PowerupConfig.PickupLifetime
	activePickups[part] = {
		powerupName = powerupName,
		expiryTime = expiryTime,
	}

	PowerupSpawnedRemote:FireAllClients({
		powerupName = powerupName,
		position = position,
	})

	-- auto-despawn timer
	task.delay(PowerupConfig.PickupLifetime, function()
		if activePickups[part] then
			activePickups[part] = nil
			PowerupExpiredRemote:FireAllClients({
				powerupName = powerupName,
			})
			if part and part.Parent then
				part:Destroy()
			end
		end
	end)
end

--------------------------------------------------
-- Pickup Collection (touch detection)
--------------------------------------------------

local function SetupPickupTouch(part: BasePart, powerupName: string)
	part.Touched:Connect(function(otherPart: BasePart)
		-- check if a player touched it
		local character = otherPart:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end

		local player: Player? = nil
		for _, p in Players:GetPlayers() do
			if p.Character == character then
				player = p
				break
			end
		end

		if not player then
			return
		end

		-- check if pickup is still active
		local pickupData = activePickups[part]
		if not pickupData then
			return
		end

		-- collect it
		activePickups[part] = nil

		PowerupCollectedRemote:FireAllClients({
			powerupName = powerupName,
			collectorId = player.UserId,
		})

		ApplyPowerup(powerupName, player)

		if part and part.Parent then
			part:Destroy()
		end
	end)
end

--------------------------------------------------
-- Zombie Death Hook (BindableEvent)
--------------------------------------------------

local function CreateDeathHook()
	local existing = ServerScriptService:FindFirstChild("PowerupDropEvent")
	if existing then
		existing:Destroy()
	end

	local dropEvent = Instance.new("BindableEvent")
	dropEvent.Name = "PowerupDropEvent"
	dropEvent.Parent = ServerScriptService

	dropEvent.Event:Connect(function(position: Vector3)
		-- roll for powerup drop
		if math.random() <= PowerupConfig.DropChance then
			local powerupName = PowerupConfig.PickRandomPowerup()
			local part = CreatePickupPart(position, powerupName)
			SetupPickupTouch(part, powerupName)

			local expiryTime = tick() + PowerupConfig.PickupLifetime
			activePickups[part] = {
				powerupName = powerupName,
				expiryTime = expiryTime,
			}

			PowerupSpawnedRemote:FireAllClients({
				powerupName = powerupName,
				position = position,
			})

			task.delay(PowerupConfig.PickupLifetime, function()
				if activePickups[part] then
					activePickups[part] = nil
					PowerupExpiredRemote:FireAllClients({
						powerupName = powerupName,
					})
					if part and part.Parent then
						part:Destroy()
					end
				end
			end)
		end
	end)
end

--------------------------------------------------
-- Bob + Spin Animation for Pickups
--------------------------------------------------

local function StartPickupAnimations()
	local startTime = tick()
	RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		for part, data in activePickups do
			if part and part.Parent then
				local bobOffset = math.sin(elapsed * PowerupConfig.BobSpeed * math.pi * 2)
					* PowerupConfig.BobHeight / 2
				local basePos = part.Position
				local spinAngle = elapsed * PowerupConfig.SpinSpeed
				part.CFrame = CFrame.new(basePos.X, basePos.Y + bobOffset * 0.016, basePos.Z)
					* CFrame.Angles(0, math.rad(spinAngle), 0)
			end
		end
	end)
end

--------------------------------------------------
-- Initialization
--------------------------------------------------

CreateQueryBindable()
CreateDeathHook()
StartPickupAnimations()
