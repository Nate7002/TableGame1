local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIService = {}

-- Constants
local PROMPT_TIMEOUT_DEFAULT = 30

-- State
local activePrompts = {} -- [Player] = { thread = thread, startTime = number, promptId = string }
local ActivePrompts = {} -- [player] = promptId (server-authoritative registry, registered before UI fires)

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
		UseShield = ensureEvent("UseShield"),
		UseShieldFailed = ensureEvent("UseShieldFailed"),
		ShieldArmed = ensureEvent("ShieldArmed"),
		ShieldChanged = ensureEvent("ShieldChanged"),
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

function UIService.RegisterPrompt(player, promptId)
	if not (player and player.Parent) then return end
	ActivePrompts[player] = promptId
end

function UIService.ClearPrompt(player)
	if not player then return end
	ActivePrompts[player] = nil
	-- Also clear and resume any waiting prompt (e.g. on abort, timeout)
	local prompt = activePrompts[player]
	if prompt then
		activePrompts[player] = nil
		task.spawn(prompt.thread, nil)
	end
end

function UIService.GetActivePrompt(player)
	return ActivePrompts[player]
end

function UIService.PromptChoice(player, payload)
	if not (player and player.Parent) then return nil end

	-- Generate promptId if missing (caller should pass it when using RegisterPrompt)
	local promptId = payload.promptId or (player.UserId .. "_" .. tostring(os.clock()))
	payload.promptId = promptId

	-- Ensure registered (caller may have already called RegisterPrompt; this backs up)
	UIService.RegisterPrompt(player, promptId)

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
			ActivePrompts[player] = nil
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
	UIService.ClearPrompt(player)
	Remotes.CloseStageUI:FireClient(player)
end

function UIService.FireStatsUpdate(player, stats)
	if not (player and player.Parent) then return end
	local remotes = getRemotes()
	if remotes and remotes.StatsUpdate then
		remotes.StatsUpdate:FireClient(player, stats, 0)
	end
end

function UIService.FireShieldChanged(player, newCount)
	if not (player and player.Parent) then return end
	local remotes = getRemotes()
	if remotes and remotes.ShieldChanged then
		remotes.ShieldChanged:FireClient(player, newCount)
	end
end

function UIService.FireShieldArmed(player)
	if not (player and player.Parent) then return end
	local remotes = getRemotes()
	if remotes and remotes.ShieldArmed then
		remotes.ShieldArmed:FireClient(player)
	end
end

function UIService.NotifyOpponentLeft(player, tableModel)
	if not (player and player.Parent) then return end
	print("[UIService] Notifying", player.Name, "that opponent left")
	Remotes.OpponentLeft:FireClient(player, tableModel)
end

-- Internal Handler
local function handleResponse(player, choiceId, promptId)
	local expectedPromptId = ActivePrompts[player]

	if not expectedPromptId then
		warn("[UIService] PromptResponse ignored - no active prompt")
		return
	end

	if promptId ~= expectedPromptId then
		warn(string.format(
			"[UIService] PromptResponse ignored - wrong promptId player=%s got=%s expected=%s",
			player.Name,
			tostring(promptId),
			tostring(expectedPromptId)
		))
		return
	end

	ActivePrompts[player] = nil

	local prompt = activePrompts[player]
	if prompt and prompt.promptId == promptId then
		activePrompts[player] = nil
		task.spawn(prompt.thread, choiceId)
	else
		warn("[UIService] PromptResponse accepted but no thread to resume - prompt may have timed out")
	end
end

-- Init
Remotes.PromptResponse.OnServerEvent:Connect(handleResponse)

return UIService
