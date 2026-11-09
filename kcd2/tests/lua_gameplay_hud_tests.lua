-- SPDX-License-Identifier: GPL-3.0-or-later
-- Real Lua VM, simulated engine UI. Does not establish native clip identity.
assert(type(MINECOME_MODULE_PATH)=='string')
local A,B=string.rep('a',32),string.rep('b',32)
local passed=0
local function eq(a,b)assert(a==b,'got '..tostring(a)..', expected '..tostring(b))end
local function test(name,fn)local ok,err=pcall(fn);if not ok then error(name..': '..tostring(err),0)end;passed=passed+1;print('PASS '..name)end
local function fixture()
 local f={time=10,visible=true,other={Compass=true,Subtitles=true,DialogLeft=true,QAMWeapon=true},writes={},reads=0,timers={},logs={},in_callback=false,schedules=0}
 player={id=7};f.movement={run=A,entity=player,id=7,deadline=100,sequence=1,latest={received=10}}
 MineCome={_gameplay_movement={active=f.movement}};MineCome_GameplayHudTimer=nil
 System={GetCurrTime=function()return f.time end,LogAlways=function(line)if f.log_failure then error('log failed')end;f.logs[#f.logs+1]=line end}
 UIAction={IsVisible=function(element,instance,clip)
  eq(f.in_callback,true);eq(element,'hud');eq(instance,0);eq(clip,'Stats');f.reads=f.reads+1
  if f.read_error then error('read failed')end;return f.visible
 end,SetVisible=function(element,instance,clip,v)
  eq(f.in_callback,true);eq(element,'hud');eq(instance,0);eq(clip,'Stats');eq(type(v),'boolean')
  eq(MineCome._gameplay_hud.active.timers.expiry~=nil or v==true,true)
  f.writes[#f.writes+1]=v;if not f.ignore_write then f.visible=v end
  if f.after_write then f.after_write(#f.writes)end
  if f.throw_write==#f.writes then error('after mutation')end
  if f.false_write==#f.writes then return false end
 end}
 Script={SetTimerForFunction=function(ms,name,data,pause)
  eq(name,'MineCome_GameplayHudTimer');eq(pause,true);assert(ms>=1 and ms<=86400000)
  f.schedules=f.schedules+1;if f.fail_schedule==f.schedules then return nil end
  local id=f.schedules;f.timers[#f.timers+1]={id=id,name=name,data=data,ms=ms,alive=true};return id
 end,KillTimer=function(id)
  if f.kill_failure then error('kill failed')end
  local found=false;for _,t in ipairs(f.timers)do if t.id==id and t.alive then t.alive=false;found=true end end;eq(found,true)
 end}
 dofile(MINECOME_MODULE_PATH);eq(#f.writes,0);eq(f.reads,0);eq(#f.timers,0)
 function f:fire(slot,advance)
  local t;for _,e in ipairs(self.timers)do if e.alive and e.data.slot==slot then t=e;break end end;assert(t,'missing '..slot)
  t.alive=false;self.time=self.time+(advance or 0);self.in_callback=true
  local ok,r=pcall(_G[t.name],t.data);self.in_callback=false;assert(ok,r);return r,t.data
 end
 function f:begin()eq(MineCome.GameplayHudBegin(A,30000),true);return self:fire('tick',.001)end
 function f:finish()eq(MineCome.GameplayHudEnd(A),true);return self:fire('stop',.001)end
 function f:status()local ok,s=MineCome.ReportGameplayHud(A);eq(ok,true);return s end
 function f:heartbeat(dt)self.time=self.time+dt;self.movement.latest.received=self.time;self.movement.sequence=self.movement.sequence+1;return self:fire('tick')end
 function f:timersAlive()local n=0;for _,t in ipairs(self.timers)do if t.alive then n=n+1 end end;return n end
 return f
end
test('load has no UI work and preserves existing movement owner',function()local f=fixture();eq(MineCome._gameplay_movement.active,f.movement)end)
test('strict run and duration reject without reads',function()
 local f=fixture();for _,run in ipairs({'','a',string.rep('A',32),string.rep('a',33),12,{}})do eq(MineCome.GameplayHudBegin(run,30000),false)end
 for _,ms in ipairs({0,999,86400001,1000.5,math.huge,0/0,'30000'})do eq(MineCome.GameplayHudBegin(A,ms),false)end
 eq(f.reads,0);eq(f:timersAlive(),0)
end)
test('exact movement owner required',function()
 for _,change in ipairs({function(f)f.movement.run=B end,function(f)f.movement.stopping=true end,function(f)f.movement.terminal=true end,function(f)f.movement.id=8 end,function(f)f.movement.entity={}end,function(f)MineCome._gameplay_movement.active=nil end})do local f=fixture();change(f);eq(MineCome.GameplayHudBegin(A,30000),false);eq(f.reads,0)end
end)
test('missing APIs reject without scheduling',function()
 for _,p in ipairs({{'UIAction','IsVisible'},{'UIAction','SetVisible'},{'System','GetCurrTime'},{'System','LogAlways'},{'Script','SetTimerForFunction'},{'Script','KillTimer'}})do local f=fixture();_G[p[1]][p[2]]=nil;eq(MineCome.GameplayHudBegin(A,30000),false);eq(f.reads,0);eq(#f.timers,0)end
end)
test('hide and exact restore leave all other HUD clips untouched',function()
 local f=fixture();eq(MineCome.GameplayHudBegin(A,30000),true);eq(#f.writes,0);eq(f.reads,0);eq(f.timers[1].data.slot,'expiry')
 eq(f:fire('tick',.001),true);eq(f.visible,false);local s=f:status();eq(s.hidden,true);eq(s.original_visible,true);eq(s.backend,'ui_movieclip')
 for _,v in pairs(f.other)do eq(v,true)end
 eq(f:finish(),true);s=f:status();eq(s.active,false);eq(s.restored,true);eq(s.current_visible,true);eq(s.timers_cancelled,true);eq(f:timersAlive(),0);eq(#f.writes,2)
end)
test('already hidden baseline is restored without writes',function()local f=fixture();f.visible=false;eq(f:begin(),true);eq(f:status().hidden,true);eq(f:finish(),true);eq(f.visible,false);eq(#f.writes,0)end)
test('unknown visibility fails without writing',function()for _,v in ipairs({0,1,'true',{}})do local f=fixture();f.visible=v;eq(f:begin(),true);eq(f:status().active,false);eq(f:status().result,'visibility_unavailable');eq(#f.writes,0)end end)
test('host pose heartbeat keeps lease alive without extra UI writes',function()local f=fixture();f:begin();for i=1,4 do eq(f:heartbeat(1),true)end;eq(f:status().active,true);eq(#f.writes,1);f:finish()end)
test('cached status does not renew lease or read UI',function()local f=fixture();f:begin();local n=f.reads;f.time=f.time+2.01;f:status();eq(f.reads,n);eq(f:fire('tick'),true);eq(f:status().result,'peer_lease_expired');eq(f.visible,true)end)
test('expired movement owner restores even when heartbeat is fresh',function()
 for _,change in ipairs({function(f)f.movement.stopping=true end,function(f)f.movement.terminal=true end,function(f)MineCome._gameplay_movement.active=nil end,function(f)MineCome._gameplay_movement={active=f.movement}end})do local f=fixture();f:begin();change(f);eq(f:fire('tick',.1),true);eq(f:status().result,'movement_stopped');eq(f.visible,true)end
end)
test('player replacement restores owned UI',function()local f=fixture();f:begin();player={id=7};f:fire('tick',.1);eq(f:status().result,'player_changed');eq(f.visible,true)end)
test('session deadline cannot be extended by fresh heartbeats',function()local f=fixture();f:begin();f.movement.deadline=500;f.time=40.1;f.movement.latest.received=f.time;f:fire('tick');eq(f:status().result,'session_expired');eq(f.visible,true)end)
test('movement deadline bounds requested HUD duration',function()local f=fixture();f.movement.deadline=12;eq(MineCome.GameplayHudBegin(A,30000),true);eq(f.timers[1].ms,2000);f:fire('tick');f:fire('expiry',2);eq(f.visible,true);eq(f:status().restored,true)end)
test('clock regression restores and stops',function()local f=fixture();f:begin();f.time=9;f:fire('tick');eq(f:status().result,'clock_invalid');eq(f.visible,true)end)
test('foreign visibility change is preserved without fighting it',function()local f=fixture();f:begin();f.visible=true;f:fire('tick',.1);eq(#f.writes,1);eq(f:status().restored,true);eq(f:status().result,'visibility_changed')end)
test('foreign change to initially hidden baseline is preserved',function()local f=fixture();f.visible=false;f:begin();f.visible=true;eq(f:fire('tick',.1),false);eq(#f.writes,0);eq(f:status().restored,false);eq(MineCome.GameplayHudBegin(B,30000),false)end)
test('UI binding replacement prevents foreign writes',function()local f=fixture();f:begin();local calls=0;UIAction.SetVisible=function()calls=calls+1 end;eq(f:fire('tick',.1),false);eq(calls,0);eq(f:status().restored,false)end)
test('failed writes after mutation are read back and rolled back',function()for _,field in ipairs({'throw_write','false_write'})do local f=fixture();f[field]=1;eq(f:begin(),true);eq(f:status().result,'hide_failed');eq(f:status().restored,true);eq(f.visible,true)end end)
test('restore readback detects ignored write',function()local f=fixture();f:begin();f.ignore_write=true;eq(f:finish(),false);eq(f:status().restored,false)end)
test('timer failures before apply do not touch UI',function()for n=1,2 do local f=fixture();f.fail_schedule=n;eq(MineCome.GameplayHudBegin(A,30000),false);eq(f:status().restored,true);eq(f.reads,0);eq(#f.writes,0);eq(f:timersAlive(),0)end end)
test('tick rescheduling failure restores immediately',function()local f=fixture();f.fail_schedule=3;eq(f:begin(),true);eq(f:status().result,'heartbeat_timer_failed');eq(f.visible,true);eq(f:timersAlive(),0)end)
test('failed stop timer falls back to existing heartbeat restoration',function()local f=fixture();f:begin();f.fail_schedule=f.schedules+1;eq(MineCome.GameplayHudEnd(A),false);eq(f.visible,false);eq(f:fire('tick',.1),true);eq(f.visible,true)end)
test('timer cancellation failure is reported and stale callbacks stay inert',function()
 local f=fixture();f:begin();f.kill_failure=true;eq(f:finish(),true);eq(f:status().timers_cancelled,false)
 local n=#f.writes;eq(f:fire('tick',.1),false);eq(f:fire('expiry'),false);eq(#f.writes,n);eq(f.visible,true)
end)
test('duplicate stop and stale timer cannot alter later sessions',function()
 local f=fixture();f:begin();local _,old=f:fire('tick',.1);f:finish();local n=#f.writes;eq(MineCome.GameplayHudEnd(A),true);eq(#f.writes,n)
 f.movement.run=B;f.movement.latest.received=f.time;eq(MineCome.GameplayHudBegin(B,30000),true);eq(MineCome_GameplayHudTimer(old),false);eq(#f.writes,n)
end)
test('foreign run cannot stop or inspect active lease',function()local f=fixture();f:begin();eq(MineCome.GameplayHudEnd(B),false);eq(MineCome.ReportGameplayHud(B),false);eq(f.visible,false);f:finish()end)
test('normal reload preserves active exact exports',function()local f=fixture();f:begin();dofile(MINECOME_MODULE_PATH);eq(f.visible,false);eq(f:finish(),true)end)
test('foreign exported callback refuses reload',function()fixture();MineCome.GameplayHudEnd=function()end;eq(pcall(dofile,MINECOME_MODULE_PATH),false)end)
print('GAMEPLAY_HUD_TESTS_PASS '..passed)
