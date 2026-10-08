local Module = {}

Module.Init = function(context)
	local UHE4 = _G.Tool:Extend()
	local Tool = _G.Tool

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
	local Workspace = game:GetService("Workspace")
	local GameObjects = ReplicatedStorage:WaitForChild("GameObjects")
	local CurrentMapValue = GameObjects:WaitForChild("CurrentMap")
	local FreezeTime = GameObjects:WaitForChild("FreezeTime")
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

	local function setSurfaceGuisEnabled(root, enabled)
		if not root then
			return
		end
		for _, inst in ipairs(root:GetDescendants()) do
			if inst:IsA("SurfaceGui") then
				inst.Enabled = enabled and true or false
			end
		end
	end

	local function getConfigCFrame(config, ...)
		if type(config) ~= "table" then
			return nil
		end
		for _, key in ipairs({ ... }) do
			local value = config[key]
			if typeof(value) == "CFrame" then
				return value
			end
		end
		return nil
	end

	function UHE4.New(Model)
		local newTool = Tool.New("UHE-4", Model)
		setmetatable(newTool, UHE4)

		-- Initialize properties
		newTool.Equipped = false
		newTool.Equipping = false
		newTool.CanAttack = false
		newTool.M1Hold = false
		newTool.ViewModel = nil
		newTool.ViewAnimator = nil
		newTool.ClientModel = nil
		newTool.CL_IDLE = nil
		newTool.CL_EQUIP = nil
		newTool.CL_PLANT = nil
		newTool.Highlights = {}
		newTool._onSiteConn = nil
		newTool._mapConn = nil
		return newTool
	end

	function UHE4:PrepareViewmodelRig()
		if not self.ViewModel then
			return
		end

		local rightArm = self.ViewModel:FindFirstChild("Right Arm")
		local leftArm = self.ViewModel:FindFirstChild("Left Arm")
		local rightGrip = rightArm and rightArm:FindFirstChild("RightGrip")
		local leftGrip = leftArm and leftArm:FindFirstChild("LeftGrip")
		local cfg = self.WeaponConfigRaw or {}

		if rightGrip and rightGrip:IsA("Motor6D") then
			rightGrip.C0 = CFrame.new()
			rightGrip.C1 = CFrame.new()
			local rightC0 = getConfigCFrame(cfg, "C0", "RC0", "RightC0")
			local rightC1 = getConfigCFrame(cfg, "C1", "RC1", "RightC1")
			if rightC0 then
				rightGrip.C0 = rightC0
			end
			if rightC1 then
				rightGrip.C1 = rightC1
			end
		end

		if leftGrip and leftGrip:IsA("Motor6D") then
			leftGrip.C0 = CFrame.new()
			leftGrip.C1 = CFrame.new()
			local leftC0 = getConfigCFrame(cfg, "LC0", "L_C0", "LeftC0")
			local leftC1 = getConfigCFrame(cfg, "LC1", "L_C1", "LeftC1")
			if leftC0 then
				leftGrip.C0 = leftC0
			end
			if leftC1 then
				leftGrip.C1 = leftC1
			end
		end

		if cfg.CopyRig then
			local rigCopyFolder = game.ReplicatedFirst.Assets.Models:FindFirstChild("RigCopy")
			local rigCopy = rigCopyFolder and rigCopyFolder:FindFirstChild(self.Tool and self.Tool.Name or "")
			if rigCopy then
				Framework.CopyRig(self.ViewModel, rigCopy)
			end
		end
	end
	function UHE4:Retool()
		self.Model = self.GTool and self.GTool:FindFirstChild("ToModel") and self.GTool.ToModel.Value or self.Model
		self.Tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value or self.Tool

		self.MainPart = self.Model:WaitForChild("Main")

	end

	function UHE4:_bindToolEvents(timeoutSeconds, requireEquippedTool)
		local timeout = timeoutSeconds or 0
		local deadline = tick() + timeout
		local tool = nil
		local events = nil
		local mouseEvent = nil

		repeat
			tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value
			local isEquippedTool = not requireEquippedTool
				or (ClientPlayer.Character and tool and tool.Parent == ClientPlayer.Character)
			if tool and isEquippedTool then
				events = tool:FindFirstChild("Events")
				mouseEvent = events and events:FindFirstChild("MouseEvent")
				if mouseEvent and mouseEvent:IsA("RemoteEvent") then
					self.Tool = tool
					self.Model = self.GTool and self.GTool:FindFirstChild("ToModel") and self.GTool.ToModel.Value or self.Model
					self.MainPart = self.Model and self.Model:FindFirstChild("Main")
					self.MouseEvent = mouseEvent
					return true
				end
			end
			if timeout <= 0 then
				break
			end
			task.wait()
		until tick() >= deadline
		return false
	end
	
	local function getCurrentZones()
		local mapName = CurrentMapValue.Value
		if not mapName or mapName == "" then
			return nil
		end
		local mapModel = Workspace:FindFirstChild(mapName)
		if not mapModel then
			return nil
		end
		return mapModel:FindFirstChild("Zones")
	end

	local function clearTable(tbl)
		for key in pairs(tbl) do
			tbl[key] = nil
		end
	end

	local function clearHighlights(self)
		for _, highlight in pairs(self.Highlights) do
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
		end
		clearTable(self.Highlights)
	end

	function UHE4:Initialize()
		self.GTool = self.Model
		self.Model = self.GTool and self.GTool:FindFirstChild("ToModel") and self.GTool.ToModel.Value or self.Model
		self.Tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value or self.Tool

		self.MainPart = self.Model:WaitForChild("Main")
		
		self.CDATA = ClientPlayer.Character:WaitForChild("CDATA")
		self.MouseEvent = self.Tool.Events.MouseEvent
		self.WeaponConfig = require(self.Tool:WaitForChild("WeaponConfig"))	
		self.ConfigAnim = game.ReplicatedFirst.Assets.Animations:WaitForChild(self.Name)
		if not self.Tool.WeaponConfig:FindFirstChildOfClass("Configuration") then
			self.WeaponConfig = Framework.AddAttributes(self.WeaponConfig,self.Tool.WeaponConfig)
			wait()
		end
		self.TransparencyTable = {}
		self.WeaponConfigRaw = require(self.Tool:WaitForChild("WeaponConfig"))	
		self.WeaponConfig = Framework.IndexAttribute(self.Tool.WeaponConfig.Configuration)
		self.EquipTime = (self.WeaponConfig.EQUIP_TIME or 0) * 0.5
		if not self._mapConn then
			self._mapConn = CurrentMapValue:GetPropertyChangedSignal("Value"):Connect(function()
				if self.Equipped then
					self:ToggleBox(true)
				else
					self:ToggleBox(false)
				end
			end)
		end
	end

	function UHE4:ToggleBox(Bool)
		local zones = getCurrentZones()
		if not zones then
			clearHighlights(self)
			return
		end

		if Bool then
			for _, zone in ipairs(zones:GetChildren()) do
				if zone:IsA("BasePart") then
					local highlight = self.Highlights[zone]
					if not highlight or not highlight.Parent then
						if highlight then
							highlight:Destroy()
						end
						highlight = Instance.new("Highlight")
						highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
						highlight.FillColor = Color3.fromHSV(0.153083, 0.866667, 1)
						highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
						highlight.Adornee = zone
						highlight.Parent = zone
						self.Highlights[zone] = highlight
					end
					highlight.Enabled = true
					zone.Transparency = 0
				end
			end
		else
			for _, highlight in pairs(self.Highlights) do
				if highlight then
					highlight.Enabled = false
					highlight:Destroy()
				end
			end
			clearTable(self.Highlights)
			for _, zone in ipairs(zones:GetChildren()) do
				if zone:IsA("BasePart") then
					zone.Transparency = 1
				end
			end
		end
	end

	function UHE4:Equip()
		if self.Equipped or self.Equipping or _G.EquippingItem then
			return
		end
		self.Equipping = true
		_G.EquippingItem = self
		_G.CurrentWeaponSign = -1
		if _G.HideOtherVM then
			_G.HideOtherVM()
		end
		Remotes.Server.Inventory.EquipItem:FireServer(self.ID)
		if not self:_bindToolEvents(2, true) then
			self.Equipping = false
			self.CanAttack = false
			if _G.EquippingItem == self then
				_G.EquippingItem = nil
			end
			self:ToggleBox(false)
			return
		end
		self:ToggleBox(true)
		self.MainPart.Deploy:Play()
		ClientPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		InputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		InputService.MouseIconEnabled = false
		local LVM = LoadWeapon(self.Tool.Name)
		if not LVM then
			LoadViewModel(#Viewmodels + 1)
			LVM = LoadWeapon(self.Tool.Name)
		end
		if not LVM then
			self.Equipping = false
			self.CanAttack = false
			if _G.EquippingItem == self then
				_G.EquippingItem = nil
			end
			self:ToggleBox(false)
			return
		end
		self.ViewModel = LVM
		_G.CurrentCVM = LVM
		self.ViewAnimator = self.ViewModel:FindFirstChild("Animator", true) or Instance.new("Animator", self.ViewModel:WaitForChild("AnimationController"))
		self.ClientModel = self.ViewModel:FindFirstChild(self.Tool.Name, true)
		if not self.ClientModel then
			for _, model in ipairs(self.ViewModel:GetDescendants()) do
				if model:IsA("Model") and model:FindFirstChild("Main") then
					self.ClientModel = model
					break
				end
			end
		end
		self:PrepareViewmodelRig()
		if _G.ViewmodelController and _G.ViewmodelController.EnsureEquippedViewmodelVisible then
			_G.ViewmodelController:EnsureEquippedViewmodelVisible(self.ViewModel, self.ClientModel)
		end
		if _G.ViewmodelController and _G.ViewmodelController.PropagateViewmodels then
			_G.ViewmodelController:RequestViewmodelPropagation()
			_G.ViewmodelController:PropagateViewmodels()
		end
		coroutine.wrap(function()
			task.wait(0.15)
			self.Model = self.GTool and self.GTool:FindFirstChild("ToModel") and self.GTool.ToModel.Value or self.Model
			Framework.TransparencyControl(self.TransparencyTable, "Hide", self.Model)
		end)()
		coroutine.wrap(function()
			if _G.InventoryForceUpdate then
				_G.InventoryForceUpdate()
			end
		end)()
		TweenPropertyOut(ClientCamera, "FieldOfView", 0.1, tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value))
		self.CL_EQUIP = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_EQUIP)
		self.CL_EQUIP.Priority = Enum.AnimationPriority.Action
		self.CL_IDLE = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_IDLE)
		self.CL_IDLE.Priority = Enum.AnimationPriority.Idle
		self.CL_PLANT = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_PLANT)
		self.CL_PLANT.Priority = Enum.AnimationPriority.Action2
		self.CL_IDLE.Looped = true
		for _, animTrack in pairs(self.ViewAnimator:GetPlayingAnimationTracks()) do
			animTrack:Stop(0)
		end
		self.CL_EQUIP:Play(0)
		self.CL_IDLE:Play(0)
		if self.CL_IDLE.AdjustWeight then
			self.CL_IDLE:AdjustWeight(0, 0)
		end
		task.delay(0.00, function()
			if self.ClientModel then
				for _, v in pairs(self.ClientModel:GetDescendants()) do
					if v:IsA("BasePart") and not v:FindFirstChild("TransparencyTag") then
						v.Transparency = 0
					elseif v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal") then
						v.Transparency = 0
					end
				end
			end
			if self.ViewModel then
				for _, v in pairs(self.ViewModel:GetDescendants()) do
					if v:IsA("Texture") or v:IsA("Decal") then
						v.Transparency = 0
					elseif v:FindFirstChild("TransparencyTag") then
						v.Transparency = v.TransparencyTag.Value
					end
				end
			end
		end)
		for _ = 1, 10 do
			if self ~= _G.EquippingItem then
				self.Equipping = false
				break
			end
			task.wait(self.EquipTime / 10)
		end
		if self.Equipping and _G.EquippingItem == self then
			self.Equipped = true
			self.CanAttack = true
			_G.Equipped = self
			if self.CL_IDLE then
				if self.CL_IDLE.AdjustWeight then
					self.CL_IDLE:AdjustWeight(1, 0.02)
				else
					self.CL_IDLE:Play(0.02)
				end
			end
			if self.CL_EQUIP then
				self.CL_EQUIP:Stop(0.02)
			end
		end

	end

	function UHE4:Unequip(reason)
		self:ToggleBox(false)
		self:Unplant()
		Framework.TransparencyControl(
			self.TransparencyTable,
			"Show",
			self.Model
		)
		self.Equipped = false
		self.Equipping = false
		self.CanAttack = false
		if _G.Equipped == self then
			_G.Equipped = nil
		end
		if _G.EquippingItem == self then
			_G.EquippingItem = nil
		end
		if _G.CurrentCVM == self.ViewModel then
			_G.CurrentCVM = nil
			if _G.ViewmodelController and _G.ViewmodelController.RequestViewmodelPropagation then
				_G.ViewmodelController:RequestViewmodelPropagation()
			end
		end
		if self.ViewModel then
			setSurfaceGuisEnabled(self.ViewModel, false)
			for _, v in pairs(self.ViewModel:GetDescendants()) do
				if v:IsA("BasePart") then
					v.Transparency = 1
				elseif v:IsA("Texture") or v:IsA("Decal") then
					v.Transparency = 1
				elseif v:IsA("RopeConstraint") then
					v.Visible = false
				end
			end

			-- Destroy glove attachments
			if self.ViewModel:FindFirstChild("Left Arm") and self.ViewModel["Left Arm"]:FindFirstChild("LeftGlove") then
				for _, v in pairs(self.ViewModel["Left Arm"].LeftGlove:GetChildren()) do
					if v:IsA("Attachment") then v:Destroy() end
				end
			end
			if self.ViewModel:FindFirstChild("Right Arm") and self.ViewModel["Right Arm"]:FindFirstChild("RightGlove") then
				for _, v in pairs(self.ViewModel["Right Arm"].RightGlove:GetChildren()) do
					if v:IsA("Attachment") then v:Destroy() end
				end
			end

			self.Equipped = false
			self.Equipping = false
			self.CanAttack = false
			if _G.Equipped == self then
				_G.Equipped = nil
			end
			if _G.EquippingItem == self then
				_G.EquippingItem = nil
			end
			if _G.CurrentCVM == self.ViewModel then
				_G.CurrentCVM = nil
				if _G.ViewmodelController and _G.ViewmodelController.RequestViewmodelPropagation then
					_G.ViewmodelController:RequestViewmodelPropagation()
				end
			end
			if self.ViewAnimator then
				for _, animTrack in pairs(self.ViewAnimator:GetPlayingAnimationTracks()) do
					animTrack:Stop(0)
				end
			end
		end
		if reason ~= "Consumed" then
			Remotes.Server.Inventory.UnequipItem:FireServer(self.ID)
		end
	end

	function UHE4:Plant()
		if not self.MouseEvent or not self.MouseEvent.Parent then
			if not self:_bindToolEvents(1, true) then
				return
			end
		end
		self:Retool()
		if not self.CDATA.OnSite.Value then return end
		if self.CanAttack and self.Equipped and ClientPlayer.Team.Name == game.ReplicatedStorage.GameObjects.ATeam.Value and self.CDATA.OnSite.Value == true then
			if self.M1Hold then
				self.CanAttack = false
				self.MouseEvent:FireServer("Started")
				self.CL_PLANT:Play()
				-- Listen for OnSite value change to unplant
				if self._onSiteConn then
					self._onSiteConn:Disconnect()
					self._onSiteConn = nil
				end
				self._onSiteConn = self.CDATA.OnSite:GetPropertyChangedSignal("Value"):Connect(function()
					self:Unplant()
				end)
			end
		end
	end

	function UHE4:Unplant()
		if self._onSiteConn then
			self._onSiteConn:Disconnect()
			self._onSiteConn = nil
		end
		if self.CL_PLANT then
			self.CL_PLANT:Stop()
		end
		if self.Equipped then
			if self.CL_IDLE then
				self.CL_IDLE:Play()
			end
		end
		if self.MouseEvent then
			self.MouseEvent:FireServer("Ended")
		end
		self.CanAttack = true
	end

	function UHE4:HandleInputBegan(Input, InputSunk)
		if InputSunk then return end
		if Input.UserInputType == Enum.UserInputType.MouseButton1 and self.Equipped and self.CanAttack and PlayerData.CanUse.Value == "true" then
			self.M1Hold = true
			self:Plant()
		end
	end

	function UHE4:HandleInputEnded(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.M1Hold = false
			self:Unplant()
		end
	end

	return UHE4
end

return Module
