local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local IntroTableGuide = {}
IntroTableGuide.__index = IntroTableGuide

local GUIDE_HEIGHT = 2.6
local GUIDE_ARROW_OFFSET = 3.4

local function getTables()
	local tables = {}
	local seen = {}
	local searchContainers = {}

	local directTables = Workspace:FindFirstChild("Tables")
	if directTables then
		table.insert(searchContainers, directTables)
	end

	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby then
		local lobbyTables = lobby:FindFirstChild("Tables")
		if lobbyTables then
			table.insert(searchContainers, lobbyTables)
		end
	end

	table.insert(searchContainers, Workspace)

	for _, container in ipairs(searchContainers) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") and not seen[child] and child:FindFirstChild("SpinDisplay") then
				seen[child] = true
				table.insert(tables, child)
			end
		end
	end

	return tables
end

local function getSeatInstances(tableModel)
	if not tableModel or not tableModel.Parent then
		return nil, nil
	end

	local chairRed = tableModel:FindFirstChild("ChairRed")
	local chairBlue = tableModel:FindFirstChild("ChairBlue")
	local promptPartA = chairRed and chairRed:FindFirstChild("PromptPartA")
	local promptPartB = chairBlue and chairBlue:FindFirstChild("PromptPartB")
	local seatA = promptPartA and promptPartA:FindFirstChild("SeatA")
	local seatB = promptPartB and promptPartB:FindFirstChild("SeatB")
	return seatA, seatB
end

local function getFreeSeatCount(tableModel)
	local seatA, seatB = getSeatInstances(tableModel)
	local freeSeats = 0

	if seatA and not seatA.Occupant then
		freeSeats += 1
	end
	if seatB and not seatB.Occupant then
		freeSeats += 1
	end

	return freeSeats
end

local function getAnchorData(tableModel)
	if not tableModel or not tableModel.Parent then
		return nil
	end

	local spinDisplay = tableModel:FindFirstChild("SpinDisplay")
	local billboardAnchor = spinDisplay and spinDisplay:FindFirstChild("BillboardAnchor")
	local billboardAttachment = billboardAnchor and billboardAnchor:FindFirstChild("BillboardAttachment")
	if billboardAttachment and billboardAttachment:IsA("Attachment") then
		return {
			part = billboardAttachment.Parent,
			position = billboardAttachment.WorldPosition,
		}
	end
	if billboardAnchor and billboardAnchor:IsA("BasePart") then
		return {
			part = billboardAnchor,
			position = billboardAnchor.Position,
		}
	end
	if tableModel.PrimaryPart then
		return {
			part = tableModel.PrimaryPart,
			position = tableModel.PrimaryPart.Position,
		}
	end
	return {
		part = nil,
		position = tableModel:GetPivot().Position,
	}
end

function IntroTableGuide.new()
	local self = setmetatable({}, IntroTableGuide)
	self._random = Random.new()
	self._folder = nil
	self._startPart = nil
	self._endPart = nil
	self._beam = nil
	self._billboard = nil
	self._currentTarget = nil
	self._active = false
	self._connection = nil
	return self
end

