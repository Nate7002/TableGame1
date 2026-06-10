-- BOOT HEARTBEAT (ABSOLUTE TOP)
print("[CLIENT] BOOT START", os.clock())

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
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
local MonetizationConfig = safeRequire(Shared:WaitForChild("MonetizationConfig", 2), "MonetizationConfig")
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
local PromptMonetizationProductEvent = Remotes:WaitForChild("PromptMonetizationProduct", 5)
local MonetizationSnapshotEvent = Remotes:WaitForChild("MonetizationSnapshot", 5)
local RestoreOfferStateEvent = Remotes:WaitForChild("RestoreOfferState", 5)
local RequestRestorePurchaseEvent = Remotes:WaitForChild("RequestRestorePurchase", 5)
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
local StatsHUD = safeRequire(UI:WaitForChild("Components"):WaitForChild("StatsHUD", 2), "StatsHUD")
local RestoreOfferMenu = safeRequire(UI:WaitForChild("Components"):WaitForChild("RestoreOfferMenu", 2), "RestoreOfferMenu")
local IntroGuideOverlay = safeRequire(UI:WaitForChild("Components"):WaitForChild("IntroGuideOverlay", 2), "IntroGuideOverlay")
local IntroTableGuide = safeRequire(UI:WaitForChild("Components"):WaitForChild("IntroTableGuide", 2), "IntroTableGuide")
local VIPPromoCard = safeRequire(UI:WaitForChild("Components"):WaitForChild("VIPPromoCard", 2), "VIPPromoCard")
local seatUIComponent = nil -- Initialized in getScreenGui or later
local shieldInventoryUI = nil
local statsHudComponent = nil
local restoreOfferMenuComponent = nil
local introGuideOverlayComponent = nil
local introTableGuideComponent = nil
local vipPromoCardComponent = nil
local shieldUIState = {
	count = 0,
	armed = false,
	pending = false,
	max = DEFAULT_SHIELD_MAX
}
local seatPresentationState = {
	seated = false,
	matchActive = false,
	choiceActive = false,
}
local activeMonetizationPrompt = {
	source = nil,
	productId = nil,
}
local applyShieldUIState
local applyStatsHudState
local restoreOfferState = {
	Active = false,
}
local applyRestoreOfferState
local applyMonetizationState
local applyLobbyLayout
local updatePersistentLobbySurfaceVisibility
local lastKnownStats = nil
local monetizationSnapshot = nil
local introOverlayDismissed = false
local introMovementWatcher = nil
local viewportCameraConnection = nil
local viewportSizeConnection = nil
local onboardingState = {
	introShown = false,
	seatedHintShown = false,
	postRoundHintShown = false,
}
local onboardingTokens = {
	intro = 0,
	seated = 0,
	postRound = 0,
}
local dismissIntroOverlay
local stopIntroGuideFlow
local startIntroGuideFlow

local LEFT_STACK_STATS_Y = -78
local LEFT_STACK_SHIELDS_Y = 40

local function getVIPGamePassId()
	local monetization = type(MonetizationConfig) == "table" and MonetizationConfig or nil
	local vipConfig = monetization and monetization.VIP or nil
	local gamePassKey = type(vipConfig) == "table" and tostring(vipConfig.GamePassKey or "VIP") or "VIP"
	local gamePasses = monetization and monetization.GamePasses or nil
	local vipPass = type(gamePasses) == "table" and gamePasses[gamePassKey] or nil
	return math.max(0, tonumber(vipPass and vipPass.Id) or 0)
end

local function sanitizeMonetizationSnapshot(snapshot)
	local configuredPassId = getVIPGamePassId()
	local sanitized = type(snapshot) == "table" and snapshot or {}
	local gamePassId = math.max(0, tonumber(sanitized.GamePassId) or configuredPassId)
	local configured = sanitized.Configured == true or gamePassId > 0

	return {
		HasVIP = sanitized.HasVIP == true,
		RewardMultiplier = math.max(1, tonumber(sanitized.RewardMultiplier) or 1),
		Configured = configured,
		GamePassId = configured and gamePassId or 0,
	}
end

monetizationSnapshot = sanitizeMonetizationSnapshot(nil)

local function getLobbyLayoutMetrics()
	local camera = Workspace.CurrentCamera
	local viewportWidth = camera and camera.ViewportSize.X or 1400

	if viewportWidth >= 1400 then
		return 1, 18
	elseif viewportWidth >= 900 then
		return 0.82, 12
	end

	return 0.68, 8
