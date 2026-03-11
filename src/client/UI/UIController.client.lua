-- BOOT HEARTBEAT (ABSOLUTE TOP)
print("[CLIENT] BOOT START", os.clock())

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

-- Safe Require Helper
local function safeRequire(path, name)
	local ok, mod = pcall(require, path)
	if not ok then
		warn("[CLIENT] REQUIRE FAILED:", name, mod)
		return nil
	end
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
local ShieldConfig = safeRequire(Shared:WaitForChild("ShieldConfig", 2), "ShieldConfig")
local DEFAULT_SHIELD_MAX = (ShieldConfig and ShieldConfig.MaxShields) or 3

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PromptChoiceEvent = Remotes:WaitForChild("PromptChoice")
local PromptResponseEvent = Remotes:WaitForChild("PromptResponse")
local NotifyEvent = Remotes:WaitForChild("Notify")
local MatchStartEvent = Remotes:WaitForChild("MatchStart", 5)
local MatchEndEvent = Remotes:WaitForChild("MatchEnd", 5)
local UIFxEvent = Remotes:WaitForChild("UIFxEvent", 5)
local StopSpinCinematic = Remotes:WaitForChild("StopSpinCinematic", 5)
local CloseStageUI = Remotes:WaitForChild("CloseStageUI", 5)
local OpponentLeft = Remotes:WaitForChild("OpponentLeft", 5)
local OpponentLeftToast = Remotes:WaitForChild("OpponentLeftToast", 5)
local OpponentLeftCard = Remotes:WaitForChild("OpponentLeftCard", 5)
local PlaySpinCinematic = Remotes:WaitForChild("PlaySpinCinematic", 5)
local ShieldArmedEvent = Remotes:WaitForChild("ShieldArmed", 5)
local UseShieldFailedEvent = Remotes:WaitForChild("UseShieldFailed", 5)
-- Task: Renamed to CinematicStartedAck
local CinematicStartedAck = Remotes:WaitForChild("CinematicStartedAck", 5)
local CinematicStoppedAck = Remotes:WaitForChild("CinematicStoppedAck", 5)
-- Step A: MatchStartingNow
local MatchStartingNow = Remotes:WaitForChild("MatchStartingNow", 5)

-- State
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = nil
local popupComponent = nil
local toastComponent = nil

-- UX FIX B: Setup Seated UI (Invite/Leave buttons)
local SeatUI = safeRequire(UI:WaitForChild("Components"):WaitForChild("SeatUI", 2), "SeatUI")
local ShieldInventoryUI = safeRequire(UI:WaitForChild("Components"):WaitForChild("ShieldInventoryUI", 2), "ShieldInventoryUI")
local seatUIComponent = nil -- Initialized in getScreenGui or later
local shieldInventoryUI = nil
local shieldUIState = {
	count = 0,
	armed = false,
	pending = false,
	max = DEFAULT_SHIELD_MAX
}
local applyShieldUIState

local function setShieldCount(count)
	shieldUIState.count = math.max(0, tonumber(count) or 0)
	if shieldUIState.count <= 0 then
		shieldUIState.armed = false
		shieldUIState.pending = false
	end
	if applyShieldUIState then
		applyShieldUIState()
	end
end

local function setShieldMax(max)
	shieldUIState.max = math.max(0, tonumber(max) or 0)
	if applyShieldUIState then
		applyShieldUIState()
	end
end

local function setShieldArmed(armed)
	shieldUIState.armed = armed == true
	if shieldUIState.armed then
		shieldUIState.pending = false
	end
	if applyShieldUIState then
		applyShieldUIState()
	end
end

local function setShieldPending(pending)
	shieldUIState.pending = pending == true and not shieldUIState.armed
	if applyShieldUIState then
		applyShieldUIState()
	end
end

local function clearShieldPresentation()
	shieldUIState.armed = false
	shieldUIState.pending = false
	if applyShieldUIState then
		applyShieldUIState()
	end
