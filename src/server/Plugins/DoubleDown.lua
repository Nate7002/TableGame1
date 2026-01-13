local DoubleDown = {}

local REWARDS = {100, 250, 500, 1000}

function DoubleDown.Run(context)
	local players = context.players
	if not players or #players < 2 then
		return { ok = false, meta = { error = "Not enough players" } }
	end
	
	print("[DoubleDown] Starting round... Waiting 5 seconds.")
	task.wait(5) -- MVP: Simulate game duration
	
	-- MVP: Random Reward & Force Split
	local reward = REWARDS[math.random(1, #REWARDS)]
	
	local p1 = players[1]
	local p2 = players[2]
	
	local choices = {}
	choices[p1.UserId] = "SPLIT"
	choices[p2.UserId] = "SPLIT"
	
	return {
		ok = true,
		data = {
			outcome = "SPLIT",
			reward = reward,
			winners = {p1, p2},
			choices = choices
		}
	}
end

return DoubleDown

