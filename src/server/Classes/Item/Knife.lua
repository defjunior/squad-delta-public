local Item = require(script.Parent)
local Framework = require(game.ReplicatedStorage.Modules.Framework)
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Assets = ReplicatedFirst:WaitForChild("Assets")
local Animations = Assets:WaitForChild("Animations")



local Knife = Item:Extend()
Knife.__index = Knife

function Knife:New(Model)
	local self = Item:New(Model)
	self.Activated = false
	self.ClassName = "Weapon"
	if not self.ItemConfig then
		self.ItemConfig = Framework.DeepCopyTable(_G.GlobalConfig[Model.Name])
	end
	self.ItemType = "Knife"
	setmetatable(self, Knife)
	self.CurrentTool = nil
	return self
end

function Knife:CreateTool()
	local Tool = Item.CreateTool(self)
	-- Add any knife-specific creation logic here
	return Tool
end

function Knife:Equip(ID)
	if not Framework.HasIndex(_G.Players, ID) then warn("No Found Player") return end
	if not _G.Players[ID].CharacterObject then warn("No Found Character") return end
	warn(("[Knife] Equip start item=%s id=%s character=%s"):format(tostring(self.ItemName), tostring(self.ID), _G.Players[ID].CharacterObject:GetFullName()))

	for _, tool in pairs(_G.Players[ID].CharacterObject:GetChildren()) do
		if tool:IsA("Tool") then
			tool:Destroy()
		end
	end

	self.CurrentTool = self:CreateTool()
	warn(("[Knife] Created tool %s parent=%s"):format(tostring(self.CurrentTool and self.CurrentTool:GetFullName()), tostring(self.CurrentTool and self.CurrentTool.Parent and self.CurrentTool.Parent:GetFullName())))
	task.wait() -- allow the init to be overridden

	local GPlayer = _G.Players[ID]
	GPlayer.CurrentTool = self
	self.CurrentTool.Parent = GPlayer.CharacterObject
	warn(("[Knife] Parent set to %s"):format(tostring(self.CurrentTool.Parent and self.CurrentTool.Parent:GetFullName())))
	task.wait()
	local ready, reason = self:AwaitInit(10)
	if not ready then
		warn(("[Knife] Failed to equip %s: %s"):format(tostring(self.ItemName), reason))
		return
	end
	warn(("[Knife] Init starting item=%s"):format(tostring(self.ItemName)))
	self:Init()
	warn(("[Knife] Init finished item=%s"):format(tostring(self.ItemName)))
end

function Knife:Unequip(ID)
	if not Framework.HasIndex(_G.Players, ID) then return end
	if not _G.Players[ID].CharacterObject then return end

	if self.CurrentTool then
		warn(("[Knife] Unequip start item=%s id=%s"):format(tostring(self.ItemName), tostring(self.ID)))
		if self.Uninit then
			self:Uninit()
		end
		self.Init = nil
		if self.CurrentTool then
			self.CurrentTool:Destroy()
		end
		self.CurrentTool = false
		warn(("[Knife] Unequip finished item=%s id=%s"):format(tostring(self.ItemName), tostring(self.ID)))
	end
end

return Knife
