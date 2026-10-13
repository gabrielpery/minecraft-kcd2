-- SPDX-License-Identifier: GPL-3.0-or-later
-- Real Lua VM with simulated engine bindings. No live HUD/graphics proof.
assert(type(MINECOME_MODULE_PATH)=="string")
local passed=0
local A,B=string.rep("a",32),string.rep("b",32)
local function eq(a,b) assert(a==b,"got "..tostring(a)..", expected "..tostring(b)) end
local function test(name,fn) local ok,err=pcall(fn);if not ok then error(name..": "..tostring(err),0) end;passed=passed+1;print("PASS "..name) end
local function fixture()
    local f={time=10,hud=1,logs={},timers={},writes={},kills={},schedules=0,reads=0,in_callback=false}
    local retained={marker="untouched"}
    MineCome={_hud_gpu_budget=retained,_movement_probe=retained};MineCome_HudVisibilityTimer=nil
    System={GetCurrTime=function() return f.time end,
        GetCVar=function(name) eq(name,"wh_ui_ShowHud");f.reads=f.reads+1;if f.on_read then f.on_read(f.reads) end;return f.hud end,
        SetCVar=function(name,value)
            eq(f.in_callback,true);eq(name,"wh_ui_ShowHud");assert(value==0 or value==1)
            local p=MineCome._hud_visibility.active
            f.writes[#f.writes+1]={value=value,expiry_armed=p and p.timers.expiry~=nil}
            if f.no_write~=#f.writes then f.hud=value end
            if f.after_write then f.after_write(#f.writes) end
            if f.throw_write==#f.writes then error("after mutation") end
            if f.false_write==#f.writes then return false end
        end,
        LogAlways=function(line) if f.log_error then error("logging failed") end;f.logs[#f.logs+1]=line end}
    Script={SetTimerForFunction=function(ms,name,data,pause)
        eq(pause,true);eq(name,"MineCome_HudVisibilityTimer");assert(ms>=1 and ms<=120000)
        f.schedules=f.schedules+1;if f.fail_schedule==f.schedules then return nil end
        local id=f.userdata and data.slot=="expiry" and io.stderr or f.schedules
        f.timers[#f.timers+1]={id=id,name=name,data=data,ms=ms,alive=true};return id
    end,KillTimer=function(id)
        f.kills[#f.kills+1]=id;if f.kill_error then error("kill failed") end
        local found=false
        for _,e in ipairs(f.timers) do if e.alive and e.id==id then e.alive=false;found=true end end
        assert(found,"killed unowned or consumed timer")
    end}
    dofile(MINECOME_MODULE_PATH)
    eq(MineCome._hud_gpu_budget,retained);eq(MineCome._movement_probe,retained)
    eq(#f.writes,0);eq(#f.timers,0);eq(#f.logs,0);eq(f.reads,0)
    function f:fire(slot,advance)
        local event
        for _,e in ipairs(self.timers) do if e.alive and e.data.slot==slot then event=e;break end end
        assert(event,"missing timer "..slot);event.alive=false
        self.time=self.time+(advance or 0);self.in_callback=true
        local ok,result,reason=pcall(_G[event.name],event.data,event.id);self.in_callback=false
        assert(ok,result);return result,reason
    end
    function f:begin(run) eq(MineCome.BeginHudVisibility(run or A,120000),true);return self:fire("apply",.001) end
    function f:finish(run) eq(MineCome.EndHudVisibility(run or A),true);return self:fire("end",.001) end
    function f:status(run) local ok,s=MineCome.ReportHudVisibility(run or A);eq(ok,true);return s end
    function f:activeTimers() local n=0;for _,e in ipairs(self.timers) do if e.alive then n=n+1 end end;return n end
    return f
end
test("load preserves unrelated state without any engine work",function() fixture() end)
test("strict run and duration refuse scheduling",function()
    local f=fixture()
    for _,run in ipairs({"", "a",string.rep("a",33),string.rep("A",32),12,{}}) do
        eq(MineCome.BeginHudVisibility(run,120000),false);eq(MineCome.EndHudVisibility(run),false);eq(MineCome.ReportHudVisibility(run),false)
    end
    for _,ms in ipairs({0,1,-1,120001,120000.1,math.huge,0/0,"120000"}) do eq(MineCome.BeginHudVisibility(A,ms),false) end
    eq(#f.writes,0);eq(#f.timers,0)
end)
test("original must be numeric zero or one",function()
    for _,v in ipairs({-1,2,0.5,"0","1",false,math.huge,-math.huge,0/0}) do
        local f=fixture();f.hud=v;eq(MineCome.BeginHudVisibility(A,120000),false);eq(#f.writes,0);eq(#f.timers,0)
    end
    local f=fixture();f.hud=nil;eq(MineCome.BeginHudVisibility(A,120000),false)
end)
test("missing required bindings refuse before scheduling",function()
    for _,pair in ipairs({{"System","GetCurrTime"},{"System","GetCVar"},{"System","SetCVar"},{"System","LogAlways"},{"Script","SetTimerForFunction"},{"Script","KillTimer"}}) do
        local f=fixture();_G[pair[1]][pair[2]]=nil;eq(MineCome.BeginHudVisibility(A,120000),false);eq(#f.writes,0);eq(#f.timers,0)
    end
end)
test("deferred apply prearms expiry and checked end is also deferred",function()
    local f=fixture();f.userdata=true;eq(MineCome.BeginHudVisibility(A,120000),true)
    eq(#f.writes,0);eq(f.timers[1].data.slot,"expiry");eq(f.timers[1].ms,120000);eq(f.timers[2].ms,1)
    eq(f:fire("apply",.001),true);eq(#f.writes,1);eq(f.writes[1].expiry_armed,true);eq(f.hud,0)
    local s=f:status();eq(s.applied,true);eq(s.owned_write,true);eq(s.already_hidden,false);eq(s.timer_armed,true)
    eq(MineCome.EndHudVisibility(A),true);eq(f.hud,0);eq(#f.writes,1);eq(f.timers[3].ms,1)
    eq(f:fire("end",.001),true);eq(f.hud,1);eq(f.kills[1],io.stderr);eq(f:activeTimers(),0)
    s=f:status();eq(s.active,false);eq(s.reason,"requested_end");eq(s.restore_result,"restored");eq(s.restored,true);eq(s.expired,false)
end)
test("original zero succeeds already hidden with bounded lease and zero writes",function()
    local f=fixture();f.hud=0;eq(f:begin(),true)
    local s=f:status();eq(s.active,true);eq(s.applied,true);eq(s.reason,"already_hidden");eq(s.already_hidden,true);eq(s.owned_write,false);eq(s.timer_armed,true)
    eq(f:finish(),true);s=f:status();eq(s.restored,true);eq(s.restore_result,"already_hidden");eq(s.restore_attempted,false);eq(#f.writes,0)
end)
test("already hidden lease expires without writing",function()
    local f=fixture();f.hud=0;f:begin();eq(f:fire("expiry",0),true)
    local s=f:status();eq(s.expired,true);eq(s.active,false);eq(s.already_hidden,true);eq(s.restore_result,"already_hidden");eq(#f.writes,0)
end)
test("external change during already hidden lease is preserved",function()
    local f=fixture();f.hud=0;f:begin();f.hud=1;eq(f:finish(),false)
    eq(f.hud,1);eq(#f.writes,0);eq(f:status().restore_result,"external_change_preserved")
end)
test("preapply recheck prevents overwriting either changed original",function()
    for _,original in ipairs({0,1}) do
        local f=fixture();f.hud=original;eq(MineCome.BeginHudVisibility(A,120000),true);f.hud=1-original
        f:fire("apply",.001);eq(#f.writes,0);eq(f.hud,1-original);eq(f:status().reason,"preapply_changed");eq(f:activeTimers(),0)
    end
end)
test("expiry is mandatory before any apply timer",function()
    for _,n in ipairs({1,2}) do
        local f=fixture();f.fail_schedule=n;eq(MineCome.BeginHudVisibility(A,120000),false);eq(#f.writes,0);eq(f:activeTimers(),0)
        eq(f:status().reason,"timer_arm_failed")
    end
end)
test("end timer failure retains bounded expiry without synchronous restoration",function()
    local f=fixture();f:begin();f.fail_schedule=3;eq(MineCome.EndHudVisibility(A),false)
    eq(MineCome.EndHudVisibility(A),false);eq(f.hud,0);eq(#f.writes,1);eq(f:status().timer_armed,true)
    eq(f:fire("expiry",0),true);eq(f.hud,1);eq(f:status().reason,"timer_expired")
end)
test("queued end prevents first write and canceled callbacks cannot mutate",function()
    local f=fixture();eq(MineCome.BeginHudVisibility(A,120000),true);local apply=f.timers[2]
    eq(MineCome.EndHudVisibility(A),true);eq(f:fire("end",.001),true);eq(#f.writes,0);eq(f:activeTimers(),0)
    eq(_G[apply.name](apply.data,apply.id),false);eq(#f.writes,0)
end)
test("apply wins queued end race by restoring without hiding",function()
    local f=fixture();eq(MineCome.BeginHudVisibility(A,120000),true);eq(MineCome.EndHudVisibility(A),true)
    eq(f:fire("apply",.001),true);eq(#f.writes,0);eq(f:status().reason,"requested_end");eq(f:activeTimers(),0)
end)
test("busy mismatched runs and reload preserve active lease",function()
    local f=fixture();f:begin();local p=MineCome._hud_visibility.active;local deadline=p.deadline
    eq(MineCome.BeginHudVisibility(B,120000),false);eq(MineCome.EndHudVisibility(B),false);eq(MineCome.ReportHudVisibility(B),false)
    dofile(MINECOME_MODULE_PATH);eq(MineCome._hud_visibility.active,p);eq(p.deadline,deadline);eq(#f.timers,2)
    eq(f:fire("expiry",0),true);eq(f.hud,1);eq(f:status().expired,true)
end)
test("pause-updating expiry restores when engine clock stays fixed",function()
    local f=fixture();f:begin();local time=f.time;eq(f:fire("expiry",0),true);eq(f.time,time)
    eq(f.hud,1);eq(f:status().reason,"timer_expired");eq(f:activeTimers(),0)
end)
test("late apply and end cannot extend immutable engine deadline",function()
    local f=fixture();eq(MineCome.BeginHudVisibility(A,120000),true);f:fire("apply",121);eq(#f.writes,0);eq(f:status().expired,true)
    f=fixture();f:begin();f.time=131;eq(f:finish(),true);eq(f.hud,1);eq(f:status().reason,"engine_lease_expired")
end)
test("clock loss regression and mutation overrun restore exact original",function()
    for _,time in ipairs({9,0/0,math.huge}) do
        local f=fixture();f:begin();f.time=time;eq(f:finish(),true);eq(f.hud,1);eq(f:status().expired,true)
    end
    local f=fixture();f.after_write=function(n) if n==1 then f.time=131 end end;f:begin();eq(f.hud,1);eq(f:status().expired,true)
end)
test("failed apply includes throw after mutation and required readback",function()
    for _,mode in ipairs({"throw_write","false_write","no_write"}) do
        local f=fixture();f[mode]=1;f:begin();eq(f.hud,1);eq(f:status().reason,"apply_failed");eq(f:status().restored,true);eq(f:activeTimers(),0)
    end
end)
test("changed values are preserved and an external original needs no restore write",function()
    local f=fixture();f:begin();f.hud=2;eq(f:finish(),false);eq(f.hud,2);eq(#f.writes,1);eq(f:status().restore_result,"external_change_preserved")
    f=fixture();f:begin();f.hud=1;eq(f:finish(),true);eq(#f.writes,1);eq(f:status().restore_result,"already_original")
end)
test("restoration failure and unavailable current value are reported",function()
    local f=fixture();f:begin();f.no_write=2;eq(f:finish(),false);eq(f.hud,0);eq(f:status().restore_result,"readback_failed")
    f=fixture();f:begin();f.hud=nil;eq(f:finish(),false);eq(#f.writes,1);eq(f:status().restore_result,"current_unavailable")
end)
test("restoration setter throw succeeds only on actual readback",function()
    local f=fixture();f:begin();f.throw_write=2;eq(f:finish(),true);eq(f.hud,1);eq(f:status().restored,true)
end)
test("replaced reader cannot fabricate original-value restoration",function()
    for _,original in ipairs({0,1}) do
        local f=fixture();f.hud=original;f:begin()
        local reads=0;System.GetCVar=function() reads=reads+1;return original end
        eq(f:finish(),false);eq(f.hud,0);eq(reads,0)
        local s=f:status();eq(s.restored,false);eq(s.current_hud,nil);eq(s.restore_result,"binding_changed")
        eq(#f.writes,original)
    end
end)
test("expiry and failed-apply terminal receipts remain idempotent on End",function()
    local f=fixture();f:begin();eq(f:fire("expiry",0),true);local count=#f.writes
    eq(MineCome.EndHudVisibility(A),true);eq(#f.writes,count);eq(f:status().reason,"timer_expired");eq(f:status().expired,true)
    f=fixture();f.throw_write=1;f:begin();count=#f.writes
    eq(MineCome.EndHudVisibility(A),true);eq(#f.writes,count);eq(f:status().reason,"apply_failed");eq(f:status().restored,true)
end)
test("replaced setter and reader bindings are never used to write",function()
    local f=fixture();eq(MineCome.BeginHudVisibility(A,120000),true);System.SetCVar=function() error("foreign setter invoked") end
    f:fire("apply",.001);eq(#f.writes,0);eq(f:status().reason,"binding_changed")
    f=fixture();f:begin();System.SetCVar=function() error("foreign setter invoked") end
    eq(f:finish(),false);eq(#f.writes,1);eq(f:status().restore_result,"binding_changed")
    f=fixture();f:begin();System.GetCVar=function() return 0 end
    eq(f:finish(),false);eq(#f.writes,1);eq(f:status().restore_result,"binding_changed")
end)
test("logging failure before or after mutation leaves no active hidden owner",function()
    local f=fixture();f.log_error=true;eq(MineCome.BeginHudVisibility(A,120000),false);eq(#f.writes,0);eq(f:activeTimers(),0)
    f=fixture();eq(MineCome.BeginHudVisibility(A,120000),true);f.log_error=true;f:fire("apply",.001);eq(f.hud,1);eq(f:activeTimers(),0)
    f=fixture();f:begin();f.log_error=true;eq(MineCome.EndHudVisibility(A),false);f:fire("end",.001);eq(f.hud,1);eq(f:activeTimers(),0)
end)
test("cancellation failure and late callbacks cannot affect a later run",function()
    local f=fixture();f:begin();local old=f.timers[1];f.kill_error=true;eq(f:finish(),true);eq(f:status().timer_cancelled,false)
    f.kill_error=false;eq(MineCome.BeginHudVisibility(A,120000),false);eq(MineCome.BeginHudVisibility(B,120000),true)
    eq(_G[old.name](old.data,old.id),false);eq(f.hud,1);f:fire("apply",.001);eq(f.hud,0);eq(f:finish(B),true)
end)
test("copied report cannot alter original or renew deadline",function()
    local f=fixture();f:begin();local s=f:status();s.original_hud=0;s.duration_ms=999999;s.deadline_engine_seconds=999999
    s=f:status();eq(s.original_hud,1);eq(s.duration_ms,120000);eq(s.deadline_engine_seconds,130);eq(#f.writes,1);eq(#f.timers,2)
    assert(f.logs[#f.logs]:match('^%[MineComeHudVisibility%] {'));assert(f.logs[#f.logs]:find('"owned_write":true',1,true))
end)
test("foreign state callback and exports are preserved on reload",function()
    for _,field in ipairs({"callback","state","begin","end","report"}) do
        local f=fixture();local foreign=function() end
        if field=="callback" then MineCome_HudVisibilityTimer=foreign
        elseif field=="state" then MineCome._hud_visibility={}
        elseif field=="begin" then MineCome.BeginHudVisibility=foreign
        elseif field=="end" then MineCome.EndHudVisibility=foreign
        else MineCome.ReportHudVisibility=foreign end
        eq(pcall(dofile,MINECOME_MODULE_PATH),false);eq(#f.writes,0)
    end
end)
test("forged timer payloads cannot mutate the active lease",function()
    local f=fixture();eq(MineCome.BeginHudVisibility(A,120000),true);local p=MineCome._hud_visibility.active
    for _,v in ipairs({false,{}, {probe={}}, {probe=p,slot="apply"}, {probe=p,slot="foreign"}}) do eq(MineCome_HudVisibilityTimer(v),false) end
    eq(#f.writes,0);eq(f:fire("apply",.001),true);eq(#f.writes,1)
end)
print("HUD visibility standalone checks passed: "..passed)
