local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local Tool = script.Parent
local Events = Tool:WaitForChild("Events")
local MouseEvent = Events:WaitForChild("MouseEvent")
local PlantBindable = Events:WaitForChild("Plant")

local Framework = require(ReplicatedStorage.Modules.Framework)

local RawWeaponConfig = require(Tool:WaitForChild("WeaponConfig"))
local WeaponConfig = RawWeaponConfig
local AnimConfig = ReplicatedFirst.Assets.Animations:WaitForChild(Tool.Name)
local Model = Tool:WaitForChild("UHE-4")
local MainPart = Model:WaitForChild("Main")
local GameObjects = ReplicatedStorage:WaitForChild("GameObjects")
local FreezeTime = GameObjects:WaitForChild("FreezeTime")

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

local state = {
	equipped = false,
	equipping = false,
	canAttack = false,
	planting = false,
	moveLockedByPlant = false,
	planted = false,
	consumed = false,
	plantToken = 0,
	currentSite = nil,
	player = nil,
	playerObj = nil,
	character = nil,
	grip = nil,
	siteConn = nil,
	animEquip = nil,
	animIdle = nil,
	animPlant = nil,
	hiddenBackParts = {},
}

local PLANT_DURATION = 2.33
local PLANT_STEPS = 50
local DEFAULT_PLANTABLE_PHASES = {
	live = true,
}

local cachedDefusalConfig = nil
local cachedDefusalConfigResolved = false

