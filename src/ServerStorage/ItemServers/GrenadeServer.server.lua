---------------------------
-- Services & Modules  --
---------------------------
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerStorage       = game:GetService("ServerStorage")
local Teams               = game:GetService("Teams")
local SoundService        = game:GetService("SoundService")
local Players             = game:GetService("Players")
local UserInputService    = game:GetService("UserInputService")
local RunService          = game:GetService("RunService")
local TweenService        = game:GetService("TweenService")

local Tool                = script.Parent
local WeaponRepository    = ServerStorage:FindFirstChild("WeaponRepository")
local GrenadeRepository   = WeaponRepository and WeaponRepository:FindFirstChild("Grenade")

local UpdateRemote        = script:FindFirstChild("Update")
if not UpdateRemote or not UpdateRemote:IsA("RemoteEvent") then
	if UpdateRemote then
		UpdateRemote:Destroy()
	end
	UpdateRemote = Instance.new("RemoteEvent")
	UpdateRemote.Name = "Update"
	UpdateRemote.Parent = script
end

local function cloneGrenadeAsset(assetName)
	local repositoryAsset = GrenadeRepository and GrenadeRepository:FindFirstChild(assetName)
	if repositoryAsset then
		return repositoryAsset:Clone()
	end

	local legacyAsset = script:FindFirstChild(assetName)
	if legacyAsset then
		return legacyAsset:Clone()
	end

	error(("GrenadeServer is missing required asset '%s' in ServerStorage.WeaponRepository.Grenade"):format(assetName))
end

local WeaponConfig        = require(Tool:WaitForChild("WeaponConfig"))
local AnimConfig          = game.ReplicatedFirst.Assets.Animations:WaitForChild("Grenade")
local Model               = Tool:WaitForChild("WeaponModel")
local Framework           = require(ReplicatedStorage.Modules.Framework)
local RWC                 = require(Tool.WeaponConfig) -- used for attribute setup

---------------------------
-- Configuration & Globals  --
---------------------------
local EquipTime           = WeaponConfig.EQUIP_TIME
local WalkSpeed           = WeaponConfig.WALKSPEED
local MUST_BOUNCE         = WeaponConfig.MUSTBOUNCEBEFORETIMER
local seenDistance        = WeaponConfig.RANGE

-- Animation variables (will be set during tool initialization)
local SV_EQUIP, SV_IDLE, SV_PULL, SV_PULLIDLE, grip

-- State flags
local Equipping, Equipped, CanAttack = false, false, false

-- Wait for valid ItemID then get the associated global tool
local ItemIDObj = Tool:FindFirstChild("ItemID")
repeat wait(0.01) until ItemIDObj and ItemIDObj.Value ~= ""
local ItemID = ItemIDObj.Value
local GTool = _G.Items[ItemID]

-- Ignore list for raycasts – initialized during equip
local ignoreList

-- Table to store active grenades
local activeGrenades = {}

---------------------------
-- Utility Functions  --
---------------------------
-- FromAxisAngle converts an axis-angle rotation into a CFrame rotation.
local function fromAxisAngle(x, y, z)
	if not y then
		x, y, z = x.x, x.y, x.z
	end
	local m = math.sqrt(x * x + y * y + z * z)
	if m > 1e-5 then
		local s = math.sin(m/2) / m
		return CFrame.new(0,0,0, s*x, s*y, s*z, math.cos(m/2))
	else
		return CFrame.new()
	end
end

-- Checks if a character’s head sees the explosion.
local function sightCheck(explosionPos, headCFrame, ignore, charName)
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = ignore
	rayParams.FilterType = Enum.RaycastFilterType.Blacklist

	local origin = headCFrame.Position
	local toExplosion = explosionPos - origin
	local distance = toExplosion.Magnitude
	if distance <= 1e-4 then
		return true
	end

	local dotCF = toExplosion.Unit
	local lookCF = headCFrame.LookVector
	local dp = dotCF:Dot(lookCF)

	local rayResult = workspace:Raycast(origin, toExplosion, rayParams)
	local hasLineOfSight = (not rayResult) or (rayResult.Instance and rayResult.Instance:FindFirstAncestor(charName))
	if not hasLineOfSight then
		return false
	end

	if dp >= 0.25 then
		return true
	end
	return "kinda"
end

