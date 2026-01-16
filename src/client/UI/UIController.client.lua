local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local screenGui = nil
local popupComponent = nil
local toastComponent = nil

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
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
		gui.Parent = playerGui
	end
	screenGui = gui
	
	-- Initialize Components ONCE
	if not popupComponent then
		popupComponent = ChoicePopup.new(gui)
	end
	if not toastComponent then
		toastComponent = Toast.new(gui)
	end
	
	return gui
end

-- Handlers
local function onPromptChoice(payload)
	getScreenGui() -- Ensure created
	
	-- Show reusing the single instance
	popupComponent:Show(payload, function(choiceId)
		PromptResponseEvent:FireServer(choiceId)
	end)
end

local function onNotify(text, duration)
	getScreenGui() -- Ensure created
	
	-- Show via singleton
	toastComponent:Show(text, duration)
end

-- Listeners
PromptChoiceEvent.OnClientEvent:Connect(onPromptChoice)
NotifyEvent.OnClientEvent:Connect(onNotify)

print("[UIController] Started")
