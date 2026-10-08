local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local BaseController = require(game.ReplicatedFirst.Client.Modules.BaseController)
local MovementController = {}
MovementController.__index = MovementController

setmetatable(MovementController, BaseController)

function MovementController.new()
	return setmetatable(BaseController.new(script), MovementController)
end

function MovementController:_requireDependency(value, dependencyName, context)
	if value ~= nil then
		return value
	end
	error(("[CharacterController] Missing dependency '%s' while %s"):format(dependencyName, context), 2)
end

function MovementController:_waitForCharacterChild(character, childName, timeoutSeconds)
	self:_requireDependency(character, "Character", ("resolving '%s'"):format(childName))

	local child = character:FindFirstChild(childName)
	if child then
		return child
	end

	child = character:WaitForChild(childName, timeoutSeconds)
	if child then
		return child
	end

	warn(("[CharacterController] Character '%s' is missing child '%s'; setup deferred."):format(
		character:GetFullName(),
		childName
	))
	return nil
end

function MovementController:_isCharacterReady()
	return self.Character ~= nil
		and self.Character.Parent ~= nil
		and self.Humanoid ~= nil
		and self.Humanoid.Parent ~= nil
		and self.HumanoidRootPart ~= nil
		and self.HumanoidRootPart.Parent ~= nil
		and self.movementPosition ~= nil
		and self.movementPosition.Parent ~= nil
		and self.movementVelocity ~= nil
		and self.movementVelocity.Parent ~= nil
		and self.gravityForce ~= nil
		and self.gravityForce.Parent ~= nil
end

function MovementController:_clearCharacterState()
	self:_cleanupAlignOrientation()
	self.Character = nil
	self.Humanoid = nil
	self.RootPart = nil
	self.HumanoidRootPart = nil
	self.movementPosition = nil
	self.movementVelocity = nil
	self.gravityForce = nil
	self.IsSliding = false
	self.IsClimbing = false
	self.IsVaulting = false
	self.playerGrounded = false
end

function MovementController:_bindPlayerDataSignals(playerData)
	if self._playerDataSignalsBound then
		return true
	end

	local canMoveValue = playerData:FindFirstChild("CanMove")
	local speedValue = playerData:FindFirstChild("Speed")
	local jumpValue = playerData:FindFirstChild("Jump")
	if not canMoveValue or not speedValue or not jumpValue then
		return false
	end

	self.PlayerData = playerData
	self.CanMove = tostring(canMoveValue.Value)
	self.ServerMovementSpeed = tonumber(speedValue.Value) or self.ServerMovementSpeed
	self.ClientMovementSpeed = self.ServerMovementSpeed
	self.GroundAcceleration = self.ServerMovementSpeed * 10
	self.AirAcceleration = self.ServerMovementSpeed / self.AAC
	self.JumpForce = tonumber(jumpValue.Value) or self.JumpForce

	self:Connect(canMoveValue:GetPropertyChangedSignal("Value"), function()
		self.CanMove = tostring(canMoveValue.Value)
		if self.CanMove ~= "true" then
			self:ApplyFreezeMovementLock()
		end
	end)

	self:Connect(speedValue:GetPropertyChangedSignal("Value"), function()
		self.ServerMovementSpeed = tonumber(speedValue.Value) or self.ServerMovementSpeed
		if self.IsWalking then
			self.ClientMovementSpeed = self.ServerMovementSpeed * self.WalkingModifier
			self.GroundAcceleration = self.ServerMovementSpeed * self.WalkingModifier * 10
			self.AirAcceleration = self.ServerMovementSpeed * self.WalkingModifier / self.AAC
		elseif self.IsCrouching then
			self.ClientMovementSpeed = self.ServerMovementSpeed * self.CrouchingModifier
			self.GroundAcceleration = self.ServerMovementSpeed * self.CrouchingModifier * 10
			self.AirAcceleration = self.ServerMovementSpeed * self.CrouchingModifier / self.AAC
		else
			self.ClientMovementSpeed = self.ServerMovementSpeed
			self.GroundAcceleration = self.ServerMovementSpeed * 10
			self.AirAcceleration = self.ServerMovementSpeed / self.AAC
		end
	end)

	self:Connect(jumpValue:GetPropertyChangedSignal("Value"), function()
		self.JumpForce = tonumber(jumpValue.Value) or self.JumpForce
	end)

	self._playerDataSignalsBound = true
	return true
end

function MovementController:_tryBindPlayerData()
	if not self.inGame or self._playerDataSignalsBound then
		return true
	end

	local playerData = (_G and _G.PlayerData) or self.Player:FindFirstChild("PlayerData")
	if not playerData then
		local playerLikeStorage = ReplicatedStorage:FindFirstChild("PlayerLikeStorage")
		if playerLikeStorage then
			playerData = playerLikeStorage:FindFirstChild(tostring(self.Player.UserId))
		end
	end

	if not playerData then
		return false
	end

	local bound = self:_bindPlayerDataSignals(playerData)
	if not bound and not self._loggedPlayerDataShapeWarning then
		self._loggedPlayerDataShapeWarning = true
		warn("[CharacterController] PlayerData found but missing CanMove/Speed/Jump values; waiting for full replication.")
	end
	return bound
end

function MovementController:_getCanMoveState()
	if self.PlayerData then
		local canMoveValue = self.PlayerData:FindFirstChild("CanMove")
		if canMoveValue then
			return tostring(canMoveValue.Value)
		end
	end
	return tostring(self.CanMove or "false")
end

function MovementController:_fireCrouchRemote(isCrouching)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local clientRemotes = remotes and remotes:FindFirstChild("Client")
	local crouchRemote = clientRemotes and clientRemotes:FindFirstChild("Crouch")
	if crouchRemote then
		crouchRemote:FireServer(isCrouching)
	end
end

