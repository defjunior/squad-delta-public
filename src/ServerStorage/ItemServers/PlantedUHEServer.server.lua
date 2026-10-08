local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WeaponRepository = ServerStorage:FindFirstChild("WeaponRepository")
local ObjectiveAssetRepository = (WeaponRepository and WeaponRepository:FindFirstChild("UHE-4"))
	or (WeaponRepository and WeaponRepository:FindFirstChild("Objective") and WeaponRepository.Objective:FindFirstChild("UHE-4"))

local function ensureScriptAsset(assetName, className)
	local existing = script:FindFirstChild(assetName)
	if existing then
		if not className or existing.ClassName == className then
			return existing
		end
	end

	local repositoryAsset = ObjectiveAssetRepository and ObjectiveAssetRepository:FindFirstChild(assetName)
	if repositoryAsset and (not className or repositoryAsset.ClassName == className) then
		local clone = repositoryAsset:Clone()
		clone.Parent = script
		return clone
	end

	if className == "BindableEvent" then
		local bindable = Instance.new("BindableEvent")
		bindable.Name = assetName
		bindable.Parent = script
		warn(("PlantedUHEServer: Created fallback BindableEvent '%s'."):format(assetName))
		return bindable
	end

	if className == "ModuleScript" then
		warn(("PlantedUHEServer: Missing ModuleScript '%s'; using default config values."):format(assetName))
		return nil
	end

	error(("PlantedUHEServer is missing required asset '%s' in ServerStorage.WeaponRepository.UHE-4 or ServerStorage.WeaponRepository.Objective.UHE-4"):format(assetName))
end

local Event = ensureScriptAsset("trole", "BindableEvent")
local MainPart = script.Parent
local Sounds = MainPart:WaitForChild("Sounds")
local ConfigModule = ensureScriptAsset("WeaponConfig", "ModuleScript")
local Config = {}
if ConfigModule then
	local ok, loaded = pcall(require, ConfigModule)
	if ok and type(loaded) == "table" then
		Config = loaded
	end
end
if type(Config) ~= "table" then
	Config = {}
end
Config.EXPLOSION_TIME = tonumber(Config.EXPLOSION_TIME) or 45
Config.RANGE = tonumber(Config.RANGE) or 75
Config.DAMAGE = tonumber(Config.DAMAGE) or 200
local Framework = require(ReplicatedStorage.Modules.Framework)

local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server")
local EventsFolder = ServerStorage:WaitForChild("Events")
local RED_COLOR = Color3.new(1, 0, 0)
local BLU_COLOR = Color3.new(0, 0, 1)
local TOOL_NAME = "UHE-4"

local state = {
	planted = false,
	defused = false,
	detonated = false,
	defuserCaptured = false,
	activeDefuser = nil,
	activeDefuserInfo = nil,
	teamThatPlanted = nil,
	planter = nil,
	beeping = false,
}

local function canDefuse(actorInfo)
	if not actorInfo or not actorInfo.character then
		return false
	end

	local gameObjects = ReplicatedStorage:FindFirstChild("GameObjects")
	local defendersValue = gameObjects and gameObjects:FindFirstChild("DTeam")
	local defenderTeamName = defendersValue and defendersValue.Value
	local actorTeam = actorInfo.playerObj and actorInfo.playerObj.Team or (actorInfo.player and actorInfo.player.Team)
	if defenderTeamName and actorTeam and actorTeam.Name ~= defenderTeamName then
		return false
	end

	local hrp = actorInfo.character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end

	return (hrp.Position - MainPart.Position).Magnitude <= 30
end

local function resolveActor(actor)
	local actorPlayer = nil
	local actorPlayerObj = nil
	local actorCharacter = nil
	local actorUserId = nil

	if typeof(actor) == "Instance" and actor:IsA("Player") then
		actorPlayer = actor
		actorUserId = actor.UserId
		actorPlayerObj = _G.Players and _G.Players[actorUserId]
		actorCharacter = actor.Character
	elseif type(actor) == "table" then
		actorUserId = actor.UserId or actor.ID
		if actor.CharacterObject and actor.Team then
			actorPlayerObj = actor
		end
		if actorUserId ~= nil then
			actorPlayerObj = actorPlayerObj or (_G.Players and _G.Players[actorUserId])
			if type(actorUserId) == "number" then
				actorPlayer = Players:GetPlayerByUserId(actorUserId)
			end
		end
		actorCharacter = actor.Character or actor.CharacterObject or (actorPlayerObj and actorPlayerObj.CharacterObject)
	end

	if not actorCharacter and actorPlayerObj then
		actorCharacter = actorPlayerObj.CharacterObject
	end

	if not actorPlayerObj and actorPlayer and actorPlayer.UserId then
		actorPlayerObj = _G.Players and _G.Players[actorPlayer.UserId]
	end

	if not actorUserId and actorPlayerObj then
		actorUserId = actorPlayerObj.ID
	end

	return {
		raw = actor,
		player = actorPlayer,
		playerObj = actorPlayerObj,
		character = actorCharacter,
		userId = actorUserId,
	}
end