function IntroTableGuide:_ensureRuntime()
	if self._folder and self._folder.Parent then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "IntroTableGuide_Runtime"
	folder.Parent = Workspace
	self._folder = folder

	local startPart = Instance.new("Part")
	startPart.Name = "GuideStart"
	startPart.Anchored = true
	startPart.CanCollide = false
	startPart.CanQuery = false
	startPart.CanTouch = false
	startPart.Transparency = 1
	startPart.Size = Vector3.new(0.2, 0.2, 0.2)
	startPart.Parent = folder
	self._startPart = startPart

	local endPart = startPart:Clone()
	endPart.Name = "GuideEnd"
	endPart.Parent = folder
	self._endPart = endPart

	local startAttachment = Instance.new("Attachment")
	startAttachment.Name = "StartAttachment"
	startAttachment.Parent = startPart

	local endAttachment = Instance.new("Attachment")
	endAttachment.Name = "EndAttachment"
	endAttachment.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.Enabled = false
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Segments = 16
	beam.Width0 = 0.22
	beam.Width1 = 0.14
	beam.CurveSize0 = 1.4
	beam.CurveSize1 = -1.4
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(240, 252, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(98, 220, 255)),
	})
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0.28),
	})
	beam.Parent = folder
	self._beam = beam

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GuideArrow"
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Size = UDim2.fromOffset(90, 102)
	billboard.Adornee = endPart
	billboard.Parent = folder
	self._billboard = billboard

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Position = UDim2.new(0, 0, 0, 0)
	arrow.Size = UDim2.new(1, 0, 0, 62)
	arrow.Font = Enum.Font.FredokaOne
	arrow.Text = "V"
	arrow.TextColor3 = Color3.fromRGB(86, 214, 255)
	arrow.TextSize = 48
	arrow.TextStrokeTransparency = 0.1
	arrow.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
	arrow.Parent = billboard

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, 0)
	caption.Size = UDim2.new(1, 0, 0, 30)
	caption.Font = Enum.Font.GothamBold
	caption.Text = "SIT HERE"
	caption.TextColor3 = Color3.fromRGB(244, 251, 255)
	caption.TextSize = 18
	caption.TextStrokeTransparency = 0.25
	caption.TextStrokeColor3 = Color3.fromRGB(37, 88, 140)
	caption.Parent = billboard
end

function IntroTableGuide:_pickTarget()
	local emptyTables = {}
	local openTables = {}

	for _, tableModel in ipairs(getTables()) do
		local freeSeats = getFreeSeatCount(tableModel)
		if freeSeats >= 2 then
			table.insert(emptyTables, tableModel)
		elseif freeSeats >= 1 then
			table.insert(openTables, tableModel)
		end
	end

	local pool = #emptyTables > 0 and emptyTables or openTables
	if #pool == 0 then
		return nil
	end

	return pool[self._random:NextInteger(1, #pool)]
end

function IntroTableGuide:_isTargetUsable(tableModel)
	return tableModel and tableModel.Parent and getFreeSeatCount(tableModel) > 0
end

function IntroTableGuide:_hideGuide()
	if self._beam then
		self._beam.Enabled = false
	end
	if self._billboard then
		self._billboard.Enabled = false
	end
end

function IntroTableGuide:_getPlayerOrigin()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	return hrp.Position + hrp.CFrame.LookVector * 1.2 + Vector3.new(0, GUIDE_HEIGHT, 0)
end

function IntroTableGuide:_update(now)
	if not self._active then
		self:_hideGuide()
		return
	end

	if not self:_isTargetUsable(self._currentTarget) then
		self._currentTarget = self:_pickTarget()
	end

	if not self._currentTarget then
		self:_hideGuide()
		return
	end

	local playerOrigin = self:_getPlayerOrigin()
	local anchorData = getAnchorData(self._currentTarget)
	if not playerOrigin or not anchorData or not anchorData.position then
		self:_hideGuide()
		return
	end

	local targetPosition = anchorData.position + Vector3.new(0, GUIDE_HEIGHT + 0.4, 0)
	self._startPart.Position = playerOrigin
	self._endPart.Position = targetPosition
	self._beam.Enabled = true
	self._billboard.Enabled = true
	self._billboard.StudsOffsetWorldSpace = Vector3.new(0, GUIDE_ARROW_OFFSET + math.sin(now * 3.2) * 0.35, 0)

	local pulse = 90 + math.floor((math.sin(now * 4.5) * 0.5 + 0.5) * 8)
	self._billboard.Size = UDim2.fromOffset(pulse, 102)
end

function IntroTableGuide:Start(targetTable)
	self:_ensureRuntime()
	self._active = true
	self._currentTarget = self:_isTargetUsable(targetTable) and targetTable or self:_pickTarget()

	if self._connection then
		self._connection:Disconnect()
	end

	self._connection = RunService.RenderStepped:Connect(function()
		self:_update(os.clock())
	end)

	self:_update(os.clock())
end

function IntroTableGuide:Stop()
	self._active = false
	self._currentTarget = nil
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	self:_hideGuide()
	if self._folder then
		self._folder:Destroy()
		self._folder = nil
	end
	self._startPart = nil
	self._endPart = nil
	self._beam = nil
	self._billboard = nil
end

function IntroTableGuide:Destroy()
	self:Stop()
end

return IntroTableGuide
