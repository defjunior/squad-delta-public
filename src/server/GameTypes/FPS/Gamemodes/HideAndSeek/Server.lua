local HideAndSeekConfig = require(script.Parent.HideAndSeekConfig)
local ModeServer = require(script.Parent.Parent.Common.ModeServer)

local HideAndSeekServer = {
	ModeId = "GameTypes/FPS/Gamemodes/HideAndSeek/Server",
}

function HideAndSeekServer.new(ctx, config)
	return ModeServer.new(ctx, config or HideAndSeekConfig, {
		modeId = HideAndSeekServer.ModeId,
		componentsFolder = script.Parent:WaitForChild("Components"),
	})
end

return HideAndSeekServer
