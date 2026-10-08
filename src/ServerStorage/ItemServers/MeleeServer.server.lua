local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tool = script.Parent
local Events = Tool:WaitForChild("Events")
local MouseEvent = Events:WaitForChild("MouseEvent")

local Framework = require(ReplicatedStorage.Modules.Framework)
local ContainerService = require(ReplicatedStorage.Modules.Services.ContainerService)
local Assets = ReplicatedFirst:WaitForChild("Assets")

local RawWeaponConfig = require(Tool:WaitForChild("WeaponConfig"))
local WeaponConfig = RawWeaponConfig
local AnimConfig = ReplicatedFirst.Assets.Animations:WaitForChild(Tool.Name)

local Model = Tool:WaitForChild("WeaponModel")
local MainPart = Model:WaitForChild("Main")
local SoundFolder = MainPart:WaitForChild("Sounds")
local ParticlesFolder = Assets:WaitForChild("Particles")
local PFPrimary = ParticlesFolder:WaitForChild("Primary")
local PFSplash = ParticlesFolder:WaitForChild("Splash")

local EquipTime = WeaponConfig.EQUIP_TIME
local WalkSpeed = WeaponConfig.WALKSPEED
local IsEquippedValue = script:FindFirstChild("IsEquipped")
if not IsEquippedValue or not IsEquippedValue:IsA("BoolValue") then
	if IsEquippedValue then
		IsEquippedValue:Destroy()
	end
	IsEquippedValue = Instance.new("BoolValue")
	IsEquippedValue.Name = "IsEquipped"
	IsEquippedValue.Parent = script
end

local ItemIDValue = Tool:WaitForChild("ItemID")
repeat
	task.wait(0.01)
until ItemIDValue.Value ~= ""
local ItemID = ItemIDValue.Value
repeat
	task.wait(0.01)
until _G.Items[ItemID] ~= nil
local GTool = _G.Items[ItemID]

if _G.RecentTags == nil then
	_G.RecentTags = {}
end

local state = {
	equipped = false,
	equipping = false,
	canAttack = false,
	player = nil,
	playerObj = nil,
	character = nil,
	grip = nil,
	animEquip = nil,
	animIdle = nil,
	animAttack1 = nil,
	animAttack2 = nil,
	lastAttackAt = 0,
}

local function resolveConfig()
	if not Tool.WeaponConfig:FindFirstChildOfClass("Configuration") then
		WeaponConfig = Framework.AddAttributes(RawWeaponConfig, Tool.WeaponConfig)
	else
		WeaponConfig = Tool.WeaponConfig.Configuration
	end
	WeaponConfig = Framework.IndexAttribute(WeaponConfig)
	EquipTime = WeaponConfig.EQUIP_TIME or EquipTime
	WalkSpeed = WeaponConfig.WALKSPEED or WalkSpeed
end

local function stopTrack(track)
	if track then
		track:Stop()
	end
end

local function playHitSound(sound, part, length)
	if not sound or not part then
		return
	end
	local soundPart = Instance.new("Part")
	soundPart.Name = "KnifeHitSound"
	soundPart.Transparency = 1
	soundPart.CanCollide = false
	soundPart.CanTouch = false
	soundPart.CanQuery = false
	soundPart.Anchored = true
	soundPart.Position = part.Position
	soundPart.Parent = workspace:FindFirstChild("Ignore") or workspace

	local newSound = sound:Clone()
	newSound.Parent = soundPart
	newSound:Play()

	local cleanupDelay = tonumber(length)
		or ((newSound.TimeLength > 0 and newSound.TimeLength + 0.1) or 3)
	Debris:AddItem(soundPart, cleanupDelay)
end

local function makeParticleFX(particle, position, normal)
	if not particle or not position or not normal then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.new(position, position + normal)
	attachment.Parent = workspace.Terrain

	local p = particle:Clone()
	p.Parent = attachment
	p:Emit(p.Rate)

	if particle.Name == "Dink" then
		Debris:AddItem(attachment, p.Lifetime.Max)
	else
		Debris:AddItem(attachment, p.Lifetime.Max + 1)
	end

	task.delay(0.15, function()
		if p then
			p.Enabled = false
		end
	end)
end

local function getRaycastData(raycastResult, fallbackPart)
	local position = nil
	local normal = nil

	if type(raycastResult) == "table" then
		position = raycastResult.Position
		normal = raycastResult.Normal
	end

	if typeof(position) ~= "Vector3" then
		position = fallbackPart and fallbackPart.Position or nil
	end
	if typeof(normal) ~= "Vector3" then
		normal = Vector3.new(0, 1, 0)
	end

	return position, normal
