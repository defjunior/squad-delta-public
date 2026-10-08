local OneInTheChamberConfig = require(script.Parent.OneInTheChamberConfig)
local ModeServer = require(script.Parent.Parent.Common.ModeServer)

local OneInTheChamberServer = {
	ModeId = "GameTypes/FPS/Gamemodes/OneInTheChamber/Server",
}

function OneInTheChamberServer.new(ctx, config)
	return ModeServer.new(ctx, config or OneInTheChamberConfig, {
		modeId = OneInTheChamberServer.ModeId,
		componentsFolder = script.Parent:WaitForChild("Components"),
	})
end

return OneInTheChamberServer
