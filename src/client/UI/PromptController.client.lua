local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PromptController = {}

-- State
local promptStates = {} -- [ProximityPrompt] = original Enabled value
local isMatchActive = false
local descendantAddedConnection = nil

-- Disable all proximity prompts during match
function PromptController.DisablePrompts()
	if isMatchActive then return end
	isMatchActive = true
	
	print("[PromptController] Disabling proximity prompts")
	
	-- Store original states and disable all existing prompts
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			promptStates[descendant] = descendant.Enabled
			descendant.Enabled = false
		end
	end
	
	-- Listen for new prompts during match
	descendantAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			promptStates[descendant] = descendant.Enabled
			descendant.Enabled = false
		end
	end)
end

-- Restore proximity prompts after match
function PromptController.EnablePrompts()
	if not isMatchActive then return end
	isMatchActive = false
	
	print("[PromptController] Restoring proximity prompts")
	
	-- Disconnect listener
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		descendantAddedConnection = nil
	end
	
	-- Restore original states
	for prompt, originalState in pairs(promptStates) do
		if prompt and prompt.Parent then
			prompt.Enabled = originalState
		end
	end
	
	-- Clear state map
	promptStates = {}
end

-- Listen for match start/end signals
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if Remotes then
	local MatchStartEvent = Remotes:FindFirstChild("MatchStart", 5)
	local MatchEndEvent = Remotes:FindFirstChild("MatchEnd", 5)
	
	if MatchStartEvent then
		MatchStartEvent.OnClientEvent:Connect(function()
			PromptController.DisablePrompts()
		end)
	end
	
	if MatchEndEvent then
		MatchEndEvent.OnClientEvent:Connect(function()
			PromptController.EnablePrompts()
		end)
	end
end

return PromptController

