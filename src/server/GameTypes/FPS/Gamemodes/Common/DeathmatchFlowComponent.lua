local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Modules.Logger)
local Framework = require(ReplicatedStorage.Modules.Framework)
local ModeRules = require(script.Parent.ModeRules)

local DeathmatchFlowComponent = {}
DeathmatchFlowComponent.__index = DeathmatchFlowComponent

local COMPONENT_NAME = "DeathmatchFlow"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function isMatchInstance()
	if _G.ServerRole == "MatchInstance" then
		return true
	end
	local rules = ReplicatedStorage:FindFirstChild("GameRules")
	local flag = rules and rules:FindFirstChild("IsMatchInstance")
	return flag and flag.Value == true
end

local function setStatus(ctx, text)
	local status = ctx and ctx.gameObjects and ctx.gameObjects:FindFirstChild("Status")
	if status then
		status.Value = text or ""
	end
	Logger.Info("[DeathmatchFlowComponent]", "Status -> %s", tostring(text))
end

local function setTimer(gameObjects, value)
	if gameObjects and gameObjects:FindFirstChild("Timer") then
		gameObjects.Timer.Value = value
	end
end

local function setFreeze(gameObjects, isFrozen)
	if gameObjects and gameObjects:FindFirstChild("FreezeTime") then
		gameObjects.FreezeTime.Value = isFrozen
	end
end

local function setBuyTime(gameObjects, value)
	if gameObjects and gameObjects:FindFirstChild("BuyTime") then
		gameObjects.BuyTime.Value = value or 0
	end
end

local function setRoundFlags(gameObjects, opts)
	if not gameObjects then
		return
	end
	if gameObjects:FindFirstChild("RoundEnded") then
		gameObjects.RoundEnded.Value = opts.roundEnded == true
	end
	if gameObjects:FindFirstChild("RoundOngoing") then
		gameObjects.RoundOngoing.Value = opts.roundOngoing == true
	end
end

local function shouldCountPlayer(gp)
	return gp and gp.IsPlaying == true and gp.Team and gp.Team.Name ~= "Spectator"
end

local function getStat(gp, statName)
	local stats = gp and gp.CurrentGameStats
	return tonumber(stats and stats[statName]) or 0
end

