-- LeaderboardService: Weekly + Overall in-world leaderboards (MaxStreak, GamesPlayed, Donations).
-- OrderedDataStores; weekly reset Monday 00:00 UTC. Optimized, resilient, safe on player leave.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local DataService = require(script.Parent:WaitForChild("DataService"))
local StatsService = require(script.Parent:WaitForChild("StatsService"))
local DebugService = require(script.Parent:WaitForChild("DebugService"))

local LeaderboardService = {}

-- Constants
local TOP_N = 10
local ROTATE_INTERVAL = 30
local ROTATE_TWEEN_DURATION = 1
local REFRESH_INTERVAL = 120 -- 2 min; not tied to rotation
local WRITE_DEBOUNCE = 15 -- seconds per (userId, category, scope)
local FLUSH_INTERVAL = 60 -- periodic flush of dirty writes
local READ_CACHE_TTL = 45 -- seconds to cache GetTop results
local STAGGER_DELAY = 1.5 -- seconds between category reads on refresh
local HEADER_FADE_DURATION = 0.15
local GET_SORTED_RETRIES = 2

local CATEGORIES = { "MaxStreak", "GamesPlayed", "Donations" }
local SCOPE_OVERALL = "Overall"
local SCOPE_WEEKLY = "Weekly"
local BOARD_NAMES = { LB_MaxStreak = "MaxStreak", LB_GamesPlayed = "GamesPlayed", LB_Donations = "Donations" }
-- Clean header titles
local HEADER_TITLES = { MaxStreak = "Max Streak", GamesPlayed = "Games Played", Donations = "Donations" }

-- Stat key mapping: category -> { overall = statKey, weekly = statKey }
local STAT_KEYS = {
	MaxStreak = { overall = "MaxStreak", weekly = "WeeklyMaxStreak" },
	GamesPlayed = { overall = "GamesPlayed", weekly = "WeeklyGamesPlayed" },
	Donations = { overall = "TotalDonated", weekly = "WeeklyDonations" },
}

-- State
local apiEnabled = true
local overallStores = {} -- [category] = OrderedDataStore
local weeklyStores = {} -- [namespace][weekKey][category] = OrderedDataStore
local lastWriteTime = {} -- [userId_category_scope] = tick()
local dirtySet = {} -- [userId_category_scope] = true when pending write
local nameCache = {} -- [userId] = username
local nameLookupCooldown = 0 -- tick() of last lookup; rate limit
local NAME_LOOKUP_MIN_GAP = 0.5
local readCache = {} -- [category_scope] = { entries = {}, expiresAt = tick() }
local rotateCountdown = ROTATE_INTERVAL
local weeklyOnFront = true
local NAMESPACE = "PROD"

local function resolveNamespace()
	if type(DataService.GetNamespace) == "function" then
		local ok, ns = pcall(DataService.GetNamespace, DataService)
		if ok and type(ns) == "string" and ns ~= "" then
			return ns
		end
	end
	if RunService:IsStudio() then
		return "DEV"
	end
	return "PROD"
end

function LeaderboardService.InvalidateReadCache()
	readCache = {}
end

-- ---------------------------------------------------------------------------
-- UTC Week helpers (Monday 00:00 UTC)
-- ---------------------------------------------------------------------------
local function getMondayUTC(now)
	local t = os.date("*t", now)
	local daysBack = (t.wday - 2) % 7
	if daysBack == 0 and t.hour == 0 and t.min == 0 and t.sec == 0 then
		return now
	end
	local mondayTime = now - (daysBack * 24 * 3600) - (t.hour * 3600 + t.min * 60 + t.sec)
	local mt = os.date("*t", mondayTime)
	return os.time({ year = mt.year, month = mt.month, day = mt.day, hour = 0, min = 0, sec = 0 })
end

function LeaderboardService.getWeekKeyUTC(now)
	now = now or os.time()
	local monday = getMondayUTC(now)
	local t = os.date("*t", monday)
	return string.format("%04d_%02d_%02d", t.year, t.month, t.day)
end

