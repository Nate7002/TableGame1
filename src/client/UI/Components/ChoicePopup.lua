local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)
local CountdownWidget = require(script.Parent.CountdownWidget)
local AnimatedBackgroundController = require(script.Parent.Parent.AnimatedBackgroundController)
local FxService = require(script.Parent.Parent.FxService)
local CinematicController = require(script.Parent.Parent.CinematicController)

-- Safe requires for UI Animations
local AnimationRuntime
local Anim_Hover
local Anim_Press
local Anim_Ripple

local function safeRequire(moduleInstance, name)
	if not moduleInstance then
		warn("[ChoicePopup] Missing module instance for: " .. tostring(name))
		return nil
	end
	
	local success, result = pcall(function()
		return require(moduleInstance)
	end)
	
	if success then
		return result
	else
		warn("[ChoicePopup] Failed to load animation module: " .. tostring(name) .. " - " .. tostring(result))
		return nil
	end
end

-- Try to load UIAnimations by INSTANCE
local success, result = pcall(function()
	local UIAnimations = ReplicatedStorage:WaitForChild("UIAnimations", 2)
	if UIAnimations then
		local Modules = UIAnimations:WaitForChild("Modules", 2)
		if Modules then
			AnimationRuntime = safeRequire(Modules:WaitForChild("AnimationRuntime", 2), "AnimationRuntime")
			Anim_Hover = safeRequire(Modules:WaitForChild("Frame_ScaleDown", 2), "Frame_ScaleDown")
			Anim_Press = safeRequire(Modules:WaitForChild("ImageButton_PressDown", 2), "ImageButton_PressDown")
			Anim_Ripple = safeRequire(Modules:WaitForChild("ImageButton_RippleClick", 2), "ImageButton_RippleClick")
		end
	end
end)
if not success then
	warn("[ChoicePopup] UIAnimations folder missing or failed to load: " .. tostring(result))
end

if not AnimationRuntime then
	warn("[ChoicePopup] AnimationRuntime missing -> animations disabled")
end

local ChoicePopup = {}
ChoicePopup.__index = ChoicePopup

-- Blur state for popup (NO FOV changes)
local popupBlur = nil

-- Helper: Apply blur when popup shows
local function applyPopupEffects()
	pcall(function()
		local lighting = game:GetService("Lighting")
		popupBlur = lighting:FindFirstChild("DoubleDownBlur")
		if not popupBlur then
			popupBlur = Instance.new("BlurEffect")
			popupBlur.Name = "DoubleDownBlur"
			popupBlur.Size = 0
			popupBlur.Enabled = true
			popupBlur.Parent = lighting
		end
		
		popupBlur.Size = 16
		-- NO FOV changes anywhere
	end)
end

-- Helper: Remove blur when popup closes
local function removePopupEffects()
	pcall(function()
		if popupBlur then
			popupBlur.Size = 0
			popupBlur.Enabled = false
		end
	end)
end

-- Helper: Play Sound
local function playFxSound(soundName)
	local fxFolder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FX")
	if not fxFolder then return end
	
	local soundTemplate = fxFolder:FindFirstChild(soundName)
	if soundTemplate and soundTemplate:IsA("Sound") then
		local sound = soundTemplate:Clone()
		sound.Parent = game:GetService("SoundService") -- Preferred parent for global UI sounds
		sound.TimePosition = 0
		sound:Play()
		Debris:AddItem(sound, sound.TimeLength + 0.5)
	end
end

local function isGamepadInputType(inputType)
	return typeof(inputType) == "EnumItem" and string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function prefersGamepadSelection()
	local lastInputType = UserInputService:GetLastInputType()
	return UserInputService.GamepadEnabled and (isGamepadInputType(lastInputType) or not UserInputService.MouseEnabled)
end

local OPTION_ACCENTS = {
	SPLIT = Theme.Colors.AuroraCyan,
	STEAL = Theme.Colors.HotPink,
	DOUBLEDOWN = Theme.Colors.RewardGold,
}

local OPTION_FALLBACKS = {
	Theme.Colors.AuroraCyan,
	Theme.Colors.HotPink,
	Theme.Colors.RewardGold,
}

