-- BaseController.lua
local Maid = require(game.ReplicatedStorage.Modules.Framework.Maid)

local BaseController = {}
BaseController.__index = BaseController

local function parseDependenciesFromAttribute(value)
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

function BaseController.new(moduleScript)
	local self = setmetatable({}, BaseController)

	self._moduleScript = moduleScript
	self._maid = Maid.new()

	self._inited = false
	self._running = false
	self._initError = nil
	self._startError = nil

	-- default gating
	self.Enabled = true
	self.AutoStart = true
	self.RequiredForBoot = false
	self.Dependencies = {}
	self.StartupWarningSeconds = nil
	self.StartupTimeoutSeconds = nil

	if moduleScript then
		local enabledAttr = moduleScript:GetAttribute("Enabled")
		if enabledAttr ~= nil then
			self.Enabled = (enabledAttr == true)
		end

		local autoAttr = moduleScript:GetAttribute("AutoStart")
		if autoAttr ~= nil then
			self.AutoStart = (autoAttr == true)
		end

		local requiredAttr = moduleScript:GetAttribute("Required")
		if requiredAttr ~= nil then
			self.RequiredForBoot = (requiredAttr == true)
		end

		local dependenciesAttr = moduleScript:GetAttribute("Dependencies")
		local parsedDependencies = parseDependenciesFromAttribute(dependenciesAttr)
		if parsedDependencies then
			self.Dependencies = parsedDependencies
		end

		local warningAttr = moduleScript:GetAttribute("StartupWarningSeconds")
		if typeof(warningAttr) == "number" and warningAttr > 0 then
			self.StartupWarningSeconds = warningAttr
		end

		local timeoutAttr = moduleScript:GetAttribute("StartupTimeoutSeconds")
		if typeof(timeoutAttr) == "number" and timeoutAttr > 0 then
			self.StartupTimeoutSeconds = timeoutAttr
		end
	end

	return self
end

-- Helpers: use these for EVERY connection/task you create in a controller
function BaseController:Track(taskOrSignal, fn)
	if typeof(taskOrSignal) == "RBXScriptSignal" and typeof(fn) == "function" then
		return self._maid:Give(taskOrSignal:Connect(fn))
	end
	return self._maid:Give(taskOrSignal)
end

function BaseController:Connect(signal, fn)
	return self:Track(signal:Connect(fn))
end

function BaseController:Init()
	-- override
end

function BaseController:Start()
	-- override
end

function BaseController:Stop()
	-- override
end

function BaseController:Destroy()
	self:Stop()
	self._maid:Cleanup()
end

function BaseController:GetDependencies()
	return self.Dependencies
end

function BaseController:IsRequiredForBoot()
	return self.RequiredForBoot == true
end

function BaseController:GetStartupWarningSeconds()
	return self.StartupWarningSeconds
end

function BaseController:GetStartupTimeoutSeconds()
	return self.StartupTimeoutSeconds
end

-- Engine (don't override)
function BaseController:_InitIfNeeded()
	if self._inited then
		return true
	end

	local ok, err = xpcall(function()
		if self.Init then
			self:Init()
		end
	end, debug.traceback)

	if not ok then
		self._inited = false
		self._initError = tostring(err)
		return false, self._initError
	end

	self._inited = true
	self._initError = nil
	return true
end

function BaseController:_StartIfAllowed()
	if self._running then
		return true
	end

	if not self.Enabled then
		return false, "controller disabled"
	end

	local initOk, initErr = self:_InitIfNeeded()
	if not initOk then
		self._running = false
		self._startError = tostring(initErr)
		return false, self._startError
	end

	local ok, err = xpcall(function()
		if self.Start then
			self:Start()
		end
	end, debug.traceback)

	if not ok then
		self._running = false
		self._startError = tostring(err)
		return false, self._startError
	end

	self._running = true
	self._startError = nil
	return true
end

function BaseController:_StopIfRunning()
	if not self._running then
		return
	end
	self._running = false
	if self.Stop then
		self:Stop()
	end
	-- crucial: stop should clean tasks it created during running
	self._maid:Cleanup()
end

return BaseController
