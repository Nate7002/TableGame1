local Snow = Color3.fromRGB(250, 253, 255)
local Frost = Color3.fromRGB(237, 246, 255)
local Ice = Color3.fromRGB(212, 232, 255)
local Glass = Color3.fromRGB(226, 241, 255)
local CobaltInk = Color3.fromRGB(40, 72, 124)
local CobaltMuted = Color3.fromRGB(104, 131, 173)
local AuroraCyan = Color3.fromRGB(96, 220, 255)
local Mint = Color3.fromRGB(122, 243, 208)
local HotPink = Color3.fromRGB(255, 127, 206)
local RewardGold = Color3.fromRGB(255, 208, 98)
local CoralDanger = Color3.fromRGB(255, 118, 129)
local FocusWhite = Color3.fromRGB(255, 255, 255)
local BorderSoft = Color3.fromRGB(155, 192, 236)
local BorderStrong = Color3.fromRGB(78, 126, 199)
local ShadowBlue = Color3.fromRGB(62, 102, 165)

local Theme = {}

function Theme.Blend(fromColor, toColor, alpha)
	alpha = math.clamp(alpha or 0, 0, 1)
	return Color3.new(
		fromColor.R + (toColor.R - fromColor.R) * alpha,
		fromColor.G + (toColor.G - fromColor.G) * alpha,
		fromColor.B + (toColor.B - fromColor.B) * alpha
	)
end

Theme.Colors = {
	Snow = Snow,
	Frost = Frost,
	Ice = Ice,
	Glass = Glass,
	CobaltInk = CobaltInk,
	CobaltMuted = CobaltMuted,
	AuroraCyan = AuroraCyan,
	Mint = Mint,
	HotPink = HotPink,
	RewardGold = RewardGold,
	CoralDanger = CoralDanger,

	Primary = Frost,
	Secondary = Snow,
	Accent = AuroraCyan,
	Text = CobaltInk,
	TextDim = CobaltMuted,
	Success = Mint,
	Warning = RewardGold,
	Danger = CoralDanger,
}

Theme.Surface = {
	Base = Snow,
	Elevated = Frost,
	Tinted = Ice,
	Glass = Glass,
}

Theme.Accent = {
	Primary = AuroraCyan,
	Mint = Mint,
	Pink = HotPink,
	Gold = RewardGold,
	Danger = CoralDanger,
	Focus = FocusWhite,
}

Theme.Border = {
	Soft = BorderSoft,
	Strong = BorderStrong,
	Focus = FocusWhite,
}

Theme.Shadow = {
	Color = ShadowBlue,
	Transparency = 0.8,
}

Theme.Buttons = {
	PrimaryFill = AuroraCyan,
	PrimaryHover = Theme.Blend(AuroraCyan, FocusWhite, 0.16),
	SecondaryFill = Snow,
	SecondaryHover = Ice,
	MintFill = Mint,
	MintHover = Theme.Blend(Mint, FocusWhite, 0.14),
	GoldFill = RewardGold,
	GoldHover = Theme.Blend(RewardGold, FocusWhite, 0.12),
	PinkFill = HotPink,
	PinkHover = Theme.Blend(HotPink, FocusWhite, 0.12),
	DangerFill = CoralDanger,
	DangerHover = Theme.Blend(CoralDanger, FocusWhite, 0.12),
}

Theme.Font = {
	Header = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
	BodyAlt = Enum.Font.GothamMedium,
}

Theme.Stroke = {
	Color = BorderStrong,
	Transparency = 0.48,
	Thickness = 2,
	FocusThickness = 2.6,
}

Theme.Sizes = {
	CornerRadius = UDim.new(0, 16),
	ButtonRadius = UDim.new(0, 12),
	ChipRadius = UDim.new(0, 18),
	Padding = UDim.new(0, 16),
	TextHeader = 28,
	TextBody = 18,
	TextSmall = 14,
	TextMicro = 12,
}

return Theme
