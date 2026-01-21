local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WorldSpinUIController = {}

-- Constants
local NEAR_DISTANCE = 35
local UPDATE_INTERVAL = 0.25

-- State
local isInMatch = false
local currentTableKey = nil
local updateConnection = nil
local lastUpdate = 0

-- Runtime Guard State
local runtimeListener = nil
local originalEnabled = {} -- [Instance] = boolean

-- Helper: Get unique key for a table
local function GetTableKey(tableModel)
	return tableModel.Name -- Assuming unique names like "Table_01"
end

-- Helper: Check if instance is the runtime spin UI
local function IsSpinRuntimeBillboard(inst)
	return inst:IsA("BillboardGui") and inst.Name == "SpinLabelBillboard_Runtime"
end

-- Helper: Get the table model from a UI element
local function GetTableFromGui(gui)
	-- Search up to find the Table Model (ancestor)
	-- Assumption: Table is a Model containing SpinDisplay
	-- The gui is usually inside SpinDisplay -> BillboardAnchor
	local current = gui.Parent
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChild("SpinDisplay") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Helper: Find all valid table models
local function GetTables()
	local tables = {}
	local seen = {} -- [Instance] = true

	-- Scan known locations:
	-- - Workspace.Tables (user-confirmed hierarchy)
	-- - Workspace.Lobby.Tables (TableService-created hierarchy)
	-- - Workspace direct children (fallback)
	local searchContainers = {}

	local tablesFolderDirect = Workspace:FindFirstChild("Tables")
	if tablesFolderDirect then table.insert(searchContainers, tablesFolderDirect) end

	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby then
		local tablesFolderLobby = lobby:FindFirstChild("Tables")
		if tablesFolderLobby then table.insert(searchContainers, tablesFolderLobby) end
	end

	table.insert(searchContainers, Workspace)

	for _, container in ipairs(searchContainers) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") and not seen[child] and child:FindFirstChild("SpinDisplay") then
				local spinDisplay = child.SpinDisplay
				if spinDisplay:FindFirstChild("BillboardAnchor") then
					seen[child] = true
					table.insert(tables, child)
				end
			end
		end
	end

	return tables
end

-- Helper: Toggle UI visibility
local function SetTableSpinUIEnabled(tableModel, enabled)
	local spinDisplay = tableModel:FindFirstChild("SpinDisplay")
	if not spinDisplay then return end
	
	for _, descendant in ipairs(spinDisplay:GetDescendants()) do
		if descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			-- If disabling during match (and it's not ours), cache state
			if not enabled and isInMatch and IsSpinRuntimeBillboard(descendant) then
				if originalEnabled[descendant] == nil then
					originalEnabled[descendant] = descendant.Enabled
				end
			end
			descendant.Enabled = enabled
		end
	end
end

-- Main Refresh Logic
function WorldSpinUIController.Refresh()
	local player = Players.LocalPlayer
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	
	local tables = GetTables()
	
	if isInMatch then
		-- In Match: Show ONLY current table, hide ALL others
		for _, tableModel in ipairs(tables) do
			local key = GetTableKey(tableModel)
			if key == currentTableKey then
				SetTableSpinUIEnabled(tableModel, true)
			else
				SetTableSpinUIEnabled(tableModel, false)
			end
		end
	else
		-- Not In Match: Show nearby tables only
		if not hrp then return end
		local pos = hrp.Position
		
		for _, tableModel in ipairs(tables) do
			local spinDisplay = tableModel:FindFirstChild("SpinDisplay")
			local anchor = spinDisplay and spinDisplay:FindFirstChild("BillboardAnchor")
			
			if anchor and anchor:IsA("BasePart") then
				local dist = (anchor.Position - pos).Magnitude
				SetTableSpinUIEnabled(tableModel, dist <= NEAR_DISTANCE)
			else
				SetTableSpinUIEnabled(tableModel, false)
			end
		end
	end
end

-- Public API: Set Match State
function WorldSpinUIController.SetInMatch(inMatch, tableIdOrName)
	-- Normalize incoming key to a stable string (or nil)
	local incomingKey = nil
	if typeof(tableIdOrName) == "string" and tableIdOrName ~= "" then
		incomingKey = tableIdOrName
	end

	-- Never allow SetInMatch(true, nil) to wipe the key mid-match
	if inMatch and not incomingKey then
		if isInMatch and currentTableKey then
			return
		end
		return
	end

	-- Prevent overwriting during a match (race/out-of-order events)
	if inMatch and isInMatch and currentTableKey and incomingKey and currentTableKey ~= incomingKey then
		return
	end

	if isInMatch == inMatch and currentTableKey == incomingKey then
		return -- Idempotent
	end
	
	isInMatch = inMatch
	currentTableKey = incomingKey
	
	if isInMatch then
		-- ENTERING MATCH
		-- 1. Stop Update Loop
		if updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
		end
		
		-- 2. Start Runtime Listener (Hide new spawns on other tables)
		if not runtimeListener then
			runtimeListener = Workspace.DescendantAdded:Connect(function(descendant)
				if not isInMatch then return end
				if IsSpinRuntimeBillboard(descendant) then
					-- Derive owning table using known hierarchy:
					-- Table_XX -> SpinDisplay -> (BillboardAnchor) -> SpinLabelBillboard_Runtime
					local billboardAnchor = descendant.Parent
					local spinDisplay = billboardAnchor and billboardAnchor.Parent
					local tableModel = spinDisplay and spinDisplay.Parent

					if spinDisplay and spinDisplay.Name == "SpinDisplay" and tableModel and tableModel:IsA("Model") then
						if tableModel.Name ~= currentTableKey then
							if originalEnabled[descendant] == nil then
								originalEnabled[descendant] = descendant.Enabled
							end
							descendant.Enabled = false
						end
					else
						-- Fallback: best-effort ancestor search
						local fallbackTable = GetTableFromGui(descendant)
						if fallbackTable and fallbackTable.Name ~= currentTableKey then
							if originalEnabled[descendant] == nil then
								originalEnabled[descendant] = descendant.Enabled
							end
							descendant.Enabled = false
						end
					end
				end
			end)
		end
		
		-- 3. Immediate Refresh (Hides existing)
		WorldSpinUIController.Refresh()
		task.defer(WorldSpinUIController.Refresh)
		
	else
		-- LEAVING MATCH
		-- 1. Stop Runtime Listener
		if runtimeListener then
			runtimeListener:Disconnect()
			runtimeListener = nil
		end
		
		-- 2. Restore Original States (for runtime UIs that were hidden)
		for inst, state in pairs(originalEnabled) do
			if inst.Parent then
				inst.Enabled = state
			end
		end
		originalEnabled = {}
		
		-- 3. Start Update Loop
		if not updateConnection then
			updateConnection = RunService.Heartbeat:Connect(function()
				local now = os.clock()
				if now - lastUpdate >= UPDATE_INTERVAL then
					lastUpdate = now
					WorldSpinUIController.Refresh()
				end
			end)
		end
		
		-- 4. Immediate Refresh (Show nearby)
		WorldSpinUIController.Refresh()
	end
end

function WorldSpinUIController.Init()
	-- Start loop immediately (assuming not in match at start)
	WorldSpinUIController.SetInMatch(false, nil)
end

return WorldSpinUIController