end

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
		if not ok then
			warn("[CLIENT] ChoicePopup.new FAILED:", result)
		end
	end
	if not toastComponent and Toast then
		local ok, result = pcall(function()
			toastComponent = Toast.new(gui)
		end)
		if not ok then
			warn("[CLIENT] Toast.new FAILED:", result)
		end
	end
	-- Initialize SeatUI
	if not seatUIComponent and SeatUI then
		local ok, result = pcall(function()
			seatUIComponent = SeatUI.new(gui)
		end)
		if not ok then
			warn("[CLIENT] SeatUI.new FAILED:", result)
		end
	end
	if not shieldInventoryUI and ShieldInventoryUI then
		local ok, result = pcall(function()
			shieldInventoryUI = ShieldInventoryUI.new(gui)
		end)
		if not ok then
			warn("[CLIENT] ShieldInventoryUI.new FAILED:", result)
		end
	end

	if applyShieldUIState then
		applyShieldUIState()
	end
	
	return gui
end

applyShieldUIState = function()
	if shieldInventoryUI then
		if shieldInventoryUI.SetDisplay then
			shieldInventoryUI:SetDisplay(shieldUIState.count, shieldUIState.max)
		else
			shieldInventoryUI:SetCount(shieldUIState.count)
			if shieldInventoryUI.SetMax then
				shieldInventoryUI:SetMax(shieldUIState.max)
			end
		end
	end

	if seatUIComponent then
		if seatUIComponent.SetShieldState then
			seatUIComponent:SetShieldState(shieldUIState)
		else
			seatUIComponent:SetShieldCount(shieldUIState.count)
			if seatUIComponent.SetShieldMax then
				seatUIComponent:SetShieldMax(shieldUIState.max)
			end
			seatUIComponent:SetShieldArmed(shieldUIState.armed)
			if seatUIComponent.SetShieldPending then
				seatUIComponent:SetShieldPending(shieldUIState.pending)
			end
		end
	end
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
	
	-- Stop spin sound immediately when card pops up
	if CinematicController and CinematicController.StopSpinSound then
		CinematicController.StopSpinSound("PromptChoice")
	end
	
	getScreenGui() -- Ensure created
	
	-- Show reusing the single instance
	if popupComponent and popupComponent.Show then
		popupComponent:Show(payload, function(choiceId)
			-- Problem 1: Pass promptId through to server
			PromptResponseEvent:FireServer(choiceId, payload.promptId)
		end)
	else
		warn("[CLIENT] popupComponent not available for PromptChoice")
	end
	
	-- UX FIX: Hide SeatUI when choice UI is active
	if seatUIComponent then
		seatUIComponent:SetChoiceActive(true)
	end
end

local function onNotify(text, duration)
	getScreenGui() -- Ensure created
	
	-- Show via singleton
	if toastComponent and toastComponent.Show then
		toastComponent:Show(text, duration)
	else
		warn("[CLIENT] toastComponent not available for Notify")
	end
end

-- Listeners (with logging)
if MatchStartEvent then
	MatchStartEvent.OnClientEvent:Connect(function()
		if PromptController then
			PromptController.DisablePrompts()
		end
		-- UX FIX: Hide SeatUI during match
		if seatUIComponent then
			seatUIComponent:SetMatchActive(true)
		end
		-- Duck music volume
		local music = SoundService:FindFirstChild("LobbyMusic")
		if music then
			TweenService:Create(music, TweenInfo.new(1), {Volume = 0.2}):Play()
		end
	end)
end

if MatchEndEvent then
	MatchEndEvent.OnClientEvent:Connect(function()
		if PromptController then
			PromptController.EnablePrompts()
		end
		clearShieldPresentation()
		-- UX FIX: Show SeatUI after match (if seated)
		if seatUIComponent then
			seatUIComponent:SetMatchActive(false)
		end
		-- Restore music volume
		local music = SoundService:FindFirstChild("LobbyMusic")
		if music then
			TweenService:Create(music, TweenInfo.new(1), {Volume = 0.5}):Play()
		end
	end)
end

if PromptChoiceEvent then
	PromptChoiceEvent.OnClientEvent:Connect(onPromptChoice)
else
	warn("[CLIENT] PromptChoiceEvent not found")
end