local function toPhaseKey(phaseName)
	if type(phaseName) ~= "string" then
		return nil
	end
	local trimmed = string.gsub(phaseName, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		return nil
	end
	return string.lower(trimmed)
end

local function parsePhaseFromStatus(statusText)
	local lowered = toPhaseKey(statusText)
	if not lowered then
		return nil
	end

	if string.find(lowered, "warmup", 1, true) then
		return "Warmup"
	end
	if string.find(lowered, "buy", 1, true) then
		return "Buy"
	end
	if string.find(lowered, "freeze", 1, true) then
		return "Freeze"
	end
	if string.find(lowered, "post", 1, true) or string.find(lowered, "intermission", 1, true) then
		return "Post"
	end
	if string.find(lowered, "live", 1, true) then
		return "Live"
	end
	return nil
end

local function resolveConfiguredPhaseSet(configuredPhases)
	if type(configuredPhases) ~= "table" then
		return nil
	end

	local resolved = {}
	local found = false
	for key, value in pairs(configuredPhases) do
		if type(key) == "number" then
			local phaseKey = toPhaseKey(value)
			if phaseKey then
				resolved[phaseKey] = true
				found = true
			end
		elseif value == true then
			local phaseKey = toPhaseKey(key)
			if phaseKey then
				resolved[phaseKey] = true
				found = true
			end
		end
	end

	if found then
		return resolved
	end
	return nil
end

local function readPlantablePhasesFromConfig(config)
	local objectiveConfig = config and config.Objective
	if type(objectiveConfig) ~= "table" then
		return nil
	end

	local directSet = resolveConfiguredPhaseSet(objectiveConfig.PlantablePhases)
	if directSet then
		return directSet
	end

	local actions = objectiveConfig.Actions
	if type(actions) ~= "table" then
		return nil
	end
	for _, actionRule in ipairs(actions) do
		if type(actionRule) == "table" and toPhaseKey(actionRule.Action) == "plant" then
			local actionSet = resolveConfiguredPhaseSet(actionRule.AllowedPhases)
			if actionSet then
				return actionSet
			end
		end
	end
	return nil
end

local function tryResolveDefusalConfig()
	if cachedDefusalConfigResolved then
		return cachedDefusalConfig
	end
	cachedDefusalConfigResolved = true

	local ok, result = pcall(function()
		local gameTypes = ServerScriptService:WaitForChild("GameTypes", 2)
		local fps = gameTypes and gameTypes:FindFirstChild("FPS")
		local gamemodes = fps and fps:FindFirstChild("Gamemodes")
		local defusal = gamemodes and gamemodes:FindFirstChild("Defusal")
		local moduleScript = defusal and defusal:FindFirstChild("DefusalConfig")
		if not moduleScript then
			return nil
		end
		return require(moduleScript)
	end)
	if ok then
		cachedDefusalConfig = result
	end

	return cachedDefusalConfig
end

local function getCurrentModeConfigAndPhase()
	local gameService = Framework.GetService("GameService")
	if not gameService then
		return nil, nil
	end

	local mode = gameService._currentMode
	local modeCtx = mode and mode._ctx
	local modeConfig = modeCtx and modeCtx.config
	local phase = modeCtx and modeCtx.state and modeCtx.state.phase

	return modeConfig, phase
end

local function getPlantablePhaseSet()
	local modeConfig = getCurrentModeConfigAndPhase()
	local fromMode = readPlantablePhasesFromConfig(modeConfig)
	if fromMode then
		return fromMode
	end

	local fallbackConfig = tryResolveDefusalConfig()
	local fromFallback = readPlantablePhasesFromConfig(fallbackConfig)
	if fromFallback then
		return fromFallback
	end

	return DEFAULT_PLANTABLE_PHASES
end

local function getCurrentPhaseName()
	local _, phaseFromMode = getCurrentModeConfigAndPhase()
	if type(phaseFromMode) == "string" and phaseFromMode ~= "" then
		return phaseFromMode
	end

	if FreezeTime.Value == true then
		return "Freeze"
	end

	local statusValue = GameObjects:FindFirstChild("Status")
	local statusText = statusValue and tostring(statusValue.Value) or ""
	local parsedPhase = parsePhaseFromStatus(statusText)
	if parsedPhase then
		return parsedPhase
	end

	return "Live"
end

local function isPlantablePhase()
	local phaseSet = getPlantablePhaseSet()
	local currentPhaseKey = toPhaseKey(getCurrentPhaseName())
	return currentPhaseKey ~= nil and phaseSet[currentPhaseKey] == true
end

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

local function getMaxSpeed()
	local maxSpeed = ReplicatedStorage:FindFirstChild("GameObjects")
	and ReplicatedStorage.GameObjects:FindFirstChild("MaxSpeed")
	if maxSpeed then
		return tonumber(maxSpeed.Value) or 21
	end
	return 21
end

local function stopTrack(track)
	if track then
		track:Stop()
	end
end

local function stopPlantingAudio()
	if MainPart:FindFirstChild("Planting") then
		MainPart.Planting:Stop()
	end
end

local function playPlantingAudio()
	if MainPart:FindFirstChild("Planting") then
		MainPart.Planting:Play()
	end
end

local function setCanMove(playerObj, character, canMove)
	if playerObj then
		playerObj:SetValue("CanMove", canMove)
	end
	if character and character:FindFirstChild("Humanoid") then
		if canMove then
			local targetSpeed = (playerObj and tonumber(playerObj.Speed)) or getMaxSpeed()
			character.Humanoid.WalkSpeed = targetSpeed
		else
			character.Humanoid.WalkSpeed = 0
		end
	end
end

local function hideBackAccessory(playerObj)
	if not playerObj or not playerObj.CharacterObject then
		return
	end
	local back = playerObj.CharacterObject:FindFirstChild("Back1")
	if not back then
		return
	end
	for _, desc in ipairs(back:GetDescendants()) do
		if desc:IsA("BasePart") then
			if state.hiddenBackParts[desc] == nil then
				state.hiddenBackParts[desc] = desc.Transparency
			end
			desc.Transparency = 1
		end
	end
end

local function showBackAccessory(playerObj)
	if not playerObj then
		return
	end
	for part, original in pairs(state.hiddenBackParts) do
		if part and part.Parent then
			part.Transparency = original
		end
	end
	table.clear(state.hiddenBackParts)
end

local function resolveActor(actor)
	local actorPlayer = nil
	local actorPlayerObj = nil
	local actorCharacter = nil
	local actorUserId = nil

	if typeof(actor) == "Instance" and actor:IsA("Player") then
		actorPlayer = actor
		actorUserId = actor.UserId
		actorPlayerObj = _G.Players[actorUserId]
		actorCharacter = actor.Character
	elseif type(actor) == "table" then
		actorUserId = actor.UserId
		if actorUserId ~= nil then
			actorPlayerObj = _G.Players[actorUserId]
			actorPlayer = Players:GetPlayerByUserId(actorUserId)
		end
		actorCharacter = actor.Character or (actorPlayerObj and actorPlayerObj.CharacterObject)
	end

	if not actorCharacter and actorPlayerObj then
		actorCharacter = actorPlayerObj.CharacterObject
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
		team = actorPlayerObj and actorPlayerObj.Team,
	}
