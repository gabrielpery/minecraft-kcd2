-- SPDX-License-Identifier: GPL-3.0-or-later
-- Sustained owned pose follower. Inspected APIs and guards are the same as
-- probes/movement_probe.lua: Entity.SetWorldPos/GetWorldPos/GetVelocity,
-- actor/player/human state getters, System camera/time getters and Script timers.
-- No camera, physics, input, health, velocity or control-state writes. Native
-- keyboard capture belongs to the independently expiring HUD lease.
MineCome = MineCome or {}
MineCome._gameplay_movement = MineCome._gameplay_movement or {}
local state = MineCome._gameplay_movement
local LEASE, SMOOTH, LIMIT = 0.4, 0.1, 10000000
local function finite(v) return type(v)=="number" and v==v and v>-math.huge and v<math.huge end
local function token(v) return type(v)=="string" and #v==32 and v:match("^[0-9a-f]+$")~=nil end
local function vector(v) return type(v)=="table" and finite(v.x) and finite(v.y) and finite(v.z) and math.abs(v.x)<LIMIT and math.abs(v.y)<LIMIT and math.abs(v.z)<LIMIT end
local function copy(v) return vector(v) and {x=v.x,y=v.y,z=v.z} or nil end
local function distance(a,b) if not vector(a) or not vector(b) then return math.huge end return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local function quote(v) return '"'..tostring(v):gsub('[%z\1-\31\\"]',function(c)return string.format('\\u%04x',string.byte(c))end)..'"' end
local function number(v) return finite(v) and string.format('%.17g',v) or 'null' end
local function vec(v) return vector(v) and ('{"x":'..number(v.x)..',"y":'..number(v.y)..',"z":'..number(v.z)..'}') or 'null' end
local function field(o,k) if type(o)~='table' and type(o)~='userdata' then return nil end local ok,v=pcall(function()return o[k]end);return ok and v or nil end
local function read(o,k,global) local f=field(o,k);if type(f)~='function' then return nil,false end local ok,v;if global then ok,v=pcall(f) else ok,v=pcall(f,o) end return v,ok end
local function clock() local v,ok=read(System,'GetCurrTime',true);return ok and finite(v) and v>=0 and v<1000000000000 and v or nil end
local function handle(v) return type(v)=='userdata' or (finite(v) and v>0 and v==math.floor(v)) end
local function snapshot()
 local e=type(player)=='table' and player or nil
 local s={entity=e,id=field(e,'id')};s.position=read(e,'GetWorldPos');s.velocity=read(e,'GetVelocity')
 s.forward=read(System,'GetViewCameraDir',true);s.up=read(System,'GetViewCameraUpDir',true);s.camera=read(System,'GetViewCameraPos',true);s.fov=read(System,'GetViewCameraFov',true)
 s.link,s.link_ok=read(field(e,'actor'),'GetLinkedEntity')
 s.flags={};for _,item in ipairs({{field(e,'actor'),'IsDead'},{field(e,'actor'),'IsUnconscious'},{field(e,'player'),'IsSitting'},{field(e,'player'),'IsLaying'},{field(e,'human'),'IsMounted'}}) do local v,ok=read(item[1],item[2]);s.flags[#s.flags+1]={value=v,ok=ok} end
 return s
end
local function normal(s)
 if not vector(s.forward) or not vector(s.up) or not vector(s.camera) or not finite(s.fov) or s.fov<=0 or s.fov>=math.pi or distance(s.camera,s.position)>3 then return false end
 local f,u=s.forward,s.up
 return math.abs(f.x*f.x+f.y*f.y+f.z*f.z-1)<=0.05 and math.abs(u.x*u.x+u.y*u.y+u.z*u.z-1)<=0.05 and math.abs(f.x*u.x+f.y*u.y+f.z*u.z)<=0.05
end
local function safe(s,p)
 if not s.entity or s.entity~=player or s.id==nil or field(s.entity,'id')~=s.id or not vector(s.position) or not vector(s.velocity) then return 'player_unavailable' end
 if type(s.id)~='userdata' and not(finite(s.id) and s.id>0 and s.id==math.floor(s.id)) then return 'identity_unavailable' end
 for _,f in ipairs(s.flags) do if not f.ok or type(f.value)~='boolean' or f.value then return 'unsafe_player_state' end end
 if not s.link_ok or (s.link~=nil and s.link~=0) then return 'linked_player' end
 if not normal(s) then return 'camera_unavailable' end
 if p and (s.entity~=p.entity or s.id~=p.id or (s.link==nil)~=p.link_nil) then return 'player_changed' end
 if p and distance(s.position,p.last_owned)>0.35 then return 'unexpected_player_navigation' end
 if math.sqrt(s.velocity.x*s.velocity.x+s.velocity.y*s.velocity.y)>0.2 or math.abs(s.velocity.z)>6 then return 'native_input_or_velocity' end
 return nil
end
local function inside(p,v,margin) local b=p.bounds;return vector(v) and v.x>=b[1]-margin and v.x<=b[2]+margin and v.y>=b[3]-margin and v.y<=b[4]+margin and v.z>=b[5]-margin and v.z<=b[6]+margin end
-- Same inspected RayWorldIntersection signature and hit validation as
-- probes/aim_probe.lua; the second ent_terrain ray classifies ground placement.
local function aim_sample(s)
 local unknown={known=false,distance=-1,terrain_hit=false};local began=clock()
 if not began or not Physics or type(Physics.RayWorldIntersection)~='function' then return unknown end
 -- The camera guard permits small length error; ray distances are metres, so
 -- publish and intersect the same exactly normalized direction.
 local length=math.sqrt(s.forward.x^2+s.forward.y^2+s.forward.z^2)
 s.forward={x=s.forward.x/length,y=s.forward.y/length,z=s.forward.z/length}
 local function ray(mask)
  if not finite(mask) or mask<=0 or mask>2147483647 or mask~=math.floor(mask) then return nil end
  local hits={};local d={x=s.forward.x*4.5,y=s.forward.y*4.5,z=s.forward.z*4.5}
  local ok,count=pcall(Physics.RayWorldIntersection,copy(s.camera),d,16,mask,s.id,nil,hits)
  if not ok or not finite(count) or count<0 or count>=16 or count~=math.floor(count) then return nil end
  local nearest=-1
  for i=1,16 do local h=hits[i]
   if i>count then if h~=nil then return nil end
   else
    if type(h)~='table' or not vector(h.pos) or not finite(h.dist) or h.dist<0 or h.dist>4.5 then return nil end
    local expected={x=s.camera.x+s.forward.x*h.dist,y=s.camera.y+s.forward.y*h.dist,z=s.camera.z+s.forward.z*h.dist}
    if distance(h.pos,expected)>.01 then return nil end
    if nearest<0 or h.dist<nearest then nearest=h.dist end
   end
  end
  if hits[17]~=nil then return nil end;return nearest
 end
 local all,terrain=ray(ent_all),ray(ent_terrain);local ended=clock()
 if all==nil or terrain==nil or not ended or ended<began or ended-began>.25 or s.entity~=player or field(s.entity,'id')~=s.id then return unknown end
 if terrain>=0 and (all<0 or terrain<all-.03) then return unknown end
 return {known=true,distance=all,terrain_hit=terrain>=0 and math.abs(terrain-all)<=.03}
end
local function emit(p,event,result,s,seq)
 if not System or type(System.LogAlways)~='function' then return false end
 local t='{"schema":1,"run":'..quote(p.run)..',"event":'..quote(event)..',"result":'..quote(result)..',"seq":'..number(seq or 0)
  ..',"active":'..tostring(not p.terminal)..',"pose_seq":'..number(p.sequence or 0)..',"applied_seq":'..number(p.applied or 0)..',"writes":'..number(p.writes or 0)
  ..',"sampled_engine_seconds":'..number(clock())..',"player":'..vec(s and s.position)..',"camera":'..vec(s and s.camera)..',"forward":'..vec(s and s.forward)..',"up":'..vec(s and s.up)
  ..(s and s.aim and (',"aim":{"known":'..tostring(s.aim.known)..',"distance":'..number(s.aim.distance)..',"terrain_hit":'..tostring(s.aim.terrain_hit)..',"range":4.5}') or '')
  ..',"camera_basis_valid":'..tostring(s~=nil and normal(s))..',"timers_cancelled":'..tostring(p.timers_cancelled==true)..',"position_restored":false,"control_state_changed":false}'
 local ok,v=pcall(System.LogAlways,'[MineComeGameplayMovement] '..t);return ok and v~=false
end
local function cancel(p)
 local good=true
 local kill=field(Script,'KillTimer')
 for slot,id in pairs(p.timers) do p.timers[slot]=nil;local ok,v=false,false;if type(kill)=='function' then ok,v=pcall(kill,id) end;if not ok or v==false then good=false end end
 p.timers_cancelled=good;return good
end
local function finish(p,reason)
 if state.active~=p or p.terminal then return false end
 p.terminal=true;cancel(p);state.active=nil;state.last=p
 -- Stop in place on both explicit stop and failure; never restore an old origin.
 return emit(p,'terminal',reason,snapshot())
end
local function arm(p,slot,name,delay)
 if p.timers[slot]~=nil then return false end
 local data={owner=p,slot=slot};p.data[slot]=data
 local ok,id=pcall(Script.SetTimerForFunction,delay,name,data,true)
 if not ok or not handle(id) then return false end p.timers[slot]=id;return true
end
local function consume(data)
 if type(data)~='table' then return nil end local p=data.owner
 if type(p)~='table' or state.active~=p or p.terminal or p.data[data.slot]~=data or not handle(p.timers[data.slot]) then return nil end
 p.timers[data.slot]=nil;return p
end
function MineCome.GameplayMovementBegin(run,duration_ms,minx,maxx,miny,maxy,minz,maxz,flight)
 if not token(run) or not finite(duration_ms) or duration_ms<1000 or duration_ms>86400000 or duration_ms~=math.floor(duration_ms) then return false,'invalid_identity_or_duration' end
 if flight~=nil and type(flight)~='boolean' then return false,'invalid_flight_profile' end
 if state.active then return false,'busy' end
 if MineCome._movement_probe and (MineCome._movement_probe.active or MineCome._movement_probe.follower) then return false,'diagnostic_busy' end
 local bounds={minx,maxx,miny,maxy,minz,maxz};for i=1,6 do if not finite(bounds[i]) or math.abs(bounds[i])>=LIMIT then return false,'invalid_bounds' end end
 for i=1,5,2 do if bounds[i]>=bounds[i+1] or bounds[i+1]-bounds[i]>4096 then return false,'invalid_bounds' end end
 local s,t=snapshot(),clock();local reason=safe(s)
 if reason then return false,reason end
 if not t or type(field(s.entity,'SetWorldPos'))~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' then return false,'api_unavailable' end
 local p={run=run,entity=s.entity,id=s.id,link_nil=s.link==nil,created=t,deadline=t+duration_ms/1000,last_clock=t,last_owned=copy(s.position),bounds=bounds,timers={},data={},sequence=0,applied=0,writes=0,view_sequence=0}
 -- Vanilla 1.21.1 PlayerEntity.getOffGroundSpeed doubles default .05 flight
 -- acceleration when sprinting; LivingEntity.travel damps XZ by .91. Its
 -- asymptote is below24m/s. Walking retains its existing12m/s admission.
 p.max_speed=flight==true and 24 or 12
 if not inside(p,s.position,2) then return false,'host_outside_capture' end
 state.active=p
 if not arm(p,'hard','MineCome_GameplayMovementExpiry',duration_ms) or not arm(p,'tick','MineCome_GameplayMovementTick',1) then finish(p,'initial_timer_failed');return false,'initial_timer_failed' end
 if not emit(p,'begin','ready',s) then finish(p,'log_failed');return false,'log_failed' end
 return true,'ready'
end
function MineCome.GameplayMovementPose(run,seq,source_ms,x,y,z)
 local p=state.active;if not token(run) or not p or p.run~=run then return false,'inactive' end
 local target={x=x,y=y,z=z};local t=clock();local reason
 if not finite(seq) or seq<1 or seq>10000000 or seq~=math.floor(seq) or seq<=p.sequence then reason='sequence_replayed_or_invalid'
 elseif not finite(source_ms) or source_ms<0 or source_ms>86400000 or (p.latest and source_ms<=p.latest.source_ms) then reason='source_time_invalid'
 elseif not inside(p,target,0) then reason='target_outside_capture'
 elseif not t or t<p.last_clock or t>=p.deadline or (p.latest and t-p.latest.received>LEASE) then reason='source_lease_expired'
 elseif p.latest and distance(target,p.latest.target)>0.5+p.max_speed*(source_ms-p.latest.source_ms)/1000 then reason='source_velocity_invalid' end
 if reason then finish(p,reason);return false,reason end
 p.segment={from=copy(p.last_owned),started=t};p.latest={seq=seq,source_ms=source_ms,target=copy(target),received=t,first=p.sequence==0};p.sequence=seq
 return true,'queued'
end
function MineCome.GameplayMovementSample(run,seq,with_aim)
 local p=state.active;if not token(run) or not p or p.run~=run then return false,'inactive' end
 if not finite(seq) or seq<1 or seq>1000000 or seq~=math.floor(seq) or seq<=p.view_sequence then return false,'view_sequence_invalid' end
 local s,t=snapshot(),clock();local reason=safe(s,p)
 if not t or t<p.last_clock or t>=p.deadline then reason='clock_or_deadline' end
 if reason then finish(p,reason);return false,reason end
 if with_aim==true then s.aim=aim_sample(s) end
 p.view_sequence=seq
 return emit(p,'view','sampled',s,seq),'sampled'
end
function MineCome_GameplayMovementTick(data)
 local p=consume(data);if not p then return false end
 local s,t=snapshot(),clock();local reason=safe(s,p)
 if not t or t<p.last_clock then reason='clock_regressed'
 elseif t>=p.deadline then reason='session_expired'
 elseif p.latest and t-p.latest.received>LEASE then reason='source_lease_expired'
 elseif not p.latest and t-p.created>12 then reason='first_pose_timeout' end
 if reason then return finish(p,reason) end
 p.last_clock=t
 if p.latest then
  local f=p.latest.first and 1 or math.max(0,math.min(1,(t-p.segment.started)/SMOOTH))
  local a,b=p.segment.from,p.latest.target;local target={x=a.x+(b.x-a.x)*f,y=a.y+(b.y-a.y)*f,z=a.z+(b.z-a.z)*f}
  if distance(s.position,target)>0.0001 then
   local ok,v=pcall(p.entity.SetWorldPos,p.entity,copy(target));local observed=snapshot()
   if not ok or v==false or observed.entity~=p.entity or observed.id~=p.id or distance(observed.position,target)>0.05 then return finish(p,'position_write_failed') end
   p.writes=p.writes+1;p.last_owned=copy(observed.position)
  end
  if f==1 then p.applied=p.latest.seq end
 end
 if not arm(p,'tick','MineCome_GameplayMovementTick',1) then return finish(p,'tick_timer_failed') end
 return true
end
function MineCome_GameplayMovementExpiry(data) local p=consume(data);if p then return finish(p,'session_expired') end return false end
function MineCome.GameplayMovementEnd(run)
 if not token(run) then return false,'invalid_run' end
 local p=state.active;if p and p.run==run then return finish(p,'explicit_stop'),'stopped' end
 if state.last and state.last.run==run then return true,'already_stopped' end
 return false,'inactive'
end
