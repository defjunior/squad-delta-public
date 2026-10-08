local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Framework = _G.Framework
local Classes = game.ServerScriptService.Classes
local GlobalEnum = require(game.ReplicatedStorage.Modules.Data.GlobalEnum)
local Item = require(Classes:WaitForChild("Item"))
local ContainerService = require(ReplicatedStorage.Modules.Services.ContainerService)

_G.Items = {}

local Service = {}
Service.__index = Service

local ITEM_SERVER_BY_CREATION_TYPE = {
	Gun = "GunServer",
	Grenade = "GrenadeServer",
	Knife = "MeleeServer",
	PDA = "PDAServer",
	["UHE-4"] = "UHEServer",
}

local ITEM_SERVER_BY_WEAPON_TYPE = {
	PS = "GunServer",
	SMG = "GunServer",
	SR = "GunServer",
	AR = "GunServer",
	SH = "GunServer",
	GR = "GrenadeServer",
	TR = "MeleeServer",
}

local ITEM_SERVER_BY_ITEM_NAME = {
	["PDA"] = "PDAServer",
	["UHE-4"] = "UHEServer",
}

local function resolveItemServerName(model, inheritance)
	local creationType = inheritance and inheritance[1]
	if creationType and ITEM_SERVER_BY_CREATION_TYPE[creationType] then
		return ITEM_SERVER_BY_CREATION_TYPE[creationType]
	end

	local itemName = model and model.Name
	if itemName and ITEM_SERVER_BY_ITEM_NAME[itemName] then
		return ITEM_SERVER_BY_ITEM_NAME[itemName]
	end

	local weaponType = itemName and Framework.GetWeaponType(itemName)
	if weaponType and ITEM_SERVER_BY_WEAPON_TYPE[weaponType] then
		return ITEM_SERVER_BY_WEAPON_TYPE[weaponType]
	end

	return nil
end

local function prepareToolItemServer(tool, model, inheritance)
	if not tool or not tool:IsA("Tool") then
		return
	end

	local serverName = resolveItemServerName(model, inheritance)
	if not serverName then
		return
	end

	local itemServers = ServerStorage:FindFirstChild("ItemServers")
	if not itemServers then
		warn("ItemService: ServerStorage.ItemServers was not found; skipping runtime item server injection.")
		return
	end

	local template = itemServers:FindFirstChild(serverName)
	if not template then
		warn(("ItemService: Missing item server template '%s' in ServerStorage.ItemServers."):format(serverName))
		return
	end

	local existing = tool:FindFirstChild(serverName)
	if existing then
		existing:Destroy()
	end

	local clonedServer = template:Clone()
	clonedServer.Parent = tool
	clonedServer.Enabled = true
end

function Service:NewItem(Model, ...)
	local Inheritance = { ... }
	local ItemModule = Classes:WaitForChild("Item")
	local CurrentType = ItemModule
	for _, d in ipairs(Inheritance) do
		local token = tostring(d)
		local nextType = CurrentType:FindFirstChild(token)
		if not nextType and CurrentType == ItemModule then
			local normalized = token
			local orderType = Framework.GetWeaponOrderType(token)
			if orderType == "Primary" or orderType == "Secondary" then
				normalized = "Gun"
			elseif orderType == "Tertiary" then
				normalized = "Knife"
			elseif orderType == "Grenade" then
				normalized = "Grenade"
			elseif token == "UHE4" then
				normalized = "UHE-4"
			end
			nextType = ItemModule:FindFirstChild(normalized)
		end
		if not nextType then
			error(("ItemService: Unknown item inheritance '%s' for model '%s'"):format(token, tostring(Model and Model.Name)))
		end
		CurrentType = nextType
	end
	local Mod = require(CurrentType)
	local newItem = Mod:New(Model)
	if newItem and newItem.Tool then
		prepareToolItemServer(newItem.Tool, Model, Inheritance)
	end
	return newItem
end

function safeFloatDifference(a, b)
	local difference = a - b

	local epsilon = 1e-10

	if math.abs(difference - math.floor(difference + 0.5)) < epsilon then
		difference = math.floor(difference + 0.5)
	end

	return tonumber(string.format("%.2f", difference))
end

local function normalizeTeam(team)
	if team == "BLU" then
		return "BLU"
	end
	return "RED"
end