end

local function isAttacker(actorInfo)
	local aTeamValue = ReplicatedStorage:FindFirstChild("GameObjects")
		and ReplicatedStorage.GameObjects:FindFirstChild("ATeam")
	if not aTeamValue or not actorInfo.team then
		return false
	end
	return actorInfo.team.Name == aTeamValue.Value
end

local function updateOnSite(character)
	if not character then
		return
	end
	local cdata = character:FindFirstChild("CDATA")
	if cdata and cdata:FindFirstChild("OnSite") then
		cdata.OnSite.Value = false
	end
end

local function stopSiteCheck()
	if state.siteConn then
		state.siteConn:Disconnect()
		state.siteConn = nil
	end
end

local function startSiteCheck(character, playerObj)
	stopSiteCheck()
	if not character or not playerObj then
		return
	end

	local cdata = character:FindFirstChild("CDATA")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not cdata or not cdata:FindFirstChild("OnSite") or not hrp then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace.Ignore, workspace.Camera, playerObj.CharacterObject }

	state.siteConn = RunService.Heartbeat:Connect(function()
		if not state.equipped then
			return
		end
		if not character.Parent then
			return
		end

		local cast = workspace:Raycast(hrp.Position, Vector3.new(0, -16.5, 0), params)
		if cast and ReplicatedStorage.GameObjects:FindFirstChild("RoundCode") then
			local roundCode = tostring(ReplicatedStorage.GameObjects.RoundCode.Value)
			if string.find(cast.Instance.Name, roundCode, 1, true) then
				state.currentSite = cast.Instance.Name
				cdata.OnSite.Value = true
				return
			end
		end
		cdata.OnSite.Value = false
	end)
end

local function consumeObjective(actorInfo)
	if state.consumed then
		return
	end
	state.consumed = true

	local ownerObj = actorInfo.playerObj or state.playerObj
	local ownerPlayer = actorInfo.player or state.player
	local consumedItemId = (GTool and GTool.ID) or ItemID
	if ownerObj and consumedItemId then
		if ownerPlayer then
			ReplicatedStorage.Remotes.Server.Inventory.UnequipItem:FireClient(ownerPlayer, consumedItemId, "Consumed")
		end
		ownerObj:RemoveItemFromBackpack(consumedItemId)
		for i = #ownerObj.Backpack, 1, -1 do
			local item = ownerObj.Backpack[i]
			if item and (item.ID == consumedItemId or item.ItemType == "UHE-4" or item.ItemName == "UHE-4") then
				ownerObj:RemoveItemFromBackpack(item.ID)
				if item.Destroy and item ~= GTool then
					item:Destroy()
				end
			end
		end
	end
	if GTool then
		GTool:Destroy()
	end
end

