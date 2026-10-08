-- Generic lifecycle loader extracted from SquadDelta. Game services and bootstrap order were excluded at the owner's request.
-- Generic server module loader used for services and controllers.
local ServerModuleLoader = {}
ServerModuleLoader.__index = ServerModuleLoader

local function requireWithTrace(moduleScript)
	local loaded
	local ok, err = xpcall(function()
		loaded = require(moduleScript)
	end, debug.traceback)
	if not ok then
		error(("[ServerModuleLoader] require failed for %s\n%s"):format(moduleScript:GetFullName(), tostring(err)), 0)
	end
	return loaded
end

local function instantiateModule(moduleScript)
	local factory = requireWithTrace(moduleScript)
	if typeof(factory) == "function" then
		return factory(moduleScript)
	elseif typeof(factory) == "table" then
		if typeof(factory.new) == "function" then
			return factory.new(moduleScript)
		end
		return factory
	end

	error(("Server module loader could not instantiate %s"):format(moduleScript:GetFullName()), 2)
end

function ServerModuleLoader.new(folder, options)
	local self = setmetatable({}, ServerModuleLoader)
	self._folder = folder
	self._items = {}
	self._registerFn = options and options.register
	return self
end

function ServerModuleLoader:_register(name, instance)
	if self._registerFn then
		self._registerFn(name, instance)
	end
end

function ServerModuleLoader:LoadAll()
	for _, moduleScript in ipairs(self._folder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local module = instantiateModule(moduleScript)
			module._moduleScript = module._moduleScript or moduleScript

			local name = moduleScript.Name
			self._items[name] = module
			self:_register(name, module)
		end
	end
	return self._items
end

function ServerModuleLoader:Get(name)
	return self._items[name]
end

function ServerModuleLoader:InitAll()
	for _, module in pairs(self._items) do
		if typeof(module.Init) == "function" then
			module:Init()
		end
	end
end

function ServerModuleLoader:StartAll()
	for _, module in pairs(self._items) do
		if typeof(module.Start) == "function" then
			module:Start()
		end
	end
end

function ServerModuleLoader:StopAll()
	for _, module in pairs(self._items) do
		if typeof(module.Stop) == "function" then
			module:Stop()
		end
	end
end

function ServerModuleLoader:Destroy()
	for _, module in pairs(self._items) do
		if typeof(module.Destroy) == "function" then
			module:Destroy()
		elseif typeof(module.Stop) == "function" then
			module:Stop()
		end
	end
	self._items = {}
end

return ServerModuleLoader