local function resolveGameplayPlayer(player)
	if not player then
		return nil
	end
	if _G.Players then
		local byId = _G.Players[player.UserId]
		if byId then
			return byId
		end
	end
	local ps = Framework.GetService("PlayerService")
	return ps and ps:GetPlayerFromName(player.Name) or nil
end

local function resolveSavedDataFolder(player, gameplayPlayer)
	if player then
		local direct = player:FindFirstChild("SavedData")
		if direct then
			return direct
		end
	end
	local playerData = gameplayPlayer and gameplayPlayer.PlayerData
	local savedData = playerData and playerData:FindFirstChild("SavedData")
	if savedData then
		return savedData
	end
	local storage = ReplicatedStorage:FindFirstChild("PlayerLikeStorage")
	local replicatedPlayerData = storage and player and storage:FindFirstChild(tostring(player.UserId))
	return replicatedPlayerData and replicatedPlayerData:FindFirstChild("SavedData")
end

local function applySkinToEquippedItem(gameplayPlayer, weaponName, skinName, teamName)
	if not gameplayPlayer or not gameplayPlayer.CurrentTool then
		return
	end
	if gameplayPlayer.Team and gameplayPlayer.Team.Name ~= teamName then
		return
	end

	local item = gameplayPlayer.CurrentTool
	if item.ItemName ~= weaponName then
		return
	end
	local tool = item.CurrentTool
	if typeof(tool) ~= "Instance" then
		return
	end

	local function apply(model)
		if not model then
			return
		end
		local applied = model:FindFirstChild("AppliedSkin")
		if applied then
			applied:Destroy()
		end
		local charm = model:FindFirstChild("WeaponCharm")
		if charm then
			charm:Destroy()
		end
		if skinName ~= "Stock" and skinName ~= "" then
			ContainerService.ApplySkin(model, weaponName, skinName)
		end
	end

	local character = tool.Parent
	local model = tool:FindFirstChild("WeaponModel")
		or (character and character:FindFirstChild("WeaponModel"))
	if model then
		local main = model:FindFirstChild("Main")
		local skin = main and main:FindFirstChild("Skin")
		if skin then
			skin.Value = skinName
		end
		apply(model)
		apply(tool:FindFirstChild("WeaponModel2")
			or (character and character:FindFirstChild("WeaponModel2")))
	end
end

function Service:AccessorySlotEquip(player, id, accessoryType, slot, team)
	team = normalizeTeam(team)
	local stringKey = accessoryType .. slot
	local gPlayer = resolveGameplayPlayer(player)
	local savedDataFolder = resolveSavedDataFolder(player, gPlayer)
	if not (gPlayer and savedDataFolder) then
		return false
	end
	local loadout = savedDataFolder:FindFirstChild(team .. "Loadout")
	local characterSlots = loadout and loadout:FindFirstChild("CharacterSlots")
	local found = characterSlots and characterSlots:FindFirstChild(stringKey)
	local inventory = gPlayer.SavedData and gPlayer.SavedData.Inventory
	if not inventory then
		return false
	end

	local index
	for a, b in pairs(inventory) do
		local split = string.split(b, ":")
		if string.match(split[3], id) then
			index = a
		end
	end

	if not index then return false end

	if found then
		found.Value = id
		gPlayer:SetValue(stringKey, id, "SavedData", team .. "Loadout", "CharacterSlots")
		return true
	else
		return false
	end
end

function Service:TauntSlotEquip(player, id, slot)
	slot = math.clamp(slot, 1, 5)
	local stringKey = "Slot" .. slot
	local gPlayer = resolveGameplayPlayer(player)
	local savedDataFolder = resolveSavedDataFolder(player, gPlayer)
	if not (gPlayer and savedDataFolder) then
		return false
	end
	local taunts = savedDataFolder:FindFirstChild("Taunts")
	local found = taunts and taunts:FindFirstChild(stringKey)
	local inventory = gPlayer.SavedData and gPlayer.SavedData.Inventory
	if not inventory then
		return false
	end

	local index
	for a, b in pairs(inventory) do
		local split = string.split(b, ":")
		if string.match(split[3], id) then
			index = a
		end
	end

	if not index then return false end

	if found then
		found.Value = id
		gPlayer:SetValue(stringKey, id, "SavedData", "Taunts")
		return true
	else
		return false
	end
end

