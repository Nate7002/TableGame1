local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent.Theme)
local CountdownWidget = require(script.Parent.CountdownWidget)
local AnimatedBackgroundController = require(script.Parent.Parent.AnimatedBackgroundController)
local FxService = require(script.Parent.Parent.FxService)
local CinematicController = require(script.Parent.Parent.CinematicController)

-- Safe requires for UI Animations
local AnimationRuntime
local Anim_Hover
local Anim_Press
local Anim_Ripple

local function safeRequire(moduleInstance, name)
	if not moduleInstance then
		warn("[ChoicePopup] Missing module instance for: " .. tostring(name))
		return nil
	end
	
	local success, result = pcall(function()
		return require(moduleInstance)
	end)
	
	if success then
		return result
	else
		warn("[ChoicePopup] Failed to load animation module: " .. tostring(name) .. " - " .. tostring(result))
		return nil
	end
end

-- Try to load UIAnimations by INSTANCE
local success, result = pcall(function()
	local UIAnimations = ReplicatedStorage:WaitForChild("UIAnimations", 2)
	if UIAnimations then
		local Modules = UIAnimations:WaitForChild("Modules", 2)
		if Modules then
			AnimationRuntime = safeRequire(Modules:WaitForChild("AnimationRuntime", 2), "AnimationRuntime")
			Anim_Hover = safeRequire(Modules:WaitForChild("Frame_ScaleDown", 2), "Frame_ScaleDown")
			Anim_Press = safeRequire(Modules:WaitForChild("ImageButton_PressDown", 2), "ImageButton_PressDown")
			Anim_Ripple = safeRequire(Modules:WaitForChild("ImageButton_RippleClick", 2), "ImageButton_RippleClick")
			
			if AnimationRuntime then
				print("[UIAnim] AnimationRuntime loaded OK")
			end
		end
	end
end)
if not success then
	warn("[ChoicePopup] UIAnimations folder missing or failed to load: " .. tostring(result))
end

if not AnimationRuntime then
	warn("[ChoicePopup] AnimationRuntime missing -> animations disabled")
end

local ChoicePopup = {}
ChoicePopup.__index = ChoicePopup

-- Blur state for popup (NO FOV changes)
local popupBlur = nil

-- Helper: Apply blur when popup shows
local function applyPopupEffects()
	pcall(function()
		local lighting = game:GetService("Lighting")
		popupBlur = lighting:FindFirstChild("DoubleDownBlur")
		if not popupBlur then
			popupBlur = Instance.new("BlurEffect")
			popupBlur.Name = "DoubleDownBlur"
			popupBlur.Size = 0
			popupBlur.Enabled = true
			popupBlur.Parent = lighting
		end
		
		popupBlur.Size = 16
		-- NO FOV changes anywhere
	end)
end

-- Helper: Remove blur when popup closes
local function removePopupEffects()
	pcall(function()
		if popupBlur then
			popupBlur.Size = 0
			popupBlur.Enabled = false
		end
	end)
end

-- Helper: Play Sound
local function playFxSound(soundName)
	local fxFolder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("FX")
	if not fxFolder then return end
	
	local soundTemplate = fxFolder:FindFirstChild(soundName)
	if soundTemplate and soundTemplate:IsA("Sound") then
		local sound = soundTemplate:Clone()
		sound.Parent = game:GetService("SoundService") -- Preferred parent for global UI sounds
		sound.TimePosition = 0
		sound:Play()
		Debris:AddItem(sound, sound.TimeLength + 0.5)
	end
end

-- Fallback animation helper if Runtime fails mult-reg or is missing
local function applyFallbackAnimations(btn)
	-- Store original size if not present
	if not btn:GetAttribute("OrigScale") then
		btn:SetAttribute("OrigScale", 1) 
	end
	
	-- Hover Tween
	btn.MouseEnter:Connect(function()
		local t = TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(0.92, 0.92)
		})
		t:Play()
	end)
	
	btn.MouseLeave:Connect(function()
		local t = TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(1, 1)
		})
		t:Play()
	end)
	
	-- Press Tween (One-shot)
	btn.Activated:Connect(function()
		local t1 = TweenService:Create(btn, TweenInfo.new(0.05, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(0.96, 0.96)
		})
		t1:Play()
		t1.Completed:Wait()
		local t2 = TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
			Size = UDim2.fromScale(1, 1)
		})
		t2:Play()
	end)
