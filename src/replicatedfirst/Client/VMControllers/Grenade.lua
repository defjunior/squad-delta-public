-- GrenadeClientModule.lua

local Module = {}

Module.Init = function(context)
	local Grenade = _G.Tool:Extend()
	local Tool = _G.Tool

	-- Environment variables
	local Environment = context or {}
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Framework = _G.Framework
	local WeaponData = ReplicatedStorage.Modules.Data:WaitForChild("WeaponData")
	local GetAbilityData = ReplicatedStorage:WaitForChild("Remotes").Client:WaitForChild("GetAbilityData")
	local SavedData = _G.SavedData
	local PlayerData = _G.PlayerData
	local ClientPlayer = _G.Player
	local InputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local FreezeTime = ReplicatedStorage:WaitForChild("GameObjects").FreezeTime
	local lerp = function(a, b, t) 
		return a * (1 - t) + (b * t)
	end
	
	local ClientCamera = game.Workspace.CurrentCamera
	local TweenPropertyOut = _G.TweenPropertyOut
	local Remotes = ReplicatedStorage.Remotes
	local ContainerService = require(ReplicatedStorage.Modules.Services.ContainerService)
	local CH = ClientPlayer.PlayerGui:WaitForChild("HUD").Crosshair
	local TweenPropertyIn = _G.TweenPropertyIn
	local LoadViewModel = function(...)
		return _G.ViewmodelController:LoadVM(...)
	end
	local LoadWeapon = function(...)
		return _G.ViewmodelController:LoadWeapon(...)
	end
	local TweenService = game:GetService("TweenService")
	local Viewmodels = _G.ViewmodelController.Viewmodels


	function Grenade.New(Model)
		local newTool = Tool.New("Grenade", Model)
		setmetatable(newTool, Grenade)
		-- Initialize properties
		newTool.Reloading = false
		newTool.IsAiming = false
		newTool.Grip = nil
		newTool.ViewAnimator = nil
		newTool.ViewModel = nil
		newTool.TransparencyTable = {}
		newTool.CanAttack = true
		newTool.Equipped = false
		newTool.Equipping = false
		newTool.PulledPin = false
		newTool.Thrown = false
		newTool.FirstEquip = true
		newTool.Inspecting = false
		newTool.OnePressed = false
		newTool.TwoPressed = false
		newTool.Starting = {}
		newTool.ThrowTime = nil
		newTool.PullCon = nil
		newTool.WorldModelHideCon = nil
		return newTool
	end

	function Grenade:_resolveWorldModel()
		local toModelValue = self.GTool and (self.GTool:FindFirstChild("ToModel") or self.GTool:WaitForChild("ToModel", 1))
		local modelFromGTool = toModelValue and toModelValue.Value
		if modelFromGTool and modelFromGTool:IsA("Model") then
			return modelFromGTool
		end

		local toolModel = self.Tool and self.Tool:FindFirstChild("WeaponModel")
		if toolModel and toolModel:IsA("Model") then
			return toolModel
		end

		local character = ClientPlayer.Character
		local charModel = character and character:FindFirstChild("WeaponModel")
		if charModel and charModel:IsA("Model") then
			return charModel
		end

		return nil
	end

	function Grenade:HideWorldModel()
		local worldModel = self.Model or self:_resolveWorldModel()
		if not worldModel then
			return
		end

		for _, v in next, worldModel:GetDescendants() do
			if v:IsA("BasePart") then
				v.LocalTransparencyModifier = 1
			elseif v:IsA("SurfaceGui") then
				v.Enabled = false
			end
		end
	end

	function Grenade:Initialize()
		self.GTool = self.Model
		self.Tool = self.GTool.ToCurrentTool.Value
		self.Model = self:_resolveWorldModel()

		-- Initialize WeaponConfig
		self.WeaponConfig = require(self.Tool:WaitForChild("WeaponConfig"))
		if not self.Tool.WeaponConfig:FindFirstChildOfClass("Configuration") then
			self.WeaponConfig = Framework.AddAttributes(self.WeaponConfig, self.Tool.WeaponConfig)
			wait()
		end
		self.WeaponConfigRaw = require(self.Tool:WaitForChild("WeaponConfig"))
		self.WeaponConfig = Framework.IndexAttribute(self.Tool.WeaponConfig.Configuration)
		self.ConfigAnim = game.ReplicatedFirst.Assets.Animations:WaitForChild("Grenade")

		-- Initialize properties
		self.PlayerData = PlayerData
		SavedData = SavedData
		self.SoundFolder = self.Model
		self.MainPart = self.Model:WaitForChild("Main")
		self.Camera = workspace.CurrentCamera
		self.Server = self.Tool:WaitForChild("GrenadeServer")

		self.EquipTime = self.WeaponConfig.EQUIP_TIME
		self.WalkSpeed = self.WeaponConfig.WALKSPEED
		self:HideWorldModel()

		-- Event connections
		--InputService.InputBegan:Connect(function(Input, InputSank)
		--	self:HandleInputBegan(Input, InputSank)
		--end)

		--InputService.InputEnded:Connect(function(Input, InputSank)
		--	self:HandleInputEnded(Input, InputSank)
		--end)

		self.Server.Update.OnClientEvent:Connect(function()
			self:OnServerUpdate()
		end)

		-- Mobile controls
		if InputService.KeyboardEnabled == false then
			ClientPlayer.PlayerGui.HUD:WaitForChild("Fire").InputBegan:Connect(function()
				self:OnMobileFireInputBegan()
			end)
			ClientPlayer.PlayerGui.HUD:WaitForChild("Fire").InputEnded:Connect(function()
				self:OnMobileFireInputEnded()
			end)
			ClientPlayer.PlayerGui.HUD:WaitForChild("Reload").InputBegan:Connect(function()
				self:OnMobileReloadInputBegan()
			end)
			ClientPlayer.PlayerGui.HUD:WaitForChild("Reload").InputEnded:Connect(function()
				self:OnMobileReloadInputEnded()
			end)
		end
	end
	
	function Grenade:Retool()
		self.Tool = self.GTool.ToCurrentTool.Value
		self.Model = self:_resolveWorldModel()
		if self.Model then
			self.MainPart = self.Model:FindFirstChild("Main") or self.MainPart
		end
		self:HideWorldModel()
	end
	
	function Grenade:Equip()
		
		if self.Thrown == true then return end
		
		self:Retool()
		self.Server = self.Tool:WaitForChild("GrenadeServer")
		
		self.PulledPin = false
		self:HideWorldModel()
		
		
		
		
		local Character = ClientPlayer.Character
		self.Equipping = true
		_G.CurrentWeaponSign = -1
		ClientPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		InputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		InputService.MouseIconEnabled = false

		-- Hide other viewmodels
		_G.HideOtherVM()
		Remotes.Server.Inventory.EquipItem:FireServer(self.ID)
		task.wait()
		coroutine.wrap(function()
			_G.InventoryForceUpdate()
		end)()
		-- Load the viewmodel
		local LVM = LoadWeapon(self.Tool.Name)
		if not LVM then
			LoadViewModel(#Viewmodels + 1)
			LVM = LoadWeapon(self.Tool.Name)
		end
		self.ViewModel = LVM
		_G.CurrentCVM = self.ViewModel

		self.ClientModel = self.ViewModel:FindFirstChild(self.Tool.Name)
		if _G.ViewmodelController and _G.ViewmodelController.DelayEquippedViewmodelVisible then
			_G.ViewmodelController:DelayEquippedViewmodelVisible(self.ViewModel, self.ClientModel, 0.1)
		end

		if not self.ViewModel:FindFirstChild("AnimationController") then
			local new = Instance.new("AnimationController", self.ViewModel)
			Instance.new("Animator", new)
		end

		Framework.CopyRig(self.ViewModel, game.ReplicatedFirst.Assets.Models.RigCopy["Grenade"])
		self.ViewAnimator = LVM:FindFirstChild("Animator",true) or Instance.new("Animator",LVM:WaitForChild("AnimationController"))

		-- Load animations
		self.CL_EQUIP = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_EQUIP)
		self.CL_EQUIP.Priority = Enum.AnimationPriority.Movement
		self.CL_IDLE = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_IDLE)
		self.CL_IDLE.Priority = Enum.AnimationPriority.Idle
		self.CL_PULL = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_PULL)
		self.CL_PULL.Priority = Enum.AnimationPriority.Movement
		self.CL_PULLIDLE = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_PULLIDLE)
		self.CL_PULLIDLE.Priority = Enum.AnimationPriority.Movement
		self.CL_THROW1 = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_THROW1)
		self.CL_THROW1.Priority = Enum.AnimationPriority.Action
		self.CL_THROW2 = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_THROW2)
		self.CL_THROW2.Priority = Enum.AnimationPriority.Action
		self.CL_THROW3 = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_THROW3)
		self.CL_THROW3.Priority = Enum.AnimationPriority.Action
		self.CL_THROW4 = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_THROW4)
		self.CL_THROW4.Priority = Enum.AnimationPriority.Action

		self.CL_PULL.Looped = false
		self.CL_PULLIDLE.Looped = true
		self.CL_IDLE.Looped = true

		for i, v in next, self.ViewAnimator:GetPlayingAnimationTracks() do
			v:Stop(0)
		end

		self.CL_EQUIP:Play(0)
		if self.WorldModelHideCon then
			self.WorldModelHideCon:Disconnect()
			self.WorldModelHideCon = nil
		end
		self.WorldModelHideCon = RunService.RenderStepped:Connect(function()
			if self.Equipped or self.Equipping then
				self:HideWorldModel()
			end
		end)

		-- Wait for equip time
		_G.EquippingItem = self
		for _ = 1, 10 do
			if self ~= _G.EquippingItem then
				self.Equipping = false
				break
			end
			task.wait(self.EquipTime / 10)
		end


		if self.Equipping then
			self.Equipped = true
			_G.Equipped = self
			self.CanAttack = true
			--for i, v in pairs(ViewAnimator:GetPlayingAnimationTracks()) do
			--	v:Stop()
			--end
			self.CL_IDLE:Play(0)
		end
	end

	function Grenade:Unequip()
		if self.WorldModelHideCon then
			self.WorldModelHideCon:Disconnect()
			self.WorldModelHideCon = nil
		end
		self.Equipped = false
		self.Equipping = false
		if _G.Equipped == self then
			_G.Equipped = nil
		end
		if _G.EquippingItem == self then
			_G.EquippingItem = nil
		end
		Remotes.Server.Inventory.UnequipItem:FireServer(self.ID)
		pcall(function()
			if self.ViewModel then
				for i, v in pairs(self.ViewModel:GetDescendants()) do
					if v:IsA("BasePart") then
						v.Transparency = 1
					elseif v:IsA("Texture") or v:IsA("Decal") then
						v.Transparency = 1
					elseif v:IsA("RopeConstraint") then
						v.Visible = false
					end
				end
				local LeftGlove = self.ViewModel["Left Arm"].LeftGlove
				local RightGlove = self.ViewModel["Right Arm"].RightGlove

				for i, v in pairs(LeftGlove:GetChildren()) do
					if v:IsA("Attachment") then
						v:Destroy()
					end
				end

				for i, v in pairs(RightGlove:GetChildren()) do
					if v:IsA("Attachment") then
						v:Destroy()
					end
				end

				self.CanAttack = false
				if self.ViewAnimator then
					for i, v in next, self.ViewAnimator:GetPlayingAnimationTracks() do
						v:Stop(0)
					end
				end
			end
		end)
		
	end

	function Grenade:OnServerUpdate()
		self:Unequip()
	end

	function Grenade:HandleInputBegan(Input, InputSank)
		if InputSank then return end
		if not self.Equipped then return end
		if Input.UserInputState == Enum.UserInputState.End then return end
		if (Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.MouseButton2) and not self.Thrown and self.PlayerData.CanUse.Value == "true" then
			self:UpdateState()
			self.Starting = self:ConstructObject()
			task.wait()
			self:PullPin()
		end
	end

	function Grenade:HandleInputEnded(Input, InputSank)
		if not self.Equipped then return end
		if self.Thrown then return end
		if self.Starting.OnePressed and Input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:Throw(4)
		elseif self.Starting.TwoPressed and Input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:Throw(3)
		elseif self.Starting.OnePressed and Input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:Throw(2)
		elseif self.Starting.TwoPressed and Input.UserInputType == Enum.UserInputType.MouseButton2 then
			self:Throw(1)
		end
	end

	function Grenade:UpdateState()
		self.OnePressed = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		self.TwoPressed = InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	end

	function Grenade:ConstructObject()
		return {
			OnePressed = self.OnePressed,
			TwoPressed = self.TwoPressed,
		}
	end

	function Grenade:PullPin()
		if not self.PulledPin then
			self.PulledPin = true
			if self.CL_IDLE then
				self.CL_IDLE:Stop()
			end
			self.CL_PULL:Play()
			self.PullCon = self.CL_PULL.Stopped:Connect(function()
				if self.Equipped then
					self.Tool:Destroy()
				end
			end)
			self.Model.Swing.Pitch = math.random(90, 110) / 100
			self.Model.Swing:Play()
			self.Server.Update:FireServer("Pull")
		end
	end
	
	

	
	function Grenade:Throw(Num)
		self:Retool()
		if not self.Equipped then return end
		self.Server = self.Tool:WaitForChild("GrenadeServer")

		self.Thrown = true
		if Num == 1 then
			self.CL_THROW1:Play()
		elseif Num == 2 then
			self.CL_THROW2:Play()
		elseif Num == 3 then
			self.CL_THROW3:Play()
		elseif Num == 4 then
			self.CL_THROW4:Play()
		end
		task.wait(0.25)
		self.Server.Update:FireServer("Throw", Num, self.Camera.CFrame, ClientPlayer.Character.HumanoidRootPart.AssemblyLinearVelocity)
		task.wait(0.6)
		self:Unequip()
		_G.Tools[self.ID] = nil
		_G.InventoryForceUpdate()
	end

	-- Mobile input handling
	function Grenade:OnMobileFireInputBegan()
		if self.Equipped and not self.Thrown and self.PlayerData.CanUse.Value == "true" then
			self.OnePressed = true
			self:UpdateState()
			self.Starting = self:ConstructObject()
		end
	end

	function Grenade:OnMobileFireInputEnded()
		if self.Equipped and not self.Thrown and self.PlayerData.CanUse.Value == "true" then
			self.Thrown = true
			if self.Starting.OnePressed and self.Starting.TwoPressed then
				self:Throw(3)
			elseif self.Starting.OnePressed then
				self:Throw(4)
			end
		end
	end

	function Grenade:OnMobileReloadInputBegan()
		if self.Equipped and not self.Thrown and self.PlayerData.CanUse.Value == "true" then
			self.TwoPressed = true
			self:UpdateState()
			self.Starting = self:ConstructObject()
		end
	end

	function Grenade:OnMobileReloadInputEnded()
		if self.Equipped and not self.Thrown and self.PlayerData.CanUse.Value == "true" then
			self.Thrown = true
			if self.Starting.OnePressed and self.Starting.TwoPressed then
				self:Throw(2)
			elseif self.Starting.TwoPressed then
				self:Throw(1)
			end
		end
	end

	return Grenade
end

return Module
