local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ModeRules = require(script.Parent.Parent.Parent.Common.ModeRules)

local AliveRosterComponent = {}
AliveRosterComponent.__index = AliveRosterComponent

local COMPONENT_NAME = "AliveRoster"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function getTeamNames(ctx)
	return ModeRules.getRoleTeams(ctx)
end

local function isAlive(gp)
	if not gp then
		return false
	end
	if gp.IsAlive ~= nil then
		return gp.IsAlive == true
	end
	return gp.CharacterObject ~= nil
end

local function isPlaying(gp)
	return gp and gp.IsPlaying == true
end

local function buildPlayerKey(gp)
	if not gp then
		return nil
	end
	if gp.PlayerObject and gp.PlayerObject.UserId then
		return tostring(gp.PlayerObject.UserId)
	end
	if gp.ID then
		return tostring(gp.ID)
	end
	if gp.PlayerName then
		return gp.PlayerName
	end
	return nil
end

local function disconnectAll(connections)
	for _, conn in ipairs(connections) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		elseif conn and conn.disconnect then
			conn:disconnect()
		end
	end
end

function AliveRosterComponent.new(ctx)
	local self = setmetatable({}, AliveRosterComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function AliveRosterComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._connections = {}
	self._phase = "Init"

	table.insert(self._connections, ctx.Events:On("RoundPhaseChanged", function(phase)
		self._phase = phase
	end, eventLabel("RoundPhaseChanged")))

	table.insert(self._connections, ctx.Events:On("RoundReset", function()
		self:_refreshFromPlayers()
	end, eventLabel("RoundReset")))

	table.insert(self._connections, ctx.Events:On("PlayerSpawned", function(gp)
		self:_markSpawn(gp)
	end, eventLabel("PlayerSpawned")))

	table.insert(self._connections, ctx.Events:On("PlayerDied", function(gp)
		self:_markDead(gp, false)
	end, eventLabel("PlayerDied")))

	table.insert(self._connections, ctx.Events:On("PlayerLeft", function(gp)
		self:_markDead(gp, true)
	end, eventLabel("PlayerLeft")))

	self:_bindExternalSignals()
	self:_refreshFromPlayers()
end

function AliveRosterComponent:_bindExternalSignals()
	local eventsFolder = ServerStorage:FindFirstChild("Events")
	if eventsFolder and eventsFolder:FindFirstChild("NewDeath") then
		table.insert(self._connections, eventsFolder.NewDeath.Event:Connect(function(playerId)
			local gp = _G.Players and _G.Players[playerId]
			if gp then
				self._ctx.Events:Emit("PlayerDied", gp)
			end
		end))
	end

	table.insert(self._connections, Players.PlayerRemoving:Connect(function(player)
		local gp = _G.Players and _G.Players[player.UserId]
		if gp then
			self._ctx.Events:Emit("PlayerLeft", gp)
		end
	end))
end

function AliveRosterComponent:_refreshFromPlayers()
	local attackersTeam, defendersTeam = getTeamNames(self._ctx)
	local attackers = {}
	local defenders = {}
	local aliveAttackers = {}
	local aliveDefenders = {}

	for _, gp in pairs(_G.Players) do
		if isPlaying(gp) then
			if gp.Team and gp.Team.Name == attackersTeam then
				table.insert(attackers, gp)
				if isAlive(gp) then
					table.insert(aliveAttackers, gp)
				end
			elseif gp.Team and gp.Team.Name == defendersTeam then
				table.insert(defenders, gp)
				if isAlive(gp) then
					table.insert(aliveDefenders, gp)
				end
			end
		end
	end

	self._roster = {
		attackersTeam = attackersTeam,
		defendersTeam = defendersTeam,
		attackers = attackers,
		defenders = defenders,
		aliveAttackers = aliveAttackers,
		aliveDefenders = aliveDefenders,
	}

	self._ctx.state.roster = self._roster
	self._ctx.Events:Emit("RosterUpdated", self._roster)
	self:_sendRosterUpdate()
end

function AliveRosterComponent:_markSpawn(gp)
	if not isPlaying(gp) then
		return
	end
	if not self._roster then
		self:_refreshFromPlayers()
		return
	end

	local attackersTeam, defendersTeam = getTeamNames(self._ctx)
	if gp.Team and gp.Team.Name == attackersTeam then
		table.insert(self._roster.attackers, gp)
		table.insert(self._roster.aliveAttackers, gp)
	elseif gp.Team and gp.Team.Name == defendersTeam then
		table.insert(self._roster.defenders, gp)
		table.insert(self._roster.aliveDefenders, gp)
	end
	self._ctx.state.roster = self._roster
	self._ctx.Events:Emit("RosterUpdated", self._roster)
	self:_sendRosterUpdate()
end

function AliveRosterComponent:_markDead(gp, dropTeam)
	if not gp or not self._roster then
		return
	end

	local function drop(list, player)
		for i, candidate in ipairs(list) do
			if candidate == player then
				table.remove(list, i)
				return
			end
		end
	end

	drop(self._roster.aliveAttackers, gp)
	drop(self._roster.aliveDefenders, gp)
	if dropTeam then
		drop(self._roster.attackers, gp)
		drop(self._roster.defenders, gp)
	end

	self._ctx.state.roster = self._roster
	self._ctx.Events:Emit("RosterUpdated", self._roster)
	self:_sendRosterUpdate()
end

function AliveRosterComponent:_serializeRoster()
	local roster = self._roster
	if not roster then
		return nil
	end
	local payload = {}
	local function addPlayers(list, teamName)
		if not list then
			return
		end
		for _, gp in ipairs(list) do
			local key = buildPlayerKey(gp)
			if key and key ~= "" then
				payload[key] = {
					PlayerName = gp.PlayerName,
					Team = teamName or (gp.Team and gp.Team.Name) or "Spectator",
					Alive = isAlive(gp),
					UserId = gp.PlayerObject and gp.PlayerObject.UserId,
					PlayerId = gp.ID,
					IsBot = gp.IsBot == true,
				}
			end
		end
	end
	addPlayers(roster.attackers, roster.attackersTeam)
	addPlayers(roster.defenders, roster.defendersTeam)
	return payload
end

function AliveRosterComponent:_sendRosterUpdate()
	local payload = self:_serializeRoster()
	if not payload then
		return
	end
	if self._ctx.events and self._ctx.events.FireAll then
		self._ctx.events:FireAll("Server/RosterUpdated", payload)
	end
end

function AliveRosterComponent:RegisterEndpoints(eventService)
	if not eventService or self._endpointsRegistered then
		return
	end
	self._endpointsRegistered = true
	eventService:RegisterFunction("Server/GetRoster", function()
		local payload = self:_serializeRoster()
		return true, payload
	end, {
		guard = { gp = false, inGame = false, alive = false, character = false },
		rateLimitKey = "Server/GetRoster",
		rateLimit = { calls = 2, seconds = 1 },
	})
	self:_sendRosterUpdate()
end

function AliveRosterComponent:Dismount()
	disconnectAll(self._connections or {})
	self._connections = nil
	self._mounted = false
end

return AliveRosterComponent