local function emitPlantToDefusalFlow(actorInfo)
	local gameService = Framework.GetService("GameService")
	if gameService and gameService.EmitModeEvent then
		gameService:EmitModeEvent("BombPlantAttempt", {
			userId = actorInfo.userId,
			gp = actorInfo.playerObj,
			raw = actorInfo.raw,
			source = "UHEServer",
		})
	end

	local eventsFolder = game.ServerStorage:FindFirstChild("Events")
	local plantedEvent = eventsFolder and eventsFolder:FindFirstChild("BombPlanted")
	if plantedEvent and plantedEvent:IsA("BindableEvent") then
		plantedEvent:Fire(actorInfo.userId)
	end
end

local function findPlantedServerTemplate()
	local itemServers = ServerStorage:FindFirstChild("ItemServers")
	if not itemServers then
		return nil
	end
	return itemServers:FindFirstChild("PlantedUHEServer")
		or itemServers:FindFirstChild("PlantedUHEServer.server")
end

local function ensurePlantedFolder()
	local ignoreFolder = workspace:FindFirstChild("Ignore")
	if not ignoreFolder then
		warn("UHEServer: Missing workspace.Ignore; cannot place planted UHE-4.")
		return nil
	end

	local plantedFolder = ignoreFolder:FindFirstChild("UHE-4")
	if not plantedFolder then
		plantedFolder = Instance.new("Folder")
		plantedFolder.Name = "UHE-4"
		plantedFolder.Parent = ignoreFolder
	end

	return plantedFolder
end

local function ensurePlantedServer(plantedModel)
	if not plantedModel then
		return
	end

	local plantedMain = plantedModel:FindFirstChild("Main", true)
	if not plantedMain or not plantedMain:IsA("BasePart") then
		return
	end

	local existing = plantedMain:FindFirstChild("Script")
	if existing and existing:IsA("Script") then
		existing.Disabled = false
		return
	end

	local template = findPlantedServerTemplate()
	if not template or not template:IsA("Script") then
		warn("UHEServer: Could not find PlantedUHEServer template in ServerStorage.ItemServers.")
		return
	end

	local clone = template:Clone()
	clone.Name = "Script"
	clone.Disabled = false
	clone.Parent = plantedMain
end

local function placePlantedModel(model, plantedFrom)
	if not model or not plantedFrom then
		return
	end

	local targetCFrame = plantedFrom * CFrame.new(0, -2.5, 0.2) * CFrame.Angles(math.rad(-90), 0, 0)
	local ok = pcall(function()
		if model:IsA("Model") then
			if model.PrimaryPart then
				model:SetPrimaryPartCFrame(targetCFrame)
			else
				model:PivotTo(targetCFrame)
			end
		end
	end)

	if not ok then
		warn("UHEServer: Failed to position planted UHE-4 model.")
	end
end

local function firePlantedModelEvent(model, actorRaw)
	if not model then
		return false
	end

	-- Prefer the trigger that belongs to the runtime planted script.
	local plantedMain = model:FindFirstChild("Main", true)
	local serverScript = plantedMain and plantedMain:FindFirstChild("Script")
	local plantedTrigger = serverScript and serverScript:FindFirstChild("trole")
	if (not plantedTrigger or not plantedTrigger:IsA("BindableEvent")) then
		plantedTrigger = model:FindFirstChild("trole", true)
	end
	if plantedTrigger and plantedTrigger:IsA("BindableEvent") then
		plantedTrigger:Fire(actorRaw, "Planting")
		return true
	end
	return false
end

