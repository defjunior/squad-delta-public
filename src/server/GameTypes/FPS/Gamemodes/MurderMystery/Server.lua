local MurderMysteryConfig = require(script.Parent.MurderMysteryConfig)
local ModeServer = require(script.Parent.Parent.Common.ModeServer)

local MurderMysteryServer = {
	ModeId = "GameTypes/FPS/Gamemodes/MurderMystery/Server",
}

function MurderMysteryServer.new(ctx, config)
	return ModeServer.new(ctx, config or MurderMysteryConfig, {
		modeId = MurderMysteryServer.ModeId,
		componentsFolder = script.Parent:WaitForChild("Components"),
	})
end

return MurderMysteryServer
