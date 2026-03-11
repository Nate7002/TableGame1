-- UX FIX B: Seated UI (Invite Friend + Leave Seat buttons)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.Theme)
local Toast = require(script.Parent.Toast)

local SeatUI = {}
SeatUI.__index = SeatUI

-- Constants
local FAST_HIDE_DURATION = 0.12 -- Step D: Fast hide duration
local SHIELD_HOVER_COLOR = Color3.fromRGB(80, 140, 255)
local SHIELD_BUY_IDLE_COLOR = Color3.fromRGB(60, 175, 105)
local SHIELD_BUY_HOVER_COLOR = Color3.fromRGB(80, 200, 120)

function SeatUI.new(parentGui)
	local self = setmetatable({}, SeatUI)
	self._parent = parentGui
	self._frame = nil
	self._visible = false
	self._toast = Toast.new(parentGui)
	
	-- State flags
	self._isSeated = false
	self._matchActive = false
	self._choiceUIActive = false
	self._shieldArmedPending = false
	self._shieldArmed = false
	self._shieldCount = 0
	self._shieldMax = 0
	self._shieldHovering = false
	self._lastShieldRenderKey = nil
	
	-- Step E: Transient flag to prevent flicker during match start transition
	self._isTransitioningToMatch = false

	self._shieldBtn = nil
	self._shieldCountLabel = nil

	return self
end

-- State Setters
function SeatUI:SetSeated(seated)
	self._isSeated = seated

	if not seated then
		self._shieldHovering = false
		self._shieldArmedPending = false
		self:_applyShieldButtonState()
	end

	self:_updateVisibility()
end

function SeatUI:SetMatchActive(active)
	-- Step E: Ignore SetMatchActive(false) if we are in the middle of a fast ease-out to match
	if not active and self._isTransitioningToMatch then
		return
	end
	
	self._matchActive = active
	self:_updateVisibility()
end

function SeatUI:SetChoiceActive(active)
	self._choiceUIActive = active
	self:_updateVisibility()
end

function SeatUI:_updateVisibility()
	-- Show if seated AND not in match AND not in choice UI
	local shouldShow = self._isSeated and not self._matchActive and not self._choiceUIActive
	
	if shouldShow then
		self:Show()
	else
		self:Hide()
	end
end

function SeatUI:Show()
	if self._visible then return end
	self._visible = true
	
	-- Create UI if not exists
	if not self._frame then
		self:_createUI()
	end
	
	-- Animate in
	self._frame.Visible = true
	self._frame.Position = UDim2.new(0.5, 0, 1, 10)
	
	local tween = TweenService:Create(self._frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.85, 0)
	})
	tween:Play()
end

function SeatUI:Hide()
	if not self._visible then return end
	self._visible = false
	
	if not self._frame then return end
	
	-- Animate out
	local tween = TweenService:Create(self._frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 1, 10)
	})
	tween:Play()
	tween.Completed:Connect(function()
		if self._frame and not self._visible then
			self._frame.Visible = false
		end
	end)
end

-- Step B: Implement EaseOutFast
function SeatUI:EaseOutFast()
	if not self._visible then return end
	self._visible = false
	
	-- Step E: Set transient flag
	self._isTransitioningToMatch = true
	task.delay(0.2, function()
		self._isTransitioningToMatch = false
	end)
	
	if not self._frame then return end
	
	-- Fast animate out
	local tween = TweenService:Create(self._frame, TweenInfo.new(FAST_HIDE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 1, 10)
	})
	tween:Play()
	tween.Completed:Connect(function()
		if self._frame and not self._visible then
			self._frame.Visible = false
		end
	end)
end

function SeatUI:_createUI()
	-- Container Frame
	local frame = Instance.new("Frame")
	frame.Name = "SeatUI"
	frame.BackgroundColor3 = Theme.Colors.Primary
	frame.BorderSizePixel = 0
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.new(0, 0, 0, 60)
	frame.Position = UDim2.new(0.5, 0, 1, 10)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Visible = false
	frame.ZIndex = 50 -- INCREASED: Ensure it's above other UI (like countdown toast)
	frame.Parent = self._parent
	self._frame = frame
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Theme.Sizes.CornerRadius
	corner.Parent = frame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.TextDim
	stroke.Transparency = 0.8
	stroke.Thickness = 1
	stroke.Parent = frame
	
	-- Horizontal layout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame
	
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = frame
	
	-- Invite Friend Button
	local inviteBtn = self:_createButton("Invite Friend", function()
		self:_handleInviteFriend()
	end)
	inviteBtn.Parent = frame

	-- Use Shield Button
	self._shieldBtn = self:_createButton("Use Shield", function()
		self:_handleUseShield()
	end, {
		disableHoverColors = true
	})
	self._shieldBtn.Parent = frame
	self._shieldBtn.MouseEnter:Connect(function()
		self._shieldHovering = true
		self:_applyShieldButtonState()
	end)
	self._shieldBtn.MouseLeave:Connect(function()
		self._shieldHovering = false
		self:_applyShieldButtonState()
	end)

	local shieldCountLabel = Instance.new("TextLabel")
	shieldCountLabel.Name = "ShieldCountLabel"
	shieldCountLabel.BackgroundTransparency = 1
	shieldCountLabel.Size = UDim2.new(0, 48, 0, 12)
	shieldCountLabel.AnchorPoint = Vector2.new(1, 1)
	shieldCountLabel.Position = UDim2.new(1, -6, 1, -4)
	shieldCountLabel.Font = Theme.Font.Body
	shieldCountLabel.Text = "0/0"
	shieldCountLabel.TextColor3 = Theme.Colors.TextDim
	shieldCountLabel.TextSize = Theme.Sizes.TextSmall
	shieldCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	shieldCountLabel.ZIndex = 61
	shieldCountLabel.Parent = self._shieldBtn
	self._shieldCountLabel = shieldCountLabel

	self:_applyShieldButtonState()
	
	-- Leave Seat Button
	local leaveBtn = self:_createButton("Leave Seat", function()
		self:_handleLeaveSeat()
	end)
	leaveBtn.Parent = frame
