local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIService = {}

-- Constants
local PROMPT_TIMEOUT_DEFAULT = 30

-- State
local activePrompts = {} -- [Player] = { thread = thread, startTime = number }

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
		Notify = ensureEvent("Notify")
	}
end

local Remotes = getRemotes()

-- Public API
function UIService.PromptChoice(player, payload)
	if not (player and player.Parent) then return nil end
	
	-- Cancel existing prompt for this player
	if activePrompts[player] then
		-- Resume the old thread with nil to close it
		task.spawn(activePrompts[player].thread, nil)
		activePrompts[player] = nil
	end
	
	local currentThread = coroutine.running()
	activePrompts[player] = {
		thread = currentThread,
		startTime = os.time()
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

-- Internal Handler
local function handleResponse(player, choiceId)
	local prompt = activePrompts[player]
	if prompt then
		activePrompts[player] = nil
		task.spawn(prompt.thread, choiceId)
	else
		-- Ignore late/unexpected responses
	end
end

-- Init
Remotes.PromptResponse.OnServerEvent:Connect(handleResponse)

return UIService

