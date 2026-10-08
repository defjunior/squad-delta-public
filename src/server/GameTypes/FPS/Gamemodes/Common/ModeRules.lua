local ModeRules = {}

-- Omitted: authored default team-role assignment.
local DEFAULT_ROLES = {}

local function readRoleConfig(config)
	local roleConfig = config and config.TeamRoles
	if type(roleConfig) ~= "table" then
		return DEFAULT_ROLES
	end
	return {
		attackers = roleConfig.attackers or config.AttackerTeam or DEFAULT_ROLES.attackers,
		defenders = roleConfig.defenders or config.DefenderTeam or DEFAULT_ROLES.defenders,
	}
end

function ModeRules.getRoleTeams(ctx)
	local config = ctx and ctx.config or {}
	local roleConfig = readRoleConfig(config)
	local gameObjects = ctx and ctx.gameObjects

	local attackers = gameObjects and gameObjects.ATeam and gameObjects.ATeam.Value or roleConfig.attackers
	local defenders = gameObjects and gameObjects.DTeam and gameObjects.DTeam.Value or roleConfig.defenders
	return attackers, defenders
end

function ModeRules.getTeamByRole(ctx, roleName)
	local attackers, defenders = ModeRules.getRoleTeams(ctx)
	if roleName == "attackers" then
		return attackers
	end
	if roleName == "defenders" then
		return defenders
	end
	return nil
end

function ModeRules.getRoleForTeam(ctx, teamName)
	if not teamName then
		return nil
	end
	local attackers, defenders = ModeRules.getRoleTeams(ctx)
	if teamName == attackers then
		return "attackers"
	end
	if teamName == defenders then
		return "defenders"
	end
	return nil
end

function ModeRules.getWinCounterName(config, teamName)
	if not teamName then
		return nil
	end
	local map = config and config.TeamWinCounters
	if type(map) == "table" and map[teamName] then
		return map[teamName]
	end
	return teamName .. "Wins"
end

return ModeRules
