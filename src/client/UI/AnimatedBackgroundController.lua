local RunService = game:GetService("RunService")
local Theme = require(script.Parent.Theme)

local AnimatedBackgroundController = {}

-- Rarity Tints (Subtle)
local RARITY_TINTS = {
	Common = Color3.fromRGB(150, 150, 150),
	Uncommon = Color3.fromRGB(100, 200, 120),
	Rare = Color3.fromRGB(100, 180, 255),
	Epic = Color3.fromRGB(180, 100, 255),
	Mythic = Color3.fromRGB(255, 200, 50),
	Ultra = Color3.fromRGB(255, 255, 100)
}

function AnimatedBackgroundController.GetTintColor(rarity)
	return RARITY_TINTS[rarity] or RARITY_TINTS.Common
end

function AnimatedBackgroundController.AttachAnimatedBackground(parentFrame, opts)
	opts = opts or {}
	local speed = opts.speed or 0.05
	local tintColor = opts.tintColor or RARITY_TINTS.Common
	
	-- 1. Clone Template
	local template = game.ReplicatedStorage.Assets.UI.Shared:FindFirstChild("AnimatedBackground")
	if not template then
		warn("[AnimatedBackgroundController] Missing template!")
		return function() end
	end
	
	local bg = template:Clone()
	bg.Name = "AnimatedBackground_Runtime"
	bg.Size = UDim2.fromScale(1, 1)
	bg.ZIndex = 0 -- Behind content
	
	-- Hard-enforce Fullscreen Layout for all layers
	local layers = {"BasePanel", "HueBloom", "Tint", "Pattern", "Vignette"}
	for _, name in ipairs(layers) do
		local layer = bg:FindFirstChild(name)
		if layer then
			layer.Size = UDim2.fromScale(1, 1)
			layer.Position = UDim2.fromScale(0, 0)
			layer.AnchorPoint = Vector2.new(0, 0)
			if layer:IsA("Frame") or layer:IsA("ImageLabel") then
				layer.BorderSizePixel = 0
			end
		end
	end
	
	bg.Parent = parentFrame
	
	-- Apply Tint to HueBloom (NOT Pattern/Tint frame)
	local hueBloom = bg:FindFirstChild("HueBloom")
	if hueBloom then
		hueBloom.BackgroundColor3 = tintColor
		hueBloom.BackgroundTransparency = 0.90 -- Subtle tint
	end
	
	-- Update the actual Tint frame if it exists (legacy support or extra layer)
	local tintLayer = bg:FindFirstChild("Tint")
	if tintLayer then
		tintLayer.BackgroundColor3 = tintColor
		tintLayer.BackgroundTransparency = 0.94 -- Very subtle
	end
	
	-- Ensure Pattern stays neutral
	local pattern = bg:FindFirstChild("Pattern")
	if pattern then
		pattern.ImageColor3 = Color3.fromRGB(200, 200, 200) -- Neutral light grey
		pattern.ImageTransparency = 0.93 -- Very subtle
		pattern.BackgroundTransparency = 1 -- Ensure pattern frame doesn't block background
		pattern.Position = UDim2.fromScale(0, 0)
		
		-- Animation Loop
		-- Moves pattern diagonally up-right (negative X/Y offset on Tile) or Position?
		-- Easier: Move Position from 0,0 to -1, -1 and reset?
		-- If ScaleType is Tile, we can tween TileOffset or just move the ImageLabel inside a Clip container.
		-- Best for "PLS DONATE" style: Move TileOffset if possible, or move the ImageLabel position.
		-- Since TileOffset isn't a property of ImageLabel (it has TileSize), we usually animate Position.
		-- To loop seamlessly, we need the image to be 2x size or just wrap. 
		-- Easiest seamless loop: Animate Position from UDim2(0,0,0,0) to UDim2(0, -tileSize, 0, -tileSize) then reset.
		-- Let's assume standard diagonal drift.
		
		local t = 0
		connection = RunService.RenderStepped:Connect(function(dt)
			t = t + dt * speed
			local offset = t % 1
			-- Move diagonally up-right: 
			-- Up = negative Y
			-- Right = positive X
			-- But usually "drifting" means background moves.
			-- Let's do: Background slides down-left so diamonds appear to move up-right?
			-- Actually, simple diagonal pan:
			
			-- We can't easily manipulate TileOffset on ImageLabel directly without a shader or sprite sheet trick.
			-- Standard trick: Make ImageLabel size {2,0},{2,0}, position it at {-1,0},{-1,0} and tween to {0,0}.
			-- BUT for a simple "Tile" ImageLabel, changing Position works if the parent clips it? No.
			-- WAIT: ImageLabel doesn't have offset. 
			-- Standard Roblox "Infinite Scroll":
			--   1. Use a Texture instance inside a Frame? No, ImageLabel.
			--   2. Actually, 'ScaleType=Tile' creates a static tile.
			--   3. BETTER: Use a **Texture** object (which has OffsetStudsU/V) inside a Frame? 
			--      User asked for ImageLabel in the prompt (Part A, Step 2).
			--      If it's an ImageLabel, we can't scroll the tile texture itself.
			--      We must move the Label.
			
			-- Strategy:
			-- The ImageLabel 'Pattern' covers the frame.
			-- We can make it Size {2, 0}, {2, 0}.
			-- Move it from Position {0, 0} to {-0.5, 0}, {-0.5, 0} (assuming 2x size) or match tile size.
			-- Let's stick to moving the position 0 -> 1 loop if size is big enough?
			-- Actually, if ScaleType=Tile, resizing the label just reveals more tiles.
			-- So we just need to move the label slightly? No, that moves the frame.
			-- CORRECT APPROACH for "ImageLabel" infinite scroll:
			-- Use a **Texture** object parented to a Frame (BasePanel).
			-- But user explicitely requested "Pattern (ImageLabel)". 
			-- Okay, if we MUST use ImageLabel:
			-- We can't scroll texture coords.
			-- We'll just oscillate or move the UIGradient? No.
			-- We will fallback to: Make ImageLabel Size {2,0},{2,0} and animate Position from {-0.5,0},{-0.5,0} to {0,0}.
			
			-- Let's adjust runtime property to allow scrolling:
			pattern.Size = UDim2.fromScale(2, 2)
			pattern.Position = UDim2.fromScale(-1 + offset, -1 + offset) 
			-- This moves from -1,-1 to 0,0.
			-- This effectively slides the pattern Down-Right.
			-- To move Up-Right:
			-- Start at {0, -1} -> {1, 0}?
			-- Let's just do a simple diagonal slide.
			-- -1 + offset goes -1 -> 0.
		end)
	end
	
	-- Cleanup
	return function()
		if connection then connection:Disconnect() end
		if bg then bg:Destroy() end
	end
end

return AnimatedBackgroundController

