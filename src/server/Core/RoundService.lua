local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Core = script.Parent
local FXService = require(Core.FXService)
local ModifierService = require(Core.ModifierService)
local PluginRunner = require(Core.PluginRunner)
local StatsService = require(Core.StatsService)
local TableService = require(Core.TableService) -- BUG FIX A: Seat reset integration

local RoundService = {}

-- State
local activeSessions = {} -- [tableModel] = { startTime = number, players = {Player}, state = "SPINNING"|"STAGE1"|"STAGE2"|"RESOLVING"|"ENDED", spinStopFlag = boolean?, abortFlag = boolean? }
local playerLeaveConnections = {} -- [Player] = connection
local activeCountdowns = {} -- [tableModel] = { token = string, players = {Player} }

-- Task: Cinematic ACKs State (Renamed to StartedAck)
local startedAcks = {} -- [cineToken] = count
local stoppedAcks = {} -- [cineToken] = count

-- Constants
local ROUND_DURATION = 5
local COUNTDOWN_DURATION = 3 -- Seconds before match starts

-- Private Functions

-- Helper: Format round result summary for logging
local function formatResultSummary(resultPayload, participants, winnersArray, losersArray)
	local summary = {
		outcome = "UNKNOWN",
		winnerNames = {},
		loserNames = {},
		rewardCash = resultPayload.rewardCash or 0
	}
	
	if resultPayload.isNeutral then
		summary.outcome = "NEUTRAL_TIMEOUT"
	elseif resultPayload.wasAborted then
		summary.outcome = "ABORTED"
	elseif resultPayload.didBothLose then
		summary.outcome = "BOTH_LOSE"
		for _, p in ipairs(participants) do
			table.insert(summary.loserNames, p.Name)
		end
	elseif resultPayload.didDraw then
		summary.outcome = "DRAW_SPLIT"
		for _, p in ipairs(participants) do
			table.insert(summary.winnerNames, p.Name)
		end
	else
		-- Single winner/loser
		summary.outcome = "SINGLE_WINNER"
		for _, w in ipairs(winnersArray) do
			table.insert(summary.winnerNames, w.Name)
		end
		for _, l in ipairs(losersArray) do
			table.insert(summary.loserNames, l.Name)
		end
	end
	
	return summary
end

local function playersToUniqueUserIds(playersArray)
	local userIds = {}
	local seen = {}

	for _, player in ipairs(playersArray or {}) do
		local userId = player and player.UserId
		if userId and not seen[userId] then
			seen[userId] = true
			table.insert(userIds, userId)
		end
	end

	return userIds
end

local function freezePlayer(player, shouldFreeze)
	if not (player and player.Character) then return end
	local hum = player.Character:FindFirstChild("Humanoid")
	if not hum then return end
	
	if shouldFreeze then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0 -- Prevent jumping if UseJumpPower is false
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	else
		hum.WalkSpeed = 16
		hum.JumpPower = 50
		hum.JumpHeight = 7.2 -- Standard height
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end

local function teleportToSpawn(player)
	if not (player and player.Character) then return end
	
	local spawnLocation = Workspace:FindFirstChild("SpawnLocation", true)
	local targetCFrame = spawnLocation and spawnLocation.CFrame or CFrame.new(0, 10, 0)
	
	-- Add random offset to prevent stacking
	local offset = Vector3.new(math.random(-5, 5), 3, math.random(-5, 5))
	
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = targetCFrame + offset
	end
end

local function resetPlayerState(player)
	if not (player and player.Character) then return end
	
	-- Unfreeze
	freezePlayer(player, false)
	
	-- Force stand
	local hum = player.Character:FindFirstChild("Humanoid")
	if hum then
		hum.Sit = false
	end
end

local function safeTeleport(player)
	if not (player and player.Character) then return end
	
	-- 1) Force unsit and update state
	local hum = player.Character:FindFirstChild("Humanoid")
	if hum then
		hum.Sit = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	
	-- 2) Unfreeze
	freezePlayer(player, false)
	
	-- 3) Wait a frame to break the weld, then teleport
	task.delay(0.1, function()
		teleportToSpawn(player)
	end)
end

local function ejectWinner(player)
	if not (player and player.Character) then return end
	
	-- Unfreeze
	freezePlayer(player, false)
	
	-- Force stand
	local hum = player.Character:FindFirstChild("Humanoid")
	if hum then
		hum.Sit = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- Helper: Validate players are still seated and ready (uses TableService for table-aware seat check)
