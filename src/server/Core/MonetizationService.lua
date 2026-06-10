local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local DebugService = require(script.Parent:WaitForChild("DebugService"))
local StatsService = require(script.Parent:WaitForChild("StatsService"))
local UIService = require(script.Parent:WaitForChild("UIService"))

local MonetizationService = {}

local PRODUCT_DECISION = Enum.ProductPurchaseDecision

local initialized = false
local playerRemovingConnection = nil
local vipOwnershipCache = {} -- [UserId] = { ownsVIP = boolean, expiresAt = number }
local studioVipOverrides = {} -- [UserId] = boolean (Studio-only in-memory override)
local gamePassesById = {}
local developerProductsById = {}
local developerProductKeysByConfig = {}
local receiptHandlersByKind = {}
local processReceiptBound = false
local restoreOffersByUserId = {}
local processedRestoreOutcomeRoundIds = {}
local restoreProductKeys = {}
local restoreOfferExpiryTokensByUserId = {}
local restorePromptThrottleByUserId = {}
local requestRestorePurchaseConnection = nil
local playerAddedConnection = nil
local promptGamePassPurchaseFinishedConnection = nil

local function countEntries(entries)
	local count = 0

	for _ in pairs(entries) do
		count += 1
	end

	return count
end

local function positiveInteger(value)
	return type(value) == "number" and value > 0 and math.floor(value) == value
end

local function validRestoreTestUserId(value)
	return type(value) == "number"
		and math.floor(value) == value
		and (value > 0 or (RunService:IsStudio() and value < 0))
end

local function resolveUserId(playerOrUserId)
	if validRestoreTestUserId(playerOrUserId) then
		return playerOrUserId
	end

	if typeof(playerOrUserId) == "Instance" or type(playerOrUserId) == "table" then
		local userId = playerOrUserId.UserId
		if validRestoreTestUserId(userId) then
			return userId
		end
	end

	return nil
end

local function hasStudioVipOverride(userId)
	if not RunService:IsStudio() then
		return false
	end

	local studioOverrides = MonetizationConfig.StudioOverrides or {}
	local vipUserIds = studioOverrides.VIPUserIds

	if type(vipUserIds) ~= "table" then
		return false
	end

	for _, overrideUserId in ipairs(vipUserIds) do
		if overrideUserId == userId then
			return true
		end
	end

	return false
end

local function getStudioVipOverrideState(playerOrUserId)
	if not RunService:IsStudio() then
		return nil, "not_studio"
	end

	local userId = resolveUserId(playerOrUserId)
	if not userId then
		return nil, "invalid"
	end

	local forcedValue = studioVipOverrides[userId]
	if forcedValue ~= nil then
		return forcedValue == true, "forced"
	end

	if hasStudioVipOverride(userId) then
		return true, "config"
	end

	return nil, "default"
end

local function clearPlayerCache(player)
	local userId = resolveUserId(player)
	if not userId then
		return
	end

	vipOwnershipCache[userId] = nil
	studioVipOverrides[userId] = nil
	restoreOffersByUserId[userId] = nil
	restoreOfferExpiryTokensByUserId[userId] = nil
	restorePromptThrottleByUserId[userId] = nil
end

local function getVIPGamePassId()
	local vipConfig = MonetizationConfig.VIP or {}
	local vipPass = MonetizationService.GetGamePassConfig(vipConfig.GamePassKey or "VIP")
	return tonumber(vipPass and vipPass.Id) or 0
end

