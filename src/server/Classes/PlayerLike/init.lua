local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Class = require(ServerStorage.Modules.Class)

local PlayerLike = Class:Extend()
PlayerLike.__index = PlayerLike

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

function PlayerLike:AddItemToBackpack(Item)
	--internal reference
	table.insert(self.Backpack, Item)
	Item.Owner = self
	--object display
	local val = Instance.new("StringValue")
	val.Name = Item.ID
	val.Parent = self.BackpackFolder
end

function PlayerLike:RemoveItemFromBackpack(ItemID)
	local foundIndex
	for i, item in pairs(self.Backpack) do
		if item.ID == ItemID then
			foundIndex = i
		end
	end
	if not foundIndex then
		return
	end

	table.remove(self.Backpack, foundIndex)
	if self.BackpackFolder:FindFirstChild(ItemID) then
		self.BackpackFolder[ItemID]:Destroy()
	end
end

function PlayerLike:Bind(Key, fn)
	self["Bind_" .. Key] = fn
	return "Bind_" .. Key
end

function PlayerLike:CheckForBinds(Key, ...)
	local fn = self["Bind_" .. Key]
	if type(fn) == "function" then
		fn(self, ...)
	end
end

function PlayerLike:SetValue(Key, NewValue, ...)
	local DirectoryArgs = { ... }
	if Key == "InGame" or Key == "IsAlive" or Key == "IsDowned" then
		NewValue = NewValue == true
	end

	if not DirectoryArgs[1] then
		self[Key] = NewValue
		if self.IsBot == false and self.PlayerObject ~= nil then
			Remotes.Server.PlayerDataChanged:FireClient(game.Players:WaitForChild(self.PlayerName), "Player." .. Key, NewValue)
			local playerData = self.PlayerData
			if playerData then
				playerData:WaitForChild(Key).Value = tostring(NewValue)
			end
		end
	else
		local ref = self
		local refName = "Player"
		for _, v in pairs(DirectoryArgs) do
			refName = refName .. "." .. v
			ref = ref[v]
		end

		local ref2 = self.PlayerData
		if ref2 then
			for _, v in pairs(DirectoryArgs) do
				ref2 = ref2:FindFirstChild(v)
			end
			if ref2 and ref2:FindFirstChild(Key) then
				ref2[Key].Value = tostring(NewValue)
			end
		end

		ref[Key] = NewValue
	end

	self:CheckForBinds(Key, NewValue)
end

function PlayerLike:InventoryEdit(Key, Add, Remove, Create)
	if Add then
		local index = -1
		for i, v in pairs(self.SavedData.Inventory) do
			local split = string.split(v, ":")
			local compare = split[2]
			for idx = 3, #split, 1 do
				compare = compare .. ":" .. split[idx]
			end

			if compare == Key then
				index = i
			end
		end

		local entry = self.SavedData.Inventory[index]
		if not entry then
			return
		end

		local parts = string.split(entry, ":")
		local numerator = tonumber(parts[1])
		numerator += tonumber(Add)
		local newString = tostring(numerator)
		for i = 2, #parts, 1 do
			newString = newString .. ":" .. parts[i]
		end

		self.SavedData.Inventory[index] = newString
		if self.IsBot == false then
			local invFolder = self.PlayerData.SavedData:WaitForChild("Inventory")
			local item
			for _, v in pairs(self.PlayerData.SavedData.Inventory:GetChildren()) do
				if v.Name == Key then
					item = v
				end
			end

			if not item and numerator == 1 then
				local ns = Instance.new("StringValue")
				local split2 = string.split(newString, ":")
				newString = split2[2]
				for i = 3, #split2, 1 do
					newString = newString .. ":" .. split2[i]
				end
				ns.Name = newString
				item = ns
			end

			ReplicatedStorage.Remotes.Server.UpdateInventoryPointer:FireClient(self.PlayerObject, newString, numerator)
			if item then
				item.Value = newString
				item.Parent = invFolder
			end
		end
	end

	if Remove then
		local index = -1
		for i, entry in pairs(self.SavedData.Inventory) do
			local split = string.split(entry, ":")
			local compare = split[2]
			for idx = 3, #split, 1 do
				compare = compare .. ":" .. split[idx]
			end

			if compare == Key then
				index = i
			end
		end
		ReplicatedStorage.Remotes.Server.UpdateInventoryPointer:FireClient(self.PlayerObject, Key, 0)
		if index > 0 then
			table.remove(self.SavedData.Inventory, index)
		end
	end

	if Create then
		table.insert(self.SavedData.Inventory, Create)
		if self.PlayerObject then
			local newItem = Instance.new("StringValue")
			local split = string.split(Create, ":")
			local newString = split[2]
			for i, v in pairs(split) do
				if i > 2 then
					newString = newString .. ":" .. v
				end
			end
			newItem.Name = newString
			newItem.Value = Create
			newItem.Parent = self.PlayerData.SavedData.Inventory
		end
	end
end

return PlayerLike