function DeathmatchFlowComponent.new(ctx)
	local self = setmetatable({}, DeathmatchFlowComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function DeathmatchFlowComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = ctx.config or {}
	self._flow = self._config.Deathmatch or {}
	self._connections = {}

	self._running = false
	self._roundTask = nil
	self._matchEnded = false
	self._mapLoaded = false
	self._phase = "Init"
	self._roundNumber = 0

	self._warmupRequested = false
	self._matchStartRequested = false
	self._warmupDurationOverride = nil
	self._warmupPhasePlayed = false
	self._warmupEndsAt = nil

	self._matchInstanceService = nil

	table.insert(self._connections, ctx.Events:On("MapLoaded", function(mapInstance)
		self._mapLoaded = mapInstance ~= nil
	end, eventLabel("MapLoaded")))

	table.insert(self._connections, ctx.Events:On("MatchEndRequested", function(payload)
		self:_endMatch(payload and payload.winnerPlayer, payload and payload.reason, payload and payload.winnerTeam)
	end, eventLabel("MatchEndRequested")))

	table.insert(self._connections, ctx.Events:On("PlayerEliminated", function(payload)
		self:_onPlayerEliminated(payload)
	end, eventLabel("PlayerEliminated")))
end

function DeathmatchFlowComponent:_setPhase(phase, data)
	self._phase = phase
	self._ctx.state.phase = phase
	self._ctx.Events:Emit("RoundPhaseChanged", phase, data)
end

function DeathmatchFlowComponent:_emitTimerTick(phase, timeRemaining, roundNumber)
	self._ctx.state.timer = timeRemaining
	self._ctx.Events:Emit("RoundTimerTick", {
		phase = phase,
		timeRemaining = timeRemaining,
		round = roundNumber,
	})
end

function DeathmatchFlowComponent:_getMatchInstanceService()
	if self._matchInstanceService then
		return self._matchInstanceService
	end
	self._matchInstanceService = Framework.GetService("MatchInstanceService")
	return self._matchInstanceService
end

function DeathmatchFlowComponent:_publishDisplayName()
	local displayName = self._config.DisplayName or "Deathmatch"
	local gameObjects = self._ctx.gameObjects
	if gameObjects and gameObjects:FindFirstChild("GamemodeName") then
		gameObjects.GamemodeName.Value = displayName
	end
	if gameObjects and gameObjects:FindFirstChild("Gamemode") and (gameObjects.Gamemode.Value == "" or gameObjects.Gamemode.Value == "Defusal") then
		gameObjects.Gamemode.Value = displayName
	end
end

function DeathmatchFlowComponent:_waitForPlayers()
	local minimumPlayers = math.max(1, math.floor(tonumber(self._flow.MinimumPlayers) or 1))
	while self._running and not self._matchEnded do
		local active = 0
		for _, gp in pairs(_G.Players or {}) do
			if shouldCountPlayer(gp) then
				active += 1
			end
		end
		if active >= minimumPlayers then
			return true
		end
		setStatus(self._ctx, ("Waiting for players (%d/%d)"):format(active, minimumPlayers))
		task.wait(1)
	end
	return false
end

function DeathmatchFlowComponent:_ensureMap()
	if self._mapLoaded then
		return true
	end
	self._ctx.Events:Emit("MapLoadRequested")
	while self._running and not self._mapLoaded and not self._matchEnded do
		task.wait(0.5)
	end
	return self._mapLoaded
end

function DeathmatchFlowComponent:_prepareRound(roundNumber)
	self._roundNumber = roundNumber
	self._ctx.state.round = roundNumber
	setRoundFlags(self._ctx.gameObjects, { roundEnded = false, roundOngoing = true })
	setBuyTime(self._ctx.gameObjects, 0)
	self._ctx.Events:Emit("RoundReset", { round = roundNumber })
end

function DeathmatchFlowComponent:_waitForWarmupStart()
	if not isMatchInstance() then
		self._warmupRequested = true
		return true
	end
	while self._running and not self._warmupRequested and not self._matchEnded do
		setStatus(self._ctx, "Waiting for ability selection...")
		task.wait(1)
	end
	return self._warmupRequested
end

function DeathmatchFlowComponent:_waitForMatchStart()
	if not isMatchInstance() then
		self._matchStartRequested = true
		return true
	end
	while self._running and not self._matchStartRequested and not self._matchEnded do
		setStatus(self._ctx, "Waiting for match start...")
		task.wait(1)
	end
	return self._matchStartRequested
end

function DeathmatchFlowComponent:_runWarmupPhase()
	if self._warmupPhasePlayed then
		return
	end
	self._warmupPhasePlayed = true

	local warmupDuration = self._warmupDurationOverride
	if warmupDuration == nil then
		warmupDuration = tonumber(self._flow.WarmupDuration) or 0
	end
	if warmupDuration <= 0 then
		local matchInstance = self:_getMatchInstanceService()
		if matchInstance and matchInstance.HandleWarmupComplete and isMatchInstance() then
			matchInstance:HandleWarmupComplete()
		end
		return
	end

	self._warmupEndsAt = (workspace and workspace.GetServerTimeNow and workspace:GetServerTimeNow() or os.clock()) + warmupDuration
	self:_prepareRound(0)
	self:_setPhase("Warmup", { round = 0 })
	setFreeze(self._ctx.gameObjects, false)
	setStatus(self._ctx, "Warmup")
	self._ctx.Events:Emit("WarmupStarted", { duration = warmupDuration, endsAt = self._warmupEndsAt })

	local matchInstance = self:_getMatchInstanceService()
	if matchInstance and matchInstance.BeginWarmup then
		matchInstance:BeginWarmup(self._warmupEndsAt, warmupDuration)
	end

	while self._running and not self._matchEnded do
		local now = workspace and workspace.GetServerTimeNow and workspace:GetServerTimeNow() or os.clock()
		local remaining = math.max(0, math.ceil(self._warmupEndsAt - now))
		setTimer(self._ctx.gameObjects, remaining)
		self:_emitTimerTick("Warmup", remaining, 0)
		if matchInstance and matchInstance.TickWarmup then
			matchInstance:TickWarmup(self._warmupEndsAt, warmupDuration)
		end
		if remaining <= 0 then
			break
		end
		task.wait(1)
	end

	self._ctx.Events:Emit("WarmupEnded", { round = 0 })
	if matchInstance and matchInstance.EndWarmup then
		matchInstance:EndWarmup()
	end
	if matchInstance and matchInstance.HandleWarmupComplete and isMatchInstance() then
		matchInstance:HandleWarmupComplete()
	end
	setFreeze(self._ctx.gameObjects, true)
	setStatus(self._ctx, "Warmup complete")
	self._warmupEndsAt = nil
end

function DeathmatchFlowComponent:_pickTopPlayer()
	local scoreStat = self._flow.ScoreStat or "Kills"
	local bestPlayer = nil
	local bestScore = nil
	local bestDeaths = nil

	for _, gp in pairs(_G.Players or {}) do
		if shouldCountPlayer(gp) then
			local score = getStat(gp, scoreStat)
			local deaths = getStat(gp, "Deaths")
			if bestScore == nil
				or score > bestScore
				or (score == bestScore and (bestDeaths == nil or deaths < bestDeaths))
			then
				bestScore = score
				bestDeaths = deaths
				bestPlayer = gp
			end
		end
	end

	return bestPlayer, bestScore or 0
end

function DeathmatchFlowComponent:_resolveWinningTeam(winnerPlayer, forcedTeam)
	if type(forcedTeam) == "string" and forcedTeam ~= "" then
		return forcedTeam
	end
	if winnerPlayer and winnerPlayer.Team and winnerPlayer.Team.Name then
		return winnerPlayer.Team.Name
	end
	return ModeRules.getTeamByRole(self._ctx, "attackers") or "RED"
end

function DeathmatchFlowComponent:_incrementTeamWin(teamName)
	if not teamName then
		return
	end
	local gameObjects = self._ctx.gameObjects
	if not gameObjects then
		return
	end
	local counterName = (self._config.TeamWinCounters and self._config.TeamWinCounters[teamName]) or (teamName .. "Wins")
	local counter = gameObjects:FindFirstChild(counterName)
	if counter and typeof(counter.Value) == "number" then
		counter.Value += 1
	end
end

function DeathmatchFlowComponent:_announceWinner(winnerPlayer, winningTeam, reason)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local serverFolder = remotes and remotes:FindFirstChild("Server")
	local personal = serverFolder and serverFolder:FindFirstChild("PersonalSystemMessage")
	if personal then
		if winnerPlayer then
			personal:FireAllClients(
				("[SYSTEM] %s won %s."):format(winnerPlayer.PlayerName, self._config.DisplayName or "the match"),
				Color3.new(0.984314, 1, 0)
			)
		else
			personal:FireAllClients(
				("[SYSTEM] %s won %s."):format(tostring(winningTeam), self._config.DisplayName or "the match"),
				Color3.new(0.984314, 1, 0)
			)
		end
	end

	if self._ctx.events and self._ctx.events.FireAll then
		self._ctx.events:FireAll("Server/ShowEnd", winningTeam, self._config.EndTime or 8)
	else
		local showEnd = serverFolder and serverFolder:FindFirstChild("ShowEnd")
		if showEnd then
			showEnd:FireAllClients(winningTeam, self._config.EndTime or 8)
		end
	end

	Logger.Info(
		"[DeathmatchFlowComponent]",
		"Match ended team=%s winner=%s reason=%s",
		tostring(winningTeam),
		tostring(winnerPlayer and winnerPlayer.PlayerName or "none"),
		tostring(reason)
	)
end

function DeathmatchFlowComponent:_endMatch(winnerPlayer, reason, forcedTeam)
	if self._matchEnded then
		return
	end
	self._matchEnded = true
	self._running = false

	local winningTeam = self:_resolveWinningTeam(winnerPlayer, forcedTeam)
	self:_incrementTeamWin(winningTeam)

	setFreeze(self._ctx.gameObjects, true)
	setTimer(self._ctx.gameObjects, 0)
	setRoundFlags(self._ctx.gameObjects, { roundEnded = true, roundOngoing = false })
	setStatus(self._ctx, ("Match ended: %s"):format(tostring(winningTeam)))

	self:_announceWinner(winnerPlayer, winningTeam, reason or "completed")

	self._ctx.Events:Emit("MatchEnded", {
		winner = winningTeam,
		winnerPlayer = winnerPlayer,
		reason = reason or "completed",
		round = self._roundNumber,
	})

	if self._ctx.gameService and self._ctx.gameService.CompetitiveEnd then
		self._ctx.gameService:CompetitiveEnd()
	end
end

function DeathmatchFlowComponent:_runLivePhase()
	self:_prepareRound(1)
	self:_setPhase("Live", { round = 1 })
	setFreeze(self._ctx.gameObjects, false)
	setStatus(self._ctx, "Round in progress")

	local duration = math.max(1, math.floor(tonumber(self._flow.TimeLimit) or tonumber(self._config.RoundTime) or 300))
	for remaining = duration, 0, -1 do
		if not self._running or self._matchEnded then
			return
		end
		setTimer(self._ctx.gameObjects, remaining)
		self:_emitTimerTick("Live", remaining, 1)
		if remaining <= 0 then
			break
		end
		task.wait(1)
	end

	if self._matchEnded then
		return
	end
	local winnerPlayer = nil
	local bestScore = 0
	if self._flow.TimeExpiryWinner == "none" then
		self:_endMatch(nil, "Time expired", self._flow.TimeExpiryWinnerTeam)
		return
	end
	winnerPlayer, bestScore = self:_pickTopPlayer()
	self:_endMatch(winnerPlayer, ("Time expired (%d %s)"):format(bestScore, tostring(self._flow.ScoreStat or "Kills")), self._flow.TimeExpiryWinnerTeam)
end

function DeathmatchFlowComponent:_onPlayerEliminated(payload)
	if not payload or self._matchEnded then
		return
	end
	local flow = self._flow
	local victim = payload.victim
	local killer = payload.killer

	if flow.InstantRespawn == true and victim then
		local respawnDelay = tonumber(flow.RespawnDelay) or 1.5
		task.delay(respawnDelay, function()
			if not self._mounted or self._matchEnded or not self._running then
				return
			end
			if not (victim and victim.IsPlaying == true) then
				return
			end
			self._ctx.Events:Emit("WarmupRespawn", victim)
		end)
	end

	local killGoal = tonumber(flow.KillGoal)
	if killGoal and killer and killer.CurrentGameStats then
		local kills = tonumber(killer.CurrentGameStats.Kills) or 0
		if kills >= killGoal then
			self:_endMatch(killer, ("Kill goal reached (%d)"):format(killGoal))
		end
	end
end

function DeathmatchFlowComponent:_run()
	self:_publishDisplayName()
	if not self:_waitForPlayers() then
		return
	end
	if not self:_ensureMap() then
		warn("[DeathmatchFlowComponent] Failed to load map")
		return
	end
	if not self:_waitForWarmupStart() then
		return
	end
	self:_runWarmupPhase()
	if self._matchEnded then
		return
	end
	if not self:_waitForMatchStart() then
		return
	end
	self:_runLivePhase()
end

function DeathmatchFlowComponent:Start()
	if self._running then
		return
	end
	self._running = true
	self._matchEnded = false
	self._roundTask = task.spawn(function()
		self:_run()
	end)
end

function DeathmatchFlowComponent:StartWarmup(duration)
	self._warmupRequested = true
	if duration ~= nil then
		self._warmupDurationOverride = tonumber(duration) or self._warmupDurationOverride
	end
	return true
end

function DeathmatchFlowComponent:SignalMatchStart()
	self._matchStartRequested = true
	return true
end

function DeathmatchFlowComponent:Stop()
	self._running = false
	if self._roundTask then
		task.cancel(self._roundTask)
		self._roundTask = nil
	end
end

function DeathmatchFlowComponent:Dismount()
	self:Stop()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return DeathmatchFlowComponent
