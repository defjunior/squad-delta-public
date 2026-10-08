-- Extracted from SquadDelta's rate-limiting plumbing.
-- Production endpoint names and security tuning were excluded at the owner's request.
local RateLimiterService = {}
RateLimiterService.__index = RateLimiterService

function RateLimiterService.new(options)
    assert(options and options.defaultLimit, "Provide a default limit for your application")
    return setmetatable({
        Default = options.defaultLimit,
        Limits = options.limits or {},
        _clock = options.clock or os.clock,
        _buckets = {player = {}, global = {}},
    }, RateLimiterService)
end

function RateLimiterService:RemovePlayer(player)
    self._buckets.player[player.UserId] = nil
end

function RateLimiterService:_normalize(limit)
	if not limit then return nil end
	if limit.maxCalls or limit.perSeconds then
		return {
			mode = "window",
			maxCalls = limit.maxCalls,
			perSeconds = limit.perSeconds,
		}
	end

	local capacity = limit.capacity or limit.burst
	local refill = limit.refillPerSec or limit.rate
	if capacity or refill then
		return {
			mode = "token",
			capacity = capacity or 1,
			refillPerSec = refill or 1,
		}
	end

	return nil
end

function RateLimiterService:GetLimit(key, override)
	if override then return override end
	return self.Limits[key] or self.Default
end

function RateLimiterService:_getBucket(scope, userId, key, limit)
	local scopeTable = self._buckets[scope] or self._buckets.player
	local u = scopeTable[userId]
	if not u then
		u = {}
		scopeTable[userId] = u
	end

	local b = u[key]
	if not b or b.mode ~= limit.mode then
		b = { mode = limit.mode }
		if limit.mode == "token" then
			b.tokens = limit.capacity
			b.last = self._clock()
		else
			b.times = {}
			b.head = 1
		end
		u[key] = b
	end
	return b
end

function RateLimiterService:_allowToken(bucket, limit, now)
	local dt = now - bucket.last
	bucket.last = now
	bucket.tokens = math.min(limit.capacity, bucket.tokens + dt * limit.refillPerSec)

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiterService:_allowWindow(bucket, limit, now)
	local times = bucket.times
	local head = bucket.head
	local n = #times

	while head <= n and (now - times[head]) > limit.perSeconds do
		head += 1
	end

	local count = n - head + 1
	if count >= limit.maxCalls then
		bucket.head = head
		return false
	end

	times[n + 1] = now
	bucket.head = head

	if head > 25 then
		local compact = {}
		for i = head, #times do
			compact[#compact + 1] = times[i]
		end
		bucket.times = compact
		bucket.head = 1
	end

	return true
end

function RateLimiterService:Allow(plr, key, limitOverride, scope)
	if not key then return true end

	local scopeKey = scope == "global" and "global" or "player"
	local userId
	if scopeKey == "global" then
		userId = 0
	else
		if not plr then return false end
		userId = plr.UserId
	end

	local rawLimit = limitOverride or self.Limits[key] or self.Default
	local limit = self:_normalize(rawLimit)
	if not limit then return true end

	local bucket = self:_getBucket(scopeKey, userId, key, limit)
	local now = self._clock()

	if limit.mode == "token" then
		return self:_allowToken(bucket, limit, now)
	end

	return self:_allowWindow(bucket, limit, now)
end

return RateLimiterService
