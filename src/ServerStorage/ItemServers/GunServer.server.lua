local Tool = script.Parent
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst= game:GetService("ReplicatedFirst")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local Model = Tool:WaitForChild("WeaponModel")
local MainPart = Model:WaitForChild("Main")
local AnimConfig = ReplicatedFirst.Assets.Animations:WaitForChild(Tool.Name)
local Events = Tool.Events
local MouseEvent = Events.MouseEvent
local ReloadEvent = Events.ReloadEvent
local SilencerEvent = Events.Suppressor
local AimEvent = Events.AimEvent

local WeaponRepository = ServerStorage:FindFirstChild("WeaponRepository")
local GunAssetRepository = WeaponRepository and WeaponRepository:FindFirstChild("Gun")

local FireBindable = script:FindFirstChild("Fire")
if not FireBindable or not FireBindable:IsA("BindableEvent") then
	if FireBindable then
		FireBindable:Destroy()
	end
	FireBindable = Instance.new("BindableEvent")
	FireBindable.Name = "Fire"
	FireBindable.Parent = script
end

local ReloadBindable = script:FindFirstChild("Reload")
if not ReloadBindable or not ReloadBindable:IsA("BindableEvent") then
	if ReloadBindable then
		ReloadBindable:Destroy()
	end
	ReloadBindable = Instance.new("BindableEvent")
	ReloadBindable.Name = "Reload"
	ReloadBindable.Parent = script
end

local IsEquippedValue = script:FindFirstChild("IsEquipped")
if not IsEquippedValue or not IsEquippedValue:IsA("BoolValue") then
	if IsEquippedValue then
		IsEquippedValue:Destroy()
	end
	IsEquippedValue = Instance.new("BoolValue")
	IsEquippedValue.Name = "IsEquipped"
	IsEquippedValue.Parent = script
end

local function cloneGunAsset(assetName)
	local repositoryAsset = GunAssetRepository and GunAssetRepository:FindFirstChild(assetName)
	if repositoryAsset then
		return repositoryAsset:Clone()
	end

	local legacyAsset = script:FindFirstChild(assetName)
	if legacyAsset then
		return legacyAsset:Clone()
	end

	error(("GunServer is missing required asset '%s' in ServerStorage.WeaponRepository.Gun"):format(assetName))
end

local FirePointObject = MainPart.FirePoint
local FireSound = MainPart.Sounds.Fire
local ImpactParticle = cloneGunAsset("ImpactParticle")

local Framework = require(ReplicatedStorage.Modules:WaitForChild("Framework"))
local WeaponData = ReplicatedStorage.Modules.Data:WaitForChild("WeaponData")
local ContainerService = require(ReplicatedStorage.Modules.Services.ContainerService)

local EntryName = script.Parent.Name
local Entry = Framework.GetJSONEntry(EntryName,WeaponData)

local FastCast = require(game.ReplicatedStorage:WaitForChild("Modules").GunServer.FastCastRedux)
local table = require(game.ReplicatedStorage:WaitForChild("Modules").GunServer.FastCastRedux.Table)
local PartCacheModule = require(game.ReplicatedStorage:WaitForChild("Modules").GunServer.PartCache)
local GlobalEnum = require(ReplicatedStorage.Modules.Data.GlobalEnum)		
local SAC = _G.SAC
local WeaponConfig = require(Tool:WaitForChild("WeaponConfig"))	


if script.Parent.Parent:IsA("Folder") then
	repeat task.wait(1) until not script.Parent.Parent:IsA("Folder")
end

-- Omitted: authored material-to-effect map.
local MaterialMap = {}

local function ResolveWeaponConfig(baseConfig)
	local resolvedConfig
	if not Tool.WeaponConfig:FindFirstChildOfClass("Configuration") then
		resolvedConfig = Framework.AddAttributes(baseConfig,Tool.WeaponConfig)
	else
		resolvedConfig = Tool.WeaponConfig.Configuration
	end
	return Framework.IndexAttribute(resolvedConfig)
end

WeaponConfig = ResolveWeaponConfig(WeaponConfig)

wait()
local CanBounce = WeaponConfig.BOUNCE
local IsDual = WeaponConfig.DUALWEAPON
if IsDual then
	Model2 = Tool:WaitForChild("WeaponModel2")
	MainPart2 = Model2.Main2
	IsLeftFire = true
end

local SoundFolder =	MainPart.Sounds

local EQUIP_TIME = WeaponConfig.EQUIP_TIME
local WalkSpeed = WeaponConfig.WALKSPEED
local BULLET_SPEED = 1000					-- Studs/second - the speed of the bullet
local BULLET_MAXDIST = WeaponConfig.MAXDIST						-- The furthest distance the bullet can travel 
local BULLET_GRAVITY = WeaponConfig.BULLET_GRAV	-- The amount of gravity applied to the bullet in world space (so yes, you can have sideways gravity)
local FIRE_DELAY = WeaponConfig.FIRE_RATE							-- The amount of time that must pass after firing the gun before we can fire again.
local BULLETS_PER_SHOT = WeaponConfig.BULLET_NUM	

local RNG = Random.new()							
local TAU = math.pi * 2	
local TRACERDELAY = 0.25

local CurrentAmmo = Tool.Ammo.Current
local ReserveAmmo = Tool.Ammo.Reserve
local Sounds = ReplicatedFirst.Assets.Sounds.HitSounds
local ParticlesFolder = ReplicatedFirst.Assets:WaitForChild("Particles")
local PFPrimary = ParticlesFolder.Primary
local PFSecondary = ParticlesFolder.Secondary
local PFKevlar = ParticlesFolder.Kevlar
local PFSplash = ParticlesFolder.Splash
local PFDink = ParticlesFolder.Dink
local PFSpark = ParticlesFolder.Spark
local WeaponClass = WeaponConfig.CLASS


local IsScoped = false
local ScopeRequestId = 0
local CanFire = true
local FireDelay = false
local PIERCE = true				
local Equipped = false
local Equipping = false
local DidParticles = false
local Grip
local RELOADING = false

local DEBUG = ReplicatedStorage.GameObjects.DEBUG.Value
FastCast.DebugLogging = DEBUG
FastCast.VisualizeCasts = DEBUG

local FireTable = Entry.FireTable
local GTool

local function setScopedState(player, scoped)
	local playerData = player and player:FindFirstChild("PlayerData")
	local scoping = playerData and playerData:FindFirstChild("Scoping")
	if scoping and scoping:IsA("BoolValue") then
		scoping.Value = scoped and true or false
	end
end

function debugprint(a)
	print(a)
end

local function syncExternalAmmoState()
	local toolRef = GTool and GTool.Tool
	if not toolRef then
		return
	end
	local ammoFolder = toolRef:FindFirstChild("Ammo")
	if not ammoFolder then
		return
	end
	local currentValue = ammoFolder:FindFirstChild("Current") or ammoFolder:FindFirstChild("CurrentAmmo")
	if currentValue and currentValue:IsA("ValueBase") then
		currentValue.Value = CurrentAmmo.Value
	end
	local reserveValue = ammoFolder:FindFirstChild("Reserve") or ammoFolder:FindFirstChild("ReserveAmmo")
	if reserveValue and reserveValue:IsA("ValueBase") then
		reserveValue.Value = ReserveAmmo.Value
	end
end

local function PlayMuzzleEffects(mainPart, track)
	if track then
		track:Play()
	end
	mainPart.Ejector.Shells:Emit(BULLETS_PER_SHOT)
	mainPart.FirePoint.MuzzleFlash:Emit(BULLETS_PER_SHOT)
	mainPart.FirePoint.Smoke:Emit(WeaponConfig.SMOKEC)
	mainPart.FirePoint.FlashPL.Enabled = true
end

local function ResetFlash(mainPart)
	if mainPart.FirePoint.FlashPL.Enabled == true then
		mainPart.FirePoint.FlashPL.Enabled = false
	end
	if mainPart.FirePoint.FlashPL.Brightness ~=  2 then
		mainPart.FirePoint.FlashPL.Brightness = 2
	end
end

local function CreateEffect(EffectName,...)
	--print("Create Effect",EffectName)
	ReplicatedStorage.Remotes.Server.CreateEffect:FireAllClients(EffectName,{...})
end

local function sanitizeDamageTagValue(value)
	return tostring(value or ""):gsub(":", ""):gsub("%|", "")
end

local function buildDamageTag(attackerName, weaponName, flags, damage, hitGroup, distance, timestamp)
	local roundedDamage = math.floor((tonumber(damage) or 0) * 10 + 0.5) / 10
	local roundedDistance = math.floor((tonumber(distance) or 0) + 0.5)
	local roundedTime = math.floor((tonumber(timestamp) or tick()) * 1000)
	return table.concat({
		sanitizeDamageTagValue(attackerName),
		sanitizeDamageTagValue(weaponName),
		sanitizeDamageTagValue(flags),
		tostring(roundedDamage),
		sanitizeDamageTagValue(hitGroup),
		tostring(roundedDistance),
		tostring(roundedTime),
	}, ":")
end

