-- SPDX-License-Identifier: GPL-3.0-or-later
-- Opt-in, temporary sys_MaxFPS=60 comparison. No automatic work on load.
-- Inspected kcd2-mod-docs 9cb067543245ec5cf4e27b3d21e32485a35db518:
-- script_bind_2025_01_14/CScriptBindSystem__{Get,Set}CVar@IFunctionHandler__.html
-- documents System.GetCVar(name)/SetCVar(name,value). SetTimerForFunction
-- ...@IFunctionHandler__@int@char__.html:70-110 documents userdata, returned
-- ScriptHandle and bUpdateDuringPause; KillTimer...@ScriptHandle.html:70-84.
-- Timers run on the engine script thread; process/engine stalls can delay them.
-- This is an engine timer lease, not an independent UTC watchdog.

MineCome = MineCome or {}
assert(type(MineCome) == "table", "MineCome namespace unavailable")
local root = MineCome
local state = root._hud_gpu_budget
if state == nil then
    assert(MineCome_HudGpuBudgetTimer == nil, "GPU budget callback already owned")
    state = { schema = 1, owner = "minecome_hud_gpu_budget_v1" }
    root._hud_gpu_budget = state
else
    assert(type(state) == "table" and state.owner == "minecome_hud_gpu_budget_v1"
        and state.callback == MineCome_HudGpuBudgetTimer, "GPU budget state already owned")
end
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function token(v) return type(v) == "string" and #v == 32 and v:match("^[0-9a-f]+$") ~= nil end
local function handle(v) return type(v) == "userdata" or (finite(v) and v > 0 and v == math.floor(v)) end
local function owned() return MineCome == root and root._hud_gpu_budget == state and MineCome_HudGpuBudgetTimer == state.callback end
local function quote(v) return '"' .. tostring(v):gsub('[%z\1-\31\\"]', function(c) return string.format("\\u%04x", string.byte(c)) end) .. '"' end
local function num(v) return finite(v) and string.format("%.17g", v) or "null" end
local function read(name)
    if not System or type(System.GetCVar) ~= "function" then return nil end
    local ok, value = pcall(System.GetCVar, name)
    return ok and finite(value) and value or nil
end
local function now()
    if not System or type(System.GetCurrTime) ~= "function" then return nil end
    local ok, value = pcall(System.GetCurrTime)
    return ok and finite(value) and value >= 0 and value < 1000000000000 and value or nil
end
local function snapshot(p, stage)
    return { schema=1, run=p.run, stage=stage, reason=p.reason or "queued", original_fps=p.original,
        requested_fps=60, current_fps=read("sys_MaxFPS"), active=state.active==p and not p.terminal,
        restored=p.restored==true, restore_attempted=p.restore_attempted==true,
        restore_result=p.restore_result or "not_attempted", expired=p.expired==true,
        applied=p.applied==true, write_attempted=p.write_attempted==true,
        timer_armed=handle(p.timers.expiry), timer_cancelled=p.timer_cancelled~=false,
        created_engine_seconds=p.created, deadline_engine_seconds=p.deadline, duration_ms=p.duration }
end
local function emit(p, stage)
    local s = snapshot(p, stage)
    if not System or type(System.LogAlways) ~= "function" then return false, s end
    local text = '{"schema":1,"run":'..quote(s.run)..',"stage":'..quote(s.stage)..',"reason":'..quote(s.reason)
        ..',"original_fps":'..num(s.original_fps)..',"requested_fps":60,"current_fps":'..num(s.current_fps)
        ..',"active":'..tostring(s.active)..',"restored":'..tostring(s.restored)
        ..',"restore_attempted":'..tostring(s.restore_attempted)..',"restore_result":'..quote(s.restore_result)
        ..',"expired":'..tostring(s.expired)..',"applied":'..tostring(s.applied)..',"write_attempted":'..tostring(s.write_attempted)
        ..',"timer_armed":'..tostring(s.timer_armed)..',"timer_cancelled":'..tostring(s.timer_cancelled)
        ..',"created_engine_seconds":'..num(s.created_engine_seconds)..',"deadline_engine_seconds":'..num(s.deadline_engine_seconds)
        ..',"duration_ms":'..num(s.duration_ms)..'}'
    local ok, result = pcall(System.LogAlways, "[MineComeHudGpuBudget] "..text)
    return ok and result ~= false, s
end
local function cancel(p)
    for slot, id in pairs(p.timers) do
        p.timers[slot] = nil
        local ok, result = false, nil
        if Script and type(Script.KillTimer) == "function" then ok, result = pcall(Script.KillTimer, id) end
        if not ok or result == false then p.timer_cancelled = false end
    end
