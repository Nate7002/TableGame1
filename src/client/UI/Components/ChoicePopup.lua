local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.Theme)

local ChoicePopup = {}
ChoicePopup.__index = ChoicePopup

function ChoicePopup.new(parent, payload, onResponse)
	local self = setmetatable({}, ChoicePopup)
	
	self.Parent = parent
	self.OnResponse = onResponse
	self.IsClosing = false
	
	-- Main Container (Overlay)
	local overlay = Instance.new("Frame")
	overlay.Name = "ChoiceOverlay"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1 -- Animate to 0.5
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 10
	overlay.Parent = parent
	self.Overlay = overlay
	
	-- Popup Frame
	local frame = Instance.new("Frame")
	frame.Name = "Popup"
	frame.BackgroundColor3 = Theme.Colors.Primary
	frame.Size = UDim2.fromOffset(400, 250)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = overlay
	
	-- Initial Scale (for pop-in)
	local originalSize = frame.Size
	frame.Size = UDim2.fromOffset(360, 225) -- Start slightly smaller
	frame.BackgroundTransparency = 1
	self.Frame = frame
	self.OriginalSize = originalSize
	
	Instance.new("UICorner", frame).CornerRadius = Theme.Sizes.CornerRadius
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -40, 0, 40)
	title.Position = UDim2.new(0, 20, 0, 20)
	title.Font = Theme.Font.Header
	title.Text = payload.title or "Choice"
	title.TextColor3 = Theme.Colors.Text
	title.TextSize = Theme.Sizes.TextHeader
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	
	-- Description
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, -40, 0, 60)
	desc.Position = UDim2.new(0, 20, 0, 60)
	desc.Font = Theme.Font.Body
	desc.Text = payload.description or "Please select an option."
	desc.TextColor3 = Theme.Colors.TextDim
	desc.TextSize = Theme.Sizes.TextBody
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.Parent = frame
	
	-- Options Container
	local optionsContainer = Instance.new("Frame")
	optionsContainer.Name = "Options"
	optionsContainer.BackgroundTransparency = 1
	optionsContainer.Size = UDim2.new(1, -40, 0, 50)
	optionsContainer.Position = UDim2.new(0, 20, 1, -70)
	optionsContainer.Parent = frame
	
	local uiList = Instance.new("UIListLayout")
	uiList.FillDirection = Enum.FillDirection.Horizontal
	uiList.Padding = UDim.new(0, 15)
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiList.Parent = optionsContainer
	
	-- Generate Buttons
	if payload.options then
		for _, opt in ipairs(payload.options) do
			self:CreateButton(optionsContainer, opt)
		end
	end
	
	-- Animate In
	self:AnimateIn()
	
	-- Timeout
	if payload.timeout then
		self:StartTimer(payload.timeout)
	end
	
	return self
end

function ChoicePopup:CreateButton(parent, option)
	local btn = Instance.new("TextButton")
	btn.Name = "Option_" .. option.id
	btn.BackgroundColor3 = Theme.Colors.Secondary
	btn.Size = UDim2.new(0.5, -10, 1, 0) -- Adjust based on count? 
	-- Simple auto-sizing logic for 2 buttons:
	btn.Size = UDim2.new(0, 150, 1, 0)
	
	btn.Font = Theme.Font.Header
	btn.Text = option.label
	btn.TextColor3 = Theme.Colors.Text
	btn.TextSize = Theme.Sizes.TextBody
	btn.AutoButtonColor = true
	btn.Parent = parent
	
	Instance.new("UICorner", btn).CornerRadius = Theme.Sizes.CornerRadius
	
	-- Hover Effect (Simple)
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Theme.Colors.Accent
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = Theme.Colors.Secondary
	end)
	
	btn.MouseButton1Click:Connect(function()
		if self.IsClosing then return end
		self:Close(option.id)
	end)
end

function ChoicePopup:StartTimer(seconds)
	-- Visual timer bar could go here
	-- For MVP, just internal delay
	task.delay(seconds, function()
		if not self.IsClosing and self.Overlay.Parent then
			self:Close(nil) -- Timeout returns nil
		end
	end)
end

function ChoicePopup:AnimateIn()
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	
	local overlayTween = TweenService:Create(self.Overlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 })
	overlayTween:Play()
	
	local frameTween = TweenService:Create(self.Frame, info, {
		Size = self.OriginalSize,
		BackgroundTransparency = 0
	})
	frameTween:Play()
	
	-- Fade text in
	for _, child in ipairs(self.Frame:GetDescendants()) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			local targetTrans = child:IsA("TextButton") and 0 or 0 -- Keep buttons opaque
			-- Actually button BG is 0, Text is 0. 
			-- Simplified: Just let them appear with the frame for now or they pop in.
		end
	end
end

function ChoicePopup:Close(resultId)
	if self.IsClosing then return end
	self.IsClosing = true
	
	-- Send Response
	if self.OnResponse then
		self.OnResponse(resultId)
	end
	
	-- Animate Out
	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	
	local overlayTween = TweenService:Create(self.Overlay, info, { BackgroundTransparency = 1 })
	overlayTween:Play()
	
	local frameTween = TweenService:Create(self.Frame, info, {
		Size = UDim2.fromOffset(360, 225),
		BackgroundTransparency = 1
	})
	frameTween:Play()
	
	frameTween.Completed:Connect(function()
		self.Overlay:Destroy()
	end)
end

return ChoicePopup

