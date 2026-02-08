--!strict

-- server script: barricade repair system
-- when a player stands inside a part named "repair" within a barricade model,
-- one broken part (CanCollide == false) is repaired every second
-- (set back to CanCollide = true, Transparency = 0)

local Players = game:GetService("Players")

--------------------------------------------------
-- State
--------------------------------------------------

-- tracks which players are inside which repair zones
-- key: repair part, value: { [Player]: true }
local playersInZone: { [BasePart]: { [Player]: boolean } } = {}

-- maps repair parts to their parent barricade model
local repairToBarricade: { [BasePart]: Model } = {}

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function GetPlayerFromPart(part: BasePart): Player?
	local character = part:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if player.Character == character then
			return player
		end
	end
	return nil
end

-- find one broken part in the barricade that can be repaired
-- broken = CanCollide false, excluding the repair trigger zone itself
local function FindBrokenPart(barricadeModel: Model, repairPart: BasePart): BasePart?
	for _, descendant in barricadeModel:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and descendant ~= repairPart
			and descendant.Name ~= "Repair"
			and not descendant.CanCollide
		then
			return descendant
		end
	end
	return nil
end

--------------------------------------------------
-- Zone Detection
--------------------------------------------------

local function SetupRepairZone(repairPart: BasePart)
	local barricade = repairPart.Parent
	if not barricade or not barricade:IsA("Model") then
		warn("[BarricadeService] 'repair' part has no Model parent:", repairPart:GetFullName())
		return
	end

	-- skip if already registered
	if repairToBarricade[repairPart] then
		return
	end

	repairToBarricade[repairPart] = barricade :: Model
	playersInZone[repairPart] = {}
	print("[BarricadeService] Registered repair zone:", repairPart:GetFullName(), "| Barricade:", barricade.Name)

	repairPart.Touched:Connect(function(hit: BasePart)
		local player = GetPlayerFromPart(hit)
		if not player then
			return
		end
		local zone = playersInZone[repairPart]
		if zone then
			zone[player] = true
			print("[BarricadeService] Player ENTERED repair zone:", player.Name, "| Barricade:", barricade:GetFullName())
		end
	end)

	repairPart.TouchEnded:Connect(function(hit: BasePart)
		local player = GetPlayerFromPart(hit)
		if not player then
			return
		end
		local zone = playersInZone[repairPart]
		if zone then
			zone[player] = nil
			print("[BarricadeService] Player LEFT repair zone:", player.Name, "| Barricade:", barricade:GetFullName())
		end
	end)
end

-- clean up when a repair part is removed from workspace
local function TeardownRepairZone(repairPart: BasePart)
	playersInZone[repairPart] = nil
	repairToBarricade[repairPart] = nil
end

--------------------------------------------------
-- Discovery
--------------------------------------------------

-- scan workspace for all existing "repair" parts
local function DiscoverRepairZones()
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == "Repair" then
			SetupRepairZone(descendant)
		end
	end
end

-- handle barricades added at runtime
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("BasePart") and descendant.Name == "Repair" then
		-- defer so the parent model is fully parented
		task.defer(function()
			SetupRepairZone(descendant)
		end)
	end
end)

-- handle barricades removed at runtime
workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("BasePart") and descendant.Name == "Repair" then
		TeardownRepairZone(descendant)
	end
end)

--------------------------------------------------
-- Repair Loop (every 1 second)
--------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)

		for repairPart, playerSet in playersInZone do
			local barricade = repairToBarricade[repairPart]
			if not barricade or not barricade.Parent then
				continue
			end

			for player, _ in playerSet do
				-- validate player is still alive and in-game
				if not player.Parent or not player.Character then
					playerSet[player] = nil
					continue
				end

				local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
				if not humanoid or humanoid.Health <= 0 then
					playerSet[player] = nil
					continue
				end

				-- repair one broken part per player per tick
				local brokenPart = FindBrokenPart(barricade, repairPart)
				if brokenPart then
					brokenPart.CanCollide = true
					brokenPart.Transparency = 0
					print("[BarricadeService] REPAIRED part:", brokenPart.Name, "| Barricade:", barricade:GetFullName(), "| By:", player.Name)
				else
					print("[BarricadeService] No broken parts to repair | Barricade:", barricade:GetFullName(), "| Player:", player.Name)
				end
			end
		end
	end
end)

--------------------------------------------------
-- Cleanup on player leave
--------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	for _, playerSet in playersInZone do
		playerSet[player] = nil
	end
end)

--------------------------------------------------
-- Initialize
--------------------------------------------------

DiscoverRepairZones()