end

function ChoicePopup.new(parentGui)
	local self = setmetatable({}, ChoicePopup)
	self._parent = parentGui
	
	-- Create static structure (hidden initially)
	local overlay = Instance.new("Frame")
	overlay.Name = "ChoiceOverlay"
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 1 -- Dimmer Layer
	overlay.Visible = false
	overlay.Parent = parentGui
	self._overlay = overlay
	
	-- Popup Frame
	local frame = Instance.new("Frame")
	frame.Name = "Popup"
	frame.BackgroundColor3 = Theme.Colors.Primary
	frame.Size = UDim2.fromOffset(400, 250)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.BackgroundTransparency = 1
	frame.ZIndex = 10 -- Card Layer (Above Background)
	frame.Parent = overlay
	self._frame = frame
	self._originalSize = frame.Size
	
	Instance.new("UICorner", frame).CornerRadius = Theme.Sizes.CornerRadius
	
	-- Animated Background (Placeholder for runtime attachment)
	self._bgCleanup = nil
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -120, 0, 40)
	title.Position = UDim2.new(0, 20, 0, 20)
	title.Font = Theme.Font.Header
	title.TextColor3 = Theme.Colors.Text
	title.TextSize = Theme.Sizes.TextHeader
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 20 -- Text Layer
	title.Parent = frame
	self._titleLabel = title
	
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Theme.Stroke.Color
	titleStroke.Transparency = Theme.Stroke.Transparency
	titleStroke.Thickness = Theme.Stroke.Thickness
	titleStroke.Parent = title
	
	-- Description
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, -40, 0, 60)
	desc.Position = UDim2.new(0, 20, 0, 60)
	desc.Font = Theme.Font.Body
	desc.TextColor3 = Theme.Colors.TextDim
	desc.TextSize = Theme.Sizes.TextBody
	desc.TextWrapped = true
	desc.RichText = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.ZIndex = 20 -- Text Layer
	desc.Parent = frame
	self._descLabel = desc
	
	local descStroke = Instance.new("UIStroke")
	descStroke.Color = Theme.Stroke.Color
	descStroke.Transparency = Theme.Stroke.Transparency
	descStroke.Thickness = Theme.Stroke.Thickness
	descStroke.Parent = desc
	
	-- Options Container
	local optionsContainer = Instance.new("Frame")
	optionsContainer.Name = "Options"
	optionsContainer.BackgroundTransparency = 1
	optionsContainer.Size = UDim2.new(1, -40, 0, 50)
	optionsContainer.Position = UDim2.new(0, 20, 1, -70)
	optionsContainer.ZIndex = 20 -- Buttons Layer
	optionsContainer.Parent = frame
	self._optionsContainer = optionsContainer
	
	local uiList = Instance.new("UIListLayout")
	uiList.FillDirection = Enum.FillDirection.Horizontal
	uiList.Padding = UDim.new(0, 15)
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiList.Parent = optionsContainer
	
	-- Timer Widget
	self._countdown = CountdownWidget.new(frame)
	self._countdown:SetPosition(UDim2.new(1, -20, 0, 20), Vector2.new(1, 0))
	
	-- Status Label (for "Waiting on opponent..." state)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, -40, 0, 40)
	statusLabel.Position = UDim2.new(0, 20, 0, 120)
	statusLabel.Font = Theme.Font.Body
	statusLabel.TextColor3 = Theme.Colors.Text
	statusLabel.TextSize = Theme.Sizes.TextBody
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.TextYAlignment = Enum.TextYAlignment.Center
	statusLabel.ZIndex = 25
	statusLabel.Visible = false
	statusLabel.Parent = frame
	self._statusLabel = statusLabel
	
	local statusStroke = Instance.new("UIStroke")
	statusStroke.Color = Theme.Stroke.Color
	statusStroke.Transparency = Theme.Stroke.Transparency
	statusStroke.Thickness = Theme.Stroke.Thickness
	statusStroke.Parent = statusLabel
	
	self._connections = {}
	self._isClosing = false
	self._isWaiting = false
	self._currentTimerId = 0
	
	return self
