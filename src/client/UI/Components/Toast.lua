local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Theme = require(script.Parent.Parent.Theme)

local Toast = {}
Toast.__index = Toast

-- Constants
local SHOW_DURATION = 0.15
local HIDE_DURATION = 0.12
local FAST_HIDE_DURATION = 0.12 -- Step D: Fast hide duration

function Toast.new(parentGui)
	local self = setmetatable({}, Toast)
	self._parent = parentGui
	self._shadow = nil
	self._frame = nil
	self._label = nil
	self._uiStroke = nil
	self._labelStroke = nil
	self._activeTweens = {}
	self._hideTask = nil
	return self
end

-- Helper: Cancel all active tweens (does NOT cancel hide task)
function Toast:_cancelTweens()
	for _, tween in ipairs(self._activeTweens) do
		if tween then
			tween:Cancel()
		end
	end
	self._activeTweens = {}
end

-- Helper: Cancel scheduled hide task
function Toast:_cancelHideTask()
	if self._hideTask then
		task.cancel(self._hideTask)
		self._hideTask = nil
	end
end

-- Helper: Create frame if needed
function Toast:_ensureFrame()
	if self._frame and self._frame.Parent then
		return -- Already exists
	end
	
	if not self._parent then return end
	
	local shadow = Instance.new("Frame")
	shadow.Name = "ToastShadow"
	shadow.BackgroundColor3 = Theme.Shadow.Color
	shadow.BackgroundTransparency = 1
	shadow.BorderSizePixel = 0
	shadow.Position = UDim2.new(0.5, 0, 0.85, 4)
	shadow.Size = UDim2.new(0, 360, 0, 64)
	shadow.AnchorPoint = Vector2.new(0.5, 1)
	shadow.ZIndex = 94
	shadow.Parent = self._parent

	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = Theme.Sizes.ChipRadius
	shadowCorner.Parent = shadow

	-- Create frame
	local frame = Instance.new("Frame")
	frame.Name = "Toast"
	frame.BackgroundColor3 = Theme.Surface.Base
	frame.BorderSizePixel = 0
	frame.Position = UDim2.new(0.5, 0, 0.85, 0)
	frame.Size = UDim2.new(0, 360, 0, 64)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.ZIndex = 95
	frame.Parent = self._parent
	
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = Theme.Sizes.ChipRadius
	uiCorner.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Surface.Base),
		ColorSequenceKeypoint.new(1, Theme.Surface.Glass),
	})
	gradient.Rotation = 90
	gradient.Parent = frame
	
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = Theme.Border.Soft
	uiStroke.Thickness = 2
	uiStroke.Transparency = 0.18
	uiStroke.Parent = frame
	
	local innerGlow = Instance.new("Frame")
	innerGlow.Name = "InnerGlow"
	innerGlow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	innerGlow.BackgroundTransparency = 0.7
	innerGlow.BorderSizePixel = 0
	innerGlow.Position = UDim2.new(0, 8, 0, 7)
	innerGlow.Size = UDim2.new(1, -16, 0, 22)
	innerGlow.ZIndex = 96
	innerGlow.Parent = frame

	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(0, 12)
	glowCorner.Parent = innerGlow

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -36, 1, 0)
	label.Position = UDim2.new(0, 18, 0, 0)
	label.Font = Theme.Font.Body
	label.TextColor3 = Theme.Colors.Text
	label.TextSize = Theme.Sizes.TextBody + 1
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 97
	label.Parent = frame
	
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Theme.Stroke.Color
	labelStroke.Transparency = Theme.Stroke.Transparency
	labelStroke.Thickness = Theme.Stroke.Thickness
	labelStroke.Parent = label
	
	-- Set initial hidden state for smooth first-time easing
	shadow.BackgroundTransparency = 1
	shadow.Position = UDim2.new(0.5, 0, 0.85, 6)
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.new(0.5, 0, 0.85, 0)
	uiStroke.Transparency = 1
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	labelStroke.Transparency = 1
	
	-- Store references
	self._shadow = shadow
	self._frame = frame
	self._label = label
	self._uiStroke = uiStroke
	self._labelStroke = labelStroke
end

