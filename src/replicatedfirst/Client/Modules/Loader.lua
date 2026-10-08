-- ControllerLoader.lua
local ControllerLoader = {}
ControllerLoader.__index = ControllerLoader

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Modules.Logger)

local TERMINAL_STATUS = {
	started = true,
	failed = true,
	timed_out = true,
	skipped = true,
	skipped_disabled = true,
}

local function requireWithTrace(moduleScript)
	local loaded
	local ok, err = xpcall(function()
		loaded = require(moduleScript)
	end, debug.traceback)
	if not ok then
		error(("[ControllerLoader] require failed for %s\n%s"):format(moduleScript:GetFullName(), tostring(err)), 0)
	end
	return loaded
end

local function isBaseController(controller)
	return typeof(controller._InitIfNeeded) == "function" and typeof(controller._StartIfAllowed) == "function"
end

local function ensureBoolean(value, default)
	if value == nil then
		return default
	end
	return value == true
end

local function shouldAutoStart(controller)
	return controller and controller.Enabled and ensureBoolean(controller.AutoStart, true)
end

local function parseDependenciesAttribute(value)
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	local dependencies = {}
	local seen = {}
	for token in string.gmatch(value, "([^,]+)") do
		local trimmed = string.match(token, "^%s*(.-)%s*$")
		if trimmed and trimmed ~= "" and not seen[trimmed] then
			seen[trimmed] = true
			table.insert(dependencies, trimmed)
		end
	end
	return (#dependencies > 0) and dependencies or nil
end

local function normalizeDependencies(rawDependencies, selfName)
	local dependencies = {}
	local seen = {}
	if typeof(rawDependencies) ~= "table" then
		return dependencies
	end

	for _, dependencyName in ipairs(rawDependencies) do
		if typeof(dependencyName) == "string" then
			local trimmed = string.match(dependencyName, "^%s*(.-)%s*$")
			if trimmed and trimmed ~= "" and trimmed ~= selfName and not seen[trimmed] then
				seen[trimmed] = true
				table.insert(dependencies, trimmed)
			end
		end
	end

	return dependencies
end

local function dependenciesToString(snapshot)
	if typeof(snapshot) ~= "table" or #snapshot == 0 then
		return "none"
	end

	local parts = {}
	for _, item in ipairs(snapshot) do
		table.insert(parts, ("%s=%s"):format(item.name, item.status))
	end
	return table.concat(parts, ", ")
end

local function cloneArray(source)
	local out = {}
	for i = 1, #source do
		out[i] = source[i]
	end
	return out
end

local function copySnapshot(snapshot)
	local out = {}
	for i = 1, #snapshot do
		local item = snapshot[i]
		out[i] = {
			name = item.name,
			status = item.status,
			reason = item.reason,
		}
	end
	return out
end

local function applyModuleAttributes(controller, moduleScript)
	local enabledAttr = moduleScript:GetAttribute("Enabled")
	if enabledAttr ~= nil then
		controller.Enabled = enabledAttr == true
	end

	local autoAttr = moduleScript:GetAttribute("AutoStart")
	if autoAttr ~= nil then
		controller.AutoStart = autoAttr == true
	end

	if controller.Enabled == nil then
		controller.Enabled = true
	end
	if controller.AutoStart == nil then
		controller.AutoStart = true
	end
end

function ControllerLoader.new(controllersFolder, baseControllerModule, options)
	local self = setmetatable({}, ControllerLoader)
	self._folder = controllersFolder
	self._base = baseControllerModule
	self._controllers = {}
	self._controllerStates = {}
	self._excludeSet = {}
	self._controllerPolicies = (options and options.controllerPolicies) or {}
	self._defaultRequired = (options and options.defaultRequired) == true
	self._defaultStartupWarningSeconds = tonumber(options and (options.startupWarningSeconds or options.stallWarnSeconds)) or 5
	self._defaultStartupTimeoutSeconds = tonumber(options and (options.startupTimeoutSeconds or options.controllerTimeoutSeconds)) or 20
	self._stallWarningIntervalSeconds = tonumber(options and options.stallWarningIntervalSeconds) or 5

	if options and typeof(options.exclude) == "table" then
		for _, name in ipairs(options.exclude) do
			if typeof(name) == "string" then
				self._excludeSet[name] = true
			end
		end
	end

	return self
end

function ControllerLoader:_stateIsTerminal(state)
	return state and TERMINAL_STATUS[state.status] == true
end

function ControllerLoader:_policyFor(name)
	local policy = self._controllerPolicies and self._controllerPolicies[name]
	if typeof(policy) == "table" then
		return policy
	end
	return nil
end

function ControllerLoader:_resolveDependencies(name, controller, moduleScript, policy)
	local dependencies = nil

	if policy and typeof(policy.dependencies) == "table" then
		dependencies = policy.dependencies
	elseif typeof(controller.GetDependencies) == "function" then
		dependencies = controller:GetDependencies()
	elseif typeof(controller.Dependencies) == "table" then
		dependencies = controller.Dependencies
	end

	if dependencies == nil and moduleScript then
		dependencies = parseDependenciesAttribute(moduleScript:GetAttribute("Dependencies"))
	end

	return normalizeDependencies(dependencies, name)
end

function ControllerLoader:_resolveRequired(controller, moduleScript, policy)
	if policy and policy.required ~= nil then
		return policy.required == true
	end

	if typeof(controller.IsRequiredForBoot) == "function" then
		return controller:IsRequiredForBoot() == true
	end

	if controller.RequiredForBoot ~= nil then
		return controller.RequiredForBoot == true
	end

	if moduleScript then
		local requiredAttr = moduleScript:GetAttribute("Required")
		if requiredAttr ~= nil then
			return requiredAttr == true
		end
	end

	return self._defaultRequired
end

function ControllerLoader:_resolveStartupWarning(controller, moduleScript, policy)
	if policy and tonumber(policy.startupWarningSeconds) and tonumber(policy.startupWarningSeconds) > 0 then
		return tonumber(policy.startupWarningSeconds)
	end

	if typeof(controller.GetStartupWarningSeconds) == "function" then
		local value = tonumber(controller:GetStartupWarningSeconds())
		if value and value > 0 then
			return value
		end
	end

	local controllerValue = tonumber(controller.StartupWarningSeconds)
	if controllerValue and controllerValue > 0 then
		return controllerValue
	end

	if moduleScript then
		local attrValue = tonumber(moduleScript:GetAttribute("StartupWarningSeconds"))
		if attrValue and attrValue > 0 then
			return attrValue
		end
	end

	return self._defaultStartupWarningSeconds
end

function ControllerLoader:_resolveStartupTimeout(controller, moduleScript, policy)
	if policy and tonumber(policy.startupTimeoutSeconds) and tonumber(policy.startupTimeoutSeconds) > 0 then
		return tonumber(policy.startupTimeoutSeconds)
	end

	if typeof(controller.GetStartupTimeoutSeconds) == "function" then
		local value = tonumber(controller:GetStartupTimeoutSeconds())
		if value and value > 0 then
			return value
		end
	end

	local controllerValue = tonumber(controller.StartupTimeoutSeconds)
	if controllerValue and controllerValue > 0 then
		return controllerValue
	end

	if moduleScript then
		local attrValue = tonumber(moduleScript:GetAttribute("StartupTimeoutSeconds"))
		if attrValue and attrValue > 0 then
			return attrValue
		end
	end

	return self._defaultStartupTimeoutSeconds
end

function ControllerLoader:_buildState(name, controller, moduleScript)
	local policy = self:_policyFor(name)
	local dependencies = self:_resolveDependencies(name, controller, moduleScript, policy)
	local required = self:_resolveRequired(controller, moduleScript, policy)
	local startupWarningSeconds = self:_resolveStartupWarning(controller, moduleScript, policy)
	local startupTimeoutSeconds = self:_resolveStartupTimeout(controller, moduleScript, policy)

	return {
		name = name,
		isBase = isBaseController(controller),
		initialized = false,
		running = false,
		required = required,
		dependencies = dependencies,
		startupWarningSeconds = startupWarningSeconds,
		startupTimeoutSeconds = startupTimeoutSeconds,
		status = "loaded",
		failureReason = nil,
		phase = nil,
		phases = {},
	}
end

function ControllerLoader:_instantiateController(moduleScript)
	local controllerFactory = requireWithTrace(moduleScript)
	local controller

	if typeof(controllerFactory) == "function" then
		controller = controllerFactory(moduleScript)
	elseif typeof(controllerFactory) == "table" then
		local constructor = controllerFactory.new
		if typeof(constructor) == "function" then
			controller = constructor(moduleScript)
		else
			controller = controllerFactory
		end
	end

	if not controller then
		error(("Controller loader could not instantiate %s"):format(moduleScript:GetFullName()), 2)
	end

	if not controller._moduleScript then
		controller._moduleScript = moduleScript
	end

	return controller
end

function ControllerLoader:_dependencySnapshot(state)
	local snapshot = {}
	local pending = false
	local blocked = false
	local blockedReasons = {}

	for _, dependencyName in ipairs(state.dependencies or {}) do
		local dependencyState = self._controllerStates[dependencyName]
		local dependencyController = self._controllers[dependencyName]

		if not dependencyController then
			blocked = true
			table.insert(blockedReasons, ("%s missing"):format(dependencyName))
			table.insert(snapshot, {
				name = dependencyName,
				status = "missing",
				reason = "controller not loaded",
			})
		elseif not shouldAutoStart(dependencyController) then
			blocked = true
			table.insert(blockedReasons, ("%s disabled"):format(dependencyName))
			table.insert(snapshot, {
				name = dependencyName,
				status = "disabled",
				reason = "dependency disabled/autostart off",
			})
		elseif dependencyState and dependencyState.running then
			table.insert(snapshot, {
				name = dependencyName,
				status = "running",
				reason = nil,
			})
		elseif dependencyState and dependencyState.status == "started" then
			table.insert(snapshot, {
				name = dependencyName,
				status = "started",
				reason = nil,
			})
		elseif dependencyState and TERMINAL_STATUS[dependencyState.status] then
			blocked = true
			local dependencyReason = dependencyState.failureReason or dependencyState.status
			table.insert(blockedReasons, ("%s %s"):format(dependencyName, dependencyReason))
			table.insert(snapshot, {
				name = dependencyName,
				status = dependencyState.status,
				reason = dependencyReason,
			})
		else
			pending = true
			local pendingStatus = (dependencyState and dependencyState.status) or "pending"
			table.insert(snapshot, {
				name = dependencyName,
				status = pendingStatus,
				reason = "dependency not started yet",
			})
		end
	end

	return snapshot, pending, blocked, blockedReasons
end

function ControllerLoader:_runPhaseWithDiagnostics(name, state, phase, callback)
	local phaseStartedAt = os.clock()
	local dependencySnapshot = self:_dependencySnapshot(state)
	local dependencyStatusText = dependenciesToString(dependencySnapshot)
	local warningThreshold = tonumber(state.startupWarningSeconds) or self._defaultStartupWarningSeconds
	local timeoutSeconds = tonumber(state.startupTimeoutSeconds) or self._defaultStartupTimeoutSeconds

	Logger.Info(
		"ControllerLoader",
		"%s begin controller=%s required=%s deps=%s",
		phase,
		name,
		tostring(state.required),
		dependencyStatusText
	)

	local finished = false
	local ok = false
	local err = nil
	task.spawn(function()
		ok, err = xpcall(callback, debug.traceback)
		finished = true
	end)

	local warned = false
	local nextWarnAt = warningThreshold
	local warningCount = 0
	while not finished do
		local elapsed = os.clock() - phaseStartedAt
		if warningThreshold > 0 and elapsed >= nextWarnAt then
			warned = true
			warningCount += 1
			Logger.Warn(
				"ControllerLoader",
				"%s stalled controller=%s elapsed=%.2fs deps=%s",
				phase,
				name,
				elapsed,
				dependencyStatusText
			)
			nextWarnAt = nextWarnAt + math.max(self._stallWarningIntervalSeconds, 0.5)
		end

		if timeoutSeconds > 0 and elapsed >= timeoutSeconds then
			local timeoutReason = ("%s timed out after %.2fs"):format(phase, elapsed)
			local phaseRecord = {
				phase = phase,
				ok = false,
				timedOut = true,
				duration = elapsed,
				error = timeoutReason,
				warningCount = warningCount,
				dependencies = copySnapshot(dependencySnapshot),
				startedAt = phaseStartedAt,
				endedAt = os.clock(),
			}
			table.insert(state.phases, phaseRecord)
			Logger.Error(
				"ControllerLoader",
				"%s timeout controller=%s duration=%.2fs deps=%s reason=%s",
				phase,
				name,
				elapsed,
				dependencyStatusText,
				timeoutReason
			)
			return false, timeoutReason, elapsed, true
		end

		task.wait(0.05)
	end

	local duration = os.clock() - phaseStartedAt
	local phaseRecord = {
		phase = phase,
		ok = ok,
		timedOut = false,
		duration = duration,
		error = ok and nil or tostring(err),
		warningCount = warningCount,
		dependencies = copySnapshot(dependencySnapshot),
		startedAt = phaseStartedAt,
		endedAt = os.clock(),
	}
	table.insert(state.phases, phaseRecord)

	if not ok then
		Logger.Error(
			"ControllerLoader",
			"%s failed controller=%s duration=%.2fs deps=%s reason=%s",
			phase,
			name,
			duration,
			dependencyStatusText,
			tostring(err)
		)
		return false, tostring(err), duration, false
	end

	if warned then
		Logger.Warn("ControllerLoader", "%s recovered controller=%s duration=%.2fs", phase, name, duration)
	end
	Logger.Info("ControllerLoader", "%s complete controller=%s duration=%.2fs", phase, name, duration)
	return true, nil, duration, false
end

function ControllerLoader:_markFailure(state, status, reason, phase)
	state.running = false
	state.status = status or "failed"
	state.phase = phase
	state.failureReason = tostring(reason or "unknown failure")
end

function ControllerLoader:_markSkipped(state, reason, phase)
	state.running = false
	state.status = "skipped"
	state.phase = phase
	state.failureReason = tostring(reason or "skipped")
end

function ControllerLoader:_ensureInitialized(name, controller, state)
	if state.initialized then
		return true
	end

	local phase = state.isBase and "Init(base)" or "Init"
	local ok, err
	if state.isBase then
		ok, err = self:_runPhaseWithDiagnostics(name, state, phase, function()
			local initOk, initErr = controller:_InitIfNeeded()
			if initOk == false then
				error(initErr or "base init returned false", 0)
			end
		end)
	else
		ok, err = self:_runPhaseWithDiagnostics(name, state, phase, function()
			if typeof(controller.Init) == "function" then
				controller:Init()
			end
		end)
	end

	if not ok then
		self:_markFailure(state, "failed", err, "init")
		return false
	end

	state.initialized = true
	if state.status == "loaded" then
		state.status = "initialized"
	end
	return true
end

function ControllerLoader:_startControllerByName(name, options)
	options = options or {}
	local controller = self._controllers[name]
	local state = self._controllerStates[name]
	if not controller or not state then
		return false, "controller_missing"
	end

	if state.running or state.status == "started" then
		return true
	end

	if self:_stateIsTerminal(state) and state.status ~= "initialized" then
		return false, state.status
	end

	if not shouldAutoStart(controller) then
		state.status = "skipped_disabled"
		state.running = false
		return false, "not_auto_start"
	end

	if not options.ignoreDependencies then
		local dependencySnapshot, dependencyPending, dependencyBlocked, blockedReasons = self:_dependencySnapshot(state)
		if dependencyPending then
			return false, "dependencies_pending"
		end

		if dependencyBlocked then
			local reason = "blocked by dependencies: " .. dependenciesToString(dependencySnapshot)
			if state.required then
				self:_markFailure(state, "failed", reason, "dependency")
				Logger.Error("ControllerLoader", "Dependency block controller=%s required=true reason=%s", name, reason)
			else
				self:_markSkipped(state, reason, "dependency")
				Logger.Warn("ControllerLoader", "Dependency block controller=%s required=false reason=%s", name, reason)
			end
			return false, "dependencies_blocked", blockedReasons
		end
	end

	if not self:_ensureInitialized(name, controller, state) then
		if not state.required then
			Logger.Warn("ControllerLoader", "Optional controller init failed: %s (%s)", name, tostring(state.failureReason))
		end
		return false, "init_failed"
	end

	local phase = state.isBase and "Start(base)" or "Start"
	local startOk, startErr, _, startTimedOut
	if state.isBase then
		startOk, startErr, _, startTimedOut = self:_runPhaseWithDiagnostics(name, state, phase, function()
			local ok, err = controller:_StartIfAllowed()
			if ok == false then
				error(err or "base start returned false", 0)
			end
		end)
	else
		startOk, startErr, _, startTimedOut = self:_runPhaseWithDiagnostics(name, state, phase, function()
			if typeof(controller.Start) == "function" then
				controller:Start()
			end
		end)
	end

	if not startOk then
		local status = startTimedOut and "timed_out" or "failed"
		self:_markFailure(state, status, startErr, "start")
		if state.required then
			Logger.Error(
				"ControllerLoader",
				"Required controller failed to start: %s (%s)",
				name,
				tostring(startErr)
			)
		else
			Logger.Warn(
				"ControllerLoader",
				"Optional controller failed to start: %s (%s)",
				name,
				tostring(startErr)
			)
		end
		return false, status
	end

	state.running = true
	state.status = "started"
	state.failureReason = nil
	state.phase = "start"
	return true
end

function ControllerLoader:_stopNonBase(name, controller, state)
	if not state.running then
		return
	end

	state.running = false
	state.status = "initialized"
	if typeof(controller.Stop) == "function" then
		local ok, err = xpcall(function()
			controller:Stop()
		end, debug.traceback)
		if not ok then
			Logger.Error("ControllerLoader", "Stop failed for %s: %s", name, tostring(err))
		end
	end
end

function ControllerLoader:LoadAll()
	local modules = {}
	for _, moduleScript in ipairs(self._folder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			table.insert(modules, moduleScript)
		end
	end
	table.sort(modules, function(a, b)
		return a.Name < b.Name
	end)

	for _, moduleScript in ipairs(modules) do
		local name = moduleScript.Name
		if self._excludeSet[name] then
			Logger.Info("ControllerLoader", "Skipping excluded controller %s", name)
			continue
		end
		if self._controllers[name] then
			Logger.Warn("ControllerLoader", "Duplicate controller module name detected (%s); skipping %s", name, moduleScript:GetFullName())
			continue
		end

		local controller = self:_instantiateController(moduleScript)
		applyModuleAttributes(controller, moduleScript)

		self._controllers[name] = controller
		self._controllerStates[name] = self:_buildState(name, controller, moduleScript)
		local state = self._controllerStates[name]
		Logger.Info(
			"ControllerLoader",
			"Loaded controller=%s required=%s autoStart=%s deps=%s timeout=%.2fs",
			name,
			tostring(state.required),
			tostring(controller.AutoStart == true),
			dependenciesToString(self:_dependencySnapshot(state)),
			tonumber(state.startupTimeoutSeconds) or 0
		)
	end

	return self._controllers
end

function ControllerLoader:InitAll()
	local names = {}
	for name in pairs(self._controllers) do
		table.insert(names, name)
	end
	table.sort(names)

	for _, name in ipairs(names) do
		local controller = self._controllers[name]
		local state = self._controllerStates[name]
		if controller and controller.Enabled and state then
			self:_ensureInitialized(name, controller, state)
		end
	end
end

function ControllerLoader:StartAll()
	self:StartOrdered(nil)
end

function ControllerLoader:StartOrdered(names)
	local ordered = {}
	local seen = {}

	if typeof(names) == "table" then
		for i = 1, #names do
			local name = names[i]
			if typeof(name) == "string" and not seen[name] and self._controllers[name] ~= nil then
				seen[name] = true
				table.insert(ordered, name)
			end
		end
	end

	local remaining = {}
	for name in pairs(self._controllers) do
		if not seen[name] then
			table.insert(remaining, name)
		end
	end
	table.sort(remaining)
	for i = 1, #remaining do
		table.insert(ordered, remaining[i])
	end

	while true do
		local progress = false
		local unresolvedCount = 0

		for i = 1, #ordered do
			local name = ordered[i]
			local controller = self._controllers[name]
			local state = self._controllerStates[name]
			if controller and state and shouldAutoStart(controller) and not self:_stateIsTerminal(state) then
				unresolvedCount += 1
				local ok, reason = self:_startControllerByName(name)
				if ok then
					progress = true
				elseif reason ~= "dependencies_pending" then
					progress = true
				end
			end
		end

		if unresolvedCount == 0 then
			break
		end

		if not progress then
			for i = 1, #ordered do
				local name = ordered[i]
				local controller = self._controllers[name]
				local state = self._controllerStates[name]
				if controller and state and shouldAutoStart(controller) and not self:_stateIsTerminal(state) then
					local dependencySnapshot = self:_dependencySnapshot(state)
					local reason = "unresolved startup dependency wait: " .. dependenciesToString(dependencySnapshot)
					if state.required then
						self:_markFailure(state, "failed", reason, "dependency")
						Logger.Error("ControllerLoader", "Required controller unresolved: %s (%s)", name, reason)
					else
						self:_markSkipped(state, reason, "dependency")
						Logger.Warn("ControllerLoader", "Optional controller unresolved: %s (%s)", name, reason)
					end
				end
			end
			break
		end
	end
end

function ControllerLoader:SetEnabled(name, enabled)
	local controller = self._controllers[name]
	local state = self._controllerStates[name]
	if not controller or not state then
		return false
	end

	controller.Enabled = enabled == true
	if controller._moduleScript then
		controller._moduleScript:SetAttribute("Enabled", controller.Enabled)
	end

	if controller.Enabled then
		state.status = state.initialized and "initialized" or "loaded"
		state.failureReason = nil
		self:_startControllerByName(name)
	else
		if state.isBase then
			local ok, err = xpcall(function()
				controller:_StopIfRunning()
			end, debug.traceback)
			if not ok then
				Logger.Error("ControllerLoader", "Stop failed for %s: %s", name, tostring(err))
			end
		else
			self:_stopNonBase(name, controller, state)
		end
		state.running = false
		state.status = "skipped_disabled"
	end

	return true
end

function ControllerLoader:Get(name)
	return self._controllers[name]
end

function ControllerLoader:GetState(name)
	return self._controllerStates[name]
end

function ControllerLoader:GetStates()
	local snapshot = {}
	for name, state in pairs(self._controllerStates) do
		snapshot[name] = {
			status = state.status,
			required = state.required,
			initialized = state.initialized,
			running = state.running,
			failureReason = state.failureReason,
			dependencies = cloneArray(state.dependencies or {}),
			phase = state.phase,
			phases = state.phases,
		}
	end
	return snapshot
end

function ControllerLoader:WaitForControllers(names, timeoutSeconds)
	if typeof(names) ~= "table" then
		return true, {}
	end

	local pending = {}
	for i = 1, #names do
		local name = names[i]
		if typeof(name) == "string" then
			pending[name] = true
		end
	end

	local failures = {}
	local deadline = os.clock() + (tonumber(timeoutSeconds) or 20)
	while true do
		local waiting = 0
		for name in pairs(pending) do
			local controller = self._controllers[name]
			local state = self._controllerStates[name]
			if not controller or not state then
				failures[name] = "missing"
				pending[name] = nil
			elseif not shouldAutoStart(controller) then
				pending[name] = nil
			elseif state.status == "started" then
				pending[name] = nil
			elseif TERMINAL_STATUS[state.status] then
				failures[name] = state.failureReason or state.status
				pending[name] = nil
			else
				waiting += 1
			end
		end

		if waiting == 0 then
			return next(failures) == nil, failures
		end
		if os.clock() >= deadline then
			for name in pairs(pending) do
				local state = self._controllerStates[name]
				failures[name] = state and (state.status or "timeout") or "timeout"
			end
			return false, failures
		end

		task.wait(0.1)
	end
end

function ControllerLoader:GetRequiredFailures()
	local failures = {}
	for name, state in pairs(self._controllerStates) do
		local controller = self._controllers[name]
		if state and controller and state.required and shouldAutoStart(controller) and state.status ~= "started" then
			if state.status == "failed" or state.status == "timed_out" or state.status == "skipped" then
				table.insert(failures, {
					name = name,
					status = state.status,
					reason = state.failureReason,
					dependencies = cloneArray(state.dependencies or {}),
				})
			end
		end
	end
	table.sort(failures, function(a, b)
		return a.name < b.name
	end)
	return failures
end

function ControllerLoader:GetDiagnostics()
	local diagnostics = {}
	for name, state in pairs(self._controllerStates) do
		diagnostics[name] = {
			status = state.status,
			required = state.required,
			initialized = state.initialized,
			running = state.running,
			failureReason = state.failureReason,
			dependencies = cloneArray(state.dependencies or {}),
			phases = state.phases,
		}
	end
	return diagnostics
end

function ControllerLoader:Destroy()
	for name, controller in pairs(self._controllers) do
		local state = self._controllerStates[name]
		if state and not state.isBase then
			self:_stopNonBase(name, controller, state)
		end

		if typeof(controller.Destroy) == "function" then
			local ok, err = xpcall(function()
				controller:Destroy()
			end, debug.traceback)
			if not ok then
				Logger.Error("ControllerLoader", "Destroy failed for %s: %s", name, tostring(err))
			end
		elseif typeof(controller.Stop) == "function" then
			local ok, err = xpcall(function()
				controller:Stop()
			end, debug.traceback)
			if not ok then
				Logger.Error("ControllerLoader", "Stop fallback failed for %s: %s", name, tostring(err))
			end
		end
	end

	self._controllers = {}
	self._controllerStates = {}
end

return ControllerLoader
