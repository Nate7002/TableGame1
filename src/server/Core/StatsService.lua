local Players = game:GetService("Players")

local DataService = require(script.Parent:WaitForChild("DataService"))
local DebugService = require(script.Parent:WaitForChild("DebugService"))
local UIService = require(script.Parent:WaitForChild("UIService"))

local StatsService = {}

local function snapshotStats(stats)
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
		WeeklyStamp = stats.WeeklyStamp,
		Gems = stats.Gems,
		Shields = stats.Shields,
		FreeShieldGranted = stats.FreeShieldGranted
	}
end

local function formatRoundDebugStats(stats)
	if not stats then
		return "nil"
	end

	return string.format(
		"cash=%d,wins=%d,streak=%d,games=%d",
		tonumber(stats.Cash) or 0,
		tonumber(stats.Wins) or 0,
		tonumber(stats.Streak) or 0,
		tonumber(stats.GamesPlayed) or 0
	)
end

local function getRoundBranchLabel(resultPayload)
	if resultPayload.isNeutral then
		return "neutral"
	elseif resultPayload.wasAborted then
		return "aborted"
	elseif resultPayload.didBothLose then
		return "both_lose"
	elseif resultPayload.didDraw then
		return "draw"
	end

	return "single_winner"
end

local function PushStatsUpdate(player, statsOverride)
	if not player then return end
	local stats = statsOverride and snapshotStats(statsOverride) or StatsService.GetStats(player)
	if stats then
		UIService.FireStatsUpdate(player, stats)
	end
end

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
	WeeklyStamp = "",
	Gems = 0,
	Shields = 0,
	FreeShieldGranted = false,
}

local MAX_SHIELDS = 3

-- State (in-memory, per session)
local playerStats = {} -- [UserId] = stats table
local processedRounds = {} -- [roundId] = true (idempotency guard)
local activeShieldArms = {} -- [UserId] = true (armed for current round only)
local hydratingPlayers = {} -- [UserId] = true while hydrate is running
local hydratedPlayers = {} -- [UserId] = true after authoritative hydrate completes
local nextStatsSlotId = 0
local lastGetStatsLogAt = {}

local function getStatsSlotId(stats)
	if not stats then
		return "nil"
	end

	return tostring(stats.__debugSlotId or "nil")
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
		DebugService.Info("STATS", "WEEKLY_RESET", {
			userId = player.UserId,
			newStamp = currentWeekKey
		})
		return true
	end
	return false
end

-- Helper: Ensure stats exist for player
local function ensureStats(player)
	local userId = player.UserId
	if not playerStats[userId] then
		nextStatsSlotId = nextStatsSlotId + 1
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
			WeeklyStamp = DEFAULT_STATS.WeeklyStamp,
			Gems = DEFAULT_STATS.Gems,
			Shields = DEFAULT_STATS.Shields,
			FreeShieldGranted = DEFAULT_STATS.FreeShieldGranted,
			__debugSlotId = nextStatsSlotId,
		}
	end
	return playerStats[userId]
end

local function toUserIdSet(userIds)
	local set = {}

	for _, userId in ipairs(userIds or {}) do
		if type(userId) == "number" then
			set[userId] = true
		end
	end

	return set
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
				WeeklyStamp = stats.WeeklyStamp,
				Gems = stats.Gems,
				Shields = stats.Shields,
				FreeShieldGranted = stats.FreeShieldGranted
			},
			updatedAt = os.time()
		}
		DataService.SavePlayer(player, payload, reason)
	end)
end