local function resolveCastShooter(activeCast, playerService)
	local userData = activeCast and activeCast.UserData
	local shooterName = nil
	local shooterId = nil

	if type(userData) == "table" then
		local playerNameField = userData.PlayerName
		if type(playerNameField) == "table" then
			shooterName = playerNameField.PlayerName or playerNameField.Name
			shooterId = playerNameField.PlayerId or playerNameField.ID or playerNameField.UserId
		elseif type(playerNameField) == "string" then
			shooterName = playerNameField
		end
		if shooterId == nil then
			shooterId = userData.PlayerId
		end
	elseif type(userData) == "string" then
		shooterName = userData
	end

	local shooter = nil
	if type(shooterName) == "string" and shooterName ~= "" then
		shooter = playerService:GetPlayerFromName(shooterName)
	end

	if not shooter and shooterId ~= nil then
		shooter = playerService:GetPlayerFromID(shooterId)
	end

	if not shooterName and shooter and shooter.PlayerName then
		shooterName = shooter.PlayerName
	end

	return shooter, shooterName
end

local LegTable = {"RightLowerLeg" ,"RightUpperLeg" ,"LeftLowerLeg" ,"LeftUpperLeg"}
local BodyTable = {"UpperTorso",}
local ArmTable = {"LeftLowerArm" ,"RightLowerArm","LeftUpperArm" ,"RightUpperArm"}
local SmallTable = {"RightHand","LeftHand","RightFoot","LeftFoot","LowerTorso"}

local AllTable = Framework.InsertArrays(LegTable,BodyTable,ArmTable,SmallTable)

if  WeaponConfig.SCOPEENABLED == true then

	AimEvent.OnServerEvent:Connect(function(Player,ARG)
		local GUI = Player.PlayerGui.Scope:WaitForChild(Tool.Name.."_Scope")

		if ARG == "Scope" then
			ScopeRequestId += 1
			local requestId = ScopeRequestId
			wait(WeaponConfig.SCOPEDELAY)
			if requestId ~= ScopeRequestId or Tool.Parent ~= Player.Character then
				return
			end
			IsScoped = not IsScoped
			setScopedState(Player, IsScoped)
		elseif ARG == "Unequip" or ARG == "Equip" then
			ScopeRequestId += 1
			if IsScoped then
				IsScoped = false
				setScopedState(Player, false)
			end
		elseif ARG == "Fire" then
			ScopeRequestId += 1
			local wasScoped = IsScoped
			if wasScoped then
				IsScoped = false
				setScopedState(Player, false)
				if Tool.Name ~= "M110" then
					AimEvent:FireClient(Player,false)
				end
			end
			local fireRequestId = ScopeRequestId
			wait(FIRE_DELAY)
			if fireRequestId ~= ScopeRequestId then
				return
			end
			if wasScoped and not IsScoped and Tool.Parent == Player.Character and Player.SavedData.PlayerSettings.ControlSettings.AutoScope == "true" then
				IsScoped = true
				setScopedState(Player, true)
				AimEvent:FireClient(Player,true)
			end
		elseif ARG == "IsScoped" then
			AimEvent:FireClient(Player,IsScoped)
		end
	end)
elseif WeaponConfig.ADSENABLED == true then

	AimEvent.OnServerEvent:Connect(function(Player,ARG)
		IsScoped = ARG
		
		GP.PlayerData.Aiming.Value = ARG
	end)
	
	

elseif WeaponConfig.SCOPEENABLED == false and WeaponConfig.ADSENABLED == false then
	AimEvent.OnServerEvent:Connect(function(LPlayer)
		pcall(function()
			SAC.TimeBan(LPlayer,1361,"months","pepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap",nil,"SAC")
		end)
	end)
end


-- Cosmetic bullet container
local CosmeticBulletsFolder = workspace:FindFirstChild("CosmeticBulletsFolder") or Instance.new("Folder", workspace)
CosmeticBulletsFolder.Name = "CosmeticBulletsFolder"

-- Now we set the caster values.
local Caster = FastCast.new() --Create a new caster object.


local CosmeticBullet = cloneGunAsset("Tracer")
CosmeticBullet.Material = Enum.Material.Neon
CosmeticBullet.Color = WeaponConfig.CCOL
CosmeticBullet.CanCollide = false
CosmeticBullet.Anchored = true
CosmeticBullet.Size = WeaponConfig.CSIZE
CosmeticBullet.Beam.Enabled = false

-- New raycast parameters.
local CastParams = RaycastParams.new()
CastParams.IgnoreWater = true
CastParams.FilterType = Enum.RaycastFilterType.Exclude
CastParams.FilterDescendantsInstances = {}


local CosmeticPartProvider = PartCacheModule.new(CosmeticBullet, 25, CosmeticBulletsFolder)

local CastBehavior = FastCast.newBehavior()
CastBehavior.RaycastParams = CastParams
CastBehavior.MaxDistance = BULLET_MAXDIST
CastBehavior.HighFidelityBehavior = FastCast.HighFidelityBehavior.Default


CastBehavior.CosmeticBulletProvider = CosmeticPartProvider 

CastBehavior.CosmeticBulletContainer = CosmeticBulletsFolder
CastBehavior.Acceleration = BULLET_GRAVITY
CastBehavior.AutoIgnoreContainer = false

local MinimumDropoffDamage = WeaponConfig.DAMAGE * WeaponConfig.MAX_DAMAGEDROPOFF
local LAG_COMP_MAX_REWIND = 0.35
local LAG_COMP_LEAD_TOLERANCE = 0.05
local CLIENT_SHOT_ORIGIN_MAX_OFFSET = 8

local function getLagCompTelemetryRoot()
	_G.LagCompTelemetry = _G.LagCompTelemetry or {
		Counters = {},
	}
	if not _G.GetLagCompTelemetrySnapshot then
		_G.GetLagCompTelemetrySnapshot = function()
			local counters = (_G.LagCompTelemetry and _G.LagCompTelemetry.Counters) or {}
			local copy = {}
			for key, value in pairs(counters) do
				copy[key] = value
			end
			return copy
		end
	end
	return _G.LagCompTelemetry
end

local function bumpLagCompCounter(counterName)
	if type(counterName) ~= "string" or counterName == "" then
		return
	end
	local telemetry = getLagCompTelemetryRoot()
	local counters = telemetry.Counters
	counters[counterName] = (counters[counterName] or 0) + 1
end

local function getServerNow()
	if workspace and workspace.GetServerTimeNow then
		return workspace:GetServerTimeNow()
	end
	return os.clock()
end

local function sanitizeShotServerTime(rawShotTime)
	local now = getServerNow()
	local requested = tonumber(rawShotTime)
	local reason = "ok"
	if requested == nil then
		requested = now
		reason = "missing"
	elseif requested ~= requested then
		requested = now
		reason = "nan"
	end
	local minAllowed = now - LAG_COMP_MAX_REWIND
	local maxAllowed = now + LAG_COMP_LEAD_TOLERANCE
	local clamped = math.clamp(requested, minAllowed, maxAllowed)
	if clamped ~= requested then
		if requested < minAllowed then
			reason = "clamped_past"
		else
			reason = "clamped_future"
		end
	end
	bumpLagCompCounter("sanitize_" .. reason)
	return clamped, now, reason
end

local function sanitizeShotOrigin(rawShotOrigin, fallbackOrigin, character)
	if typeof(fallbackOrigin) ~= "Vector3" then
		return rawShotOrigin, "fallback_missing"
	end

	if typeof(rawShotOrigin) ~= "Vector3" then
		bumpLagCompCounter("origin_fallback_missing")
		return fallbackOrigin, "fallback_missing"
	end

	if (rawShotOrigin - fallbackOrigin).Magnitude > CLIENT_SHOT_ORIGIN_MAX_OFFSET then
		bumpLagCompCounter("origin_fallback_offset")
		return fallbackOrigin, "fallback_offset"
	end

	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		if (rawShotOrigin - head.Position).Magnitude > CLIENT_SHOT_ORIGIN_MAX_OFFSET then
			bumpLagCompCounter("origin_fallback_head_offset")
			return fallbackOrigin, "fallback_head_offset"
		end
	end

	bumpLagCompCounter("origin_client")
	return rawShotOrigin, "client"
end

local function mapShotToSnapshotTime(shotServerTime, shotServerNow)
	local now = getServerNow()
	local referenceNow = tonumber(shotServerNow) or now
	local age = math.clamp(referenceNow - shotServerTime, 0, LAG_COMP_MAX_REWIND)
	return now - age, age
end

local function resolveSnapshotPartName(hitPart)
	if not hitPart then
		return nil
	end
	local redirect = hitPart:FindFirstChild("Redirect")
	if redirect and redirect:IsA("ObjectValue") and redirect.Value and redirect.Value:IsA("BasePart") then
		return redirect.Value.Name
	end
	return string.gsub(hitPart.Name, "^Ghost_", "")
end

local function buildLagCompRayParams(shooterCharacter, targetCharacter)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local ignore = {}
	if shooterCharacter then
		table.insert(ignore, shooterCharacter)
	end
	if targetCharacter then
		table.insert(ignore, targetCharacter)
	end
	local workspaceIgnore = workspace:FindFirstChild("Ignore")
	if workspaceIgnore and workspaceIgnore:FindFirstChild("Ghosts") then
		table.insert(ignore, workspaceIgnore.Ghosts)
	end
	params.FilterDescendantsInstances = ignore
	return params
end

