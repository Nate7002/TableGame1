local Core = script:WaitForChild("Core")
local TableService = require(Core:WaitForChild("TableService"))
local RoundService = require(Core:WaitForChild("RoundService"))
local UIService = require(Core:WaitForChild("UIService"))
local Players = game:GetService("Players")

local function Start()
	print("[GameManager] Starting Phase 1 Step 3...")
	
	-- Initialize Table Service
	TableService.Init()
	
	-- Connect TableService to RoundService
	TableService.OnTableReady:Connect(function(tableModel, players)
		RoundService.StartRound(tableModel, players)
	end)
	
	-- TEST HOOK: UI System
	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			print("[TEST] Sending Choice Popup to " .. player.Name)
			
			local choice = UIService.PromptChoice(player, {
				title = "Welcome to Table Game!",
				description = "We are testing the new UI System. Please select an option below.",
				options = {
					{ id = "A", label = "Awesome" },
					{ id = "B", label = "Cool" }
				},
				timeout = 10
			})
			
			print("[TEST] Result from " .. player.Name .. ": ", choice)
			
			if choice then
				UIService.Notify(player, "You chose: " .. choice, 3)
			else
				UIService.Notify(player, "You ignored the prompt!", 3)
			end
		end)
	end)
end

Start()