local function getOptionAccent(optionId, optionIndex)
	local normalizedId = string.upper(tostring(optionId or ""))
	return OPTION_ACCENTS[normalizedId] or OPTION_FALLBACKS[optionIndex] or Theme.Colors.AuroraCyan
end

local function extractRewardInfo(rawDescription)
	local descText = type(rawDescription) == "string" and rawDescription or ""
	local rewardText = descText:gsub("<[^>]->", ""):match("Reward:%s*%$[%d,]+")
	local cleanedDesc = descText:gsub("^<font.-</font>%s*\n?", "")
	cleanedDesc = cleanedDesc:gsub("^%s+", "")
	return rewardText, cleanedDesc
end

-- Fallback animation helper if Runtime fails mult-reg or is missing
local function applyFallbackAnimations(btn)
	-- Store original size if not present
	if not btn:GetAttribute("OrigScale") then
		btn:SetAttribute("OrigScale", 1) 
	end
	
	-- Hover Tween
	btn.MouseEnter:Connect(function()
		local t = TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(0.92, 0.92)
		})
		t:Play()
	end)
	
	btn.MouseLeave:Connect(function()
		local t = TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(1, 1)
		})
		t:Play()
	end)
	
	-- Press Tween (One-shot)
	btn.Activated:Connect(function()
		local t1 = TweenService:Create(btn, TweenInfo.new(0.05, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(0.96, 0.96)
		})
		t1:Play()
		t1.Completed:Wait()
		local t2 = TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(1, 1)
		})
		t2:Play()
	end)
end

