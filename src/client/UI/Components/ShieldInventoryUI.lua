local Players = game:GetService("Players")

local Theme = require(script.Parent.Parent.Theme)

local ShieldInventoryUI = {}
ShieldInventoryUI.__index = ShieldInventoryUI

function ShieldInventoryUI.new(parentGui)
	local self = setmetatable({}, ShieldInventoryUI)

	local frame = Instance.new("Frame")
	frame.Name = "ShieldInventory"
	frame.Size = UDim2.new(0, 140, 0, 50)
	frame.Position = UDim2.new(1, -20, 0, 20)
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.BackgroundColor3 = Theme.Colors.Primary
	frame.BorderSizePixel = 0
	frame.Parent = parentGui

	-- Styling
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Sizes.CornerRadius
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Stroke.Color
	stroke.Transparency = Theme.Stroke.Transparency
	stroke.Thickness = Theme.Stroke.Thickness
	stroke.Parent = frame

	-- Layout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame

	-- Icon (Emoji for now, but styled)
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(0, 30, 0, 30)
	icon.Font = Theme.Font.Header
	icon.Text = "🛡️"
	icon.TextSize = 28
	icon.TextColor3 = Theme.Colors.Text
	icon.Parent = frame

	-- Count Label
	local label = Instance.new("TextLabel")
	label.Name = "Count"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0, 60, 0, 40)
	label.Font = Theme.Font.Header
	label.Text = "0/0"
	label.TextColor3 = Theme.Colors.Text
	label.TextSize = 26
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = frame

	-- Add a subtle gradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Colors.Secondary),
		ColorSequenceKeypoint.new(1, Theme.Colors.Primary)
	})
	gradient.Rotation = 90
	gradient.Parent = frame

	self._frame = frame
	self._label = label
	self._count = 0
	self._max = 0
	self._lastRenderText = nil

	return self
end

function ShieldInventoryUI:SetVisible(v)
	self._frame.Visible = v
end

function ShieldInventoryUI:_applyDisplay()
	local renderText = string.format("%d/%d", self._count, self._max)
	self._label.Text = renderText
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
