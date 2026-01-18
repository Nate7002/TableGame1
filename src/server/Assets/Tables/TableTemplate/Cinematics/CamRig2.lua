local model = Instance.new("Model")
model.Name = "CamRig2"
local root = Instance.new("Part", model)
root.Name = "Root"
local camera = Instance.new("Part", model)
camera.Name = "Camera"
local animController = Instance.new("AnimationController", model)
local animator = Instance.new("Animator", animController)
return model
