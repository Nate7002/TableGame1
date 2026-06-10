-- UX FIX B: Seated UI (Invite Friend + Leave Seat buttons)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)
local Toast = require(script.Parent.Toast)

local SeatUI = {}
SeatUI.__index = SeatUI

-- Constants
local FAST_HIDE_DURATION = 0.12 -- Step D: Fast hide duration
local SEAT_VISIBLE_POSITION = UDim2.new(0.5, 0, 1, -22)
local SEAT_HIDDEN_POSITION = UDim2.new(0.5, 0, 1, 84)
local SEAT_CARD_HEIGHT = 66
local SHIELD_HOVER_COLOR = Theme.Buttons.PrimaryHover
local SHIELD_BUY_IDLE_COLOR = Theme.Buttons.MintFill
local SHIELD_BUY_HOVER_COLOR = Theme.Buttons.MintHover

local function isGamepadInputType(inputType)
	return typeof(inputType) == "EnumItem" and string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function prefersGamepadSelection()
	local lastInputType = UserInputService:GetLastInputType()
	return UserInputService.GamepadEnabled and (isGamepadInputType(lastInputType) or not UserInputService.MouseEnabled)
end

function SeatUI.new(parentGui)
	local self = setmetatable({}, SeatUI)
	self._parent = parentGui
	self._frame = nil
	self._card = nil
	self._visible = false
	self._toast = Toast.new(parentGui)
	
	-- State flags
	self._isSeated = false
	self._matchActive = false
	self._choiceUIActive = false
	self._shieldArmedPending = false
	self._shieldArmed = false
	self._shieldCount = 0
	self._shieldMax = 0
	self._shieldHovering = false
	self._lastShieldRenderKey = nil
	
	-- Step E: Transient flag to prevent flicker during match start transition
	self._isTransitioningToMatch = false

	self._shieldBtn = nil
	self._shieldCountLabel = nil
	self._shieldGradient = nil
	self._shieldStroke = nil
	self._shieldShimmerTween = nil
	self._shieldShimmerToken = 0
	self._shieldShimmerActive = false
	self._scaleNode = nil
	self._scale = 1
	self._inviteBtn = nil
	self._leaveBtn = nil

	return self
end

-- State Setters
function SeatUI:SetSeated(seated)
	self._isSeated = seated

	if not seated then
		self._shieldHovering = false
		self._shieldArmedPending = false
		self:_applyShieldButtonState()
	end

	self:_updateVisibility()
end

function SeatUI:SetMatchActive(active)
	-- Step E: Ignore SetMatchActive(false) if we are in the middle of a fast ease-out to match
	if not active and self._isTransitioningToMatch then
		return
	end
	
	self._matchActive = active
	self:_updateVisibility()
end

function SeatUI:SetChoiceActive(active)
	self._choiceUIActive = active
	self:_updateVisibility()
end

function SeatUI:_updateVisibility()
	-- Show if seated AND not in match AND not in choice UI
	local shouldShow = self._isSeated and not self._matchActive and not self._choiceUIActive
	
	if shouldShow then
		self:Show()
	else
		self:Hide()
	end
end

function SeatUI:Show()
	if self._visible then return end
	self._visible = true
	
	-- Create UI if not exists
	if not self._frame then
		self:_createUI()
	end
	
	-- Animate in
	self._frame.Visible = true
	self._frame.Position = SEAT_HIDDEN_POSITION
	
	local tween = TweenService:Create(self._frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = SEAT_VISIBLE_POSITION
	})
	tween:Play()

	self:_applyShieldButtonState()
	self:_focusDefaultButton()
end

function SeatUI:Hide()
	if not self._visible then return end
	self._visible = false
	
	if not self._frame then return end
	self:_stopShieldShimmer()
	
	-- Animate out
	local tween = TweenService:Create(self._frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = SEAT_HIDDEN_POSITION
	})
	tween:Play()
	tween.Completed:Connect(function()
		if self._frame and not self._visible then
			self._frame.Visible = false
		end
	end)
	self:_clearFocus()
end

