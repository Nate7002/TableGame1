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
	
	-- Step E: Transient flag to prevent flicker during match start transition
	self._isTransitioningToMatch = false
	
	return self
end

-- State Setters
function SeatUI:SetSeated(seated)
	self._isSeated = seated
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
	
	print(string.format("[SeatUI] UpdateVisibility seated=%s match=%s choice=%s -> visible=%s", 
		tostring(self._isSeated), tostring(self._matchActive), tostring(self._choiceUIActive), tostring(shouldShow)))
	
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
	frame.Size = UDim2.new(0, 300, 0, 60)
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
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = frame
	
	-- Invite Friend Button
	local inviteBtn = self:_createButton("Invite Friend", function()
		self:_handleInviteFriend()
	end)
	inviteBtn.Parent = frame
	
	-- Leave Seat Button
	local leaveBtn = self:_createButton("Leave Seat", function()
		self:_handleLeaveSeat()
	end)
	leaveBtn.Parent = frame
end

function SeatUI:_createButton(text, callback)
	local btn = Instance.new("TextButton")
	btn.BackgroundColor3 = Theme.Colors.Secondary
	btn.BorderSizePixel = 0
	btn.Size = UDim2.new(0, 130, 0, 40)
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
	
	-- Hover effect
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Theme.Colors.Accent
	end)
	
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = Theme.Colors.Secondary
	end)
	
	-- Click handler
	btn.Activated:Connect(function()
		if callback then
			callback()
		end
	end)
	
	return btn
end

function SeatUI:_handleInviteFriend()
	print("[SeatUI] Invite Friend clicked")
	
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
	print("[SeatUI] Leave Seat clicked")
	
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