function MovementController:Start()
	--// ======= S1: services, locals, data =======
	self.Player = self:_requireDependency(Players.LocalPlayer, "Players.LocalPlayer", "starting CharacterController")
	self.Character = nil
	self.Camera = workspace.CurrentCamera

	-- If you wire PlayerData/Remotes, flip this true.
	self.inGame = true

	_G.Taunting = false
	self.GLoad = false

	self.SavedData = _G and _G.SavedData or nil
	self.PlayerData = nil

	--// ======= Tunables (names preserved from s1) =======
	self.WalkingModifier   = 0.5
	self.CrouchingModifier = 0.4
	self.AAC = 2
	self.GroundFriction = 7
	self.ServerMovementSpeed = 21
	self.ClientMovementSpeed = self.ServerMovementSpeed
	self.GroundMaxSpeed = self.ServerMovementSpeed
	self.GroundAcceleration = self.ServerMovementSpeed * 10
	self.AirMaxSpeed = 21
	self.AirAcceleration = self.ClientMovementSpeed / self.AAC
	self.JumpForce = 26
	self.CanMove = "false"
	self.gravityScale = 1

	-- Match legacy grounding geometry to keep stair contact stable.
	self.playerTorsoToGround = 3.0
	self.movementStickDistance = 0.5

	-- Keys / state flags (s1)
	self.IsWalking = false
	self.IsCrouching = false
	self.IsJumping = false
	self.IsMobile = not UserInputService.KeyboardEnabled

	-- Input tables (s1)
	self.GlobalInput = { W=false, A=false, S=false, D=false, Space=false, V=false }
	self.FrequencyInput = table.clone(self.GlobalInput)
	self.MoveInputSum = { forward=0, side=0 }

	self.movementPosition = nil
	self.movementVelocity = nil
	self.gravityForce = nil
	self._alignOrientation = nil
	self._alignTargetPart = nil
	self._alignSourceAttachment = nil
	self._alignTargetAttachment = nil

	self.IsSliding = false
	self.SlideTimer = 0
	self.LastSlideEnd = -10

	self.playerGrounded = false
	self.allowStick = true
	self.dt = 1/60

	--// ======= Extra Mechanics: Sliding / Ladder / Vault =======
	-- Sliding
	self.SlideEnabled = true
	self.AutoSlideEnabled = false
	self.SlideMinSpeed = 16
	self.SlideFriction = 10
	self.SlideBoost    = 4
	self.SlideDuration = 0.8
	self.SlideCooldown = 0.6
	self.SlideCameraTilt = math.rad(6)

	-- Slope physics
	self.SlideStartAngleDeg  = 45
	self.SlideAutoAngleDeg   = 72
	self.SlideStopAngleDeg   = 30
	self.SlideMinSpeed       = 12
	self.SlideSteer          = 0.4
	self.SlideMuK            = 0.2
	self.SlideAirDrag        = 0.1
	self.SlideMaxSpeed       = 45

	self.SurfAngleDeg = 60

	-- Ladder
	self.LadderEnabled = true
	self.IsClimbing = false
	self.LadderPart = nil
	self.LadderUpSpeed   = 12
	self.LadderDownSpeed = 12
	self.LadderSnapDistance = 2
	self.LadderFaceSnap = true

	-- Vault
	self.VaultEnabled = true
	self.IsVaulting = false
	self.VaultCooldown = 0.5
	self.LastVaultEnd = -10
	self.VaultMinHeight = 2
	self.VaultMaxHeight = 3.75
	self.VaultForwardProbe = 2
	self.VaultUpClearance = 2.5
	self.VaultTime = 0.22

	self.LandMinSpeed        = 10
	self.LandMinAirTime      = 0.10
	self.LandCooldown        = 0.15
	self.LandMaxIntensityVel = 60

	self.wasGrounded      = false
	self.lastAirStartT    = 0
	self.lastLandT        = -1
	self.lastVy           = 0

	-- Surf/Stick hysteresis (angles from horizontal)
	self.SurfEnterAngleDeg = 40
	self.SurfExitAngleDeg  = 10

	self.StickEnterDist = self.movementStickDistance + 0.03
	self.StickExitDist  = self.movementStickDistance + 0.08

	self.GroundMode = "STICK"

	-- s2 grounding geometry
	self.maxMovementPitch = 0.6
	self.rayYLength = self.playerTorsoToGround + self.movementStickDistance
	self.stepMergeHeight = 0.6
	self.StepSnapEnabled = true
	self.StepSnapHeight = 2.25
	self.StepSnapForwardDistance = 1.5
	self.StepSnapForwardNudge = 0.55

	self.movementVelocityForce = 300000
	self.movementPositionForce = 50000

	self.ungroundUntil = 0
	self.prevUpdate = tick()
	self._jumpPressedAt = 0
	self._lastJumpAt = 0
	self._playerDataSignalsBound = false
	self._loggedPlayerDataShapeWarning = false

	-- ======= HITBOX DIRECTORY CHANGE (ONLY FUNCTIONAL CHANGE REQUESTED) =======
	-- Previous legacy path (old): ReplicatedFirst.Assets.Models.MovementModels (NOW REQUIRED)
	-- Contains: CharacterHitbox, Crouch
	-- local mm = ReplicatedFirst:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("MovementModels")
	-- -- self.CharacterHitbox = mm:WaitForChild("CharacterHitbox")
	-- -- self.CrouchHitbox = mm:WaitForChild("Crouch")

	-- ======= _G hooks (legacy) =======
	_G.GetVelocity = function()
		return self.movementVelocity and self.movementVelocity.Velocity or Vector3.zero
	end
	_G.CheckGround = function()
		return self.allowStick and self.playerGrounded
	end
	_G.CheckCrouching = function()
		return self.IsCrouching
	end
	_G.CheckSliding = function()
		return self.IsSliding
	end
	_G.OnLandEvent = _G.OnLandEvent or Instance.new("BindableEvent")
	_G.OnMove = _G.OnMove or Instance.new("BindableEvent")
	_G.OnJump = _G.OnJump or Instance.new("BindableEvent")

	-- ======= binds =======
	ContextActionService:BindAction("Walk", function(_, inputState)
		self:onWalkAction(_, inputState)
	end, false, Enum.KeyCode.LeftShift)

	ContextActionService:BindAction("Crouch", function(_, inputState)
		self:onCrouchAction(_, inputState)
	end, false, Enum.KeyCode.LeftControl)

	-- Raw key -> GlobalInput (s1)
	self:Connect( UserInputService.InputBegan, function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local k = input.KeyCode.Name
			if self.GlobalInput[k] ~= nil then
				self.GlobalInput[k] = true
				if k == "Space" then
					self._jumpPressedAt = self:now()
				end
			end
		end
	end)

	self:Connect( UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local k = input.KeyCode.Name
			if self.GlobalInput[k] ~= nil then
				self.GlobalInput[k] = false
			end
		end
	end)

	self:_tryBindPlayerData()

	-- Character setup
	if self.Player.Character then
		self:SetupCharacter(self.Player.Character)
	end
	self:Connect( self.Player.CharacterAdded, function(char)
		self:SetupCharacter(char)
	end)
	self:Connect(self.Player.CharacterRemoving, function(char)
		if self.Character == char then
			self:_clearCharacterState()
		end
	end)

	-- Heartbeat
	self:Connect( RunService.RenderStepped, function()
		self:UpdateMovement()
	end)
