local Theme = require(script.Parent.Parent.Theme)

local ShieldInventoryUI = {}
ShieldInventoryUI.__index = ShieldInventoryUI

function ShieldInventoryUI.new(parentGui)
	local self = setmetatable({}, ShieldInventoryUI)

	local frame = Instance.new("Frame")
	frame.Name = "ShieldInventory"
	frame.Size = UDim2.fromOffset(196, 82)
	frame.Position = UDim2.new(1, -20, 1, -20)
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.BackgroundColor3 = Theme.Surface.Base
	frame.BorderSizePixel = 0
	frame.Parent = parentGui

	local scaleNode = Instance.new("UIScale")
	scaleNode.Name = "Scale"
	scaleNode.Scale = 1
	scaleNode.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Sizes.ChipRadius
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
	stroke.Transparency = 0.16
	stroke.Thickness = 2
	stroke.Parent = frame

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.72
	shine.BorderSizePixel = 0
	shine.Position = UDim2.new(0, 10, 0, 8)
	shine.Size = UDim2.new(1, -20, 0, 18)
	shine.Parent = frame

	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0, 10)
	shineCorner.Parent = shine

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 14, 0, 12)
	title.Size = UDim2.new(1, -28, 0, 16)
	title.Font = Theme.Font.BodyAlt
	title.Text = "SHIELDS"
	title.TextColor3 = Theme.Colors.TextDim
	title.TextSize = Theme.Sizes.TextSmall
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Count"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -14, 0, 28)
	label.Size = UDim2.new(0, 84, 0, 30)
	label.Font = Theme.Font.Header
	label.Text = "0/0"
	label.TextColor3 = Theme.Colors.AuroraCyan
	label.TextSize = 24
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.Parent = frame

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.new(0, 14, 0, 58)
	subtitle.Size = UDim2.new(1, -28, 0, 16)
	subtitle.Font = Theme.Font.BodyAlt
	subtitle.Text = "Protect ready"
	subtitle.TextColor3 = Theme.Colors.Text
	subtitle.TextSize = Theme.Sizes.TextSmall + 1
	subtitle.TextScaled = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = frame

	local subtitleConstraint = Instance.new("UITextSizeConstraint")
	subtitleConstraint.MaxTextSize = Theme.Sizes.TextSmall + 2
	subtitleConstraint.MinTextSize = 10
	subtitleConstraint.Parent = subtitle

	self._frame = frame
	self._scaleNode = scaleNode
	self._label = label
	self._subtitle = subtitle
	self._subtitleConstraint = subtitleConstraint
	self._count = 0
	self._max = 0
	self._lastRenderText = nil

	return self
end

function ShieldInventoryUI:SetVisible(v)
	self._frame.Visible = v
end

function ShieldInventoryUI:SetPosition(position, anchorPoint)
	if anchorPoint ~= nil then
		self._frame.AnchorPoint = anchorPoint
	end
	if position ~= nil then
		self._frame.Position = position
	end
end

function ShieldInventoryUI:SetScale(scale)
	if self._scaleNode then
		self._scaleNode.Scale = math.max(0.5, tonumber(scale) or 1)
	end
end

function ShieldInventoryUI:_applyDisplay()
	local renderText = string.format("%d/%d", self._count, self._max)
	local isEmpty = self._count <= 0
	self._label.Text = renderText
	self._label.TextColor3 = isEmpty and Theme.Colors.Success or Theme.Colors.AuroraCyan
	self._subtitle.Text = isEmpty and "BUY PROTECTION" or "Protect ready"
	self._subtitle.TextColor3 = isEmpty and Theme.Colors.Success or Theme.Colors.Text
	self._subtitle.Font = isEmpty and Theme.Font.Body or Theme.Font.BodyAlt
	self._subtitleConstraint.MaxTextSize = isEmpty and (Theme.Sizes.TextSmall + 2) or (Theme.Sizes.TextSmall + 1)
	self._lastRenderText = renderText
end

function ShieldInventoryUI:SetDisplay(count, max)
	self._count = math.max(0, tonumber(count) or 0)
	self._max = math.max(0, tonumber(max) or 0)
	self:_applyDisplay()
end

function ShieldInventoryUI:SetCount(count)
	self._count = math.max(0, tonumber(count) or 0)
	self:_applyDisplay()
end

function ShieldInventoryUI:SetMax(max)
	self._max = math.max(0, tonumber(max) or 0)
	self:_applyDisplay()
end

return ShieldInventoryUI
