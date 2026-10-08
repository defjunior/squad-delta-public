-- FPS/ModeRegistry.lua
-- Simple factory/registry for game modes so they can be created with a consistent lifecycle.
local ModeRegistry = {}
ModeRegistry.__index = ModeRegistry

function ModeRegistry.new()
	local self = setmetatable({}, ModeRegistry)
	self._registry = {}
	return self
end

function ModeRegistry:Register(modeId, moduleRef)
	assert(type(modeId) == "string" and modeId ~= "", "modeId must be a non-empty string")
	assert(moduleRef, "moduleRef is required")
	self._registry[modeId] = moduleRef
end

function ModeRegistry:Create(modeId, ctx, config)
	local moduleRef = self._registry[modeId]
	if not moduleRef then
		return nil, ("Mode '%s' is not registered"):format(modeId)
	end

	-- Resolve to an instance; prefer constructor helpers when available.
	if type(moduleRef) == "table" then
		if type(moduleRef.new) == "function" then
			return moduleRef.new(ctx, config)
		end
		if type(moduleRef.Create) == "function" then
			return moduleRef.Create(ctx, config)
		end
	end

	if type(moduleRef) == "function" then
		return moduleRef(ctx, config)
	end

	-- If the module itself represents the instance, clone shallowly to avoid shared state.
	if type(moduleRef) == "table" then
		local instance = table.clone(moduleRef)
		instance._config = config
		if instance.Init and ctx then
			instance:Init(ctx, config)
		end
		return instance
	end

	return nil, ("Mode '%s' is registered with an unsupported type (%s)"):format(modeId, typeof(moduleRef))
end

return ModeRegistry