end

function MovementController:Stop()
	pcall(function() ContextActionService:UnbindAction("Walk") end)
	pcall(function() ContextActionService:UnbindAction("Crouch") end)
	self:_clearCharacterState()
end

-- ======= helpers copied 1:1 =======

function MovementController:UpdateMoveInputSum()
	if self.IsMobile then
		-- (legacy left blank)
	end
	self.MoveInputSum.forward = (self.GlobalInput.W and 1 or 0) - (self.GlobalInput.S and 1 or 0)
	self.MoveInputSum.side    = (self.GlobalInput.D and 1 or 0) - (self.GlobalInput.A and 1 or 0)
end

function MovementController:ApplyFreezeMovementLock()
	if self.CanMove == "true" then
		return
	end
	self.MoveInputSum.forward = 0
	self.MoveInputSum.side = 0
	self.GlobalInput.Space = false
	if self.Humanoid then
		self.Humanoid.WalkSpeed = 0
	end
	if self.movementVelocity then
		self.movementVelocity.Velocity = Vector3.zero
	end
	if self.HumanoidRootPart then
		self.HumanoidRootPart.Velocity = Vector3.zero
	end
end

function MovementController:getAirAccelerate()    return self.AirAcceleration end
function MovementController:getAirMaxSpeed()      return self.AirMaxSpeed end
function MovementController:getGroundAccelerate() return self.GroundAcceleration end
function MovementController:getGroundMaxVel()     return self.GroundMaxSpeed end
function MovementController:getFriction()         return self.GroundFriction end
function MovementController:getJumpVelocity()     return self.JumpForce end

function MovementController:initBodyMovers()
	for _, bm in ipairs(self.HumanoidRootPart:GetChildren()) do
		if bm:IsA("BodyVelocity") or bm:IsA("BodyPosition") or bm:IsA("BodyForce") then
			bm:Destroy()
		end
	end

	self.movementPosition = Instance.new("BodyPosition")
	self.movementPosition.Name = "movementPosition"
	self.movementPosition.D = 220
	self.movementPosition.P = 7000
	self.movementPosition.MaxForce = Vector3.new()
	self.movementPosition.Position = self.HumanoidRootPart.Position
	self.movementPosition.Parent = self.HumanoidRootPart

	self.movementVelocity = Instance.new("BodyVelocity")
	self.movementVelocity.Name = "movementVelocity"
	self.movementVelocity.P = 1500
	self.movementVelocity.MaxForce = Vector3.new()
	self.movementVelocity.Velocity = Vector3.new()
	self.movementVelocity.Parent = self.HumanoidRootPart

	self.gravityForce = Instance.new("BodyForce")
	self.gravityForce.Name = "gravityForce"
	local charMass = 0
	for _, p in ipairs(self.Character:GetDescendants()) do
		if p:IsA("BasePart") then charMass += p:GetMass() end
	end
	self.gravityForce.Force = Vector3.new(0, (1 - self.gravityScale) * workspace.Gravity, 0) * charMass
	self.gravityForce.Parent = self.HumanoidRootPart
end

function MovementController:_cleanupAlignOrientation()
	if self._alignOrientation then
		self._alignOrientation:Destroy()
		self._alignOrientation = nil
	end
	if self._alignSourceAttachment then
		self._alignSourceAttachment:Destroy()
		self._alignSourceAttachment = nil
	end
	if self._alignTargetAttachment then
		self._alignTargetAttachment:Destroy()
		self._alignTargetAttachment = nil
	end
	if self._alignTargetPart then
		self._alignTargetPart:Destroy()
		self._alignTargetPart = nil
	end
end

function MovementController:_setupAlignOrientation()
	if not self.HumanoidRootPart then
		return
	end
	self:_cleanupAlignOrientation()

	local alignTarget = Instance.new("Part")
	alignTarget.Name = "MovementAlignTarget"
	alignTarget.CanCollide = false
	alignTarget.CanTouch = false
	alignTarget.Anchored = true
	alignTarget.Transparency = 1
	alignTarget.Size = Vector3.new(0.2, 0.2, 0.2)
	alignTarget.Parent = workspace:FindFirstChild("Ignore") or workspace

	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "MovementAlignTargetAttachment"
	targetAttachment.Parent = alignTarget

	local sourceAttachment = Instance.new("Attachment")
	sourceAttachment.Name = "MovementAlignSource"
	sourceAttachment.Parent = self.HumanoidRootPart

	local align = Instance.new("AlignOrientation")
	align.Name = "MovementAlignOrientation"
	align.Attachment0 = sourceAttachment
	align.Attachment1 = targetAttachment
	align.Responsiveness = 1
	align.RigidityEnabled = true
	align.AlignType = Enum.AlignType.AllAxes
	align.MaxTorque = 1e6
	align.PrimaryAxis = Vector3.new(0, 1, 0)
	align.PrimaryAxisOnly = true
	align.Parent = self.HumanoidRootPart

	self._alignOrientation = align
	self._alignTargetPart = alignTarget
	self._alignSourceAttachment = sourceAttachment
	self._alignTargetAttachment = targetAttachment
end

function MovementController:_updateAlignTarget(targetForward)
	if not self._alignTargetPart then
		return
	end
	if targetForward.Magnitude <= 0 then
		return
	end
	local pos = self.HumanoidRootPart.Position
	local targetCf = CFrame.new(pos, pos + targetForward.Unit)
	self._alignTargetPart.CFrame = targetCf
end

