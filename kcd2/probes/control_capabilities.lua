-- SPDX-License-Identifier: GPL-3.0-or-later
-- Original explicit READ-ONLY capability probe. Module load calls no engine API.
-- Pinned kcd2-mod-docs9cb067543245ec5cf4e27b3d21e32485a35db518:
-- script_bind_2025_01_14 ActionMapManager.EnableActionFilter/IsFilterEnabled/
-- EnableActionMapManager; C_ScriptBind_GameRules FreezeInput and IsFrozen;
-- Entity.EnablePhysics; actor/player/human getters; Game.IsLoadingEngineSaveGame;
-- Calendar.IsWorldTimePaused; CScriptBindAction.IsGameStarted (actual CryAction
-- namespace in lua_dump_state/LuaState_Sorted.txt:5975,6005).
-- Installed tools Scripts.pak BasicAIActions.lua:44,80; RuntimePrefab.lua:21;
-- TriggerBase.lua:464. g_gameRules.game is the stock game-rules binding owner
-- (SinglePlayer.lua:192,203,261); global GameRules is reported independently.
-- FreezeInput(bool) is a mutator; IsFrozen(entityId) describes entity freezing,
-- not the prior input-freeze state. Their method TYPES alone are reported.
-- This probe does not establish menu/cutscene safety or reversible ownership.

if MineCome == nil then MineCome = {} end
assert(type(MineCome) == "table", "MineCome namespace is not a table")

local function lookup(owner, name)
    if type(owner) ~= "table" and type(owner) ~= "userdata" then return nil, true end
    local ok, value = pcall(function() return owner[name] end)
    if ok then return value, true end
    return nil, false
end
local function quote(value) return '"' .. value .. '"' end -- only fixed names/Lua types/validated hex
local function method(owner, name)
    local fn, ok = lookup(owner, name)
    return { owner = owner, name = name, fn = fn, lookup_ok = ok, method_type = ok and type(fn) or "error" }
end
local function descriptor(m, global)
    local result = { method_type = m.method_type, ok = false, value_type = "nil" }
    if m.method_type ~= "function" then
        if not m.lookup_ok then result.value_type = "error" end
        return result
    end
    local ok, value
    if global then ok, value = pcall(m.fn) else ok, value = pcall(m.fn, m.owner) end
    result.value_type = ok and type(value) or "error"
    result.ok = ok and type(value) == "boolean"
    if result.ok then result.value = value end
    return result
end
local function descriptor_json(d)
    local value = "null"
    if d.ok and type(d.value) == "boolean" then value = tostring(d.value) end
    return '{"method_type":' .. quote(d.method_type) .. ',"ok":' .. tostring(d.ok)
        .. ',"value_type":' .. quote(d.value_type) .. ',"value":' .. value .. '}'
end

