local Core = script.Parent

local ShieldModifier = require(Core.Modifiers.ShieldModifier)

local ModifierService = {}

local modifiers = {
	ShieldModifier,
}

table.sort(modifiers, function(a, b)
	return (a.priority or 0) < (b.priority or 0)
end)

function ModifierService.ApplyRoundModifiers(context)
	if not context or context.isNeutral then
		return
	end

	for _, modifier in ipairs(modifiers) do
		if modifier and type(modifier.Apply) == "function" then
			modifier.Apply(context)
		end
	end
end

return ModifierService