function MovementController:groundProbe()
	local rootCF = self.HumanoidRootPart.CFrame
	local origins = {
		self.HumanoidRootPart.Position,
		(rootCF * CFrame.new(-0.8, 0, 0)).Position,
		(rootCF * CFrame.new(0.8, 0, 0)).Position,
		(rootCF * CFrame.new(0, 0, 0.8)).Position,
		(rootCF * CFrame.new(0, 0, -0.8)).Position,
	}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = { self.Character, self.Camera, workspace.Ignore }

	local hits = {}
	local highestY = -math.huge

	for _, o in ipairs(origins) do
		local r = workspace:Raycast(o, Vector3.new(0, -self.rayYLength, 0), params)
		if r then
			table.insert(hits, r)
			if r.Position.Y > highestY then highestY = r.Position.Y end
		end
	end
	if #hits == 0 then return false end

	local sumN = Vector3.zero
	local sumP = Vector3.zero
	local count = 0
	for _, r in ipairs(hits) do
		if (highestY - r.Position.Y) <= self.stepMergeHeight then
			sumN += r.Normal
			sumP += r.Position
			count += 1
		end
	end
	local avgN = (count > 0) and sumN.Unit or Vector3.yAxis
	local avgP = (count > 0) and (sumP / count) or hits[1].Position

	local slopeOK = avgN.Y >= math.cos(math.rad(90 * self.maxMovementPitch))
	return true, avgP, avgN, slopeOK, hits[1].Instance, (self.HumanoidRootPart.Position.Y - avgP.Y)
end

function MovementController:slopeAngleDeg(n)
	return math.deg(math.acos(math.clamp(n.Y, -1, 1)))
end

function MovementController:clampMag(maxMag, vec)
	return vec.unit * (math.clamp(vec.Magnitude, 0, maxMag))
end

function MovementController:downhillFromNormal(n)
	local g = Vector3.new(0, -workspace.Gravity, 0)
	local tangent = g - n * g:Dot(n)
	local mag = tangent.Magnitude
	if mag < 1e-5 then
		return Vector3.zero, 0
	end
	return tangent / mag, mag
end

function MovementController:horiz(v) return Vector3.new(v.X, 0, v.Z) end

function MovementController:faceCameraYaw()
	local look = self.Camera.CFrame.LookVector
	local pos = self.HumanoidRootPart.Position
	local flat = Vector3.new(look.X, 0, look.Z)
	local mag = flat.Magnitude
	if mag <= 1e-5 then
		return
	end
	local targetForward = flat / mag
	local currentForward = Vector3.new(self.HumanoidRootPart.CFrame.LookVector.X, 0, self.HumanoidRootPart.CFrame.LookVector.Z)
	-- if currentForward.Magnitude > 1e-4 then
	-- 	local dot = currentForward.Unit:Dot(targetForward)
	-- 	if dot > 0.9995 then
	-- 		return
	-- 	end
	-- end
	if self._alignTargetPart then
		self:_updateAlignTarget(targetForward)
		local rx, ry, rz = self.HumanoidRootPart.CFrame.Rotation:ToOrientation()
		self.HumanoidRootPart.CFrame = CFrame.new(self.HumanoidRootPart.CFrame.Position) * CFrame.Angles(0, ry, rz)
		self.HumanoidRootPart.RotVelocity = Vector3.new()
		return
	end
	--self.HumanoidRootPart.CFrame = CFrame.new(pos, pos + targetForward)
	
end

function MovementController:getAccelDir()
	local lookCf = self.Camera.CFrame
	local forward = Vector3.new(lookCf.LookVector.X, 0, lookCf.LookVector.Z)
	local right = Vector3.new(lookCf.RightVector.X, 0, lookCf.RightVector.Z)
	if forward.Magnitude > 0 then
		forward = forward.Unit
	end
	if right.Magnitude > 0 then
		right = right.Unit
	end
	local dir = forward * self.MoveInputSum.forward + right * self.MoveInputSum.side
	return dir.Magnitude > 0 and dir.Unit or Vector3.zero
end

function MovementController:getAirForceForDir(dir)
	return Vector3.new(math.abs(dir.X), 0, math.abs(dir.Z)) * self.movementVelocityForce
end

function MovementController:capHorizontalVelocity(velocity, maxSpeed)
	if maxSpeed <= 0 then
		return velocity
	end
	local mag = velocity.Magnitude
	if mag <= maxSpeed or mag <= 1e-5 then
		return velocity
	end
	return velocity * (maxSpeed / mag)
end

function MovementController:steerVelocityAtCap(prevVelocity, accelDir, maxVelocity, accelVel)
	local speed = prevVelocity.Magnitude
	if speed <= 1e-5 then
		return prevVelocity
	end
	local currentDir = prevVelocity / speed
	local lateral = accelDir - currentDir * accelDir:Dot(currentDir)
	local lateralMag = lateral.Magnitude
	if lateralMag <= 1e-5 then
		return prevVelocity
	end
	local steerStep = accelVel * 6
	local steered = prevVelocity + (lateral / lateralMag) * steerStep
	local targetMag = math.min(speed, maxVelocity)
	if steered.Magnitude <= 1e-5 then
		return currentDir * targetMag
	end
	return steered.Unit * targetMag
end

function MovementController:getMovementVelocity(prevVelocity, accelerate, maxVelocity)
	local accelDir = self:getAccelDir()
	if self.CanMove ~= "true" then accelDir = Vector3.zero end
	if maxVelocity <= 0 then
		return prevVelocity
	end
	local baseVelocity = self:capHorizontalVelocity(prevVelocity, maxVelocity)
	if accelDir.Magnitude <= 0 then return baseVelocity end

	local projVel  = baseVelocity:Dot(accelDir)
	local accelVel = accelerate * self.dt
	local addVel = maxVelocity - projVel
	if addVel <= 0 then
		return self:steerVelocityAtCap(baseVelocity, accelDir, maxVelocity, accelVel)
	end
	if accelVel > addVel then
		accelVel = addVel
	end
	local wished = baseVelocity + accelDir * accelVel
	local cappedWished = self:capHorizontalVelocity(wished, maxVelocity)
	if baseVelocity.Magnitude >= (maxVelocity * 0.98) then
		local steered = self:steerVelocityAtCap(baseVelocity, accelDir, maxVelocity, accelVel)
		if steered:Dot(accelDir) > cappedWished:Dot(accelDir) then
			return steered
		end
	end
	return cappedWished
end

function MovementController:now()
	return tick()
end

