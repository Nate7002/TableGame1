local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Core = script.Parent
local FXService = require(Core.FXService)
local PluginRunner = require(Core.PluginRunner)
local StatsService = require(Core.StatsService)

local RoundService = {}

-- State
local activeSessions = {} -- [tableModel] = { startTime = number, players = {Player}, state = "SPINNING"|"STAGE1"|"STAGE2"|"RESOLVING"|"ENDED", spinStopFlag = boolean?, abortFlag = boolean? }
local playerLeaveConnections = {} -- [Player] = connection

-- Constants
local ROUND_DURATION = 5

-- Private Functions
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
	
	local spawnLocation = Workspace:FindFirstChild("SpawnLocation")
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

local function finishRound(tableModel, winner, loser, isTie)
	local session = activeSessions[tableModel]
	if not session then return end
	
	-- Note: 'winner' and 'loser' args are deprecated in favor of parsing result data dynamically,
	-- but the architecture keeps the signature.
	-- We will look at the session.latestResult if stored, or just rely on arguments.
	-- Actually, RoundService handles the plugin result inline in StartRound. 
	-- This function 'finishRound' was used by the OLD hardcoded logic.
	-- The NEW DoubleDown logic handles its own finish.
	-- However, the user says "RoundService end-of-round logic is wrong".
	-- Ah, I see: In StartRound (lines 145+), I have the logic that needs updating.
end

