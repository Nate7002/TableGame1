local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local SpinService = {}

-- Config
local DEBUG = false
local SPIN_TICK = 0.1 -- Fixed tick interval for spin updates (seconds)

-- Near-miss cooldown state (module-level)
local lastNearMissAt = {} -- [tableModel] = os.clock() timestamp
local tableSpinCount = {} -- [tableModel] = integer
local lastNearMissSpin = {} -- [tableModel] = integer

-- Assets
local SPIN_MODELS_PATH = "Assets/DoubleDown/SpinItems/Models"
local SPIN_UI_PATH = "Assets/DoubleDown/UI/SpinLabelBillboard"

-- Helpers
local function ResolvePath(root, path)
	local current = root
	local segments = string.split(path, "/")
	
	for _, segment in ipairs(segments) do
		local nextInstance = current:FindFirstChild(segment)
		if not nextInstance then
			if DEBUG then
				print(string.format("[SpinService] ResolvePath failed at segment '%s' in root '%s'", segment, current:GetFullName()))
				print("Available children:")
				for _, child in ipairs(current:GetChildren()) do
					print(" - " .. child.Name)
				end
			end
			return nil
		end
		current = nextInstance
	end
	
	if DEBUG then
		print(string.format("[SpinService] Resolved path: %s", current:GetFullName()))
	end
	return current
end

local function getAsset(path, name)
	-- Legacy helper - redirecting to ResolvePath where appropriate
	-- Models are usually in ServerStorage
	-- UI is usually in ReplicatedStorage
	local root = ServerStorage
	if string.sub(path, 1, 17) == "ReplicatedStorage" then
		root = ReplicatedStorage
		path = string.sub(path, 19)
	end
	
	local result = ResolvePath(root, path)
	
	if result and name then
		return result:FindFirstChild(name)
	end
	return result
end

-- Gradient Definitions (ColorSequences)
local GRADIENT_COLORS = {
	Rare = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 150, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 255))
	}),
	Epic = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 0, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255))
	}),
	Mythic = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 0))
	}),
	Ultra = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255))
	})
}

local function updateBillboard(billboard, item, config)
	if not billboard then return end
	
	-- Robust finding: search recursively anywhere in the billboard
	-- Note: "Rarity" is the new name for the main label (formerly ItemName)
	local rarityLabel = billboard:FindFirstChild("Rarity", true) or billboard:FindFirstChild("ItemName", true)
	local chanceLabel = billboard:FindFirstChild("Chance", true)
	
	if DEBUG then
		if not (rarityLabel and chanceLabel) then
			warn("[SpinService] updateBillboard: Missing rarity/chance labels in billboard hierarchy.")
		end
	end
	
	local color = config.RarityColors[item.rarity] or Color3.new(1,1,1)
	
	if rarityLabel then 
		rarityLabel.Text = string.upper(item.rarity) -- Show RARITY instead of Name
		rarityLabel.TextColor3 = color
		
		-- Handle Gradients (Disable all first, then enable specific)
		local hasGradient = false
		for _, child in ipairs(rarityLabel:GetChildren()) do
			if child:IsA("UIGradient") then
				child.Enabled = false
			end
		end
		
		-- Only apply gradient for Rare+
		if GRADIENT_COLORS[item.rarity] then
			local gradientName = "Gradient_" .. item.rarity
			local gradient = rarityLabel:FindFirstChild(gradientName)
			if gradient then
				gradient.Enabled = true
				gradient.Color = GRADIENT_COLORS[item.rarity]
				gradient.Rotation = 45
				rarityLabel.TextColor3 = Color3.new(1,1,1) -- White text to let gradient show
				hasGradient = true
			end
		end
	end
	if chanceLabel then 
		chanceLabel.Text = string.format("%.2f%% chance", item.chance) 
		chanceLabel.TextColor3 = color
		-- Ensure Chance label is always legible (no gradient, just color)
	end
	-- Value label is hidden/unused
end

