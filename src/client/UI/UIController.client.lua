local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local UI = script.Parent
local Components = UI.Components
local ChoicePopup = require(Components.ChoicePopup)
local Toast = require(Components.Toast)

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PromptChoiceEvent = Remotes:WaitForChild("PromptChoice")
local PromptResponseEvent = Remotes:WaitForChild("PromptResponse")
local NotifyEvent = Remotes:WaitForChild("Notify")

-- State
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local activePopup = nil
local screenGui = nil

-- Init GUI
local function getScreenGui()
	if screenGui then return screenGui end
	
	local gui = playerGui:FindFirstChild("GameUI")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "GameUI"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.None
		gui.Parent = playerGui
	end
	screenGui = gui
	return gui
end

-- Handlers
local function onPromptChoice(payload)
	local gui = getScreenGui()
	
	-- Close existing if needed
	if activePopup then
		activePopup:Close(nil) -- Cancel previous
	end
	
	activePopup = ChoicePopup.new(gui, payload, function(choiceId)
		-- Send response back to server
		PromptResponseEvent:FireServer(choiceId)
		activePopup = nil
	end)
end

local function onNotify(text, duration)
	local gui = getScreenGui()
	Toast.new(gui, text, duration)
end

-- Listeners
PromptChoiceEvent.OnClientEvent:Connect(onPromptChoice)
NotifyEvent.OnClientEvent:Connect(onNotify)

print("[UIController] Started")