function ChoicePopup.new(parentGui)
	local self = setmetatable({}, ChoicePopup)
	self._parent = parentGui
	
	-- Create static structure (hidden initially)
	local overlay = Instance.new("Frame")
	overlay.Name = "ChoiceOverlay"
	overlay.BackgroundColor3 = Color3.fromRGB(27, 55, 97)
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.SelectionGroup = true
	overlay.ZIndex = 1 -- Dimmer Layer
	overlay.Visible = false
	overlay.Parent = parentGui
	self._overlay = overlay
	
	-- Popup Frame
	local frame = Instance.new("Frame")
	frame.Name = "Popup"
	frame.BackgroundColor3 = Theme.Surface.Base
	frame.Size = UDim2.fromOffset(480, 336)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.BackgroundTransparency = 1
	frame.ZIndex = 10 -- Card Layer (Above Background)
	frame.Parent = overlay
	self._frame = frame
	self._originalSize = frame.Size
	
	Instance.new("UICorner", frame).CornerRadius = Theme.Sizes.CornerRadius

	local frameGradient = Instance.new("UIGradient")
	frameGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Surface.Base),
		ColorSequenceKeypoint.new(1, Theme.Surface.Glass),
	})
	frameGradient.Rotation = 90
	frameGradient.Parent = frame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Theme.Border.Soft
	frameStroke.Transparency = 0.08
	frameStroke.Thickness = 2
	frameStroke.Parent = frame

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.74
	shine.BorderSizePixel = 0
	shine.Position = UDim2.new(0, 16, 0, 12)
	shine.Size = UDim2.new(1, -32, 0, 24)
	shine.ZIndex = 12
	shine.Parent = frame

	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0, 12)
	shineCorner.Parent = shine
	
	-- Animated Background (Placeholder for runtime attachment)
	self._bgCleanup = nil
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -182, 0, 44)
	title.Position = UDim2.new(0, 24, 0, 22)
	title.Font = Theme.Font.Header
	title.TextColor3 = Theme.Colors.Text
	title.TextSize = Theme.Sizes.TextHeader + 4
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 20 -- Text Layer
	title.Parent = frame
	self._titleLabel = title
	
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Theme.Stroke.Color
	titleStroke.Transparency = 0.72
	titleStroke.Thickness = Theme.Stroke.Thickness
	titleStroke.Parent = title

	local rewardBadge = Instance.new("Frame")
	rewardBadge.Name = "RewardBadge"
	rewardBadge.BackgroundColor3 = Theme.Blend(Theme.Surface.Base, Theme.Colors.RewardGold, 0.32)
	rewardBadge.BorderSizePixel = 0
	rewardBadge.Position = UDim2.new(0, 24, 0, 72)
	rewardBadge.Size = UDim2.fromOffset(164, 32)
	rewardBadge.Visible = false
	rewardBadge.ZIndex = 18
	rewardBadge.Parent = frame
	self._rewardBadge = rewardBadge

	local rewardCorner = Instance.new("UICorner")
	rewardCorner.CornerRadius = UDim.new(0, 12)
	rewardCorner.Parent = rewardBadge

	local rewardStroke = Instance.new("UIStroke")
	rewardStroke.Color = Theme.Colors.RewardGold
	rewardStroke.Transparency = 0.08
	rewardStroke.Thickness = 2
	rewardStroke.Parent = rewardBadge

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "Label"
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Size = UDim2.new(1, -18, 1, 0)
	rewardLabel.Position = UDim2.new(0, 12, 0, 0)
	rewardLabel.Font = Theme.Font.Body
	rewardLabel.Text = "Reward: $0"
	rewardLabel.TextColor3 = Theme.Colors.Text
	rewardLabel.TextSize = Theme.Sizes.TextSmall
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.ZIndex = 19
	rewardLabel.Parent = rewardBadge
	self._rewardBadgeLabel = rewardLabel
	
	-- Description
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, -48, 0, 46)
	desc.Position = UDim2.new(0, 24, 0, 112)
	desc.Font = Theme.Font.BodyAlt
	desc.TextColor3 = Theme.Colors.TextDim
	desc.TextSize = Theme.Sizes.TextBody
	desc.TextWrapped = true
	desc.RichText = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.ZIndex = 20 -- Text Layer
	desc.Parent = frame
	self._descLabel = desc
	
	local descStroke = Instance.new("UIStroke")
	descStroke.Color = Theme.Stroke.Color
	descStroke.Transparency = 0.86
	descStroke.Thickness = 1
	descStroke.Parent = desc
	
	-- Options Container
	local optionsContainer = Instance.new("Frame")
	optionsContainer.Name = "Options"
	optionsContainer.BackgroundTransparency = 1
	optionsContainer.Size = UDim2.new(1, -48, 0, 78)
	optionsContainer.Position = UDim2.new(0, 24, 1, -104)
	optionsContainer.ZIndex = 20 -- Buttons Layer
	optionsContainer.Parent = frame
	self._optionsContainer = optionsContainer
	
	local uiList = Instance.new("UIListLayout")
	uiList.FillDirection = Enum.FillDirection.Horizontal
	uiList.Padding = UDim.new(0, 12)
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiList.Parent = optionsContainer
	
	-- Timer Widget
	self._countdown = CountdownWidget.new(frame)
	self._countdown:SetPosition(UDim2.new(1, -24, 0, 22), Vector2.new(1, 0))
	
	-- Status Label (for "Waiting on opponent..." state)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, -48, 0, 28)
	statusLabel.Position = UDim2.new(0, 24, 0, 198)
	statusLabel.Font = Theme.Font.BodyAlt
	statusLabel.TextColor3 = Theme.Colors.Text
	statusLabel.TextSize = Theme.Sizes.TextSmall + 2
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.TextYAlignment = Enum.TextYAlignment.Center
	statusLabel.ZIndex = 25
	statusLabel.Visible = false
	statusLabel.Parent = frame
	self._statusLabel = statusLabel
	
	local statusStroke = Instance.new("UIStroke")
	statusStroke.Color = Theme.Stroke.Color
	statusStroke.Transparency = Theme.Stroke.Transparency
	statusStroke.Thickness = Theme.Stroke.Thickness
	statusStroke.Parent = statusLabel
	
	self._connections = {}
	self._isClosing = false
	self._isWaiting = false
	self._currentTimerId = 0
	self._reminderTask = nil -- UX FIX C: Track reminder task
	self._opponentPickedConnection = nil -- UX FIX C: Track opponent picked listener
	self._reminderSound = nil -- Track reminder sound instance
	self._optionButtons = {}
	
	return self
end

