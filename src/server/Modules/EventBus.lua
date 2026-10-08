local EventBus = {}
EventBus.__index = EventBus

local VERBOSE_EVENTBUS_LOGS = false

local function debugPrint(...)
	if VERBOSE_EVENTBUS_LOGS then
		print(...)
	end
end

local function describeHandler(handler)
	if not handler then
		return "unknown"
	end
	local ok, info = pcall(debug.getinfo, handler, "Sl")
	if not ok or not info then
		return "unknown"
	end
	local source = info.short_src or "unknown"
	local line = info.linedefined or 0
	return ("%s:%d"):format(source, line)
end

function EventBus.new()
	return setmetatable({
		_listeners = {},
	}, EventBus)
end

function EventBus:subscribe(eventName, handler, label)
	if not eventName or type(handler) ~= "function" then
		return
	end
	local listeners = self._listeners[eventName]
	if not listeners then
		listeners = {}
		self._listeners[eventName] = listeners
	end
	local listener = {
		handler = handler,
		desc = (label and tostring(label)) or describeHandler(handler),
	}
	table.insert(listeners, listener)
	debugPrint(("[EventBus] subscribed %s -> %s"):format(eventName, listener.desc))
	return {
		disconnect = function()
			for i, entry in ipairs(listeners) do
				if entry.handler == handler then
					table.remove(listeners, i)
					debugPrint(("[EventBus] unsubscribed %s <- %s"):format(eventName, entry.desc))
					break
				end
			end
		end,
	}
end

function EventBus:publish(eventName, ...)
	local listeners = self._listeners[eventName]
	if not listeners then
		return
	end
	debugPrint(("[EventBus] publishing %s to %d listener(s)"):format(eventName, #listeners))
	local args = {...}
	for _, listener in ipairs(listeners) do
		debugPrint(("[EventBus] delivering %s -> %s"):format(eventName, listener.desc))
		listener.handler(table.unpack(args))
	end
end

return EventBus
