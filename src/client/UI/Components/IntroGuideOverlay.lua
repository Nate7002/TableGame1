local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Parent.Theme)

local IntroGuideOverlay = {}
IntroGuideOverlay.__index = IntroGuideOverlay

local DIMMER_TRANSPARENCY = 0.32
local CARD_COLOR_TOP = Color3.fromRGB(245, 251, 255)
local CARD_COLOR_BOTTOM = Color3.fromRGB(214, 236, 255)
local CARD_STROKE = Color3.fromRGB(82, 140, 214)
local TITLE_COLOR = Color3.fromRGB(34, 66, 122)
local BODY_COLOR = Color3.fromRGB(74, 103, 150)
local BUTTON_COLOR = Color3.fromRGB(92, 214, 255)
local BUTTON_GLOW = Color3.fromRGB(255, 255, 255)
local BUTTON_TEXT = Color3.fromRGB(25, 67, 116)

local function isGamepadInputType(inputType)
	return typeof(inputType) == "EnumItem" and string.sub(inputType.Name, 1, 7) == "Gamepad"
end

local function prefersGamepadSelection()
	local lastInputType = UserInputService:GetLastInputType()
	return UserInputService.GamepadEnabled and (isGamepadInputType(lastInputType) or not UserInputService.MouseEnabled)
end

function IntroGuideOverlay.new(parentGui)
	local self = setmetatable({}, IntroGuideOverlay)
	self._parent = parentGui
	self._visible = false
	self._pulseToken = 0
	self._confirmCallback = nil

	local overlay = Instance.new("Frame")
	overlay.Name = "IntroGuideOverlay"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Visible = false
	overlay.Active = false
	overlay.SelectionGroup = true
	overlay.ZIndex = 140
	overlay.Parent = parentGui
	self._overlay = overlay

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(460, 244)
	card.BackgroundColor3 = CARD_COLOR_TOP
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.ZIndex = 141
	card.Parent = overlay
	self._card = card
	self._cardBaseSize = card.Size

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = card

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CARD_COLOR_TOP),
		ColorSequenceKeypoint.new(1, CARD_COLOR_BOTTOM),
	})
	gradient.Rotation = 90
	gradient.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = CARD_STROKE
	stroke.Transparency = 0.12
	stroke.Thickness = 2
	stroke.Parent = card

	local innerGlow = Instance.new("Frame")
	innerGlow.Name = "InnerGlow"
	innerGlow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	innerGlow.BackgroundTransparency = 0.78
	innerGlow.BorderSizePixel = 0
	innerGlow.Position = UDim2.new(0, 10, 0, 10)
	innerGlow.Size = UDim2.new(1, -20, 0, 72)
	innerGlow.ZIndex = 142
	innerGlow.Parent = card

	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 16)
	glowCorner.Parent = innerGlow

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 28, 0, 28)
	title.Size = UDim2.new(1, -56, 0, 44)
	title.Font = Theme.Font.Header
	title.Text = "Go sit down to play!"
	title.TextColor3 = TITLE_COLOR
	title.TextSize = 30
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.ZIndex = 143
	title.Parent = card
	self._titleLabel = title

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 28, 0, 92)
	body.Size = UDim2.new(1, -56, 0, 64)
	body.Font = Theme.Font.Body
	body.Text = "Walk to a table and sit to start a match."
	body.TextColor3 = BODY_COLOR
	body.TextSize = 21
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.ZIndex = 143
	body.Parent = card
	self._bodyLabel = body

	local button = Instance.new("TextButton")
	button.Name = "ConfirmButton"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -26)
	button.Size = UDim2.fromOffset(172, 52)
	button.BackgroundColor3 = BUTTON_COLOR
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = "OK"
	button.TextColor3 = BUTTON_TEXT
	button.TextSize = 22
	button.Font = Theme.Font.Header
	button.Selectable = true
	button.ZIndex = 143
	button.Parent = card
	self._button = button
	self._buttonBaseSize = button.Size

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 14)
	buttonCorner.Parent = button

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(255, 255, 255)
	buttonStroke.Transparency = 0.18
	buttonStroke.Thickness = 2
	buttonStroke.Parent = button
	self._buttonStroke = buttonStroke

	local buttonGlow = Instance.new("UIGradient")
	buttonGlow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, BUTTON_COLOR),
	})
	buttonGlow.Rotation = 90
	buttonGlow.Parent = button

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -84)
	hint.Size = UDim2.new(1, -56, 0, 22)
	hint.Font = Theme.Font.Body
	hint.Text = "Press A"
	hint.TextColor3 = BODY_COLOR
	hint.TextSize = 16
	hint.Visible = false
	hint.ZIndex = 143
	hint.Parent = card
	self._hintLabel = hint

	button.MouseEnter:Connect(function()
		if self._visible then
			button.BackgroundColor3 = Color3.fromRGB(120, 228, 255)
		end
	end)

	button.MouseLeave:Connect(function()
		if self._visible then
			button.BackgroundColor3 = BUTTON_COLOR
		end
	end)

	button.SelectionGained:Connect(function()
		if self._visible then
			button.BackgroundColor3 = Color3.fromRGB(120, 228, 255)
		end
	end)

	button.SelectionLost:Connect(function()
		if self._visible then
			button.BackgroundColor3 = BUTTON_COLOR
		end
	end)

	button.Activated:Connect(function()
		if not self._visible then
			return
		end

		if self._confirmCallback then
			self._confirmCallback()
		end
	end)

	return self
