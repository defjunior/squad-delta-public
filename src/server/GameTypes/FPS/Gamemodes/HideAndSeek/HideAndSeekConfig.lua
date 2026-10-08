-- Authored values omitted; original component wiring retained.
local config = {
	ModeId = "GameTypes/FPS/Gamemodes/HideAndSeek/Server",
	Server = {
		Components = {
			{ module = "Defusal/Components/MapVoteComponent", key = "MapVote" },
			{ module = "Defusal/Components/SpawnProvisionComponent", key = "SpawnProvision" },
			{ module = "Defusal/Components/AliveRosterComponent", key = "AliveRoster" },
			{ module = "Defusal/Components/ObjectiveEventBridgeComponent", key = "ObjectiveBridge" },
			{ module = "Defusal/Components/BombObjectiveComponent", key = "ObjectivePlugin" },
			{ module = "Defusal/Components/AnnouncerComponent", key = "Announcer" },
			{ module = "HideAndSeekComponent", key = "HideAndSeek" },
			{ module = "Common/DeathmatchFlowComponent", key = "MatchFlow" },
		},
		EndpointComponents = { "Announcer", "AliveRoster" },
		ControlComponent = "MatchFlow",
	},
	-- Omitted authored keys: DisplayName, Intermission, MapVoteTime, EndTime, DefaultJumpPower, TeamRoles, TeamWinCounters, Map, Deathmatch, HideAndSeek, Revive, Objective, SpawnProvision.
}

return config