-- Helper: Animate to visible state
function Toast:_animateShow()
	if not (self._frame and self._frame.Parent) then return end
	
	-- Cancel any ongoing animations and previous hide task
	self:_cancelTweens()
	self:_cancelHideTask()
	
	local showInfo = TweenInfo.new(SHOW_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	local shadowTween = TweenService:Create(self._shadow, showInfo, {
		Position = UDim2.new(0.5, 0, 0.8, 5),
		BackgroundTransparency = Theme.Shadow.Transparency,
	})

	-- Tween frame position + background
	local frameTween = TweenService:Create(self._frame, showInfo, {
		Position = UDim2.new(0.5, 0, 0.8, 0),
		BackgroundTransparency = 0.04
	})
	
	-- Tween label text + stroke (CRITICAL: both TextTransparency AND TextStrokeTransparency)
	local labelTween = TweenService:Create(self._label, showInfo, {
		TextTransparency = 0,
		TextStrokeTransparency = Theme.Stroke.Transparency -- Show stroke
	})
	
	-- Tween frame stroke
	local frameStrokeTween = TweenService:Create(self._uiStroke, showInfo, {
		Transparency = 0.18
	})
	
	-- Tween label stroke (on the label itself)
	local labelStrokeTween = TweenService:Create(self._labelStroke, showInfo, {
		Transparency = Theme.Stroke.Transparency
	})
	
	-- Store tweens
	self._activeTweens = {shadowTween, frameTween, labelTween, frameStrokeTween, labelStrokeTween}
	
	-- Play all tweens
	for _, tween in ipairs(self._activeTweens) do
		tween:Play()
	end
end

-- Helper: Animate to hidden state
function Toast:_animateHide(onComplete, duration)
	if not (self._frame and self._frame.Parent) then return end
	
	local hideDuration = duration or HIDE_DURATION
	
	-- Cancel only ongoing tweens (do NOT cancel hide task here)
	self:_cancelTweens()
	
	local hideInfo = TweenInfo.new(hideDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	
	local shadowTween = TweenService:Create(self._shadow, hideInfo, {
		Position = UDim2.new(0.5, 0, 0.75, 7),
		BackgroundTransparency = 1,
	})

	-- Tween frame position + background
	local frameTween = TweenService:Create(self._frame, hideInfo, {
		Position = UDim2.new(0.5, 0, 0.75, 0),
		BackgroundTransparency = 1
	})
	
	-- Tween label text + stroke (CRITICAL: both TextTransparency AND TextStrokeTransparency)
	local labelTween = TweenService:Create(self._label, hideInfo, {
		TextTransparency = 1,
		TextStrokeTransparency = 1 -- Hide stroke completely
	})
	
	-- Tween frame stroke
	local frameStrokeTween = TweenService:Create(self._uiStroke, hideInfo, {
		Transparency = 1
	})
	
	-- Tween label stroke (on the label itself)
	local labelStrokeTween = TweenService:Create(self._labelStroke, hideInfo, {
		Transparency = 1
	})
	
	-- Store tweens
	self._activeTweens = {shadowTween, frameTween, labelTween, frameStrokeTween, labelStrokeTween}
	
	-- Play all tweens
	for _, tween in ipairs(self._activeTweens) do
		tween:Play()
	end
	
	-- On complete callback (use :Once to prevent leak)
	if onComplete then
		frameTween.Completed:Once(onComplete)
	end
end

function Toast:Show(text, duration)
	duration = duration or 3
	
	if not self._parent then return end
	
	-- Ensure frame exists
	self:_ensureFrame()
	
	if not self._frame then return end
	
	-- Update text
	self._label.Text = text
	
	-- Animate to visible (_animateShow handles cancellation)
	self:_animateShow()
	
	-- Cancel any previous hide task before scheduling new one
	self:_cancelHideTask()
	
	-- Schedule hide
	self._hideTask = task.delay(duration, function()
		self:_animateHide(function()
			if self._frame and self._frame.Parent then
				if self._shadow and self._shadow.Parent then
					self._shadow:Destroy()
					self._shadow = nil
				end
				self._frame:Destroy()
				self._frame = nil
				self._label = nil
				self._uiStroke = nil
				self._labelStroke = nil
			end
		end)
	end)
end

-- Step B: Implement HideFast
function Toast:HideFast()
	self:_cancelHideTask()
	self:_animateHide(function()
		if self._frame and self._frame.Parent then
			if self._shadow and self._shadow.Parent then
				self._shadow:Destroy()
				self._shadow = nil
			end
			self._frame:Destroy()
			self._frame = nil
			self._label = nil
			self._uiStroke = nil
			self._labelStroke = nil
		end
	end, FAST_HIDE_DURATION)
end

-- Step B: Implement HideImmediate
function Toast:HideImmediate()
	self:_cancelHideTask()
	self:_cancelTweens()
	if self._shadow then
		self._shadow:Destroy()
		self._shadow = nil
	end
	if self._frame then
		self._frame:Destroy()
		self._frame = nil
		self._label = nil
		self._uiStroke = nil
		self._labelStroke = nil
	end
end

function Toast:Destroy()
	-- Toasts clean themselves up individually
end

return Toast