local function validatePlayersSeated(tableModel, players)
	if not (tableModel and tableModel.Parent) then
		return false, "Table invalid"
	end
	
	for _, player in ipairs(players) do
		if not (player and player.Parent) then
			return false, player and (player.Name .. " disconnected") or "Player invalid"
		end
		
		local ok, reason = TableService.IsPlayerStillSeatedAtTable(tableModel, player)
		if not ok then
			return false, (player.Name .. " " .. (reason or "unseated"))
		end
	end
	
	return true, "Valid"
end

-- Public API: Start countdown before match (called by TableService.OnTableReady)
function RoundService.HandleTableReady(tableModel, players)
	-- Check if already counting down or in session
	if activeCountdowns[tableModel] or activeSessions[tableModel] then
		return
	end
	
	if #players < 2 then
		return
	end
	
	-- Generate unique countdown token
	local countdownToken = tableModel.Name .. "_" .. tostring(os.clock())
	activeCountdowns[tableModel] = {
		token = countdownToken,
		players = players
	}
	
	print(string.format("[RoundService] Countdown start: %s (%s vs %s) t=%d", 
		tableModel.Name, players[1].Name, players[2].Name, COUNTDOWN_DURATION))
	
	-- Fire countdown start to clients
	local Remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	if Remotes then
		local MatchCountdown = Remotes:FindFirstChild("MatchCountdown")
		if MatchCountdown then
			for _, p in ipairs(players) do
				if p and p.Parent then
					-- Guard: ensure opponent exists and get name safely
					local opponent = (p == players[1]) and players[2] or players[1]
					local opponentName = (opponent and opponent.Parent and opponent.Name) or "Opponent"
					MatchCountdown:FireClient(p, tableModel.Name, COUNTDOWN_DURATION, opponentName)
				end
			end
		end
	end
	
	-- Countdown loop (non-blocking per table)
	task.spawn(function()
		for i = COUNTDOWN_DURATION, 1, -1 do
			task.wait(1)
			
			-- Validate countdown still valid
			local countdown = activeCountdowns[tableModel]
			if not countdown or countdown.token ~= countdownToken then
				print(string.format("[RoundService] Countdown cancelled: %s (superseded)", tableModel.Name))
				return
			end
			
			-- Validate players still seated
			local valid, reason = validatePlayersSeated(tableModel, players)
			if not valid then
				print(string.format("[RoundService] Countdown cancelled: %s (%s)", tableModel.Name, reason))
				activeCountdowns[tableModel] = nil
				
				-- Notify clients countdown cancelled
				if Remotes then
					local MatchCountdownCancel = Remotes:FindFirstChild("MatchCountdownCancel")
					if MatchCountdownCancel then
						for _, p in ipairs(players) do
							if p and p.Parent then
								MatchCountdownCancel:FireClient(p, reason)
							end
						end
					end
				end
				return
			end
			
			-- Update countdown (optional tick notification)
			if i > 1 then
				if Remotes then
					local MatchCountdown = Remotes:FindFirstChild("MatchCountdown")
					if MatchCountdown then
						for _, p in ipairs(players) do
							if p and p.Parent then
								-- Guard: ensure opponent exists and get name safely
								local opponent = (p == players[1]) and players[2] or players[1]
								local opponentName = (opponent and opponent.Parent and opponent.Name) or "Opponent"
								MatchCountdown:FireClient(p, tableModel.Name, i - 1, opponentName)
							end
						end
					end
				end
			end
		end
		
		-- Final validation before starting
		local valid, reason = validatePlayersSeated(tableModel, players)
		if not valid then
			print(string.format("[RoundService] Countdown cancelled: %s (%s)", tableModel.Name, reason))
			activeCountdowns[tableModel] = nil
			if Remotes then
				local MatchCountdownCancel = Remotes:FindFirstChild("MatchCountdownCancel")
				if MatchCountdownCancel then
					for _, p in ipairs(players) do
						if p and p.Parent then
							MatchCountdownCancel:FireClient(p, reason)
						end
					end
				end
			end
			return
		end
		
		-- Countdown complete -> start round
		print(string.format("[RoundService] Countdown complete -> starting round: %s at %0.6f", tableModel.Name, os.clock()))
		activeCountdowns[tableModel] = nil
		
		-- Step A: Fire MatchStartingNow to both players
		local UIService = require(Core.UIService)
		for _, p in ipairs(players) do
			if p and p.Parent then
				UIService.MatchStartingNow(p)
			end
		end
		
		-- Step D: Wait only 0.05s tiny buffer
		task.wait(0.05)
		
		-- Final gate: Re-validate after wait (catches last-second jump)
		local valid, reason = validatePlayersSeated(tableModel, players)
		if not valid then
			print(string.format("[RoundService] Start aborted: %s (%s)", tableModel.Name, reason))
			activeCountdowns[tableModel] = nil -- Explicit cleanup (already nil from line 276; belt-and-suspenders for deterministic cleanup)
			if Remotes then
				local MatchCountdownCancel = Remotes:FindFirstChild("MatchCountdownCancel")
				if MatchCountdownCancel then
					for _, p in ipairs(players) do
						if p and p.Parent then
							MatchCountdownCancel:FireClient(p, reason)
						end
					end
				end
			end
			return
		end
		
		RoundService.StartRound(tableModel, players)
	end)
