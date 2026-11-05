-- SPDX-License-Identifier: GPL-3.0-or-later
-- Sustained read-only terrain acquisition. The inspected RayWorldIntersection
-- signature/ent_terrain evidence is the same as probes/ground_extension.lua:
-- kcd2-mod-docs9cb0675 script_bind_2025_01_14 and installed PressurizedObject.lua
--308-310. Script timers use the existing gameplay movement/blocks binding.
-- Fixed world anchor, nine rays per timer callback, no player/world writes.
MineCome = MineCome or {}
MineCome._gameplay_terrain = MineCome._gameplay_terrain or {}
local state=MineCome._gameplay_terrain
local LEASE,BUDGET,CAPACITY=2,9,64
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function integer(v,a,b)return finite(v) and v==math.floor(v) and v>=a and v<=b end
local function token(v)return type(v)=='string' and #v==32 and v:match('^[0-9a-f]+$')~=nil end
local function vector(v)return type(v)=='table' and finite(v.x) and finite(v.y) and finite(v.z) and math.abs(v.x)<10000000 and math.abs(v.y)<10000000 and math.abs(v.z)<10000000 end
local function clock()local ok,v=pcall(System.GetCurrTime);if ok and finite(v) and v>=0 then return v end end
local function number(v)return finite(v) and string.format('%.17g',v) or 'null'end
local function emit(p,event,result,job,first)
 local s='[MineComeGameplayTerrain] {"schema":1,"run":"'..p.run..'","event":"'..event..'","result":"'..result..'","active":'..tostring(state.active==p and not p.stopped)..',"timers_cancelled":'..tostring(p.timer==nil)
 if job then
  s=s..',"request":'..job.id..',"tx":'..job.tx..',"tz":'..job.tz..',"ray_count":'..job.rays..',"mask":'..number(p.mask)
  if event=='captured' then
   s=s..',"anchor":{"x":'..number(p.x)..',"y":'..number(p.y)..',"z":'..number(p.z)..'}'
  elseif event=='samples' then
   -- The native log truncates individual lines at4095 bytes. Nine samples fit
   -- below that bound; the final header commits the otherwise private batches.
   s=s..',"first":'..first..',"count":'..(#job.points-first+1)..',"points":['
   for i=first,#job.points do local q=job.points[i]
    if i>first then s=s..','end
    s=s..'{"index":'..i..',"x":'..number(q.x)..',"y":'..number(q.y)..',"z":'..number(q.z)..',"nx":'..number(q.nx)..',"ny":'..number(q.ny)..',"nz":'..number(q.nz)..'}'
   end
   s=s..']'
  end
 end
 local ok,v=pcall(System.LogAlways,s..'}');return ok and v~=false
end
local function schedule(p,ms)
 if p.timer~=nil then return true end
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,ms,'MineCome_GameplayTerrainTick',data,true)
 if not ok or id==nil or id==false then return false end;p.timer=id;p.timer_data=data;return true
end
local function stop(p,why)
 if p.stopped then return true end
 p.stopped=true;p.reason=why;p.job=nil
 if p.timer~=nil then local ok,v=pcall(Script.KillTimer,p.timer);if not ok or v==false then p.reason='timer_cleanup_failed'else p.timer=nil end;p.timer_data=nil end
 state.active=nil;state.last=p;emit(p,'terminal',p.reason);return p.reason==why
end
local function valid(p)
 local t=clock()
 if not t or t<p.last_clock or t>=p.deadline or t-p.received>LEASE then return false,'lease_expired'end
 if player~=p.player or player.id~=p.player_id then return false,'player_changed'end
 p.last_clock=t;return true,nil,t
end
function MineCome.GameplayTerrainBegin(run,duration_ms,x,y,z)
 if not token(run) or not integer(duration_ms,1000,86400000) or not vector({x=x,y=y,z=z}) or math.abs(x)>9999928 or math.abs(y)>9999928 or math.abs(z)>9999990 then return false,'invalid_identity_or_anchor'end
 if state.active then return false,'session_owned'end
 if not System or type(System.LogAlways)~='function' or type(System.GetCurrTime)~='function' or not Physics or type(Physics.RayWorldIntersection)~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' then return false,'api_unavailable'end
 if not player or player.id==nil then return false,'player_unavailable'end
 if not integer(ent_terrain,1,2147483647) then return false,'terrain_mask_unavailable'end
 local t=clock();if not t then return false,'clock_unavailable'end
 local p={run=run,x=x,y=y,z=z,deadline=t+duration_ms/1000,received=t,last_clock=t,player=player,player_id=player.id,mask=ent_terrain,seen={['0:0']=true},tiles=1,sequence=0}
 state.active=p;if not schedule(p,100)then state.active=nil;return false,'timer_unavailable'end
 emit(p,'begin','ready');return true
