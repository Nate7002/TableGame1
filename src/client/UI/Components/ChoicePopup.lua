local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.Theme)
local CountdownWidget = require(script.Parent.CountdownWidget)

local ChoicePopup = {}
ChoicePopup.__index = ChoicePopup

function ChoicePopup.new(parentGui)
	local self = setmetatable({}, ChoicePopup)
	self._parent = parentGui
	
	-- Create static structure (hidden initially)
	local overlay = Instance.new("Frame")
	overlay.Name = "ChoiceOverlay"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 10
	overlay.Visible = false
	overlay.Parent = parentGui
	self._overlay = overlay
	
	-- Popup Frame
	local frame = Instance.new("Frame")
	frame.Name = "Popup"
	frame.BackgroundColor3 = Theme.Colors.Primary
	frame.Size = UDim2.fromOffset(400, 250)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.BackgroundTransparency = 1
	frame.Parent = overlay
	self._frame = frame
	self._originalSize = frame.Size
	
	Instance.new("UICorner", frame).CornerRadius = Theme.Sizes.CornerRadius
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -120, 0, 40)
	title.Position = UDim2.new(0, 20, 0, 20)
	title.Font = Theme.Font.Header
	title.TextColor3 = Theme.Colors.Text
	title.TextSize = Theme.Sizes.TextHeader
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	self._titleLabel = title
	
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Theme.Stroke.Color
	titleStroke.Transparency = Theme.Stroke.Transparency
	titleStroke.Thickness = Theme.Stroke.Thickness
	titleStroke.Parent = title
	
	-- Description
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, -40, 0, 60)
	desc.Position = UDim2.new(0, 20, 0, 60)
	desc.Font = Theme.Font.Body
	desc.TextColor3 = Theme.Colors.TextDim
	desc.TextSize = Theme.Sizes.TextBody
	desc.TextWrapped = true
	desc.RichText = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.Parent = frame
	self._descLabel = desc
	
	local descStroke = Instance.new("UIStroke")
	descStroke.Color = Theme.Stroke.Color
	descStroke.Transparency = Theme.Stroke.Transparency
	descStroke.Thickness = Theme.Stroke.Thickness
	descStroke.Parent = desc
	
	-- Options Container
	local optionsContainer = Instance.new("Frame")
	optionsContainer.Name = "Options"
	optionsContainer.BackgroundTransparency = 1
	optionsContainer.Size = UDim2.new(1, -40, 0, 50)
	optionsContainer.Position = UDim2.new(0, 20, 1, -70)
	optionsContainer.Parent = frame
	self._optionsContainer = optionsContainer
	
	local uiList = Instance.new("UIListLayout")
	uiList.FillDirection = Enum.FillDirection.Horizontal
	uiList.Padding = UDim.new(0, 15)
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiList.Parent = optionsContainer
	
	-- Timer Widget
	self._countdown = CountdownWidget.new(frame)
	self._countdown:SetPosition(UDim2.new(1, -20, 0, 20), Vector2.new(1, 0))
	
	self._connections = {}
	self._isClosing = false
	self._currentTimerId = 0
	
	return self
end

