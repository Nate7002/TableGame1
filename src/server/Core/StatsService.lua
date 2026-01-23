local Players = game:GetService("Players")

local StatsService = {}

-- Constants
local DEFAULT_STATS = {
	Cash = 0,
	Wins = 0,
	Streak = 0,
	MaxStreak = 0
}

-- State (in-memory, per session)
local playerStats = {} -- [UserId] = {Cash, Wins, Streak, MaxStreak}
local processedRounds = {} -- [roundId] = true (idempotency guard)

-- Helper: Ensure stats exist for player
local function ensureStats(player)
	local userId = player.UserId
	if not playerStats[userId] then
		playerStats[userId] = {
			Cash = DEFAULT_STATS.Cash,
			Wins = DEFAULT_STATS.Wins,
			Streak = DEFAULT_STATS.Streak,
			MaxStreak = DEFAULT_STATS.MaxStreak
		}
	end
	return playerStats[userId]
end

-- Public API

function StatsService.Init()
	print("[StatsService] Initializing...")
	
	-- Cleanup on player leave
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		if playerStats[userId] then
			print(string.format("[StatsService] Clearing stats for %s (UserId: %d)", player.Name, userId))
			playerStats[userId] = nil
		end
	end)
	
	-- Initialize stats for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		ensureStats(player)
	end
	
	print("[StatsService] Ready.")
end

function StatsService.GetStats(player)
	if not player or not player.Parent then return nil end
	local stats = ensureStats(player)
	-- Return a copy to prevent external mutation
	return {
		Cash = stats.Cash,
		Wins = stats.Wins,
		Streak = stats.Streak,
		MaxStreak = stats.MaxStreak
	}
end

-- Apply round result and update stats
-- resultPayload contract:
-- {
--   roundId = string (required for idempotency)
--   winnerUserId = number? (single winner)
--   loserUserId = number? (single loser)
--   didDraw = boolean? (both win/tie)
--   didBothLose = boolean? (both lose)
--   rewardCash = number (total cash reward)
--   wasAborted = boolean? (no-contest/abort)
--   reason = string? (optional debug)
-- }
function StatsService.ApplyRoundResult(playerA, playerB, resultPayload)
	-- Idempotency guard
	local roundId = resultPayload.roundId
	if not roundId then
		warn("[StatsService] ApplyRoundResult called without roundId - skipping")
		return
	end
	
	if processedRounds[roundId] then
		print("[StatsService] Round already processed:", roundId, "- skipping duplicate")
		return
	end
	processedRounds[roundId] = true
	
	-- Abort: no rewards, no stat changes
	if resultPayload.wasAborted then
		print("[StatsService] Round aborted - no stats applied")
		return
	end
	
	local rewardCash = resultPayload.rewardCash or 0
	
	-- Validate players
	if not (playerA and playerA.Parent) then
		warn("[StatsService] PlayerA invalid")
		return
	end
	if not (playerB and playerB.Parent) then
		warn("[StatsService] PlayerB invalid")
		return
	end
	
	local statsA = ensureStats(playerA)
	local statsB = ensureStats(playerB)
	
	-- Case 1: Both Lose (rare edge case)
	if resultPayload.didBothLose then
		print("[StatsService] Both players lost - resetting streaks")
		statsA.Streak = 0
		statsB.Streak = 0
		return
	end
	
	-- Case 2: Draw / Split-Split (both win)
	if resultPayload.didDraw then
		print("[StatsService] Draw - both players win, splitting reward")
		local splitReward = math.floor(rewardCash / 2)
		
		-- Player A: cash + wins + streak
		statsA.Cash = statsA.Cash + splitReward
		statsA.Wins = statsA.Wins + 1
		statsA.Streak = statsA.Streak + 1
		statsA.MaxStreak = math.max(statsA.MaxStreak, statsA.Streak)
		
		-- Player B: cash + wins + streak
		statsB.Cash = statsB.Cash + splitReward
		statsB.Wins = statsB.Wins + 1
		statsB.Streak = statsB.Streak + 1
		statsB.MaxStreak = math.max(statsB.MaxStreak, statsB.Streak)
		
		print(string.format("[StatsService] Split/Split: %s (+$%d, Wins:%d, Streak:%d, MaxStreak:%d)",
			playerA.Name, splitReward, statsA.Wins, statsA.Streak, statsA.MaxStreak))
		print(string.format("[StatsService] Split/Split: %s (+$%d, Wins:%d, Streak:%d, MaxStreak:%d)",
			playerB.Name, splitReward, statsB.Wins, statsB.Streak, statsB.MaxStreak))
		
		return
	end
	
	-- Case 3: Single Winner
	local winnerId = resultPayload.winnerUserId
	local loserId = resultPayload.loserUserId
	
	if not winnerId then
		warn("[StatsService] No winner specified and not draw/abort - unexpected")
		return
	end
	
	local winner = playerA.UserId == winnerId and playerA or (playerB.UserId == winnerId and playerB or nil)
	local loser = playerA.UserId == loserId and playerA or (playerB.UserId == loserId and playerB or nil)
	
	if not winner then
		warn("[StatsService] Winner UserId does not match either player")
		return
	end
	
	local winnerStats = ensureStats(winner)
	
	-- Apply winner rewards
	winnerStats.Cash = winnerStats.Cash + rewardCash
	winnerStats.Wins = winnerStats.Wins + 1
	winnerStats.Streak = winnerStats.Streak + 1
	winnerStats.MaxStreak = math.max(winnerStats.MaxStreak, winnerStats.Streak)
	
	print(string.format("[StatsService] Winner: %s (+$%d, Wins:%d, Streak:%d, MaxStreak:%d)",
		winner.Name, rewardCash, winnerStats.Wins, winnerStats.Streak, winnerStats.MaxStreak))
	
	-- Apply loser penalty (reset streak)
	if loser then
		local loserStats = ensureStats(loser)
		loserStats.Streak = 0
		print(string.format("[StatsService] Loser: %s (Streak reset to 0)", loser.Name))
	end
end

return StatsService

