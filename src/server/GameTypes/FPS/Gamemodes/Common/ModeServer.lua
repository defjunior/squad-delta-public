local ServerScriptService = game:GetService("ServerScriptService")

local EventBus = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("EventBus"))

local ModeServer = {}
ModeServer.__index = ModeServer

local function createEventHub()
	local bus = EventBus.new()
	return {
		On = function(_, eventName, handler, label)
			local conn = bus:subscribe(eventName, handler, label)
			if not conn then
				return nil
			end
			return {
				Disconnect = function()
					if conn.disconnect then
						conn:disconnect()
					elseif conn.Disconnect then
						conn:Disconnect()
					end
				end,
			}
		end,
		Emit = function(_, eventName, ...)
			bus:publish(eventName, ...)
		end,
	}
end

local function cloneTable(source)
	local out = {}
	for k, v in pairs(source or {}) do
		out[k] = v
	end
	return out
end

local function buildDefaultState(config)
	local defaultState = {
		roster = { attackers = {}, defenders = {}, aliveAttackers = {}, aliveDefenders = {} },
		map = nil,
		phase = "Init",
		round = 0,
		timer = 0,
		objective = {},
	}
	local configured = config and config.InitialState
	if type(configured) == "table" then
		for k, v in pairs(configured) do
			defaultState[k] = v
		end
	end
	return defaultState
end

local function getComponentSpecName(spec)
	if type(spec) == "string" then
		return spec
	end
	if type(spec) == "table" then
		return spec.module or spec.name
	end
	return nil
end

local function getComponentKey(spec, fallbackName)
	if type(spec) == "table" and type(spec.key) == "string" and spec.key ~= "" then
		return spec.key
	end
	local base = fallbackName or "Component"
	return base:gsub("Component$", "")
end

function ModeServer.new(baseCtx, config, options)
	local self = setmetatable({}, ModeServer)
	self:Init(baseCtx, config, options)
	return self
end

function ModeServer:Init(baseCtx, config, options)
	-- GameService currently calls :Init() after .new(); preserve constructor options
	-- when options are omitted on subsequent init calls.
	if options then
		self._options = options
	elseif not self._options then
		self._options = {}
	end
	self._componentsFolder = self._options.componentsFolder or self._componentsFolder
	self._modeId = self._options.modeId or self._modeId
	self._config = config or {}
	if self._componentList then
		self:_dismountAll()
	end
	self:_buildContext(baseCtx, self._config)
	self:_mountComponents()
	self._initialized = true
end

function ModeServer:_buildContext(baseCtx, config)
	self._ctx = {
		config = config,
		state = buildDefaultState(config),
		framework = baseCtx and baseCtx.framework,
		gameObjects = (baseCtx and baseCtx.gameObjects) or game.ReplicatedStorage:WaitForChild("GameObjects"),
		gameService = baseCtx and baseCtx.gameService,
		events = baseCtx and baseCtx.events,
		Events = createEventHub(),
	}
end

function ModeServer:_resolveComponent(spec)
	if not self._componentsFolder then
		return nil, "components folder missing"
	end
	local moduleName = getComponentSpecName(spec)
	if not moduleName then
		return nil, "component spec missing module name"
	end
	local moduleScript = nil
	if string.find(moduleName, "/") then
		local parts = string.split(moduleName, "/")
		local cursor = self._componentsFolder and self._componentsFolder.Parent and self._componentsFolder.Parent.Parent
		for _, part in ipairs(parts) do
			if not cursor then
				break
			end
			cursor = cursor:FindFirstChild(part)
		end
		moduleScript = cursor
	else
		moduleScript = self._componentsFolder:FindFirstChild(moduleName)
	end
	if not moduleScript then
		return nil, ("component module not found: %s"):format(moduleName)
	end
	local ok, componentModule = pcall(require, moduleScript)
	if not ok then
		return nil, ("failed to require %s: %s"):format(moduleName, tostring(componentModule))
	end
	return componentModule, nil, moduleName
end

function ModeServer:_mountComponents()
	local serverConfig = self._config.Server or {}
	local componentSpecs = serverConfig.Components or {}
	self._componentList = {}
	self._componentsByKey = {}

	for _, spec in ipairs(componentSpecs) do
		local componentModule, err, moduleName = self:_resolveComponent(spec)
		if not componentModule then
			warn(("[ModeServer] %s (%s)"):format(err or "unknown component error", tostring(self._modeId)))
			continue
		end

		local instance = nil
		if type(componentModule.new) == "function" then
			instance = componentModule.new(self._ctx)
		else
			instance = cloneTable(componentModule)
			if type(instance.Mount) == "function" then
				instance:Mount(self._ctx)
			end
		end
		if not instance then
			continue
		end

		table.insert(self._componentList, instance)
		local componentKey = getComponentKey(spec, moduleName)
		self._componentsByKey[componentKey] = instance
	end
end

function ModeServer:GetComponent(key)
	return self._componentsByKey and self._componentsByKey[key] or nil
end

function ModeServer:RegisterEndpoints(eventService)
	if not self._ctx then
		return
	end
	self._ctx.events = eventService

	local endpointKeys = (self._config.Server and self._config.Server.EndpointComponents) or {}
	for _, key in ipairs(endpointKeys) do
		local component = self:GetComponent(key)
		if component and type(component.RegisterEndpoints) == "function" then
			component:RegisterEndpoints(eventService)
		end
	end
end

local function resolveControlComponent(self)
	local serverConfig = self._config.Server or {}
	local key = serverConfig.ControlComponent or "RoundFlow"
	return self:GetComponent(key)
end

function ModeServer:Start()
	if self._ctx and self._ctx.events then
		self:RegisterEndpoints(self._ctx.events)
	end

	local serverConfig = self._config.Server or {}
	local serverComponents = serverConfig.Components or {}
	if #serverComponents > 0 then
		for _, entry in ipairs(serverComponents) do
			local key = entry.key
			local component = self:GetComponent(key)
			if component and type(component.Start) == "function" then
				component:Start()
			end
		end
		return
	end

	local control = resolveControlComponent(self)
	if control and type(control.Start) == "function" then
		control:Start()
	end
end

function ModeServer:StartWarmup(duration)
	local control = resolveControlComponent(self)
	if not control then
		return
	end
	if control.IsRunning and not control:IsRunning() and control.Start then
		control:Start()
	end
	if type(control.StartWarmup) == "function" then
		control:StartWarmup(duration)
	end
end

function ModeServer:SignalMatchStart()
	local control = resolveControlComponent(self)
	if control and type(control.SignalMatchStart) == "function" then
		control:SignalMatchStart()
	end
end

function ModeServer:Stop(reason)
	local control = resolveControlComponent(self)
	if control and type(control.Stop) == "function" then
		control:Stop(reason or "stopped")
	end
end

function ModeServer:_dismountAll()
	if not self._componentList then
		return
	end
	for i = #self._componentList, 1, -1 do
		local component = self._componentList[i]
		if component then
			if component.Dismount then
				component:Dismount()
			elseif component.Destroy then
				component:Destroy()
			end
		end
	end
	self._componentList = nil
	self._componentsByKey = nil
end

function ModeServer:Destroy()
	self:_dismountAll()
end

return ModeServer
