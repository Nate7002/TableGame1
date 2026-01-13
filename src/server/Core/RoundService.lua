local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Core = script.Parent
local FXService = require(Core.FXService)
local PluginRunner = require(Core.PluginRunner)

local RoundService = {}

-- State
local activeSessions = {} -- [tableModel] = { startTime = number, players = {Player} }

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
	else
		hum.WalkSpeed = 16
		hum.JumpPower = 50
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
		players = players
	}
	
	-- 1. Freeze
	for _, p in ipairs(players) do
		freezePlayer(p, true)
	end
	
	-- 2. Run Game Plugin (DoubleDown)
	task.spawn(function()
		local result = PluginRunner.Run("DoubleDown", { 
			players = players, 
			tableModel = tableModel 
		})
		
		if not result.ok then
			warn("[RoundService] Plugin failed: " .. tostring(result.meta.error))
			-- Abort/Reset
			for _, p in ipairs(players) do
				resetPlayerState(p)
			end
			activeSessions[tableModel] = nil
			return
		end
		
		-- 3. Handle Result
		local data = result.data
		print(string.format("[RoundService] DoubleDown Result: Outcome=%s, Reward=%d", data.outcome, data.reward))
		
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
		
		-- Clean up session
		activeSessions[tableModel] = nil
	end)
end

return RoundService

