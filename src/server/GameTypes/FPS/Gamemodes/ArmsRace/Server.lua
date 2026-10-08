local ArmsRaceConfig = require(script.Parent.ArmsRaceConfig)
local ModeServer = require(script.Parent.Parent.Common.ModeServer)

local ArmsRaceServer = {
	ModeId = "GameTypes/FPS/Gamemodes/ArmsRace/Server",
}

function ArmsRaceServer.new(ctx, config)
	return ModeServer.new(ctx, config or ArmsRaceConfig, {
		modeId = ArmsRaceServer.ModeId,
		componentsFolder = script.Parent:WaitForChild("Components"),
	})
end

return ArmsRaceServer