-- Creates an effect on all clients.
local function createEffect(effectName, ...)
	ReplicatedStorage.Remotes.Server.CreateEffect:FireAllClients(effectName, { ... })
end

local function sanitizeDamageTagValue(value)
	return tostring(value or ""):gsub(":", ""):gsub("%|", "")
end

local function buildDamageTag(attackerName, weaponName, flags, damage)
	local roundedDamage = math.floor((tonumber(damage) or 0) * 10 + 0.5) / 10
	return table.concat({
		sanitizeDamageTagValue(attackerName),
		sanitizeDamageTagValue(weaponName),
		sanitizeDamageTagValue(flags),
		tostring(roundedDamage),
	}, ":")
end

---------------------------
-- Grenade Class  --
---------------------------
local Grenade = {}
Grenade.__index = Grenade

function Grenade.new(args)
	local self = setmetatable({}, Grenade)

	-- Clone the grenade model and set initial properties
	self.model = game.ReplicatedFirst.Assets.Models[Tool.Name]:Clone()
	self.model.Parent = workspace.Ignore
	self.position     = args.position and args.position or Vector3.new()
	self.velocity     = args.velocity or Vector3.new()
	self.acceleration = args.acceleration or Vector3.new()
	self.name = Tool.Name
	self.elasticity   = 0.25
	self.radius       = seenDistance
	self.id           = args.id

	-- Set fuse based on throw velocity
	if self.velocity.Magnitude <= 50 then
		self.fuseTime = tick() + 1
		self.acceleration = Vector3.new(0, -45, 0)
	else
		self.fuseTime = tick() + 1.5
	end

	-- Bounce control variables
	self.firstBounce  = false
	self.lastBounce   = false
	self.touchedInterval = tick() + 0.5
	self.exploded     = false

	-- Setup grenade physics
	local mainPart = self.model.Main
	mainPart.Massless = false
	mainPart:SetNetworkOwner(nil)
	mainPart.Anchored = true
	mainPart.CanCollide = true

	-- Connect touched event for bounce sound/effects
	mainPart.Touched:Connect(function()
		if tick() >= self.touchedInterval then
			self.touchedInterval = tick() + 0.15
			if self.model:FindFirstChild("Touched") then
				self.model.Touched:Play()
			end
			self.lastBounce = true
		end
	end)

	return self
end

