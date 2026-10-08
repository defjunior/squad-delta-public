local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Framework = require(ReplicatedStorage.Modules.Framework)

local Utils = {}

local function toArray(value)
	if type(value) ~= "table" then
		return {}
	end
	local out = {}
	for _, entry in ipairs(value) do
		table.insert(out, entry)
	end
	return out
end

function Utils.itemTool(itemOrTool)
	if not itemOrTool then
		return nil
	end
	if itemOrTool.IsA and itemOrTool:IsA("Tool") then
		return itemOrTool
	end
	return itemOrTool.Tool
end

function Utils.getPlayerItems(gp)
	if not gp then
		return {}
	end
	local items = toArray(gp.Backpack)
	local character = gp.CharacterObject
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				local found = false
				for _, item in ipairs(items) do
					if Utils.itemTool(item) == child then
						found = true
						break
					end
				end
				if not found then
					table.insert(items, child)
				end
			end
		end
	end
	return items
end

function Utils.forEachTool(gp, callback)
	if type(callback) ~= "function" then
		return
	end
	for _, item in ipairs(Utils.getPlayerItems(gp)) do
		local tool = Utils.itemTool(item)
		if tool then
			callback(tool, item)
		end
	end
end

function Utils.removeBackpackItems(gp, predicate)
	if not (gp and gp.Backpack and type(predicate) == "function") then
		return
	end
	local snapshot = {}
	for _, item in ipairs(gp.Backpack) do
		table.insert(snapshot, item)
	end
	for _, item in ipairs(snapshot) do
		local tool = Utils.itemTool(item)
		local shouldRemove = predicate(item, tool) == true
		if shouldRemove then
			if item.Unequip then
				pcall(function()
					item:Unequip(gp.ID)
				end)
			end
			if gp.RemoveItemFromBackpack and item.ID then
				pcall(function()
					gp:RemoveItemFromBackpack(item.ID)
				end)
			end
			if item.Destroy then
				pcall(function()
					item:Destroy()
				end)
			elseif tool and tool.Parent then
				tool:Destroy()
			end
		end
	end
end

function Utils.giveItem(gp, itemService, itemName, itemType)
	if not (gp and itemService and itemName and itemName ~= "") then
		return nil
	end
	local weapons = ServerStorage:FindFirstChild("Weapons")
	local base = weapons and weapons:FindFirstChild(itemName)
	if not base then
		return nil
	end
	local item = itemService:NewItem(base, itemType or "Gun")
	if not item then
		return nil
	end
	if gp.AddItemToBackpack then
		gp:AddItemToBackpack(item)
	else
		local tool = Utils.itemTool(item)
		if tool then
			tool.Parent = gp.CharacterObject or tool.Parent
		end
	end
	return item
end

function Utils.sendPersonalMessage(gp, message, color)
	if not (gp and gp.PlayerObject and message) then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local serverFolder = remotes and remotes:FindFirstChild("Server")
	local remote = serverFolder and serverFolder:FindFirstChild("PersonalSystemMessage")
	if remote then
		remote:FireClient(gp.PlayerObject, message, color or Color3.new(1, 1, 1))
	end
end

function Utils.setToolAmmo(tool, current, reserve)
	if not tool then
		return
	end
	local ammo = tool:FindFirstChild("Ammo")
	if not ammo then
		return
	end
	local currentValue = ammo:FindFirstChild("Current")
	local reserveValue = ammo:FindFirstChild("Reserve")
	if currentValue and current ~= nil then
		currentValue.Value = current
	end
	if reserveValue and reserve ~= nil then
		reserveValue.Value = reserve
	end
end

local function resolveIndexedWeaponConfig(weaponConfigObject)
	if not weaponConfigObject then
		return nil, nil
	end

	local required = nil
	pcall(function()
		required = require(weaponConfigObject)
	end)

	local indexed = required
	local configInstance = weaponConfigObject:FindFirstChildOfClass("Configuration")
	if not configInstance and required and Framework.AddAttributes then
		local ok, configured = pcall(Framework.AddAttributes, required, weaponConfigObject)
		if ok then
			indexed = configured
		end
	else
		indexed = configInstance or indexed
	end

	if indexed and Framework.IndexAttribute then
		local ok, withIndex = pcall(Framework.IndexAttribute, indexed)
		if ok then
			indexed = withIndex
		end
	end

	return indexed, required
end

function Utils.setToolWeaponConfig(tool, overrides)
	if not (tool and type(overrides) == "table") then
		return
	end
	local weaponConfigObject = tool:FindFirstChild("WeaponConfig")
	if not weaponConfigObject then
		return
	end
	local indexed = resolveIndexedWeaponConfig(weaponConfigObject)
	if not indexed then
		return
	end
	for key, value in pairs(overrides) do
		pcall(function()
			indexed[key] = value
		end)
	end
end

function Utils.restoreToolWeaponConfig(tool, keys)
	if not (tool and type(keys) == "table") then
		return
	end
	local weaponConfigObject = tool:FindFirstChild("WeaponConfig")
	if not weaponConfigObject then
		return
	end
	local indexed, defaults = resolveIndexedWeaponConfig(weaponConfigObject)
	if not (indexed and type(defaults) == "table") then
		return
	end
	for _, key in ipairs(keys) do
		if defaults[key] ~= nil then
			pcall(function()
				indexed[key] = defaults[key]
			end)
		end
	end
end

function Utils.forceEquip(gp, itemName)
	if not (gp and gp.PlayerObject and itemName and itemName ~= "") then
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local serverFolder = remotes and remotes:FindFirstChild("Server")
	local remote = serverFolder and serverFolder:FindFirstChild("ForceEquip")
	if remote then
		remote:FireClient(gp.PlayerObject, itemName)
	end
end

return Utils
