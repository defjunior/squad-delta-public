local MovementComponent = require(script.Parent.Parent.neutral.MovementComponent)

local FPSMovementComponent = MovementComponent:Extend()
FPSMovementComponent.__index = FPSMovementComponent
FPSMovementComponent.Name = "FPSMovementComponent"

return FPSMovementComponent