function MovementController:doJump()
	local v = self.HumanoidRootPart.Velocity
	self.HumanoidRootPart.Velocity = Vector3.new(v.X, self:getJumpVelocity(), v.Z)
	self.ungroundUntil = self:now() + 0.12
	self._lastJumpAt = self:now()
	_G.OnJump:Fire(self.movementVelocity.Velocity)
end

function MovementController:_trySnapUpStepInDirection(moveDir)
	if moveDir.Magnitude <= 1e-4 then
		return false
	end
	moveDir = moveDir.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = { self.Character, self.Camera, workspace.Ignore }

	local rootPos = self.HumanoidRootPart.Position
	local footY = rootPos.Y - self.playerTorsoToGround
	local lowerOrigin = Vector3.new(rootPos.X, footY + 0.15, rootPos.Z)
	local forward = moveDir * self.StepSnapForwardDistance

	local lowerHit = workspace:Raycast(lowerOrigin, forward, params)
	if not lowerHit then
		return false
	end
	if lowerHit.Normal.Y > 0.35 then
		return false
	end

	local upperOrigin = lowerOrigin + Vector3.new(0, self.StepSnapHeight, 0)
	local upperHit = workspace:Raycast(upperOrigin, forward, params)
	if upperHit then
		return false
	end

	local downOrigin = lowerOrigin + forward + Vector3.new(0, self.StepSnapHeight, 0)
	local downHit = workspace:Raycast(downOrigin, Vector3.new(0, -(self.StepSnapHeight + 1.5), 0), params)
	if not downHit then
		return false
	end
	if downHit.Normal.Y < 0.65 then
		return false
	end

	local rise = downHit.Position.Y - footY
	if rise <= 0.15 or rise > self.StepSnapHeight then
		return false
	end

	local targetY = downHit.Position.Y + self.playerTorsoToGround
	local nudge = moveDir * self.StepSnapForwardNudge
	local targetPos = Vector3.new(rootPos.X + nudge.X, targetY, rootPos.Z + nudge.Z)
	self.HumanoidRootPart.CFrame = CFrame.new(targetPos) * self.HumanoidRootPart.CFrame.Rotation
	return true
end

function MovementController:trySnapUpStep()
	if not self.StepSnapEnabled then
		return false
	end
	if self.CanMove ~= "true" then
		return false
	end

	local accelDir = self:getAccelDir()
	local inputDir = Vector3.new(accelDir.X, 0, accelDir.Z)
	local velDir = Vector3.new(self.HumanoidRootPart.Velocity.X, 0, self.HumanoidRootPart.Velocity.Z)
	local hasInputIntent = (self.MoveInputSum.forward ~= 0) or (self.MoveInputSum.side ~= 0)
	if not hasInputIntent and velDir.Magnitude < 4 then
		return false
	end

	local candidates = {}
	if inputDir.Magnitude > 1e-4 then
		table.insert(candidates, inputDir.Unit)
	end
	if velDir.Magnitude > 4 then
		table.insert(candidates, velDir.Unit)
	end

	if #candidates == 0 then
		return false
	end

	for _, dir in ipairs(candidates) do
		if self:_trySnapUpStepInDirection(dir) then
			return true
		end
	end
	return false
end

function MovementController:runOnGround(groundPos)
	local v = self.HumanoidRootPart.Velocity
	local hv = Vector3.new(v.X, 0, v.Z)
	local speed = hv.Magnitude
	if speed > 0 then
		local drop = speed * self:getFriction() * self.dt
		hv = hv * math.max(speed - drop, 0) / speed
	end

	if self:trySnapUpStep() then
		local grounded, snappedGroundPos = self:groundProbe()
		if grounded and snappedGroundPos then
			groundPos = snappedGroundPos
		end
	end

	self.movementPosition.Position = groundPos + Vector3.new(0, self.playerTorsoToGround, 0)
	self.movementPosition.MaxForce = Vector3.new(0, self.movementPositionForce, 0)

	local wished = self:getMovementVelocity(hv, self:getGroundAccelerate(), self:getGroundMaxVel())
	self.movementVelocity.Velocity = Vector3.new(wished.X, 0, wished.Z)
	self.movementVelocity.MaxForce = Vector3.new(self.movementVelocityForce, 0, self.movementVelocityForce)
	self.movementVelocity.P = 1500

	_G.OnMove:Fire(self.movementVelocity.Velocity)
end

function MovementController:airStep()
	self.movementPosition.MaxForce = Vector3.new()
	local cur = self.HumanoidRootPart.Velocity
	local hv = Vector3.new(cur.X, 0, cur.Z)
	local wished = self:getMovementVelocity(hv, self:getAirAccelerate(), self:getAirMaxSpeed())
	self.movementVelocity.Velocity = Vector3.new(wished.X, cur.Y, wished.Z)
	self.movementVelocity.MaxForce = Vector3.new(self.movementVelocityForce, 0, self.movementVelocityForce)
end

-- Sliding (copied 1:1)
function MovementController:tryStartSlide(groundPos, groundNormal)
	if self.IsSliding then return false end
	if self:now() - self.LastSlideEnd < self.SlideCooldown then return false end

	self.IsSliding = true
	self.SlideTimer = 0

	if self.movementVelocity.Velocity.Magnitude > 17 then
		TweenService:Create(self.Humanoid, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			CameraOffset = Vector3.new(0, -2.2, 0)
		}):Play()
	end
	return true
end

function MovementController:endSlide()
	if not self.IsSliding then return end
	self.IsSliding = false
	self.LastSlideEnd = self:now()

	TweenService:Create(self.Humanoid, TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		CameraOffset = Vector3.new(0, 0, 0)
	}):Play()

	self.Camera.CFrame = self.Camera.CFrame * CFrame.Angles(0, 0, -self.SlideCameraTilt)
end

