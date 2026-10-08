local Module = {}



Module.Init = function()
	local Gun = _G.Tool:Extend()
	local Tool = _G.Tool


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

	local function isScopeEnabled(tool)
		local module = tool and (tool:FindFirstChild("WeaponConfig") or tool:FindFirstChild("Config"))
		if not (module and module:IsA("ModuleScript")) then
			return false
		end

		local ok, config = pcall(require, module)
		return ok and type(config) == "table" and config.SCOPEENABLED == true
	end

	local function getReferenceValue(gTool, valueName)
		local valueObj = gTool and gTool:FindFirstChild(valueName)
		if valueObj and valueObj:IsA("ObjectValue") then
			return valueObj.Value
		end
		return nil
	end

	local function getBaseMouseSensitivity()
		return tonumber(SavedData.PlayerSettings.ControlSettings.Sensitivity.Value) or 1
	end

	local function getScopedMouseSensitivity(scopeFov)
		local baseSensitivity = getBaseMouseSensitivity()
		local scopeSensitivity = tonumber(SavedData.PlayerSettings.ControlSettings.ScopeSensitivity.Value) or 1
		local baseFov = tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value) or 70
		local targetFov = tonumber(scopeFov) or baseFov

		if baseFov <= 0 then
			return baseSensitivity * scopeSensitivity
		end

		-- Keep a scope multiplier of 1 neutral even as the scoped FOV changes.
		return baseSensitivity * scopeSensitivity * (targetFov / baseFov)
	end

	local function ensureScopeGui()
		local playerGui = ClientPlayer:FindFirstChild("PlayerGui")
		if not playerGui then
			return nil
		end
		local scope = playerGui:FindFirstChild("Scope")
		if scope then
			return scope
		end
		local clientRoot = game:GetService("ReplicatedFirst"):FindFirstChild("Client")
		local uiAssets = clientRoot and clientRoot:FindFirstChild("UIAssets")
		local template = uiAssets and uiAssets:FindFirstChild("Scope")
		if template and template:IsA("ScreenGui") then
			scope = template:Clone()
			scope.ResetOnSpawn = false
			scope.Parent = playerGui
		end
		return scope
	end

	local function playSoundIfPresent(folder, soundName, pitch)
		if not folder then
			return
		end

		local sound = folder:FindFirstChild(soundName)
		if sound then
			Framework.PlayRandomPitch(sound, pitch)
		end
	end

	local function playExclusiveTrack(activeTrack, inactiveTrack)
		if inactiveTrack then
			if inactiveTrack.IsPlaying then
				inactiveTrack:Stop(0)
			end
			if inactiveTrack.AdjustWeight then
				inactiveTrack:AdjustWeight(0, 0)
			end
		end

		if activeTrack then
			activeTrack.TimePosition = 0
			if activeTrack.AdjustWeight then
				activeTrack:AdjustWeight(1, 0)
			end
			activeTrack:Play(0)
		end
	end

	function Gun.New(Model)
		local newTool = Tool.New("Gun",Model)
		setmetatable(newTool,Gun)

		newTool.Reloading = false
		newTool.IsAiming = false

		newTool.Grip, newTool.InspectTrack = nil, nil
		newTool.CurrentPlayer = ""
		newTool.ViewAnimator, newTool.ViewModel = nil
		newTool.TransparencyTable = {}
		newTool.CanAttack = true
		newTool.FirePointOffset = nil
		newTool.FirePointAttachment = nil
		newTool.FirePointAttachment2 = nil
		newTool.AimTarget = 0
		newTool.AimLerpIn = 10
		newTool.AimLerpOut = 12
		newTool.ProceduralKickStrength = 0.8
		newTool.ProceduralFireDecay = 14
		newTool.LastEquipReconcile = 0
		newTool.IsScoped = false
		return newTool
	end

	function Gun:_applyAimGoal(goal)
		self.AimTarget = goal
		if _G.ViewmodelController and _G.ViewmodelController.ApplyWeaponPose then
			_G.ViewmodelController:ApplyWeaponPose({
				aimGoal = goal,
			})
		end
	end

	function Gun:_setClientScoped(scoped)
		self.IsScoped = scoped and true or false
		if _G.ViewmodelController and _G.ViewmodelController.SetClientScoped then
			_G.ViewmodelController:SetClientScoped(scoped)
		end
	end

	function Gun:_canPredictScope()
		return self.Equipped == true
			and self.CanAttack == true
			and not self.Reloading
			and not self.Inspecting
			and PlayerData.CanUse.Value == "true"
			and self.GUI ~= nil
			and self.WeaponConfig ~= nil
			and isScopeEnabled(self.Tool)
	end

	function Gun:_triggerProceduralFire()
		if not (_G.ViewmodelController and _G.ViewmodelController.ApplyWeaponPose) then
			return
		end

		local base = self.FirePointOffset
		if base then
			base = CFrame.lookAt(Vector3.new(), base.LookVector, base.UpVector)
		else
			base = CFrame.new()
		end

		local kick = base
			* CFrame.new(0, 0, -(self.ProceduralKickStrength or 0.12))
			* CFrame.Angles(
				math.rad((_G.CurrentWeaponSign or 1) * 0.25),
				0,
				0
			)

		_G.ViewmodelController:ApplyWeaponPose({
			proceduralKick = kick,
			proceduralDecay = self.ProceduralFireDecay or 14,
		})
	end

	function Gun:_setupFirePoints()
		if not self.ClientModel then
			return
		end

		local main = self.ClientModel:FindFirstChild("Main")


		if main then

			if _G.ViewmodelController and _G.ViewmodelController.ApplyWeaponPose then
				local partAim = main:FindFirstChild("AimPoint")
				
				_G.ViewmodelController:ApplyWeaponPose({
					aimPoint = partAim or false,
					aimSpeeds = { inSpeed = self.AimLerpIn, outSpeed = self.AimLerpOut },
					aimGoal = self.AimTarget or 0,
				})
			end
		end
	end

	function Gun:_setNodeVisibility(node, visible)
		if not node then
			return
		end

		local targetTransparency = visible and 0 or 1
		local function apply(inst)
			if inst:IsA("BasePart") or inst:IsA("Texture") or inst:IsA("Decal") then
				-- For reload mags, force exact visibility state; do not defer to TransparencyTag.
				inst.Transparency = targetTransparency
			end
		end

		apply(node)
		for _, d in ipairs(node:GetDescendants()) do
			apply(d)
		end
	end

	function Gun:_setModelMagVisibility(model, visible)
		if not model then
			return
		end

		self:_setNodeVisibility(model:FindFirstChild("Mag"), visible)
		self:_setNodeVisibility(model:FindFirstChild("Mag2"), visible)
	end

	function Gun:_setReloadMagVisibility(visible)
		self:_setModelMagVisibility(self.ClientModel, visible)
		self:_setModelMagVisibility(self.ClientModel2, visible)
	end

	function Gun:_applyReplicatedSkin()
		local skinValue = self.MainPart and self.MainPart:FindFirstChild("Skin")
		local skinName = skinValue and tostring(skinValue.Value) or ""
		if skinName == "" or skinName == "Stock" then
			return
		end
		for _, model in ipairs({ self.ClientModel, self.ClientModel2 }) do
			if model then
				local applied = model:FindFirstChild("AppliedSkin")
				if applied and applied.Value == skinName then
					continue
				end
				if applied then
					applied:Destroy()
				end
				local charm = model:FindFirstChild("WeaponCharm")
				if charm then
					charm:Destroy()
				end
				ContainerService.ApplySkin(model, self.Name, skinName)
			end
		end
	end

	function Gun:_bindSkinUpdates()
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

	function Gun:_applyConfiguredAudio()
		local audioMultiplier = tonumber(self.Entry and self.Entry.AudioVolumeMultiplier) or 1
		if audioMultiplier == 1 or not self.SoundFolder then
			return
		end
		for _, sound in ipairs(self.SoundFolder:GetDescendants()) do
			if sound:IsA("Sound") then
				local baseVolume = sound:GetAttribute("ConfiguredBaseVolume")
				if type(baseVolume) ~= "number" then
					baseVolume = sound.Volume
					sound:SetAttribute("ConfiguredBaseVolume", baseVolume)
				end
				sound.Volume = baseVolume * audioMultiplier
			end
		end
	end

	function Gun:_bindToolEvents(timeoutSeconds, requireEquippedTool)
		local timeout = timeoutSeconds or 0
		local deadline = tick() + timeout
		local tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value
		local events

		repeat
			tool = self.GTool and self.GTool:FindFirstChild("ToCurrentTool") and self.GTool.ToCurrentTool.Value
			local isEquippedTool = not requireEquippedTool
				or (ClientPlayer.Character and tool and tool.Parent == ClientPlayer.Character)
			if tool and isEquippedTool then
				events = tool:FindFirstChild("Events")
				if events then
					local mouseEvent = events:FindFirstChild("MouseEvent")
					local reloadEvent = events:FindFirstChild("ReloadEvent")
					local suppressorEvent = events:FindFirstChild("Suppressor")
					local aimEvent = events:FindFirstChild("AimEvent")
					if mouseEvent and reloadEvent and suppressorEvent and aimEvent then
						self.Tool = tool
						self.MouseEvent = mouseEvent
						self.ReloadEvent = reloadEvent
						self.SuppressorEvent = suppressorEvent
						self.AimEvent = aimEvent
						return true
					end
				end
			end
			if timeout <= 0 then
				break
			end
			task.wait()
		until tick() >= deadline

		return false
	end

	function Gun:_connectReloadEventListener()
		if self.ReloadEventCon then
			self.ReloadEventCon:Disconnect()
			self.ReloadEventCon = nil
		end
		if not self.ReloadEvent then
			return
		end
		self.ReloadEventCon = self.ReloadEvent.OnClientEvent:Connect(function(sus)
			self.CurrentAmmoLocal = sus
			self:_setReloadMagVisibility(true)
			-- Keep this callback as state sync only; do not cut reload animation here.
			self.CurrentAmmoLocal = self.CurrentAmmo.Value
		end)
	end

	function Gun:_finalizeReloadPose()
		self:_setReloadMagVisibility(true)
		if self.CL_IDLE and not self.CL_IDLE.IsPlaying then
			self.CL_IDLE:Play(0)
		end
	end

	function Gun:_reconcileServerEquip()
		if not (self.Equipped and self.ID) then
			return
		end
		if self.Equipping or self.Reloading or (self.CanAttack == false) then
			return
		end
		if not self.Tool or self.Tool.Parent ~= ClientPlayer.Character then
			return
		end
		local gunServer = self.Tool and self.Tool:FindFirstChild("GunServer")
		local isEquippedFlag = gunServer and gunServer:FindFirstChild("IsEquipped")
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

	

	function Gun:_emitMuzzle(muzzle, includeFlash)
		if not muzzle then
			return
		end
		local flash = muzzle:FindFirstChild("MuzzleFlash")
		if includeFlash ~= false and flash and flash:IsA("ParticleEmitter") then
			flash:Emit(1)
		end
		local smoke = muzzle:FindFirstChild("Smoke")
		if smoke and smoke:IsA("ParticleEmitter") then
			smoke:Emit(1)
		end
	end

	function Gun:PlayFireSound()
		if not self.Entry then return end
		if self.Entry.FireTable then
			coroutine.wrap(function()
				for a,b in pairs(self.Entry.FireTable) do
					local Split = string.split(b,":")
					if Split[1] == "Sound" then
						local NewSound = self.SoundFolder[Split[2]]:Clone()
						NewSound.Parent = ClientPlayer.Character
						NewSound:Play()
						game.Debris:AddItem(NewSound, NewSound.TimeLength)
					elseif Split[1] == "Wait" or Split[1] == "wait" then
						task.wait(tonumber(Split[2]))
					end
				end
			end)()
		else
			local NewSound = self.SoundFolder.Fire:Clone()
			NewSound.Parent = ClientPlayer.Character
			Framework.PlayRandomPitch(NewSound,55)
			game.Debris:AddItem(NewSound, NewSound.TimeLength)
		end
	end
		
	function Gun:Retool()
		self.Model = getReferenceValue(self.GTool, "ToModel") or ClientPlayer.Character:WaitForChild("WeaponModel")
		self.Tool = getReferenceValue(self.GTool, "ToCurrentTool")
		self.MainPart = self.Model:FindFirstChild("Main")
		self:_bindToolEvents(1)
		self:_connectReloadEventListener()

		if self.HideCon then  
			self.HideCon:Disconnect()
		end

		self.HideCon = ClientPlayer.Character.ChildAdded:Connect(function(NewChild)
			if NewChild:IsA("Model") and NewChild.Name == "WeaponModel" and _G.EquippingItem == self then

				warn(self.MainPart:GetFullName())
				self.MainPart = NewChild:FindFirstChild("Main")
				self.MainPart.Ejector.Shells.Size = NumberSequence.new(0)
				self.MainPart.FirePoint.MuzzleFlash.Size = NumberSequence.new(0)
				self.MainPart.FirePoint.Smoke.Size = NumberSequence.new(0)

				self.Model = NewChild
				

			end
			if NewChild:IsA("Model") and NewChild.Name == "WeaponModel2" and _G.EquippingItem == self then
				if self.IsDual then
					self.MainPart2 = self.Model2:FindFirstChild("Main2")
					self.MainPart2.Ejector.Shells.Size = NumberSequence.new(0)
					self.MainPart2.FirePoint.MuzzleFlash.Size = NumberSequence.new(0)
					self.MainPart2.FirePoint.Smoke.Size = NumberSequence.new(0)
				end
			end
		end)
	end

	function Gun:Initialize()
		
		
		self.GTool = self.Model
		self.Model = getReferenceValue(self.GTool, "ToModel")
		self.Tool = getReferenceValue(self.GTool, "ToCurrentTool")
		if not self:_bindToolEvents(2) then
			-- Fallback: block until the tool remotes exist instead of aborting initialize.
			local toolValue = self.GTool:WaitForChild("ToCurrentTool")
			while not toolValue.Value do
				task.wait()
			end
			self.Tool = toolValue.Value
			local events = self.Tool:WaitForChild("Events")
			self.MouseEvent = events:WaitForChild("MouseEvent")
			self.ReloadEvent = events:WaitForChild("ReloadEvent")
			self.SuppressorEvent = events:WaitForChild("Suppressor")
			self.AimEvent = events:WaitForChild("AimEvent")
		end
				
		self.WeaponConfig = require(self.Tool:WaitForChild("WeaponConfig"))	
		if not self.Tool.WeaponConfig:FindFirstChildOfClass("Configuration") then
			self.WeaponConfig = Framework.AddAttributes(self.WeaponConfig,self.Tool.WeaponConfig)
			wait()
		end
		self.WeaponConfigRaw = require(self.Tool:WaitForChild("WeaponConfig"))	
		self.WeaponConfig = Framework.IndexAttribute(self.Tool.WeaponConfig.Configuration)
		self.ConfigAnim = game.ReplicatedFirst.Assets.Animations:WaitForChild(self.Name)
		self.AimEvent = self.Tool.Events.AimEvent

		self.SoundFolder = self.Tool:WaitForChild("Sounds")
		self.CurrentAmmo = self.Tool.Ammo:WaitForChild("Current")

		if self.WeaponConfigRaw.REMOVABLESUPPRESSOR == true then
			self.SilencerEnabled = self.Tool.WeaponModel:WaitForChild("SilencerEnabled")
		end
		self.PlayingSounds = {}
		
		

		self.AimDB = false
		self.SwitchDB = false
		self.EntryName = self.Tool.Name
		self.Entry = Framework.GetJSONEntry(self.EntryName,WeaponData)
		self:_applyConfiguredAudio()

		self.MainPart = self.Model:WaitForChild("Main", 50)
		
		self.lastclick = tick()
		self.curshots = 0
		self.RecoilPattern = self.Entry.RecoilPattern
		self.AimLerpIn = self.WeaponConfigRaw.ADS_LERP_IN or self.AimLerpIn
		self.AimLerpOut = self.WeaponConfigRaw.ADS_LERP_OUT or self.AimLerpOut
		self.ProceduralKickStrength = self.WeaponConfigRaw.PROCEDURAL_KICK or self.ProceduralKickStrength
		self.ProceduralFireDecay = self.WeaponConfigRaw.PROCEDURAL_DECAY or self.ProceduralFireDecay

		self.IsDual = self.WeaponConfig.DUALWEAPON
		if self.IsDual then
			self.IsRightFire = true
			self.Model2 = self.Tool:WaitForChild("WeaponModel2")
			self.MainPart2 = self.Model2:WaitForChild("Main2")
		end

		self.EquipTime = self.WeaponConfigRaw.EQUIP_TIME
		self.ReloadTime = self.WeaponConfig.RELOAD_TIME
		self.FireRate = self.WeaponConfig.FIRE_RATE
		self.Automatic = self.WeaponConfig.FULL_AUTO
		self.MagSize = self.WeaponConfig.MAG_SIZE
		self.Switchable = self.WeaponConfig.MODE_SWITCH

		self.Inspecting = false


		if self.WeaponConfigRaw.REMOVABLESUPPRESSOR == true then
			self.SilencerEnabled = self.Tool.WeaponModel:WaitForChild("SilencerEnabled")
		end

		self.CurrentAmmoLocal = self.CurrentAmmo.Value

		self:_bindToolEvents(1)
		self:_connectReloadEventListener()

		if self.WeaponConfigRaw.REMOVABLESUPPRESSOR == true then
			self.SilencerEnabled:GetPropertyChangedSignal("Value"):Connect(function(NewValue)
				if self.Equipped then
					if NewValue then
						self.Tool.WeaponModel[self.WeaponConfigRaw.SILENCERNAME].LocalTransparencyModifier = 1
						self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].Transparency = 0
						self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].TransparencyTag.Value = 0
					else
						self.Tool.WeaponModel[self.WeaponConfigRaw.SILENCERNAME].LocalTransparencyModifier = 1
						self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].Transparency = 1
						self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].TransparencyTag.Value = 1

					end


				end





			end)
		end
		
		RunService.RenderStepped:Connect(function()
			self:_reconcileServerEquip()
			if self.Equipped and self.CanAttack == true and PlayerData.CanUse.Value == "true" and self.Pressing and self.Automatic then
				self:Fire()
			end
		end)

	end
	function Gun:ShootRecoil()
	
		self.curshots = (tick() - self.lastclick > self.WeaponConfigRaw.RECOILDECAYTIME and 1 or self.curshots + 1)  
		self.lastclick = tick()
		for i, v in pairs(self.RecoilPattern) do
			if self.curshots <= v[1] then
				task.spawn(function()
					local num = 0
					local const = 1
					if _G.CurrentAbilityData then
						if table.find(_G.CurrentAbilityData.Solvers,"Ballistic Solver") and tonumber(PlayerData.SolutionStage.Value) >= 3 then
							const = 0.1
						end
						if table.find(_G.CurrentAbilityData.Traits,"Adaptive") then
							const = 0.5
						end
						if table.find(_G.CurrentAbilityData.Flaws,"Dim") then
							const = 1.25
						end
					end

					while math.abs(num - v[2]) > 0.01 do
						num = lerp(num, v[2], v[4])
						local rec = num / 10

						_G.ViewmodelFireOffsetY += lerp(_G.ViewmodelFireOffsetY,0.05,0.1) /6
						_G.ViewmodelFireOffsetY = math.clamp(_G.ViewmodelFireOffsetY,0,0.2)
						_G.ViewmodelFireOffsetX += lerp(_G.ViewmodelFireOffsetX,rec/100,0.1)/ 4
						_G.ViewmodelFireOffsetAY += lerp(_G.ViewmodelFireOffsetAY,rec/100,0.1)
						_G.ViewmodelFireOffsetAX = lerp(_G.ViewmodelFireOffsetAX,math.sin(tick() * 20) * 0.32 * rec,0.1)
						_G.ViewmodelFireOffsetAZ += lerp(_G.ViewmodelFireOffsetAZ,rec/10,0.1)
						ClientCamera.CFrame = ClientCamera.CFrame * CFrame.Angles(math.rad(rec* const), math.rad(rec * v[5]* const), 0) 
						RunService.RenderStepped:Wait()

					end
					while math.abs(num - v[3]) > 0.01 do
						num = lerp(num, v[3], v[4])
						local rec = num / 10
						ClientCamera.CFrame = ClientCamera.CFrame * CFrame.Angles(math.rad(rec* const), math.rad(rec * v[5]* const), 0)
						RunService.RenderStepped:Wait()
					end

				end)
				break
			end
		end

	end
	function Gun:Fire()
		if not self.MouseEvent then
			if not self:_bindToolEvents(0.5) then
				return
			end
		end

		local parent3 = self.MouseEvent.Parent and self.MouseEvent.Parent.Parent and self.MouseEvent.Parent.Parent.Parent
		if parent3 and parent3:IsA("Folder") then
			self.CurrentAmmo = self.Tool.Ammo:WaitForChild("Current")
		end
		self.CurrentAmmoLocal = self.CurrentAmmo.Value
		local SavedT = tick() 
		if FreezeTime.Value == true then return end
		if self.CanAttack == true and self.Equipped == true and self.CurrentAmmo.Value > 0 and self.CurrentAmmoLocal > 0  and PlayerData.CanUse.Value == "true"  then
			
			--warn("Fire")
			self:PlayFireSound()
			self.CanAttack = false
			self.Reloading = false

			self.CurrentAmmoLocal -= 1
			local shotDirection = ClientCamera.CFrame.LookVector
			local shotOrigin = ClientCamera.CFrame.Position
			local shotServerTime = workspace.GetServerTimeNow and workspace:GetServerTimeNow() or tick()
			self.MouseEvent:FireServer(
				shotDirection,
				ClientPlayer.Character.HumanoidRootPart.Velocity.Magnitude or 27,
				shotOrigin,
				shotServerTime
			)

			local i = 0
			if self.WeaponConfig.CLASS == "Sniper" then
				self.ShowBolt = true
			end

			
			self:ShootRecoil()

			if self.IsAiming then
				self:_triggerProceduralFire()
			elseif not self.IsDual then
				self.CL_ATTACK.TimePosition = 0
				self.CL_ATTACK:Play(0)
			elseif self.IsDual then
				self.IsRightFire = not self.IsRightFire
				if self.IsRightFire then
					playExclusiveTrack(self.CL_ATTACK2, self.CL_ATTACK)
				else
					playExclusiveTrack(self.CL_ATTACK, self.CL_ATTACK2)
				end

			end


			if self.CL_INSPECT then
				self.CL_INSPECT:Stop()
			end

			if self.CL_RELOAD then
				self:_setReloadMagVisibility(true)
				self.CL_RELOAD:Stop()
			end

			if isScopeEnabled(self.Tool) then
				self:_setClientScoped(false)
				self.AimEvent:FireServer("Fire")
				CH.Visible = true
				if Tool.Name ~= "M110" then
					self.GUI.Visible = false
					task.wait(self.WeaponConfig.SCOPEDELAY)
					self:HideVM(false)
					TweenPropertyIn(workspace.CurrentCamera,"FieldOfView",(self.WeaponConfig.SCOPEDELAY),tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value))
					InputService.MouseDeltaSensitivity = getBaseMouseSensitivity()
				end
			end



			local flashEnabled = self.WeaponConfig.FLASHENABLED == true
			local primaryMain = self.ClientModel and self.ClientModel:FindFirstChild("Main")
			local secondaryMain = self.ClientModel2
				and (self.ClientModel2:FindFirstChild("Main2") or self.ClientModel2:FindFirstChild("Main"))
			local primaryMuzzle = self.FirePointAttachment
				or (primaryMain and primaryMain:FindFirstChild("FirePoint"))
			local secondaryMuzzle = self.FirePointAttachment2
				or (secondaryMain and secondaryMain:FindFirstChild("FirePoint"))

			if self.IsDual then
				if self.IsRightFire then
					if primaryMain then
						self:_emitMuzzle(primaryMuzzle, flashEnabled)
						primaryMain.Ejector.Shells:Emit(1)
					end
				else
					if secondaryMain then
						self:_emitMuzzle(secondaryMuzzle, flashEnabled)
						secondaryMain.Ejector.Shells:Emit(1)
					end
				end
			elseif self.WeaponConfig.CLASS ~= "Shotgun" and self.WeaponConfig.CLASS ~= "Sniper" then
				if primaryMain then
					primaryMain.Ejector.Shells:Emit(1)
					self:_emitMuzzle(primaryMuzzle, flashEnabled)
				end
			elseif primaryMain then
				self:_emitMuzzle(primaryMuzzle, flashEnabled)
				primaryMain.Ejector.Shells:Emit(1)
			end



			--repeat task.wait() i += 1 until tick() >= SavedT + FireRate
			local FireRate = self.FireRate
			if table.find(_G.CurrentAbilityData.Traits,"Manic") then
				FireRate *= (1/1.25)
			end
			if table.find(_G.CurrentAbilityData.Traits,"Apathetic") then
				FireRate *= (1/0.85)
			end

			task.wait(FireRate)
			self.CanAttack = true

		end

	end
	function Gun:RemoveSuppressor()
		if not self.SuppressorEvent then
			if not self:_bindToolEvents(0.5) then
				return
			end
		end
		if self.Adjusting then return end
		self.Adjusting = true
		self.CanAttack = false
		self.SuppressorEvent:FireServer()
		if self.SilencerEnabled.Value == true then
			self.CL_SILENCEROFF:Play()
			self.Tool.WeaponModel[self.WeaponConfigRaw.SILENCERNAME].LocalTransparencyModifier = 1
			local DoneTick = tick() + 1
			while tick() < DoneTick do
				if not self.Equipped then self.Adjusting = false return end
				task.wait()
			end
			self.SoundFolder.Fire.SoundId = "rbxassetid://"..self.WeaponConfigRaw.UNSILENCEDID
			self.SoundFolder.Fire.RollOffMaxDistance = self.WeaponConfigRaw.UNSILENCEDRANGE
			self.CanAttack = true
			self.Adjusting = false
		else
			self.CL_SILENCERON:Play()
			self.Tool.WeaponModel[self.WeaponConfigRaw.SILENCERNAME].LocalTransparencyModifier = 1
			self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].Transparency = 0
			self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].TransparencyTag.Value = 0
			local DoneTick = tick() + 1
			while tick() < DoneTick do
				if not self.Equipped then self.Adjusting = false return end
				task.wait()
			end

			self.SoundFolder.Fire.SoundId = "rbxassetid://"..self.WeaponConfigRaw.SILENCEDID
			self.SoundFolder.Fire.RollOffMaxDistance = self.WeaponConfigRaw.SILENCEDRANGE
			self.CanAttack = true
			self.Adjusting = false
		end
	end
	function Gun:Reload()
		self:Retool()
		if not self.ReloadEvent then
			if not self:_bindToolEvents(0.5) then
				return
			end
			self:_connectReloadEventListener()
		end
		local reloadParent3 = self.ReloadEvent.Parent and self.ReloadEvent.Parent.Parent and self.ReloadEvent.Parent.Parent.Parent
		if reloadParent3 and reloadParent3:IsA("Folder") then
			self.CurrentAmmo = self.Tool.Ammo:WaitForChild("Current")
		end
		
		local CanReload = PlayerData.CanReload

		if self.WeaponConfigRaw.REMOVABLESUPPRESSOR == true then
			if self.CurrentAmmoLocal == self.WeaponConfigRaw.MAG_SIZE then
				coroutine.wrap(self.RemoveSuppressor)()
				return
			end
		end

		if self.CurrentAmmo.Value < self.MagSize and self.Tool.Ammo.Reserve.Value > 0 and self.Equipped and not self.Reloading and CanReload.Value == "true" and self.CanAttack == true then
			self.Reloading = true
			if self.WeaponConfig.CLASS == "Shotgun" then
				self.CanAttack = true
			else
				self.CanAttack = false
			end

			if self.CL_INSPECT then
				self.CL_INSPECT:Stop()
			end

			if self.IsAiming == true then
				self.IsAiming = false
				self.CL_IDLE:Play(0)
				workspace.CurrentCamera.FieldOfView = tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value)
				self.AimEvent:FireServer(false)
				self:_applyAimGoal(0)
			end	

			self.ReloadEvent:FireServer()
			self:_setReloadMagVisibility(true)
			self.CL_RELOAD:Play()

			if self.WeaponConfig.CLASS == "Shotgun" then

				while self.CurrentAmmo.Value < self.MagSize do
					task.wait(self.ReloadTime)
					self.CurrentAmmoLocal = self.CurrentAmmo.Value
				end
				self.CanAttack = true
				self.Reloading = false

				self.CL_RELOAD2:Play()
				task.wait(self.CL_RELOAD2.Length)
				self.CL_RELOAD:Stop(0)
				self:_finalizeReloadPose()

			else
				local animLen = (self.CL_RELOAD and self.CL_RELOAD.Length) or 0
				local reloadDuration = math.max(self.ReloadTime, animLen)
				task.wait(reloadDuration)
				self.CurrentAmmoLocal = self.CurrentAmmo.Value
				self.CL_RELOAD:Stop(0)
				self:_finalizeReloadPose()
				self.Reloading = false
				self.CanAttack = true
			end

		end

	end
	function Gun:HideVM(Bool)
		local Data = SavedData
		local Loadout = Data[ClientPlayer.Team.Name.."Loadout"]
		local GloveSlot = Loadout:FindFirstChild("GloveSkin")
		if Bool == true then
			for i,v in pairs(self.ViewModel:GetDescendants())do
				if v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal") or string.find(v.Name,"Lense")  then
					v.Transparency = 1
				end
			end
		else
			if self.ViewModel then
				
				for i,v in next,self.ViewModel:GetDescendants() do
					if v:IsA("Texture") or v:IsA("Decal") and not v:FindFirstChild("TransparencyTag") then
						v.Transparency = 0
					elseif v:FindFirstChild("TransparencyTag") then
						v.Transparency = v.TransparencyTag.Value
					end
				end
			end


			if self.ClientModel then
				for i,v in next,self.ClientModel:GetDescendants() do
					if v:IsA("BasePart") and not v:FindFirstChild("TransparencyTag") then
						v.Transparency =  0
					end
					if v:FindFirstChild("TransparencyTag") then
						v.Transparency = v.TransparencyTag.Value
					end
				end

				if Tool.Name == "G36" then
					self.ClientModel.Sight.Lense.Transparency = 1
				end
			end
			if self.ClientModel2 then
				for i,v in next,self.ClientModel2:GetDescendants() do
					if v:IsA("BasePart") and not v:FindFirstChild("TransparencyTag") then
						v.Transparency =  0
					elseif v:IsA("BasePart") then
						v.Transparency = 0
					end
				end
			end


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


			for i,v in pairs(self.ViewModel["Right Arm"]:GetDescendants()) do
				if v:IsA("BasePart")  and v.Name ~= "RightGlove" and v.Name ~= "LeftGlove" then
					v.Transparency = 0
				end
			end
			for i,v in pairs(self.ViewModel["Left Arm"]:GetDescendants()) do
				if v:IsA("BasePart")  and v.Name ~= "RightGlove" and v.Name ~= "LeftGlove" then
					v.Transparency = 0
				end
			end


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
	end
	function Gun:Equip()

		self:Retool()
		self:_setClientScoped(nil)

		TweenPropertyOut(workspace.CurrentCamera,"FieldOfView",0.1,tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value))

		if isScopeEnabled(self.Tool) then
			CH.Visible = false
			self.ScopeGUI = ensureScopeGui()
			self.GUI = self.ScopeGUI and self.ScopeGUI:FindFirstChild(self.Tool.Name.."_Scope")
			if not self.GUI then
				self.Equipping = false
				warn(("[Gun] Missing scope UI for %s"):format(self.Tool.Name))
				return
			end
		else
			CH.Visible = true
		end

		self.Equipping = true
		
		_G.HideOtherVM()
		
		Remotes.Server.Inventory.EquipItem:FireServer(self.ID)
		if not self:_bindToolEvents(2, true) then
			self.Equipping = false
			warn(("[Gun] Timed out waiting for equipped tool events (%s)"):format(tostring(self.ID)))
			return
		end
		self.SoundFolder = self.Tool:WaitForChild("Sounds")
		self:_applyConfiguredAudio()
		coroutine.wrap(function()
			_G.InventoryForceUpdate()
		end)()
		
	

		if Framework.GetWeaponType(self.Model.Name) == "PS" or Framework.GetWeaponType(self.Model.Name) == "TR" or Framework.GetWeaponType(self.Model.Name) == "SMG" then
			_G.CurrentWeaponSign =-1
		else
			_G.CurrentWeaponSign = 1
		end

		InputService.MouseIconEnabled = false
	

		if isScopeEnabled(self.Tool) then

			self.GUI.Visible = false
			self.AimEvent:FireServer("Equip")
		end

		ClientPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		InputService.MouseBehavior = Enum.MouseBehavior.LockCenter

		local LVM = LoadWeapon(self.Tool.Name)
		if not LVM then
			LoadViewModel(#Viewmodels + 1)
			LVM = LoadWeapon(self.Tool.Name)
		end

		_G.CurrentCVM = LVM

		self.ViewModel = LVM

		self.ViewAnimator = LVM:FindFirstChild("Animator",true) or Instance.new("Animator",LVM:WaitForChild("AnimationController") )

		self.ClientModel = self.ViewModel:FindFirstChild(self.Tool.Name,true)
		if _G.ViewmodelController and _G.ViewmodelController.DelayEquippedViewmodelVisible then
			_G.ViewmodelController:DelayEquippedViewmodelVisible(self.ViewModel, self.ClientModel, 0.1)
		end

		InputService.MouseDeltaSensitivity = getBaseMouseSensitivity()

		workspace.CurrentCamera.FieldOfView = tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value) or workspace.CurrentCamera.FieldOfView

		
		self:_applyAimGoal(0)
		
		if self.ViewModel["Torso"]:FindFirstChild("Neck") then
			self.ViewModel.Torso.Neck.C0 = CFrame.new(0, 1, 0, -1, 8.74227766e-08, 3.82137093e-15, 0, -4.37113883e-08, 1, 8.74227766e-08, 1, 4.37113883e-08)
		end
		if self.ViewModel["Right Arm"]:FindFirstChild("RightGrip") then
			self.ViewModel["Right Arm"].RightGrip.C1 = CFrame.new()
			self.ViewModel["Right Arm"].RightGrip.C0 = CFrame.new()
		end
		if self.ViewModel["Left Arm"]:FindFirstChild("LeftGrip") then
			self.ViewModel["Left Arm"].LeftGrip.C1 = CFrame.new()
			self.ViewModel["Left Arm"].LeftGrip.C0 = CFrame.new()
		end

		if self.WeaponConfigRaw.CopyRig then
			Framework.CopyRig(self.ViewModel,game.ReplicatedFirst.Assets.Models.RigCopy[self.Tool.Name])
		end

		if self.WeaponConfigRaw.C1 then
			self.ViewModel["Right Arm"].RightGrip.C1  = self.WeaponConfigRaw.C1
		end
		if self.WeaponConfigRaw.NeckC0 then
			self.ViewModel.Torso.Neck.C0 = self.WeaponConfigRaw.NeckC0
		end

		for i, v in next, self.ViewAnimator:GetPlayingAnimationTracks() do
			v:Stop()
		end

		self.CL_EQUIP   = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_EQUIP)
		self.CL_EQUIP.Priority = Enum.AnimationPriority.Movement
		self.EquipToPlay = self.CL_EQUIP
		if self.WeaponConfig.CLASS == "Sniper" then
			self.CL_BOLTEQUIP   = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_BOLTEQUIP)
			self.CL_BOLTEQUIP.Priority = Enum.AnimationPriority.Movement
			self.CL_BOLTEQUIP.KeyframeReached:Connect(function(KeyName)
				if self.SoundFolder:FindFirstChild(KeyName) then
					Framework.PlayRandomPitch(self.SoundFolder[KeyName],20)
				end
			end)

			if self.ShowBolt == true then
				self.ShowBolt = false
				self.EquipToPlay = self.CL_BOLTEQUIP
			end
		end

		-- from beginning of :Fire()
		self.ClientModel = self.ViewModel:FindFirstChild(self.Name)
		self:_setupFirePoints()
		self.ClientModel2 = self.ViewModel:FindFirstChild(self.Name.."2")
		if self.IsDual then
			self:_setupFirePoints()
		end

		if self.WeaponConfig.ALTEQUIP then
			self.ALTEQUIP = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_ALTEQUIP)
			self.ALTEQUIP.Priority = Enum.AnimationPriority.Movement
			self.ALTEQUIP.KeyframeReached:Connect(function(KeyName)
				Framework.PlayRandomPitch(self.SoundFolder[KeyName],20)
			end)
			local Roll= math.random(1,self.WeaponConfigRaw.ALTEQUIPCHANCE)
			if Roll == 1 then
				self.EquipToPlay = self.ALTEQUIP
			end	
		end
		self.CL_EQUIP.KeyframeReached:Connect(function(KeyName)
			self.SoundFolder[KeyName]:Play()
		end)
		if self.Model.Name == "Vector" then
			self.ClientModel:WaitForChild("ScreenDot").Transparency = 1
			self.ClientModel:WaitForChild("ScreenOutline").Transparency = 1
			--CL_EQUIP.KeyframeReached:Connect(function(KeyName)
			--	if KeyName == "MakeVisible" then
			--		local Sight1 =self.ClientModel:WaitForChild("ScreenDot")
			--		local Sight2 =self.ClientModel:WaitForChild("ScreenOutline")
			--		local Info = TweenInfo.new(1,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,false,0)
			--		local Tween1 = TweenService:Create(Sight1,Info,{Transparency = 0})
			--		local Tween2 = TweenService:Create(Sight2,Info,{Transparency = 0})
			--		Tween1:Play()
			--		Tween2:Play()

			--	end

			--end)
			local Sight1 = self.ClientModel:WaitForChild("ScreenDot")
			local Sight2 = self.ClientModel:WaitForChild("ScreenOutline")
			local Info = TweenInfo.new(1,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,false,0)
			local Tween1 = TweenService:Create(Sight1,Info,{Transparency = 0})
			local Tween2 = TweenService:Create(Sight2,Info,{Transparency = 0})
			Tween1:Play()
			Tween2:Play()
		end

		self.CL_IDLE    = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_IDLE)
		self.CL_IDLE.Priority = Enum.AnimationPriority.Core
		self.CL_INSPECT = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_INSPECT)
		self.CL_INSPECT.Priority = Enum.AnimationPriority.Idle
		self.CL_ATTACK  = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_ATTACK)
		self.CL_ATTACK.Priority = Enum.AnimationPriority.Action
		self.CL_ATTACK.Looped = false
		self.CL_ATTACK.KeyframeReached:Connect(function(KeyName)
			if self.SoundFolder:FindFirstChild(KeyName) then
				local Sound = self.SoundFolder[KeyName]
				Framework.PlayRandomPitch(Sound,20)
			end
			if KeyName == "PumpInEject" then
				self.MainPart.Ejector.Shells:Emit(1)
				self.SoundFolder.PumpIn:Play()
			end
			if self.WeaponConfig.CLASS == "Sniper" then
				if KeyName == "BoltOut"  then
					self.MainPart.Ejector.Shells:Emit(1)
					self.ShowBolt = false
				end	
			end

		end)
		self.CL_INSPECT.KeyframeReached:Connect(function(KeyName)
			if self.SoundFolder:FindFirstChild(KeyName) then
				local Sound = self.SoundFolder[KeyName]
				Framework.PlayRandomPitch(Sound,20)
				table.insert(self.PlayingSounds,Sound)
			end
		end)
		self.CL_INSPECT.Stopped:Connect(function()
			for a,b in pairs(self.PlayingSounds) do
				b:Stop()
			end
		end)
		if self.IsDual then
			self.CL_ATTACK2  = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_ATTACK2)
			self.CL_ATTACK2.Priority = Enum.AnimationPriority.Action4
			self.CL_ATTACK2.Looped = false
			self.CL_ATTACK2.KeyframeReached:Connect(function(KeyName)
				if self.SoundFolder:FindFirstChild(KeyName) then
					local Sound = self.SoundFolder[KeyName]
					Framework.PlayRandomPitch(Sound,20)
				end
				if KeyName == "PumpInEject" then
					self.MainPart.Ejector.Shells:Emit(1)
					self.SoundFolder.PumpIn:Play()
				end
			end)
		end
		self.CL_RELOAD  = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_RELOAD)
		self.CL_RELOAD.Priority = Enum.AnimationPriority.Action4
		self.CL_RELOAD.Stopped:Connect(function()
			if self.Equipped then
				self:_finalizeReloadPose()
			end
		end)
		self.CL_RELOAD.KeyframeReached:Connect(function(KeyName)
			if KeyName == "MagHide" then
				self:_setReloadMagVisibility(false)
				return
			elseif KeyName == "MagShow" then
				self:_setReloadMagVisibility(true)
				return
			end
			local Sound = self.SoundFolder[KeyName]
			Framework.PlayRandomPitch(Sound,20)
		end)
		self.CL_GBI = self.ViewAnimator:LoadAnimation(game.ReplicatedFirst.Assets.Animations.GBI)
		if self.WeaponConfig.CLASS == "Shotgun" then
			self.CL_RELOAD.Looped = true
			self.CL_RELOAD2 = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_RELOAD2)
			self.CL_RELOAD.Priority = Enum.AnimationPriority.Action
			self.CL_RELOAD2.KeyframeReached:Connect(function(KeyName)
				if self.SoundFolder:FindFirstChild(KeyName) then
					local Sound = self.SoundFolder[KeyName]
					Framework.PlayRandomPitch(Sound,20)
				end
				if KeyName == "PumpInEject" then
					self.MainPart.Ejector.Shells:Emit(1)
					self.SoundFolder.PumpIn:Play()
				end
			end)
		end

		self.CL_IDLE.Looped = true

		local Data = SavedData
		local Loadout = Data[ClientPlayer.Team.Name.."Loadout"]
		local GloveSlot = Loadout:FindFirstChild("GloveSkin")

		local Team = ClientPlayer.Team
		self.CL_IDLE:Play()
		--self.MainPart.Ejector.Shells.Lifetime = NumberRange.new(1, 3)
		playSoundIfPresent(self.SoundFolder, "SwitchWeapon", 45)

		self.EquipTime = self.WeaponConfigRaw.EQUIP_TIME
		--if table.find(_G.CurrentAbilityData.Flaws,"Flimsy") then
		--	EquipTime *= 1.25
		--	EquipToPlay:AdjustSpeed(0.75)
		--end


		self.EquipToPlay:Play(0)
		
		_G.EquippingItem = self


		self:Retool()
		self:_bindSkinUpdates()

		
		coroutine.wrap(function()
			--self.MainPart = ClientPlayer.Character:FindFirstChild("WeaponModel",0.05):FindFirstChild("Main")
			--self.Model = ClientPlayer.Character:FindFirstChild("WeaponModel",0.05)
			

			--if not self.Model then
			--	self:Retool()
			--end
		

			Framework.TransparencyControl(
				self.TransparencyTable,
				"Hide",
				self.Model
			)
			if self.IsDual then
				self.Model2 = ClientPlayer.Character:WaitForChild("WeaponModel2")
				Framework.TransparencyControl(
					self.TransparencyTable,
					"Hide",
					self.Model2
				)
			end
			
			

			

		
			if self.MainPart.Skin.Value == "Stock" then
				--bruh
			elseif self.MainPart.Skin.Value == "" or self.MainPart.Owner.Value == "" then
				if SavedData[ClientPlayer.Team.Name.."Loadout"] then
					if SavedData[ClientPlayer.Team.Name.."Loadout"]:FindFirstChild(self.Name) then
						local SkinSlot = SavedData[ClientPlayer.Team.Name.."Loadout"][self.Name].Value
						local FoundApplied = self.Model:FindFirstChild("AppliedSkin")
						if FoundApplied then
							if FoundApplied.Value ~= SkinSlot then
								if SkinSlot ~= "Stock"  then
									ContainerService.ApplySkin(self.ClientModel,self.Name,FoundApplied.Value)
									if self.IsDual then

										ContainerService.ApplySkin(self.ClientModel2,self.Name,FoundApplied.Value)
									end
								end
							end

						else

							if SkinSlot ~= "Stock"  then
								ContainerService.ApplySkin(self.ClientModel,self.Name,SkinSlot)
								if self.IsDual then

									ContainerService.ApplySkin(self.ClientModel2,self.Name,SkinSlot)
								end
							end
						end

					end
				end
			else
				ContainerService.ApplySkin(self.ClientModel,self.Name,self.MainPart.Skin.Value)
			end
		end)()
		
		
		if self.WeaponConfigRaw.REMOVABLESUPPRESSOR == true then

			self.CL_SILENCERON   = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_SILENCERON)
			self.CL_SILENCEROFF   = self.ViewAnimator:LoadAnimation(self.ConfigAnim.CL_SILENCEROFF)
			self.CL_SILENCEROFF .Priority = Enum.AnimationPriority.Action4
			self.CL_SILENCERON .Priority = Enum.AnimationPriority.Action4
			self.CL_SILENCEROFF.Ended:Connect(function()
				self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].Transparency = 1
				self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].TransparencyTag.Value = 1
			end)
			self.CL_SILENCERON.Ended:Connect(function()
				self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].Transparency = 0
				self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].TransparencyTag.Value = 0
			end)
			if self.SilencerEnabled.Value == true then
				self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].Transparency = 0
				self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].TransparencyTag.Value = 0
			else
				self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].Transparency = 1
				self.ClientModel[self.WeaponConfigRaw.SILENCERNAME].TransparencyTag.Value = 1
			end

		end

		if self.Tool.Name == "G36" then
			self.ClientModel.Sight.Lense.Transparency = 1
		end


		task.delay(0,function()

			if self.ViewModel then
				--
				for i,v in next,self.ViewModel:GetDescendants() do
					if v:IsA("Texture") or v:IsA("Decal") then
						v.Transparency = 0
					elseif v:FindFirstChild("TransparencyTag") then
						v.Transparency = v.TransparencyTag.Value
					end
				end
			end


			if self.ClientModel then
				for i,v in next,self.ClientModel:GetDescendants() do
					if v:IsA("BasePart") and not v:FindFirstChild("TransparencyTag") then
						v.Transparency =  0
					elseif v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal") then
						v.Transparency = 0
					end
				end
			end

			if self.IsDual then
				if self.ClientModel2 then
					for i,v in next,self.ClientModel2:GetDescendants() do
						if v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal") then
							v.Transparency = 0
						end
					end
				end
				if self.ClientModel2 then
					for i,v in next,self.ClientModel2:GetDescendants() do
						if v:IsA("BasePart") and not v:FindFirstChild("TransparencyTag") then
							v.Transparency =  0
						elseif v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal") then
							v.Transparency = 0
						end
					end
				end
			end


			RunService.Heartbeat:Wait()

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


			for i,v in pairs(self.ViewModel["Right Arm"]:GetDescendants()) do
				if v:IsA("BasePart")  and v.Name ~= "RightGlove" and v.Name ~= "LeftGlove" then
					v.Transparency = 0
				end
			end
			for i,v in pairs(self.ViewModel["Left Arm"]:GetDescendants()) do
				if v:IsA("BasePart")  and v.Name ~= "RightGlove" and v.Name ~= "LeftGlove" then
					v.Transparency = 0
				end
			end


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

		

			self:HideVM(false)
		end)
		
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



		self.FirstEquip = true

		self:Retool()

	end