function ChoicePopup:_setButtonHighlight(btn, highlighted)
	if not btn or self._isWaiting then
		return
	end

	local idleFill = btn:GetAttribute("IdleFill") or Theme.Buttons.SecondaryFill
	local focusFill = btn:GetAttribute("FocusFill") or Theme.Buttons.PrimaryFill
	local accentColor = btn:GetAttribute("AccentColor") or Theme.Border.Soft
	local stroke = btn:FindFirstChild("Stroke")

	btn.BackgroundColor3 = highlighted and focusFill or idleFill
	btn.BackgroundTransparency = 0

	if stroke and stroke:IsA("UIStroke") then
		if highlighted then
			stroke.Color = Theme.Border.Focus
			stroke.Transparency = 0.04
			stroke.Thickness = Theme.Stroke.FocusThickness
		else
			stroke.Color = accentColor
			stroke.Transparency = 0.16
			stroke.Thickness = 2
		end
	end
end

function ChoicePopup:_wireOptionSelection()
	for index, btn in ipairs(self._optionButtons) do
		btn.NextSelectionLeft = self._optionButtons[index - 1] or btn
		btn.NextSelectionRight = self._optionButtons[index + 1] or btn
	end
end

function ChoicePopup:_focusDefaultOption()
	if not prefersGamepadSelection() then
		return
	end

	local firstButton = self._optionButtons[1]
	if not firstButton then
		return
	end

	task.defer(function()
		if self._overlay and self._overlay.Visible and not self._isClosing and not self._isWaiting and firstButton.Parent then
			GuiService.SelectedObject = firstButton
		end
	end)
end

function ChoicePopup:Show(payload, onResponse)
	-- Reset state but DON'T call Hide() (which destroys overlay)
	-- Only reset closing/waiting flags
	self._isClosing = false
	self._isWaiting = false
	self._overlay.Visible = true
	
	-- UX FIX C: Cancel any existing reminder
	self:_cancelReminder()
	
	-- Hide status label initially
	if self._statusLabel then
		self._statusLabel.Visible = false
	end
	
	-- Apply blur when popup appears (not during cinematic)
	applyPopupEffects()
	
	-- Attach Animated Background (only if not already attached)
	local tint = AnimatedBackgroundController.GetTintColor(payload.rarity or "Common")
	if not self._bgCleanup then
		-- First time: create background
		self._bgCleanup = AnimatedBackgroundController.AttachAnimatedBackground(self._overlay, {
			speed = 0.05,
			tintColor = tint
		})
	else
		-- Update existing background tint if needed (reuse overlay)
		-- Background controller should handle tint updates internally
		-- If it doesn't, we'll need to update it, but for now just reuse
	end
	
	-- Update Content
	local titleText = type(payload.title) == "string" and payload.title or ""
	local rawDescText = type(payload.description) == "string" and payload.description or ""
	local rewardText, descText = extractRewardInfo(rawDescText)
	if titleText == "" then
		titleText = "Make Your Pick"
	end
	if descText == "" then
		descText = "Choose before the timer ends. Winning rounds pays cash and builds streak."
	end
	self._titleLabel.Text = titleText
	self._descLabel.Text = descText
	if self._rewardBadge and self._rewardBadgeLabel then
		self._rewardBadge.Visible = rewardText ~= nil
		if rewardText then
			self._rewardBadgeLabel.Text = rewardText
			self._descLabel.Position = UDim2.new(0, 24, 0, 112)
		else
			self._rewardBadgeLabel.Text = ""
			self._descLabel.Position = UDim2.new(0, 24, 0, 92)
		end
	end
	
	-- Play Popup Sound (Server Controlled)
	if payload.sfx then
		FxService.Play(payload.sfx)
	end
	
	-- Clear Buttons
	for _, child in ipairs(self._optionsContainer:GetChildren()) do
		if child:IsA("Frame") or child:IsA("GuiObject") then
			if child:IsA("UIListLayout") then continue end
			child:Destroy()
		end
	end
	self._optionButtons = {}
	
	-- Create Buttons
	if payload.options then
		local count = #payload.options
		for optionIndex, opt in ipairs(payload.options) do
			self:CreateButton(opt, count, onResponse, optionIndex)
		end
	end
	self:_wireOptionSelection()
	self:_focusDefaultOption()
	
	-- Animate In
	self:AnimateIn()
	
	-- Timer
	self._currentTimerId += 1
	local timerId = self._currentTimerId
	
	if payload.endTime then
		self:StartSyncedTimer(payload.endTime, onResponse, timerId)
		self._countdown:SetVisible(true)
	elseif payload.timeout then
		self:StartTimer(payload.timeout, onResponse, timerId)
		self._countdown:SetVisible(true)
	else
		self._countdown:SetVisible(false)
	end
	
	-- UX FIX C: Listen for OpponentPicked
	if not self._opponentPickedConnection then
		local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if Remotes then
			local OpponentPicked = Remotes:FindFirstChild("OpponentPicked")
			if OpponentPicked then
				self._opponentPickedConnection = OpponentPicked.OnClientEvent:Connect(function(opponentName)
					-- Opponent picked first, schedule reminder after 3 seconds
					self:_scheduleReminder(opponentName)
				end)
			end
		end
	end