end

local function shouldShowVIPPromoCard()
	return monetizationSnapshot ~= nil
		and (monetizationSnapshot.HasVIP == true or monetizationSnapshot.Configured == true)
end

local function shouldShowPersistentLobbySurfaces()
	return seatPresentationState.matchActive ~= true and seatPresentationState.choiceActive ~= true
end

local function snapshotPresentationStats(stats)
	if type(stats) ~= "table" then
		return nil
	end

	return {
		Cash = tonumber(stats.Cash) or 0,
		Wins = tonumber(stats.Wins) or 0,
		Streak = tonumber(stats.Streak) or 0,
		Gems = tonumber(stats.Gems) or 0,
		Shields = tonumber(stats.Shields) or 0,
	}
end

local function setSeatPresentationSeated(seated)
	seatPresentationState.seated = seated == true
	if seatUIComponent then
		seatUIComponent:SetSeated(seated == true)
	end
	if updatePersistentLobbySurfaceVisibility then
		updatePersistentLobbySurfaceVisibility()
	end
	if seated == true and stopIntroGuideFlow then
		onboardingTokens.intro += 1
		stopIntroGuideFlow("seated")
	end
	if seated ~= true then
		onboardingTokens.seated += 1
	end
end

local function setSeatPresentationMatchActive(active)
	seatPresentationState.matchActive = active == true
	if seatUIComponent then
		seatUIComponent:SetMatchActive(active == true)
	end
	if updatePersistentLobbySurfaceVisibility then
		updatePersistentLobbySurfaceVisibility()
	end
	if active == true and stopIntroGuideFlow then
		onboardingTokens.intro += 1
		stopIntroGuideFlow("match_active")
	end
	if active == true then
		onboardingTokens.seated += 1
		onboardingTokens.postRound += 1
	end
end

local function setSeatPresentationChoiceActive(active)
	seatPresentationState.choiceActive = active == true
	if seatUIComponent then
		seatUIComponent:SetChoiceActive(active == true)
	end
	if updatePersistentLobbySurfaceVisibility then
		updatePersistentLobbySurfaceVisibility()
	end
	if active == true and stopIntroGuideFlow then
		onboardingTokens.intro += 1
		stopIntroGuideFlow("choice_active")
	end
	if active == true then
		onboardingTokens.seated += 1
		onboardingTokens.postRound += 1
	end
end

local function trackMonetizationPrompt(source, productId)
	activeMonetizationPrompt.source = tostring(source or "")
	activeMonetizationPrompt.productId = tonumber(productId)
end

local function clearTrackedMonetizationPrompt(source)
	if source == nil or activeMonetizationPrompt.source == source then
		activeMonetizationPrompt.source = nil
		activeMonetizationPrompt.productId = nil
	end
end

local function canResetShieldBuyPromptPending()
	return seatPresentationState.seated == true
		and seatPresentationState.matchActive ~= true
		and seatPresentationState.choiceActive ~= true
		and shieldUIState.armed ~= true
		and shieldUIState.count <= 0
end

local function setShieldCount(count)
	shieldUIState.count = math.max(0, tonumber(count) or 0)
	if shieldUIState.count <= 0 then
		shieldUIState.armed = false
		shieldUIState.pending = false
		clearTrackedMonetizationPrompt("ShieldSingle")
	elseif activeMonetizationPrompt.source == "ShieldSingle" then
		shieldUIState.pending = false
		clearTrackedMonetizationPrompt("ShieldSingle")
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
		clearTrackedMonetizationPrompt("ShieldSingle")
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

local function clearMonetizationPromptPending(source)
	clearTrackedMonetizationPrompt(source)
	if source == "ShieldSingle" then
		setShieldPending(false)
	elseif source == "RestoreOffer" and restoreOfferMenuComponent and restoreOfferMenuComponent.SetPurchasePending then
		restoreOfferMenuComponent:SetPurchasePending(false)
	end
end

local function clearShieldPresentation()
	shieldUIState.armed = false
	shieldUIState.pending = false
	clearTrackedMonetizationPrompt("ShieldSingle")
	if applyShieldUIState then
		applyShieldUIState()
	end
end