-- BUG FIX B: Helper to pick item without consecutive duplicates
local function pickWithoutDuplicate(pickFunction, lastItemId, itemPool)
	local MAX_RETRIES = 6
	local picked = pickFunction()
	
	-- If no lastItemId (first pick), return immediately
	if not lastItemId then
		return picked
	end
	
	-- If picked item is different, return immediately
	if picked.id ~= lastItemId then
		return picked
	end
	
	-- Retry up to MAX_RETRIES times
	for i = 1, MAX_RETRIES do
		picked = pickFunction()
		if picked.id ~= lastItemId then
			return picked
		end
	end
	
	-- If still same after retries (tiny pool), deterministically choose first different item
	if itemPool then
		for _, item in ipairs(itemPool) do
			if item.id ~= lastItemId then
				return item
			end
		end
	end
	
	-- Fallback: return picked even if duplicate (tiny pool, all same ID)
	return picked
end

-- Public API
function SpinService.SpinTable(tableModel, spinConfig, stopFlag, cineToken)
	-- stopFlag: if set to true, spin will stop immediately
	local spinDisplay = tableModel:FindFirstChild("SpinDisplay")
	local itemAnchor = spinDisplay and spinDisplay:FindFirstChild("ItemAnchor")
	local billboardAnchor = spinDisplay and spinDisplay:FindFirstChild("BillboardAnchor")
	
	if not itemAnchor then
		warn("[SpinService] Missing ItemAnchor on table: " .. tableModel.Name)
	end
	
	if not billboardAnchor then
		warn("[SpinService] Missing BillboardAnchor on table: " .. tableModel.Name)
	end
	
	-- Setup Billboard
	local billboardTemplate = ResolvePath(ReplicatedStorage, SPIN_UI_PATH)
	
	-- Pre-setup rig template in ReplicatedStorage for client access
	local RIG_PATH = "Assets/Cinematics/CamRig2"
	local rigTemplate = ResolvePath(ReplicatedStorage, RIG_PATH)
	if not rigTemplate then
		-- Fallback or init logic if needed, but client needs this path
		-- If it's in ServerStorage, we should move it or rely on manual setup
		local serverRig = ResolvePath(ServerStorage, "Assets/Tables/TableTemplate/Cinematics/CamRig2")
		if serverRig then
			-- Ensure it exists in ReplicatedStorage
			local targetFolder = ReplicatedStorage:FindFirstChild("Assets"):FindFirstChild("Cinematics") 
			if not targetFolder then
				-- This part is tricky at runtime; best to ensure it exists via edit.
				-- For now, warn if missing.
			end
		end
	end
	local billboard
	if billboardTemplate then
		billboard = billboardTemplate:Clone()
		billboard.Name = "SpinLabelBillboard_Runtime"
		
		local attachment = billboardAnchor and billboardAnchor:FindFirstChild("BillboardAttachment")
		local adornee = attachment or billboardAnchor
		
		if adornee then
			billboard.Adornee = adornee
			
			-- Guarantee Parent is a workspace part (BillboardAnchor)
			if billboardAnchor then
				billboard.Parent = billboardAnchor
			else
				billboard.Parent = tableModel
				warn(string.format("[SpinService] Billboard runtime not parented to BillboardAnchor (parent=%s)", tostring(billboard.Parent)))
			end
			
			-- Force Visibility properties
			billboard.Enabled = true
			billboard.AlwaysOnTop = true
			if billboard.MaxDistance < 50 then billboard.MaxDistance = 1000 end
			
			-- Safety: Ensure Size isn't 0
			if billboard.Size == UDim2.fromScale(0, 0) and billboard.Size.X.Offset == 0 then
				billboard.Size = UDim2.fromOffset(220, 60)
			end
			
			-- Safety: Ensure Offset isn't 0 if it looks buried
			if billboard.StudsOffset == Vector3.new(0, 0, 0) then
				billboard.StudsOffset = Vector3.new(0, 2.5, 0)
			end
			
			-- Layout Enforcement (Fix for overlapping labels in template)
			local frame = billboard:FindFirstChild("MainFrame") or billboard:FindFirstChild("Frame")
			if frame then
				frame.BackgroundTransparency = 0.1 -- Dark rounded card aesthetic
				frame.ZIndex = 1
			end

			local function enforceLabel(name, pos, size)
				-- Try finding by new name "Rarity" first, then legacy "ItemName"
				local label = billboard:FindFirstChild(name, true)
				if name == "Rarity" and not label then
					label = billboard:FindFirstChild("ItemName", true)
				end
				
				if label then
					label.BackgroundTransparency = 1 -- Transparent background
					label.TextScaled = true
					label.ZIndex = 2 -- On top of background
					label.Position = pos
					label.Size = size
					
					-- Ensure Global Style is Enforced
					label.Font = Enum.Font.Cartoon
					label.TextStrokeTransparency = 0
					label.TextStrokeColor3 = Color3.new(0,0,0)
					
					if name == "Value" then
						label.Visible = false -- Ensure Value is hidden
					end
				end
			end

			-- Rarity (was ItemName): Top ~60%
			enforceLabel("Rarity", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.6, 0))
			-- Chance: Bottom ~40%
			enforceLabel("Chance", UDim2.new(0, 0, 0.6, 0), UDim2.new(1, 0, 0.4, 0))
			-- Value: Hidden
			enforceLabel("Value", UDim2.new(0, 0, 0, 0), UDim2.new(0, 0, 0, 0))
			
		else
			warn("[SpinService] Billboard has nil Adornee; cannot render")
			billboard:Destroy()
			billboard = nil
		end
	else
		warn(string.format("[SpinService] Missing billboard template at: ReplicatedStorage/%s", SPIN_UI_PATH))
	end
	
	-- Spin Logic
	local duration = 3.5
	local startTime = os.clock()
	local spinSpeed = SPIN_TICK -- Fixed tick interval
	
	-- Fire Cinematic IMMEDIATELY (no delays, same tick as spin start)
	local UIService = require(game:GetService("ServerScriptService").Server.Core.UIService)
	
	local seats = {}
	for _, inst in ipairs(tableModel:GetDescendants()) do
		if inst:IsA("Seat") or inst:IsA("VehicleSeat") then
			table.insert(seats, inst)
		end
	end

	local players = {}
	local seenPlayers = {}
	
	for _, seat in ipairs(seats) do
		if seat.Occupant then
			local player = game.Players:GetPlayerFromCharacter(seat.Occupant.Parent)
			if player and not seenPlayers[player.UserId] then
				seenPlayers[player.UserId] = true
				table.insert(players, player)
			end
		end
	end
	
	-- Task: Fire IMMEDIATELY (no task.wait, no delays)
	print(string.format("[SpinService] Firing PlaySpinCinematic at %0.6f", os.clock()))
	for _, p in ipairs(players) do
		UIService.PlayCinematic(p, 91378284817819, duration, tableModel, cineToken)
	end
	
	-- Task: Wait for CinematicStartedAck (Move wait to AFTER firing)
	local RoundService = require(game:GetService("ServerScriptService").Server.Core.RoundService)
	if cineToken then
		RoundService.WaitForCinematicStarted(cineToken, #players)
	end
	
	local lastSpinTime = 0
	
	local currentModel = nil
	local currentItem = nil
	local lastItemId = nil -- BUG FIX B: Track last item ID to prevent consecutive duplicates
	
	local modelsFolder = getAsset(SPIN_MODELS_PATH)
	
	-- BUG FIX B: Get item pool for fallback (deterministic pick)
	local itemPool = nil
	if spinConfig and spinConfig.GetPool then
		itemPool = spinConfig.GetPool()
	end
	
	-- NEAR-MISS: Increment spin count for this table
	tableSpinCount[tableModel] = (tableSpinCount[tableModel] or 0) + 1
	
	-- NEAR-MISS: Decide FINAL reward at spin start (CRITICAL: never changes)
	local finalItem = pickWithoutDuplicate(spinConfig.PickRandom, nil, itemPool)
	if not finalItem then
		-- Fallback: pick first item from pool
		if itemPool and #itemPool > 0 then
			finalItem = itemPool[1]
		else
			warn("[SpinService] Failed to pick finalItem, using fallback")
			finalItem = { id = "RobuxCoin", name = "Robux Coin", rarity = "Common", value = 50, chance = 12.5 }
		end
	end
	
	if DEBUG then
		print(string.format("[SpinService] FinalItem decided: %s (rarity: %s, value: %d)", 
			finalItem.id, finalItem.rarity, finalItem.value))
	end
	
	-- NEAR-MISS: Determine eligibility and cooldown
	local nearMissActive = false
	local baitItem = nil
	
	-- Eligibility: finalItem must NOT be Epic/Mythic/Ultra, and NOT jackpot
	local isEligible = (finalItem.rarity ~= "Epic" and finalItem.rarity ~= "Mythic" and finalItem.rarity ~= "Ultra")
	local isNotJackpot = (finalItem.id ~= "Diamond" and finalItem.rarity ~= "Ultra")
	
	if isEligible and isNotJackpot then
		-- Cooldown check: time-based and spin-count-based
		local timeSinceLast = os.clock() - (lastNearMissAt[tableModel] or 0)
		local spinsSinceLast = tableSpinCount[tableModel] - (lastNearMissSpin[tableModel] or -999)
		local cooldownPassed = (timeSinceLast >= 20) and (spinsSinceLast >= 2)
		
		if cooldownPassed then
			-- Build bait pool (Epic/Mythic/Ultra only, exclude finalItem)
			local baitPool = {}
			if itemPool then
				for _, item in ipairs(itemPool) do
					if (item.rarity == "Epic" or item.rarity == "Mythic" or item.rarity == "Ultra") 
						and item.id ~= finalItem.id and item.name ~= finalItem.name then
						table.insert(baitPool, item)
					end
				end
			end
			
			if #baitPool > 0 then
				-- Tier-weighted selection
				local epicItems = {}
				local mythicItems = {}
				local ultraItems = {}
				
				for _, item in ipairs(baitPool) do
					if item.rarity == "Epic" then
						table.insert(epicItems, item)
					elseif item.rarity == "Mythic" then
						table.insert(mythicItems, item)
					elseif item.rarity == "Ultra" then
						table.insert(ultraItems, item)
					end
				end
				
				-- Use deterministic RNG for near-miss decisions
				local rng = Random.new(math.floor(os.clock() * 1000) + tableSpinCount[tableModel] * 97)
				local nearMissRoll = rng:NextNumber()
				
				-- 42% chance to trigger near-miss
				if nearMissRoll < 0.42 then
					-- Tier selection: 70% Epic, 25% Mythic, 5% Ultra
					local tierRoll = rng:NextNumber()
					local selectedTier = nil
					
					if tierRoll < 0.70 and #epicItems > 0 then
						selectedTier = epicItems
					elseif tierRoll < 0.95 and #mythicItems > 0 then
						selectedTier = mythicItems
					elseif #ultraItems > 0 then
						selectedTier = ultraItems
					else
						-- Fallback: prioritize Epic > Mythic > Ultra
						if #epicItems > 0 then
							selectedTier = epicItems
						elseif #mythicItems > 0 then
							selectedTier = mythicItems
						elseif #ultraItems > 0 then
							selectedTier = ultraItems
						end
					end
					
					if selectedTier and #selectedTier > 0 then
						baitItem = selectedTier[rng:NextInteger(1, #selectedTier)]
						nearMissActive = true
						
						-- Update cooldown state
						lastNearMissAt[tableModel] = os.clock()
						lastNearMissSpin[tableModel] = tableSpinCount[tableModel]
						
						if DEBUG then
							print(string.format("[SpinService] Near-miss ACTIVE: bait=%s (rarity: %s)", 
								baitItem.id, baitItem.rarity))
						end
					end
				else
					if DEBUG then
						print(string.format("[SpinService] Near-miss roll failed: %.3f >= 0.42", nearMissRoll))
					end
				end
			else
				if DEBUG then
					print("[SpinService] Near-miss disabled: no bait items available")
				end
			end
		else
			if DEBUG then
				print(string.format("[SpinService] Near-miss cooldown: time=%.1fs spins=%d", 
					timeSinceLast, spinsSinceLast))
			end
		end
	end
	
	-- Spin Loop with near-miss end sequence
	local lastSpinTime = 0
	local currentModel = nil
	local currentItem = nil
	local lastItemId = nil
	local endPhase = 0 -- 0=normal, 1=pre-final, 2=bait, 3=final locked
	
	while os.clock() - startTime < duration do
		-- Check stop flag (for opponent leave during spin)
		if stopFlag and stopFlag() then
			print("[SpinService] Spin stopped due to abort flag")
			break
		end
		
		local now = os.clock()
		local t = (now - startTime) / duration
		
		-- Update Item visually
		if now - lastSpinTime >= spinSpeed then
			lastSpinTime = now
			
			-- Cleanup old
			if currentModel then currentModel:Destroy() end
			
			-- End phase logic (when t >= 0.90)
			if t >= 0.90 then
				if endPhase == 0 then
					-- Enter pre-final phase
					endPhase = 1
					if DEBUG then
						print("[SpinService] Entering end phase")
					end
				elseif endPhase == 1 then
					-- Show bait (if near-miss active)
					if nearMissActive and baitItem then
						endPhase = 2
						currentItem = baitItem
						if DEBUG then
							print(string.format("[SpinService] Showing BAIT: %s", baitItem.id))
						end
					else
						-- Skip bait, go straight to final
						endPhase = 3
						currentItem = finalItem
						if DEBUG then
							print("[SpinService] Skipping bait, showing final")
						end
					end
				elseif endPhase == 2 then
					-- Final locked: always show finalItem
					endPhase = 3
					currentItem = finalItem
					if DEBUG then
						print("[SpinService] Final locked: showing finalItem")
					end
				else
					-- Phase 3: keep showing finalItem
					currentItem = finalItem
				end
			else
				-- Normal phase: random pick with anti-duplicate
				currentItem = pickWithoutDuplicate(spinConfig.PickRandom, lastItemId, itemPool)
			end
			
			-- Update lastItemId for anti-duplicate (only in normal phase)
			if endPhase == 0 then
				lastItemId = currentItem.id
			end
			
			-- Clone Model
			if modelsFolder and itemAnchor and currentItem then
				local template = modelsFolder:FindFirstChild(currentItem.id) or modelsFolder:FindFirstChild(currentItem.name)
				if template then
					currentModel = template:Clone()
					currentModel:PivotTo(itemAnchor.CFrame)
					currentModel.Parent = tableModel
				end
			end
			
			-- Update UI
			if billboard and currentItem then
				updateBillboard(billboard, currentItem, spinConfig)
			end
		end
		
		task.wait()
	end
	
	-- Ensure finalItem is displayed at the end (if loop ended early)
	if currentItem ~= finalItem then
		if currentModel then currentModel:Destroy() end
		currentItem = finalItem
		
		-- Clone final model
		if modelsFolder and itemAnchor and finalItem then
			local template = modelsFolder:FindFirstChild(finalItem.id) or modelsFolder:FindFirstChild(finalItem.name)
			if template then
				currentModel = template:Clone()
				currentModel:PivotTo(itemAnchor.CFrame)
				currentModel.Parent = tableModel
			end
		end
		
		-- Update UI to final
		if billboard and finalItem then
			updateBillboard(billboard, finalItem, spinConfig)
		end
	end
	
	-- Cleanup UI after short delay? Or keep it for the round?
	-- "DoubleDown plugin should call SpinService first, then proceed... Clean up when round ends."
	
	local cleanup = function()
		if currentModel then currentModel:Destroy() end
		if billboard then billboard:Destroy() end
	end
	
	-- CRITICAL: Always return finalItem (never baitItem or currentItem)
	return finalItem, cleanup
end

return SpinService