function LeaderboardService.getNextResetUTC(now)
	now = now or os.time()
	local thisMonday = getMondayUTC(now)
	return thisMonday + (7 * 24 * 3600)
end

function LeaderboardService.secondsUntilNextReset(now)
	now = now or os.time()
	local nextReset = LeaderboardService.getNextResetUTC(now)
	return math.max(0, nextReset - now)
end

-- ---------------------------------------------------------------------------
-- OrderedDataStore access (cached; API disabled => nil, no throw)
-- ---------------------------------------------------------------------------
local function getOverallStore(category)
	if not apiEnabled then return nil end
	if not NAMESPACE then
		NAMESPACE = resolveNamespace()
	end
	if not overallStores[category] then
		local storeName = "LB_" .. NAMESPACE .. "_OVERALL_" .. category:upper()
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(storeName)
		end)
		if ok and store then
			overallStores[category] = store
		else
			DebugService.Warn("LEADERBOARD", "STORE_FAIL", { ns = tostring(NAMESPACE), storeName = storeName })
		end
	end
	return overallStores[category]
end

local function getWeeklyStore(category, weekKey)
	if not apiEnabled then return nil end
	if not NAMESPACE then
		NAMESPACE = resolveNamespace()
	end
	weeklyStores[NAMESPACE] = weeklyStores[NAMESPACE] or {}
	weeklyStores[NAMESPACE][weekKey] = weeklyStores[NAMESPACE][weekKey] or {}
	if not weeklyStores[NAMESPACE][weekKey][category] then
		local storeName = "LB_" .. NAMESPACE .. "_WEEKLY_" .. weekKey .. "_" .. category:upper()
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(storeName)
		end)
		if ok and store then
			weeklyStores[NAMESPACE][weekKey][category] = store
		else
			DebugService.Warn("LEADERBOARD", "STORE_FAIL", { ns = tostring(NAMESPACE), storeName = storeName })
		end
	end
	return weeklyStores[NAMESPACE][weekKey][category]
end

