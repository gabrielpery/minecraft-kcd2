-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual Lua runtime tests of the original probe with simulated bindings.
-- These do not prove live raycasts, movement or a complete collision export.
assert(type(MINECOME_MODULE_PATH) == "string")
local passed = 0
local function equal(actual, expected)
    assert(actual == expected, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local function field(line, name)
    return line:match('"' .. name .. '":([^,}]+)')
end
local function fixture()
    local f = { logs = {}, rays = {}, reads = 0, mutations = 0 }
    local retained = { marker = "preserved" }
    MineCome = { _block_sink = retained, _interactive_input = retained, ProbeGround = retained }
    player = { id = 999, position = { x = 120, y = 2040, z = 56 } }
    f.original_player = player
    function player:GetWorldPos()
        f.reads = f.reads + 1
        if f.on_read then return f.on_read(f.reads, self) end
        return self.position
    end
    local function mutation() f.mutations = f.mutations + 1; error("probe must never mutate") end
    player.SetWorldPos = mutation
    System = { LogAlways = function(line) f.logs[#f.logs + 1] = line end,
        SpawnEntity = mutation, RemoveEntity = mutation,
        GetTerrainElevation = function() error("no extra terrain queries") end }
    Script = { SetTimerForFunction = mutation }
    ent_terrain, ent_all = 256, 287
    Physics = { RayWorldIntersection = function(origin, direction, maximum, mask, skip, skip2, output)
        local index = #f.rays + 1
        f.rays[index] = { origin = origin, direction = direction, maximum = maximum, mask = mask,
            skip = skip, skip2 = skip2, output = output }
        local hit = { pos = { x = origin.x, y = origin.y, z = origin.z - 2 },
            normal = { x = 0, y = 0, z = 1 }, dist = 2 }
        local count = 1
        if f.on_ray then count, hit = f.on_ray(index, hit, origin) end
        output[1] = hit
        return count
    end }
    dofile(MINECOME_MODULE_PATH)
    equal(#f.logs, 0); equal(#f.rays, 0); equal(f.reads, 0)
    equal(MineCome._block_sink, retained); equal(MineCome._interactive_input, retained)
    equal(MineCome.ProbeGround, retained)
    function f:sample(token)
        local ok, result = MineCome.SampleGroundPatch(token or "a1b2")
        equal(ok, true); equal(self.mutations, 0)
        equal(MineCome._block_sink, retained); equal(MineCome._interactive_input, retained)
        return result
    end
    function f:summary(name) return field(self.logs[#self.logs], name) end
    function f:point(index, name) return field(self.logs[index], name) end
    return f
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1; print("PASS " .. name)
end

test("fixed row-major 25-ray terrain-only grid excludes player and copies vectors", function()
    local f = fixture(); local source = player.position
    equal(f:sample(), "sampled"); equal(#f.rays, 25); equal(#f.logs, 26); equal(f.reads, 2)
    for index, ray in ipairs(f.rays) do
        equal(ray.origin.x, 118 + (index - 1) % 5)
        equal(ray.origin.y, 2038 + math.floor((index - 1) / 5)); equal(ray.origin.z, 58)
        equal(ray.direction.x, 0); equal(ray.direction.y, 0); equal(ray.direction.z, -8)
        equal(ray.maximum, 1); equal(ray.mask, 256); equal(ray.skip, 999); equal(ray.skip2, nil)
        assert(ray.origin ~= source)
        for previous = 1, index - 1 do assert(ray.output ~= f.rays[previous].output) end
        equal(f:point(index, "index"), tostring(index)); equal(f:point(index, "z"), "56")
        equal(f:point(index, "valid"), "true"); equal(f:point(index, "mask"), "256")
    end
    equal(player.position, source); equal(source.x, 120); equal(source.z, 56)
    equal(f:summary("point_count"), "25"); equal(f:summary("valid_count"), "25")
    equal(f:summary("stable_player"), "true"); equal(f:summary("approximate_heightfield"), "true")
    equal(f:summary("full_collision_export_verified"), "false")
end)

test("token injection and wrong types never reach bindings or logging", function()
    local f = fixture()
    for _, token in ipairs({ "", "g", "a\n", 'a"', " a", "a ", "-1", "a);bad()", string.rep("a", 65), 1, {}, true }) do
        local ok, reason = MineCome.SampleGroundPatch(token)
        equal(ok, false); equal(reason, "invalid_run")
    end
    equal(MineCome.SampleGroundPatch(nil), false)
    equal(f.reads, 0); equal(#f.rays, 0); equal(#f.logs, 0)
    equal(f:sample("ABCDEF019"), "sampled")
end)

test("menu missing mask and missing ray bindings fail without fallback", function()
    local f = fixture(); player = nil; equal(f:sample(), "no_world")
    equal(#f.rays, 0); equal(f:summary("point_count"), "0")
    f = fixture(); ent_terrain = nil; equal(f:sample(), "terrain_mask_unavailable")
    equal(#f.rays, 0); equal(f:summary("mask"), "null"); equal(ent_all, 287)
    for _, mask in ipairs({ 0, -1, 1.5, "256", math.huge, 2147483648 }) do
        f = fixture(); ent_terrain = mask; equal(f:sample(), "terrain_mask_unavailable"); equal(#f.rays, 0)
    end
    f = fixture(); Physics = nil; equal(f:sample(), "ray_unavailable"); equal(#f.rays, 0)
    f = fixture(); player.id = nil; equal(f:sample(), "skip_id_unavailable"); equal(#f.rays, 0)
end)

test("invalid player positions and entire patch bounds fail before rays", function()
    for _, coordinate in ipairs({ math.huge, -math.huge, "120", 10000001 }) do
        local f = fixture(); player.position.x = coordinate
        equal(f:sample(), "player_position_invalid"); equal(#f.rays, 0)
    end
    local f = fixture(); player.position.x = 0/0
    equal(f:sample(), "player_position_invalid"); equal(#f.rays, 0)
    for _, change in ipairs({ { "x", 9999999 }, { "y", -9999999 }, { "z", 9999999 }, { "z", -9999995 } }) do
        f = fixture(); player.position[change[1]] = change[2]
        equal(f:sample(), "patch_out_of_bounds"); equal(#f.rays, 0)
    end
    f = fixture(); f.on_read = function() error("world lost") end
    equal(f:sample(), "player_position_error"); equal(#f.rays, 0)
end)

test("bounded no-hit output remains null even when output table contains stale hit", function()
    local f = fixture(); f.on_ray = function(_, hit) return 0, hit end
    equal(f:sample(), "no_hits"); equal(f:summary("valid_count"), "0")
    for index = 1, 25 do
        equal(f:point(index, "valid"), "false"); equal(f:point(index, "result"), '"no_hit"')
        equal(f:point(index, "z"), "null"); equal(f:point(index, "nz"), "null")
    end
end)

test("malformed return counts and thrown rays produce bounded per-point diagnostics", function()
    for _, count in ipairs({ -1, 2, 0.5, math.huge, "1", {}, false }) do
        local f = fixture(); f.on_ray = function(_, hit) return count, hit end
        equal(f:sample(), "no_valid_points"); equal(#f.rays, 25)
        equal(f:point(1, "result"), type(count) == "number" and '"ray_count_invalid"' or '"ray_count_unrecognized"')
        equal(f:point(1, "z"), "null"); equal(f:summary("valid_count"), "0")
    end
    local f = fixture(); f.on_ray = function() error("unavailable") end
    equal(f:sample(), "no_valid_points"); equal(f:point(1, "result"), '"ray_error"')
    equal(#f.rays, 25); equal(f:summary("ray_count"), "25")
end)

test("hit fields require finite bounded position distance and physical normal", function()
    local changes = {
        function(hit) hit.pos = nil end, function(hit) hit.normal = nil end,
        function(hit) hit.dist = nil end, function(hit) hit.dist = "2" end,
        function(hit) hit.dist = 8.01 end, function(hit) hit.dist = -0.01 end,
        function(hit) hit.pos.z = 0/0 end, function(hit) hit.normal.x = math.huge end,
        function(hit) hit.normal = { x = 0, y = 0, z = 0 } end,
        function(hit) hit.normal.z = 2 end
    }
    for _, change in ipairs(changes) do
        local f = fixture(); f.on_ray = function(_, hit) change(hit); return 1, hit end
        equal(f:sample(), "no_valid_points"); equal(f:point(1, "result"), '"hit_fields_invalid"')
        equal(f:point(1, "z"), "null")
    end
end)

test("reported hits must lie on the finite downward segment with consistent distance", function()
    for _, change in ipairs({ function(hit) hit.pos.x = hit.pos.x + 0.1 end,
        function(hit) hit.pos.y = hit.pos.y - 0.1 end, function(hit) hit.pos.z = 59 end,
        function(hit) hit.pos.z = 49 end, function(hit) hit.dist = 3 end }) do
        local f = fixture(); f.on_ray = function(_, hit) change(hit); return 1, hit end
        equal(f:sample(), "no_valid_points"); equal(f:point(1, "result"), '"hit_outside_segment"')
    end
end)

test("partial patches preserve exact index and distinguish missing terrain", function()
    local f = fixture(); f.on_ray = function(index, hit)
        if index == 13 then return 0, hit end
        if index == 25 then hit.normal = nil end
        return 1, hit
    end
    equal(f:sample(), "partial"); equal(f:summary("valid_count"), "23")
    equal(f:point(13, "result"), '"no_hit"'); equal(f:point(25, "result"), '"hit_fields_invalid"')
    equal(f:point(12, "valid"), "true")
end)

test("identity id and world changes invalidate every buffered geometry record", function()
    for _, change in ipairs({ function() player = nil end,
        function() player = { id = 999, GetWorldPos = function() return { x = 120, y = 2040, z = 56 } end } end,
        function() player.id = 1000 end }) do
        local f = fixture(); f.on_ray = function(index, hit) if index == 25 then change() end; return 1, hit end
        equal(f:sample(), "player_changed"); equal(f:summary("valid_count"), "0")
        equal(f:summary("stable_player"), "false")
        for index = 1, 25 do equal(f:point(index, "z"), "null"); equal(f:point(index, "valid"), "false") end
    end
end)

test("readback uses Euclidean ten-centimeter bound and retains copied center", function()
    for _, movement in ipairs({ { x = 0.101, y = 0 }, { x = 0.08, y = 0.08 } }) do
        local f = fixture(); f.on_read = function(index, entity)
            if index == 2 then entity.position.x = entity.position.x + movement.x; entity.position.y = entity.position.y + movement.y end
            return entity.position
        end
        equal(f:sample(), "player_changed"); equal(f:point(1, "z"), "null")
        assert(f.logs[26]:find('"center":{"x":120,"y":2040,"z":56}', 1, true))
    end
    local f = fixture(); f.on_read = function(index, entity)
        if index == 2 then return { x = 120.09, y = 2040, z = 56 } end
        return entity.position
    end
    equal(f:sample(), "sampled"); equal(f:summary("stable_player"), "true")
    f = fixture(); f.on_read = function(index, entity) if index == 2 then error("lost") end; return entity.position end
    equal(f:sample(), "player_changed")
end)

test("engine hit aliases and arbitrary metadata never leak into JSON", function()
    local f = fixture(); local reused = { pos = {}, normal = { x = 0, y = 0, z = 1 }, dist = 2,
        entity = { secret = 'bad"value' }, surface = 'bad\nvalue' }
    f.on_ray = function(_, _, origin)
        reused.pos.x, reused.pos.y, reused.pos.z = origin.x, origin.y, origin.z - 2
        return 1, reused
    end
    equal(f:sample(), "sampled")
    equal(f:point(1, "x"), "118"); equal(f:point(25, "x"), "122")
    for _, line in ipairs(f.logs) do assert(not line:find("secret", 1, true)); assert(not line:find("bad", 1, true)) end
end)

test("module reload retains other MineCome state and creates no automatic work", function()
    local f = fixture(); f:sample(); local previous = MineCome.SampleGroundPatch
    dofile(MINECOME_MODULE_PATH)
    assert(previous ~= MineCome.SampleGroundPatch); equal(#f.rays, 25); equal(#f.logs, 26)
    equal(f:sample(), "sampled"); equal(#f.rays, 50)
end)

test("logging failures never emit a successful summary or schedule cleanup", function()
    local f = fixture(); System.LogAlways = nil
    local ok, reason = MineCome.SampleGroundPatch("a1"); equal(ok, false); equal(reason, "log_unavailable")
    equal(#f.rays, 0); equal(f.reads, 0)
    f = fixture(); System.LogAlways = function() error("log unavailable") end
    ok, reason = MineCome.SampleGroundPatch("a1"); equal(ok, false); equal(reason, "log_failed")
    equal(#f.rays, 25); equal(#f.logs, 0); equal(f.mutations, 0)
    f = fixture(); System.LogAlways = function(line)
        if #f.logs == 7 then return false end
        f.logs[#f.logs + 1] = line
    end
    ok, reason = MineCome.SampleGroundPatch("a1"); equal(ok, false); equal(reason, "log_failed")
    equal(#f.logs, 7); assert(not f.logs[7]:find("[MineComeGroundPatch]", 1, true))
end)

print(string.format("Verified %d standalone ground-patch cases in %s; engine bindings simulated", passed, _VERSION))