local function emitDefuseAttempt(actorInfo)
	local gp = actorInfo and actorInfo.playerObj
	if not gp and actorInfo and actorInfo.userId ~= nil then
		gp = _G.Players and _G.Players[actorInfo.userId]
	end
	local gameService = Framework.GetService("GameService")
	if gameService and gameService.EmitModeEvent then
		return gameService:EmitModeEvent("BombDefuseAttempt", {
			userId = actorInfo and actorInfo.userId,
			gp = gp,
			raw = actorInfo and actorInfo.raw,
			source = "PlantedUHEServer",
		})
	end
	return false
end

local function getPlanterName(planter)
	if not planter then
		return "Unknown"
	end
	return planter.Name or planter.PlayerName  or "Unknown"
end

local function getTeamColor(teamName)
	if teamName == "RED" then
		return RED_COLOR
	end
	return BLU_COLOR
end

local function setLightColor(color)
	local attachment = MainPart:FindFirstChild("Attachment")
	if not attachment then
		return
	end

	local flash = attachment:FindFirstChild("Flash")
	if flash and flash:IsA("ParticleEmitter") then
		flash.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(1, color),
		})
	end

	local shine = attachment:FindFirstChild("Shine")
	if shine and shine:IsA("ParticleEmitter") then
		shine.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(1, color),
		})
	end
end

local function emitBeep()
	if Sounds:FindFirstChild("Beep") then
		Sounds.Beep:Play()
	end
	local attachment = MainPart:FindFirstChild("Attachment")
	local flash = attachment and attachment:FindFirstChild("Flash")
	if flash and flash:IsA("ParticleEmitter") then
		flash:Emit(1)
	end
end

local function createExplosionPulse(range, tweenTime)
	local ignoreFolder = workspace:FindFirstChild("Ignore")
	local pulse = Instance.new("Part")
	pulse.Shape = Enum.PartType.Ball
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CastShadow = false
	pulse.Transparency = 0
	pulse.Material = Enum.Material.Neon
	pulse.Color = getTeamColor(state.teamThatPlanted)
	pulse.CFrame = MainPart.CFrame
	pulse.Size = Vector3.new(1, 1, 1)
	pulse.Parent = ignoreFolder or workspace

	local tween = TweenService:Create(
		pulse,
		TweenInfo.new(tweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Size = Vector3.new(range, range, range) }
	)
	tween:Play()
	Debris:AddItem(pulse, 5)
end

local function applyExplosionDamage(planter, damage, range)
	for _, target in pairs(_G.Players or {}) do
		if target.CharacterObject and target.IsPlaying then
			local hrp = target.CharacterObject:FindFirstChild("HumanoidRootPart")
			if hrp then
				local distance = (MainPart.CFrame.Position - hrp.Position).Magnitude
				if distance <= range then
					local dealtDamage = (distance / range) * damage
					target:TakeDamage(
						dealtDamage,
						("%s:%s:%s"):format(getPlanterName(planter), TOOL_NAME, dealtDamage)
					)

					if target.Health <= 0 then
						local knockback = Instance.new("BodyVelocity")
						knockback.MaxForce = Vector3.new(1e8, 1e8, 1e8)
						knockback.Velocity = (MainPart.CFrame.Position - hrp.Position).Unit * -(dealtDamage / 15)
						knockback.Parent = hrp
						Debris:AddItem(knockback, 0.5)
					end
				end
			end
		end
	end
end

local function detonate()
	if state.detonated then
		return
	end

	state.detonated = true
	state.beeping = false
	if Sounds:FindFirstChild("bruh") then
		Sounds.bruh:Play()
	end
	createExplosionPulse(Config.RANGE, 2.2)
	task.wait(0.15)
	applyExplosionDamage(state.planter, Config.DAMAGE, Config.RANGE)
	EventsFolder.BombDetonated:Fire()
	Debris:AddItem(MainPart.Parent, 5)
end

local function onDefuseComplete(defuser)
	if state.defuserCaptured or state.detonated or not state.planted then
		return false
	end
	local defuserInfo = resolveActor(defuser or state.activeDefuser)
	if (not defuserInfo.playerObj or not defuserInfo.character) and state.activeDefuserInfo then
		defuserInfo = state.activeDefuserInfo
	end
	if not canDefuse(defuserInfo) then
		return false
	end

	state.defuserCaptured = true
	state.defused = true
	state.beeping = false
	state.activeDefuser = nil
	state.activeDefuserInfo = nil
	if Sounds:FindFirstChild("XDDDDDDDDDDDD") then
		Sounds.XDDDDDDDDDDDD.PlaybackSpeed = 1.15 + (math.random(0, 100) / 100)
		Sounds.XDDDDDDDDDDDD:Play()
	end

	local playerId = defuserInfo.userId
	emitDefuseAttempt(defuserInfo)
	EventsFolder.BombDefused:Fire(playerId)
	return true
end

local function getMessageColor(secondsLeft, totalSeconds)
	if secondsLeft >= (totalSeconds * 0.5) then
		local percent = (totalSeconds * 0.5) / math.max(secondsLeft, 1)
		return Color3.new(percent, 1, 0)
	end
	local percent = secondsLeft / 22
	return Color3.new(1, percent, 0)
