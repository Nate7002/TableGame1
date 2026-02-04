local Players = game:GetService("Players")

local DataService = require(script.Parent:WaitForChild("DataService"))

local StatsService = {}

local DEBUG = true

-- Stats-changed signal: fired when any stat mutates (for leaderboard sync)
local StatsChanged = Instance.new("BindableEvent")
StatsService.StatsChanged = StatsChanged.Event

-- Constants
local DEFAULT_STATS = {
	Cash = 0,
	Wins = 0,
	Streak = 0,
	MaxStreak = 0,
	GamesPlayed = 0,
	TotalDonated = 0,
	WeeklyGamesPlayed = 0,
	WeeklyMaxStreak = 0,
	WeeklyDonations = 0,
	WeeklyStamp = ""
}

-- State (in-memory, per session)
local playerStats = {} -- [UserId] = stats table
local processedRounds = {} -- [roundId] = true (idempotency guard)

local function dprint(...)
	if DEBUG then
		print(...)
	end
end

-- Week key: Monday 00:00 UTC, formatted YYYY_MM_DD
local function getWeekKeyUTC(now)
	now = now or os.time()
	local t = os.date("*t", now)
	-- wday: 1=Sunday, 2=Monday, ..., 7=Saturday
	local daysBack = (t.wday - 2) % 7
	if daysBack == 0 and t.hour == 0 and t.min == 0 and t.sec == 0 then
		-- already Monday 00:00
		t = os.date("*t", now)
	else
		-- snap back to this week's Monday 00:00
		local mondayTime = now - (daysBack * 24 * 3600) - (t.hour * 3600 + t.min * 60 + t.sec)
		t = os.date("*t", mondayTime)
	end
	return string.format("%04d_%02d_%02d", t.year, t.month, t.day)
end

-- Ensure weekly counters are for the current week; reset if stamp differs.
local function ensureWeekly(player, stats)
	if not stats then return false end
	local currentWeekKey = getWeekKeyUTC()
	if stats.WeeklyStamp ~= currentWeekKey then
		stats.WeeklyGamesPlayed = 0
		stats.WeeklyMaxStreak = 0
		stats.WeeklyDonations = 0
		stats.WeeklyStamp = currentWeekKey
		dprint(string.format("[StatsService][WeeklyReset] %s(%d) -> %s", player.Name, player.UserId, currentWeekKey))
		return true
	end
	return false
end

