-- BOOT HEARTBEAT (ABSOLUTE TOP)
print("[CLIENT] BOOT START", os.clock())

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Safe Require Helper
local function safeRequire(path, name)
	local ok, mod = pcall(require, path)
	if not ok then
		warn("[CLIENT] REQUIRE FAILED:", name, mod)
		return nil
	end
	print("[CLIENT] REQUIRE OK:", name)
	return mod
end

local UI = script.Parent
local Components = UI.Components

-- Wrap ALL requires with safeRequire
local ChoicePopup = safeRequire(Components.ChoicePopup, "ChoicePopup")
local Toast = safeRequire(Components.Toast, "Toast")
local FxService = safeRequire(UI.FxService, "FxService")
local CinematicController = safeRequire(UI.CinematicController, "CinematicController")
local PromptController = safeRequire(UI.PromptController, "PromptController")

-- Remotes (with safe waits)
print("[CLIENT] Waiting for Remotes...")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
print("[CLIENT] Remotes found")

local PromptChoiceEvent = Remotes:WaitForChild("PromptChoice")
local PromptResponseEvent = Remotes:WaitForChild("PromptResponse")
local NotifyEvent = Remotes:WaitForChild("Notify")
local UIFxEvent = Remotes:WaitForChild("UIFxEvent", 5) -- Optional wait
local StopSpinCinematic = Remotes:WaitForChild("StopSpinCinematic", 5)
local CloseStageUI = Remotes:WaitForChild("CloseStageUI", 5) -- Optional wait
local OpponentLeft = Remotes:WaitForChild("OpponentLeft", 5) -- Optional wait
local OpponentLeftToast = Remotes:WaitForChild("OpponentLeftToast", 5) -- Optional wait
local OpponentLeftCard = Remotes:WaitForChild("OpponentLeftCard", 5) -- Optional wait
local PlaySpinCinematic = Remotes:WaitForChild("PlaySpinCinematic", 5) -- Optional wait

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
	
	-- Initialize Components ONCE (with safe checks)
	if not popupComponent and ChoicePopup then
		local ok, result = pcall(function()
			popupComponent = ChoicePopup.new(gui)
		end)
		if ok then
			print("[CLIENT] ChoicePopup.new OK")
		else
			warn("[CLIENT] ChoicePopup.new FAILED:", result)
		end
	end
	if not toastComponent and Toast then
		local ok, result = pcall(function()
			toastComponent = Toast.new(gui)
		end)
		if ok then
			print("[CLIENT] Toast.new OK")
		else
			warn("[CLIENT] Toast.new FAILED:", result)
		end
	end
	
	return gui
end

-- Handlers
local function onPromptChoice(payload)
	print("[CLIENT] PromptChoice RECEIVED")
	getScreenGui() -- Ensure created
	
	-- Show reusing the single instance
	if popupComponent and popupComponent.Show then
		popupComponent:Show(payload, function(choiceId)
			PromptResponseEvent:FireServer(choiceId)
		end)
	else
		warn("[CLIENT] popupComponent not available for PromptChoice")
	end
end

local function onNotify(text, duration)
	print("[CLIENT] Notify RECEIVED:", text)
	getScreenGui() -- Ensure created
	
	-- Show via singleton
	if toastComponent and toastComponent.Show then
		toastComponent:Show(text, duration)
	else
		warn("[CLIENT] toastComponent not available for Notify")
	end
end

-- Listeners (with logging)
if PromptChoiceEvent then
	PromptChoiceEvent.OnClientEvent:Connect(onPromptChoice)
	print("[CLIENT] Hooked PromptChoice")
else
	warn("[CLIENT] PromptChoiceEvent not found")
end

if NotifyEvent then
	NotifyEvent.OnClientEvent:Connect(onNotify)
	print("[CLIENT] Hooked Notify")
else
	warn("[CLIENT] NotifyEvent not found")
end

if UIFxEvent then
	UIFxEvent.OnClientEvent:Connect(function(soundName)
		print("[CLIENT] UIFxEvent RECEIVED:", soundName)
		if FxService and FxService.Play then
			FxService.Play(soundName)
		end
	end)
	print("[CLIENT] Hooked UIFxEvent")
else
	warn("[CLIENT] UIFxEvent not found")
end

