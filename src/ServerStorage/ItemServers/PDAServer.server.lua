--[[Services & Events]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeamService = game:GetService("Teams")
local SoundService = game:GetService("SoundService")
local PlayerService = game:GetService("Players")
local InputService = game:GetService("UserInputService");
local RunService = game:GetService("RunService");


--[[Tables & Instances]]
local Tool = script.Parent;
local WeaponConfig = require(Tool:WaitForChild("WeaponConfig"))	
local AnimConfig = game.ReplicatedFirst.Assets.Animations:WaitForChild(Tool.Name)
local SoundFolder = Tool:WaitForChild("Sounds")
local Model = Tool:WaitForChild("PDA")
local MainPart = Model:WaitForChild("Main")

local EventsFolder = Tool:WaitForChild("Events")
local MouseFunc = EventsFolder:WaitForChild("MouseFunc");
local IsEquippedValue = script:FindFirstChild("IsEquipped")
if not IsEquippedValue or not IsEquippedValue:IsA("BoolValue") then
	if IsEquippedValue then
		IsEquippedValue:Destroy()
	end
	IsEquippedValue = Instance.new("BoolValue")
	IsEquippedValue.Name = "IsEquipped"
	IsEquippedValue.Parent = script
end
--[[ Config Stuff ]]--
local EquipTime = WeaponConfig.EQUIP_TIME 
local WalkSpeed = WeaponConfig.WALKSPEED
--[[ Main Stuff ]]--
--HumanoidRootPart.CFrame*CFrame.new(0,-2.7,-0.2)
local Equipped = false
local Equipping = false
local CanAttack = false
local grip
local GlobalKey = "Ended"
local Time = 0
local HoldE = false
local PlayerOBJ
local Player


local Params = RaycastParams.new()
function Switch(Key)
	if tostring(Key) == "Default" then
		local GUI = MainPart.Screen.SurfaceGui
		GUI.Menu.Visible = true
		GUI.Defuse.Visible = false
	else
		local GUI = MainPart.Screen.SurfaceGui
		GUI.Menu.Visible = false
		GUI.Defuse.Visible = true
	end
end

local function getUHEFolder()
	local ignoreFolder = workspace:FindFirstChild("Ignore")
	if not ignoreFolder then
		return nil
	end

	local uheFolder = ignoreFolder:FindFirstChild("UHE-4")
	if not uheFolder then
		uheFolder = Instance.new("Folder")
		uheFolder.Name = "UHE-4"
		uheFolder.Parent = ignoreFolder
	end

	return uheFolder
end

local function bindUHETimeMeter()
	local uheFolder = getUHEFolder()
	if not uheFolder then
		return
	end

	local function hookActiveUHE()
		local GUI = MainPart.Screen.SurfaceGui
		local UHE = uheFolder:FindFirstChild("UHE-4")
		local main = UHE and UHE:FindFirstChild("Main")
		if not main then
			return
		end

		local Time = main:FindFirstChild("Time") or main:WaitForChild("Time", 2)
		if not Time then
			return
		end

		Time:GetPropertyChangedSignal("Value"):Connect(function()
			pcall(function()
				local Perce = tostring(Time.Value / ReplicatedStorage.GameObjects.UHEDefuseTime.Value)
				local Percen = string.sub(Perce,1,6)
				local Percent = math.clamp(tonumber(Percen) or 0, 0, 1)
				GUI.Defuse.DefuseMeter:TweenSize(UDim2.new(1,0,Percent,0),Enum.EasingDirection.In,Enum.EasingStyle.Sine,0.10)
			end)
		end)
	end

	uheFolder.ChildAdded:Connect(hookActiveUHE)
	hookActiveUHE()
end

bindUHETimeMeter()



local Tickrate = 5
local function invokeMouseClient(targetPlayer, successState, animState)
	if not targetPlayer then
		return false
	end
	local ok, err = pcall(function()
		MouseFunc:InvokeClient(targetPlayer, successState, animState)
	end)
	if not ok then
		warn("PDAServer: Failed to invoke MouseFunc client callback:", err)
		return false
	end
	return true
end

local function resolveDefuseActor(triggeredActor)
	local resolvedPlayer = nil
	local resolvedPlayerObj = nil
	local resolvedCharacter = nil

	if typeof(triggeredActor) == "Instance" and triggeredActor:IsA("Player") then
		resolvedPlayer = triggeredActor
		resolvedPlayerObj = _G.Players and _G.Players[triggeredActor.UserId]
		resolvedCharacter = triggeredActor.Character
	elseif type(triggeredActor) == "table" then
		local userId = triggeredActor.UserId or triggeredActor.ID
		if triggeredActor.CharacterObject and triggeredActor.Team then
			resolvedPlayerObj = triggeredActor
		elseif userId ~= nil then
			resolvedPlayerObj = _G.Players and _G.Players[userId]
		end
		if type(userId) == "number" then
			resolvedPlayer = PlayerService:GetPlayerByUserId(userId)
		end
		resolvedCharacter = triggeredActor.Character or triggeredActor.CharacterObject
	end

	if not resolvedCharacter and resolvedPlayerObj then
		resolvedCharacter = resolvedPlayerObj.CharacterObject
	end
	if not resolvedCharacter and resolvedPlayer then
		resolvedCharacter = resolvedPlayer.Character
	end

	return resolvedPlayer, resolvedPlayerObj, resolvedCharacter
end

Tool.Events.DefuseFeedback.Event:Connect(function(TriggeredPlayer,UHEMain)
	if not UHEMain or not UHEMain.Parent then
		return
	end
	local UHETime = UHEMain:FindFirstChild("Time")
	if not UHETime then
		return
	end

	local activePlayer, activePlayerObj, activeCharacter = resolveDefuseActor(TriggeredPlayer)
	if not activeCharacter then
		return
	end

	warn("Received PDA Feedback")
	local equipDeadline = tick() + 0.5
	while not Equipped and tick() < equipDeadline do
		task.wait(0.05)
	end

	local DefuseSpeed = 0.01 * Tickrate
	if Equipped == false then
		DefuseSpeed *= 0.95
	end
	local WasEquipped = Equipped
	local completed = false
	local finished = false

	local function restoreWalkSpeed()
		local humanoid = activeCharacter and activeCharacter:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = game.ReplicatedStorage.GameObjects.MaxSpeed.Value
		end
	end

	local function finishDefuse(state)
		if finished then
			return
		end
		finished = true
		Switch("Default")
		restoreWalkSpeed()

		if state == "complete" then
			completed = true
			SoundFolder.DefuseEnd:Play()
			if activePlayer then
				invokeMouseClient(activePlayer, nil, true)
			end
			return
		end

		if activePlayer then
			invokeMouseClient(activePlayer, false, nil)
		end
	end

	Switch("Defuse")
	SoundFolder.DefuseStart:Play()
	if activePlayer then
		coroutine.wrap(function()
			invokeMouseClient(activePlayer, true, nil)
		end)()
	end

	coroutine.wrap(function()
		while activeCharacter and activeCharacter.Parent and UHEMain.Parent and not finished do
			task.wait(0.01 * Tickrate)

			if UHETime.Value <= 0 then
				local serverScript = UHEMain:FindFirstChild("Script")
				local trigger = serverScript and serverScript:FindFirstChild("trole")
				if trigger then
					trigger:Fire(TriggeredPlayer,"Defuse")
				end
				if game.ServerStorage:FindFirstChild("Events") and game.ServerStorage.Events:FindFirstChild("UHE") then
					game.ServerStorage.Events.UHE:Fire(TriggeredPlayer, "Defuse")
				end
				finishDefuse("complete")
				break	
			end

			if Equipped and WasEquipped then
				UHETime.Value -= DefuseSpeed
			else
				UHETime.Value -= DefuseSpeed * 0.85
			end

			local humanoid = activeCharacter:FindFirstChild("Humanoid")
			if Equipped and WasEquipped then
				if humanoid then
					humanoid.WalkSpeed = 0
				end
			elseif humanoid and humanoid.WalkSpeed == 0 then
				humanoid.WalkSpeed = game.ReplicatedStorage.GameObjects.MaxSpeed.Value
			end

			local hrp = activeCharacter:FindFirstChild("HumanoidRootPart")
			if not hrp or (hrp.CFrame.Position - UHEMain.CFrame.Position).Magnitude > 30 then
				break
			end
		end

		if not completed then
			finishDefuse("cancel")
		end
	end)()
end)

-- PDA Server Script

local ItemID = script.Parent:FindFirstChild("ItemID")

repeat wait(0.01) until ItemID.Value ~= ""

ItemID = ItemID.Value

local GTool = _G.Items[ItemID]
local RWC = require(script.Parent.WeaponConfig)
local Framework = require(game.ReplicatedStorage.Modules.Framework) 

GTool.Init = function()
	Tool:WaitForChild("WeaponConfig")
	-- Initialize WeaponConfig
	IsEquippedValue.Value = true
	if not Tool.WeaponConfig:FindFirstChildOfClass("Configuration") then
		WeaponConfig = Framework.AddAttributes(RWC, Tool.WeaponConfig)
	else
		WeaponConfig = Tool.WeaponConfig.Configuration
	end

	WeaponConfig = Framework.IndexAttribute(WeaponConfig)
	local EQUIP_TIME = WeaponConfig.EQUIP_TIME or EquipTime

	-- Wait until the tool is parented to a character
	repeat wait() until Tool.Parent
	repeat wait() until Tool.Parent:IsA("Model")

	Character = Tool.Parent
	local Humanoid = Character:WaitForChild("Humanoid")

	local IsBot = Character:FindFirstChild("IsBot")

	coroutine.wrap(function()
		local defaultSpeed = tonumber(ReplicatedStorage.GameObjects and ReplicatedStorage.GameObjects:FindFirstChild("MaxSpeed") and ReplicatedStorage.GameObjects.MaxSpeed.Value) or 21
		local WalkSpeed = tonumber(WeaponConfig.WALKSPEED) or defaultSpeed
		local PlayerOBJ
		if not IsBot then
			Player = game.Players:WaitForChild(Character.Name)
			PlayerOBJ = _G.Players[Player.UserId]    
		else
			PlayerOBJ = _G.Players[Character.Name]    
		end
		PlayerOBJ:SetWalkSpeed(WalkSpeed)
	end)()

	Equipping = true
	Grip = Character["RightLowerArm"]:WaitForChild("RightGrip", 50)

	Model.Parent = Character

	Grip.Part1 = MainPart

	SV_EQUIP = Humanoid:LoadAnimation(AnimConfig.SV_EQUIP)
	SV_IDLE = Humanoid:LoadAnimation(AnimConfig.SV_IDLE)
	SV_EQUIP.Priority = Enum.AnimationPriority.Action
	SV_EQUIP.Looped = false
	SV_IDLE.Priority = Enum.AnimationPriority.Idle
	SV_IDLE.Looped = true
	SV_EQUIP:Play(0.1)

	-- Wait for equip time
	for i = EQUIP_TIME, EQUIP_TIME * 10 do
		if Tool.Parent ~= Character then
			Equipping = false
			break
		end
		wait(EQUIP_TIME / 10)
	end

	if Equipping then
		Equipped = true
		CanAttack = true
		SV_IDLE:Play(0.1)
	end
end
GTool.Uninit = function()
	IsEquippedValue.Value = false
	Equipped = false
	Equipping = false
	CanAttack = false
	if not Character then return end
	Humanoid = Character:WaitForChild("Humanoid")
	 Grip = Character["RightLowerArm"]:WaitForChild("RightGrip", 50)

	if SV_EQUIP then
		SV_EQUIP:Stop()
	end
	if SV_IDLE then
		SV_IDLE:Stop()
	end

	Grip.C1 = CFrame.new()
	Grip.C0 = CFrame.new()

	-- Return the model to a storage location
	if game.ReplicatedStorage.ReferenceModels:FindFirstChild(ItemID) then
		Model.Parent = game.ReplicatedStorage.ReferenceModels[ItemID]
		Model:Destroy()
	else
		Model.Parent = nil
	end
end









--function Fire(Player,LookV,Pos,Key)
--	--print(LookV,Pos,Key)
--	if tostring(Key) == "Ended" then 
--		GlobalKey = "Ended" 
--		Player.Character:FindFirstChild("Humanoid").WalkSpeed = game.ReplicatedStorage.GameObjects.MaxSpeed.Value
--		Switch("Default")
--		return 
--	end

--	if Key == "Started" and GlobalKey == Key then return end
	
--	GlobalKey = Key

--	local IgnoreList = {workspace.CurrentCamera,Player.Character}
--	for i,v in pairs(workspace:GetDescendants()) do
--		if string.find(v.Name,"Site") then
--			table.insert(IgnoreList,v)
--		end
--	end

--	local Params = RaycastParams.new()

--	Params.FilterType = Enum.RaycastFilterType.Blacklist
--	Params.FilterDescendantsInstances = IgnoreList

--	local HeadPos = Player.Character:WaitForChild("Head").Position

--	local Unit = LookV

--	local Direction =  Unit * 22--MHit +( CFrame.lookAt(HeadPos,MHit).lookVector * 0.01 )

--	local Dist = (HeadPos - Pos).Magnitude

--	if  Dist > 22 then return end

--	local RR = workspace:Raycast(HeadPos,Direction,Params)


--	if RR == nil then --print("NoRR") return false end

--	local HitPart = RR.Instance

--	if HitPart then
--		--print("PDARay",HitPart:GetFullName())
		
--		if HitPart.Parent.Name == "UHE-4" and Equipped == true then
--			--print(HitPart.Parent.Name)
--			Switch("Defuse")
--			Tool.PDA.Sounds.DefuseStart:Play()
--			MouseFunc:InvokeClient(Player,true)
--			coroutine.wrap(function()
--				while Equipped == true do
--					--print("tick")
--					task.wait(0.05)

--					if GlobalKey ~= "Started" then break end
--					if HitPart.Parent.Main.Time.Value <= 0 then
--						Player.Character:FindFirstChild("Humanoid").WalkSpeed = game.ReplicatedStorage.GameObjects.MaxSpeed.Value
--						HitPart.Parent.Main.Script:FindFirstChild("trole"):Fire(Player,"Defuse")
--						Tool.PDA.Sounds.DefuseEnd:Play()
--						--print("Fired Defuse Event")
--						MouseFunc:InvokeClient(Player,nil,true)
--						break	
--					end
--					HitPart.Parent.Main.Time.Value -= 0.05
--					--Player.Character:FindFirstChild("Humanoid").WalkSpeed = 0
--					if  (Player.Character.Origin.Position - HitPart.CFrame.Position).Magnitude > 30 then
--						break
--					end
--				end
--			end)()

--			return true
--		end
--	end

--	--RayCastVisualizer.ShowRay(HeadPos,Direction,Color3.new(1, 0.886275, 0),1,100,true)
--end
