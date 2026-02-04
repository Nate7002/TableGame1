local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataService = {}

-- Constants
local DATASTORE_NAMESPACE = RunService:IsStudio() and "DEV" or "PROD"
local DATASTORE_NAME = "TableGame1_v1_" .. DATASTORE_NAMESPACE
local KEY_PREFIX = "p_"
local SCHEMA_VERSION = 1
local RETRY_ATTEMPTS = 3
local RETRY_DELAYS = {1, 2, 4} -- Backoff in seconds
local SAVE_THROTTLE = 10 -- Minimum seconds between saves per player
local AUTOSAVE_INTERVAL = 120 -- Autosave every 2 minutes
local SHUTDOWN_SAVE_TIMEOUT = 10 -- Max time to spend saving on shutdown

-- State
local dataStore = nil
local cache = {} -- [UserId] = {v, stats, updatedAt}
local lastSaveTime = {} -- [UserId] = os.clock()
local apiEnabled = true
local autosaveConnection = nil

-- Helper: Default data structure
local function getDefaultData()
	return {
		v = SCHEMA_VERSION,
		stats = {
			Cash = 0,
			Wins = 0,
			Streak = 0,
			MaxStreak = 0,
			GamesPlayed = 0,
			TotalDonated = 0
		},
		updatedAt = os.time()
	}
end

-- Helper: Validate and sanitize loaded data
local function sanitizeData(data)
	if type(data) ~= "table" then
		return getDefaultData()
	end
	
	-- Ensure schema
	data.v = data.v or SCHEMA_VERSION
	data.stats = data.stats or {}
	data.stats.Cash = data.stats.Cash or 0
	data.stats.Wins = data.stats.Wins or 0
	data.stats.Streak = data.stats.Streak or 0
	data.stats.MaxStreak = data.stats.MaxStreak or 0
	data.stats.GamesPlayed = data.stats.GamesPlayed or 0
	data.stats.TotalDonated = data.stats.TotalDonated or 0
	data.updatedAt = data.updatedAt or os.time()
	
	return data
end

-- Helper: Retry wrapper for datastore operations
local function retryOperation(operationName, operationFunc)
	for attempt = 1, RETRY_ATTEMPTS do
		local success, result = pcall(operationFunc)
		if success then
			return true, result
		else
			if attempt < RETRY_ATTEMPTS then
				local delay = RETRY_DELAYS[attempt]
				warn(string.format("[DataService] %s failed (attempt %d/%d): %s. Retrying in %ds...", 
					operationName, attempt, RETRY_ATTEMPTS, tostring(result), delay))
				task.wait(delay)
			else
				warn(string.format("[DataService] %s failed after %d attempts: %s", 
					operationName, RETRY_ATTEMPTS, tostring(result)))
				return false, result
			end
		end
	end
	return false, "Max retries exceeded"
end

-- Public API

function DataService.Init()
	print("[DataService] Initializing...")
	
	-- Attempt to get DataStore
	local success, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	
	if success then
		dataStore = result
		apiEnabled = true
		print("[DataService] DataStore connected:", DATASTORE_NAME)
	else
		warn("[DataService] DataStore API disabled or failed:", result)
		apiEnabled = false
		-- Game continues without saving
	end
	
	-- Start autosave loop
	if apiEnabled then
		autosaveConnection = task.spawn(function()
			while true do
				task.wait(AUTOSAVE_INTERVAL)
				DataService.AutosaveAll()
			end
		end)
	end
	
	-- Bind to shutdown
	game:BindToClose(function()
		print("[DataService] Shutdown triggered - saving all players...")
		DataService.SaveAllOnShutdown()
	end)
	
	print("[DataService] Ready.")
end

