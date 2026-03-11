local Core = script.Parent.Parent
local StatsService = require(Core.StatsService)

local ShieldModifier = {
	priority = 10,
}

function ShieldModifier.Apply(context)
	local losers = context.losers
	local participants = context.participants
	local streakProtectedLosers = context.streakProtectedLosers
	local shieldConsumePlayers = context.shieldConsumePlayers
	local shieldDisarmPlayers = context.shieldDisarmPlayers

	for _, player in ipairs(losers) do
		if StatsService.IsShieldArmed(player) then
			table.insert(streakProtectedLosers, player)
		end
	end

	for _, player in ipairs(participants) do
		if StatsService.IsShieldArmed(player) then
			table.insert(shieldConsumePlayers, player)
			table.insert(shieldDisarmPlayers, player)
		end
	end
end

return ShieldModifier
