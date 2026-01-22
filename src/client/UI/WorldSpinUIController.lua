local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WorldSpinUIController = {}

-- Constants
local NEAR_DISTANCE = 45
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

local function getPlayerPos()
	local player = Players.LocalPlayer
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

local function getAnchorPos(tableModel)
	local spinDisplay = tableModel:FindFirstChild("SpinDisplay")
	local anchor = spinDisplay and spinDisplay:FindFirstChild("BillboardAnchor")
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	if tableModel.PrimaryPart then
		return tableModel.PrimaryPart.Position
	end
	return tableModel:GetPivot().Position
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

-- Helper: Toggle runtime billboard visibility (only SpinLabelBillboard_Runtime)
local function SetTableRuntimeBillboardEnabled(tableModel, enabled)
	local spinDisplay = tableModel:FindFirstChild("SpinDisplay")
	if not spinDisplay then return end
	
	for _, descendant in ipairs(spinDisplay:GetDescendants()) do
		if IsSpinRuntimeBillboard(descendant) then
			-- If disabling during match (and it's not ours), cache state
			if not enabled and isInMatch then
				if originalEnabled[descendant] == nil then
					originalEnabled[descendant] = descendant.Enabled
				end
			end
			descendant.Enabled = enabled
		end
	end
end

local function UpdateVisibility()
	local tables = GetTables()

	if isInMatch then
		-- In Match: Ignore proximity. Only current table shows.
		for _, tableModel in ipairs(tables) do
			local shouldShow = (tableModel.Name == currentTableKey)
			SetTableRuntimeBillboardEnabled(tableModel, shouldShow)
		end
		return
	end

	-- Not In Match: Proximity-based.
	local pos = getPlayerPos()
	if not pos then
		-- Character not ready: hide all to avoid leaving stale "on" state
		for _, tableModel in ipairs(tables) do
			SetTableRuntimeBillboardEnabled(tableModel, false)
		end
		return
	end

	for _, tableModel in ipairs(tables) do
		local anchorPos = getAnchorPos(tableModel)
		local dist = (anchorPos - pos).Magnitude
		SetTableRuntimeBillboardEnabled(tableModel, dist <= NEAR_DISTANCE)
	end
end

-- Public refresh hook (kept for existing callsites)
function WorldSpinUIController.Refresh()
	UpdateVisibility()
end

local function StartLoop()
	if updateConnection then return end
	updateConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastUpdate >= UPDATE_INTERVAL then
			lastUpdate = now
			UpdateVisibility()
		end
	end)
end

local function StopLoop()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
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
		StopLoop()
		
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
		UpdateVisibility()
		task.defer(UpdateVisibility)
		
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
		StartLoop()
		
		-- 4. Immediate Refresh (Show nearby)
		UpdateVisibility()
	end
end

function WorldSpinUIController.Init()
	-- Start loop immediately (idempotent). Do not call SetInMatch(false, nil) here,
	-- because SetInMatch is intentionally idempotent and may early-return.
	StartLoop()
	UpdateVisibility()
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.defer(UpdateVisibility)
	end)
end

return WorldSpinUIController