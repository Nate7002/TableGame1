local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)

local RestoreOfferMenu = {}
RestoreOfferMenu.__index = RestoreOfferMenu

local function isGamepadInputType(inputType)
	return typeof(inputType) == "EnumItem" and string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function prefersGamepadSelection()
	local lastInputType = UserInputService:GetLastInputType()
	return UserInputService.GamepadEnabled and (isGamepadInputType(lastInputType) or not UserInputService.MouseEnabled)
end

local function buildMessage(snapshot)
	local preLossStreak = math.max(0, tonumber(snapshot and snapshot.PreLossStreak) or 0)
	local projectedRestoreStreak = math.max(0, tonumber(snapshot and snapshot.ProjectedRestoredStreak) or 0)

	if preLossStreak > 0 and projectedRestoreStreak > 0 then
		return string.format(
			"You lost a %d streak. Restore back to %d before the offer expires.",
			preLossStreak,
			projectedRestoreStreak
		)
	end

	if preLossStreak > 0 then
		return string.format(
			"You lost a %d streak. Restore is available for a short time only.",
			preLossStreak
		)
	end

	return "Restore is available for a short time only."
end

function RestoreOfferMenu.new(parentGui, onRestoreRequested)
	local self = setmetatable({}, RestoreOfferMenu)

	self._parent = parentGui
	self._onRestoreRequested = onRestoreRequested
	self._visible = false
	self._timerToken = 0

	local overlay = Instance.new("Frame")
	overlay.Name = "RestoreOfferOverlay"
	overlay.BackgroundColor3 = Color3.fromRGB(26, 59, 107)
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.SelectionGroup = true
	overlay.Visible = false
	overlay.ZIndex = 80
	overlay.Parent = parentGui
	self._overlay = overlay

	local frame = Instance.new("Frame")
	frame.Name = "RestoreOfferMenu"
	frame.BackgroundColor3 = Theme.Surface.Base
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(380, 180)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 81
	frame.Parent = overlay
	self._frame = frame
	self._baseSize = frame.Size

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Sizes.CornerRadius
	corner.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Surface.Base),
		ColorSequenceKeypoint.new(1, Theme.Surface.Glass),
	})
	gradient.Rotation = 90
	gradient.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border.Soft
	stroke.Transparency = 0.14
	stroke.Thickness = Theme.Stroke.Thickness
	stroke.Parent = frame

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.72
	shine.BorderSizePixel = 0
	shine.Position = UDim2.new(0, 12, 0, 10)
	shine.Size = UDim2.new(1, -24, 0, 24)
	shine.ZIndex = 81
	shine.Parent = frame

	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0, 12)
	shineCorner.Parent = shine

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 20, 0, 18)
	title.Size = UDim2.new(1, -110, 0, 28)
	title.Font = Theme.Font.Header
	title.Text = "Restore Streak"
	title.TextColor3 = Theme.Colors.Text
	title.TextSize = Theme.Sizes.TextHeader + 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 82
	title.Parent = frame
	self._titleLabel = title

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 20, 0, 58)
	body.Size = UDim2.new(1, -40, 0, 54)
	body.Font = Theme.Font.Body
	body.Text = ""
	body.TextColor3 = Theme.Colors.TextDim
	body.TextSize = Theme.Sizes.TextBody + 1
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.ZIndex = 82
	body.Parent = frame
	self._bodyLabel = body

	local countdownFrame = Instance.new("Frame")
	countdownFrame.Name = "Countdown"
	countdownFrame.BackgroundColor3 = Theme.Blend(Theme.Surface.Base, Theme.Colors.Warning, 0.26)
	countdownFrame.BorderSizePixel = 0
	countdownFrame.Position = UDim2.new(1, -20, 0, 18)
	countdownFrame.Size = UDim2.fromOffset(72, 34)
	countdownFrame.AnchorPoint = Vector2.new(1, 0)
	countdownFrame.ZIndex = 82
	countdownFrame.Parent = frame
	self._countdownFrame = countdownFrame

	local countdownCorner = Instance.new("UICorner")
	countdownCorner.CornerRadius = UDim.new(0, 8)
	countdownCorner.Parent = countdownFrame

	local countdownStroke = Instance.new("UIStroke")
	countdownStroke.Color = Theme.Colors.Warning
	countdownStroke.Transparency = 0.12
	countdownStroke.Thickness = 2
	countdownStroke.Parent = countdownFrame

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Value"
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Size = UDim2.fromScale(1, 1)
	countdownLabel.Font = Theme.Font.Header
	countdownLabel.Text = "0.0s"
	countdownLabel.TextColor3 = Theme.Colors.Text
	countdownLabel.TextSize = Theme.Sizes.TextBody
	countdownLabel.ZIndex = 83
	countdownLabel.Parent = countdownFrame
	self._countdownLabel = countdownLabel

	local button = Instance.new("TextButton")
	button.Name = "RestoreButton"
	button.BackgroundColor3 = Theme.Buttons.GoldFill
	button.BorderSizePixel = 0
	button.Position = UDim2.new(0, 20, 1, -58)
	button.Size = UDim2.new(1, -40, 0, 38)
	button.Font = Theme.Font.Body
	button.Text = "Restore"
	button.TextColor3 = Theme.Colors.Text
	button.TextSize = Theme.Sizes.TextBody + 1
	button.AutoButtonColor = false
	button.Selectable = true
	button.ZIndex = 82
	button.Parent = frame
	self._button = button

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Theme.Border.Focus
	buttonStroke.Transparency = 0.1
	buttonStroke.Thickness = 2
	buttonStroke.Parent = button

	button.MouseEnter:Connect(function()
		if button.Active then
			button.BackgroundColor3 = Theme.Buttons.GoldHover
			buttonStroke.Color = Theme.Border.Focus
			buttonStroke.Thickness = Theme.Stroke.FocusThickness
		end
	end)

	button.MouseLeave:Connect(function()
		if button.Active then
			button.BackgroundColor3 = Theme.Buttons.GoldFill
			buttonStroke.Color = Theme.Border.Focus
			buttonStroke.Thickness = 2
		end
	end)

	button.SelectionGained:Connect(function()
		if button.Active then
			button.BackgroundColor3 = Theme.Buttons.GoldHover
			buttonStroke.Color = Theme.Border.Focus
			buttonStroke.Thickness = Theme.Stroke.FocusThickness
		end
	end)

	button.SelectionLost:Connect(function()
		if button.Active then
			button.BackgroundColor3 = Theme.Buttons.GoldFill
			buttonStroke.Color = Theme.Border.Focus
			buttonStroke.Thickness = 2
		end
	end)

	button.Activated:Connect(function()
		if not button.Active then
			return
		end

		self:SetPurchasePending(true)
		if self._onRestoreRequested then
			self._onRestoreRequested()
		end
	end)

	return self