end

function ChoicePopup:CreateButton(option, count, onResponse, optionIndex)
	-- Wrapper for UIListLayout to hold space
	local wrapper = Instance.new("Frame")
	wrapper.Name = "Wrapper_" .. option.id
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = 20
	wrapper.ClipsDescendants = false -- Ensure button scale/ripple isn't aggressively clipped
	if count then
		wrapper.Size = UDim2.new(1/count, -12, 1, 0)
	else
		wrapper.Size = UDim2.new(0, 150, 1, 0)
	end
	wrapper.Parent = self._optionsContainer

	-- ImageButton Root
	local btn = Instance.new("ImageButton")
	local accentColor = getOptionAccent(option.id, optionIndex)
	local idleFill = Theme.Blend(Theme.Surface.Base, accentColor, 0.24)
	local focusFill = Theme.Blend(accentColor, Color3.fromRGB(255, 255, 255), 0.06)
	btn.Name = "Option_" .. option.id
	btn.BackgroundColor3 = idleFill
	btn.BackgroundTransparency = 0
	btn.AutoButtonColor = false -- We handle colors manually
	btn.Image = "" -- Blank for now
	btn.ScaleType = Enum.ScaleType.Stretch
	btn.Selectable = true
	btn.ZIndex = 20
	btn.ClipsDescendants = true -- Required for Ripple containment
	
	-- FIX: Anchor Center for proper scaling animations
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromScale(0.5, 0.5)
	btn.Size = UDim2.new(1, 0, 1, -10)
	
	-- Store original size attributes for dynamic animations
	btn:SetAttribute("OrigXScale", 1)
	btn:SetAttribute("OrigXOffset", 0)
	btn:SetAttribute("OrigYScale", 1)
	btn:SetAttribute("OrigYOffset", 0)
	btn:SetAttribute("AccentColor", accentColor)
	btn:SetAttribute("IdleFill", idleFill)
	btn:SetAttribute("FocusFill", focusFill)
	
	btn.Parent = wrapper
	
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Name = "Stroke"
	btnStroke.Color = accentColor
	btnStroke.Transparency = 0.16
	btnStroke.Thickness = 2
	btnStroke.Parent = btn
	
	Instance.new("UICorner", btn).CornerRadius = Theme.Sizes.ButtonRadius

	local btnGradient = Instance.new("UIGradient")
	btnGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Blend(Theme.Surface.Base, accentColor, 0.12)),
		ColorSequenceKeypoint.new(1, idleFill),
	})
	btnGradient.Rotation = 90
	btnGradient.Parent = btn

	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.BackgroundColor3 = accentColor
	accentBar.BorderSizePixel = 0
	accentBar.Size = UDim2.new(1, 0, 0, 5)
	accentBar.ZIndex = 24
	accentBar.Parent = btn
	
	-- Text Label
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = Theme.Font.Header
	label.Text = option.label
	label.TextColor3 = Theme.Colors.Text
	label.TextSize = Theme.Sizes.TextBody + 1
	label.TextScaled = false
	label.ZIndex = 30 -- Ensure label is above ripple (ripple will be ZIndex + 2 = 22, so 30 is safe)
	label.Parent = btn
	
	-- Interaction
	local connClick = btn.Activated:Connect(function() -- Activated is better for all devices
		if self._isClosing or self._isWaiting then return end
		
		playFxSound("ButtonClick") -- Play click sound
		
		-- Send choice to server
		if onResponse then onResponse(option.id) end
		
		-- Show waiting state instead of closing
		self:ShowWaitingState(option.label)
	end)
	table.insert(self._connections, connClick)
	
	-- Hover Sounds & Color
	local connEnter = btn.MouseEnter:Connect(function()
		if self._isWaiting then return end
		self:_setButtonHighlight(btn, true)
		playFxSound("ButtonHover") -- Play hover sound
	end)
	table.insert(self._connections, connEnter)
	
	local connLeave = btn.MouseLeave:Connect(function()
		if self._isWaiting then return end
		self:_setButtonHighlight(btn, false)
	end)
	table.insert(self._connections, connLeave)

	local connSelected = btn.SelectionGained:Connect(function()
		self:_setButtonHighlight(btn, true)
	end)
	table.insert(self._connections, connSelected)

	local connDeselected = btn.SelectionLost:Connect(function()
		self:_setButtonHighlight(btn, false)
	end)
	table.insert(self._connections, connDeselected)
	
	-- Animation Logic (Try Runtime, Fallback to Manual)
	local animsRegistered = false
	
	if AnimationRuntime then
		-- Register each animation separately (AnimationRuntime.run supports one config at a time)
		local boundCount = 0
		
		-- Hover animation (ScaleDown)
		if Anim_Hover then
			local cfg = table.clone(Anim_Hover)
			cfg.prop = "Size"
			cfg.val = UDim2.fromScale(0.92, 0.92)
			-- Config already has event = "hover", keep it
			local success, err = pcall(function()
				AnimationRuntime.run(btn, cfg)
			end)
			if success then
				boundCount = boundCount + 1
			else
				warn("[UIAnim] Hover animation failed:", err)
			end
		end
		
		-- Press animation (PressDown - override to use Size instead of Position)
		if Anim_Press then
			local cfg = table.clone(Anim_Press)
			cfg.prop = "Size" -- Override from Position to Size
			cfg.val = UDim2.fromScale(0.96, 0.96)
			cfg.reset = true -- Keep reset behavior
			cfg.resetTime = 0.1
			-- Config already has event = "click", keep it
			local success, err = pcall(function()
				AnimationRuntime.run(btn, cfg)
			end)
			if success then
				boundCount = boundCount + 1
			else
				warn("[UIAnim] Press animation failed:", err)
			end
		end
		
		-- Ripple animation (RippleClick)
		if Anim_Ripple then
			local cfg = table.clone(Anim_Ripple)
			-- Config already has event = "click" and prop = "Ripple", keep them
			local success, err = pcall(function()
				AnimationRuntime.run(btn, cfg)
			end)
			if success then
				boundCount = boundCount + 1
			else
				warn("[UIAnim] Ripple animation failed:", err)
			end
		end
		
		if boundCount > 0 then
			animsRegistered = true
		else
			warn("[UIAnim] No animations bound to", btn.Name)
		end

		-- UX FIX D: ZIndex fix for ripple (ensure ripple is visible but below label)
		if Anim_Ripple then
			-- Monitor for ripple frames and set their ZIndex
			local rippleMonitor
			rippleMonitor = btn.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("Frame") and descendant.Name ~= "Label" then
					-- This is likely a ripple frame
					descendant.ZIndex = 25 -- Between button (20) and label (30)
					
					-- Ensure ripple UICorner is also visible
					for _, child in ipairs(descendant:GetChildren()) do
						if child:IsA("UICorner") then
							child.Parent = descendant -- Ensure proper parenting
						end
					end
				end
			end)
			table.insert(self._connections, rippleMonitor)
		end
	end
	
	if not animsRegistered then
		applyFallbackAnimations(btn)
	end

	table.insert(self._optionButtons, btn)
