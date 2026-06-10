local Theme = require(script.Parent.Parent.Theme)

local VIPPromoCard = {}
VIPPromoCard.__index = VIPPromoCard

local function formatMultiplier(multiplier)
	return string.format("%dX", math.max(1, math.floor((tonumber(multiplier) or 1) + 0.5)))
end

function VIPPromoCard.new(parentGui, onPurchaseRequested)
	local self = setmetatable({}, VIPPromoCard)
	self._parent = parentGui
	self._onPurchaseRequested = onPurchaseRequested
	self._snapshot = {
		HasVIP = false,
		RewardMultiplier = 1,
		Configured = false,
		GamePassId = 0,
	}
	self._requestedVisible = true
	self._renderable = false

	local frame = Instance.new("Frame")
	frame.Name = "VIPPromoCard"
	frame.Size = UDim2.fromOffset(206, 172)
	frame.Position = UDim2.new(1, -18, 0.5, 0)
	frame.AnchorPoint = Vector2.new(1, 0.5)
	frame.BackgroundColor3 = Theme.Surface.Base
	frame.BorderSizePixel = 0
	frame.Visible = true
	frame.Parent = parentGui
	self._frame = frame

	local scaleNode = Instance.new("UIScale")
	scaleNode.Name = "Scale"
	scaleNode.Scale = 1
	scaleNode.Parent = frame
	self._scaleNode = scaleNode

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Sizes.ChipRadius
	corner.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Surface.Base),
		ColorSequenceKeypoint.new(1, Theme.Blend(Theme.Surface.Glass, Theme.Colors.RewardGold, 0.16)),
	})
	gradient.Rotation = 90
	gradient.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border.Soft
	stroke.Transparency = 0.14
	stroke.Thickness = 2
	stroke.Parent = frame

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.74
	shine.BorderSizePixel = 0
	shine.Position = UDim2.new(0, 10, 0, 8)
	shine.Size = UDim2.new(1, -20, 0, 22)
	shine.Parent = frame

	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0, 10)
	shineCorner.Parent = shine

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.BackgroundColor3 = Theme.Blend(Theme.Colors.RewardGold, Color3.fromRGB(255, 255, 255), 0.18)
	badge.BorderSizePixel = 0
	badge.Position = UDim2.new(0, 16, 0, 18)
	badge.Size = UDim2.fromOffset(58, 58)
	badge.Parent = frame

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge

	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Theme.Colors.RewardGold
	badgeStroke.Transparency = 0.08
	badgeStroke.Thickness = 2
	badgeStroke.Parent = badge

	local badgeText = Instance.new("TextLabel")
	badgeText.Name = "Value"
	badgeText.BackgroundTransparency = 1
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.Font = Theme.Font.Header
	badgeText.Text = "2X"
	badgeText.TextColor3 = Theme.Colors.Text
	badgeText.TextSize = 22
	badgeText.Parent = badge
	self._badgeText = badgeText

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 86, 0, 20)
	title.Size = UDim2.new(1, -100, 0, 26)
	title.Font = Theme.Font.Header
	title.Text = "VIP ACCESS"
	title.TextColor3 = Theme.Colors.Text
	title.TextSize = Theme.Sizes.TextBody + 2
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	self._titleLabel = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.new(0, 86, 0, 48)
	subtitle.Size = UDim2.new(1, -100, 0, 34)
	subtitle.Font = Theme.Font.Body
	subtitle.Text = "2X cash rewards every win."
	subtitle.TextColor3 = Theme.Colors.TextDim
	subtitle.TextSize = Theme.Sizes.TextSmall + 1
	subtitle.TextWrapped = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextYAlignment = Enum.TextYAlignment.Top
	subtitle.Parent = frame
	self._subtitleLabel = subtitle

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 16, 0, 92)
	body.Size = UDim2.new(1, -32, 0, 34)
	body.Font = Theme.Font.BodyAlt
	body.Text = "Unlock the boosted VIP payout lane."
	body.TextColor3 = Theme.Colors.TextDim
	body.TextSize = Theme.Sizes.TextSmall + 1
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Parent = frame
	self._bodyLabel = body

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.BackgroundColor3 = Theme.Buttons.GoldFill
	button.BorderSizePixel = 0
	button.Position = UDim2.new(0, 16, 1, -54)
	button.Size = UDim2.new(1, -32, 0, 38)
	button.Font = Theme.Font.Body
	button.Text = "BUY VIP"
	button.TextColor3 = Theme.Colors.Text
	button.TextSize = Theme.Sizes.TextBody
	button.AutoButtonColor = false
	button.Selectable = true
	button.Parent = frame
	self._button = button

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 10)
	buttonCorner.Parent = button

	local buttonGradient = Instance.new("UIGradient")
	buttonGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Blend(Theme.Buttons.GoldFill, Color3.fromRGB(255, 255, 255), 0.14)),
		ColorSequenceKeypoint.new(1, Theme.Buttons.GoldFill),
	})
	buttonGradient.Rotation = 90
	buttonGradient.Parent = button

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Theme.Border.Focus
	buttonStroke.Transparency = 0.12
	buttonStroke.Thickness = 2
	buttonStroke.Parent = button
	self._buttonStroke = buttonStroke

	button.MouseEnter:Connect(function()
		if self._snapshot.Configured == true and self._snapshot.HasVIP ~= true then
			button.BackgroundColor3 = Theme.Buttons.GoldHover
			buttonStroke.Thickness = Theme.Stroke.FocusThickness
		end
	end)

	button.MouseLeave:Connect(function()
		if self._snapshot.Configured == true and self._snapshot.HasVIP ~= true then
			button.BackgroundColor3 = Theme.Buttons.GoldFill
			buttonStroke.Thickness = 2
		end
	end)

	button.SelectionGained:Connect(function()
		if self._snapshot.Configured == true and self._snapshot.HasVIP ~= true then
			button.BackgroundColor3 = Theme.Buttons.GoldHover
			buttonStroke.Thickness = Theme.Stroke.FocusThickness
		end
	end)

	button.SelectionLost:Connect(function()
		if self._snapshot.Configured == true and self._snapshot.HasVIP ~= true then
			button.BackgroundColor3 = Theme.Buttons.GoldFill
			buttonStroke.Thickness = 2
		end
	end)

	button.Activated:Connect(function()
		if self._snapshot.Configured ~= true or self._snapshot.HasVIP == true then
			return
		end
		if self._onPurchaseRequested then
			self._onPurchaseRequested()
		end
	end)

	self:SetSnapshot(self._snapshot)

	return self
