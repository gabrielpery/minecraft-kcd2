-- SPDX-License-Identifier: GPL-3.0-or-later
-- Standalone engine-binding simulation, never live game evidence.
local A,B=string.rep('a',32),string.rep('b',32)
local passed=0
local function eq(a,b)assert(a==b,'got '..tostring(a)..', expected '..tostring(b))end
local function test(name,fn)local ok,err=pcall(fn);if not ok then error(name..': '..tostring(err),0)end;passed=passed+1;print('PASS '..name)end
local function copy(v)return{x=v.x,y=v.y,z=v.z}end
local function fixture()
 local f={time=10,position={x=1,y=2,z=3},velocity={x=0,y=0,z=0},timers={},logs={},writes=0,serial=0,callback=false}
 Physics=nil;CryAction=nil;ent_all=15;ent_terrain=1
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
 function f:pose(seq,source,x,y,z,mode,generation)return MineCome.GameplayMovementPose(A,seq,source,x,y,z,mode,mode~=nil and (generation or 1) or nil)end
 function f:fire(slot,advance)
  local event;for _,e in pairs(self.timers)do if e.alive and e.data.slot==slot then event=e;break end end
  assert(event,'missing timer '..slot);event.alive=false;self.time=self.time+(advance or 0);self.callback=true
  if self.pending_camera~=nil then self.camera=self.pending_camera or nil;self.pending_camera=nil end
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

test('only explicit Creative flight permits vanilla sprint flight speed',function()
 local f=fixture();eq(MineCome.GameplayMovementBegin(A,86400000,-10,10,-10,10,-10,10,'true'),false);eq(f.serial,0)
 f:begin();f:pose(1,0,1,2,3);f:fire('tick',.001)
 eq(f:pose(2,100,3.2,2,3),false);f:lastReason('source_velocity_invalid')
 f=fixture();eq(MineCome.GameplayMovementBegin(A,86400000,-10,10,-10,10,-10,10,true),true)
 f:pose(1,0,1,2,3);f:fire('tick',.001);eq(f:pose(2,100,3.2,2,3),true);f:fire('tick',.1)
 eq(f:pose(3,200,6.3,2,3),false);f:lastReason('source_velocity_invalid')
end)

