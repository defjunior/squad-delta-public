local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModeRules = require(script.Parent.Parent.Parent.Common.ModeRules)

local BombObjectiveComponent = {}
BombObjectiveComponent.__index = BombObjectiveComponent

local COMPONENT_NAME = "BombObjective"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local HUD_MESSAGE_COLOR = Color3.new(1, 0.278431, 0.215686)

local function setReplicatedDefusedState(gameObjects, value)
	if not gameObjects then
		return
	end
	local defused = gameObjects:FindFirstChild("UHEDefused")
	if not defused then
		defused = Instance.new("BoolValue")
		defused.Name = "UHEDefused"
		defused.Parent = gameObjects
	end
	defused.Value = value == true
	gameObjects:SetAttribute("BombDefused", value == true)
end

local function fireHudEvent(ctx, key, ...)
	if ctx and ctx.events then
		ctx.events:FireAll("Server/HUDEvent", key, ...)
	end
end

local function fireShowWin(ctx, title, message, duration)
	if ctx and ctx.events then
		ctx.events:FireAll("Server/ShowWin", title, message, duration)
	end
end

local function firePersonalMessage(ctx, text, color)
	if not ctx or not ctx.events then
		return
	end
	ctx.events:FireAll("Server/PersonalSystemMessage", text, color or HUD_MESSAGE_COLOR)
end

local function isNearSite(ctx, gp, maxDistance)
	if not gp or not gp.CharacterObject then
		return false
	end
	local hrp = gp.CharacterObject:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local map = _G.ChosenMap
	if not map then
		return true -- allow when map missing to avoid hard-blocking
	end
	local zones = map:FindFirstChild("Zones")
	if not zones then
		return true
	end

	local radius = maxDistance or 30
	local zoneNameContains = (ctx and ctx.config and ctx.config.Map and ctx.config.Map.ObjectiveZoneNameContains) or "Site"
	for _, zone in ipairs(zones:GetChildren()) do
		if zone:IsA("BasePart") and (zoneNameContains == "" or string.find(zone.Name, zoneNameContains)) then
			local localPos = zone.CFrame:PointToObjectSpace(hrp.Position)
			local halfSize = zone.Size / 2
			local clamped = Vector3.new(
				math.clamp(localPos.X, -halfSize.X, halfSize.X),
				math.clamp(localPos.Y, -halfSize.Y, halfSize.Y),
				math.clamp(localPos.Z, -halfSize.Z, halfSize.Z)
			)
			local closest = zone.CFrame:PointToWorldSpace(clamped)
			local dist = (hrp.Position - closest).Magnitude
			if dist <= radius then
				return true
			end
		end
	end
	return false
end

local function getTeams(ctx)
	return ModeRules.getRoleTeams(ctx)
end

local function toPhaseSet(configured)
	if type(configured) ~= "table" then
		return nil
	end
	local set = {}
	local hasValue = false
	for key, value in pairs(configured) do
		if type(key) == "number" then
			if type(value) == "string" and value ~= "" then
				set[string.lower(value)] = true
				hasValue = true
			end
		elseif value == true and type(key) == "string" and key ~= "" then
			set[string.lower(key)] = true
			hasValue = true
		end
	end
	return hasValue and set or nil
end

local function isPlantPhaseAllowed(ctx)
	local currentPhase = ctx and ctx.state and ctx.state.phase
	if type(currentPhase) ~= "string" or currentPhase == "" then
		return true
	end
	local configSet = toPhaseSet(ctx and ctx.config and ctx.config.Objective and ctx.config.Objective.PlantablePhases)
	if not configSet then
		return true
	end
	return configSet[string.lower(currentPhase)] == true
end

local function copyState(source)
	return {
		planted = source.planted,
		defused = source.defused,
		detonated = source.detonated,
		planter = source.planter,
		defuser = source.defuser,
	}
end

local function isOnTeam(gp, teamName)
	return gp and gp.Team and gp.Team.Name == teamName
end

