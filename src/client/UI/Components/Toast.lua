local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Theme = require(script.Parent.Parent.Theme)

local Toast = {}

function Toast.new(parent, text, duration)
	duration = duration or 3
	
	local frame = Instance.new("Frame")
	frame.Name = "Toast"
	frame.BackgroundColor3 = Theme.Colors.Secondary
	frame.BorderSizePixel = 0
	frame.Position = UDim2.new(0.5, 0, 0.85, 0) -- Start lower
	frame.Size = UDim2.new(0, 300, 0, 50)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Parent = parent
	
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = Theme.Sizes.CornerRadius
	uiCorner.Parent = frame
	
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = Theme.Colors.TextDim
	uiStroke.Thickness = 1
	uiStroke.Transparency = 0.8
	uiStroke.Parent = frame
	
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Position = UDim2.new(0, 12, 0, 0)
	label.Font = Theme.Font.Body
	label.TextColor3 = Theme.Colors.Text
	label.TextSize = Theme.Sizes.TextBody
	label.Text = text
	label.TextWrapped = true
	label.Parent = frame
	
	-- Animation
	frame.BackgroundTransparency = 1
	label.TextTransparency = 1
	uiStroke.Transparency = 1
	
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	-- In
	local tweenIn = TweenService:Create(frame, info, {
		Position = UDim2.new(0.5, 0, 0.8, 0), -- Move up slightly
		BackgroundTransparency = 0.1
	})
	local textTweenIn = TweenService:Create(label, info, { TextTransparency = 0 })
	local strokeTweenIn = TweenService:Create(uiStroke, info, { Transparency = 0.8 })
	
	tweenIn:Play()
	textTweenIn:Play()
	strokeTweenIn:Play()
	
	-- Out
	task.delay(duration, function()
		if not frame.Parent then return end
		local tweenOut = TweenService:Create(frame, info, {
			Position = UDim2.new(0.5, 0, 0.75, 0), -- Float up more while fading
			BackgroundTransparency = 1
		})
		local textTweenOut = TweenService:Create(label, info, { TextTransparency = 1 })
		local strokeTweenOut = TweenService:Create(uiStroke, info, { Transparency = 1 })
		
		tweenOut:Play()
		textTweenOut:Play()
		strokeTweenOut:Play()
		
		tweenOut.Completed:Connect(function()
			frame:Destroy()
		end)
	end)
end

return Toast