end

function ChoicePopup:StartSyncedTimer(endTime, onResponse, timerId)
	local function update()
		if self._isClosing or self._currentTimerId ~= timerId then return end
		
		local remaining = math.ceil(endTime - workspace:GetServerTimeNow())
		if remaining < 0 then remaining = 0 end
		
		self._countdown:Update(remaining)
		
		if remaining <= 0 then
			self:Hide()
			if onResponse then onResponse(nil) end
			return
		end
		
		task.delay(0.2, update)
	end
	update()
end

function ChoicePopup:StartTimer(seconds, onResponse, timerId)
	local endTime = os.clock() + seconds
	local function update()
		if self._isClosing or self._currentTimerId ~= timerId then return end
		
		local remaining = math.ceil(endTime - os.clock())
		if remaining < 0 then remaining = 0 end
		
		self._countdown:Update(remaining)
		
		if remaining <= 0 then
			self:Hide()
			if onResponse then onResponse(nil) end
			return
		end
		
		task.delay(0.2, update)
	end
	update()
end

function ChoicePopup:AnimateIn()
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	
	self._overlay.BackgroundTransparency = 1
	local overlayTween = TweenService:Create(self._overlay, info, { BackgroundTransparency = 0.46 })
	overlayTween:Play()
	
	self._frame.Size = UDim2.fromOffset(442, 300)
	self._frame.BackgroundTransparency = 1
	
	local frameTween = TweenService:Create(self._frame, info, {
		Size = self._originalSize,
		BackgroundTransparency = 0 -- BasePanel handles color, this is container
	})
	frameTween:Play()
