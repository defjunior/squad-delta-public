-- ToolController.lua (ModuleScript)
-- Extracted from legacy viewmodel script: tool system + backpack wiring + input routing.
-- Keeps _G.Tools / _G.Equipped / _G.Tool compatibility, but isolates into a controller.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local Framework = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Framework"))
local Class = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Class"))
local Logger = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Logger"))
local ToolController = {}
ToolController.__index = ToolController
local ToolBase
local LOG_TAG = "ToolController"
local STARTUP_WARN_AFTER_SECONDS = 8
local STARTUP_WARN_EVERY_SECONDS = 12
local STARTUP_WAIT_STEP = 0.1
local CHILD_WAIT_TIMEOUT = 5
local STARTUP_DEPENDENCY_TIMEOUT_SECONDS = 25

-- ===== Legacy globals preserved =====
-- _G.Tools: [string] -> tool instance
-- _G.Tool: base Tool class
-- _G.Equipped: tool instance or nil
-- _G.InventoryForceUpdate: optional callback (legacy)
-- _G.GetAbilityData: RemoteFunction (legacy)
-- _G.FreezeTime: folder/value (legacy)
-- _G.WeaponData: ModuleScript (legacy)

local function waitForChildWithTimeout(parent: Instance?, childName: string, timeoutSeconds: number?): Instance?
	if not parent then
		return nil
	end
	local existing = parent:FindFirstChild(childName)
	if existing then
		return existing
	end
	local timeout = tonumber(timeoutSeconds) or CHILD_WAIT_TIMEOUT
	if timeout <= 0 then
		return nil
	end
	return parent:WaitForChild(childName, timeout)
end

local function parseBool(value)
	if typeof(value) == "boolean" then
		return value
	end
	if typeof(value) == "string" then
		return value == "true" or value == "True"
	end
	if typeof(value) == "number" then
		return value ~= 0
	end
	return false
end

local function isPlayerDowned()
	local pd = rawget(_G, "PlayerData")
	local isDownedValue = pd and pd:FindFirstChild("IsDowned")
	return parseBool(isDownedValue and isDownedValue.Value)
end

local function getReferenceModelById(id: string): Instance?
	local referenceModels = ReplicatedStorage:FindFirstChild("ReferenceModels")
	if not referenceModels then
		return nil
	end
	-- Legacy script does: FoundReference = ReplicatedStorage.ReferenceModels[NewID.Name]
	-- then waits until it exists.
	local ref = referenceModels:FindFirstChild(id)
	return ref
end

