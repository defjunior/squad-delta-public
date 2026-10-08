local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Framework = require(game.ReplicatedStorage.Modules.Framework)
local GlobalEnum = require(game.ReplicatedStorage.Modules.Data.GlobalEnum)
local VERBOSE_ITEM_LOGS = false
local DROP_FORWARD_DISTANCE = 3
local DROP_VERTICAL_OFFSET = 2
local DROP_RAYCAST_HEIGHT = 10
local DROP_RAYCAST_DEPTH = 30
local DROP_CLEARANCE = 0.2
local DROP_THROW_SPEED = 16
local DROP_THROW_UPWARD = 3

local function debugWarn(...)
	if VERBOSE_ITEM_LOGS then
		warn(...)
	end
end

local function getDropMainPart(model)
	if not model then
		return nil
	end
	return model:FindFirstChild("Main", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getHalfHeight(model)
	local _, size = model:GetBoundingBox()
	return math.max(size.Y * 0.5, 0.5)
end

local function getDropCFrame(character, model)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local lookVector = hrp.CFrame.LookVector
	local basePosition = hrp.Position + (lookVector * DROP_FORWARD_DISTANCE)
	local dropPosition = basePosition + Vector3.new(0, DROP_VERTICAL_OFFSET, 0)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character, model }
	rayParams.IgnoreWater = true

	local castOrigin = basePosition + Vector3.new(0, DROP_RAYCAST_HEIGHT, 0)
	local castDirection = Vector3.new(0, -(DROP_RAYCAST_HEIGHT + DROP_RAYCAST_DEPTH), 0)
	local hit = Workspace:Raycast(castOrigin, castDirection, rayParams)
	if hit then
		local halfHeight = getHalfHeight(model)
		dropPosition = hit.Position + hit.Normal * (halfHeight + DROP_CLEARANCE)
	end

	return CFrame.new(dropPosition, dropPosition + lookVector), lookVector
end

local function Weld(one,two)
	local NewWeldConstraint = Instance.new("WeldConstraint")
	NewWeldConstraint.Part0 = one
	NewWeldConstraint.Part1 = two
	NewWeldConstraint.Parent = one
end

_G.Items = {}

local Class = require(game.ReplicatedStorage.Modules.Class)

Item = Class:Extend()
Item.__index = Item

function Item:New(Model)
	local newTool = {}
	setmetatable(newTool,Item)
	
	newTool.ID = game:GetService("HttpService"):GenerateGUID()
	_G.Items[newTool.ID] = newTool
	newTool.CurrentTool = 1
	newTool.ClassName = "Item"
	if Model then
		newTool.ItemName = Model.Name 
		--print(Model)
		newTool.Tool = Model:Clone()
		local TF = Instance.new("Folder")
		TF.Parent = game.ReplicatedStorage.ReferenceModels
		newTool.Tool.Parent = TF
		TF.Name = newTool.ID
		newTool.Tool.ItemID.Value = newTool.ID
		newTool.Tool.ToModel.Value = Framework.GetWeaponType(newTool.ItemName) ~= nil and newTool.Tool:FindFirstChild("WeaponModel")  or newTool.Tool:FindFirstChild(newTool.ItemName)
		newTool.Tool.ToCurrentTool.Value = newTool.Tool
		newTool.CurrentTool = newTool.Tool
		--for a,b in pairs(Model:GetDescendants()) do
		--	if b:IsA("BasePart") then
		--		b.CollisionGroup = "Tools"
		--	end
		--end

	else
		newTool.ItemName = ""
	end
	
	
	return _G.Items[newTool.ID]
end

function Item:CreateTool()
	--print("Creating Tool...")
	
	local Tool= self.Tool:Clone()
	local Tag = Instance.new("StringValue")
	Tag.Value = self.ItemType
	Tag.Name = "ToolType"
	Tool.RequiresHandle = true
	local ToolConfig = Tool:WaitForChild("WeaponConfig")
	ToolConfig.Parent = Tool
	local Tag2 = Instance.new("StringValue")
	Tag2.Value = self.ID
	Tag2.Name = "ToolIdentifier"
	self.Tool.ToCurrentTool.Value = Tool
	self.Tool.ToModel.Value = Tool:FindFirstChildOfClass("Model")
	Tool.Destroying:Connect(function()
		self.Tool.ToCurrentTool.Value = self.Tool
		self.Tool.ToModel.Value = self.Tool:FindFirstChildOfClass("Model")
	end)
	return Tool
end

function Item:AwaitInit(timeoutSeconds)
	local timeout = tonumber(timeoutSeconds) or 10
	local deadline = os.clock() + timeout
	while not self.Init do
		if not self.CurrentTool or not self.CurrentTool.Parent then
			return false, "equipped tool was removed before its item server initialized"
		end
		if os.clock() >= deadline then
			return false, ("item server did not initialize within %.1f seconds"):format(timeout)
		end
		task.wait()
	end
	return true
end


function Item:Destroy()
	if game.ReplicatedStorage.ReferenceModels:FindFirstChild(self.ID) then
		game.ReplicatedStorage.ReferenceModels[self.ID]:Destroy()
	end
	
	if workspace.Ignore.Weapons:FindFirstChild(self.ID) then
		workspace.Ignore.Weapons[self.ID]:Destroy()
	end
	if self.Tool then
		self.Tool:Destroy()
	end
	--if self.Owner then
	--	self.Owner:RemoveItemFromBackpack(self.ID)
	--end
	debugWarn("Destroying",self.ItemName)
	_G.Items[self.ID] = nil
	self = nil
end

local function find(table,id)
	for a,b in pairs(table) do
		if b.ID == id then	
			return true
		end
	end
end

function Item:CreateDrop(ID)
	debugWarn("Creating Dropped item...",self.ItemName)
	local GP = _G.Players[ID]
	if not GP then return end
	if not find(GP.Backpack,self.ID) then return end
	if not self.CurrentTool then self.CurrentTool = self:CreateTool()  end
	local NewModel = (self.CurrentTool:FindFirstChild("ToModel").Value):Clone()
	for a,b in pairs(NewModel:GetDescendants()) do
		if b:IsA("BasePart") then
			b.CollisionGroup = "Default"
			b.CanCollide = true
			b.CanTouch = true
			b.CanQuery = true
			b.Anchored = false
		end
	end
	local MPart = getDropMainPart(NewModel)
	if not MPart then
		warn(("[Item] Failed to drop '%s' (%s): no main part found."):format(tostring(self.ItemName), tostring(self.ID)))
		return
	end
	local dropCFrame, lookVector = getDropCFrame(GP.CharacterObject, NewModel)
	if dropCFrame then
		NewModel:PivotTo(dropCFrame)
	end
	NewModel.Parent = workspace.Ignore.Weapons
	NewModel.Name = self.ID
	GP:RemoveItemFromBackpack(self.ID)
	pcall(function()
		MPart:SetNetworkOwner(nil)
	end)
	local throwVector = (lookVector or Vector3.new(0, 0, -1)) * DROP_THROW_SPEED + Vector3.new(0, DROP_THROW_UPWARD, 0)
	MPart:ApplyImpulse(throwVector * MPart.AssemblyMass)
	local NewProx = Instance.new("ProximityPrompt",MPart)
	NewProx.HoldDuration = 1
	NewProx.RequiresLineOfSight = false
	NewProx.ActionText = "Pickup"
	NewProx.ObjectText = self.ItemName
	debugWarn("Dropped",self.ItemName)
	return NewModel,NewProx
end


return Item
