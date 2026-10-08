local TeamComponent = require(script.Parent.Parent.neutral.TeamComponent)

local FPSTeamComponent = TeamComponent:Extend()
FPSTeamComponent.__index = FPSTeamComponent
FPSTeamComponent.Name = "FPSTeamComponent"

return FPSTeamComponent
