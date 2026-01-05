local Core = script:WaitForChild("Core")
local TableService = require(Core:WaitForChild("TableService"))
local RoundService = require(Core:WaitForChild("RoundService"))

local function Start()
	print("[GameManager] Starting Phase 1 Step 2...")
	
	-- Initialize Table Service
	TableService.Init()
	
	-- Connect TableService to RoundService
	TableService.OnTableReady:Connect(function(tableModel, players)
		RoundService.StartRound(tableModel, players)
	end)
end

Start()
