-- PDAClientModule.lua
local Module = {}

Module.Init = function(context)
	-- Extend the base Tool class
	local PDA = _G.Tool:Extend()
	local Tool = _G.Tool

	-- Get environment variables
	local Environment = context or {}

	-- Services and variables from the environment
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Framework = _G.Framework
	local WeaponData = ReplicatedStorage.Modules.Data:WaitForChild("WeaponData")
	local GetAbilityData = ReplicatedStorage:WaitForChild("Remotes").Client:WaitForChild("GetAbilityData")
	local AbilityDataUpdated = ReplicatedStorage:WaitForChild("Remotes").Server:WaitForChild("AbilityDataUpdated")
	local SavedData = _G.SavedData
	local PlayerData = _G.PlayerData
	local ClientPlayer = _G.Player
	local InputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local GameObjects = ReplicatedStorage:WaitForChild("GameObjects")
	local FreezeTime = GameObjects.FreezeTime
	local lerp = function(a, b, t) 
		return a * (1 - t) + (b * t)
	end
	
	local ClientCamera = game.Workspace.CurrentCamera
	local TweenPropertyOut = _G.TweenPropertyOut
	local Remotes = ReplicatedStorage.Remotes
	local ContainerService = require(ReplicatedStorage.Modules.Services.ContainerService)
	local CH = ClientPlayer.PlayerGui:WaitForChild("HUD").Crosshair
	local TweenPropertyIn = _G.TweenPropertyIn
	local LoadViewModelShell = function(...)
		return _G.ViewmodelController:LoadVM(...)
	end
	local LoadWeaponShell = function(...)
		return _G.ViewmodelController:LoadWeapon(...)
	end
	local TweenService = game:GetService("TweenService")
	local Viewmodels = _G.ViewmodelController.Viewmodels

	local UserInputService = game:GetService("UserInputService")
	local Workspace = game:GetService("Workspace")
	local SoundService = game:GetService("SoundService")
	local IgnoreFolder = Workspace:WaitForChild("Ignore")
	local UHEFolderName = "UHE-4"
	local MAX_ABILITY_COOLDOWN = 300

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

	local function setViewmodelArmsVisible(viewModel, visible)
		if not viewModel then
			return
		end
		if not visible then
			for _, armName in ipairs({ "Left Arm", "Right Arm" }) do
				local arm = viewModel:FindFirstChild(armName)
				if arm and arm:IsA("BasePart") then
					arm.Transparency = 1
					for _, inst in ipairs(arm:GetDescendants()) do
						if inst:IsA("BasePart") or inst:IsA("Texture") or inst:IsA("Decal") then
							inst.Transparency = 1
						end
					end
				end
			end
			return
		end

		local loadout = nil
		if ClientPlayer.Team and ClientPlayer.Team.Name ~= "Spectator" then
			loadout = SavedData and SavedData:FindFirstChild(ClientPlayer.Team.Name .. "Loadout")
		end
		if not loadout then
			loadout = SavedData and SavedData:FindFirstChild("REDLoadout")
		end
		local gloveSkinValue = loadout and loadout:FindFirstChild("GloveSkin")
		local hasGloveSkin = gloveSkinValue and gloveSkinValue.Value ~= "None"

		local leftArm = viewModel:FindFirstChild("Left Arm")
		local rightArm = viewModel:FindFirstChild("Right Arm")
		local leftGlove = leftArm and leftArm:FindFirstChild("LeftGlove")
		local rightGlove = rightArm and rightArm:FindFirstChild("RightGlove")

		local function restoreArm(arm)
			if not (arm and arm:IsA("BasePart")) then
				return
			end
			local armTag = arm:FindFirstChild("TransparencyTag")
			arm.Transparency = (armTag and armTag.Value) or 0
			for _, inst in ipairs(arm:GetDescendants()) do
				if inst:IsA("BasePart") and inst ~= leftGlove and inst ~= rightGlove then
					local instTag = inst:FindFirstChild("TransparencyTag")
					inst.Transparency = (instTag and instTag.Value) or 0
				elseif inst:IsA("Texture") or inst:IsA("Decal") then
					local instTag = inst:FindFirstChild("TransparencyTag")
					inst.Transparency = (instTag and instTag.Value) or 0
				end
			end
		end

		restoreArm(leftArm)
		restoreArm(rightArm)

		local leftVisible = false
		local rightVisible = false
		if hasGloveSkin or viewModel:FindFirstChild("ShowBothGloves") then
			leftVisible = true
			rightVisible = true
		end
		if viewModel:FindFirstChild("ShowRightGlove") then
			leftVisible = false
			rightVisible = true
		end
		if viewModel:FindFirstChild("ShowLeftGlove") then
			leftVisible = true
			rightVisible = false
		end

		if leftGlove and leftGlove:IsA("BasePart") then
			leftGlove.Transparency = leftVisible and 0 or 1
			for _, inst in ipairs(leftGlove:GetDescendants()) do
				if inst:IsA("BasePart") or inst:IsA("Texture") or inst:IsA("Decal") then
					inst.Transparency = leftVisible and 0 or 1
				end
			end
		end
		if rightGlove and rightGlove:IsA("BasePart") then
			rightGlove.Transparency = rightVisible and 0 or 1
			for _, inst in ipairs(rightGlove:GetDescendants()) do
				if inst:IsA("BasePart") or inst:IsA("Texture") or inst:IsA("Decal") then
					inst.Transparency = rightVisible and 0 or 1
				end
			end
		end
	end

	local function getCooldownNow()
		if Workspace and Workspace.GetServerTimeNow then
			local ok, now = pcall(Workspace.GetServerTimeNow, Workspace)
			if ok and type(now) == "number" then
				return now
			end
		end
		return tick()
	end

	local function sanitizeCooldownDuration(value)
		local numeric = tonumber(value) or 0
		if numeric < 0 then
			return 0
		end
		return math.min(MAX_ABILITY_COOLDOWN, math.floor(numeric + 0.5))
	end

	local function getCooldownRemaining(cooldownEnd)
		local endStamp = tonumber(cooldownEnd)
		if not endStamp then
			return 0
		end
		local remaining = math.ceil(endStamp - getCooldownNow())
		if remaining <= 0 then
			return 0
		end
		if remaining > MAX_ABILITY_COOLDOWN then
			return 0
		end
		return remaining
	end

	local function bindUHEFolder(self)
		local function attach(folder)
			if self._uheFolderConn then
				self._uheFolderConn:Disconnect()
				self._uheFolderConn = nil
			end
			self._uheFolderConn = folder.ChildAdded:Connect(function()
				self:OnUHEAdded()
			end)
			self:OnUHEAdded()
		end

		local folder = IgnoreFolder:FindFirstChild(UHEFolderName)
		if folder then
			attach(folder)
			return
		end

		if self._uheWaitConn then
			self._uheWaitConn:Disconnect()
			self._uheWaitConn = nil
		end
		self._uheWaitConn = IgnoreFolder.ChildAdded:Connect(function(child)
			if child.Name ~= UHEFolderName then
				return
			end
			if self._uheWaitConn then
				self._uheWaitConn:Disconnect()
				self._uheWaitConn = nil
			end
			attach(child)
		end)
	end

	function PDA.New(Model)
		local newTool = Tool.New("PDA", Model)
		setmetatable(newTool, PDA)

		-- Initialize properties
		newTool.CurrentPlayer = nil
		newTool.Equipped = false
		newTool.Equipping = false
		newTool.CanAttack = false
		newTool.Grip = nil
		newTool.ViewModel = nil
		newTool.ViewAnimator = nil
		newTool.GUI = nil
		newTool.ClientModel = nil
		newTool.UHE = nil
		newTool.Percent = 1
		newTool.Defusing = false
		newTool.CurrentSlot = 0
		newTool.FlashCon = nil
		newTool.AbilitySlot1 = ""
		newTool.AbilitySlot2 = ""
		newTool.AbilityDataConn = nil
		newTool.DBAA = false
		newTool.PendingDefuseStart = false
		newTool._uheFolderConn = nil
		newTool._uheWaitConn = nil
		newTool._uheTimeConn = nil
		return newTool
	end

	function PDA:_bindToolEvents(timeoutSeconds, requireEquippedTool)
		local deadline = tick() + (tonumber(timeoutSeconds) or 0)
		repeat
			local toolValue = self.GTool and self.GTool:FindFirstChild("ToCurrentTool")
			local tool = toolValue and toolValue.Value
			local events = tool and tool:FindFirstChild("Events")
			local mouseFunc = events and events:FindFirstChild("MouseFunc")
			local isEquippedTool = not requireEquippedTool
				or (ClientPlayer.Character and tool and tool.Parent == ClientPlayer.Character)
			if tool and isEquippedTool and mouseFunc and mouseFunc:IsA("RemoteFunction") then
				if self.MouseFunc and self.MouseFunc ~= mouseFunc then
					pcall(function()
						self.MouseFunc.OnClientInvoke = nil
					end)
				end
				self.Tool = tool
				self.MouseFunc = mouseFunc
				self.MouseFunc.OnClientInvoke = function(success, animState)
					self:OnMouseFuncInvoke(success, animState)
				end
				return true
			end
			task.wait()
		until tick() >= deadline
		return false
	end
	
	function PDA:Retool()
		self.Model = self.GTool and self.GTool:FindFirstChild("ToModel") and self.GTool.ToModel.Value or self.Model
		self.Tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value or self.Tool
		if self.ClientModel and self.ClientModel.Main and self.ClientModel.Main.Screen then
			self.GUI = self.ClientModel.Main.Screen.SurfaceGui
		end
	end

	function PDA:_clearViewmodelState()
		self.ViewModel = nil
		self.ViewAnimator = nil
		self.GUI = nil
		self.ClientModel = nil
	end

	function PDA:_setWelcomeText()
		if not (self.GUI and self.GUI:FindFirstChild("Menu")) then
			return
		end

		local welcomeLabel = self.GUI.Menu:FindFirstChild("Welcome")
		if not (welcomeLabel and welcomeLabel:IsA("TextLabel")) then
			return
		end

		local characterName = ClientPlayer.Character and ClientPlayer.Character.Name or ClientPlayer.Name
		local welcomeString = "Welcome, " .. tostring(characterName)
		welcomeLabel.Text = welcomeString
		welcomeLabel.MaxVisibleGraphemes = 0

		task.spawn(function()
			for _ in utf8.graphemes(welcomeString) do
				welcomeLabel.MaxVisibleGraphemes += 1
				RunService.Heartbeat:Wait()
				RunService.Heartbeat:Wait()
				RunService.Heartbeat:Wait()
			end
		end)
	end

	function PDA:LoadViewModel()
		self:_clearViewmodelState()
		if _G.HideOtherVM then
			_G.HideOtherVM()
		end

		Remotes.Server.Inventory.EquipItem:FireServer(self.ID)
		task.wait()
		if not self:_bindToolEvents(2, true) then
			warn(("[PDA] Timed out waiting for equipped tool events (%s)"):format(tostring(self.ID)))
			return nil
		end

		self.Model = self.GTool and self.GTool:FindFirstChild("ToModel") and self.GTool.ToModel.Value or self.Model
		self.Tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value or self.Tool
		if not self.Tool then
			warn(("[PDA] Missing ToCurrentTool binding for %s"):format(tostring(self.ID)))
			return nil
		end

		local viewModel = LoadWeaponShell(self.Tool.Name)
		if not viewModel then
			LoadViewModelShell(#Viewmodels + 1)
			viewModel = LoadWeaponShell(self.Tool.Name)
		end

		if not viewModel then
			warn(("[PDA] Failed to load viewmodel shell for %s"):format(tostring(self.Tool.Name)))
			return nil
		end

		self.ViewModel = viewModel

		local animationController = self.ViewModel:FindFirstChild("AnimationController")
		if not animationController then
			animationController = Instance.new("AnimationController")
			animationController.Parent = self.ViewModel
		end

		self.ViewAnimator = self.ViewModel:FindFirstChild("Animator", true) or Instance.new("Animator", animationController)
		self.ClientModel = self.ViewModel:FindFirstChild(self.Tool.Name, true)
		if not self.ClientModel then
			warn(("[PDA] Client model %s missing from viewmodel shell %s"):format(tostring(self.Tool.Name), tostring(self.ViewModel:GetFullName())))
			return nil
		end

		local main = self.ClientModel.Main
		local screen = main and main.Screen
		local surfaceGui = screen and screen.SurfaceGui
		if not (surfaceGui and surfaceGui:IsA("SurfaceGui")) then
			warn(("[PDA] SurfaceGui missing from client model %s"):format(tostring(self.ClientModel:GetFullName())))
			return nil
		end

		self.GUI = surfaceGui
		self:_setWelcomeText()
		if _G.ViewmodelController and _G.ViewmodelController.DelayEquippedViewmodelVisible then
			_G.ViewmodelController:DelayEquippedViewmodelVisible(self.ViewModel, self.ClientModel, 0.1, function()
				setSurfaceGuisEnabled(self.ViewModel, true)
				setViewmodelArmsVisible(self.ViewModel, true)
			end)
		end

		self:_bindToolEvents(0.5, true)

		return self.ViewModel
	end
	function PDA:Initialize()
		self.GTool = self.Model
		self.Model = self.GTool and self.GTool:FindFirstChild("ToModel") and self.GTool.ToModel.Value or self.Model
		self.Tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value or self.Tool

		-- Initialize weapon configurations
		self.WeaponConfig = require(self.Tool:WaitForChild("WeaponConfig"))
		if not self.Tool.WeaponConfig:FindFirstChildOfClass("Configuration") then
			self.WeaponConfig = Framework.AddAttributes(self.WeaponConfig, self.Tool.WeaponConfig)
			wait()
		end
		self.WeaponConfigRaw = require(self.Tool:WaitForChild("WeaponConfig"))
		self.WeaponConfig = Framework.IndexAttribute(self.Tool.WeaponConfig.Configuration)
		self.AnimConfig = game.ReplicatedFirst.Assets.Animations:WaitForChild(self.Tool.Name)
		self.SoundFolder = self.Tool:WaitForChild("Sounds")
		self:_bindToolEvents(1)

		self.PlayerData = _G.PlayerData
		SavedData = _G.SavedData

		self.EquipTime = (self.WeaponConfig.EQUIP_TIME or 0) * 0.5
		self.WalkSpeed = self.WeaponConfig.WALKSPEED
		self.GetAbilityData = GetAbilityData
		self.GlobalEnum = require(ReplicatedStorage.Modules.Data.GlobalEnum)
		self.TransparencyTable = {}
		-- Event connections
		if self.AbilityDataConn then
			self.AbilityDataConn:Disconnect()
		end
		self.AbilityDataConn = AbilityDataUpdated.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end
			self.CurrentAbilityData = payload
			_G.CurrentAbilityData = payload
			if self.Equipped and self.GUI then
				self:RenderAbilities()
			end
		end)

		bindUHEFolder(self)
		
	
		
		
		-- Mobile controls
		if UserInputService.KeyboardEnabled == false then
			--ClientPlayer.PlayerGui.HUD:WaitForChild("Scope").InputBegan:Connect(function()
				self:OnMobileScopeInputBegan()
			--end)
			--ClientPlayer.PlayerGui.HUD:WaitForChild("Fire").InputEnded:Connect(function()
				self:OnMobileFireInputEnded()
			--end)
		end
	end

	function PDA:GetLatestAbilityData()
		local latest = nil
		if self.GetAbilityData then
			local ok, result = pcall(function()
				return self.GetAbilityData:InvokeServer()
			end)
			if ok and type(result) == "table" then
				latest = result
			end
		end
		if type(latest) ~= "table" then
			latest = _G.CurrentAbilityData
		end
		if type(latest) ~= "table" then
			latest = {}
		end
		self.CurrentAbilityData = latest
		_G.CurrentAbilityData = latest
	end

	function PDA:RenderAbilities()
		if not self.GUI then
			return
		end
		_G.CDUpdateFuncs = _G.CDUpdateFuncs or {}
		_G.AbilityCDs = _G.AbilityCDs or {}
		local readyColor = Color3.new(0, 1, 0.0666667)
		local inUseColor = Color3.new(1, 0, 0.0156863)
		local unavailableColor = Color3.fromRGB(128, 128, 128)

		local abilityPanels = {
			self.GUI:FindFirstChild("Ability1"),
			self.GUI:FindFirstChild("Ability2"),
		}

		self.AbilitySlot1 = ""
		self.AbilitySlot2 = ""

		for _, panel in ipairs(abilityPanels) do
			if panel then
				if panel:FindFirstChild("AbilityIcon") then
					panel.AbilityIcon.Image = ""
					panel.AbilityIcon.ImageColor3 = unavailableColor
					panel.AbilityIcon.ImageTransparency = 0.15
				end
				if panel:FindFirstChild("AbilityName") then
					panel.AbilityName.Text = "UNAVAILABLE"
					panel.AbilityName.TextColor3 = unavailableColor
				end
				if panel:FindFirstChild("Status") then
					panel.Status.Text = "UNAVAILABLE"
					panel.Status.TextColor3 = unavailableColor
				end
			end
		end

		local abilities = {}
		local source = self.CurrentAbilityData and self.CurrentAbilityData.Abilities
		if type(source) == "table" then
			for _, abilityName in ipairs(source) do
				if type(abilityName) == "string" and abilityName ~= "" then
					table.insert(abilities, abilityName)
				end
			end
		end
		table.sort(abilities, function(a, b)
			return string.len(a) < string.len(b)
		end)

		for index = 1, math.min(2, #abilities) do
			local abilityName = abilities[index]
			local panel = abilityPanels[index]
			if panel then
				if panel:FindFirstChild("AbilityIcon") then
					panel.AbilityIcon.Image = self.GlobalEnum.AbilityIcon[abilityName] or "" -- Omitted: authored fallback icon asset.
					panel.AbilityIcon.ImageColor3 = Color3.new(1, 1, 1)
					panel.AbilityIcon.ImageTransparency = 0
				end
				if panel:FindFirstChild("AbilityName") then
					panel.AbilityName.Text = string.upper(abilityName)
					panel.AbilityName.TextColor3 = Color3.new(1, 1, 1)
				end
				if panel:FindFirstChild("Status") then
					local cooldownEnd = _G.AbilityCDs[abilityName]
					local remaining = getCooldownRemaining(cooldownEnd)
					if remaining > 0 then
						panel.Status.Text = "IN USE (" .. remaining .. ")"
						panel.Status.TextColor3 = inUseColor
					else
						_G.AbilityCDs[abilityName] = nil
						panel.Status.Text = "READY"
						panel.Status.TextColor3 = readyColor
					end
				end
			end

			if index == 1 then
				self.AbilitySlot1 = abilityName
			else
				self.AbilitySlot2 = abilityName
			end

			local boundPanel = panel
			local boundAbilityName = abilityName
			_G.CDUpdateFuncs[boundAbilityName] = function(Time)
				if not self.GUI or not boundPanel or not boundPanel:FindFirstChild("Status") then
					return
				end
				local duration = sanitizeCooldownDuration(Time)
				if duration <= 0 then
					boundPanel.Status.Text = "READY"
					boundPanel.Status.TextColor3 = readyColor
					return
				end
				for i = 1, duration, 1 do
					boundPanel.Status.TextColor3 = inUseColor
					boundPanel.Status.Text = "IN USE (" .. math.max(0, duration - i) .. ")"
					task.wait(1)
					if getCooldownRemaining(_G.AbilityCDs[boundAbilityName]) <= 0 then
						break
					end
				end
				boundPanel.Status.Text = "READY"
				boundPanel.Status.TextColor3 = readyColor
			end
		end
	end

	function PDA:Equip()
		self.Tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value or self.Tool

		TweenPropertyOut(workspace.CurrentCamera, "FieldOfView", 0.1, tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value))

		self.Equipping = true
		_G.EquippingItem = self
		_G.HideOtherVM()
		
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
		

		InputService.MouseIconEnabled = false

		self.SoundFolder = self.Tool and self.Tool:FindFirstChild("Sounds") or self.SoundFolder
		local deploySound = self.SoundFolder and self.SoundFolder:FindFirstChild("Deploy")
		if deploySound and deploySound:IsA("Sound") then
			deploySound:Play()
		end

		ClientPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		InputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		local LVM = self:LoadViewModel()
		if not LVM then
			self.Equipping = false
			if _G.EquippingItem == self then
				_G.EquippingItem = nil
			end
			return
		end

		_G.CurrentCVM = LVM
		self.SoundFolder = self.Tool:WaitForChild("Sounds")

		InputService.MouseDeltaSensitivity = tonumber(SavedData.PlayerSettings.ControlSettings.Sensitivity.Value) or 1

		workspace.CurrentCamera.FieldOfView = tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value) or workspace.CurrentCamera.FieldOfView

		-- Stop any playing animations
		for i, v in next, self.ViewAnimator:GetPlayingAnimationTracks() do
			v:Stop()
		end
		
		self.CL_EQUIP = self.ViewAnimator:LoadAnimation(self.AnimConfig.CL_EQUIP)
		self.CL_EQUIP.Priority = Enum.AnimationPriority.Movement
		self.CL_IDLE = self.ViewAnimator:LoadAnimation(self.AnimConfig.CL_IDLE)
		self.CL_IDLE.Priority = Enum.AnimationPriority.Idle
		self.CL_DEFUSE = self.ViewAnimator:LoadAnimation(self.AnimConfig.CL_DEFUSE)
		self.CL_DEFUSE.Priority = Enum.AnimationPriority.Action
		self.CL_DEFUSECOMPLETE = self.ViewAnimator:LoadAnimation(self.AnimConfig.CL_DEFUSECOMPLETE)
		self.CL_DEFUSECOMPLETE.Priority = Enum.AnimationPriority.Action2
		self.CL_DEFUSE.Looped = true
		self.CL_DEFUSECOMPLETE.Looped = false
		self.CL_IDLE.Looped = true
		self.CL_EQUIP.Looped = false

		-- Play equip animation
		self.CL_EQUIP:Play(0)

		-- Viewmodel setup is handled by LoadViewModel.
		self.GUI = self.ClientModel.Main.Screen.SurfaceGui

		function self:SetPercent(num)
			self.GUI = self.ClientModel.Main.Screen.SurfaceGui

			self.Percent = math.clamp(tonumber(num) or 0, 0, 1)
			--print("SetPercent : " .. num)
			if self.ClientModel then
				self.GUI.Defuse.DefuseMeter:TweenSize(UDim2.new(1, 0, self.Percent, 0), Enum.EasingDirection.In, Enum.EasingStyle.Sine, 0.10)
			end
			if (self.Defusing or self.PendingDefuseStart) and self.GUI and self.GUI.Defuse and not self.GUI.Defuse.Visible then
				self:Switch("")
			end
		end

		self.CurrentSlot = 0
		self.CurrentPlayer = ClientPlayer.Name
		self:GetLatestAbilityData()
		self:RenderAbilities()

		if self.FlashCon ~= nil then self.FlashCon:Disconnect() end

		local fcfunc = function()
			if not self.GUI:FindFirstChild("Ability1") then self.FlashCon:Disconnect() return end
			task.wait(0.5)
			if self.GUI  then
				self.GUI.Ability1.Status.Visible = true
				self.GUI.Ability2.Status.Visible = true
			else
				self.FlashCon:Disconnect()
			end
			task.wait(0.5)
			if self.GUI  then
				self.GUI.Ability1.Status.Visible = false
				self.GUI.Ability2.Status.Visible = false
			else
				self.FlashCon:Disconnect()
			end
		end

		self.FlashCon = RunService.Heartbeat:Connect(function()
			if not self.Equipped then
				self.FlashCon:Disconnect()
				return
			end
			pcall(fcfunc)
		end)

		setViewmodelArmsVisible(self.ViewModel, true)
		
		
		-- Hide the server model
	
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
			if self.Defusing or self.PendingDefuseStart then
				self.PendingDefuseStart = false
				self:Switch("")
				if self.CL_IDLE then
					self.CL_IDLE:Stop(0.05)
				end
				if self.CL_DEFUSE and not self.CL_DEFUSE.IsPlaying then
					self.CL_DEFUSE:Play(0.05)
				end
			else
				self:Switch("Default")
				if self.CL_IDLE then
					self.CL_IDLE:AdjustWeight(1, 0.08)
					self.CL_IDLE:Play(0.08)
				end
			end
		end

	
		
		if self.SFG then
			coroutine.wrap(function()
				for i = 1,100,1 do
					task.wait(0.1)
					if self.Equipped == true and self.SFG then
						self.SFG.Enabled = false
					elseif self.SFG then
						self.SFG.Enabled = true
						break
					end
				end
			end)()
		end

		-- task.delay(0.2, function()
		-- 	if not self.ViewModel or not self.ClientModel then
		-- 		return
		-- 	end
		-- 	if _G.ViewmodelController and _G.ViewmodelController.EnsureEquippedViewmodelVisible then
		-- 		_G.ViewmodelController:EnsureEquippedViewmodelVisible(self.ViewModel, self.ClientModel)
		-- 	end
		-- 	setViewmodelArmsVisible(self.ViewModel, true)
		-- 	if self.ViewModel then
		-- 		setSurfaceGuisEnabled(self.ViewModel, true)
		-- 	end
		-- end)

		-- task.delay(0.6, function()
		-- 	if self.Equipped then
		-- 		if not self.ViewModel or not self.ClientModel then
		-- 			return
		-- 		end
		-- 		if _G.ViewmodelController and _G.ViewmodelController.EnsureEquippedViewmodelVisible then
		-- 			_G.ViewmodelController:EnsureEquippedViewmodelVisible(self.ViewModel, self.ClientModel)
		-- 		end
		-- 		setViewmodelArmsVisible(self.ViewModel, true)
		-- 		if self.ViewModel then
		-- 			setSurfaceGuisEnabled(self.ViewModel, true)
		-- 		end
		-- 	end
		-- end)
		
	end

	function PDA:Unequip()
		if self._unequipping then return end
		self._unequipping = true
		local id = self.ID
		local viewModel = self.ViewModel
		local model = self.Model
		self.Equipped = false
		self.Equipping = false
		self.CanAttack = false
		if _G.Equipped == self then
			_G.Equipped = nil
		end
		if _G.EquippingItem == self then
			_G.EquippingItem = nil
		end
		pcall(function()
			if self.MouseFunc then
				self.MouseFunc.OnClientInvoke = nil
			end
		end)
		pcall(function()
			if self.FlashCon then self.FlashCon:Disconnect() self.FlashCon = nil end
			if self._uheFolderConn then self._uheFolderConn:Disconnect() self._uheFolderConn = nil end
			if self._uheWaitConn then self._uheWaitConn:Disconnect() self._uheWaitConn = nil end
			if self._uheTimeConn then self._uheTimeConn:Disconnect() self._uheTimeConn = nil end
		end)
		pcall(function()
			if self.ViewAnimator then
				for _, v in next, self.ViewAnimator:GetPlayingAnimationTracks() do
					v:Stop(0)
				end
			end
		end)
		pcall(function()
			if viewModel then
				setSurfaceGuisEnabled(viewModel, false)
			end
			Framework.TransparencyControl(self.TransparencyTable, "Show", model)
			if viewModel and viewModel["Left Arm"] then
				for _, v in pairs(viewModel:GetDescendants()) do
					if v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal") then
						v.Transparency = 1
					elseif v:IsA("RopeConstraint") then
						v.Visible = false
					end
				end
			end
		end)
		pcall(function()
			Remotes.Server.Inventory.UnequipItem:FireServer(id)
		end)
		self._unequipping = false
		
	end

	function PDA:HandleInputBegan(Input, InputSank)
		if InputSank then return end
		if Input.UserInputType == Enum.UserInputType.MouseButton1 and self.Equipped and not InputSank then
			self:ActivateAbility()
		end
		if Input.UserInputType == Enum.UserInputType.MouseButton2 and not InputSank then
			if not self.Equipped then return end
			self:Scroll()
		end
	end

	function PDA:HandleInputEnded(Input, InputSank)
	end

	function PDA:OnMobileScopeInputBegan()
		if self.Equipped == true and self.CanAttack == true and self.PlayerData.CanUse.Value == "true" then
			self:Scroll()
		end
	end

	function PDA:OnMobileFireInputEnded()
		if self.Equipped == true and self.PlayerData.CanUse.Value == "true" then
			self:ActivateAbility()
		end
	end

	function PDA:ActivateAbility()
		if self.CurrentSlot == 1 and self.GUI and self.DBAA == false then
			self.DBAA = true
			Remotes.Client.UseAbility:FireServer(self.AbilitySlot1, ClientCamera.CFrame)
			self.SoundFolder.Activate:Play()
			task.wait(0.5)
			self.DBAA = false
		elseif self.CurrentSlot == 2 and self.GUI and self.DBAA == false and self.AbilitySlot2 ~= "" then
			self.DBAA = true
			Remotes.Client.UseAbility:FireServer(self.AbilitySlot2, ClientCamera.CFrame)
			self.SoundFolder.Activate:Play()
			task.wait(0.5)
			self.DBAA = false
		end
	end

	function PDA:Scroll()
		self.SoundFolder.Deploy:Play()
		if self.CurrentSlot == 2 then
			self.CurrentSlot = 1
			self:Switch("Ability" .. self.CurrentSlot)
		else
			self.CurrentSlot += 1
			self:Switch("Ability".. self.CurrentSlot)
		end
	end

	function PDA:Switch(Key)
		if not self.GUI then return end

		if ClientPlayer.Character.HumanoidRootPart:FindFirstChild("Hacked") then
			self.GUI.Menu.Visible = false
			self.GUI.Defuse.Visible = false
			self.GUI.Ability1.Visible = false
			self.GUI.Ability2.Visible = false
			self.GUI.Hack.Visible = true
			coroutine.wrap(function()
				task.wait(3)
				self.GUI.Hack.Visible = false
			end)()
		elseif tostring(Key) == "Default" then
			self.CurrentSlot = 0
			self.GUI.Menu.Visible = true
			self.GUI.Defuse.Visible = false
			self.GUI.Ability1.Visible = false
			self.GUI.Ability2.Visible = false
		elseif tostring(Key) == "Ability1" then
			self.GUI.Menu.Visible = false
			self.GUI.Defuse.Visible = false
			self.GUI.Ability1.Visible = true
			self.GUI.Ability2.Visible = false
		elseif tostring(Key) == "Ability2" then
			self.GUI.Menu.Visible = false
			self.GUI.Defuse.Visible = false
			self.GUI.Ability2.Visible = true
			self.GUI.Ability1.Visible = false
		else
			self.CurrentSlot = 0
			self.GUI.Menu.Visible = false
			self.GUI.Defuse.Visible = true
			self.GUI.Ability1.Visible = false
			self.GUI.Ability2.Visible = false
		end
		if self.Equipped then
			self.GUI.Enabled = true
		else
			self.GUI.Enabled = false
		end
	end

	function PDA:OnMouseFuncInvoke(Success, AnimState)
		if AnimState then
			self.Defusing = false
			self.PendingDefuseStart = false
			if self.CL_DEFUSE then
				self.CL_DEFUSE:Stop(0.05)
			end
			if self.CL_DEFUSECOMPLETE then
				self.CL_DEFUSECOMPLETE:Play()
			end
			self:Switch("Default")
			self.SoundFolder.DefuseEnd:Play()
		elseif Success then
			self.Defusing = true
			self.PendingDefuseStart = true
			if not self.Equipped and _G.ForceEquip then
				_G.ForceEquip("PDA")
			end
			local equipDeadline = tick() + 1.5
			while not self.Equipped and tick() < equipDeadline do
				task.wait()
			end
			local animDeadline = tick() + 1.5
			while not self.CL_DEFUSE and tick() < animDeadline do
				task.wait()
			end
			if self.CL_DEFUSE then
				self.PendingDefuseStart = false
				if not self.CL_DEFUSE.IsPlaying then
					self.CL_DEFUSE:Play(0.05)
				end
			end
			self:Switch("")
			task.defer(function()
				if self.Equipped and self.Defusing then
					self:Switch("")
				end
			end)
		else
			self.Defusing = false
			self.PendingDefuseStart = false
			if self.CL_DEFUSE and self.CL_DEFUSE.IsPlaying then
				self.CL_DEFUSE:Stop(0.05)
			end
			self:Switch("Default")
		end
	end

	function PDA:OnUHEAdded()
		local uheFolder = IgnoreFolder:FindFirstChild(UHEFolderName)
		if not uheFolder then
			return
		end

		local uheModel = uheFolder:FindFirstChild("UHE-4")
		if not uheModel then
			for _, child in ipairs(uheFolder:GetChildren()) do
				if child:IsA("Model") and child:FindFirstChild("Main") and child.Main:FindFirstChild("Time") then
					uheModel = child
					break
				end
			end
		end
		if not uheModel or self.UHE == uheModel then
			return
		end

		self.UHE = uheModel
		if self._uheTimeConn then
			self._uheTimeConn:Disconnect()
			self._uheTimeConn = nil
		end

		local mainPart = self.UHE:WaitForChild("Main")
		local timeValue = mainPart:WaitForChild("Time")

		local function updatePercent()
			local configuredDefuseTime = tonumber(GameObjects:FindFirstChild("UHEDefuseTime") and GameObjects.UHEDefuseTime.Value) or 3
			local percent = 0
			if configuredDefuseTime > 0 then
				percent = math.clamp(timeValue.Value / configuredDefuseTime, 0, 1)
			end
			if self.SetPercent then
				self:SetPercent(percent)
			end
			if self.Equipped and (self.Defusing or self.PendingDefuseStart) then
				self:Switch("")
			end
		end

		updatePercent()
		self._uheTimeConn = timeValue:GetPropertyChangedSignal("Value"):Connect(updatePercent)
	end

	return PDA
end

return Module