local function resolveRewoundHitPosition(targetPlayer, snapshotPartName, samplePart, hitPos, shotServerTime, now)
	if not (targetPlayer and snapshotPartName and samplePart and hitPos and type(shotServerTime) == "number") then
		return nil, "invalid_input"
	end
	local ghosts = _G.Ghosts
	if not ghosts then
		return nil, "no_ghost_table"
	end
	local manager = ghosts[targetPlayer.ID]
	if not manager or not manager.History then
		return nil, "no_manager"
	end
	local snapshotClock = mapShotToSnapshotTime(shotServerTime, now)
	local snapshot = manager._GetSnapshotForTime and manager:_GetSnapshotForTime(snapshotClock)
	if not (snapshot and snapshot.Parts) then
		return nil, "no_snapshot"
	end
	local snapshotPartCFrame = snapshot.Parts[snapshotPartName]
	if not snapshotPartCFrame then
		return nil, "missing_part"
	end
	local localPoint = samplePart.CFrame:PointToObjectSpace(hitPos)
	return snapshotPartCFrame:PointToWorldSpace(localPoint), "rewound"
end

local function passesRewoundOcclusionCheck(shooterCharacter, targetCharacter, origin, rewoundHitPosition)
	if not (targetCharacter and origin and rewoundHitPosition) then
		return false
	end
	local direction = rewoundHitPosition - origin
	if direction.Magnitude <= 0 then
		return true
	end
	local params = buildLagCompRayParams(shooterCharacter, targetCharacter)
	local rayResult = workspace:Raycast(origin, direction, params)
	if not rayResult then
		return true
	end
	return rayResult.Instance and rayResult.Instance:IsDescendantOf(targetCharacter)
end




function ApplyVel(part,velocity,timenum)
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.Velocity = velocity
	bv.Parent = part
	game:GetService("Debris"):AddItem(bv, timenum)
end
local SoundReplicationService = Framework.GetService("SoundReplicationService")
local function EmitGunfireHeardCue()
	-- Omitted: AI hearing/aiming/fire integration.
end

function PlayFireSound()
	local audioMultiplier = tonumber(Entry.AudioVolumeMultiplier) or 1
	if Entry.FireTable then
		for a,b in pairs(FireTable) do
			local Split = string.split(b,":")
			if Split[1] == "Sound" then
				local NewSound = SoundFolder[Split[2]]:Clone()
				NewSound.Volume *= audioMultiplier
				NewSound.Parent = MainPart
				NewSound:Play()
				Debris:AddItem(NewSound, NewSound.TimeLength)
			elseif Split[1] == "Wait" or Split[1] == "wait" then
				task.wait(tonumber(Split[2]))
			end
		end
	else
		SoundReplicationService:AnnounceSound(FireSound,{
			
			originName = PlayerOBJ.PlayerName,
			soundType = "WeaponAttack",
			parent = MainPart,
			pitchRange = 15,
			volume = FireSound.Volume * audioMultiplier
		})
	end
	EmitGunfireHeardCue()
end

function PlayHitSound(Sound,Part)
	SoundReplicationService:AnnounceSound(Sound,{

		originName = PlayerOBJ.PlayerName,
		soundType = "HitSound",
		parent = Part,
		pitchRange = 15
	})
end


function MakeParticleFX(Particle,position,normal)
	if not Particle then return end
	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.new(position, position + normal)
	attachment.Parent = workspace.Terrain
	local particle = Particle:Clone()
	particle.Parent = attachment
	particle:Emit(particle.Rate)
	if Particle.Name == "Dink" then
		Debris:AddItem(attachment, particle.Lifetime.Max) 
	else
		Debris:AddItem(attachment, particle.Lifetime.Max + 1) 
	end 

	wait(0.15)
	particle.Enabled = false

end


function PlayHitAnim(Type,Humanoid)
	pcall(function()
		if not Humanoid then return end
	if Type == "Head" then
		if not Humanoid then return end
		local Anim = ReplicatedFirst.Assets.Animations["TDHEAD"..math.random(1,2)]
		local AnimTrack = Humanoid:LoadAnimation(Anim)
		AnimTrack:Play(0)
	else 
		if not Humanoid then return end
		local Anim = ReplicatedFirst.Assets.Animations["TDBODY"..math.random(1,2)]
		local AnimTrack = Humanoid:LoadAnimation(Anim)
		AnimTrack:Play(0)
	end
	end)
	
end

--	-- get the incident angle using cos
	
local function Reflect(surfaceNormal, bulletNormal)
		local Dot = bulletNormal:Dot(surfaceNormal)
		local Magnitudes = bulletNormal.Magnitude * surfaceNormal.Magnitude
	local Angle = math.deg(math.acos(Dot/Magnitudes)) - 90
	--print("Angle : ",Angle,"Radians :", math.acos(Dot/Magnitudes))
	local Chance = math.random(1,math.clamp(Angle/9,1,360))
	if Chance == 1 then
		return bulletNormal - (2 * bulletNormal:Dot(surfaceNormal) * surfaceNormal),true
	else
		return bulletNormal,false
	end
end



local LastShotTime = tick()
local SprayCount = 0

function Fire(player,direction,AssumedSpeed,Class,shotServerTime,shotOrigin)
	
	if Tool.Parent:IsA("Backpack") or Tool.Parent:IsA("Folder") then return end
	repeat wait() until Player
	local Character = Tool.Parent
	local Humanoid = Character:WaitForChild("Humanoid")
	local JumpingState
	
	AssumedSpeed = tonumber(AssumedSpeed) or 0

	if AssumedSpeed == 0 then
		AssumedSpeed = 0.01
	elseif AssumedSpeed < 0 then
		SAC.TimeBan(player,"1392","months","pepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap\npepega clap",nil,"SAC")
	elseif AssumedSpeed > _G.Players[player.UserId].Speed * 2.5 then
		_G.UserData[player.UserId].AssumedSpeedFlags += 1
		if _G.UserData[player.UserId].AssumedSpeedFlags >= _G.SAC.MaxAssumedFlags then
			SAC.TimeBan(player,"1","weeks","You can appeal this by sending a clip of gameplay, include the ban notice.\nYou can be unbanned after a flag without sending a clip once.",nil,"SAC")
		end
	end

	if Humanoid.FloorMaterial == Enum.Material.Air then
		JumpingState = true
	else
		JumpingState = false
	end

	if Humanoid.Health <= 0 then return end

	local NewSpread
	local SpreadRamp = false
	
	GP = _G.Players[player.UserId]

	local CurrentSpeed = Character:FindFirstChild("HumanoidRootPart").AssemblyLinearVelocity.Magnitude
	
	--print("CurrentSpeed:",CurrentSpeed,"AssumedSpeed:",AssumedSpeed)
	
	CurrentSpeed = CurrentSpeed - ((AssumedSpeed - CurrentSpeed)/2)
	CurrentSpeed = math.clamp(CurrentSpeed,0,100)
	
	GP.UserData.LastFire = tick()
	
	local BaseSpread = RNG:NextNumber(WeaponConfig.MIN_BASESPREAD,WeaponConfig.MAX_BASESPREAD)
	
	if table.find(GP.Traits,"Relaxed") then
		BaseSpread = RNG:NextNumber(math.clamp(WeaponConfig.MIN_BASESPREAD * 0.2,0,0.25),WeaponConfig.MAX_BASESPREAD)
	end
	if table.find(GP.Solvers,"Ballistic Solver") and GP.SolutionStage >= 1 then
		if math.random(1,5) == 5 then
			_G.SMessage(GP,"Internal ballistics have been solved. Recalculating...")
		end
		BaseSpread = 0
	end
	
	local FIRE_RATE = FIRE_DELAY
	if table.find(GP.Traits,"Manic") then
		FIRE_RATE *= (1/1.25)
	end
	if GP.UserData.Switch then
		FIRE_RATE *= (1/1.25)
	end
	local function ApplyApexAccuracy(Input)
		if JumpingState == true and CurrentSpeed <= WeaponConfig.JUMPAPEXACCURACYSPEED then
			return WeaponConfig.JUMPAPEXACCURACY
		else
			return Input
		end	
	end

	local function ApplyMovementInAccuracy(Input)
		if CurrentSpeed > WeaponConfig.INACCURATESPEED then
			local DIF = CurrentSpeed - WeaponConfig.INACCURATESPEED
			local NS = Input + (WeaponConfig.MOVESPREAD + (DIF * WeaponConfig.MOVEMENTINACCURACYMULT))
			if table.find(GP.Traits,"Active") then
				NS *= 0.5
			elseif  table.find(GP.Traits,"Precise") then
				NS *= 0.85
				
			end
			if table.find(GP.Solvers,"Ballistic Solver") and GP.SolutionStage >= 3 then
				NS *= 0.1
				if math.random(1,5) == 5 then
					_G.SMessage(GP,"Movement accuracy adjustments have been solved. Recalculating...")
				end
			end
			return NS
		else
			return Input
		end
	end

	local function ApplySpreadRamp(Input)
		local RT = Input + WeaponConfig.SPREADRAMP * (SprayCount or 1)
		if table.find(GP.Traits,"Autodidactic") then
			RT = Input
		end
		return RT
	end

	local function ApplyScopedSpread(Input)
		
		if IsScoped then
			return WeaponConfig.ADSSPREAD
		elseif GP.PlayerData.Aiming.Value == true then
			local RT = WeaponConfig.MIN_BASESPREAD
			if table.find(GP.Traits,"Precise") then
				RT = 0
			end
			return RT
		else
			
			return Input
		end
	end

	
	local Decay = WeaponConfig.RECOILDECAYTIME
	if table.find(GP.Traits,"Paranoid") then
		WeaponConfig.RECOILDECAYTIME *= 0.1
	end


	if tick() - LastShotTime <= Decay and SprayCount >= 1 then
		SprayCount += 1
		SpreadRamp = true
	else
		SprayCount = 0
		SpreadRamp = false
	end
	
	--print("BaseSpread:",BaseSpread)

	if LastShotTime < FIRE_RATE  then
		--print("Are you cheating, ",Character.Name.."?")
		_G.Offenses[Character.Name] += 1
		if _G.Offenses[Character.Name] > 12 then
			_G.Players[Character.Name]:TakeDamage(150)
			SAC.TimeBan(player,"3","weeks","You can appeal this by sending a clip of gameplay, include the ban notice.\nYou can be unbanned after a flag without sending a clip once.",nil,"SAC")
		end
		return
	end

	NewSpread = ApplyScopedSpread(NewSpread)

	NewSpread = ApplyMovementInAccuracy(BaseSpread)
	
	--print("NewMoveSpread:",NewSpread)

	if SpreadRamp == true then
		NewSpread = ApplySpreadRamp(NewSpread)
	end

	NewSpread = ApplyApexAccuracy(NewSpread)

	NewSpread = math.clamp(NewSpread,0,WeaponConfig.SPREADCAP)
	if table.find(GP.Solvers,"Reserve Corps") and GP.SolutionStage >= 5 then
		NewSpread *= (1 - ((tick() - GP.UserData.LastFire)/20))
		NewSpread = math.clamp(NewSpread,0,1)
		_G.TellSS(GP.PlayerObject)
	end
	
	if table.find(GP,"Total Concentration") then
		_G.TellSS(GP.PlayerObject)
		local TC = GP.SolverData["TC"]
		if TC > 0 then
			TC -= 1
			NewSpread = 0.0001
		end
	end

	debugprint(Character.Name,NewSpread)

	local directionalCF = CFrame.new(Vector3.new(), direction)
	local direction = (directionalCF * CFrame.fromOrientation(0, 0, RNG:NextNumber(0, TAU)) * CFrame.fromOrientation(math.rad(NewSpread), 0, 0)).LookVector


	LastShotTime = tick()

	local NewBulletSpeed = BULLET_SPEED


	if PIERCE then
		CastBehavior.CanPierceFunction = CanRayPierce
	end	
	if not IsDual then
		PlayMuzzleEffects(MainPart, FireTrack)
		
	else
		
		if IsLeftFire == true then
			PlayMuzzleEffects(MainPart, FireTrack)
		else
			PlayMuzzleEffects(MainPart2, FireTrack2)
		end
		IsLeftFire = not IsLeftFire
	end
	
	
	local shooterName = (GP and GP.PlayerName) or (player and player.Name) or Character.Name
	local defaultCastOrigin = Character.Head.Position
	local castOrigin, castOriginReason = sanitizeShotOrigin(shotOrigin, defaultCastOrigin, Character)
	local safeShotTime, shotNow, sanitizeReason = sanitizeShotServerTime(shotServerTime)
	local simBullet = Caster:Fire(castOrigin, direction, direction* NewBulletSpeed, CastBehavior, shooterName)
	if simBullet then
		simBullet.UserData = {
			PlayerName = shooterName,
			PlayerId = GP and GP.ID or (player and player.UserId),
			MouseDirection = direction,
			ShotServerTime = safeShotTime,
			ShotServerNow = shotNow,
			ShotTimeSanitizeReason = sanitizeReason,
			CastOrigin = castOrigin,
			CastOriginReason = castOriginReason,
			DidPenetrateWall = false,
			PenetrationReduction = 0,
		}
	end
	if Class ~= "Shotgun" then
			PlayFireSound()
	end

	wait()
	
	

	task.wait(0.25)
	
	ResetFlash(MainPart)
	if IsDual then
		ResetFlash(MainPart2)
	end
	
	
	
	
	
	
	