function Grenade:explode()
	if self.exploded then return end
	self.exploded = true
	warn("Exploded")
	local explosionPos = self.model.Main.CFrame.Position

	-- Hide and freeze grenade parts
	for _, part in pairs(self.model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 1
			part.Anchored = true
		end
	end

	-- Handle explosion effects by grenade type
	if self.name == "Flashbang" or self.name == "HE Grenade" then
		createEffect("Explosion", explosionPos, self.name)
		-- Process each player in the game for flash/damage effects
		for _, playerData in pairs(_G.Players) do
			if playerData.CharacterObject and playerData.CharacterObject:FindFirstChild("Humanoid") and playerData.CharacterObject.Humanoid.Health > 0 then
				local hrp = playerData.CharacterObject:FindFirstChild("HumanoidRootPart")
				if hrp then
					local distance = (hrp.Position - explosionPos).Magnitude
					if distance <= self.radius then
						local tempIgnore = { workspace.Ignore }
						table.insert(tempIgnore, playerData.CharacterObject)
						for _, v in pairs(workspace:GetDescendants()) do
							if v:IsA("Accessory") then
								table.insert(tempIgnore, v)
							end
						end
						local check = sightCheck(explosionPos, playerData.CharacterObject.Head.CFrame, tempIgnore, playerData.CharacterObject.Name)
						if check then
							local constant = 1
							if table.find(playerData.Traits, "Relentless") then
								constant = constant * 0.35
							end
							if table.find(playerData.Flaws, "Sensitive") then
								constant = constant * 1.25
							end

							local normalizedDistance = (self.radius > 0) and math.clamp(distance / self.radius, 0, 1) or 1
							local proximity = 1 - normalizedDistance

							-- Apply flashbang GUI effects
							if self.name == "Flashbang" then
								local GUI = cloneGrenadeAsset("Flash")
								local flashTime = (check == true)
									and math.clamp(proximity * WeaponConfig.FLASH_MAX_LENGTH * constant, 1, WeaponConfig.FLASH_MAX_LENGTH * constant)
									or math.clamp((0.1 - normalizedDistance) * WeaponConfig.FLASH_MAX_LENGTH * constant, 1, WeaponConfig.FLASH_MAX_LENGTH * constant)
								GUI.Time.Value = flashTime
								GUI.Dist.Value = distance
								GUI.Brightness.Value = (check == true)
									and math.clamp(proximity * WeaponConfig.FLASH_BRIGHTNESS * constant, 0, WeaponConfig.FLASH_MAX_BRIGHTNESS * constant)
									or math.clamp((0.1 - normalizedDistance) * WeaponConfig.FLASH_BRIGHTNESS * constant, 0, WeaponConfig.FLASH_MAX_BRIGHTNESS * constant)
								if check ~= true then
									for _, child in pairs(GUI.Stun:GetChildren()) do
										child.Volume = 0.01
									end
								end
								GUI.Stun.Disabled = false
								GUI.Parent = playerData.CharacterObject

								if constant >= 1 then
									playerData:SetModifier("Mod", playerData.SpeedModifier + WeaponConfig.WALKSPEED_EFFECT)
									task.delay(2 * normalizedDistance, function()
										playerData:SetModifier("Mod", playerData.SpeedModifier - WeaponConfig.WALKSPEED_EFFECT)
									end)
								end
							end

							-- HE damage should be strongest near the blast center.
							if self.name == "HE Grenade" and WeaponConfig.DAMAGEENABLED then
								local visibilityScale = (check == true) and 1 or 0.3
								local dmg = math.max(0, proximity * WeaponConfig.DAMAGE * constant * visibilityScale)
								if dmg > 0 then
									local attackerObj = _G.Players and _G.Players[self.id]
									local attackerName = attackerObj and attackerObj.PlayerName or "Unknown"
									local damageTag = buildDamageTag(attackerName, self.name, "EX", dmg)
									playerData:TakeDamage(dmg, damageTag)
								end
							end
						end
					end
				end
			end
		end

	elseif self.name == "Smoke Grenade" then
		local smoke = game.ReplicatedFirst.Assets.Models.Smoke:Clone()
		local mult = table.find(_G.Players[self.id].Traits, "Autodidactic") and 1.5 or 1
		smoke:PivotTo(CFrame.new(explosionPos))
		smoke.Parent = workspace.Ignore
		smoke.SmokeAudio:Play()
		game.Debris:AddItem(smoke, WeaponConfig.SMOKE_LENGTH)

		local tweenInfo = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		smoke.LocalScript.Enabled = true

		local holdOld = Instance.new("Attachment", workspace.Lobby.Part)
		holdOld.WorldCFrame = CFrame.new(explosionPos)
		task.delay((10 * mult) - 4, function()
			for _, descendant in pairs(smoke:GetDescendants()) do
				if descendant:IsA("BasePart") then
					local tw = TweenService:Create(descendant, tweenInfo, { Transparency = 1 })
					tw:Play()
				elseif descendant:IsA("ParticleEmitter") then
					descendant.Parent = holdOld
					descendant.Enabled = false
				end
			end
			game.Debris:AddItem(holdOld, 10 * mult)
		end)
	end

	task.wait(0.5)
	self.model.Main.Transparency = 1
	game.Debris:AddItem(self.model, 10)
	self.model:Destroy()
end

function Grenade:step(deltaTime)
	if self.exploded then
		return true
	end

	-- fuse / bounce handling
	-- prefer using grenade's velocity magnitude for consistency rather than reading model physics
	local speed = self.velocity and self.velocity.Magnitude or 0
	if MUST_BOUNCE and self.firstBounce and tick() >= self.fuseTime then
		self:explode()
		return true
	elseif tick() >= self.fuseTime and not MUST_BOUNCE then
		self:explode()
		return true
	elseif MUST_BOUNCE and self.model and not self.firstBounce and speed <= 5 then
		-- flagged as 'first bounce' when slowed (matches your original intent)
		self.firstBounce = true
		self.fuseTime = tick() + 1.2
	end

	-- Integrate (semi-implicit / simple Euler)
	local newVelocity = self.velocity + deltaTime * self.acceleration
	local newPosition = self.position + deltaTime * self.velocity

	-- Prepare raycast
	local rayDir = newPosition - self.position
	if rayDir.Magnitude > 1e-8 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreList or {}
		-- Use workspace:Raycast so we can get hit.Normal
		local rayResult = workspace:Raycast(self.position, rayDir, params)

		if rayResult and rayResult.Instance then
			-- Extract true surface normal (guaranteed unit length)
			local n = rayResult.Normal
			-- safety: if for some reason normal is zero, fallback to simple opposite velocity
			if n.Magnitude <= 1e-8 then
				n = (self.velocity.Magnitude > 0) and self.velocity.Unit * -1 or Vector3.new(0,1,0)
			end

			-- Move grenade to the contact point (with tiny offset to avoid re-penetration)
			local contactPos = rayResult.Position
			self.position = contactPos + n * 0.001

			-- Decompose velocity into normal and tangential components
			local v = self.velocity
			local v_n = n * (v:Dot(n))            -- normal component (could be positive or negative)
			local v_t = v - v_n                   -- tangential component

			-- Compute coefficient of friction (clamped) and restitution (elasticity)
			-- Make friction computation safe if tangential speed is near zero
			local tanSpeed = v_t.Magnitude
			-- Example friction model: base friction scaled by acceleration magnitude
			local friction = 0.08 * (self.acceleration and self.acceleration.Magnitude or 0) * deltaTime
			-- Bound friction to [0, 1]
			friction = math.clamp(friction, 0, 1)

			-- Update tangential velocity (lost to friction)
			local v_t_after = (tanSpeed > 1e-6) and (v_t * math.max(0, 1 - friction)) or Vector3.new(0,0,0)
			-- Update normal velocity using restitution (elasticity)
			-- flip sign and apply elasticity: v_n' = -elasticity * v_n
			local v_n_after = -self.elasticity * v_n

			-- New velocity after bounce
			self.velocity = v_t_after + v_n_after

			self.lastBounce = true
		else
			-- no collision => accept integrated movement
			self.position = newPosition
			self.velocity = newVelocity
			self.lastBounce = false
		end
	else
		-- no movement this tick
		self.velocity = newVelocity
		self.lastBounce = false
	end

	-- Keep grenade visual in sync (position only)
	if self.model and self.model.Main then
		-- preserve orientation if you want: CFrame.new(position) is okay for a simple grenade
		self.model.Main.CFrame = CFrame.new(self.position)
		-- if other systems rely on AssemblyLinearVelocity, update it too:
		pcall(function() self.model.Main.AssemblyLinearVelocity = self.velocity end)
	else
		return true
	end

	return false
end

---------------------------
-- Grenade Manager Update  --
---------------------------
local function updateGrenades(deltaTime)
	for i = #activeGrenades, 1, -1 do
		local nade = activeGrenades[i]
		if not nade then
			table.remove(activeGrenades, i)
		else
			local shouldRemove = nade:step(deltaTime)
			if shouldRemove then
				table.remove(activeGrenades, i)
			end
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	updateGrenades(dt)
end)

