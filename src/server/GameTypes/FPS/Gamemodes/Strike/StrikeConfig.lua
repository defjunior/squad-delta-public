-- Authored values omitted; original component wiring retained.
local config = {
	ModeId = "GameTypes/FPS/Gamemodes/Strike/Server",
	Server = {
		Components = {
			{ module = "Defusal/Components/MapVoteComponent", key = "MapVote" },
			{ module = "Defusal/Components/SpawnProvisionComponent", key = "SpawnProvision" },
			{ module = "Defusal/Components/AliveRosterComponent", key = "AliveRoster" },
			{ module = "Defusal/Components/ObjectiveEventBridgeComponent", key = "ObjectiveBridge" },
			{ module = "Defusal/Components/BombObjectiveComponent", key = "ObjectivePlugin" },
			{ module = "Defusal/Components/ObjectiveWinRuleComponent", key = "ObjectiveWinRule" },
			{ module = "Defusal/Components/EliminationWinRuleComponent", key = "EliminationWinRule" },
			{ module = "Defusal/Components/TimerWinRuleComponent", key = "TimerWinRule" },
			{ module = "Defusal/Components/EconomyRuleComponent", key = "EconomyRule" },
			{ module = "Defusal/Components/ScoreRuleComponent", key = "ScoreRule" },
			{ module = "Defusal/Components/AnnouncerComponent", key = "Announcer" },
			{ module = "StrikeComponent", key = "Strike" },
			{ module = "Defusal/Components/RoundFlowComponent", key = "RoundFlow" },
		},
		EndpointComponents = { "Announcer", "AliveRoster" },
		ControlComponent = "RoundFlow",
	},
	InitialState = {
		bombState = {},
		objective = {},
	},
	Network = {
		EventPrefix = "FPS/Strike",
	},
	-- Omitted authored keys: DisplayName, Phases, TeamRoles, TeamWinCounters, ScoreWeights, Intermission, MapVoteTime, FreezeTime, BuyTime, EndTime, RoundsToWin, SideSwapRound, MatchRules, RoundTime, BombPlantTimeExtension, BaseCash, WarmupBaseCash, RoundReward, LoseBonus, WinBonus, DetonationBonus, DefusalBonus, FreePistol, AttackerBomb, Map, Objective, Strike, Revive, SpawnProvision, DefaultWalkSpeed, DefaultJumpPower.
}

return config