function DataService.LoadPlayer(player)
	if not apiEnabled or not dataStore then
		warn("[DataService] LoadPlayer: API disabled")
		return nil
	end
	
	local userId = player.UserId
	local key = KEY_PREFIX .. tostring(userId)
	
	local success, data = retryOperation("LoadPlayer", function()
		return dataStore:GetAsync(key)
	end)
	
	if success then
		if data then
			data = sanitizeData(data)
			cache[userId] = data
			print(string.format("[DataService] Loaded %s: Cash=%d, Wins=%d, Streak=%d, MaxStreak=%d", 
				player.Name, data.stats.Cash, data.stats.Wins, data.stats.Streak, data.stats.MaxStreak))
			return data
		else
			-- New player
			local defaultData = getDefaultData()
			cache[userId] = defaultData
			print(string.format("[DataService] New player %s - using defaults", player.Name))
			return defaultData
		end
	else
		-- Load failed, use defaults but don't cache
		warn(string.format("[DataService] Load failed for %s - using defaults", player.Name))
		return getDefaultData()
	end
end

function DataService.SavePlayer(player, data, reason)
	if not apiEnabled or not dataStore then
		return false
	end
	
	if not (player and player.Parent) then
		return false
	end
	
	local userId = player.UserId
	local key = KEY_PREFIX .. tostring(userId)
	
	-- Throttle saves (except for critical reasons)
	local now = os.clock()
	local lastSave = lastSaveTime[userId] or 0
	local timeSinceLastSave = now - lastSave
	
	if timeSinceLastSave < SAVE_THROTTLE then
		if reason ~= "PlayerRemoving" and reason ~= "Shutdown" then
			-- Throttled - update cache but skip save
			cache[userId] = data
			return false
		end
	end
	
	-- Update cache
	cache[userId] = data
	lastSaveTime[userId] = now
	
	-- Save to DataStore using UpdateAsync (merge with existing data)
	local success, result = retryOperation("SavePlayer", function()
		return dataStore:UpdateAsync(key, function(existingData)
			existingData = existingData or {}
			
			-- Merge: preserve v, overwrite stats, update timestamp
			existingData.v = SCHEMA_VERSION
			existingData.stats = data.stats or existingData.stats or {}
			existingData.updatedAt = os.time()
			
			return existingData
		end)
	end)
	
	if success then
		print(string.format("[DataService] Saved %s (%s): Cash=%d, Wins=%d, Streak=%d", 
			player.Name, reason or "manual", data.stats.Cash, data.stats.Wins, data.stats.Streak))
		return true
	else
		warn(string.format("[DataService] Save failed for %s (%s)", player.Name, reason or "manual"))
		return false
	end
end

function DataService.GetCached(player)
	if not player then return nil end
	return cache[player.UserId]
end

function DataService.SetCached(player, data)
	if not player then return end
	cache[player.UserId] = data
end

function DataService.AutosaveAll()
	if not apiEnabled then return end
	
	print("[DataService] Autosave triggered")
	local savedCount = 0
	local failedCount = 0
	
	-- Time-slice to avoid spikes: save one player per frame
	for userId, data in pairs(cache) do
		local player = Players:GetPlayerByUserId(userId)
		if player and player.Parent then
			local success = DataService.SavePlayer(player, data, "Autosave")
			if success then
				savedCount = savedCount + 1
			else
				failedCount = failedCount + 1
			end
			task.wait() -- Yield to spread load
		end
	end
	
	if savedCount > 0 or failedCount > 0 then
		print(string.format("[DataService] Autosave complete: %d saved, %d failed", savedCount, failedCount))
	end
end

function DataService.SaveAllOnShutdown()
	if not apiEnabled then return end
	
	local startTime = os.clock()
	local savedCount = 0
	local failedCount = 0
	
	for userId, data in pairs(cache) do
		-- Check timeout
		if os.clock() - startTime > SHUTDOWN_SAVE_TIMEOUT then
			warn("[DataService] Shutdown save timeout reached - stopping")
			break
		end
		
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local success = DataService.SavePlayer(player, data, "Shutdown")
			if success then
				savedCount = savedCount + 1
			else
				failedCount = failedCount + 1
			end
		end
	end
	
	local duration = os.clock() - startTime
	print(string.format("[DataService] Shutdown save complete: %d saved, %d failed, %.2fs elapsed", 
		savedCount, failedCount, duration))
end

function DataService.ClearCache(userId)
	cache[userId] = nil
	lastSaveTime[userId] = nil
end

function DataService.IsApiEnabled()
	return apiEnabled
end

function DataService.GetNamespace()
	return DATASTORE_NAMESPACE
end

return DataService

