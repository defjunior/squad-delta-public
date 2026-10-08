local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Framework = require(ReplicatedStorage.Modules.Framework)
local ModeRules = require(script.Parent.Parent.Parent.Common.ModeRules)
local Utils = require(script.Parent.Parent.Parent.Common.ModePlayerUtils)

local MurderMysteryComponent = {}
MurderMysteryComponent.__index = MurderMysteryComponent

local COMPONENT_NAME = "MurderMystery"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local function isPlaying(gp)
	return gp and gp.IsPlaying == true and gp.Team and gp.Team.Name ~= "Spectator"
end

local function isAlive(gp)
	if not gp or gp.IsAlive ~= true then
		return false
	end
	if gp.IsDowned == true then
		return false
	end
	local character = gp.CharacterObject
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end
	return true
end

local function pickRandom(list)
	if type(list) ~= "table" or #list <= 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function normalizePhase(phase)
	return string.lower(tostring(phase or ""))
end

local function getById(id)
	return _G.Players and (_G.Players[id] or _G.Players[tonumber(id)] or _G.Players[tostring(id)])
end

local function playerName(gp)
	if not gp then
		return "Unknown"
	end
	return tostring(gp.PlayerName or (gp.PlayerObject and gp.PlayerObject.Name) or "Unknown")
end

local function sendGlobalMessage(ctx, message, color)
	if not (ctx and message and message ~= "") then
		return
	end
	if ctx.events and ctx.events.FireAll then
		ctx.events:FireAll("Server/PersonalSystemMessage", message, color or Color3.new(1, 1, 1))
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local serverFolder = remotes and remotes:FindFirstChild("Server")
	local remote = serverFolder and serverFolder:FindFirstChild("PersonalSystemMessage")
	if remote then
		remote:FireAllClients(message, color or Color3.new(1, 1, 1))
	end
end

local function setRoleValue(gp, roleName)
	if gp and gp.SetValue then
		gp:SetValue("MurderRole", roleName or "Unassigned")
	end
end

