-- SPDX-License-Identifier: GPL-3.0-or-later
-- Sustained owned pose follower. Inspected APIs and guards are the same as
-- probes/movement_probe.lua: Entity.SetWorldPos/GetWorldPos/GetVelocity,
-- actor/player/human state getters, System camera/time getters and Script timers.
-- Opted-in world rendering also uses actor.GetHeadPos/GetHeadDir and
-- CryAction.SetViewCamera/ResetToNormalCamera, inspected in
-- kcd2-mod-docs 9cb0675 cube.xml:14-38 and actor binding pages. Live independent
-- look receipt: runtime/evidence/perspective-probe-20261108-114140-eaea0d0b798e4e388046162f9b311759.
-- No physics, input, health, velocity or control-state writes.
-- Owned world-block sessions establish a VISIBLE native body-slot0 baseline.
-- BasicActor.lua:203 loads slot0; inspected CScriptBindEntity__DrawSlot and
-- IsSlotValid/IsSlotCharacter/IsHidden bindings provide render-only suppression.
-- There is no draw-flag getter: this does not preserve third-party hidden flags.
MineCome = MineCome or {}
MineCome._gameplay_movement = MineCome._gameplay_movement or {}
local state = MineCome._gameplay_movement
local LEASE, SMOOTH, LIMIT = 0.4, 0.1, 10000000
local function finite(v) return type(v)=="number" and v==v and v>-math.huge and v<math.huge end
local function token(v) return type(v)=="string" and #v==32 and v:match("^[0-9a-f]+$")~=nil end
local function vector(v) return type(v)=="table" and finite(v.x) and finite(v.y) and finite(v.z) and math.abs(v.x)<LIMIT and math.abs(v.y)<LIMIT and math.abs(v.z)<LIMIT end
local function copy(v) return vector(v) and {x=v.x,y=v.y,z=v.z} or nil end
local function distance(a,b) if not vector(a) or not vector(b) then return math.huge end return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local function dot(a,b)return a.x*b.x+a.y*b.y+a.z*b.z end
local function scale(a,n)return{x=a.x*n,y=a.y*n,z=a.z*n}end
local function plus(a,b)return{x=a.x+b.x,y=a.y+b.y,z=a.z+b.z}end
local function unit(v)if not vector(v) then return nil end local n=math.sqrt(dot(v,v));if n<.000001 then return nil end return scale(v,1/n)end
local function up_for(f)return unit({x=-f.x*f.z,y=-f.y*f.z,z=1-f.z*f.z})end
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
 s.head_position=read(field(e,'actor'),'GetHeadPos');s.head_direction=read(field(e,'actor'),'GetHeadDir')
 s.link,s.link_ok=read(field(e,'actor'),'GetLinkedEntity')
 s.flags={};for _,item in ipairs({{field(e,'actor'),'IsDead'},{field(e,'actor'),'IsUnconscious'},{field(e,'player'),'IsSitting'},{field(e,'player'),'IsLaying'},{field(e,'human'),'IsMounted'}}) do local v,ok=read(item[1],item[2]);s.flags[#s.flags+1]={value=v,ok=ok} end
 return s
end
local function normal(s,p)
 if not vector(s.forward) or not vector(s.up) or not vector(s.camera) or not finite(s.fov) or s.fov<=0 or s.fov>=math.pi then return false end
 if p and p.camera_owned then
  if distance(s.head_position,s.position)>3 or distance(s.camera,s.head_position)>4 then return false end
 elseif distance(s.camera,s.position)>3 then return false end
 local f,u=s.forward,s.up
 return math.abs(f.x*f.x+f.y*f.y+f.z*f.z-1)<=0.05 and math.abs(u.x*u.x+u.y*u.y+u.z*u.z-1)<=0.05 and math.abs(f.x*u.x+f.y*u.y+f.z*u.z)<=0.05
end
local function safe(s,p)
 if not s.entity or s.entity~=player or s.id==nil or field(s.entity,'id')~=s.id or not vector(s.position) or not vector(s.velocity) then return 'player_unavailable' end
 if type(s.id)~='userdata' and not(finite(s.id) and s.id>0 and s.id==math.floor(s.id)) then return 'identity_unavailable' end
 for _,f in ipairs(s.flags) do if not f.ok or type(f.value)~='boolean' or f.value then return 'unsafe_player_state' end end
 if not s.link_ok or (s.link~=nil and s.link~=0) then return 'linked_player' end
 if not normal(s,p) then return 'camera_unavailable' end
 if p and p.allow_perspective and (distance(s.head_position,s.position)>3 or not unit(s.head_direction) or not up_for(unit(s.head_direction))) then return 'head_camera_unavailable' end
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
 local origin=s.eye or s.camera;local direction=unit(s.aim_direction or s.forward)
 if not direction then return unknown end
 if not s.aim_direction then s.forward=direction end
 local function ray(mask)
  if not finite(mask) or mask<=0 or mask>2147483647 or mask~=math.floor(mask) then return nil end
  local hits={};local d=scale(direction,4.5)
  local ok,count=pcall(Physics.RayWorldIntersection,copy(origin),d,16,mask,s.id,nil,hits)
  if not ok or not finite(count) or count<0 or count>=16 or count~=math.floor(count) then return nil end
  local nearest=-1
  for i=1,16 do local h=hits[i]
   if i>count then if h~=nil then return nil end
   else
    if type(h)~='table' or not vector(h.pos) or not finite(h.dist) or h.dist<0 or h.dist>4.5 then return nil end
    local expected=plus(origin,scale(direction,h.dist))
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
  ..',"sampled_engine_seconds":'..number(clock())..',"player":'..vec(s and s.position)..',"camera":'..vec(s and s.camera)..',"forward":'..vec(s and s.forward)..',"up":'..vec(s and s.up)..',"fov":'..number(s and s.fov)
  ..(p.allow_perspective and (',"perspective":'..number(s and s.perspective)..',"eye":'..vec(s and s.eye)..',"aim_direction":'..vec(s and s.aim_direction)..',"camera_forward":'..vec(s and s.camera_forward)..',"camera_up":'..vec(s and s.camera_up)) or '')
  ..(s and s.aim and (',"aim":{"known":'..tostring(s.aim.known)..',"distance":'..number(s.aim.distance)..',"terrain_hit":'..tostring(s.aim.terrain_hit)..',"range":4.5}') or '')
  ..',"camera_basis_valid":'..tostring(s~=nil and normal(s,p))..',"camera_override_changed":'..tostring(p.camera_attempted==true)..',"camera_restored":'..tostring(p.camera_restored==true)..',"camera_reset_attempts":'..number(p.reset_attempts or 0)..',"timers_cancelled":'..tostring(p.timers_cancelled==true)..',"position_restored":false,"control_state_changed":false}'
 if p.allow_perspective then t=t:sub(1,-2)..',"body_visible_baseline_owned":true,"body_hidden":'..tostring(p.body_hidden==true)..',"body_restore_dispatched":'..tostring(p.body_restore_dispatched==true)..',"body_draw_calls":'..number(p.body_draw_calls or 0)..'}' end
 local ok,v=pcall(System.LogAlways,'[MineComeGameplayMovement] '..t);return ok and v~=false
end
local function cancel(p)
 local good=true
 local kill=field(Script,'KillTimer')
 for slot,id in pairs(p.timers) do p.timers[slot]=nil;local ok,v=false,false;if type(kill)=='function' then ok,v=pcall(kill,id) end;if not ok or v==false then good=false end end
 p.timers_cancelled=good;return good
end
local function body_valid(p)
 if player~=p.entity or field(player,'id')~=p.id or field(p.entity,'DrawSlot')~=p.draw_body then return false end
 local ok,valid=pcall(p.slot_valid,p.entity,0);local good,character=pcall(p.slot_character,p.entity,0);local visible,hidden=pcall(p.is_hidden,p.entity)
 return ok and valid==true and good and character==true and visible and hidden==false
end
local function draw_body(p,enabled)
 if not body_valid(p) then return false end
 p.body_draw_calls=(p.body_draw_calls or 0)+1;p.body_restore_needed=true;p.body_restore_dispatched=false
 local ok,v=pcall(p.draw_body,p.entity,0,enabled)
 if ok and v~=false then p.body_hidden=enabled==0;p.body_restore_needed=enabled==0;p.body_restore_dispatched=enabled==1;return true end
 return false
end
local function restore_body(p)return not p.body_restore_needed or draw_body(p,1)end
local arm,finish,cleanup
local function terminal(p,reason)
 if state.active~=p or p.terminal then return false end
 p.terminal=true;cancel(p);state.active=nil;state.last=p
 -- Stop in place on both explicit stop and failure; never restore an old origin.
 return emit(p,'terminal',reason,snapshot())
end
finish=function(p,reason)
 if state.active~=p or p.terminal then return false end
 if p.stopping then return true end
 if not p.camera_owned and not p.body_restore_needed then return terminal(p,reason) end
 p.stopping=true;p.stop_reason=reason;p.cleanup_started=clock();p.cleanup_attempts=0;cancel(p)
 return cleanup(p)
end
arm=function(p,slot,name,delay)
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
local function restored(s,p)
 return s.entity==p.entity and s.id==p.id and normal(s) and distance(s.head_position,s.position)<=3
  and distance(s.camera,s.head_position)<=.05 and distance(unit(s.forward),unit(s.head_direction))<=.02
end
cleanup=function(p)
 local s=snapshot()
 local camera_ok=not p.camera_owned or p.cleanup_attempts>0 and p.cleanup_reset_succeeded and restored(s,p)
 if camera_ok and p.camera_owned then p.camera_owned=false;p.camera_restored=true end
 local body_ok=not p.body_restore_needed or p.cleanup_attempts<3 and restore_body(p)
 if camera_ok and body_ok then return terminal(p,p.stop_reason) end
 if p.cleanup_attempts>=3 then return terminal(p,(camera_ok and 'body_restore_failed:' or 'camera_restore_failed:')..p.stop_reason) end
 p.cleanup_attempts=p.cleanup_attempts+1
 if not camera_ok then p.reset_attempts=(p.reset_attempts or 0)+1;local ok,v=pcall(p.reset_camera);p.cleanup_reset_succeeded=ok and v~=false end
 -- Reset bindings can apply on the next engine frame. Three bounded retries
 -- retain ownership until a current head/camera readback confirms release.
 if not arm(p,'cleanup','MineCome_GameplayMovementCleanup',50) then
  while p.cleanup_attempts<3 do p.cleanup_attempts=p.cleanup_attempts+1;if p.camera_owned then p.reset_attempts=(p.reset_attempts or 0)+1;pcall(p.reset_camera) end;restore_body(p) end
  s=snapshot();p.camera_restored=restored(s,p);p.camera_owned=not p.camera_restored
  return terminal(p,p.camera_restored and not p.body_restore_needed and p.stop_reason or 'camera_or_body_restore_unverified:'..p.stop_reason)
 end
 return true
end
function MineCome_GameplayMovementCleanup(data)local p=consume(data);if p and p.stopping then return cleanup(p) end return false end
local function clipped_distance(s,direction,up)
 if not Physics or type(Physics.RayWorldIntersection)~='function' or not finite(ent_all) or ent_all<=0 or ent_all>2147483647 or ent_all~=math.floor(ent_all) then return 0 end
 local right=unit({x=direction.y*up.z-direction.z*up.y,y=direction.z*up.x-direction.x*up.z,z=direction.x*up.y-direction.y*up.x})
 if not right then return 0 end
 local nearest=2.5
 for _,corner in ipairs({{0,0},{-.12,-.12},{-.12,.12},{.12,-.12},{.12,.12}}) do
  local origin=plus(s.head_position,plus(scale(right,corner[1]),scale(up,corner[2])));local hits={}
  local ok,count=pcall(Physics.RayWorldIntersection,copy(origin),scale(direction,2.5),16,ent_all,s.id,nil,hits)
  if not ok or not finite(count) or count<0 or count>=16 or count~=math.floor(count) then return 0 end
  for i=1,16 do local h=hits[i]
   if i>count then if h~=nil then return 0 end
   else
    if type(h)~='table' or not vector(h.pos) or not finite(h.dist) or h.dist<0 or h.dist>2.5 or distance(h.pos,plus(origin,scale(direction,h.dist)))>.01 then return 0 end
    nearest=math.min(nearest,math.max(0,h.dist-.15))
   end
  end
  if hits[17]~=nil then return 0 end
 end
 return nearest
end
-- A mode is acknowledged only from System's actual camera readback. The eye
-- and natural look belong to that exact submitted view, never a later head pose.
local function admit_view(p,s)
 if not p.allow_perspective then return s end
 if not p.camera_owned then
  s.perspective=0;s.eye=copy(s.camera);s.forward=unit(s.forward);s.aim_direction=copy(s.forward);s.camera_forward=copy(s.forward);s.camera_up=copy(s.up);return s
 end
 if p.camera_releasing then return nil end
 local r;local now=clock();local actual=unit(s.forward)
 if not now or not actual then return nil end
 -- System can expose a view two or more callbacks behind the most recent
 -- SetViewCamera. Match the actual view against bounded immutable requests;
 -- never combine its camera with the newest (different) head/eye/mode.
 local history=p.camera_requests or {}
 for i=#history,1,-1 do local candidate=history[i]
  if now>=candidate.at and now-candidate.at<=.25 and distance(s.camera,candidate.camera)<=.03 and distance(actual,candidate.direction)<=.01 then r=candidate;break end
 end
 if not r then return nil end
 s.camera_forward=unit(s.forward);s.camera_up=copy(s.up);s.eye=copy(r.eye);s.aim_direction=copy(s.camera_forward);s.perspective=r.mode
 s.forward=copy(r.forward);s.up=copy(r.up);p.unacked_since=nil
 return s
end
local function sample_view(p,s,request)
 local admitted=admit_view(p,s);if not admitted then return false end
 if request.with_aim then admitted.aim=aim_sample(admitted) end
 return emit(p,'view','sampled',admitted,request.seq)
end
local function update_camera(p,s,t)
 if not p.allow_perspective then return true end
 if p.requested_mode==0 or p.camera_releasing then
  if not restore_body(p) then return false,'body_restore_failed' end
  if not p.camera_owned then return true end
  if p.camera_releasing and restored(s,p) then p.camera_owned=false;p.camera_releasing=nil;p.camera_requests=nil;p.camera_restored=true;return true end
  if not p.camera_releasing then p.camera_releasing=t;p.release_attempts=0;p.release_at=nil end
  if t-p.camera_releasing>.25 then return false,'camera_release_failed' end
  if p.release_at and t-p.release_at<.05 then return true end
  if p.release_attempts>=3 then return true end
  p.release_attempts=p.release_attempts+1;p.reset_attempts=(p.reset_attempts or 0)+1
  p.release_at=t
  local ok,v=pcall(p.reset_camera);if not ok or v==false then return false,'camera_release_failed' end
  return true
 end
 local forward=unit(s.head_direction);local up=forward and up_for(forward)
 if not forward or not up then return false,'head_camera_unavailable' end
 if not p.body_hidden and not draw_body(p,0) then return false,'body_hide_failed' end
 local offset=scale(forward,p.requested_mode==1 and -1 or 1);local reach=clipped_distance(s,offset,up)
 local target=plus(s.head_position,scale(offset,reach));local direction=scale(forward,p.requested_mode==2 and -1 or 1)
 local history=p.camera_requests or {};p.camera_requests=history
 while #history>0 and (t-history[1].at>.25 or #history>=16) do table.remove(history,1) end
 history[#history+1]={camera=target,direction=direction,eye=copy(s.head_position),forward=forward,up=up,mode=p.requested_mode,at=t}
 p.camera_attempted=true;p.camera_owned=true;p.camera_restored=false;p.unacked_since=p.unacked_since or t
 if t-p.unacked_since>.25 then return false,'camera_readback_expired' end
 local ok,v=pcall(p.set_camera,copy(target),{direction.x,direction.y,direction.z})
 if not ok or v==false then return false,'camera_write_failed' end
 return true
end
function MineCome.GameplayMovementBegin(run,duration_ms,minx,maxx,miny,maxy,minz,maxz,flight,allow_perspective)
 if not token(run) or not finite(duration_ms) or duration_ms<1000 or duration_ms>86400000 or duration_ms~=math.floor(duration_ms) then return false,'invalid_identity_or_duration' end
 if flight~=nil and type(flight)~='boolean' then return false,'invalid_flight_profile' end
 if allow_perspective~=nil and type(allow_perspective)~='boolean' then return false,'invalid_perspective_profile' end
 if state.active then return false,'busy' end
 -- A failed bounded cleanup retains its ownership debt in the terminal state.
 -- A new run must not adopt that overridden camera/hidden body as its baseline.
 if state.last and (state.last.camera_owned or state.last.body_restore_needed) then return false,'prior_cleanup_incomplete' end
 if MineCome._movement_probe and (MineCome._movement_probe.active or MineCome._movement_probe.follower) then return false,'diagnostic_busy' end
 if MineCome._perspective_probe and MineCome._perspective_probe.active then return false,'diagnostic_busy' end
 local bounds={minx,maxx,miny,maxy,minz,maxz};for i=1,6 do if not finite(bounds[i]) or math.abs(bounds[i])>=LIMIT then return false,'invalid_bounds' end end
 for i=1,5,2 do if bounds[i]>=bounds[i+1] or bounds[i+1]-bounds[i]>4096 then return false,'invalid_bounds' end end
 local s,t=snapshot(),clock();local reason=safe(s)
 if reason then return false,reason end
 if not t or type(field(s.entity,'SetWorldPos'))~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' then return false,'api_unavailable' end
 local p={run=run,entity=s.entity,id=s.id,link_nil=s.link==nil,created=t,deadline=t+duration_ms/1000,last_clock=t,last_owned=copy(s.position),bounds=bounds,timers={},data={},sequence=0,applied=0,writes=0,view_sequence=0}
 p.allow_perspective=allow_perspective==true;p.requested_mode=0
 if p.allow_perspective then
  p.set_camera=field(CryAction,'SetViewCamera');p.reset_camera=field(CryAction,'ResetToNormalCamera')
  if type(p.set_camera)~='function' or type(p.reset_camera)~='function' or distance(s.head_position,s.position)>3 or not unit(s.head_direction) or not up_for(unit(s.head_direction)) then return false,'perspective_api_unavailable' end
  p.draw_body,p.slot_valid,p.slot_character,p.is_hidden=field(s.entity,'DrawSlot'),field(s.entity,'IsSlotValid'),field(s.entity,'IsSlotCharacter'),field(s.entity,'IsHidden')
  if type(p.draw_body)~='function' or type(p.slot_valid)~='function' or type(p.slot_character)~='function' or type(p.is_hidden)~='function' or not body_valid(p) then return false,'body_slot_unavailable' end
 end
 -- Vanilla 1.21.1 PlayerEntity.getOffGroundSpeed doubles default .05 flight
 -- acceleration when sprinting; LivingEntity.travel damps XZ by .91. Its
 -- asymptote is below24m/s. Walking retains its existing12m/s admission.
 p.max_speed=flight==true and 24 or 12
 if not inside(p,s.position,2) then return false,'host_outside_capture' end
 state.active=p
 if not arm(p,'hard','MineCome_GameplayMovementExpiry',duration_ms) or not arm(p,'tick','MineCome_GameplayMovementTick',1) then finish(p,'initial_timer_failed');return false,'initial_timer_failed' end
 if p.allow_perspective and not draw_body(p,1) then finish(p,'body_baseline_failed');return false,'body_baseline_failed' end
 if not emit(p,'begin','ready',s) then finish(p,'log_failed');return false,'log_failed' end
 return true,'ready'
end
function MineCome.GameplayMovementPose(run,seq,source_ms,x,y,z,requested_mode)
 local p=state.active;if not token(run) or not p or p.run~=run then return false,'inactive' end
 local target={x=x,y=y,z=z};local t=clock();local reason
 if p.stopping then return false,'stopping' end
 if (p.allow_perspective and (not finite(requested_mode) or requested_mode<0 or requested_mode>2 or requested_mode~=math.floor(requested_mode))) or (not p.allow_perspective and requested_mode~=nil) then reason='perspective_request_invalid'
 elseif not finite(seq) or seq<1 or seq>10000000 or seq~=math.floor(seq) or seq<=p.sequence then reason='sequence_replayed_or_invalid'
 elseif not finite(source_ms) or source_ms<0 or source_ms>86400000 or (p.latest and source_ms<=p.latest.source_ms) then reason='source_time_invalid'
 elseif not inside(p,target,0) then reason='target_outside_capture'
 elseif not t or t<p.last_clock or t>=p.deadline or (p.latest and t-p.latest.received>LEASE) then reason='source_lease_expired'
 elseif p.latest and distance(target,p.latest.target)>0.5+p.max_speed*(source_ms-p.latest.source_ms)/1000 then reason='source_velocity_invalid' end
 if reason then finish(p,reason);return false,reason end
 p.segment={from=copy(p.last_owned),started=t};p.latest={seq=seq,source_ms=source_ms,target=copy(target),received=t,first=p.sequence==0};p.sequence=seq
 if p.allow_perspective then p.requested_mode=requested_mode end
 return true,'queued'
end
function MineCome.GameplayMovementSample(run,seq,with_aim)
 local p=state.active;if not token(run) or not p or p.run~=run then return false,'inactive' end
 if p.stopping then return false,'stopping' end
 if not finite(seq) or seq<1 or seq>1000000 or seq~=math.floor(seq) or seq<=p.view_sequence then return false,'view_sequence_invalid' end
 local s,t=snapshot(),clock();local reason=safe(s,p)
 if not t or t<p.last_clock or t>=p.deadline then reason='clock_or_deadline' end
 if reason then finish(p,reason);return false,reason end
 p.view_sequence=seq
 local request={seq=seq,with_aim=with_aim==true}
 if sample_view(p,s,request) then return true,'sampled' end
 p.pending_view=request;return true,'camera_pending'
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
 if p.pending_view and sample_view(p,s,p.pending_view) then p.pending_view=nil
 elseif p.allow_perspective then admit_view(p,s) end
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
 local ok,why=update_camera(p,snapshot(),t);if not ok then return finish(p,why) end
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