end

function ChoicePopup:Show(payload, onResponse)
	print("[UI] Show called at", os.clock())
	
	-- Reset state but DON'T call Hide() (which destroys overlay)
	-- Only reset closing/waiting flags
	self._isClosing = false
	self._isWaiting = false
	self._overlay.Visible = true
	
	-- Hide status label initially
	if self._statusLabel then
		self._statusLabel.Visible = false
	end
	
	-- Apply blur when popup appears (not during cinematic)
	applyPopupEffects()
	
	-- Attach Animated Background (only if not already attached)
	local tint = AnimatedBackgroundController.GetTintColor(payload.rarity or "Common")
	if not self._bgCleanup then
		-- First time: create background
		self._bgCleanup = AnimatedBackgroundController.AttachAnimatedBackground(self._overlay, {
			speed = 0.05,
			tintColor = tint
		})
	else
		-- Update existing background tint if needed (reuse overlay)
		-- Background controller should handle tint updates internally
		-- If it doesn't, we'll need to update it, but for now just reuse
	end
	
	-- Update Content
	self._titleLabel.Text = payload.title or "Choice"
	self._descLabel.Text = payload.description or "Please select an option."
	
	-- Play Popup Sound (Server Controlled)
	if payload.sfx then
		FxService.Play(payload.sfx)
	end
	
	-- Clear Buttons
	for _, child in ipairs(self._optionsContainer:GetChildren()) do
		if child:IsA("Frame") or child:IsA("GuiObject") then
			if child:IsA("UIListLayout") then continue end
			child:Destroy()
		end
	end
	
	-- Create Buttons
	if payload.options then
		local count = #payload.options
		for _, opt in ipairs(payload.options) do
			self:CreateButton(opt, count, onResponse)
		end
	end
	
	-- Animate In
	self:AnimateIn()
	
	-- Timer
	self._currentTimerId += 1
	local timerId = self._currentTimerId
	
	if payload.endTime then
		self:StartSyncedTimer(payload.endTime, onResponse, timerId)
		self._countdown:SetVisible(true)
	elseif payload.timeout then
		self:StartTimer(payload.timeout, onResponse, timerId)
		self._countdown:SetVisible(true)
	else
		self._countdown:SetVisible(false)
	end
end

