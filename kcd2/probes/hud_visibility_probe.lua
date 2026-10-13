-- SPDX-License-Identifier: GPL-3.0-or-later
-- Opt-in whole-HUD visibility lease; also may affect subtitles/dialogue widgets.
-- Inspected kcd2-mod-docs 9cb067543245ec5cf4e27b3d21e32485a35db518:
-- Scripts/Scripts/CommandExecutor/sample_terrain.xml:18 and
-- sample_terrain_default.xml:14 use wh_ui_ShowHud=0 and =1 respectively.
-- script_bind_2025_01_14/CScriptBindSystem__{Get,Set}CVar@IFunctionHandler__.html;
-- CScriptBindScript__SetTimerForFunction@IFunctionHandler__@int@char__.html
-- documents userdata, ScriptHandle and bUpdateDuringPause; KillTimer takes that handle.
-- All writes run in owned engine timer callbacks. Engine stalls can delay expiry.
-- Readback comparison cannot distinguish another writer setting the same value.

MineCome = MineCome or {}
assert(type(MineCome)=="table", "MineCome namespace unavailable")
local root, state = MineCome, MineCome._hud_visibility
local function exports_owned(s)
    return root.BeginHudVisibility==s.begin and root.EndHudVisibility==s.finish and root.ReportHudVisibility==s.report
end
if state==nil then
    assert(MineCome_HudVisibilityTimer==nil and root.BeginHudVisibility==nil and root.EndHudVisibility==nil and root.ReportHudVisibility==nil,
        "HUD visibility callback or exports already owned")
    state={schema=1,owner="minecome_hud_visibility_v1"};root._hud_visibility=state
else
    assert(type(state)=="table" and state.owner=="minecome_hud_visibility_v1" and state.callback==MineCome_HudVisibilityTimer and exports_owned(state),
        "HUD visibility state already owned")
end
local function finite(n) return type(n)=="number" and n==n and n>-math.huge and n<math.huge end
local function token(v) return type(v)=="string" and #v==32 and v:match("^[0-9a-f]+$")~=nil end
local function handle(v) return type(v)=="userdata" or (finite(v) and v>0 and v==math.floor(v)) end
local function owned() return MineCome==root and root._hud_visibility==state and MineCome_HudVisibilityTimer==state.callback and exports_owned(state) end
local function reader_owned(p) return System==p.system and System and System.GetCVar==p.reader and type(p.reader)=="function" end
local function read(p)
    if p and not reader_owned(p) then return nil end
    if not System or type(System.GetCVar)~="function" then return nil end
    local ok,v=pcall(System.GetCVar,"wh_ui_ShowHud");return ok and finite(v) and v or nil
end
local function now()
    if not System or type(System.GetCurrTime)~="function" then return nil end
    local ok,v=pcall(System.GetCurrTime);return ok and finite(v) and v>=0 and v<1000000000000 and v or nil
