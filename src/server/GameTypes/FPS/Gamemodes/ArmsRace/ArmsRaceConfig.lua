-- Authored values omitted; original component wiring retained.
local config = {
	ModeId = "GameTypes/FPS/Gamemodes/ArmsRace/Server",
	Server = {
		Components = {
			{ module = "Defusal/Components/MapVoteComponent", key = "MapVote" },
			{ module = "Defusal/Components/SpawnProvisionComponent", key = "SpawnProvision" },
			{ module = "Defusal/Components/AliveRosterComponent", key = "AliveRoster" },
			{ module = "ArmsRaceComponent", key = "ArmsRace" },
			{ module = "Common/DeathmatchFlowComponent", key = "MatchFlow" },
		},
		ControlComponent = "MatchFlow",
	},
	-- Omitted authored keys: DisplayName, Intermission, MapVoteTime, EndTime, DefaultJumpPower, TeamRoles, TeamWinCounters, Map, Deathmatch, Revive, ArmsRace, SpawnProvision.
}

return config