local function hydratePlayer(player, source)
	if not (player and player.Parent) then return end

	local userId = player.UserId
	if hydratedPlayers[userId] then
		return
	end

	if hydratingPlayers[userId] then
		return
	end

	hydratingPlayers[userId] = true
	local stats = ensureStats(player)

	local data = DataService.LoadPlayer(player)

	if data and data.stats then
		stats.Cash = data.stats.Cash or 0
		stats.Wins = data.stats.Wins or 0
		stats.Streak = data.stats.Streak or 0
		stats.MaxStreak = data.stats.MaxStreak or 0
		stats.GamesPlayed = data.stats.GamesPlayed or 0
		stats.TotalDonated = data.stats.TotalDonated or 0
		stats.WeeklyGamesPlayed = data.stats.WeeklyGamesPlayed or 0
		stats.WeeklyMaxStreak = data.stats.WeeklyMaxStreak or 0
		stats.WeeklyDonations = data.stats.WeeklyDonations or 0
		stats.WeeklyStamp = data.stats.WeeklyStamp or ""
		stats.Gems = data.stats.Gems or 0
		stats.Shields = math.max(stats.Shields or 0, data.stats.Shields or 0)
		stats.FreeShieldGranted = data.stats.FreeShieldGranted or false

		DebugService.Info("STATS", "PLAYER_HYDRATED", {
			userId = userId,
			source = source or "hydrate"
		})
	end

	if ensureWeekly(player, stats) then
		asyncSavePlayer(player, "WeeklyReset")
		StatsChanged:Fire(player)
	end

	PushStatsUpdate(player, stats)
	if UIService.FireShieldChanged then
		UIService.FireShieldChanged(player, stats.Shields or 0)
	end

	hydratingPlayers[userId] = nil
	hydratedPlayers[userId] = true
end

-- Public API

function StatsService.Init()
	DebugService.Info("STATS", "INIT_START")
	
	-- Load data on player join
	Players.PlayerAdded:Connect(function(player)
		hydratePlayer(player, "player_added")
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
					WeeklyStamp = playerStats[userId].WeeklyStamp,
					Gems = playerStats[userId].Gems,
					Shields = playerStats[userId].Shields,
					FreeShieldGranted = playerStats[userId].FreeShieldGranted
				},
				updatedAt = os.time()
			}
			local saveSucceeded = DataService.SavePlayer(player, payload, "PlayerRemoving")
			if saveSucceeded then
				DataService.ClearCache(userId)
			else
				DebugService.Warn("STATS", "PLAYER_REMOVE_SAVE_FAILED", {
					userId = userId,
					playerName = playerName
				})
			end
		end

		playerStats[userId] = nil

		activeShieldArms[userId] = nil
		hydratingPlayers[userId] = nil
		hydratedPlayers[userId] = nil
	end)
	
	-- Load stats for existing players (guarded so Studio doesn't hydrate twice)
	for _, player in ipairs(Players:GetPlayers()) do
		hydratePlayer(player, "existing_player_scan")
	end
	
	DebugService.Info("STATS", "INIT_READY")
end

function StatsService.GetStats(player)
	if not player or not player.Parent then return nil end
	local userId = player.UserId
	local slotExistsBeforeRead = playerStats[userId] ~= nil
	local stats = ensureStats(player)
	local slotCreated = not slotExistsBeforeRead
	if ensureWeekly(player, stats) then
		asyncSavePlayer(player, "WeeklyReset")
		StatsChanged:Fire(player)
	end
	local now = os.clock()
	local shouldLogRead = slotCreated or (now - (lastGetStatsLogAt[userId] or 0)) >= 1.5
	if shouldLogRead then
		lastGetStatsLogAt[userId] = now
		DebugService.Info("STATS", "GET_STATS_READ", {
			userId = userId,
			slotExistsBeforeRead = tostring(slotExistsBeforeRead),
			slotCreated = tostring(slotCreated),
			slotId = getStatsSlotId(stats),
			playerParentValid = tostring(player.Parent ~= nil),
			isDummyUserId = tostring(userId <= 0),
			stats = formatRoundDebugStats(stats)
		})
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
		WeeklyStamp = stats.WeeklyStamp,
		Gems = stats.Gems,
		Shields = stats.Shields,
		FreeShieldGranted = stats.FreeShieldGranted
	}
end

function StatsService.SetMaxShields(value)
	if type(value) == "number" and value >= 0 then
		MAX_SHIELDS = math.floor(value)
		DebugService.Info("STATS", "MAX_SHIELDS_UPDATED", {
			newMax = MAX_SHIELDS
		})
	end
end

function StatsService.GetMaxShields()
	return MAX_SHIELDS
end

