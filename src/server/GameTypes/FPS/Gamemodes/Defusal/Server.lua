local DefusalConfig = require(script.Parent.DefusalConfig)
local ModeServer = require(script.Parent.Parent.Common.ModeServer)

local DefusalServer = {
	ModeId = "GameTypes/FPS/Gamemodes/Defusal/Server",
}

function DefusalServer.new(ctx, config)
	return ModeServer.new(ctx, config or DefusalConfig, {
		modeId = DefusalServer.ModeId,
		componentsFolder = script.Parent:WaitForChild("Components"),
	})
end

return DefusalServer
