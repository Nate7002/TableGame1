local SpinTable = {}

SpinTable.RarityColors = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(0, 255, 100),
	Rare = Color3.fromRGB(0, 150, 255),
	Epic = Color3.fromRGB(170, 0, 255),
	Mythic = Color3.fromRGB(255, 215, 0),
	Ultra = Color3.fromRGB(255, 0, 0) -- Red/Rainbow placeholder
}

SpinTable.Items = {
	-- Common (50%)
	{ id = "RobuxCoin", name = "Robux Coin", chance = 12.5, value = 50, rarity = "Common" },
	{ id = "Robuck", name = "Robuck", chance = 12.5, value = 75, rarity = "Common" },
	{ id = "CoinPile", name = "Coin Pile", chance = 10, value = 100, rarity = "Common" },
	{ id = "CoinStack", name = "Coin Stack", chance = 8, value = 150, rarity = "Common" },
	{ id = "CashBundle", name = "Cash Bundle", chance = 7, value = 200, rarity = "Common" },
	
	-- Uncommon (28%)
	{ id = "SilverBar", name = "Silver Bar", chance = 9, value = 300, rarity = "Uncommon" },
	{ id = "SilverStack", name = "Silver Stack", chance = 8, value = 400, rarity = "Uncommon" },
	{ id = "MoneyBag", name = "Money Bag", chance = 6.5, value = 600, rarity = "Uncommon" },
	{ id = "CoinCrate", name = "Coin Crate", chance = 4.5, value = 800, rarity = "Uncommon" },
	
	-- Rare (16%)
	{ id = "GoldBar", name = "Gold Bar", chance = 6.5, value = 1200, rarity = "Rare" },
	{ id = "GoldStack", name = "Gold Stack", chance = 5, value = 1800, rarity = "Rare" },
	{ id = "RobuxPile", name = "Robux Pile", chance = 4.5, value = 2500, rarity = "Rare" },
	
	-- Epic (5%)
	{ id = "Crown", name = "Crown", chance = 2, value = 4000, rarity = "Epic" },
	{ id = "Trophy", name = "Trophy", chance = 1.75, value = 5500, rarity = "Epic" },
	{ id = "PirateChest", name = "Pirate Chest", chance = 1.25, value = 7500, rarity = "Epic" },
	
	-- Mythic (0.75%)
	{ id = "Diamond", name = "Diamond", chance = 0.75, value = 12000, rarity = "Mythic" },
	
	-- Ultra (0.25%)
	{ id = "VoidStar", name = "Void Star", chance = 0.25, value = 50000, rarity = "Ultra" }
}

-- Public API: Get full item pool
function SpinTable.GetPool()
	return SpinTable.Items
end

-- Pick a random item based on weights
function SpinTable.PickRandom()
	local totalWeight = 0
	for _, item in ipairs(SpinTable.Items) do
		totalWeight += item.chance
	end
	
	local roll = math.random() * totalWeight
	local current = 0
	
	for _, item in ipairs(SpinTable.Items) do
		current += item.chance
		if roll <= current then
			return item
		end
	end
	
	return SpinTable.Items[#SpinTable.Items] -- Fallback
end

-- Debug Simulation
function SpinTable.Simulate(n)
	print(string.format("Simulating %d spins...", n))
	local counts = {Common=0, Uncommon=0, Rare=0, Epic=0, Mythic=0, Ultra=0}
	
	for i = 1, n do
		local item = SpinTable.PickRandom()
		counts[item.rarity] = (counts[item.rarity] or 0) + 1
	end
	
	for k, v in pairs(counts) do
		print(string.format("%s: %d (%.2f%%)", k, v, (v/n)*100))
	end
end

return SpinTable
