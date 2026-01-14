local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local UIService = require(ServerScriptService.Server.Core.UIService)
local SpinService = require(ServerScriptService.Server.Core.SpinService)

-- Load config from ServerScriptService (Repo Config)
local SpinConfig = require(ServerScriptService.Server.Config.SpinTable)

local DoubleDown = {}

local STAGE1_TIME = 10
local STAGE2_TIME = 10

-- Helper: Get choices from both players in parallel
local function getChoices(players, stage, currentReward)
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
				description = string.format("Reward: $%d\nChoose your move!", currentReward),
				options = options,
				timeout = duration,
				endTime = endTime
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
	if not players or #players < 2 then
		return { ok = false, meta = { error = "Not enough players" } }
	end
	
	local p1, p2 = players[1], players[2]
	
	-- SPIN PHASE
	print("[DoubleDown] Spinning for reward...")
	local spinItem, spinCleanup = SpinService.SpinTable(tableModel, SpinConfig)
	local reward = spinItem.value
	
	print("[DoubleDown] Starting Stage 1...")
	
	-- Stage 1
	local choices1 = getChoices(players, 1, reward)
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
		print("[DoubleDown] Both Doubled Down! Entering Stage 2...")
		
		spinCleanup() -- Clean up visuals before Stage 2
		
		-- Stage 2: Sudden Death (Split/Steal only)
		local choices2 = getChoices(players, 2, reward * 2) 
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