end

-- Public API: Start round (called after countdown or directly if needed)
function RoundService.StartRound(tableModel, players)
	if activeSessions[tableModel] then
		warn("[RoundService] Round already active for " .. tableModel.Name)
		return
	end
	
	if #players < 2 then
		warn("[RoundService] Not enough players to start round.")
		return
	end

	TableService.CloseShieldArmingWindow(tableModel)
	
	print(string.format("[RoundService] Starting Round for %s with %s vs %s at %0.6f", 
		tableModel.Name, players[1].Name, players[2].Name, os.clock()))
		
	-- Problem 2: Create unique cineToken
	local cineToken = tableModel.Name .. "_CINE_" .. tostring(os.clock())
	
	activeSessions[tableModel] = {
		startTime = os.time(),
		players = players,
		state = "SPINNING",
		spinStopFlag = false,
		abortFlag = false,
		spinCleanup = nil,
		leaveHandled = false,
		ending = false,
		cineToken = cineToken
	}
	
	-- Fire MatchStart event to clients (for prompt disabling)
	local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	local MatchStartEvent = Remotes:FindFirstChild("MatchStart", 5)
	if MatchStartEvent then
		for _, p in ipairs(players) do
			MatchStartEvent:FireClient(p)
		end
	end
	
	-- Track player leaves
	local function onPlayerRemoving(leavingPlayer)
		local session = activeSessions[tableModel]
		if session and session.players then
			for _, p in ipairs(session.players) do
				if p == leavingPlayer then
					-- Player left mid-match
					HandleOpponentLeave(tableModel, leavingPlayer.UserId, session.state)
					break
				end
			end
		end
	end
	
	for _, p in ipairs(players) do
		local conn = Players.PlayerRemoving:Connect(onPlayerRemoving)
		playerLeaveConnections[p] = conn
	end
	
	-- 1. Freeze
	for _, p in ipairs(players) do
		freezePlayer(p, true)
	end
	
	-- 2. Run Game Plugin (DoubleDown)
	task.spawn(function()
		-- Helper: disconnect player-leave listeners on any early exit (prevents connection leak)
		local function disconnectLeaveListeners()
			for _, p in ipairs(players) do
				if playerLeaveConnections[p] then
					playerLeaveConnections[p]:Disconnect()
					playerLeaveConnections[p] = nil
				end
			end
		end
		
		-- Validate required objects
		if not tableModel or not tableModel.Parent then
			warn("[RoundService] tableModel invalid, aborting")
			for _, p in ipairs(players) do
				resetPlayerState(p)
			end
			disconnectLeaveListeners()
			activeSessions[tableModel] = nil
			return
		end
		
		if not players or #players < 2 then
			warn("[RoundService] Invalid players list, aborting")
			for _, p in ipairs(players or {}) do
				resetPlayerState(p)
			end
			disconnectLeaveListeners()
			activeSessions[tableModel] = nil
			return
		end
		
		local session = activeSessions[tableModel]
		if not session then
			disconnectLeaveListeners()
			return
		end
		
		-- Run Plugin
		local result
		local ok, err = pcall(function()
			result = PluginRunner.Run("DoubleDown", { 
				players = players, 
				tableModel = tableModel,
				session = session
			})
		end)
		
		if not ok then
			warn("[RoundService] Plugin execution error: " .. tostring(err))
			-- Cleanup on error
			for _, p in ipairs(players) do
				resetPlayerState(p)
			end
			disconnectLeaveListeners()
			activeSessions[tableModel] = nil
			return
		end
		
		if not result or not result.ok then
			warn("[RoundService] Plugin failed: " .. tostring(result and result.meta and result.meta.error or "unknown"))
			-- Cleanup on error
			if session and session.spinCleanup then
				pcall(session.spinCleanup)
				session.spinCleanup = nil
			end
			for _, p in ipairs(players) do
				resetPlayerState(p)
			end
			disconnectLeaveListeners()
			activeSessions[tableModel] = nil
			return
		end
		
		-- 3. Handle Result
		if session and session.abortFlag then
			if session.spinCleanup then
				pcall(session.spinCleanup)
				session.spinCleanup = nil
			end
			disconnectLeaveListeners()
			return
		end
		
		if not result.data then
			warn("[RoundService] Plugin result missing data, aborting")
			for _, p in ipairs(players) do
				resetPlayerState(p)
			end
			disconnectLeaveListeners()
			activeSessions[tableModel] = nil
			return
		end
		
		local data = result.data
		
		-- Problem 5: Neutral round behavior
		local isNeutral = (data.neutral == true) or (data.outcome == "NEUTRAL_TIMEOUT")
		
		-- HARDENED ENDING GUARD
		if session.ending then
			disconnectLeaveListeners()
			return
		end
		session.ending = true
		
		-- Parse winners
		local winners = data.winners or {}
		local participants = players
		
		local winnerSet = {}
		for _, w in ipairs(winners) do winnerSet[w] = true end
		
		local losers = {}
		if not isNeutral then
			for _, p in ipairs(participants) do
				if not winnerSet[p] then table.insert(losers, p) end
			end
		end

		local roundContext = {
			participants = participants,
			winners = winners,
			losers = losers,
			streakProtectedLosers = {},
			shieldConsumePlayers = {},
			shieldDisarmPlayers = {},
			isNeutral = isNeutral,
			outcome = data.outcome,
			rewardCash = data.reward or 0,
		}
		ModifierService.ApplyRoundModifiers(roundContext)
		
		local soundPlayed = "None"
		
		-- Close UI
		local UIService = require(Core.UIService)
		if UIService and UIService.CloseStageUI then
			for _, p in ipairs(players) do
				if p and p.Parent then
					UIService.CloseStageUI(p)
				end
			end
		end
		
		-- Release Cinematic Camera
		-- Set ACK counter BEFORE firing so client ACKs are never dropped (race fix)
		stoppedAcks[cineToken] = 0
		local StopSpinCinematic = Remotes:WaitForChild("StopSpinCinematic")
		for _, p in ipairs(players) do
			StopSpinCinematic:FireClient(p)
		end
		
		-- Problem 2: Wait for CinematicStoppedAck
		local stopWait = os.clock()
		while stoppedAcks[cineToken] < #players and (os.clock() - stopWait) < 0.75 do
			task.wait(0.05)
		end
		
		-- Problem 3: ForceUnlockTable (Deterministic cleanup)
		TableService.ForceUnlockTable(tableModel, "match_end_resolve")
		
		-- Handle Neutral Notification
		if isNeutral then
			local OpponentLeftToast = Remotes:FindFirstChild("OpponentLeftToast")
			if OpponentLeftToast then
				for _, p in ipairs(participants) do
					OpponentLeftToast:FireClient(p, "All users timed out, no stats were changed", 2)
				end
			end
		end
		
		-- Sounds
		if isNeutral then
			soundPlayed = "None (Neutral Timeout)"
		elseif #winners > 0 then
			soundPlayed = "WinSound (Winners Only)"
			for _, w in ipairs(winners) do
				FXService.PlayWin(w)
				FXService.PlayConfetti(w)
			end
		else
			soundPlayed = "LoseSound (Everyone)"
			for _, p in ipairs(participants) do
				FXService.PlayLose(p)
			end
		end
		
		-- Respawn Logic
		local respawned = {}
		local ejected = {}
		
		if isNeutral then
			for _, p in ipairs(participants) do
				safeTeleport(p)
				table.insert(respawned, p.Name)
			end
		elseif #winners == #participants then
			for _, p in ipairs(participants) do
				safeTeleport(p)
				table.insert(respawned, p.Name)
			end
		elseif #winners == 0 then
			for _, p in ipairs(participants) do
				safeTeleport(p)
				table.insert(respawned, p.Name)
			end
		else
			for _, w in ipairs(winners) do
				ejectWinner(w)
				table.insert(ejected, w.Name)
			end
			for _, l in ipairs(losers) do
				safeTeleport(l)
				table.insert(respawned, l.Name)
			end
		end
		
		-- Apply Stats (Step 6)
		local roundId = tableModel.Name .. "_" .. tostring(os.clock())
		local playerA = players[1]
		local playerB = players[2]
		
		local resultPayload = {
			roundId = roundId,
			rewardCash = data.reward or 0,
			wasAborted = false,
			isNeutral = isNeutral,
			streakProtectedLoserUserIds = {},
			shieldConsumeUserIds = {},
			shieldDisarmUserIds = {},
		}
		
		if not isNeutral then
			if #winners == 0 then
				resultPayload.didBothLose = true
			elseif #losers == 0 then
				resultPayload.didDraw = true
				resultPayload.winnerUserId = nil
				resultPayload.loserUserId = nil
			else
				if #winners == 1 then
					resultPayload.winnerUserId = winners[1].UserId
					resultPayload.loserUserId = losers[1] and losers[1].UserId or nil
				end
			end

			resultPayload.streakProtectedLoserUserIds = playersToUniqueUserIds(roundContext.streakProtectedLosers)
			resultPayload.shieldConsumeUserIds = playersToUniqueUserIds(roundContext.shieldConsumePlayers)
			resultPayload.shieldDisarmUserIds = playersToUniqueUserIds(roundContext.shieldDisarmPlayers)
			
			-- Apply stats
			StatsService.ApplyRoundResult(playerA, playerB, resultPayload)
		end
		
		-- Log
		local resultSummary = formatResultSummary(resultPayload, participants, winners, losers)
		print(string.format("[RoundService] ROUND RESULT: outcome=%s | winners=[%s] | losers=[%s] | reward=$%d", 
			resultSummary.outcome,
			table.concat(resultSummary.winnerNames, ","),
			table.concat(resultSummary.loserNames, ","),
			resultSummary.rewardCash))
		
		-- Notify Update
		if not isNeutral then
			for _, p in ipairs(players) do
				if p and p.Parent then
					local stats = StatsService.GetStats(p)
					if stats then
						local cashDelta = 0
						if resultPayload.didDraw then
							-- Draw always splits the POT
							cashDelta = math.floor((resultPayload.rewardCash or 0) / 2)
						elseif resultPayload.winnerUserId == p.UserId then
							-- Single winner gets full POT
							cashDelta = resultPayload.rewardCash or 0
						end

						UIService.FireStatsUpdate(p, stats, {
							kind = "round_result",
							cashDelta = cashDelta
						})
					end
				end
			end
		end
		
		-- Disconnect
		for _, p in ipairs(players) do
			if playerLeaveConnections[p] then
				playerLeaveConnections[p]:Disconnect()
				playerLeaveConnections[p] = nil
			end
		end
		
		if session and session.spinCleanup then
			pcall(session.spinCleanup)
			session.spinCleanup = nil
		end
		
		-- Fire MatchEnd
		local MatchEndEvent = Remotes:FindFirstChild("MatchEnd", 5)
		if MatchEndEvent then
			for _, p in ipairs(players) do
				if p and p.Parent then
					MatchEndEvent:FireClient(p)
				end
			end
		end
		
		-- Problem 2: Cleanup ACK state
		if cineToken then
			startedAcks[cineToken] = nil
			stoppedAcks[cineToken] = nil
		end
		
		activeSessions[tableModel] = nil
		print(string.format("[RoundService] Cleanup complete: %s", tableModel.Name))
	end)