end




function BotFire(GP,LV,AssumedSpeed)
	-- Omitted: AI hearing/aiming/fire integration.
end

local function resolveBotFireActor(actor)
	-- Omitted: AI hearing/aiming/fire integration.
end

-- Omitted: bot-fire event handler and bot trait/policy wiring.

function TracerAdded(ActiveCast,CosmeticBulletObject)
	if WeaponConfig.FLASHENABLED ~= true then
		return
	end

	local mouseDir = ActiveCast and ActiveCast.UserData and ActiveCast.UserData.MouseDirection
	if typeof(mouseDir) ~= "Vector3" then
		return
	end

	local castOrigin = Model.Main.FirePoint.WorldCFrame
	local rayOrigin = ActiveCast and ActiveCast.RayInfo and ActiveCast.RayInfo.Origin
	if typeof(rayOrigin) == "Vector3" then
		castOrigin = CFrame.new(rayOrigin, rayOrigin + mouseDir)
	elseif typeof(rayOrigin) == "CFrame" then
		castOrigin = rayOrigin
	end

	local firingPlayerName
	local playerService = Framework.GetService("PlayerService")
	if playerService then
		local _, resolvedName = resolveCastShooter(ActiveCast, playerService)
		firingPlayerName = resolvedName
	end

	CreateEffect("Tracer", firingPlayerName, Tool.WeaponConfig.Configuration, mouseDir, castOrigin)
end

