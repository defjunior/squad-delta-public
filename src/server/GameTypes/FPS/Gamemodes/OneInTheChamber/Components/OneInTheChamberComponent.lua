local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Modules.Framework)
local Utils = require(script.Parent.Parent.Parent.Common.ModePlayerUtils)

local OneInTheChamberComponent = {}
OneInTheChamberComponent.__index = OneInTheChamberComponent

local COMPONENT_NAME = "OneInTheChamber"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function getUspTool(gp)
	local found = nil
	Utils.forEachTool(gp, function(tool, item)
		local itemName = item and item.ItemName or tool.Name
		if itemName == "USP-SD" or tool.Name == "USP-SD" then
			found = tool
		end
	end)
	return found
end

function OneInTheChamberComponent.new(ctx)
	local self = setmetatable({}, OneInTheChamberComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function OneInTheChamberComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = ctx.config or {}
	self._itemService = Framework.GetService("ItemService")
	self._connections = {}
	self._spawnRuleNames = { match_spawn = true, respawn_spawn = true }

	table.insert(self._connections, ctx.Events:On("PlayerProvisionRuleApplied", function(payload)
		local gp = payload and payload.player
		local ruleName = payload and payload.ruleName
		if gp and self._spawnRuleNames[ruleName] then
			self:_applyLoadout(gp)
		end
	end, eventLabel("PlayerProvisionRuleApplied")))

	table.insert(self._connections, ctx.Events:On("PlayerEliminated", function(payload)
		local killer = payload and payload.killer
		if killer then
			self:_grantBullet(killer)
		end
	end, eventLabel("PlayerEliminated")))
end

function OneInTheChamberComponent:_applyOitcWeaponConfig(tool)
	if not tool then
		return
	end
	Utils.setToolWeaponConfig(tool, {
		DAMAGE = 100,
		CRITICAL_DAMAGE = 300,
	})
end

function OneInTheChamberComponent:_ensureWeapon(gp)
	local usp = getUspTool(gp)
	if usp then
		return usp
	end
	if not self._itemService then
		return nil
	end
	local item = Utils.giveItem(gp, self._itemService, "USP-SD", "Gun")
	return Utils.itemTool(item)
end

function OneInTheChamberComponent:_applyLoadout(gp)
	local usp = self:_ensureWeapon(gp)
	if not usp then
		return
	end
	self:_applyOitcWeaponConfig(usp)
	Utils.setToolAmmo(usp, 1, 0)
end

function OneInTheChamberComponent:_grantBullet(gp)
	local usp = self:_ensureWeapon(gp)
	if not usp then
		return
	end
	self:_applyOitcWeaponConfig(usp)
	local ammo = usp:FindFirstChild("Ammo")
	local current = ammo and ammo:FindFirstChild("Current")
	local reserve = ammo and ammo:FindFirstChild("Reserve")
	if current then
		current.Value = math.clamp((tonumber(current.Value) or 0) + 1, 0, 12)
	end
	if reserve then
		reserve.Value = 0
	end
	Utils.sendPersonalMessage(gp, "[SYSTEM] Kill confirmed: +1 bullet.", Color3.new(0.2, 1, 0.45))
end

function OneInTheChamberComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return OneInTheChamberComponent
