local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local PromptController = {}

-- State
local disabledByMatch = false
local disabledBySeated = false
local descendantAddedConnection = nil
local humanoidSeatedConnection = nil
local characterAddedConnection = nil

-- Signals
local seatedChangedEvent = Instance.new("BindableEvent")
PromptController.SeatedChanged = seatedChangedEvent.Event

-- Helper: Check if prompt is a Sit prompt
local function isSitPrompt(prompt)
	return prompt.ActionText == "Sit" or prompt:GetAttribute("SitPrompt") == true
end

-- Helper: Update prompt enabled state based on flags
local function UpdatePromptEnabled(prompt)
	if not prompt or not prompt.Parent then return end
	
	if isSitPrompt(prompt) then
		-- Sit prompts are disabled if match is active OR player is seated
		prompt.Enabled = not disabledByMatch and not disabledBySeated
	else
		-- Other prompts are only disabled by match
		prompt.Enabled = not disabledByMatch
	end
end

-- Helper: Refresh all prompts in workspace
local function RefreshAllPrompts()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			UpdatePromptEnabled(descendant)
		end
	end
end

-- UX FIX A: Setup humanoid seated listener
local function setupSeatedListener()
	local player = Players.LocalPlayer
	if not player then return end
	
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- Disconnect existing listener
	if humanoidSeatedConnection then
		humanoidSeatedConnection:Disconnect()
		humanoidSeatedConnection = nil
	end
	
	-- Connect new listener
	humanoidSeatedConnection = humanoid.Seated:Connect(function(active)
		disabledBySeated = active
		print("[PromptController] Seated state changed:", active)
		RefreshAllPrompts()
		seatedChangedEvent:Fire(active) -- Fire signal
	end)
	
	-- Set initial state
	disabledBySeated = humanoid.Sit
	RefreshAllPrompts()
	seatedChangedEvent:Fire(humanoid.Sit) -- Fire initial state
end

-- UX FIX A: Setup character listener
local function setupCharacterListener()
	local player = Players.LocalPlayer
	if not player then return end
	
	-- Disconnect existing listener
	if characterAddedConnection then
		characterAddedConnection:Disconnect()
		characterAddedConnection = nil
	end
	
	-- Connect to CharacterAdded
	characterAddedConnection = player.CharacterAdded:Connect(function(character)
		-- Wait for character to load fully
		task.delay(0.1, function()
			setupSeatedListener()
		end)
	end)
	
	-- Setup for current character
	if player.Character then
		setupSeatedListener()
	end
end

-- Disable all proximity prompts during match
function PromptController.DisablePrompts()
	if disabledByMatch then return end
	disabledByMatch = true
	
	print("[PromptController] Disabling proximity prompts (match active)")
	RefreshAllPrompts()
	
	-- Listen for new prompts during match
	if not descendantAddedConnection then
		descendantAddedConnection = Workspace.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("ProximityPrompt") then
				UpdatePromptEnabled(descendant)
			end
		end)
	end
end

-- Restore proximity prompts after match
function PromptController.EnablePrompts()
	if not disabledByMatch then return end
	disabledByMatch = false
	
	print("[PromptController] Restoring proximity prompts (match ended)")
	RefreshAllPrompts()
	
	-- Disconnect listener
	if descendantAddedConnection then
		descendantAddedConnection:Disconnect()
		descendantAddedConnection = nil
	end
end

-- Initialize
function PromptController.Init()
	setupCharacterListener()
	
	-- Initial scan
	RefreshAllPrompts()
end

return PromptController