end

function SeatUI:_createButton(text, callback, options)
	options = options or {}

	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = Theme.Colors.Secondary
	btn.BorderSizePixel = 0
	btn.Size = UDim2.new(0, 120, 0, 40)
	btn.Font = Theme.Font.Body
	btn.Text = text
	btn.TextColor3 = Theme.Colors.Text
	btn.TextSize = Theme.Sizes.TextBody
	btn.AutoButtonColor = false
	btn.ZIndex = 60 -- INCREASED
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Stroke.Color
	stroke.Transparency = Theme.Stroke.Transparency
	stroke.Thickness = Theme.Stroke.Thickness
	stroke.Parent = btn
	
	if not options.disableHoverColors then
		btn.MouseEnter:Connect(function()
			btn.BackgroundColor3 = Theme.Colors.Accent
		end)

		btn.MouseLeave:Connect(function()
			btn.BackgroundColor3 = Theme.Colors.Secondary
		end)
	end
	
	-- Click handler
	btn.Activated:Connect(function()
		if callback then
			callback()
		end
	end)
	
	return btn
end

function SeatUI:_applyShieldButtonState()
	if not self._shieldBtn then return end

	local shieldMax = math.max(0, tonumber(self._shieldMax) or 0)
	local countText = string.format("%d/%d", self._shieldCount, shieldMax)
	if self._shieldCountLabel then
		self._shieldCountLabel.Text = countText
	end

	if self._shieldArmed then
		self._shieldBtn.Text = "Shield Armed"
		self._shieldBtn.Active = false
		self._shieldBtn.AutoButtonColor = false
		self._shieldBtn.BackgroundColor3 = Theme.Colors.Primary
	else
		self._shieldBtn.Text = self._shieldCount <= 0 and "Buy Shield" or "Use Shield"
		self._shieldBtn.Active = not self._shieldArmedPending
		self._shieldBtn.AutoButtonColor = false

		if self._shieldCount <= 0 then
			self._shieldBtn.BackgroundColor3 = self._shieldHovering and SHIELD_BUY_HOVER_COLOR or SHIELD_BUY_IDLE_COLOR
		elseif self._shieldHovering then
			self._shieldBtn.BackgroundColor3 = SHIELD_HOVER_COLOR
		else
			self._shieldBtn.BackgroundColor3 = Theme.Colors.Secondary
		end
	end

	self._lastShieldRenderKey = string.format("%s|%s|armed=%s|pending=%s",
		self._shieldBtn.Text,
		countText,
		tostring(self._shieldArmed),
		tostring(self._shieldArmedPending)
	)
end

function SeatUI:SetShieldState(state)
	state = state or {}
	self._shieldCount = math.max(0, tonumber(state.count) or 0)
	self._shieldMax = math.max(0, tonumber(state.max) or self._shieldMax or 0)
	self._shieldArmed = state.armed == true
	self._shieldArmedPending = state.pending == true
	self:_applyShieldButtonState()
end

function SeatUI:SetShieldCount(count)
	self:SetShieldState({
		count = count,
		max = self._shieldMax,
		armed = self._shieldArmed,
		pending = self._shieldArmedPending
	})
end

function SeatUI:SetShieldMax(max)
	self:SetShieldState({
		count = self._shieldCount,
		max = max,
		armed = self._shieldArmed,
		pending = self._shieldArmedPending
	})
end

function SeatUI:SetShieldArmed(armed)
	self:SetShieldState({
		count = self._shieldCount,
		max = self._shieldMax,
		armed = armed,
		pending = self._shieldArmedPending
	})
end

function SeatUI:SetShieldPending(pending)
	self:SetShieldState({
		count = self._shieldCount,
		max = self._shieldMax,
		armed = self._shieldArmed,
		pending = pending
	})
end

function SeatUI:_handleUseShield()
	if self._shieldArmedPending or self._shieldArmed then return end
	if self._shieldCount <= 0 then return end
	self:SetShieldPending(true)

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		self:SetShieldPending(false)
		warn("[SeatUI] Remotes folder not found")
		return
	end

	local shieldRemote = remotes:FindFirstChild("UseShield")
	if not shieldRemote then
		self:SetShieldPending(false)
		warn("[SeatUI] UseShield remote not found")
		return
	end

	shieldRemote:FireServer()
end

function SeatUI:_handleInviteFriend()
	-- Try to use SocialService (only works in published games)
	local success, err = pcall(function()
		local player = Players.LocalPlayer
		SocialService:PromptGameInvite(player)
	end)
	
	if not success then
		-- Fallback: show toast
		self._toast:Show("Invite is only available in published game.", 3)
		warn("[SeatUI] SocialService:PromptGameInvite failed:", err)
	end
end

function SeatUI:_handleLeaveSeat()
	-- Fire remote to server
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		warn("[SeatUI] Remotes folder not found")
		return
	end
	
	local leaveSeatRemote = remotes:FindFirstChild("LeaveSeat")
	if not leaveSeatRemote then
		warn("[SeatUI] LeaveSeat remote not found")
		return
	end
	
	leaveSeatRemote:FireServer()
	
	-- Hide UI immediately
	self:Hide()
end

function SeatUI:Destroy()
	self:Hide()
	if self._frame then
		self._frame:Destroy()
		self._frame = nil
	end
	if self._toast then
		self._toast:Destroy()
		self._toast = nil
	end
end

return SeatUI