end

function IntroGuideOverlay:_runPulse()
	self._pulseToken += 1
	local pulseToken = self._pulseToken
	local button = self._button
	local stroke = self._buttonStroke
	local baseSize = self._buttonBaseSize

	task.spawn(function()
		while self._visible and pulseToken == self._pulseToken and button and button.Parent do
			local expandTween = TweenService:Create(button, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(baseSize.X.Offset + 8, baseSize.Y.Offset + 4),
				BackgroundColor3 = Color3.fromRGB(126, 232, 255),
			})
			local strokeTween = TweenService:Create(stroke, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Color = BUTTON_GLOW,
				Transparency = 0,
			})
			expandTween:Play()
			strokeTween:Play()
			expandTween.Completed:Wait()

			if not self._visible or pulseToken ~= self._pulseToken or not button.Parent then
				break
			end

			local settleTween = TweenService:Create(button, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				Size = baseSize,
				BackgroundColor3 = BUTTON_COLOR,
			})
			local strokeSettle = TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				Color = Color3.fromRGB(255, 255, 255),
				Transparency = 0.18,
			})
			settleTween:Play()
			strokeSettle:Play()
			settleTween.Completed:Wait()
		end

		if button and button.Parent then
			button.Size = baseSize
			button.BackgroundColor3 = BUTTON_COLOR
		end
		if stroke and stroke.Parent then
			stroke.Color = Color3.fromRGB(255, 255, 255)
			stroke.Transparency = 0.18
		end
	end)
end

function IntroGuideOverlay:Show(config)
	config = type(config) == "table" and config or {}
	self._confirmCallback = config.onConfirm
	self._titleLabel.Text = tostring(config.title or "Go sit down to play!")
	self._bodyLabel.Text = tostring(config.body or "Walk to a table and sit to start a match.")

	local showGamepadHint = config.showGamepadHint == true
	if config.showGamepadHint == nil then
		showGamepadHint = prefersGamepadSelection()
	end
	self._hintLabel.Visible = showGamepadHint

	self._visible = true
	self._overlay.Visible = true
	self._overlay.BackgroundTransparency = 1
	self._card.BackgroundTransparency = 1
	self._card.Size = UDim2.fromOffset(self._cardBaseSize.X.Offset - 28, self._cardBaseSize.Y.Offset - 14)
	self._button.Size = self._buttonBaseSize
	self._button.BackgroundColor3 = BUTTON_COLOR

	TweenService:Create(self._overlay, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = DIMMER_TRANSPARENCY,
	}):Play()

	TweenService:Create(self._card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
		Size = self._cardBaseSize,
	}):Play()

	self:_runPulse()

	if showGamepadHint and self._button and self._button.Parent then
		task.defer(function()
			if self._visible and self._button and self._button.Parent then
				GuiService.SelectedObject = self._button
			end
		end)
	end
end

function IntroGuideOverlay:Hide()
	if not self._visible then
		return
	end

	self._visible = false
	self._pulseToken += 1
	self._confirmCallback = nil

	if GuiService.SelectedObject == self._button then
		GuiService.SelectedObject = nil
	end

	local overlay = self._overlay
	local card = self._card
	if not (overlay and card) then
		return
	end

	local overlayTween = TweenService:Create(overlay, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
	local cardTween = TweenService:Create(card, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(self._cardBaseSize.X.Offset - 24, self._cardBaseSize.Y.Offset - 12),
	})
	overlayTween:Play()
	cardTween:Play()
	cardTween.Completed:Once(function()
		if not self._visible and self._overlay then
			self._overlay.Visible = false
			self._card.Size = self._cardBaseSize
		end
	end)
end

function IntroGuideOverlay:Destroy()
	self:Hide()
	if self._overlay then
		self._overlay:Destroy()
		self._overlay = nil
	end
	self._card = nil
	self._button = nil
	self._hintLabel = nil
	self._titleLabel = nil
	self._bodyLabel = nil
	self._buttonStroke = nil
end

return IntroGuideOverlay