end

function VIPPromoCard:_applyVisibility()
	if self._frame then
		self._frame.Visible = self._requestedVisible == true and self._renderable == true
	end
end

function VIPPromoCard:SetVisible(visible)
	self._requestedVisible = visible == true
	self:_applyVisibility()
end

function VIPPromoCard:SetPosition(position, anchorPoint)
	if not self._frame then
		return
	end

	if anchorPoint ~= nil then
		self._frame.AnchorPoint = anchorPoint
	end
	if position ~= nil then
		self._frame.Position = position
	end
end

function VIPPromoCard:SetScale(scale)
	if self._scaleNode then
		self._scaleNode.Scale = math.max(0.5, tonumber(scale) or 1)
	end
end

function VIPPromoCard:SetSnapshot(snapshotTable)
	snapshotTable = type(snapshotTable) == "table" and snapshotTable or {}
	self._snapshot = {
		HasVIP = snapshotTable.HasVIP == true,
		RewardMultiplier = math.max(1, tonumber(snapshotTable.RewardMultiplier) or 1),
		Configured = snapshotTable.Configured == true,
		GamePassId = math.max(0, tonumber(snapshotTable.GamePassId) or 0),
	}

	if not self._button or not self._subtitleLabel or not self._bodyLabel or not self._badgeText then
		return
	end

	local hasVIP = self._snapshot.HasVIP == true
	local configured = self._snapshot.Configured == true
	local multiplierText = formatMultiplier(self._snapshot.RewardMultiplier)
	self._badgeText.Text = multiplierText

	if hasVIP then
		self._renderable = true
		self._titleLabel.Text = "VIP ACTIVE"
		self._subtitleLabel.Text = string.format("%s cash rewards are live.", multiplierText)
		self._bodyLabel.Text = "Your payouts are boosted right now."
		self._bodyLabel.TextColor3 = Theme.Colors.Success
		self._button.Active = false
		self._button.Selectable = false
		self._button.Text = string.format("%s ACTIVE", multiplierText)
		self._button.BackgroundColor3 = Theme.Buttons.MintFill
		self._buttonStroke.Color = Theme.Colors.Success
		self._buttonStroke.Transparency = 0.12
		self._buttonStroke.Thickness = 2
	elseif configured then
		self._renderable = true
		self._titleLabel.Text = "VIP ACCESS"
		self._subtitleLabel.Text = string.format("%s cash rewards every win.", multiplierText)
		self._bodyLabel.Text = "Unlock the boosted VIP payout lane."
		self._bodyLabel.TextColor3 = Theme.Colors.TextDim
		self._button.Active = true
		self._button.Selectable = true
		self._button.Text = "BUY VIP"
		self._button.BackgroundColor3 = Theme.Buttons.GoldFill
		self._buttonStroke.Color = Theme.Border.Focus
		self._buttonStroke.Transparency = 0.12
		self._buttonStroke.Thickness = 2
	else
		self._renderable = false
		self._titleLabel.Text = "VIP ACCESS"
		self._subtitleLabel.Text = string.format("%s cash rewards every win.", multiplierText)
		self._bodyLabel.Text = "Unlock the boosted VIP payout lane."
		self._bodyLabel.TextColor3 = Theme.Colors.TextDim
		self._button.Active = false
		self._button.Selectable = false
		self._button.Text = "BUY VIP"
		self._button.BackgroundColor3 = Theme.Buttons.SecondaryFill
		self._buttonStroke.Color = Theme.Border.Soft
		self._buttonStroke.Transparency = 0.22
		self._buttonStroke.Thickness = 2
	end

	self:_applyVisibility()
end

function VIPPromoCard:SetConfigured(configured)
	self:SetSnapshot({
		HasVIP = self._snapshot.HasVIP,
		RewardMultiplier = self._snapshot.RewardMultiplier,
		Configured = configured == true,
		GamePassId = self._snapshot.GamePassId,
	})
end

function VIPPromoCard:Destroy()
	if self._frame then
		self._frame:Destroy()
		self._frame = nil
	end
end

return VIPPromoCard
