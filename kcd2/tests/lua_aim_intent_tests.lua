-- SPDX-License-Identifier: GPL-3.0-or-later
-- Real Lua, synthetic bindings. Does not establish live aiming or input timing.
assert(type(MINECOME_MODULE_PATH) == "string")
local probe = MINECOME_MODULE_PATH:gsub("aim_intent.lua$", "aim_probe.lua")
local passed, checks = 0, 0
local RUN = string.rep("a", 32)
local function equal(actual, expected)
    checks = checks + 1
    assert(actual == expected, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function fixture()
    local f = { now = 42, logs = {}, rays = 0, calls = 0, count = 0, hit_distance = 2 }
    local untouched = {}; MineCome = { _block_sink = untouched, _interactive_input = untouched }
    player = { id = 999 }; ent_all = 287
    local function forbidden() error("game-state write attempted") end
    System = {
        GetCurrTime = function() f.calls = f.calls + 1; if f.clock_error then error("clock failed") end; return f.now end,
        GetViewCameraPos = function() return { x = 120, y = 2040, z = 57 } end,
        GetViewCameraDir = function() return { x = 0, y = 2, z = 0 } end,
        LogAlways = function(line)
            f.logs[#f.logs + 1] = line
            if f.log_error then error("write then error") end
            return f.log_result
        end,
        SpawnEntity = forbidden, RemoveEntity = forbidden, ExecuteCommand = forbidden, AddCCommand = forbidden
    }
    Script = { SetTimerForFunction = forbidden }
    Physics = { RayWorldIntersection = function(origin, direction, maximum, mask, skip, skip2, hits)
        f.rays = f.rays + 1
        equal(origin.x, 120); equal(direction.y, 4.5); equal(maximum, 16); equal(mask, 287); equal(skip, 999)
        if f.count > 0 then hits[1] = { pos = { x = 120, y = 2040 + f.hit_distance, z = 57 }, dist = f.hit_distance } end
        if f.on_ray then f.on_ray() end
        if f.ray_error then error("ray failed") end
        return f.count
    end }
    dofile(probe); dofile(MINECOME_MODULE_PATH)
    equal(#f.logs, 0); equal(f.calls, 0); equal(f.rays, 0)
    function f:contains(text) return self.logs[#self.logs]:find(text, 1, true) ~= nil end
    function f:begin(run, arena, seconds)
        local ok, reason = MineCome.BeginAimedInput(run or RUN, arena or "1", seconds or 60)
        equal(ok, true); equal(reason, "accepted")
    end
    function f:permit(value)
        local ok, reason = MineCome.InstallAimedPermit(RUN, "1", value or "1")
        equal(ok, true); equal(reason, "installed")
    end
    function f:click(permit, click, action)
        local ok, request = MineCome.AimedIntent(RUN, "1", permit or "1", click or "1", action or 1)
        equal(ok, true); equal(request, click or "1")
        equal(MineCome._block_sink, untouched); equal(MineCome._interactive_input, untouched)
        return self.logs[#self.logs]
    end
    function f:decline(fn, reason)
        local before = #self.logs; local ok, got = fn();equal(ok, false);equal(got, reason);equal(#self.logs, before)
    end
    return f
end

test("loading stays inactive and actions require explicit matching session", function()
    local f = fixture()
    f:decline(function() return MineCome.InstallAimedPermit(RUN, "1", "1") end, "session_mismatch")
    f:decline(function() return MineCome.AimedIntent(RUN, "1", "1", "1", 1) end, "session_mismatch")
    equal(f.rays, 0); equal(f.calls, 0)
end)

test("exact begin permit intent and end acknowledgements", function()
    local f = fixture();f:begin();f:permit()
    equal(f:contains('[MineComeAimPermit] {"schema":1,"run":"' .. RUN .. '","arena":"1","permit":"1","result":"installed","engine_time":42,"expires_engine_time":42.5}'), true)
    local line = f:click()
    equal(line:find('"request":"1","permit":"1","click":"1","action":1', 1, true) ~= nil, true)
    equal(f:contains('"result":"sampled","reason":"none","permit_engine_time":42,"engine_time":42,"completed_engine_time":42'), true)
    equal(f:contains('"direction":{"x":0,"y":1,"z":0},"range":4.5,"occlusion":1,"nearest_distance":0'), true)
    equal(f.rays, 1)
    local ok, result = MineCome.EndAimedInput(RUN, "1");equal(ok, true);equal(result, "ended")
    equal(f:contains('"event":"end","result":"ended","engine_time":42,"expires_engine_time":null'), true)
    f:decline(function() return MineCome.AimedIntent(RUN, "1", "1", "2", 1) end, "session_mismatch")
end)

test("IDs survive exact53 boundary and invalid identities never reach engine sampling", function()
    local invalid = { "0", "01", "-1", "1.0", "1e2", "9007199254740992", string.rep("9", 64), "1'", 1 }
    for _, id in ipairs(invalid) do
        local f=fixture();f:decline(function() return MineCome.BeginAimedInput(RUN, id, 60) end, "invalid_identity")
        f:begin();f:decline(function() return MineCome.InstallAimedPermit(RUN,"1",id) end,"invalid_identity")
        f:decline(function() return MineCome.AimedIntent(RUN,"1","1",id,1) end,"invalid_identity")
        equal(f.rays,0)
    end
    local f=fixture();f:begin();f:permit("9007199254740991");f:click("9007199254740991","9007199254740991",2)
    equal(f:contains('"request":"9007199254740991","permit":"9007199254740991","click":"9007199254740991","action":2'),true)
end)

test("leases require bounded integer duration and exact lowercase run", function()
    for _, seconds in ipairs({0,44,181,45.5,math.huge,0/0}) do
        local f=fixture();f:decline(function() return MineCome.BeginAimedInput(RUN,"1",seconds) end,"invalid_lease")
    end
    for _, run in ipairs({"",string.rep("A",32),string.rep("a",31),string.rep("b",33),"'"}) do
        local f=fixture();f:decline(function() return MineCome.BeginAimedInput(run,"1",60) end,"invalid_identity")
    end
    local f=fixture();f:begin();f:decline(function() return MineCome.BeginAimedInput(RUN,"1",60) end,"already_active")
    equal(MineCome.EndAimedInput(RUN,"1"),true)
    f:decline(function() return MineCome.BeginAimedInput(RUN,"1",60) end,"replayed_run")
end)

test("single use permits and increasing click IDs consume ambiguous refusals", function()
    local f=fixture();f:begin();f:permit();f:permit("2");f:click("1","1")
    f:decline(function() return MineCome.AimedIntent(RUN,"1","1","2",1) end,"permit_unavailable")
    f:decline(function() return MineCome.AimedIntent(RUN,"1","2","2",1) end,"click_replayed")
    f:click("2","5")
    f:decline(function() return MineCome.InstallAimedPermit(RUN,"1","2") end,"permit_replayed")
    equal(f.rays,2)
end)

test("bounded permit history retains an older pre-edge permit without substitution", function()
    local f=fixture();f:begin()
    for i=1,16 do f:permit(tostring(i)) end
    f:decline(function() return MineCome.InstallAimedPermit(RUN,"1","17") end,"permit_capacity")
    f:click("1","1");f:permit("17")
    f.now=42.51;f:permit("18")
    f:decline(function() return MineCome.AimedIntent(RUN,"1","17","2",1) end,"permit_unavailable")
    f:click("18","3")
end)

test("expired permits and world identity changes cannot sample", function()
    local f=fixture();f:begin();f:permit();f.now=42.501
    f:decline(function() return MineCome.AimedIntent(RUN,"1","1","1",1) end,"permit_expired");equal(f.rays,0)
    f=fixture();f:begin();f:permit();player={id=999}
    f:decline(function() return MineCome.AimedIntent(RUN,"1","1","1",1) end,"world_changed");equal(MineCome._aimed_input.active,nil)
    f=fixture();f:begin();f:permit();player.id=1000
    f:decline(function() return MineCome.AimedIntent(RUN,"1","1","1",1) end,"world_changed");equal(f.rays,0)
end)

test("clock rollback unavailable clock and lease expiry revoke all state", function()
    local f=fixture();f:begin();f:permit();f.now=41
    f:decline(function() return MineCome.AimedIntent(RUN,"1","1","1",1) end,"clock_reversed");equal(MineCome._aimed_input.active,nil)
    f=fixture();f:begin();f:permit();f.clock_error=true
    f:decline(function() return MineCome.AimedIntent(RUN,"1","1","1",1) end,"clock_unavailable");equal(MineCome._aimed_input.active,nil)
    f=fixture();f:begin();f.now=102
    f:decline(function() return MineCome.InstallAimedPermit(RUN,"1","1") end,"session_expired");equal(MineCome._aimed_input.active,nil)
end)

test("camera and nearest obstruction are captured in the same admitted call", function()
    local f=fixture();f:begin();f:permit();f.count=1;f:click()
    equal(f:contains('"occlusion":2,"nearest_distance":2'),true);equal(f.rays,1)
    f=fixture();f:begin();f:permit();f.ray_error=true;f:click()
    equal(f:contains('"result":"unavailable","reason":"ray_error"'),true)
    equal(f:contains('"origin":null,"direction":null,"range":4.5,"occlusion":0,"nearest_distance":0'),true)
end)

test("expiry world loss or clock reversal during capture is explicit unavailable", function()
    local f=fixture();f:begin();f:permit();f.now=42.3;f.on_ray=function() f.now=42.51 end;f:click()
    equal(f:contains('"result":"unavailable","reason":"permit_expired_during_capture"'),true)
    f=fixture();f:begin();f:permit();f.on_ray=function() player={id=999} end;f:click()
    equal(f:contains('"result":"unavailable","reason":"world_changed"'),true);equal(MineCome._aimed_input.active,nil)
    f=fixture();f:begin();f:permit();f.on_ray=function() f.now=41 end;f:click()
    equal(f:contains('"result":"unavailable","reason":"clock_reversed"'),true);equal(MineCome._aimed_input.active,nil)
end)

test("write then failure cannot replay a consumed permit or click", function()
    local f=fixture();f:begin();f.log_error=true
    local ok,reason=MineCome.InstallAimedPermit(RUN,"1","1");equal(ok,false);equal(reason,"log_failed")
    f.log_error=false;f:decline(function() return MineCome.InstallAimedPermit(RUN,"1","1") end,"permit_replayed")
    f:permit("2");f.log_error=true;ok,reason=MineCome.AimedIntent(RUN,"1","2","1",1);equal(ok,false);equal(reason,"log_failed")
    f.log_error=false;f:decline(function() return MineCome.AimedIntent(RUN,"1","2","1",1) end,"click_replayed");equal(f.rays,1)
end)

test("reload revokes old permissions and pinned sampler resists later replacement", function()
    local f=fixture();f:begin();f:permit();MineCome.CaptureAimSample=function() error("later replacement must not execute") end;f:click()
    equal(f:contains('"result":"sampled"'),true)
    dofile(probe);dofile(MINECOME_MODULE_PATH)
    f:decline(function() return MineCome.AimedIntent(RUN,"1","1","2",1) end,"session_mismatch")
    f:decline(function() return MineCome.BeginAimedInput(RUN,"1",60) end,"replayed_run")
end)

print(string.format("PASS Lua aimed intent: %d groups, %d checks",passed,checks))
