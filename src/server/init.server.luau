local Core = script:WaitForChild("Core")
local TableService = require(Core:WaitForChild("TableService"))
local RoundService = require(Core:WaitForChild("RoundService"))
local UIService = require(Core:WaitForChild("UIService"))
local DataService = require(Core:WaitForChild("DataService"))
local StatsService = require(Core:WaitForChild("StatsService"))
local PluginRegistry = require(Core:WaitForChild("PluginRegistry"))
local PluginRunner = require(Core:WaitForChild("PluginRunner"))
local Players = game:GetService("Players")

local function Start()
	print("[GameManager] Starting Phase 1 Step 7...")
	
	-- Initialize Data Service (Step 7 - before Stats)
	DataService.Init()
	
	-- Initialize Stats Service (Step 6/7)
	StatsService.Init()
	
	-- Initialize Table Service
	TableService.Init()
	
	-- Connect TableService to RoundService (with countdown)
	TableService.OnTableReady:Connect(function(tableModel, players)
		RoundService.HandleTableReady(tableModel, players)
	end)
	
	-- TEST HOOK: UI System (Step 3)
	-- Players.PlayerAdded:Connect(function(player)
	-- 	task.delay(3, function()
	-- 		... (disabled for Step 4 focus)
	-- 	end)
	-- end)
	
	-- TEST HOOK: Plugin System (Step 4)
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(msg)
			if msg == "/plugins" then
				print("Available Plugins:", PluginRegistry.List())
			elseif string.sub(msg, 1, 5) == "/run " then
				local name = string.sub(msg, 6)
				print("Running Plugin:", name)
				local result = PluginRunner.Run(name, { player = player })
				print("Result:", result)
			end
		end)
	end)
end

Start()