---------------------------
-- Remote Event Handling  --
---------------------------
local thrown = false
UpdateRemote.OnServerEvent:Connect(function(player, key, data, cframe1, addVel)
	if not (player and player:IsA("Player")) then
		return
	end
	if not player.Character or Tool.Parent ~= player.Character then
		return
	end
	if thrown then return end

	if key == "Pull" then
		if SV_PULL and SV_PULLIDLE and not SV_PULLIDLE.IsPlaying then
			SV_PULL:Play()
			wait(SV_PULL.Length - 0.01)
			SV_PULLIDLE:Play()
		end
		return
	elseif key == "Throw" then
		local throwPower = tonumber(data) or 1
		throwPower = math.clamp(throwPower, 1, 4)
		local fallbackCF = player.Character:FindFirstChild("HumanoidRootPart")
			and player.Character.HumanoidRootPart.CFrame
			or CFrame.new()
		local throwCF = (typeof(cframe1) == "CFrame") and cframe1 or fallbackCF
		local inheritedVelocity = (typeof(addVel) == "Vector3") and addVel or Vector3.new()

		thrown = true
		if SV_PULLIDLE then
			SV_PULLIDLE:Stop()
		end
		if SV_PULL then
			SV_PULL:Stop()
		end

		local throwVelocity = throwCF.LookVector * ((throwPower / 4) * 100) + inheritedVelocity
		local newNade = Grenade.new{
			position     = throwCF.Position + throwCF.LookVector * 2,
			velocity     = throwVelocity,
			acceleration = Vector3.new(0, -80, 0),
			id           = player.UserId,
		}
		table.insert(activeGrenades, newNade)

		-- Force re-equip and cleanup tool
		local GPlayer = _G.Players and _G.Players[player.UserId]
		local itemIdObj = Tool:FindFirstChild("ItemID")
		local itemId = itemIdObj and itemIdObj.Value or nil
		local Item = itemId and _G.Items and _G.Items[itemId] or nil
		if GPlayer and Item then
			GPlayer:RemoveItemFromBackpack(Item.ID)
		end

		task.wait()
		script.Parent = workspace
		game.Debris:AddItem(script, 25)
		ReplicatedStorage.Remotes.Server.ForceEquip:FireClient(player)
		task.wait(25)
		if Item and Item.Destroy then
			Item:Destroy()
		end

		-- Reset state flags as needed
		Equipped = false
		Equipping = false
		CanAttack = false
		if SV_IDLE then
			SV_IDLE:Stop(0)
		elseif SV_EQUIP then
			SV_EQUIP:Stop(0)
		end
		if SV_PULLIDLE then
			SV_PULLIDLE:Stop(0)
		end
	end
end)

