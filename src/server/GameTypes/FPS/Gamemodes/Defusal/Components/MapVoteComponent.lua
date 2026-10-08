local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MapVoteComponent = {}
MapVoteComponent.__index = MapVoteComponent

local COMPONENT_NAME = "MapVote"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local MATCH_OVERRIDE_RULE = "MatchInstanceMap"

local DEFAULT_VOTE_TIME = 10

local function chooseRandom(tbl)
	if #tbl == 0 then
		return nil
	end
	return tbl[math.random(1, #tbl)]
end

local function gatherMaps()
	local mapsFolder = ServerStorage:FindFirstChild("Maps")
	if not mapsFolder then
		return {}
	end
	local maps = {}
	for _, child in ipairs(mapsFolder:GetChildren()) do
		if (child:IsA("Folder") or child:IsA("Model")) and child.Name ~= "PackageLink" then
			table.insert(maps, child)
		end
	end
	return maps
end

local function pickCandidates(allMaps, preferred)
	if preferred and #preferred > 0 then
		return preferred
	end
	local map1 = chooseRandom(allMaps)
	local map2 = chooseRandom(allMaps)
	if map1 == map2 and #allMaps > 1 then
		repeat
			map2 = chooseRandom(allMaps)
		until map2 ~= map1
	end
	return { map1, map2 }
end

local function resetLighting()
	if _G.ResetLighting then
		_G.ResetLighting()
	end
end

local function applyMapLighting(mapInstance)
	if not mapInstance then
		return
	end
	local lightingFolder = mapInstance:FindFirstChild("Lighting")
	if not lightingFolder then
		return
	end
	for _, child in ipairs(lightingFolder:GetChildren()) do
		if child:IsA("ValueBase") then
			if game.Lighting:FindFirstChild(child.Name) then
				game.Lighting[child.Name] = child.Value
			end
		elseif child:IsA("Instance") then
			local clone = child:Clone()
			if clone.Name == "Clouds" then
				clone.Parent = workspace.Terrain
			else
				clone.Parent = game.Lighting
			end
		end
	end
end

local function findMapByName(name)
	if not name or name == "" then
		return nil
	end
	local mapsFolder = ServerStorage:FindFirstChild("Maps")
	if not mapsFolder then
		return nil
	end
	for _, candidate in ipairs(mapsFolder:GetChildren()) do
		if (candidate:IsA("Folder") or candidate:IsA("Model")) and candidate.Name ~= "PackageLink" then
			if string.lower(candidate.Name) == string.lower(name) then
				return candidate
			end
		end
	end
	return nil
end

local function getMatchInstanceOverride()
	local override = _G.MatchInstanceMap
	local rules = ReplicatedStorage:FindFirstChild("GameRules")
	if rules then
		local value = rules:FindFirstChild(MATCH_OVERRIDE_RULE)
		if value and value:IsA("StringValue") and value.Value ~= "" then
			override = value.Value
		end
	end
	if type(override) == "string" and override ~= "" then
		return override
	end
	return nil
end

function MapVoteComponent:_updateMapDisplay(primary, secondary)
	local gameObjects = self._ctx and self._ctx.gameObjects
	if not gameObjects then
		return
	end
	if gameObjects.Map1 then
		gameObjects.Map1.Value = primary and primary.Name or ""
	end
	if gameObjects.Map2 then
		gameObjects.Map2.Value = secondary and secondary.Name or ""
	end
end

local function callMapInit(mapInstance)
	if not mapInstance then
		return
	end
	local initModule = mapInstance:FindFirstChild("Init")
	if not initModule then
		return
	end
	local ok, init = pcall(require, initModule)
	if not ok then
		warn("[MapVoteComponent] Failed to require map Init:", init)
		return
	end
	if init.Lighting then
		pcall(init.Lighting)
	end
	if init.Init then
		pcall(init.Init)
	end
end

local function setStatus(ctx, text)
	local status = ctx.gameObjects and ctx.gameObjects:FindFirstChild("Status")
	if status then
		status.Value = text
	end
	ctx.Events:Emit("StatusChanged", text)
end

function MapVoteComponent.new(ctx)
	local self = setmetatable({}, MapVoteComponent)
	if ctx then
		self:Mount(ctx)
		self._ctx = ctx
	end
	return self
end

function MapVoteComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = ctx.config or {}
	self._connections = {}

	table.insert(self._connections, ctx.Events:On("MapLoadRequested", function()
		self:_ensureMapLoaded()
	end, eventLabel("MapLoadRequested")))
end

function MapVoteComponent:_beginVote(candidates)
	local map1 = candidates[1]
	local map2 = candidates[2]
	local gameObjects = self._ctx.gameObjects
	self:_updateMapDisplay(map1, map2)

	self._ctx.Events:Emit("MapVoteStarted", {
		duration = self._config.MapVoteTime or DEFAULT_VOTE_TIME,
		map1 = map1,
		map2 = map2,
	})

	local votes = {
		[map1 and map1.Name or ""] = 0,
		[map2 and map2.Name or ""] = 0,
	}

	self._voteDisconnect = self._ctx.gameService
		and self._ctx.gameService:SubscribeVote(function(_, selection)
			if selection == "Map1" and map1 then
				votes[map1.Name] += 1
			elseif selection == "Map2" and map2 then
				votes[map2.Name] += 1
			end
		end)

	task.wait(self._config.MapVoteTime or DEFAULT_VOTE_TIME)

	if self._voteDisconnect then
		self._voteDisconnect()
		self._voteDisconnect = nil
	end

	if (votes[map1 and map1.Name or ""] or 0) >= (votes[map2 and map2.Name or ""] or 0) then
		return map1
	end
	return map2
end

function MapVoteComponent:_cleanWorkspace()
	if _G.ChosenMap then
		_G.ChosenMap:Destroy()
		_G.ChosenMap = nil
	end
end

function MapVoteComponent:_runIntermission()
	local seconds = self._config.Intermission or 0
	if seconds <= 0 then
		return
	end
	for i = seconds, 0, -1 do
		if not self._loading then
			return
		end
		setStatus(self._ctx, ("Intermission (%s)"):format(i))
		task.wait(1)
	end
end

function MapVoteComponent:_loadMap()
	self._loading = true
	self:_runIntermission()

	local maps = gatherMaps()
	local overrideName = getMatchInstanceOverride()
	local overrideMap = overrideName and findMapByName(overrideName)
	local isMatchInstance = _G.ServerRole == "MatchInstance"
	local rules = ReplicatedStorage:FindFirstChild("GameRules")
	local isMatchValue = rules and rules:FindFirstChild("IsMatchInstance")
	if isMatchValue and isMatchValue.Value == true then
		isMatchInstance = true
	end
	if overrideName and not overrideMap then
		warn("[MapVoteComponent] Match-instance override map not found:", overrideName)
	end
	local chosenMap
	local chosenCandidates
	if overrideMap then
		setStatus(self._ctx, ("Loading %s..."):format(overrideMap.Name))
		self:_updateMapDisplay(overrideMap, nil)
		chosenMap = overrideMap
		chosenCandidates = { overrideMap }
	elseif isMatchInstance then
		chosenMap = chooseRandom(maps)
		if chosenMap then
			setStatus(self._ctx, ("Loading %s..."):format(chosenMap.Name))
			self:_updateMapDisplay(chosenMap, nil)
			chosenCandidates = { chosenMap }
		end
	else
		chosenCandidates = pickCandidates(maps)
		setStatus(self._ctx, "Selecting Maps...")
		chosenMap = self:_beginVote(chosenCandidates)
	end

	self._ctx.Events:Emit("MapChosen", {
		map = chosenMap,
		candidates = chosenCandidates,
	})

	if not chosenMap then
		warn("[MapVoteComponent] No map selected; falling back to first available")
		chosenMap = maps[1]
	end

	setStatus(self._ctx, "Loading...")
	self:_cleanWorkspace()

	if not chosenMap then
		warn("[MapVoteComponent] No maps available in ServerStorage/Maps")
		self._loading = false
		return nil
	end

	local clone = chosenMap:Clone()
	clone.Parent = workspace
	_G.ChosenMap = clone

	resetLighting()
	callMapInit(clone)
	applyMapLighting(clone)

	local gameObjects = self._ctx.gameObjects
	if gameObjects then
		if gameObjects.CurrentMap then
			gameObjects.CurrentMap.Value = clone.Name
		end
		if gameObjects.Gamemode then
			local mapConfig = self._config.Map or {}
			gameObjects.Gamemode.Value = mapConfig.GameObjectName or self._config.DisplayName or ""
		end
		if gameObjects.RoundCode then
			gameObjects.RoundCode.Value = math.random(1, 20300)
		end
	end

	local zoneNameContains = (self._config.Map and self._config.Map.ObjectiveZoneNameContains) or "Site"
	local zonesFolder = _G.ChosenMap and _G.ChosenMap:FindFirstChild("Zones")
	if zonesFolder and gameObjects and gameObjects.RoundCode then
		for _, zone in pairs(zonesFolder:GetChildren()) do
			if zoneNameContains == "" or string.find(zone.Name, zoneNameContains) then
				zone.Name = gameObjects.RoundCode.Value .. ":" .. zone.Name
			end
		end
	end

	self._map = clone
	self._ctx.state.map = clone
	setStatus(self._ctx, "Loaded")
	self._loading = false

	self._ctx.Events:Emit("MapLoaded", clone)
	return clone
end

function MapVoteComponent:_ensureMapLoaded()
	if self._map then
		self._ctx.Events:Emit("MapLoaded", self._map)
		return self._map
	end
	return self:_loadMap()
end

function MapVoteComponent:GetMap()
	return self._map
end

function MapVoteComponent:Dismount()
	if self._voteDisconnect then
		self._voteDisconnect()
		self._voteDisconnect = nil
	end
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return MapVoteComponent
