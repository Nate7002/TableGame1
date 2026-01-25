local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIService = {}

-- Constants
local PROMPT_TIMEOUT_DEFAULT = 30

-- State
local activePrompts = {} -- [Player] = { thread = thread, startTime = number, promptId = string }

-- Setup Remotes
local function getRemotes()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	
	local function ensureEvent(name)
		if not folder:FindFirstChild(name) then
			local re = Instance.new("RemoteEvent")
			re.Name = name
			re.Parent = folder
		end
		return folder[name]
	end
	
	return {
		PromptChoice = ensureEvent("PromptChoice"),
		PromptResponse = ensureEvent("PromptResponse"),
		Notify = ensureEvent("Notify"),
		UIFxEvent = ensureEvent("UIFxEvent"),
		PlaySpinCinematic = ensureEvent("PlaySpinCinematic"),
		StopSpinCinematic = ensureEvent("StopSpinCinematic"),
		CloseStageUI = ensureEvent("CloseStageUI"),
		MatchStart = ensureEvent("MatchStart"),
		MatchEnd = ensureEvent("MatchEnd"),
		OpponentLeft = ensureEvent("OpponentLeft"),
		OpponentLeftToast = ensureEvent("OpponentLeftToast"),
		OpponentLeftCard = ensureEvent("OpponentLeftCard"),
		StatsUpdate = ensureEvent("StatsUpdate"),
		MatchCountdown = ensureEvent("MatchCountdown"),
		MatchCountdownCancel = ensureEvent("MatchCountdownCancel"),
		LeaveSeat = ensureEvent("LeaveSeat"),
		OpponentPicked = ensureEvent("OpponentPicked"),
		CinematicStoppedAck = ensureEvent("CinematicStoppedAck"),
		-- Task: Rename ack to match what it actually means
		CinematicStartedAck = ensureEvent("CinematicStartedAck"),
		MatchStartingNow = ensureEvent("MatchStartingNow")
	}
end

local Remotes = getRemotes()

-- Public API
function UIService.PlayCinematic(player, animId, duration, tableModel, cineToken)
	if not (player and player.Parent) then return end
	print(string.format("[UIService] PlaySpinCinematic firing to %s at %0.6f token=%s", player.Name, os.clock(), tostring(cineToken)))
	Remotes.PlaySpinCinematic:FireClient(player, animId, duration, tableModel, cineToken)
end

function UIService.StopCinematic(player)
	if not (player and player.Parent) then return end
	Remotes.StopSpinCinematic:FireClient(player)
end

-- Step A: MatchStartingNow
function UIService.MatchStartingNow(player)
	if not (player and player.Parent) then return end
	print(string.format("[UIService] MatchStartingNow firing to %s at %0.6f", player.Name, os.clock()))
	Remotes.MatchStartingNow:FireClient(player)
end

function UIService.PlayFx(player, soundName)
	if not (player and player.Parent) then return end
	Remotes.UIFxEvent:FireClient(player, soundName)
end

function UIService.PromptChoice(player, payload)
	if not (player and player.Parent) then return nil end
	
	-- Problem 1: Generate promptId if missing
	local promptId = payload.promptId or (player.UserId .. "_" .. tostring(os.clock()))
	payload.promptId = promptId
	
	-- Cancel existing prompt for this player
	if activePrompts[player] then
		-- Resume the old thread with nil to close it
		task.spawn(activePrompts[player].thread, nil)
		activePrompts[player] = nil
	end
	
	local currentThread = coroutine.running()
	activePrompts[player] = {
		thread = currentThread,
		startTime = os.time(),
		promptId = promptId
	}
	
	-- Send to client
	Remotes.PromptChoice:FireClient(player, payload)
	
	-- Handle Timeout (Server-side safety)
	local timeout = payload.timeout or PROMPT_TIMEOUT_DEFAULT
	task.delay(timeout + 1, function() -- +1 buffer for latency
		local prompt = activePrompts[player]
		if prompt and prompt.thread == currentThread then
			activePrompts[player] = nil
			task.spawn(currentThread, nil) -- Resume with nil (timeout)
		end
	end)
	
	-- Yield until response
	return coroutine.yield()
end

function UIService.Notify(player, text, duration)
	if not (player and player.Parent) then return end
	Remotes.Notify:FireClient(player, text, duration)
end

function UIService.CloseStageUI(player)
	if not (player and player.Parent) then return end
	print("[UIService] CloseStageUI firing to", player.Name, "at", os.clock())
	Remotes.CloseStageUI:FireClient(player)
end

function UIService.NotifyOpponentLeft(player, tableModel)
	if not (player and player.Parent) then return end
	print("[UIService] Notifying", player.Name, "that opponent left")
	Remotes.OpponentLeft:FireClient(player, tableModel)
end

-- Internal Handler
local function handleResponse(player, choiceId, promptId)
	local prompt = activePrompts[player]
	if prompt then
		-- Problem 1: Stale response rejection
		if prompt.promptId == promptId then
			activePrompts[player] = nil
			task.spawn(prompt.thread, choiceId)
		else
			print(string.format("[UIService] Ignoring stale PromptResponse %s choice=%s id=%s expected=%s", 
				player.Name, tostring(choiceId), tostring(promptId), tostring(prompt.promptId)))
		end
	else
		-- Ignore late/unexpected responses
		print(string.format("[UIService] Ignoring unexpected PromptResponse %s choice=%s id=%s (no active prompt)", 
			player.Name, tostring(choiceId), tostring(promptId)))
	end
end

-- Init
Remotes.PromptResponse.OnServerEvent:Connect(handleResponse)

return UIService