end

local function getTargetCharacter(target)
	if typeof(target) ~= "Instance" then
		return nil
	end
	if target:IsA("Model") and target:FindFirstChildOfClass("Humanoid") then
		return target
	end
	if target:IsA("BasePart") and target.Parent and target.Parent:FindFirstChildOfClass("Humanoid") then
		return target.Parent
	end
	return nil
end

local function getPlayerObjectByCharacter(character)
	local player = Players:FindFirstChild(character.Name)
	if player then
		return _G.Players[player.UserId], player
	end
	return _G.Players[character.Name], nil
end

local function playAttackAnim()
	local track = (math.random(1, 2) == 1) and state.animAttack1 or state.animAttack2
	if track then
		track:Play(0)
	end
end

local function canDamageTarget(attackerObj, targetObj)
	if not attackerObj or not targetObj then
		return false
	end
	if attackerObj.Team and targetObj.Team and attackerObj.Team.Name == targetObj.Team.Name then
		local teamDamage = ReplicatedStorage:FindFirstChild("GameObjects")
			and ReplicatedStorage.GameObjects:FindFirstChild("TeamDamage")
		if not teamDamage or teamDamage.Value ~= true then
			return false
		end
	end
	return true
end

local function buildTag(attackerName, weaponName, isBackstab, damage)
	local mode = isBackstab and "BS" or "S"
	return string.format("%s:%s:%s:%s", attackerName, weaponName, mode, tostring(damage))
end

local function registerTag(targetObj, tag)
	if not targetObj then
		return
	end
	local targetName = targetObj.PlayerName
	if not _G.RecentTags[targetName] then
		_G.RecentTags[targetName] = {}
	end
	table.insert(_G.RecentTags[targetName], tag)
end

local function applyKillKnockback(targetRoot, damage, isBackstab)
	if not targetRoot then
		return
	end
	local rgdoll = ReplicatedStorage:FindFirstChild("GameObjects")
		and ReplicatedStorage.GameObjects:FindFirstChild("RGDOLLKB")
	if not rgdoll then
		return
	end
	local multi = isBackstab and 3 or 1
	local direction = (Tool.WeaponModel.Main.Position - targetRoot.Position).Unit
	local velocity = direction * (-(damage / 3) + rgdoll.Value * multi)
	if Framework.ApplyVel then
		Framework:ApplyVel(targetRoot, velocity, 0.25)
	end
end

local function resolveDamageAndBackstab(attackerRoot, targetRoot, attackType)
	local targetToAttacker = (attackerRoot.Position - targetRoot.Position).Unit
	local targetLook = targetRoot.CFrame.LookVector
	local dot = targetToAttacker:Dot(targetLook)
	local isBackstab = dot >= 0.25

	local damage = WeaponConfig.DAMAGE
	if attackType == 2 then
		damage = WeaponConfig.DAMAGE2
	end

	if isBackstab then
		damage = WeaponConfig.CRITICAL_DAMAGE
		if attackType == 2 then
			damage += WeaponConfig.DAMAGE2
		end
	end

	return damage, isBackstab
end

