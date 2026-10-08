local FPSGameController = {}
FPSGameController.Name = "FPSGameController"
FPSGameController._started = false

function FPSGameController:Start()
	if self._started then
		return
	end
	self._started = true

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Framework = require(ReplicatedStorage.Modules.Framework)
	local Logger = require(ReplicatedStorage.Modules.Logger)
	local GameObjects = ReplicatedStorage:WaitForChild("GameObjects")
	local GameInstanceService = Framework.GetService("MatchInstanceService")
	local GameService = Framework.GetService("GameService")
	local MatchmakingData = require(ReplicatedStorage.Modules.Data.MatchmakingData)

	local function getDefaultMap()
		local serverType = _G.ServerType or MatchmakingData.DefaultServerType or "Casual"
		local info = MatchmakingData.ServerTypes and MatchmakingData.ServerTypes[serverType]
		local pool = info and info.mapPool
		return pool and pool[1]
	end

	local function clearMapSelection()
		local defaultMap = getDefaultMap() or ""
		if GameObjects.Map1 then
			GameObjects.Map1.Value = defaultMap
		end
		if GameObjects.Map2 then
			GameObjects.Map2.Value = defaultMap
		end
		if GameObjects.Map1Override then
			GameObjects.Map1Override.Value = defaultMap
		end
		if GameObjects.Map2Override then
			GameObjects.Map2Override.Value = defaultMap
		end
	end

	local function updateStatus(statusText, joinInfo)
		if GameObjects.Status then
			GameObjects.Status.Value = statusText
		end
		if GameObjects.JoinInfo then
			GameObjects.JoinInfo.Value = joinInfo or ""
		end
	end

	local function updateModeDisplay(modeName)
		if not modeName then
			return
		end
		if GameObjects.GamemodeName then
			GameObjects.GamemodeName.Value = modeName
		end
		if GameObjects.Gamemode then
			GameObjects.Gamemode.Value = modeName
		end
	end

	local function startMatchInstance()
		clearMapSelection()
		local warmupText = "Warmup Lobby"
		Logger.Info("[FPSGameController]", "MatchInstance path active; initiating warmup display.")
		updateStatus("Match Instance", "Warmup is running")
		updateModeDisplay("Defusal")
		if GameService and GameService.ApplyLighting then
			GameService:ApplyLighting("Match")
		end
		if GameObjects.CanChooseAbilities then
			GameObjects.CanChooseAbilities.Value = true
		end
		if ReplicatedStorage.Remotes.Server:FindFirstChild("ForceTraitLoad") then
			ReplicatedStorage.Remotes.Server.ForceTraitLoad:FireAllClients()
		end
		if GameObjects.JoinInfo then
			GameObjects.JoinInfo.Value = warmupText
		end
	end

	local function startHub()
		clearMapSelection()
		updateStatus("Hub Server", "Matchmaking queue is open")
		updateModeDisplay("Defusal")
		if GameObjects.CanChooseAbilities then
			GameObjects.CanChooseAbilities.Value = false
		end
		Logger.Info("[FPSGameController]", "Hub path active; waiting on matchmaking.")
		
	end

	if _G.ServerRole == "MatchInstance" then
		startMatchInstance()
	else
		startHub()
	end

	return FPSGameController
end

return FPSGameController
