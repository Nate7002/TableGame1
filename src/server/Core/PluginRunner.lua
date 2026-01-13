local Core = script.Parent
local PluginRegistry = require(Core.PluginRegistry)

local PluginRunner = {}

-- Public API
function PluginRunner.Run(pluginName, context)
	local startTime = os.clock()
	
	-- 1. Locate Plugin
	local module = PluginRegistry.Get(pluginName)
	if not module then
		return {
			ok = false,
			meta = { error = "Plugin not found: " .. tostring(pluginName) }
		}
	end
	
	-- 2. Load Module
	local success, plugin = pcall(require, module)
	if not success then
		warn("[PluginRunner] Failed to require plugin: " .. pluginName)
		return {
			ok = false,
			meta = { error = "Require failed: " .. tostring(plugin) }
		}
	end
	
	-- 3. Check Contract
	local runFunc = plugin.Run or plugin.Start
	if typeof(runFunc) ~= "function" then
		return {
			ok = false,
			meta = { error = "Plugin invalid: Missing Run() or Start() function." }
		}
	end
	
	-- 4. Execute Safely
	local execSuccess, result = pcall(function()
		return runFunc(context)
	end)
	
	local duration = (os.clock() - startTime) * 1000 -- ms
	
	-- 5. Handle Result
	if not execSuccess then
		warn("[PluginRunner] Runtime error in plugin '" .. pluginName .. "': " .. tostring(result))
		return {
			ok = false,
			meta = { 
				error = "Runtime Error: " .. tostring(result),
				pluginName = pluginName,
				durationMs = duration
			}
		}
	end
	
	-- Enforce shape
	if typeof(result) ~= "table" then
		result = { ok = true, data = result } -- Auto-wrap if lazy
	end
	
	-- Attach meta
	result.meta = result.meta or {}
	result.meta.pluginName = pluginName
	result.meta.durationMs = duration
	
	return result
end

return PluginRunner

