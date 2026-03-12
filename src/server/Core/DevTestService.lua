local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Core = script.Parent
local MonetizationService = require(Core:WaitForChild("MonetizationService"))
local StatsService = require(Core:WaitForChild("StatsService"))

local DevTestService = {}

local COMMAND_PREFIX = "[DevTest]"
local ROUND_REWARD_CASH = 100
local COMPARED_FIELDS = { "Cash", "Wins", "Streak", "MaxStreak", "GamesPlayed" }
local trackedPlayers = {}
local initialized = false
local nextSyntheticUserId = -1
local scenarioRegistry = {}

local function isRealPlayer(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and type(player.UserId) == "number"
		and player.UserId > 0
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

	print(string.format(
		"%s monetization uid=%d vip=%s multiplier=%s override=%s",
		COMMAND_PREFIX,
		snapshot.UserId,
		tostring(snapshot.HasVIP),
		tostring(snapshot.RewardMultiplier),
		formatStudioOverride(snapshot)
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

		context.resultPayload = scenario.buildResultPayload(context)
		StatsService.ApplyRoundResult(context.caller, context.syntheticRival, context.resultPayload)

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
	if not isRealPlayer(player) then
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