-- Helper: Ensure stats exist for player
local function ensureStats(player)
	local userId = player.UserId
	if not playerStats[userId] then
		playerStats[userId] = {
			Cash = DEFAULT_STATS.Cash,
			Wins = DEFAULT_STATS.Wins,
			Streak = DEFAULT_STATS.Streak,
			MaxStreak = DEFAULT_STATS.MaxStreak,
			GamesPlayed = DEFAULT_STATS.GamesPlayed,
			TotalDonated = DEFAULT_STATS.TotalDonated,
			WeeklyGamesPlayed = DEFAULT_STATS.WeeklyGamesPlayed,
			WeeklyMaxStreak = DEFAULT_STATS.WeeklyMaxStreak,
			WeeklyDonations = DEFAULT_STATS.WeeklyDonations,
			WeeklyStamp = DEFAULT_STATS.WeeklyStamp
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
				MaxStreak = stats.MaxStreak,
				GamesPlayed = stats.GamesPlayed,
				TotalDonated = stats.TotalDonated,
				WeeklyGamesPlayed = stats.WeeklyGamesPlayed,
				WeeklyMaxStreak = stats.WeeklyMaxStreak,
				WeeklyDonations = stats.WeeklyDonations,
				WeeklyStamp = stats.WeeklyStamp
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
				MaxStreak = data.stats.MaxStreak or 0,
				GamesPlayed = data.stats.GamesPlayed or 0,
				TotalDonated = data.stats.TotalDonated or 0,
				WeeklyGamesPlayed = data.stats.WeeklyGamesPlayed or 0,
				WeeklyMaxStreak = data.stats.WeeklyMaxStreak or 0,
				WeeklyDonations = data.stats.WeeklyDonations or 0,
				WeeklyStamp = data.stats.WeeklyStamp or ""
			}
			print(string.format("[StatsService] Hydrated %s from datastore", player.Name))
		else
			-- Use defaults
			ensureStats(player)
		end

		-- Enforce weekly reset on join
		local stats = ensureStats(player)
		if ensureWeekly(player, stats) then
			asyncSavePlayer(player, "WeeklyReset")
			StatsChanged:Fire(player)
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
					MaxStreak = playerStats[userId].MaxStreak,
					GamesPlayed = playerStats[userId].GamesPlayed,
					TotalDonated = playerStats[userId].TotalDonated,
					WeeklyGamesPlayed = playerStats[userId].WeeklyGamesPlayed,
					WeeklyMaxStreak = playerStats[userId].WeeklyMaxStreak,
					WeeklyDonations = playerStats[userId].WeeklyDonations,
					WeeklyStamp = playerStats[userId].WeeklyStamp
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
				MaxStreak = data.stats.MaxStreak or 0,
				GamesPlayed = data.stats.GamesPlayed or 0,
				TotalDonated = data.stats.TotalDonated or 0,
				WeeklyGamesPlayed = data.stats.WeeklyGamesPlayed or 0,
				WeeklyMaxStreak = data.stats.WeeklyMaxStreak or 0,
				WeeklyDonations = data.stats.WeeklyDonations or 0,
				WeeklyStamp = data.stats.WeeklyStamp or ""
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
	if ensureWeekly(player, stats) then
		asyncSavePlayer(player, "WeeklyReset")
		StatsChanged:Fire(player)
	end
	-- Return a copy to prevent external mutation
	return {
		Cash = stats.Cash,
		Wins = stats.Wins,
		Streak = stats.Streak,
		MaxStreak = stats.MaxStreak,
		GamesPlayed = stats.GamesPlayed,
		TotalDonated = stats.TotalDonated,
		WeeklyGamesPlayed = stats.WeeklyGamesPlayed,
		WeeklyMaxStreak = stats.WeeklyMaxStreak,
		WeeklyDonations = stats.WeeklyDonations,
		WeeklyStamp = stats.WeeklyStamp
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
--   rewardCash = number (ALWAYS the TOTAL POT - never per-winner)
--   wasAborted = boolean? (no-contest/abort)
--   isNeutral = boolean? (no-contest; do not change stats)
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
	
	-- Neutral: no rewards, no stat changes (both timeout)
	if resultPayload.isNeutral then
		print("[StatsService] Neutral round - no stats applied")
		return
	end
	
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

	-- Enforce weekly reset before any weekly increments
	local didResetA = ensureWeekly(playerA, statsA)
	local didResetB = ensureWeekly(playerB, statsB)
	if didResetA then
		asyncSavePlayer(playerA, "WeeklyReset")
		StatsChanged:Fire(playerA)
	end
	if didResetB then
		asyncSavePlayer(playerB, "WeeklyReset")
		StatsChanged:Fire(playerB)
	end
	
	-- GamesPlayed: increment for both players when round is not neutral/aborted
	statsA.GamesPlayed = statsA.GamesPlayed + 1
	statsB.GamesPlayed = statsB.GamesPlayed + 1
	statsA.WeeklyGamesPlayed = statsA.WeeklyGamesPlayed + 1
	statsB.WeeklyGamesPlayed = statsB.WeeklyGamesPlayed + 1
	dprint(string.format(
		"[StatsService][Weekly] GamesPlayed++ %s WGP=%d | %s WGP=%d",
		playerA.Name,
		statsA.WeeklyGamesPlayed,
		playerB.Name,
		statsB.WeeklyGamesPlayed
	))
	
	-- Case 1: Both Lose (rare edge case)
	if resultPayload.didBothLose then
		print("[StatsService] Both players lost - resetting streaks")
		statsA.Streak = 0
		statsB.Streak = 0
		
		-- Save both players (non-blocking)
		asyncSavePlayer(playerA, "RoundResult")
		asyncSavePlayer(playerB, "RoundResult")
		dprint(string.format("[StatsService][Weekly] %s WMS=%d | %s WMS=%d", playerA.Name, statsA.WeeklyMaxStreak, playerB.Name, statsB.WeeklyMaxStreak))
		StatsChanged:Fire(playerA)
		StatsChanged:Fire(playerB)
		return
	end
	
	-- Case 2: Draw / Split-Split (both win)
	if resultPayload.didDraw then
		local splitReward = math.floor(rewardCash / 2)
		print(string.format(
			"[StatsService] Draw - splitting pot: $%d/2 = $%d each",
			rewardCash,
			splitReward
		))
		
		-- Player A: cash + wins + streak
		statsA.Cash = statsA.Cash + splitReward
		statsA.Wins = statsA.Wins + 1
		statsA.Streak = statsA.Streak + 1
		statsA.MaxStreak = math.max(statsA.MaxStreak, statsA.Streak)
		statsA.WeeklyMaxStreak = math.max(statsA.WeeklyMaxStreak, statsA.Streak)
		
		-- Player B: cash + wins + streak
		statsB.Cash = statsB.Cash + splitReward
		statsB.Wins = statsB.Wins + 1
		statsB.Streak = statsB.Streak + 1
		statsB.MaxStreak = math.max(statsB.MaxStreak, statsB.Streak)
		statsB.WeeklyMaxStreak = math.max(statsB.WeeklyMaxStreak, statsB.Streak)
		
		print(string.format("[StatsService] Split/Split: %s (+$%d, Wins:%d, Streak:%d, MaxStreak:%d)",
			playerA.Name, splitReward, statsA.Wins, statsA.Streak, statsA.MaxStreak))
		print(string.format("[StatsService] Split/Split: %s (+$%d, Wins:%d, Streak:%d, MaxStreak:%d)",
			playerB.Name, splitReward, statsB.Wins, statsB.Streak, statsB.MaxStreak))
		
		-- Save both players (non-blocking)
		asyncSavePlayer(playerA, "RoundResult")
		asyncSavePlayer(playerB, "RoundResult")
		dprint(string.format("[StatsService][Weekly] %s WMS=%d | %s WMS=%d", playerA.Name, statsA.WeeklyMaxStreak, playerB.Name, statsB.WeeklyMaxStreak))
		StatsChanged:Fire(playerA)
		StatsChanged:Fire(playerB)
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
	winnerStats.WeeklyMaxStreak = math.max(winnerStats.WeeklyMaxStreak, winnerStats.Streak)
	
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
	dprint(string.format("[StatsService][Weekly] %s WMS=%d", winner.Name, winnerStats.WeeklyMaxStreak))
	StatsChanged:Fire(winner)
	if loser then
		StatsChanged:Fire(loser)
	end
end

-- Add donation to player's TotalDonated. Validates amount > 0, saves async, fires StatsChanged.
function StatsService.AddDonation(player, amount)
	if not (player and player.Parent) then return end
	if type(amount) ~= "number" or amount <= 0 then
		warn("[StatsService] AddDonation: amount must be a positive number")
		return
	end
	local stats = ensureStats(player)
	if ensureWeekly(player, stats) then
		asyncSavePlayer(player, "WeeklyReset")
		StatsChanged:Fire(player)
	end
	stats.TotalDonated = stats.TotalDonated + amount
	stats.WeeklyDonations = stats.WeeklyDonations + amount
	dprint(string.format("[StatsService][Weekly] %s WeeklyDonations=%s", player.Name, tostring(stats.WeeklyDonations)))
	asyncSavePlayer(player, "Donation")
	StatsChanged:Fire(player)
end

return StatsService

