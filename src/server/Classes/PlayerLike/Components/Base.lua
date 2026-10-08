local ServerStorage = game:GetService("ServerStorage")

local Class = require(ServerStorage.Modules.Class)

local ComponentBase = Class:Extend()
ComponentBase.__index = ComponentBase
ComponentBase.Name = "ComponentBase"

function ComponentBase:New(player, ctx)
	local instance = setmetatable({}, self)
	instance.player = player
	instance.ctx = ctx
	instance.isActive = false
	return instance
end

function ComponentBase:Init(player, ctx)
	-- override if necessary
end

function ComponentBase:Start()
	self.isActive = true
end

function ComponentBase:Stop()
	self.isActive = false
end

function ComponentBase:Destroy()
	self:Stop()
end

return ComponentBase
