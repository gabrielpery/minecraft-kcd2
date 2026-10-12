-- SPDX-License-Identifier: GPL-3.0-or-later
-- Existing real Lua runtime; all engine/input/timer bindings are simulated.
-- Passing does not prove delivery of physical keyboard/controller actions.
assert(type(MINECOME_MODULE_PATH) == "string")
local unpack_values = table.unpack or unpack
local passed = 0
local function pack(...) return { n = select("#", ...), ... } end
local function equal(actual, expected)
    assert(actual == expected, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local function fixture(inherited)
    local f = { logs = {}, calls = {}, timers = {}, mutations = 0 }
    local retained = { marker = "preserved" }
    MineCome = { _block_sink = retained, _interactive_input = retained, ProbeGround = retained }
    f.original = function(self, ...)
        f.calls[#f.calls + 1] = { self = self, args = pack(...) }
        if f.throw then error(f.throw, 0) end
        return unpack_values(f.returns or { n = 0 }, 1, (f.returns or { n = 0 }).n)
    end
    player = { id = 999, GetWorldPos = function() return f.position or { x = 120, y = 2040, z = 56 } end }
    f.player = player
    if inherited then f.prototype = { OnAction = f.original }; setmetatable(player, { __index = f.prototype })
    else player.OnAction = f.original end
    local function mutation() f.mutations = f.mutations + 1; error("forbidden engine mutation") end
    System = { LogAlways = function(line)
        if f.log_fail then error("logger failed") end
        f.logs[#f.logs + 1] = line
    end, SpawnEntity = mutation, RemoveEntity = mutation, AddCCommand = mutation }
    ActionMapManager = { SetActionListener = mutation, EnableActionMap = mutation }
    Script = { SetTimerForFunction = function(delay, callback, data, paused)
        equal(player.OnAction, f.original) -- cleanup must be armed before install
        equal(delay, f.expected_delay or 15000); equal(paused, true)
        if f.timer_hook then f.timer_hook(data) end
        if f.timer_fail then error("timer failed") end
        if f.timer_false then return false end
        f.timers[#f.timers + 1] = { delay = delay, callback = callback, data = data, paused = paused }
        if f.timer_nil then return nil end
        return #f.timers
    end }
    dofile(MINECOME_MODULE_PATH)
    equal(#f.logs, 0); equal(#f.timers, 0); equal(f.player.OnAction, f.original)
    function f:begin(token)
        local ok, result = MineCome.BeginInputProbe(token or "a1b2")
        equal(ok, true); equal(result, "started"); equal(self.mutations, 0)
        equal(MineCome._block_sink, retained); equal(MineCome._interactive_input, retained)
        return rawget(self.player, "OnAction")
    end
    function f:events()
        local lines = {}
        for _, line in ipairs(self.logs) do if line:find("[MineComeActionProbe]", 1, true) then lines[#lines + 1] = line end end
        return lines
    end
    function f:contains(text) return self.logs[#self.logs]:find(text, 1, true) ~= nil end
    function f:fire(index)
        local timer = self.timers[index or 1]; assert(timer)
        _G[timer.callback](timer.data, 1)
    end
    return f
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1; print("PASS " .. name)
end

test("start arms one paused lease before installation and end restores exact raw callback", function()
    local f = fixture(); local wrapper = f:begin()
    assert(wrapper ~= f.original); equal(#f.timers, 1)
    assert(f:contains('"event":"begin","result":"started","events":0,"callback_restored":false'))
    local ok, result = MineCome.EndInputProbe("a1b2"); equal(ok, true); equal(result, "ended")
    equal(rawget(f.player, "OnAction"), f.original)
    assert(f:contains('"callback_restored":true')); equal(MineCome._input_probe.active, nil)
end)

test("forwarding preserves self all arguments and multiple returns including nil", function()
    local f = fixture(); local wrapper = f:begin(); local extra = {}
    f.returns = pack(nil, false, extra, "tail", nil)
    local returned = pack(wrapper(f.player, "moveforward", "press", 1, nil, extra, nil))
    equal(returned.n, 5); equal(returned[1], nil); equal(returned[2], false)
    equal(returned[3], extra); equal(returned[4], "tail"); equal(returned[5], nil)
    equal(f.calls[1].self, f.player); equal(f.calls[1].args.n, 6)
    equal(f.calls[1].args[1], "moveforward"); equal(f.calls[1].args[4], nil)
    equal(f.calls[1].args[5], extra); equal(f.calls[1].args[6], nil)
end)

test("original errors propagate unchanged after observation", function()
    local f = fixture(); local wrapper = f:begin(); local error_object = {}
    f.throw = error_object
    local ok, err = pcall(wrapper, f.player, "jump", "press", 1)
    equal(ok, false); equal(err, error_object); equal(#f:events(), 1); equal(#f.calls, 1)
end)

test("only action whitelist logs all value types while every action still forwards", function()
    local f = fixture(); local wrapper = f:begin()
    for _, action in ipairs({ "moveforward", "moveback", "moveleft", "moveright", "jump", "sprint",
        "xi_movex", "xi_movey", "rotateyaw", "rotatepitch", "xi_rotateyaw", "xi_rotatepitch", "ui_start_pause", "ui_back" }) do
        wrapper(f.player, action, "press", 0.25)
    end
    equal(#f:events(), 14)
    for _, action in ipairs({ "text_input", 'bad"action', "custom_quest_call_horse_action", {}, false }) do
        wrapper(f.player, action, "press", 1)
    end
    for _, value in ipairs({ math.huge, -math.huge, "1", {} }) do wrapper(f.player, "jump", "press", value) end
    wrapper(f.player, "jump", "press", 0/0); wrapper(f.player, "jump", "press", nil)
    local events = f:events()
    equal(#events, 20); equal(#f.calls, 25)
    assert(events[14]:find('"value_type":"number","value":0.25', 1, true))
    for index = 15, 20 do assert(events[index]:find('"value":null', 1, true)) end
    assert(events[17]:find('"value_type":"string"', 1, true))
    assert(events[18]:find('"value_type":"table"', 1, true))
    assert(events[20]:find('"value_type":"nil"', 1, true))
    equal(f.calls[22].args[3], "1"); equal(f.calls[25].args[3], nil)
end)

test("activation names remain bounded and numeric modes are never guessed", function()
    local f = fixture(); local wrapper = f:begin()
    for _, activation in ipairs({ "press", "release", "hold", 'bad"activation', 1, {} }) do
        wrapper(f.player, "xi_movex", activation, -0.5)
    end
    local events = f:events()
    assert(events[1]:find('"activation_type":"string","activation":"press"', 1, true))
    assert(events[4]:find('"activation":"unknown"', 1, true)); assert(not events[4]:find("bad", 1, true))
    assert(events[5]:find('"activation_type":"number","activation":"unknown"', 1, true))
    equal(f.calls[5].args[2], 1); equal(#f.calls, 6)
end)

test("max 128 receipts restores handler without suppressing final or cached callback delivery", function()
    local f = fixture(); local wrapper = f:begin()
    for index = 1, 130 do wrapper(f.player, "moveforward", "hold", 1) end
    equal(#f:events(), 128); equal(#f.calls, 130); equal(f.player.OnAction, f.original)
    assert(f:contains('"event":"event_limit","result":"ended","events":128,"callback_restored":true'))
    f:fire(); equal(f.player.OnAction, f.original); equal(#f:events(), 128)
end)

test("duplicate begin and wrong end cannot extend lease or replace ownership", function()
    local f = fixture(); local wrapper = f:begin()
    local ok, result = MineCome.BeginInputProbe("a1b2"); equal(ok, true); equal(result, "already_active")
    ok, result = MineCome.BeginInputProbe("c3d4"); equal(ok, false); equal(result, "rejected_active")
    ok, result = MineCome.EndInputProbe("c3d4"); equal(ok, false); equal(result, "rejected_token")
    equal(#f.timers, 1); equal(f.player.OnAction, wrapper)
    f:fire(); equal(f.player.OnAction, f.original)
    assert(f:contains('"event":"expired","result":"ended"'))
end)

test("inherited callback restores nil raw field and retains prototype behavior", function()
    local f = fixture(true); equal(rawget(f.player, "OnAction"), nil)
    local wrapper = f:begin(); wrapper(f.player, "jump", "release", 0)
    local new_inherited = function() return "new prototype" end
    f.prototype.OnAction = new_inherited
    assert(MineCome.EndInputProbe("a1b2"))
    equal(rawget(f.player, "OnAction"), nil); equal(f.player.OnAction, new_inherited)
end)

test("replacement handlers are never clobbered by end or lease", function()
    for _, mode in ipairs({ "end", "lease", "cached" }) do
        local f = fixture(); local wrapper = f:begin(); local replacement = function() return "replacement" end
        f.player.OnAction = replacement
        if mode == "end" then local _, result = MineCome.EndInputProbe("a1b2"); equal(result, "superseded")
        elseif mode == "lease" then f:fire()
        else wrapper(f.player, "jump", "press", 1); equal(#f.calls, 1) end
        equal(f.player.OnAction, replacement); equal(MineCome._input_probe.active, nil)
        assert(f:contains('"callback_restored":false'))
    end
end)

test("identity loss restores only captured object and leaves replacement player untouched", function()
    local f = fixture(); local wrapper = f:begin(); local replacement = function() end
    player = { id = 1000, OnAction = replacement }
    wrapper(f.player, "jump", "press", 1)
    equal(player.OnAction, replacement); equal(f.player.OnAction, f.original); equal(#f.calls, 1)
    equal(#f:events(), 0); assert(f:contains('"event":"identity_changed"'))
    f = fixture(); wrapper = f:begin(); f.player.id = 1000
    wrapper(f.player, "jump", "press", 1); equal(f.player.OnAction, f.original)
end)

test("reload preserves active wrapper timer and exact original restoration", function()
    local f = fixture(true); local wrapper = f:begin(); local before = MineCome.BeginInputProbe
    dofile(MINECOME_MODULE_PATH)
    assert(MineCome.BeginInputProbe ~= before); equal(f.player.OnAction, wrapper); equal(#f.timers, 1)
    wrapper(f.player, "jump", "press", 1); equal(#f:events(), 1)
    f:fire(); equal(rawget(f.player, "OnAction"), nil); equal(f.player.OnAction, f.original)
end)

test("stale timer cannot restore or end a newer probe even with repeated token", function()
    local f = fixture(); f:begin(); assert(MineCome.EndInputProbe("a1b2"))
    local wrapper = f:begin(); equal(#f.timers, 2)
    f:fire(1); equal(f.player.OnAction, wrapper); assert(MineCome._input_probe.active)
    f:fire(2); equal(f.player.OnAction, f.original); equal(MineCome._input_probe.active, nil)
end)

test("timer failure false and nil ids are handled before handler installation", function()
    for _, mode in ipairs({ "timer_fail", "timer_false" }) do
        local f = fixture(); f[mode] = true
        local ok, result = MineCome.BeginInputProbe("a1b2")
        equal(ok, false); equal(result, "rejected_timer"); equal(f.player.OnAction, f.original)
        equal(MineCome._input_probe.active, nil)
    end
    local f = fixture(); f.timer_nil = true; f:begin(); f:fire(); equal(f.player.OnAction, f.original)
end)

test("synchronous lease and callback replacement during timer arming cannot install", function()
    local f = fixture(); f.timer_hook = function(data) MineCome_InputProbeLease(data, 1) end
    local ok, result = MineCome.BeginInputProbe("a1b2")
    equal(ok, false); equal(result, "rejected_expired"); equal(f.player.OnAction, f.original)
    f = fixture(true); local replacement = function() end
    f.timer_hook = function() f.prototype.OnAction = replacement end
    ok, result = MineCome.BeginInputProbe("a1b2")
    equal(ok, false); equal(result, "rejected_changed"); equal(rawget(f.player, "OnAction"), nil)
    equal(f.player.OnAction, replacement)
end)

test("invalid tokens world and callback bindings cannot install or arm cleanup", function()
    local f = fixture()
    for _, token in ipairs({ "", "g", 'a"', "a\n", "-1", string.rep("a", 65), 1, {}, true }) do
        equal(MineCome.BeginInputProbe(token), false); equal(MineCome.EndInputProbe(token), false)
    end
    equal(MineCome.BeginInputProbe(nil), false); equal(#f.logs, 0); equal(#f.timers, 0)
    f = fixture(); player = nil; local _, result = MineCome.BeginInputProbe("a1"); equal(result, "rejected_world")
    f = fixture(); f.position = { x = math.huge, y = 1, z = 2 }
    _, result = MineCome.BeginInputProbe("a1"); equal(result, "rejected_world"); equal(#f.timers, 0)
    f = fixture(); f.player.OnAction = nil
    _, result = MineCome.BeginInputProbe("a1"); equal(result, "rejected_callback"); equal(#f.timers, 0)
    f = fixture(); Script = nil
    _, result = MineCome.BeginInputProbe("a1"); equal(result, "rejected_timer"); equal(f.player.OnAction, f.original)
end)

test("wrong self still forwards exactly without recording unrelated callback use", function()
    local f = fixture(); local wrapper = f:begin(); local other = {}
    wrapper(other, "jump", "press", 1)
    equal(f.calls[1].self, other); equal(#f:events(), 0)
end)

test("logging errors fail closed while original action delivery continues", function()
    local f = fixture(); local wrapper = f:begin(); f.log_fail = true
    wrapper(f.player, "jump", "press", 1)
    equal(#f.calls, 1); equal(f.player.OnAction, f.original); equal(MineCome._input_probe.active, nil)
    f = fixture(); f.log_fail = true
    local ok, result = MineCome.BeginInputProbe("a1b2")
    equal(ok, false); equal(result, "log_failed"); equal(f.player.OnAction, f.original)
end)

test("repeated end acknowledges completed probe and no-session end never mutates", function()
    local f = fixture(); f:begin(); assert(MineCome.EndInputProbe("a1b2"))
    local ok, result = MineCome.EndInputProbe("a1b2"); equal(ok, true); equal(result, "ended")
    assert(f:contains('"callback_restored":true')); equal(f.player.OnAction, f.original)
    ok, result = MineCome.EndInputProbe("c3d4"); equal(ok, false); equal(result, "no_session")
    equal(f.player.OnAction, f.original); equal(f.mutations, 0)
end)

test("optional initial lease accepts only bounded integer15 through60 seconds", function()
    for _, seconds in ipairs({ 15, 30, 60 }) do
        local f = fixture(); f.expected_delay = seconds * 1000
        local ok, result = MineCome.BeginInputProbe("a1b2", seconds)
        equal(ok, true); equal(result, "started"); equal(#f.timers, 1)
        equal(f.timers[1].delay, seconds * 1000)
        assert(f:contains('"lease_ms":' .. tostring(seconds * 1000)))
        f:fire(); equal(f.player.OnAction, f.original)
    end
    for _, seconds in ipairs({ 14, 61, 15.5, 0, -1, math.huge, "60", {}, false }) do
        local f = fixture()
        local ok, result = MineCome.BeginInputProbe("a1b2", seconds)
        equal(ok, false); equal(result, "invalid_lease")
        equal(#f.timers, 0); equal(#f.logs, 0); equal(f.player.OnAction, f.original)
    end
    local f = fixture(); equal(MineCome.BeginInputProbe("a1b2", 0/0), false); equal(#f.timers, 0)
end)

test("active begin60 cannot extend the original15-second cleanup lease", function()
    local f = fixture(); local wrapper = f:begin()
    local ok, result = MineCome.BeginInputProbe("a1b2", 60)
    equal(ok, true); equal(result, "already_active"); equal(#f.timers, 1)
    equal(f.timers[1].delay, 15000); equal(f.player.OnAction, wrapper)
    assert(f:contains('"lease_ms":15000'))
    f:fire(); equal(f.player.OnAction, f.original)
end)

print(string.format("Verified %d standalone input-probe cases in %s; engine bindings simulated", passed, _VERSION))
