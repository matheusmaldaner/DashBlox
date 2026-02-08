--!strict

-- client-side zombie visual effects: ragdoll fade-out, explosion particles,
-- floating damage numbers

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RemoteService = require(ReplicatedStorage.Modules.RemoteService)
local ZombieConfig = require(ReplicatedStorage.Modules.Zombies.ZombieConfig)
local AudioService = require(ReplicatedStorage.Modules.Audio.AudioService)

--------------------------------------------------
-- Remotes
--------------------------------------------------

local ZombieDiedRemote = RemoteService.GetRemote("ZombieDied") :: RemoteEvent
local ZombieSpawnedRemote = RemoteService.GetRemote("ZombieSpawned") :: RemoteEvent

--------------------------------------------------
-- Ragdoll Death Effect
--------------------------------------------------

-- after ragdoll settles, fades all parts to transparent before pool cleanup
local function RagdollFadeZombie(zombieModel: Model, exploded: boolean)
	if not zombieModel or not zombieModel.Parent then
		return
	end

	-- hide healthbar immediately on death
	local healthbarGui = zombieModel:FindFirstChild("HealthbarGui")
	if healthbarGui and healthbarGui:IsA("BillboardGui") then
		healthbarGui.Enabled = false
	end

	-- hide highlight immediately so the red outline doesn't persist on the ragdoll
	local highlight = zombieModel:FindFirstChildOfClass("Highlight")
	if highlight then
		highlight.Enabled = false
	end

	-- spawn explosion particles if exploder
	if exploded then
		local position = if zombieModel.PrimaryPart
			then zombieModel.PrimaryPart.Position
			else Vector3.zero
		if position ~= Vector3.zero then
			CreateExplosionEffect(position)
		end
	end

	-- wait for ragdoll to settle before fading
	local ragdollTime = ZombieConfig.RagdollTime
	if exploded then
		ragdollTime = 0.5
	end
	task.wait(ragdollTime)

	-- fade out all parts (no shrinking, just transparency)
	local fadeTime = ZombieConfig.FadeOutTime
	local tweenInfo = TweenInfo.new(
		fadeTime,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)

	if not zombieModel or not zombieModel.Parent then
		return
	end

	for _, descendant in zombieModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			local fadeTween = TweenService:Create(descendant, tweenInfo, {
				Transparency = 1,
			})
			fadeTween:Play()
		elseif descendant:IsA("Decal") then
			local decalTween = TweenService:Create(descendant, tweenInfo, {
				Transparency = 1,
			})
			decalTween:Play()
		elseif descendant:IsA("PointLight") then
			local lightTween = TweenService:Create(descendant, tweenInfo, {
				Brightness = 0,
			})
			lightTween:Play()
		end
	end
end

--------------------------------------------------
-- Explosion Particle Effect
--------------------------------------------------

-- orange/yellow particle burst for exploder zombies
local function CreateExplosionEffect(position: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 30, 10)),
	})
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.3, 4),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(0.3, 0.8)
	particles.Rate = 0
	particles.Speed = NumberRange.new(15, 40)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.LightEmission = 1
	particles.Parent = attachment

	particles:Emit(30)

	-- cleanup after particles finish
	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

--------------------------------------------------
-- Spawn Effect (subtle ground smoke)
--------------------------------------------------

local function CreateSpawnEffect(position: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80))
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 3),
		NumberSequenceKeypoint.new(1, 0),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.5, 1.0)
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(180, 30)
	smoke.Parent = attachment

	smoke:Emit(10)

	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

--------------------------------------------------
-- Event Listeners
--------------------------------------------------

ZombieDiedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local zombieModel = data.zombieModel
	if zombieModel and typeof(zombieModel) == "Instance" and zombieModel:IsA("Model") then
		-- play death sound at zombie position immediately
		local position = if zombieModel.PrimaryPart
			then zombieModel.PrimaryPart.Position
			else data.position
		if position and typeof(position) == "Vector3" then
			local zombieType = data.zombieType or "Normal"
			AudioService.PlayZombieDeath(position, zombieType)
		end

		-- ragdoll fade runs in its own thread (yields for ragdoll settle time)
		task.spawn(RagdollFadeZombie, zombieModel, data.exploded or false)
	end
end)

ZombieSpawnedRemote.OnClientEvent:Connect(function(data: any)
	if not data then
		return
	end

	local position = data.position
	if position and typeof(position) == "Vector3" then
		CreateSpawnEffect(position)
	end
end)
