local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage.Modules.Framework)
local ComponentRegistry = require(script.Parent.Components)

local PlayerLike = require(script.Parent)
local PlayerBase = PlayerLike:Extend()

local function bindComponentMethod(component, method)
	return function(_, ...)
		return method(component, ...)
	end
end

local function bindClassMethods(target, class)
	for name, value in pairs(class) do
		if type(value) == "function" and string.sub(name, 1, 1) ~= "_" and string.sub(name, 1, 2) ~= "__" then
			if rawget(target, name) == nil then
				target[name] = value
			end
		end
	end
end

local function bindComponentMethodsToPlayer(player, component, componentName)
	local bound = {}
	for name, value in pairs(component) do
		if type(value) == "function" and string.sub(name, 1, 1) ~= "_" then
			local boundFn = bindComponentMethod(component, value)
			player[name] = boundFn
			bound[name] = boundFn
		end
	end

	player.ComponentMethodBindings = player.ComponentMethodBindings or {}
	player.ComponentMethodBindings[componentName] = bound
end

local function unbindComponentMethodsFromPlayer(player, componentName)
	local bindings = player.ComponentMethodBindings
	if not bindings then
		return
	end
	local bound = bindings[componentName]
	if not bound then
		return
	end

	for name, boundFn in pairs(bound) do
		if rawget(player, name) == boundFn then
			player[name] = nil
		end
	end
	bindings[componentName] = nil
end

function PlayerBase:__index(key)
	-- prefer class members first
	local class = PlayerBase
	local classValue = rawget(class, key)
	if classValue ~= nil then
		return classValue
	end

	local mt = getmetatable(self)
	if mt and mt ~= self then
		local mtValue = rawget(mt, key)
		if mtValue ~= nil then
			return mtValue
		end
	end

	-- delegate to components if they expose a matching function
	local components = rawget(self, "Components")
	if components then
		-- use rawget to avoid re-entering __index when Components/MountedComponents are missing
		local mountedComponents = rawget(self, "MountedComponents")
		if mountedComponents then
			for _, name in ipairs(mountedComponents) do
				local component = components[name]
				if component then
					local candidate = component[key]
					if type(candidate) == "function" then
						return bindComponentMethod(component, candidate)
					end
				end
			end
		end

		-- fallback for any components mounted outside the list
		for _, component in pairs(components) do
			if component then
				local candidate = component[key]
				if type(candidate) == "function" then
					return bindComponentMethod(component, candidate)
				end
			end
		end
	end

	return nil
end

function PlayerBase:EnsureBase(playerObject, setName)
	self.UserId = playerObject and playerObject.UserId or self.UserId or tostring(setName)
	self.PlayerObject = playerObject or self.PlayerObject
	self.PlayerName = setName or (playerObject and playerObject.Name) or self.PlayerName

	self.Maid = self.Maid or {}
	self.Components = self.Components or {}
	self.MountedComponents = self.MountedComponents or {}
	self.ComponentMethodBindings = self.ComponentMethodBindings or {}

	bindClassMethods(self, PlayerLike)
	bindClassMethods(self, PlayerBase)
end

local function removeFromMounted(list, target)
	for i, name in ipairs(list) do
		if name == target then
			table.remove(list, i)
			return
		end
	end
end

function PlayerBase:MountComponent(name, ctx)
	if not name then
		return nil
	end
	if self.Components[name] then
		return self.Components[name]
	end

	local componentClass = ComponentRegistry:Get(name)
	if not componentClass then
		warn(("[PlayerBase] Component %s is not registered."):format(tostring(name)))
		return nil
	end

	local component = componentClass:New(self, ctx)
	self.Components[name] = component
	table.insert(self.MountedComponents, name)

	bindComponentMethodsToPlayer(self, component, name)

	if component.Init then
		component:Init(self, ctx)
	end
	if component.Start then
		component:Start()
	end

	return component
end



function PlayerBase:GetComponent(name)
	return self.Components[name]
end

function PlayerBase:HasComponent(name)
	return self.Components[name] ~= nil
end

function PlayerBase:UnmountComponent(name)
	local component = self.Components[name]
	if not component then
		return
	end

	if component.Stop then
		component:Stop()
	end
	if component.Destroy then
		component:Destroy()
	end

	self.Components[name] = nil
	removeFromMounted(self.MountedComponents, name)
	unbindComponentMethodsFromPlayer(self, name)
end

function PlayerBase:GetMountedComponentNames()
	local names = {}
	for _, name in ipairs(self.MountedComponents) do
		table.insert(names, name)
	end
	return names
end

function PlayerBase:DestroyComponents()
	-- destroy in mount order for determinism
	for _, name in ipairs(self.MountedComponents) do
		local component = self.Components[name]
		if component then
			if component.Stop then
				component:Stop()
			end
			if component.Destroy then
				component:Destroy()
			end
			self.Components[name] = nil
		end
		unbindComponentMethodsFromPlayer(self, name)
	end
	table.clear(self.MountedComponents)
end

function PlayerBase:AddCleanup(name, fn)
	if not name or type(fn) ~= "function" then
		return
	end
	self.Maid[name] = fn
	return function()
		self.Maid[name] = nil
	end
end

function PlayerBase:Cleanup()
	for name, fn in pairs(self.Maid) do
		if type(fn) == "function" then
			pcall(fn)
		end
		self.Maid[name] = nil
	end
end

function PlayerBase:DebugDump()
	local componentList = self:GetMountedComponentNames()
	local profiles = {}
	for key in pairs(self.Profiles or {}) do
		table.insert(profiles, key)
	end
	for key in pairs(self.MountedData or {}) do
		if not table.find(profiles, key) then
			table.insert(profiles, key)
		end
	end
	return {
		components = componentList,
		profiles = profiles,
	}
end

return PlayerBase
