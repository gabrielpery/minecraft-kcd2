-- Execute the exact request.lua captured by hud_camera_delivery.Tests.ps1.
-- The existing Lua test runner supplies its path as MINECOME_MODULE_PATH.
-- No game bindings or HTTP calls are used.
local command = assert(loadfile(MINECOME_MODULE_PATH))
local logs, calls, accepted, reason = {}, 0, true, "sampled"
System = {LogAlways=function(value) logs[#logs+1]=value end}
MineCome = {SamplePhysicalHudView=function(run)
    assert(type(run)=="string" and #run==32 and run:match("^[0-9a-f]+$"))
    calls=calls+1
    return accepted,reason
end}
local checks=0
local function check(value) checks=checks+1;assert(value) end
local function invoke(ok,value)
    accepted,reason,logs=ok,value,{}
    local before=calls;command();check(calls==before+1)
    check(logs[#logs]:match("^%[MineComeHudWalkingFlush%] [0-9a-f]+$")~=nil)
end
invoke(true,"sampled");check(#logs==1)
for _,value in ipairs({"velocity_unavailable_or_moving","clock_not_advancing","view_budget_expired"}) do
    invoke(false,value)
    check(#logs==2 and logs[1]:find('"seq":1,"result":"rejected","reason":"'..value..'"}',1,true)~=nil)
end
for _,value in ipairs({'unsafe"reason',"line\nbreak",string.rep("a",65),"",{},true}) do
    invoke(false,value)
    check(#logs==2 and logs[1]:find('"reason":"invalid_rejection_reason"}',1,true)~=nil)
end
invoke(nil,"unexpected");check(#logs==1)
print("HUD_CAMERA_REQUEST_LUA_TESTS checks="..checks.." PASS game_calls=false")
