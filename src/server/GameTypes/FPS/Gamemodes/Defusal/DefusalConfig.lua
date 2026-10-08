local RunService = game:GetService("RunService")

-- Authored values omitted; original component wiring retained.
local config = {
	ModeId = "FPS/Defusal",
	Server = {
		Components = {
			{ module = "MapVoteComponent", key = "MapVote" },
			{ module = "SpawnProvisionComponent", key = "SpawnProvision" },
			{ module = "AliveRosterComponent", key = "AliveRoster" },
			{ module = "ObjectiveEventBridgeComponent", key = "ObjectiveBridge" },
			{ module = "BombObjectiveComponent", key = "ObjectivePlugin" },
			{ module = "ObjectiveWinRuleComponent", key = "ObjectiveWinRule" },
			{ module = "EliminationWinRuleComponent", key = "EliminationWinRule" },
			{ module = "TimerWinRuleComponent", key = "TimerWinRule" },
			{ module = "EconomyRuleComponent", key = "EconomyRule" },
			{ module = "ScoreRuleComponent", key = "ScoreRule" },
			{ module = "AnnouncerComponent", key = "Announcer" },
			{ module = "RoundFlowComponent", key = "RoundFlow" },
		},
		EndpointComponents = { "Announcer", "AliveRoster" },
		ControlComponent = "RoundFlow",
	},
	InitialState = {
		bombState = {},
		objective = {},
	},
	Network = {
		EventPrefix = "FPS/Defusal",
	},
	-- Omitted authored keys: DisplayName, Phases, TeamRoles, TeamWinCounters, ScoreWeights, Intermission, MapVoteTime, FreezeTime, BuyTime, EndTime, RoundsToWin, SideSwapRound, MatchRules, RoundTime, BombPlantTimeExtension, BaseCash, WarmupBaseCash, RoundReward, LoseBonus, WinBonus, DetonationBonus, DefusalBonus, FreePistol, AttackerBomb, Map, Objective, Revive, SpawnProvision, DefaultJumpPower.
}

return config
