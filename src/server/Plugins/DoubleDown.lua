local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local UIService = require(ServerScriptService.Server.Core.UIService)
local SpinService = require(ServerScriptService.Server.Core.SpinService)

-- Load config from ServerScriptService (Repo Config)
local SpinConfig = require(ServerScriptService.Server.Config.SpinTable)

local DoubleDown = {}

local STAGE1_TIME = 15
local STAGE2_TIME = 10

-- Stage options (for random selection)
local STAGE1_OPTIONS = {"SPLIT", "STEAL", "DOUBLEDOWN"}
local STAGE2_OPTIONS = {"SPLIT", "STEAL"}

-- Helper: Normalize choices and handle timeouts (Bulletproof Hardening)
local function normalizeStageChoices(playerA, choiceA, didPickA, playerB, choiceB, didPickB, stage)
	local validOptions = (stage == 1) and STAGE1_OPTIONS or STAGE2_OPTIONS
	
	print(string.format("[DoubleDown] Stage%d choices (raw): %s=%s (picked=%s) %s=%s (picked=%s)", 
		stage, playerA.Name, tostring(choiceA), tostring(didPickA), playerB.Name, tostring(choiceB), tostring(didPickB)))
	
	-- Problem 1: Neutral ONLY when BOTH are raw TIMEOUT and NEITHER picked
	if not didPickA and not didPickB and choiceA == "TIMEOUT" and choiceB == "TIMEOUT" then
		print(string.format("[DoubleDown] Stage%d normalization: neutral=true (both timed out)", stage))
		return {
			isNeutral = true,
			finalA = "TIMEOUT",
			finalB = "TIMEOUT"
		}
	end
	
	-- Rule: If ONE is TIMEOUT (or didn't pick), randomize only that one
	local finalA = choiceA
	local finalB = choiceB
	
	if not didPickA then
		finalA = validOptions[math.random(1, #validOptions)]
		print(string.format("[DoubleDown] %s timed out -> random choice: %s (stage %d)", playerA.Name, finalA, stage))
	elseif not didPickB then
		finalB = validOptions[math.random(1, #validOptions)]
		print(string.format("[DoubleDown] %s timed out -> random choice: %s (stage %d)", playerB.Name, finalB, stage))
	end
	
	print(string.format("[DoubleDown] Stage%d normalization: neutral=false finalA=%s finalB=%s", stage, finalA, finalB))
	return {
		isNeutral = false,
		finalA = finalA,
		finalB = finalB
	}
end

-- Helper: Get choices from both players in parallel
local function getChoices(players, stage, currentReward, rarity, sfxOverride, tableModel)
	local choices = {}
	local didPick = {} -- [player] = boolean
	local threads = 0
	local thread = coroutine.running()
	local firstPicker = nil -- UX FIX C: Track who picked first
	
	local duration = (stage == 1) and STAGE1_TIME or STAGE2_TIME
	local endTime = workspace:GetServerTimeNow() + duration
	
	local options
	local validOptionIds = {}
	if stage == 1 then
		options = {
			{ id = "SPLIT", label = "Split" },
			{ id = "STEAL", label = "Steal" },
			{ id = "DOUBLEDOWN", label = "Double Down" }
		}
	else
		options = {
			{ id = "SPLIT", label = "Split" },
			{ id = "STEAL", label = "Steal" }
		}
	end
	for _, opt in ipairs(options) do validOptionIds[opt.id] = true end
	
	-- UX FIX C: Setup remote for OpponentPicked
	local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	local OpponentPicked = Remotes:FindFirstChild("OpponentPicked")
	
	for _, player in ipairs(players) do
		threads += 1
		task.spawn(function()
			-- Problem 1: Generate unique promptId per player per stage
			local promptId = string.format("%s_S%d_%d_%0.6f", 
				tableModel and tableModel.Name or "Table", 
				stage, 
				player.UserId, 
				os.clock())
			
			local choice = UIService.PromptChoice(player, {
				promptId = promptId, -- Problem 1: Pass promptId
				title = stage == 1 and "Double Down" or "SUDDEN DEATH",
				description = string.format("<font color=\"rgb(85, 255, 127)\">Reward: $%d</font>\nChoose your move!", currentReward),
				options = options,
				timeout = duration,
				endTime = endTime,
				rarity = rarity,
				sfx = sfxOverride
			})
			
			choices[player] = choice or "TIMEOUT"
			didPick[player] = (choice ~= nil and validOptionIds[choice] == true)
			
			-- UX FIX C: If this is the first picker, notify the opponent
			if not firstPicker and didPick[player] then
				firstPicker = player
				-- Find opponent
				local opponent = (player == players[1]) and players[2] or players[1]
				if opponent and opponent.Parent and OpponentPicked then
					OpponentPicked:FireClient(opponent, player.Name)
					print(string.format("[DoubleDown] %s picked first, notified %s", player.Name, opponent.Name))
				end
			end
			
			threads -= 1
			if threads == 0 then
				task.spawn(thread)
			end
		end)
	end
	
	if threads > 0 then
		coroutine.yield()
	end
	
	return choices, didPick
end

function DoubleDown.Run(context)
	local players = context.players
	local tableModel = context.tableModel
	local session = context.session -- RoundService session for abort checking
	if not players or #players < 2 then
		return { ok = false, meta = { error = "Not enough players" } }
	end
	
	local p1, p2 = players[1], players[2]
	
	-- SPIN PHASE
	print("[DoubleDown] Spinning for reward...")
	-- Update state
	local spinItem, spinCleanup
	if session then
		session.state = "SPINNING"
		-- Create stop flag function
		session.spinStopFlag = false
		local stopFlag = function()
			return session and (session.spinStopFlag or session.abortFlag)
		end
		-- Cinematic fired inside SpinTable now
		spinItem, spinCleanup = SpinService.SpinTable(tableModel, SpinConfig, stopFlag, session.cineToken)
		-- Store cleanup function in session for abort path
		if session then
			session.spinCleanup = spinCleanup
		end
	else
		spinItem, spinCleanup = SpinService.SpinTable(tableModel, SpinConfig)
	end
	
	-- Check abort flag after spin
	if session and session.abortFlag then
		print("[DoubleDown] Abort flag set after spin")
		-- Cleanup spin visuals immediately on abort
		if spinCleanup then
			pcall(spinCleanup)
			print("[DoubleDown] Spin cleanup called on abort")
		end
		return { ok = false, meta = { error = "Match aborted" } }
	end
	
	if not spinItem then
		return { ok = false, meta = { error = "Spin failed" } }
	end
	
	local reward = spinItem.value
	local rarity = spinItem.rarity -- Capture rarity
	
	-- SFX: Check for Rare Drop or Jackpot
	local isJackpot = (spinItem.id == "Diamond") -- Assuming Diamond is jackpot
	local isRarePlus = (rarity == "Rare" or rarity == "Epic" or rarity == "Mythic" or rarity == "Ultra")
	local isEpicPlus = (rarity == "Epic" or rarity == "Mythic" or rarity == "Ultra")
	
	-- Determine Phase 1 SFX
	local phase1Sfx = "NotificationSound"
	if isJackpot or isEpicPlus then
		phase1Sfx = "JackpotSound"
		
		-- GLOBAL JACKPOT AUDIO
		if isJackpot then
			task.spawn(function()
				local Debris = game:GetService("Debris")
				local SoundService = game:GetService("SoundService")
				local ReplicatedStorage = game:GetService("ReplicatedStorage")
				local fx = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FX") and ReplicatedStorage.Assets.FX:FindFirstChild("JackpotSound")
				
				if fx and fx:IsA("Sound") then
					local clone = fx:Clone()
					clone.Parent = SoundService
					clone:Play()
					Debris:AddItem(clone, (clone.TimeLength > 0 and clone.TimeLength or 3) + 0.5)
					print("[DoubleDown] GLOBAL JACKPOT SOUND FIRED")
				end
			end)
		end
	end
	
	print("[DoubleDown] Starting Stage 1... at", os.clock())
	print("[DoubleDown] Showing Stage1 UI to players")
	
	-- Stage 1
	local rawChoices1, didPick1 = getChoices(players, 1, reward, rarity, phase1Sfx, tableModel)
	print("[DoubleDown] Both choices received at", os.clock())
	
	-- Normalize Stage 1
	local norm1 = normalizeStageChoices(p1, rawChoices1[p1], didPick1[p1], p2, rawChoices1[p2], didPick1[p2], 1)
	local c1, c2 = norm1.finalA, norm1.finalB
	
	local finalChoices = {[p1.UserId] = c1, [p2.UserId] = c2}
	local winners = {}
	local outcome = "None"
	local finalReward = reward
	
	-- Handle Neutral Stage 1 (Both Timeout)
	if norm1.isNeutral then
		spinCleanup()
		return {
			ok = true,
			data = {
				outcome = "NEUTRAL_TIMEOUT",
				neutral = true,
				reward = 0,
				winners = {},
				choices = finalChoices
			}
		}
	end

	-- Check for Double Down Standoff
	if c1 == "DOUBLEDOWN" and c2 == "DOUBLEDOWN" then
		-- Check abort flag
		if session and session.abortFlag then
			print("[DoubleDown] Abort flag set before Stage 2")
			return { ok = false, meta = { error = "Match aborted" } }
		end
		
		print("[DoubleDown] Both Doubled Down! Entering Stage 2...")
		
		-- Update state
		if session then
			session.state = "STAGE2"
		end
		
		-- Stage 2: Sudden Death (Split/Steal only)
		local rawChoices2, didPick2 = getChoices(players, 2, reward * 2, rarity, "DoubleDownSound", tableModel)
		
		-- Check abort flag after Stage 2 choices
		if session and session.abortFlag then
			print("[DoubleDown] Abort flag set after Stage 2 choices")
			return { ok = false, meta = { error = "Match aborted" } }
		end 
		finalReward = reward * 2
		
		-- Normalize Stage 2
		local norm2 = normalizeStageChoices(p1, rawChoices2[p1], didPick2[p1], p2, rawChoices2[p2], didPick2[p2], 2)
		local sc1, sc2 = norm2.finalA, norm2.finalB
		
		finalChoices[p1.UserId] = sc1 .. "_S2"
		finalChoices[p2.UserId] = sc2 .. "_S2"
		
		-- Handle Neutral Stage 2 (Both Timeout)
		if norm2.isNeutral then
			spinCleanup()
			return {
				ok = true,
				data = {
					outcome = "NEUTRAL_TIMEOUT",
					neutral = true,
					reward = 0,
					winners = {},
					choices = finalChoices
				}
			}
		end

		-- Resolve Stage 2 (Standard Split/Steal)
		if sc1 == "SPLIT" and sc2 == "SPLIT" then
			outcome = "SPLIT_S2"
			winners = {p1, p2}
			finalReward = finalReward / 2
		elseif sc1 == "STEAL" and sc2 == "SPLIT" then
			outcome = "STEAL_P1_S2"
			winners = {p1}
		elseif sc1 == "SPLIT" and sc2 == "STEAL" then
			outcome = "STEAL_P2_S2"
			winners = {p2}
		else -- Steal/Steal
			outcome = "CRASH_S2"
			winners = {}
			finalReward = 0
		end
		
	else
		-- Resolve Stage 1
		if c1 == "SPLIT" and c2 == "SPLIT" then
			outcome = "SPLIT"
			winners = {p1, p2}
			finalReward = reward / 2
			
		elseif c1 == "STEAL" and c2 == "SPLIT" then
			outcome = "STEAL_P1"
			winners = {p1}
			
		elseif c1 == "SPLIT" and c2 == "STEAL" then
			outcome = "STEAL_P2"
			winners = {p2}
			
		elseif c1 == "STEAL" and c2 == "STEAL" then
			outcome = "CRASH"
			winners = {}
			finalReward = 0
			
		-- Double Down Interactions
		elseif c1 == "DOUBLEDOWN" and c2 == "SPLIT" then
			outcome = "SPLIT_P2"
			winners = {p2}
			finalReward = reward
			
		elseif c1 == "SPLIT" and c2 == "DOUBLEDOWN" then
			outcome = "SPLIT_P1"
			winners = {p1}
			finalReward = reward
			
		elseif c1 == "DOUBLEDOWN" and c2 == "STEAL" then
			outcome = "CRASH_DD"
			winners = {}
			finalReward = 0
			
		elseif c1 == "STEAL" and c2 == "DOUBLEDOWN" then
			outcome = "CRASH_DD"
			winners = {}
			finalReward = 0
		end
	end
	
	spinCleanup() -- Clean up at end of logic
	
	print(string.format("[DoubleDown] Outcome decided: %s", outcome))
	return {
		ok = true,
		data = {
			outcome = outcome,
			reward = finalReward,
			winners = winners,
			choices = finalChoices,
			neutral = (outcome == "NEUTRAL_TIMEOUT")
		}
	}
end

return DoubleDown
