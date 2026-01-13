local ServerStorage = game:GetService("ServerStorage")

local PluginRegistry = {}

-- Constants
local PLUGINS_FOLDER_NAME = "Plugins"

-- Private
local function getPluginsFolder()
	return ServerStorage:FindFirstChild(PLUGINS_FOLDER_NAME)
end

-- Public API

-- Discover available plugins recursively
function PluginRegistry.Discover()
	local folder = getPluginsFolder()
	if not folder then
		warn("[PluginRegistry] No 'Plugins' folder found in ServerStorage.")
		return {}
	end
	
	local plugins = {}
	
	local function scan(dir)
		for _, child in ipairs(dir:GetChildren()) do
			if child:IsA("ModuleScript") then
				-- Enforce unique names check
				if plugins[child.Name] then
					warn("[PluginRegistry] Duplicate plugin name found: " .. child.Name .. ". Ignoring second instance.")
				else
					plugins[child.Name] = child
				end
			elseif child:IsA("Folder") then
				scan(child)
			end
		end
	end
	
	scan(folder)
	return plugins
end

function PluginRegistry.Get(name)
	local plugins = PluginRegistry.Discover() -- For now, re-discover to handle hot-reloading/updates. 
	-- Optimization: Cache this if performance becomes an issue.
	
	return plugins[name]
end

function PluginRegistry.List()
	local plugins = PluginRegistry.Discover()
	local names = {}
	for name, _ in pairs(plugins) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return PluginRegistry

