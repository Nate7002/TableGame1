local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local SpinService = {}

-- Assets
local SPIN_MODELS_PATH = "Assets/DoubleDown/SpinItems/Models"
local SPIN_UI_PATH = "Assets/DoubleDown/UI/SpinLabelBillboard"

-- Helpers
local function getAsset(path, name)
	local current = ServerStorage
	if string.sub(path, 1, 17) == "ReplicatedStorage" then
		current = ReplicatedStorage
		path = string.sub(path, 19)
	end
	
	for _, part in ipairs(string.split(path, "/")) do
		current = current:FindFirstChild(part)
		if not current then return nil end
	end
	
	if name then
		return current:FindFirstChild(name)
	end
	return current
end

local function updateBillboard(billboard, item, config)
	if not billboard then return end
	
	local frame = billboard:FindFirstChild("MainFrame") or billboard:FindFirstChild("Frame") -- Adjust based on structure
	if not frame then return end
	
	local nameLabel = frame:FindFirstChild("ItemName")
	local chanceLabel = frame:FindFirstChild("Chance")
	local valueLabel = frame:FindFirstChild("Value")
	
	local color = config.RarityColors[item.rarity] or Color3.new(1,1,1)
	
	if nameLabel then 
		nameLabel.Text = item.name 
		nameLabel.TextColor3 = color
	end
	if chanceLabel then 
		chanceLabel.Text = string.format("%.1f%%", item.chance) 
		chanceLabel.TextColor3 = color
	end
	if valueLabel then 
		valueLabel.Text = "$" .. item.value 
		valueLabel.TextColor3 = color
	end
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
	local billboardTemplate = getAsset(SPIN_UI_PATH) -- Actually RepStorage
	local billboard
	if billboardTemplate then
		billboard = billboardTemplate:Clone()
		
		local attachment = billboardAnchor and billboardAnchor:FindFirstChild("BillboardAttachment")
		local adornee = attachment or billboardAnchor
		
		if adornee then
			billboard.Adornee = adornee
			billboard.Parent = tableModel
			billboard.Enabled = true
		else
			warn("[SpinService] FAILED to mount Billboard: Neither BillboardAnchor nor BillboardAttachment exists on " .. tableModel.Name)
		end
	else
		warn("[SpinService] Missing billboard template at: " .. SPIN_UI_PATH)
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
	-- "Clean up: destroy old spawned spin model(s) + billboard when round ends."
	-- So we return references for cleanup later or handle it here?
	-- "DoubleDown plugin should call SpinService first, then proceed... Clean up when round ends."
	-- We'll attach cleanup to the tableModel or return a cleanup function.
	
	local cleanup = function()
		if currentModel then currentModel:Destroy() end
		if billboard then billboard:Destroy() end
	end
	
	return currentItem, cleanup
end

return SpinService

