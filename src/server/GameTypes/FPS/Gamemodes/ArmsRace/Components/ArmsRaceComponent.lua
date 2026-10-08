local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Modules.Framework)
local Utils = require(script.Parent.Parent.Parent.Common.ModePlayerUtils)

local ArmsRaceComponent = {}
ArmsRaceComponent.__index = ArmsRaceComponent

local COMPONENT_NAME = "ArmsRace"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function copyAndShuffle(source)
	local out = {}
	for _, value in ipairs(source or {}) do
		table.insert(out, value)
	end
	for i = #out, 2, -1 do
		local j = math.random(1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function isPlaying(gp)
	return gp and gp.IsPlaying == true
end

function ArmsRaceComponent.new(ctx)
	local self = setmetatable({}, ArmsRaceComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function ArmsRaceComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = ctx.config or {}
	self._rules = self._config.ArmsRace or {}
	self._itemService = Framework.GetService("ItemService")
	self._connections = {}
	self._progress = {}
	self._killstreak = {}
	self._spawnRuleNames = { match_spawn = true, respawn_spawn = true }
	self._weaponOrder = copyAndShuffle(self._rules.WeaponPool)

	table.insert(self._connections, ctx.Events:On("PlayerProvisionRuleApplied", function(payload)
		local gp = payload and payload.player
		local ruleName = payload and payload.ruleName
		if gp and self._spawnRuleNames[ruleName] then
			self:_ensurePlayerWeapon(gp)
		end
	end, eventLabel("PlayerProvisionRuleApplied")))

	table.insert(self._connections, ctx.Events:On("PlayerEliminated", function(payload)
		self:_onPlayerEliminated(payload)
	end, eventLabel("PlayerEliminated")))
end

function ArmsRaceComponent:_ensureProgress(gp)
	if not gp then
		return 1
	end
	local current = self._progress[gp.ID]
	if current == nil then
		current = 1
		self._progress[gp.ID] = current
	end
	return current
end

function ArmsRaceComponent:_weaponNameForPlayer(gp)
	local index = self:_ensureProgress(gp)
	return self._weaponOrder[index], index
end

function ArmsRaceComponent:_stripGuns(gp)
	Utils.removeBackpackItems(gp, function(item, tool)
		local itemType = item and item.ItemType
		if itemType == "Gun" then
			return true
		end
		if tool and Framework.GetWeaponOrderType(tool.Name) == "Primary" then
			return true
		end
		if tool and Framework.GetWeaponOrderType(tool.Name) == "Secondary" then
			return true
		end
		return false
	end)
end

function ArmsRaceComponent:_grantGrenade(gp, itemName)
	if not (gp and itemName and self._itemService) then
		return
	end
	local item = Utils.giveItem(gp, self._itemService, itemName, "Grenade")
	if item then
		Utils.sendPersonalMessage(gp, ("[SYSTEM] Killstreak reward: %s"):format(itemName), Color3.new(0.2, 0.85, 1))
	end
end

function ArmsRaceComponent:_grantProgressWeapon(gp)
	if not (gp and self._itemService) then
		return
	end
	local weaponName, index = self:_weaponNameForPlayer(gp)
	if not weaponName then
		return
	end

	self:_stripGuns(gp)
	local item = Utils.giveItem(gp, self._itemService, weaponName, "Gun")
	if not item then
		return
	end

	if self._rules.ForceEquip ~= false then
		Utils.forceEquip(gp, weaponName)
	end

	Utils.sendPersonalMessage(
		gp,
		("[SYSTEM] Arms Race [%d/%d]: %s"):format(index, #self._weaponOrder, weaponName),
		Color3.new(0.2, 1, 0.45)
	)
end

function ArmsRaceComponent:_ensurePlayerWeapon(gp)
	if not isPlaying(gp) then
		return
	end
	self:_ensureProgress(gp)
	self:_grantProgressWeapon(gp)
end

function ArmsRaceComponent:_advancePlayer(gp)
	if not gp then
		return false
	end
	local current = self:_ensureProgress(gp)
	local nextIndex = current + 1
	self._progress[gp.ID] = nextIndex
	return nextIndex > #self._weaponOrder
end

function ArmsRaceComponent:_onPlayerEliminated(payload)
	if not payload then
		return
	end
	local killer = payload.killer
	local victim = payload.victim
	if victim then
		self._killstreak[victim.ID] = 0
	end
	if not killer then
		return
	end

	local streak = (self._killstreak[killer.ID] or 0) + 1
	self._killstreak[killer.ID] = streak

	local rewardName = self._rules.KillstreakGrenades and self._rules.KillstreakGrenades[streak]
	if rewardName then
		self:_grantGrenade(killer, rewardName)
	end

	local done = self:_advancePlayer(killer)
	if done then
		self._ctx.Events:Emit("MatchEndRequested", {
			winnerPlayer = killer,
			reason = "All weapons cycled",
		})
		return
	end

	if killer.IsAlive == true then
		self:_grantProgressWeapon(killer)
	end
end

function ArmsRaceComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return ArmsRaceComponent