local function publishMonetizationSnapshot(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return
	end

	local snapshot = MonetizationService.GetPlayerMonetizationSnapshot(player)
	if snapshot then
		UIService.FireMonetizationSnapshot(player, snapshot)
	end
end

local function publishMonetizationSnapshotByUserId(playerOrUserId)
	local userId = resolveUserId(playerOrUserId)
	if not positiveInteger(userId) then
		return
	end

	local player = Players:GetPlayerByUserId(userId)
	if player then
		publishMonetizationSnapshot(player)
	end
end

local function scheduleMonetizationSnapshotPublish(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	task.defer(function()
		publishMonetizationSnapshot(player)
	end)

	task.delay(2, function()
		publishMonetizationSnapshot(player)
	end)
end

local function registerIdMap(sourceEntries, targetMap, kind)
	for key, config in pairs(sourceEntries or {}) do
		local id = type(config) == "table" and config.Id or nil

		if positiveInteger(id) then
			if targetMap[id] then
				DebugService.Warn("MONETIZATION", "DUPLICATE_ID", {
					kind = kind,
					id = id,
					key = key,
				})
			end

			targetMap[id] = config
		end
	end
end

local function getSortedKeys(entries)
	local keys = {}

	for key in pairs(entries or {}) do
		table.insert(keys, key)
	end

	table.sort(keys)
	return keys
end

local function copyArray(values)
	local clone = {}

	for index, value in ipairs(values or {}) do
		clone[index] = value
	end

	return clone
end

local function buildRestoreProductKeys()
	local keys = {}

	for productKey, productConfig in pairs(MonetizationConfig.DeveloperProducts or {}) do
		if type(productConfig) == "table" and productConfig.Kind == "Restore" then
			table.insert(keys, productKey)
		end
	end

	table.sort(keys)
	return keys
end

local function getRestoreOfferConfig()
	local restoreConfig = MonetizationConfig.RestoreOffers or {}
	return {
		WindowSeconds = math.max(0, tonumber(restoreConfig.WindowSeconds) or 0),
		PromptCooldownSeconds = math.max(0, tonumber(restoreConfig.PromptCooldownSeconds) or 0),
	}
end

local function clearRestorePromptThrottle(userId)
	local resolvedUserId = resolveUserId(userId)
	if resolvedUserId then
		restorePromptThrottleByUserId[resolvedUserId] = nil
	end
end

local function getShieldPromptProductKey()
	local configuredKey = MonetizationConfig.ShieldPromptProductKey
	if type(configuredKey) == "string" and configuredKey ~= "" then
		return configuredKey
	end

	return "ShieldSingle"
end

local function buildRestoreTierSelectionEntries()
	local entries = {}

	for _, entry in ipairs(MonetizationConfig.RestoreTierSelection or {}) do
		if type(entry) == "table" then
			local minValue = tonumber(entry.Min)
			local maxValue = tonumber(entry.Max)
			local productKey = type(entry.ProductKey) == "string" and entry.ProductKey or nil

			if positiveInteger(minValue) and productKey then
				local normalizedMax = nil
				if maxValue ~= nil then
					normalizedMax = math.max(math.floor(maxValue), math.floor(minValue))
				end

				table.insert(entries, {
					Min = math.floor(minValue),
					Max = normalizedMax,
					ProductKey = productKey,
				})
			end
		end
	end

	table.sort(entries, function(a, b)
		return a.Min < b.Min
	end)

	return entries
end

local function pruneProcessedRestoreOutcomeRoundIds(now)
	now = now or time()

	for roundId, expiresAt in pairs(processedRestoreOutcomeRoundIds) do
		if type(expiresAt) ~= "number" or expiresAt <= now then
			processedRestoreOutcomeRoundIds[roundId] = nil
		end
	end
end

local function markRestoreOutcomeProcessed(roundId, now)
	if type(roundId) ~= "string" or roundId == "" then
		return
	end

	now = now or time()
	local restoreConfig = getRestoreOfferConfig()
	local ttl = math.max(30, restoreConfig.WindowSeconds + restoreConfig.PromptCooldownSeconds + 1)
	processedRestoreOutcomeRoundIds[roundId] = now + ttl
end

local function syncRestoreOfferRecord(record, now)
	if type(record) ~= "table" then
		return nil
	end

	now = now or time()
	if record.Active == true and type(record.ExpiresAt) == "number" and now >= record.ExpiresAt then
		record.Active = false
		record.Reason = "OfferExpired"
		record.ExpiresAt = nil
		clearRestorePromptThrottle(record.LoserUserId)
	end

	if record.Active ~= true and record.Reason == "CooldownActive" then
		local cooldownUntil = type(record.CooldownUntil) == "number" and record.CooldownUntil or 0
		if cooldownUntil <= now then
			record.Reason = "NoActiveOffer"
		end
	end

	return record
end

local function getRestoreOfferRecord(userId, now)
	if not validRestoreTestUserId(userId) then
		return nil
	end

	return syncRestoreOfferRecord(restoreOffersByUserId[userId], now)
end

local function clearRestoreOfferByUserId(userId, reason, now)
	if not validRestoreTestUserId(userId) then
		return false
	end

	clearRestorePromptThrottle(userId)
	restoreOfferExpiryTokensByUserId[userId] = nil

	local record = getRestoreOfferRecord(userId, now)
	if not record then
		return false
	end

	record.Active = false
	record.Reason = reason or record.Reason or "NoActiveOffer"
	record.ExpiresAt = nil
	return true
end

local function buildRestoreOfferSnapshotFromRecord(record, now)
	now = now or time()
	record = syncRestoreOfferRecord(record, now)

	if type(record) ~= "table" then
		return {
			Active = false,
			Reason = "NoActiveOffer",
			RoundId = nil,
			ExpiresAt = nil,
			SecondsRemaining = 0,
			CooldownUntil = nil,
			CooldownRemaining = 0,
			PreLossStreak = nil,
			ValidRestoreProductKeys = {},
			SelectedRestoreProductKey = nil,
			SelectedRestoreProductId = nil,
			SelectedRestoreTier = nil,
			ProjectedRestoredStreak = nil,
		}
	end

	local cooldownRemaining = 0
	if type(record.CooldownUntil) == "number" then
		cooldownRemaining = math.max(0, record.CooldownUntil - now)
	end

	local secondsRemaining = 0
	if record.Active == true and type(record.ExpiresAt) == "number" then
		secondsRemaining = math.max(0, record.ExpiresAt - now)
	end

	return {
		Active = record.Active == true,
		Reason = record.Active == true and "ActiveOffer" or tostring(record.Reason or "NoActiveOffer"),
		RoundId = record.RoundId,
		ExpiresAt = record.ExpiresAt,
		SecondsRemaining = secondsRemaining,
		CooldownUntil = record.CooldownUntil,
		CooldownRemaining = cooldownRemaining,
		PreLossStreak = positiveInteger(record.PreLossStreak) and record.PreLossStreak or nil,
		ValidRestoreProductKeys = copyArray(record.ValidRestoreProductKeys or {}),
		SelectedRestoreProductKey = type(record.SelectedRestoreProductKey) == "string" and record.SelectedRestoreProductKey or nil,
		SelectedRestoreProductId = positiveInteger(record.SelectedRestoreProductId) and record.SelectedRestoreProductId or nil,
		SelectedRestoreTier = positiveInteger(record.SelectedRestoreTier) and record.SelectedRestoreTier or nil,
		ProjectedRestoredStreak = positiveInteger(record.ProjectedRestoredStreak) and record.ProjectedRestoredStreak or nil,
	}
end

local function isRestoreProductConfig(productConfig)
	return type(productConfig) == "table" and productConfig.Kind == "Restore"
end

local function buildRestoreTier(productConfig)
	if type(productConfig) ~= "table" then
		return nil
	end

	local tier = tonumber(productConfig.Tier)
	if positiveInteger(tier) then
		return tier
	end

	return nil
end

local function buildProjectedRestoreStreak(preLossStreak, tier)
	if not positiveInteger(preLossStreak) then
		return nil
	end

	if not positiveInteger(tier) or tier < 1 or tier > 3 then
		return nil
	end

	return math.max(1, math.ceil(preLossStreak * tier / 3))
end

local function buildProjectedRestoreStreakForPlayer(playerOrUserId, preLossStreak, tier)
	if not positiveInteger(preLossStreak) then
		return nil
	end

	local overrideValue, overrideSource = getStudioVipOverrideState(playerOrUserId)
	if overrideSource == "forced" or overrideSource == "config" then
		if overrideValue == true then
			return preLossStreak
		end

		return buildProjectedRestoreStreak(preLossStreak, tier)
	end

	local userId = resolveUserId(playerOrUserId)
	local player = userId and Players:GetPlayerByUserId(userId) or nil
	if typeof(player) == "Instance" and player:IsA("Player") and player.Parent and MonetizationService.PlayerHasVIP(player) then
		return preLossStreak
	end

	return buildProjectedRestoreStreak(preLossStreak, tier)
end

local function selectRestoreProduct(preLossStreak)
	if not positiveInteger(preLossStreak) then
		return nil, nil, nil
	end

	for _, entry in ipairs(buildRestoreTierSelectionEntries()) do
		local maxValue = entry.Max
		if preLossStreak >= entry.Min and (maxValue == nil or preLossStreak <= maxValue) then
			local productConfig = MonetizationService.GetDeveloperProductConfig(entry.ProductKey)
			local tier = buildRestoreTier(productConfig)
			if isRestoreProductConfig(productConfig) and tier then
				return entry.ProductKey, productConfig, tier
			end
		end
	end

	return nil, nil, nil
end

local function buildSelectedRestoreFields(playerOrUserId, productKey, productConfig, tier, preLossStreak)
	local projectedRestoreStreak = buildProjectedRestoreStreakForPlayer(playerOrUserId, preLossStreak, tier)
	return {
		SelectedRestoreProductKey = productKey,
		SelectedRestoreProductId = type(productConfig) == "table" and tonumber(productConfig.Id) or nil,
		SelectedRestoreTier = tier,
		ProjectedRestoredStreak = projectedRestoreStreak,
	}
end

local function publishRestoreOfferStateByUserId(userId, now)
	local resolvedUserId = resolveUserId(userId)
	local currentNow = now or time()
	local snapshot = resolvedUserId and buildRestoreOfferSnapshotFromRecord(getRestoreOfferRecord(resolvedUserId, currentNow), currentNow) or nil
	local player = resolvedUserId and Players:GetPlayerByUserId(resolvedUserId) or nil
	local playerIsLive = typeof(player) == "Instance" and player:IsA("Player") and player.Parent ~= nil

	DebugService.Info("MONETIZATION", "RESTORE_PROBE_PUBLISH", {
		inputUserId = userId,
		resolvedUserId = resolvedUserId,
		playerFound = playerIsLive,
		active = snapshot and snapshot.Active == true,
		reason = snapshot and snapshot.Reason or nil,
		roundId = snapshot and snapshot.RoundId or nil,
		secondsRemaining = snapshot and snapshot.SecondsRemaining or nil,
		expiresAt = snapshot and snapshot.ExpiresAt or nil,
	})

	if not resolvedUserId then
		return nil
	end

	if not playerIsLive then
		return nil
	end

	UIService.FireRestoreOfferState(player, snapshot)
	return snapshot
end

local function scheduleRestoreOfferExpiryPush(userId, roundId, expiresAt)
	local resolvedUserId = resolveUserId(userId)
	if not resolvedUserId or type(roundId) ~= "string" or roundId == "" or type(expiresAt) ~= "number" then
		return
	end

	restoreOfferExpiryTokensByUserId[resolvedUserId] = roundId
	local delaySeconds = math.max(0, expiresAt - time()) + 0.05

	task.delay(delaySeconds, function()
		if restoreOfferExpiryTokensByUserId[resolvedUserId] ~= roundId then
			return
		end

		local record = getRestoreOfferRecord(resolvedUserId, time())
		if type(record) ~= "table" or record.RoundId ~= roundId then
			return
		end

		publishRestoreOfferStateByUserId(resolvedUserId, time())
	end)
end

local function getDeveloperProductKey(productConfig)
	if type(productConfig) ~= "table" then
		return nil
	end

	return developerProductKeysByConfig[productConfig]
end

local function makeUnwiredReceiptHandler(expectedKind)
	return function(receiptInfo, productConfig)
		DebugService.Warn("MONETIZATION", "RECEIPT_UNWIRED_HANDLER", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			kind = expectedKind,
			configuredKind = productConfig and productConfig.Kind,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end
end

local function resolveReceiptPlayer(playerId)
	if not positiveInteger(playerId) then
		return nil
	end

	local player = Players:GetPlayerByUserId(playerId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return nil
	end

	return player
end

local function resolveRestoreOfferPlayer(userId)
	if not validRestoreTestUserId(userId) then
		return nil
	end

	local player = Players:GetPlayerByUserId(userId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return nil
	end

	return player
end

local function handleGemsReceipt(receiptInfo, productConfig)
	local amount = type(productConfig) == "table" and productConfig.Amount or nil
	if not positiveInteger(amount) then
		DebugService.Warn("MONETIZATION", "RECEIPT_GEMS_INVALID_AMOUNT", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			amount = amount,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local player = resolveReceiptPlayer(receiptInfo and receiptInfo.PlayerId)
	if not player then
		DebugService.Warn("MONETIZATION", "RECEIPT_PLAYER_UNAVAILABLE", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			kind = productConfig and productConfig.Kind,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local grantSucceeded = StatsService.AddGems(player, amount, "DeveloperProduct")
	if not grantSucceeded then
		DebugService.Warn("MONETIZATION", "RECEIPT_GEMS_GRANT_FAILED", {
			playerId = player.UserId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			amount = amount,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	DebugService.Info("MONETIZATION", "RECEIPT_GEMS_GRANTED", {
		playerId = player.UserId,
		productId = receiptInfo and receiptInfo.ProductId,
		purchaseId = receiptInfo and receiptInfo.PurchaseId,
		added = amount,
		total = StatsService.GetGems(player),
	})
	return PRODUCT_DECISION.PurchaseGranted
end

local function handleShieldsReceipt(receiptInfo, productConfig)
	local amount = type(productConfig) == "table" and productConfig.Amount or nil
	if not positiveInteger(amount) then
		DebugService.Warn("MONETIZATION", "RECEIPT_SHIELDS_INVALID_AMOUNT", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			amount = amount,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local player = resolveReceiptPlayer(receiptInfo and receiptInfo.PlayerId)
	if not player then
		DebugService.Warn("MONETIZATION", "RECEIPT_PLAYER_UNAVAILABLE", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			kind = productConfig and productConfig.Kind,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local grantSucceeded = StatsService.AddShields(player, amount)
	if not grantSucceeded then
		DebugService.Warn("MONETIZATION", "RECEIPT_SHIELDS_GRANT_FAILED", {
			playerId = player.UserId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			amount = amount,
			total = StatsService.GetShields(player),
			cap = StatsService.GetMaxShields(),
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	DebugService.Info("MONETIZATION", "RECEIPT_SHIELDS_GRANTED", {
		playerId = player.UserId,
		productId = receiptInfo and receiptInfo.ProductId,
		purchaseId = receiptInfo and receiptInfo.PurchaseId,
		added = amount,
		total = StatsService.GetShields(player),
		cap = StatsService.GetMaxShields(),
	})
	return PRODUCT_DECISION.PurchaseGranted
end

local function consumeRestoreOfferByUserId(userId, reason, purchaseId, now)
	if not validRestoreTestUserId(userId) then
		return false
	end

	now = now or time()
	local record = getRestoreOfferRecord(userId, now) or {}
	record.Active = false
	record.Reason = reason or "Consumed"
	record.ExpiresAt = nil
	record.LoserUserId = record.LoserUserId or userId
	record.ValidRestoreProductKeys = copyArray(record.ValidRestoreProductKeys or {})
	restoreOffersByUserId[userId] = record
	restoreOfferExpiryTokensByUserId[userId] = nil
	clearRestorePromptThrottle(userId)

	DebugService.Info("MONETIZATION", "RESTORE_OFFER_CONSUMED", {
		userId = userId,
		reason = record.Reason,
		purchaseId = purchaseId,
		roundId = record.RoundId,
	})

	return true
end

local function handleRestoreReceipt(receiptInfo, productConfig)
	local tier = buildRestoreTier(productConfig)
	if not tier then
		DebugService.Warn("MONETIZATION", "RECEIPT_RESTORE_INVALID_TIER", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			tier = type(productConfig) == "table" and productConfig.Tier or nil,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local player = resolveReceiptPlayer(receiptInfo and receiptInfo.PlayerId)
	if not player then
		DebugService.Warn("MONETIZATION", "RECEIPT_PLAYER_UNAVAILABLE", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			kind = productConfig and productConfig.Kind,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local productKey = getDeveloperProductKey(productConfig)
	if type(productKey) ~= "string" or productKey == "" then
		DebugService.Warn("MONETIZATION", "RECEIPT_RESTORE_UNKNOWN_KEY", {
			playerId = player.UserId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local validation = MonetizationService.ValidateRestoreAttempt(player, productKey)
	if not validation or validation.Allowed ~= true then
		DebugService.Info("MONETIZATION", "RECEIPT_RESTORE_VALIDATION_BLOCKED", {
			playerId = player.UserId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			productKey = productKey,
			reason = validation and validation.Reason or "Unknown",
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local targetStreak = positiveInteger(validation.ProjectedRestoredStreak) and validation.ProjectedRestoredStreak or nil
	local preLossStreak = positiveInteger(validation.PreLossStreak) and validation.PreLossStreak or nil
	if not targetStreak or not preLossStreak then
		DebugService.Warn("MONETIZATION", "RECEIPT_RESTORE_INVALID_TARGET", {
			playerId = player.UserId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			productKey = productKey,
			preLossStreak = validation and validation.PreLossStreak or nil,
			projectedRestoredStreak = validation and validation.ProjectedRestoredStreak or nil,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local applySucceeded = StatsService.RestoreStreak(player, targetStreak, "DeveloperProductRestore")
	if not applySucceeded then
		DebugService.Warn("MONETIZATION", "RECEIPT_RESTORE_APPLY_FAILED", {
			playerId = player.UserId,
			productId = receiptInfo and receiptInfo.ProductId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
			productKey = productKey,
			tier = tier,
			targetStreak = targetStreak,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	consumeRestoreOfferByUserId(player.UserId, "Consumed", receiptInfo and receiptInfo.PurchaseId, time())
	publishRestoreOfferStateByUserId(player.UserId, time())

	DebugService.Info("MONETIZATION", "RECEIPT_RESTORE_APPLIED", {
		playerId = player.UserId,
		productId = receiptInfo and receiptInfo.ProductId,
		purchaseId = receiptInfo and receiptInfo.PurchaseId,
		productKey = productKey,
		tier = tier,
		preLossStreak = preLossStreak,
		restoredStreak = targetStreak,
	})

	return PRODUCT_DECISION.PurchaseGranted
end

local function registerReceiptHandlers()
	receiptHandlersByKind = {
		Gems = handleGemsReceipt,
		Restore = handleRestoreReceipt,
		Shields = handleShieldsReceipt,
	}
end

local function rebuildIndexes()
	gamePassesById = {}
	developerProductsById = {}
	developerProductKeysByConfig = {}

	for key, config in pairs(MonetizationConfig.DeveloperProducts or {}) do
		if type(config) == "table" then
			developerProductKeysByConfig[config] = key
		end
	end

	registerIdMap(MonetizationConfig.GamePasses, gamePassesById, "GamePass")
	registerIdMap(MonetizationConfig.DeveloperProducts, developerProductsById, "DeveloperProduct")
	restoreProductKeys = buildRestoreProductKeys()
	registerReceiptHandlers()
end

local function getConfigEntry(entriesByKey, entriesById, keyOrId)
	if type(keyOrId) == "string" then
		return entriesByKey and entriesByKey[keyOrId] or nil
	end

	if positiveInteger(keyOrId) then
		return entriesById[keyOrId]
	end

	return nil
end

local function dispatchReceiptDecision(receiptInfo, productConfig)
	local productId = type(receiptInfo) == "table" and receiptInfo.ProductId or nil
	local productKind = type(productConfig.Kind) == "string" and productConfig.Kind or nil
	if not productKind or productKind == "" then
		DebugService.Warn("MONETIZATION", "RECEIPT_MISSING_KIND", {
			playerId = receiptInfo.PlayerId,
			productId = productId,
			purchaseId = receiptInfo.PurchaseId,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local handler = receiptHandlersByKind[productKind]
	if not handler then
		DebugService.Warn("MONETIZATION", "RECEIPT_NO_HANDLER", {
			playerId = receiptInfo.PlayerId,
			productId = productId,
			purchaseId = receiptInfo.PurchaseId,
			kind = productKind,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local ok, decision = pcall(handler, receiptInfo, productConfig)
	if not ok then
		DebugService.Warn("MONETIZATION", "RECEIPT_HANDLER_FAILED", {
			playerId = receiptInfo.PlayerId,
			productId = productId,
			kind = productKind,
			error = decision,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	if decision ~= PRODUCT_DECISION.PurchaseGranted and decision ~= PRODUCT_DECISION.NotProcessedYet then
		DebugService.Warn("MONETIZATION", "RECEIPT_INVALID_DECISION", {
			playerId = receiptInfo.PlayerId,
			productId = productId,
			kind = productKind,
			decision = tostring(decision),
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	return decision
end

local function handleReceipt(receiptInfo)
	if type(receiptInfo) ~= "table" then
		DebugService.Warn("MONETIZATION", "RECEIPT_MALFORMED", {
			receiptInfoType = typeof(receiptInfo),
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local productId = receiptInfo.ProductId
	if not positiveInteger(productId) then
		DebugService.Warn("MONETIZATION", "RECEIPT_MALFORMED", {
			playerId = receiptInfo.PlayerId,
			productId = productId,
			purchaseId = receiptInfo.PurchaseId,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local productConfig = MonetizationService.GetDeveloperProductConfig(productId)

	if not productConfig then
		DebugService.Warn("MONETIZATION", "RECEIPT_UNKNOWN_PRODUCT", {
			playerId = receiptInfo.PlayerId,
			productId = productId,
			purchaseId = receiptInfo.PurchaseId,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	return dispatchReceiptDecision(receiptInfo, productConfig)
end

function MonetizationService.GetReceiptRoutingSnapshot()
	return {
		Initialized = initialized == true,
		ProcessReceiptBound = processReceiptBound == true,
		ConfiguredProductCount = countEntries(MonetizationConfig.DeveloperProducts or {}),
		IndexedProductCount = countEntries(developerProductsById),
		RegisteredReceiptKinds = getSortedKeys(receiptHandlersByKind),
	}
end

function MonetizationService.GetGamePassConfig(keyOrId)
	return getConfigEntry(MonetizationConfig.GamePasses, gamePassesById, keyOrId)
end

function MonetizationService.GetDeveloperProductConfig(keyOrId)
	return getConfigEntry(MonetizationConfig.DeveloperProducts, developerProductsById, keyOrId)
end

function MonetizationService.GetShieldPromptProductConfig()
	local productKey = getShieldPromptProductKey()
	local productConfig = MonetizationService.GetDeveloperProductConfig(productKey)
	return productKey, productConfig
end

function MonetizationService.PromptShieldPurchase(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return false, "InvalidPlayer"
	end

	local productKey, productConfig = MonetizationService.GetShieldPromptProductConfig()
	local productId = type(productConfig) == "table" and tonumber(productConfig.Id) or nil
	if type(productKey) ~= "string" or productKey == "" or not positiveInteger(productId) then
		DebugService.Warn("MONETIZATION", "SHIELD_PROMPT_PRODUCT_UNAVAILABLE", {
			playerId = player.UserId,
			productKey = productKey,
			productId = productId,
		})
		return false, "ShieldPromptUnavailable"
	end

	UIService.FireMonetizationPrompt(player, productId, "ShieldSingle")
	DebugService.Info("MONETIZATION", "SHIELD_PROMPT_REQUESTED", {
		playerId = player.UserId,
		productKey = productKey,
		productId = productId,
	})
	return true, nil
end

function MonetizationService.GetRestoreOfferSnapshot(playerOrUserId)
	local userId = resolveUserId(playerOrUserId)
	if not userId then
		return buildRestoreOfferSnapshotFromRecord(nil, time())
	end

	return buildRestoreOfferSnapshotFromRecord(getRestoreOfferRecord(userId, time()), time())
end

function MonetizationService.ValidateRestoreAttempt(playerOrUserId, productKey)
	local userId = resolveUserId(playerOrUserId)
	local productConfig = MonetizationService.GetDeveloperProductConfig(productKey)
	local offerSnapshot = MonetizationService.GetRestoreOfferSnapshot(userId)
	local tier = offerSnapshot.SelectedRestoreTier or buildRestoreTier(productConfig)
	local projectedRestoreStreak = offerSnapshot.ProjectedRestoredStreak
		or buildProjectedRestoreStreakForPlayer(playerOrUserId, offerSnapshot.PreLossStreak, tier)

	if not isRestoreProductConfig(productConfig) then
		return {
			Allowed = false,
			Reason = "UnknownRestoreProduct",
			EffectImplemented = false,
			ProductKey = tostring(productKey),
			Tier = nil,
			PreLossStreak = offerSnapshot.PreLossStreak,
			ProjectedRestoredStreak = nil,
			OfferSnapshot = offerSnapshot,
		}
	end

	if offerSnapshot.Active ~= true then
		local blockedReason = offerSnapshot.Reason
		if blockedReason ~= "OfferExpired" and blockedReason ~= "CooldownActive" then
			blockedReason = "NoActiveOffer"
		end

		return {
			Allowed = false,
			Reason = blockedReason,
			EffectImplemented = false,
			ProductKey = tostring(productKey),
			Tier = tier,
			PreLossStreak = offerSnapshot.PreLossStreak,
			ProjectedRestoredStreak = projectedRestoreStreak,
			OfferSnapshot = offerSnapshot,
		}
	end

	if not positiveInteger(offerSnapshot.PreLossStreak) or not positiveInteger(projectedRestoreStreak) then
		DebugService.Warn("MONETIZATION", "RESTORE_VALIDATION_INVALID_STATE", {
			userId = userId,
			productKey = tostring(productKey),
			preLossStreak = offerSnapshot.PreLossStreak,
			projectedRestoreStreak = projectedRestoreStreak,
		})

		return {
			Allowed = false,
			Reason = "NoActiveOffer",
			EffectImplemented = false,
			ProductKey = tostring(productKey),
			Tier = tier,
			PreLossStreak = offerSnapshot.PreLossStreak,
			ProjectedRestoredStreak = projectedRestoreStreak,
			OfferSnapshot = offerSnapshot,
		}
	end

	if tostring(productKey) ~= tostring(offerSnapshot.SelectedRestoreProductKey) then
		return {
			Allowed = false,
			Reason = "UnknownRestoreProduct",
			EffectImplemented = false,
			ProductKey = tostring(productKey),
			Tier = tier,
			PreLossStreak = offerSnapshot.PreLossStreak,
			ProjectedRestoredStreak = projectedRestoreStreak,
			OfferSnapshot = offerSnapshot,
		}
	end

	return {
		Allowed = true,
		Reason = "EligibleForValidationOnly",
		EffectImplemented = false,
		ProductKey = tostring(productKey),
		Tier = tier,
		PreLossStreak = offerSnapshot.PreLossStreak,
		ProjectedRestoredStreak = projectedRestoreStreak,
		OfferSnapshot = offerSnapshot,
	}
end

function MonetizationService.ClearRestoreOffer(playerOrUserId, reason)
	local userId = resolveUserId(playerOrUserId)
	if not userId then
		DebugService.Info("MONETIZATION", "RESTORE_PROBE_CLEAR", {
			userId = nil,
			reason = tostring(reason or "nil"),
			cleared = false,
			roundId = nil,
		})
		return false
	end

	local now = time()
	local currentRecord = getRestoreOfferRecord(userId, now)
	-- This seam stays idempotent and republishes the latest snapshot after every clear attempt.
	local cleared = clearRestoreOfferByUserId(userId, reason, now)
	DebugService.Info("MONETIZATION", "RESTORE_PROBE_CLEAR", {
		userId = userId,
		reason = tostring(reason or "nil"),
		cleared = cleared,
		roundId = currentRecord and currentRecord.RoundId or nil,
	})
	publishRestoreOfferStateByUserId(userId, now)
	return cleared
end

function MonetizationService.RequestRestorePurchasePrompt(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		return false, "InvalidPlayer"
	end

	local userId = player.UserId
	local offerSnapshot = MonetizationService.GetRestoreOfferSnapshot(player)
	local selectedProductKey = offerSnapshot.SelectedRestoreProductKey
	local selectedProductId = offerSnapshot.SelectedRestoreProductId

	if offerSnapshot.Active ~= true or type(selectedProductKey) ~= "string" or selectedProductKey == "" then
		publishRestoreOfferStateByUserId(userId, time())
		return false, offerSnapshot.Reason or "NoActiveOffer"
	end

	local now = os.clock()
	local throttle = restorePromptThrottleByUserId[userId]
	if type(throttle) == "table"
		and throttle.RoundId == offerSnapshot.RoundId
		and type(throttle.LastRequestAt) == "number"
		and (now - throttle.LastRequestAt) < 0.5
	then
		publishRestoreOfferStateByUserId(userId, time())
		return false, "PromptThrottled"
	end

	local validation = MonetizationService.ValidateRestoreAttempt(player, selectedProductKey)
	if not validation or validation.Allowed ~= true or not positiveInteger(selectedProductId) then
		publishRestoreOfferStateByUserId(userId, time())
		return false, validation and validation.Reason or "NoActiveOffer"
	end

	restorePromptThrottleByUserId[userId] = {
		RoundId = offerSnapshot.RoundId,
		LastRequestAt = now,
	}

	UIService.FireMonetizationPrompt(player, selectedProductId, "RestoreOffer")
	DebugService.Info("MONETIZATION", "RESTORE_PROMPT_REQUESTED", {
		playerId = userId,
		productKey = selectedProductKey,
		productId = selectedProductId,
		roundId = offerSnapshot.RoundId,
	})
	return true, nil
end

function MonetizationService.HandlePostRoundOutcome(outcomeContext)
	if type(outcomeContext) ~= "table" then
		DebugService.Warn("MONETIZATION", "RESTORE_OUTCOME_MALFORMED", {
			contextType = typeof(outcomeContext),
		})
		return false
	end

	local roundId = outcomeContext.RoundId
	if type(roundId) ~= "string" or roundId == "" then
		DebugService.Warn("MONETIZATION", "RESTORE_OUTCOME_MISSING_ROUND_ID", {})
		return false
	end

	local now = time()
	pruneProcessedRestoreOutcomeRoundIds(now)
	if processedRestoreOutcomeRoundIds[roundId] then
		return false
	end

	local participantUserIds = {}
	for _, userId in ipairs(outcomeContext.ParticipantUserIds or {}) do
		if validRestoreTestUserId(userId) then
			table.insert(participantUserIds, userId)
		end
	end

	local loserUserId = validRestoreTestUserId(outcomeContext.LoserUserId) and outcomeContext.LoserUserId or nil
	local clearedRestoreParticipants = {}

	for _, userId in ipairs(participantUserIds) do
		if clearRestoreOfferByUserId(userId, "RoundResolved", now) then
			clearedRestoreParticipants[userId] = true
			if userId ~= loserUserId then
				publishRestoreOfferStateByUserId(userId, now)
			end
		end
	end

	local loserPreLossStreak = positiveInteger(outcomeContext.LoserPreLossStreak) and outcomeContext.LoserPreLossStreak or nil
	local streakProtectedSet = {}
	for _, userId in ipairs(outcomeContext.StreakProtectedLoserUserIds or {}) do
		if validRestoreTestUserId(userId) then
			streakProtectedSet[userId] = true
		end
	end

	local shouldOpenOffer = loserUserId ~= nil
		and loserPreLossStreak ~= nil
		and streakProtectedSet[loserUserId] ~= true

	if loserUserId and clearedRestoreParticipants[loserUserId] and not shouldOpenOffer then
		publishRestoreOfferStateByUserId(loserUserId, now)
	end

	if shouldOpenOffer then
		local restoreRecord = getRestoreOfferRecord(loserUserId, now) or {}
		local cooldownUntil = type(restoreRecord.CooldownUntil) == "number" and restoreRecord.CooldownUntil or 0
		if cooldownUntil > now then
			local selectedProductKey, selectedProductConfig, selectedTier = selectRestoreProduct(loserPreLossStreak)
			local selectedFields =
				buildSelectedRestoreFields(loserUserId, selectedProductKey, selectedProductConfig, selectedTier, loserPreLossStreak)
			restoreOffersByUserId[loserUserId] = {
				Active = false,
				Reason = "CooldownActive",
				RoundId = roundId,
				OpenedAt = restoreRecord.OpenedAt,
				ExpiresAt = nil,
				CooldownUntil = cooldownUntil,
				LoserUserId = loserUserId,
				PreLossStreak = loserPreLossStreak,
				ValidRestoreProductKeys = selectedProductKey and { selectedProductKey } or {},
				SelectedRestoreProductKey = selectedFields.SelectedRestoreProductKey,
				SelectedRestoreProductId = selectedFields.SelectedRestoreProductId,
				SelectedRestoreTier = selectedFields.SelectedRestoreTier,
				ProjectedRestoredStreak = selectedFields.ProjectedRestoredStreak,
			}
			restoreOfferExpiryTokensByUserId[loserUserId] = nil

			DebugService.Info("MONETIZATION", "RESTORE_OFFER_COOLDOWN_BLOCKED", {
				userId = loserUserId,
				roundId = roundId,
				cooldownRemaining = math.max(0, cooldownUntil - now),
			})
			publishRestoreOfferStateByUserId(loserUserId, now)
		else
			local player = resolveRestoreOfferPlayer(loserUserId)
			if player then
				local selectedProductKey, selectedProductConfig, selectedTier = selectRestoreProduct(loserPreLossStreak)
				if not selectedProductKey or not selectedProductConfig or not selectedTier then
					DebugService.Warn("MONETIZATION", "RESTORE_SELECTION_UNAVAILABLE", {
						userId = loserUserId,
						roundId = roundId,
						preLossStreak = loserPreLossStreak,
					})
					publishRestoreOfferStateByUserId(loserUserId, now)
					markRestoreOutcomeProcessed(roundId, now)
					return true
				end

				local restoreConfig = getRestoreOfferConfig()
				local selectedFields =
					buildSelectedRestoreFields(loserUserId, selectedProductKey, selectedProductConfig, selectedTier, loserPreLossStreak)
				restoreOffersByUserId[loserUserId] = {
					Active = true,
					Reason = "ActiveOffer",
					RoundId = roundId,
					OpenedAt = now,
					ExpiresAt = now + restoreConfig.WindowSeconds,
					CooldownUntil = now + restoreConfig.PromptCooldownSeconds,
					LoserUserId = loserUserId,
					PreLossStreak = loserPreLossStreak,
					ValidRestoreProductKeys = { selectedProductKey },
					SelectedRestoreProductKey = selectedFields.SelectedRestoreProductKey,
					SelectedRestoreProductId = selectedFields.SelectedRestoreProductId,
					SelectedRestoreTier = selectedFields.SelectedRestoreTier,
					ProjectedRestoredStreak = selectedFields.ProjectedRestoredStreak,
				}
				clearRestorePromptThrottle(loserUserId)
				scheduleRestoreOfferExpiryPush(loserUserId, roundId, now + restoreConfig.WindowSeconds)

				DebugService.Info("MONETIZATION", "RESTORE_OFFER_OPENED", {
					userId = loserUserId,
					roundId = roundId,
					windowSeconds = restoreConfig.WindowSeconds,
					cooldownSeconds = restoreConfig.PromptCooldownSeconds,
					preLossStreak = loserPreLossStreak,
					selectedProductKey = selectedProductKey,
					selectedTier = selectedTier,
					projectedRestoreStreak = selectedFields.ProjectedRestoredStreak,
				})
				publishRestoreOfferStateByUserId(loserUserId, now)
			else
				DebugService.Info("MONETIZATION", "RESTORE_OFFER_PLAYER_UNAVAILABLE", {
					userId = loserUserId,
					roundId = roundId,
				})
			end
		end
	end

	markRestoreOutcomeProcessed(roundId, now)
	return true
end

function MonetizationService.RunStudioOnlyReceiptTest(player, productKey)
	if not RunService:IsStudio() then
		DebugService.Warn("MONETIZATION", "RECEIPT_TEST_NOT_STUDIO", {
			productKey = tostring(productKey),
		})
		return PRODUCT_DECISION.NotProcessedYet, nil
	end

	if not initialized then
		DebugService.Warn("MONETIZATION", "RECEIPT_TEST_NOT_READY", {
			productKey = tostring(productKey),
		})
		return PRODUCT_DECISION.NotProcessedYet, nil
	end

	if typeof(player) ~= "Instance" or not player:IsA("Player") or not player.Parent then
		DebugService.Warn("MONETIZATION", "RECEIPT_TEST_INVALID_PLAYER", {
			productKey = tostring(productKey),
		})
		return PRODUCT_DECISION.NotProcessedYet, nil
	end

	local productConfig = MonetizationService.GetDeveloperProductConfig(productKey)
	if not productConfig then
		DebugService.Warn("MONETIZATION", "RECEIPT_TEST_UNKNOWN_PRODUCT", {
			playerId = player.UserId,
			productKey = tostring(productKey),
		})
		return PRODUCT_DECISION.NotProcessedYet, nil
	end

	local receiptInfo = {
		PlayerId = player.UserId,
		ProductId = tonumber(productConfig.Id) or 0,
		PurchaseId = string.format("studio_receipt_%s_%d_%d", tostring(productKey), player.UserId, math.floor(os.clock() * 1000)),
	}

	return dispatchReceiptDecision(receiptInfo, productConfig), productConfig
end

function MonetizationService.GetShieldInventoryCap()
	local shieldsConfig = MonetizationConfig.Shields or {}
	return math.max(0, math.floor(tonumber(shieldsConfig.MaxInventory) or 0))
end

function MonetizationService.SetStudioVIPOverride(playerOrUserId, ownsVIP)
	if not RunService:IsStudio() then
		return false
	end

	local userId = resolveUserId(playerOrUserId)
	if not userId then
		return false
	end

	if ownsVIP == nil then
		studioVipOverrides[userId] = nil
	else
		studioVipOverrides[userId] = ownsVIP == true
	end

	vipOwnershipCache[userId] = nil
	publishMonetizationSnapshotByUserId(userId)
	return true
end

function MonetizationService.GetStudioVIPOverrideState(playerOrUserId)
	local value, source = getStudioVipOverrideState(playerOrUserId)
	return {
		value = value,
		source = source,
	}
end

function MonetizationService.PlayerHasVIP(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local userId = player.UserId
	if type(userId) ~= "number" or userId <= 0 then
		return false
	end

	local studioOverrideValue, studioOverrideSource = getStudioVipOverrideState(userId)
	if studioOverrideSource == "forced" or studioOverrideSource == "config" then
		return studioOverrideValue == true
	end

	local cached = vipOwnershipCache[userId]
	local now = os.clock()
	if cached and cached.expiresAt > now then
		return cached.ownsVIP == true
	end

	local vipConfig = MonetizationConfig.VIP or {}
	local vipPassId = getVIPGamePassId()
	local cacheTtl = math.max(1, tonumber(vipConfig.CacheTTLSeconds) or 60)

	if not positiveInteger(vipPassId) then
		vipOwnershipCache[userId] = {
			ownsVIP = false,
			expiresAt = now + cacheTtl,
		}
		return false
	end

	local ok, ownsVIP = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, vipPassId)
	end)

	if not ok then
		DebugService.Warn("MONETIZATION", "VIP_LOOKUP_FAILED", {
			userId = userId,
			gamePassId = vipPassId,
			error = ownsVIP,
		})

		vipOwnershipCache[userId] = {
			ownsVIP = false,
			expiresAt = now + 5,
		}
		return false
	end

	vipOwnershipCache[userId] = {
		ownsVIP = ownsVIP == true,
		expiresAt = now + cacheTtl,
	}

	return ownsVIP == true
end

function MonetizationService.GetRewardMultiplier(player)
	local vipConfig = MonetizationConfig.VIP or {}
	if MonetizationService.PlayerHasVIP(player) then
		return tonumber(vipConfig.CashRewardMultiplier) or 1
	end

	return 1
end

function MonetizationService.GetPlayerMonetizationSnapshot(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local overrideState = MonetizationService.GetStudioVIPOverrideState(player)
	local hasVIP = MonetizationService.PlayerHasVIP(player)
	local vipConfig = MonetizationConfig.VIP or {}
	local vipPassId = getVIPGamePassId()
	local configured = positiveInteger(vipPassId)

	return {
		UserId = player.UserId,
		HasVIP = hasVIP,
		RewardMultiplier = hasVIP and (tonumber(vipConfig.CashRewardMultiplier) or 1) or 1,
		Configured = configured,
		GamePassId = configured and vipPassId or 0,
		StudioOverrideSource = overrideState.source,
		StudioOverrideValue = overrideState.value,
	}
end

function MonetizationService.Init()
	if initialized then
		return
	end

	rebuildIndexes()
	StatsService.SetMaxShields(MonetizationService.GetShieldInventoryCap())
	MarketplaceService.ProcessReceipt = handleReceipt
	processReceiptBound = true

	if not requestRestorePurchaseConnection then
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local requestRestorePurchase = remotes:WaitForChild("RequestRestorePurchase")
		requestRestorePurchaseConnection = requestRestorePurchase.OnServerEvent:Connect(function(player)
			MonetizationService.RequestRestorePurchasePrompt(player)
		end)
	end

	if not playerAddedConnection then
		playerAddedConnection = Players.PlayerAdded:Connect(function(player)
			scheduleMonetizationSnapshotPublish(player)
		end)
	end

	if not playerRemovingConnection then
		playerRemovingConnection = Players.PlayerRemoving:Connect(clearPlayerCache)
	end

	if not promptGamePassPurchaseFinishedConnection then
		promptGamePassPurchaseFinishedConnection = MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return
			end

			local configuredVipPassId = getVIPGamePassId()
			if not positiveInteger(configuredVipPassId) or tonumber(gamePassId) ~= configuredVipPassId then
				return
			end

			if wasPurchased == true then
				local vipConfig = MonetizationConfig.VIP or {}
				vipOwnershipCache[player.UserId] = {
					ownsVIP = true,
					expiresAt = os.clock() + math.max(1, tonumber(vipConfig.CacheTTLSeconds) or 60),
				}
			else
				vipOwnershipCache[player.UserId] = nil
			end

			publishMonetizationSnapshot(player)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		scheduleMonetizationSnapshotPublish(player)
	end

	initialized = true

	DebugService.Info("MONETIZATION", "INIT_READY", {
		gamePassCount = countEntries(MonetizationConfig.GamePasses or {}),
		productCount = countEntries(MonetizationConfig.DeveloperProducts or {}),
		indexedProductCount = countEntries(developerProductsById),
		receiptHandlerKindCount = countEntries(receiptHandlersByKind),
		processReceiptBound = processReceiptBound == true,
		shieldCap = MonetizationService.GetShieldInventoryCap(),
		restoreProductCount = #restoreProductKeys,
	})
end

return MonetizationService
