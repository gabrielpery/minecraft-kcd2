-- SPDX-License-Identifier: GPL-3.0-or-later
-- Original explicitly invoked read-only approximate terrain sampler.
-- Binding evidence matches probes/ground_probe.lua:
-- kcd2-mod-docs commit 9cb067543245ec5cf4e27b3d21e32485a35db518,
-- script_bind_2025_01_14/CScriptBindPhysics__RayWorldIntersection@IFunctionHandler_.html:107.
-- Installed official KCD2Mod 1.5.5 Data/Scripts.pak:
-- Scripts/Entities/Physics/PressurizedObject.lua:308-310 passes a range-scaled
-- direction, max hits, exported mask, skip id, nil and private output table;
-- the returned integer count indexes output entries with pos/normal/dist.
-- libKCD2 commit 10d20f28faba462c4bf98a01abb48225cc51bb91:
-- include/CryEngine/CryCommon/physinterface.h:2393-2395 declares ent_terrain.
-- The mask below uses only the actual exported Lua constant, never a bit guess.
-- Official output field documentation:
-- https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1638401/pages/1933330
-- This has no auto-load calls, writes to entities/positions/world, timers or
-- shared hit table. It cannot describe walls, ceilings, bridges or full meshes.

MineCome = MineCome or {}
local RANGE, MAX_POSITION = 8, 10000000
local SEGMENT_TOLERANCE, READBACK_LIMIT = 0.05, 0.1

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function position(value)
    return type(value) == "table" and finite(value.x) and finite(value.y) and finite(value.z)
        and math.abs(value.x) <= MAX_POSITION and math.abs(value.y) <= MAX_POSITION
        and math.abs(value.z) <= MAX_POSITION
end

local function normal(value)
    if not position(value) or math.abs(value.x) > 1.01 or math.abs(value.y) > 1.01
        or math.abs(value.z) > 1.01 then return false end
    local length_squared = value.x * value.x + value.y * value.y + value.z * value.z
    return length_squared >= 0.81 and length_squared <= 1.21
end

local function number_json(value)
    return finite(value) and string.format("%.17g", value) or "null"
end

local function vector_json(value)
    if not position(value) then return "null" end
    return string.format('{"x":%.17g,"y":%.17g,"z":%.17g}', value.x, value.y, value.z)
end

local function emit(line)
    local ok, result = pcall(System.LogAlways, line)
    return ok and result ~= false
end

local function unchanged(expected_player, expected_id, center)
    if player ~= expected_player or expected_player.id ~= expected_id
        or type(expected_player.GetWorldPos) ~= "function" then return false end
    local ok, value = pcall(function() return expected_player:GetWorldPos() end)
    if not ok or not position(value) or player ~= expected_player or expected_player.id ~= expected_id then
        return false
    end
    local dx, dy, dz = value.x - center.x, value.y - center.y, value.z - center.z
    return dx * dx + dy * dy + dz * dz <= READBACK_LIMIT * READBACK_LIMIT
end