end

local function runBeepLoop(totalSeconds)
	local startTime = tick()
	local nextBeepAt = tick()
	state.beeping = true

	while state.beeping do
		local now = tick()
		local remainingRatio = (startTime + totalSeconds - now) / totalSeconds
		local clampedRatio = math.clamp(remainingRatio, 0, 1)

		if now >= nextBeepAt then
			emitBeep()
			nextBeepAt = now + 0.01 + clampedRatio
		end
		task.wait()
	end
end

local function startPlantedLoop(planter)
	if state.planted then
		return
	end

	state.planted = true
	state.planter = planter
	state.teamThatPlanted = planter and planter.Team and planter.Team.Name or nil
	state.activeDefuser = nil
	state.activeDefuserInfo = nil

	local defuseTimeValue = MainPart:FindFirstChild("Time")
	local totalSeconds = Config.EXPLOSION_TIME or 45
	local plantedAt = tonumber(workspace.DistributedGameTime)

	if defuseTimeValue then
		defuseTimeValue:GetPropertyChangedSignal("Value"):Connect(function()
			if defuseTimeValue.Value <= 0 then
				onDefuseComplete(state.activeDefuser)
			end
		end)
	end

	setLightColor(getTeamColor(state.teamThatPlanted))
	task.spawn(runBeepLoop, totalSeconds)

	for i = totalSeconds, 0, -1 do
		if state.defused then
			break
		end

		if i == 5 and Sounds:FindFirstChild("EnergyLow") then
			Sounds.EnergyLow:Play()
		end

		Remotes.PersonalSystemMessage:FireAllClients(
			("[UHE-4] %s seconds till detonation."):format(i),
			getMessageColor(i, totalSeconds)
		)

		task.wait(1)

		if plantedAt + totalSeconds < workspace.DistributedGameTime then
			detonate()
			return
		end
	end
end

local function getDefuseFeedbackEvent(character)
	if not character then
		return nil
	end
	local pda = character:FindFirstChild("PDA")
	if not pda then
		return nil
	end
	local events = pda:FindFirstChild("Events")
	local feedback = events and events:FindFirstChild("DefuseFeedback")
	if feedback and feedback:IsA("BindableEvent") then
		return feedback
	end
	return nil
end

local function triggerPdaDefuseFeedback(actor)
	local actorInfo = resolveActor(actor)
	if state.defuserCaptured or state.detonated or not state.planted then
		return false
	end
	if not canDefuse(actorInfo) then
		return false
	end
	state.activeDefuser = actorInfo.player or actorInfo.playerObj or actorInfo.raw
	state.activeDefuserInfo = actorInfo
	local feedbackEvent = getDefuseFeedbackEvent(actorInfo.character)

	if not feedbackEvent and actorInfo.player and Remotes:FindFirstChild("ForceEquip") then
		Remotes.ForceEquip:FireClient(actorInfo.player, "PDA")
		local timeoutAt = tick() + 1.5
		repeat
			task.wait(0.05)
			if actorInfo.player.Character then
				actorInfo.character = actorInfo.player.Character
			end
			feedbackEvent = getDefuseFeedbackEvent(actorInfo.character)
		until feedbackEvent or tick() >= timeoutAt
	end

	if feedbackEvent then
		feedbackEvent:Fire(actorInfo.player or actorInfo.playerObj or actorInfo.raw, MainPart)
		return true
	end
	state.activeDefuser = nil
	state.activeDefuserInfo = nil
	return false
end

do
	local proximityPrompt = MainPart:FindFirstChild("ProximityPrompt")
	if proximityPrompt and proximityPrompt:IsA("ProximityPrompt") then
		proximityPrompt.Triggered:Connect(function(playerThatTriggered)
			task.spawn(function()
				local startedViaPda = triggerPdaDefuseFeedback(playerThatTriggered)
				if not startedViaPda then
					onDefuseComplete(playerThatTriggered)
				end
			end)
		end)
	else
		warn("PlantedUHEServer: Main part missing ProximityPrompt; prompt defuse trigger disabled.")
	end
end

do
	local timeValue = MainPart:FindFirstChild("Time")
	local gameObjects = ReplicatedStorage:FindFirstChild("GameObjects")
	local configuredTime = gameObjects and gameObjects:FindFirstChild("UHEDefuseTime")
	if timeValue and configuredTime then
		timeValue.Value = configuredTime.Value
	end
end

Event.Event:Connect(function(player, action)
	if state.planted and action ~= "Defuse" and action ~= "DefuseAttempt" then
		return
	end

	if action == "Defuse" then
		onDefuseComplete(player)
		return
	end

	if action == "DefuseAttempt" then
		if not triggerPdaDefuseFeedback(player) then
			onDefuseComplete(player)
		end
		return
	end

	startPlantedLoop(player)
end)

-- Fallback: if the external "Planting" signal was missed, still arm this instance.
task.delay(0.35, function()
	if not state.planted and MainPart and MainPart.Parent then
		startPlantedLoop(nil)
	end
end)