if NotifyEvent then
	NotifyEvent.OnClientEvent:Connect(onNotify)
else
	warn("[CLIENT] NotifyEvent not found")
end

if UIFxEvent then
	UIFxEvent.OnClientEvent:Connect(function(soundName)
		if FxService and FxService.Play then
			FxService.Play(soundName)
		end
	end)
else
	warn("[CLIENT] UIFxEvent not found")
end

-- Cinematic remotes (UIController is the ONLY listener - no double-start)
if PlaySpinCinematic and CinematicController then
	PlaySpinCinematic.OnClientEvent:Connect(function(animId, duration, tableModel, cineToken)
		-- Clear countdown state when match actually starts
		countdownActive = false
		if CinematicController and CinematicController.Play then
			local ok, err = pcall(function()
				CinematicController.Play(animId, duration, tableModel)
			end)
			if not ok then
				warn("[CLIENT] CinematicController.Play error:", err)
			end
		end
		
		-- Task: Send CinematicStartedAck IMMEDIATELY after calling Play
		if CinematicStartedAck then
			local tableKey = NormalizeTableKey(tableModel)
			CinematicStartedAck:FireServer(tableKey, cineToken)
		end
		
		-- Hide other world UIs
		if WorldSpinUIController then
			local key = NormalizeTableKey(tableModel)
			if key then
				WorldSpinUIController.SetInMatch(true, key)
			end
		end
		-- UX FIX: Hide SeatUI during cinematic (match active)
		if seatUIComponent then
			seatUIComponent:SetMatchActive(true)
		end
	end)
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
		if CinematicController and CinematicController.Stop then
			local ok, err = pcall(function()
				CinematicController.Stop(immediate)
			end)
			if not ok then
				warn("[CLIENT] CinematicController.Stop error:", err)
			end
		end
		
		-- Problem 2: Send CinematicStoppedAck
		if CinematicStoppedAck then
			CinematicStoppedAck:FireServer()
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
		if popupComponent and popupComponent.Hide then
			popupComponent:Hide()
		end
		-- UX FIX: Show SeatUI when choice UI closes (if still seated and not in match)
		if seatUIComponent then
			seatUIComponent:SetChoiceActive(false)
		end
	end)
else
	warn("[CLIENT] CloseStageUI not found")
end

if OpponentLeftToast then
	OpponentLeftToast.OnClientEvent:Connect(function(message, seconds)
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
		
		-- UX FIX: Reset SeatUI flags
		clearShieldPresentation()
		if seatUIComponent then
			seatUIComponent:SetMatchActive(false)
			seatUIComponent:SetChoiceActive(false)
		end
	end)
else
	warn("[CLIENT] OpponentLeftToast not found")
end

if OpponentLeftCard then
	OpponentLeftCard.OnClientEvent:Connect(function(message, seconds)
		if popupComponent then
			-- Show \"Opponent left\" message on card
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
					
					-- UX FIX: Reset SeatUI flags
					clearShieldPresentation()
					if seatUIComponent then
						seatUIComponent:SetMatchActive(false)
						seatUIComponent:SetChoiceActive(false)
					end
				end)
			end
		else
			warn("[CLIENT] popupComponent not available for OpponentLeftCard")
		end
	end)
else
	warn("[CLIENT] OpponentLeftCard not found")
end

