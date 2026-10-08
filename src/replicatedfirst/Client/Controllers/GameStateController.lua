local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BaseController = require(script.Parent.Parent.Modules.BaseController)

local GameObjects = ReplicatedStorage:WaitForChild("GameObjects")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerLikeStorage = ReplicatedStorage:WaitForChild("PlayerLikeStorage")

local GameStateController = BaseController.new(script)
GameStateController.Name = "GameStateController"

local function boolFromValue(val)
	if type(val) == "boolean" then
		return val
	end
	if val == nil then
		return false
	end
	local s = tostring(val):lower()
	return s == "true" or s == "1"
end

local function copyTable(tbl)
	local out = {}
	for k, v in pairs(tbl) do
		out[k] = v
	end
	return out
end

function GameStateController:Init()
	self._event = Instance.new("BindableEvent")
	self._state = {
		statusText = "",
		timer = 0,
		winBanner = nil,
		alliesAlive = 0,
		enemiesAlive = 0,
		lastUpdate = tick(),
		freezeTime = false,
	}
	self.LocalPlayer = Players.LocalPlayer
	self.LocalTeamName = self.LocalPlayer and self.LocalPlayer.Team and self.LocalPlayer.Team.Name or nil
end

local function getTeamNameFromPlayerData(folder)
	if not folder then
		return nil
	end
	local teamValue = folder:FindFirstChild("Team")
	if teamValue then
		return teamValue.Value
	end
	return nil
end

local function isAliveFromPlayerData(folder)
	if not folder then
		return false
	end
	local aliveVal = folder:FindFirstChild("IsAlive")
	if aliveVal then
		return boolFromValue(aliveVal.Value)
	end
	return false
end

function GameStateController:_setState(partial)
	for k, v in pairs(partial) do
		self._state[k] = v
	end
	self._state.lastUpdate = tick()
	self._event:Fire(copyTable(self._state))
end

function GameStateController:_recalculateAliveCounts()
	local allies = 0
	local enemies = 0
	self.LocalTeamName = self.LocalPlayer and self.LocalPlayer.Team and self.LocalPlayer.Team.Name or self.LocalTeamName

	for _, folder in pairs(PlayerLikeStorage:GetChildren()) do
		if folder:IsA("Folder") then
			local teamName = getTeamNameFromPlayerData(folder)
			local alive = isAliveFromPlayerData(folder)
			if teamName and alive then
				if self.LocalTeamName and teamName == self.LocalTeamName then
					allies += 1
				else
					enemies += 1
				end
			end
		end
	end

	self:_setState({
		alliesAlive = allies,
		enemiesAlive = enemies,
	})
end

function GameStateController:_trackTimer()
	local timerValue = GameObjects:FindFirstChild("Timer")
	if not timerValue then
		return
	end
	self:Connect(timerValue:GetPropertyChangedSignal("Value"), function()
		self:_setState({ timer = timerValue.Value })
	end)
	self:_setState({ timer = timerValue.Value })
end

function GameStateController:_trackStatus()
	local statusValue = GameObjects:FindFirstChild("Status")
	if not statusValue then
		return
	end
	self:Connect(statusValue:GetPropertyChangedSignal("Value"), function()
		self:_setState({ statusText = statusValue.Value })
	end)
	self:_setState({ statusText = statusValue.Value })
end

function GameStateController:_trackWinBanner()
	if Remotes and Remotes.Server and Remotes.Server.ShowWin then
		self:Connect(Remotes.Server.ShowWin.OnClientEvent, function(line1, line2, duration)
			self:_setState({
				winBanner = {
					title = line1,
					subtitle = line2,
					duration = duration,
					at = tick(),
				},
			})
		end)
	end
	if Remotes and Remotes.Server and Remotes.Server.PersonalSystemMessage then
		self:Connect(Remotes.Server.PersonalSystemMessage.OnClientEvent, function(message, color)
			self:_setState({ statusText = message })
		end)
	end
end

function GameStateController:_watchPlayers()
	self:_recalculateAliveCounts()
	self:Connect(Players.PlayerAdded, function()
		self:_recalculateAliveCounts()
	end)
	self:Connect(Players.PlayerRemoving, function()
		self:_recalculateAliveCounts()
	end)
	self._heartbeat = self:Connect(RunService.Heartbeat, function()
		-- update periodically to catch replicated PlayerData changes
		self:_recalculateAliveCounts()
	end)
end

function GameStateController:Start()
	self:_trackTimer()
	self:_trackStatus()
	self:_trackWinBanner()
	self:_watchPlayers()
	self:_trackFreezeTime()
end

function GameStateController:_trackFreezeTime()
	local freezeValue = GameObjects:FindFirstChild("FreezeTime")
	if not freezeValue then
		return
	end
	self:Connect(freezeValue:GetPropertyChangedSignal("Value"), function()
		self:_setState({ freezeTime = freezeValue.Value })
	end)
	self:_setState({ freezeTime = freezeValue.Value })
end

function GameStateController:GetState()
	return copyTable(self._state)
end

function GameStateController:OnChanged(callback)
	if type(callback) ~= "function" then
		return
	end
	return self._event.Event:Connect(callback)
end

return GameStateController