local function setRestoreOfferState(snapshot)
	restoreOfferState = type(snapshot) == "table" and snapshot or { Active = false }
	if applyRestoreOfferState then
		applyRestoreOfferState()
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
	if not statsHudComponent and StatsHUD then
		local ok, result = pcall(function()
			statsHudComponent = StatsHUD.new(gui)
		end)
		if not ok then
			warn("[CLIENT] StatsHUD.new FAILED:", result)
		end
	end
	if not restoreOfferMenuComponent and RestoreOfferMenu then
		local ok, result = pcall(function()
			restoreOfferMenuComponent = RestoreOfferMenu.new(gui, function()
				if RequestRestorePurchaseEvent then
					RequestRestorePurchaseEvent:FireServer()
				end
			end)
		end)
		if not ok then
			warn("[CLIENT] RestoreOfferMenu.new FAILED:", result)
		end
	end
	if not introGuideOverlayComponent and IntroGuideOverlay then
		local ok, result = pcall(function()
			introGuideOverlayComponent = IntroGuideOverlay.new(gui)
		end)
		if not ok then
			warn("[CLIENT] IntroGuideOverlay.new FAILED:", result)
		end
	end
	if not introTableGuideComponent and IntroTableGuide then
		local ok, result = pcall(function()
			introTableGuideComponent = IntroTableGuide.new()
		end)
		if not ok then
			warn("[CLIENT] IntroTableGuide.new FAILED:", result)
		end
	end
	if not vipPromoCardComponent and VIPPromoCard then
		local ok, result = pcall(function()
			vipPromoCardComponent = VIPPromoCard.new(gui, function()
				local vipGamePassId = monetizationSnapshot and monetizationSnapshot.GamePassId or getVIPGamePassId()
				if vipGamePassId > 0 then
					MarketplaceService:PromptGamePassPurchase(player, vipGamePassId)
				end
			end)
		end)
		if not ok then
			warn("[CLIENT] VIPPromoCard.new FAILED:", result)
		end
	end

	if applyShieldUIState then
		applyShieldUIState()
	end
	if applyStatsHudState then
		applyStatsHudState()
	end
	if applyMonetizationState then
		applyMonetizationState()
	end
	if applyRestoreOfferState then
		applyRestoreOfferState()
	end
	if applyLobbyLayout then
		applyLobbyLayout()
	end
	if updatePersistentLobbySurfaceVisibility then
		updatePersistentLobbySurfaceVisibility()
	end
	
	return gui
end

local function disconnectViewportSizeWatcher()
	if viewportSizeConnection then
		viewportSizeConnection:Disconnect()
		viewportSizeConnection = nil
	end
end

local function attachViewportSizeWatcher()
	disconnectViewportSizeWatcher()

	local camera = Workspace.CurrentCamera
	if camera then
		viewportSizeConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if applyLobbyLayout then
				applyLobbyLayout()
			end
		end)
	end

	if applyLobbyLayout then
		applyLobbyLayout()
	end
end

local function bindViewportLayoutWatcher()
	if viewportCameraConnection then
		return
	end

	viewportCameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		attachViewportSizeWatcher()
	end)

	attachViewportSizeWatcher()
end

local function isGamepadInputType(inputType)
	return typeof(inputType) == "EnumItem" and string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function shouldUseGamepadOnboardingCopy()
	local lastInputType = UserInputService:GetLastInputType()
	return UserInputService.GamepadEnabled and (isGamepadInputType(lastInputType) or not UserInputService.MouseEnabled)
end

local function scheduleOnboardingTip(key, text, duration, delaySeconds, predicate)
	onboardingTokens[key] = (onboardingTokens[key] or 0) + 1
	local token = onboardingTokens[key]

	task.delay(delaySeconds or 0, function()
		if onboardingTokens[key] ~= token then
			return
		end

		if predicate and not predicate() then
			return
		end

		getScreenGui()
		if toastComponent and toastComponent.Show then
			toastComponent:Show(text, duration or 3.5)
		end
	end)
end

local function stopIntroMovementWatcher()
	if introMovementWatcher then
		introMovementWatcher:Disconnect()
		introMovementWatcher = nil
	end
end

dismissIntroOverlay = function(_reason)
	if introOverlayDismissed then
		return
	end

	introOverlayDismissed = true
	stopIntroMovementWatcher()

	if introGuideOverlayComponent and introGuideOverlayComponent.Hide then
		introGuideOverlayComponent:Hide()
	end
end

stopIntroGuideFlow = function(_reason)
	dismissIntroOverlay("cleanup")

	if introTableGuideComponent and introTableGuideComponent.Stop then
		introTableGuideComponent:Stop()
	end