function Service:ModelSlotEquip(player, id, team)
	team = normalizeTeam(team)
	local gPlayer = resolveGameplayPlayer(player)
	local savedDataFolder = resolveSavedDataFolder(player, gPlayer)
	if not (gPlayer and savedDataFolder) then
		return false
	end
	local loadout = savedDataFolder:FindFirstChild(team .. "Loadout")
	local slot = loadout and loadout:FindFirstChild("CharacterModel")
	local split = string.split(id, "")
	local typeTable = {
		["r"] = "RED",
		["b"] = "BLU"
	}
	local inventory = gPlayer.SavedData and gPlayer.SavedData.Inventory
	if not inventory then
		return false
	end

	local index
	for a, b in pairs(inventory) do
		local split2 = string.split(b, ":")
		if string.match(split2[3], id) then
			index = a
		end
	end

	if not index then return false end

	if not typeTable[split[1]] then
		if slot then
			slot.Value = id
			gPlayer:SetValue("CharacterModel", id, "SavedData", team .. "Loadout")
			return true
		end
	elseif typeTable[split[1]] == team then
		if slot then
			slot.Value = id
			gPlayer:SetValue("CharacterModel", id, "SavedData", team .. "Loadout")
			return true
		end
	end

	return false
end

function Service:ModelSlotClear(player, model)
	local gPlayer = resolveGameplayPlayer(player)
	local savedDataFolder = resolveSavedDataFolder(player, gPlayer)
	if not (gPlayer and savedDataFolder) then
		return false
	end

	local team = "RED"
	local bluLoadout = savedDataFolder:FindFirstChild("BLULoadout")
	local redLoadout = savedDataFolder:FindFirstChild("REDLoadout")
	local bluModel = bluLoadout and bluLoadout:FindFirstChild("CharacterModel")
	local redModel = redLoadout and redLoadout:FindFirstChild("CharacterModel")
	if bluModel and tostring(bluModel.Value) == tostring(model) then
		team = "BLU"
	elseif redModel and tostring(redModel.Value) == tostring(model) then
	else
		if redModel then
			redModel.Value = "None"
		end
		if bluModel then
			bluModel.Value = "None"
		end
		gPlayer:SetValue("CharacterModel", "None", "SavedData", "RED" .. "Loadout")
		gPlayer:SetValue("CharacterModel", "None", "SavedData", "BLU" .. "Loadout")
		return true
	end
	local loadout = savedDataFolder:FindFirstChild(team .. "Loadout")
	local slot = loadout and loadout:FindFirstChild("CharacterModel")
	if slot then
		slot.Value = "None"
		gPlayer:SetValue("CharacterModel", "None", "SavedData", team .. "Loadout")
		return true
	else
		return false
	end
end

function Service:AccessorySlotClear(player, id)
	local found = false
	local gPlayer = resolveGameplayPlayer(player)
	local savedDataFolder = resolveSavedDataFolder(player, gPlayer)
	if not (gPlayer and savedDataFolder) then
		return false
	end
	local bluSlots = savedDataFolder:FindFirstChild("BLULoadout")
	bluSlots = bluSlots and bluSlots:FindFirstChild("CharacterSlots")
	local redSlots = savedDataFolder:FindFirstChild("REDLoadout")
	redSlots = redSlots and redSlots:FindFirstChild("CharacterSlots")
	for _, b in pairs(bluSlots and bluSlots:GetChildren() or {}) do
		if b.Value == id then
			found = true
			b.Value = ""
			gPlayer:SetValue(b.Name, "", "SavedData", "BLULoadout", "CharacterSlots")
		end
	end
	for _, b in pairs(redSlots and redSlots:GetChildren() or {}) do
		if b.Value == id then
			found = true
			b.Value = ""
			gPlayer:SetValue(b.Name, "", "SavedData", "REDLoadout", "CharacterSlots")
		end
	end
	if found == true then
		return true
	else
		return false
	end
end