-- Cinematic remotes (UIController is the ONLY listener - no double-start)
if PlaySpinCinematic and CinematicController then
	PlaySpinCinematic.OnClientEvent:Connect(function(animId, duration, tableModel)
		print("[CLIENT] PlaySpinCinematic RECEIVED:", animId, duration)
		if CinematicController and CinematicController.Play then
			local ok, err = pcall(function()
				CinematicController.Play(animId, duration, tableModel)
			end)
			if not ok then
				warn("[CLIENT] CinematicController.Play error:", err)
			end
		end
	end)
	print("[CLIENT] Hooked PlaySpinCinematic (single listener)")
else
	if not PlaySpinCinematic then
		warn("[CLIENT] PlaySpinCinematic not found")
	end
	if not CinematicController then
		warn("[CLIENT] CinematicController not available for PlaySpinCinematic")
	end
end

if StopSpinCinematic and CinematicController then
	StopSpinCinematic.OnClientEvent:Connect(function(immediate)
		print("[CLIENT] StopSpinCinematic RECEIVED at", os.clock(), "immediate:", immediate or false)
		if CinematicController and CinematicController.Stop then
			local ok, err = pcall(function()
				CinematicController.Stop(immediate)
			end)
			if not ok then
				warn("[CLIENT] CinematicController.Stop error:", err)
			end
		end
	end)
	print("[CLIENT] Hooked StopSpinCinematic (single listener)")
else
	if not StopSpinCinematic then
		warn("[CLIENT] StopSpinCinematic not found")
	end
	if not CinematicController then
		warn("[CLIENT] CinematicController not available for StopSpinCinematic")
	end
end

if CloseStageUI then
	CloseStageUI.OnClientEvent:Connect(function()
		print("[CLIENT] CloseStageUI RECEIVED at", os.clock())
		if popupComponent and popupComponent.Hide then
			popupComponent:Hide()
		else
			warn("[CLIENT] popupComponent not available for CloseStageUI")
		end
	end)
	print("[CLIENT] Hooked CloseStageUI")
else
	warn("[CLIENT] CloseStageUI not found")
end

if OpponentLeftToast then
	OpponentLeftToast.OnClientEvent:Connect(function(message, seconds)
		print("[CLIENT] OpponentLeftToast RECEIVED:", message)
		-- Show toast notification
		if toastComponent and toastComponent.Show then
			toastComponent:Show(message, seconds or 2)
		else
			warn("[CLIENT] toastComponent not available for OpponentLeftToast")
		end
	end)
	print("[CLIENT] Hooked OpponentLeftToast")
else
	warn("[CLIENT] OpponentLeftToast not found")
end

if OpponentLeftCard then
	OpponentLeftCard.OnClientEvent:Connect(function(message, seconds)
		print("[CLIENT] OpponentLeftCard RECEIVED:", message)
		if popupComponent then
			-- Show "Opponent left" message on card
			if popupComponent._statusLabel then
				popupComponent._statusLabel.Text = message
				popupComponent._statusLabel.Visible = true
			end
			-- Disable buttons immediately
			if popupComponent._optionsContainer then
				for _, child in ipairs(popupComponent._optionsContainer:GetChildren()) do
					if child:IsA("Frame") then
						local btn = child:FindFirstChildOfClass("ImageButton")
						if btn then
							btn.Active = false
							btn.AutoButtonColor = false
						end
					end
				end
			end
			-- Hide countdown (optional, but cleaner)
			if popupComponent._countdown then
				popupComponent._countdown:SetVisible(false)
			end
			-- Auto-close after specified seconds (server will also force close)
			if seconds and seconds > 0 then
				task.delay(seconds, function()
					if popupComponent and not popupComponent._isClosing then
						popupComponent:Hide()
					end
				end)
			end
		else
			warn("[CLIENT] popupComponent not available for OpponentLeftCard")
		end
	end)
	print("[CLIENT] Hooked OpponentLeftCard")
else
	warn("[CLIENT] OpponentLeftCard not found")
end

-- Safe Init Calls
if CinematicController and CinematicController.Init then
	local ok2, err = pcall(function() 
		CinematicController.Init() 
	end)
	if ok2 then
		print("[CLIENT] CinematicController.Init OK")
	else
		warn("[CLIENT] CinematicController.Init FAILED:", err)
	end
else
	if not CinematicController then
		warn("[CLIENT] CinematicController missing")
	else
		warn("[CLIENT] CinematicController has no Init method")
	end
end

-- BOOT COMPLETE MARKER
print("[CLIENT] BOOT COMPLETE", os.clock())
