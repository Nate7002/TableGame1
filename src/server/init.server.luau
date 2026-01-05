local Core = script:WaitForChild("Core")
local TableService = require(Core:WaitForChild("TableService"))

local function Start()
	print("[GameManager] Starting Phase 1 Step 1...")
	
	-- Initialize Table Service
	TableService.Init()
	
	-- Listen for Table Ready Event (Goal #5)
	TableService.OnTableReady:Connect(function(tableModel, players)
		print(string.format(">>> EVENT: %s is READY with %d players! <<<", tableModel.Name, #players))
		if players then
			for _, p in ipairs(players) do
				print("    - " .. p.Name)
			end
		end
	end)
end

Start()