function Service:SkinSlotClear(player, weapon)
	local gPlayer = resolveGameplayPlayer(player)
	local savedDataFolder = resolveSavedDataFolder(player, gPlayer)
	if not (gPlayer and savedDataFolder) then
		return false
	end
	local redLoadout = savedDataFolder:FindFirstChild("REDLoadout")
	local bluLoadout = savedDataFolder:FindFirstChild("BLULoadout")
	if Framework.GetWeaponType(weapon) ~= "TR" then
		local slot = redLoadout and redLoadout:FindFirstChild(weapon)
		if slot then
			slot.Value = "Stock"
		end
		slot = bluLoadout and bluLoadout:FindFirstChild(weapon)
		if slot then
			slot.Value = "Stock"
		end
		gPlayer:SetValue(weapon, "Stock", "SavedData", "RED" .. "Loadout")
		gPlayer:SetValue(weapon, "Stock", "SavedData", "BLU" .. "Loadout")
	else
		local translatedType
		for a, b in pairs(GlobalEnum.KnifeType) do
			if b == weapon then
				translatedType = a
			end
		end
		local slot = redLoadout and redLoadout:FindFirstChild("KnifeType")
		if slot then
			slot.Value = 1
		end
		slot = bluLoadout and bluLoadout:FindFirstChild("KnifeType")
		if slot then
			slot.Value = 1
		end
		slot = bluLoadout and bluLoadout:FindFirstChild("KnifeSkin")
		if slot then
			slot.Value = "Stock"
		end
		slot = redLoadout and redLoadout:FindFirstChild("KnifeSkin")
		if slot then
			slot.Value = "Stock"
		end
	end

	return true
end

function Service:SkinSlotEquip(player, id, team, weapon)
	team = normalizeTeam(team)
	local gPlayer = resolveGameplayPlayer(player)
	local savedDataFolder = resolveSavedDataFolder(player, gPlayer)
	if not (gPlayer and savedDataFolder) then
		return false
	end
	local inventory = gPlayer.SavedData and gPlayer.SavedData.Inventory
	if not inventory then
		return false
	end

	local index
	local skinName
	for a, b in pairs(inventory) do
		local hasFour = true
		local b2 = string.gsub(b, "%-", "")
		local split2 = string.split(b2, ":")

		skinName = split2[4]
		if #split2 > 4 then
			for i = 5, #split2, 1 do
				skinName = skinName .. ":" .. split2[i]
			end
		end

		if not split2[4] then hasFour = false end
		local usingWeapon = weapon
		usingWeapon, _ = string.gsub(usingWeapon, "%-", "")
		if hasFour then
			if string.match(split2[3] .. ":" .. skinName, usingWeapon .. ":" .. id) then
				index = a
				break
			end
		end
	end

	if not index then return false end

	if Framework.GetWeaponType(weapon) ~= "TR" then
		local loadout = savedDataFolder:FindFirstChild(team .. "Loadout")
		local slot = loadout and loadout:FindFirstChild(weapon)

		if slot then
			slot.Value = skinName
			gPlayer:SetValue(weapon, skinName, "SavedData", team .. "Loadout")
			applySkinToEquippedItem(gPlayer, weapon, skinName, team)
			return true
		end

		return false
	else
		local translatedType
		for a, b in pairs(GlobalEnum.KnifeType) do
			if b == weapon then
				translatedType = a
			end
		end
		local loadout = savedDataFolder:FindFirstChild(team .. "Loadout")
		local slot = loadout and loadout:FindFirstChild("KnifeType")
		if slot then
			slot.Value = translatedType
			local slot2 = loadout and loadout:FindFirstChild("KnifeSkin")
			if slot2 then
				slot2.Value = skinName
			end
			gPlayer:SetValue("KnifeType", translatedType, "SavedData", team .. "Loadout")
			gPlayer:SetValue("KnifeSkin", skinName, "SavedData", team .. "Loadout")
			applySkinToEquippedItem(gPlayer, weapon, skinName, team)

			return true
		end
		return false
	end
end