local function finalizePlant(actorInfo, plantedFrom)
	state.planted = true
	state.planting = false
	state.plantToken += 1

	stopTrack(state.animIdle)
	stopTrack(state.animPlant)
	stopPlantingAudio()

	local plantedFolder = ensurePlantedFolder()
	local plantedModel = nil
	if plantedFolder then
		local objectiveRepo = ServerStorage:FindFirstChild("WeaponRepository")
			and ServerStorage.WeaponRepository:FindFirstChild("Objective")
		local objectiveModel = objectiveRepo and objectiveRepo:FindFirstChild("UHE-4")
		if not objectiveModel then
			warn("UHEServer: Missing ServerStorage.WeaponRepository.Objective.UHE-4, falling back to ReplicatedFirst.Assets.Models.UHE-4")
			objectiveModel = ReplicatedFirst.Assets.Models:FindFirstChild("UHE-4")
		end
		if objectiveModel then
			local clone = objectiveModel:Clone()
			clone.Parent = plantedFolder
			placePlantedModel(clone, plantedFrom)
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			ensurePlantedServer(clone)
			plantedModel = clone
		else
			warn("UHEServer: Unable to resolve planted UHE-4 model.")
		end
	end

	if plantedModel and not firePlantedModelEvent(plantedModel, actorInfo.raw) then
		task.spawn(function()
			local timeoutAt = os.clock() + 2
			repeat
				task.wait(0.1)
				if firePlantedModelEvent(plantedModel, actorInfo.raw) then
					return
				end
			until os.clock() >= timeoutAt
			warn("UHEServer: Timed out waiting for planted UHE-4 trigger.")
		end)
	end
	emitPlantToDefusalFlow(actorInfo)

	if state.currentSite and _G.TellBombPlanted then
		local split = string.split(state.currentSite, ":")
		_G.TellBombPlanted(split[2])
	end

	setCanMove(actorInfo.playerObj, actorInfo.character, true)
	state.moveLockedByPlant = false

	consumeObjective(actorInfo)
	if actorInfo.player then
		task.delay(0.05, function()
			ReplicatedStorage.Remotes.Server.ForceEquip:FireClient(actorInfo.player)
		end)
	end
	task.defer(function()
		if Tool and Tool.Parent then
			Tool:Destroy()
		end
	end)
end

local function cancelPlant(actorInfo)
	local hadPlantLock = state.moveLockedByPlant == true
	state.planting = false
	state.plantToken += 1
	stopTrack(state.animPlant)
	stopPlantingAudio()
	if state.equipped then
		if state.animIdle and not state.animIdle.IsPlaying then
			state.animIdle:Play(0)
		end
	end
	if actorInfo and hadPlantLock then
		setCanMove(actorInfo.playerObj, actorInfo.character, true)
	end
	state.moveLockedByPlant = false
end

local function canStartPlant(actorInfo)
	if not actorInfo or not actorInfo.character then
		return false
	end
	if not isPlantablePhase() then
		return false
	end
	if not state.equipped or not state.canAttack or state.planted then
		return false
	end
	if not isAttacker(actorInfo) then
		return false
	end
	local cdata = actorInfo.character:FindFirstChild("CDATA")
	if not cdata or not cdata:FindFirstChild("OnSite") then
		return false
	end
	return cdata.OnSite.Value == true
end

local function startPlant(actorInfo)
	if state.planting then
		return
	end
	if not canStartPlant(actorInfo) then
		return
	end

	state.planting = true
	state.plantToken += 1
	local token = state.plantToken

	state.moveLockedByPlant = true
	setCanMove(actorInfo.playerObj, actorInfo.character, false)
	stopTrack(state.animIdle)

	if state.animPlant then
		state.animPlant:Play(0)
	end
	playPlantingAudio()

	local hrp = actorInfo.character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		cancelPlant(actorInfo)
		return
	end
	local plantedFrom = hrp.CFrame

	task.spawn(function()
		for _ = 1, PLANT_STEPS do
			if token ~= state.plantToken then
				return
			end
			if not state.equipped then
				cancelPlant(actorInfo)
				return
			end
			if not canStartPlant(actorInfo) then
				cancelPlant(actorInfo)
				return
			end
			task.wait(PLANT_DURATION / PLANT_STEPS)
		end

		if token ~= state.plantToken then
			return
		end
		finalizePlant(actorInfo, plantedFrom)
	end)
