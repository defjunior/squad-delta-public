local ServerScriptService = game:GetService("ServerScriptService")

local ComponentRegistry = require(ServerScriptService.Classes.PlayerLike.Components.Registry)

local PlayerComponentService = {}
PlayerComponentService.Name = "PlayerComponentService"

function PlayerComponentService:Start()
	local componentsFolder = ServerScriptService:FindFirstChild("Classes")
	if not componentsFolder then
		warn("[PlayerComponentService] Missing Classes folder; player components not registered")
		return
	end
	local playerLikeFolder = componentsFolder:FindFirstChild("PlayerLike")
	if not playerLikeFolder then
		warn("[PlayerComponentService] Missing PlayerLike folder; player components not registered")
		return
	end
	local components = playerLikeFolder:FindFirstChild("Components")
	if not components then
		warn("[PlayerComponentService] Missing Components folder; player components not registered")
		return
	end

	for _, moduleScript in ipairs(components:GetChildren()) do
		if not moduleScript:IsA("ModuleScript") then
			continue
		end
		if moduleScript.Name == "Registry" then
			continue
		end
		local ok, result = pcall(require, moduleScript)
		if not ok then
			warn(("[PlayerComponentService] Failed to require %s: %s"):format(moduleScript.Name, tostring(result)))
		else
			ComponentRegistry:Register(moduleScript.Name, result)
		end
	end
end

return PlayerComponentService
