local EliminationWinRuleComponent = {}
EliminationWinRuleComponent.__index = EliminationWinRuleComponent
local ModeRules = require(script.Parent.Parent.Parent.Common.ModeRules)

local COMPONENT_NAME = "EliminationWinRule"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end
local function getTeams(ctx)
	return ModeRules.getRoleTeams(ctx)
end

local function emitRoundEnd(ctx, payload)
	ctx.Events:Emit("RoundEndRequested", payload)
end

local function isObjectiveActive(ctx)
	if not ctx then
		return false
	end

	local bombState = ctx.state and ctx.state.bombState
	if type(bombState) == "table" then
		local hasBombState = bombState.planted ~= nil or bombState.defused ~= nil or bombState.detonated ~= nil
		if hasBombState then
			local planted = bombState.planted == true
			local resolved = bombState.defused == true or bombState.detonated == true
			return planted and not resolved
		end
	end

	local objectiveState = ctx.state and ctx.state.objective
	if type(objectiveState) == "table" then
		local hasObjectiveState = objectiveState.active ~= nil or objectiveState.completed ~= nil
		if hasObjectiveState then
			return objectiveState.active == true and objectiveState.completed ~= true
		end
	end

	local gameObjects = ctx.gameObjects
	if gameObjects and gameObjects:FindFirstChild("UHEPlanted") and gameObjects.UHEPlanted.Value == true then
		return true
	end

	return false
end

function EliminationWinRuleComponent.new(ctx)
	local self = setmetatable({}, EliminationWinRuleComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function EliminationWinRuleComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._connections = {}
	self._roundLive = false

	table.insert(self._connections, ctx.Events:On("RoundPhaseChanged", function(phase)
		self._roundLive = (phase == "Live")
	end, eventLabel("RoundPhaseChanged")))

	table.insert(self._connections, ctx.Events:On("RoundEnded", function()
		self._roundLive = false
	end, eventLabel("RoundEnded")))

	table.insert(self._connections, ctx.Events:On("RosterUpdated", function(roster)
		if not self._roundLive then
			return
		end
		local attackersTeam, defendersTeam = getTeams(ctx)
		if roster.aliveAttackers and #roster.aliveAttackers <= 0 then
			if isObjectiveActive(ctx) then
				return
			end
			emitRoundEnd(ctx, {
				winner = defendersTeam,
				reason = "Attackers eliminated",
				method = "elimination",
			})
			return
		end
		if roster.aliveDefenders and #roster.aliveDefenders <= 0 then
			emitRoundEnd(ctx, {
				winner = attackersTeam,
				reason = "Defenders eliminated",
				method = "elimination",
			})
		end
	end, eventLabel("RosterUpdated")))
end

function EliminationWinRuleComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return EliminationWinRuleComponent
