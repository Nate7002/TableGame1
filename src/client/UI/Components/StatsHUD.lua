local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.Theme)

local StatsHUD = {}
StatsHUD.__index = StatsHUD

local MIN_TWEEN_DURATION = 0.25
local MAX_TWEEN_DURATION = 0.8
local TWEEN_SCALE = 1800
local PULSE_SIZE_BOOST = 4

local function formatInteger(value)
	value = math.floor(math.abs(tonumber(value) or 0))
	local render = tostring(value)

	while true do
		local nextRender, count = render:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		render = nextRender
		if count == 0 then
			break
		end
	end

	return render
end

local function createRow(parent, order, labelText)
	local row = Instance.new("Frame")
	row.Name = labelText .. "Row"
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 34)
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.42, 0, 1, 0)
	label.Font = Theme.Font.BodyAlt
	label.Text = labelText
	label.TextColor3 = Theme.Colors.TextDim
	label.TextSize = Theme.Sizes.TextSmall
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.Position = UDim2.new(0.42, 0, 0, 0)
	value.Size = UDim2.new(0.58, 0, 1, 0)
	value.Font = Theme.Font.Header
	value.Text = "0"
	value.TextColor3 = Theme.Colors.Text
	value.TextSize = Theme.Sizes.TextHeader - 2
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Parent = row

	return value
end

local function formatCash(value)
	return "$" .. formatInteger(value)
end

local function formatStreak(value)
	return tostring(math.max(0, math.floor((tonumber(value) or 0) + 0.5)))
end

local function createAnimatedState(label, formatter)
	local driver = Instance.new("NumberValue")
	local state = {
		label = label,
		formatter = formatter,
		driver = driver,
		valueTween = nil,
		pulseTween = nil,
		settleTween = nil,
		baseTextSize = label.TextSize,
		initialized = false,
	}

	state.connection = driver:GetPropertyChangedSignal("Value"):Connect(function()
		if state.label then
			state.label.Text = state.formatter(driver.Value)
		end
	end)

	return state
end

function StatsHUD.new(parentGui)
	local self = setmetatable({}, StatsHUD)

	local frame = Instance.new("Frame")
	frame.Name = "StatsHUD"
	frame.Size = UDim2.fromOffset(196, 104)
	frame.Position = UDim2.new(1, -20, 1, -92)
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.BackgroundColor3 = Theme.Surface.Base
	frame.BorderSizePixel = 0
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

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border.Soft
	stroke.Transparency = 0.14
	stroke.Thickness = Theme.Stroke.Thickness
	stroke.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Surface.Base),
		ColorSequenceKeypoint.new(1, Theme.Surface.Glass),
	})
	gradient.Rotation = 90
	gradient.Parent = frame

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.72
	shine.BorderSizePixel = 0
	shine.Position = UDim2.new(0, 10, 0, 8)
	shine.Size = UDim2.new(1, -20, 0, 20)
	shine.Parent = frame

	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(0, 10)
	shineCorner.Parent = shine

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = frame

	self._cashValue = createRow(frame, 1, "CASH")
	self._streakValue = createRow(frame, 2, "STREAK")
	self._cashState = createAnimatedState(self._cashValue, formatCash)
	self._streakState = createAnimatedState(self._streakValue, formatStreak)

	self:SetDisplay(nil)

	return self
end

function StatsHUD:_cancelValueTween(state)
	if state and state.valueTween then
		state.valueTween:Cancel()
		state.valueTween = nil
	end
end

function StatsHUD:_cancelPulseTweens(state)
	if not state then
		return
	end

	if state.pulseTween then
		state.pulseTween:Cancel()
		state.pulseTween = nil
	end

	if state.settleTween then
		state.settleTween:Cancel()
		state.settleTween = nil
	end
end

