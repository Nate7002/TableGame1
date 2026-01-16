local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local SpinService = {}

-- Config
local DEBUG = false

-- Assets
local SPIN_MODELS_PATH = "Assets/DoubleDown/SpinItems/Models"
local SPIN_UI_PATH = "Assets/DoubleDown/UI/SpinLabelBillboard"

-- Helpers
local function ResolvePath(root, path)
	local current = root
	local segments = string.split(path, "/")
	
	for _, segment in ipairs(segments) do
		local nextInstance = current:FindFirstChild(segment)
		if not nextInstance then
			if DEBUG then
				print(string.format("[SpinService] ResolvePath failed at segment '%s' in root '%s'", segment, current:GetFullName()))
				print("Available children:")
				for _, child in ipairs(current:GetChildren()) do
					print(" - " .. child.Name)
				end
			end
			return nil
		end
		current = nextInstance
	end
	
	if DEBUG then
		print(string.format("[SpinService] Resolved path: %s", current:GetFullName()))
	end
	return current
end

local function getAsset(path, name)
	-- Legacy helper - redirecting to ResolvePath where appropriate
	-- Models are usually in ServerStorage
	-- UI is usually in ReplicatedStorage
	local root = ServerStorage
	if string.sub(path, 1, 17) == "ReplicatedStorage" then
		root = ReplicatedStorage
		path = string.sub(path, 19)
	end
	
	local result = ResolvePath(root, path)
	
	if result and name then
		return result:FindFirstChild(name)
	end
	return result
end

-- Gradient Definitions (ColorSequences)
local GRADIENT_COLORS = {
	Rare = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 150, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 255))
	}),
	Epic = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 0, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255))
	}),
	Mythic = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 0))
	}),
	Ultra = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255))
	})
}

local function updateBillboard(billboard, item, config)
	if not billboard then return end
	
	-- Robust finding: search recursively anywhere in the billboard
	-- Note: "Rarity" is the new name for the main label (formerly ItemName)
	local rarityLabel = billboard:FindFirstChild("Rarity", true) or billboard:FindFirstChild("ItemName", true)
	local chanceLabel = billboard:FindFirstChild("Chance", true)
	
	if DEBUG then
		if not (rarityLabel and chanceLabel) then
			warn("[SpinService] updateBillboard: Missing rarity/chance labels in billboard hierarchy.")
		end
	end
	
	local color = config.RarityColors[item.rarity] or Color3.new(1,1,1)
	
	if rarityLabel then 
		rarityLabel.Text = string.upper(item.rarity) -- Show RARITY instead of Name
		rarityLabel.TextColor3 = color
		
		-- Handle Gradients (Disable all first, then enable specific)
		local hasGradient = false
		for _, child in ipairs(rarityLabel:GetChildren()) do
			if child:IsA("UIGradient") then
				child.Enabled = false
			end
		end
		
		-- Only apply gradient for Rare+
		if GRADIENT_COLORS[item.rarity] then
			local gradientName = "Gradient_" .. item.rarity
			local gradient = rarityLabel:FindFirstChild(gradientName)
			if gradient then
				gradient.Enabled = true
				gradient.Color = GRADIENT_COLORS[item.rarity]
				gradient.Rotation = 45
				rarityLabel.TextColor3 = Color3.new(1,1,1) -- White text to let gradient show
				hasGradient = true
			end
		end
	end
	if chanceLabel then 
		chanceLabel.Text = string.format("%.2f%% chance", item.chance) 
		chanceLabel.TextColor3 = color
		-- Ensure Chance label is always legible (no gradient, just color)
	end
	-- Value label is hidden/unused
end