-- Step B: Implement EaseOutFast
function SeatUI:EaseOutFast()
	if not self._visible then return end
	self._visible = false
	
	-- Step E: Set transient flag
	self._isTransitioningToMatch = true
	task.delay(0.2, function()
		self._isTransitioningToMatch = false
	end)
	
	if not self._frame then return end
	self:_stopShieldShimmer()
	
	-- Fast animate out
	local tween = TweenService:Create(self._frame, TweenInfo.new(FAST_HIDE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = SEAT_HIDDEN_POSITION
	})
	tween:Play()
	tween.Completed:Connect(function()
		if self._frame and not self._visible then
			self._frame.Visible = false
		end
	end)
	self:_clearFocus()
end

function SeatUI:_clearFocus()
	local selectedObject = GuiService.SelectedObject
	if selectedObject and self._frame and selectedObject:IsDescendantOf(self._frame) then
		GuiService.SelectedObject = nil
	end
end

function SeatUI:_focusDefaultButton()
	if not prefersGamepadSelection() then
		return
	end

	local target = self._inviteBtn or self._shieldBtn or self._leaveBtn
	if not target then
		return
	end

	task.defer(function()
		if self._visible and self._frame and self._frame.Visible and target.Parent then
			GuiService.SelectedObject = target
		end
	end)
end

function SeatUI:_stopShieldShimmer()
	self._shieldShimmerToken += 1
	self._shieldShimmerActive = false

	if self._shieldShimmerTween then
		self._shieldShimmerTween:Cancel()
		self._shieldShimmerTween = nil
	end

	if self._shieldGradient then
		self._shieldGradient.Offset = Vector2.new(0, 0)
	end
end

function SeatUI:_startShieldShimmer()
	if self._shieldShimmerActive or not self._shieldGradient or not self._shieldGradient.Parent then
		return
	end

	self:_stopShieldShimmer()
	self._shieldShimmerActive = true
	local token = self._shieldShimmerToken

	local function run()
		if not self._shieldShimmerActive or self._shieldShimmerToken ~= token then
			return
		end
		if not self._shieldGradient or not self._shieldGradient.Parent then
			self._shieldShimmerActive = false
			return
		end

		self._shieldGradient.Offset = Vector2.new(-1, 0)
		local tween = TweenService:Create(self._shieldGradient, TweenInfo.new(1.15, Enum.EasingStyle.Linear), {
			Offset = Vector2.new(1, 0),
		})
		self._shieldShimmerTween = tween
		tween.Completed:Once(function()
			if self._shieldShimmerTween == tween then
				self._shieldShimmerTween = nil
			end
			if not self._shieldShimmerActive or self._shieldShimmerToken ~= token then
				return
			end
			task.delay(0.12, run)
		end)
		tween:Play()
	end

	run()
end

function SeatUI:_setButtonGradient(gradient, baseColor, accentColor)
	if not gradient then
		return
	end

	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Blend(baseColor, Color3.fromRGB(255, 255, 255), 0.2)),
		ColorSequenceKeypoint.new(0.55, accentColor or baseColor),
		ColorSequenceKeypoint.new(1, baseColor),
	})
end