end

local function handlePlantEvent(actor, key)
	local actorInfo = resolveActor(actor)
	if not actorInfo.playerObj or not actorInfo.character then
		return
	end

	if key == "Ended" then
		cancelPlant(actorInfo)
		return
	end

	if key == nil then
		key = "Started"
	end

	if key == "Started" then
		startPlant(actorInfo)
	end
end

MouseEvent.OnServerEvent:Connect(function(player, key)
	handlePlantEvent(player, key)
end)

PlantBindable.Event:Connect(function(actor, key)
	handlePlantEvent(actor, key)
end)

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
	state.animPlant = humanoid:LoadAnimation(AnimConfig.SV_PLANT)
	state.animPlant.Priority = Enum.AnimationPriority.Action
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
		player = Players:FindFirstChild(character.Name)
		if player then
			playerObj = _G.Players[player.UserId]
		end
	else
		playerObj = _G.Players[character.Name]
	end

	state.player = player
	state.playerObj = playerObj
	state.character = character
	state.currentSite = nil
	state.planted = false
	state.consumed = false
	state.planting = false
	state.moveLockedByPlant = false
	state.canAttack = false
	state.equipped = false
	state.equipping = true
	IsEquippedValue.Value = false

	local defaultSpeed = tonumber(ReplicatedStorage.GameObjects and ReplicatedStorage.GameObjects:FindFirstChild("MaxSpeed") and ReplicatedStorage.GameObjects.MaxSpeed.Value) or 21
	local equipSpeed = tonumber(WalkSpeed) or tonumber(defaultSpeed)
	if playerObj and equipSpeed then
		playerObj:SetWalkSpeed(equipSpeed)
	end

	showBackAccessory(playerObj)
	if character:FindFirstChild("Objective") then
		character.Objective:Destroy()
	end

	mountModel(character)
	loadAnimations(character)

	local rightLowerArm = character:FindFirstChild("RightLowerArm")
	if rightLowerArm then
		state.grip = rightLowerArm:FindFirstChild("RightGrip")
	end
	if state.grip then
		state.grip.Part1 = MainPart
	end

	if MainPart:FindFirstChild("Deploy") then
		MainPart.Deploy:Play()
	end

	startSiteCheck(character, playerObj)

	if state.animEquip then
		state.animEquip.Priority = Enum.AnimationPriority.Action
		state.animEquip:Play(0.1)
	end

	for _ = EquipTime, EquipTime * 10 do
		if Tool.Parent ~= character then
			state.equipping = false
			break
		end
		task.wait(EquipTime / 10)
	end

	if state.equipping then
		state.equipped = true
		IsEquippedValue.Value = true
		state.canAttack = true
		if state.animIdle then
			state.animIdle:Play(0)
		end
	end
end


GTool.Uninit = function()
	local playerObj = state.playerObj
	IsEquippedValue.Value = false

	cancelPlant({ playerObj = playerObj, character = state.character })
	stopSiteCheck()
	updateOnSite(state.character)

	state.equipped = false
	state.equipping = false
	state.canAttack = false

	stopTrack(state.animEquip)
	stopTrack(state.animIdle)
	stopTrack(state.animPlant)

	if state.grip then
		state.grip.Part1 = nil
	end

	if playerObj then
		local currentItem = _G.Items[ItemID]
		if Tool.Parent ~= playerObj.CharacterObject and currentItem and table.find(playerObj.Backpack, currentItem) then
			hideBackAccessory(playerObj)
			ReplicatedFirst.Assets.Models.Objective:Clone().Parent = playerObj.CharacterObject
		end
	end

	if ReplicatedStorage.ReferenceModels:FindFirstChild(ItemID) then
		Model.Parent = ReplicatedStorage.ReferenceModels[ItemID]
		Model:Destroy()
	else
		Model.Parent = nil
	end
end
