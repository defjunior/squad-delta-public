-- Extracted from SquadDelta's guarded remote pipeline.
-- Production manifests, framework glue, player rules and proprietary systems were excluded at the owner's request.
local EventService = {}
EventService.__index = EventService

function EventService.new(options)
    assert(options and options.storage and options.newInstance and options.rateLimiter,
        "storage, newInstance and rateLimiter are required")
    return setmetatable({
        _storage = options.storage,
        _newInstance = options.newInstance,
        _context = options.context or function(player, name)
            return {player = player, userId = player and player.UserId, remoteName = name}
        end,
        _log = options.log or function(message) print(message) end,
        DefaultGuard = options.defaultGuard or function() return false end,
        AutoCreateRemotes = options.autoCreateRemotes ~= false,
        RateLimiter = options.rateLimiter,
        _bindings = {},
    }, EventService)
end

function EventService:_warn(remotePath, message)
    self._log("[EventService] " .. tostring(message) .. " (" .. remotePath .. ")")
end

function EventService:_getRemotesRoot(create)
	local root = self._storage:FindFirstChild("Remotes")
	if not root and create then
		root = self._newInstance("Folder")
		root.Name = "Remotes"
		root.Parent = self._storage
	end
	return root
end

function EventService:_resolveRemote(remotePath, className, create)
	local root = self:_getRemotesRoot(create)
	if not root then return nil end

	local node = root
	local parts = string.split(remotePath, "/")
	for i, part in ipairs(parts) do
		local isLeaf = (i == #parts)
		local child = node:FindFirstChild(part)
		if not child then
			if not create then return nil end
			child = self._newInstance(isLeaf and className or "Folder")
			child.Name = part
			child.Parent = node
			self._log("Created remote " .. child:GetFullName())
		end
		node = child
	end

	local classMismatch = false
	if className and not node:IsA(className) then
		local eventClassCompat = (className == "RemoteEvent" and node:IsA("UnreliableRemoteEvent"))
			or (className == "UnreliableRemoteEvent" and node:IsA("RemoteEvent"))
		if not eventClassCompat then
			classMismatch = true
		end
	end
	if classMismatch then
		self:_warn(remotePath, ("Expected %s but found %s"):format(className, node.ClassName))
		return nil
	end

	return node
end

-- Production player-state globals and game-specific guards were excluded at the owner's request.
function EventService:_makeContext(player, remotePath)
    return self._context(player, remotePath)
end

function EventService:_passesGuards(ctx, guard)
    if not guard then return true end
    local ok, allowed = pcall(guard, ctx)
    return ok and allowed == true
end

function EventService:_applyRateLimit(player, rateKey, rateLimit, scope)
	if not self.RateLimiter then return true end
	local limit = self.RateLimiter:GetLimit(rateKey, rateLimit)
	if not limit then return true end
	return self.RateLimiter:Allow(player, rateKey, limit, scope)
end

function EventService:_runValidate(remotePath, validate, args)
	if not validate then return true end
	local ok, vOk, vErr = pcall(validate, table.unpack(args))
	if not ok then
		self:_warn(remotePath, ("Validate crashed: %s"):format(tostring(vOk)))
		return false, "Bad request"
	end
	if vOk == false then
		return false, vErr or "Bad request"
	end
	return true
end

function EventService:_runMiddleware(remotePath, middleware, ctx)
	if not middleware then return true end
	for _, mw in ipairs(middleware) do
		local ok, mOk, mErr = pcall(mw, ctx)
		if not ok then
			self:_warn(remotePath, ("Middleware crashed: %s"):format(tostring(mOk)))
			return false, "Server error"
		end
		if mOk == false then
			return false, mErr or "Unauthorized"
		end
	end
	return true
end

function EventService:_runHandler(remotePath, handler, ctx, args)
	local ok, a, b, c = pcall(handler, ctx, table.unpack(args))
	if not ok then
		self:_warn(remotePath, ("Handler crashed: %s"):format(tostring(a)))
		return false, "Server error"
	end
	return true, a, b, c
end

function EventService:_bind(remotePath, className, handler, opts)
	self._bindings = self._bindings or {}
	if self._bindings[remotePath] then
		self:_warn(remotePath, "Already registered")
		return
	end

	local remote = self:_resolveRemote(remotePath, className, self.AutoCreateRemotes)
	if not remote then
		self:_warn(remotePath, "Missing remote")
		return
	end

	opts = opts or {}
	local guards = opts.guard or self.DefaultGuard
	local rateKey = opts.rateLimitKey or remotePath
	local rateScope = opts.rateLimitScope or "player"

	local isEventClass = className == "RemoteEvent" or className == "UnreliableRemoteEvent"
	if isEventClass then
		remote.OnServerEvent:Connect(function(player, ...)
			local args = { ... }
			local ctx = self:_makeContext(player, remotePath)

			if not self:_passesGuards(ctx, guards) then return end
			if not self:_applyRateLimit(player, rateKey, opts.rateLimit, rateScope) then return end

			local ok, err = self:_runValidate(remotePath, opts.validate, args)
			if not ok then return end

			ok, err = self:_runMiddleware(remotePath, opts.middleware, ctx)
			if not ok then return end

			self:_runHandler(remotePath, handler, ctx, args)
		end)
	else
		remote.OnServerInvoke = function(player, ...)
			local args = { ... }
			local ctx = self:_makeContext(player, remotePath)

			if not self:_passesGuards(ctx, guards) then
				return false, "Unauthorized"
			end
			if not self:_applyRateLimit(player, rateKey, opts.rateLimit, rateScope) then
				return false, "Rate limited"
			end

			local ok, err = self:_runValidate(remotePath, opts.validate, args)
			if not ok then
				return false, err
			end

			ok, err = self:_runMiddleware(remotePath, opts.middleware, ctx)
			if not ok then
				return false, err
			end

			local okHandler, a, b, c = self:_runHandler(remotePath, handler, ctx, args)
			if not okHandler then
				return false, a
			end
			return a, b, c
		end
	end

	self._bindings[remotePath] = true
end

function EventService:RegisterEvent(remotePath, handler, opts)
	self:_bind(remotePath, "RemoteEvent", handler, opts)
end

function EventService:RegisterFunction(remotePath, handler, opts)
	self:_bind(remotePath, "RemoteFunction", handler, opts)
end

function EventService:EnsureRemote(remotePath, className)
	return self:_resolveRemote(remotePath, className, true)
end

function EventService:EnsureRemotes(list)
	if type(list) ~= "table" then
		return
	end
	for _, entry in ipairs(list) do
		local path = entry.path or entry[1]
		local className = entry.className or entry[2]
		if path and className then
			self:EnsureRemote(path, className)
		end
	end
end

function EventService:FireClient(player, remotePath, ...)
	local remote = self:_resolveRemote(remotePath, "RemoteEvent", self.AutoCreateRemotes)
	if not remote then
		self:_warn(remotePath, "Missing remote")
		return
	end
	remote:FireClient(player, ...)
end

function EventService:FireAll(remotePath, ...)
    local remote = self:_resolveRemote(remotePath, "RemoteEvent", self.AutoCreateRemotes)
    if not remote then
        self:_warn(remotePath, "Missing remote")
        return
    end
    self._log("FireAll -> " .. remotePath)
    remote:FireAllClients(...)
end


return EventService
