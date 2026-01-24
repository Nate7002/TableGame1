local Players = game:GetService("Players")

local DataService = require(script.Parent:WaitForChild("DataService"))

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

-- Helper: Non-blocking save after stats mutation
local function asyncSavePlayer(player, reason)
	if not (player and player.Parent) then return end
	
	local userId = player.UserId
	local stats = playerStats[userId]
	if not stats then return end
	
	-- Spawn non-blocking save
	task.spawn(function()
		local payload = {
			v = 1,
			stats = {
				Cash = stats.Cash,
				Wins = stats.Wins,
				Streak = stats.Streak,
				MaxStreak = stats.MaxStreak
			},
			updatedAt = os.time()
		}
		DataService.SavePlayer(player, payload, reason)
	end)
end

-- Public API

function StatsService.Init()
	print("[StatsService] Initializing...")
	
	-- Load data on player join
	Players.PlayerAdded:Connect(function(player)
		local data = DataService.LoadPlayer(player)
		if data and data.stats then
			-- Hydrate from loaded data
			playerStats[player.UserId] = {
				Cash = data.stats.Cash or 0,
				Wins = data.stats.Wins or 0,
				Streak = data.stats.Streak or 0,
				MaxStreak = data.stats.MaxStreak or 0
			}
			print(string.format("[StatsService] Hydrated %s from datastore", player.Name))
		else
			-- Use defaults
			ensureStats(player)
		end
	end)
	
	-- Save and cleanup on player leave
	Players.PlayerRemoving:Connect(function(player)
		-- Capture reliable identifiers immediately while player reference is valid
		local userId = player and player.UserId
		local playerName = player and player.Name or "Unknown"
		
		-- Validate userId (Roblox UserIds are always positive integers)
		if not userId or userId <= 0 then
			warn(string.format("[StatsService] Invalid or missing UserId for %s - skipping save", playerName))
			return
		end
		
		if playerStats[userId] then
			-- Save before clearing
			local payload = {
				v = 1,
				stats = {
					Cash = playerStats[userId].Cash,
					Wins = playerStats[userId].Wins,
					Streak = playerStats[userId].Streak,
					MaxStreak = playerStats[userId].MaxStreak
				},
				updatedAt = os.time()
			}
			DataService.SavePlayer(player, payload, "PlayerRemoving")
			
			print(string.format("[StatsService] Saved and cleared stats for %s (UserId: %d)", playerName, userId))
			playerStats[userId] = nil
			DataService.ClearCache(userId)
		end
	end)
	
	-- Load stats for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService.LoadPlayer(player)
		if data and data.stats then
			playerStats[player.UserId] = {
				Cash = data.stats.Cash or 0,
				Wins = data.stats.Wins or 0,
				Streak = data.stats.Streak or 0,
				MaxStreak = data.stats.MaxStreak or 0
			}
			print(string.format("[StatsService] Hydrated %s (existing player)", player.Name))
		else
			ensureStats(player)
		end
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
		
		-- Save both players (non-blocking)
		asyncSavePlayer(playerA, "RoundResult")
		asyncSavePlayer(playerB, "RoundResult")
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
		
		-- Save both players (non-blocking)
		asyncSavePlayer(playerA, "RoundResult")
		asyncSavePlayer(playerB, "RoundResult")
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
	
	-- Save both players (non-blocking)
	asyncSavePlayer(winner, "RoundResult")
	if loser then
		asyncSavePlayer(loser, "RoundResult")
	end
end

return StatsService