function SeatUI:_createUI()
	local frame = Instance.new("Frame")
	frame.Name = "SeatUI"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(0, 0)
	frame.Position = SEAT_HIDDEN_POSITION
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Visible = false
	frame.SelectionGroup = true
	frame.ZIndex = 50
	frame.Parent = self._parent
	self._frame = frame

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, 0)
	card.AutomaticSize = Enum.AutomaticSize.X
	card.Size = UDim2.fromOffset(0, SEAT_CARD_HEIGHT)
	card.BackgroundColor3 = Theme.Surface.Base
	card.BorderSizePixel = 0
	card.ZIndex = 50
	card.Parent = frame
	self._card = card

	local scaleNode = Instance.new("UIScale")
	scaleNode.Name = "Scale"
	scaleNode.Scale = self._scale or 1
	scaleNode.Parent = card
	self._scaleNode = scaleNode

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Sizes.ChipRadius
	corner.Parent = card

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Surface.Base),
		ColorSequenceKeypoint.new(1, Theme.Surface.Glass),
	})
	gradient.Rotation = 90
	gradient.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border.Soft
	stroke.Transparency = 0.14
	stroke.Thickness = 2
	stroke.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = card
	
	-- Invite Friend Button
	local inviteBtn = self:_createButton("Invite Friend", function()
		self:_handleInviteFriend()
	end, {
		size = UDim2.fromOffset(122, 42),
		idleColor = Theme.Buttons.PrimaryFill,
		hoverColor = Theme.Buttons.PrimaryHover,
		textColor = Theme.Colors.Text,
		focusStrokeColor = Theme.Border.Focus,
	})
	inviteBtn.Parent = card
	self._inviteBtn = inviteBtn

	-- Use Shield Button
	self._shieldBtn = self:_createButton("Use Shield", function()
		self:_handleUseShield()
	end, {
		size = UDim2.fromOffset(138, 42),
		disableHoverColors = true
	})
	self._shieldBtn.Parent = card
	self._shieldGradient = self._shieldBtn:FindFirstChildOfClass("UIGradient")
	self._shieldStroke = self._shieldBtn:FindFirstChildOfClass("UIStroke")
	self._shieldBtn.MouseEnter:Connect(function()
		self._shieldHovering = true
		self:_applyShieldButtonState()
	end)
	self._shieldBtn.MouseLeave:Connect(function()
		self._shieldHovering = false
		self:_applyShieldButtonState()
	end)
	self._shieldBtn.SelectionGained:Connect(function()
		self._shieldHovering = true
		self:_applyShieldButtonState()
	end)
	self._shieldBtn.SelectionLost:Connect(function()
		self._shieldHovering = false
		self:_applyShieldButtonState()
	end)

	local shieldCountLabel = Instance.new("TextLabel")
	shieldCountLabel.Name = "ShieldCountLabel"
	shieldCountLabel.BackgroundTransparency = 1
	shieldCountLabel.Size = UDim2.new(0, 48, 0, 12)
	shieldCountLabel.AnchorPoint = Vector2.new(1, 1)
	shieldCountLabel.Position = UDim2.new(1, -6, 1, -4)
	shieldCountLabel.Font = Theme.Font.Body
	shieldCountLabel.Text = "0/0"
	shieldCountLabel.TextColor3 = Theme.Colors.TextDim
	shieldCountLabel.TextSize = Theme.Sizes.TextSmall
	shieldCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	shieldCountLabel.ZIndex = 61
	shieldCountLabel.Parent = self._shieldBtn
	self._shieldCountLabel = shieldCountLabel

	self:_applyShieldButtonState()
	
	-- Leave Seat Button
	local leaveBtn = self:_createButton("Leave Seat", function()
		self:_handleLeaveSeat()
	end, {
		size = UDim2.fromOffset(122, 42),
		idleColor = Theme.Buttons.SecondaryFill,
		hoverColor = Theme.Buttons.SecondaryHover,
		textColor = Theme.Colors.Text,
		focusStrokeColor = Theme.Colors.CoralDanger,
	})
	leaveBtn.Parent = card
	self._leaveBtn = leaveBtn

	inviteBtn.NextSelectionRight = self._shieldBtn
	self._shieldBtn.NextSelectionLeft = inviteBtn
	self._shieldBtn.NextSelectionRight = leaveBtn
	leaveBtn.NextSelectionLeft = self._shieldBtn
end

function SeatUI:SetScale(scale)
	self._scale = math.max(0.5, tonumber(scale) or 1)
	if self._scaleNode then
		self._scaleNode.Scale = self._scale
	end
end

