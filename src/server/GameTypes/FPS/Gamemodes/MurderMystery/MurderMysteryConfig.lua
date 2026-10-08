-- Authored values omitted; original component wiring retained.
local config = {
	ModeId = "GameTypes/FPS/Gamemodes/MurderMystery/Server",
	Server = {
		Components = {
			{ module = "Defusal/Components/MapVoteComponent", key = "MapVote" },
			{ module = "MurderMysteryComponent", key = "MurderMystery" },
			{ module = "Defusal/Components/SpawnProvisionComponent", key = "SpawnProvision" },
			{ module = "Defusal/Components/AliveRosterComponent", key = "AliveRoster" },
			{ module = "Common/DeathmatchFlowComponent", key = "MatchFlow" },
		},
		EndpointComponents = { "AliveRoster" },
		ControlComponent = "MatchFlow",
	},
	-- Omitted authored keys: DisplayName, Intermission, MapVoteTime, EndTime, DefaultJumpPower, TeamRoles, TeamWinCounters, Map, Deathmatch, MurderMystery, Revive, SpawnProvision.
}

return config
