local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local TableService = {}

-- Constants
local TABLE_TEMPLATE_PATH = "Assets/Tables/TableTemplate/TableModel"
local MAX_TABLES = 10
local GRID_ORIGIN = Vector3.new(0, 2.634, 20) -- Precise height adjustment
local SPACING_X = 15
local SPACING_Z = 15
local COLS = 5

-- State
local activeTables = {} -- [model] = { SeatA = player?, SeatB = player?, State = "Empty" }
local tableReadyEvent = Instance.new("BindableEvent")

-- Public Events
TableService.OnTableReady = tableReadyEvent.Event

-- Private Functions
local function getTemplate()
	local current = ServerStorage
	for _, part in ipairs(string.split(TABLE_TEMPLATE_PATH, "/")) do
		current = current:FindFirstChild(part)
		if not current then return nil end
	end
	return current
end

local function updateTableState(model)
	local data = activeTables[model]
	if not data then return end

	local count = (data.SeatA and 1 or 0) + (data.SeatB and 1 or 0)
	
	local newState
	if count == 0 then
		newState = "Empty"
	elseif count == 2 then
		newState = "Full"
	else
		newState = "Waiting"
	end
	
	if data.State ~= newState then
		data.State = newState
		-- print(string.format("[%s] State: %s (%d/2)", model.Name, newState, count))
		
		if newState == "Full" then
			tableReadyEvent:Fire(model, {data.SeatA, data.SeatB})
		end
	end
end

local function handleOccupantChange(model, seat, seatKey)
	local data = activeTables[model]
	if not data then return end
	
	local occupant = seat.Occupant
	
	-- Manage Seat.Disabled:
	-- If occupied, keep Enabled. If empty, Disable to prevent touch-sitting.
	if occupant then
		seat.Disabled = false
	else
		seat.Disabled = true
	end

	local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
	
	data[seatKey] = player
	updateTableState(model)
end

local function handleSitRequest(model, seat, player, sideKey)
	local data = activeTables[model]
	if not data then return end

	-- Check soft lock (Race Condition Prevention)
	local lockKey = "Locked" .. sideKey
	if data[lockKey] then return end
	
	-- Check if seat is free
	if seat.Occupant then return end
	
	local hum = player.Character and player.Character:FindFirstChild("Humanoid")
	if hum and hum.Health > 0 then
		-- Lock
		data[lockKey] = true
		task.delay(1, function()
			if activeTables[model] then
				activeTables[model][lockKey] = false
			end
		end)

		print(string.format("[TableService] Force sitting %s in %s", player.Name, model.Name))
		
		-- 1. Enable seat so Sit() works
		seat.Disabled = false
		
		-- 2. Force sit
		seat:Sit(hum)
		
		-- 3. Safety Check: If Sit() failed, re-disable
		task.delay(0.5, function()
			if not seat.Occupant then
				seat.Disabled = true
			end
		end)
	end
end

local function setupTable(model)
	-- Hierarchy Adjustment:
	-- TableModel -> ChairRed -> PromptPartA -> JoinPromptA, SeatA
	-- TableModel -> ChairBlue -> PromptPartB -> JoinPromptB, SeatB
	
	local chairRed = model:FindFirstChild("ChairRed")
	local chairBlue = model:FindFirstChild("ChairBlue")
	
	if not (chairRed and chairBlue) then
		warn("[TableService] Skipping invalid table structure (missing chairs): " .. model.Name)
		return
	end

	local ppA = chairRed:FindFirstChild("PromptPartA")
	local ppB = chairBlue:FindFirstChild("PromptPartB")

	if not (ppA and ppB) then
		warn("[TableService] Skipping invalid table (missing prompt parts): " .. model.Name)
		return
	end
	
	local seatA = ppA:FindFirstChild("SeatA")
	local promptA = ppA:FindFirstChild("JoinPromptA")
	
	local seatB = ppB:FindFirstChild("SeatB")
	local promptB = ppB:FindFirstChild("JoinPromptB")
	
	if not (seatA and seatB and promptA and promptB) then
		warn("[TableService] Skipping invalid table (missing seats/prompts): " .. model.Name)
		return
	end
	
	-- 2) Seat Config (Start Disabled)
	seatA.Disabled = true
	seatB.Disabled = true
	
	-- 3) Prompt Config (Ensure visibility)
	for _, prompt in ipairs({promptA, promptB}) do
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.ActionText = "Sit"
		-- prompt.ObjectText = "Table" -- Optional
	end
	
	-- State Init
	activeTables[model] = {
		SeatA = nil,
		SeatB = nil,
		LockedA = false,
		LockedB = false,
		State = "Empty"
	}
	
	-- Connect Prompts
	promptA.Triggered:Connect(function(player)
		handleSitRequest(model, seatA, player, "A")
	end)
	
	promptB.Triggered:Connect(function(player)
		handleSitRequest(model, seatB, player, "B")
	end)
	
	-- Monitor Occupancy
	seatA:GetPropertyChangedSignal("Occupant"):Connect(function()
		handleOccupantChange(model, seatA, "SeatA")
	end)
	
	seatB:GetPropertyChangedSignal("Occupant"):Connect(function()
		handleOccupantChange(model, seatB, "SeatB")
	end)
	
	-- Initial state check
	handleOccupantChange(model, seatA, "SeatA")
	handleOccupantChange(model, seatB, "SeatB")
end

local function spawnTables(parentFolder)
	local template = getTemplate()
	if not template then
		warn("[TableService] FATAL: Could not find table template at " .. TABLE_TEMPLATE_PATH)
		return
	end

	for i = 1, MAX_TABLES do
		local tbl = template:Clone()
		tbl.Name = string.format("Table_%02d", i)
		tbl.Parent = parentFolder
		
		-- Grid Layout
		local idx = i - 1
		local col = idx % COLS
		local row = math.floor(idx / COLS)
		local x = col * SPACING_X
		local z = row * SPACING_Z
		
		-- Position relative to origin
		local pos = GRID_ORIGIN + Vector3.new(x, 0, z)
		
		-- Use MoveTo or manually set position to avoid burying if PrimaryPart isn't centered
		if tbl.PrimaryPart then
			tbl:SetPrimaryPartCFrame(CFrame.new(pos))
		else
			tbl:PivotTo(CFrame.new(pos))
		end
		
		setupTable(tbl)
	end
end

-- Public API
function TableService.Init()
	print("[TableService] Initializing...")
	
	local lobby = Workspace:FindFirstChild("Lobby") or Instance.new("Folder", Workspace)
	lobby.Name = "Lobby"
	
	local tablesFolder = lobby:FindFirstChild("Tables") or Instance.new("Folder", lobby)
	tablesFolder.Name = "Tables"
	
	if #tablesFolder:GetChildren() == 0 then
		spawnTables(tablesFolder)
	else
		print("[TableService] Found existing tables. Hooking up...")
		for _, tbl in ipairs(tablesFolder:GetChildren()) do
			setupTable(tbl)
		end
	end
	
	print("[TableService] Ready.")
end

return TableService

