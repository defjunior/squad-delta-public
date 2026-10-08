local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ComponentBase = require(script.Parent.Parent.Base)
local Framework = require(ReplicatedStorage.Modules.Framework)

local StatusComponent = ComponentBase:Extend()
StatusComponent.__index = StatusComponent
StatusComponent.Name = "StatusComponent"

local IsServer = RunService:IsServer()

local function teleportPlayer(player, cf)
	if not player or not cf then
		return false
	end
	local anticheat = Framework.GetService("AnticheatService")
	if anticheat and anticheat.TeleportPlayer then
		return anticheat:TeleportPlayer(player, cf)
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = cf
		return true
	end
	return false
end

function StatusComponent:ApplyStatus(Status,Value,Duration,...)
	local player = self.player
	print(player.PlayerName,"ApplyStatus",Status,Value)
	player:SetValue("Value",Value,"StatusEffects",Status)
	local Args = {...}
	if Status == "Rewind" and Duration and player.CharacterObject then
		local PreviousPosition = player.CharacterObject.HumanoidRootPart.CFrame
		player:SetValue("Stack",player.StatusEffects[Status].Stack + Args[1],"StatusEffects",Status)
		player.StatusEffects[Status].Time = tick() + Duration
		if player.StatusEffects[Status].Value == false then
			player:SetValue("Value",true,"StatusEffects",Status)
			coroutine.wrap(function()
				repeat wait() until tick() >= player.StatusEffects[Status].Time
				player:SetValue("Value",false,"StatusEffects",Status)
				player:SetValue("Stack",0,"StatusEffects",Status)
			end)()
		end

		wait(Duration)
		if player.IsBot == false then
			coroutine.wrap(function()
			end)()
			teleportPlayer(player.PlayerObject, PreviousPosition)
		elseif player.CharacterObject then
			player.CharacterObject.HumanoidRootPart.CFrame = PreviousPosition
		end


	elseif Status == "Bleed" then
		player:SetValue("Stack",player.StatusEffects[Status].Stack + Args[1],"StatusEffects",Status)
		player.StatusEffects[Status].Time = tick() + Duration
		if player.StatusEffects[Status].Value == false then
			player:SetValue("Value",true,"StatusEffects",Status)
			coroutine.wrap(function()
				repeat task.wait(1) player:TakeDamage(Args[2]) until tick() >= player.StatusEffects[Status].Time
				player:Unstack(Status)
			end)()
		end
	end
end

function StatusComponent:Unstack(Status)
	local player = self.player
	coroutine.wrap(function()
		player:SetValue("Stack",0,"StatusEffects",Status)	
	end)()
	player:SetValue("Value",false,"StatusEffects",Status)
end

return StatusComponent
