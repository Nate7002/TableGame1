local MonetizationConfig = {
	GamePasses = {
		VIP = {
			Id = 0,
		},
	},

	DeveloperProducts = {
		GemPackSmall = {
			Id = 3557887444,
			Kind = "Gems",
			Amount = 50,
		},
		GemPackMedium = {
			Id = 3557888145,
			Kind = "Gems",
			Amount = 150,
		},
		GemPackLarge = {
			Id = 3557888239,
			Kind = "Gems",
			Amount = 500,
		},
		ShieldSingle = {
			Id = 3557888497,
			Kind = "Shields",
			Amount = 1,
		},
		RestoreTier1 = {
			Id = 3557888719,
			Kind = "Restore",
			Tier = 1,
		},
		RestoreTier2 = {
			Id = 3557888826,
			Kind = "Restore",
			Tier = 2,
		},
		RestoreTier3 = {
			Id = 3557888927,
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

	ShieldPromptProductKey = "ShieldSingle",

	RestoreOffers = {
		WindowSeconds = 5.9,
		PromptCooldownSeconds = 10,
	},

	RestoreTierSelection = {
		{ Min = 1, Max = 3, ProductKey = "RestoreTier1" },
		{ Min = 4, Max = 9, ProductKey = "RestoreTier2" },
		{ Min = 10, Max = nil, ProductKey = "RestoreTier3" },
	},
}

return MonetizationConfig