function SeatUI:_createButton(text, callback, options)
	options = options or {}
	local idleColor = options.idleColor or Theme.Buttons.SecondaryFill
	local hoverColor = options.hoverColor or Theme.Buttons.PrimaryHover
	local textColor = options.textColor or Theme.Colors.Text
	local focusStrokeColor = options.focusStrokeColor or Theme.Border.Focus
	local buttonSize = options.size or UDim2.fromOffset(132, 44)

	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = idleColor
	btn.BorderSizePixel = 0
	btn.Size = buttonSize
	btn.Font = Theme.Font.Body
	btn.Text = text
	btn.TextColor3 = textColor
	btn.TextSize = Theme.Sizes.TextBody
	btn.TextScaled = true
	btn.AutoButtonColor = false
	btn.Selectable = true
	btn.ZIndex = 60 -- INCREASED
	
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = Theme.Sizes.TextBody
	textConstraint.MinTextSize = 10
	textConstraint.Parent = btn

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Sizes.ButtonRadius
	corner.Parent = btn

	local gradient = Instance.new("UIGradient")
	gradient.Name = "Gradient"
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Blend(idleColor, Color3.fromRGB(255, 255, 255), 0.14)),
		ColorSequenceKeypoint.new(1, idleColor),
	})
	gradient.Rotation = 90
	gradient.Parent = btn
	
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = Theme.Border.Soft
	stroke.Transparency = 0.18
	stroke.Thickness = 2
	stroke.Parent = btn
	
	if not options.disableHoverColors then
		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = hoverColor
			stroke.Color = focusStrokeColor
			stroke.Thickness = Theme.Stroke.FocusThickness
		end)

		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = idleColor
			stroke.Color = Theme.Border.Soft
			stroke.Thickness = 2
		end)

		btn.SelectionGained:Connect(function()
			btn.BackgroundColor3 = hoverColor
			stroke.Color = focusStrokeColor
			stroke.Thickness = Theme.Stroke.FocusThickness
		end)

		btn.SelectionLost:Connect(function()
			btn.BackgroundColor3 = idleColor
			stroke.Color = Theme.Border.Soft
			stroke.Thickness = 2
		end)
	end
	
	-- Click handler
	btn.Activated:Connect(function()
		if callback then
			callback()
		end
	end)
	
	return btn
end

function SeatUI:_applyShieldButtonState()
	if not self._shieldBtn then return end

	local shieldMax = math.max(0, tonumber(self._shieldMax) or 0)
	local countText = string.format("%d/%d", self._shieldCount, shieldMax)
	local isBuyingState = self._shieldCount <= 0 and not self._shieldArmed and not self._shieldArmedPending
	local baseColor = Theme.Buttons.SecondaryFill
	local focusColor = SHIELD_HOVER_COLOR
	if self._shieldCountLabel then
		self._shieldCountLabel.Text = countText
		self._shieldCountLabel.TextColor3 = isBuyingState and Theme.Colors.Success or Theme.Colors.TextDim
	end

	if self._shieldArmed then
		self:_stopShieldShimmer()
		self._shieldBtn.Text = "Shield Armed"
		self._shieldBtn.Active = false
		self._shieldBtn.AutoButtonColor = false
		self._shieldBtn.Selectable = false
		baseColor = Theme.Surface.Tinted
		self._shieldBtn.BackgroundColor3 = baseColor
		if self._shieldStroke then
			self._shieldStroke.Color = Theme.Border.Soft
			self._shieldStroke.Thickness = 2
		end
	else
		self._shieldBtn.Text = isBuyingState and "Buy Shield" or "Use Shield"
		self._shieldBtn.Active = not self._shieldArmedPending
		self._shieldBtn.AutoButtonColor = false
		self._shieldBtn.Selectable = not self._shieldArmedPending

		if isBuyingState then
			baseColor = self._shieldHovering and SHIELD_BUY_HOVER_COLOR or SHIELD_BUY_IDLE_COLOR
			focusColor = Theme.Blend(baseColor, Color3.fromRGB(255, 255, 255), 0.18)
			self._shieldBtn.BackgroundColor3 = baseColor
			if self._shieldStroke then
				self._shieldStroke.Color = Theme.Colors.Success
				self._shieldStroke.Thickness = self._shieldHovering and Theme.Stroke.FocusThickness or 2
			end
			self:_setButtonGradient(self._shieldGradient, baseColor, Theme.Blend(Theme.Colors.Success, Color3.fromRGB(255, 255, 255), 0.35))
			self:_startShieldShimmer()
		elseif self._shieldArmedPending then
			self:_stopShieldShimmer()
			baseColor = Theme.Blend(Theme.Surface.Base, Theme.Colors.Warning, 0.2)
			self._shieldBtn.BackgroundColor3 = baseColor
			if self._shieldStroke then
				self._shieldStroke.Color = Theme.Colors.Warning
				self._shieldStroke.Thickness = 2
			end
			self:_setButtonGradient(self._shieldGradient, baseColor, Theme.Colors.Warning)
		elseif self._shieldHovering then
			self:_stopShieldShimmer()
			baseColor = SHIELD_HOVER_COLOR
			self._shieldBtn.BackgroundColor3 = baseColor
			if self._shieldStroke then
				self._shieldStroke.Color = Theme.Border.Focus
				self._shieldStroke.Thickness = Theme.Stroke.FocusThickness
			end
			self:_setButtonGradient(self._shieldGradient, baseColor, Theme.Blend(baseColor, Color3.fromRGB(255, 255, 255), 0.22))
		else
			self:_stopShieldShimmer()
			self._shieldBtn.BackgroundColor3 = baseColor
			if self._shieldStroke then
				self._shieldStroke.Color = Theme.Border.Soft
				self._shieldStroke.Thickness = 2
			end
			self:_setButtonGradient(self._shieldGradient, baseColor, Theme.Blend(baseColor, Color3.fromRGB(255, 255, 255), 0.14))
		end
	end

	if self._shieldArmed then
		self:_setButtonGradient(self._shieldGradient, baseColor, Theme.Blend(baseColor, Color3.fromRGB(255, 255, 255), 0.14))
	end

	if GuiService.SelectedObject == self._shieldBtn and not self._shieldBtn.Selectable then
		GuiService.SelectedObject = self._leaveBtn or self._inviteBtn
	end

	self._lastShieldRenderKey = string.format("%s|%s|armed=%s|pending=%s",
		self._shieldBtn.Text,
		countText,
		tostring(self._shieldArmed),
		tostring(self._shieldArmedPending)
	)
