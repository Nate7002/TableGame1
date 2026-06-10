local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Core = script.Parent
local MonetizationService = require(Core:WaitForChild("MonetizationService"))
local StatsService = require(Core:WaitForChild("StatsService"))

local DevTestService = {}

local COMMAND_PREFIX = "[DevTest]"
local PRODUCT_DECISION = Enum.ProductPurchaseDecision
local ROUND_REWARD_CASH = 100
local COMPARED_FIELDS = { "Cash", "Wins", "Streak", "MaxStreak", "GamesPlayed" }
local NO_MUTATION_FIELDS = { "Cash", "Gems", "Shields", "Wins", "Streak", "MaxStreak", "GamesPlayed" }
local trackedPlayers = {}
local initialized = false
local nextSyntheticUserId = -1
local scenarioRegistry = {}

local function positiveInteger(value)
	return type(value) == "number" and value > 0 and math.floor(value) == value
end

local function canUseHarnessCommands(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and type(player.UserId) == "number"
		and math.floor(player.UserId) == player.UserId
		and (player.UserId > 0 or (RunService:IsStudio() and player.UserId < 0))
end

local function trimMessage(message)
	if type(message) ~= "string" then
		return ""
	end

	return string.match(message, "^%s*(.-)%s*$") or ""
end

local function getStatsSnapshot(player)
	local stats = StatsService.GetStats(player)
	if not stats then
		return nil
	end

	return {
		UserId = player.UserId,
		Cash = tonumber(stats.Cash) or 0,
		Gems = tonumber(stats.Gems) or 0,
		Shields = tonumber(stats.Shields) or 0,
		Wins = tonumber(stats.Wins) or 0,
		Streak = tonumber(stats.Streak) or 0,
		MaxStreak = tonumber(stats.MaxStreak) or 0,
		GamesPlayed = tonumber(stats.GamesPlayed) or 0,
	}
end

local function formatSnapshot(snapshot)
	if not snapshot then
		return "snapshot=nil"
	end

	return string.format(
		"uid=%d cash=%d gems=%d shields=%d wins=%d streak=%d max=%d games=%d",
		tonumber(snapshot.UserId) or 0,
		tonumber(snapshot.Cash) or 0,
		tonumber(snapshot.Gems) or 0,
		tonumber(snapshot.Shields) or 0,
		tonumber(snapshot.Wins) or 0,
		tonumber(snapshot.Streak) or 0,
		tonumber(snapshot.MaxStreak) or 0,
		tonumber(snapshot.GamesPlayed) or 0
	)
end

local function buildDelta(beforeSnapshot, afterSnapshot)
	beforeSnapshot = beforeSnapshot or {}
	afterSnapshot = afterSnapshot or {}

	return {
		Cash = (afterSnapshot.Cash or 0) - (beforeSnapshot.Cash or 0),
		Wins = (afterSnapshot.Wins or 0) - (beforeSnapshot.Wins or 0),
		Streak = (afterSnapshot.Streak or 0) - (beforeSnapshot.Streak or 0),
		MaxStreak = (afterSnapshot.MaxStreak or 0) - (beforeSnapshot.MaxStreak or 0),
		GamesPlayed = (afterSnapshot.GamesPlayed or 0) - (beforeSnapshot.GamesPlayed or 0),
	}
end

local function formatDelta(delta)
	return string.format(
		"cash=%+d wins=%+d streak=%+d max=%+d games=%+d",
		tonumber(delta.Cash) or 0,
		tonumber(delta.Wins) or 0,
		tonumber(delta.Streak) or 0,
		tonumber(delta.MaxStreak) or 0,
		tonumber(delta.GamesPlayed) or 0
	)
end

local function compareSnapshots(actualSnapshot, expectedSnapshot, fields)
	local mismatches = {}

	for _, fieldName in ipairs(fields) do
		if actualSnapshot[fieldName] ~= expectedSnapshot[fieldName] then
			table.insert(
				mismatches,
				string.format(
					"%s expected=%s actual=%s",
					fieldName,
					tostring(expectedSnapshot[fieldName]),
					tostring(actualSnapshot[fieldName])
				)
			)
		end
	end

	return #mismatches == 0, mismatches
end

local function appendMismatch(mismatches, label, expectedValue, actualValue)
	if expectedValue ~= actualValue then
		table.insert(
			mismatches,
			string.format("%s expected=%s actual=%s", label, tostring(expectedValue), tostring(actualValue))
		)
	end
end

local function printSnapshotLine(label, player, snapshot)
	print(string.format(
		"%s %s %s {%s}",
		COMMAND_PREFIX,
		label,
		player.Name or "Unknown",
		formatSnapshot(snapshot)
	))
end

local function dumpPlayerStats(player, label)
	local snapshot = getStatsSnapshot(player)
	if not snapshot then
		warn(string.format("%s %s %s snapshot unavailable", COMMAND_PREFIX, label, player.Name or "Unknown"))
		return
	end

	printSnapshotLine(label, player, snapshot)
end

local function makeSyntheticRival()
	local syntheticUserId = nextSyntheticUserId
	nextSyntheticUserId -= 1

	return {
		Name = "SyntheticRival_" .. tostring(math.abs(syntheticUserId)),
		UserId = syntheticUserId,
		Parent = script,
	}
end

local function buildRoundId(scenarioName, player)
	return string.format("devtest_%s_%d_%0.6f", scenarioName, player.UserId, os.clock())
end

local function buildWinnerAfter(beforeSnapshot, cashAward)
	return {
		Cash = beforeSnapshot.Cash + cashAward,
		Wins = beforeSnapshot.Wins + 1,
		Streak = beforeSnapshot.Streak + 1,
		MaxStreak = math.max(beforeSnapshot.MaxStreak, beforeSnapshot.Streak + 1),
		GamesPlayed = beforeSnapshot.GamesPlayed + 1,
	}
end

local function buildLoserAfter(beforeSnapshot)
	return {
		Cash = beforeSnapshot.Cash,
		Wins = beforeSnapshot.Wins,
		Streak = 0,
		MaxStreak = beforeSnapshot.MaxStreak,
		GamesPlayed = beforeSnapshot.GamesPlayed + 1,
	}
end

local function buildDrawAfter(beforeSnapshot, cashAward)
	return {
		Cash = beforeSnapshot.Cash + cashAward,
		Wins = beforeSnapshot.Wins + 1,
		Streak = beforeSnapshot.Streak + 1,
		MaxStreak = math.max(beforeSnapshot.MaxStreak, beforeSnapshot.Streak + 1),
		GamesPlayed = beforeSnapshot.GamesPlayed + 1,
	}
end

local function buildBothLoseAfter(beforeSnapshot)
	return {
		Cash = beforeSnapshot.Cash,
		Wins = beforeSnapshot.Wins,
		Streak = 0,
		MaxStreak = beforeSnapshot.MaxStreak,
		GamesPlayed = beforeSnapshot.GamesPlayed + 1,
	}
end

local function buildProjectedRestoreStreak(preLossStreak, tier)
	if not positiveInteger(preLossStreak) then
		return nil
	end

	if not positiveInteger(tier) or tier < 1 or tier > 3 then
		return nil
	end

	return math.max(1, math.ceil(preLossStreak * tier / 3))
end

local function buildExpectedProjectedRestoreStreak(player, preLossStreak, tier)
	if positiveInteger(preLossStreak) and MonetizationService.PlayerHasVIP(player) then
		return preLossStreak
	end

	return buildProjectedRestoreStreak(preLossStreak, tier)
end

local function buildMonetizationOutcomeContext(resultPayload, participants, preRoundStatsByUserId)
	local loserUserId = resultPayload and resultPayload.loserUserId
	local loserPreLossStats = type(preRoundStatsByUserId) == "table" and preRoundStatsByUserId[loserUserId] or nil
	local loserPreLossStreak = type(loserPreLossStats) == "table" and tonumber(loserPreLossStats.Streak) or nil

	return {
		RoundId = resultPayload and resultPayload.roundId,
		ParticipantUserIds = {
			participants[1] and participants[1].UserId,
			participants[2] and participants[2].UserId,
		},
		WinnerUserId = resultPayload and resultPayload.winnerUserId,
		LoserUserId = resultPayload and resultPayload.loserUserId,
		LoserPreLossStreak = loserPreLossStreak,
		DidDraw = resultPayload and resultPayload.didDraw == true,
		DidBothLose = resultPayload and resultPayload.didBothLose == true,
		WasAborted = resultPayload and resultPayload.wasAborted == true,
		IsNeutral = resultPayload and resultPayload.isNeutral == true,
		StreakProtectedLoserUserIds = (resultPayload and resultPayload.streakProtectedLoserUserIds) or {},
	}
end

local function addCleanupTask(context, cleanupTask)
	if type(cleanupTask) ~= "function" then
		return
	end

	context.cleanupTasks = context.cleanupTasks or {}
	table.insert(context.cleanupTasks, cleanupTask)
end

local function restoreStudioVipOverride(player, priorState)
	if not player then
		return
	end

	if priorState and priorState.source == "forced" then
		MonetizationService.SetStudioVIPOverride(player, priorState.value)
		return
	end

	MonetizationService.SetStudioVIPOverride(player, nil)
end

local function applyForcedVipOverride(context, player, forcedValue)
	local priorState = MonetizationService.GetStudioVIPOverrideState(player)
	if not MonetizationService.SetStudioVIPOverride(player, forcedValue) then
		return false
	end

	addCleanupTask(context, function()
		restoreStudioVipOverride(player, priorState)
	end)

	return true
end

local function runCleanupTasks(context)
	for index = #(context.cleanupTasks or {}), 1, -1 do
		local cleanupTask = context.cleanupTasks[index]
		local ok, err = pcall(cleanupTask)
		if not ok then
			warn(string.format(
				"%s cleanup scenario=%s error=%s",
				COMMAND_PREFIX,
				context.scenarioName or "unknown",
				tostring(err)
			))
		end
	end
end

local function formatStudioOverride(snapshot)
	local source = snapshot and snapshot.StudioOverrideSource or "unknown"

	if source == "forced" then
		return (snapshot.StudioOverrideValue == true) and "forced:on" or "forced:off"
	end

	if source == "config" then
		return "config:on"
	end

	return source
end

local function buildVipValidationMismatches(context)
	local mismatches = {}
	local callerMonetization = context.callerMonetization

	if not callerMonetization then
		table.insert(mismatches, "caller.monetization unavailable")
		return mismatches
	end

	appendMismatch(mismatches, "caller.vip", true, callerMonetization.HasVIP)
	appendMismatch(mismatches, "caller.overrideSource", "forced", callerMonetization.StudioOverrideSource)

	local rewardMultiplier = tonumber(callerMonetization.RewardMultiplier) or 0
	if rewardMultiplier <= 1 then
		table.insert(
			mismatches,
			string.format("caller.rewardMultiplier expected=>1 actual=%s", tostring(callerMonetization.RewardMultiplier))
		)
	end

	appendMismatch(mismatches, "synthetic.rewardMultiplier", 1, context.syntheticRewardMultiplier)
	return mismatches
end

local function reportScenarioResult(context)
	local expectedPlayerDelta = buildDelta(context.beforeCaller, context.expectedAfterCaller)
	local expectedRivalDelta = buildDelta(context.beforeSynthetic, context.expectedAfterSynthetic)
	local actualPlayerDelta = buildDelta(context.beforeCaller, context.afterCaller)
	local actualRivalDelta = buildDelta(context.beforeSynthetic, context.afterSynthetic)

	print(string.format(
		"%s scenario=%s caller=%s synthetic=%s",
		COMMAND_PREFIX,
		context.scenarioName,
		context.caller.Name,
		context.syntheticRival.Name
	))
	print(string.format(
		"%s before caller{%s} synthetic{%s}",
		COMMAND_PREFIX,
		formatSnapshot(context.beforeCaller),
		formatSnapshot(context.beforeSynthetic)
	))
	print(string.format(
		"%s expected delta caller{%s} synthetic{%s}",
		COMMAND_PREFIX,
		formatDelta(expectedPlayerDelta),
		formatDelta(expectedRivalDelta)
	))
	print(string.format(
		"%s actual delta caller{%s} synthetic{%s}",
		COMMAND_PREFIX,
		formatDelta(actualPlayerDelta),
		formatDelta(actualRivalDelta)
	))

	local playerPass, playerMismatches = compareSnapshots(context.afterCaller, context.expectedAfterCaller, COMPARED_FIELDS)
	local rivalPass, rivalMismatches =
		compareSnapshots(context.afterSynthetic, context.expectedAfterSynthetic, COMPARED_FIELDS)
	local validationMismatches = context.validationMismatches or {}
	local passed = playerPass and rivalPass and #validationMismatches == 0

	if passed then
		print(string.format("%s PASS scenario=%s", COMMAND_PREFIX, context.scenarioName))
		return
	end

	local mismatchParts = {}
	for _, mismatch in ipairs(playerMismatches) do
		table.insert(mismatchParts, "caller." .. mismatch)
	end
	for _, mismatch in ipairs(rivalMismatches) do
		table.insert(mismatchParts, "synthetic." .. mismatch)
	end
	for _, mismatch in ipairs(validationMismatches) do
		table.insert(mismatchParts, mismatch)
	end

	warn(string.format(
		"%s FAIL scenario=%s %s",
		COMMAND_PREFIX,
		context.scenarioName,
		table.concat(mismatchParts, " | ")
	))
end

scenarioRegistry = {
	single_win_p1 = {
		buildResultPayload = function(context)
			return {
				roundId = buildRoundId(context.scenarioName, context.caller),
				rewardCash = context.rewardCash,
				winnerUserId = context.caller.UserId,
				loserUserId = context.syntheticRival.UserId,
			}
		end,
		buildExpectedAfter = function(context)
			return {
				caller = buildWinnerAfter(context.beforeCaller, context.rewardCash),
				synthetic = buildLoserAfter(context.beforeSynthetic),
			}
		end,
	},
	single_lose_p1 = {
		buildResultPayload = function(context)
			return {
				roundId = buildRoundId(context.scenarioName, context.caller),
				rewardCash = context.rewardCash,
				winnerUserId = context.syntheticRival.UserId,
				loserUserId = context.caller.UserId,
			}
		end,
		buildExpectedAfter = function(context)
			return {
				caller = buildLoserAfter(context.beforeCaller),
				synthetic = buildWinnerAfter(context.beforeSynthetic, context.rewardCash),
			}
		end,
	},
	draw = {
		buildResultPayload = function(context)
			return {
				roundId = buildRoundId(context.scenarioName, context.caller),
				rewardCash = context.rewardCash,
				didDraw = true,
				didBothLose = false,
				isNeutral = false,
				wasAborted = false,
			}
		end,
		buildExpectedAfter = function(context)
			local splitReward = math.floor(context.rewardCash / 2)
			return {
				caller = buildDrawAfter(context.beforeCaller, splitReward),
				synthetic = buildDrawAfter(context.beforeSynthetic, splitReward),
			}
		end,
	},
	vip_single_win_p1 = {
		setup = function(context)
			if not applyForcedVipOverride(context, context.caller, true) then
				error("caller VIP override failed")
			end

			context.callerMonetization = MonetizationService.GetPlayerMonetizationSnapshot(context.caller)
			context.callerRewardMultiplier =
				math.max(1, tonumber(context.callerMonetization and context.callerMonetization.RewardMultiplier) or 1)
			context.syntheticRewardMultiplier =
				math.max(1, tonumber(MonetizationService.GetRewardMultiplier(context.syntheticRival)) or 1)
		end,
		validate = buildVipValidationMismatches,
		buildResultPayload = function(context)
			local callerAward = math.max(0, math.floor(context.rewardCash * context.callerRewardMultiplier))
			context.cashAwardByUserId = {
				[context.caller.UserId] = callerAward,
				[context.syntheticRival.UserId] = 0,
			}

			return {
				roundId = buildRoundId(context.scenarioName, context.caller),
				rewardCash = context.rewardCash,
				winnerUserId = context.caller.UserId,
				loserUserId = context.syntheticRival.UserId,
				cashAwardByUserId = context.cashAwardByUserId,
			}
		end,
		buildExpectedAfter = function(context)
			return {
				caller = buildWinnerAfter(context.beforeCaller, context.cashAwardByUserId[context.caller.UserId] or 0),
				synthetic = buildLoserAfter(context.beforeSynthetic),
			}
		end,
	},
	vip_draw_mixed = {
		setup = function(context)
			if not applyForcedVipOverride(context, context.caller, true) then
				error("caller VIP override failed")
			end

			context.callerMonetization = MonetizationService.GetPlayerMonetizationSnapshot(context.caller)
			context.callerRewardMultiplier =
				math.max(1, tonumber(context.callerMonetization and context.callerMonetization.RewardMultiplier) or 1)
			context.syntheticRewardMultiplier =
				math.max(1, tonumber(MonetizationService.GetRewardMultiplier(context.syntheticRival)) or 1)
		end,
		validate = buildVipValidationMismatches,
		buildResultPayload = function(context)
			local splitReward = math.floor(context.rewardCash / 2)
			local callerAward = math.max(0, math.floor(splitReward * context.callerRewardMultiplier))
			local syntheticAward = math.max(0, math.floor(splitReward * context.syntheticRewardMultiplier))
			context.cashAwardByUserId = {
				[context.caller.UserId] = callerAward,
				[context.syntheticRival.UserId] = syntheticAward,
			}

			return {
				roundId = buildRoundId(context.scenarioName, context.caller),
				rewardCash = context.rewardCash,
				didDraw = true,
				didBothLose = false,
				isNeutral = false,
				wasAborted = false,
				cashAwardByUserId = context.cashAwardByUserId,
			}
		end,
		buildExpectedAfter = function(context)
			return {
				caller = buildDrawAfter(context.beforeCaller, context.cashAwardByUserId[context.caller.UserId] or 0),
				synthetic = buildDrawAfter(
					context.beforeSynthetic,
					context.cashAwardByUserId[context.syntheticRival.UserId] or 0
				),
			}
		end,
	},
	both_lose = {
		buildResultPayload = function(context)
			return {
				roundId = buildRoundId(context.scenarioName, context.caller),
				rewardCash = context.rewardCash,
				didBothLose = true,
				didDraw = false,
				isNeutral = false,
				wasAborted = false,
			}
		end,
		buildExpectedAfter = function(context)
			return {
				caller = buildBothLoseAfter(context.beforeCaller),
				synthetic = buildBothLoseAfter(context.beforeSynthetic),
			}
		end,
	},
}

local function getScenarioUsage()
	local scenarioNames = {}

	for scenarioName in pairs(scenarioRegistry) do
		table.insert(scenarioNames, scenarioName)
	end

	table.sort(scenarioNames)
	return table.concat(scenarioNames, " | ")
end

local function handleDumpStats(messagePlayer, dumpAll)
	if dumpAll then
		print(string.format("%s /dumpstats all", COMMAND_PREFIX))
		for _, player in ipairs(Players:GetPlayers()) do
			dumpPlayerStats(player, "player")
		end
		return
	end

	print(string.format("%s /dumpstats caller=%s", COMMAND_PREFIX, messagePlayer.Name))
	dumpPlayerStats(messagePlayer, "player")
end

local function handleDumpMonetization(player)
	local snapshot = MonetizationService.GetPlayerMonetizationSnapshot(player)
	if not snapshot then
		warn(string.format("%s /dumpmonetization snapshot unavailable", COMMAND_PREFIX))
		return
	end

	local routingSnapshot = MonetizationService.GetReceiptRoutingSnapshot()
	local receiptKinds = "none"
	if routingSnapshot and #(routingSnapshot.RegisteredReceiptKinds or {}) > 0 then
		receiptKinds = table.concat(routingSnapshot.RegisteredReceiptKinds, ",")
	end

	print(string.format(
		"%s monetization uid=%d vip=%s multiplier=%s override=%s",
		COMMAND_PREFIX,
		snapshot.UserId,
		tostring(snapshot.HasVIP),
		tostring(snapshot.RewardMultiplier),
		formatStudioOverride(snapshot)
	))
	print(string.format(
		"%s receipt-routing initialized=%s bound=%s configured=%d indexed=%d kinds=%s",
		COMMAND_PREFIX,
		tostring(routingSnapshot and routingSnapshot.Initialized == true),
		tostring(routingSnapshot and routingSnapshot.ProcessReceiptBound == true),
		tonumber(routingSnapshot and routingSnapshot.ConfiguredProductCount) or 0,
		tonumber(routingSnapshot and routingSnapshot.IndexedProductCount) or 0,
		receiptKinds
	))

	local restoreSnapshot = MonetizationService.GetRestoreOfferSnapshot(player)
	local restoreKeys = "none"
	if restoreSnapshot and #(restoreSnapshot.ValidRestoreProductKeys or {}) > 0 then
		restoreKeys = table.concat(restoreSnapshot.ValidRestoreProductKeys, ",")
	end

	print(string.format(
		"%s restore-offer active=%s reason=%s remaining=%0.2fs cooldown=%0.2fs preLoss=%s selectedKey=%s selectedTier=%s projected=%s keys=%s",
		COMMAND_PREFIX,
		tostring(restoreSnapshot and restoreSnapshot.Active == true),
		tostring(restoreSnapshot and restoreSnapshot.Reason or "NoActiveOffer"),
		tonumber(restoreSnapshot and restoreSnapshot.SecondsRemaining) or 0,
		tonumber(restoreSnapshot and restoreSnapshot.CooldownRemaining) or 0,
		tostring(restoreSnapshot and restoreSnapshot.PreLossStreak),
		tostring(restoreSnapshot and restoreSnapshot.SelectedRestoreProductKey),
		tostring(restoreSnapshot and restoreSnapshot.SelectedRestoreTier),
		tostring(restoreSnapshot and restoreSnapshot.ProjectedRestoredStreak),
		restoreKeys
	))
end

local function handleSetVip(player, rawMode)
	local mode = string.lower(rawMode or "")
	local overrideValue = nil

	if mode == "on" then
		overrideValue = true
	elseif mode == "off" then
		overrideValue = false
	else
		warn(string.format("%s Usage: /setvip on | /setvip off", COMMAND_PREFIX))
		return
	end

	if not MonetizationService.SetStudioVIPOverride(player, overrideValue) then
		warn(string.format("%s /setvip %s failed", COMMAND_PREFIX, mode))
		return
	end

	print(string.format("%s /setvip %s caller=%s", COMMAND_PREFIX, mode, player.Name))
	handleDumpMonetization(player)
end

local function getReceiptTestExpectation(productConfig, beforeSnapshot, restoreValidationBefore)
	local expectation = {
		Decision = PRODUCT_DECISION.NotProcessedYet,
		ExpectedGemDelta = 0,
		ExpectedShieldDelta = 0,
		ExpectedKind = "Unknown",
		ExpectedSnapshot = {
			Cash = beforeSnapshot.Cash,
			Wins = beforeSnapshot.Wins,
			Streak = beforeSnapshot.Streak,
			MaxStreak = beforeSnapshot.MaxStreak,
			GamesPlayed = beforeSnapshot.GamesPlayed,
		},
		ExpectRestoreConsumed = false,
		ProjectedRestoreStreak = nil,
	}

	if type(productConfig) ~= "table" then
		return expectation
	end

	expectation.ExpectedKind = tostring(productConfig.Kind or "Unknown")
	local amount = tonumber(productConfig.Amount)
	if productConfig.Kind == "Gems" and amount and amount > 0 and math.floor(amount) == amount then
		expectation.Decision = PRODUCT_DECISION.PurchaseGranted
		expectation.ExpectedGemDelta = amount
		return expectation
	end

	if productConfig.Kind == "Shields" and amount and amount > 0 and math.floor(amount) == amount then
		local currentShields = type(beforeSnapshot) == "table" and (tonumber(beforeSnapshot.Shields) or 0) or 0
		if currentShields < StatsService.GetMaxShields() then
			expectation.Decision = PRODUCT_DECISION.PurchaseGranted
			expectation.ExpectedShieldDelta = amount
		end
		return expectation
	end

	if productConfig.Kind == "Restore" then
		local projectedRestoreStreak = restoreValidationBefore and tonumber(restoreValidationBefore.ProjectedRestoredStreak) or nil
		expectation.ProjectedRestoreStreak = projectedRestoreStreak
		if restoreValidationBefore and restoreValidationBefore.Allowed == true and positiveInteger(projectedRestoreStreak) then
			expectation.Decision = PRODUCT_DECISION.PurchaseGranted
			expectation.ExpectedSnapshot.Streak = projectedRestoreStreak
			expectation.ExpectedSnapshot.MaxStreak = math.max(beforeSnapshot.MaxStreak or 0, projectedRestoreStreak)
			expectation.ExpectRestoreConsumed = true
		end
		return expectation
	end

	return expectation
end

local function handleTestReceipt(player, rawProductKey)
	local productKey = trimMessage(rawProductKey)
	if productKey == "" then
		warn(string.format("%s Usage: /testreceipt <productKey>", COMMAND_PREFIX))
		return
	end

	local beforeSnapshot = getStatsSnapshot(player)
	if not beforeSnapshot then
		warn(string.format("%s /testreceipt %s before snapshot unavailable", COMMAND_PREFIX, productKey))
		return
	end

	local restoreValidationBefore = MonetizationService.ValidateRestoreAttempt(player, productKey)
	local restoreSnapshotBefore = MonetizationService.GetRestoreOfferSnapshot(player)
	local decision, productConfig = MonetizationService.RunStudioOnlyReceiptTest(player, productKey)
	local afterSnapshot = getStatsSnapshot(player)
	if not afterSnapshot then
		warn(string.format("%s /testreceipt %s after snapshot unavailable", COMMAND_PREFIX, productKey))
		return
	end

	local restoreSnapshotAfter = MonetizationService.GetRestoreOfferSnapshot(player)
	local expectation = getReceiptTestExpectation(productConfig, beforeSnapshot, restoreValidationBefore)
	local actualGemDelta = (afterSnapshot.Gems or 0) - (beforeSnapshot.Gems or 0)
	local actualShieldDelta = (afterSnapshot.Shields or 0) - (beforeSnapshot.Shields or 0)
	local actualKind = type(productConfig) == "table" and tostring(productConfig.Kind or "Unknown") or "Unknown"
	local snapshotPassed, snapshotMismatches = compareSnapshots(afterSnapshot, expectation.ExpectedSnapshot, COMPARED_FIELDS)
	local mismatches = {}

	appendMismatch(mismatches, "decision", expectation.Decision, decision)
	appendMismatch(mismatches, "gemDelta", expectation.ExpectedGemDelta, actualGemDelta)
	appendMismatch(mismatches, "shieldDelta", expectation.ExpectedShieldDelta, actualShieldDelta)
	for _, mismatch in ipairs(snapshotMismatches) do
		table.insert(mismatches, mismatch)
	end

	if actualKind == "Restore" then
		if expectation.ExpectRestoreConsumed then
			appendMismatch(mismatches, "restoreActiveAfter", false, restoreSnapshotAfter and restoreSnapshotAfter.Active == true)
			appendMismatch(mismatches, "restoreReasonAfter", "Consumed", restoreSnapshotAfter and restoreSnapshotAfter.Reason)
		else
			appendMismatch(
				mismatches,
				"restoreActiveAfterBlocked",
				restoreSnapshotBefore and restoreSnapshotBefore.Active == true,
				restoreSnapshotAfter and restoreSnapshotAfter.Active == true
			)
			appendMismatch(
				mismatches,
				"restoreReasonAfterBlocked",
				restoreSnapshotBefore and restoreSnapshotBefore.Reason,
				restoreSnapshotAfter and restoreSnapshotAfter.Reason
			)
		end
	end

	local passed = snapshotPassed and #mismatches == 0

	print(string.format(
		"%s receipt=%s kind=%s decision=%s expectedDecision=%s gemDelta=%+d expectedGemDelta=%+d shieldDelta=%+d expectedShieldDelta=%+d projectedRestore=%s",
		COMMAND_PREFIX,
		productKey,
		actualKind,
		tostring(decision),
		tostring(expectation.Decision),
		actualGemDelta,
		expectation.ExpectedGemDelta,
		actualShieldDelta,
		expectation.ExpectedShieldDelta,
		tostring(expectation.ProjectedRestoreStreak)
	))
	print(string.format(
		"%s receipt before{%s} after{%s}",
		COMMAND_PREFIX,
		formatSnapshot(beforeSnapshot),
		formatSnapshot(afterSnapshot)
	))

	if passed then
		print(string.format("%s PASS receipt=%s expectedKind=%s", COMMAND_PREFIX, productKey, expectation.ExpectedKind))
		return
	end

	warn(string.format(
		"%s FAIL receipt=%s actualKind=%s decision=%s expectedDecision=%s gemDelta=%+d expectedGemDelta=%+d shieldDelta=%+d expectedShieldDelta=%+d mismatches=%s",
		COMMAND_PREFIX,
		productKey,
		actualKind,
		tostring(decision),
		tostring(expectation.Decision),
		actualGemDelta,
		expectation.ExpectedGemDelta,
		actualShieldDelta,
		expectation.ExpectedShieldDelta,
		#mismatches > 0 and table.concat(mismatches, " | ") or "none"
	))
end

local function getRestoreTestExpectation(productKey, restoreSnapshot)
	local productConfig = MonetizationService.GetDeveloperProductConfig(productKey)
	if type(productConfig) ~= "table" or productConfig.Kind ~= "Restore" then
		return false, "UnknownRestoreProduct", productConfig
	end

	if restoreSnapshot and restoreSnapshot.Active == true then
		if tostring(restoreSnapshot.SelectedRestoreProductKey) == tostring(productKey) then
			return true, "EligibleForValidationOnly", productConfig
		end

		return false, "UnknownRestoreProduct", productConfig
	end

	if restoreSnapshot and restoreSnapshot.Reason == "OfferExpired" then
		return false, "OfferExpired", productConfig
	end

	if restoreSnapshot and restoreSnapshot.Reason == "CooldownActive" then
		return false, "CooldownActive", productConfig
	end

	return false, "NoActiveOffer", productConfig
end

local function handleTestRestore(player, rawProductKey)
	local productKey = trimMessage(rawProductKey)
	if productKey == "" then
		warn(string.format("%s Usage: /testrestore <productKey>", COMMAND_PREFIX))
		return
	end

	local beforeSnapshot = getStatsSnapshot(player)
	if not beforeSnapshot then
		warn(string.format("%s /testrestore %s before snapshot unavailable", COMMAND_PREFIX, productKey))
		return
	end

	local restoreSnapshotBefore = MonetizationService.GetRestoreOfferSnapshot(player)
	local expectedAllowed, expectedReason, productConfig = getRestoreTestExpectation(productKey, restoreSnapshotBefore)
	local validation = MonetizationService.ValidateRestoreAttempt(player, productKey)
	local afterSnapshot = getStatsSnapshot(player)
	if not afterSnapshot then
		warn(string.format("%s /testrestore %s after snapshot unavailable", COMMAND_PREFIX, productKey))
		return
	end

	local unchanged, mismatches = compareSnapshots(afterSnapshot, beforeSnapshot, NO_MUTATION_FIELDS)
	local actualKind = type(productConfig) == "table" and tostring(productConfig.Kind or "Unknown") or "Unknown"
	local expectedPreLossStreak = restoreSnapshotBefore and restoreSnapshotBefore.PreLossStreak or nil
	local expectedTier = restoreSnapshotBefore and restoreSnapshotBefore.SelectedRestoreTier
		or (type(productConfig) == "table" and tonumber(productConfig.Tier) or nil)
	local expectedProjectedRestoreStreak = restoreSnapshotBefore and restoreSnapshotBefore.ProjectedRestoredStreak or nil
	if expectedProjectedRestoreStreak == nil and type(productConfig) == "table" then
		expectedProjectedRestoreStreak =
			buildExpectedProjectedRestoreStreak(player, expectedPreLossStreak, expectedTier)
	end
	local passed = validation
		and validation.Allowed == expectedAllowed
		and validation.Reason == expectedReason
		and validation.EffectImplemented == false
		and validation.PreLossStreak == expectedPreLossStreak
		and validation.ProjectedRestoredStreak == expectedProjectedRestoreStreak
		and unchanged

	print(string.format(
		"%s restore=%s kind=%s allowed=%s expectedAllowed=%s reason=%s expectedReason=%s effectImplemented=%s preLoss=%s projected=%s",
		COMMAND_PREFIX,
		productKey,
		actualKind,
		tostring(validation and validation.Allowed),
		tostring(expectedAllowed),
		tostring(validation and validation.Reason),
		tostring(expectedReason),
		tostring(validation and validation.EffectImplemented),
		tostring(validation and validation.PreLossStreak),
		tostring(validation and validation.ProjectedRestoredStreak)
	))
	print(string.format(
		"%s restore before{%s} after{%s}",
		COMMAND_PREFIX,
		formatSnapshot(beforeSnapshot),
		formatSnapshot(afterSnapshot)
	))

	if passed then
		print(string.format("%s PASS restore=%s", COMMAND_PREFIX, productKey))
		return
	end

	warn(string.format(
		"%s FAIL restore=%s allowed=%s expectedAllowed=%s reason=%s expectedReason=%s effectImplemented=%s preLoss=%s expectedPreLoss=%s projected=%s expectedProjected=%s mismatches=%s",
		COMMAND_PREFIX,
		productKey,
		tostring(validation and validation.Allowed),
		tostring(expectedAllowed),
		tostring(validation and validation.Reason),
		tostring(expectedReason),
		tostring(validation and validation.EffectImplemented),
		tostring(validation and validation.PreLossStreak),
		tostring(expectedPreLossStreak),
		tostring(validation and validation.ProjectedRestoredStreak),
		tostring(expectedProjectedRestoreStreak),
		#mismatches > 0 and table.concat(mismatches, " | ") or "none"
	))
end

local function handleTestRound(messagePlayer, scenarioName)
	local scenario = scenarioRegistry[scenarioName]
	if not scenario then
		warn(string.format("%s Usage: /testround %s", COMMAND_PREFIX, getScenarioUsage()))
		return
	end

	local context = {
		scenarioName = scenarioName,
		caller = messagePlayer,
		syntheticRival = makeSyntheticRival(),
		rewardCash = ROUND_REWARD_CASH,
		cleanupTasks = {},
	}

	local ok, err = pcall(function()
		if scenario.setup then
			scenario.setup(context)
		end

		context.beforeCaller = getStatsSnapshot(context.caller)
		context.beforeSynthetic = getStatsSnapshot(context.syntheticRival)
		if not context.beforeCaller or not context.beforeSynthetic then
			error("snapshot setup failed")
		end
		context.preRoundStatsByUserId = {
			[context.beforeCaller.UserId] = context.beforeCaller,
			[context.beforeSynthetic.UserId] = context.beforeSynthetic,
		}

		context.resultPayload = scenario.buildResultPayload(context)
		StatsService.ApplyRoundResult(context.caller, context.syntheticRival, context.resultPayload)
		MonetizationService.HandlePostRoundOutcome(
			buildMonetizationOutcomeContext(context.resultPayload, { context.caller, context.syntheticRival }, context.preRoundStatsByUserId)
		)

		context.afterCaller = getStatsSnapshot(context.caller)
		context.afterSynthetic = getStatsSnapshot(context.syntheticRival)
		if not context.afterCaller or not context.afterSynthetic then
			error("after snapshot unavailable")
		end

		local expectedAfter = scenario.buildExpectedAfter(context)
		context.expectedAfterCaller = expectedAfter.caller
		context.expectedAfterSynthetic = expectedAfter.synthetic
		context.validationMismatches = scenario.validate and scenario.validate(context) or {}

		reportScenarioResult(context)
	end)

	runCleanupTasks(context)

	if not ok then
		warn(string.format("%s scenario=%s error=%s", COMMAND_PREFIX, scenarioName, tostring(err)))
	end
end

local exactCommandHandlers = {
	["/dumpstats"] = function(player)
		handleDumpStats(player, false)
	end,
	["/dumpstats all"] = function(player)
		handleDumpStats(player, true)
	end,
	["/dumpmonetization"] = handleDumpMonetization,
	["/setvip"] = function()
		warn(string.format("%s Usage: /setvip on | /setvip off", COMMAND_PREFIX))
	end,
	["/testreceipt"] = function()
		warn(string.format("%s Usage: /testreceipt <productKey>", COMMAND_PREFIX))
	end,
	["/testrestore"] = function()
		warn(string.format("%s Usage: /testrestore <productKey>", COMMAND_PREFIX))
	end,
	["/testround"] = function()
		warn(string.format("%s Usage: /testround %s", COMMAND_PREFIX, getScenarioUsage()))
	end,
}

local patternCommandHandlers = {
	{
		pattern = "^/setvip%s+([%w_]+)$",
		handler = handleSetVip,
	},
	{
		pattern = "^/testreceipt%s+([%w_]+)$",
		handler = handleTestReceipt,
	},
	{
		pattern = "^/testrestore%s+([%w_]+)$",
		handler = handleTestRestore,
	},
	{
		pattern = "^/testround%s+([%w_]+)$",
		handler = handleTestRound,
	},
}

local function dispatchCommand(player, trimmed)
	local exactHandler = exactCommandHandlers[trimmed]
	if exactHandler then
		exactHandler(player)
		return true
	end

	for _, command in ipairs(patternCommandHandlers) do
		local captures = { string.match(trimmed, command.pattern) }
		if captures[1] ~= nil then
			command.handler(player, table.unpack(captures))
			return true
		end
	end

	return false
end

local function attachChatHooks(player)
	if not canUseHarnessCommands(player) then
		return
	end

	if trackedPlayers[player.UserId] then
		return
	end

	trackedPlayers[player.UserId] = true

	player.Chatted:Connect(function(message)
		local trimmed = trimMessage(message)
		dispatchCommand(player, trimmed)
	end)
end

function DevTestService.Init()
	if initialized then
		return
	end

	if not RunService:IsStudio() then
		return
	end

	initialized = true

	Players.PlayerAdded:Connect(attachChatHooks)
	Players.PlayerRemoving:Connect(function(player)
		if player then
			trackedPlayers[player.UserId] = nil
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		attachChatHooks(player)
	end
end

return DevTestService
