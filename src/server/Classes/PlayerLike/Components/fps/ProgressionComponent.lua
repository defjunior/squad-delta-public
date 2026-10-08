local ProgressionComponent = require(script.Parent.Parent.neutral.ProgressionComponent)

local FPSProgressionComponent = ProgressionComponent:Extend()
FPSProgressionComponent.__index = FPSProgressionComponent
FPSProgressionComponent.Name = "FPSProgressionComponent"

return FPSProgressionComponent
