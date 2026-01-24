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
local WorldSpinUIController = safeRequire(UI.WorldSpinUIController, "WorldSpinUIController")

-- Remotes (with safe waits)
print("[CLIENT] Waiting for Remotes...")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
print("[CLIENT] Remotes found")

local PromptChoiceEvent = Remotes:WaitForChild("PromptChoice")
local PromptResponseEvent = Remotes:WaitForChild("PromptResponse")
local NotifyEvent = Remotes:WaitForChild("Notify")
local MatchStartEvent = Remotes:WaitForChild("MatchStart", 5)
local MatchEndEvent = Remotes:WaitForChild("MatchEnd", 5)
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

-- Helper: Normalize Table Key
local function NormalizeTableKey(v)
	if typeof(v) == "Instance" then
		return v.Name
	elseif typeof(v) == "string" then
		return v
	elseif typeof(v) == "number" then
		return string.format("Table_%02d", v)
	end
	return nil
end

-- Handlers
local function onPromptChoice(payload)
	-- Clear countdown state when UI opens (match in progress)
	countdownActive = false
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

local MatchStartEvent = Remotes:FindFirstChild("MatchStart", 5)
local MatchEndEvent = Remotes:FindFirstChild("MatchEnd", 5)

-- Listeners (with logging)
if MatchStartEvent then
	MatchStartEvent.OnClientEvent:Connect(function()
		print("[CLIENT] MatchStart RECEIVED")
		if PromptController then
			PromptController.DisablePrompts()
		end
	end)
end

if MatchEndEvent then
	MatchEndEvent.OnClientEvent:Connect(function()
		print("[CLIENT] MatchEnd RECEIVED")
		if PromptController then
			PromptController.EnablePrompts()
		end
	end)
end

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
		-- Clear countdown state when match actually starts
		countdownActive = false
		print("[CLIENT] PlaySpinCinematic RECEIVED:", animId, duration)
		if CinematicController and CinematicController.Play then
			local ok, err = pcall(function()
				CinematicController.Play(animId, duration, tableModel)
			end)
			if not ok then
				warn("[CLIENT] CinematicController.Play error:", err)
			end
		end
		-- Hide other world UIs
		if WorldSpinUIController then
			local key = NormalizeTableKey(tableModel)
			if key then
				WorldSpinUIController.SetInMatch(true, key)
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
		-- Ensure prompts are enabled if match ends abruptly via StopSpinCinematic (fallback)
		if PromptController and immediate then
			PromptController.EnablePrompts()
		end
		-- Restore world UIs on stop
		if WorldSpinUIController then
			WorldSpinUIController.SetInMatch(false, nil)
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
		end
		-- Safe no-op if component missing or already hidden
	end)
	print("[CLIENT] Hooked CloseStageUI")
else
	warn("[CLIENT] CloseStageUI not found")
end

if OpponentLeftToast then
	OpponentLeftToast.OnClientEvent:Connect(function(message, seconds)
		print("[CLIENT] OpponentLeftToast RECEIVED:", message)
		getScreenGui() -- Ensure GUI exists even if no Stage UI ever opened
		
		-- Show toast notification
		if toastComponent and toastComponent.Show then
			toastComponent:Show(message, seconds or 2)
		else
			warn("[CLIENT] toastComponent not available for OpponentLeftToast")
		end
		
		-- Cleanup UI/Cinematic/Prompts (Idempotent safety)
		if popupComponent and popupComponent.Hide then popupComponent:Hide() end
		if CinematicController and CinematicController.Stop then pcall(function() CinematicController.Stop(true) end) end
		if PromptController then PromptController.EnablePrompts() end
		if WorldSpinUIController then WorldSpinUIController.SetInMatch(false, nil) end
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
					-- Ensure final cleanup
					if CinematicController and CinematicController.Stop then pcall(function() CinematicController.Stop(true) end) end
					if PromptController then PromptController.EnablePrompts() end
					if WorldSpinUIController then WorldSpinUIController.SetInMatch(false, nil) end
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

-- Step 6: Stats Update Feedback
local StatsUpdate = Remotes:WaitForChild("StatsUpdate", 5)
if StatsUpdate then
	StatsUpdate.OnClientEvent:Connect(function(stats, cashDelta)
		cashDelta = cashDelta or 0
		print("[CLIENT] StatsUpdate RECEIVED:", stats.Cash, "total cash", cashDelta, "delta", stats.Wins, "wins", stats.Streak, "streak")
		
		-- Ensure toast is available
		if not toastComponent then
			getScreenGui() -- Initialize if needed
		end
		
		if toastComponent then
			-- Show reward toast if cash was earned this round
			if cashDelta > 0 then
				local message = string.format("💰 +$%d | 🏆 %d Wins | 🔥 %d Streak", 
					cashDelta, stats.Wins or 0, stats.Streak or 0)
				toastComponent:Show(message, 4)
			else
				-- Show stats even if no cash (for streak reset visibility)
				local message = string.format("🏆 %d Wins | 🔥 %d Streak", 
					stats.Wins or 0, stats.Streak or 0)
				toastComponent:Show(message, 3)
			end
		else
			warn("[CLIENT] toastComponent not available for StatsUpdate")
		end
	end)
	print("[CLIENT] Hooked StatsUpdate")
else
	warn("[CLIENT] StatsUpdate not found")
end

-- Match Countdown Display (using Toast system)
local MatchCountdown = Remotes:WaitForChild("MatchCountdown", 5)
local MatchCountdownCancel = Remotes:WaitForChild("MatchCountdownCancel", 5)
local countdownActive = false

if MatchCountdown then
	MatchCountdown.OnClientEvent:Connect(function(tableId, secondsRemaining, opponentName)
		-- Guard: ensure opponentName is a string
		opponentName = tostring(opponentName or "Opponent")
		
		print("[CLIENT] MatchCountdown RECEIVED:", tableId, secondsRemaining, opponentName)
		
		-- Ensure toast is available
		if not toastComponent then
			getScreenGui() -- Initialize if needed
		end
		
		if not toastComponent then
			warn("[CLIENT] Toast not available for countdown")
			return
		end
		
		countdownActive = true
		
		-- Show countdown toast
		if secondsRemaining > 0 then
			local message = string.format("⏱️ Match starting in %d... (vs %s)", secondsRemaining, opponentName)
			toastComponent:Show(message, 1.5) -- Duration slightly longer than tick interval
		end
	end)
	print("[CLIENT] Hooked MatchCountdown")
else
	warn("[CLIENT] MatchCountdown not found")
end

if MatchCountdownCancel then
	MatchCountdownCancel.OnClientEvent:Connect(function(reason)
		-- Guard: ensure reason is a string
		reason = tostring(reason or "Unknown reason")
		
		print("[CLIENT] MatchCountdownCancel RECEIVED:", reason)
		
		countdownActive = false
		
		-- Ensure toast is available
		if not toastComponent then
			getScreenGui()
		end
		
		if toastComponent then
			local message = string.format("❌ Match cancelled: %s", reason)
			toastComponent:Show(message, 2)
		end
	end)
	print("[CLIENT] Hooked MatchCountdownCancel")
else
	warn("[CLIENT] MatchCountdownCancel not found")
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

if WorldSpinUIController and WorldSpinUIController.Init then
	WorldSpinUIController.Init()
	print("[CLIENT] WorldSpinUIController.Init OK")
end

-- BOOT COMPLETE MARKER
print("[CLIENT] BOOT COMPLETE", os.clock())
