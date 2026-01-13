local Theme = require(script.Parent.Parent.Theme)

local CountdownWidget = {}
CountdownWidget.__index = CountdownWidget

function CountdownWidget.new(parent)
	local self = setmetatable({}, CountdownWidget)
	
	-- Container Pill
	local frame = Instance.new("Frame")
	frame.Name = "CountdownWidget"
	frame.BackgroundColor3 = Theme.Colors.Secondary
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromOffset(50, 36)
	frame.Parent = parent
	self._frame = frame
	
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.TextDim
	stroke.Thickness = 1
	stroke.Transparency = 0.8
	stroke.Parent = frame
	
	-- Number Label
	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Size = UDim2.new(1, 0, 1, 0)
	value.Position = UDim2.new(0, 0, 0, 0)
	value.Font = Theme.Font.Header
	value.Text = "--"
	value.TextColor3 = Theme.Colors.Danger
	value.TextSize = 22
	value.TextXAlignment = Enum.TextXAlignment.Center
	value.Parent = frame
	self._valueLabel = value
	
	return self
end

function CountdownWidget:Update(remainingSeconds)
	if not self._frame then return end
	if remainingSeconds < 0 then remainingSeconds = 0 end
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
