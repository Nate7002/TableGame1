local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local TableService = {}

-- Constants
local TABLE_TEMPLATE_PATH = "Assets/Tables/TableTemplate/TableModel"
local MAX_TABLES = 12
local GRID_ORIGIN = Vector3.new(0, 2.634, 20) -- Precise height adjustment
local SPACING_X = 15
local SPACING_Z = 15
local COLS = 5
local DEBUG = false

-- State
local activeTables = {} -- [model] = { SeatA = player?, SeatB = player?, State = "Empty" }
local tableReadyEvent = Instance.new("BindableEvent")
local seatBaselines = {} -- [seat] = { CFrame = ... }

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

local function getTableSpawnParts()
	local map = Workspace:FindFirstChild("Map")
	if not map then return nil end

	local hitboxes = map:FindFirstChild("Hitboxes")
	if not hitboxes then return nil end

	local parts = {}
	for _, inst in ipairs(hitboxes:GetChildren()) do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end

	if #parts == 0 then return nil end

	-- Hitbox01..Hitbox12 sorts correctly
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)

	return parts
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
		-- Reset seat position when it becomes empty
		TableService.ResetSeat(seat, "occupant_cleared")
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
	
	-- BUG FIX A: Cache original CFrame and set network ownership
	for _, seat in ipairs({seatA, seatB}) do
		-- Cache baseline CFrame
		seatBaselines[seat] = { CFrame = seat.CFrame }
		
		-- Force server-authoritative (prevent client network ownership from moving seat)
		pcall(function()
			if seat.Anchored then
				-- Already anchored, no network owner to set
			else
				-- Set network owner to nil (server authority)
				seat:SetNetworkOwner(nil)
			end
		end)
		
		if DEBUG then
			print(string.format("[TableService] Cached baseline for %s: %s", seat.Name, tostring(seat.CFrame)))
		end
	end
	
	-- 3) Prompt Config (Ensure visibility)
	for _, prompt in ipairs({promptA, promptB}) do
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 8
		prompt.ActionText = "Sit"
		-- prompt.ObjectText = "Table" -- Optional
	end

	-- 4) Billboard Config Check
	local spinDisplay = model:FindFirstChild("SpinDisplay")
	local billboardAnchor = spinDisplay and spinDisplay:FindFirstChild("BillboardAnchor")
	local billboardAttachment = billboardAnchor and billboardAnchor:FindFirstChild("BillboardAttachment")
	
	if not billboardAttachment then
		warn(string.format("[TableService] Spawned table missing BillboardAttachment: %s", model:GetFullName()))
	end
	
	-- State Init
	activeTables[model] = {
		SeatA = nil,
		SeatB = nil,
		LockedA = false,
		LockedB = false,
		State = "Empty",
		Seats = {seatA, seatB}, -- Store reference for cleanup
		Prompts = {promptA, promptB} -- Store for ForceUnlock
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

	local spawnParts = getTableSpawnParts()

	local totalToSpawn = MAX_TABLES
	if spawnParts then
		totalToSpawn = math.min(MAX_TABLES, #spawnParts)
	end

	for i = 1, totalToSpawn do
		local tbl = template:Clone()
		tbl.Name = string.format("Table_%02d", i)
		tbl.Parent = parentFolder

		if spawnParts then
			local sp = spawnParts[i]
			if not sp then
				-- No more hitboxes; stop spawning tables
				break
			end
			tbl:PivotTo(sp.CFrame)
		else
			-- Grid Layout (fallback when Hitboxes missing)
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
		end

		setupTable(tbl)
	end
end

-- Public API

-- Problem 3: ForceUnlockTable
function TableService.ForceUnlockTable(tableModel, reason)
	local data = activeTables[tableModel]
	if not data then return end
	
	print(string.format("[TableService] ForceUnlockTable %s reason=%s", tableModel.Name, reason or "unknown"))
	
	-- Clear locks
	data.LockedA = false
	data.LockedB = false
	
	-- Process seats
	if data.Seats then
		for _, seat in ipairs(data.Seats) do
			-- Temporarily enable to allow state changes
			seat.Disabled = false
			
			local occupant = seat.Occupant
			if occupant then
				local hum = occupant.Parent:FindFirstChild("Humanoid")
				if hum then
					print(string.format("[TableService] Force unseating %s from %s", occupant.Parent.Name, seat.Name))
					hum.Sit = false
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end
			
			-- Reset to baseline
			TableService.ResetSeat(seat, "ForceUnlock")
			
			-- Re-disable after delay if no occupant
			task.delay(0.2, function()
				if not seat.Occupant then
					seat.Disabled = true
				end
			end)
		end
	end
	
	-- Restore prompts
	if data.Prompts then
		for _, prompt in ipairs(data.Prompts) do
			prompt.Enabled = true
		end
	end
	
	-- Clear state
	data.SeatA = nil
	data.SeatB = nil
	updateTableState(tableModel)
end

-- BUG FIX A: ResetSeat function to restore seat to original position
function TableService.ResetSeat(seat, reason)
	if not seat or not seat.Parent then return end
	
	local baseline = seatBaselines[seat]
	if not baseline then
		if DEBUG then
			warn(string.format("[TableService] ResetSeat: no baseline for %s", seat:GetFullName()))
		end
		return
	end
	
	local beforeCF = seat.CFrame
	seat.CFrame = baseline.CFrame
	
	if DEBUG then
		print(string.format("[TableService] ResetSeat: %s reason=%s before=%s after=%s", 
			seat.Name, reason or "unknown", tostring(beforeCF), tostring(seat.CFrame)))
	end
end

-- BUG FIX A: ResetTableSeats - resets all seats for a table (called on match end)
function TableService.ResetTableSeats(tableModel, reason)
	local data = activeTables[tableModel]
	if not data or not data.Seats then return end
	
	for _, seat in ipairs(data.Seats) do
		TableService.ResetSeat(seat, reason)
	end
end

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
	
	-- UX FIX B: Setup LeaveSeat remote handler
	local Remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 5)
	if Remotes then
		local LeaveSeat = Remotes:FindFirstChild("LeaveSeat")
		if LeaveSeat then
			LeaveSeat.OnServerEvent:Connect(function(player)
				-- Find which seat the player is in
				if not (player and player.Character) then return end
				
				local humanoid = player.Character:FindFirstChild("Humanoid")
				if not humanoid then return end
				
				-- Check if seated
				if not humanoid.Sit then return end
				
				-- Force unseat
				humanoid.Sit = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				
				print(string.format("[TableService] %s left seat via UI button", player.Name))
			end)
			print("[TableService] LeaveSeat remote handler connected")
		else
			warn("[TableService] LeaveSeat remote not found")
		end
	end
	
	print("[TableService] Ready.")
end

return TableService