end
function MineCome.GameplayTerrainHeartbeat(run)
 local p=state.active;if not p or p.run~=run then return false,'session_missing'end
 local ok,why,t=valid(p);if not ok then stop(p,why);return false,why end;p.received=t;return true
end
function MineCome.GameplayTerrainCapture(run,request,tx,tz)
 local p=state.active;if not p or p.run~=run then return false,'session_missing'end
 if not integer(request,1,10000) or request<=p.sequence or not integer(tx,-8,8) or not integer(tz,-8,8) or p.seen[tx..':'..tz] or p.job then return false,'request_or_capacity'end
 local ok,why=MineCome.GameplayTerrainHeartbeat(run);if not ok then return false,why end
 p.sequence=request;p.seen[tx..':'..tz]=true
 local job={id=request,tx=tx,tz=tz,points={},rays=0,started=p.last_clock}
 if p.tiles>=CAPACITY then emit(p,'refused','capacity_reached',job);return true end
 p.job=job;return true
end
local function ray(p,job,index)
 local row=math.floor((index-1)/9);local col=(index-1)%9
 local x,y=p.x+(8*job.tx+col-4),p.y+(-8*job.tz+row-4);local origin={x=x,y=y,z=p.z+8};local hits={}
 local ok,count=pcall(Physics.RayWorldIntersection,origin,{x=0,y=0,z=-16},1,p.mask,p.player_id,nil,hits);job.rays=job.rays+1
 if not ok or count~=1 or type(hits[1])~='table' or hits[2]~=nil then return nil,'terrain_miss'end
 local h=hits[1];if not vector(h.pos) or not vector(h.normal) or not finite(h.dist) or h.dist<0 or h.dist>16 then return nil,'terrain_hit_invalid'end
 local n=h.normal;local norm=n.x*n.x+n.y*n.y+n.z*n.z
 if math.abs(norm-1)>.05 or n.z<.5 or math.abs(h.pos.x-x)>.0001 or math.abs(h.pos.y-y)>.0001 or math.abs(h.pos.z-p.z)>8 or math.abs(origin.z-h.pos.z-h.dist)>.05 then return nil,'terrain_hit_invalid'end
 -- Preserve the requested lattice, as ground_patch.lua does. The engine hit
 -- vector rounds XY to float precision; only height and normal are sampled.
 local q={x=x,y=y,z=h.pos.z,nx=n.x,ny=n.y,nz=n.z}
 if col>0 and math.abs(q.z-job.points[index-1].z)>.5 or row>0 and math.abs(q.z-job.points[index-9].z)>.5 then return nil,'terrain_step_invalid'end
 return q
end
function MineCome_GameplayTerrainTick(data)
 if type(data)~='table' then return end;local p=data.owner
 if not p or state.active~=p or p.timer_data~=data then return end;p.timer=nil;p.timer_data=nil
 local ok,why,t=valid(p);if not ok then stop(p,why);return end
 local job=p.job
 if job then
  if t-job.started>1.5 then emit(p,'refused','capture_expired',job);p.job=nil
  else
   local first=#job.points+1
   for _=1,BUDGET do
    local index=#job.points+1;local q,reason=ray(p,job,index)
    if player~=p.player or player.id~=p.player_id then stop(p,'player_changed');return end
    if not q then emit(p,'refused',reason,job);p.job=nil;break end
    job.points[index]=q
    if index==81 then break end
   end
   if p.job==job then
    local alive,expired,finished=valid(p);if not alive then stop(p,expired);return end
    if finished-job.started>1.5 then emit(p,'refused','capture_expired',job);p.job=nil
    elseif not emit(p,'samples','sampling',job,first)then stop(p,'log_failed');return
    elseif #job.points==81 then p.tiles=p.tiles+1;emit(p,'captured','sampled',job);p.job=nil end
   end
  end
 end
 if not schedule(p,p.job and 10 or 100)then stop(p,'timer_unavailable')end
end
function MineCome.GameplayTerrainEnd(run)
 local p=state.active
 if not p then if state.last and state.last.run==run then emit(state.last,'terminal',state.last.reason);return true end;return false,'session_missing'end
 if p.run~=run then return false,'session_owned'end;return stop(p,'explicit_stop')
end
