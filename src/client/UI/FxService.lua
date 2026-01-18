local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local FxService = {}

function FxService.Play(soundName)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return end
	
	local fxFolder = assets:FindFirstChild("FX")
	if not fxFolder then return end
	
	local template = fxFolder:FindFirstChild(soundName)
	if not template then
		warn("[FxService] Missing sound: " .. tostring(soundName))
		return
	end
	
	local sound = template:Clone()
	sound.Parent = SoundService -- Global playback
	
	if sound.Volume <= 0 then sound.Volume = 0.5 end
	
	sound:Play()
	Debris:AddItem(sound, sound.TimeLength + 1)
end

return FxService
