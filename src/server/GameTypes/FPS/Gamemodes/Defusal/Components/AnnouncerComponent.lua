local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ModeRules = require(script.Parent.Parent.Parent.Common.ModeRules)

local AnnouncerComponent = {}
AnnouncerComponent.__index = AnnouncerComponent

local COMPONENT_NAME = "Announcer"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local baseGuard = { gp = true, inGame = true, alive = true, character = true }

local function getTeams(ctx)
	return ModeRules.getRoleTeams(ctx)
end

local function isOnTeam(gp, teamName)
	return gp and gp.Team and gp.Team.Name == teamName
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
		return true
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

local function getEventPrefix(ctx)
	local network = ctx and ctx.config and ctx.config.Network
	return network and network.EventPrefix or "FPS/Defusal"
end

local LEGACY_TEAM_CHAT_COLOR = {
	RED = Color3.new(1, 0.396078, 0.478431),
	BLU = Color3.new(0.4, 0.580392, 1),
}

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

local function isActionAllowedInPhase(ctx, actionRule, objectiveConfig)
	local phaseName = ctx and ctx.state and ctx.state.phase
	if type(phaseName) ~= "string" or phaseName == "" then
		return true
	end

	local phaseKey = string.lower(phaseName)
	local configuredSet = toPhaseSet(actionRule and actionRule.AllowedPhases)
	if not configuredSet and actionRule and actionRule.Action == "plant" then
		configuredSet = toPhaseSet(objectiveConfig and objectiveConfig.PlantablePhases)
	end
	if not configuredSet then
		return true
	end
	return configuredSet[phaseKey] == true
end

local function getRoundAnnouncementPayload(ctx, result)
	local attackersTeam, defendersTeam = getTeams(ctx)
	local winner = tostring(result and result.winner or "Team")
	local loser = nil
	if winner == attackersTeam then
		loser = defendersTeam
	elseif winner == defendersTeam then
		loser = attackersTeam
	end

	local reasonLower = string.lower(tostring(result and result.reason or ""))
	local methodLower = string.lower(tostring(result and result.method or ""))
	local subtitle = loser and ("Squad %s has been eliminated."):format(loser) or ""
	local personalMessage = nil

	if string.find(reasonLower, "detonated", 1, true) then
		subtitle = "UHE-4 has been detonated."
		personalMessage = ("[SYSTEM] Squad %s detonated UHE-4."):format(winner)
	elseif string.find(reasonLower, "defused", 1, true) then
		subtitle = "UHE-4 has been defused."
		personalMessage = ("[SYSTEM] Squad %s defused UHE-4."):format(winner)
	elseif methodLower == "objective" and winner == defendersTeam then
		subtitle = "UHE-4 has been defused."
		personalMessage = ("[SYSTEM] Squad %s defused UHE-4."):format(winner)
	elseif methodLower == "objective" and winner == attackersTeam then
		subtitle = "UHE-4 has been detonated."
		personalMessage = ("[SYSTEM] Squad %s detonated UHE-4."):format(winner)
	elseif winner == attackersTeam and loser then
		personalMessage = ("[SYSTEM] %s has successfully eliminated %s."):format(winner, loser)
	elseif winner == defendersTeam and attackersTeam then
		personalMessage = ("[SYSTEM] Squad %s failed to detonate UHE-4."):format(attackersTeam)
	end

	return {
		title = ("%s has won."):format(winner),
		subtitle = subtitle,
		personalMessage = personalMessage,
		color = LEGACY_TEAM_CHAT_COLOR[winner] or Color3.new(1, 1, 1),
	}
end

local function fireWinAnnouncement(ctx, result)
	local payload = getRoundAnnouncementPayload(ctx, result)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and remotes.Server and remotes.Server.ShowWin then
		remotes.Server.ShowWin:FireAllClients(
			payload.title,
			payload.subtitle,
			10
		)
	end
	if remotes and remotes.Server and remotes.Server.PersonalSystemMessage and payload.personalMessage then
		remotes.Server.PersonalSystemMessage:FireAllClients(payload.personalMessage, payload.color)
	end
end

local function firePersonalMessage(data)
	if not data or not data.player or not data.message then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and remotes.Server and remotes.Server.PersonalSystemMessage then
		remotes.Server.PersonalSystemMessage:FireClient(data.player, data.message, data.color or Color3.new(1, 1, 1))
	end
end

local function buildRoundAnnouncementKey(result)
	return ("%s|%s|%s"):format(
		tostring(result and result.round or ""),
		tostring(result and result.winner or ""),
		tostring(result and result.reason or "")
	)
end

local function isMatchInstance()
	if _G.ServerRole == "MatchInstance" then
		return true
	end
	local rules = ReplicatedStorage:FindFirstChild("GameRules")
	local flag = rules and rules:FindFirstChild("IsMatchInstance")
	return flag and flag.Value == true
end

