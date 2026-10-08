local Module = {}

Module.Init = function(context)
	local Knife = _G.Tool:Extend()
	local Tool = _G.Tool

	local Environment = context or {}
	
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ReplicatedFirst = game:GetService("ReplicatedFirst")
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
	local SoundService = game:GetService("SoundService")
	local Debris = game:GetService("Debris")
	local HitSoundsFolder = ReplicatedFirst:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("HitSounds")
	local Viewmodels = _G.ViewmodelController.Viewmodels

	local function hideViewmodelArms(viewModel)
		if not viewModel then
			return
		end

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
	end

	local function safeUnit(v: Vector3, fallback: Vector3): Vector3
		local m = v.Magnitude
		if m > 1e-6 then
			return v / m
		end
		return fallback
	end

	local function getReferenceValue(gTool, valueName)
		local valueObj = gTool and gTool:FindFirstChild(valueName)
		if valueObj and valueObj:IsA("ObjectValue") then
			return valueObj.Value
		end
		return nil
	end

	local function getMeleeRaycast(character, range)
		local camera = workspace.CurrentCamera
		local head = character and character:FindFirstChild("Head")
		local direction = camera and camera.CFrame.LookVector or (head and head.CFrame.LookVector) or Vector3.new(0, 0, -1)
		direction = safeUnit(direction, Vector3.new(0, 0, -1))

		local origin = camera and camera.CFrame.Position or (head and head.Position) or Vector3.zero
		origin += direction * 0.5

		return origin, direction * (range or 0)
	end

	local function playMeleeImpactSound(hitPart)
		if not (Framework and Framework.PlayHitSound and hitPart) then
			return
		end

		local sound = HitSoundsFolder:FindFirstChild("Bullet" .. tostring(math.random(1, 3)))
		if sound and sound:IsA("Sound") then
			Framework.PlayHitSound(sound, hitPart)
		end
	end

	local function isInvisibleRaycastPart(part)
		if not (part and part:IsA("BasePart")) then
			return false
		end

		return (part.Transparency or 0) >= 0.99 or (part.LocalTransparencyModifier or 0) >= 0.99
	end

	local function raycastIgnoringInvisible(origin, direction, params)
		local directionLength = direction.Magnitude
		if directionLength <= 0 then
			return nil
		end

		local unit = safeUnit(direction, Vector3.new(0, 0, -1))
		local remainingOrigin = origin
		local remainingLength = directionLength

		for _ = 1, 12 do
			if remainingLength <= 0 then
				return nil
			end

			local hit = workspace:Raycast(remainingOrigin, unit * remainingLength, params)
			if not hit then
				return nil
			end

			if not isInvisibleRaycastPart(hit.Instance) then
				return hit
			end

			local traveled = (hit.Position - remainingOrigin).Magnitude
			local step = math.max(traveled + 0.05, 0.1)
			remainingOrigin = remainingOrigin + unit * step
			remainingLength -= step
		end

		return nil
	end

	function Knife:_spawnSurfaceSlash(hitPosition: Vector3, hitNormal: Vector3, attackDir: Vector3)
		local normal = safeUnit(hitNormal, Vector3.yAxis)
		local dir = safeUnit(attackDir, -normal)

		local tangent = normal:Cross(dir)
		if tangent.Magnitude < 1e-4 then
			tangent = normal:Cross(Vector3.yAxis)
			if tangent.Magnitude < 1e-4 then
				tangent = normal:Cross(Vector3.xAxis)
			end
		end
		tangent = safeUnit(tangent, Vector3.xAxis)
		local up = safeUnit(tangent:Cross(normal), Vector3.yAxis)

		local angle = (math.random() - 0.5) * math.rad(30)
		up = CFrame.fromAxisAngle(normal, angle):VectorToWorldSpace(up)

		local ignoreFolder = workspace:FindFirstChild("Ignore")
		local parent = ignoreFolder or workspace:FindFirstChild("Effects") or workspace:FindFirstChild("Debris") or workspace.Terrain

		local mark = Instance.new("Part")
		mark.Name = "KnifeSlashMark"
		mark.Anchored = true
		mark.CanCollide = false
		mark.CanQuery = false
		mark.CanTouch = false
		mark.CastShadow = false
		mark.Material = Enum.Material.SmoothPlastic
		mark.Color = Color3.fromRGB(15, 15, 15)
		mark.Transparency = 0.25
		mark.Size = Vector3.new(1.25, 0.06, 0.01)
		mark.CFrame = CFrame.lookAt(hitPosition + normal * 0.02, hitPosition + normal, up)
		mark.Parent = parent

		local visibleTime = 4
		local fadeTime = 0.75
		task.delay(visibleTime, function()
			if mark.Parent then
				TweenService:Create(mark, TweenInfo.new(fadeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Transparency = 1,
				}):Play()
			end
		end)
		Debris:AddItem(mark, visibleTime + fadeTime + 0.25)
	end

	local function getInspectKeyCode()
		local keyName = SavedData
			and SavedData:FindFirstChild("PlayerSettings")
			and SavedData.PlayerSettings:FindFirstChild("ControlSettings")
			and SavedData.PlayerSettings.ControlSettings:FindFirstChild("InspectKey")
			and SavedData.PlayerSettings.ControlSettings.InspectKey.Value
		if type(keyName) ~= "string" or keyName == "" then
			keyName = "F"
		end
		return Enum.KeyCode[keyName] or Enum.KeyCode.F
	end


	function Knife.New(Model)
		local newTool = Tool.New("Knife", Model)
		setmetatable(newTool, Knife)

		newTool.CanInspect = true
		newTool.Equipped = false
		newTool.Equipping = false
		newTool.CanAttack = true
		newTool.IGList = {}
		newTool.LastEquipReconcile = 0
		newTool.ReconcileCon = nil

		return newTool
	end

	function Knife:_bindToolEvents(timeoutSeconds, requireEquippedTool)
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
				if mouseEvent then
					self.Tool = tool
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

	function Knife:_reconcileServerEquip()
		if not (self.Equipped and self.ID and ClientPlayer.Character) then
			return
		end
		if self.Equipping or (self.CanAttack == false) then
			return
		end
		self:_bindToolEvents(0)
		if not self.Tool then
			return
		end
		if self.Tool.Parent ~= ClientPlayer.Character then
			return
		end
		local meleeServer = self.Tool:FindFirstChild("MeleeServer")
		local isEquippedFlag = meleeServer and meleeServer:FindFirstChild("IsEquipped")
		if not (isEquippedFlag and isEquippedFlag:IsA("BoolValue")) then
			return
		end
		if isEquippedFlag.Value then
			return
		end
		local now = tick()
		if now - (self.LastEquipReconcile or 0) < 0.75 then
			return
		end
		self.LastEquipReconcile = now
		Remotes.Server.Inventory.EquipItem:FireServer(self.ID)
	end

	function Knife:_applyReplicatedSkin()
		local skinValue = self.MainPart and self.MainPart:FindFirstChild("Skin")
		local skinName = skinValue and tostring(skinValue.Value) or ""
		if skinName == "" or skinName == "Stock" or not self.ClientModel then
			return
		end
		local applied = self.ClientModel:FindFirstChild("AppliedSkin")
		if applied and applied.Value == skinName then
			return
		end
		if applied then
			applied:Destroy()
		end
		local charm = self.ClientModel:FindFirstChild("WeaponCharm")
		if charm then
			charm:Destroy()
		end
		ContainerService.ApplySkin(self.ClientModel, self.Tool.Name, skinName)
	end

	function Knife:_bindSkinUpdates()
		if self.SkinCon then
			self.SkinCon:Disconnect()
			self.SkinCon = nil
		end
		local skinValue = self.MainPart and self.MainPart:FindFirstChild("Skin")
		if skinValue then
			self.SkinCon = skinValue:GetPropertyChangedSignal("Value"):Connect(function()
				self:_applyReplicatedSkin()
			end)
		end
		self:_applyReplicatedSkin()
	end

	function Knife:_playLocalToolSound(soundName)
		local template = self.SoundFolder and self.SoundFolder:FindFirstChild(soundName)
		if not (template and template:IsA("Sound")) then
			return
		end
		local sound = template:Clone()
		SoundService:PlayLocalSound(sound)
		Debris:AddItem(sound, (sound.TimeLength > 0 and sound.TimeLength + 0.1) or 3)
	end



	function Knife:Initialize()
		self.GTool = self.Model
		self.Model = getReferenceValue(self.GTool, "ToModel")
		self.Tool = getReferenceValue(self.GTool, "ToCurrentTool")
		self.MainPart = self.Model.Main
		if not self:_bindToolEvents(2) then
			local toolValue = self.GTool:WaitForChild("ToCurrentTool")
			while not toolValue.Value do
				task.wait()
			end
			self.Tool = toolValue.Value
			local events = self.Tool:WaitForChild("Events")
			self.MouseEvent = events:WaitForChild("MouseEvent")
		end
		self.WeaponConfig = require(self.Tool:WaitForChild("WeaponConfig"))
		self.ConfigAnim = game.ReplicatedFirst.Assets.Animations:WaitForChild(self.Name)

		self.SoundFolder = self.Tool:WaitForChild("Sounds")

		self.MeleeStudRange = self.WeaponConfig.RANGE
		self.EquipTime = (self.WeaponConfig.EQUIP_TIME or 0) * 0.5
		self.AttackWait = self.WeaponConfig.ATTACK_WAIT
		self.MeleeCooldown = self.WeaponConfig.ATTACK_COOLDOWN
		self.WalkSpeed = self.WeaponConfig.WALKSPEED

		if self.ReconcileCon then
			self.ReconcileCon:Disconnect()
		end
		self.ReconcileCon = RunService.RenderStepped:Connect(function()
			self:_reconcileServerEquip()
		end)

		
	end

	function Knife:SetupAnimations()
		local ViewAnimator = self.ViewAnimator
		self.CL_EQUIP = ViewAnimator:LoadAnimation(self.ConfigAnim.CL_EQUIP)
		self.CL_EQUIP.Priority = Enum.AnimationPriority.Movement
		
		if self.ConfigAnim:FindFirstChild("CL_EQUIP2") then
			self.CL_EQUIP2 = ViewAnimator:LoadAnimation(self.ConfigAnim.CL_EQUIP2)
			self.CL_EQUIP2.Priority = Enum.AnimationPriority.Movement
		end
		if self.ConfigAnim:FindFirstChild("CL_EQUIP3") then
			self.CL_EQUIP3 = ViewAnimator:LoadAnimation(self.ConfigAnim.CL_EQUIP3)
			self.CL_EQUIP3.Priority = Enum.AnimationPriority.Movement
		end
		self.CL_IDLE = ViewAnimator:LoadAnimation(self.ConfigAnim.CL_IDLE)
		self.CL_IDLE.Priority = Enum.AnimationPriority.Core
		self.CL_INSPECT = ViewAnimator:LoadAnimation(self.ConfigAnim.CL_INSPECT)
		self.CL_BACKSTAB = ViewAnimator:LoadAnimation(self.ConfigAnim.CL_BACKSTAB)
		self.CL_ATTACK1 = ViewAnimator:LoadAnimation(self.ConfigAnim:WaitForChild("CL_ATTACK1"))
		
		self.CL_ATTACK2 = ViewAnimator:LoadAnimation(self.ConfigAnim:WaitForChild("CL_ATTACK2"))
		self.CL_ATTACK3 = ViewAnimator:LoadAnimation(self.ConfigAnim:WaitForChild("CL_ATTACK3"))
		self.CL_INSPECTLOOP = self.ConfigAnim:FindFirstChild("CL_INSPECTLOOP") and ViewAnimator:LoadAnimation(self.ConfigAnim:FindFirstChild("CL_INSPECTLOOP"))
		self.CL_ATTACK1.Priority = Enum.AnimationPriority.Action
		self.CL_ATTACK2.Priority = Enum.AnimationPriority.Action
		self.CL_ATTACK3.Priority = Enum.AnimationPriority.Action
		self.CL_IDLE.Looped = true
		self.CL_BACKSTAB.Looped = false
		self.CL_BACKSTAB.Priority = Enum.AnimationPriority.Action2
		if self.CL_INSPECTLOOP then
			self.CL_INSPECTLOOP.Looped = true
		end
	end
	
	function Knife:Equip()
		if self.SoundFolder:FindFirstChild("Inspect") then
			self.SoundFolder.Inspect:Stop()
		end
		self.IGList = {}
		self.Inspecting = false
		if self.cnt_Inspect then
			self.cnt_Inspect:Disconnect()
			self.cnt_Inspect = nil
		end
		if self.cnt_GBI then
			self.cnt_GBI:Disconnect()
			self.cnt_GBI = nil
		end

		_G.CurrentWeaponSign = Framework.GetKnifeWeight(self.Tool.Name)

		-- Populate IGList
		for i, v in next, workspace:GetDescendants() do
			if v:IsA("Accessory") then
				table.insert(self.IGList, v)
			elseif not v:IsA("Model") and string.find(v.Name, "_Shader") then
				table.insert(self.IGList, v)
			end
			if v.Name == "LeftGlove" or v.Name == "RightGlove" then
				table.insert(self.IGList, v)
			end
		end

		-- MainPart Owner Check
		local mainPart = self.MainPart
		local ownerValue = mainPart and mainPart:FindFirstChild("Owner")
		local soundsFolder = mainPart and mainPart:FindFirstChild("Sounds")
		if ownerValue and ownerValue:IsA("StringValue") and ClientPlayer.Character.Name == ownerValue.Value then
			if soundsFolder then
				for _, sound in pairs(soundsFolder:GetChildren()) do
					if sound:IsA("Sound") then
						sound.Volume = 0
					end
				end
			end
		end

		table.insert(self.IGList, self.Tool.Parent)
		table.insert(self.IGList, workspace.Ignore)
		table.insert(self.IGList, ClientPlayer.Character)

		self.CanInspect = true
		self.Equipping = true

		self:_playLocalToolSound("Deploy")
		ClientPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		InputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		self:LoadViewModel()
		
		self:SetupAnimations()
		
		self.CL_IDLE:Play()

		local equipRoll = math.random(1, 3)
		if equipRoll == 2 and self.CL_EQUIP2 then
			self.CL_EQUIP2:Play(0, 3)
		elseif equipRoll == 3 and self.CL_EQUIP3 then
			self.CL_EQUIP3:Play(0, 3)
		else
			self.CL_EQUIP:Play(0, 3)
		end

		self:FinalizeEquip()
	end
	
	function Knife:LoadViewModel()
		-- Load view model into Camera
		_G.HideOtherVM()
		
		Remotes.Server.Inventory.EquipItem:FireServer(self.ID)
		task.wait()
		if not self:_bindToolEvents(2, true) then
			self.Equipping = false
			warn(("[Knife] Timed out waiting for equipped tool events (%s)"):format(tostring(self.ID)))
			return
		end
		self.Model = getReferenceValue(self.GTool, "ToModel")
		self.MainPart = self.Model and self.Model:FindFirstChild("Main") or self.MainPart
		
		local LVM = LoadWeapon(self.Tool.Name)
		if not LVM then
			LoadViewModel(#Viewmodels + 1)
			LVM = LoadWeapon(self.Tool.Name)
		end

		_G.CurrentCVM = LVM

		self.ViewModel = LVM

		self.ViewAnimator = LVM:FindFirstChild("Animator",true) or Instance.new("Animator",LVM:WaitForChild("AnimationController") )

		self.ClientModel = self.ViewModel:FindFirstChild(self.Tool.Name,true)
		self:_bindSkinUpdates()
		if _G.ViewmodelController and _G.ViewmodelController.DelayEquippedViewmodelVisible then
			_G.ViewmodelController:DelayEquippedViewmodelVisible(self.ViewModel, self.ClientModel, 0.1)
		end


		if self.ViewModel["Right Arm"]:FindFirstChild("RightGrip") then
			self.ViewModel["Right Arm"].RightGrip.C1 = CFrame.new()
			self.ViewModel["Right Arm"].RightGrip.C0 = CFrame.new()
		end
		if self.ViewModel["Left Arm"]:FindFirstChild("LeftGrip") then
			self.ViewModel["Left Arm"].LeftGrip.C1 = CFrame.new()
			self.ViewModel["Left Arm"].LeftGrip.C0 = CFrame.new()
		end

		if self.WeaponConfig.C0 then
			self.ViewModel["Right Arm"].RightGrip.C0 = self.WeaponConfig.C0
		end
		if self.WeaponConfig.C1 then
			self.ViewModel["Right Arm"].RightGrip.C1 = self.WeaponConfig.C1
		end

		-- The server swaps the backing Tool instance during equip, so refresh the
		-- binding after the new tool is definitely present in the character.
		self:_bindToolEvents(0.5, true)

	
	end
	
	function Knife:FinalizeEquip()
		-- Apply Skin if any
		local skinValue = self.MainPart and self.MainPart:FindFirstChild("Skin")
		local ownerValue = self.MainPart and self.MainPart:FindFirstChild("Owner")
		if skinValue and skinValue.Value == "Stock" then
			-- default stock, nothing to do
		elseif not skinValue
			or skinValue.Value == ""
			or not ownerValue
			or ownerValue.Value == ""
			or not self.Tool.WeaponModel:FindFirstChild("AppliedSkin") then
			if SavedData[ClientPlayer.Team.Name .. "Loadout"] then
				if SavedData[ClientPlayer.Team.Name .. "Loadout"]:FindFirstChild("KnifeType") then
					local SkinSlot = SavedData[ClientPlayer.Team.Name .. "Loadout"]["KnifeSkin"].Value
					local FoundApplied = self.Tool.WeaponModel:FindFirstChild("AppliedSkin")
					if FoundApplied and FoundApplied.Value ~= SkinSlot then
						if SkinSlot ~= "Stock" then
							ContainerService.ApplySkin(self.ClientModel, self.Tool.Name, FoundApplied.Value)
							if self.IsDual then
								ContainerService.ApplySkin(self.ClientModel2, self.Tool.Name, FoundApplied.Value)
							end
						end
					else
						if SkinSlot ~= "Stock" then
							ContainerService.ApplySkin(self.ClientModel, self.Tool.Name, SkinSlot)
							if self.IsDual then
								ContainerService.ApplySkin(self.ClientModel2, self.Tool.Name, SkinSlot)
							end
						end
					end
				end
			end
		else
			ContainerService.ApplySkin(self.ClientModel, self.Tool.Name, self.MainPart.Parent.AppliedSkin.Value)
		end

		task.delay(0, function()
			self:ApplyGloveTransparency()
		end)

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

		end
	end
	
	function Knife:ApplyGloveTransparency()
		local hideShellArms = self.Tool and self.Tool.Name == "Knife"
		if hideShellArms then
			hideViewmodelArms(self.ViewModel)
		else
			if not self.ViewModel["Left Arm"]:FindFirstChild("TransparencyTag") then
				self.ViewModel["Left Arm"].Transparency = 0
			else
				self.ViewModel["Left Arm"].Transparency = self.ViewModel["Left Arm"]:FindFirstChild("TransparencyTag").Value
			end

			if not self.ViewModel["Right Arm"]:FindFirstChild("TransparencyTag") then
				self.ViewModel["Right Arm"].Transparency = 0
			else
				self.ViewModel["Right Arm"].Transparency = self.ViewModel["Right Arm"]:FindFirstChild("TransparencyTag").Value
			end

			local Data = SavedData
			local Loadout = Data[ClientPlayer.Team.Name .. "Loadout"]
			local GloveSlot = Loadout:WaitForChild("GloveSkin")

			if GloveSlot.Value ~= "None" or self.ViewModel:FindFirstChild("ShowBothGloves") then
				self.ViewModel["Left Arm"].LeftGlove.Transparency = 0
				self.ViewModel["Right Arm"].RightGlove.Transparency = 0
			end

			if self.ViewModel:FindFirstChild("ShowRightGlove") then
				self.ViewModel["Right Arm"].RightGlove.Transparency = 0
				self.ViewModel["Left Arm"].LeftGlove.Transparency = 1
			end

			if self.ViewModel:FindFirstChild("ShowLeftGlove") then
				self.ViewModel["Left Arm"].LeftGlove.Transparency = 0
				self.ViewModel["Right Arm"].RightGlove.Transparency = 1
			end
		end

		for _, v in next, self.Model:GetDescendants() do
			if v:IsA("BasePart") then
				v.LocalTransparencyModifier = 1
			end
		end
	end
	
	function Knife:Unequip()
		if self.SoundFolder:FindFirstChild("Inspect") then
			self.SoundFolder.Inspect:Stop()
		end
		table.clear(self.IGList)
		if self.cnt_Inspect then
			self.cnt_Inspect:Disconnect()
			self.cnt_Inspect = nil
		end
		if self.cnt_GBI then
			self.cnt_GBI:Disconnect()
			self.cnt_GBI = nil
		end
		self.Inspecting = false
		Remotes.Server.Inventory.UnequipItem:FireServer(self.ID)
		if self.ViewModel and self.ViewModel:FindFirstChild("Left Arm")  then
			for _, v in pairs(self.ViewModel:GetDescendants()) do
				if v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal") then
					v.Transparency = 1
				elseif v:IsA("RopeConstraint") then
					v.Visible = false
				end
			end

			local LeftGlove = self.ViewModel["Left Arm"].LeftGlove
			local RightGlove = self.ViewModel["Right Arm"].RightGlove

			for _, v in pairs(LeftGlove:GetChildren()) do
				if v:IsA("Attachment") then
					v:Destroy()
				end
			end

			for _, v in pairs(RightGlove:GetChildren()) do
				if v:IsA("Attachment") then
					v:Destroy()
				end
			end

			
			if self.ViewAnimator then
				for _, animTrack in pairs(self.ViewAnimator:GetPlayingAnimationTracks()) do
					animTrack:Stop(0)
				end
			end
		end
		
		if _G.Equipped == self then
			_G.Equipped = nil
		end
		if _G.EquippingItem == self then
			_G.EquippingItem = nil
		end

		self.Equipped = false
		self.Equipping = false
		self.CanAttack = false
		if self.ReconcileCon then
			self.ReconcileCon:Disconnect()
			self.ReconcileCon = nil
		end
		if self.SkinCon then
			self.SkinCon:Disconnect()
			self.SkinCon = nil
		end

	end

	function Knife:PrimaryAttack()
		--print("Start Primary Attack")
		if self.SoundFolder:FindFirstChild("Inspect") then
			self.SoundFolder.Inspect:Stop()
		end

		local Character = ClientPlayer.Character
		local RNG = math.random(1, 2)
		local AnimToPlay = RNG == 1 and self.CL_ATTACK1 or self.CL_ATTACK2

		self.CanInspect = true

		if self.CanAttack and self.Equipped then
			if not self:_bindToolEvents(0.5) or not self.Tool or self.Tool.Parent ~= Character then
				return
			end
			self.CanAttack = false

			if self.CL_INSPECT then
				self.CL_INSPECT:Stop()
			end
			self.Inspecting = false

			self:_playLocalToolSound("Swoosh" .. math.random(1, 2))
			local Params = RaycastParams.new()
			Params.FilterType = Enum.RaycastFilterType.Exclude
			Params.FilterDescendantsInstances = self.IGList

			local RayOrigin, RayDirection = getMeleeRaycast(Character, self.MeleeStudRange)
			local RR = raycastIgnoringInvisible(RayOrigin, RayDirection, Params)

			if not RR then
				AnimToPlay:Play(0)
				task.wait(self.AttackWait)
				self.MouseEvent:FireServer(nil, nil)
				task.wait(math.abs(self.WeaponConfig.ATTACK_COOLDOWN))

				if self.Equipped then
					self.CanAttack = true
				end
				return
			end

			local HitPart = RR.Instance
			warn("ClientMelee : " .. HitPart:GetFullName(), HitPart.Parent:GetFullName())

			local FoundHumanoid = HitPart.Parent:FindFirstChildOfClass("Humanoid")
			if FoundHumanoid then
				local T2M = (Character.HumanoidRootPart.Position - HitPart.Parent.HumanoidRootPart.Position).Unit
				local TLV = HitPart.Parent.HumanoidRootPart.CFrame.LookVector
				local DP = T2M:Dot(TLV)

				if DP >= 0.25 then
					AnimToPlay:Play(0)
					local RandomChance = math.random(1, 100)
					if RandomChance == 1 then
						game.ReplicatedFirst.Assets.Sounds.OnKill.Chimasu:Play()
					end
					self.CL_BACKSTAB:Play()
					task.wait(self.AttackWait)
					self.MouseEvent:FireServer(1, HitPart.Parent, true, {Normal = RR.Normal,Position = RR.Position})
				elseif DP < -0.25 then
					local RandomChance = math.random(1, 100)
					if RandomChance == 1 then
						game.ReplicatedFirst.Assets.Sounds.OnKill.Chimasu:Play()
					end
					AnimToPlay:Play(0)
					task.wait(self.AttackWait)
					self.MouseEvent:FireServer(2, HitPart.Parent, true, {Normal = RR.Normal,Position = RR.Position})
				end
			else
				AnimToPlay:Play(0)
				task.wait(self.AttackWait)
				self:_spawnSurfaceSlash(RR.Position, RR.Normal, RayDirection)
				playMeleeImpactSound(RR.Instance)
				self.MouseEvent:FireServer(1, HitPart, false, {Normal = RR.Normal,Position = RR.Position})
			end
		elseif self.CanAttack and not self.Equipped then
			return
		end

		task.wait(math.abs(self.WeaponConfig.ATTACK_COOLDOWN))
		self.CanAttack = true
	end
	
	function Knife:SecondaryAttack()
		--print("Start Secondary Attack")
		if self.SoundFolder:FindFirstChild("Inspect") then
			self.SoundFolder.Inspect:Stop()
		end

		local Character = ClientPlayer.Character
		local AnimToPlay = self.CL_ATTACK3 or self.CL_BACKSTAB

		self.CanInspect = true

		if self.CanAttack and self.Equipped then
			if not self:_bindToolEvents(0.5) or not self.Tool or self.Tool.Parent ~= Character then
				return
			end
			self.CanAttack = false

			if self.CL_INSPECT then
				self.CL_INSPECT:Stop()
			end
			self.Inspecting = false

			self:_playLocalToolSound("Swoosh" .. math.random(1, 2))
			local Params = RaycastParams.new()
			Params.FilterType = Enum.RaycastFilterType.Blacklist
			Params.FilterDescendantsInstances = self.IGList

			local RayOrigin, RayDirection = getMeleeRaycast(Character, self.MeleeStudRange)
			local RR = raycastIgnoringInvisible(RayOrigin, RayDirection, Params)

			if not RR then
				AnimToPlay:Play(0)
				task.wait(self.AttackWait)
				self.MouseEvent:FireServer(nil, nil)
				task.wait(math.abs(self.WeaponConfig.ATTACK_COOLDOWN_2))

				if self.Equipped then
					self.CanAttack = true
				end
				return
			end

			local HitPart = RR.Instance
			warn("ClientMelee : " .. HitPart:GetFullName(), HitPart.Parent:GetFullName())

			local FoundHumanoid = HitPart.Parent:FindFirstChildOfClass("Humanoid")
			if FoundHumanoid then
				local T2M = (Character.HumanoidRootPart.Position - HitPart.Parent.HumanoidRootPart.Position).Unit
				local TLV = HitPart.Parent.HumanoidRootPart.CFrame.LookVector
				local DP = T2M:Dot(TLV)

				if DP <= -0.25 then
					local RandomChance = math.random(1, 100)
					if RandomChance == 1 then
						game.ReplicatedFirst.Assets.Sounds.OnKill.Chimasu:Play()
					end
					AnimToPlay:Play(0)
					task.wait(self.AttackWait)
					self.MouseEvent:FireServer(2, HitPart.Parent, true, {Normal = RR.Normal,Position = RR.Position})
					task.wait(self.WeaponConfig.ATTACK_COOLDOWN_2)
					if self.Equipped then
						self.CanAttack = true
					end
					return
				end

				if DP > 0.25 then
					AnimToPlay:Play(0)
					task.wait(self.AttackWait)
					self.MouseEvent:FireServer(2, HitPart.Parent, true, {Normal = RR.Normal,Position = RR.Position})
				end
			else
				AnimToPlay:Play(0)
				task.wait(self.AttackWait)
				self:_spawnSurfaceSlash(RR.Position, RR.Normal, RayDirection)
				playMeleeImpactSound(RR.Instance)
				self.MouseEvent:FireServer(2, HitPart, false, {Normal = RR.Normal,Position = RR.Position})
			end
		elseif self.CanAttack and not self.Equipped then
			return
		end

		task.wait(math.abs(self.WeaponConfig.ATTACK_COOLDOWN_2))
		self.CanAttack = true
	end
	
	function Knife:HandleInputBegan(Input, InputSank)
		if InputSank then return end
		if Input.UserInputType == Enum.UserInputType.MouseButton1 and self.Equipped and self.CanAttack and PlayerData.CanUse.Value == "true" then
			-- Primary attack
			self:PrimaryAttack()
			return
		end
		if Input.UserInputType == Enum.UserInputType.MouseButton2 and self.Equipped and self.CanAttack and PlayerData.CanUse.Value == "true" then
			-- Secondary attack
			self:SecondaryAttack()
			return
		end
		local inspectKey = getInspectKeyCode()
		if Input.KeyCode == inspectKey and self.Equipped and not self.Reloading and not self.Inspecting and self.CL_INSPECT then
			-- Inspect animation
			self.CL_INSPECT.Looped = true
			self.CL_INSPECT:Play()
			self.Inspecting = true
			if self.cnt_Inspect then
				self.cnt_Inspect:Disconnect()
			end
			self.cnt_Inspect = self.CL_INSPECT.Stopped:Connect(function()
				self.Inspecting = false
			end)
			return
		end
		if Input.KeyCode == Enum.KeyCode.Z and self.Equipped and not self.Reloading and PlayerData.CanUse.Value == "true" and not self.Inspecting and self.CL_GBI then
			-- Special animation or action
			self.CL_GBI:Play()
			self.Inspecting = true
			if not self.cnt_GBI then
				self.cnt_GBI = self.CL_GBI.Stopped:Connect(function()
					self.Inspecting = false
				end)
			end
			return
		end
	end
	
	function Knife:HandleInputEnded(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- End primary attack
			self.Pressing = false
		end
		if Input.KeyCode == getInspectKeyCode() and PlayerData.CanUse.Value == "true" and self.CL_INSPECT then
			-- End inspect animation
			self.CL_INSPECT.Looped = false
		end
	end
	
	return Knife
end

return Module