end
local function quote(v) return '"'..tostring(v):gsub('[%z\1-\31\\"]',function(c) return string.format("\\u%04x",string.byte(c)) end)..'"' end
local function num(v) return finite(v) and string.format("%.17g",v) or "null" end
local function emit(p,stage)
    local s={schema=1,run=p.run,stage=stage,reason=p.reason or "queued",original_hud=p.original,current_hud=read(p),requested_hud=0,
        active=state.active==p and not p.terminal,applied=p.applied==true,owned_write=p.owned_write==true,already_hidden=p.already_hidden==true,
        write_attempted=p.write_attempted==true,restored=p.restored==true,restore_attempted=p.restore_attempted==true,
        restore_result=p.restore_result or "not_attempted",expired=p.expired==true,timer_armed=handle(p.timers.expiry),
        timer_cancelled=p.timer_cancelled~=false,created_engine_seconds=p.created,deadline_engine_seconds=p.deadline,duration_ms=p.duration}
    local parts={}
    for _,key in ipairs({"schema","run","stage","reason","original_hud","current_hud","requested_hud","active","applied","owned_write","already_hidden",
        "write_attempted","restored","restore_attempted","restore_result","expired","timer_armed","timer_cancelled","created_engine_seconds","deadline_engine_seconds","duration_ms"}) do
        local value=s[key];parts[#parts+1]=quote(key)..":"..(type(value)=="string" and quote(value) or type(value)=="boolean" and tostring(value) or num(value))
    end
    if not System or type(System.LogAlways)~="function" then return false,s end
    local ok,result=pcall(System.LogAlways,"[MineComeHudVisibility] {"..table.concat(parts,",").."}")
    return ok and result~=false,s
end
local function cancel(p)
    for slot,id in pairs(p.timers) do
        p.timers[slot]=nil
        local ok,result=false,nil
        if Script==p.script and Script.KillTimer==p.kill and type(p.kill)=="function" then ok,result=pcall(p.kill,id) end
        if not ok or result==false then p.timer_cancelled=false end
    end
end
local function writer_owned(p)
    return reader_owned(p) and System.SetCVar==p.setter and type(p.setter)=="function"
end
local function finish(p,reason,expired)
    if state.active~=p or p.terminal then return false end
    p.reason,p.expired=reason,expired==true
    local current=read(p)
    if not reader_owned(p) then p.restore_result="binding_changed"
    elseif not p.write_attempted then
        p.restored=current==p.original
        p.restore_result=p.restored and (p.already_hidden and "already_hidden" or "not_attempted") or (current==nil and "current_unavailable" or "external_change_preserved")
    elseif current==p.original then p.restored,p.restore_result=true,"already_original"
    elseif current==nil then p.restore_result="current_unavailable"
    elseif current~=0 then p.restore_result="external_change_preserved"
    elseif not writer_owned(p) then p.restore_result="binding_changed"
    else
        p.restore_attempted=true
        pcall(p.setter,"wh_ui_ShowHud",p.original)
        -- Mandatory readback even if the binding threw after mutation.
        p.restored=read(p)==p.original;p.restore_result=p.restored and "restored" or "readback_failed"
    end
    p.terminal=true;cancel(p);state.active,state.last=nil,p
    local logged=emit(p,"terminal");return p.restored==true and logged,p.reason
end
local function arm(p,slot,delay)
    if Script~=p.script or Script.SetTimerForFunction~=p.schedule or type(p.schedule)~="function" then return false end
    local data={probe=p,slot=slot};p.data[slot]=data
    local ok,id=pcall(p.schedule,delay,"MineCome_HudVisibilityTimer",data,true)
    if not ok or not handle(id) then p.data[slot]=nil;return false end
    p.timers[slot]=id;return true
end
local function clock_reason(p)
    local clock=now()
    if not clock then return "clock_unavailable" end
    if clock<p.created or clock<p.last_clock then return "clock_regressed" end
    p.last_clock=clock
    if clock>=p.deadline then return "engine_lease_expired" end
end
function MineCome.BeginHudVisibility(run,durationMs)
    if not token(run) then return false,"invalid_run" end
    if not owned() then return false,"ownership_lost" end
    if state.active then return false,"busy" end
    if state.last and state.last.run==run then return false,"run_consumed" end
    if not finite(durationMs) or durationMs~=math.floor(durationMs) or durationMs<2 or durationMs>120000 then return false,"invalid_duration" end
    local p={run=run,duration=durationMs,timers={},data={},timer_cancelled=true,created=now(),original=read(),system=System,script=Script}
    p.reader=System and System.GetCVar
    p.last_clock=p.created;p.deadline=p.created and p.created+durationMs/1000 or nil
    local reason
    if not p.created then reason="clock_unavailable"
    elseif p.original~=0 and p.original~=1 then reason="original_not_boolean"
    elseif not System or type(System.SetCVar)~="function" or type(System.LogAlways)~="function" then reason="binding_unavailable"
    elseif not Script or type(Script.SetTimerForFunction)~="function" or type(Script.KillTimer)~="function" then reason="timer_unavailable" end
    if reason then p.reason=reason;emit(p,"rejected");return false,reason end
    p.reader,p.setter,p.schedule,p.kill=System.GetCVar,System.SetCVar,Script.SetTimerForFunction,Script.KillTimer
    state.active=p
    -- Expiry exists before any callback capable of writing the CVar.
    if not arm(p,"expiry",durationMs) or not arm(p,"apply",1) then finish(p,"timer_arm_failed",false);return false,"timer_arm_failed" end
    if not emit(p,"queued") then finish(p,"log_failed",false);return false,"log_failed" end
    return true,"queued"
end
function MineCome_HudVisibilityTimer(data)
    if type(data)~="table" or type(data.probe)~="table" then return false end
    local p,slot=data.probe,data.slot
    if not owned() or state.active~=p or p.terminal or p.data[slot]~=data or not handle(p.timers[slot]) then return false end
    p.timers[slot]=nil
    if slot=="expiry" then return finish(p,"timer_expired",true) end
    local reason=clock_reason(p)
    if reason then return finish(p,reason,true) end
    if p.end_requested then return finish(p,"requested_end",false) end
    if slot~="apply" then return false end
    if not writer_owned(p) then return finish(p,"binding_changed",false) end
    if read(p)~=p.original then return finish(p,"preapply_changed",false) end
    if p.original==0 then p.already_hidden=true
    else
        p.write_attempted=true
        local ok,result=pcall(p.setter,"wh_ui_ShowHud",0)
        local current=read(p);p.owned_write=current==0
        reason=clock_reason(p)
        if reason then return finish(p,reason,true) end
        if not ok or result==false or current~=0 then return finish(p,"apply_failed",false) end
    end
    reason=clock_reason(p)
    if reason then return finish(p,reason,true) end
    p.applied,p.reason=true,p.already_hidden and "already_hidden" or "applied"
    if not emit(p,"applied") then return finish(p,"log_failed",false) end
    return true
end
state.callback=MineCome_HudVisibilityTimer
function MineCome.EndHudVisibility(run)
    if not token(run) then return false,"invalid_run" end
    if not owned() then return false,"ownership_lost" end
    local p=state.active or state.last
    if not p or p.run~=run then return false,"run_mismatch" end
    if p.terminal then local logged=emit(p,"terminal");return p.restored==true and logged,p.reason end
    if p.end_requested then
        if not handle(p.timers["end"]) then emit(p,"end_failed");return false,"end_timer_arm_failed" end
        local logged=emit(p,"end_queued");return logged,"end_queued"
    end
    p.end_requested,p.reason=true,"end_queued"
    if not arm(p,"end",1) then p.reason="end_timer_arm_failed";emit(p,"end_failed");return false,p.reason end
    local logged=emit(p,"end_queued");return logged,"end_queued"
end
function MineCome.ReportHudVisibility(run)
    if not token(run) then return false,"invalid_run" end
    if not owned() then return false,"ownership_lost" end
    local p=state.active or state.last
    if not p or p.run~=run then return false,"run_mismatch" end
    return emit(p,"status") -- A copied snapshot never renews the lease.
end
state.begin,state.finish,state.report=root.BeginHudVisibility,root.EndHudVisibility,root.ReportHudVisibility
