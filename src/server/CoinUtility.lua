--!strict

-- server module: coin system bridge utilities
-- provides get/deduct/refund/add for player coins
-- tries bindable -> leaderstats -> attribute fallbacks

local ServerScriptService = game:GetService("ServerScriptService")

local CoinUtility = {}

-- get current coin count for a player
function CoinUtility.GetCoins(player: Player): number
	-- try bindable first (if economy system exists)
	local getCoins = ServerScriptService:FindFirstChild("GetCoinsBindable") :: BindableFunction?
	if getCoins then
		local success, result = pcall(function()
			return getCoins:Invoke(player)
		end)
		if success and typeof(result) == "number" then
			return result
		end
	end

	-- fallback: leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local coins = leaderstats:FindFirstChild("Coins")
		if coins and coins:IsA("IntValue") then
			return coins.Value
		end
	end

	-- fallback: player attribute
	return player:GetAttribute("Coins") or 0
end

-- deduct coins, returns true if successful
function CoinUtility.Deduct(player: Player, amount: number): boolean
	local current = CoinUtility.GetCoins(player)
	if current < amount then
		return false
	end

	-- try bindable
	local spendCoins = ServerScriptService:FindFirstChild("SpendCoinsBindable") :: BindableFunction?
	if spendCoins then
		local success, result = pcall(function()
			return spendCoins:Invoke(player, amount)
		end)
		if success then
			return result == true
		end
	end

	-- fallback: leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local coins = leaderstats:FindFirstChild("Coins")
		if coins and coins:IsA("IntValue") then
			if coins.Value >= amount then
				coins.Value -= amount
				return true
			end
		end
	end

	-- fallback: attribute
	local attrCoins = player:GetAttribute("Coins")
	if attrCoins and typeof(attrCoins) == "number" and attrCoins >= amount then
		player:SetAttribute("Coins", attrCoins - amount)
		return true
	end

	return false
end

-- refund coins to player
function CoinUtility.Refund(player: Player, amount: number)
	local addCoins = ServerScriptService:FindFirstChild("AddCoinsEvent") :: BindableEvent?
	if addCoins then
		addCoins:Fire(player, amount)
		return
	end

	-- fallback: leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local coins = leaderstats:FindFirstChild("Coins")
		if coins and coins:IsA("IntValue") then
			coins.Value += amount
			return
		end
	end

	-- fallback: attribute
	local attrCoins = player:GetAttribute("Coins") or 0
	player:SetAttribute("Coins", attrCoins + amount)
end

return CoinUtility
