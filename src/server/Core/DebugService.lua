local DebugService = {}

-- =============================
-- Configuration
-- =============================

local LOG_LEVELS = {
	TRACE = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4
}

local currentLevel = LOG_LEVELS.INFO
local bufferSize = 200
local logBuffer = {}
local suppressedInfoTags = {
	STATS = {
		MAX_SHIELDS_UPDATED = true,
		SHIELD_ARM_ALREADY = true,
		SHIELD_ARM_FAILED_NO_INVENTORY = true,
		SHIELD_DISARMED = true,
		ROUND_NEUTRAL = true,
		ROUND_ABORTED = true,
		ROUND_SHIELD_CONSUME = true,
	},
}

-- Optional metadata context
local globalContext = {}

-- =============================
-- Internal Helpers
-- =============================

local function formatPayload(payload)
	if type(payload) ~= "table" then
		return tostring(payload)
	end

	local parts = {}
	for k, v in pairs(payload) do
		table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
	end

	return table.concat(parts, " ")
end

local function pushToBuffer(entry)
	table.insert(logBuffer, entry)
	if #logBuffer > bufferSize then
		table.remove(logBuffer, 1)
	end
end

-- =============================
-- Public API
-- =============================

function DebugService.SetLevel(levelName)
	if LOG_LEVELS[levelName] then
		currentLevel = LOG_LEVELS[levelName]
	end
end

function DebugService.SetContext(contextTable)
	globalContext = contextTable or {}
end

function DebugService.GetBuffer()
	return logBuffer
end

local function isSuppressed(levelName, system, tag)
	if levelName ~= "INFO" then
		return false
	end

	local systemTags = suppressedInfoTags[system]
	return systemTags and systemTags[tag] == true or false
end

function DebugService.Log(levelName, system, tag, payload)
	local level = LOG_LEVELS[levelName] or LOG_LEVELS.INFO

	if level < currentLevel then
		return
	end

	if isSuppressed(levelName, system, tag) then
		return
	end

	local contextStr = formatPayload(globalContext)
	local payloadStr = formatPayload(payload)

	local timestamp = os.date("%H:%M:%S")

	local message = string.format(
		"[%s][%s][%s][%s] %s %s",
		timestamp,
		levelName,
		system,
		tag,
		contextStr,
		payloadStr
	)

	if levelName == "ERROR" then
		error(message)
	elseif levelName == "WARN" then
		warn(message)
	else
		print(message)
	end
	pushToBuffer(message)
end

function DebugService.Trace(system, tag, payload)
	DebugService.Log("TRACE", system, tag, payload)
end

function DebugService.Info(system, tag, payload)
	DebugService.Log("INFO", system, tag, payload)
end

function DebugService.Warn(system, tag, payload)
	DebugService.Log("WARN", system, tag, payload)
end

function DebugService.Error(system, tag, payload)
	DebugService.Log("ERROR", system, tag, payload)
end

return DebugService