function MovementController:slideStep(groundPos)
	if not groundPos then
		self:endSlide()
		return
	end

	self.SlideTimer += self.dt

	self.movementPosition.Position = groundPos + Vector3.new(0, self.playerTorsoToGround - 0.4, 0)
	self.movementPosition.MaxForce = Vector3.new(0, self.movementPositionForce, 0)
	self.movementVelocity.MaxForce = Vector3.new(self.movementVelocityForce, 0, self.movementVelocityForce)

	local _, _, normal = self:groundProbe()
	if not normal then normal = Vector3.yAxis end

	local downhillDir, a_grav = self:downhillFromNormal(normal)
	local normalScale = math.max(normal.Y, 0)
	local a_fric = self.SlideMuK * workspace.Gravity * normalScale

	local v = self.HumanoidRootPart.Velocity
	local vPlanar = v - Vector3.new(0, v.Y, 0)
	local speed = vPlanar.Magnitude

	local fricDir
	if speed > 0.5 then
		fricDir = -vPlanar.Unit
	else
		fricDir = -downhillDir
	end

	local inputDir = self:getAccelDir()
	local steerVel = Vector3.zero
	if inputDir.Magnitude > 0 then
		local inputInPlane = (inputDir - normal * inputDir:Dot(normal)).Unit
		steerVel = inputInPlane * (self.ClientMovementSpeed * self.SlideSteer)
	end

	local aPlanar = downhillDir * a_grav + fricDir * a_fric - vPlanar * self.SlideAirDrag
	local vPlanarNew = vPlanar + aPlanar * self.dt + steerVel * self.dt

	if vPlanarNew.Magnitude > self.SlideMaxSpeed then
		vPlanarNew = vPlanarNew.Unit * self.SlideMaxSpeed
	end

	self.movementVelocity.Velocity = Vector3.new(vPlanarNew.X, math.min(v.Y, 2), vPlanarNew.Z)
	self.HumanoidRootPart.Velocity = Vector3.new(vPlanarNew.X, math.min(v.Y, 2), vPlanarNew.Z)

	local ang = self:slopeAngleDeg(normal)
	if (ang <= self.SlideStopAngleDeg and vPlanarNew.Magnitude < 9) or (not self.IsCrouching) or (not self.playerGrounded) then
		self:endSlide()
	end

	if vPlanarNew.Magnitude > 17 then
		self.Camera.CFrame = self.Camera.CFrame * CFrame.Angles(0, 0, self.SlideCameraTilt * math.min(v.Magnitude, self.SlideMaxSpeed) / self.SlideMaxSpeed)
	end
end

-- Ladder detection (copied 1:1)
function MovementController:isLadder(part)
	if not part or not part:IsA("BasePart") then return false end
	if CollectionService:HasTag(part, "Ladder") then return true end
	local tag = part:FindFirstChild("IsLadder")
	return (tag and tag:IsA("BoolValue") and tag.Value) or false
end

