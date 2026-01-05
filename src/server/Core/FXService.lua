local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local FXService = {}

-- Constants
local FX_FOLDER_PATH = "Assets/FX"
local SOUND_LIFETIME = 5
local CONFETTI_LIFETIME = 3

-- Private Helpers
local function getFXFolder()
	local folder = ReplicatedStorage
	for _, part in ipairs(string.split(FX_FOLDER_PATH, "/")) do
		folder = folder:FindFirstChild(part)
		if not folder then return nil end
	end
	return folder
end

local function playSound(name, target)
	if not target then return end
	local folder = getFXFolder()
	if not folder then return end
	
	local soundTemplate = folder:FindFirstChild(name)
	if soundTemplate and soundTemplate:IsA("Sound") then
		local sound = soundTemplate:Clone()
		sound.Parent = target
		sound:Play()
		Debris:AddItem(sound, sound.TimeLength > 0 and sound.TimeLength + 1 or SOUND_LIFETIME)
	else
		warn("[FXService] Sound not found: " .. name)
	end
end

-- Public API
function FXService.PlayWin(player)
	if player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		playSound("WinSound", hrp)
	end
end

function FXService.PlayLose(player)
	if player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		playSound("LoseSound", hrp)
	end
end

function FXService.PlayConfetti(player)
	if not (player and player.Character) then return end
	
	local folder = getFXFolder()
	if not folder then return end
	
	local pack = folder:FindFirstChild("ConfettiPack")
	if not pack then
		warn("[FXService] ConfettiPack not found")
		return
	end
	
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	-- Clone all contents of the pack (Attachment + Emitters)
	for _, child in ipairs(pack:GetChildren()) do
		local clone = child:Clone()
		clone.Parent = hrp
		
		if clone:IsA("ParticleEmitter") then
			clone:Emit(clone:GetAttribute("EmitCount") or 20) -- Default to 20 if no attribute
			Debris:AddItem(clone, CONFETTI_LIFETIME)
		elseif clone:IsA("Attachment") then
			-- If emitters are inside attachment
			for _, subChild in ipairs(clone:GetChildren()) do
				if subChild:IsA("ParticleEmitter") then
					subChild:Emit(subChild:GetAttribute("EmitCount") or 20)
				end
			end
			Debris:AddItem(clone, CONFETTI_LIFETIME)
		end
	end
end

-- Hooks for later
function FXService.PlayDoubleDown(source) playSound("DoubleDownSound", source) end
function FXService.PlayRareDrop(source) playSound("RareDropSound", source) end
function FXService.PlayJackpot(source) playSound("JackpotSound", source) end

return FXService