function AnnouncerComponent.new(ctx)
	local self = setmetatable({}, AnnouncerComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function AnnouncerComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._connections = {}

	self:_registerEndpoints()

	table.insert(self._connections, ctx.Events:On("MapVoteStarted", function(data)
		self:_announceMapVote(data)
	end, eventLabel("MapVoteStarted")))

	table.insert(self._connections, ctx.Events:On("RoundEnded", function(result)
		self:_announceRound(result or {})
	end, eventLabel("RoundEnded")))

	table.insert(self._connections, ctx.Events:On("PersonalMessage", function(data)
		firePersonalMessage(data)
	end, eventLabel("PersonalMessage")))

	table.insert(self._connections, ctx.Events:On("MVPDeclared", function(data)
		self:_announceMvp(data)
	end, eventLabel("MVPDeclared")))

	table.insert(self._connections, ctx.Events:On("RoundPhaseChanged", function(phase)
		self._lastPhase = phase
	end, eventLabel("RoundPhaseChanged")))

	table.insert(self._connections, ctx.Events:On("ObjectiveStateChanged", function(data)
		self:_announceObjective(data)
	end, eventLabel("ObjectiveStateChanged")))
end

function AnnouncerComponent:_announceRound(result)
	local key = buildRoundAnnouncementKey(result)
	if self._lastRoundAnnouncementKey == key then
		return
	end
	self._lastRoundAnnouncementKey = key
	fireWinAnnouncement(self._ctx, result or {})
end

function AnnouncerComponent:_announceMapVote(data)
	local duration = data and data.duration or 0
	if isMatchInstance() then
		return
	end

	if self._ctx.events and self._ctx.events.FireAll then
		self._ctx.events:FireAll("Game/VoteInitiate", duration, "Map")
	end

	-- legacy fallback (can be removed after old GameObjects.Remotes are retired)
	local remotes = self._ctx.gameObjects and self._ctx.gameObjects.Remotes
	if remotes and remotes.VoteInitiate then
		remotes.VoteInitiate:FireAllClients(duration, "Map")
	end
end

function AnnouncerComponent:_announceMvp(data)
	if not data or not data.player or not data.player.PlayerObject then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and remotes.Server and remotes.Server.PersonalSystemMessage then
		remotes.Server.PersonalSystemMessage:FireAllClients(
			("[SYSTEM] %s (%s) was the MVP for this round."):format(
				data.player.PlayerName,
				data.player.Team and data.player.Team.Name or "Team"
			),
			Color3.new(0.984314, 1, 0)
		)
	end
	if remotes and remotes.Server and remotes.Server.DialogueEvent then
	-- Omitted: dialogue-event glue.
	end
end

function AnnouncerComponent:_announceObjective(data)
	local stateKey = data and data.stateKey
	if not stateKey then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes or not remotes.Server or not remotes.Server.PersonalSystemMessage then
		return
	end

	local objectiveConfig = self._ctx.config and self._ctx.config.Objective or {}
	if objectiveConfig.EmitStateMessages ~= true then
		return
	end
	local messages = objectiveConfig.MessagesByState or {}
	local message = messages[stateKey]

	if message then
		remotes.Server.PersonalSystemMessage:FireAllClients(message, Color3.new(1, 1, 1))
	end
end

function AnnouncerComponent:RegisterEndpoints(eventService)
	self._ctx.events = eventService
	self:_registerEndpoints()
end

function AnnouncerComponent:_registerEndpoints()
	local eventService = self._ctx.events
	if not eventService or self._endpointsRegistered then
		return
	end

	self._endpointsRegistered = true

	local prefix = getEventPrefix(self._ctx)
	local objectiveConfig = self._ctx.config and self._ctx.config.Objective or {}
	local endpointConfig = objectiveConfig.Endpoint or {}

	eventService:RegisterFunction((endpointConfig.StatusPath or (prefix .. "/Status")), function()
		return true, self._ctx.state and self._ctx.state.objective or {}
	end, {
		guard = baseGuard,
		rateLimitKey = endpointConfig.StatusRateLimitKey or (prefix .. "/Status"),
		rateLimit = { calls = 5, seconds = 1 },
	})

	local actions = objectiveConfig.Actions or {
		{
			Action = "plant",
			Path = prefix .. "/Plant",
			Role = "attackers",
			RequireNearSite = true,
			RequireObjectiveActive = false,
			RateLimitKey = prefix .. "/Plant",
			RateLimit = { calls = 2, seconds = 2 },
		},
		{
			Action = "defuse",
			Path = prefix .. "/Defuse",
			Role = "defenders",
			RequireNearSite = true,
			RequireObjectiveActive = true,
			RateLimitKey = prefix .. "/Defuse",
			RateLimit = { calls = 2, seconds = 2 },
		},
	}

	for _, actionRule in ipairs(actions) do
		eventService:RegisterEvent(actionRule.Path, function(remoteCtx)
			local gp = remoteCtx.gp
			local attackersTeam, defendersTeam = getTeams(self._ctx)
			local expectedTeam = actionRule.Role == "attackers" and attackersTeam
				or actionRule.Role == "defenders" and defendersTeam
				or nil
			if expectedTeam and not isOnTeam(gp, expectedTeam) then
				return
			end
			if not isActionAllowedInPhase(self._ctx, actionRule, objectiveConfig) then
				return
			end
			if actionRule.RequireNearSite and not isNearSite(self._ctx, gp) then
				return
			end
			if actionRule.RequireObjectiveActive then
				local objectiveState = self._ctx.state and self._ctx.state.objective or {}
				local planted = objectiveState.planted == true
				local active = planted or (objectiveState.active == true)
				if not active then
					return
				end
			end

			if actionRule.Action == "defuse" then
				local eventsFolder = ServerStorage:FindFirstChild("Events")
				local uheEvent = eventsFolder and eventsFolder:FindFirstChild("UHE")
				local sourceActor = remoteCtx.player or remoteCtx.gp
				if sourceActor and uheEvent and uheEvent:IsA("BindableEvent") then
					uheEvent:Fire(sourceActor, "DefuseAttempt")
					return
				end
			end

			self._ctx.Events:Emit("ObjectiveActionAttempt", {
				action = actionRule.Action,
				userId = remoteCtx.userId,
				gp = remoteCtx.gp,
				raw = remoteCtx,
			})
		end, {
			guard = actionRule.Guard or baseGuard,
			rateLimitKey = actionRule.RateLimitKey or actionRule.Path,
			rateLimit = actionRule.RateLimit or { calls = 2, seconds = 2 },
		})
	end
end

function AnnouncerComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return AnnouncerComponent