function StatsService.GetShieldCount(player)
	if not (player and player.Parent) then return 0 end
	local stats = ensureStats(player)
	return stats.Shields or 0
end

-- Alias for consistency (single source of truth)
function StatsService.GetShields(player)
	return StatsService.GetShieldCount(player)
end

function StatsService.HasShield(player)
	return StatsService.GetShieldCount(player) > 0
end

function StatsService.GetGems(player)
	if not (player and player.Parent) then return 0 end
	local stats = ensureStats(player)
	return stats.Gems or 0
end

function StatsService.HasGems(player, amount)
	if type(amount) ~= "number" or amount <= 0 then
		return false
	end

	return StatsService.GetGems(player) >= amount
end

function StatsService.AddGems(player, amount, reason)
	if not (player and player.Parent) then return false end
	if type(amount) ~= "number" or amount <= 0 then
		DebugService.Warn("STATS", "GEMS_ADD_INVALID", {
			userId = player.UserId,
			amount = amount
		})
		return false
	end

	local stats = ensureStats(player)
	stats.Gems = (stats.Gems or 0) + amount

	asyncSavePlayer(player, reason or "GemsAdd")
	StatsChanged:Fire(player)

	DebugService.Info("STATS", "GEMS_ADDED", {
		userId = player.UserId,
		added = amount,
		total = stats.Gems,
		reason = reason
	})

	PushStatsUpdate(player)
	return true
end

function StatsService.SpendGems(player, amount, reason)
	if not (player and player.Parent) then return false end
	if type(amount) ~= "number" or amount <= 0 then
		DebugService.Warn("STATS", "GEMS_SPEND_INVALID", {
			userId = player.UserId,
			amount = amount
		})
		return false
	end

	local stats = ensureStats(player)
	local current = stats.Gems or 0

	if current < amount then
		DebugService.Info("STATS", "GEMS_SPEND_INSUFFICIENT", {
			userId = player.UserId,
			requested = amount,
			current = current,
			reason = reason
		})
		return false
	end

	stats.Gems = math.max(0, current - amount)

	asyncSavePlayer(player, reason or "GemsSpend")
	StatsChanged:Fire(player)

	DebugService.Info("STATS", "GEMS_SPENT", {
		userId = player.UserId,
		spent = amount,
		remaining = stats.Gems,
		reason = reason
	})

	PushStatsUpdate(player)
	return true
end

function StatsService.AddShields(player, amount)
	if not (player and player.Parent) then return false end
	if type(amount) ~= "number" or amount <= 0 then
		DebugService.Warn("STATS", "SHIELD_ADD_INVALID", {
			userId = player.UserId,
			amount = amount
		})
		return false
	end

	local stats = ensureStats(player)
	local previous = stats.Shields or 0

	-- Allow exceeding max if already above cap (legacy scenario)
	if previous < MAX_SHIELDS then
		stats.Shields = previous + amount
	else
		DebugService.Info("STATS", "SHIELD_ADD_BLOCKED_CAP", {
			userId = player.UserId,
			current = previous,
			max = MAX_SHIELDS
		})
		return false
	end

	asyncSavePlayer(player, "ShieldAdd")
	StatsChanged:Fire(player)

	DebugService.Info("STATS", "SHIELD_ADDED", {
		userId = player.UserId,
		added = amount,
		total = stats.Shields
	})

	PushStatsUpdate(player)
	if UIService.FireShieldChanged then
		UIService.FireShieldChanged(player, stats.Shields)
	end
	return true
end

function StatsService.ConsumeShield(player)
	if not (player and player.Parent) then return false end

	local stats = ensureStats(player)
	local current = stats.Shields or 0

	if current <= 0 then
		DebugService.Info("STATS", "SHIELD_CONSUME_FAILED", {
			userId = player.UserId
		})
		return false
	end

	stats.Shields = current - 1

	asyncSavePlayer(player, "ShieldConsume")
	StatsChanged:Fire(player)

	DebugService.Info("STATS", "SHIELD_CONSUMED", {
		userId = player.UserId,
		remaining = stats.Shields
	})

	PushStatsUpdate(player)
	if UIService.FireShieldChanged then
		UIService.FireShieldChanged(player, stats.Shields)
	end
	return true