end

function SeatUI:SetShieldState(state)
	state = state or {}
	self._shieldCount = math.max(0, tonumber(state.count) or 0)
	self._shieldMax = math.max(0, tonumber(state.max) or self._shieldMax or 0)
	self._shieldArmed = state.armed == true
	self._shieldArmedPending = state.pending == true
	self:_applyShieldButtonState()
end

function SeatUI:SetShieldCount(count)
	self:SetShieldState({
		count = count,
		max = self._shieldMax,
		armed = self._shieldArmed,
		pending = self._shieldArmedPending
	})
end

function SeatUI:SetShieldMax(max)
	self:SetShieldState({
		count = self._shieldCount,
		max = max,
		armed = self._shieldArmed,
		pending = self._shieldArmedPending
	})
end

function SeatUI:SetShieldArmed(armed)
	self:SetShieldState({
		count = self._shieldCount,
		max = self._shieldMax,
		armed = armed,
		pending = self._shieldArmedPending
	})
end

function SeatUI:SetShieldPending(pending)
	self:SetShieldState({
		count = self._shieldCount,
		max = self._shieldMax,
		armed = self._shieldArmed,
		pending = pending
	})
end

function SeatUI:_handleUseShield()
	if self._shieldArmedPending or self._shieldArmed then return end
	self:SetShieldPending(true)

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		self:SetShieldPending(false)
		warn("[SeatUI] Remotes folder not found")
		return
	end

	local shieldRemote = remotes:FindFirstChild("UseShield")
	if not shieldRemote then
		self:SetShieldPending(false)
		warn("[SeatUI] UseShield remote not found")
		return
	end

	shieldRemote:FireServer()
end

function SeatUI:_handleInviteFriend()
	-- Try to use SocialService (only works in published games)
	local success, err = pcall(function()
		local player = Players.LocalPlayer
		SocialService:PromptGameInvite(player)
	end)
	
	if not success then
		-- Fallback: show toast
		self._toast:Show("Invite is only available in published game.", 3)
		warn("[SeatUI] SocialService:PromptGameInvite failed:", err)
	end
end

function SeatUI:_handleLeaveSeat()
	-- Fire remote to server
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		warn("[SeatUI] Remotes folder not found")
		return
	end
	
	local leaveSeatRemote = remotes:FindFirstChild("LeaveSeat")
	if not leaveSeatRemote then
		warn("[SeatUI] LeaveSeat remote not found")
		return
	end
	
	leaveSeatRemote:FireServer()
	
	-- Hide UI immediately
	self:Hide()
end

function SeatUI:Destroy()
	self:_stopShieldShimmer()
	self:Hide()
	if self._frame then
		self._frame:Destroy()
		self._frame = nil
	end
	if self._toast then
		self._toast:Destroy()
		self._toast = nil
	end
end

return SeatUI