end

local function startIntroMovementWatcher()
	stopIntroMovementWatcher()

	introMovementWatcher = RunService.Heartbeat:Connect(function()
		if introOverlayDismissed or seatPresentationState.seated or seatPresentationState.matchActive or seatPresentationState.choiceActive then
			stopIntroMovementWatcher()
			return
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		if humanoid and humanoid.MoveDirection.Magnitude >= 0.1 then
			dismissIntroOverlay("movement")
		end
	end)
end

startIntroGuideFlow = function()
	if onboardingState.introShown then
		return
	end

	if seatPresentationState.seated or seatPresentationState.matchActive or seatPresentationState.choiceActive then
		return
	end

	onboardingState.introShown = true
	introOverlayDismissed = false

	getScreenGui()

	if introGuideOverlayComponent and introGuideOverlayComponent.Show then
		introGuideOverlayComponent:Show({
			title = "Go sit down to play!",
			body = "Walk to a table and sit to start a match.",
			showGamepadHint = shouldUseGamepadOnboardingCopy(),
			onConfirm = function()
				dismissIntroOverlay("confirm")
			end,
		})
	end

	if introTableGuideComponent and introTableGuideComponent.Start then
		introTableGuideComponent:Start(nil)
	end

	startIntroMovementWatcher()
end

local function scheduleIntroOnboarding()
	if onboardingState.introShown then
		return
	end

	onboardingTokens.intro = (onboardingTokens.intro or 0) + 1
	local token = onboardingTokens.intro
	task.delay(0.9, function()
		if onboardingTokens.intro ~= token then
			return
		end

		startIntroGuideFlow()
	end)
end

local function scheduleSeatedOnboarding()
	if onboardingState.seatedHintShown then
		return
	end

	onboardingState.seatedHintShown = true
	local message = "Invite friends or wait for someone to sit down with you!"
	if shouldUseGamepadOnboardingCopy() then
		message = "Invite friends or wait for someone to sit down with you! Use the D-pad or stick, then press A."
	end

	scheduleOnboardingTip("seated", message, 4.5, 0.4, function()
		return seatPresentationState.seated
			and not seatPresentationState.matchActive
			and not seatPresentationState.choiceActive
	end)
end

local function schedulePostRoundOnboarding(delaySeconds)
	if onboardingState.postRoundHintShown then
		return
	end

	onboardingState.postRoundHintShown = true
	scheduleOnboardingTip("postRound", "Save up money for upcoming chairs and climb the leaderboard!", 4.5, delaySeconds or 0.35, function()
		return not seatPresentationState.matchActive
			and not seatPresentationState.choiceActive
	end)
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
	if updatePersistentLobbySurfaceVisibility then
		updatePersistentLobbySurfaceVisibility()
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

applyStatsHudState = function()
	if not statsHudComponent then
		return
	end

	statsHudComponent:SetDisplay(lastKnownStats)
	if updatePersistentLobbySurfaceVisibility then
		updatePersistentLobbySurfaceVisibility()
	end
end

applyMonetizationState = function()
	if vipPromoCardComponent and vipPromoCardComponent.SetSnapshot then
		vipPromoCardComponent:SetSnapshot(monetizationSnapshot)
	end
	if updatePersistentLobbySurfaceVisibility then
		updatePersistentLobbySurfaceVisibility()
	end
end

applyLobbyLayout = function()
	local scale, inset = getLobbyLayoutMetrics()

	if statsHudComponent then
		if statsHudComponent.SetScale then
			statsHudComponent:SetScale(scale)
		end
		if statsHudComponent.SetPosition then
			statsHudComponent:SetPosition(UDim2.new(0, inset, 0.5, math.floor(LEFT_STACK_STATS_Y * scale)), Vector2.new(0, 0.5))
		end
	end

	if shieldInventoryUI then
		if shieldInventoryUI.SetScale then
			shieldInventoryUI:SetScale(scale)
		end
		if shieldInventoryUI.SetPosition then
			shieldInventoryUI:SetPosition(UDim2.new(0, inset, 0.5, math.floor(LEFT_STACK_SHIELDS_Y * scale)), Vector2.new(0, 0.5))
		end
	end

	if vipPromoCardComponent then
		if vipPromoCardComponent.SetScale then
			vipPromoCardComponent:SetScale(scale)
		end
		if vipPromoCardComponent.SetPosition then
			vipPromoCardComponent:SetPosition(UDim2.new(1, -inset, 0.5, 0), Vector2.new(1, 0.5))
		end
	end

	if seatUIComponent and seatUIComponent.SetScale then
		seatUIComponent:SetScale(scale)
	end