function MineCome.SampleGroundPatch(runToken, walking_area)
    if type(runToken) ~= "string" or #runToken < 1 or #runToken > 64
        or not string.match(runToken, "^[0-9a-fA-F]+$") then return false, "invalid_run" end
    if walking_area ~= nil and walking_area ~= "wide" then return false, "invalid_walking_area" end
    local grid_size = walking_area == "wide" and 9 or 5
    local radius = (grid_size - 1) / 2
    if not System or type(System.LogAlways) ~= "function" then return false, "log_unavailable" end

    local center, mask, expected_player, expected_id
    local result, stable = "no_world", false
    local points, rays, valid_count = {}, 0, 0
    if player and type(player.GetWorldPos) == "function" then
        expected_player, expected_id = player, player.id
        local ok, value = pcall(function() return expected_player:GetWorldPos() end)
        if not ok then result = "player_position_error"
        elseif not position(value) then result = "player_position_invalid"
        else
            center = { x = value.x, y = value.y, z = value.z }
            if expected_id == nil then result = "skip_id_unavailable"
            elseif player ~= expected_player or expected_player.id ~= expected_id then result = "player_changed"
            elseif not Physics or type(Physics.RayWorldIntersection) ~= "function" then result = "ray_unavailable"
            elseif not finite(ent_terrain) or ent_terrain <= 0 or ent_terrain > 2147483647
                or ent_terrain ~= math.floor(ent_terrain) then result = "terrain_mask_unavailable"
            elseif math.abs(center.x) + radius > MAX_POSITION or math.abs(center.y) + radius > MAX_POSITION
                or center.z + 2 > MAX_POSITION or center.z - 6 < -MAX_POSITION then result = "patch_out_of_bounds"
            else
                mask = ent_terrain
                -- Row-major KCD XY offsets; one immutable center for all rays.
                -- Results remain private until identity/position readback succeeds.
                for offset_y = -radius, radius do
                    for offset_x = -radius, radius do
                        local point = { x = center.x + offset_x, y = center.y + offset_y,
                            valid = false, result = "ray_error" }
                        local origin_z, hits = center.z + 2, {}
                        local ray_ok, count = pcall(Physics.RayWorldIntersection,
                            { x = point.x, y = point.y, z = origin_z },
                            { x = 0, y = 0, z = -RANGE }, 1, mask, expected_id, nil, hits)
                        rays = rays + 1
                        if not ray_ok then point.result = "ray_error"
                        elseif type(count) ~= "number" then point.result = "ray_count_unrecognized"
                        elseif not finite(count) or (count ~= 0 and count ~= 1) then point.result = "ray_count_invalid"
                        elseif count == 0 then point.result = "no_hit"
                        else
                            local hit = hits[1]
                            if type(hit) ~= "table" or not position(hit.pos) or not normal(hit.normal)
                                or not finite(hit.dist) or hit.dist < 0 or hit.dist > RANGE then
                                point.result = "hit_fields_invalid"
                            elseif math.abs(hit.pos.x - point.x) > SEGMENT_TOLERANCE
                                or math.abs(hit.pos.y - point.y) > SEGMENT_TOLERANCE
                                or hit.pos.z > origin_z + SEGMENT_TOLERANCE
                                or hit.pos.z < origin_z - RANGE - SEGMENT_TOLERANCE
                                or math.abs(origin_z - hit.pos.z - hit.dist) > 0.1 then
                                point.result = "hit_outside_segment"
                            else
                                point.valid, point.result = true, "hit"
                                point.z, point.nx, point.ny, point.nz = hit.pos.z, hit.normal.x, hit.normal.y, hit.normal.z
                                valid_count = valid_count + 1
                            end
                        end
                        points[#points + 1] = point
                    end
                end
                stable = unchanged(expected_player, expected_id, center)
                if not stable then
                    result, valid_count = "player_changed", 0
                    for _, point in ipairs(points) do
                        point.valid, point.result = false, "player_changed"
                        point.z, point.nx, point.ny, point.nz = nil, nil, nil, nil
                    end
                elseif valid_count == grid_size * grid_size then result = "sampled"
                elseif valid_count > 0 then result = "partial"
                else
                    result = "no_hits"
                    for _, point in ipairs(points) do
                        if point.result ~= "no_hit" then result = "no_valid_points"; break end
                    end
                end
            end
        end
    end

    for index, point in ipairs(points) do
        local line = string.format(
            '[MineComeGroundPatchPoint] {"schema":1,"run":"%s","index":%d,"x":%s,"y":%s,"z":%s,"nx":%s,"ny":%s,"nz":%s,"mask":%s,"valid":%s,"result":"%s","approximate_heightfield":true,"full_collision_export_verified":false}',
            runToken, index, number_json(point.x), number_json(point.y), number_json(point.z),
            number_json(point.nx), number_json(point.ny), number_json(point.nz), number_json(mask),
            tostring(point.valid), point.result)
        if not emit(line) then return false, "log_failed" end
    end
    local line = string.format(
        '[MineComeGroundPatch] {"schema":1,"run":"%s","result":"%s","center":%s,"grid_size":%d,"spacing":1,"point_count":%d,"valid_count":%d,"ray_count":%d,"mask_name":"ent_terrain","mask":%s,"stable_player":%s,"approximate_heightfield":true,"full_collision_export_verified":false%s}',
        runToken, result, vector_json(center), grid_size, #points, valid_count, rays, number_json(mask), tostring(stable),
        walking_area == "wide" and ',"walking_area":"wide"' or "")
    if not emit(line) then return false, "log_failed" end
    return true, result
end
