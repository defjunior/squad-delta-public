local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Framework = require(ReplicatedStorage.Modules.Framework)

local LoadoutMutationComponent = {}
LoadoutMutationComponent.__index = LoadoutMutationComponent

local COMPONENT_NAME = "LoadoutMutation"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function pickRandom(list)
	if type(list) ~= "table" or #list <= 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function itemTool(itemOrTool)
	if not itemOrTool then
		return nil
	end
	if itemOrTool.IsA and itemOrTool:IsA("Tool") then
		return itemOrTool
	end
	return itemOrTool.Tool
end

local function giveTool(gp, item)
	if not gp or not item then
		return
	end
	if gp.AddItemToBackpack then
		gp:AddItemToBackpack(item)
		return
	end
	if item.Parent then
		item.Parent = gp.Backpack or gp.CharacterObject
	end
end

local function applyAmmo(tool, ammoConfig)
	if not tool or not ammoConfig then
		return
	end
	local ammo = tool:FindFirstChild("Ammo")
	if not ammo then
		return
	end
	if ammoConfig.Current and ammo:FindFirstChild("Current") then
		ammo.Current.Value = ammoConfig.Current
	end
	if ammoConfig.Reserve and ammo:FindFirstChild("Reserve") then
		ammo.Reserve.Value = ammoConfig.Reserve
	end
end

local function applyWeaponConfig(tool, overrides)
	if not tool or type(overrides) ~= "table" then
		return
	end
	local weaponConfigObject = tool:FindFirstChild("WeaponConfig")
	if not weaponConfigObject then
		return
	end

	local ok, required = pcall(require, weaponConfigObject)
	if not ok then
		return
	end

	local indexed = required
	local configInstance = weaponConfigObject:FindFirstChildOfClass("Configuration")
	if not configInstance and Framework.AddAttributes then
		local addOk, addResult = pcall(Framework.AddAttributes, required, weaponConfigObject)
		if addOk then
			indexed = addResult
		end
	else
		indexed = configInstance or indexed
	end
	if Framework.IndexAttribute then
		local idxOk, idxResult = pcall(Framework.IndexAttribute, indexed)
		if idxOk then
			indexed = idxResult
		end
	end
	for key, value in pairs(overrides) do
		pcall(function()
			indexed[key] = value
		end)
	end
end

function LoadoutMutationComponent.new(ctx)
	local self = setmetatable({}, LoadoutMutationComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function LoadoutMutationComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = (ctx.config and ctx.config.LoadoutMutation) or {}
	self._itemService = Framework.GetService("ItemService")
	self._connections = {}

	table.insert(self._connections, ctx.Events:On("PlayerProvisionRuleApplied", function(payload)
		self:_handleProvisionRule(payload)
	end, eventLabel("PlayerProvisionRuleApplied")))
end

function LoadoutMutationComponent:_applyMutationToTool(tool, mutation)
	if not tool or not mutation then
		return
	end
	applyAmmo(tool, mutation.Ammo)
	applyWeaponConfig(tool, mutation.WeaponConfig)
end

function LoadoutMutationComponent:_giveConfiguredWeapon(gp, mutation)
	if not gp or not mutation or not self._itemService then
		return nil
	end
	local pool = mutation.RandomWeaponPool
	local weaponName = mutation.WeaponName or pickRandom(pool)
	if not weaponName then
		return nil
	end
	local weaponBase = ServerStorage:FindFirstChild("Weapons") and ServerStorage.Weapons:FindFirstChild(weaponName)
	if not weaponBase then
		return nil
	end
	local item = self._itemService:NewItem(weaponBase, mutation.ItemType or "Gun")
	giveTool(gp, item)
	local tool = itemTool(item)
	if tool then
		self:_applyMutationToTool(tool, mutation)
	end
	return item
end

function LoadoutMutationComponent:_mutateBackpackGuns(gp, mutation)
	if not gp or not gp.Backpack then
		return
	end
	for _, item in pairs(gp.Backpack) do
		local tool = itemTool(item)
		if tool then
			self:_applyMutationToTool(tool, mutation)
		end
	end
end

function LoadoutMutationComponent:_handleProvisionRule(payload)
	local ruleName = payload and payload.ruleName
	local gp = payload and payload.player
	if not ruleName or not gp then
		return
	end
	local rules = self._config.RulesByProvisionRule or {}
	local mutation = rules[ruleName]
	if not mutation then
		return
	end

	if mutation.ReplaceWithRandomWeapon then
		self:_giveConfiguredWeapon(gp, mutation)
		return
	end
	self:_mutateBackpackGuns(gp, mutation)
end

function LoadoutMutationComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return LoadoutMutationComponent