---------------------------
-- Tool Initialization & Uninitialization  --
---------------------------
GTool.Init = function()
	-- Ensure WeaponConfig has attributes set up
	Tool:WaitForChild("WeaponConfig", 0.25)
	if not Tool.WeaponConfig:FindFirstChildOfClass("Configuration") then
		WeaponConfig = Framework.AddAttributes(RWC, Tool.WeaponConfig)
	else
		WeaponConfig = Tool.WeaponConfig.Configuration
	end
	WeaponConfig = Framework.IndexAttribute(WeaponConfig)

	local character = Tool.Parent
	local isBot = character:FindFirstChild("IsBot")
	spawn(function()
		local playerObj
		if not isBot then
			local player = game.Players:WaitForChild(character.Name)
			playerObj = _G.Players[player.UserId]
		else
			playerObj = _G.Players[character.Name]
		end
		playerObj:SetWalkSpeed(WalkSpeed or WeaponConfig.WALKSPEED)
	end)

	ignoreList = { workspace.CurrentCamera, workspace:WaitForChild("Ignore"), character }

	Equipping = true
	grip = character["RightLowerArm"].RightGrip
	UserInputService.MouseIconEnabled = false
	wait()
	grip.Part1 = Model.Main

	SV_EQUIP    = character.Humanoid:LoadAnimation(AnimConfig.SV_EQUIP)
	SV_IDLE     = character.Humanoid:LoadAnimation(AnimConfig.SV_IDLE)
	SV_PULL     = character.Humanoid:LoadAnimation(AnimConfig.SV_PULL)
	SV_PULLIDLE = character.Humanoid:LoadAnimation(AnimConfig.SV_PULLIDLE)
	SV_PULLIDLE.Looped = true
	SV_EQUIP.Priority = Enum.AnimationPriority.Action
	SV_IDLE.Priority  = Enum.AnimationPriority.Idle
	SV_IDLE.Looped   = true

	SV_EQUIP:Play(0.1)
	for i = EquipTime, EquipTime * 10 do
		if Tool.Parent ~= character then
			Equipping = false
			warn("Equip process interrupted.")
			break
		end
		wait(EquipTime / 10)
	end

	if Equipping then
		Equipped = true
		CanAttack = true
		SV_IDLE:Play(0.1)
	end
end

GTool.Uninit = function()
	Equipped = false
	Equipping = false
	CanAttack = false

	if SV_IDLE then
		SV_IDLE:Stop(0)
	elseif SV_EQUIP then
		SV_EQUIP:Stop(0)
	end
	if SV_PULLIDLE then
		SV_PULLIDLE:Stop(0)
	end

	if grip then
		grip.C0 = CFrame.new()
		grip.C1 = CFrame.new()
	end

	if game.ReplicatedStorage.ReferenceModels:FindFirstChild(ItemID) then
		local WM = Tool:FindFirstChild("WeaponModel")
		if WM then
			WM.Parent = game.ReplicatedStorage.ReferenceModels[ItemID]
			WM:Destroy()
		end
	end

	-- Clear character/player references
	Character = nil
	Player = nil
end
