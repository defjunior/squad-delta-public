local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = require(ReplicatedStorage.Modules.Framework)
local ModeRules = require(script.Parent.Parent.Parent.Common.ModeRules)
local Utils = require(script.Parent.Parent.Parent.Common.ModePlayerUtils)

local HideAndSeekComponent = {}
HideAndSeekComponent.__index = HideAndSeekComponent

local COMPONENT_NAME = "HideAndSeek"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function isPlaying(gp)
	return gp and gp.IsPlaying == true and gp.Team and gp.Team.Name ~= "Spectator"
end

local function isAttacker(ctx, gp)
	if not gp or not gp.Team then
		return false
	end
	local attackerTeamName = ModeRules.getTeamByRole(ctx, "attackers")
	return gp.Team.Name == attackerTeamName
end

local function emitMatchEnd(ctx, winnerRole, reason)
	local winnerTeam = ModeRules.getTeamByRole(ctx, winnerRole)
	if not winnerTeam then
		return
	end
	ctx.Events:Emit("MatchEndRequested", {
		reason = reason,
		winnerTeam = winnerTeam,
	})
end

local function setCombatFlags(gp, canUse)
	if not gp then
		return
	end
	gp:SetValue("CanUse", canUse == true)
	gp:SetValue("CanReload", canUse == true)
end

local function canDamageWithKnife(ctx, gp, rolesReversed)
	local attacker = isAttacker(ctx, gp)
	if rolesReversed then
		return attacker
	end
	return not attacker
end

function HideAndSeekComponent.new(ctx)
	local self = setmetatable({}, HideAndSeekComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function HideAndSeekComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = ctx.config or {}
	self._rules = self._config.HideAndSeek or {}
	self._connections = {}
	self._spawnRuleNames = { match_spawn = true, respawn_spawn = true }
	self._live = false
	self._rolesReversed = false
	self._bombPlanted = false
	self._matchEnded = false
	self._hideTimerToken = 0

	table.insert(self._connections, ctx.Events:On("RoundReset", function()
		self._live = false
		self._rolesReversed = false
		self._bombPlanted = false
		self._matchEnded = false
		self._hideTimerToken += 1
	end, eventLabel("RoundReset")))

	table.insert(self._connections, ctx.Events:On("RoundPhaseChanged", function(phase)
		if phase == "Live" then
			self._live = true
			self._rolesReversed = false
			self._bombPlanted = false
			self:_applyRulesToAllPlayers()
			self:_startHideTimer()
		else
			self._live = false
		end
	end, eventLabel("RoundPhaseChanged")))

	table.insert(self._connections, ctx.Events:On("PlayerProvisionRuleApplied", function(payload)
		local gp = payload and payload.player
		local ruleName = payload and payload.ruleName
		if gp and self._spawnRuleNames[ruleName] then
			self:_applyRulesToPlayer(gp)
		end
	end, eventLabel("PlayerProvisionRuleApplied")))

	table.insert(self._connections, ctx.Events:On("ObjectiveStateChanged", function(data)
		self:_onObjectiveStateChanged(data)
	end, eventLabel("ObjectiveStateChanged")))

	table.insert(self._connections, ctx.Events:On("RosterUpdated", function(roster)
		self:_checkEliminationWin(roster)
	end, eventLabel("RosterUpdated")))

	table.insert(self._connections, ctx.Events:On("MatchEnded", function()
		self._matchEnded = true
		self._hideTimerToken += 1
	end, eventLabel("MatchEnded")))
end

function HideAndSeekComponent:_applyRulesToKnife(gp)
	local lethalKnife = canDamageWithKnife(self._ctx, gp, self._rolesReversed)
	Utils.forEachTool(gp, function(tool, item)
		local itemType = item and item.ItemType
		local isKnife = itemType == "Knife" or Framework.GetWeaponOrderType(tool.Name) == "Tertiary"
		if not isKnife then
			return
		end
		if lethalKnife then
			Utils.restoreToolWeaponConfig(tool, { "DAMAGE", "CRITICAL_DAMAGE", "DAMAGE2" })
		else
			Utils.setToolWeaponConfig(tool, {
				DAMAGE = 0,
				CRITICAL_DAMAGE = 0,
				DAMAGE2 = 0,
			})
		end
	end)
end

function HideAndSeekComponent:_applyRulesToPlayer(gp)
	if not isPlaying(gp) then
		return
	end
	setCombatFlags(gp, true)
	self:_applyRulesToKnife(gp)
end

function HideAndSeekComponent:_applyRulesToAllPlayers()
	for _, gp in pairs(_G.Players or {}) do
		self:_applyRulesToPlayer(gp)
	end
end

function HideAndSeekComponent:_startHideTimer()
	local duration = math.max(1, math.floor(tonumber(self._rules.HideDuration) or 120))
	self._hideTimerToken += 1
	local myToken = self._hideTimerToken
	task.spawn(function()
		for _ = duration, 0, -1 do
			if not self._mounted or self._matchEnded or not self._live or self._bombPlanted then
				return
			end
			if myToken ~= self._hideTimerToken then
				return
			end
			task.wait(1)
		end
		if not self._mounted or self._matchEnded or self._bombPlanted then
			return
		end
		emitMatchEnd(self._ctx, "attackers", "Attackers survived until timeout")
	end)
end

function HideAndSeekComponent:_onObjectiveStateChanged(data)
	if not data or not data.stateKey or self._matchEnded then
		return
	end
	local stateKey = string.lower(tostring(data.stateKey))
	if stateKey == "planted" then
		self._bombPlanted = true
		self._rolesReversed = true
		self:_applyRulesToAllPlayers()
		local message = self._rules.RoleSwapMessage
		if message and self._ctx.events and self._ctx.events.FireAll then
			self._ctx.events:FireAll("Server/PersonalSystemMessage", message, Color3.new(1, 0.93, 0.4))
		end
		return
	end
	if stateKey == "detonated" then
		emitMatchEnd(self._ctx, "defenders", "Attackers failed before detonation")
		return
	end
	if stateKey == "defused" then
		emitMatchEnd(self._ctx, "defenders", "Bomb defused")
	end
end

function HideAndSeekComponent:_checkEliminationWin(roster)
	if not self._live or self._matchEnded or not roster then
		return
	end
	local attackersAlive = roster.aliveAttackers and #roster.aliveAttackers or 0
	local defendersAlive = roster.aliveDefenders and #roster.aliveDefenders or 0
	if attackersAlive <= 0 then
		emitMatchEnd(self._ctx, "defenders", "Attackers eliminated")
		return
	end
	if defendersAlive <= 0 then
		emitMatchEnd(self._ctx, "attackers", "Defenders eliminated")
	end
end

function HideAndSeekComponent:Dismount()
	self._hideTimerToken += 1
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return HideAndSeekComponent