function MineCome.ProbeControlCapabilities(run)
    if type(run) ~= "string" or #run ~= 32 or not run:match("^[0-9a-f]+$") then return false, "invalid_run" end
    local system = rawget(_G, "System")
    local log, log_ok = lookup(system, "LogAlways")
    if not log_ok or type(log) ~= "function" then return false, "log_unavailable" end
    local entity = rawget(_G, "player")
    local id, id_ok = lookup(entity, "id")
    local actor, actor_ok = lookup(entity, "actor")
    local player_methods, player_methods_ok = lookup(entity, "player")
    local human, human_ok = lookup(entity, "human")
    local manager = rawget(_G, "ActionMapManager")
    local global_rules = rawget(_G, "GameRules")
    local game_rules = rawget(_G, "g_gameRules")
    local bound_rules, bound_rules_ok = lookup(game_rules, "game")
    local game, calendar, action = rawget(_G, "Game"), rawget(_G, "Calendar"), rawget(_G, "CryAction")
    local all_methods = {}
    local function capture(owner, name)
        local m = method(owner, name); all_methods[#all_methods + 1] = m; return m
    end
    local groups = {
        { name = "action_map_manager", owner = manager, methods = {
            capture(manager, "EnableActionFilter"), capture(manager, "IsFilterEnabled"), capture(manager, "EnableActionMapManager") } },
        { name = "global_game_rules", owner = global_rules, methods = {
            capture(global_rules, "FreezeInput"), capture(global_rules, "IsFrozen") } },
        { name = "game_rules_game", owner = bound_rules, methods = {
            capture(bound_rules, "FreezeInput"), capture(bound_rules, "IsFrozen") } },
        { name = "player", owner = entity, methods = { capture(entity, "EnablePhysics") } }
    }
    local guards = {
        { name = "dead", m = capture(actor, "IsDead") },
        { name = "unconscious", m = capture(actor, "IsUnconscious") },
        { name = "sitting", m = capture(player_methods, "IsSitting") },
        { name = "laying", m = capture(player_methods, "IsLaying") },
        { name = "mounted", m = capture(human, "IsMounted") },
        { name = "in_dialog", m = capture(human, "IsInDialog") },
        { name = "loading_engine_save", m = capture(game, "IsLoadingEngineSaveGame"), global = true },
        { name = "world_time_paused", m = capture(calendar, "IsWorldTimePaused"), global = true },
        { name = "game_started", m = capture(action, "IsGameStarted"), global = true }
    }
    local function identity()
        local current_id, ok = lookup(entity, "id")
        return id_ok and ok and type(id) == "userdata" and rawequal(rawget(_G, "player"), entity) and rawequal(current_id, id)
    end
    local function references()
        if not actor_ok or not player_methods_ok or not human_ok or not bound_rules_ok then return false end
        local current_id, current_id_ok = lookup(entity, "id")
        if not rawequal(rawget(_G, "player"), entity) or current_id_ok ~= id_ok or not rawequal(current_id, id)
            or not rawequal(rawget(_G, "System"), system) or not rawequal(lookup(system, "LogAlways"), log)
            or not rawequal(rawget(_G, "ActionMapManager"), manager)
            or not rawequal(rawget(_G, "GameRules"), global_rules)
            or not rawequal(rawget(_G, "g_gameRules"), game_rules)
            or not rawequal(lookup(game_rules, "game"), bound_rules)
            or not rawequal(lookup(entity, "actor"), actor)
            or not rawequal(lookup(entity, "player"), player_methods)
            or not rawequal(lookup(entity, "human"), human)
            or not rawequal(rawget(_G, "Game"), game)
            or not rawequal(rawget(_G, "Calendar"), calendar)
            or not rawequal(rawget(_G, "CryAction"), action) then return false end
        for _, m in ipairs(all_methods) do
            local current, ok = lookup(m.owner, m.name)
            if ok ~= m.lookup_ok or not rawequal(current, m.fn) then return false end
        end
        return true
    end
    local stable_identity, stable_references = identity(), references()
    for _, guard in ipairs(guards) do
        -- Never continue any reads after a player/id/owner transition. Global
        -- reads can describe an initially missing-world sample, before any change.
        if stable_references and (guard.global or stable_identity) then guard.result = descriptor(guard.m, guard.global)
        else guard.result = { method_type = guard.m.method_type, ok = false, value_type = "nil" } end
        stable_identity = stable_identity and identity()
        stable_references = stable_references and references()
    end
    if not stable_identity or not stable_references then
        for _, guard in ipairs(guards) do guard.result.ok = false; guard.result.value = nil end
    end
    local type_json = {}
    for _, group in ipairs(groups) do
        local parts = { '"owner_type":' .. quote(type(group.owner)) }
        for _, m in ipairs(group.methods) do parts[#parts + 1] = quote(m.name) .. ':' .. quote(m.method_type) end
        type_json[#type_json + 1] = quote(group.name) .. ':{' .. table.concat(parts, ',') .. '}'
    end
    local guard_json = {}
    for _, guard in ipairs(guards) do guard_json[#guard_json + 1] = quote(guard.name) .. ':' .. descriptor_json(guard.result) end
    local line = '[MineComeControlCapabilities] {"schema":1,"run":' .. quote(run)
        .. ',"identity_stable":' .. tostring(stable_identity) .. ',"entity_id_type":' .. quote(type(id))
        .. ',"references_stable":' .. tostring(stable_references)
        .. ',"function_types":{' .. table.concat(type_json, ',') .. '},"guards":{' .. table.concat(guard_json, ',') .. '}'
        .. ',"ownership_verified":false,"restoration_verified":false,"is_frozen_is_input_state":false}'
    if #line > 4096 then return false, "receipt_too_large" end
    local ok, result = pcall(log, line)
    return ok and result ~= false, ok and result ~= false and "sampled" or "log_failed"
end