end
local function finish(p, reason, expired)
    if state.active ~= p or p.terminal then return false end
    p.reason, p.expired = reason, expired == true
    local current = read("sys_MaxFPS")
    if not p.write_attempted then p.restore_result = "not_attempted"
    elseif current == p.original then p.restored, p.restore_result = true, "already_original"
    elseif current == nil then p.restore_result = "current_unavailable"
    elseif current ~= 60 then p.restore_result = "external_change_preserved"
    else
        p.restore_attempted = true
        local ok, result = false, nil
        if System and type(System.SetCVar) == "function" then ok, result = pcall(System.SetCVar, "sys_MaxFPS", p.original) end
        -- Readback is mandatory even if the binding throws after changing the CVar.
        p.restored = read("sys_MaxFPS") == p.original
        p.restore_result = p.restored and "restored" or "readback_failed"
        p.restore_call_ok = ok and result ~= false
    end
    p.terminal = true
    cancel(p)
    state.active, state.last = nil, p
    local logged = emit(p, "terminal")
    return p.restored == true and logged, p.reason
end
local function arm(p, slot, delay)
    local data = { probe=p, slot=slot }; p.data[slot] = data
    local ok, id = pcall(Script.SetTimerForFunction, delay, "MineCome_HudGpuBudgetTimer", data, true)
    if not ok or not handle(id) then p.data[slot] = nil; return false end
    p.timers[slot] = id
    return true
end
local function clock_reason(p)
    local clock = now()
    if not clock then return "clock_unavailable" end
    if clock < p.created or clock < p.last_clock then return "clock_regressed" end
    p.last_clock = clock
    if clock >= p.deadline then return "engine_lease_expired" end
end
function MineCome.BeginHudGpuBudget(run, durationMs, fps)
    if not token(run) then return false, "invalid_run" end
    if not owned() then return false, "ownership_lost" end
    if state.active then return false, "busy" end
    if state.last and state.last.run == run then return false, "run_consumed" end
    if not finite(durationMs) or durationMs ~= math.floor(durationMs) or durationMs < 2 or durationMs > 120000 or fps ~= 60 then return false, "invalid_budget" end
    local p = {run=run, duration=durationMs, timers={}, data={}, timer_cancelled=true, created=now(), original=read("sys_MaxFPS")}
    p.last_clock = p.created
    p.deadline = p.created and p.created + durationMs/1000 or nil
    local reason
    if not p.created then reason = "clock_unavailable"
    elseif p.original == nil then reason = "original_unavailable"
    elseif p.original > 0 and p.original <= 60 then reason = "original_not_above_budget"
    elseif read("r_VSync") ~= 0 then reason = "vsync_not_disabled"
    elseif not System or type(System.SetCVar) ~= "function" or type(System.LogAlways) ~= "function" then reason = "binding_unavailable"
    elseif not Script or type(Script.SetTimerForFunction) ~= "function" or type(Script.KillTimer) ~= "function" then reason = "timer_unavailable" end
    if reason then p.reason=reason; emit(p,"rejected"); return false,reason end
    state.active = p
    -- The immutable expiry is armed before the engine-thread apply callback.
    if not arm(p,"expiry",durationMs) or not arm(p,"apply",1) then finish(p,"timer_arm_failed",false); return false,"timer_arm_failed" end
    if not emit(p,"queued") then finish(p,"log_failed",false); return false,"log_failed" end
    return true,"queued"
end
function MineCome_HudGpuBudgetTimer(data)
    if type(data) ~= "table" or type(data.probe) ~= "table" then return false end
    local p, slot = data.probe, data.slot
    if not owned() or state.active ~= p or p.terminal or p.data[slot] ~= data or not handle(p.timers[slot]) then return false end
    p.timers[slot] = nil -- Timer has fired; never cancel a consumed handle.
    if slot == "expiry" then return finish(p,"timer_expired",true) end
    local reason = clock_reason(p)
    if reason then return finish(p,reason,true) end
    if read("sys_MaxFPS") ~= p.original or read("r_VSync") ~= 0 then return finish(p,"preapply_changed",false) end
    p.write_attempted = true
    local ok, result = pcall(System.SetCVar,"sys_MaxFPS",60)
    local current = read("sys_MaxFPS")
    reason = clock_reason(p)
    if reason then return finish(p,reason,true) end
    if not ok or result == false or current ~= 60 then return finish(p,"apply_failed",false) end
    p.applied, p.reason = true, "applied"
    if not emit(p,"applied") then return finish(p,"log_failed",false) end
    return true
end
state.callback = MineCome_HudGpuBudgetTimer
function MineCome.EndHudGpuBudget(run)
    if not token(run) then return false,"invalid_run" end
    if not owned() then return false,"ownership_lost" end
    local p = state.active or state.last
    if not p or p.run ~= run then return false,"run_mismatch" end
    if p.terminal then local logged=emit(p,"terminal");return p.restored==true and logged,p.reason end
    local reason = clock_reason(p)
    return finish(p,reason or "requested_end",reason~=nil)
end
function MineCome.HudGpuBudgetStatus(run)
    if not token(run) then return false,"invalid_run" end
    if not owned() then return false,"ownership_lost" end
    local p = state.active or state.last
    if not p or p.run ~= run then return false,"run_mismatch" end
    -- Fresh copied snapshot only; this cannot renew or modify the lease.
    local logged, receipt = emit(p,"status")
    return logged,receipt
end