local function onAttack(player, attackType, target, isAlive, raycastResult)
	if not state.equipped or not state.canAttack then
		return
	end
	if not player or not player:IsA("Player") then
		return
	end
	if state.playerObj then
		local eventPlayerObj = _G.Players and _G.Players[player.UserId]
		if eventPlayerObj ~= state.playerObj then
			return
		end
	elseif state.player and player ~= state.player then
		return
	end
	if not state.character or Tool.Parent ~= state.character then
		return
	end
	if state.playerObj and tonumber(state.playerObj.Health) <= 0 then
		return
	end

	attackType = tonumber(attackType) or 1
	if attackType ~= 1 and attackType ~= 2 then
		attackType = 1
	end

	local now = tick()
	local cooldown = attackType == 2 and (WeaponConfig.ATTACK_COOLDOWN_2 or WeaponConfig.ATTACK_COOLDOWN) or WeaponConfig.ATTACK_COOLDOWN
	if now - state.lastAttackAt < (cooldown or 0) * 0.8 then
		return
	end
	state.lastAttackAt = now

	local attackerRoot = state.character:FindFirstChild("HumanoidRootPart")
	if not attackerRoot then
		playAttackAnim()
		return
	end

	local targetCharacter = getTargetCharacter(target)
	if not targetCharacter or isAlive ~= true then
		playAttackAnim()
		return
	end

	local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	local forcefield = targetCharacter:FindFirstChildOfClass("ForceField")
	if forcefield and targetRoot then
		if ReplicatedFirst.Assets.Sounds:FindFirstChild("button.wav") and Framework.PlayHitSound then
			Framework.PlayHitSound(ReplicatedFirst.Assets.Sounds["button.wav"], 3, targetRoot, 3)
		end
		return
	end

	if not targetHumanoid or targetHumanoid.Health <= 0 or not targetRoot then
		playAttackAnim()
		return
	end

	local range = WeaponConfig.RANGE or 6
	local distance = (attackerRoot.Position - targetRoot.Position).Magnitude
	if distance > range + 1 then
		return
	end

	local targetObj = getPlayerObjectByCharacter(targetCharacter)
	if not targetObj then
		return
	end
	if not canDamageTarget(state.playerObj, targetObj) then
		return
	end

	local position, normal = getRaycastData(raycastResult, targetRoot)
	local damage, isBackstab = resolveDamageAndBackstab(attackerRoot, targetRoot, attackType)

	if attackType == 1 then
		if state.animAttack1 then
			state.animAttack1:Play(0)
		end
	else
		if state.animAttack2 then
			state.animAttack2:Play(0)
		end
	end

	task.wait(WeaponConfig.ATTACK_WAIT or 0)

	makeParticleFX(PFPrimary, position, normal)
	if isBackstab then
		makeParticleFX(PFSplash, position, normal)
		local critSound = SoundFolder:FindFirstChild("CRIT")
		if critSound then
			playHitSound(critSound, targetRoot)
		end
	else
		local stabSound = SoundFolder:FindFirstChild("Stab" .. tostring(math.random(1, 3)))
		if stabSound then
			playHitSound(stabSound, targetRoot)
		end
	end

	local attackerName = state.player and state.player.Name or (state.playerObj and state.playerObj.PlayerName) or "Unknown"
	local tag = buildTag(attackerName, Tool.Name, isBackstab, damage)
	registerTag(targetObj, tag)

	targetObj:TakeDamage(damage, tag)

	if state.playerObj and state.playerObj.Traits and table.find(state.playerObj.Traits, "Surgical") then
		if _G.Message then
			_G.Message(state.playerObj, "Your surgical precision causes your knife to instantly kill.")
		end
		targetObj:TakeDamage(999, tag)
	end

	if targetHumanoid.Health <= 0 then
		applyKillKnockback(targetRoot, damage, isBackstab)
	end
end

MouseEvent.OnServerEvent:Connect(onAttack)