-- Step 6: Stats Update Feedback
local StatsUpdate = Remotes:WaitForChild("StatsUpdate", 5)
if StatsUpdate then
	StatsUpdate.OnClientEvent:Connect(function(stats, cashDelta)
		cashDelta = cashDelta or 0
		
		-- Ensure toast is available
		if not toastComponent then
			getScreenGui() -- Initialize if needed
		end
		setShieldCount(stats.Shields or 0)
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
else
	warn("[CLIENT] StatsUpdate not found")
end

-- Shield inventory sync (authoritative server updates)
local ShieldChanged = Remotes:FindFirstChild("ShieldChanged")
if ShieldChanged then
	ShieldChanged.OnClientEvent:Connect(function(newCount)
		setShieldCount(newCount)
	end)
end

if ShieldArmedEvent then
	ShieldArmedEvent.OnClientEvent:Connect(function()
		setShieldArmed(true)
	end)
else
	warn("[CLIENT] ShieldArmedEvent not found")
end

if UseShieldFailedEvent then
	UseShieldFailedEvent.OnClientEvent:Connect(function(_reason)
		clearShieldPresentation()
	end)
else
	warn("[CLIENT] UseShieldFailedEvent not found")
end

-- Match Countdown Display (using Toast system)
local MatchCountdown = Remotes:WaitForChild("MatchCountdown", 5)
local MatchCountdownCancel = Remotes:WaitForChild("MatchCountdownCancel", 5)
local countdownActive = false

if MatchCountdown then
	MatchCountdown.OnClientEvent:Connect(function(tableId, secondsRemaining, opponentName)
		-- Guard: ensure opponentName is a string
		opponentName = tostring(opponentName or "Opponent")
		
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
		
		-- UX FIX: Keep SeatUI visible during countdown
		if seatUIComponent then
			seatUIComponent:SetMatchActive(false) -- Explicitly false during countdown
		end
	end)
else
	warn("[CLIENT] MatchCountdown not found")
end

if MatchCountdownCancel then
	MatchCountdownCancel.OnClientEvent:Connect(function(reason)
		-- Guard: ensure reason is a string
		reason = tostring(reason or "Unknown reason")
		
		countdownActive = false
		
		-- Ensure toast is available
		if not toastComponent then
			getScreenGui()
		end
		
		if toastComponent then
			local message = string.format("❌ Match cancelled: %s", reason)
			toastComponent:Show(message, 2)
		end
		
		-- UX FIX: Show SeatUI again if match cancelled
		if seatUIComponent then
			seatUIComponent:SetMatchActive(false)
		end
	end)
else
	warn("[CLIENT] MatchCountdownCancel not found")
end

-- Step B: MatchStartingNow Handler
if MatchStartingNow then
	MatchStartingNow.OnClientEvent:Connect(function()
		countdownActive = false
		
		-- Immediately hide countdown toast fast
		if toastComponent and toastComponent.HideFast then
			toastComponent:HideFast()
		end
		
		-- Immediately hide SeatUI fast
		if seatUIComponent and seatUIComponent.EaseOutFast then
			seatUIComponent:EaseOutFast()
		end
	end)
end

-- Safe Init Calls
if CinematicController and CinematicController.Init then
	local ok2, err = pcall(function() 
		CinematicController.Init() 
	end)
	if not ok2 then
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
end

-- Initialize seated UI listener (connect before Init to receive initial SeatedChanged fire)
getScreenGui() -- Ensure components are created
if PromptController and PromptController.SeatedChanged then
	PromptController.SeatedChanged:Connect(function(isSeated)
		if not isSeated then
			clearShieldPresentation()
		end
		if seatUIComponent then
			seatUIComponent:SetSeated(isSeated)
		end
		if shieldInventoryUI then
			shieldInventoryUI:SetVisible(not isSeated)
		end
		if isSeated and applyShieldUIState then
			applyShieldUIState()
		end
	end)
else
	warn("[CLIENT] PromptController missing SeatedChanged signal")
end

if not seatUIComponent then
	warn("[CLIENT] SeatUI component not initialized")
end

-- UX FIX A: Initialize PromptController (after Connect so we receive initial SeatedChanged fire)
if PromptController and PromptController.Init then
	PromptController.Init()
end

-- Lobby Music
task.spawn(function()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return end
	local fx = assets:FindFirstChild("FX")
	if not fx then return end
	local musicTemplate = fx:FindFirstChild("PlaygroundOfTheStars")
	
	if musicTemplate and musicTemplate:IsA("Sound") then
		local music = SoundService:FindFirstChild("LobbyMusic")
		if not music then
			music = musicTemplate:Clone()
			music.Name = "LobbyMusic"
			music.Volume = 0.5
			music.Looped = true
			music.Parent = SoundService
			music:Play()
		end
	end
end)

-- BOOT COMPLETE MARKER
print("[CLIENT] BOOT COMPLETE", os.clock())
