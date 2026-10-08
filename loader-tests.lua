local Loader=require("./ModuleLoader")
local passed=0
local function test(name,fn) fn();passed+=1;print("PASS "..name) end
-- The require/instantiation boundary needs real ModuleScripts in Roblox.
-- These tests isolate the generic lifecycle behavior without claiming to cover it.
test("lookup and lifecycle dispatch",function()
 local calls={}
 local instance={}
 for _,name in ipairs({"Init","Start","Stop","Destroy"}) do
  instance[name]=function() calls[#calls+1]=name end
 end
 local loader=Loader.new(nil)
 loader._items={Example=instance}
 assert(loader:Get("Example")==instance)
 loader:InitAll();loader:StartAll();loader:StopAll();loader:Destroy()
 assert(table.concat(calls,",")=="Init,Start,Stop,Destroy")
 assert(loader:Get("Example")==nil)
end)
test("destroy falls back to stop",function()
 local stopped=false;local loader=Loader.new(nil)
 loader._items={Example={Stop=function() stopped=true end}}
 loader:Destroy();assert(stopped)
end)
test("optional callbacks are optional",function()
 local loader=Loader.new(nil);loader._items={Example={}}
 loader:InitAll();loader:StartAll();loader:StopAll();loader:Destroy()
end)
test("registration hook receives instances",function()
 local name,value;local loader=Loader.new(nil,{register=function(n,v) name=n;value=v end})
 local instance={};loader:_register("Example",instance)
 assert(name=="Example" and value==instance)
end)
print(passed.." tests passed")
