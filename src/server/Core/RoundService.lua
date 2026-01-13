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

local function finishRound(tableModel, winner, loser, isTie)
	local session = activeSessions[tableModel]
	if not session then return end
	
	print(string.format("[RoundService] Round Ended for %s", tableModel.Name))
	
	if isTie then
		print(" > Result: TIE")
		for _, p in ipairs(session.players) do
			FXService.PlayLose(p)
			safeTeleport(p)
		end
	else
		print(string.format(" > Result: Winner=%s, Loser=%s", winner.Name, loser.Name))
		
		-- Winner FX
		FXService.PlayWin(winner)
		FXService.PlayConfetti(winner)
		resetPlayerState(winner) 
		-- Winner stays at table (standing)
		
		-- Loser FX & TP
		safeTeleport(loser)
	end
	
	-- Clean up session
	activeSessions[tableModel] = nil
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
		
		-- For MVP: "ends the round by resetting both players to spawn"
		-- In a real split, maybe we play a Win sound? 
		-- For now, just safe teleport everyone as requested.
		
		for _, p in ipairs(players) do
			-- Optional: Play Win sound if they are in the 'winners' list?
			-- The prompt implies just reset. I'll add a Win sound for good measure if they won.
			local isWinner = false
			if data.winners then
				for _, w in ipairs(data.winners) do
					if w == p then isWinner = true break end
				end
			end
			
			if isWinner then
				FXService.PlayWin(p)
			else
				FXService.PlayLose(p)
			end
			
			safeTeleport(p)
		end
		
		-- Clean up session
		activeSessions[tableModel] = nil
	end)
end

return RoundService