end

function RestoreOfferMenu:_animateVisible(visible)
	if not self._overlay or not self._frame then
		return
	end

	self._overlay.Visible = true
	self._frame.Visible = true

	if visible then
		self._frame.Size = UDim2.fromOffset(self._baseSize.X.Offset - 24, self._baseSize.Y.Offset - 12)
		self._frame.BackgroundTransparency = 1
		self._overlay.BackgroundTransparency = 1

		TweenService:Create(self._overlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.52,
		}):Play()

		TweenService:Create(self._frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0,
			Size = self._baseSize,
		}):Play()

		if prefersGamepadSelection() and self._button then
			task.defer(function()
				if self._visible and self._button and self._button.Parent then
					GuiService.SelectedObject = self._button
				end
			end)
		end
		return
	end

	local overlayTween = TweenService:Create(self._overlay, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
	local frameTween = TweenService:Create(self._frame, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(self._baseSize.X.Offset - 24, self._baseSize.Y.Offset - 12),
	})
	overlayTween:Play()
	frameTween:Play()
	frameTween.Completed:Once(function()
		if not self._visible and self._overlay and self._frame then
			self._overlay.Visible = false
			self._frame.Visible = false
			self._frame.Size = self._baseSize
		end
	end)

	if GuiService.SelectedObject == self._button then
		GuiService.SelectedObject = nil
	end
