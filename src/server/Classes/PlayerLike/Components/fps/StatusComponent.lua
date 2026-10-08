local StatusComponent = require(script.Parent.Parent.neutral.StatusComponent)

local FPSStatusComponent = StatusComponent:Extend()
FPSStatusComponent.__index = FPSStatusComponent
FPSStatusComponent.Name = "FPSStatusComponent"

return FPSStatusComponent