function BombObjectiveComponent.new(ctx)
	local self = setmetatable({}, BombObjectiveComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function BombObjectiveComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = ctx.config or {}
	self._connections = {}
	self._eventConnections = {}

	self:Reset()

	table.insert(self._connections, ctx.Events:On("RoundReset", function()
		self:Reset()
	end, eventLabel("RoundReset")))

	table.insert(self._connections, ctx.Events:On("BombPlantAttempt", function(requestCtx)
		self:_handlePlantAttempt(requestCtx)
	end, eventLabel("BombPlantAttempt")))

	table.insert(self._connections, ctx.Events:On("BombDefuseAttempt", function(requestCtx)
		self:_handleDefuseAttempt(requestCtx)
	end, eventLabel("BombDefuseAttempt")))

	self:_bindObjectiveEvents()
end

function BombObjectiveComponent:_bindObjectiveEvents()
	local eventsFolder = ServerStorage:FindFirstChild("Events")
	if not eventsFolder then
		warn("[BombObjectiveComponent] Missing ServerStorage.Events; skipping objective bindings")
		return
	end

	local function connect(bindableEvent)
		if bindableEvent and bindableEvent:IsA("BindableEvent") then
			local conn = bindableEvent.Event:Connect(function(playerId)
				self:_handleExternalEvent(bindableEvent.Name, playerId)
			end)
			table.insert(self._eventConnections, conn)
		end
	end

	connect(eventsFolder:FindFirstChild("BombPlanted"))
	connect(eventsFolder:FindFirstChild("BombDefused"))
	connect(eventsFolder:FindFirstChild("BombDetonated"))
end

function BombObjectiveComponent:_handleExternalEvent(name, playerId)
	if name == "BombPlanted" then
		self:MarkPlanted(playerId)
	elseif name == "BombDefused" then
		self:MarkDefused(playerId)
	elseif name == "BombDetonated" then
		self:MarkDetonated()
	end
end

function BombObjectiveComponent:_updateState()
	self._ctx.state.bombState = copyState(self._state)
end

function BombObjectiveComponent:Reset()
	self._state = {
		planted = false,
		defused = false,
		detonated = false,
		planter = nil,
		defuser = nil,
	}
	local gameObjects = self._ctx.gameObjects
	if gameObjects and gameObjects.UHEPlanted then
		gameObjects.UHEPlanted.Value = false
	end
	setReplicatedDefusedState(gameObjects, false)

	fireHudEvent(self._ctx, "BombHide")
	self:_updateState()
	self._ctx.Events:Emit("BombStateReset", self._state)
end

function BombObjectiveComponent:_emitObjective(eventName, playerId)
	self:_updateState()
	self._ctx.Events:Emit("ObjectiveEvent", {
		type = eventName,
		playerId = playerId,
		state = self._ctx.state.bombState,
	})
	self._ctx.Events:Emit(eventName, self._ctx.state.bombState, playerId)
	if eventName == "BombPlanted" then
		fireHudEvent(self._ctx, "BombPlanted")
		fireShowWin(self._ctx, "ALERT", "Something has been armed.", 5)
		firePersonalMessage(self._ctx, "[SYSTEM] Something has been armed.")
	elseif eventName == "BombDefused" then
		fireHudEvent(self._ctx, "BombDefused")
		fireShowWin(self._ctx, "ALERT", "Bomb defused!", 5)
		firePersonalMessage(self._ctx, "[SYSTEM] The bomb has been defused.")
	elseif eventName == "BombDetonated" then
		fireHudEvent(self._ctx, "BombDetonated")
		fireShowWin(self._ctx, "ALERT", "Bomb detonated!", 5)
		firePersonalMessage(self._ctx, "[SYSTEM] The bomb has detonated.", Color3.new(1, 0, 0))
	end
end

function BombObjectiveComponent:MarkPlanted(playerId)
	if self._state.planted or self._state.detonated then
		return
	end
	self._state.planted = true
	self._state.planter = playerId

	local gameObjects = ReplicatedStorage:FindFirstChild("GameObjects")
	if gameObjects and gameObjects:FindFirstChild("UHEPlanted") then
		gameObjects.UHEPlanted.Value = true
	end
	setReplicatedDefusedState(gameObjects, false)

	self:_emitObjective("BombPlanted", playerId)
end

function BombObjectiveComponent:MarkDefused(playerId)
	if self._state.defused or self._state.detonated then
		return
	end
	self._state.defused = true
	self._state.defuser = playerId
	setReplicatedDefusedState(self._ctx.gameObjects or ReplicatedStorage:FindFirstChild("GameObjects"), true)
	self:_emitObjective("BombDefused", playerId)
end

function BombObjectiveComponent:MarkDetonated()
	if self._state.detonated then
		return
	end
	self._state.detonated = true
	setReplicatedDefusedState(self._ctx.gameObjects or ReplicatedStorage:FindFirstChild("GameObjects"), false)
	self:_emitObjective("BombDetonated")
end

function BombObjectiveComponent:_handlePlantAttempt(requestCtx)
	local gp = requestCtx and requestCtx.gp
	if not gp then
		return
	end
	if not isPlantPhaseAllowed(self._ctx) then
		return
	end
	local attackersTeam = getTeams(self._ctx)
	if not isOnTeam(gp, attackersTeam) then
		return
	end
	if not isNearSite(self._ctx, gp) then
		return
	end
	self:MarkPlanted(requestCtx.userId)
end

function BombObjectiveComponent:_handleDefuseAttempt(requestCtx)
	local gp = requestCtx and requestCtx.gp
	if not gp or not self._state.planted or self._state.defused or self._state.detonated then
		return
	end
	local _, defendersTeam = getTeams(self._ctx)
	if not isOnTeam(gp, defendersTeam) then
		return
	end
	if not isNearSite(self._ctx, gp) then
		return
	end
	self:MarkDefused(requestCtx.userId)
end

function BombObjectiveComponent:GetState()
	return copyState(self._state)
end

function BombObjectiveComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	for _, conn in ipairs(self._eventConnections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._eventConnections = nil
	self._mounted = false
end

return BombObjectiveComponent
