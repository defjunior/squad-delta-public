local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Framework = require(ReplicatedStorage.Modules.Framework)

-- Compatibility wrapper for legacy modules referencing GameController;
-- the new implementation lives in Services/GameService.lua.
return Framework.GetService("GameService")
