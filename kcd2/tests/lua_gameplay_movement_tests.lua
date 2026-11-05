-- SPDX-License-Identifier: GPL-3.0-or-later
-- Standalone engine-binding simulation, never live game evidence.
local A,B=string.rep('a',32),string.rep('b',32)
local passed=0
local function eq(a,b)assert(a==b,'got '..tostring(a)..', expected '..tostring(b))end
local function test(name,fn)local ok,err=pcall(fn);if not ok then error(name..': '..tostring(err),0)end;passed=passed+1;print('PASS '..name)end
local function copy(v)return{x=v.x,y=v.y,z=v.z}end
local function fixture()
 local f={time=10,position={x=1,y=2,z=3},velocity={x=0,y=0,z=0},timers={},logs={},writes=0,serial=0,callback=false}
 local retained={marker='untouched'};MineCome={_movement_probe=retained}
 player={id=17,actor={IsDead=function()return false end,IsUnconscious=function()return false end,GetLinkedEntity=function()return nil end},
  player={IsSitting=function()return false end,IsLaying=function()return false end},human={IsMounted=function()return false end},
  GetWorldPos=function()return copy(f.position)end,GetVelocity=function()return copy(f.velocity)end,
  SetWorldPos=function(_,v)eq(f.callback,true);f.position=copy(v);f.writes=f.writes+1;if f.write_error then error('write failed')end end}
 System={GetCurrTime=function()return f.time end,GetViewCameraPos=function()local v=copy(f.position);v.z=v.z+1.6;return v end,
  GetViewCameraDir=function()return{x=0,y=1,z=0}end,GetViewCameraUpDir=function()return{x=0,y=0,z=1}end,GetViewCameraFov=function()return 1 end,
  LogAlways=function(v)f.logs[#f.logs+1]=v end}
 Script={SetTimerForFunction=function(ms,name,data,pause)eq(pause,true);f.serial=f.serial+1;if f.fail_timer==f.serial then return nil end
   f.timers[f.serial]={name=name,data=data,ms=ms,alive=true};return f.serial end,
  KillTimer=function(id)assert(f.timers[id] and f.timers[id].alive,'unowned timer');f.timers[id].alive=false end}
 dofile(MINECOME_MODULE_PATH);eq(MineCome._movement_probe,retained);eq(f.serial,0);eq(f.writes,0)
 function f:begin(run,duration)return MineCome.GameplayMovementBegin(run or A,duration or 86400000,-10,10,-10,10,-10,10)end
 function f:pose(seq,source,x,y,z)return MineCome.GameplayMovementPose(A,seq,source,x,y,z)end
 function f:fire(slot,advance)
  local event;for _,e in pairs(self.timers)do if e.alive and e.data.slot==slot then event=e;break end end
  assert(event,'missing timer '..slot);event.alive=false;self.time=self.time+(advance or 0);self.callback=true
  local ok,result=pcall(_G[event.name],event.data);self.callback=false;assert(ok,result);return result
 end
 function f:activeTimers()local n=0;for _,e in pairs(self.timers)do if e.alive then n=n+1 end end;return n end
 function f:lastReason(reason)assert(self.logs[#self.logs]:find('"result":"'..reason..'"',1,true),self.logs[#self.logs])end
 return f
end
test('load and refused begin leave native state untouched',function()
 local f=fixture();eq(f:begin('bad'),false);eq(f:begin(A,86400001),false)
 f.position.x=20;eq(f:begin(),false);eq(f.serial,0);eq(f.writes,0)
 f.position.x=1;player.actor.IsDead=function()return true end;eq(f:begin(),false);eq(f.serial,0)
end)
test('saved position resumes within coverage and normal stop leaves it there',function()
 local f=fixture();eq(f:begin(),true);eq(f.timers[1].ms,86400000);eq(f:pose(1,0,8,8,3),true);eq(f.writes,0)
 f:fire('tick',.01);eq(f.position.x,8);eq(f.position.y,8);eq(f.writes,1)
 eq(MineCome.GameplayMovementEnd(A),true);eq(f.position.x,8);eq(f:activeTimers(),0);f:lastReason('explicit_stop')
 eq(MineCome.GameplayMovementEnd(A),true);eq(f.writes,1)
end)
test('continuous session outlives all demo cutoffs without origin teleport',function()
 local f=fixture();eq(f:begin(),true);eq(f:pose(1,0,1,2,3),true);f:fire('tick',.001)
 for i=2,501 do eq(f:pose(i,(i-1)*50,1+(i-1)*.01,2,3),true);f:fire('tick',.05)end
 assert(f.time>35);assert(MineCome._gameplay_movement.active);assert(f.position.x>5.9);assert(f.position.x<6.01)
 eq(MineCome.GameplayMovementSample(A,500000),true);eq(MineCome.GameplayMovementEnd(A),true);assert(f.position.x>5.9)
end)
test('fresh stationary inventory poses renew lease without movement writes',function()
 local f=fixture();f:begin();f:pose(1,0,1,2,3);f:fire('tick',.001)
 for i=2,21 do eq(f:pose(i,(i-1)*100,1,2,3),true);f:fire('tick',.1)end
 eq(f.writes,0);assert(MineCome._gameplay_movement.active);MineCome.GameplayMovementEnd(A)
end)
test('short lease loss stops in place and old callbacks cannot revive movement',function()
 local f=fixture();f:begin();f:pose(1,0,5,2,3);f:fire('tick',.01)
 local old;for _,e in pairs(f.timers)do if e.alive and e.data.slot=='tick' then old=e.data end end
 f:fire('tick',.401);f:lastReason('source_lease_expired');eq(f.position.x,5);eq(f:activeTimers(),0)
 f:begin(B);local writes=f.writes;eq(MineCome_GameplayMovementTick(old),false);eq(f.writes,writes);MineCome.GameplayMovementEnd(B)
end)
test('replay and out of capture targets terminate before position writes',function()
 for _,args in ipairs({{1,100,1,2,3},{2,100,20,2,3},{2,0,1,2,3},{2,10,9,2,3}})do
  local f=fixture();f:begin();f:pose(1,0,1,2,3);f:fire('tick',.001)
  eq(f:pose(unpack(args)),false);eq(f.writes,0);eq(f:activeTimers(),0)
 end
end)
test('navigation conflicts and explicit hard expiry stop without origin restoration',function()
 local f=fixture();f:begin();f:pose(1,0,5,2,3);f:fire('tick',.01);f.position.x=6
 f:fire('tick',.01);f:lastReason('unexpected_player_navigation');eq(f.position.x,6)
 f=fixture();f:begin(A,1000);f:pose(1,0,5,2,3);f:fire('tick',.01);f:fire('hard',1)
 f:lastReason('session_expired');eq(f.position.x,5);eq(f:activeTimers(),0)
end)
test('native binding failure cleans up and preserves changed world position',function()
 local f=fixture();f:begin();f.write_error=true;f:pose(1,0,5,2,3);f:fire('tick',.01)
 f:lastReason('position_write_failed');eq(f.position.x,5);eq(f:activeTimers(),0)
 f=fixture();f.fail_timer=2;eq(f:begin(),false);eq(f:activeTimers(),0);eq(f.writes,0)
end)
print('PASS '..passed..' gameplay movement tests (simulated bindings)')