function Service:DropItem(player, itemId, options)
	local forceDrop = type(options) == "table" and options.force == true
	local gPlayer = typeof(player) == "Object" and player or _G.Players[player.UserId]
	if not gPlayer then
		return
	end
	if not forceDrop and not gPlayer.IsAlive then return end
	if _G.Items[itemId] and table.find(gPlayer.Backpack, _G.Items[itemId]) then
		local model, proxPrompt = _G.Items[itemId]:CreateDrop(gPlayer.ID)
		_G.Items[itemId]:Unequip(gPlayer.ID)
		if not proxPrompt then return end
		local toolId = Framework.GetWeaponOrderType(_G.Items[itemId].ItemName)
		proxPrompt.ActionText = "Equip"
		proxPrompt.ObjectText = _G.Items[itemId].ItemName
		proxPrompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		proxPrompt.Style = Enum.ProximityPromptStyle.Default
		proxPrompt.ClickablePrompt = false
		proxPrompt.MaxActivationDistance = 4.5
		proxPrompt.RequiresLineOfSight = false
		local weaponType = Framework.GetWeaponType(_G.Items[itemId].ItemName)
		if weaponType == "PS" then
			proxPrompt.HoldDuration = 0.01
		elseif weaponType == "TR" then
			proxPrompt.HoldDuration = 0.01
		elseif weaponType == "SMG" then
			proxPrompt.HoldDuration = 0.25
		elseif weaponType == "AR" then
			proxPrompt.HoldDuration = 0.45
		elseif weaponType == "SR" then
			proxPrompt.HoldDuration = 0.65
		end
		local hh

		if toolId == "UHE-4" then
			hh = Instance.new("Highlight", model)
			hh.DepthMode = Enum.HighlightDepthMode.Occluded
			hh.FillTransparency = 1
			hh.OutlineColor = Color3.new(1, 0.968627, 0)
			_G.BombDropped(true)
			for _, v in pairs(model["UHE-4"]:GetChildren()) do
				if v:IsA("BasePart") then
					v.CollisionGroup = "Items"
					v.CanCollide = true
					v.CustomPhysicalProperties = PhysicalProperties.new(10, 2, 0, 5, 0)
				end
			end
		else
			hh = Instance.new("Highlight", model)
			hh.DepthMode = Enum.HighlightDepthMode.Occluded
			hh.FillTransparency = 1
			hh.OutlineColor = Color3.new(1, 1, 1)
		end

		local proxEnabled = true
		local onPickup = function(tPlayer)
			local userId = tPlayer and tPlayer.UserId
			local gp = userId ~= nil and _G.Players[userId] or nil
			local droppedItem = _G.Items[itemId]
			if not (gp and droppedItem and droppedItem == _G.Items[itemId] and proxEnabled == true) then
				return
			end
			if gp.IsAlive ~= true or not model.Parent or not proxPrompt.Parent or not MPart.Parent then
				return
			end
			if table.find(gp.Backpack, droppedItem) then
				return
			end

			local root = gp.CharacterObject and gp.CharacterObject:FindFirstChild("HumanoidRootPart")
			local maxDistance = (proxPrompt.MaxActivationDistance or 4.5) + 2
			if not root or (root.Position - MPart.Position).Magnitude > maxDistance then
				return
			end

			proxEnabled = false
			proxPrompt.Enabled = false
			local committed = false
			local ok, err = pcall(function()
				local hasConflict = false
				if toolId ~= "Grenade" then
					for _, v in pairs(gp.Backpack) do
						if Framework.GetWeaponOrderType(v.Tool.Name) == toolId and v.ID ~= itemId then
							if toolId == "Tertiary" then
								self:DropItem(gp.PlayerObject or tPlayer, v.ID, { force = true })
							else
								hasConflict = true
							end
							break
						end
					end
				else
					local grenadeCount = 0
					for _, v in pairs(gp.Backpack) do
						if Framework.GetWeaponOrderType(v.Tool.Name) == toolId then
							grenadeCount += 1
						end
					end
					hasConflict = grenadeCount >= 3
				end
				if hasConflict then
					return
				end
				if not model.Parent or _G.Items[itemId] ~= droppedItem or table.find(gp.Backpack, droppedItem) then
					return
				end
				if toolId == "UHE-4" then
					_G.BombDropped(false)
				end
				hh:Destroy()
				gp:AddItemToBackpack(droppedItem)
				committed = true
				proxPrompt:Destroy()
				model:Destroy()
				local eventHandler = game.ServerScriptService:FindFirstChild("EventHandler")
				local pickupSound = eventHandler and eventHandler:FindFirstChild("Pickup")
				if pickupSound and gp.CharacterObject and gp.CharacterObject:FindFirstChild("HumanoidRootPart") then
					Framework:PlayHitSound(pickupSound, gp.CharacterObject.HumanoidRootPart, 1)
				end
			end)
			if not ok then
				warn(("[ItemService] Pickup failed for %s (%s): %s"):format(tostring(gp.PlayerName), tostring(itemId), tostring(err)))
			end
			if not committed and proxPrompt.Parent and model.Parent then
				proxEnabled = true
				proxPrompt.Enabled = true
			end
		end
		proxPrompt.Triggered:Connect(onPickup)
		MPart.Touched:Connect(function(part)
			local fModel = part.Parent:IsA("Model") and part.Parent or false
			if fModel then
				if fModel:FindFirstChild("Humanoid") then
					if fModel:FindFirstChild("IsBot") then
						onPickup({ UserId = fModel.Name })
					end
				end
			end
		end)

		return true
	end
	return false
