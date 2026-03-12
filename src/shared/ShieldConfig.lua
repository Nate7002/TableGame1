local MonetizationConfig = require(script.Parent:WaitForChild("MonetizationConfig"))

local ShieldConfig = {
	-- Compatibility shim: canonical shield tunables now live in MonetizationConfig.
	MaxShields = (MonetizationConfig.Shields and MonetizationConfig.Shields.MaxInventory) or 3,
}

return ShieldConfig
