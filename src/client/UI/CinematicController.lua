local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local CinematicController = {}

-- Constants
local YAW_FIX_DEG = 180

-- State
local currentRig = nil
local currentTrack = nil
local currentConnection = nil
local savedCameraState = nil
local isCinematicActive = false
local frozenCFrame = nil -- Captured CFrame for freeze frame
local currentToken = nil -- Token to make Stop() idempotent

-- Helper: Get Anchor BasePart from SpinDisplay (prefer ItemAnchor > BillboardAnchor > first BasePart)
local function getAnchorPart(tableModel)
	if not tableModel then return nil end

	local spinDisplay = tableModel:FindFirstChild("SpinDisplay", true)
	if not spinDisplay then return nil end

	-- If SpinDisplay is a BasePart, use it
	if spinDisplay:IsA("BasePart") then
		return spinDisplay
	end

	-- If SpinDisplay is a Model, use PrimaryPart or first BasePart
	if spinDisplay:IsA("Model") then
		return spinDisplay.PrimaryPart or spinDisplay:FindFirstChildWhichIsA("BasePart", true)
	end

	-- If SpinDisplay is a Folder, prefer ItemAnchor > BillboardAnchor > first BasePart
	if spinDisplay:IsA("Folder") then
		local itemAnchor = spinDisplay:FindFirstChild("ItemAnchor", true)
		if itemAnchor and itemAnchor:IsA("BasePart") then
			return itemAnchor
		end
		
		local billboardAnchor = spinDisplay:FindFirstChild("BillboardAnchor", true)
		if billboardAnchor and billboardAnchor:IsA("BasePart") then
			return billboardAnchor
		end
		
		return spinDisplay:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

-- Internal cleanup method (safe, no external dependencies)
local function _cleanupInternal()
	if currentConnection then
		currentConnection:Disconnect()
		currentConnection = nil
	end
	if currentTrack then
		pcall(function() 
			currentTrack:Stop()
			currentTrack:AdjustSpeed(1)
		end)
		currentTrack = nil
	end
	if currentRig then
		pcall(function() currentRig:Destroy() end)
		currentRig = nil
	end
	isCinematicActive = false
	frozenCFrame = nil
	currentToken = nil
end

function CinematicController.Init()
	-- REMOVED: Direct remote listeners
	-- UIController is now the only listener to avoid double-start
	-- CinematicController is a pure module: Play() and Stop() are called directly
	print("[CINE] Init() called - remotes handled by UIController")
	
	-- Warmup immediately on init
	task.spawn(function()
		CinematicController.Warmup()
	end)
end

function CinematicController.Warmup()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return end
	
	-- Preload Spin Anim
	local ContentProvider = game:GetService("ContentProvider")
	local spinAnimId = "rbxassetid://80453620398560"
	local anim = Instance.new("Animation")
	anim.AnimationId = spinAnimId
	
	pcall(function()
		ContentProvider:PreloadAsync({anim})
		print("[CINE] Warmup: Animation preloaded")
	end)
	
	-- Dummy load to warm Animator (optional but good)
	local tempModel = Instance.new("Model")
	local tempAnimController = Instance.new("AnimationController", tempModel)
	local tempAnimator = Instance.new("Animator", tempAnimController)
	tempModel.Parent = workspace
	
	pcall(function()
		local track = tempAnimator:LoadAnimation(anim)
		track:Play()
		track:Stop()
	end)
	tempModel:Destroy()
	print("[CINE] Warmup complete")
end

