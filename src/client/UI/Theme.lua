local Theme = {
	Colors = {
		Primary = Color3.fromRGB(45, 45, 50),
		Secondary = Color3.fromRGB(60, 60, 65),
		Accent = Color3.fromRGB(0, 170, 255),
		Text = Color3.fromRGB(255, 255, 255),
		TextDim = Color3.fromRGB(180, 180, 180),
		Success = Color3.fromRGB(85, 255, 127),
		Warning = Color3.fromRGB(255, 170, 0),
		Danger = Color3.fromRGB(255, 85, 85),
	},
	
	Font = {
		Header = Enum.Font.Cartoon,
		Body = Enum.Font.Cartoon,
	},
	
	Stroke = {
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0,
		Thickness = 2,
	},
	
	Sizes = {
		CornerRadius = UDim.new(0, 8),
		Padding = UDim.new(0, 12),
		TextHeader = 24,
		TextBody = 18,
		TextSmall = 14,
	}
}

return Theme

