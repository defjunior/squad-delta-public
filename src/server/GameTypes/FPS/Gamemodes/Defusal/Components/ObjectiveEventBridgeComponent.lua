local ObjectiveEventBridgeComponent = {}
ObjectiveEventBridgeComponent.__index = ObjectiveEventBridgeComponent

local COMPONENT_NAME = "ObjectiveEventBridge"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function readObjectiveConfig(ctx)
	local config = ctx and ctx.config or {}
	local objective = config.Objective or {}
	local bridge = objective.Bridge or {}
	return objective, bridge
end

local function emitRoundResetState(ctx)
	ctx.Events:Emit("ObjectiveStateChanged", {
		objectiveType = "none",
		stateKey = "reset",
		active = false,
		completed = false,
		snapshot = {},
	})
end

function ObjectiveEventBridgeComponent.new(ctx)
	local self = setmetatable({}, ObjectiveEventBridgeComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function ObjectiveEventBridgeComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._connections = {}
	self._objectiveConfig, self._bridgeConfig = readObjectiveConfig(ctx)
	self._ctx.state.objective = self._ctx.state.objective or {}

	table.insert(self._connections, ctx.Events:On("RoundReset", function()
		self._ctx.state.objective = { active = false, completed = false }
		emitRoundResetState(ctx)
	end, eventLabel("RoundReset")))

	local actionToLegacy = self._bridgeConfig.ActionToLegacyAttempt or {}
	table.insert(self._connections, ctx.Events:On("ObjectiveActionAttempt", function(payload)
		local action = payload and payload.action
		local legacyEvent = action and actionToLegacy[action] or nil
		if legacyEvent then
			ctx.Events:Emit(legacyEvent, payload)
		end
	end, eventLabel("ObjectiveActionAttempt")))

	local stateEventToKey = self._bridgeConfig.LegacyStateToStateKey or {}
	for legacyEventName, stateKey in pairs(stateEventToKey) do
		table.insert(self._connections, ctx.Events:On(legacyEventName, function(state, playerId)
			local normalized = {
				objectiveType = self._objectiveConfig.Type or "unknown",
				stateKey = stateKey,
				active = stateKey == "planted",
				completed = stateKey == "defused" or stateKey == "detonated" or stateKey == "captured",
				playerId = playerId,
				snapshot = state or {},
			}
			self._ctx.state.objective = normalized.snapshot or {}
			self._ctx.state.objective.active = normalized.active
			self._ctx.state.objective.completed = normalized.completed
			ctx.Events:Emit("ObjectiveStateChanged", normalized)
		end, eventLabel(legacyEventName)))
	end
end

function ObjectiveEventBridgeComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return ObjectiveEventBridgeComponent