local function mountModel(character)
	for _, desc in ipairs(Model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = false
			local tag = desc:FindFirstChild("TransparencyTag")
			desc.Transparency = tag and tag.Value or 0
		end
	end
	Model.Parent = character
end

local function loadAnimations(character)
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end
	state.animEquip = humanoid:LoadAnimation(AnimConfig.SV_EQUIP)
	state.animIdle = humanoid:LoadAnimation(AnimConfig.SV_IDLE)
	state.animAttack1 = humanoid:LoadAnimation(AnimConfig.SV_ATTACK1)
	state.animAttack2 = humanoid:LoadAnimation(AnimConfig.SV_ATTACK2)
	if state.animIdle then
		state.animIdle.Looped = true
	end
end

local function resolveRightGrip(character)
	if not character then
		return nil
	end
	local armCandidates = {
		character:FindFirstChild("RightLowerArm"),
		character:FindFirstChild("RightHand"),
		character:FindFirstChild("Right Arm"),
		character:FindFirstChild("RightUpperArm"),
	}
	for _, arm in ipairs(armCandidates) do
		if arm then
			local grip = arm:FindFirstChild("RightGrip")
			if grip and grip:IsA("Motor6D") then
				return grip
			end
		end
	end
	local part0 = nil
	for _, arm in ipairs(armCandidates) do
		if arm and arm:IsA("BasePart") then
			part0 = arm
			break
		end
	end
	if not part0 then
		return nil
	end
	local newGrip = Instance.new("Motor6D")
	newGrip.Name = "RightGrip"
	newGrip.Part0 = part0
	newGrip.C0 = CFrame.new()
	newGrip.C1 = CFrame.new()
	newGrip.Parent = part0
	return newGrip
end

local function applyKnifeSkin(playerObj)
	if not playerObj then
		return
	end
	local tag = MainPart:WaitForChild("Skin")
	local ownerTag = MainPart:WaitForChild("Owner")
	if ownerTag.Value == "" then
		ownerTag.Value = playerObj.PlayerName
	end
	if tag.Value ~= "" then
		return
	end
	local skin = nil
	if playerObj.Team and playerObj.Team.Name ~= "Spectator" and playerObj.SavedData then
		local loadout = playerObj.SavedData[playerObj.Team.Name .. "Loadout"]
		if typeof(loadout) == "Instance" then
			local knifeSkinValue = loadout:FindFirstChild("KnifeSkin")
			if knifeSkinValue and knifeSkinValue:IsA("ValueBase") then
				skin = knifeSkinValue.Value
			end
		elseif type(loadout) == "table" then
			local knifeSkin = loadout.KnifeSkin
			if typeof(knifeSkin) == "Instance" and knifeSkin:IsA("ValueBase") then
				skin = knifeSkin.Value
			elseif type(knifeSkin) == "string" then
				skin = knifeSkin
			end
		end
	end
	if skin and skin ~= "Stock" then
		ContainerService.ApplySkin(Model, Tool.Name, skin)
	end
	tag.Value = skin or "Stock"
end

GTool.Init = function()
	resolveConfig()

	repeat
		task.wait()
	until Tool.Parent:IsA("Model")

	local character = Tool.Parent
	local isBot = character:FindFirstChild("IsBot")
	local player = nil
	local playerObj = nil

	if not isBot then
		player = Players:FindFirstChild(character.Name) or Players:GetPlayerFromCharacter(character)
		if player then
			playerObj = _G.Players[player.UserId]
		end
	else
		playerObj = _G.Players[character.Name]
	end
	if not player and playerObj and tonumber(playerObj.ID) then
		player = Players:GetPlayerByUserId(tonumber(playerObj.ID))
	end

	state.player = player
	state.playerObj = playerObj
	state.character = character
	state.grip = nil
	state.equipped = false
	IsEquippedValue.Value = false
	state.equipping = true
	state.canAttack = false
	state.lastAttackAt = 0

	local defaultSpeed = tonumber(ReplicatedStorage.GameObjects and ReplicatedStorage.GameObjects:FindFirstChild("MaxSpeed") and ReplicatedStorage.GameObjects.MaxSpeed.Value) or 21
	local equipSpeed = tonumber(WalkSpeed) or tonumber(defaultSpeed)
	if playerObj and equipSpeed then
		playerObj:SetWalkSpeed(equipSpeed)
	end

	local equipTime = tonumber(EquipTime) or 0
	if equipTime < 0 then
		equipTime = 0
	end

	mountModel(character)
	loadAnimations(character)
	applyKnifeSkin(playerObj)

	state.grip = resolveRightGrip(character)
	if state.grip then
		if WeaponConfig.SC0 then
			state.grip.C0 = WeaponConfig.SC0
		end
		if WeaponConfig.SC1 then
			state.grip.C1 = WeaponConfig.SC1
		end
		state.grip.Part1 = MainPart
	end

	if state.animEquip then
		state.animEquip.Priority = Enum.AnimationPriority.Action
		state.animEquip:Play(0)
	end

	for _ = equipTime, equipTime * 10 do
		if Tool.Parent ~= character then
			state.equipping = false
			break
		end
		if equipTime > 0 then
			task.wait(equipTime / 10)
		else
			task.wait()
		end
	end

	if state.equipping then
		state.equipped = true
		IsEquippedValue.Value = true
		state.canAttack = true
		if state.animIdle then
			state.animIdle.Priority = Enum.AnimationPriority.Action
			state.animIdle:Play(0)
		end
	end
end


GTool.Uninit = function()
	state.equipped = false
	IsEquippedValue.Value = false
	state.equipping = false
	state.canAttack = false
	state.lastAttackAt = 0

	stopTrack(state.animEquip)
	stopTrack(state.animIdle)
	stopTrack(state.animAttack1)
	stopTrack(state.animAttack2)

	if state.grip then
		state.grip.Part1 = nil
		state.grip.C0 = CFrame.new()
		state.grip.C1 = CFrame.new()
	end

	if ReplicatedStorage.ReferenceModels:FindFirstChild(ItemID) then
		Model.Parent = ReplicatedStorage.ReferenceModels[ItemID]
		Model:Destroy()
	else
		Model.Parent = nil
	end

	state.player = nil
	state.playerObj = nil
	state.character = nil
	state.grip = nil
	state.animEquip = nil
	state.animIdle = nil
	state.animAttack1 = nil
	state.animAttack2 = nil
end