test('flight follows vertical rise hover and landing with normal lease cleanup',function()
 local f=fixture();eq(MineCome.GameplayMovementBegin(A,86400000,-10,10,-10,10,-10,10,true),true)
 f:pose(1,0,1,2,3);f:fire('tick',.001)
 for i=2,11 do eq(f:pose(i,(i-1)*100,1,2,3+(i-1)*.25),true);f:fire('tick',.1)end
 assert(math.abs(f.position.z-5.5)<.000001)
 for i=12,21 do eq(f:pose(i,(i-1)*100,1,2,5.5),true);f:fire('tick',.1)end
 for i=22,31 do eq(f:pose(i,(i-1)*100,1,2,5.5-(i-21)*.25),true);f:fire('tick',.1)end
 assert(math.abs(f.position.z-3)<.000001);eq(MineCome.GameplayMovementEnd(A),true);eq(f:activeTimers(),0)
end)
test('native binding failure cleans up and preserves changed world position',function()
 local f=fixture();f:begin();f.write_error=true;f:pose(1,0,5,2,3);f:fire('tick',.01)
 f:lastReason('position_write_failed');eq(f.position.x,5);eq(f:activeTimers(),0)
 f=fixture();f.fail_timer=2;eq(f:begin(),false);eq(f:activeTimers(),0);eq(f.writes,0)
end)
local function aim_fixture(all_distance,terrain_distance)
 local f=fixture();f.rays={};f:begin()
 Physics={RayWorldIntersection=function(origin,direction,maximum,mask,skip,skip2,hits)
  eq(maximum,16);eq(skip,17);eq(skip2,nil)
  assert(math.abs(direction.x^2+direction.y^2+direction.z^2-4.5^2)<.000001)
  f.rays[#f.rays+1]={origin=copy(origin),direction=copy(direction),mask=mask}
  local d=mask==ent_all and all_distance or terrain_distance
  if d and d>=0 then hits[1]={pos={x=origin.x+direction.x*d/4.5,y=origin.y+direction.y*d/4.5,z=origin.z+direction.z*d/4.5},dist=d} end
  -- Bindings may mutate their argument copies; the captured origin is immutable.
  origin.x=999;direction.y=999
  return d and d>=0 and 1 or 0
 end}
 function f:sample(seq)
  eq(MineCome.GameplayMovementSample(A,seq or 1,true),true)
  return self.logs[#self.logs]
 end
 return f
end
test('aim samples use camera origin and normalized direction without native writes',function()
 local f=aim_fixture(2,2);System.GetViewCameraDir=function()return{x=0,y=1.01,z=0}end
 local line=f:sample();assert(line:find('"aim":{"known":true,"distance":2,"terrain_hit":true,"range":4.5}',1,true),line)
 eq(#f.rays,2);eq(f.rays[1].origin.x,1);eq(f.rays[1].origin.z,4.6);eq(f.rays[1].direction.y,4.5)
 assert(line:find('"forward":{"x":0,"y":1,"z":0}',1,true),line);eq(f.writes,0)
 MineCome.GameplayMovementEnd(A)
end)
test('aim distinguishes clear ground and nearer native obstruction',function()
 for _,case in ipairs({{-1,-1,false},{1,2,false},{2,2,true}})do
  local f=aim_fixture(case[1],case[2]);local line=f:sample()
  assert(line:find('"known":true,"distance":'..case[1]..',"terrain_hit":'..tostring(case[3]),1,true),line)
  eq(f.writes,0);MineCome.GameplayMovementEnd(A)
 end
end)
test('uncertain rays never authorize native obstruction bypass',function()
 local faults={
  function(f)Physics=nil end,
  function(f)ent_terrain=2147483648 end,
  function(f)Physics.RayWorldIntersection=function()error('binding unavailable')end end,
  function(f)Physics.RayWorldIntersection=function()return 16 end end,
  function(f)Physics.RayWorldIntersection=function(o,d,n,m,s,s2,h)h[1]={pos={x=20,y=20,z=20},dist=1};return 1 end end,
  function(f)Physics.RayWorldIntersection=function(o,d,n,m,s,s2,h)h[1]={pos=copy(o),dist=0};return 0 end end,
  function(f)local ray=Physics.RayWorldIntersection;Physics.RayWorldIntersection=function(...)f.time=f.time+.2;return ray(...)end end,
  function(f)local ray=Physics.RayWorldIntersection;Physics.RayWorldIntersection=function(...)local count=ray(...);player.id=18;return count end end
 }
 for _,fault in ipairs(faults)do
  local f=aim_fixture(2,2);fault(f);local line=f:sample()
  assert(line:find('"aim":{"known":false,"distance":-1,"terrain_hit":false',1,true),line);eq(f.writes,0)
 end
 local f=aim_fixture(2,1);local line=f:sample();assert(line:find('"known":false',1,true),line)
end)
local function perspective_fixture()
 local f=fixture();f.look={x=0,y=1,z=0};f.camera_writes=0;f.resets=0;f.clip_rays=0;f.body_draws={};f.body_visible=true
 player.IsSlotValid=function(_,slot)eq(slot,0);return true end;player.IsSlotCharacter=player.IsSlotValid;player.IsHidden=function()return false end
 player.DrawSlot=function(_,slot,enabled)
  eq(slot,0);f.body_draws[#f.body_draws+1]=enabled;f.body_visible=enabled==1
  if enabled==0 and f.body_hide_error then error('partial body hide')end
  if enabled==1 and f.body_restore_error then return false end
 end
 local function eye()return{x=f.position.x,y=f.position.y,z=f.position.z+1.6}end
 player.actor.GetHeadPos=eye;player.actor.GetHeadDir=function()return copy(f.look)end
 System.GetViewCameraPos=function()return f.camera and copy(f.camera.position) or eye()end
 System.GetViewCameraDir=function()return f.camera and copy(f.camera.direction) or copy(f.look)end
 System.GetViewCameraUpDir=function()
  local d=System.GetViewCameraDir();local u={x=-d.x*d.z,y=-d.y*d.z,z=1-d.z*d.z};local n=math.sqrt(u.x*u.x+u.y*u.y+u.z*u.z)
  return{x=u.x/n,y=u.y/n,z=u.z/n}
 end
 CryAction={SetViewCamera=function(position,direction)
  eq(f.callback,true);f.camera_writes=f.camera_writes+1
  if not f.drop_camera then f.pending_camera={position=copy(position),direction={x=direction[1],y=direction[2],z=direction[3]}} end
  if f.camera_error then error('partial camera write')end
 end,ResetToNormalCamera=function()
  f.resets=f.resets+1;if f.reset_errors and f.resets<=f.reset_errors then error('reset error')end
  f.pending_camera=false
 end}
 Physics={RayWorldIntersection=function(o,d,n,mask,skip,skip2,hits)
  eq(n,16);eq(skip,17);eq(skip2,nil);local length=math.sqrt(d.x*d.x+d.y*d.y+d.z*d.z)
  if math.abs(length-2.5)<.00001 then
   f.clip_rays=f.clip_rays+1;if f.bad_clip then error('clip unavailable')end
   local distance=f.clip_distance
   if distance then hits[1]={pos={x=o.x+d.x*distance/length,y=o.y+d.y*distance/length,z=o.z+d.z*distance/length},dist=distance};return 1 end
  else f.last_aim={origin=copy(o),direction=copy(d)} end
  return 0
 end}
 function f:beginPerspective()
  local ok,why=MineCome.GameplayMovementBegin(A,86400000,-10,10,-10,10,-10,10,false,true)
  if ok then eq(MineCome.GameplayCameraGeometry(A,1,1,1,0,0,0,true,''),true) end
  return ok,why
 end
 function f:finishPerspective()MineCome.GameplayMovementEnd(A);for i=1,3 do if MineCome._gameplay_movement.active then self:fire('cleanup',.05)end end;eq(self:activeTimers(),0)end
 return f
end
test('perspective is explicit and initial first person remains camera-write free',function()
 local f=perspective_fixture();eq(MineCome.GameplayMovementBegin(A,1000,-10,10,-10,10,-10,10,false,'true'),false)
 eq(f:beginPerspective(),true);eq(f:pose(1,0,1,2,3,0),true);f:fire('tick',.01)
 eq(MineCome.GameplayMovementSample(A,1,true),true);assert(f.logs[#f.logs]:find('"perspective":0',1,true));eq(f.camera_writes,0);eq(f.resets,0);f:finishPerspective()
 f=fixture();f:begin();eq(f:pose(1,0,1,2,3,1),false);f:lastReason('perspective_request_invalid')
 for _,mode in ipairs({-1,3,1.5,'1'})do f=perspective_fixture();f:beginPerspective();eq(f:pose(1,0,1,2,3,mode),false);eq(f.camera_writes,0)end
end)
test('third back acknowledges only actual deferred camera and keeps eye aiming',function()
 local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01)
 eq(f.camera_writes,1);eq(f.clip_rays,5)
 local logs=#f.logs;local ok,result=MineCome.GameplayMovementSample(A,1,true);eq(ok,true);eq(result,'camera_pending');eq(#f.logs,logs)
 f:fire('tick',.01);assert(f.logs[#f.logs]:find('"perspective":1',1,true),f.logs[#f.logs]);eq(f.camera.position.y,-.5)
 eq(f.last_aim.origin.y,2);eq(f.last_aim.origin.z,4.6);eq(f.last_aim.direction.y,4.5)
 f:finishPerspective();f:lastReason('explicit_stop');assert(f.logs[#f.logs]:find('"camera_restored":true',1,true))
end)
test('independent native yaw pitch drives camera while front retains natural movement forward',function()
 local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01);f:fire('tick',.01)
 f.look={x=.8,y=0,z=.6};f:pose(2,50,1,2,3,2);f:fire('tick',.01);f:fire('tick',.01)
 eq(MineCome.GameplayMovementSample(A,2,true),true);local line=f.logs[#f.logs]
 assert(line:find('"perspective":2',1,true),line);assert(line:find('"forward":{"x":0.8',1,true) or line:find('"forward":{"x":0.800000',1,true),line)
 assert(f.camera.direction.x<-.79);assert(f.last_aim.direction.x< -3.59);eq(f.last_aim.origin.x,1)
 f:finishPerspective();eq(f.writes,0)
end)
test('camera corner rays clip displacement and malformed clipping collapses to eye',function()
 for _,bad in ipairs({false,true})do
  local f=perspective_fixture();f.clip_distance=.7;f.bad_clip=bad;f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01);f:fire('tick',.01)
  assert(math.abs(f.camera.position.y-(bad and 2 or 1.45))<.000001);eq(MineCome.GameplayMovementSample(A,1,true),true);f:finishPerspective()
 end
end)
test('return to first person waits for current head readback and releases override',function()
 local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01);f:fire('tick',.01)
 f:pose(2,50,1,2,3,0);f:fire('tick',.01);local ok,result=MineCome.GameplayMovementSample(A,1,true);eq(ok,true);eq(result,'camera_pending')
 f:fire('tick',.01);f:fire('tick',.01);assert(f.logs[#f.logs]:find('"perspective":0',1,true),f.logs[#f.logs]);eq(f.camera,nil)
 local resets=f.resets;f:finishPerspective();eq(f.resets,resets)
end)
test('camera lease loss and partial write failure restore before terminal receipt',function()
 for _,write_error in ipairs({false,true})do
  local f=perspective_fixture();f:beginPerspective();f.camera_error=write_error;f:pose(1,0,1,2,3,1);f:fire('tick',.01)
  if not write_error then f:fire('tick',.401)end
  assert(MineCome._gameplay_movement.active.stopping);f:fire('cleanup',.05);eq(MineCome._gameplay_movement.active,nil);eq(f.camera,nil);eq(f:activeTimers(),0)
  f:lastReason(write_error and 'camera_write_failed' or 'source_lease_expired')
 end
end)
test('reset retries are bounded and failed camera readback never acknowledges new mode',function()
 local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01);f:fire('tick',.01);f.reset_errors=9;f:finishPerspective();eq(f.resets,3);f:lastReason('camera_restore_failed:explicit_stop')
 f=perspective_fixture();f.drop_camera=true;f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01);MineCome.GameplayMovementSample(A,1,true)
 f:fire('tick',.26);f:fire('cleanup',.05);eq(MineCome._gameplay_movement.active,nil);f:lastReason('camera_readback_expired')
 for _,line in ipairs(f.logs)do assert(not line:find('"event":"view"',1,true),line)end
end)
test('delayed camera readback matches its original eye and mode amid newer mouse requests',function()
 local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.005)
 local old=f.pending_camera;f.pending_camera=nil;f.look={x=1,y=0,z=0};f:pose(2,10,1,2,3,2);f:fire('tick',.005)
 f.pending_camera=nil;f.camera=old;eq(MineCome.GameplayMovementSample(A,1,true),true)
 local line=f.logs[#f.logs];assert(line:find('"perspective":1',1,true),line);assert(line:find('"forward":{"x":0,"y":1,"z":0}',1,true),line)
 eq(f.last_aim.origin.y,2);eq(f.last_aim.direction.y,4.5)
 for i=1,20 do f:fire('tick',.001)end
 assert(#MineCome._gameplay_movement.active.camera_requests<=16);f:finishPerspective()
end)
test('high frequency ticks do not exhaust reset retries before delayed normal view',function()
 local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.005);f:fire('tick',.005)
 f:pose(2,20,1,2,3,0);f:fire('tick',.001);eq(f.resets,1)
 for i=1,8 do f.pending_camera=nil;f:fire('tick',.005)end
 eq(f.resets,1);assert(MineCome._gameplay_movement.active);f.pending_camera=false;f:fire('tick',.005)
 eq(MineCome._gameplay_movement.active.camera_owned,false);f:finishPerspective();eq(f.resets,1)
end)
test('owned body baseline hides only third person and restores on first person and stop',function()
 local f=perspective_fixture();f:beginPerspective();eq(#f.body_draws,1);eq(f.body_draws[1],1)
 f:pose(1,0,1,2,3,1);f:fire('tick',.005);eq(f.body_visible,false);eq(f.body_draws[2],0);f:fire('tick',.005);eq(#f.body_draws,2)
 f:pose(2,20,1,2,3,0);f:fire('tick',.005);eq(f.body_visible,true);f:fire('tick',.005)
 f:pose(3,40,1,2,3,2);f:fire('tick',.005);eq(f.body_visible,false);f:fire('tick',.005);f:finishPerspective();eq(f.body_visible,true)
 assert(f.logs[#f.logs]:find('"body_restore_dispatched":true',1,true),f.logs[#f.logs]);eq(f.writes,0)
end)
test('body slot validation and partial hide failures never leave an owned hidden slot',function()
 local f=perspective_fixture();player.IsSlotCharacter=function()return false end;eq(f:beginPerspective(),false);eq(#f.body_draws,0)
 f=perspective_fixture();f:beginPerspective();f.body_hide_error=true;f:pose(1,0,1,2,3,1);f:fire('tick',.005)
 eq(f.body_visible,true);eq(MineCome._gameplay_movement.active,nil);f:lastReason('body_hide_failed');eq(f.camera_writes,0)
 f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.005);f:fire('tick',.005);f.body_restore_error=true;f:finishPerspective()
 f:lastReason('body_restore_failed:explicit_stop');assert(f.logs[#f.logs]:find('"body_restore_dispatched":false',1,true),f.logs[#f.logs])
end)
test('unresolved camera or body cleanup blocks both legacy and perspective begin without writes',function()
 for _,failure in ipairs({'camera','body'})do
  local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.005);f:fire('tick',.005)
  if failure=='camera' then f.reset_errors=9 else f.body_restore_error=true end
  f:finishPerspective();f:lastReason(failure..'_restore_failed:explicit_stop')
  local previous=MineCome._gameplay_movement.last
  assert(previous.camera_owned or previous.body_restore_needed)
  local serial,writes,resets,draws,logs=f.serial,f.camera_writes,f.resets,#f.body_draws,#f.logs
  local ok,reason=f:begin(B);eq(ok,false);eq(reason,'prior_cleanup_incomplete')
  ok,reason=f:beginPerspective();eq(ok,false);eq(reason,'prior_cleanup_incomplete')
  eq(MineCome._gameplay_movement.active,nil);eq(MineCome._gameplay_movement.last,previous)
  eq(f.serial,serial);eq(f.camera_writes,writes);eq(f.resets,resets);eq(#f.body_draws,draws);eq(#f.logs,logs);eq(f:activeTimers(),0)
 end
end)
test('successful perspective cleanup permits later legacy and perspective sessions',function()
 for _,perspective in ipairs({false,true})do
  local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.005);f:fire('tick',.005);f:finishPerspective()
  f:lastReason('explicit_stop');eq(MineCome._gameplay_movement.last.camera_owned,false);eq(MineCome._gameplay_movement.last.body_restore_needed,false)
  if perspective then eq(f:beginPerspective(),true);f:finishPerspective()
  else eq(f:begin(B),true);eq(MineCome.GameplayMovementEnd(B),true)end
  eq(f:activeTimers(),0);eq(f.body_visible,true);eq(f.camera,nil)
 end
end)
local function pack_box(q)local t={};for _,n in ipairs(q)do t[#t+1]=string.format('%04x',(n*16)%65536)end;return table.concat(t)end
test('owned camera volume clips full boxes and corners while preserving partial gaps',function()
 -- MC boxes map (x,y,z) to native (x,-z,y). Native eye is (1,2,4.6).
 for _,case in ipairs({
  {box={.5,4,-1,1.5,5,0},reach=.85},
  {box={1.1,4,-1,1.5,5,0},reach=.85},
  {box={.5,3,-1,1.5,4,0},reach=2.5},
  {box={.5,4,-2,1.5,5,-1},reach=0},
 }) do
  -- Quantized thin corner begins at 1.0625, intersecting the camera volume.
  if case.box[1]==1.1 then case.box[1]=1.0625 end
  local f=perspective_fixture();f:beginPerspective()
  eq(MineCome.GameplayCameraGeometry(A,2,1,1,0,0,0,true,pack_box(case.box)),true)
  eq(f:pose(1,0,1,2,3,1,2),true);f:fire('tick',.01);f:fire('tick',.01)
  assert(math.abs(f.camera.position.y-(2-case.reach))<.000001,tostring(f.camera.position.y));f:finishPerspective()
 end
end)
test('owned geometry is atomic and new incomplete generation collapses camera until commit',function()
 local f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1,2);f:fire('tick',.01);f:fire('tick',.01);eq(f.camera.position.y,2)
 local far=pack_box({5,5,5,6,6,6});local wall=pack_box({.5,4,-1,1.5,5,0})
 eq(MineCome.GameplayCameraGeometry(A,2,1,2,0,0,0,true,far),true)
 f:fire('tick',.01);f:fire('tick',.01);eq(f.camera.position.y,2)
 eq(MineCome.GameplayCameraGeometry(A,2,2,2,0,0,0,true,wall),true)
 f:fire('tick',.01);f:fire('tick',.01);assert(math.abs(f.camera.position.y-1.15)<.000001)
 f:pose(2,100,1,2,3,1,3);eq(MineCome.GameplayCameraGeometry(A,3,1,1,0,0,0,false,''),true)
 f:fire('tick',.01);f:fire('tick',.01);eq(f.camera.position.y,2)
 f:pose(3,150,1,2,3,1,4);eq(MineCome.GameplayCameraGeometry(A,4,1,1,0,0,0,true,''),true)
 f:fire('tick',.01);f:fire('tick',.01);eq(f.camera.position.y,-.5);f:finishPerspective()
end)
test('front orbit and native scenery take the nearest independently clipped distance',function()
 local f=perspective_fixture();f:beginPerspective();local wall=pack_box({.5,4,-4,1.5,5,-3})
 eq(MineCome.GameplayCameraGeometry(A,2,1,1,0,0,0,true,wall),true)
 f:pose(1,0,1,2,3,2,2);f:fire('tick',.01);f:fire('tick',.01)
 assert(math.abs(f.camera.position.y-2.85)<.000001)
 f.clip_distance=.5;f:fire('tick',.01);f:fire('tick',.01)
 assert(math.abs(f.camera.position.y-2.35)<.000001);f:finishPerspective()
end)
test('geometry rejects malformed replay and mixed chunks without partial commit',function()
 local f=perspective_fixture();f:beginPerspective();local wall=pack_box({.5,4,0,1.5,5,1})
 for _,packed in ipairs({'g',string.rep('0',24),wall..'a',string.rep(wall,33)})do eq(MineCome.GameplayCameraGeometry(A,2,1,1,0,0,0,true,packed),false)end
 eq(MineCome.GameplayCameraGeometry(B,2,1,1,0,0,0,true,wall),false)
 eq(MineCome.GameplayCameraGeometry(A,1,1,1,0,0,0,true,wall),false)
 eq(MineCome.GameplayCameraGeometry(A,3,1,2,0,0,0,true,wall),true)
 eq(MineCome.GameplayCameraGeometry(A,3,2,2,1,0,0,true,wall),false)
 eq(MineCome.GameplayCameraGeometry(A,3,2,2,0,0,0,true,wall),true)
 eq(MineCome.GameplayCameraGeometry(A,3,2,2,0,0,0,true,wall),false)
 eq(MineCome._gameplay_movement.active.camera_geometry.generation,3);eq(#MineCome._gameplay_movement.active.camera_geometry.boxes,2)
 eq(f:pose(1,0,1,2,3,1,3),true);eq(f:pose(2,100,1,2,3,1,2),false);f:lastReason('camera_geometry_generation_invalid')
end)
test('third person follows observed feet beyond frozen native head position',function()
 local f=perspective_fixture();local head=player.actor.GetHeadPos;local frozen=head()
 player.actor.GetHeadPos=function()return f.camera and copy(frozen) or head()end
 f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01);f:fire('tick',.01)
 for i=2,42 do
  eq(f:pose(i,(i-1)*50,1+(i-1)*.1,2,3,1),true);f:fire('tick',.05)
  assert(MineCome._gameplay_movement.active and not MineCome._gameplay_movement.active.stopping)
 end
 f:fire('tick',.1);f:fire('tick',.01);eq(MineCome.GameplayMovementSample(A,1,true),true)
 assert(f.position.x-frozen.x>4);assert(math.abs(f.last_aim.origin.x-f.position.x)<.000001)
 assert(math.abs(f.camera.position.x-f.position.x)<.000001);eq(f.last_aim.origin.z,4.6)
 -- Reset still requires the actual normal head readback, not the derived eye.
 f:pose(43,2200,f.position.x,2,3,0);f:fire('tick',.01);f:fire('tick',.01);f:fire('tick',.01)
 eq(f.camera,nil);eq(MineCome.GameplayMovementSample(A,2,true),true)
 assert(f.logs[#f.logs]:find('"perspective":0',1,true),f.logs[#f.logs]);f:finishPerspective()
end)
test('captured local eye offset rotates with live yaw without tilting its height',function()
 local f=perspective_fixture();local function actual_head()return{x=f.position.x+.2,y=f.position.y+.1,z=f.position.z+1.6}end
 local frozen=actual_head();player.actor.GetHeadPos=function()return f.camera and copy(frozen) or actual_head()end
 local camera_pos=System.GetViewCameraPos;System.GetViewCameraPos=function()return f.camera and camera_pos() or actual_head()end
 f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01);f:fire('tick',.01)
 f.look={x=.8,y=0,z=.6};f:pose(2,50,1.1,2,3,1);f:fire('tick',.1);f:fire('tick',.01)
 eq(MineCome.GameplayMovementSample(A,1,true),true)
 assert(math.abs(f.last_aim.origin.x-1.2)<.000001);assert(math.abs(f.last_aim.origin.y-1.8)<.000001);eq(f.last_aim.origin.z,4.6)
 assert(math.abs(f.camera.position.x-(1.2-2))<.000001);assert(math.abs(f.camera.position.z-3.1)<.000001)
 f:finishPerspective();f:lastReason('explicit_stop')
end)
test('derived eye preserves head baseline bounds and native velocity guards',function()
 local f=perspective_fixture();player.actor.GetHeadPos=function()return{x=1,y=2,z=6.01}end
 local ok,why=f:beginPerspective();eq(ok,false);eq(why,'perspective_api_unavailable');eq(f.camera_writes,0)
 f=perspective_fixture();f:beginPerspective();f:pose(1,0,1,2,3,1);f:fire('tick',.01);f:fire('tick',.01)
 f.velocity.x=.21;f:fire('tick',.01);f:fire('cleanup',.05);f:lastReason('native_input_or_velocity')
end)
print('PASS '..passed..' gameplay movement tests (simulated bindings)')