-- ---------------------------------------------------------------------------
-- Username resolution: cache + rate limit; fallback "@userId"
-- ---------------------------------------------------------------------------
local function getUsername(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local now = tick()
	if now - nameLookupCooldown < NAME_LOOKUP_MIN_GAP then
		return "@" .. tostring(userId)
	end
	nameLookupCooldown = now
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = (ok and name and name ~= "") and name or ("@" .. tostring(userId))
	nameCache[userId] = result
	return result
end

-- ---------------------------------------------------------------------------
-- Writes: debounce + dirty queue + flush on leave and periodic
-- ---------------------------------------------------------------------------
local function writeKey(userId, category, scope, value)
	local key = userId .. "_" .. category .. "_" .. scope
	local weekKey = LeaderboardService.getWeekKeyUTC()
	local store = scope == SCOPE_OVERALL and getOverallStore(category) or getWeeklyStore(category, weekKey)
	if not store then return false end
	local ok = pcall(function()
		store:SetAsync(tostring(userId), value)
	end)
	if not ok then
		dirtySet[key] = true
		DebugService.Warn("LEADERBOARD", "WRITE_FAIL", { ns = tostring(NAMESPACE), scope = scope, category = category, userId = userId, value = tostring(value) })
		return false
	end
	return true
end

local function markWritten(userId, category, scope)
	local key = userId .. "_" .. category .. "_" .. scope
	lastWriteTime[key] = tick()
	dirtySet[key] = nil
end

local function shouldDebounce(userId, category, scope)
	local key = userId .. "_" .. category .. "_" .. scope
	local last = lastWriteTime[key] or 0
	return (tick() - last) < WRITE_DEBOUNCE
end

-- Last known stats per userId (for flush on leave)
local lastKnownStats = {}

local function updatePlayerInStores(userId, stats, force)
	if not stats then return end
	lastKnownStats[userId] = stats

	for _, cat in ipairs(CATEGORIES) do
		local keys = STAT_KEYS[cat]
		local overallVal = (keys and stats[keys.overall]) or stats[cat] or 0
		local weeklyVal = (keys and stats[keys.weekly]) or 0
		if type(overallVal) ~= "number" then overallVal = 0 end
		if type(weeklyVal) ~= "number" then weeklyVal = 0 end

		local keyO = userId .. "_" .. cat .. "_" .. SCOPE_OVERALL
		local keyW = userId .. "_" .. cat .. "_" .. SCOPE_WEEKLY

		if force or not shouldDebounce(userId, cat, SCOPE_OVERALL) then
			local ok = writeKey(userId, cat, SCOPE_OVERALL, overallVal)
			if ok then
				markWritten(userId, cat, SCOPE_OVERALL)
			else
				dirtySet[keyO] = true
				lastWriteTime[keyO] = tick()
			end
		else
			dirtySet[keyO] = true
		end

		if force or not shouldDebounce(userId, cat, SCOPE_WEEKLY) then
			local ok = writeKey(userId, cat, SCOPE_WEEKLY, weeklyVal)
			if ok then
				markWritten(userId, cat, SCOPE_WEEKLY)
			else
				dirtySet[keyW] = true
				lastWriteTime[keyW] = tick()
			end
		else
			dirtySet[keyW] = true
		end
	end
end

-- Flush all dirty for a userId using last known stats (call on PlayerRemoving)
local function flushDirtyForPlayer(userId)
	local stats = lastKnownStats[userId]
	if stats then
		updatePlayerInStores(userId, stats, true)
	end
	lastKnownStats[userId] = nil
end

-- Periodic flush: only players with pending dirty writes
local function flushDirtyPeriodic()
	local userIdsToFlush = {}
	for key in pairs(dirtySet) do
		local userId = tonumber(key:match("^(%d+)_"))
		if userId and not userIdsToFlush[userId] then
			userIdsToFlush[userId] = true
		end
	end
	for userId in pairs(userIdsToFlush) do
		local stats = lastKnownStats[userId]
		if stats then
			updatePlayerInStores(userId, stats, true)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Reading: cache + retry + stagger
-- ---------------------------------------------------------------------------
local function getCachedKey(category, scope)
	return category .. "_" .. scope
end

local function readTopFromStore(store, category, scope)
	if not store then return {} end
	for attempt = 1, GET_SORTED_RETRIES do
		local ok, result = pcall(function()
			return store:GetSortedAsync(false, TOP_N)
		end)
		if ok and result then
			local entries = {}
			local page = result:GetCurrentPage()
			for i, data in ipairs(page) do
				local uid = tonumber(data.key) or data.key
				table.insert(entries, {
					rank = i,
					userId = uid,
					username = getUsername(uid),
					value = data.value
				})
			end
			return entries
		end
		if attempt < GET_SORTED_RETRIES then
			task.wait(0.5)
		end
	end
	return {}
end

function LeaderboardService.GetTop(category, scope)
	local ckey = getCachedKey(category, scope)
	local cached = readCache[ckey]
	if cached and tick() <= cached.expiresAt then
		return cached.entries
	end

	local store
	if scope == SCOPE_OVERALL then
		store = getOverallStore(category)
	else
		store = getWeeklyStore(category, LeaderboardService.getWeekKeyUTC())
	end

	local entries = readTopFromStore(store, category, scope)
	if not apiEnabled then
		entries = {}
	end
	readCache[ckey] = { entries = entries, expiresAt = tick() + READ_CACHE_TTL }
	return entries
end

-- ---------------------------------------------------------------------------
-- World UI: safe folder access
-- ---------------------------------------------------------------------------
local function getLeaderboardsFolder()
	local map = Workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Leaderboards") or nil
end

local function clearGeneratedRows(scrollingFrame)
	local layout = scrollingFrame:FindFirstChild("UIListLayout")
	local template = scrollingFrame:FindFirstChild("Template")
	local titles = scrollingFrame:FindFirstChild("Titles")
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child ~= layout and child ~= template and child ~= titles then
			child:Destroy()
		end
	end
end

local function findLabelInTemplate(template, name)
	local l = template:FindFirstChild(name)
	if l then return l end
	for _, child in ipairs(template:GetChildren()) do
		l = child:FindFirstChild(name)
		if l then return l end
	end
	return nil
end

local function setRowFromTemplate(template, rank, username, value)
	local r = findLabelInTemplate(template, "Rank")
	local u = findLabelInTemplate(template, "Username")
	local v = findLabelInTemplate(template, "Value")
	if r then r.Text = tostring(rank) end
	if u then u.Text = username end
	if v then v.Text = tostring(value) end
end

local function populateScrollingFrame(scrollingFrame, entries)
	if not scrollingFrame then return end
	local template = scrollingFrame:FindFirstChild("Template")
	if not template then return end
	if not findLabelInTemplate(template, "Rank") and not findLabelInTemplate(template, "Username") and not findLabelInTemplate(template, "Value") then
		return
	end
	clearGeneratedRows(scrollingFrame)
	template.Visible = false
	for i, e in ipairs(entries) do
		local row = template:Clone()
		row.Name = "Row_" .. string.format("%02d", i)
		row.Visible = true
		setRowFromTemplate(row, e.rank, e.username, e.value)
		row.Parent = scrollingFrame
	end
end

local function setupHeaderLabel(gui, text)
	local nameLabel = gui:FindFirstChild("Name")
	if not nameLabel then
		for _, c in ipairs(gui:GetChildren()) do
			if c:IsA("TextLabel") then
				nameLabel = c
				c.Name = "Name"
				break
			end
		end
	end
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("TextLabel") then
			c.Visible = (c == nameLabel)
		end
	end
	if nameLabel then
		nameLabel.Text = text
		nameLabel.TextScaled = true
		nameLabel.Size = UDim2.fromScale(1, 1)
		nameLabel.Position = UDim2.fromScale(0, 0)
		nameLabel.AnchorPoint = Vector2.new(0, 0)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	end
	return nameLabel
end

local function getHeaderTitle(categoryName)
	local title = HEADER_TITLES[categoryName] or categoryName
	return title
end

local function setHeaderTextsForBoard(boardModel, categoryName)
	local header = boardModel:FindFirstChild("Header")
	if not header then return end

	local title = getHeaderTitle(categoryName)
	local weeklyText = "Weekly " .. title
	local frontText = weeklyOnFront and weeklyText or title
	local backText = weeklyOnFront and title or weeklyText

	local frontHeaderGui = header:FindFirstChild("SurfaceGui")
	local backHeaderGui = header:FindFirstChild("SurfaceGui_Back")
	if frontHeaderGui then
		setupHeaderLabel(frontHeaderGui, frontText)
	end
	if backHeaderGui then
		setupHeaderLabel(backHeaderGui, backText)
	end
end

local function applyAllHeaderTexts()
	local leaderboards = getLeaderboardsFolder()
	if not leaderboards then return end

	for modelName, categoryName in pairs(BOARD_NAMES) do
		local board = leaderboards:FindFirstChild(modelName)
		if board then
			setHeaderTextsForBoard(board, categoryName)
		end
	end
end

local function ensureBackFaceAndHeaders(boardModel, categoryName)
	local details = boardModel:FindFirstChild("Details")
	local header = boardModel:FindFirstChild("Header")
	if not details or not header then return end

	local frontGui = details:FindFirstChild("SurfaceGui")
	if frontGui and not details:FindFirstChild("SurfaceGui_Back") then
		local backGui = frontGui:Clone()
		backGui.Name = "SurfaceGui_Back"
		backGui.Face = Enum.NormalId.Back
		backGui.Parent = details
	end

	local frontHeaderGui = header:FindFirstChild("SurfaceGui")
	if frontHeaderGui and not header:FindFirstChild("SurfaceGui_Back") then
		local backHeaderGui = frontHeaderGui:Clone()
		backHeaderGui.Name = "SurfaceGui_Back"
		backHeaderGui.Face = Enum.NormalId.Back
		backHeaderGui.Parent = header
	end

	setHeaderTextsForBoard(boardModel, categoryName)
end

local function updateBoardUI(boardModel, categoryName)
	local details = boardModel:FindFirstChild("Details")
	if not details then return end
	local frontGui = details:FindFirstChild("SurfaceGui")
	local backGui = details:FindFirstChild("SurfaceGui_Back")
	if not frontGui then return end

	local weeklyEntries = LeaderboardService.GetTop(categoryName, SCOPE_WEEKLY)
	local overallEntries = LeaderboardService.GetTop(categoryName, SCOPE_OVERALL)
	if not apiEnabled then
		weeklyEntries = {}
		overallEntries = {}
	end

	local frontScroll = frontGui:FindFirstChild("ScrollingFrame")
	local backScroll = backGui and backGui:FindFirstChild("ScrollingFrame") or nil
	populateScrollingFrame(frontScroll, weeklyEntries)
	if backScroll then
		populateScrollingFrame(backScroll, overallEntries)
	end
end

local function bindAllBoards()
	local leaderboards = getLeaderboardsFolder()
	if not leaderboards then return end

	for modelName, categoryName in pairs(BOARD_NAMES) do
		local board = leaderboards:FindFirstChild(modelName)
		if board then
			ensureBackFaceAndHeaders(board, categoryName)
			updateBoardUI(board, categoryName)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Rotation: Details only, header text swaps like an open sign
-- ---------------------------------------------------------------------------
local function getAllHeaderLabels()
	local leaderboards = getLeaderboardsFolder()
	if not leaderboards then return {} end
	local labels = {}
	for modelName in pairs(BOARD_NAMES) do
		local board = leaderboards:FindFirstChild(modelName)
		if board then
			local header = board:FindFirstChild("Header")
			if header then
				for _, guiName in ipairs({ "SurfaceGui", "SurfaceGui_Back" }) do
					local gui = header:FindFirstChild(guiName)
					if gui then
						local nameLabel = gui:FindFirstChild("Name")
						if nameLabel and nameLabel:IsA("TextLabel") then
							table.insert(labels, nameLabel)
						end
					end
				end
			end
		end
	end
	return labels
end

local function fadeHeaderLabels(toTransparency, durationSec)
	local labels = getAllHeaderLabels()
	durationSec = durationSec or HEADER_FADE_DURATION
	for _, label in ipairs(labels) do
		local tweenInfo = TweenInfo.new(durationSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(label, tweenInfo, { TextTransparency = toTransparency })
		tween:Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, tweenInfo, { Transparency = toTransparency }):Play()
		end
	end
	task.wait(durationSec)
end

local function rotateAllBoards()
	local leaderboards = getLeaderboardsFolder()
	if not leaderboards then return end

	local partsToRotate = {}
	for modelName in pairs(BOARD_NAMES) do
		local board = leaderboards:FindFirstChild(modelName)
		if board then
			local details = board:FindFirstChild("Details")
			if details and details:IsA("BasePart") then
				table.insert(partsToRotate, details)
			end
		end
	end
	if #partsToRotate == 0 then return end

	task.spawn(function()
		fadeHeaderLabels(1, HEADER_FADE_DURATION)

		weeklyOnFront = not weeklyOnFront
		applyAllHeaderTexts()

		local startTime = tick()
		local startCFrames = {}
		local endCFrames = {}
		for _, part in ipairs(partsToRotate) do
			startCFrames[part] = part.CFrame
			endCFrames[part] = part.CFrame * CFrame.Angles(0, math.rad(180), 0)
		end
		local alpha = 0
		repeat
			local elapsed = tick() - startTime
			alpha = math.min(1, elapsed / ROTATE_TWEEN_DURATION)
			alpha = 1 - (1 - alpha) ^ 2
			for _, part in ipairs(partsToRotate) do
				part.CFrame = startCFrames[part]:Lerp(endCFrames[part], alpha)
			end
			task.wait()
		until alpha >= 1

		bindAllBoards()

		fadeHeaderLabels(0, HEADER_FADE_DURATION)
	end)
end

-- ---------------------------------------------------------------------------
-- Countdown UI
-- ---------------------------------------------------------------------------
local function ensureCountdownParts()
	local leaderboards = getLeaderboardsFolder()
	if not leaderboards then return end

	local function setupLabel(part, labelName)
		local gui = part and part:FindFirstChildOfClass("SurfaceGui")
		if not gui then return end
		local label = gui:FindFirstChild(labelName)
		if not label then
			for _, c in ipairs(gui:GetChildren()) do
				if c:IsA("TextLabel") then
					c.Name = labelName
					label = c
					break
				end
			end
		end
		if label then
			label.TextScaled = true
			label.Size = UDim2.fromScale(1, 1)
			label.Position = UDim2.fromScale(0, 0)
			label.AnchorPoint = Vector2.new(0, 0)
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center
			if not label:FindFirstChildOfClass("UIStroke") then
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = 1
				stroke.Parent = label
			end
		end
	end

	setupLabel(leaderboards:FindFirstChild("CountdownSpin"), "RotateText")
	setupLabel(leaderboards:FindFirstChild("CountdownReset"), "ResetText")
end

local function formatResetCountdown(seconds)
	local d = math.floor(seconds / 86400)
	local h = math.floor((seconds % 86400) / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d:%02d:%02d", d, h, m, s)
end

local function updateCountdownUI()
	local leaderboards = getLeaderboardsFolder()
	if not leaderboards then return end

	local spinPart = leaderboards:FindFirstChild("CountdownSpin")
	if spinPart then
		local gui = spinPart:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChild("RotateText")
		if label then
			label.Text = "Rotating in: " .. tostring(math.ceil(rotateCountdown)) .. " Seconds"
		end
	end

	local resetPart = leaderboards:FindFirstChild("CountdownReset")
	if resetPart then
		local gui = resetPart:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChild("ResetText")
		if label then
			local secs = LeaderboardService.secondsUntilNextReset()
			label.Text = "Leaderboards reset in: " .. formatResetCountdown(secs)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function LeaderboardService.Init()
	NAMESPACE = resolveNamespace()
	DebugService.Info("LEADERBOARD", "NAMESPACE", { ns = NAMESPACE })

	apiEnabled = DataService.IsApiEnabled()
	if not apiEnabled then
		DebugService.Warn("LEADERBOARD", "API_DISABLED", {})
	end

	ensureCountdownParts()
	bindAllBoards()

	-- Initial write for loaded players
	for _, player in ipairs(Players:GetPlayers()) do
		if player and player.Parent then
			local stats = StatsService.GetStats(player)
			if stats then
				updatePlayerInStores(player.UserId, stats, true)
			end
		end
	end

	-- Stats changed: coalesce (debounced) + track for flush
	StatsService.StatsChanged:Connect(function(player)
		if not player or not player.Parent then return end
		local stats = StatsService.GetStats(player)
		if stats then
			updatePlayerInStores(player.UserId, stats, false)
			LeaderboardService.InvalidateReadCache()
			bindAllBoards()
		end
	end)

	-- Flush on player leave (persist last stats)
	Players.PlayerRemoving:Connect(function(player)
		local userId = player and player.UserId
		if userId then
			flushDirtyForPlayer(userId)
		end
	end)

	local lastRefresh = tick()
	local lastFlush = tick()

	-- Rotation + countdown loop (every 1s)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = tick()

			rotateCountdown = rotateCountdown - 1
			if rotateCountdown <= 0 then
				rotateCountdown = ROTATE_INTERVAL
				rotateAllBoards()
			end
			updateCountdownUI()

			-- Refresh UI at REFRESH_INTERVAL (staggered reads)
			if now - lastRefresh >= REFRESH_INTERVAL then
				lastRefresh = now
				readCache = {}
				for _, categoryName in pairs(BOARD_NAMES) do
					LeaderboardService.GetTop(categoryName, SCOPE_WEEKLY)
					task.wait(STAGGER_DELAY)
					LeaderboardService.GetTop(categoryName, SCOPE_OVERALL)
					task.wait(STAGGER_DELAY)
				end
				bindAllBoards()
			end

			-- Periodic flush dirty
			if now - lastFlush >= FLUSH_INTERVAL then
				lastFlush = now
				flushDirtyPeriodic()
			end
		end
	end)

	DebugService.Info("LEADERBOARD", "INIT_COMPLETE", {})
end

return LeaderboardService
