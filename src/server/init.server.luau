local Core = script:WaitForChild("Core")
local DebugService = require(Core:WaitForChild("DebugService"))
local DataService = require(Core:WaitForChild("DataService"))
local TableService = require(Core:WaitForChild("TableService"))
local RoundService = require(Core:WaitForChild("RoundService"))
local UIService = require(Core:WaitForChild("UIService"))
local StatsService = require(Core:WaitForChild("StatsService"))
local MonetizationService = require(Core:WaitForChild("MonetizationService"))
local LeaderboardService = require(Core:WaitForChild("LeaderboardService"))
local PluginRegistry = require(Core:WaitForChild("PluginRegistry"))
local PluginRunner = require(Core:WaitForChild("PluginRunner"))
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local chatHookedPlayers = {}

DebugService.SetLevel("INFO")

DebugService.SetContext({
	env = DataService.GetNamespace(),
	serverId = game.JobId
})

local function attachDevChatHooks(player)
	if not player then return end
	if chatHookedPlayers[player.UserId] then return end

	chatHookedPlayers[player.UserId] = true

	player.Chatted:Connect(function(msg)
		if msg == "/plugins" then
			print("Available Plugins:", PluginRegistry.List())
		elseif msg == "/cmds" then
			print("[StudioCmds] Legacy dev commands:")
			print("[StudioCmds] /plugins")
			print("[StudioCmds] /run <pluginName>")
			print("[StudioCmds] /shields <amount>")
			print("[StudioCmds] /gems <amount>")
			print("[StudioCmds] /shieldtest")
			print("[StudioCmds] Harness/debug commands:")
			print("[StudioCmds] /dumpstats")
			print("[StudioCmds] /dumpstats all")
			print("[StudioCmds] /dumpmonetization")
			print("[StudioCmds] /setvip on")
			print("[StudioCmds] /setvip off")
			print("[StudioCmds] /testreceipt <productKey>")
			print("[StudioCmds] /testrestore <productKey>")
			print("[StudioCmds] /testround single_win_p1")
			print("[StudioCmds] /testround single_lose_p1")
			print("[StudioCmds] /testround draw")
			print("[StudioCmds] /testround vip_single_win_p1")
			print("[StudioCmds] /testround vip_draw_mixed")
			print("[StudioCmds] /testround both_lose")
		elseif string.sub(msg, 1, 5) == "/run " then
			local name = string.sub(msg, 6)
			print("Running Plugin:", name)
			local result = PluginRunner.Run(name, { player = player })
			print("Result:", result)
		elseif string.sub(msg, 1, 9) == "/shields " then
			local amount = tonumber(string.sub(msg, 10))
			if amount and amount >= 0 then
				local wholeAmount = math.floor(amount)
				local ok = StatsService.SetShields(player, wholeAmount, "DevCommand")
				print("[Shield] /shields set", wholeAmount, "->", ok and "OK" or "FAIL", "inventory:", StatsService.GetShields(player))
			else
				print("[Shield] Usage: /shields <amount> (e.g. /shields 0)")
			end
		elseif string.sub(msg, 1, 6) == "/gems " then
			local amount = tonumber(string.sub(msg, 7))
			if amount and amount > 0 then
				local wholeAmount = math.floor(amount)
				local ok = StatsService.AddGems(player, wholeAmount, "DevCommand")
				print("[Gems] /gems", wholeAmount, "->", ok and "OK" or "FAIL", "inventory:", StatsService.GetGems(player))
			else
				print("[Gems] Usage: /gems <amount> (e.g. /gems 25)")
			end
		elseif msg == "/shieldtest" then
			local players = Players:GetPlayers()
			local playerA, playerB = players[1], players[2]
			if not playerA or not playerB then
				print("[ShieldTest] Need 2 players. Found:", #players)
				return
			end
			StatsService.ApplyRoundResult(playerA, playerB, {
				roundId = "test_no_shield",
				winnerUserId = playerB.UserId,
				loserUserId = playerA.UserId,
				rewardCash = 100
			})
			print("[ShieldTest] Test 1 executed. Check logs for ROUND_WINNER / ROUND_LOSER_RESET")
		end
	end)
end

local function Start()
	print("[GameManager] Starting Phase 1 Step 8...")
	
	-- Initialize Data Service (Step 7 - before Stats)
	DataService.Init()
	
	-- Initialize Stats Service (Step 6/7)
	StatsService.Init()

	-- Initialize Monetization Service (Step 10A - backend authority only)
	MonetizationService.Init()

	-- Dev chat hooks are Studio-only so published servers never expose test commands.
	if RunService:IsStudio() then
		local DevTestService = require(Core:WaitForChild("DevTestService"))
		Players.PlayerAdded:Connect(attachDevChatHooks)
		for _, player in ipairs(Players:GetPlayers()) do
			attachDevChatHooks(player)
		end
		DevTestService.Init()
	end
	
	-- Initialize Leaderboard Service (Step 8 - Weekly + Overall leaderboards)
	LeaderboardService.Init()
	
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
	
end

Start()