function MurderMysteryComponent.new(ctx)
	local self = setmetatable({}, MurderMysteryComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function MurderMysteryComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = ctx.config or {}
	self._rules = self._config.MurderMystery or {}
	self._itemService = Framework.GetService("ItemService")
	self._connections = {}
	self._spawnRuleNames = { match_spawn = true, respawn_spawn = true, round_start = true, warmup_respawn = true }
	self._murdererId = nil
	self._sheriffId = nil
	self._rolesAssigned = false
	self._rolesRevealed = false
	self._phase = "Init"
	self._assignRolesPhase = normalizePhase(self._rules.AssignRolesPhase or "Live")
	self._revealRolesOnEnd = self._rules.RevealRolesOnMatchEnd ~= false
	self._ended = false

	table.insert(self._connections, ctx.Events:On("RoundReset", function(payload)
		self._ended = false
		self._murdererId = nil
		self._sheriffId = nil
		self._rolesAssigned = false
		self._rolesRevealed = false
		for _, gp in ipairs(self:_collectActivePlayers()) do
			setRoleValue(gp, "Unassigned")
		end
		local roundNumber = tonumber(payload and payload.round) or 0
		local assignNow = self._assignRolesPhase == "roundreset"
			or (self._assignRolesPhase == "live" and roundNumber >= 1)
		if assignNow then
			self:_assignRoles()
		end
	end, eventLabel("RoundReset")))

	table.insert(self._connections, ctx.Events:On("RoundPhaseChanged", function(phase)
		self._phase = tostring(phase or self._phase or "Init")
		if not self._rolesAssigned and normalizePhase(phase) == self._assignRolesPhase then
			self:_assignRoles()
		end
	end, eventLabel("RoundPhaseChanged")))

	table.insert(self._connections, ctx.Events:On("PlayerProvisionRuleApplied", function(payload)
		local gp = payload and payload.player
		local ruleName = payload and payload.ruleName
		if gp and self._spawnRuleNames[ruleName] and self._rolesAssigned then
			self:_applyRoleLoadout(gp)
		end
	end, eventLabel("PlayerProvisionRuleApplied")))

	table.insert(self._connections, ctx.Events:On("PlayerEliminated", function()
		self:_evaluateEndConditions()
	end, eventLabel("PlayerEliminated")))

	table.insert(self._connections, ctx.Events:On("RosterUpdated", function()
		self:_evaluateEndConditions()
	end, eventLabel("RosterUpdated")))

	table.insert(self._connections, ctx.Events:On("PlayerLeft", function()
		self:_evaluateEndConditions()
	end, eventLabel("PlayerLeft")))

	table.insert(self._connections, ctx.Events:On("MatchEnded", function()
		self._ended = true
		if self._revealRolesOnEnd then
			self:_revealRoles()
		end
	end, eventLabel("MatchEnded")))
end

function MurderMysteryComponent:_collectActivePlayers()
	local out = {}
	for _, gp in pairs(_G.Players or {}) do
		if isPlaying(gp) then
			table.insert(out, gp)
		end
	end
	return out
end

function MurderMysteryComponent:_assignTeams(players, murderer)
	local attackerName = ModeRules.getTeamByRole(self._ctx, "attackers")
	local defenderName = ModeRules.getTeamByRole(self._ctx, "defenders")
	local attackerTeam = attackerName and Teams:FindFirstChild(attackerName)
	local defenderTeam = defenderName and Teams:FindFirstChild(defenderName)

	if not (attackerTeam and defenderTeam) then
		return
	end

	for _, gp in ipairs(players) do
		if murderer and gp.ID == murderer.ID then
			gp:SetTeam(attackerTeam)
		else
			gp:SetTeam(defenderTeam)
		end
	end
end

function MurderMysteryComponent:_assignRoles()
	local players = self:_collectActivePlayers()
	if #players < 2 then
		self._murdererId = nil
		self._sheriffId = nil
		self._rolesAssigned = false
		return
	end

	local murderer = pickRandom(players)
	if not murderer then
		self._rolesAssigned = false
		return
	end
	self._murdererId = murderer.ID

	local innocents = {}
	for _, gp in ipairs(players) do
		if gp.ID ~= murderer.ID then
			table.insert(innocents, gp)
		end
	end
	local sheriff = pickRandom(innocents)
	self._sheriffId = sheriff and sheriff.ID or nil
	self._rolesAssigned = true

	self:_assignTeams(players, murderer)

	for _, gp in ipairs(players) do
		if gp.ID == self._murdererId then
			setRoleValue(gp, "Murderer")
			Utils.sendPersonalMessage(gp, "[SYSTEM] Role: Murderer. Your knife is lethal.", Color3.new(1, 0.2, 0.2))
		elseif self._sheriffId and gp.ID == self._sheriffId then
			setRoleValue(gp, "Sheriff")
			Utils.sendPersonalMessage(gp, "[SYSTEM] Role: Sheriff. You have the USP.", Color3.new(0.2, 0.8, 1))
		else
			setRoleValue(gp, "Innocent")
			Utils.sendPersonalMessage(gp, "[SYSTEM] Role: Innocent. Survive and identify the murderer.", Color3.new(1, 1, 0.5))
		end
		self:_applyRoleLoadout(gp)
	end
end

function MurderMysteryComponent:_stripGuns(gp, keepSheriffWeapon)
	local sheriffWeapon = self._rules.SheriffWeapon or "USP-SD"
	Utils.removeBackpackItems(gp, function(item, tool)
		local itemType = item and item.ItemType
		local toolName = tool and tool.Name or (item and item.ItemName)
		if keepSheriffWeapon and toolName == sheriffWeapon then
			return false
		end
		if itemType == "Gun" then
			return true
		end
		if tool then
			local order = Framework.GetWeaponOrderType(tool.Name)
			return order == "Primary" or order == "Secondary"
		end
		return false
	end)
end

function MurderMysteryComponent:_applyKnifeDamage(gp)
	local isMurderer = gp and self._murdererId and gp.ID == self._murdererId
	local knifeDamage = tonumber(self._rules.MurdererKnifeDamage) or 45
	local knifeCritDamage = tonumber(self._rules.MurdererKnifeCriticalDamage) or 150
	Utils.forEachTool(gp, function(tool, item)
		local itemType = item and item.ItemType
		local isKnife = itemType == "Knife" or Framework.GetWeaponOrderType(tool.Name) == "Tertiary"
		if not isKnife then
			return
		end
		if isMurderer then
			Utils.setToolWeaponConfig(tool, {
				DAMAGE = knifeDamage,
				CRITICAL_DAMAGE = knifeCritDamage,
			})
		else
			Utils.setToolWeaponConfig(tool, {
				DAMAGE = 0,
				CRITICAL_DAMAGE = 0,
				DAMAGE2 = 0,
			})
		end
	end)
end

function MurderMysteryComponent:_grantSheriffWeapon(gp)
	if not (gp and gp.ID == self._sheriffId and self._itemService) then
		return
	end
	local sheriffWeapon = self._rules.SheriffWeapon or "USP-SD"
	local item = Utils.giveItem(gp, self._itemService, sheriffWeapon, "Gun")
	local tool = Utils.itemTool(item)
	if tool then
		local current = tonumber(self._rules.SheriffAmmoCurrent)
		local reserve = tonumber(self._rules.SheriffAmmoReserve)
		Utils.setToolAmmo(tool, current, reserve)
	end
	Utils.forceEquip(gp, sheriffWeapon)
end

function MurderMysteryComponent:_applyRoleLoadout(gp)
	if not isPlaying(gp) or not self._rolesAssigned then
		return
	end
	local isSheriff = self._sheriffId and gp.ID == self._sheriffId
	self:_stripGuns(gp, isSheriff == true)
	if isSheriff then
		self:_grantSheriffWeapon(gp)
	end
	self:_applyKnifeDamage(gp)
end

function MurderMysteryComponent:_revealRoles()
	if self._rolesRevealed then
		return
	end
	self._rolesRevealed = true
	local murderer = getById(self._murdererId)
	local sheriff = getById(self._sheriffId)
	local message = ("[SYSTEM] Roles revealed - Murderer: %s | Sheriff: %s"):format(playerName(murderer), playerName(sheriff))
	sendGlobalMessage(self._ctx, message, Color3.new(1, 0.93, 0.4))
end

function MurderMysteryComponent:_emitWinner(role, reason, winnerPlayer)
	local winnerTeam = ModeRules.getTeamByRole(self._ctx, role)
	if not winnerTeam then
		return
	end
	self._ended = true
	if self._revealRolesOnEnd then
		self:_revealRoles()
	end
	self._ctx.Events:Emit("MatchEndRequested", {
		winnerTeam = winnerTeam,
		winnerPlayer = winnerPlayer,
		reason = reason,
	})
end

function MurderMysteryComponent:_evaluateEndConditions()
	if self._ended or not self._murdererId or not self._rolesAssigned then
		return
	end

	local murderer = getById(self._murdererId)
	if not isAlive(murderer) then
		self:_emitWinner("defenders", "Murderer eliminated", nil)
		return
	end

	local innocentsAlive = 0
	for _, gp in pairs(_G.Players or {}) do
		if gp and gp.ID ~= self._murdererId and isPlaying(gp) and isAlive(gp) then
			innocentsAlive += 1
		end
	end

	if innocentsAlive <= 0 then
		self:_emitWinner("attackers", "All innocents eliminated", murderer)
	end
end

function MurderMysteryComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return MurderMysteryComponent