function OnRayHit(ActiveCast, raycastResult, segmentVelocity, cosmeticBulletObject)

	local HitPart = raycastResult.Instance
	local HitPos = raycastResult.Position
	local HitNormal = raycastResult.Normal
	local lagCompSamplePart = HitPart
	local lagCompPartName = resolveSnapshotPartName(HitPart)
	local Distance = CastBehavior.DistanceCovered
	local WB = false
	local GhostCF = false
	local PlayerService = Framework.GetService("PlayerService")
	
	debugprint("RayHit : "..HitPart:GetFullName())

	local FiringPlayer, firingPlayerName = resolveCastShooter(ActiveCast, PlayerService)
	if not FiringPlayer then 
		debugprint("NoFiringPlayer") 
		return
	end
	if HitPart ~= nil and FiringPlayer.Health > 0  then 
		
		if HitPart:FindFirstChild("HitEvent") then
			HitPart.HitEvent:Fire(firingPlayerName)
			MakeParticleFX(ParticlesFolder["Kevlar"],HitPos,HitNormal)
			return
		end
		
		if HitPart:FindFirstChild("Redirect") then
			local Redirect = HitPart:FindFirstChild("Redirect")
			if not (Redirect and Redirect.Value and Redirect.Value:IsA("BasePart")) then
				return
			end
			HitPart = Redirect.Value
			lagCompPartName = HitPart.Name
			if HitPart.Parent.Name == firingPlayerName then
				return
			end
			--print("Backtracked")
			local ghostRoot = Redirect.Parent and Redirect.Parent.Parent and Redirect.Parent.Parent:FindFirstChild("Ghost_HumanoidRootPart")
			if ghostRoot then
				GhostCF = ghostRoot.CFrame
			end
		end
		
		local FHumanoid = HitPart.Parent:FindFirstChildOfClass("Humanoid")
		local Forcefield = HitPart.Parent:FindFirstChildOfClass("ForceField")
		
		if Forcefield then return end
		
		local CharName 

		if FHumanoid then
			CharName =  FHumanoid.Parent.Name
			

			if ActiveCast.UserData.DidPenetrateWall == true then
				WB = true
			end

			local HitName = HitPart.Name
			local Leg,Head,Body,Arm,Small = false,false,false,false,false

			if HitName == "Head" then
				Head = true
			else 
				if table.find(LegTable,HitName)  then
						Leg = true
				end

				if table.find(BodyTable,HitName)  then
					Body = true
				end
				if table.find(ArmTable,HitName)  then
					Arm = true
				end
				if table.find(SmallTable,HitName)  then
					Small = true
				end

			end

			if string.find(HitName,"_Shader") then
				return
			end

			local Flags = Head and "HS" or "BS"
			if WB then
				Flags = Flags.."+WB"
			end

			debugprint("Tag : "..Flags)

		

			local PlayerObject

			if not PlayerService:GetPlayerFromName(FHumanoid.Parent.Name) then
				return
			else 
				PlayerObject = PlayerService:GetPlayerFromName(FHumanoid.Parent.Name) 
			end

			if not PlayerObject then
				return
			end
			if PlayerObject.IsAlive ~= true or PlayerObject.InGame ~= true then
				return
			end
			if not PlayerObject.CharacterObject or PlayerObject.CharacterObject ~= FHumanoid.Parent then
				return
			end
			if FHumanoid.Health <= 0 or (tonumber(PlayerObject.Health) or 0) <= 0 then
				return
			end

			local userData = ActiveCast and ActiveCast.UserData
			if type(userData) ~= "table" then
				userData = {}
				if ActiveCast then
					ActiveCast.UserData = userData
				end
			end
			local hitRegistry = userData.HitTargets
			if type(hitRegistry) ~= "table" then
				hitRegistry = {}
				userData.HitTargets = hitRegistry
			end
			local hitTargetKey = PlayerObject.ID or PlayerObject.PlayerName or FHumanoid.Parent.Name
			if hitTargetKey ~= nil then
				hitTargetKey = tostring(hitTargetKey)
				if hitRegistry[hitTargetKey] then
					bumpLagCompCounter("resolve_duplicate_target")
					return
				end
			end
			local shotServerTime = tonumber(userData.ShotServerTime)
			local shotServerNow = tonumber(userData.ShotServerNow) or getServerNow()
			local castOrigin = userData.CastOrigin
			if typeof(castOrigin) ~= "Vector3" then
				local rayInfo = ActiveCast and ActiveCast.RayInfo
				local rayOrigin = rayInfo and rayInfo.Origin
				if typeof(rayOrigin) == "Vector3" then
					castOrigin = rayOrigin
				elseif typeof(rayOrigin) == "CFrame" then
					castOrigin = rayOrigin.Position
				elseif FiringPlayer and FiringPlayer.CharacterObject and FiringPlayer.CharacterObject:FindFirstChild("Head") then
					castOrigin = FiringPlayer.CharacterObject.Head.Position
				end
			end

			local rewoundHitPosition = nil
			local lagCompReason = "missing_shot_time"
			if shotServerTime then
				rewoundHitPosition, lagCompReason = resolveRewoundHitPosition(
					PlayerObject,
					lagCompPartName,
					lagCompSamplePart,
					HitPos,
					shotServerTime,
					shotServerNow
				)
			end
			if rewoundHitPosition and castOrigin then
				if not passesRewoundOcclusionCheck(
					FiringPlayer and FiringPlayer.CharacterObject,
					PlayerObject.CharacterObject,
					castOrigin,
					rewoundHitPosition
				) then
					bumpLagCompCounter("resolve_occluded")
					return
				end
				HitPos = rewoundHitPosition
				lagCompReason = "rewind_applied"
			elseif rewoundHitPosition and not castOrigin then
				lagCompReason = "missing_cast_origin"
			end
			if lagCompReason then
				bumpLagCompCounter("resolve_" .. lagCompReason)
			end
			
			
			
			
			coroutine.wrap(function()
				if DidParticles == false then
					DidParticles = true
					task.delay(0.1,function()
						DidParticles = false
					end)
					if PlayerObject.Armor > 35 then
						if Head then
							PlayHitSound(Sounds["Helmet"..math.random(1,5)],HitPart)
							PlayHitSound(Sounds["Kevlar"..math.random(1,5)],HitPart)
							MakeParticleFX(PFDink,HitPos,HitNormal)
							MakeParticleFX(PFSpark,HitPos,HitNormal)
						elseif not Leg and Arm or Body then
							PlayHitSound(Sounds["Kevlar"..math.random(1,5)],HitPart)
							MakeParticleFX(PFKevlar,HitPos,HitNormal)
						elseif Leg then
							PlayHitSound(Sounds["Bullet"..math.random(1,3)],HitPart)
							MakeParticleFX(PFSplash,HitPos,HitNormal)
						end
					else
						if Head then
							PlayHitSound(Sounds["Headshot"..math.random(1,5)],HitPart)
							MakeParticleFX(PFPrimary,HitPos,HitNormal)
							MakeParticleFX(PFSplash,HitPos,HitNormal)
							MakeParticleFX(PFSecondary,HitPos,HitNormal)
						else 
							PlayHitSound(Sounds["Bullet"..math.random(1,3)],HitPart)
							MakeParticleFX(PFSplash,HitPos,HitNormal)
						end
					end

				end

			end)()
	
			
			
			
			if PlayerObject.Team.Name == FiringPlayer.Team.Name and ReplicatedStorage.GameObjects.TeamDamage.Value ~= true then
				return
			end

			if hitTargetKey ~= nil then
				hitRegistry[hitTargetKey] = true
			end
			
			

			local AP = WeaponConfig.PENETRATION
			local DamageType = ""
			local NewDamage 
			if Head == true then
				NewDamage = WeaponConfig.CRITICAL_DAMAGE 
				DamageType = "Head"
				PlayHitAnim("Head",PlayerObject.CharacterObject.Humanoid)
			elseif Body == true then
				NewDamage = WeaponConfig.DAMAGE
				DamageType = "Body"
				PlayHitAnim("Body",PlayerObject.CharacterObject.Humanoid)
			elseif Arm == true or Leg == true then
				NewDamage = WeaponConfig.DAMAGE * 0.45
				if Arm == true then
					DamageType = "Arm"
				else 
					DamageType = "Leg"
				end
				PlayHitAnim("Body",PlayerObject.CharacterObject.Humanoid)
			elseif Small == true then
				NewDamage = WeaponConfig.DAMAGE * 0.10
				DamageType = "Small"
			end
			
			if Player then
				ReplicatedStorage.Remotes.Server.SendHitInfo:FireClient(Player,DamageType,PlayerObject.Armor,PlayerObject.PlayerName)
			end
			

			if DamageType == "Body" or DamageType == "Arm" then

				local Const = 1
				if table.find(PlayerObject.Traits,"Lucky") then
					Const = 0.75
				end
				
				if PlayerObject.Armor ~= 0 and PlayerObject.Armor > 35 then

					NewDamage *= AP
					
					ArmorDamage = (NewDamage) * 0.75 * Const
					ArmorDifference = (PlayerObject.Armor - ArmorDamage)

					if math.sign(ArmorDifference) == -1 then
						NewDamage += ArmorDifference * Const
					end	

					
					if not Head then
						coroutine.wrap(function()
							PlayerObject:SetValue("Armor",math.clamp(ArmorDifference,0,100)) 
						end)()
						
					end

				elseif PlayerObject.Armor ~= 0 and PlayerObject.Armor < 35 and math.random(1,3) <= 2 then

					NewDamage *= AP

					ArmorDamage = (NewDamage) * 0.75 * Const
					ArmorDifference = (PlayerObject.Armor - ArmorDamage)

					if math.sign(ArmorDifference) == -1 then
						NewDamage += ArmorDifference * Const
					end	


					if not Head then
						coroutine.wrap(function()
							PlayerObject:SetValue("Armor",math.clamp(ArmorDifference,0,100)) 
						end)()
						
					end

				end

			end

			if WB then
				local PR = (ActiveCast.UserData.PenetrationReduction or 0)
				PR = math.clamp(PR,0,1)
				local RealPenetrationDamage = WeaponConfig.PENETRATIONDAMAGEPERCENT - PR
				NewDamage = (NewDamage) * (RealPenetrationDamage or 1)
				debugprint("WBAPPLIED:"..(NewDamage ) * (WeaponConfig.PENETRATIONDAMAGEPERCENT - PR))
			end


			if Distance then
				if Distance >= WeaponConfig.MIN_DAMAGEDROPOFFSTUDS then
					local frac = Distance / WeaponConfig.MAX_DAMAGEDROPOFFSTUDS
					local best = math.max(frac,WeaponConfig.MAX_DAMAGEDROPOFF)
					NewDamage = NewDamage - (NewDamage*best)
				end
			end
			
			NewDamage = math.clamp(NewDamage,MinimumDropoffDamage,1000)
			Vel = (MainPart.Position - HitPart.Position).Unit * -((NewDamage/10) + ReplicatedStorage.GameRules:WaitForChild("RGDOLLKB").Value)

			local function ApplyKB(Multi,Time)
				local MaxTime = 500
				local Index =  0
				ApplyKBConnection = workspace.RagdollPointers.ChildAdded:Connect(function(C)
					local OBJ = C.Value
					----print(C,C.Name,CharName,OBJ:GetFullName())
					if C.Name == CharName then
					
						----print("ApplyKB",OBJ)
						----print(HitName)
						local Part = OBJ:FindFirstChild(HitName)
						if Part then
							----print("FoundPart")
							if typeof(GhostCF) == "CFrame" then
								OBJ.HumanoidRootPart.CFrame = GhostCF
							end
							ApplyVel(Part,Vel,Time)
						end
						
						ApplyKBConnection:Disconnect()
					end	
				end)
			end
			
				
			local bruh = coroutine.create(function()
				----print("RanBruh")
				if PlayerObject.Armor <= 0 then
					ApplyKB(2,0.2)
				else
					ApplyKB(1,0.2)
				end
			end)
			
			if PlayerObject.Health - (NewDamage or 0) <= 0 then
				--print("WillDie")
				coroutine.resume(bruh)
			end

		
			coroutine.wrap(function()
				if PlayerObject then
				if table.find(FiringPlayer.Solvers,"Reserve Corps") and FiringPlayer.SolutionStage >= 1 and WeaponConfig.FIRE_RATE < 1/10 then
					NewDamage *= 1.2
				end
				if table.find(FiringPlayer.Solvers,"Reserve Corps") and FiringPlayer.SolutionStage >= 3 and Head == true then
					NewDamage *= 1.2
					_G.SMessage(FiringPlayer,"Successfully hit a vital area.")
				end
				
				if table.find(FiringPlayer.Solvers,"Reserve Corps") and FiringPlayer.SolutionStage >= 5 then
					NewDamage *= (1 + ((tick() - FiringPlayer.UserData.LastFire)/20))
				end
				if Distance then
					if table.find(PlayerObject.Solvers,"Dirac's Delta") and PlayerObject.SolutionStage >= 1 and Distance > 75 then
						NewDamage *= 0.5
						_G.RawMessage(PlayerObject,"[NOTICE] A bullet has phased through you. ",Color3.new(0.235294, 1, 0))
					end
				end
				
				local attackerName = "Unknown"
				if FiringPlayer and FiringPlayer.PlayerName then
					attackerName = FiringPlayer.PlayerName
				elseif type(firingPlayerName) == "string" and firingPlayerName ~= "" then
					attackerName = firingPlayerName
				end
				local damageTag = buildDamageTag(attackerName, Tool.Name, Flags, NewDamage, DamageType, Distance, tick())
				PlayerObject:TakeDamage(NewDamage,damageTag)
			end
			
			end)()
		
			

		
			

		end

	end
	
	coroutine.wrap(function()
		if HitPart ~= nil and HitPart.Transparency < 0.9 then
			if HitPart.Parent then
				if HitPart.Parent:FindFirstChildOfClass("Humanoid") then
					return
				end
			end

			CreateEffect("HitPart",HitPos,HitNormal,HitPart)
			MakeParticleFX(ImpactParticle,HitPos, HitNormal)

		end

	end)()

