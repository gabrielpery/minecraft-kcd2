-- SPDX-License-Identifier: GPL-3.0-or-later
-- Read-only frame/timer observation. Never reads or writes an actor transform.
-- Pinned official script_bind_2025_01_14 System.GetFrameID/GetFrameTime and
-- Script.SetTimerForFunction/KillTimer bindings; no periodic guarantee assumed.
MineCome = MineCome or {}
local active
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function n(v) return finite(v) and string.format("%.17g",v) or "null" end
local function read(name)
    if not System or type(System[name])~="function" then return nil end
    local ok,value=pcall(System[name]);if ok and finite(value) then return value end
end
local function emit(p,event,slot)
    return pcall(System.LogAlways,'[MineComeTimerCadence] {"schema":1,"run":"'..p.run
        ..'","event":"'..event..'","chain":"'..(slot or "none")..'","engine_seconds":'..n(read("GetCurrTime"))
        ..',"frame_id":'..n(read("GetFrameID"))..',"frame_time_raw":'..n(read("GetFrameTime"))
        ..',"count":'..n(slot and p.counts[slot] or 0)..',"timers_cancelled":'..tostring(p.clean==true)..'}')
end
local function stop(p,event)
    if active~=p then return end
    active=nil;p.clean=true
    for key,id in pairs(p.timers) do
        local ok,value=pcall(Script.KillTimer,id);if not ok or value==false then p.clean=false end
        p.timers[key]=nil
    end
    emit(p,event)
end
local function arm(p,slot,delay)
    local data={probe=p,slot=slot};p.data[slot]=data
    local ok,id=pcall(Script.SetTimerForFunction,delay,"MineCome_TimerCadenceTick",data,true)
    if not ok or (type(id)~="userdata" and not(finite(id) and id>0 and id==math.floor(id))) then return false end
    p.timers[slot]=id;return true
end
function MineCome_TimerCadenceTick(data)
    local p=active
    if type(data)~="table" or data.probe~=p or not p or p.data[data.slot]~=data or not p.timers[data.slot] then return end
    local slot=data.slot;p.timers[slot]=nil
    if slot=="deadline" then stop(p,"deadline");return end
    p.counts[slot]=p.counts[slot]+1
    if not emit(p,"sample",slot) then stop(p,"log_failed");return end
    if p.counts[slot]<6 then
        if not arm(p,slot,1) then stop(p,"schedule_failed") end
    elseif p.counts.a==6 and p.counts.b==6 and p.counts.c==6 then stop(p,"complete") end
end
function MineCome.ProbeTimerCadence(run)
    if active or type(run)~="string" or not run:match("^[0-9a-f]+$") or #run~=32 then return false end
    if not Script or type(Script.SetTimerForFunction)~="function" or type(Script.KillTimer)~="function"
        or not read("GetCurrTime") or not read("GetFrameID") or not read("GetFrameTime") then return false end
    local p={run=run,timers={},data={},counts={a=0,b=0,c=0}};active=p
    if not arm(p,"deadline",1000) or not arm(p,"a",1) or not arm(p,"b",18) or not arm(p,"c",35) then stop(p,"schedule_failed");return false end
    emit(p,"begin");return true
end
