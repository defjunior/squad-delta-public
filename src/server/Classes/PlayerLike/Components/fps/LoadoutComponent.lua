local ComponentBase = require(script.Parent.Parent.Base)

local LoadoutComponent = ComponentBase:Extend()
LoadoutComponent.__index = LoadoutComponent
LoadoutComponent.Name = "FPSLoadoutComponent"

local function shouldWipe(item)
	if not item then
		return false
	end
	local itemName = item.ItemName
	local itemType = item.ItemType
	return itemName == "UHE-4" or itemName == "PDA" or itemType == "Knife"
end

function LoadoutComponent:Init(player, ctx)
	self.gameObjects = ctx and ctx.gameObjects
end

function LoadoutComponent:ResetRoundWeapons()
	local player = self.player
	local i = 1
	while i <= #player.Backpack do
		local item = player.Backpack[i]
		if shouldWipe(item) then
			player:RemoveItemFromBackpack(item.ID)
			if item.Destroy then
				item:Destroy()
			end
			i = 1
		else
			i += 1
		end
	end
end

return LoadoutComponent
