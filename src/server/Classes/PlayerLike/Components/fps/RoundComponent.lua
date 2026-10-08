local ComponentBase = require(script.Parent.Parent.Base)

local RoundComponent = ComponentBase:Extend()
RoundComponent.__index = RoundComponent
RoundComponent.Name = "FPSRoundComponent"

local Vector3 = Vector3

function RoundComponent:Init(player, ctx)
	self.ctx = ctx
	self.player = player
end

function RoundComponent:ResetRoundState()
	local player = self.player
	if not player then
		return
	end

	player:AddStats("RoundsPlayed", 1)
	player:SetValue("Taunting", false)
	player:AddStage(-99)
	player:SetModifier("Mod", 0)
	if _G.UserData[player.ID] then
		_G.UserData[player.ID].PositionTen = Vector3.new(0, 0, 0)
	end
	player.DamageTable = {}
end

function RoundComponent:ArchiveRoundStats()
	local player = self.player
	if not player then
		return
	end

	for statKey, statVal in pairs(player.CurrentRoundStats) do
		pcall(function()
			player:UpdateSavedStat(tostring(statKey), tostring(statVal), "PerRound")
			player:AddStats(tostring(statKey), 0, "Set", "CurrentRoundStats")
		end)
	end
end

function RoundComponent:PrepareForNewRound()
	self:ResetRoundState()
	self:ArchiveRoundStats()
end

return RoundComponent
