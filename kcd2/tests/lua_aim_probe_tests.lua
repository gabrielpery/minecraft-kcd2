-- SPDX-License-Identifier: GPL-3.0-or-later
-- Runs the separate probe in a real Lua runtime with simulated bindings.
-- Passing does not establish live physics, camera alignment, or aiming.
assert(type(MINECOME_MODULE_PATH) == "string")
local passed, checks = 0, 0
local function equal(actual, expected)
    checks = checks + 1
    assert(actual == expected, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local function fixture()
    local f = { logs = {}, rays = {}, calls = {}, count = 1, start = 42, finish = 42.01,
        origin = { x = 120, y = 2040, z = 57 }, forward = { x = 0, y = 2, z = 0 }, hits = {} }
    local untouched = { marker = "preserved" }
    MineCome = { _block_sink = untouched, _interactive_input = untouched }
    player = { id = 999 }
    ent_all, ent_terrain = 287, 256
    local function forbidden() error("game-state mutation attempted") end
    System = {
        LogAlways = function(line) f.logs[#f.logs + 1] = line; return f.log_result end,
        GetCurrTime = function()
            f.calls[#f.calls + 1] = "time"
            f.time_calls = (f.time_calls or 0) + 1
            if f.time_error == f.time_calls then error("clock failed") end
            if f.time_calls % 2 == 1 then return f.start end
            return f.finish
        end,
        GetViewCameraPos = function()
            f.calls[#f.calls + 1] = "origin"
            if f.position_error then error("camera failed") end
            return f.origin
        end,
        GetViewCameraDir = function()
            f.calls[#f.calls + 1] = "forward"
            if f.forward_error then error("camera failed") end
            return f.forward
        end,
        SpawnEntity = forbidden, RemoveEntity = forbidden, ExecuteCommand = forbidden
    }
    Script = { SetTimerForFunction = forbidden }
    Physics = { RayWorldIntersection = function(origin, direction, maximum, mask, skip, skip2, output)
        f.calls[#f.calls + 1] = "ray"
        f.rays[#f.rays + 1] = { origin = origin, direction = direction, maximum = maximum,
            mask = mask, skip = skip, skip2 = skip2, output = output }
        for index, hit in pairs(f.hits) do output[index] = hit end
        if f.on_ray then f.on_ray(origin, direction) end
        if f.ray_error then error("ray failed") end
        return f.count
    end }
    function f:hit(distance)
        return { dist = distance, pos = { x = self.origin.x, y = self.origin.y + distance, z = self.origin.z } }
    end
    f.hits[1] = f:hit(2)
    dofile(MINECOME_MODULE_PATH)
    equal(#f.logs, 0); equal(#f.rays, 0); equal(#f.calls, 0)
    function f:contains(text)
        return self.logs[#self.logs]:find(text, 1, true) ~= nil
    end
    function f:probe(token)
        local ok, result = MineCome.ProbeAim(token or "a1b2")
        equal(ok, true)
        equal(MineCome._block_sink, untouched); equal(MineCome._interactive_input, untouched)
        equal(self:contains('"diagnostic_only":true,"aiming_verified":false'), true)
        return result
    end
    function f:unavailable(reason)
        equal(self:probe(), "unavailable")
        equal(self:contains('"reason":"' .. reason .. '"'), true)
        equal(self:contains('"obstruction_known":false,"clear":false'), true)
        equal(self:contains('"nearest_position":null,"nearest_distance":null'), true)
    end
    return f
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1; print("PASS " .. name)
end

test("camera ray and timestamps share one ordered callback, with exact ent_all and player skip", function()
    local f = fixture()
    equal(f:probe("ABCDEF019"), "hit")
    equal(table.concat(f.calls, ","), "time,origin,forward,ray,time")
    equal(#f.rays, 1)
    local ray = f.rays[1]
    equal(ray.origin.x, 120); equal(ray.origin.y, 2040); equal(ray.origin.z, 57)
    equal(ray.direction.x, 0); equal(ray.direction.y, 4.5); equal(ray.direction.z, 0)
    equal(ray.maximum, 16); equal(ray.mask, 287); equal(ray.skip, 999); equal(ray.skip2, nil)
    equal(ray.origin ~= f.origin, true); equal(ray.direction ~= f.forward, true)
    equal(f.origin.y, 2040); equal(f.forward.y, 2)
    equal(f:contains('"run":"ABCDEF019"'), true)
    equal(f:contains('"forward":{"x":0,"y":1,"z":0}'), true)
    equal(f:contains('"nearest_position":{"x":120,"y":2042,"z":57},"nearest_distance":2'), true)
    equal(f:contains('"obstruction_known":true,"clear":false'), true)
end)

test("only an explicit empty complete physics result reports clear", function()
    local f = fixture(); f.count, f.hits = 0, {}
    equal(f:probe(), "no_hit")
    equal(f:contains('"reason":"none"'), true)
    equal(f:contains('"hit_count":0,"obstruction_known":true,"clear":true'), true)
    equal(f:contains('"nearest_position":null,"nearest_distance":null'), true)
    f = fixture(); f.count = 0; f:unavailable("hit_count_mismatch")
end)

test("all unsorted hits are validated and nearest obstruction is selected", function()
    local f = fixture(); f.count = 3
    f.hits = { f:hit(4.5), f:hit(0), f:hit(2.5) }
    equal(f:probe(), "hit"); equal(f:contains('"nearest_distance":0'), true)
    f = fixture(); f.count = 3; f.hits = { f:hit(3), f:hit(1), f:hit(2) }
    equal(f:probe(), "hit"); equal(f:contains('"nearest_distance":1'), true)
    f = fixture(); f.count = 2; f.hits[2] = f:hit(3); f.hits[2].dist = math.huge
    f:unavailable("hit_fields_invalid")
    f = fixture(); f.count = 2; f.hits[2] = f:hit(3); f.hits[2].pos.x = 120.1
    f:unavailable("hit_outside_segment")
end)

test("reported distance and full XYZ position must describe the same bounded segment", function()
    for _, distance in ipairs({ -0.01, 4.5001, math.huge, -math.huge, "2", 0/0 }) do
        local f = fixture(); f.hits[1].dist = distance; f:unavailable("hit_fields_invalid")
    end
    for _, component in ipairs({ "x", "y", "z" }) do
        for _, value in ipairs({ math.huge, -math.huge, 10000001, "2", 0/0 }) do
            local f = fixture(); f.hits[1].pos[component] = value; f:unavailable("hit_fields_invalid")
        end
        local f = fixture(); f.hits[1].pos[component] = f.hits[1].pos[component] + 0.02
        f:unavailable("hit_outside_segment")
    end
    local f = fixture(); f.hits[1].pos = nil; f:unavailable("hit_fields_invalid")
    f = fixture(); f.hits[1] = false; f:unavailable("hit_fields_invalid")
    f = fixture(); f.hits[1].dist = 1; f:unavailable("hit_outside_segment")
end)

test("truncated, inconsistent and unfamiliar hit counts never become clear", function()
    for _, count in ipairs({ -1, 0.5, 17, math.huge, -math.huge, "0", false, {}, 0/0 }) do
        local f = fixture(); f.count = count; f:unavailable("hit_count_invalid")
    end
    local f = fixture(); f.count = nil; f:unavailable("hit_count_invalid")
    f = fixture(); f.count = 2; f:unavailable("hit_fields_invalid")
    f = fixture(); f.hits[2] = f:hit(3); f:unavailable("hit_count_mismatch")
    f = fixture(); f.hits[17] = f:hit(3); f:unavailable("hit_count_mismatch")
    f = fixture(); f.count = 16
    for index = 1, 16 do f.hits[index] = f:hit(index * 0.25) end
    f:unavailable("hit_buffer_saturated")
end)

test("camera fields are bounded and zero or nonfinite directions are refused", function()
    for _, which in ipairs({ "origin", "forward" }) do
        for _, component in ipairs({ "x", "y", "z" }) do
            for _, value in ipairs({ math.huge, -math.huge, 10000001, "2", 0/0 }) do
                local f = fixture(); f[which][component] = value
                f:unavailable(which == "origin" and "camera_position_invalid" or "camera_forward_invalid")
                equal(#f.rays, 0)
            end
        end
    end
    local f = fixture(); f.forward = { x = 0, y = 0, z = 0 }; f:unavailable("camera_forward_invalid")
    f = fixture(); f.forward = { x = 0, y = 1e-12, z = 0 }; f:unavailable("camera_forward_invalid")
    f = fixture(); f.origin = false; f:unavailable("camera_position_invalid")
    f = fixture(); f.forward = false; f:unavailable("camera_forward_invalid")
    f = fixture(); f.position_error = true; f:unavailable("camera_position_error")
    f = fixture(); f.forward_error = true; f:unavailable("camera_forward_error")
end)

test("oblique camera direction is normalized without changing the camera", function()
    local f = fixture(); f.forward = { x = 3, y = 4, z = 0 }
    f.hits[1] = { pos = { x = 121.2, y = 2041.6, z = 57 }, dist = 2 }
    equal(f:probe(), "hit")
    equal(math.abs(f.rays[1].direction.x - 2.7) < 1e-12, true)
    equal(math.abs(f.rays[1].direction.y - 3.6) < 1e-12, true)
    equal(f.forward.x, 3); equal(f.forward.y, 4)
end)

test("missing world, mask and binding paths are explicit unavailable without fallback", function()
    local f = fixture(); player = nil; f:unavailable("no_world")
    f = fixture(); player.id = nil; f:unavailable("skip_id_unavailable")
    f = fixture(); Physics = nil; f:unavailable("ray_unavailable")
    for _, field in ipairs({ "GetViewCameraPos", "GetViewCameraDir", "GetCurrTime" }) do
        f = fixture(); System[field] = nil
        f:unavailable(field == "GetCurrTime" and "time_unavailable" or "camera_unavailable")
        equal(#f.rays, 0)
    end
    for _, mask in ipairs({ 0, -1, 0.5, math.huge, 2147483648, "287", false, 0/0 }) do
        f = fixture(); ent_all = mask; f:unavailable("mask_unavailable"); equal(#f.rays, 0)
    end
    f = fixture(); ent_all = nil; f:unavailable("mask_unavailable"); equal(#f.rays, 0)
end)

test("invalid, reversed and slow clocks invalidate the entire sample", function()
    for _, value in ipairs({ -1, math.huge, -math.huge, 1000000000001, "42", false, 0/0 }) do
        local f = fixture(); f.start = value; f:unavailable("time_invalid"); equal(#f.rays, 0)
        f = fixture(); f.finish = value; f:unavailable("completed_time_invalid")
    end
    local f = fixture(); f.start = nil; f:unavailable("time_invalid")
    f = fixture(); f.finish = nil; f:unavailable("completed_time_invalid")
    f = fixture(); f.finish = 41.99; f:unavailable("clock_reversed")
    f = fixture(); f.finish = 42.251; f:unavailable("sample_expired")
    f = fixture(); f.finish = 42.25; equal(f:probe(), "hit")
    f = fixture(); f.time_error = 1; f:unavailable("time_error")
    f = fixture(); f.time_error = 2; f:unavailable("completed_time_error")
    f = fixture(); f.start, f.finish = 0, 0; equal(f:probe(), "hit")
end)

test("private output and copied vectors prevent previous samples from becoming evidence", function()
    local f = fixture(); equal(f:probe(), "hit")
    f.count, f.hits = 0, {}; equal(f:probe(), "no_hit")
    equal(f.rays[1].output ~= f.rays[2].output, true)
    f.ray_error = true; f:unavailable("ray_error")
    f = fixture(); f.on_ray = function(origin, direction)
        f.origin.x, f.forward.y, origin.x, direction.y = 500, 50, 600, 60
    end
    equal(f:probe(), "hit")
    equal(f:contains('"origin":{"x":120,"y":2040,"z":57}'), true)
    equal(f:contains('"direction":{"x":0,"y":4.5,"z":0}'), true)
end)

test("a changed player or skipped id after the physics call invalidates evidence", function()
    local f = fixture(); f.on_ray = function() player = { id = 999 } end; f:unavailable("world_changed")
    f = fixture(); f.on_ray = function() player.id = 1000 end; f:unavailable("world_changed")
    f = fixture(); f.on_ray = function() player = nil end; f:unavailable("world_changed")
end)

test("invalid caller tokens cannot call the bindings or write logs", function()
    local f = fixture()
    for _, token in ipairs({ "", "0g", "a\n", "a\"", " a", "a ", "-1", "1);bad()", string.rep("a",65), 1, {}, true }) do
        local ok, result = MineCome.ProbeAim(token); equal(ok, false); equal(result, "invalid_run")
    end
    equal(MineCome.ProbeAim(nil), false)
    equal(#f.logs, 0); equal(#f.calls, 0); equal(#f.rays, 0)
end)

test("reload changes only the probe and does not traverse arbitrary hit metadata", function()
    local f = fixture(); local old = MineCome.ProbeAim
    dofile(MINECOME_MODULE_PATH); equal(MineCome.ProbeAim ~= old, true)
    local poison = setmetatable({}, { __tostring = function() error("unexpected metadata") end,
        __pairs = function() error("unexpected traversal") end })
    f.hits[1].entity, f.hits[1].surface, f.hits[1].normal = poison, poison, poison
    equal(f:probe(), "hit"); equal(#f.logs, 1); equal(#f.rays, 1)
    f = fixture(); f.hits[1] = setmetatable({}, { __index = function() error("malformed hit") end })
    f:unavailable("probe_error")
end)

test("logging failures return failure rather than claiming a recorded sample", function()
    local f = fixture(); System.LogAlways = nil
    local ok, result = MineCome.ProbeAim("a1"); equal(ok, false); equal(result, "log_unavailable"); equal(#f.rays, 0)
    f = fixture(); f.log_result = false
    ok, result = MineCome.ProbeAim("a1"); equal(ok, false); equal(result, "log_failed")
    f = fixture(); System.LogAlways = function() error("closed log") end
    ok, result = MineCome.ProbeAim("a1"); equal(ok, false); equal(result, "log_failed")
end)

print("Aim probe: " .. passed .. " groups, " .. checks .. " checks passed (simulated engine bindings).")
