local Limiter = require("./RateLimiter")
local Events = require("./EventService")
local count = 0
local function test(name, fn)
 fn()
 count += 1
 print("PASS " .. name)
end
local now = 0
local function limiter(limit)
 return Limiter.new({defaultLimit=limit,clock=function() return now end})
end
local p, q = {UserId=1}, {UserId=2}
test("token burst, refill and player isolation", function()
 local l=limiter({capacity=2,refillPerSec=1})
 assert(l:Allow(p,"Ping")); assert(l:Allow(p,"Ping")); assert(not l:Allow(p,"Ping"))
 assert(l:Allow(q,"Ping")); now=1; assert(l:Allow(p,"Ping"))
end)
test("global scope shares capacity",function()
 local l=limiter({capacity=1,refillPerSec=1})
 assert(l:Allow(p,"Ping",nil,"global"));assert(not l:Allow(q,"Ping",nil,"global"))
end)
test("sliding window and cleanup",function()
 now=0;local l=limiter({maxCalls=2,perSeconds=1})
 assert(l:Allow(p,"Ping"));assert(l:Allow(p,"Ping"));assert(not l:Allow(p,"Ping"))
 now=1.1;assert(l:Allow(p,"Ping"));l:RemovePlayer(p);assert(l._buckets.player[1]==nil)
end)
local function node(class)
 local x={ClassName=class,Name="",children={}}
 function x:FindFirstChild(name) return self.children[name] end
 function x:IsA(name) return self.ClassName==name end
 function x:GetFullName() return self.Name end
 x.OnServerEvent={Connect=function(signal,fn) signal.handler=fn end}
 function x:FireClient(player,...) self.lastClient=player;self.lastArgs=table.pack(...) end
 function x:FireAllClients(...) self.lastArgs=table.pack(...) end
 return setmetatable(x,{__newindex=function(obj,key,value)
  rawset(obj,key,value)
  if key=="Parent" then value.children[obj.Name]=obj end
 end})
end
local function setup()
 local storage=node("Folder")
 local e=Events.new({storage=storage,newInstance=node,rateLimiter=limiter({capacity=5,refillPerSec=1}),log=function() end})
 return e,storage
end
test("default guard denies",function()
 local e,s=setup();local calls=0;e:RegisterFunction("Demo/Ping",function() calls+=1;return "pong" end)
 local ok,msg=s.children.Remotes.children.Demo.children.Ping.OnServerInvoke(p)
 assert(ok==false and msg=="Unauthorized" and calls==0)
end)
test("guard, validation and middleware",function()
 local e,s=setup();local calls=0
 e:RegisterFunction("Demo/Ping",function(ctx,value) calls+=1;return value end,{
  guard=function(ctx) return ctx.userId==1 end,
  validate=function(v) return type(v)=="number" end,
  middleware={function(ctx) return ctx.player==p end},
 })
 local remote=s.children.Remotes.children.Demo.children.Ping
 assert(remote.OnServerInvoke(p,7)==7)
 assert(remote.OnServerInvoke(q,7)==false)
 assert(remote.OnServerInvoke(p,"bad")==false)
 assert(calls==1)
end)
test("crashed guard and handler fail closed",function()
 local e,s=setup();e:RegisterFunction("Demo/Crash",function() error("boom") end,{guard=function() return true end})
 local ok,msg=s.children.Remotes.children.Demo.children.Crash.OnServerInvoke(p)
 assert(ok==false and msg=="Server error")
 e:RegisterFunction("Demo/GuardCrash",function() error("must not run") end,{guard=function() error("boom") end})
 assert(s.children.Remotes.children.Demo.children.GuardCrash.OnServerInvoke(p)==false)
end)
test("events are rate limited",function()
 local e,s=setup();local calls=0
 e:RegisterEvent("Demo/Event",function() calls+=1 end,{guard=function() return true end,rateLimit={capacity=1,refillPerSec=1}})
 local remote=s.children.Remotes.children.Demo.children.Event
 remote.OnServerEvent.handler(p);remote.OnServerEvent.handler(p);assert(calls==1)
end)
test("duplicate binding and class mismatch do not overwrite",function()
 local e,s=setup();e:RegisterFunction("Demo/Ping",function() return 1 end,{guard=function() return true end})
 e:RegisterFunction("Demo/Ping",function() return 2 end,{guard=function() return true end})
 assert(s.children.Remotes.children.Demo.children.Ping.OnServerInvoke(p)==1)
 assert(e:_resolveRemote("Demo/Ping","RemoteEvent",false)==nil)
end)
print(tostring(count).." tests passed")
