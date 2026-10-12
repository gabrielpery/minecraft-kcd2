-- SPDX-License-Identifier: GPL-3.0-or-later
-- Original read-only diagnostic; deliberately separate from the loaded mod.
-- Warhorse binding dump pinned at kcd2-mod-docs commit
-- 9cb067543245ec5cf4e27b3d21e32485a35db518, script_bind_2025_01_14:
-- CScriptBindPhysics__RayWorldIntersection@IFunctionHandler_.html:107
-- CScriptBindSystem__GetTerrainElevation@IFunctionHandler__.html:82
-- Installed official KCD2Mod 1.5.5 Data/Scripts.pak primary usage:
-- Scripts/Entities/Physics/PressurizedObject.lua:308-310 supplies direction *
-- range, maxHits, exported ent_all, skip id, nil, output table; returns count.
-- Official CryEngine Common Lua documents output pos/normal/dist/surface/entity:
-- https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1638401/pages/1933330
-- Those fields are checked, never guessed. This is not geometry extraction,
-- a collision controller, or evidence that guest movement follows host terrain.
-- No auto-load, shared global hit table, entity/position writes or timers.

MineCome = MineCome or {}
local RANGE = 8
local MAX_HITS = 4
local MAX_POSITION = 10000000

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function position(value)
    return type(value) == "table" and finite(value.x) and finite(value.y) and finite(value.z)
        and math.abs(value.x) <= MAX_POSITION and math.abs(value.y) <= MAX_POSITION
        and math.abs(value.z) <= MAX_POSITION
end

local function number_json(value)
    return finite(value) and string.format("%.17g", value) or "null"
end

local function vector_json(value)
    if not position(value) then return "null" end
    return string.format('{"x":%.17g,"y":%.17g,"z":%.17g}', value.x, value.y, value.z)
end

local function mask_value(value)
    return finite(value) and value > 0 and value <= 2147483647 and value == math.floor(value)
end

local function field_names(hit)
    if type(hit) ~= "table" then return "[]" end
    local names = {}
    -- Inspect only the finite documented schema; never enumerate engine entity
    -- objects or stringify arbitrary keys/values into the log.
    for _, name in ipairs({ "pos", "normal", "dist", "surface", "entity" }) do
        if hit[name] ~= nil then names[#names + 1] = '"' .. name .. '"' end
    end
    return "[" .. table.concat(names, ",") .. "]"
end

function MineCome.ProbeGround(runToken)
    if type(runToken) ~= "string" or #runToken < 1 or #runToken > 64
        or not string.match(runToken, "^[0-9a-fA-F]+$") then
        return false, "invalid_run"
    end
    if not System or type(System.LogAlways) ~= "function" then return false, "log_unavailable" end
    local player_position, origin, hit, count, mask
    local mask_name, result, terrain_result = "unavailable", "no_world", "unavailable"
    local count_type = "unavailable"
    local terrain_elevation
    local skipped_player = false
    if player and type(player.GetWorldPos) == "function" then
        local ok, value = pcall(function() return player:GetWorldPos() end)
        if ok and position(value) then
            -- Copy the engine-owned vector; adding the ray offset must not
            -- mutate the player's returned position table.
            player_position = { x = value.x, y = value.y, z = value.z }
            origin = { x = value.x, y = value.y, z = value.z + 1 }
            if type(System.GetTerrainElevation) == "function" then
                local terrain_ok, elevation = pcall(System.GetTerrainElevation,
                    { x = value.x, y = value.y, z = value.z })
                if not terrain_ok then terrain_result = "error"
                elseif not finite(elevation) or math.abs(elevation) > MAX_POSITION then terrain_result = "invalid"
                else terrain_result = "value"; terrain_elevation = elevation end
            end
            if mask_value(ent_terrain) then mask, mask_name = ent_terrain, "ent_terrain"
            elseif mask_value(ent_all) then mask, mask_name = ent_all, "ent_all" end
            if not position(origin) then result = "origin_out_of_bounds"
            elseif player.id == nil then result = "skip_id_unavailable"
            elseif not Physics or type(Physics.RayWorldIntersection) ~= "function" then result = "ray_unavailable"
            elseif not mask then result = "mask_unavailable"
            else
                local hits = {}
                -- Match the inspected installed usage exactly, with a private
                -- output table and only one finite downward ray.
                local ray_ok, ray_count = pcall(Physics.RayWorldIntersection, origin,
                    { x = 0, y = 0, z = -RANGE }, MAX_HITS, mask, player.id, nil, hits)
                skipped_player = true
                if not ray_ok then result = "ray_error"
                else
                    count_type = type(ray_count)
                    -- Even an unfamiliar return form can expose only the
                    -- bounded documented field names/types for diagnosis.
                    hit = hits[1]
                end
                if ray_ok and type(ray_count) ~= "number" then result = "ray_count_unrecognized"
                elseif ray_ok and (not finite(ray_count) or ray_count < 0 or ray_count > MAX_HITS
                    or ray_count ~= math.floor(ray_count)) then result = "ray_count_invalid"
                elseif ray_ok then
                    count = ray_count
                    if count == 0 then result = "no_hit"
                    else
                        if type(hit) ~= "table" or not position(hit.pos) or not position(hit.normal)
                            or not finite(hit.dist) or hit.dist < 0 or hit.dist > RANGE + 0.05 then
                            result = "hit_fields_invalid"
                        elseif math.abs(hit.pos.x - origin.x) > 0.05 or math.abs(hit.pos.y - origin.y) > 0.05
                            or hit.pos.z > origin.z + 0.05 or hit.pos.z < origin.z - RANGE - 0.05 then
                            result = "hit_outside_segment"
                        else result = "hit" end
                    end
                end
            end
        else result = ok and "player_position_invalid" or "player_position_error" end
    end
    local valid_hit = result == "hit" and hit or nil
    local types = type(hit) == "table" and string.format(
        '{"pos":"%s","normal":"%s","dist":"%s","surface":"%s","entity":"%s"}',
        type(hit.pos), type(hit.normal), type(hit.dist), type(hit.surface), type(hit.entity)) or "null"
    local line = string.format(
        '[MineComeGroundProbe] {"schema":1,"run":"%s","result":"%s","player":%s,"origin":%s,"direction":{"x":0,"y":0,"z":-8},"max_hits":4,"mask_name":"%s","mask":%s,"skip_player":%s,"hit_count":%s,"hit_count_type":"%s","hit_fields":%s,"hit_field_types":%s,"hit_position":%s,"hit_normal":%s,"hit_distance":%s,"terrain_result":"%s","terrain_elevation":%s,"hit_minus_terrain":%s,"diagnostic_only":true,"geometry_export_verified":false}',
        runToken, result, vector_json(player_position), vector_json(origin), mask_name, number_json(mask),
        tostring(skipped_player), number_json(count), count_type, field_names(hit), types,
        vector_json(valid_hit and valid_hit.pos), vector_json(valid_hit and valid_hit.normal),
        number_json(valid_hit and valid_hit.dist), terrain_result, number_json(terrain_elevation),
        number_json(valid_hit and terrain_elevation and valid_hit.pos.z - terrain_elevation))
    local ok, logged = pcall(System.LogAlways, line)
    if not ok or logged == false then return false, "log_failed" end
    return true, result
end