end

-- Task: Wait for CinematicStartedAck (Called by SpinService or DoubleDown)
function RoundService.WaitForCinematicStarted(cineToken, playerCount)
	if not cineToken then return end
	
	startedAcks[cineToken] = 0
	local startWait = os.clock()
	-- Step D: Wait up to 0.25s
	while startedAcks[cineToken] < playerCount and (os.clock() - startWait) < 0.25 do
		task.wait(0.05)
	end
end

-- Handle opponent leave based on match state
function HandleOpponentLeave(tableModel, leaverUserId, currentState)
	local session = activeSessions[tableModel]
	if not session then return end
	
	if session.leaveHandled or session.ending then
		return
	end
	session.leaveHandled = true
	session.ending = true
	
	session.abortFlag = true
	session.state = "ENDED"
	
	local remainingPlayers = {}
	for _, p in ipairs(session.players) do
		if p.UserId ~= leaverUserId and p.Parent then
			table.insert(remainingPlayers, p)
		end
	end
	
	if #remainingPlayers == 0 then
		AbortRound(tableModel, "All players left")
		return
	end
	
	local Remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	
	local OpponentLeftToast = Remotes:FindFirstChild("OpponentLeftToast")
	if OpponentLeftToast then
		for _, p in ipairs(remainingPlayers) do
			OpponentLeftToast:FireClient(p, "Opponent left! Ending match...", 2)
		end
	end
	
	local StopSpinCinematic = Remotes:FindFirstChild("StopSpinCinematic")
	if StopSpinCinematic then
		for _, p in ipairs(remainingPlayers) do
			StopSpinCinematic:FireClient(p, true)
		end
	end
	
	-- Problem 3: ForceUnlockTable
	TableService.ForceUnlockTable(tableModel, "opponent_leave")
	
	task.spawn(function()
		AbortRound(tableModel, "Opponent left during " .. (currentState or "unknown"))
	end)
