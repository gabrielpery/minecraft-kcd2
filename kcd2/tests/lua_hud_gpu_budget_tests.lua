-- SPDX-License-Identifier: GPL-3.0-or-later
-- Real Lua VM, simulated engine CVar/timer bindings; no live graphics proof.
assert(type(MINECOME_MODULE_PATH)=="string")
local passed=0
local A,B=string.rep("a",32),string.rep("b",32)
local function eq(a,b) assert(a==b,"got "..tostring(a)..", expected "..tostring(b)) end
local function test(name,fn) local ok,err=pcall(fn);if not ok then error(name..": "..tostring(err),0) end;passed=passed+1;print("PASS "..name) end
local function fixture()
    local f={time=10,fps=-1,vsync=0,logs={},timers={},writes={},kills={},schedules=0}
    local retained={marker="untouched"}
    MineCome={_movement_probe=retained,_interactive_input=retained};MineCome_HudGpuBudgetTimer=nil
    System={GetCurrTime=function() return f.time end,
        GetCVar=function(name) if name=="sys_MaxFPS" then return f.fps end;eq(name,"r_VSync");return f.vsync end,
        SetCVar=function(name,value)
            eq(name,"sys_MaxFPS")
            local p=MineCome._hud_gpu_budget.active
            f.writes[#f.writes+1]={value=value,expiry_armed=p and p.timers.expiry~=nil}
            if not (f.no_write==#f.writes) then f.fps=value end
            if f.after_write then f.after_write(#f.writes) end
            if f.throw_write==#f.writes then error("after mutation") end
            if f.false_write==#f.writes then return false end
        end,
        LogAlways=function(line) if f.log_error then error("logging failed") end;f.logs[#f.logs+1]=line end}
    Script={SetTimerForFunction=function(ms,name,data,pause)
        eq(pause,true);eq(name,"MineCome_HudGpuBudgetTimer");assert(ms>=1 and ms<=120000)
        f.schedules=f.schedules+1;if f.fail_schedule==f.schedules then return nil end
        local id=f.userdata and data.slot=="expiry" and io.stderr or f.schedules
        f.timers[#f.timers+1]={id=id,name=name,data=data,ms=ms,alive=true};return id
    end,KillTimer=function(id)
        f.kills[#f.kills+1]=id
        if f.kill_error then error("kill failed") end
        local found=false
        for _,e in ipairs(f.timers) do if e.alive and e.id==id then e.alive=false;found=true end end
        assert(found,"killed unowned or consumed timer")
    end}
    dofile(MINECOME_MODULE_PATH)
    eq(MineCome._movement_probe,retained);eq(MineCome._interactive_input,retained)
    eq(#f.writes,0);eq(#f.timers,0);eq(#f.logs,0)
    function f:fire(slot,advance)
        local event
        for _,e in ipairs(self.timers) do if e.alive and e.data.slot==slot then event=e;break end end
        assert(event,"missing timer "..slot);event.alive=false
        self.time=self.time+(advance or 0);return _G[event.name](event.data,event.id)
    end
    function f:begin() eq(MineCome.BeginHudGpuBudget(A,120000,60),true);self:fire("apply",.001) end
    function f:status() local ok,s=MineCome.HudGpuBudgetStatus(A);eq(ok,true);return s end
    function f:activeTimers() local n=0;for _,e in ipairs(self.timers) do if e.alive then n=n+1 end end;return n end
    return f
end
test("loading preserves unrelated state and performs no engine work",function() fixture() end)
test("strict run duration and fps refuse writes and scheduling",function()
    local f=fixture()
    for _,run in ipairs({"", "a", string.rep("a",33),string.rep("A",32),'a"',12,{}}) do
        eq(MineCome.BeginHudGpuBudget(run,120000,60),false);eq(MineCome.EndHudGpuBudget(run),false)
    end
    for _,ms in ipairs({0,1,-1,120001,120000.1,math.huge,0/0,"120000"}) do eq(MineCome.BeginHudGpuBudget(A,ms,60),false) end
    for _,fps in ipairs({0,30,61,"60",math.huge,0/0}) do eq(MineCome.BeginHudGpuBudget(A,120000,fps),false) end
    eq(#f.writes,0);eq(#f.timers,0)
end)
test("numeric original and disabled vsync are required",function()
    for _,v in ipairs({"-1",false,math.huge,-math.huge,0/0,30,60}) do local f=fixture();f.fps=v;eq(MineCome.BeginHudGpuBudget(A,120000,60),false);eq(#f.writes,0);eq(#f.timers,0) end
    local f=fixture();f.fps=nil;eq(MineCome.BeginHudGpuBudget(A,120000,60),false)
    for _,v in ipairs({1,"0",false,0/0}) do f=fixture();f.vsync=v;eq(MineCome.BeginHudGpuBudget(A,120000,60),false);eq(#f.timers,0) end
end)
test("unlimited zero and negative or higher cap restore exact original",function()
    for _,value in ipairs({-1,0,144}) do local f=fixture();f.fps=value;f:begin();eq(f.fps,60);eq(MineCome.EndHudGpuBudget(A),true);eq(f.fps,value);eq(f:status().restored,true) end
end)
test("missing clock setter logger or timers refuse before mutation",function()
    for _,pair in ipairs({{"System","GetCurrTime"},{"System","SetCVar"},{"System","LogAlways"},{"Script","SetTimerForFunction"},{"Script","KillTimer"}}) do
        local f=fixture();_G[pair[1]][pair[2]]=nil;eq(MineCome.BeginHudGpuBudget(A,120000,60),false);eq(#f.writes,0);eq(#f.timers,0)
    end
end)
test("apply is queued and expiry precedes mutation with opaque handle retained",function()
    local f=fixture();f.userdata=true;eq(MineCome.BeginHudGpuBudget(A,120000,60),true)
    eq(#f.writes,0);eq(f.timers[1].data.slot,"expiry");eq(f.timers[1].ms,120000);eq(f.timers[2].ms,1)
    f:fire("apply",.001);eq(#f.writes,1);eq(f.writes[1].expiry_armed,true);eq(f:status().timer_armed,true)
    eq(MineCome.EndHudGpuBudget(A),true);eq(f.kills[1],io.stderr);eq(f:activeTimers(),0)
    local s=f:status();eq(s.active,false);eq(s.expired,false);eq(s.reason,"requested_end");eq(s.current_fps,-1)
end)
test("timer arm failure leaves no mutation and cancels only owned timer",function()
    for _,n in ipairs({1,2}) do local f=fixture();f.fail_schedule=n;eq(MineCome.BeginHudGpuBudget(A,120000,60),false);eq(#f.writes,0);eq(f:activeTimers(),0) end
end)
test("queued end prevents apply and late canceled callbacks cannot mutate",function()
    local f=fixture();eq(MineCome.BeginHudGpuBudget(A,120000,60),true);local apply=f.timers[2]
    MineCome.EndHudGpuBudget(A);eq(#f.writes,0);eq(f:activeTimers(),0)
    eq(_G[apply.name](apply.data,apply.id),false);eq(#f.writes,0)
end)
test("busy mismatched run and reload preserve immutable live lease",function()
    local f=fixture();f:begin();local p=MineCome._hud_gpu_budget.active;local deadline=p.deadline
    eq(MineCome.BeginHudGpuBudget(B,120000,60),false);eq(MineCome.EndHudGpuBudget(B),false)
    local old=MineCome.BeginHudGpuBudget;dofile(MINECOME_MODULE_PATH);assert(MineCome.BeginHudGpuBudget~=old)
    eq(MineCome._hud_gpu_budget.active,p);eq(p.deadline,deadline);eq(#f.timers,2)
    eq(f:fire("expiry",0),true);eq(f.fps,-1);eq(f:status().expired,true)
end)
test("pause-updating timer expires even when engine clock has not advanced",function()
    local f=fixture();f:begin();local time=f.time;eq(f:fire("expiry",0),true);eq(f.time,time)
    local s=f:status();eq(s.reason,"timer_expired");eq(s.expired,true);eq(s.restored,true);eq(f:activeTimers(),0)
end)
test("late end and delayed apply cannot renew expired engine deadline",function()
    local f=fixture();f:begin();f.time=131;eq(MineCome.EndHudGpuBudget(A),true);eq(f:status().reason,"engine_lease_expired");eq(f:status().expired,true)
    f=fixture();eq(MineCome.BeginHudGpuBudget(A,120000,60),true);f:fire("apply",121);eq(#f.writes,0);eq(f:activeTimers(),0)
end)
test("clock regression or unavailable after mutation restores and invalidates comparison",function()
    for _,time in ipairs({9,0/0,math.huge}) do local f=fixture();f:begin();f.time=time;eq(MineCome.EndHudGpuBudget(A),true);eq(f.fps,-1);eq(f:status().expired,true) end
    local f=fixture();f.after_write=function(n) if n==1 then f.time=131 end end;f:begin();eq(f.fps,-1);eq(f:status().expired,true)
end)
test("preapply external cap or vsync changes refuse the initial write",function()
    for _,field in ipairs({"fps","vsync"}) do local f=fixture();eq(MineCome.BeginHudGpuBudget(A,120000,60),true);f[field]=1;f:fire("apply",.001);eq(#f.writes,0);eq(f:activeTimers(),0) end
end)
test("failed apply rolls back including throw after successful mutation",function()
    for _,mode in ipairs({"throw_write","false_write","no_write"}) do local f=fixture();f[mode]=1;f:begin();eq(f.fps,-1);eq(f:status().reason,"apply_failed");eq(f:status().restored,true);eq(f:activeTimers(),0) end
end)
test("external changed cap is preserved and cannot claim restoration",function()
    local f=fixture();f:begin();f.fps=90;eq(MineCome.EndHudGpuBudget(A),false);eq(f.fps,90);eq(#f.writes,1)
    eq(f:status().restore_result,"external_change_preserved");eq(f:status().restored,false)
end)
test("already restored original is verified without an extra write",function()
    local f=fixture();f:begin();f.fps=-1;eq(MineCome.EndHudGpuBudget(A),true);eq(#f.writes,1);eq(f:status().restore_result,"already_original")
end)
test("restoration failure and unavailable current CVar are explicit",function()
    local f=fixture();f:begin();f.no_write=2;eq(MineCome.EndHudGpuBudget(A),false);eq(f.fps,60);eq(f:status().restore_result,"readback_failed")
    f=fixture();f:begin();f.fps=nil;eq(MineCome.EndHudGpuBudget(A),false);eq(#f.writes,1);eq(f:status().restore_result,"current_unavailable")
end)
test("checked restoration tolerates setter throw only if actual readback restored",function()
    local f=fixture();f:begin();f.throw_write=2;eq(MineCome.EndHudGpuBudget(A),true);eq(f.fps,-1);eq(f:status().restored,true)
end)
test("logging failure rolls back rather than leave an unreported cap",function()
    local f=fixture();f.log_error=true;eq(MineCome.BeginHudGpuBudget(A,120000,60),false);eq(#f.writes,0);eq(f:activeTimers(),0)
    f=fixture();eq(MineCome.BeginHudGpuBudget(A,120000,60),true);f.log_error=true;f:fire("apply",.001);eq(f.fps,-1);eq(f:activeTimers(),0)
end)
test("failed cancellation is logged and duplicate callback cannot affect next run",function()
    local f=fixture();f:begin();local old=f.timers[1];f.kill_error=true;eq(MineCome.EndHudGpuBudget(A),true)
    eq(f:status().timer_cancelled,false);f.kill_error=false;eq(MineCome.BeginHudGpuBudget(A,120000,60),false)
    eq(MineCome.BeginHudGpuBudget(B,120000,60),true);eq(_G[old.name](old.data,old.id),false);eq(f.fps,-1)
    f:fire("apply",.001);eq(f.fps,60);eq(MineCome.EndHudGpuBudget(B),true)
end)
test("status returns a copy and cannot extend or write the budget",function()
    local f=fixture();f:begin();local s=f:status();s.duration_ms=999999;s.original_fps=80
    eq(f:status().duration_ms,120000);eq(f:status().original_fps,-1);eq(#f.writes,1);eq(#f.timers,2)
end)
test("foreign state or callback is never overwritten on reload",function()
    local f=fixture();local foreign=function() end;MineCome_HudGpuBudgetTimer=foreign
    eq(pcall(dofile,MINECOME_MODULE_PATH),false);eq(MineCome_HudGpuBudgetTimer,foreign);eq(#f.writes,0)
    f=fixture();local foreignstate={};MineCome._hud_gpu_budget=foreignstate
    eq(pcall(dofile,MINECOME_MODULE_PATH),false);eq(MineCome._hud_gpu_budget,foreignstate);eq(#f.writes,0)
end)
print("HUD GPU budget standalone checks passed: "..passed)
