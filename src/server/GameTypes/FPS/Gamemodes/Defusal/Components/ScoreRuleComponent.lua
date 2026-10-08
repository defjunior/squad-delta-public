local ScoreRuleComponent = {}
ScoreRuleComponent.__index = ScoreRuleComponent

local COMPONENT_NAME = "ScoreRule"

local function eventLabel(name)
	return ("%s:%s"):format(COMPONENT_NAME, name)
end

local MVP_THRESHOLD = 3

local function calculateScore(weights, stats)
	local score = 0
	if not stats then
		return score
	end
	for key, weight in pairs(weights or {}) do
		local value = stats[key]
		if value then
			score += (weight * value)
		end
	end
	return score
end

function ScoreRuleComponent.new(ctx)
	local self = setmetatable({}, ScoreRuleComponent)
	if ctx then
		self:Mount(ctx)
	end
	return self
end

function ScoreRuleComponent:Mount(ctx)
	if self._mounted then
		return
	end
	self._mounted = true
	self._ctx = ctx
	self._config = ctx.config or {}
	self._connections = {}

	table.insert(self._connections, ctx.Events:On("RoundEnded", function()
		self:_declareMvp()
	end, eventLabel("RoundEnded")))
end

function ScoreRuleComponent:_declareMvp()
	local weights = self._config.ScoreWeights or {}
	local bestPlayer = nil
	local bestScore = nil

	for _, gp in pairs(_G.Players) do
		if gp and gp.IsPlaying == true then
			local score = calculateScore(weights, gp.CurrentRoundStats)
			if bestScore == nil or score > bestScore then
				bestScore = score
				bestPlayer = gp
			end
		end
	end

	if bestPlayer and bestScore and bestScore > MVP_THRESHOLD then
		if bestPlayer.AddStats then
			bestPlayer:AddStats("MVPs", 1, "Add")
		end
		self._ctx.Events:Emit("MVPDeclared", {
			player = bestPlayer,
			score = bestScore,
		})
	end
end

function ScoreRuleComponent:Dismount()
	for _, conn in ipairs(self._connections or {}) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = nil
	self._mounted = false
end

return ScoreRuleComponent