end

-- Abort round cleanly
function AbortRound(tableModel, reason)
	local session = activeSessions[tableModel]
	if not session then return end
	
	if not session.ending then
		session.ending = true
	end
	
	print("[RoundService] Aborting round:", reason)
	
	session.abortFlag = true
	session.state = "ENDED"
	
	if session.players and #session.players >= 2 then
		local roundId = tableModel.Name .. "_abort_" .. tostring(os.clock())
		local resultPayload = {
			roundId = roundId,
			wasAborted = true,
			rewardCash = 0,
			reason = reason
		}
		StatsService.ApplyRoundResult(session.players[1], session.players[2], resultPayload)
	end
	
	if session.spinCleanup then
		pcall(session.spinCleanup)
		session.spinCleanup = nil
	end
	
	local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	local StopSpinCinematic = Remotes:FindFirstChild("StopSpinCinematic", 5)
	if StopSpinCinematic then
		for _, p in ipairs(session.players) do
			if p and p.Parent then
				StopSpinCinematic:FireClient(p, true)
			end
		end
	end
	
	-- Problem 3: ForceUnlockTable
	TableService.ForceUnlockTable(tableModel, "abort_round")
	
	for _, p in ipairs(session.players) do
		if p and p.Parent then
			if playerLeaveConnections[p] then
				playerLeaveConnections[p]:Disconnect()
				playerLeaveConnections[p] = nil
			end
		end
	end
	
	local MatchEndEvent = Remotes:FindFirstChild("MatchEnd", 5)
	if MatchEndEvent then
		for _, p in ipairs(session.players) do
			if p and p.Parent then
				MatchEndEvent:FireClient(p)
			end
		end
	end
	
	local UIService = require(Core.UIService)
	if UIService and UIService.CloseStageUI then
		for _, p in ipairs(session.players) do
			if p and p.Parent then
				UIService.CloseStageUI(p)
			end
		end
	end
	
	task.spawn(function()
		for _, p in ipairs(session.players) do
			if p and p.Parent then
				safeTeleport(p)
			end
		end
	end)
	
	-- Problem 2: Cleanup ACK state
	if session.cineToken then
		startedAcks[session.cineToken] = nil
		stoppedAcks[session.cineToken] = nil
	end
	
	activeSessions[tableModel] = nil
	print(string.format("[RoundService] Abort cleanup complete: %s", tableModel.Name))
end

-- Problem 2: Init ACK Listeners
local function initAckListeners()
	local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	
	-- Task: Renamed to CinematicStartedAck
	local CinematicStartedAck = Remotes:WaitForChild("CinematicStartedAck")
	CinematicStartedAck.OnServerEvent:Connect(function(player, tableKey, token)
		if startedAcks[token] then
			startedAcks[token] += 1
		end
	end)
	
	local CinematicStoppedAck = Remotes:WaitForChild("CinematicStoppedAck")
	CinematicStoppedAck.OnServerEvent:Connect(function(player)
		-- Find session for this player to get token
		for _, session in pairs(activeSessions) do
			local isParticipant = false
			for _, p in ipairs(session.players) do
				if p == player then isParticipant = true break end
			end
			if isParticipant and session.cineToken then
				local token = session.cineToken
				if stoppedAcks[token] then
					stoppedAcks[token] += 1
				end
				break
			end
		end
	end)
end

-- Init
task.spawn(initAckListeners)

return RoundService