end

function ChoicePopup:ShowWaitingState(selectedOption)
	if self._isWaiting or self._isClosing then return end
	self._isWaiting = true
	local selectedLabel = tostring(selectedOption or "")
	if selectedLabel == "" then
		selectedLabel = "Choice"
	end
	
	-- UX FIX C: Cancel reminder when player picks
	self:_cancelReminder()
	
	-- Disable all buttons
	for _, child in ipairs(self._optionsContainer:GetChildren()) do
		if child:IsA("Frame") then
			local btn = child:FindFirstChildOfClass("ImageButton")
			if btn then
				local btnLabel = btn:FindFirstChild("Label")
				local isSelected = btnLabel and btnLabel:IsA("TextLabel") and btnLabel.Text == selectedLabel
				btn.Active = false
				btn.AutoButtonColor = false
				if isSelected then
					btn.BackgroundColor3 = btn:GetAttribute("FocusFill") or Theme.Buttons.PrimaryFill
					btn.BackgroundTransparency = 0
				else
					btn.BackgroundColor3 = btn:GetAttribute("IdleFill") or Theme.Buttons.SecondaryFill
					btn.BackgroundTransparency = 0.42
				end
			end
		end
	end

	if GuiService.SelectedObject and self._overlay and GuiService.SelectedObject:IsDescendantOf(self._overlay) then
		GuiService.SelectedObject = nil
	end
	
	-- Show waiting message
	if self._statusLabel then
		self._statusLabel.Text = string.format("Locked in: %s. Waiting for opponent.", selectedLabel)
		self._statusLabel.TextColor3 = Theme.Colors.Success
		self._statusLabel.Visible = true
	end
	
	-- Keep countdown visible (always visible, even after click)
	-- Countdown continues updating until round resolves
	if self._countdown then
		-- Ensure countdown stays visible
		self._countdown:SetVisible(true)
	end
end

-- UX FIX C: Schedule reminder after opponent picks
function ChoicePopup:_scheduleReminder(opponentName)
	-- Cancel any existing reminder
	self:_cancelReminder()
	
	-- Schedule reminder for 3 seconds
	self._reminderTask = task.delay(3, function()
		if not self._isClosing and not self._isWaiting then
			self:_showReminder()
		end
	end)
	
end

-- UX FIX C: Cancel reminder
function ChoicePopup:_cancelReminder()
	if self._reminderTask then
		task.cancel(self._reminderTask)
		self._reminderTask = nil
	end
	
	-- Stop sound if playing
	if self._reminderSound then
		pcall(function()
			self._reminderSound:Stop()
		end)
		self._reminderSound:Destroy()
		self._reminderSound = nil
	end
end

-- UX FIX C: Bulletproof sound playback helper
function ChoicePopup:_playReminderSound()
	-- stop prior instance if any (avoid stacking)
	if self._reminderSound then
		pcall(function()
			self._reminderSound:Stop()
		end)
		self._reminderSound:Destroy()
		self._reminderSound = nil
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fxFolder = assets and assets:FindFirstChild("FX")
	local template = fxFolder and fxFolder:FindFirstChild("ReminderSound")

	if not template or not template:IsA("Sound") then
		warn("[UI] ReminderSound missing or not a Sound at ReplicatedStorage.Assets.FX.ReminderSound")
		return
	end

	local s = template:Clone()
	s.Name = "ReminderSound_Playing"
	s.Parent = SoundService

	-- safety: ensure it's audible
	if s.Volume <= 0 then
		s.Volume = 0.8
	end
	s.Looped = false

	self._reminderSound = s

	s:Play()

	-- cleanup after it finishes (TimeLength can be 0 before load; give it a buffer)
	Debris:AddItem(s, math.max(2, s.TimeLength + 0.5))
