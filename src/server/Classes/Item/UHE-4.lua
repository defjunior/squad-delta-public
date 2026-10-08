local Item = require(script.Parent)
local TweenService = game:GetService("TweenService")
local Framework = require(game.ReplicatedStorage.Modules.Framework)
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Assets = ReplicatedFirst:WaitForChild("Assets")
local Animations = Assets:WaitForChild("Animations")






UHE = Item:Extend()
UHE.__index = UHE



function UHE:New(Model)
	local self = Item:New(Model)
	self.Activated = false
	self.ClassName = "Weapon"
	if not self.ItemConfig then
		self.ItemConfig = Framework.DeepCopyTable(_G.GlobalConfig[Model.Name])
	end
	self.ItemType = "UHE-4"
	setmetatable(self,UHE)
	for c,d in pairs(self) do

	end
	self.CurrentTool = nil
	return self
end

function UHE:CreateTool()
	local Tool = Item.CreateTool(self)
	-- :)

	return Tool
end
function UHE:Equip(ID,Hand)

	if not Framework.HasIndex(_G.Players,ID) then warn("No Found Player") return end
	if not _G.Players[ID].CharacterObject then warn("No Found Character") return end

	for c,d in pairs(_G.Players[ID].CharacterObject:GetChildren()) do
		if d:IsA("Tool") then
			d:Destroy()
		end
	end

	self.CurrentTool = self:CreateTool()
	task.wait() -- allow the init to be overridden

	--- all the code for equipping a UHE to a character, server side

	local GPlayer = _G.Players[ID]
	GPlayer.CurrentTool = self
	self.CurrentTool.Parent = GPlayer.CharacterObject
	task.wait()
	local ready, reason = self:AwaitInit(10)
	if not ready then
		warn(("[UHE-4] Failed to equip %s: %s"):format(tostring(self.ItemName), reason))
		if self.CurrentTool then
			self.CurrentTool:Destroy()
		end
		return
	end
	self:Init()
	

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
function UHE:Unequip(ID)

	if not Framework.HasIndex(_G.Players,ID) then return end
	if not _G.Players[ID].CharacterObject then return end

	--_G.Players[ID].CharacterObject:WaitForChild("Humanoid"):UnequipTool(self.CurrentTool)
	if self.CurrentTool then
		if self.Uninit then
			self:Uninit()
		end
		self.Init = nil
		if self.CurrentTool then
			self.CurrentTool:Destroy()
		end
		
		self.CurrentTool = false
	end

end

return UHE