function ChoicePopup:CreateButton(option, count, onResponse)
	-- Wrapper for UIListLayout to hold space
	local wrapper = Instance.new("Frame")
	wrapper.Name = "Wrapper_" .. option.id
	wrapper.BackgroundTransparency = 1
	wrapper.ZIndex = 20
	wrapper.ClipsDescendants = false -- Ensure button scale/ripple isn't aggressively clipped
	if count then
		wrapper.Size = UDim2.new(1/count, -10, 1, 0)
	else
		wrapper.Size = UDim2.new(0, 150, 1, 0)
	end
	wrapper.Parent = self._optionsContainer

	-- ImageButton Root
	local btn = Instance.new("ImageButton")
	btn.Name = "Option_" .. option.id
	btn.BackgroundColor3 = Theme.Colors.Secondary
	btn.BackgroundTransparency = 0
	btn.AutoButtonColor = false -- We handle colors manually
	btn.Image = "" -- Blank for now
	btn.ScaleType = Enum.ScaleType.Stretch
	btn.ZIndex = 20
	btn.ClipsDescendants = true -- Required for Ripple containment
	
	-- FIX: Anchor Center for proper scaling animations
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromScale(0.5, 0.5)
	btn.Size = UDim2.fromScale(1, 1)
	
	-- Store original size attributes for dynamic animations
	btn:SetAttribute("OrigXScale", 1)
	btn:SetAttribute("OrigXOffset", 0)
	btn:SetAttribute("OrigYScale", 1)
	btn:SetAttribute("OrigYOffset", 0)
	
	btn.Parent = wrapper
	
	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Theme.Stroke.Color
	btnStroke.Transparency = Theme.Stroke.Transparency
	btnStroke.Thickness = Theme.Stroke.Thickness
	btnStroke.Parent = btn
	
	Instance.new("UICorner", btn).CornerRadius = Theme.Sizes.CornerRadius
	
	-- Text Label
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = Theme.Font.Header
	label.Text = option.label
	label.TextColor3 = Theme.Colors.Text
	label.TextSize = Theme.Sizes.TextBody
	label.TextScaled = false
	label.ZIndex = 30 -- Ensure label is above ripple (ripple will be ZIndex + 2 = 22, so 30 is safe)
	label.Parent = btn
	
	-- Interaction
	local connClick = btn.Activated:Connect(function() -- Activated is better for all devices
		if self._isClosing or self._isWaiting then return end
		
		playFxSound("ButtonClick") -- Play click sound
		print("[UI] Player clicked option:", option.id, "at", os.clock())
		
		-- Send choice to server
		if onResponse then onResponse(option.id) end
		
		-- Show waiting state instead of closing
		self:ShowWaitingState(option.label)
	end)
	table.insert(self._connections, connClick)
	
	-- Hover Sounds & Color
	local connEnter = btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Theme.Colors.Accent
		playFxSound("ButtonHover") -- Play hover sound
	end)
	table.insert(self._connections, connEnter)
	
	local connLeave = btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = Theme.Colors.Secondary
	end)
	table.insert(self._connections, connLeave)
	
	-- Animation Logic (Try Runtime, Fallback to Manual)
	local animsRegistered = false
	
	if AnimationRuntime then
		-- Register each animation separately (AnimationRuntime.run supports one config at a time)
		local boundCount = 0
		
		-- Hover animation (ScaleDown)
		if Anim_Hover then
			local cfg = table.clone(Anim_Hover)
			cfg.prop = "Size"
			cfg.val = UDim2.fromScale(0.92, 0.92)
			-- Config already has event = "hover", keep it
			local success, err = pcall(function()
				AnimationRuntime.run(btn, cfg)
			end)
			if success then
				boundCount = boundCount + 1
			else
				warn("[UIAnim] Hover animation failed:", err)
			end
		end
		
		-- Press animation (PressDown - override to use Size instead of Position)
		if Anim_Press then
			local cfg = table.clone(Anim_Press)
			cfg.prop = "Size" -- Override from Position to Size
			cfg.val = UDim2.fromScale(0.96, 0.96)
			cfg.reset = true -- Keep reset behavior
			cfg.resetTime = 0.1
			-- Config already has event = "click", keep it
			local success, err = pcall(function()
				AnimationRuntime.run(btn, cfg)
			end)
			if success then
				boundCount = boundCount + 1
			else
				warn("[UIAnim] Press animation failed:", err)
			end
		end
		
		-- Ripple animation (RippleClick)
		if Anim_Ripple then
			local cfg = table.clone(Anim_Ripple)
			-- Config already has event = "click" and prop = "Ripple", keep them
			local success, err = pcall(function()
				AnimationRuntime.run(btn, cfg)
			end)
			if success then
				boundCount = boundCount + 1
			else
				warn("[UIAnim] Ripple animation failed:", err)
			end
		end
		
		if boundCount > 0 then
			animsRegistered = true
			print("[UIAnim] bound", boundCount, "animations (hover/press/ripple) to", btn.Name)
		else
			warn("[UIAnim] No animations bound to", btn.Name)
		end

		-- ZIndex fix for ripple (heuristic)
		if Anim_Ripple then
			task.delay(0.05, function()
				if not btn or not btn.Parent then return end
				for _, d in ipairs(btn:GetDescendants()) do
					if d:IsA("Frame") and d.ZIndex < 25 then
						d.ZIndex = 25
						for _, dd in ipairs(d:GetDescendants()) do
							if dd:IsA("GuiObject") then dd.ZIndex = 25 end
						end
					end
				end
			end)
		end
	end
	
	if not animsRegistered then
		applyFallbackAnimations(btn)
	end