end


function CanRayPierce(ActiveCast, rayResult, segmentVelocity)

	local HitPart = rayResult.Instance

	if ActiveCast.UserData.DidPenetrateWall == nil then
		ActiveCast.UserData.DidPenetrateWall = false
	end
	
	if (ActiveCast.UserData.Hits  == nil) then
		ActiveCast.UserData.Hits = 1
	else
		ActiveCast.UserData.Hits += 1
	end
	
	----print(ActiveCast.UserData.Hits)
	
	if (ActiveCast.UserData.Hits > WeaponConfig.MAXPIERCE) then
		return false
	end
	

	if string.find(HitPart.Name,"Ghost_") then
		local FoundPart = HitPart.Redirect.Value
		if table.find(AllTable,FoundPart.Name) then
			local HitName = FoundPart.Name
			if table.find(BodyTable,HitName) then
				ActiveCast.UserData.PenetrationReduction += 0.15
			elseif table.find(ArmTable,HitName) then
				ActiveCast.UserData.PenetrationReduction += 0.15
			elseif table.find(LegTable,HitName) then
				ActiveCast.UserData.PenetrationReduction += 0.10
			elseif HitName == "Head" then
				ActiveCast.UserData.PenetrationReduction += 0.25
			end
		end
		return true
	end
	
	if HitPart.Transparency > 0.9 then
		ActiveCast.UserData.Hits -= 1
		return true
	end


	if string.find(HitPart.Name,"_Ignore") or string.find(HitPart.Name,"_Shader") or string.find(HitPart.Name,"HumanoidRootPart") or string.find(HitPart.Name,"CharacterHitbox")  then
		ActiveCast.UserData.Hits -= 1
		return true
	end
	
	
	if string.find(HitPart.Name,"Zone") or string.find(HitPart.Name,"Tracer") then
		return true
	elseif HitPart.Parent:IsA("Accessory") then
		return true
	elseif HitPart.Name == "RightGlove" or HitPart.Name == "LeftGlove" then
		return true 
	elseif table.find(AllTable,HitPart.Name) then
		local HitName = HitPart.Name
		if table.find(BodyTable,HitName) then
			ActiveCast.UserData.PenetrationReduction += 0.90
		elseif table.find(ArmTable,HitName) then
			ActiveCast.UserData.PenetrationReduction += 0.90
		elseif table.find(LegTable,HitName) then
			ActiveCast.UserData.PenetrationReduction += 0.90
		elseif HitName == "Head" then
			ActiveCast.UserData.PenetrationReduction += 1
		end
		
		return true
	end
	
	local FHumanoid = HitPart.Parent:FindFirstChildOfClass("Humanoid")

	local Chance = math.random(1,7)
	if MaterialMap[HitPart.Material] == "Metal" then
		Chance = 1
	end
	local newNormal,result = Vector3.new(),false
	
	if Chance == 1 then
		if not FHumanoid and ActiveCast.UserData.Hits < WeaponConfig.MAXPIERCE  then
			local position = rayResult.Position
			local normal = rayResult.Normal

			newNormal,result = Reflect(normal, segmentVelocity.Unit)
			ActiveCast:SetVelocity(newNormal * segmentVelocity.Magnitude)
			ActiveCast:SetPosition(position)
			if result == true then
				CreateEffect("Ricochet",position,normal,HitPart)
				return true
			end
		end
	end
	
	
	
	if HitPart:FindFirstChild("PenetrationInfo") and result == false then

		
	
		
		ActiveCast.UserData.DidPenetrateWall = true
		ActiveCast.UserData.PenetrationReduction += HitPart.PenetrationInfo.Value
		return true

	else 
		
		
		return false
	end





end



function OnRayPierced(ActiveCast, raycastResult, segmentVelocity, cosmeticBulletObject)
	
	


	local NewDamage
	local HitPart = raycastResult.Instance

	local HitPos = raycastResult.Position
	local HitNormal = raycastResult.Normal
	local Distance = CastBehavior.DistanceCovered
	local WB = false
	OnRayHit(ActiveCast,raycastResult,segmentVelocity,cosmeticBulletObject)
	
	
	
	if HitPart ~= nil and HitPart.Transparency < 0.9 then
		if HitPart.Parent then
			if HitPart.Parent:FindFirstChildOfClass("Humanoid") then
				return
			end
		end

		

		CreateEffect("HitPart",HitPos,HitNormal,HitPart)

		MakeParticleFX(ImpactParticle,HitPos, HitNormal)
	end

end
--[[
	if HitPart ~= nil  then 

		local FHumanoid = HitPart.Parent:FindFirstChildOfClass("Humanoid")

		if FHumanoid then

			local PlayerService = Framework.GetService("PlayerService")

			if ActiveCast.UserData.Hits > 2 then
				WB = true
			end

			local HitName = HitPart.Name
			local Leg,Head,Body,Arm,Small = false,false,false,false,false

			if HitName == "Head" then
				Head = true
			else 
				for a,b in pairs(LegTable) do
					if HitName == b then
						Leg = true
					end
				end
				for a,b in pairs(BodyTable) do
					if HitName == b then
						Body = true
					end
				end
				for a,b in pairs(ArmTable) do
					if HitName == b then
						Arm =true
					end
				end
				for a,b in pairs(SmallTable) do
					if HitName == b then
						Small = true
					end
				end

			end

			if string.find(HitName,"_Shader") then
				return
			end

			local Tag = ""

			if WB then
				if Head == true then
					Tag = ":HS+WB:"
				else
					Tag = ":BS+WB:"
				end
			else
				if Head == true then
					Tag = ":HS:"
				else
					Tag = ":BS:"
				end
			end

			debugprint("Tag : "..Tag)

			debugprint("RayHit : "..HitPart:GetFullName())


			local PlayerObject

			if not PlayerService:GetPlayerFromName(FHumanoid.Parent.Name) then
				return
			else 
				PlayerObject = PlayerService:GetPlayerFromName(FHumanoid.Parent.Name) 
			end


			if PlayerObject.Armor > 0 then
				if Head then
					PlayHitSound(Sounds["Dink"],HitPart)
					PlayHitSound(Sounds["Head"],HitPart)
					MakeParticleFX(PFDink,HitPos,HitNormal)
					MakeParticleFX(PFSpark,HitPos,HitNormal)
				elseif not Leg and Arm or Body then
					PlayHitSound(Sounds["Kevlar"..math.random(1,5)],HitPart)
					MakeParticleFX(PFKevlar,HitPos,HitNormal)
				elseif Leg then
					PlayHitSound(Sounds["Bullet"..math.random(1,3)],HitPart)
					MakeParticleFX(PFSplash,HitPos,HitNormal)
				end
			else
				if Head then
					PlayHitSound(Sounds["Head"],HitPart)
					MakeParticleFX(PFPrimary,HitPos,HitNormal)
					MakeParticleFX(PFSplash,HitPos,HitNormal)
					MakeParticleFX(PFSecondary,HitPos,HitNormal)
				else 
					PlayHitSound(Sounds["Bullet"..math.random(1,3)],HitPart)
					MakeParticleFX(PFSplash,HitPos,HitNormal)
				end
			end

			if PlayerObject.Team.Name == Player.Team.Name and ReplicatedStorage.GameObjects.TeamDamage.Value ~= true then
				return
			end

			local AP = WeaponConfig.PENETRATION
			local DamageType = ""

			if Head == true then
				NewDamage = WeaponConfig.CRITICAL_DAMAGE 
				DamageType = "Head"
				PlayHitAnim("Head",PlayerObject.CharacterObject.Humanoid)
			elseif Body == true then
				NewDamage = WeaponConfig.DAMAGE
				DamageType = "Body"
				PlayHitAnim("Body",PlayerObject.CharacterObject.Humanoid)
			elseif Arm == true or Leg == true then
				NewDamage = WeaponConfig.DAMAGE * 0.25
				if Arm == true then
					DamageType = "Arm"
				else 
					DamageType = "Leg"
				end
				PlayHitAnim("Body",PlayerObject.CharacterObject.Humanoid)
			elseif Small == true then
				NewDamage = WeaponConfig.DAMAGE * 0.10
				DamageType = "Small"
			end


			if DamageType == "Body" or DamageType == "Arm" then


				if PlayerObject.Armor ~= 0 and PlayerObject.Armor > 35 then

					NewDamage *= AP

					 ArmorDamage = (NewDamage) * 0.75
					 ArmorDifference = (PlayerObject.Armor - ArmorDamage)

					if math.sign(ArmorDifference) == -1 then
						NewDamage += ArmorDifference
					end	


					if not Head then
						PlayerObject:SetValue("Armor",math.clamp(ArmorDifference,0,100)) 
					end


				elseif PlayerObject.Armor ~= 0 and PlayerObject.Armor < 35 and math.random(1,3) <= 2 then

					NewDamage *= AP

					 ArmorDamage = (NewDamage) * 0.75
					 ArmorDifference = (PlayerObject.Armor - ArmorDamage)

					if math.sign(ArmorDifference) == -1 then
						NewDamage += ArmorDifference
					end	


					if not Head then
						PlayerObject:SetValue("Armor",math.clamp(ArmorDifference,0,100)) 
					end

				end

			end
			
			if WB then
				local RealPenetrationDamage = WeaponConfig.PENETRATIONDAMAGEPERCENT - (ActiveCast.UserData.PenetrationReduction or 0)
				NewDamage = (NewDamage + ArmorDifference) * RealPenetrationDamage
				debugprint("WBAPPLIED:"..(NewDamage + ArmorDifference) * (WeaponConfig.PENETRATIONDAMAGEPERCENT - (ActiveCast.UserData.PenetrationReduction or 0)))
			end


			if Distance then
				if Distance >= WeaponConfig.MIN_DAMAGEDROPOFFSTUDS then
					local frac = Distance / WeaponConfig.MAX_DAMAGEDROPOFFSTUDS
					NewDamage = NewDamage - (NewDamage*frac)
				end
			end
			
			NewDamage = math.clamp(NewDamage,MinimumDropoffDamage,1000)
			
			pcall(function()
			
			local TagString = Tool.Name..Tag..NewDamage

			AddTag(PlayerObject,TagString)
				
			end)


			if PlayerObject then
				PlayerObject:TakeDamage(NewDamage)
			end

		end

	end

	if HitPart == nil then
		MakeParticleFX(ImpactParticle,HitPos, HitNormal) 		
	end
--]]