function ChoicePopup:Show(payload, onResponse)
	self:Hide() -- Reset if open
	self._isClosing = false
	self._overlay.Visible = true
	
	-- Update Content
	self._titleLabel.Text = payload.title or "Choice"
	self._descLabel.Text = payload.description or "Please select an option."
	
	-- Clear Buttons
	for _, child in ipairs(self._optionsContainer:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	
	-- Create Buttons
	if payload.options then
		local count = #payload.options
		for _, opt in ipairs(payload.options) do
			self:CreateButton(opt, count, onResponse)
		end
	end
	
	-- Animate In
	self:AnimateIn()
	
	-- Timer
	self._currentTimerId += 1
	local timerId = self._currentTimerId
	
	if payload.endTime then
		self:StartSyncedTimer(payload.endTime, onResponse, timerId)
		self._countdown:SetVisible(true)
	elseif payload.timeout then
		self:StartTimer(payload.timeout, onResponse, timerId)
		self._countdown:SetVisible(true)
	else
		self._countdown:SetVisible(false)
	end
end

function ChoicePopup:CreateButton(option, count, onResponse)
	local btn = Instance.new("TextButton")
	btn.Name = "Option_" .. option.id
	btn.BackgroundColor3 = Theme.Colors.Secondary
	
	if count then
		btn.Size = UDim2.new(1/count, -10, 1, 0)
	else
		btn.Size = UDim2.new(0, 150, 1, 0)
	end
	
	btn.Font = Theme.Font.Header
	btn.Text = option.label
	btn.TextColor3 = Theme.Colors.Text
	btn.TextSize = Theme.Sizes.TextBody
	btn.AutoButtonColor = true
	btn.Parent = self._optionsContainer
	
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Theme.Stroke.Color
	btnStroke.Transparency = Theme.Stroke.Transparency
	btnStroke.Thickness = Theme.Stroke.Thickness
	btnStroke.Parent = btn
	
	Instance.new("UICorner", btn).CornerRadius = Theme.Sizes.CornerRadius
	
	-- Interaction
	local connClick = btn.MouseButton1Click:Connect(function()
		if self._isClosing then return end
		self:Hide()
		if onResponse then onResponse(option.id) end
	end)
	table.insert(self._connections, connClick)
	
	-- Hover
	local connEnter = btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Theme.Colors.Accent
	end)
	table.insert(self._connections, connEnter)
	
	local connLeave = btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = Theme.Colors.Secondary
	end)
	table.insert(self._connections, connLeave)
end

function ChoicePopup:StartSyncedTimer(endTime, onResponse, timerId)
	local function update()
		if self._isClosing or self._currentTimerId ~= timerId then return end
		
		local remaining = math.ceil(endTime - workspace:GetServerTimeNow())
		if remaining < 0 then remaining = 0 end
		
		self._countdown:Update(remaining)
		
		if remaining <= 0 then
			self:Hide()
			if onResponse then onResponse(nil) end
			return
		end
		
		task.delay(0.2, update)
	end
	update()
end

function ChoicePopup:StartTimer(seconds, onResponse, timerId)
	local endTime = os.clock() + seconds
	local function update()
		if self._isClosing or self._currentTimerId ~= timerId then return end
		
		local remaining = math.ceil(endTime - os.clock())
		if remaining < 0 then remaining = 0 end
		
		self._countdown:Update(remaining)
		
		if remaining <= 0 then
			self:Hide()
			if onResponse then onResponse(nil) end
			return
		end
		
		task.delay(0.2, update)
	end
	update()
end

function ChoicePopup:AnimateIn()
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	
	self._overlay.BackgroundTransparency = 1
	local overlayTween = TweenService:Create(self._overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 })
	overlayTween:Play()
	
	self._frame.Size = UDim2.fromOffset(360, 225)
	self._frame.BackgroundTransparency = 1
	
	local frameTween = TweenService:Create(self._frame, info, {
		Size = self._originalSize,
		BackgroundTransparency = 0
	})
	frameTween:Play()
end

function ChoicePopup:Hide()
	if self._isClosing then return end
	self._isClosing = true
	self._currentTimerId += 1 -- Invalidates timers
	
	-- Disconnect inputs
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
	
	-- Animate Out
	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	
	local overlayTween = TweenService:Create(self._overlay, info, { BackgroundTransparency = 1 })
	overlayTween:Play()
	
	local frameTween = TweenService:Create(self._frame, info, {
		Size = UDim2.fromOffset(360, 225),
		BackgroundTransparency = 1
	})
	frameTween:Play()
	
	frameTween.Completed:Connect(function()
		if self._isClosing then -- Ensure didn't reopen
			self._overlay.Visible = false
		end
	end)
end

function ChoicePopup:Destroy()
	self:Hide()
	if self._overlay then self._overlay:Destroy() end
	self._overlay = nil
end

return ChoicePopup

