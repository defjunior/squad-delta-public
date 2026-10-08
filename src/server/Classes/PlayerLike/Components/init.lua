local Registry = require(script.Registry)

-- Neutral components
local MovementComponent = require(script.neutral.MovementComponent)
Registry:Register("MovementComponent", MovementComponent)

local TeamComponent = require(script.neutral.TeamComponent)
Registry:Register("TeamComponent", TeamComponent)

local StatusComponent = require(script.neutral.StatusComponent)
Registry:Register("StatusComponent", StatusComponent)

local ProgressionComponent = require(script.neutral.ProgressionComponent)
Registry:Register("ProgressionComponent", ProgressionComponent)

-- FPS-specific components
local FPSMovementComponent = require(script.fps.MovementComponent)
Registry:Register("FPSMovementComponent", FPSMovementComponent)

local FPSTeamComponent = require(script.fps.TeamComponent)
Registry:Register("FPSTeamComponent", FPSTeamComponent)

local FPSStatusComponent = require(script.fps.StatusComponent)
Registry:Register("FPSStatusComponent", FPSStatusComponent)

local FPSProgressionComponent = require(script.fps.ProgressionComponent)
Registry:Register("FPSProgressionComponent", FPSProgressionComponent)

local FPSAbilityComponent = require(script.fps.AbilityComponent)
Registry:Register("FPSAbilityComponent", FPSAbilityComponent)

local FPSDamageComponent = require(script.fps.DamageComponent)
Registry:Register("FPSDamageComponent", FPSDamageComponent)

local FPSDeathComponent = require(script.fps.DeathComponent)
Registry:Register("FPSDeathComponent", FPSDeathComponent)

local FPSEconomyComponent = require(script.fps.EconomyComponent)
Registry:Register("FPSEconomyComponent", FPSEconomyComponent)

local FPSLoadoutComponent = require(script.fps.LoadoutComponent)
Registry:Register("FPSLoadoutComponent", FPSLoadoutComponent)

local FPSRoundComponent = require(script.fps.RoundComponent)
Registry:Register("FPSRoundComponent", FPSRoundComponent)

return Registry
