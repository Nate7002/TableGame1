local Theme = require(script.Parent.Parent.Theme)

local CountdownWidget = {}
CountdownWidget.__index = CountdownWidget

function CountdownWidget.new(parent)
	local self = setmetatable({}, CountdownWidget)
	
	-- Container Pill
	local frame = Instance.new("Frame")
	frame.Name = "CountdownWidget"
	frame.BackgroundColor3 = Theme.Surface.Base
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(62, 44)
	frame.ZIndex = 20 -- Widget Layer
	frame.Parent = parent
	self._frame = frame
	
	Instance.new("UICorner", frame).CornerRadius = Theme.Sizes.ButtonRadius

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Surface.Base),
		ColorSequenceKeypoint.new(1, Theme.Surface.Glass),
	})
	gradient.Rotation = 90
	gradient.Parent = frame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border.Soft
	stroke.Thickness = 2
	stroke.Transparency = 0.18
	stroke.Parent = frame
	self._stroke = stroke
	
	-- Number Label
	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(1, 0, 1, 0)
	value.Position = UDim2.new(0, 0, 0, 0)
	value.Font = Theme.Font.Header
	value.Text = "--"
	value.TextColor3 = Theme.Colors.Text
	value.TextSize = 22
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.ZIndex = 20
	value.Parent = frame
	self._valueLabel = value
	
	local valueStroke = Instance.new("UIStroke")
	valueStroke.Color = Theme.Stroke.Color
	valueStroke.Transparency = Theme.Stroke.Transparency
	valueStroke.Thickness = Theme.Stroke.Thickness
	valueStroke.Parent = value
	
	return self
end

function CountdownWidget:Update(remainingSeconds)
	if not self._frame then return end
	if remainingSeconds < 0 then remainingSeconds = 0 end

	if remainingSeconds >= 4 then
		self._frame.BackgroundColor3 = Theme.Surface.Base
		self._valueLabel.TextColor3 = Theme.Colors.Text
		self._valueLabel.TextSize = 22
		self._stroke.Color = Theme.Border.Soft
	elseif remainingSeconds == 3 or remainingSeconds == 2 then
		self._frame.BackgroundColor3 = Theme.Blend(Theme.Surface.Base, Theme.Colors.Warning, 0.3)
		self._valueLabel.TextColor3 = Theme.Colors.Text
		self._valueLabel.TextSize = 24
		self._stroke.Color = Theme.Colors.Warning
	else
		self._frame.BackgroundColor3 = Theme.Blend(Theme.Surface.Base, Theme.Colors.Danger, 0.3)
		self._valueLabel.TextColor3 = Theme.Colors.Danger
		self._valueLabel.TextSize = 28
		self._stroke.Color = Theme.Colors.Danger
	end

	self._valueLabel.Text = tostring(remainingSeconds) .. "s"
end

function CountdownWidget:SetVisible(visible)
	if self._frame then
		self._frame.Visible = visible
	end
end

function CountdownWidget:SetPosition(position, anchorPoint)
	if self._frame then
		self._frame.Position = position
		self._frame.AnchorPoint = anchorPoint
	end
end

function CountdownWidget:Destroy()
	if self._frame then
		self._frame:Destroy()
		self._frame = nil
	end
end

return CountdownWidget