function OnRayUpdated(ActiveCast, segmentOrigin, segmentDirection, length, segmentVelocity, cosmeticBulletObject)

	--if cosmeticBulletObject == nil then return end
	--local bulletLength = cosmeticBulletObject.Size.Z / 2 
	--local baseCFrame = CFrame.new(segmentOrigin, segmentOrigin + (segmentDirection))
	--if ActiveCast.StateInfo.TotalRuntime > TRACERDELAY and cosmeticBulletObject.Beam.Enabled == false then
	--	cosmeticBulletObject.Beam.Enabled = true
	--end 	
	--cosmeticBulletObject.CFrame = CFrame.new(segmentOrigin, segmentOrigin + (segmentDirection * (WeaponConfig.TRACERSPEED or 1)))
	
end

function OnRayTerminated(ActiveCast)
	local cosmeticBullet = ActiveCast.RayInfo.CosmeticBulletObject
	if cosmeticBullet ~= nil then
		if CastBehavior.CosmeticBulletProvider ~= nil then
			wait(1)
			CastBehavior.CosmeticBulletProvider:ReturnPart(cosmeticBullet)
		else	
			pcall(function()
				wait(1)
				cosmeticBullet:Destroy()
			end)
		end
	end
end

MouseEvent.OnServerEvent:Connect(function (clientThatFired, mousePoint,AssumedVelocity, arg3, arg4)
	--print(FireDelay)
	SHOTGUNCANCELRELOAD = true
	SHOTGUNCANCELRELOAD = false
	local GP = _G.Players[clientThatFired.UserId]
	repeat wait() until FireDelay == false and tonumber(GP.PlayerData.Health.Value) > 0 
	if RELOADING and WeaponConfig.CLASS ~= "Shotgun" then return end
	local mouseDirection = mousePoint
	local shotOrigin = nil
	local shotServerTime = nil
	if typeof(arg3) == "Vector3" then
		shotOrigin = arg3
		shotServerTime = arg4
	else
		shotServerTime = arg3
	end
	if CurrentAmmo.Value > 0 then
		CurrentAmmo.Value -= 1
		
		if WeaponConfig.CLASS ~= "Shotgun" then
			for i = 1, BULLETS_PER_SHOT do
				local simBullet = Fire(clientThatFired,mouseDirection,AssumedVelocity,WeaponConfig.CLASS, shotServerTime, shotOrigin)
				game:GetService("RunService").Heartbeat:Wait()
			end
		else
			if WeaponConfig.CLASS == "Shotgun" then
					PlayFireSound()
			end
			for i = 1, BULLETS_PER_SHOT do
				coroutine.wrap(function()
					local simBullet = Fire(clientThatFired,mouseDirection,AssumedVelocity,WeaponConfig.CLASS, shotServerTime, shotOrigin)
				end)()
			end
		end
		
		
		
			FireDelay = true
		
		local FIRE_RATE = FIRE_DELAY
		if table.find(GP.Traits,"Manic") then
			FIRE_RATE *= (1/1.25)
		end
		
			wait(FIRE_DELAY)
			
			FireDelay = false
		

	end
	syncExternalAmmoState()
end)



function SpawnMag(mag, drop, reappear)
	wait(drop)
		local PhysicsService = game:GetService("PhysicsService")
		local fakeMag = mag:Clone()
		fakeMag.Parent = workspace.Ignore.Mag
		fakeMag.CanCollide = true
		fakeMag.CollisionGroup = "Items"

	
	
	--mag.Transparency = 1
	--wait(reappear)
	--mag.Transparency = 0
end

local function clearReloadState()
	RELOADING = false
	if ReloadTrack then
		pcall(function()
			ReloadTrack:Stop()
		end)
	end
end

ReloadEvent.OnServerEvent:Connect(function(Player)
	if Equipped == false then
		clearReloadState()
		return
	end

	local activeGP = _G.Players and _G.Players[Player.UserId]
	if not activeGP or not activeGP.PlayerData or activeGP.PlayerData.CanReload.Value ~= "true" then
		clearReloadState()
		return
	end

	local magSize = WeaponConfig.MAG_SIZE
	local reloadTime = WeaponConfig.RELOAD_TIME
	RELOADING = true

	if WeaponConfig.CLASS ~= "Shotgun" then
		if ReserveAmmo.Value <= 0 or CurrentAmmo.Value >= magSize then
			clearReloadState()
			return
		end

		if ReloadTrack then
			ReloadTrack:Play()
		end
		local x = coroutine.create(SpawnMag)
		if IsDual then
			coroutine.resume(x,Model2.Mag2,WeaponConfig.MAG_DROP_TIME,WeaponConfig.MAG_REAPPEAR_TIME)
		else
			coroutine.resume(x,Model.Mag,WeaponConfig.MAG_DROP_TIME,WeaponConfig.MAG_REAPPEAR_TIME)
		end
		for _ = reloadTime/10, reloadTime, reloadTime/10 do
			if not RELOADING or not Equipped then
				clearReloadState()
				return
			end
			task.wait(reloadTime/10)
		end

		if RELOADING and ReserveAmmo.Value > 0 and Equipped then
			local ammoToUse = math.min(magSize - CurrentAmmo.Value, ReserveAmmo.Value)
			CurrentAmmo.Value += ammoToUse
			ReserveAmmo.Value -= ammoToUse
			ReloadEvent:FireClient(Player,ReserveAmmo.Value)
			syncExternalAmmoState()
		end
		clearReloadState()
		return
	end

	if ReserveAmmo.Value <= 0 then
		clearReloadState()
		return
	end
	if ReloadTrack then
		ReloadTrack:Play()
	end
	while CurrentAmmo.Value < magSize do
		if ReserveAmmo.Value <= 0 or SHOTGUNCANCELRELOAD == true or not Equipped then
			clearReloadState()
			return
		end
		task.wait(reloadTime)
		CurrentAmmo.Value += 1
		ReserveAmmo.Value -= 1
		ReloadEvent:FireClient(Player,ReserveAmmo.Value)
		syncExternalAmmoState()
	end
	clearReloadState()
end)

local freezeValueObject = ReplicatedStorage:FindFirstChild("GameObjects")
	and ReplicatedStorage.GameObjects:FindFirstChild("FreezeTime")
local pendingWalkSpeedOnUnfreeze = nil

local function parseFreezeState(value)
	if type(value) == "boolean" then
		return value
	end
	local normalized = string.lower(tostring(value or ""))
	return normalized == "true" or normalized == "1"
end

local function isFreezeTimeActive()
	return freezeValueObject and parseFreezeState(freezeValueObject.Value) or false
end

local function stopCharacterMotion(character)
	if not (character and character:IsA("Model")) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.zero, true)
		humanoid.Jump = false
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		hrp.Velocity = Vector3.zero
		hrp.RotVelocity = Vector3.zero
	end
end

if freezeValueObject then
	freezeValueObject:GetPropertyChangedSignal("Value"):Connect(function()
		if isFreezeTimeActive() then
			clearReloadState()
			stopCharacterMotion(Tool.Parent)
			return
		end

		if pendingWalkSpeedOnUnfreeze and Equipped and PlayerOBJ then
			PlayerOBJ:SetWalkSpeed(pendingWalkSpeedOnUnfreeze)
			pendingWalkSpeedOnUnfreeze = nil
		end
	end)
end
local Adjusting = false
local SuppressorOn = true
local function WaitForSuppressorSwap(GPlayer)
	local DoneTick = tick() + 1
	while tick() < DoneTick do
		if not Equipped then
			Adjusting = false
			GPlayer:SetValue("CanUse",true)
			return false
		end
		if FireDelay then
			Adjusting = false
			GPlayer:SetValue("CanUse",true)
			return false
		end
		task.wait()
	end
	return true
