-- SPDX-License-Identifier: GPL-3.0-or-later
-- Executes the original separate probe in an existing real Lua runtime. Engine
-- bindings are simulated; no test here is proof of a live ray or geometry.
assert(type(MINECOME_MODULE_PATH) == "string")
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local function fixture()
    local f = { logs = {}, rays = {}, terrain_queries = {}, count = 1,
        hit = { pos = { x = 120, y = 2040, z = 56 }, normal = { x = 0, y = 0, z = 1 }, dist = 1,
            surface = 12, entity = {} } }
    local untouched = { marker = "preserved" }
    MineCome = { _block_sink = untouched, _interactive_input = untouched }
    player = { id = 999, position = { x = 120, y = 2040, z = 56 } }
    function player:GetWorldPos() if f.player_error then error("unloaded") end; return self.position end
    ent_terrain, ent_all = 256, 287
    System = {
        LogAlways = function(line) f.logs[#f.logs + 1] = line end,
        GetTerrainElevation = function(position)
            f.terrain_queries[#f.terrain_queries + 1] = position
            if f.terrain_error then error("unavailable") end
            return f.elevation == nil and 55.75 or f.elevation
        end,
        SpawnEntity = function() error("probe must never spawn") end,
        RemoveEntity = function() error("probe must never remove") end
    }
    Script = { SetTimerForFunction = function() error("probe must never schedule") end }
    Physics = { RayWorldIntersection = function(origin, direction, maximum, mask, skip, skip2, output)
        f.rays[#f.rays + 1] = { origin = origin, direction = direction, maximum = maximum, mask = mask,
            skip = skip, skip2 = skip2, output = output }
        if f.ray_error then error("ray failed") end
        output[1] = f.hit
        return f.count
    end }
    dofile(MINECOME_MODULE_PATH)
    equal(#f.logs, 0); equal(#f.rays, 0); equal(#f.terrain_queries, 0)
    function f:probe(token)
        local ok, result = MineCome.ProbeGround(token or "a1b2")
        equal(ok, true)
        equal(MineCome._block_sink, untouched); equal(MineCome._interactive_input, untouched)
        return result
    end
    function f:contains(text) return f.logs[#f.logs]:find(text, 1, true) ~= nil end
    return f
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1; print("PASS " .. name)
end

test("one bounded terrain ray excludes player and copies its vector", function()
    local f = fixture(); local position = player.position
    equal(f:probe(), "hit"); equal(#f.rays, 1); equal(#f.terrain_queries, 1)
    local ray = f.rays[1]
    equal(ray.origin.x, 120); equal(ray.origin.y, 2040); equal(ray.origin.z, 57)
    equal(ray.direction.x, 0); equal(ray.direction.y, 0); equal(ray.direction.z, -8)
    equal(ray.maximum, 4); equal(ray.mask, 256); equal(ray.skip, 999); equal(ray.skip2, nil)
    equal(player.position, position); equal(player.position.z, 56)
    assert(ray.origin ~= position and f.terrain_queries[1] ~= position)
    assert(f:contains('"run":"a1b2"')); assert(f:contains('"hit_minus_terrain":0.25'))
    assert(f:contains('"diagnostic_only":true,"geometry_export_verified":false'))
end)

test("token injection wrong types and long values cannot reach engine or log", function()
    local f = fixture()
    for _, token in ipairs({ "", "0g", "a\n", "a\"", " a", "a ", "-1", "1);bad()", string.rep("a", 65), 1, {}, true }) do
        local ok, reason = MineCome.ProbeGround(token)
        equal(ok, false); equal(reason, "invalid_run")
    end
    equal(MineCome.ProbeGround(nil), false)
    equal(#f.logs, 0); equal(#f.rays, 0); equal(#f.terrain_queries, 0)
    equal(f:probe("ABCDEF019"), "hit")
end)

test("menu player failure invalid vectors and bounds fail closed", function()
    local f = fixture(); player = nil; equal(f:probe(), "no_world"); equal(#f.rays, 0)
    f = fixture(); f.player_error = true; equal(f:probe(), "player_position_error"); equal(#f.rays, 0)
    for _, value in ipairs({ math.huge, -math.huge, 10000001, "120" }) do
        f = fixture(); player.position.x = value; equal(f:probe(), "player_position_invalid"); equal(#f.rays, 0)
        assert(f:contains('"player":null'))
    end
    f = fixture(); player.position.z = 10000000
    equal(f:probe(), "origin_out_of_bounds"); equal(#f.rays, 0)
end)

test("missing ray skip id and mask availability are diagnosed without invented flags", function()
    local f = fixture(); Physics = nil; equal(f:probe(), "ray_unavailable"); equal(#f.rays, 0)
    f = fixture(); player.id = nil; equal(f:probe(), "skip_id_unavailable"); equal(#f.rays, 0)
    f = fixture(); ent_terrain = nil; equal(f:probe(), "hit")
    equal(f.rays[1].mask, 287); assert(f:contains('"mask_name":"ent_all"'))
    f = fixture(); ent_terrain = 1.5; ent_all = "287"
    equal(f:probe(), "mask_unavailable"); equal(#f.rays, 0)
end)

test("no hit and ray errors never expose stale output geometry", function()
    local f = fixture(); f.count = 0; equal(f:probe(), "no_hit")
    assert(f:contains('"hit_position":null')); assert(f:contains('"hit_count":0'))
    f = fixture(); f.ray_error = true; equal(f:probe(), "ray_error")
    assert(f:contains('"hit_count":null')); assert(f:contains('"hit_fields":[]'))
end)

test("ray count is a bounded integer and result table is private on each call", function()
    for _, count in ipairs({ -1, 5, 0.5, math.huge }) do
        local f = fixture(); f.count = count; equal(f:probe(), "ray_count_invalid")
        assert(f:contains('"hit_position":null'))
    end
    local f = fixture(); f:probe(); f:probe()
    assert(f.rays[1].output ~= f.rays[2].output)
end)

test("unfamiliar count reports type and bounded fields without guessing geometry", function()
    for _, count in ipairs({ "1", { secret = "must not serialize" }, false }) do
        local f = fixture(); f.count = count; equal(f:probe(), "ray_count_unrecognized")
        assert(f:contains('"hit_count":null,"hit_count_type":"' .. type(count) .. '"'))
        assert(f:contains('"hit_fields":["pos","normal","dist","surface","entity"]'))
        assert(f:contains('"hit_position":null'))
        assert(not f:contains("secret"))
    end
end)

test("documented hit fields diagnose missing malformed and nonfinite schemas", function()
    for _, field in ipairs({ "pos", "normal", "dist" }) do
        local f = fixture(); f.hit[field] = nil; equal(f:probe(), "hit_fields_invalid")
        assert(f:contains('"hit_position":null'))
    end
    local f = fixture(); f.hit.pos.x = 0/0; equal(f:probe(), "hit_fields_invalid")
    f = fixture(); f.hit.normal.z = math.huge; equal(f:probe(), "hit_fields_invalid")
    f = fixture(); f.hit.dist = "1"; equal(f:probe(), "hit_fields_invalid")
    assert(f:contains('"dist":"string"'))
    f = fixture(); f.hit = 9; equal(f:probe(), "hit_fields_invalid")
end)

test("reported position and distance remain inside the bounded ray", function()
    for _, change in ipairs({ { "x", 121 }, { "y", 2042 }, { "z", 58 }, { "z", 48 } }) do
        local f = fixture(); f.hit.pos[change[1]] = change[2]
        equal(f:probe(), "hit_outside_segment"); assert(f:contains('"hit_position":null'))
    end
    local f = fixture(); f.hit.dist = 9; equal(f:probe(), "hit_fields_invalid")
end)

test("optional terrain comparison has separate unavailable error and finite checks", function()
    local f = fixture(); System.GetTerrainElevation = nil; equal(f:probe(), "hit")
    assert(f:contains('"terrain_result":"unavailable","terrain_elevation":null'))
    f = fixture(); f.terrain_error = true; equal(f:probe(), "hit")
    assert(f:contains('"terrain_result":"error"'))
    for _, elevation in ipairs({ math.huge, -10000001, "56" }) do
        f = fixture(); f.elevation = elevation; equal(f:probe(), "hit")
        assert(f:contains('"terrain_result":"invalid","terrain_elevation":null'))
    end
end)

test("arbitrary engine metadata is never serialized or traversed", function()
    local f = fixture()
    f.hit.surface = 'bad"injection'; f.hit.entity = { nested = { secret = "must not serialize" } }
    f.hit['bad"key'] = 'bad\nvalue'
    equal(f:probe(), "hit")
    assert(not f:contains("injection")); assert(not f:contains("secret")); assert(not f:contains("bad"))
    assert(f:contains('"hit_fields":["pos","normal","dist","surface","entity"]'))
    assert(f:contains('"surface":"string","entity":"table"'))
end)

test("module reload only replaces original probe function and retains state", function()
    local f = fixture(); f:probe(); local before = MineCome.ProbeGround
    dofile(MINECOME_MODULE_PATH)
    assert(MineCome.ProbeGround ~= before); equal(#f.rays, 1); equal(#f.logs, 1)
    equal(f:probe(), "hit"); equal(#f.rays, 2)
end)

test("logging unavailable and partial failure return errors without other writes", function()
    local f = fixture(); System.LogAlways = nil
    local ok, reason = MineCome.ProbeGround("a1"); equal(ok, false); equal(reason, "log_unavailable")
    equal(#f.rays, 0)
    f = fixture(); System.LogAlways = function() error("log unavailable") end
    ok, reason = MineCome.ProbeGround("a1"); equal(ok, false); equal(reason, "log_failed")
    equal(#f.rays, 1)
end)

print(string.format("Verified %d standalone ground-probe cases in %s; engine bindings simulated", passed, _VERSION))
