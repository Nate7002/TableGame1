local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local DebugService = require(script.Parent:WaitForChild("DebugService"))
local StatsService = require(script.Parent:WaitForChild("StatsService"))

local MonetizationService = {}

local PRODUCT_DECISION = Enum.ProductPurchaseDecision

local initialized = false
local playerRemovingConnection = nil
local vipOwnershipCache = {} -- [UserId] = { ownsVIP = boolean, expiresAt = number }
local studioVipOverrides = {} -- [UserId] = boolean (Studio-only in-memory override)
local gamePassesById = {}
local developerProductsById = {}
local receiptHandlers = {}

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

local function resolveUserId(playerOrUserId)
	if positiveInteger(playerOrUserId) then
		return playerOrUserId
	end

	if typeof(playerOrUserId) == "Instance" or type(playerOrUserId) == "table" then
		local userId = playerOrUserId.UserId
		if positiveInteger(userId) then
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

local function registerReceiptHandlers()
	receiptHandlers = {}

	for productId in pairs(developerProductsById) do
		receiptHandlers[productId] = function(receiptInfo, productConfig)
			DebugService.Warn("MONETIZATION", "RECEIPT_UNWIRED_HANDLER", {
				playerId = receiptInfo and receiptInfo.PlayerId,
				productId = receiptInfo and receiptInfo.ProductId,
				purchaseId = receiptInfo and receiptInfo.PurchaseId,
				kind = productConfig and productConfig.Kind,
			})
			return PRODUCT_DECISION.NotProcessedYet
		end
	end
end

local function rebuildIndexes()
	gamePassesById = {}
	developerProductsById = {}

	registerIdMap(MonetizationConfig.GamePasses, gamePassesById, "GamePass")
	registerIdMap(MonetizationConfig.DeveloperProducts, developerProductsById, "DeveloperProduct")
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

local function handleReceipt(receiptInfo)
	local productId = receiptInfo and receiptInfo.ProductId
	local productConfig = MonetizationService.GetDeveloperProductConfig(productId)

	if not productConfig then
		DebugService.Warn("MONETIZATION", "RECEIPT_UNKNOWN_PRODUCT", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = productId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local handler = receiptHandlers[productId]
	if not handler then
		DebugService.Warn("MONETIZATION", "RECEIPT_NO_HANDLER", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = productId,
			purchaseId = receiptInfo and receiptInfo.PurchaseId,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	local ok, decision = pcall(handler, receiptInfo, productConfig)
	if not ok then
		DebugService.Warn("MONETIZATION", "RECEIPT_HANDLER_FAILED", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = productId,
			error = decision,
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	if decision ~= PRODUCT_DECISION.PurchaseGranted and decision ~= PRODUCT_DECISION.NotProcessedYet then
		DebugService.Warn("MONETIZATION", "RECEIPT_INVALID_DECISION", {
			playerId = receiptInfo and receiptInfo.PlayerId,
			productId = productId,
			decision = tostring(decision),
		})
		return PRODUCT_DECISION.NotProcessedYet
	end

	return decision
end

function MonetizationService.GetGamePassConfig(keyOrId)
	return getConfigEntry(MonetizationConfig.GamePasses, gamePassesById, keyOrId)
end

function MonetizationService.GetDeveloperProductConfig(keyOrId)
	return getConfigEntry(MonetizationConfig.DeveloperProducts, developerProductsById, keyOrId)
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
	local vipPass = MonetizationService.GetGamePassConfig(vipConfig.GamePassKey or "VIP")
	local vipPassId = vipPass and vipPass.Id or 0
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

	return {
		UserId = player.UserId,
		HasVIP = hasVIP,
		RewardMultiplier = hasVIP and (tonumber(vipConfig.CashRewardMultiplier) or 1) or 1,
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

	if not playerRemovingConnection then
		playerRemovingConnection = Players.PlayerRemoving:Connect(clearPlayerCache)
	end

	initialized = true

	DebugService.Info("MONETIZATION", "INIT_READY", {
		gamePassCount = countEntries(MonetizationConfig.GamePasses or {}),
		productCount = countEntries(MonetizationConfig.DeveloperProducts or {}),
		receiptHandlerCount = countEntries(receiptHandlers),
		shieldCap = MonetizationService.GetShieldInventoryCap(),
	})
end

return MonetizationService