end

updatePersistentLobbySurfaceVisibility = function()
	local surfacesVisible = shouldShowPersistentLobbySurfaces()

	if statsHudComponent and statsHudComponent.SetVisible then
		statsHudComponent:SetVisible(surfacesVisible)
	end
	if shieldInventoryUI and shieldInventoryUI.SetVisible then
		shieldInventoryUI:SetVisible(surfacesVisible)
	end
	if vipPromoCardComponent and vipPromoCardComponent.SetVisible then
		vipPromoCardComponent:SetVisible(surfacesVisible and shouldShowVIPPromoCard())
	end
end

applyRestoreOfferState = function()
	warn(string.format(
		"[RESTORE_PROBE] applyRestoreOfferState hasMenu=%s willSetOffer=%s active=%s reason=%s roundId=%s",
		tostring(restoreOfferMenuComponent ~= nil),
		tostring(restoreOfferMenuComponent ~= nil),
		tostring(restoreOfferState and restoreOfferState.Active),
		tostring(restoreOfferState and restoreOfferState.Reason),
		tostring(restoreOfferState and restoreOfferState.RoundId)
	))
	if not restoreOfferMenuComponent then
		return
	end

	restoreOfferMenuComponent:SetOffer(restoreOfferState)
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
	onboardingTokens.seated += 1
	onboardingTokens.postRound += 1
	
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
	setSeatPresentationChoiceActive(true)
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

local function onPromptMonetizationProduct(payload)
	payload = type(payload) == "table" and payload or {}
	local productId = tonumber(payload.productId) or 0
	local source = tostring(payload.source or "")

	if productId <= 0 then
		warn("[CLIENT] PromptMonetizationProduct invalid productId for", source)
		clearMonetizationPromptPending(source)
		return
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not ok then
		warn("[CLIENT] PromptProductPurchase failed:", err)
		clearMonetizationPromptPending(source)
		return
	end

	trackMonetizationPrompt(source, productId)
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
	if userId ~= player.UserId then
		return
	end

	local trackedSource = activeMonetizationPrompt.source
	local trackedProductId = activeMonetizationPrompt.productId
	if type(trackedSource) ~= "string" or trackedSource == "" or trackedProductId ~= tonumber(productId) then
		return
	end

	if trackedSource == "ShieldSingle" then
		if wasPurchased ~= true and canResetShieldBuyPromptPending() then
			setShieldPending(false)
		end

		if wasPurchased ~= true then
			clearTrackedMonetizationPrompt("ShieldSingle")
		end
		return
	end

	clearTrackedMonetizationPrompt(trackedSource)
end)