end

-- Legacy reminder definition kept only to avoid noisy rewrite diffs.
function ChoicePopup:_showReminderLegacy()
	if not self._statusLabel then return end
	
	-- Update status label with strong message
	self._statusLabel.Text = "⚡ PICK AN OPTION! ⚡"
	self._statusLabel.TextColor3 = Color3.fromRGB(255, 85, 85) -- Red urgency
	self._statusLabel.Visible = true
	
	self:_playReminderSound()
	
	-- Pulse/shake animation
	local originalSize = self._frame.Size
	local originalPos = self._frame.Position
	
	-- Shake effect
	for i = 1, 3 do
		task.spawn(function()
			local offset = Vector2.new(math.random(-5, 5), math.random(-5, 5))
			self._frame.Position = originalPos + UDim2.fromOffset(offset.X, offset.Y)
			task.wait(0.05)
			self._frame.Position = originalPos
		end)
		task.wait(0.1)
	end
	
	-- Pulse effect on status label
	for i = 1, 2 do
		task.spawn(function()
			local tween1 = TweenService:Create(self._statusLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
				TextSize = Theme.Sizes.TextBody * 1.3
			})
			tween1:Play()
			tween1.Completed:Wait()
			
			local tween2 = TweenService:Create(self._statusLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
				TextSize = Theme.Sizes.TextBody
			})
			tween2:Play()
		end)
		task.wait(0.4)
	end
end

function ChoicePopup:_showReminder()
	if not self._statusLabel then
		return
	end

	self._statusLabel.Text = "PICK AN OPTION!"
	self._statusLabel.TextColor3 = Theme.Colors.Danger
	self._statusLabel.Visible = true

	self:_playReminderSound()

	local originalPos = self._frame.Position

	for _ = 1, 3 do
		task.spawn(function()
			local offset = Vector2.new(math.random(-5, 5), math.random(-5, 5))
			self._frame.Position = originalPos + UDim2.fromOffset(offset.X, offset.Y)
			task.wait(0.05)
			self._frame.Position = originalPos
		end)
		task.wait(0.1)
	end

	for _ = 1, 2 do
		task.spawn(function()
			local tween1 = TweenService:Create(self._statusLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
				TextSize = Theme.Sizes.TextBody * 1.3,
			})
			tween1:Play()
			tween1.Completed:Wait()

			local tween2 = TweenService:Create(self._statusLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
				TextSize = Theme.Sizes.TextBody,
			})
			tween2:Play()
		end)
		task.wait(0.4)
	end
end

function ChoicePopup:Hide()
	if self._isClosing then return end
	self._isClosing = true
	self._isWaiting = false
	self._currentTimerId += 1 -- Invalidates timers
	
	-- UX FIX C: Cancel reminder and disconnect listener
	self:_cancelReminder()
	if self._opponentPickedConnection then
		self._opponentPickedConnection:Disconnect()
		self._opponentPickedConnection = nil
	end
	
	-- Stop sound if playing
	if self._reminderSound then 
		self._reminderSound:Destroy()
		self._reminderSound = nil 
	end
	
	-- Remove blur when popup closes
	removePopupEffects()
	
	-- Cleanup background only when round ends (not between stages)
	if self._bgCleanup then
		self._bgCleanup()
		self._bgCleanup = nil
	end
	
	-- Disconnect inputs
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
	self._optionButtons = {}

	if GuiService.SelectedObject and self._overlay and GuiService.SelectedObject:IsDescendantOf(self._overlay) then
		GuiService.SelectedObject = nil
	end
	
	-- Close immediately (no animation delay on round resolve)
	self._overlay.Visible = false
end

function ChoicePopup:Destroy()
	self:Hide()
	if self._bgCleanup then self._bgCleanup() end
	if self._overlay then self._overlay:Destroy() end
	self._overlay = nil
end

return ChoicePopup
