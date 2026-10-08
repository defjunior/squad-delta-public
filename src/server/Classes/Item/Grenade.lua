local Item = require(script.Parent)
local Framework = require(game.ReplicatedStorage.Modules.Framework)

local Grenade = Item:Extend()
Grenade.__index = Grenade

function Grenade:New(Model)
	local self = Item:New(Model)
	self.Activated = false
	self.ClassName = "Weapon"
	if not self.ItemConfig then
		self.ItemConfig = Framework.DeepCopyTable(_G.GlobalConfig[Model.Name])
	end
	self.ItemType = "Grenade"
	setmetatable(self, Grenade)
	self.CurrentTool = nil
	return self
end

function Grenade:CreateTool()
	return Item.CreateTool(self)
end

function Grenade:Equip(ID)
	if not Framework.HasIndex(_G.Players, ID) then
		warn("No Found Player")
		return
	end
	if not _G.Players[ID].CharacterObject then
		warn("No Found Character")
		return
	end

	for _, child in pairs(_G.Players[ID].CharacterObject:GetChildren()) do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end

	self.CurrentTool = self:CreateTool()
	task.wait()

	local gPlayer = _G.Players[ID]
	gPlayer.CurrentTool = self
	self.CurrentTool.Parent = gPlayer.CharacterObject
	task.wait()
	repeat
		task.wait()
	until self.Init
	self:Init()
end

function Grenade:Unequip(ID)
	if not Framework.HasIndex(_G.Players, ID) then
		return
	end
	if not _G.Players[ID].CharacterObject then
		return
	end

	if self.CurrentTool then
		if self.Uninit then
			local ok, err = pcall(function()
				self:Uninit()
			end)
			if not ok then
				warn(("[Grenade] Uninit failed for %s (%s): %s"):format(tostring(self.ItemName), tostring(self.ID), tostring(err)))
			end
		end
		self.Init = nil
		if self.CurrentTool then
			self.CurrentTool:Destroy()
		end
		self.CurrentTool = false
	end
end

return Grenade