function MovementController:findLadderAhead()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Character, self.Camera, workspace.Ignore }

	local origin = self.HumanoidRootPart.Position - Vector3.new(0, 3, 0)
	local dir = (self.Camera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	if dir.Magnitude <= 0 then return nil end

	local result = workspace:Raycast(origin, dir * self.LadderSnapDistance, params)
	if result and self:isLadder(result.Instance) then
		return result
	end
	return nil
end

function MovementController:startClimb(hit)
	if not self.LadderEnabled then return false end
	if self.IsClimbing then return true end

	self.IsClimbing = true
	self.LadderPart = hit.Instance
	self.movementVelocity.MaxForce = Vector3.new(0, 0, 0)
	self.gravityForce.Force = Vector3.new(0, 0, 0)

	if self.LadderFaceSnap then
		local ladderCF = self.LadderPart.CFrame
		local forwardOnLadder = -ladderCF.LookVector
		local pos = self.HumanoidRootPart.Position
		local projected = CFrame.lookAt(pos, pos + Vector3.new(forwardOnLadder.X, 0, forwardOnLadder.Z))
		self.HumanoidRootPart.CFrame = projected
	end
	return true
end

function MovementController:endClimb()
	if not self.IsClimbing then return end
	self.IsClimbing = false
	self.LadderPart = nil

	local mass = 0
	for _, p in ipairs(self.Character:GetDescendants()) do
		if p:IsA("BasePart") then mass += p:GetMass() end
	end
	self.gravityForce.Force = Vector3.new(0, (1 - self.gravityScale) * workspace.Gravity, 0) * mass
end

function MovementController:climbStep()
	local move = (self.GlobalInput.W and 1 or 0) - (self.GlobalInput.S and 1 or 0)
	local vy = 0
	if move ~= 0 then
		vy = (move > 0) and self.LadderUpSpeed or -self.LadderDownSpeed
	end

	self.HumanoidRootPart.Velocity = Vector3.new(0, vy, 0)
	self.movementPosition.MaxForce = Vector3.new()
	self.movementVelocity.MaxForce = Vector3.new()

	if self.GlobalInput.Space then
		local back = (-self.Camera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
		local backKick = back * 8
		self.HumanoidRootPart.Velocity = Vector3.new(backKick.X, self:getJumpVelocity(), backKick.Z)
		self:endClimb()
		self.ungroundUntil = self:now() + 0.12
	end

	local ahead = self:findLadderAhead()
	if not ahead then self:endClimb() end
end

-- Vault (copied 1:1)
function MovementController:vaultProbe()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = { self.Character, workspace.Ignore, self.Camera }

	local root = self.HumanoidRootPart.Position
	local forward = (self.HumanoidRootPart.Velocity * Vector3.new(1, 0, 1)).Unit
	if forward.Magnitude <= 0 then return nil end

	local waist = root + Vector3.new(0, -1.5, 0)
	local front = workspace:Raycast(waist, forward * self.VaultForwardProbe, params)
	if not front or not front.Instance then return nil end

	local upHit = workspace:Raycast(front.Position + front.Normal * 0.05, Vector3.new(0, self.VaultMaxHeight, 0), params)
	local topY = upHit and upHit.Position.Y or (front.Position.Y + self.VaultMaxHeight)
	local height = topY - root.Y
	if height < self.VaultMinHeight or height > self.VaultMaxHeight then return nil end

	local standOrigin = Vector3.new(front.Position.X, topY + 0.2, front.Position.Z)
	local clear = workspace:Raycast(standOrigin, forward * 0.9, params)
	if clear then return nil end

	local groundCheck = workspace:Raycast(standOrigin + forward * 0.7, Vector3.new(0, -self.VaultUpClearance, 0), params)
	if not groundCheck then return nil end

	return {
		landPos = groundCheck.Position + Vector3.new(0, self.playerTorsoToGround, 0) + forward * 7,
		height = height
	}
end

function MovementController:startVault(info)
	if not self.VaultEnabled or self.IsVaulting then return false end
	if self:now() - self.LastVaultEnd < self.VaultCooldown then return false end

	self.IsVaulting = true
	self.movementPosition.MaxForce = Vector3.new()

	local startPos = self.HumanoidRootPart.Position
	local peak = startPos:Lerp(info.landPos, 0.5) + Vector3.new(0, math.clamp(info.height * 0.6, 0.7, 1.2), 0)

	local t = Instance.new("BindableEvent")
	local elapsed = 0
	local dur = self.VaultTime
	local goal = info.landPos

	TweenService:Create(self.Humanoid, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), {
		CameraOffset = Vector3.new(0, -1, 0)
	}):Play()

	local conn
	conn = RunService.RenderStepped:Connect(function(step)
		elapsed += step
		local a = math.clamp(elapsed / dur, 0, 1)

		local p0, p1, p2 = startPos, peak, goal
		local p = p0 * (1-a) * (1-a) + p1 * 2 * (1-a) * a + p2 * a * a

		self.HumanoidRootPart.CFrame = CFrame.new(p, p + self.Camera.CFrame.LookVector * Vector3.new(1, 0, 1) * self.GroundAcceleration)
		self.Camera.CFrame = self.Camera.CFrame * CFrame.Angles(0, 0, -self.SlideCameraTilt / 2)
		if a >= 1 then
			conn:Disconnect()
			t:Fire()
		end
	end)

	t.Event:Wait()
	self.LastVaultEnd = self:now()
	self.IsVaulting = false
end

-- dt
function MovementController:setDT()
	local n = tick()
	self.dt = math.clamp(n - self.prevUpdate, 1/240, 1/30)
	self.prevUpdate = n
end

function MovementController:OnLand(intensity, vNormal, normal)
	if intensity and intensity > 10 then
		_G.OnLandEvent:Fire()
	end
end

function MovementController:LandingIntensityFromContact(velocity, groundNormal)
	local vn = -velocity:Dot(groundNormal)
	if vn <= self.LandMinSpeed then return 0, 0 end
	local t = math.clamp(vn / self.LandMaxIntensityVel, 0, 1)
	return t, vn
end

function MovementController:UpdateMovement()
	if self.inGame then
		self:_tryBindPlayerData()
	end
	if not self:_isCharacterReady() then
		return
	end
	if not self.Camera then
		self.Camera = workspace.CurrentCamera
		if not self.Camera then
			return
		end
	end
	self.CanMove = self:_getCanMoveState()

	self:setDT()
	self:UpdateMoveInputSum()
	self:ApplyFreezeMovementLock()
	self:faceCameraYaw()

	self.GroundMaxSpeed = self.ClientMovementSpeed

	if self.CanMove ~= "true" then
		if self.IsSliding then
			self:endSlide()
		end
		if self.IsClimbing then
			self:endClimb()
		end
		self.IsVaulting = false

		local grounded, hitPos = self:groundProbe()
		self.playerGrounded = grounded
		self.wasGrounded = grounded

		if self.movementVelocity then
			self.movementVelocity.Velocity = Vector3.zero
			self.movementVelocity.MaxForce = Vector3.new(self.movementVelocityForce, 0, self.movementVelocityForce)
		end

		if self.movementPosition then
			if grounded and hitPos then
				self.movementPosition.Position = hitPos + Vector3.new(0, self.playerTorsoToGround, 0)
				self.movementPosition.MaxForce = Vector3.new(0, self.movementPositionForce, 0)
			else
				self.movementPosition.MaxForce = Vector3.new()
			end
		end
		return
	end

	if not self.IsVaulting then
		if not self.IsClimbing then
			local ahead = self:findLadderAhead()
			if ahead and (self.GlobalInput.W or self.GlobalInput.S) then
				self:startClimb(ahead)
			end
		end
		if self.IsClimbing then
			self:climbStep()
			return
		end
	end

	local grounded, hitPos, normal, slopeOK, inst, dist = self:groundProbe()

	if self:now() < self.ungroundUntil then
		grounded = false
	end

	self.playerGrounded = grounded

	if not self.IsVaulting and self.playerGrounded and self.GlobalInput.Space then
		local info = self:vaultProbe()
		if info then
			self:startVault(info)
			return
		end
	end

	if self.SlideEnabled and not self.IsVaulting and not self.IsClimbing then
		if not self.IsSliding and self.playerGrounded then
			local _, _, nrm = self:groundProbe()
			local ang = self:slopeAngleDeg(nrm)

			local speed = self:horiz(self.HumanoidRootPart.Velocity).Magnitude
			local wantsCrouchStart = self.IsCrouching and speed >= self.SlideMinSpeed
			local wantsAutoStart   = ang >= self.SlideAutoAngleDeg and self.AutoSlideEnabled
			local wantsAngleStart  = self.IsCrouching and ang >= self.SlideStartAngleDeg and self.AutoSlideEnabled

			if wantsAutoStart or wantsAngleStart or wantsCrouchStart then
				self:tryStartSlide(hitPos, nrm)
			end
		end
		if self.IsSliding then
			self:slideStep(hitPos)
			return
		end
	end

	local nowT = tick()
	if not self.playerGrounded and self.wasGrounded then
		self.lastAirStartT = nowT
	end

	local justLanded = (not self.wasGrounded) and self.playerGrounded and (nowT - self.lastLandT > self.LandCooldown)

	if justLanded and not self.IsClimbing and not self.IsVaulting and (self:now() >= (self.ungroundUntil or 0)) then
		local v = self.HumanoidRootPart.Velocity
		local intensity, vN = self:LandingIntensityFromContact(v, normal)
		if (nowT - self.lastAirStartT) >= self.LandMinAirTime and intensity > 0 then
			self.lastLandT = nowT
			self:OnLand(intensity, vN, normal)
		end
	end

	self.wasGrounded = self.playerGrounded
	self.lastVy = self.HumanoidRootPart.Velocity.Y

	if not self.playerGrounded and not self.allowStick and self.GlobalInput.Space then
		self.GlobalInput.Space = false
	end

	if self.playerGrounded then
		local ang = self:slopeAngleDeg(normal)
		self.allowStick = self.HumanoidRootPart.Velocity.Y <= self.JumpForce/2
			and ((dist or 9e9) <= 3 or (not inst and ang < self.SurfAngleDeg))

		local freshJumpPress = (self:now() - (self._jumpPressedAt or 0)) <= 0.2
			and (self:now() - (self._lastJumpAt or 0)) > 0.2
		local hasForwardIntent = self.GlobalInput.W == true or self.MoveInputSum.forward > 0
		if self.allowStick and self.GlobalInput.Space and (freshJumpPress or hasForwardIntent) then
			self:doJump()
			self:airStep()
		elseif self.allowStick then
			self:runOnGround(hitPos)
		else
			self.movementPosition.MaxForce = Vector3.new()
			local cur = self.HumanoidRootPart.Velocity
			local vPlane = (function(v, n) return v - n * v:Dot(n) end)(cur, normal)

			local input = self:getAccelDir()
			local accelDirPlane = (function(v, n) return v - n * v:Dot(n) end)(input, normal)
			if accelDirPlane.Magnitude > 0 then accelDirPlane = accelDirPlane.Unit end

			local accel = self:getGroundAccelerate() * self.dt
			local maxV  = self:getGroundMaxVel()

			accel /= (2 + (ang/10))
			local proj = vPlane:Dot(accelDirPlane)
			local add  = math.clamp(maxV - proj, 0, accel)
			local vPlaneNew = vPlane + accelDirPlane * add

			local vNow = self.movementVelocity.Velocity
			local vInto = vNow:Dot(normal)
			if vInto < -1.0 then
				self.movementVelocity.Velocity = vNow - normal * vInto
			end

			self.movementVelocity.Velocity = Vector3.new(vPlaneNew.X, cur.Y, vPlaneNew.Z)
			self.movementVelocity.MaxForce = Vector3.new(self.movementVelocityForce * 0.1, 0, self.movementVelocityForce * 0.1)
			self.movementVelocity.P = 900
			_G.OnMove:Fire(self.movementVelocity.Velocity)
		end
	else
		self:airStep()
	end

	self.movementVelocity.Velocity = self:clampMag(64, self.movementVelocity.Velocity)
end

--// ======= S1: Walk / Crouch kept intact =======
function MovementController:TweenPropertyIn(Object, Property, Time, Goal)
	TweenService:Create(Object, TweenInfo.new(Time, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		[Property] = Goal
	}):Play()
end
function MovementController:TweenPropertyOut(Object, Property, Time, Goal)
	TweenService:Create(Object, TweenInfo.new(Time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		[Property] = Goal
	}):Play()
end

function MovementController:onWalkAction(_, inputState)
	if not self:_isCharacterReady() then
		return
	end
	local canMove = self:_getCanMoveState() == "true"
	if inputState == Enum.UserInputState.Begin then
		if canMove then
			if not self.IsCrouching and not self.IsSliding and not self.IsClimbing then
				self.IsWalking = true
				self.ClientMovementSpeed = self.ServerMovementSpeed * self.WalkingModifier
				self.GroundAcceleration = self.ServerMovementSpeed * self.WalkingModifier * 10
				self.AirAcceleration = self.ServerMovementSpeed * self.WalkingModifier / self.AAC
				if self.Humanoid then self.Humanoid.WalkSpeed = self.ClientMovementSpeed end
			end
		end
	elseif inputState == Enum.UserInputState.End then
		if canMove then
			if not self.IsCrouching and not self.IsSliding then
				self.IsWalking = false
				self.ClientMovementSpeed = self.ServerMovementSpeed
				self.GroundAcceleration = self.ServerMovementSpeed * 10
				self.AirAcceleration = self.ServerMovementSpeed / self.AAC
				if self.Humanoid then self.Humanoid.WalkSpeed = self.ServerMovementSpeed end
			end
		end
	end
end

function MovementController:onCrouchAction(_, inputState)
	if not self:_isCharacterReady() then
		return
	end
	local canMove = self:_getCanMoveState() == "true"
	if inputState == Enum.UserInputState.Begin then
		if canMove then
			if not self.IsWalking and not self.IsSliding and not self.IsClimbing then
				self.IsCrouching = true
				self.ClientMovementSpeed = self.ServerMovementSpeed * self.CrouchingModifier
				self.GroundAcceleration = self.ServerMovementSpeed * self.CrouchingModifier * 10
				self.AirAcceleration = self.ServerMovementSpeed * self.CrouchingModifier / self.AAC
				if self.Humanoid then
					self.Humanoid.WalkSpeed = self.ClientMovementSpeed
					self:TweenPropertyIn(self.Humanoid, "CameraOffset", 0.12, Vector3.new(0, -1.6, 0))
				end
				if self.inGame then
					self:_fireCrouchRemote(true)
				end
			end
		end
	elseif inputState == Enum.UserInputState.End then
		if not canMove then
			return
		end
		self.IsCrouching = false
		self.ClientMovementSpeed = self.ServerMovementSpeed
		self.GroundAcceleration = self.ServerMovementSpeed * 10
		self.AirAcceleration = self.ServerMovementSpeed / self.AAC
		if self.Humanoid then
			self.Humanoid.WalkSpeed = self.ClientMovementSpeed
			self:TweenPropertyOut(self.Humanoid, "CameraOffset", 0.12, Vector3.new(0, 0, 0))
		end
		if self.inGame then
			self:_fireCrouchRemote(false)
		end
	end
end

function MovementController:SetupCharacter(char)
	if not char or not char:IsA("Model") then
		warn("[CharacterController] SetupCharacter expected a Model but received nil/invalid value.")
		return false
	end

	self:_clearCharacterState()
	self.Character = char
	self.Camera = workspace.CurrentCamera

	self.Humanoid = self:_waitForCharacterChild(char, "Humanoid", 10)
	self.RootPart = self:_waitForCharacterChild(char, "HumanoidRootPart", 10)
	if not self.Humanoid or not self.RootPart then
		self:_clearCharacterState()
		return false
	end
	self.HumanoidRootPart = self.RootPart

	self.Humanoid.PlatformStand = true
	--self.Humanoid.AutoRotate = false
	
	local props = PhysicalProperties.new(1, 0.3, 0, 1, 1)
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CustomPhysicalProperties = props
		end
	end

	self:initBodyMovers()
	self:_setupAlignOrientation()
	self.IsSliding, self.IsClimbing, self.IsVaulting = false, false, false
	return true
end

return MovementController