end

function Service:EquipItem(player, itemId)
	local gp = _G.Players[player.UserId]
	if not gp then return end
	if gp.IsAlive ~= true then
		return
	end
	if gp.IsDowned == true then
		return
	end
	local foundBP = ReplicatedStorage.Backpacks[gp.ID]
	if foundBP then
		local ok, err = pcall(function()
			local item = foundBP:FindFirstChild(itemId)
			if item then
				local gItem = _G.Items[itemId]
				if gItem then
					gItem:Equip(gp.ID)
				end
			end
		end)
		if not ok then
			warn(("[ItemService] EquipItem failed for %s (%s): %s"):format(tostring(gp.PlayerName), tostring(itemId), tostring(err)))
		end
	end
end

function Service:UnequipItem(player, itemId)
	local gp = _G.Players[player.UserId]
	if not gp then return end
	local foundBP = ReplicatedStorage.Backpacks[gp.ID]
	if foundBP then
		local item = foundBP:FindFirstChild(itemId)
		if item then
			local gItem = _G.Items[itemId]
			if gItem and gItem.Unequip then
				local ok, err = pcall(function()
					gItem:Unequip(gp.ID)
				end)
				if not ok then
					warn(("[ItemService] UnequipItem failed for %s (%s): %s"):format(tostring(gp.PlayerName), tostring(itemId), tostring(err)))
				end
			end
		end
	end
end

function Service:RegisterEndpoints(eventService)
	eventService:RegisterFunction("Items/AccessorySlotEquip", function(ctx, id, accessoryType, slot, team)
		return self:AccessorySlotEquip(ctx.player, id, accessoryType, slot, team)
	end, {
		guard = { gp = true, inGame = false, alive = false, character = false },
	})

	eventService:RegisterFunction("Items/TauntSlotEquip", function(ctx, id, slot)
		return self:TauntSlotEquip(ctx.player, id, slot)
	end, {
		guard = { gp = true, inGame = false, alive = false, character = false },
	})

	eventService:RegisterFunction("Items/ModelSlotEquip", function(ctx, id, team)
		return self:ModelSlotEquip(ctx.player, id, team)
	end, {
		guard = { gp = true, inGame = false, alive = false, character = false },
	})

	eventService:RegisterFunction("Items/ModelSlotClear", function(ctx, model)
		return self:ModelSlotClear(ctx.player, model)
	end, {
		guard = { gp = true, inGame = false, alive = false, character = false },
	})

	eventService:RegisterFunction("Items/AccessorySlotClear", function(ctx, id)
		return self:AccessorySlotClear(ctx.player, id)
	end, {
		guard = { gp = true, inGame = false, alive = false, character = false },
	})

	eventService:RegisterFunction("Items/SkinSlotClear", function(ctx, weapon)
		return self:SkinSlotClear(ctx.player, weapon)
	end, {
		guard = { gp = true, inGame = false, alive = false, character = false },
	})

	eventService:RegisterFunction("Items/SkinSlotEquip", function(ctx, id, team, weapon)
		return self:SkinSlotEquip(ctx.player, id, team, weapon)
	end, {
		guard = { gp = true, inGame = false, alive = false, character = false },
	})

	eventService:RegisterFunction("Client/DropItem", function(ctx, itemId)
		return self:DropItem(ctx.player, itemId)
	end, {
		rateLimitKey = "Client/DropItem",
	})

	eventService:RegisterEvent("Server/Inventory/EquipItem", function(ctx, itemId)
		self:EquipItem(ctx.player, itemId)
	end, {
		rateLimitKey = "Server/Inventory/EquipItem",
	})

	eventService:RegisterEvent("Server/Inventory/UnequipItem", function(ctx, itemId)
		self:UnequipItem(ctx.player, itemId)
	end, {
		rateLimitKey = "Server/Inventory/UnequipItem",
	})
end

function Service:Start()
	--print("Loaded ItemService.")
end

function Service:init()
	_G.Players = {}
end

return Service
