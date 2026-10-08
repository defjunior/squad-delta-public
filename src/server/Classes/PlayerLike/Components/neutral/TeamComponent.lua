local RunService = game:GetService("RunService")

local ComponentBase = require(script.Parent.Parent.Base)

local TeamComponent = ComponentBase:Extend()
TeamComponent.__index = TeamComponent
TeamComponent.Name = "TeamComponent"

local IsServer = RunService:IsServer()

function TeamComponent:SetTeam(team)
	local selfPlayer = self.player
	if not IsServer then
		warn("Attempted to run Player Class Function on client.")
		return
	end

	selfPlayer:SetValue("Team", team)
	selfPlayer.Team = team

	selfPlayer:CheckForBinds("OnTeamChange", team)
end

function TeamComponent:Bind_OnTeamChange(newTeam)
	local selfPlayer = self.player
	if selfPlayer.IsBot == false then
		selfPlayer.PlayerObject.Team = newTeam
	end
end

return TeamComponent
