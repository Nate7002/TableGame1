local MonetizationConfig = {
	GamePasses = {
		VIP = {
			Id = 0,
		},
	},

	DeveloperProducts = {
		GemPackSmall = {
			Id = 0,
			Kind = "Gems",
			Amount = 50,
		},
		GemPackMedium = {
			Id = 0,
			Kind = "Gems",
			Amount = 150,
		},
		GemPackLarge = {
			Id = 0,
			Kind = "Gems",
			Amount = 500,
		},
		ShieldSingle = {
			Id = 0,
			Kind = "Shields",
			Amount = 1,
		},
		RestoreTier1 = {
			Id = 0,
			Kind = "Restore",
			Tier = 1,
		},
		RestoreTier2 = {
			Id = 0,
			Kind = "Restore",
			Tier = 2,
		},
		RestoreTier3 = {
			Id = 0,
			Kind = "Restore",
			Tier = 3,
		},
	},

	VIP = {
		GamePassKey = "VIP",
		CacheTTLSeconds = 60,
		CashRewardMultiplier = 2,
	},

	StudioOverrides = {
		VIPUserIds = {},
	},

	Shields = {
		MaxInventory = 3,
	},

	RestoreOffers = {
		WindowSeconds = 5.9,
		PromptCooldownSeconds = 10,
	},
}

return MonetizationConfig