-- Listeners (with logging)
if MatchStartEvent then
	MatchStartEvent.OnClientEvent:Connect(function()
		onboardingTokens.seated += 1
		onboardingTokens.postRound += 1
		if PromptController then
			PromptController.DisablePrompts()
		end
		-- UX FIX: Hide SeatUI during match
		setSeatPresentationMatchActive(true)
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
		setSeatPresentationMatchActive(false)
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
		setSeatPresentationMatchActive(true)
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
		setSeatPresentationChoiceActive(false)
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
		setSeatPresentationMatchActive(false)
		setSeatPresentationChoiceActive(false)
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
					setSeatPresentationMatchActive(false)
					setSeatPresentationChoiceActive(false)
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
	StatsUpdate.OnClientEvent:Connect(function(stats, updatePayload)
		setShieldCount(stats.Shields or 0)
		local previousStats = lastKnownStats
		local currentStats = snapshotPresentationStats(stats)
		lastKnownStats = currentStats
		if applyStatsHudState then
			applyStatsHudState()
		end

		if type(updatePayload) ~= "table" or updatePayload.kind ~= "round_result" then
			return
		end

		local cashDelta = tonumber(updatePayload.cashDelta) or 0
		local currentWins = tonumber(stats.Wins) or 0
		local currentStreak = tonumber(stats.Streak) or 0

		-- Ensure toast is available only for round-result presentation.
		if not toastComponent then
			getScreenGui() -- Initialize if needed
		end

		local message
		local duration
		if previousStats then
			local winsDelta = currentWins - (previousStats.Wins or 0)
			local streakBroken = (previousStats.Streak or 0) > 0 and currentStreak == 0

			if cashDelta > 0 and currentStreak >= 2 then
				message = string.format("+$%d | Streak %d", cashDelta, currentStreak)
				duration = 4
			elseif cashDelta > 0 then
				message = string.format("+$%d | Wins %d", cashDelta, currentWins)
				duration = 4
			elseif streakBroken then
				message = string.format("Streak broken | Wins %d", currentWins)
				duration = 3.5
			elseif winsDelta > 0 then
				message = string.format("Wins %d | Streak %d", currentWins, currentStreak)
				duration = 3
			else
				message = string.format("Round over | Wins %d | Streak %d", currentWins, currentStreak)
				duration = 3
			end
		else
			if cashDelta > 0 then
				message = string.format("+$%d | Wins %d | Streak %d", cashDelta, currentWins, currentStreak)
				duration = 4
			else
				message = string.format("Wins %d | Streak %d", currentWins, currentStreak)
				duration = 3
			end
		end

		if toastComponent then
			toastComponent:Show(message, duration)
		else
			warn("[CLIENT] toastComponent not available for StatsUpdate")
		end

		schedulePostRoundOnboarding((duration or 3) + 0.4)

		return
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

if PromptMonetizationProductEvent then
	PromptMonetizationProductEvent.OnClientEvent:Connect(function(payload)
		getScreenGui()
		onPromptMonetizationProduct(payload)
	end)
else
	warn("[CLIENT] PromptMonetizationProductEvent not found")
end

if MonetizationSnapshotEvent then
	MonetizationSnapshotEvent.OnClientEvent:Connect(function(snapshot)
		monetizationSnapshot = sanitizeMonetizationSnapshot(snapshot)
		getScreenGui()
		if applyMonetizationState then
			applyMonetizationState()
		end
		if applyLobbyLayout then
			applyLobbyLayout()
		end
	end)
else
	warn("[CLIENT] MonetizationSnapshotEvent not found")
end

if RestoreOfferStateEvent then
	RestoreOfferStateEvent.OnClientEvent:Connect(function(snapshot)
		warn(string.format(
			"[RESTORE_PROBE] RestoreOfferStateEvent active=%s reason=%s roundId=%s secondsRemaining=%s expiresAt=%s",
			tostring(snapshot and snapshot.Active),
			tostring(snapshot and snapshot.Reason),
			tostring(snapshot and snapshot.RoundId),
			tostring(snapshot and snapshot.SecondsRemaining),
			tostring(snapshot and snapshot.ExpiresAt)
		))
		getScreenGui()
		setRestoreOfferState(snapshot)
	end)
else
	warn("[CLIENT] RestoreOfferStateEvent not found")
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
		onboardingTokens.seated += 1
		onboardingTokens.postRound += 1

		if secondsRemaining > 0 then
			local message
			if secondsRemaining >= 4 then
				message = string.format("Vs %s. Starts in %d", opponentName, secondsRemaining)
			elseif secondsRemaining == 3 then
				message = string.format("Get ready. %s in 3", opponentName)
			elseif secondsRemaining == 2 then
				message = "Get ready. 2"
			else
				message = "Pick in 1"
			end
			toastComponent:Show(message, 1.5) -- Duration slightly longer than tick interval

			-- UX FIX: Keep SeatUI visible during countdown
			setSeatPresentationMatchActive(false) -- Explicitly false during countdown
			return
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
		setSeatPresentationMatchActive(false)
	end)
else
	warn("[CLIENT] MatchCountdownCancel not found")
end

-- Step B: MatchStartingNow Handler
if MatchStartingNow then
	MatchStartingNow.OnClientEvent:Connect(function()
		countdownActive = false
		onboardingTokens.intro += 1
		if stopIntroGuideFlow then
			stopIntroGuideFlow("match_starting_now")
		end
		setSeatPresentationMatchActive(true)
		
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
bindViewportLayoutWatcher()
if PromptController and PromptController.SeatedChanged then
	PromptController.SeatedChanged:Connect(function(isSeated)
		if not isSeated then
			clearShieldPresentation()
		end
		setSeatPresentationSeated(isSeated)
		if isSeated and applyShieldUIState then
			applyShieldUIState()
		end
		if isSeated then
			scheduleSeatedOnboarding()
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

scheduleIntroOnboarding()

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
