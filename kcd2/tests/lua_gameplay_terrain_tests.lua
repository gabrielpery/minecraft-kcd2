-- Mocked inspected bindings: this verifies batching/ownership, not live terrain.
local A,B=string.rep('a',32),string.rep('b',32)
local passed=0
local function eq(a,b)assert(a==b,'got '..tostring(a)..', expected '..tostring(b))end
local function test(name,fn)local ok,err=pcall(fn);if not ok then error(name..': '..tostring(err),0)end;passed=passed+1;print('PASS '..name)end
local function fixture()
 local f={time=10,timers={},logs={},rays={},serial=0,callback=false};MineCome={};player={id=17};ent_terrain=256
 System={GetCurrTime=function()return f.time end,LogAlways=function(s)f.logs[#f.logs+1]=s end}
 Physics={RayWorldIntersection=function(origin,direction,count,mask,skip,skip2,hits)
  eq(f.callback,true);eq(count,1);eq(mask,256);eq(skip,17);eq(skip2,nil);eq(direction.x,0);eq(direction.y,0);eq(direction.z,-16)
  f.rays[#f.rays+1]=origin;eq(origin.z,64)
  if f.slow then f.time=f.time+f.slow end
  if f.miss then return 0 end
  local z=56;if f.step and #f.rays==2 then z=57 end
  hits[1]={pos={x=origin.x,y=origin.y,z=z},normal={x=0,y=0,z=f.bad_normal and .1 or 1},dist=64-z}
  if f.replace then player={id=17}end
  return 1
 end}
 Script={SetTimerForFunction=function(ms,name,data,paused)
  eq(paused,true);f.serial=f.serial+1;f.timers[f.serial]={name=name,data=data,ms=ms,alive=true};return f.serial
 end,KillTimer=function(id)assert(f.timers[id].alive);if f.fail_kill then return false end;f.timers[id].alive=false end}
 dofile(MINECOME_MODULE_PATH);eq(f.serial,0);eq(#f.rays,0)
 function f:begin()return MineCome.GameplayTerrainBegin(A,86400000,120,2040,56)end
 function f:fire(advance)
  local e;for i=1,self.serial do if self.timers[i].alive then e=self.timers[i];break end end;assert(e,'No timer')
  e.alive=false;self.time=self.time+(advance or e.ms/1000);self.callback=true
  local ok,err=pcall(_G[e.name],e.data);self.callback=false;assert(ok,err)
 end
 function f:reason(r)assert(self.logs[#self.logs]:find('"result":"'..r..'"',1,true),self.logs[#self.logs])end
 function f:drain(n)for _=1,n do self:fire()end end
 return f
end
test('capture is read-only, bounded and fixed to the base anchor',function()
 local f=fixture();assert(f:begin());eq(MineCome.GameplayTerrainBegin(B,1000,120,2040,56),false)
 assert(MineCome.GameplayTerrainCapture(A,1,1,-1));eq(#f.rays,0)
 f:fire();eq(#f.rays,9);eq(f.rays[1].x,124);eq(f.rays[1].y,2044)
 player.position={x=999,y=999,z=999};f:drain(8);eq(#f.rays,81);eq(f.rays[81].x,132);eq(f.rays[81].y,2052);f:reason('sampled')
 assert(f.logs[#f.logs-1]:find('"index":81',1,true));assert(f.logs[#f.logs]:find('"anchor":{"x":120,"y":2040,"z":56}',1,true))
 assert(not f.logs[#f.logs]:find('"points"',1,true));local batches=0
 for _,line in ipairs(f.logs)do assert(#line<4095,'Native log line exceeds actual engine bound');if line:find('"event":"samples"',1,true)then batches=batches+1;assert(line:find('"count":9',1,true))end end
 eq(batches,9)
 eq(MineCome.GameplayTerrainCapture(A,2,1,-1),false);eq(MineCome.GameplayTerrainCapture(A,1,0,-1),false)
 assert(MineCome.GameplayTerrainEnd(A));f:reason('explicit_stop');eq(MineCome._gameplay_terrain.active,nil)
 assert(MineCome.GameplayTerrainEnd(A));eq(#f.rays,81)
end)
test('bad terrain refuses only that tile and never publishes partial points',function()
 for _,mode in ipairs({'miss','bad_normal','step'})do
  local f=fixture();assert(f:begin());f[mode]=true;assert(MineCome.GameplayTerrainCapture(A,1,-1,0));f:fire()
  f:reason(mode=='miss' and 'terrain_miss' or mode=='step' and 'terrain_step_invalid' or 'terrain_hit_invalid')
  assert(not f.logs[#f.logs]:find('"points"',1,true));assert(MineCome._gameplay_terrain.active)
  f[mode]=false;assert(MineCome.GameplayTerrainCapture(A,2,0,1));f:drain(9);f:reason('sampled');assert(MineCome.GameplayTerrainEnd(A))
 end
end)
test('invalid requests never enter native sampling',function()
 local f=fixture();eq(MineCome.GameplayTerrainBegin('bad',1000,0,0,0),false);assert(f:begin())
 for _,p in ipairs({{1,0,0},{1,9,0},{1,0,-9},{1,.5,1},{0,1,0}})do eq(MineCome.GameplayTerrainCapture(A,p[1],p[2],p[3]),false)end
 assert(MineCome.GameplayTerrainCapture(A,1,1,0));eq(MineCome.GameplayTerrainCapture(A,2,0,1),false);eq(#f.rays,0)
end)
test('lease and player identity changes retire pending capture',function()
 local f=fixture();assert(f:begin());assert(MineCome.GameplayTerrainCapture(A,1,1,0));f:fire(2.1);f:reason('lease_expired');eq(#f.rays,0)
 f=fixture();assert(f:begin());assert(MineCome.GameplayTerrainCapture(A,1,1,0));f.replace=true;f:fire();f:reason('player_changed');eq(#f.rays,1)
end)
test('slow capture cannot publish after its deadline',function()
 local f=fixture();assert(f:begin());assert(MineCome.GameplayTerrainCapture(A,1,1,0));f:fire(1.6);f:reason('capture_expired');eq(#f.rays,0)
 f=fixture();assert(f:begin());assert(MineCome.GameplayTerrainCapture(A,1,1,0));f:drain(8);f.slow=.16;f:fire();f:reason('capture_expired');eq(#f.rays,81)
end)
test('stale callback cannot sample after stop or affect a replacement session',function()
 local f=fixture();assert(f:begin());local stale=f.timers[1].data;assert(MineCome.GameplayTerrainEnd(A));assert(MineCome.GameplayTerrainBegin(B,1000,120,2040,56))
 MineCome_GameplayTerrainTick(stale);eq(#f.rays,0);eq(MineCome._gameplay_terrain.active.run,B)
end)
test('timer cleanup failure is reported without renewing capture',function()
 local f=fixture();assert(f:begin());f.fail_kill=true;eq(MineCome.GameplayTerrainEnd(A),false);f:reason('timer_cleanup_failed')
 assert(f.logs[#f.logs]:find('"timers_cancelled":false',1,true));f:fire();eq(#f.rays,0)
end)
test('tile capacity includes base and rejects excess before native work',function()
 local f=fixture();assert(f:begin());local n=0
 for x=-8,8 do for z=-8,8 do if x~=0 or z~=0 then
  n=n+1;if n<=63 then assert(MineCome.GameplayTerrainCapture(A,n,x,z));f:drain(9);f:reason('sampled')
  else assert(MineCome.GameplayTerrainCapture(A,n,x,z));f:reason('capacity_reached');eq(#f.rays,63*81);assert(MineCome._gameplay_terrain.active);return end
 end end end
end)
print('PASS '..passed..' gameplay terrain Lua checks')