local function getReferenceTool(refContainer: Instance): Instance?
	if not refContainer then
		return nil
	end

	for _, child in ipairs(refContainer:GetChildren()) do
		if child:FindFirstChild("ToModel") and child:FindFirstChild("ToCurrentTool") then
			return child
		end
	end

	for _, child in ipairs(refContainer:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end

	return nil
end

local function resolveWeaponTypeFromRefName(refName: string): string
	local t = Framework.GetWeaponOrderType(refName) or "Tool"
	if t == "Special" then
		if refName == "PDA" then
			t = "PDA"
		elseif refName == "UHE-4" or refName == "UHE4" then
			t = "UHE-4"
		end
	elseif t == "UHE4" then
		t = "UHE-4"
	end

	if refName == "PDA" then
		t = "PDA"
	elseif refName == "UHE-4" or refName == "UHE4" then
		t = "UHE-4"
	end

	if t == "Primary" or t == "Secondary" then
		return "Gun"
	elseif t == "Tertiary" then
		return "Knife"
	end
	return t
end

local function createFallbackTool(toolType: string, ref: Instance, reason: string)
	local fallback = ToolBase.New(toolType, ref)
	fallback.Name = ref.Name
	fallback.ID = ref.Parent and ref.Parent.Name or ref.Name
	fallback.Initialized = true
	fallback._vmFallback = true
	fallback._vmFallbackReason = reason
	fallback.Tool = (ref:FindFirstChild("ToCurrentTool") and ref.ToCurrentTool.Value) or ref

	function fallback:Initialize()
		-- Fallback tool intentionally does not load a VM.
	end

	function fallback:Equip()
		self.Equipping = false
		self.Equipped = true
		_G.Equipped = self
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local serverFolder = remotes and remotes:FindFirstChild("Server")
		local inventoryFolder = serverFolder and serverFolder:FindFirstChild("Inventory")
		local equipRemote = inventoryFolder and inventoryFolder:FindFirstChild("EquipItem")
		if equipRemote and equipRemote:IsA("RemoteEvent") then
			equipRemote:FireServer(self.ID)
		end
		warn(("[ToolController] VM unavailable for %s (%s); fallback equip only."):format(self.Name, tostring(self._vmFallbackReason)))
	end

	function fallback:Unequip()
		self.Equipped = false
		self.Equipping = false
		if _G.Equipped == self then
			_G.Equipped = nil
		end
	end

	return fallback
end

-- ===== Tool base class (legacy) =====
ToolBase = Class:Extend()
ToolBase.__index = ToolBase

function ToolBase.New(Type: string, Model: Instance)
	local newTool = {}
	setmetatable(newTool, ToolBase)

	newTool.Equipped = false
	newTool.Equipping = false
	newTool.Initialized = false
	newTool.Model = Model
	newTool.Type = Type
	newTool.Name = Model.Parent.Name
	newTool.ID = Model.Parent.Name

	return newTool
end

-- ===== Controller construction =====

function ToolController.new()
	local self = setmetatable({}, ToolController)

	self._conns = {}
	self._clients = {} :: {[string]: any}
	self._createAttempts = {} :: {[string]: number}
	self._clientsInitialized = false
	self._bootstrapStarted = false
	self._backpackWired = false
	self._startupReady = false

	self._backpackFolder = nil :: Folder?
	self._started = false
	self._reconcileAccumulator = 0

	return self
end

function ToolController:_connect(signal: RBXScriptSignal, fn)
	local c = signal:Connect(fn)
	table.insert(self._conns, c)
	return c
end

function ToolController:_disconnectAll()
	for _, c in ipairs(self._conns) do
		c:Disconnect()
	end
	table.clear(self._conns)
	self._backpackWired = false
end

function ToolController:_initGlobals()
	-- Legacy globals required by other scripts
	_G.Tools = _G.Tools or {}
	_G.Tool = ToolBase
	_G.Equipped = _G.Equipped or nil

	-- These were locals in the old script, but other code may expect access.
	local modules = waitForChildWithTimeout(ReplicatedStorage, "Modules", CHILD_WAIT_TIMEOUT)
	local dataFolder = modules and waitForChildWithTimeout(modules, "Data", CHILD_WAIT_TIMEOUT)
	local gameObjects = waitForChildWithTimeout(ReplicatedStorage, "GameObjects", CHILD_WAIT_TIMEOUT)
	local remotes = waitForChildWithTimeout(ReplicatedStorage, "Remotes", CHILD_WAIT_TIMEOUT)
	local clientRemotes = remotes and waitForChildWithTimeout(remotes, "Client", CHILD_WAIT_TIMEOUT)

	_G.WeaponData = _G.WeaponData or (dataFolder and waitForChildWithTimeout(dataFolder, "WeaponData", CHILD_WAIT_TIMEOUT))
	_G.FreezeTime = _G.FreezeTime or (gameObjects and waitForChildWithTimeout(gameObjects, "FreezeTime", CHILD_WAIT_TIMEOUT))
	_G.GetAbilityData = _G.GetAbilityData or (clientRemotes and waitForChildWithTimeout(clientRemotes, "GetAbilityData", CHILD_WAIT_TIMEOUT))

	if not _G.WeaponData then
		Logger.Warn(LOG_TAG, "WeaponData was not available during startup bootstrap")
	end
	if not _G.FreezeTime then
		Logger.Warn(LOG_TAG, "GameObjects.FreezeTime was not available during startup bootstrap")
	end
	if not _G.GetAbilityData then
		Logger.Warn(LOG_TAG, "Remotes.Client.GetAbilityData was not available during startup bootstrap")
	end
end

function ToolController:_waitForDependency(label: string, resolver, timeoutSeconds: number?)
	local startedAt = os.clock()
	local nextWarnAt = STARTUP_WARN_AFTER_SECONDS
	local timeoutAt = nil
	local timeout = tonumber(timeoutSeconds) or STARTUP_DEPENDENCY_TIMEOUT_SECONDS
	if timeout > 0 then
		timeoutAt = startedAt + timeout
	end

	while self._started do
		local value = resolver()
		if value then
			local elapsed = os.clock() - startedAt
			if elapsed >= 0.25 then
				Logger.Info(LOG_TAG, "%s became ready after %.2fs", label, elapsed)
			end
			return value
		end

		local elapsed = os.clock() - startedAt
		if elapsed >= nextWarnAt then
			Logger.Warn(LOG_TAG, "Still waiting for %s (%.1fs elapsed)", label, elapsed)
			nextWarnAt = elapsed + STARTUP_WARN_EVERY_SECONDS
		end

		if timeoutAt and os.clock() >= timeoutAt then
			Logger.Error(LOG_TAG, "Timed out waiting for %s after %.1fs", label, elapsed)
			return nil
		end

		task.wait(STARTUP_WAIT_STEP)
	end

	return nil
end

function ToolController:_loadClients(vmClientsFolder: Instance)
	-- clientsFolder = script.Clients (from original LocalScript)
	self._clients = {}
	for _, m in ipairs(vmClientsFolder:GetChildren()) do
		if m:IsA("ModuleScript") then
			self._clients[m.Name] = require(m).Init({
				Tool = _G.Tool,
				Framework = _G.Framework,
				SavedData = _G.SavedData,
				PlayerData = _G.PlayerData,
				Player = _G.Player,
				ViewmodelController = _G.ViewmodelController,
			})
		end
	end
	self._clientsInitialized = true
	Logger.Info(LOG_TAG, "VM clients initialized (loaded=%d)", #vmClientsFolder:GetChildren())
end

function ToolController:_bootstrap()
	if self._bootstrapStarted then
		return self._startupReady, self._startupReady and nil or "bootstrap already attempted"
	end
	self._bootstrapStarted = true

	Logger.Info(LOG_TAG, "Bootstrap begin")

	local loadedFlag = self:_waitForDependency("_G.Loaded", function()
		return _G and _G.Loaded == true
	end, STARTUP_DEPENDENCY_TIMEOUT_SECONDS)
	if not (self._started and loadedFlag) then
		return false, "timed out waiting for _G.Loaded"
	end

	local vmController = self:_waitForDependency("_G.ViewmodelController", function()
		return _G and _G.ViewmodelController
	end, STARTUP_DEPENDENCY_TIMEOUT_SECONDS)
	if not (self._started and vmController) then
		return false, "timed out waiting for _G.ViewmodelController"
	end

	local clientRoot = ReplicatedFirst:FindFirstChild("Client")
	local vmClientsFolder = clientRoot and clientRoot:FindFirstChild("VMControllers")
	if not vmClientsFolder then
		Logger.Warn(LOG_TAG, "ReplicatedFirst.Client.VMControllers missing; continuing with fallback-only tools")
		self._clientsInitialized = true
	else
		self:_loadClients(vmClientsFolder)
	end

	local backpackFolder = self:_waitForDependency(("Backpacks/%s"):format(tostring(LocalPlayer.UserId)), function()
		local backpacks = ReplicatedStorage:FindFirstChild("Backpacks")
		return backpacks and backpacks:FindFirstChild(tostring(LocalPlayer.UserId))
	end, STARTUP_DEPENDENCY_TIMEOUT_SECONDS)
	if not (self._started and backpackFolder) then
		return false, ("timed out waiting for Backpacks/%s"):format(tostring(LocalPlayer.UserId))
	end

	self._backpackFolder = backpackFolder
	self:_wireBackpackFolder(backpackFolder)
	self:_reconcileBackpackState()
	self._startupReady = true
	Logger.Info(LOG_TAG, "Bootstrap complete; runtime ready")
	return true
end

function ToolController:_routeInput()
	self:_connect(UserInputService.InputBegan, function(input, inputSank)
		if isPlayerDowned() then
			return
		end
		local eq = rawget(_G, "Equipped")
		if eq then
			if eq.HandleInputBegan then
				eq:HandleInputBegan(input, inputSank)
			end
		end
	end)

	self:_connect(UserInputService.InputEnded, function(input, inputSank)
		if isPlayerDowned() then
			return
		end
		local eq = rawget(_G, "Equipped")
		if eq then
			if eq.HandleInputEnded then
				eq:HandleInputEnded(input, inputSank)
			end
		end
	end)
end

function ToolController:_createToolFromBackpackId(idName: string)
	-- idName is the child instance name inside ReplicatedStorage.Backpacks[userId]
	if _G.Tools and _G.Tools[idName] then
		self._createAttempts[idName] = nil
		return
	end
	if not self._clientsInitialized then
		local attempts = (self._createAttempts[idName] or 0) + 1
		self._createAttempts[idName] = attempts
		task.delay(0.25, function()
			if not self._started then
				return
			end
			local folder = self._backpackFolder
			if folder and folder:FindFirstChild(idName) and (not _G.Tools or not _G.Tools[idName]) then
				self:_createToolFromBackpackId(idName)
			end
		end)
		if attempts % 40 == 0 then
			Logger.Warn(LOG_TAG, "Still waiting for VM clients before creating tool %s (%d attempts)", idName, attempts)
		end
		return
	end

	local refContainer = getReferenceModelById(idName)
	if not refContainer then
		local attempts = (self._createAttempts[idName] or 0) + 1
		self._createAttempts[idName] = attempts
		task.delay(0.25, function()
			if not self._started then
				return
			end
			if _G.Tools and _G.Tools[idName] then
				return
			end
			local folder = self._backpackFolder
			if folder and folder:FindFirstChild(idName) then
				self:_createToolFromBackpackId(idName)
			end
		end)
		if attempts % 40 == 0 then
			warn(("[ToolController] Missing ReferenceModels entry for %s after %d attempts"):format(idName, attempts))
		end
		return
	end

	local ref = getReferenceTool(refContainer)
	if not ref then
		local attempts = (self._createAttempts[idName] or 0) + 1
		self._createAttempts[idName] = attempts
		task.delay(0.25, function()
			if not self._started then
				return
			end
			local folder = self._backpackFolder
			if folder and folder:FindFirstChild(idName) and (not _G.Tools or not _G.Tools[idName]) then
				self:_createToolFromBackpackId(idName)
			end
		end)
		if attempts % 40 == 0 then
			warn(("[ToolController] No tool object found in ReferenceModels entry for %s after %d attempts"):format(idName, attempts))
		end
		return
	end

	local toolType = resolveWeaponTypeFromRefName(ref.Name)
	local clientCtor = self._clients[toolType]
	local newTool = nil
	if not clientCtor or not clientCtor.New then
		newTool = createFallbackTool(toolType, ref, "missing VM controller")
	else
		newTool = clientCtor.New(ref)
	end
	newTool.Name = ref.Name

	_G.Tools[idName] = newTool
	self._createAttempts[idName] = nil

	-- Legacy: Initialize immediately
	if newTool.Initialize then
		newTool:Initialize()
	end

	-- Legacy dupe sweep logic (kept; note: Dupe variable was global-buggy)
	do
		for _, v in pairs(_G.Tools) do
			local ID = Framework.GetWeaponOrderType(v.Name)
			local Dupe = nil
			for _, l in pairs(_G.Tools) do
				if Framework.GetWeaponOrderType(l.Name) == ID
					and Framework.GetWeaponOrderType(l.Name) ~= "Grenade"
					and l.ID ~= v.ID
				then
					Dupe = l
				end
			end
			if Dupe then
				-- legacy commented out DropItem; preserve behavior (no-op)
				-- ReplicatedStorage.Remotes.Client.DropItem:InvokeServer(Dupe.ID)
			end
		end
	end

	if _G.Tools[idName] then
		print("d_vw_New Weapon : " .. tostring(_G.Tools[idName].Name))
	end
	self:_notifyViewmodelToolsUpdated()
end

function ToolController:_removeToolByBackpackId(idName: string, reason: string?)
	local t = _G.Tools[idName]
	if t then
		local active = rawget(_G, "Equipped")
		local pending = rawget(_G, "EquippingItem")
		local runtimeTool = t.Tool
		local isInCharacter = runtimeTool and LocalPlayer.Character and runtimeTool.Parent == LocalPlayer.Character
		if (isInCharacter or active == t or pending == t) and reason ~= "Consumed" then
			t._pendingBackpackRemoval = true
			Logger.Info(LOG_TAG, "Deferring backpack removal for active tool %s (%s)", tostring(t.Name), tostring(idName))
			task.delay(2, function()
				if not self._started then
					return
				end
				local current = _G.Tools and _G.Tools[idName]
				if not current or current ~= t then
					return
				end
				local nowActive = rawget(_G, "Equipped")
				local nowPending = rawget(_G, "EquippingItem")
				local currentRuntimeTool = current and current.Tool
				local stillInCharacter = currentRuntimeTool and LocalPlayer.Character and currentRuntimeTool.Parent == LocalPlayer.Character
				if nowActive == t or nowPending == t or stillInCharacter then
					return
				end
				if current._pendingBackpackRemoval then
					current._pendingBackpackRemoval = nil
					self:_removeToolByBackpackId(idName)
				end
			end)
			return
		end
		if t.Unequip then
			t:Unequip({
				localOnly = true,
				reason = "BackpackRemoved",
			})
		end
		print("d_vw_Weapon Lost : " .. tostring(t.Name))
		task.wait()
		_G.Tools[idName] = nil
		if _G.InventoryForceUpdate then
			_G.InventoryForceUpdate()
		end
	end
	if _G.Tools and _G.Tools[idName] and _G.Tools[idName]._pendingBackpackRemoval then
		_G.Tools[idName]._pendingBackpackRemoval = nil
	end
	self._createAttempts[idName] = nil
	self:_notifyViewmodelToolsUpdated()
end

function ToolController:_wireBackpackFolder(folder: Folder)
	if self._backpackWired then
		return
	end
	self._backpackWired = true
	Logger.Info(LOG_TAG, "Backpack folder wired: %s", folder:GetFullName())

	self:_connect(folder.ChildAdded, function(newId: Instance)
		self:_createToolFromBackpackId(newId.Name)
	end)

	self:_connect(folder.ChildRemoved, function(oldId: Instance)
		self:_removeToolByBackpackId(oldId.Name)
	end)
end

function ToolController:_wireServerInventorySignals()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes") or waitForChildWithTimeout(ReplicatedStorage, "Remotes", CHILD_WAIT_TIMEOUT)
	if not remotes then
		Logger.Warn(LOG_TAG, "Remotes not found; UnequipItem bridge not wired")
		return
	end

	local serverFolder = remotes:FindFirstChild("Server") or waitForChildWithTimeout(remotes, "Server", CHILD_WAIT_TIMEOUT)
	if not serverFolder then
		Logger.Warn(LOG_TAG, "Remotes.Server not found; UnequipItem bridge not wired")
		return
	end

	local inventoryFolder = serverFolder:FindFirstChild("Inventory")
	if not inventoryFolder then
		Logger.Warn(LOG_TAG, "Remotes.Server.Inventory not found; UnequipItem bridge not wired")
		return
	end

	local unequipRemote = inventoryFolder:FindFirstChild("UnequipItem")
	if unequipRemote and unequipRemote:IsA("RemoteEvent") then
		self:_connect(unequipRemote.OnClientEvent, function(itemId: string, reason: string?)
			if not itemId or itemId == "" then
				return
			end
			self:_removeToolByBackpackId(itemId, reason)
		end)
	end
end

function ToolController:_notifyViewmodelToolsUpdated()
	local vm = rawget(_G, "ViewmodelController")
	if vm and typeof(vm.RequestViewmodelPropagation) == "function" then
		vm:RequestViewmodelPropagation()
	end
	if vm and typeof(vm.PropagateViewmodels) == "function" then
		vm:PropagateViewmodels()
	elseif vm and typeof(vm.UpdateLoadedTools) == "function" then
		vm:UpdateLoadedTools()
	end
	local inventoryUpdate = rawget(_G, "InventoryForceUpdate")
	if type(inventoryUpdate) == "function" then
		inventoryUpdate()
	end
end

function ToolController:_reconcileBackpackState()
	if not self._backpackFolder then
		return
	end

	local expectedIds = {}
	for _, child in ipairs(self._backpackFolder:GetChildren()) do
		expectedIds[child.Name] = true
		if not (_G.Tools and _G.Tools[child.Name]) then
			self:_createToolFromBackpackId(child.Name)
		end
	end

	local staleIds = {}
	if type(_G.Tools) == "table" then
		for id in pairs(_G.Tools) do
			if not expectedIds[id] then
				table.insert(staleIds, id)
			end
		end
	end

	for _, id in ipairs(staleIds) do
		self:_removeToolByBackpackId(id)
	end
end

function ToolController:Start()
	if self._started then return end
	self._started = true
	Logger.Info(LOG_TAG, "Start begin")

	self:_initGlobals()
	self:_routeInput()
	self:_wireServerInventorySignals()
	local bootstrapOk, bootstrapErr = self:_bootstrap()
	if not bootstrapOk then
		self._started = false
		self._bootstrapStarted = false
		self._startupReady = false
		self:_disconnectAll()
		error(bootstrapErr or "tool bootstrap failed", 0)
	end

	-- Safety net: server/client ordering can miss add/remove races on spawn.
	self:_connect(RunService.Heartbeat, function(dt)
		self._reconcileAccumulator += dt
		if self._reconcileAccumulator < 0.5 then
			return
		end
		self._reconcileAccumulator = 0
		self:_reconcileBackpackState()
	end)
end

function ToolController:Stop()
	if not self._started then return end
	self._started = false
	self:_disconnectAll()
	self._bootstrapStarted = false
	self._startupReady = false
	self._backpackFolder = nil
	Logger.Info(LOG_TAG, "Stopped")
end

return ToolController
