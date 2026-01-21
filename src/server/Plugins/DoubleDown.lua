local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local UIService = require(ServerScriptService.Server.Core.UIService)
local SpinService = require(ServerScriptService.Server.Core.SpinService)

-- Load config from ServerScriptService (Repo Config)
local SpinConfig = require(ServerScriptService.Server.Config.SpinTable)

local DoubleDown = {}

local STAGE1_TIME = 15
local STAGE2_TIME = 10

-- Helper: Get choices from both players in parallel
local function getChoices(players, stage, currentReward, rarity, sfxOverride)
	local choices = {}
	local threads = 0
	local thread = coroutine.running()
	
	local duration = (stage == 1) and STAGE1_TIME or STAGE2_TIME
	local endTime = workspace:GetServerTimeNow() + duration
	
	local options
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
	
	for _, player in ipairs(players) do
		threads += 1
		task.spawn(function()
			local choice = UIService.PromptChoice(player, {
				title = stage == 1 and "Double Down" or "SUDDEN DEATH",
				description = string.format("<font color=\"rgb(85, 255, 127)\">Reward: $%d</font>\nChoose your move!", currentReward),
				options = options,
				timeout = duration,
				endTime = endTime,
				rarity = rarity, -- Pass rarity for UI tint
				sfx = sfxOverride -- Pass Phase SFX
			})
			
			choices[player] = choice or "TIMEOUT" -- Mark as TIMEOUT if nil
			
			threads -= 1
			if threads == 0 then
				task.spawn(thread)
			end
		end)
	end
	
	if threads > 0 then
		coroutine.yield()
	end
	
	-- Log choices
	local logParts = {}
	for _, p in ipairs(players) do
		table.insert(logParts, string.format("%s=%s", p.Name, choices[p]))
	end
	print(string.format("[RoundService] Stage%d choices: %s", stage, table.concat(logParts, " ")))
	
	return choices
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
		spinItem, spinCleanup = SpinService.SpinTable(tableModel, SpinConfig, stopFlag)
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
	local choices1 = getChoices(players, 1, reward, rarity, phase1Sfx)
	print("[DoubleDown] Both choices received at", os.clock())
	local c1, c2 = choices1[p1], choices1[p2]
	
	local finalChoices = {[p1.UserId] = c1, [p2.UserId] = c2}
	local winners = {}
	local outcome = "None"
	local finalReward = reward
	
	-- Check Timeouts First
	if c1 == "TIMEOUT" or c2 == "TIMEOUT" then
		spinCleanup() -- Clean up visuals
		if c1 == "TIMEOUT" and c2 == "TIMEOUT" then
			outcome = "BOTH_TIMEOUT"
			winners = {}
			finalReward = 0
		elseif c1 == "TIMEOUT" then
			outcome = "P1_TIMEOUT"
			winners = {p2} -- P2 wins by default
		else -- c2 == TIMEOUT
			outcome = "P2_TIMEOUT"
			winners = {p1} -- P1 wins by default
		end
		
		return {
			ok = true,
			data = {
				outcome = outcome,
				reward = finalReward,
				winners = winners,
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
		
		-- DO NOT call spinCleanup() here - keep reward item alive through Stage 2
		-- spinCleanup() will be called at the end of the round
		
		-- Stage 2: Sudden Death (Split/Steal only)
		-- Play DoubleDownSound ONLY here (Phase 2 start)
		local choices2 = getChoices(players, 2, reward * 2, rarity, "DoubleDownSound")
		
		-- Check abort flag after Stage 2 choices
		if session and session.abortFlag then
			print("[DoubleDown] Abort flag set after Stage 2 choices")
			return { ok = false, meta = { error = "Match aborted" } }
		end 
		finalReward = reward * 2
		
		local sc1, sc2 = choices2[p1], choices2[p2]
		finalChoices[p1.UserId] = sc1 .. "_S2"
		finalChoices[p2.UserId] = sc2 .. "_S2"
		
		-- Check Timeouts Stage 2
		if sc1 == "TIMEOUT" or sc2 == "TIMEOUT" then
			spinCleanup()
			if sc1 == "TIMEOUT" and sc2 == "TIMEOUT" then
				outcome = "BOTH_TIMEOUT_S2"
				winners = {}
				finalReward = 0
			elseif sc1 == "TIMEOUT" then
				outcome = "P1_TIMEOUT_S2"
				winners = {p2}
			else
				outcome = "P2_TIMEOUT_S2"
				winners = {p1}
			end
		-- Resolve Stage 2 (Standard Split/Steal)
		elseif sc1 == "SPLIT" and sc2 == "SPLIT" then
			outcome = "SPLIT_S2"
			winners = {p1, p2} -- Share 50% of 2x (so original reward each)
			finalReward = finalReward / 2 -- Each gets half
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
		-- Outcome Mapping:
		-- SPLIT vs SPLIT     -> SPLIT (Both Win 50%)
		-- SPLIT vs STEAL     -> STEAL_P2 (Steal Wins 100%)
		-- STEAL vs SPLIT     -> STEAL_P1 (Steal Wins 100%)
		-- STEAL vs STEAL     -> CRASH (Both Lose 0%)
		-- DD    vs SPLIT     -> SPLIT_P2 (Split Beats DD) <-- FIXED: Split wins vs DD
		-- SPLIT vs DD        -> SPLIT_P1 (Split Beats DD) <-- FIXED: Split wins vs DD
		-- DD    vs STEAL     -> CRASH_DD (Both Lose)      <-- FIXED: DD vs Steal = Crash
		-- STEAL vs DD        -> CRASH_DD (Both Lose)      <-- FIXED: DD vs Steal = Crash
		
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
			
		-- Double Down Interactions (Updated)
		elseif c1 == "DOUBLEDOWN" and c2 == "SPLIT" then
			outcome = "SPLIT_P2"
			winners = {p2}
			finalReward = reward -- Winner takes regular pot, DD loses
			
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
	
	return {
		ok = true,
		data = {
			outcome = outcome,
			reward = finalReward,
			winners = winners,
			choices = finalChoices
		}
	}
end

return DoubleDown
