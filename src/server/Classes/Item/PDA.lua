local Item = require(script.Parent)
local TweenService = game:GetService("TweenService")
local Framework = require(game.ReplicatedStorage.Modules.Framework)
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Assets = ReplicatedFirst:WaitForChild("Assets")
local Animations = Assets:WaitForChild("Animations")







PDA = Item:Extend()
PDA.__index = PDA



function PDA:New(Model)
	local self = Item:New(Model)
	self.Activated = false
	self.ClassName = "Weapon"
	if not self.ItemConfig then
		self.ItemConfig = Framework.DeepCopyTable(_G.GlobalConfig[Model.Name])
	end
	self.ItemType = "PDA"
	setmetatable(self,PDA)
	for c,d in pairs(self) do

	end
	self.CurrentTool = nil
	return self
end

function PDA:CreateTool()
	local Tool = Item.CreateTool(self)
	-- :)

	return Tool
end
function PDA:Equip(ID,Hand)

	if not Framework.HasIndex(_G.Players,ID) then warn("No Found Player") return end
	if not _G.Players[ID].CharacterObject then warn("No Found Character") return end
	warn(("[PDA] Equip start item=%s id=%s character=%s"):format(tostring(self.ItemName), tostring(self.ID), _G.Players[ID].CharacterObject:GetFullName()))

	for c,d in pairs(_G.Players[ID].CharacterObject:GetChildren()) do
		if d:IsA("Tool") then
			d:Destroy()
		end
	end

	self.CurrentTool = self:CreateTool()
	warn(("[PDA] Created tool %s parent=%s"):format(tostring(self.CurrentTool and self.CurrentTool:GetFullName()), tostring(self.CurrentTool and self.CurrentTool.Parent and self.CurrentTool.Parent:GetFullName())))
	task.wait() -- allow the init to be overridden

	--- all the code for equipping a PDA to a character, server side

	local GPlayer = _G.Players[ID]
	GPlayer.CurrentTool = self
	self.CurrentTool.Parent = GPlayer.CharacterObject
	warn(("[PDA] Parent set to %s"):format(tostring(self.CurrentTool.Parent and self.CurrentTool.Parent:GetFullName())))
	task.wait()
	local ready, reason = self:AwaitInit(10)
	if not ready then
		warn(("[PDA] Failed to equip %s: %s"):format(tostring(self.ItemName), reason))
		return
	end
	warn(("[PDA] Init starting item=%s"):format(tostring(self.ItemName)))
	self:Init()
	warn(("[PDA] Init finished item=%s"):format(tostring(self.ItemName)))
	

	--for c,d in pairs(self.CurrentTool.ItemModel:GetChildren()) do
	--	if d:IsA("CFrameValue") and string.find(d.Name,Hand) then
	--		local Name = string.split(d.Name,"/")
	--		local M6D = GPlayer.CharacterObject[Name[1]]:WaitForChild(Name[2])
	--		M6D[Name[3]] = d.Value
	--		local PartRef = self.CurrentTool.ItemModel
	--		for i = 4,#Name,1 do
	--			PartRef = PartRef[Name[i]]
	--		end
	--		M6D.Part1 = PartRef
	--	end
	--end
	
	--self.CurrentHand = Hand
	



end
function PDA:Unequip(ID)

	if not Framework.HasIndex(_G.Players,ID) then return end
	if not _G.Players[ID].CharacterObject then return end

	--_G.Players[ID].CharacterObject:WaitForChild("Humanoid"):UnequipTool(self.CurrentTool)
	if self.CurrentTool then
		warn(("[PDA] Unequip start item=%s id=%s"):format(tostring(self.ItemName), tostring(self.ID)))
		if self.Uninit then
			self:Uninit()
		end
		self.Init = nil
		if self.CurrentTool then
			self.CurrentTool:Destroy()
		end
		
		self.CurrentTool = false
		warn(("[PDA] Unequip finished item=%s id=%s"):format(tostring(self.ItemName), tostring(self.ID)))
	end

end

return PDA
