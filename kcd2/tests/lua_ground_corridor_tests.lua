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
        local ok, result = MineCome.SampleGroundCorridor(token or "a1b2")
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

test("two anchored wide tiles use162 private terrain rays without moving player", function()
    local f=fixture();local original=player.position
    equal(f:sample(),"sampled");equal(#f.rays,162);equal(#f.logs,163);equal(f.reads,2)
    equal(f:summary("tile_count"),"2");equal(f:summary("valid_count"),"162");equal(f:summary("stable_player"),"true")
    for index,ray in ipairs(f.rays) do
        local tile=math.floor((index-1)/81);local n=(index-1)%81
        equal(ray.origin.x,116+tile*4+n%9);equal(ray.origin.y,2036+math.floor(n/9));equal(ray.origin.z,58)
        equal(ray.direction.z,-8);equal(ray.maximum,1);equal(ray.mask,256);equal(ray.skip,999)
        equal(f:point(index,"tile"),tostring(tile));equal(f:point(index,"index"),tostring(n+1))
        assert(ray.origin~=original and ray.output~=f.rays[math.max(1,index-1)].output or index==1)
    end
    equal(player.position,original);equal(f.mutations,0)
end)
test("readback checks original anchor rather than second tile center", function()
    local f=fixture();f.on_read=function(n,p) return {x=120,y=2040,z=56} end
    equal(f:sample(),"sampled");equal(f:summary("stable_player"),"true")
end)
test("player movement invalidates every private sample", function()
    local f=fixture();f.on_read=function(n,p) return {x=n==1 and 120 or 120.2,y=2040,z=56} end
    equal(f:sample(),"player_changed");equal(f:summary("valid_count"),"0")
    for i=1,162 do equal(f:point(i,"valid"),"false");equal(f:point(i,"z"),"null") end
end)
test("identity swap during capture is refused", function()
    local f=fixture();f.on_ray=function(n,hit) if n==100 then player={id=1000} end;return 1,hit end
    equal(f:sample(),"player_changed");equal(f:summary("stable_player"),"false")
end)
test("partial second tile remains diagnostic only", function()
    local f=fixture();f.on_ray=function(n,hit) if n==120 then return 0,nil end;return 1,hit end
    equal(f:sample(),"partial");equal(f:summary("valid_count"),"161")
end)
test("full eastward bounds are checked before first ray", function()
    local f=fixture();player.position.x=9999993
    equal(f:sample(),"patch_out_of_bounds");equal(#f.rays,0)
end)
test("bad run and unavailable exported mask cannot cast", function()
    local f=fixture();local ok=MineCome.SampleGroundCorridor("not-a-token")
    equal(ok,false);equal(#f.rays,0);ent_terrain=nil
    equal(f:sample(),"terrain_mask_unavailable");equal(#f.rays,0)
end)
test("ray segment violation cannot enter accepted tiles", function()
    local f=fixture();f.on_ray=function(n,hit) if n==100 then hit.pos.x=hit.pos.x+1 end;return 1,hit end
    equal(f:sample(),"partial");equal(f:point(100,"result"),'"hit_outside_segment"')
end)
print("LUA_GROUND_CORRIDOR_TESTS_PASS tests="..passed)