end

function StatsService.IsShieldArmed(player)
	if not player then return false end
	return activeShieldArms[player.UserId] == true
end

function StatsService.ArmShield(player)
	if not (player and player.Parent) then
		return false
	end

	local userId = player.UserId

	-- Already armed
	if activeShieldArms[userId] then
		DebugService.Info("STATS", "SHIELD_ARM_ALREADY", {
			userId = userId
		})
		return false
	end

	-- Must own at least 1 shield to arm
	if not StatsService.HasShield(player) then
		DebugService.Info("STATS", "SHIELD_ARM_FAILED_NO_INVENTORY", {
			userId = userId
		})
		return false
	end

	activeShieldArms[userId] = true

	DebugService.Info("STATS", "SHIELD_ARMED", {
		userId = userId
	})

	return true
end

function StatsService.DisarmShield(player)
	if not player then return end

	local userId = player.UserId

	if activeShieldArms[userId] then
		activeShieldArms[userId] = nil

		DebugService.Info("STATS", "SHIELD_DISARMED", {
			userId = userId
		})
	end
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
--   streakProtectedLoserUserIds = {number}? (losers whose streak should not reset)
--   shieldConsumeUserIds = {number}? (players whose shield inventory decrements)
--   shieldDisarmUserIds = {number}? (players whose armed state clears)
--   reason = string? (optional debug)
-- }
function StatsService.ApplyRoundResult(playerA, playerB, resultPayload)
	-- Idempotency guard
	local roundId = resultPayload.roundId
	if not roundId then
		DebugService.Warn("STATS", "ROUND_MISSING_ID")
		return
	end
	
	if processedRounds[roundId] then
		DebugService.Warn("STATS", "ROUND_DUPLICATE", {
			roundId = roundId
		})
		return
	end
	processedRounds[roundId] = true

	local branchLabel = getRoundBranchLabel(resultPayload)
	local hasCashAwardMap = type(resultPayload.cashAwardByUserId) == "table"
	local playerAUserId = playerA and playerA.UserId or "nil"
	local playerBUserId = playerB and playerB.UserId or "nil"
	local slotAExists = playerA and playerStats[playerA.UserId] ~= nil or false
	local slotBExists = playerB and playerStats[playerB.UserId] ~= nil or false

	DebugService.Info("STATS", "ROUND_APPLY_ENTER", {
		roundId = roundId,
		branch = branchLabel,
		playerAUserId = playerAUserId,
		playerBUserId = playerBUserId,
		didDraw = tostring(resultPayload.didDraw == true),
		didBothLose = tostring(resultPayload.didBothLose == true),
		wasAborted = tostring(resultPayload.wasAborted == true),
		isNeutral = tostring(resultPayload.isNeutral == true),
		hasCashAwardMap = tostring(hasCashAwardMap),
		slotAExists = tostring(slotAExists),
		slotBExists = tostring(slotBExists),
		slotAId = playerA and getStatsSlotId(playerStats[playerA.UserId]) or "nil",
		slotBId = playerB and getStatsSlotId(playerStats[playerB.UserId]) or "nil",
		mutationKeyA = playerAUserId,
		mutationKeyB = playerBUserId
	})
	
	-- Neutral: no rewards, no stat changes (both timeout)
	if resultPayload.isNeutral then
		DebugService.Info("STATS", "ROUND_APPLY_EXIT", {
			roundId = roundId,
			branch = branchLabel,
			status = "neutral"
		})
		DebugService.Info("STATS", "ROUND_NEUTRAL", {
			roundId = roundId
		})
		return
	end
	
	-- Abort: no rewards, no stat changes
	if resultPayload.wasAborted then
		DebugService.Info("STATS", "ROUND_APPLY_EXIT", {
			roundId = roundId,
			branch = branchLabel,
			status = "aborted"
		})
		DebugService.Info("STATS", "ROUND_ABORTED", {
			roundId = roundId
		})
		return
	end
	
	local rewardCash = resultPayload.rewardCash or 0
	local streakProtectedLoserIds = toUserIdSet(resultPayload.streakProtectedLoserUserIds)
	local shieldConsumeUserIds = toUserIdSet(resultPayload.shieldConsumeUserIds)
	local shieldDisarmUserIds = toUserIdSet(resultPayload.shieldDisarmUserIds)
	
	-- Validate players
	if not (playerA and playerA.Parent) then
		DebugService.Info("STATS", "ROUND_APPLY_EXIT", {
			roundId = roundId,
			branch = branchLabel,
			status = "invalid_player_a"
		})
		warn("[StatsService] PlayerA invalid")
		return
	end
	if not (playerB and playerB.Parent) then
		DebugService.Info("STATS", "ROUND_APPLY_EXIT", {
			roundId = roundId,
			branch = branchLabel,
			status = "invalid_player_b"
		})
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

	local roundPlayers = {playerA, playerB}
	local beforeStatsA = formatRoundDebugStats(statsA)
	local beforeStatsB = formatRoundDebugStats(statsB)

	local function getFinalCashAward(player, legacyAward)
		if not player then
			return 0
		end

		if hasCashAwardMap then
			return math.max(0, math.floor(tonumber(resultPayload.cashAwardByUserId[player.UserId]) or 0))
		end

		return math.max(0, math.floor(tonumber(legacyAward) or 0))
	end

	local function applyShieldPayloadEffects(player)
		local userId = player.UserId

		if shieldConsumeUserIds[userId] then
			local consumed = StatsService.ConsumeShield(player)
			DebugService.Info("STATS", "ROUND_SHIELD_CONSUME", {
				roundId = roundId,
				userId = userId,
				consumed = consumed
			})
		end

		if shieldDisarmUserIds[userId] then
			StatsService.DisarmShield(player)
		end
	end
	
	-- GamesPlayed: increment for both players when round is not neutral/aborted
	statsA.GamesPlayed = statsA.GamesPlayed + 1
	statsB.GamesPlayed = statsB.GamesPlayed + 1
	statsA.WeeklyGamesPlayed = statsA.WeeklyGamesPlayed + 1
	statsB.WeeklyGamesPlayed = statsB.WeeklyGamesPlayed + 1
	
	-- Case 1: Both Lose (rare edge case)
	if resultPayload.didBothLose then
		DebugService.Info("STATS", "ROUND_BOTH_LOSE", {
			roundId = roundId
		})
		if streakProtectedLoserIds[playerA.UserId] then
			DebugService.Info("STATS", "ROUND_LOSER_STREAK_PROTECTED", {
				roundId = roundId,
				userId = playerA.UserId
			})
		else
			statsA.Streak = 0
		end

		if streakProtectedLoserIds[playerB.UserId] then
			DebugService.Info("STATS", "ROUND_LOSER_STREAK_PROTECTED", {
				roundId = roundId,
				userId = playerB.UserId
			})
		else
			statsB.Streak = 0
		end
	elseif resultPayload.didDraw then
		-- Case 2: Draw / Split-Split (both win)
		local splitReward = math.floor(rewardCash / 2)
		local awardA = getFinalCashAward(playerA, splitReward)
		local awardB = getFinalCashAward(playerB, splitReward)
		DebugService.Info("STATS", "ROUND_DRAW", {
			roundId = roundId,
			baseRewardCash = rewardCash,
			awardA = awardA,
			awardB = awardB
		})
		
		-- Player A: cash + wins + streak
		statsA.Cash = statsA.Cash + awardA
		statsA.Wins = statsA.Wins + 1
		statsA.Streak = statsA.Streak + 1
		statsA.MaxStreak = math.max(statsA.MaxStreak, statsA.Streak)
		statsA.WeeklyMaxStreak = math.max(statsA.WeeklyMaxStreak, statsA.Streak)
		
		-- Player B: cash + wins + streak
		statsB.Cash = statsB.Cash + awardB
		statsB.Wins = statsB.Wins + 1
		statsB.Streak = statsB.Streak + 1
		statsB.MaxStreak = math.max(statsB.MaxStreak, statsB.Streak)
		statsB.WeeklyMaxStreak = math.max(statsB.WeeklyMaxStreak, statsB.Streak)

	-- Case 3: Single Winner
	else
		local winnerId = resultPayload.winnerUserId
		
		if not winnerId then
			DebugService.Info("STATS", "ROUND_APPLY_EXIT", {
				roundId = roundId,
				branch = branchLabel,
				status = "missing_winner",
				beforeStatsA = beforeStatsA,
				beforeStatsB = beforeStatsB
			})
			warn("[StatsService] No winner specified and not draw/abort - unexpected")
			return
		end
		
		local winner = playerA.UserId == winnerId and playerA or (playerB.UserId == winnerId and playerB or nil)
		local loserId = resultPayload.loserUserId
		local loser = nil

		if loserId then
			if playerA.UserId == loserId then
				loser = playerA
			elseif playerB.UserId == loserId then
				loser = playerB
			end
		end

		if not winner then
			DebugService.Info("STATS", "ROUND_APPLY_EXIT", {
				roundId = roundId,
				branch = branchLabel,
				status = "winner_mismatch",
				beforeStatsA = beforeStatsA,
				beforeStatsB = beforeStatsB
			})
			warn("[StatsService] Winner UserId does not match either player")
			return
		end

		local winnerStats = ensureStats(winner)
		local winnerAward = getFinalCashAward(winner, rewardCash)

		-- Apply winner rewards
		winnerStats.Cash = winnerStats.Cash + winnerAward
		winnerStats.Wins = winnerStats.Wins + 1
		winnerStats.Streak = winnerStats.Streak + 1
		winnerStats.MaxStreak = math.max(winnerStats.MaxStreak, winnerStats.Streak)
		winnerStats.WeeklyMaxStreak = math.max(winnerStats.WeeklyMaxStreak, winnerStats.Streak)

		DebugService.Info("STATS", "ROUND_WINNER", {
			roundId = roundId,
			winnerId = winner.UserId,
			baseRewardCash = rewardCash,
			reward = winnerAward,
			streak = winnerStats.Streak
		})

		if loser then
			local loserStats = ensureStats(loser)
			if streakProtectedLoserIds[loser.UserId] then
				DebugService.Info("STATS", "ROUND_LOSER_STREAK_PROTECTED", {
					roundId = roundId,
					loserId = loser.UserId
				})
			else
				loserStats.Streak = 0
				DebugService.Info("STATS", "ROUND_LOSER_RESET", {
					roundId = roundId,
					loserId = loser.UserId
				})
			end
		end
	end

	for _, player in ipairs(roundPlayers) do
		applyShieldPayloadEffects(player)
	end
	
	-- Save both players (non-blocking)
	asyncSavePlayer(playerA, "RoundResult")
	asyncSavePlayer(playerB, "RoundResult")
	StatsChanged:Fire(playerA)
	StatsChanged:Fire(playerB)
	DebugService.Info("STATS", "ROUND_APPLY_EXIT", {
		roundId = roundId,
		branch = branchLabel,
		status = "ok",
		afterStatsA = formatRoundDebugStats(statsA),
		afterStatsB = formatRoundDebugStats(statsB),
		beforeStatsA = beforeStatsA,
		beforeStatsB = beforeStatsB,
		slotAId = getStatsSlotId(statsA),
		slotBId = getStatsSlotId(statsB)
	})
end

-- Add donation to player's TotalDonated. Validates amount > 0, saves async, fires StatsChanged.
function StatsService.AddDonation(player, amount)
	if not (player and player.Parent) then return end
	if type(amount) ~= "number" or amount <= 0 then
		DebugService.Warn("STATS", "DONATION_INVALID")
		return
	end
	local stats = ensureStats(player)
	if ensureWeekly(player, stats) then
		asyncSavePlayer(player, "WeeklyReset")
		StatsChanged:Fire(player)
	end
	stats.TotalDonated = stats.TotalDonated + amount
	stats.WeeklyDonations = stats.WeeklyDonations + amount
	DebugService.Info("STATS", "DONATION_ADDED", {
		userId = player.UserId,
		amount = amount,
		weeklyTotal = stats.WeeklyDonations
	})
	asyncSavePlayer(player, "Donation")
	StatsChanged:Fire(player)
end

return StatsService