end

function RestoreOfferMenu:_startTimer(expiresAt)
	self._timerToken += 1
	local timerToken = self._timerToken

	local function update()
		if not self._visible or self._timerToken ~= timerToken or not self._countdownLabel then
			return
		end

		local remaining = math.max(0, (tonumber(expiresAt) or 0) - Workspace:GetServerTimeNow())
		self._countdownLabel.Text = string.format("%.1fs", remaining)

		if remaining <= 0 then
			if self._button then
				self._button.Active = false
				self._button.Selectable = false
				self._button.Text = "Expired"
				self._button.BackgroundColor3 = Theme.Surface.Tinted
				if GuiService.SelectedObject == self._button then
					GuiService.SelectedObject = nil
				end
			end
			return
		end

		task.delay(0.1, update)
	end

	update()
end

function RestoreOfferMenu:SetPurchasePending(isPending)
	if not self._button then
		return
	end

	if isPending then
		self._button.Active = false
		self._button.Selectable = false
		self._button.Text = "Opening..."
		self._button.BackgroundColor3 = Theme.Surface.Tinted
		if GuiService.SelectedObject == self._button then
			GuiService.SelectedObject = nil
		end
		return
	end

	self._button.Active = true
	self._button.Selectable = true
	self._button.Text = "Restore"
	self._button.BackgroundColor3 = Theme.Buttons.GoldFill
end

function RestoreOfferMenu:SetOffer(snapshot)
	snapshot = type(snapshot) == "table" and snapshot or {}
	local secondsRemaining = tonumber(snapshot.SecondsRemaining) or 0
	local expiresAt = tonumber(snapshot.ExpiresAt)
	local timerDeadline = secondsRemaining > 0 and (Workspace:GetServerTimeNow() + secondsRemaining) or expiresAt
	warn(string.format(
		"[RESTORE_PROBE] RestoreOfferMenu:SetOffer active=%s reason=%s roundId=%s secondsRemaining=%s expiresAt=%s timerDeadline=%s",
		tostring(snapshot.Active),
		tostring(snapshot.Reason),
		tostring(snapshot.RoundId),
		tostring(snapshot.SecondsRemaining),
		tostring(snapshot.ExpiresAt),
		tostring(timerDeadline)
	))
	self:SetPurchasePending(false)

	if snapshot.Active ~= true then
		self:Hide()
		return
	end

	self._titleLabel.Text = "Restore Streak"
	self._bodyLabel.Text = buildMessage(snapshot)
	if not self._visible then
		self._visible = true
		self:_animateVisible(true)
	elseif self._overlay and self._frame then
		self._overlay.Visible = true
		self._frame.Visible = true
	end
	self:_startTimer(timerDeadline)
end

function RestoreOfferMenu:Hide()
	warn(string.format(
		"[RESTORE_PROBE] RestoreOfferMenu:Hide visible=%s overlayVisible=%s frameVisible=%s",
		tostring(self._visible),
		tostring(self._overlay and self._overlay.Visible or false),
		tostring(self._frame and self._frame.Visible or false)
	))
	self._timerToken += 1
	if not self._visible then
		if self._overlay then
			self._overlay.Visible = false
		end
		if self._frame then
			self._frame.Visible = false
		end
		return
	end

	self._visible = false
	self:_animateVisible(false)
end

function RestoreOfferMenu:Destroy()
	self:Hide()
	if self._overlay then
		self._overlay:Destroy()
		self._overlay = nil
	end
	self._frame = nil
	self._button = nil
	self._countdownLabel = nil
	self._bodyLabel = nil
	self._titleLabel = nil
end

return RestoreOfferMenu