function StatsHUD:_pulseLabel(state, pulseColor, settleColor)
	if not state or not state.label then
		return
	end

	self:_cancelPulseTweens(state)

	local label = state.label
	label.TextSize = state.baseTextSize
	label.TextColor3 = pulseColor

	local pulseTween = TweenService:Create(label, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextSize = state.baseTextSize + PULSE_SIZE_BOOST,
		TextColor3 = pulseColor,
	})
	state.pulseTween = pulseTween

	pulseTween.Completed:Once(function()
		if state.pulseTween ~= pulseTween or not label.Parent then
			return
		end
		state.pulseTween = nil

		local settleTween = TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextSize = state.baseTextSize,
			TextColor3 = settleColor,
		})
		state.settleTween = settleTween
		settleTween.Completed:Once(function()
			if state.settleTween == settleTween then
				state.settleTween = nil
			end
			if label.Parent then
				label.TextSize = state.baseTextSize
				label.TextColor3 = settleColor
			end
		end)
		settleTween:Play()
	end)

	pulseTween:Play()
end

function StatsHUD:_setAnimatedValue(state, targetValue, settleColor)
	targetValue = math.max(0, tonumber(targetValue) or 0)
	if not state or not state.label then
		return
	end

	if not state.initialized then
		state.initialized = true
		state.driver.Value = targetValue
		state.label.TextColor3 = settleColor
		state.label.TextSize = state.baseTextSize
		return
	end

	local currentValue = tonumber(state.driver.Value) or 0
	if math.abs(currentValue - targetValue) < 0.01 then
		state.driver.Value = targetValue
		state.label.TextColor3 = settleColor
		state.label.TextSize = state.baseTextSize
		return
	end

	self:_cancelValueTween(state)

	local duration = math.clamp(0.25 + (math.abs(targetValue - currentValue) / TWEEN_SCALE), MIN_TWEEN_DURATION, MAX_TWEEN_DURATION)
	local tween = TweenService:Create(state.driver, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Value = targetValue,
	})
	state.valueTween = tween
	tween.Completed:Once(function()
		if state.valueTween == tween then
			state.valueTween = nil
		end
		if state.label and state.label.Parent then
			state.driver.Value = targetValue
			state.label.TextColor3 = settleColor
			state.label.TextSize = state.baseTextSize
		end
	end)
	tween:Play()

	local pulseColor = targetValue >= currentValue and Theme.Colors.Success or Theme.Colors.Danger
	self:_pulseLabel(state, pulseColor, settleColor)
end

function StatsHUD:SetDisplay(statsTable)
	if statsTable == nil then
		self._cashValue.Text = formatCash(0)
		self._cashValue.TextColor3 = Theme.Colors.Success
		self._cashValue.TextSize = self._cashState.baseTextSize
		self._streakValue.Text = formatStreak(0)
		self._streakValue.TextColor3 = Theme.Colors.Text
		self._streakValue.TextSize = self._streakState.baseTextSize
		return
	end

	local cash = math.max(0, math.floor(tonumber(statsTable and statsTable.Cash) or 0))
	local streak = math.max(0, math.floor(tonumber(statsTable and statsTable.Streak) or 0))
	local streakColor = streak > 0 and Theme.Colors.Warning or Theme.Colors.Text

	self:_setAnimatedValue(self._cashState, cash, Theme.Colors.Success)
	self:_setAnimatedValue(self._streakState, streak, streakColor)
end

function StatsHUD:SetVisible(visible)
	self._frame.Visible = visible
end

function StatsHUD:SetPosition(position, anchorPoint)
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

function StatsHUD:SetScale(scale)
	if self._scaleNode then
		self._scaleNode.Scale = math.max(0.5, tonumber(scale) or 1)
	end
end

function StatsHUD:Destroy()
	for _, state in ipairs({ self._cashState, self._streakState }) do
		self:_cancelValueTween(state)
		self:_cancelPulseTweens(state)
		if state and state.connection then
			state.connection:Disconnect()
			state.connection = nil
		end
		if state and state.driver then
			state.driver:Destroy()
			state.driver = nil
		end
	end

	if self._frame then
		self._frame:Destroy()
		self._frame = nil
	end
end

return StatsHUD