function Gun:Unequip()
		
		Framework.TransparencyControl(self.TransparencyTable,"Show",self.Model)
		if self.IsDual then
			Framework.TransparencyControl(self.TransparencyTable,"Show",self.Model2)
		end
		
		if self.HideCon then
			self.HideCon:Disconnect()
		end
		if self.SkinCon then
			self.SkinCon:Disconnect()
			self.SkinCon = nil
		end
		
	



		if self.IsAiming then
			TweenPropertyOut(workspace.CurrentCamera,"FieldOfView",(0.15),tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value))
			self.AimEvent:FireServer(false)
			self.IsAiming = false
			self:_applyAimGoal(0)
		end

		Remotes.Server.Inventory.UnequipItem:FireServer(self.ID)

		if self.ViewModel and self.ViewModel:FindFirstChild("Left Arm") then
			
			for i,v in pairs(self.ViewModel:GetDescendants())do
				if v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal") then
					v.Transparency = 1
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
		end

		if isScopeEnabled(self.Tool) then
			self:_setClientScoped(false)
			if self.GUI then
				self.GUI.Visible = false
			end
			InputService.MouseDeltaSensitivity = getBaseMouseSensitivity()
			TweenPropertyOut(workspace.CurrentCamera, "FieldOfView", 0.15, tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value))
			CH.Visible = true
			if self.ViewModel and self.ViewModel:FindFirstChild("Left Arm") then
				self:HideVM(true)
			end
			self.AimEvent:FireServer("Unequip")
		end
		if self.Grip then
			self.Grip.Part1 = nil
		end

		self.Equipped = false
		if _G.Equipped == self then
			_G.Equipped = nil
		end
		if _G.EquippingItem == self then
			_G.EquippingItem = nil
		end

		self.Equipping = false
		self.CanAttack = false


		if self.ViewAnimator then
			for i, v in pairs(self.ViewAnimator:GetPlayingAnimationTracks()) do
				v:Stop(0)
			end
		end
		

		self.Inspecting = false
		if self.cnt_Inspect then
			self.cnt_Inspect:Disconnect()
			self.cnt_Inspect = nil
		end
		task.wait()
		local restoredModel = getReferenceValue(self.GTool, "ToModel")
		if restoredModel then
			self.Model = restoredModel
		end
	
	end


	--_G.OffsetDecayToggle = false

	function Gun:HandleInputBegan(Input,InputSunk)
		if InputSunk then return end
		if Input.UserInputType == Enum.UserInputType.MouseButton1 and self.Equipped and self.CanAttack == true and not InputSunk  and PlayerData.CanUse.Value == "true" then
			if self.Automatic then
				self.Pressing = true
			else
				self:Fire()
			end
			return
		end
		if Input.KeyCode == Enum.KeyCode[SavedData.PlayerSettings.ControlSettings.ReloadKey.Value] and self.Equipped and not InputSunk and PlayerData.CanReload.Value == "true" and PlayerData.CanUse.Value == "true" then
			self:Reload()
			return
		end
		if Input.KeyCode == Enum.KeyCode[SavedData.PlayerSettings.ControlSettings.InspectKey.Value]
			and not InputSunk
			and self.Equipped
			and not self.Reloading
			and self.Inspecting == false
			and self.CL_INSPECT
			and not self.IsScoped
		then
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
		if Input.KeyCode == Enum.KeyCode[SavedData.PlayerSettings.ControlSettings.FireModeKey.Value] and self.WeaponConfigRaw.REMOVABLESUPPRESSOR == true and not InputSunk and self.Equipped and not self.Reloading and PlayerData.CanUse.Value == "true" and self.Inspecting == false  then
			self:RemoveSuppressor()
			return
		end
		if self.Switchable == true then
			if Input.KeyCode == Enum.KeyCode[SavedData.PlayerSettings.ControlSettings.FireModeKey.Value] and self.SwitchDB == false and self.CanAttack == true and self.Equipped then
				self.SwitchDB = true
				self.Automatic = not self.Automatic
				playSoundIfPresent(self.SoundFolder, "Switch", 45)
				wait(.25)
				self.SwitchDB = false
				return
			end
		end
		if Input.UserInputType == Enum.UserInputType.MouseButton2 and self.AimDB == false and self.CanAttack == true and self.Equipped then
			self.AimDB  = true
			if isScopeEnabled(self.Tool) then
				if not self:_canPredictScope() then
					self.AimDB = false
					return
				end

				local shouldScope = not self.GUI.Visible
				self.GUI.Visible = shouldScope
				self:_setClientScoped(shouldScope)
				CH.Visible = not shouldScope
				self.AimEvent:FireServer("Scope")
				task.wait(self.WeaponConfig.SCOPEDELAY)
				if self.IsScoped ~= shouldScope or not self.Equipped then
					self.AimDB = false
					return
				end
				if shouldScope then
					if self.CL_INSPECT then
						self.CL_INSPECT:Stop(0)
					end
					Framework.TransparencyControl(self.TransparencyTable,"Hide",self.Model)
					CH.Visible = false
					self:HideVM(true)
					InputService.MouseDeltaSensitivity = getScopedMouseSensitivity(self.WeaponConfig.SCOPEFOV)
					TweenPropertyIn(workspace.CurrentCamera,"FieldOfView",(self.WeaponConfig.SCOPEDELAY),self.WeaponConfig.SCOPEFOV)
				else
					CH.Visible = true
					Framework.TransparencyControl(self.TransparencyTable,"Show",self.Model)
					self:HideVM(false)
					InputService.MouseDeltaSensitivity = getBaseMouseSensitivity()
					TweenPropertyOut(workspace.CurrentCamera,"FieldOfView",(self.WeaponConfig.SCOPEDELAY),tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value))
				end
			elseif self.WeaponConfig.ADSENABLED == true then
				if not self.IsAiming then
					self.IsAiming = true
					CH.Visible = false
					self:_applyAimGoal(1)
					InputService.MouseDeltaSensitivity = tonumber(SavedData.PlayerSettings.ControlSettings.AimSensitivity.Value) or InputService.MouseDeltaSensitivity
					TweenPropertyIn(workspace.CurrentCamera,"FieldOfView",(0.15),self.WeaponConfig.ADSFOV)
					self.AimEvent:FireServer(true)
				end
			end
			if isScopeEnabled(self.Tool) then
				wait(0.1)
			else
				wait(2)
			end

			self.AimDB  = false
		end
	end
	function Gun:HandleInputEnded(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self.WeaponConfig.ADSENABLED then
				if self.IsAiming == true then
					self.IsAiming = false
					CH.Visible = true
					InputService.MouseDeltaSensitivity = getBaseMouseSensitivity()
					TweenPropertyOut(workspace.CurrentCamera,"FieldOfView",(0.15),tonumber(SavedData.PlayerSettings.GraphicsSettings.FOV.Value))
					self.AimEvent:FireServer(false)
					self:_applyAimGoal(0)
				end	
			end
		end
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.Pressing = false
		end
		if Input.KeyCode == Enum.KeyCode[SavedData.PlayerSettings.ControlSettings.InspectKey.Value] and PlayerData.CanUse.Value == "true" and self.CL_INSPECT then
			self.CL_INSPECT.Looped = false
		end
	end
	
	
	return Gun
end

return Module