-- Public API
function RoundService.StartRound(tableModel, players)
	if activeSessions[tableModel] then
		warn("[RoundService] Round already active for " .. tableModel.Name)
		return
	end
	
	if #players < 2 then
		warn("[RoundService] Not enough players to start round.")
		return
	end
	
	print(string.format("[RoundService] Starting Round for %s with %s vs %s", 
		tableModel.Name, players[1].Name, players[2].Name))
		
	activeSessions[tableModel] = {
		startTime = os.time(),
		players = players,
		state = "SPINNING",
		spinStopFlag = false,
		abortFlag = false,
		spinCleanup = nil, -- Store cleanup function from SpinService
		leaveHandled = false, -- Prevent duplicate leave handling
		ending = false -- HARDENED: Prevent double-end paths
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
					print("[RoundService] Player", leavingPlayer.Name, "left mid-match, state:", session.state)
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
			print("[RoundService] Starting DoubleDown plugin at", os.clock())
			
			-- Validate required objects
			if not tableModel or not tableModel.Parent then
				warn("[RoundService] tableModel invalid, aborting")
				for _, p in ipairs(players) do
					resetPlayerState(p)
				end
				activeSessions[tableModel] = nil
				return
			end
			
			if not players or #players < 2 then
				warn("[RoundService] Invalid players list, aborting")
				for _, p in ipairs(players or {}) do
					resetPlayerState(p)
				end
				activeSessions[tableModel] = nil
				return
			end
			
			local session = activeSessions[tableModel]
			if not session then return end
			
			-- Store session reference for cleanup access
			local result
			local ok, err = pcall(function()
				result = PluginRunner.Run("DoubleDown", { 
					players = players, 
					tableModel = tableModel,
					session = session -- Pass session for abort checking and cleanup storage
				})
			end)
			
			if not ok then
				warn("[RoundService] Plugin execution error: " .. tostring(err))
				-- Cleanup on error
				for _, p in ipairs(players) do
					resetPlayerState(p)
				end
				activeSessions[tableModel] = nil
				return
			end
			
			if not result or not result.ok then
				warn("[RoundService] Plugin failed: " .. tostring(result and result.meta and result.meta.error or "unknown"))
				-- Check if it was an abort
				if result and result.meta and result.meta.error == "Match aborted" then
					print("[RoundService] Match aborted by plugin")
					-- Ensure cleanup still runs even on abort
					if session and session.spinCleanup then
						pcall(session.spinCleanup)
						session.spinCleanup = nil
					end
					return
				end
				-- Cleanup on error
				if session and session.spinCleanup then
					pcall(session.spinCleanup)
					session.spinCleanup = nil
				end
				for _, p in ipairs(players) do
					resetPlayerState(p)
				end
				activeSessions[tableModel] = nil
				return
			end
			
			-- 3. Handle Result
			-- Check if match was aborted
			if session and session.abortFlag then
				print("[RoundService] Match was aborted, skipping result handling")
				-- Ensure cleanup still runs even on abort
				if session.spinCleanup then
					pcall(session.spinCleanup)
					session.spinCleanup = nil
				end
				return
			end
			
			if not result.data then
				warn("[RoundService] Plugin result missing data, aborting")
				for _, p in ipairs(players) do
					resetPlayerState(p)
				end
				activeSessions[tableModel] = nil
				return
			end
			
			local data = result.data
			print(string.format("[RoundService] DoubleDown Result: Outcome=%s, Reward=%d", data.outcome or "nil", data.reward or 0))
			print("[RoundService] Outcome computed at", os.clock())
			
			-- HARDENED ENDING GUARD
			if session.ending then
				print("[RoundService] Skipping normal finish (session ending via other path)")
				return
			end
			session.ending = true
			
			-- Logic:
			-- Parse winners
			local winners = data.winners or {}
			local participants = players
			
			local winnerSet = {}
			for _, w in ipairs(winners) do winnerSet[w] = true end
			
			local losers = {}
			for _, p in ipairs(participants) do
				if not winnerSet[p] then table.insert(losers, p) end
			end
			
			-- Sounds Logic
			-- If ANY winners -> Winners get WinSound. Losers get Silence.
			-- If NO winners (Both Lose) -> Everyone gets LoseSound.
			
			local soundPlayed = "None"
			
			-- Close UI immediately when outcome is decided (BEFORE sounds)
			print("[RoundService] About to resolve round; players:", #players)
			local UIService = require(Core.UIService)
			if UIService and UIService.CloseStageUI then
				for _, p in ipairs(players) do
					if p and p.Parent then
						print("[RoundService] Closing Stage UI for", p.Name, "at", os.clock())
						UIService.CloseStageUI(p)
					end
				end
			else
				warn("[RoundService] UIService or CloseStageUI missing, skipping UI close")
			end
			
			-- Release Cinematic Camera (Direct Remote Fire)
			local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
			local StopSpinCinematic = Remotes:WaitForChild("StopSpinCinematic")
			for _, p in ipairs(players) do
				print("[CINE] STOP FIRING", p.Name, "at", os.clock())
				StopSpinCinematic:FireClient(p)
			end
			
			print("[RoundService] Sounds firing at", os.clock())
			
			if #winners > 0 then
				soundPlayed = "WinSound (Winners Only)"
				for _, w in ipairs(winners) do
					FXService.PlayWin(w)
					FXService.PlayConfetti(w)
				end
				-- Losers: Silence (do nothing FX-wise)
			else
				-- Everyone lost
				soundPlayed = "LoseSound (Everyone)"
				for _, p in ipairs(participants) do
					FXService.PlayLose(p)
				end
			end
			
			-- Respawn Logic
			-- Winners -> Stay seated (unfreeze only).
			-- Losers -> Respawn.
			-- Exception: If BOTH win (Split), BOTH respawn.
			-- Exception: If BOTH lose, BOTH respawn.
			
			local respawned = {}
			local ejected = {}
			
			if #winners == #participants then
				-- All Won (Split) -> All Respawn
				for _, p in ipairs(participants) do
					safeTeleport(p)
					table.insert(respawned, p.Name)
				end
			elseif #winners == 0 then
				-- All Lost -> All Respawn
				for _, p in ipairs(participants) do
					safeTeleport(p)
					table.insert(respawned, p.Name)
				end
			else
				-- Mixed Result
				for _, w in ipairs(winners) do
					ejectWinner(w)
					table.insert(ejected, w.Name)
				end
				for _, l in ipairs(losers) do
					safeTeleport(l)
					table.insert(respawned, l.Name)
				end
			end
			
			print(string.format("[RoundService] winners={%d} losers={%d} sound=%s respawned={%s} eject={%s}", 
				#winners, #losers, soundPlayed, table.concat(respawned, ","), table.concat(ejected, ",")))
			
			-- Apply Stats/Rewards (Step 6)
			local roundId = tableModel.Name .. "_" .. tostring(os.clock()) -- Unique round identifier
			local playerA = players[1]
			local playerB = players[2]
			
			local resultPayload = {
				roundId = roundId,
				rewardCash = data.reward or 0,
				wasAborted = false
			}
			
			-- Determine outcome type
			if #winners == 0 then
				-- Both lost
				resultPayload.didBothLose = true
			elseif #winners == #participants then
				-- Draw/Split (both win)
				resultPayload.didDraw = true
			else
				-- Single winner
				if #winners == 1 then
					resultPayload.winnerUserId = winners[1].UserId
					-- Find loser
					for _, p in ipairs(participants) do
						if p ~= winners[1] then
							resultPayload.loserUserId = p.UserId
							break
						end
					end
				end
			end
			
			-- Apply stats
			StatsService.ApplyRoundResult(playerA, playerB, resultPayload)
			
			-- Notify clients of updated stats (Step 6 client feedback)
			for _, p in ipairs(players) do
				if p and p.Parent then
					local stats = StatsService.GetStats(p)
					if stats then
						local StatsUpdate = Remotes:FindFirstChild("StatsUpdate")
						if StatsUpdate then
							-- Include reward delta for this specific player
							local cashDelta = 0
							if resultPayload.didDraw then
								cashDelta = math.floor((resultPayload.rewardCash or 0) / 2)
							elseif resultPayload.winnerUserId == p.UserId then
								cashDelta = resultPayload.rewardCash or 0
							end
							StatsUpdate:FireClient(p, stats, cashDelta)
						end
					end
				end
			end
			
			-- Clean up session
			-- Disconnect player leave connections
			for _, p in ipairs(players) do
				if playerLeaveConnections[p] then
					playerLeaveConnections[p]:Disconnect()
					playerLeaveConnections[p] = nil
				end
			end
			
			-- Cleanup spin visuals (item + billboard) if still present
			if session and session.spinCleanup then
				pcall(session.spinCleanup)
				session.spinCleanup = nil
				print("[RoundService] Spin cleanup called in normal resolve")
			end
			
			-- Fire MatchEnd event to clients (for prompt re-enabling)
			local MatchEndEvent = Remotes:FindFirstChild("MatchEnd", 5)
			if MatchEndEvent then
				for _, p in ipairs(players) do
					if p and p.Parent then
						MatchEndEvent:FireClient(p)
					end
				end
			end
			
			activeSessions[tableModel] = nil
			print("[RoundService] Cleanup complete (no crash) at", os.clock())
		end)
end

-- Handle opponent leave based on match state
function HandleOpponentLeave(tableModel, leaverUserId, currentState)
	local session = activeSessions[tableModel]
	if not session then return end
	
	-- HARDENED: Prevent duplicate leave handling OR handling if match already ending
	if session.leaveHandled or session.ending then
		print("[RoundService] Leave already handled or match ending for", tableModel.Name)
		return
	end
	session.leaveHandled = true
	session.ending = true -- Mark as ending here too
	
	-- Set abort flag to stop any running loops
	session.abortFlag = true
	session.state = "ENDED"
	
	local remainingPlayers = {}
	for _, p in ipairs(session.players) do
		if p.UserId ~= leaverUserId and p.Parent then
			table.insert(remainingPlayers, p)
		end
	end
	
	if #remainingPlayers == 0 then
		-- No remaining players, just cleanup
		AbortRound(tableModel, "All players left")
		return
	end
	
	local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	
	-- ALWAYS show toast notification (single reliable codepath)
	local OpponentLeftToast = Remotes:FindFirstChild("OpponentLeftToast")
	if OpponentLeftToast then
		for _, p in ipairs(remainingPlayers) do
			OpponentLeftToast:FireClient(p, "Opponent left! Ending match...", 2)
			print("[RoundService] Toast fired to", p.Name)
		end
	else
		warn("[RoundService] OpponentLeftToast remote not found")
	end
	
	if currentState == "SPINNING" then
		-- Opponent left during spin - stop spin and cinematic immediately
		print("[RoundService] Opponent left during SPINNING")
		
		-- Stop spin immediately
		session.spinStopFlag = true
		
		-- Stop cinematic for remaining player (immediate = true, skip freeze frame)
		local StopSpinCinematic = Remotes:FindFirstChild("StopSpinCinematic")
		if StopSpinCinematic then
			for _, p in ipairs(remainingPlayers) do
				StopSpinCinematic:FireClient(p, true) -- Pass true for immediate stop
			end
		end
	else
		-- Opponent left during Stage UI
		print("[RoundService] Opponent left during", currentState)
		
		-- Stop cinematic if still active
		local StopSpinCinematic = Remotes:FindFirstChild("StopSpinCinematic")
		if StopSpinCinematic then
			for _, p in ipairs(remainingPlayers) do
				StopSpinCinematic:FireClient(p, true)
			end
		end
	end
	
	-- Schedule abort IMMEDIATELY (concurrent cleanup)
	task.spawn(function()
		AbortRound(tableModel, "Opponent left during " .. (currentState or "unknown"))
	end)
end

-- Abort round cleanly (no rewards, no winners/losers)
function AbortRound(tableModel, reason)
	local session = activeSessions[tableModel]
	if not session then return end
	
	-- HARDENED: If already ending (via HandleOpponentLeave) this is fine as it's the chain
	-- But if called directly, we set ending=true
	if not session.ending then
		session.ending = true
	end
	
	print("[RoundService] Aborting round:", reason)
	
	-- Set abort flag
	session.abortFlag = true
	session.state = "ENDED"
	
	-- Step 6: Apply abort to stats (no rewards, no stat changes)
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
	
	-- CRITICAL: Cleanup spin visuals if they exist (item + billboard)
	if session.spinCleanup then
		pcall(session.spinCleanup)
		print("[RoundService] Spin cleanup called in AbortRound")
		session.spinCleanup = nil
	end
	
	-- Stop cinematic for all players (immediate)
	local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
	local StopSpinCinematic = Remotes:FindFirstChild("StopSpinCinematic", 5)
	if StopSpinCinematic then
		for _, p in ipairs(session.players) do
			if p and p.Parent then
				StopSpinCinematic:FireClient(p, true) -- Immediate stop
			end
		end
	end
	
	-- Cleanup round state
	local remainingPlayers = {}
	for _, p in ipairs(session.players) do
		if p and p.Parent then
			table.insert(remainingPlayers, p)
			-- Do NOT call resetPlayerState here (which would eject)
			-- Just disconnect leave handlers
			if playerLeaveConnections[p] then
				playerLeaveConnections[p]:Disconnect()
				playerLeaveConnections[p] = nil
			end
		end
	end
	
	-- Fire MatchEnd event
	local MatchEndEvent = Remotes:FindFirstChild("MatchEnd", 5)
	if MatchEndEvent then
		for _, p in ipairs(remainingPlayers) do
			MatchEndEvent:FireClient(p)
		end
	end
	
	-- Close UI for remaining players
	local UIService = require(Core.UIService)
	if UIService and UIService.CloseStageUI then
		for _, p in ipairs(remainingPlayers) do
			UIService.CloseStageUI(p)
		end
	end
	
	-- Respawn remaining players IMMEDIATELY (this is the ONLY exit - no eject first)
	task.spawn(function()
		for _, p in ipairs(remainingPlayers) do
			if p and p.Parent then
				-- Respawn is the exit - this will remove them from seat
				safeTeleport(p)
				print("[RoundService] Respawned", p.Name, "after abort (immediate)")
			end
		end
	end)
	
	activeSessions[tableModel] = nil
	print("[RoundService] Abort cleanup ran for table", tableModel.Name)
end

return RoundService