end

function ChoicePopup:StartSyncedTimer(endTime, onResponse, timerId)
	local function update()
		if self._isClosing or self._currentTimerId ~= timerId then return end
		
		local remaining = math.ceil(endTime - workspace:GetServerTimeNow())
		if remaining < 0 then remaining = 0 end
		
		self._countdown:Update(remaining)
		
		if remaining <= 0 then
			self:Hide()
			if onResponse then onResponse(nil) end
			return
		end
		
		task.delay(0.2, update)
	end
	update()
end

function ChoicePopup:StartTimer(seconds, onResponse, timerId)
	local endTime = os.clock() + seconds
	local function update()
		if self._isClosing or self._currentTimerId ~= timerId then return end
		
		local remaining = math.ceil(endTime - os.clock())
		if remaining < 0 then remaining = 0 end
		
		self._countdown:Update(remaining)
		
		if remaining <= 0 then
			self:Hide()
			if onResponse then onResponse(nil) end
			return
		end
		
		task.delay(0.2, update)
	end
	update()
end

function ChoicePopup:AnimateIn()
	local info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	
	self._overlay.BackgroundTransparency = 1
	local overlayTween = TweenService:Create(self._overlay, info, { BackgroundTransparency = 0.55 })
	overlayTween:Play()
	
	self._frame.Size = UDim2.fromOffset(360, 225)
	self._frame.BackgroundTransparency = 1
	
	local frameTween = TweenService:Create(self._frame, info, {
		Size = self._originalSize,
		BackgroundTransparency = 0 -- BasePanel handles color, this is container
	})
	frameTween:Play()
end

function ChoicePopup:ShowWaitingState(selectedOption)
	if self._isWaiting or self._isClosing then return end
	self._isWaiting = true
	
	print("[UI] ShowWaitingState called at", os.clock())
	
	-- Disable all buttons
	for _, child in ipairs(self._optionsContainer:GetChildren()) do
		if child:IsA("Frame") then
			local btn = child:FindFirstChildOfClass("ImageButton")
			if btn then
				btn.Active = false
				btn.AutoButtonColor = false
				-- Dim the button
				btn.BackgroundTransparency = 0.5
			end
		end
	end
	
	-- Show waiting message
	if self._statusLabel then
		self._statusLabel.Text = "Waiting on opponent..."
		self._statusLabel.Visible = true
	end
	
	-- Keep countdown visible (always visible, even after click)
	-- Countdown continues updating until round resolves
	if self._countdown then
		-- Ensure countdown stays visible
		self._countdown:SetVisible(true)
	end
end

function ChoicePopup:Hide()
	if self._isClosing then return end
	print("[UI] Hide() called at", os.clock())
	self._isClosing = true
	self._isWaiting = false
	self._currentTimerId += 1 -- Invalidates timers
	
	-- Remove blur when popup closes
	removePopupEffects()
	
	-- Cleanup background only when round ends (not between stages)
	if self._bgCleanup then
		self._bgCleanup()
		self._bgCleanup = nil
	end
	
	-- Disconnect inputs
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
	
	-- Close immediately (no animation delay on round resolve)
	self._overlay.Visible = false
	print("[UI] overlay.Visible set to false at", os.clock())
end

function ChoicePopup:Destroy()
	self:Hide()
	if self._bgCleanup then self._bgCleanup() end
	if self._overlay then self._overlay:Destroy() end
	self._overlay = nil
end

return ChoicePopup