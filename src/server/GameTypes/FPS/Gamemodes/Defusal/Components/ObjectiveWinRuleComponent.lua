local ObjectiveWinRuleComponent = {}
ObjectiveWinRuleComponent.__index = ObjectiveWinRuleComponent
local ModeRules = require(script.Parent.Parent.Parent.Common.ModeRules)

local COMPONENT_NAME = "ObjectiveWinRule"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function getTeams(ctx)
	return ModeRules.getRoleTeams(ctx)
end

local function emitRoundEnd(ctx, payload)
	ctx.Events:Emit("RoundEndRequested", payload)
end

function ObjectiveWinRuleComponent.new(ctx)
	local self = setmetatable({}, ObjectiveWinRuleComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function ObjectiveWinRuleComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._connections = {}

	table.insert(self._connections, ctx.Events:On("ObjectiveStateChanged", function(data)
		if not data or not data.stateKey then
			return
		end
		local rules = (ctx.config.Objective and ctx.config.Objective.WinRulesByState) or {
			detonated = { winnerRole = "attackers", reason = "Bomb detonated" },
			defused = { winnerRole = "defenders", reason = "Bomb defused" },
		}
		local rule = rules[data.stateKey]
		if not rule then
			return
		end

		local attackersTeam, defendersTeam = getTeams(ctx)
		local winner = nil
		if rule.winnerRole == "attackers" then
			winner = attackersTeam
		elseif rule.winnerRole == "defenders" then
			winner = defendersTeam
		elseif rule.winnerTeam then
			winner = rule.winnerTeam
		end
		if not winner then
			return
		end

		emitRoundEnd(ctx, {
			winner = winner,
			reason = rule.reason or ("Objective " .. data.stateKey),
			method = rule.method or "objective",
			playerId = data.playerId,
		})
	end, eventLabel("ObjectiveStateChanged")))
end

function ObjectiveWinRuleComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return ObjectiveWinRuleComponent