end

local function SetSuppressorState(isSuppressed)
	local WeaponConfig1 = ResolveWeaponConfig(WeaponConfig)
	if isSuppressed then
		local Original = require(Tool:WaitForChild("WeaponConfig"))
		WeaponConfig1.MAX_BASESPREAD = Original.MAX_BASESPREAD
		WeaponConfig1.FIRE_RATE *= Original.FIRE_RATE
		WeaponConfig1.FLASHENABLED = Original.FLASHENABLED
		SoundFolder.Fire.SoundId = "rbxassetid://"..WeaponConfig.SILENCEDID
		SoundFolder.Fire.RollOffMaxDistance = WeaponConfig.SILENCEDRANGE
		Tool.WeaponModel[WeaponConfig.SILENCERNAME].Transparency = 0
	else
		WeaponConfig1.MAX_BASESPREAD *= 1.1
		WeaponConfig1.FIRE_RATE *= 1/1.2
		WeaponConfig1.FLASHENABLED = true
		SoundFolder.Fire.SoundId = "rbxassetid://"..WeaponConfig.UNSILENCEDID
		SoundFolder.Fire.RollOffMaxDistance = WeaponConfig.UNSILENCEDRANGE
		Tool.WeaponModel[WeaponConfig.SILENCERNAME].Transparency = 1
	end
end

SilencerEvent.OnServerEvent:Connect(function(Player)
	if Equipped == false then return end
	if Adjusting then return end
	
	if GP.PlayerData.CanUse.Value == "true" and WeaponConfig.REMOVABLESUPPRESSOR == true and not FireDelay then
		local GPlayer = _G.Players[Player.UserId]
		if SuppressorOn then
			Adjusting = true
			GPlayer:SetValue("CanUse",false)
			if not WaitForSuppressorSwap(GPlayer) then return end
			SuppressorOn = false
			SetSuppressorState(false)
			GPlayer:SetValue("CanUse",true)
		else
			Adjusting = true
			GPlayer:SetValue("CanUse",false)
			if not WaitForSuppressorSwap(GPlayer) then return end
			SuppressorOn = true
			SetSuppressorState(true)
			GPlayer:SetValue("CanUse",true)
		end
	
		
		TrackEquip:Play()
		
		
	
		
		
		
		Adjusting = false
		
		
		
	end
end)


Caster.RayHit:Connect(OnRayHit)
Caster.RayPierced:Connect(OnRayPierced)
Caster.LengthChanged:Connect(OnRayUpdated)
Caster.CastTerminating:Connect(OnRayTerminated)
Caster.TracerAdded:Connect(TracerAdded)


ItemID = script.Parent:FindFirstChild("ItemID")

repeat wait(0.01) until ItemID.Value ~= ""

ItemID = ItemID.Value

GTool = _G.Items[ItemID]
local RWC = require(script.Parent.WeaponConfig)
GTool.Init = function()
	--if _G.Items[ItemID].CurrentTool ~= Tool then return end
	SHOTGUNCANCELRELOAD = false
	Tool:WaitForChild("WeaponConfig")
	WeaponConfig = ResolveWeaponConfig(WeaponConfig)
	
	EQUIP_TIME = WeaponConfig.EQUIP_TIME or EQUIP_TIME
	
	repeat wait() until Tool.Parent:IsA("Model")
	local Character = Tool.Parent
	local Humanoid = Character:WaitForChild("Humanoid")
	
	local IsBot = Character:FindFirstChild("IsBot")
	coroutine.wrap(function()
		local defaultSpeed = tonumber(ReplicatedStorage.GameObjects and ReplicatedStorage.GameObjects:FindFirstChild("MaxSpeed") and ReplicatedStorage.GameObjects.MaxSpeed.Value) or 21
		WalkSpeed = tonumber(WeaponConfig.WALKSPEED) or tonumber(WalkSpeed) or defaultSpeed
		
		if not IsBot then
			Player =  game.Players:WaitForChild(Character.Name)
			PlayerOBJ = _G.Players[Player.UserId]	
		else
			PlayerOBJ = _G.Players[Character.Name]	
		end

		if isFreezeTimeActive() then
			pendingWalkSpeedOnUnfreeze = WalkSpeed
			stopCharacterMotion(Character)
		elseif PlayerOBJ then
			PlayerOBJ:SetWalkSpeed(WalkSpeed)
			pendingWalkSpeedOnUnfreeze = nil
		end
	end)()
	

	
	local IGList = {}

	for i,v in next, workspace:GetDescendants() do
		if v:IsA("Accessory") then
			table.insert(IGList,v)
		end
	end


	for i,v in next, workspace:GetDescendants() do
		if v.Name == "LeftGlove" or v.Name == "RightGlove" then
			table.insert(IGList,v)
		end
	end

	table.insert(IGList,CosmeticBulletsFolder)
	table.insert(IGList,Tool.Parent)
	if workspace:FindFirstChild("Ignore") then
		for _, ignoreChild in ipairs(workspace.Ignore:GetChildren()) do
			if ignoreChild.Name ~= "Ghosts" then
				table.insert(IGList, ignoreChild)
			end
		end
	end


	CastParams.FilterDescendantsInstances = IGList
	

	TrackIdle = Character.Humanoid:LoadAnimation(AnimConfig.SV_IDLE)
	TrackEquip = Character.Humanoid:LoadAnimation(AnimConfig.SV_EQUIP)
	ReloadTrack = Character.Humanoid:LoadAnimation(AnimConfig.SV_RELOAD)
	FireTrack = Character.Humanoid:LoadAnimation(AnimConfig.SV_ATTACK)
	FireTrack.Looped = false
	if IsDual then
		FireTrack2 = Character.Humanoid:LoadAnimation(AnimConfig.SV_ATTACK2)
		FireTrack2.Looped = false
	end

	TrackIdle.Looped = true


	local Team = PlayerOBJ.Team.Name

	local Tag = MainPart:WaitForChild("Skin")
	local OTag = MainPart:WaitForChild("Owner")
	if OTag.Value == "" then
		OTag.Value = PlayerOBJ.PlayerName
	end
	if Tag.Value == "" then
		local Skin
		if Team ~= "Spectator" then
			Skin = PlayerOBJ.SavedData[PlayerOBJ.Team.Name .. "Loadout"][Tool.Name] 
		end
		
		if Skin ~= nil and Skin ~= "Stock" then
			
				ContainerService.ApplySkin(Model,Tool.Name,Skin)
				if IsDual then
					ContainerService.ApplySkin(Model2,Tool.Name,Skin)
				end
		
			
		end

		Tag.Value = Skin or "Stock"

	end
	
	for c,d in pairs(Model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
		end
	end
	if IsDual then
		for _, part in ipairs(Model2:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.CanCollide = false
				local tag = part:FindFirstChild("TransparencyTag")
				part.Transparency = (tag and tag.Value) or 0
			end
		end
	end

	Equipping = true
	Grip = Character["RightLowerArm"]:WaitForChild("RightGrip",50)
	
	Model.Parent = Character
	if RWC.SC0 then
		Grip.C0  = RWC.SC0
	end
	if RWC.SC1 then
		Grip.C1 = RWC.SC1
	end
	
	for _, v in pairs(Model:GetDescendants()) do
		if v:IsA("BasePart") then
			local tag = v:FindFirstChild("TransparencyTag")
			v.Transparency = (tag and tag.Value) or 0
		end
	end

	Grip.Part1 = MainPart
	TrackEquip.Priority = Enum.AnimationPriority.Action
	TrackEquip:Play(0)
	
	if IsDual then
		Model2.Parent = Character
		Grip2 = Character["LeftLowerArm"]:WaitForChild("LeftGrip",50)
		Grip2.Part1 = MainPart2
	end


	for i = EQUIP_TIME, EQUIP_TIME * 10 do
		if Tool.Parent ~= Character then
			Equipping = false
			break
		end
		task.wait(EQUIP_TIME / 10)
	end

	if Equipping then
		Equipped = true
		IsEquippedValue.Value = Equipped
		CanFire = true
		TrackIdle.Priority = Enum.AnimationPriority.Action
		TrackIdle:Play(0)

	end
end
GTool.Uninit = function()
	Equipped = false
	IsEquippedValue.Value = Equipped
	Equipping = false
	CanFire = false
	pendingWalkSpeedOnUnfreeze = nil
	clearReloadState()
	local Player = Tool.Parent.Parent

	if TrackEquip then
		TrackEquip:Stop()
	end
	if TrackIdle then
		TrackIdle:Stop()
	end
	
	if Grip then
		Grip.Part1 = nil
		Grip.C1 = CFrame.new()
		Grip.C0 = CFrame.new()
	end
	if Grip2 then
		Grip2.Part1 = nil
		Grip2.C1 = CFrame.new()
		Grip2.C0 = CFrame.new()
	end
	
	
	if WeaponConfig.SCOPEENABLED == true and Player:IsA("Player") then
		AimEvent:FireClient(Player,false)
	end
	if game.ReplicatedStorage.ReferenceModels:FindFirstChild(ItemID) then
		Model.Parent = game.ReplicatedStorage.ReferenceModels[ItemID]
		Model:Destroy()
		if Model2 then
			Model2.Parent = game.ReplicatedStorage.ReferenceModels[ItemID]
			Model2:Destroy()
		end
	end
	
end
