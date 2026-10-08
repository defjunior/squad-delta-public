local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Modules.Logger)
local ModeRules = require(script.Parent.Parent.Parent.Common.ModeRules)

local TimerWinRuleComponent = {}
TimerWinRuleComponent.__index = TimerWinRuleComponent

local COMPONENT_NAME = "TimerWinRule"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function getDefenders(ctx)
	return ModeRules.getTeamByRole(ctx, "defenders")
end

local function emitRoundEnd(ctx, payload)
	Logger.Info("[TimerWinRuleComponent]", string.format("Round end emitted: %s", payload.reason or "unknown"))
	ctx.Events:Emit("RoundEndRequested", payload)
end

function TimerWinRuleComponent.new(ctx)
	local self = setmetatable({}, TimerWinRuleComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function TimerWinRuleComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._connections = {}
	self._objectiveBlockingTimer = false

	table.insert(self._connections, ctx.Events:On("ObjectiveStateChanged", function(data)
		local timerBlockStates = (self._ctx.config.Objective and self._ctx.config.Objective.TimerBlockStates) or {
			planted = true,
			defused = false,
			detonated = false,
		}
		if not data or not data.stateKey then
			return
		end
		local setting = timerBlockStates[data.stateKey]
		if setting ~= nil then
			self._objectiveBlockingTimer = setting == true
		end
	end, eventLabel("ObjectiveStateChanged")))

	table.insert(self._connections, ctx.Events:On("RoundReset", function()
		self._objectiveBlockingTimer = false
	end, eventLabel("RoundReset")))

	table.insert(self._connections, ctx.Events:On("RoundTimerTick", function(data)
		--Logger.Info("[TimerWinRuleComponent]", string.format("Timer tick: phase=%s remaining=%s", data.phase, tostring(data.timeRemaining)))
		if data.phase ~= "Live" then
			return
		end
		if data.timeRemaining and data.timeRemaining <= 0 then
			if self._objectiveBlockingTimer then
				return
			end
			emitRoundEnd(ctx, {
				winner = getDefenders(ctx),
				reason = "Timer expired",
				method = "timer",
			})
		end
	end, eventLabel("RoundTimerTick")))
end

function TimerWinRuleComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return TimerWinRuleComponent