function CinematicController.Play(animId, duration, tableModel)
	-- Generate unique token for this cinematic session
	currentToken = os.clock() .. "_" .. math.random(1000, 9999)
	local playToken = currentToken
	isCinematicActive = true
	
	print("[CINE] Play() called, token:", playToken)
	
	-- Cleanup any existing cinematic first (safe internal cleanup)
	if currentRig or currentConnection or currentTrack then
		warn("[CINE] Cleaning up existing cinematic before starting new one")
		-- Use internal cleanup method instead of calling Stop() (which may not be defined in this scope)
		_cleanupInternal()
	end
	
	-- 1. Save Camera State
	local cam = Workspace.CurrentCamera
	if not savedCameraState then
		print("[CINE] Saving camera state - Type:", cam.CameraType, "FOV:", cam.FieldOfView)
		savedCameraState = {
			CameraType = cam.CameraType,
			CameraSubject = cam.CameraSubject,
			FieldOfView = cam.FieldOfView
		}
	end
	
	-- 2. Cleanup old (already done by _cleanupInternal if needed)
	
	-- 3. Load Rig from ReplicatedStorage (fast, no blocking waits)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then 
		warn("[CINE] Assets missing"); 
		isCinematicActive = false
		return 
	end
	local cinematics = assets:FindFirstChild("Cinematics")
	if not cinematics then 
		warn("[CINE] Cinematics folder missing"); 
		isCinematicActive = false
		return 
	end
	local rigTemplate = cinematics:FindFirstChild("CamRig2")
	if not rigTemplate then 
		warn("[CINE] CamRig2 missing"); 
		isCinematicActive = false
		return 
	end
	
	local rig = rigTemplate:Clone()
	rig.Name = "SpinCinematicRig_Active"
	rig.Parent = Workspace
	currentRig = rig
	
	-- 4. Find camera target BasePart (exact name "camera", NOT Bone)
	-- Must be BasePart (MeshPart/Part), NOT Bone
	local cameraPart = nil
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") and string.lower(descendant.Name) == "camera" then
			cameraPart = descendant
			break
		end
	end
	
	-- Fallback: try FindFirstChild if search didn't work
	if not cameraPart then
		local found = rig:FindFirstChild("camera", true)
		if found and found:IsA("BasePart") then
			cameraPart = found
		end
	end
	
	if not cameraPart or not cameraPart:IsA("BasePart") then
		warn("[CINE] Camera BasePart not found in rig")
		isCinematicActive = false
		_cleanupInternal()
		return
	end
	
	print("[CINE] Using camera BasePart:", cameraPart:GetFullName(), "Class:", cameraPart.ClassName)
	
	-- Ensure Camera can move (unanchored)
	if cameraPart.Anchored then
		cameraPart.Anchored = false
	end
	
	-- 5. Align rig so cameraPart.CFrame at t=0 matches anchor CFrame (fix framing offset)
	local anchorPart = getAnchorPart(tableModel)
	local desiredCamWorldCFrame = anchorPart and anchorPart.CFrame or Workspace.CurrentCamera.CFrame
	
	-- Get cameraPart's initial world CFrame (before animation plays)
	local initialCamWorld = cameraPart.CFrame
	
	-- Compute delta to align cameraPart to desired position
	local delta = desiredCamWorldCFrame * initialCamWorld:Inverse()
	
	-- Apply delta to entire rig with 180° yaw correction (fix rotation)
	local yawFix = CFrame.Angles(0, math.rad(YAW_FIX_DEG), 0)
	rig:PivotTo((delta * rig:GetPivot()) * yawFix)
	
	-- 6. Camera follow (strict, no lerp/smoothing) - START IMMEDIATELY (before animation loads)
	-- This ensures camera switches instantly when Play() is called
	cam.CameraType = Enum.CameraType.Scriptable
	currentConnection = RunService.RenderStepped:Connect(function()
		if not rig or not rig.Parent or currentToken ~= playToken then return end
		-- Use frozen CFrame if available (end freeze), otherwise use live cameraPart
		if frozenCFrame then
			cam.CFrame = frozenCFrame
		elseif cameraPart then
			cam.CFrame = cameraPart.CFrame
		end
	end)
	
	-- 7. Animation playback (after camera is already following)
	local animController = rig:FindFirstChildOfClass("AnimationController")
	if not animController then
		warn("[CINE] AnimationController missing")
		isCinematicActive = false
		_cleanupInternal()
		return
	end
	
	-- Ensure Animator exists
	local animator = animController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animController
	end
	
	-- Find Cinematic Animation object
	local anim = animController:FindFirstChild("Cinematic")
	if not anim or not anim:IsA("Animation") then
		warn("[CINE] Cinematic Animation not found in AnimationController")
		isCinematicActive = false
		_cleanupInternal()
		return
	end
	
	-- Set AnimationId from server
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	
	-- Load and play animation
	local success, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	
	if not success or not track then
		warn("[CINE] Failed to load animation")
		isCinematicActive = false
		_cleanupInternal()
		return
	end
	
	-- Wait for animation to load (with timeout, non-blocking)
	local waitTime = 0
	while track.Length == 0 and waitTime < 2 do
		task.wait(0.05)
		waitTime = waitTime + 0.05
	end
	
	if track.Length == 0 then
		warn("[CINE] Animation failed to load")
		isCinematicActive = false
		_cleanupInternal()
		return
	end
	
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:Play(0)
	currentTrack = track
	
	print("[CINE] track started, len:", track.Length)
	
	-- 8. Hold Last Frame (capture TRUE last frame, no snap)
	local EPS = 1/60 -- ~0.0167 seconds before end
	local freezeConnection = nil
	
	local function captureFreezeFrame()
		-- Only freeze if this is still the active cinematic (token check)
		if currentToken ~= playToken then return end
		if not isCinematicActive or not currentTrack or not cameraPart then return end
		
		local currentTime = currentTrack.TimePosition
		local trackLength = currentTrack.Length
		
		-- Never capture freeze at time=0
		if currentTime <= 0 or trackLength <= 0 then
			return false -- Not ready yet
		end
		
		-- Calculate capture time: min(duration, trackLength) - EPS to get TRUE last frame
		local captureTime = math.min(duration, trackLength) - EPS
		
		-- Only capture if we're at or past the capture point
		if currentTime >= captureTime then
			frozenCFrame = cameraPart.CFrame
			currentTrack:AdjustSpeed(0)
			print("[CINE] freeze captured CFrame at time:", currentTime, "len:", trackLength, "captureTime:", captureTime)
			return true -- Captured
		end
		
		return false -- Not ready yet
	end
	
	-- Monitor track progress and capture at the right moment
	local freezeMonitor = RunService.Heartbeat:Connect(function()
		if currentToken ~= playToken then
			if freezeMonitor then freezeMonitor:Disconnect() end
			return
		end
		
		if captureFreezeFrame() then
			-- Successfully captured, disconnect monitor
			if freezeMonitor then freezeMonitor:Disconnect() end
			freezeMonitor = nil
		end
	end)
	
	-- Also handle track.Stopped as backup
	track.Stopped:Connect(function()
		if currentToken == playToken then
			captureFreezeFrame()
		end
	end)
	
	-- Safety: capture after duration (if monitor didn't catch it)
	task.delay(duration, function()
		if currentToken == playToken and not frozenCFrame then
			captureFreezeFrame()
		end
		if freezeMonitor then
			freezeMonitor:Disconnect()
			freezeMonitor = nil
		end
	end)
end

function CinematicController.Stop(immediate)
	-- immediate: if true, skip freeze frame and restore camera instantly
	-- Make Stop() idempotent - if already stopped, return immediately
	if not isCinematicActive and not currentRig and not currentConnection and not currentTrack then
		print("[CINE] Stop() called but already stopped (idempotent)")
		return
	end
	
	local stopToken = currentToken
	print("[CINE] Stop() called at", os.clock(), "immediate:", immediate or false, "token:", stopToken)
	
	-- Mark as inactive FIRST
	isCinematicActive = false
	frozenCFrame = nil -- Clear frozen frame
	currentToken = nil -- Clear token so RenderStepped stops
	
	-- Disconnect RenderStepped FIRST (prevents any camera updates during restore)
	if currentConnection then
		currentConnection:Disconnect()
		currentConnection = nil
		print("[CINE] RenderStepped disconnected")
	end
	
	-- Disconnect any freeze monitor connections
	-- (Note: freezeMonitor is local to Play(), but we ensure cleanup here too)
	
	-- Restore Camera IMMEDIATELY (no delay, no lerp, no bounce)
	local cam = Workspace.CurrentCamera
	local localPlayer = Players.LocalPlayer
	
	-- Diagnostic: Check FOV before restore
	local fovBefore = cam.FieldOfView
	print("[CINE] FOV before restore:", fovBefore)
	
	if savedCameraState then
		-- Restore camera type and subject instantly
		cam.CameraType = Enum.CameraType.Custom
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
			print("[CINE] Camera restored - Type: Custom, Subject: Humanoid")
		else
			print("[CINE] Camera restored - Type: Custom, Subject: nil (no character)")
		end
		
		-- Diagnostic: Verify FOV unchanged
		local fovAfter = cam.FieldOfView
		if fovBefore ~= fovAfter then
			warn("[CINE] WARNING: FOV changed from", fovBefore, "to", fovAfter)
		else
			print("[CINE] FOV unchanged:", fovAfter)
		end
		
		savedCameraState = nil
	end
	
	-- Stop track and destroy rig AFTER camera is restored
	if currentTrack then
		pcall(function() 
			currentTrack:Stop()
			currentTrack:AdjustSpeed(1) -- Reset speed in case it was frozen
		end)
		currentTrack = nil
	end
	
	if currentRig then
		pcall(function() currentRig:Destroy() end)
		currentRig = nil
	end
	
	-- Final safety: ensure camera is not stuck in Scriptable mode
	local cam = Workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Scriptable then
		-- Only restore if we don't have a character (fallback)
		local localPlayer = Players.LocalPlayer
		local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraType = Enum.CameraType.Custom
			cam.CameraSubject = hum
		end
	end
	
	-- Clear saved camera state
	savedCameraState = nil
	
	print("[CINE] Stop() complete at", os.clock(), "token:", stopToken)
end

return CinematicController
