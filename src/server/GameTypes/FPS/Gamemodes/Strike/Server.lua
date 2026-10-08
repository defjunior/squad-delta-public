local StrikeConfig = require(script.Parent.StrikeConfig)
local ModeServer = require(script.Parent.Parent.Common.ModeServer)

local StrikeServer = {
	ModeId = "GameTypes/FPS/Gamemodes/Strike/Server",
}

function StrikeServer.new(ctx, config)
	return ModeServer.new(ctx, config or StrikeConfig, {
		modeId = StrikeServer.ModeId,
		componentsFolder = script.Parent:WaitForChild("Components"),
	})
end

return StrikeServer
