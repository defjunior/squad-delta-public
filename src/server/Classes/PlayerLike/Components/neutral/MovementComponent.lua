local ComponentBase = require(script.Parent.Parent.Base)

local MovementComponent = ComponentBase:Extend()
MovementComponent.__index = MovementComponent
MovementComponent.Name = "MovementComponent"

function MovementComponent:Step()
	local selfPlayer = self.player

	local New = selfPlayer.Stamina - (selfPlayer.PassiveStaminaRegen)
	New = math.clamp(New,0,selfPlayer.StaminaMax)
	selfPlayer.PlayerData.Stamina.Value = New
	selfPlayer.Stamina = New

	if selfPlayer.CharacterObject then
		local HRP = selfPlayer.CharacterObject:FindFirstChild("HumanoidRootPart")
		if HRP then
			if HRP.AssemblyLinearVelocity.Magnitude > 19 and selfPlayer.Stamina >= 10 then
				selfPlayer.Stamina -= 10
				selfPlayer.PlayerData.Stamina.Value = selfPlayer.Stamina
			end
		end

	end
end

function MovementComponent:SetWalkSpeed(Speed)
	local selfPlayer = self.player
	if selfPlayer.CharacterObject:FindFirstChild("Humanoid") then
		local Hum = selfPlayer.CharacterObject.Humanoid
		selfPlayer.PreviousWalkspeed = Hum.WalkSpeed
		if selfPlayer.SpeedModifierType == 1 then
			if selfPlayer.CanMove == true then
				selfPlayer.PreviousWalkspeed = Speed + selfPlayer.SpeedModifier	
			end
			local Sum = Speed + selfPlayer.SpeedModifier	
			selfPlayer:SetValue("Speed", Sum)
		elseif selfPlayer.SpeedModifierType == 2 then
			if selfPlayer.CanMove == true then
				selfPlayer.PreviousWalkspeed = Speed * selfPlayer.SpeedModifier
			end	
			local Sum = Speed * selfPlayer.SpeedModifier
			selfPlayer:SetValue("Speed",Sum)
		end

	end
end

function MovementComponent:SetModifier(Type,Value)
	local selfPlayer = self.player
	if Type == "Mod" then
		selfPlayer:SetValue("SpeedModifier",Value)
	elseif Type == "Type" then
		selfPlayer:SetValue("SpeedModifierType",Value)
	end
end

function MovementComponent:SetJump(Speed)
	local selfPlayer = self.player
	if selfPlayer.CharacterObject:FindFirstChild("Humanoid") then
		local Hum = selfPlayer.CharacterObject.Humanoid
		selfPlayer.UserData.PreviousVertical = Hum.JumpPower
		if selfPlayer.SpeedModifierType == 1 then
			if selfPlayer.CanMove == true then
				Hum.JumpPower = Speed + selfPlayer.SpeedModifier	
			end
			local Sum = Speed * selfPlayer.SpeedModifier
			selfPlayer:SetValue("Jump",Sum)
		elseif selfPlayer.SpeedModifierType == 2 then
			if selfPlayer.CanMove == true then
				Hum.JumpPower = Speed * selfPlayer.SpeedModifier
			end		
			local Sum = Speed * selfPlayer.SpeedModifier
			selfPlayer:SetValue("Jump",Sum)
		end

	end
end

function MovementComponent:UpdateWalkSpeed(SpeedType)
	local selfPlayer = self.player
	if selfPlayer.CharacterObject:FindFirstChild("Humanoid") then
		local SpeedMod
		if SpeedType then
			SpeedMod = SpeedType
		else
			SpeedMod =  selfPlayer.SpeedModifierType
		end
		local Hum = selfPlayer.CharacterObject.Humanoid
		if selfPlayer.PreviousWalkspeed == Hum.WalkSpeed then return end
		if SpeedMod == 1 then
			Hum.WalkSpeed = selfPlayer.PreviousWalkspeed + selfPlayer.SpeedModifier
		elseif SpeedMod == 2 then
			Hum.WalkSpeed = selfPlayer.PreviousWalkspeed * selfPlayer.SpeedModifier
		end
		self:SetWalkSpeed(selfPlayer.Speed)
	end
end

return MovementComponent