-- Public API
function SpinService.SpinTable(tableModel, spinConfig)
	local spinDisplay = tableModel:FindFirstChild("SpinDisplay")
	local itemAnchor = spinDisplay and spinDisplay:FindFirstChild("ItemAnchor")
	local billboardAnchor = spinDisplay and spinDisplay:FindFirstChild("BillboardAnchor")
	
	if not itemAnchor then
		warn("[SpinService] Missing ItemAnchor on table: " .. tableModel.Name)
	end
	
	if not billboardAnchor then
		warn("[SpinService] Missing BillboardAnchor on table: " .. tableModel.Name)
	end
	
	-- Setup Billboard
	local billboardTemplate = ResolvePath(ReplicatedStorage, SPIN_UI_PATH)
	local billboard
	if billboardTemplate then
		billboard = billboardTemplate:Clone()
		billboard.Name = "SpinLabelBillboard_Runtime"
		
		local attachment = billboardAnchor and billboardAnchor:FindFirstChild("BillboardAttachment")
		local adornee = attachment or billboardAnchor
		
		if adornee then
			billboard.Adornee = adornee
			
			-- Guarantee Parent is a workspace part (BillboardAnchor)
			if billboardAnchor then
				billboard.Parent = billboardAnchor
			else
				billboard.Parent = tableModel
				warn(string.format("[SpinService] Billboard runtime not parented to BillboardAnchor (parent=%s)", tostring(billboard.Parent)))
			end
			
			-- Force Visibility properties
			billboard.Enabled = true
			billboard.AlwaysOnTop = true
			if billboard.MaxDistance < 50 then billboard.MaxDistance = 1000 end
			
			-- Safety: Ensure Size isn't 0
			if billboard.Size == UDim2.fromScale(0, 0) and billboard.Size.X.Offset == 0 then
				billboard.Size = UDim2.fromOffset(220, 60)
			end
			
			-- Safety: Ensure Offset isn't 0 if it looks buried
			if billboard.StudsOffset == Vector3.new(0, 0, 0) then
				billboard.StudsOffset = Vector3.new(0, 2.5, 0)
			end
			
			-- Layout Enforcement (Fix for overlapping labels in template)
			local frame = billboard:FindFirstChild("MainFrame") or billboard:FindFirstChild("Frame")
			if frame then
				frame.BackgroundTransparency = 0.1 -- Dark rounded card aesthetic
				frame.ZIndex = 1
			end

			local function enforceLabel(name, pos, size)
				-- Try finding by new name "Rarity" first, then legacy "ItemName"
				local label = billboard:FindFirstChild(name, true)
				if name == "Rarity" and not label then
					label = billboard:FindFirstChild("ItemName", true)
				end
				
				if label then
					label.BackgroundTransparency = 1 -- Transparent background
					label.TextScaled = true
					label.ZIndex = 2 -- On top of background
					label.Position = pos
					label.Size = size
					
					-- Ensure Global Style is Enforced
					label.Font = Enum.Font.Cartoon
					label.TextStrokeTransparency = 0
					label.TextStrokeColor3 = Color3.new(0,0,0)
					
					if name == "Value" then
						label.Visible = false -- Ensure Value is hidden
					end
				end
			end

			-- Rarity (was ItemName): Top ~60%
			enforceLabel("Rarity", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0.6, 0))
			-- Chance: Bottom ~40%
			enforceLabel("Chance", UDim2.new(0, 0, 0.6, 0), UDim2.new(1, 0, 0.4, 0))
			-- Value: Hidden
			enforceLabel("Value", UDim2.new(0, 0, 0, 0), UDim2.new(0, 0, 0, 0))
			
		else
			warn("[SpinService] Billboard has nil Adornee; cannot render")
			billboard:Destroy()
			billboard = nil
		end
	else
		warn(string.format("[SpinService] Missing billboard template at: ReplicatedStorage/%s", SPIN_UI_PATH))
	end
	
	-- Spin Logic
	local duration = 3.5
	local startTime = os.clock()
	local spinSpeed = 0.1 -- Initial delay
	local lastSpinTime = 0
	
	local currentModel = nil
	local currentItem = nil
	
	local modelsFolder = getAsset(SPIN_MODELS_PATH)
	
	-- Spin Loop
	while os.clock() - startTime < duration do
		local now = os.clock()
		
		-- Update Item visually
		if now - lastSpinTime >= spinSpeed then
			lastSpinTime = now
			
			-- Cleanup old
			if currentModel then currentModel:Destroy() end
			
			-- Pick next
			currentItem = spinConfig.PickRandom()
			
			-- Clone Model
			if modelsFolder and itemAnchor then
				local template = modelsFolder:FindFirstChild(currentItem.id) or modelsFolder:FindFirstChild(currentItem.name)
				if template then
					currentModel = template:Clone()
					currentModel:PivotTo(itemAnchor.CFrame)
					currentModel.Parent = tableModel
				end
			end
			
			-- Update UI
			if billboard then
				updateBillboard(billboard, currentItem, spinConfig)
			end
			
			-- Slow down
			spinSpeed = spinSpeed * 1.1
		end
		
		task.wait()
	end
	
	-- Final Lock-in
	-- Ensure we have a valid item (if loop somehow didn't run once)
	if not currentItem then currentItem = spinConfig.PickRandom() end
	
	-- Cleanup UI after short delay? Or keep it for the round?
	-- "DoubleDown plugin should call SpinService first, then proceed... Clean up when round ends."
	
	local cleanup = function()
		if currentModel then currentModel:Destroy() end
		if billboard then billboard:Destroy() end
	end
	
	return currentItem, cleanup
end

return SpinService
