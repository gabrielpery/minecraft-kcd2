-- SPDX-License-Identifier: GPL-3.0-or-later
-- Native NPC melee adapter, invoked only by the exact-process guarded console
-- worker. Evidence: kcd2-mod-docs 9cb0675 script_bind_2025_01_14 Soul.GetState,
-- Soul.DealDamage(stamina,health,attackerId,suppressHitreaction), Actor.GetMaxHealth,
-- Entity.GetWorldBBox/GetRawId, System.GetEntitiesInSphere. Ray signature and
-- two excluded entities: installed Scripts/Entities/Physics/PressurizedObject.lua
-- 308-315. No guessed offsets. Incoming native damage is NOT intercepted here.
MineCome=MineCome or {}
MineCome._gameplay_combat=MineCome._gameplay_combat or {}
local state=MineCome._gameplay_combat
local LEASE,FRESH=2,.3
-- Official CombatDebug.TestLock (1324-1327) lists these player-only settings.
-- Zero-distance/zero-timeout prevented native target lock during actual hostile
-- attacks in the paired tools check. This is not a direct engine unlock API.
local LOCK_CVARS={'wh_cs_playermaxopponentdistancetolock','wh_cs_playermaxopponentdistancetounlock','wh_cs_playerunlocktimeout'}
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function integer(v,a,b)return finite(v) and v==math.floor(v) and v>=a and v<=b end
local function token(v)return type(v)=='string' and #v==32 and v:match('^[0-9a-f]+$')~=nil end
local function vector(v)return type(v)=='table' and finite(v.x) and finite(v.y) and finite(v.z) and math.abs(v.x)<10000000 and math.abs(v.y)<10000000 and math.abs(v.z)<10000000 end
local function copy(v)return{x=v.x,y=v.y,z=v.z}end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
local function number(v)return finite(v) and string.format('%.12g',v) or 'null'end
local function boolean(v)return type(v)=='boolean' and tostring(v) or 'null'end
local function clock()local ok,v=pcall(System.GetCurrTime);return ok and finite(v) and v>=0 and v or nil end
local function read(o,k,...)
 if type(o)~='table' or type(o[k])~='function' then return nil end
 local ok,v,w=pcall(o[k],o,...);if ok then return v,w end
end
local function wuid(e)
 local id=type(e)=='table' and type(e.this)=='table' and e.this.id
 if (type(id)=='string' and id~='') or (type(id)=='number' and finite(id) and id>0) or type(id)=='userdata' then
  if __null==nil or id~=__null then return id end
 end
end
local function lock_api(p)
 return System==p.lock_system and System.GetCVar==p.lock_get and System.SetCVar==p.lock_set
end
local function lock_value(p,name)
 if not lock_api(p)then return nil end
 local ok,value=pcall(p.lock_get,name);if ok and finite(value)then return value end
end
local function prepare_lock_policy(p)
 if type(System.GetCVar)~='function' or type(System.SetCVar)~='function'then return false end
 p.lock_system=System;p.lock_get=System.GetCVar;p.lock_set=System.SetCVar;p.lock_entries={};p.lock_policy_restored=true
 -- All baselines must be known before the first write.
 for _,name in ipairs(LOCK_CVARS)do
  local value=lock_value(p,name);if value==nil then return false end
  p.lock_entries[#p.lock_entries+1]={name=name,before=value,applied=0}
 end
 return true
end
local function lock_policy_owned(p)
 if not p.lock_policy_active or not lock_api(p)then return false end
 for _,entry in ipairs(p.lock_entries)do if lock_value(p,entry.name)~=entry.applied then return false end end
 return true
end
local function restore_lock_policy(p)
 if not p.lock_entries then p.lock_policy_active=false;p.lock_policy_restored=true;return true end -- Older module had no CVar writes.
 local restored=true
 for index=#p.lock_entries,1,-1 do local entry=p.lock_entries[index]
  if entry.attempted then
   local value=lock_value(p,entry.name)
   if value==entry.before then -- Already exactly restored, no setter needed.
   elseif value==entry.applied then
    local ok,result=pcall(p.lock_set,entry.name,entry.before)
    if not ok or result==false or lock_value(p,entry.name)~=entry.before then restored=false end
   else restored=false end -- Foreign/unknown value is never overwritten.
  end
 end
 p.lock_policy_active=false;p.lock_policy_restored=restored;return restored
end
local function apply_lock_policy(p)
 p.lock_policy_restored=false
 for _,entry in ipairs(p.lock_entries)do
  if lock_value(p,entry.name)~=entry.before then return false end
  entry.attempted=true -- A throwing setter may already have changed its value.
  local ok,result=pcall(p.lock_set,entry.name,entry.applied)
  if not ok or result==false or lock_value(p,entry.name)~=entry.applied then return false end
 end
 p.lock_policy_active=true;return true
end
local function emit(p,event,result,extra)
 local s='[MineComeGameplayCombat] {"schema":1,"run":"'..p.run..'","event":"'..event..'","result":"'..result..'","active":'..tostring(state.active==p and not p.stopped)..',"timers_cancelled":'..tostring(p.timer==nil)..',"lock_policy_active":'..boolean(p.lock_policy_active==true)..',"lock_policy_restored":'..boolean(p.lock_policy_restored)..',"hit_ack":'..p.hit_ack..(extra or '')..'}'
 if #s>4000 then return false end
 local ok,v=pcall(System.LogAlways,s);return ok and v~=false
end
local function stop(p,why)
 if p.stopped then return p.cleanup_complete==true end;p.stopped=true;p.reason=why
 p.incoming_restored=true
 if type(MineCome.GameplayCombatIncomingEnd)=='function'then local ok,result=pcall(MineCome.GameplayCombatIncomingEnd,p.run);p.incoming_restored=ok and result~=false end
 if p.timer then local ok,v=pcall(Script.KillTimer,p.timer);if ok and v~=false then p.timer=nil else p.reason='timer_cleanup_failed'end end
 if not restore_lock_policy(p)then p.reason='lock_policy_cleanup_unconfirmed'end
 p.cleanup_complete=p.timer==nil and p.lock_policy_restored==true and p.incoming_restored
 p.timer_data=nil;p.projectiles={};p.projectile_last=nil;p.blasts={};p.blast_last=nil;state.active=nil;state.last=p
 emit(p,'terminal',p.reason);return p.cleanup_complete
end
local function valid(p)
 local t=clock();if not t or t<p.last_clock or t>=p.deadline or t-p.received>LEASE then return nil,'lease_expired'end
 if player~=p.player or player.id~=p.player_id or player.soul~=p.player_soul or wuid(player)~=p.player_wuid then return nil,'player_changed'end
 if read(player.actor,'IsDead')~=false then return nil,'player_unavailable'end
 if not lock_policy_owned(p)then return nil,'lock_policy_changed'end
 if type(MineCome.GameplayCombatIncomingValidate)=='function' and not MineCome.GameplayCombatIncomingValidate(p.run)then return nil,'incoming_changed'end
 p.last_clock=t;return t
end
local function schedule(p)
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,100,'MineCome_GameplayCombatTick',data,true)
 if not ok or id==nil or id==false then return false end;p.timer=id;p.timer_data=data;return true
end
function MineCome_GameplayCombatTick(data)
 local p=type(data)=='table' and data.owner
 if not p or p~=state.active or p.timer_data~=data then return end;p.timer=nil;p.timer_data=nil
 local t,why=valid(p);if not t then stop(p,why)elseif not schedule(p)then stop(p,'timer_unavailable')end
end
local function actor(e)
 if type(e)~='table' or e==player or not e.id or type(e.soul)~='table' or type(e.actor)~='table' or type(e.soul.DealDamage)~='function' then return nil end
 local hp=read(e.soul,'GetState','health');local maximum=read(e.actor,'GetMaxHealth');local dead=read(e.actor,'IsDead')
 local lo,hi=read(e,'GetWorldBBox');local raw=read(e,'GetRawId');local soul_id=read(e.soul,'GetId')
 if not finite(hp) or not finite(maximum) or maximum<=0 or maximum>1000000 or hp<0 or hp>maximum or type(dead)~='boolean' or not integer(raw,1,9007199254740991) or soul_id==nil or not vector(lo) or not vector(hi) then return nil end
 local width=math.max(hi.x-lo.x,hi.y-lo.y);local height=hi.z-lo.z
 if width<.05 or width>4 or hi.x<=lo.x or hi.y<=lo.y or height<.05 or height>5 then return nil end
 return {entity=e,id=e.id,soul=e.soul,soul_id=soul_id,raw=raw,lo=copy(lo),hi=copy(hi),x=(lo.x+hi.x)/2,y=(lo.y+hi.y)/2,z=lo.z,width=width,height=height,health=hp,max_health=maximum,alive=not dead and hp>0}
end
local function same(a,b)return a and b and a.entity==b.entity and a.id==b.id and a.soul==b.soul and a.soul_id==b.soul_id and a.raw==b.raw end
local function nearby(p)
 local pos=read(p.player,'GetWorldPos');if not vector(pos)then return nil end
 local ok,entities=pcall(System.GetEntitiesInSphere,copy(pos),p.radius)
 if not ok or type(entities)~='table' then return nil end
 local list={};for _,e in pairs(entities)do local a=actor(e)
  if a and distance(pos,{x=a.x,y=a.y,z=a.z})<=p.radius then a.distance=distance(pos,{x=a.x,y=a.y,z=a.z});list[#list+1]=a end
 end
 table.sort(list,function(a,b)if a.distance==b.distance then return a.raw<b.raw end;return a.distance<b.distance end)
 return list
end
function MineCome.GameplayCombatBegin(run,duration_ms,radius,max_actors)
 if not token(run) or not integer(duration_ms,1000,86400000) or not finite(radius) or radius<4 or radius>32 or not integer(max_actors,1,8) then return false,'invalid_begin'end
 if state.active then return false,'session_owned'end
 if state.last and state.last.lock_policy_restored==false then return false,'lock_policy_cleanup_unconfirmed'end
 if state.last and state.last.incoming_restored==false then return false,'incoming_cleanup_unconfirmed'end
 if not System or type(System.GetEntitiesInSphere)~='function' or type(System.GetCurrTime)~='function' or type(System.LogAlways)~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' or not Physics or type(Physics.RayWorldIntersection)~='function' or not integer(ent_all,1,2147483647) then return false,'api_unavailable'end
 if type(player)~='table' or not player.id or not wuid(player) or type(player.soul)~='table' or read(player.actor,'IsDead')~=false then return false,'player_unavailable'end
 local t=clock();if not t then return false,'clock_unavailable'end
 local p={run=run,deadline=t+duration_ms/1000,received=t,last_clock=t,player=player,player_id=player.id,player_wuid=wuid(player),player_soul=player.soul,radius=radius,max_actors=max_actors,next_token=1,actors={},samples={},sequence=0,hit_ack=0,projectiles={},projectile_count=0,projectile_ack=0,blasts={},blast_count=0,blast_ack=0}
 if not prepare_lock_policy(p)then return false,'lock_policy_baseline_unavailable'end
 state.active=p;if not schedule(p)then state.active=nil;return false,'timer_unavailable'end
 if not apply_lock_policy(p)then stop(p,'lock_policy_setup_failed');return false,'lock_policy_setup_failed'end
 emit(p,'begin','ready');return true
end
function MineCome.GameplayCombatSample(run,sequence)
 local p=state.active;if not p or p.run~=run then return false,'session_missing'end
 local t,why=valid(p);if not t then stop(p,why);return false,why end
 if not integer(sequence,1,10000000) or sequence<=p.sequence then return false,'invalid_sequence'end
 local list=nearby(p);if not list then stop(p,'enumeration_failed');return false,'enumeration_failed'end
 p.sequence=sequence;p.received=t;local sample={time=t,actors={}};local rows={}
 for index=1,math.min(#list,p.max_actors)do local a=list[index];local found
  for id,old in pairs(p.actors)do if same(old,a) then found=id;break end end
  if not found then
   if p.next_token>256 then stop(p,'generation_capacity');return false,'generation_capacity'end
   found=p.next_token;p.next_token=p.next_token+1;a.first_seen=t;p.actors[found]=a
  end
  a.token=found;sample.actors[found]=a
  rows[#rows+1]='{"token":'..found..',"x":'..number(a.x)..',"y":'..number(a.y)..',"z":'..number(a.z)..',"width":'..number(a.width)..',"height":'..number(a.height)..',"health":'..number(a.health)..',"max_health":'..number(a.max_health)..',"alive":'..tostring(a.alive)..'}'
 end
 p.samples[sequence]=sample;for id,s in pairs(p.samples)do if t-s.time>FRESH or id<sequence-4 then p.samples[id]=nil end end
 if type(MineCome.GameplayCombatIncomingSample)=='function' and not MineCome.GameplayCombatIncomingSample(run,sequence,list)then stop(p,'incoming_sample_failed');return false,'incoming_sample_failed'end
 if not emit(p,'sample','sampled',',"seq":'..sequence..',"actors":['..table.concat(rows,',')..']')then stop(p,'log_failed');return false,'log_failed'end
 return true
end
local function reject(p,seq,why,before,after)
 local extra=',"seq":'..seq..',"before":'..number(before)..',"after":'..number(after)
 p.last_hit={seq=seq,result=why,extra=extra};emit(p,'hit',why,extra);return true,why
end
local function in_proxy(v,a)
 return math.abs(v.x-a.x)<=a.width/2+.05 and math.abs(v.y-a.y)<=a.width/2+.05 and v.z>=a.lo.z-.05 and v.z<=a.hi.z+.05
end
local function contact(origin,direction,a)
 -- Minecraft's Entity dimensions use one square horizontal width; native
 -- characters may have unequal X/Y extents. Re-intersect the actual box rather
 -- than expecting the conservative proxy's front surface to coincide with it.
 local entry,exit=0,4.5
 for _,axis in ipairs({'x','y','z'})do local d=direction[axis];local o=origin[axis]
  if math.abs(d)<.00000001 then if o<a.lo[axis] or o>a.hi[axis] then return nil end
  else local first,last=(a.lo[axis]-o)/d,(a.hi[axis]-o)/d;if first>last then first,last=last,first end
   entry=math.max(entry,first);exit=math.min(exit,last);if entry>exit then return nil end
  end
 end
 if entry<.05 or entry>4.5 then return nil end
 return{x=origin.x+direction.x*entry,y=origin.y+direction.y*entry,z=origin.z+direction.z*entry},entry
end
function MineCome.GameplayCombatHit(run,sequence,actor_token,source_seq,fraction,ox,oy,oz,tx,ty,tz)
 local p=state.active;if not p or p.run~=run then return false,'session_missing'end
 local t,why=valid(p);if not t then stop(p,why);return false,why end
 if not integer(sequence,1,10000000)then return false,'invalid_sequence'end
 if sequence==p.hit_ack and p.last_hit then emit(p,'hit',p.last_hit.result,p.last_hit.extra);return true end
 if sequence<=p.hit_ack then return false,'replayed_sequence'end
 -- Consume even rejected requests before invoking an engine setter. A timeout
 -- or exception never permits the same attack to be applied a second time.
 p.hit_ack=sequence;p.received=t
 local origin,target={x=ox,y=oy,z=oz},{x=tx,y=ty,z=tz}
 if not integer(actor_token,1,256) or not integer(source_seq,1,10000000) or not finite(fraction) or fraction<=0 or fraction>50 or not vector(origin) or not vector(target)then return reject(p,sequence,'invalid_hit')end
 local sample=p.samples[source_seq];local old=sample and sample.actors[actor_token]
 if not sample or t-sample.time>FRESH or not old or not old.alive then return reject(p,sequence,'stale_target')end
 local list=nearby(p);local current
 for _,a in ipairs(list or {})do if same(old,a)then current=a;break end end
 if not current or not same(p.actors[actor_token],current) or not current.alive then return reject(p,sequence,'target_changed')end
 local view_ok,view=pcall(function()return MineCome.GameplayMovementCombatView(run)end)
 if not view_ok or type(view)~='table' or view.entity~=p.player or view.id~=p.player_id or not vector(view.origin) or not vector(view.direction) or distance(origin,view.origin)>.35 then return reject(p,sequence,'view_changed')end
 local length=distance(origin,target)
 if length<.05 or length>4.5 or not in_proxy(target,current)then return reject(p,sequence,'out_of_reach')end
 local direction={x=(tx-ox)/length,y=(ty-oy)/length,z=(tz-oz)/length}
 local norm=math.sqrt(view.direction.x^2+view.direction.y^2+view.direction.z^2)
 if math.abs(norm-1)>.01 or (direction.x*view.direction.x+direction.y*view.direction.y+direction.z*view.direction.z)<.985 then return reject(p,sequence,'aim_changed')end
 local actual,actual_length=contact(origin,direction,current)
 if not actual then return reject(p,sequence,'out_of_reach')end
 target=actual;tx,ty,tz=target.x,target.y,target.z;length=actual_length
 local hits={};local ok,count=pcall(Physics.RayWorldIntersection,copy(origin),{x=tx-ox,y=ty-oy,z=tz-oz},16,ent_all,p.player_id,current.id,hits)
 if not ok or not integer(count,0,15)then return reject(p,sequence,'occlusion_unknown')end
 for i=1,16 do local h=hits[i]
  if i>count then if h~=nil then return reject(p,sequence,'occlusion_unknown')end
  elseif type(h)~='table' or not finite(h.dist) or h.dist<0 or h.dist>length+.01 or not vector(h.pos) or distance(h.pos,{x=ox+direction.x*h.dist,y=oy+direction.y*h.dist,z=oz+direction.z*h.dist})>.03 then return reject(p,sequence,'occlusion_unknown')
  elseif h.dist<length-.05 then return reject(p,sequence,'occluded')end
 end
 if hits[17]~=nil then return reject(p,sequence,'occlusion_unknown')end
 if not lock_policy_owned(p)then stop(p,'lock_policy_changed');return false,'lock_policy_changed'end
 local ended=clock();local again=actor(current.entity)
 if not ended or ended<t or ended-t>.1 or ended-sample.time>FRESH or not same(current,again) or not again.alive or player~=p.player or player.id~=p.player_id or wuid(player)~=p.player_wuid then return reject(p,sequence,'target_changed')end
 local before=again.health;local damage=math.min(before,fraction*again.max_health)
 -- Observe the real native lock state; the owned player-only CVar policy above
 -- does not establish hostile free-camera behavior by itself.
 local locked_before=read(p.player.player,'IsLockedToOpponent',again.id)
 -- Official hostageSituation scripts attribute DealDamage to player.this.id
 -- (WUID). player.id is only the entity handle used by ray/view APIs above.
 local applied=pcall(again.soul.DealDamage,again.soul,0,damage,p.player_wuid,false)
 local after=read(again.soul,'GetState','health')
 local locked_after=read(p.player.player,'IsLockedToOpponent',again.id)
 if not applied or not finite(after) or after<0 or after>before+.01 then return reject(p,sequence,'damage_unconfirmed',before,after)end
 local result=after<before and 'damaged' or 'no_damage'
 p.last_hit={seq=sequence,result=result,extra=',"seq":'..sequence..',"before":'..number(before)..',"after":'..number(after)..',"locked_before":'..boolean(locked_before)..',"locked_after":'..boolean(locked_after)}
 emit(p,'hit',result,p.last_hit.extra);return true
end
-- Arrow trajectory uses its own contiguous, bounded segments. Only the first
-- segment uses the shooter's eye; subsequent contacts are not melee eye rays.
-- The real Minecraft arrow computes damage after the native trace acknowledgement.
local function point_json(v)return '{"x":'..number(v.x)..',"y":'..number(v.y)..',"z":'..number(v.z)..'}'end
local function actor_json(a)
 if not a then return 'null'end
 return '{"token":'..a.token..',"x":'..number(a.x)..',"y":'..number(a.y)..',"z":'..number(a.z)..',"width":'..number(a.width)..',"height":'..number(a.height)..',"health":'..number(a.health)..',"max_health":'..number(a.max_health)..',"alive":'..tostring(a.alive)..'}'
end
local function projectile_reply(p,request,result,reason,point,normal,a,before,after)
 point=point or {x=0,y=0,z=0};normal=normal or {x=0,y=0,z=0}
 local extra=',"seq":'..request[1]..',"projectile":"'..request[3]..'","segment":'..request[4]..',"reason":"'..(reason or '')..'","contact":'..point_json(point)..',"normal":'..point_json(normal)..',"actor_token":'..(a and a.token or 0)..',"actor":'..actor_json(a)..',"before":'..number(before)..',"after":'..number(after)
 p.projectile_last={request=request,event=request[2],result=result,extra=extra}
 if not emit(p,request[2],result,extra)then stop(p,'log_failed');return false,'log_failed'end
 return true,result
end
local function projectile_request(run,request)
 local p=state.active;if not p or p.run~=run then return nil,'session_missing'end
 local t,why=valid(p);if not t then stop(p,why);return nil,why end
 if not integer(request[1],1,10000000) or not token(request[3]) or not integer(request[4],1,10000)then return nil,'invalid_request'end
 if request[1]==p.projectile_ack and p.projectile_last then
  local previous=p.projectile_last
  if #request~=#previous.request then return nil,'request_changed'end
  for i=1,#request do if request[i]~=previous.request[i]then return nil,'request_changed'end end
  emit(p,previous.event,previous.result,previous.extra);return nil,'duplicate'
 end
 if request[1]<=p.projectile_ack then return nil,'replayed_request'end
 -- Consume first, including failures. A native setter's ambiguous result cannot
 -- become another attack by resubmitting or changing an existing request.
 p.projectile_ack=request[1];p.received=t
 return p,t
end
local function projectile_close(p,id)
 local s=p.projectiles[id];if s then p.projectiles[id]={done=true}end
end
local function projectile_reject(p,request,reason)
 projectile_close(p,request[3]);return projectile_reply(p,request,'rejected',reason)
end
-- Yarn1.21.1+build.3 PersistentProjectileEntity.getEntityCollision delegates to
-- ProjectileUtil's six-argument overload, which expands the target box by0.3f.
-- Match that float promoted to double on the actual native rectangle; this
-- margin does not alter scenery rays or melee reach/contact. Inspected bytecode:
-- runtime/evidence/projectile-impact-source-20261109/ProjectileUtil.txt:228-264.
local PROJECTILE_ACTOR_MARGIN=.30000001192092896
local function segment_contact(origin,direction,length,a)
 local entry,exit=0,length;local normal={x=-direction.x,y=-direction.y,z=-direction.z}
 for _,axis in ipairs({'x','y','z'})do local d,o=direction[axis],origin[axis]
  local lo,hi=a.lo[axis]-PROJECTILE_ACTOR_MARGIN,a.hi[axis]+PROJECTILE_ACTOR_MARGIN
  if math.abs(d)<.00000001 then if o<lo or o>hi then return nil end
  else local first,last=(lo-o)/d,(hi-o)/d;local sign=-1
   if first>last then first,last=last,first;sign=1 end
   if first>entry then entry=first;normal={x=0,y=0,z=0};normal[axis]=sign end
   exit=math.min(exit,last);if entry>exit then return nil end
  end
 end
 if entry<0 or entry>length then return nil end
 return{x=origin.x+direction.x*entry,y=origin.y+direction.y*entry,z=origin.z+direction.z*entry},entry,normal
end
local function projectile_scenery(p,origin,direction,length,skip)
 if length<.000001 then return true,nil end
 local hits={};local ok,count=pcall(Physics.RayWorldIntersection,copy(origin),{x=direction.x*length,y=direction.y*length,z=direction.z*length},16,ent_all,p.player_id,skip,hits)
 if not ok or not integer(count,0,15)then return false end
 local nearest
 for i=1,16 do local h=hits[i]
  if i>count then if h~=nil then return false end
  elseif type(h)~='table' or not finite(h.dist) or h.dist<0 or h.dist>length+.01 or not vector(h.pos) or not vector(h.normal) or
   math.abs(h.normal.x^2+h.normal.y^2+h.normal.z^2-1)>.05 or
   distance(h.pos,{x=origin.x+direction.x*h.dist,y=origin.y+direction.y*h.dist,z=origin.z+direction.z*h.dist})>.03 then return false
  elseif not nearest or h.dist<nearest.dist then nearest={dist=h.dist,pos=copy(h.pos),normal=copy(h.normal)}end
 end
 if hits[17]~=nil then return false end
 return true,nearest
end
local function projectile_actor(p,origin,target,direction,length)
 local center={x=(origin.x+target.x)/2,y=(origin.y+target.y)/2,z=(origin.z+target.z)/2}
 local ok,entities=pcall(System.GetEntitiesInSphere,center,length/2+5)
 if not ok or type(entities)~='table'then return false end
 local nearest,point,normal,best;local count=0
 for _,entity in pairs(entities)do
  count=count+1;if count>128 then return false end
  local a=actor(entity)
  if a and a.alive then local hit,dist,n=segment_contact(origin,direction,length,a)
   if hit and (not best or dist<best or dist==best and a.raw<nearest.raw)then nearest,point,normal,best=a,hit,n,dist end
  end
 end
 return true,nearest,point,normal,best
end
function MineCome.GameplayProjectileTrace(run,sequence,id,segment,ox,oy,oz,tx,ty,tz)
 local request={sequence,'projectile_trace',id,segment,ox,oy,oz,tx,ty,tz}
 local p,t=projectile_request(run,request);if not p then return t=='duplicate',t end
 local origin,target={x=ox,y=oy,z=oz},{x=tx,y=ty,z=tz}
 if not vector(origin) or not vector(target)then return projectile_reject(p,request,'invalid_segment')end
 local length=distance(origin,target)
 if length<.000001 or length>4 then return projectile_reject(p,request,'invalid_segment')end
 local direction={x=(tx-ox)/length,y=(ty-oy)/length,z=(tz-oz)/length}
 local trajectory=p.projectiles[id]
 if trajectory then
  if trajectory.done or trajectory.collision then return projectile_reject(p,request,'projectile_finished')end
  if segment~=trajectory.segment+1 or distance(origin,trajectory.endpoint)>.03 or t-trajectory.started>10 or trajectory.distance+length>64 then return projectile_reject(p,request,'trajectory_changed')end
 else
  if segment~=1 or p.projectile_count>=4096 then return projectile_reject(p,request,'projectile_capacity')end
  local active=0
  for old_id,s in pairs(p.projectiles)do
   if not s.done and t-s.started>10 then projectile_close(p,old_id)elseif not s.done then active=active+1 end
  end
  if active>=16 then return projectile_reject(p,request,'projectile_capacity')end
  local ok,view=pcall(function()return MineCome.GameplayMovementCombatView(run)end)
  if not ok or type(view)~='table' or view.entity~=p.player or view.id~=p.player_id or not vector(view.origin) or not vector(view.direction) or
   distance(origin,view.origin)>.6 or math.abs(view.direction.x^2+view.direction.y^2+view.direction.z^2-1)>.02 or
   direction.x*view.direction.x+direction.y*view.direction.y+direction.z*view.direction.z<.97 then return projectile_reject(p,request,'launch_changed')end
  trajectory={started=t,segment=0,distance=0};p.projectiles[id]=trajectory;p.projectile_count=p.projectile_count+1
 end
 local ok,a,point,normal,actor_distance=projectile_actor(p,origin,target,direction,length)
 if not ok then return projectile_reject(p,request,'actors_unknown')end
 local scene_ok,scenery=projectile_scenery(p,origin,direction,length,a and a.id or nil)
 if not scene_ok then return projectile_reject(p,request,'scenery_unknown')end
 local ended,why=valid(p);if not ended then stop(p,why);return false,why end
 if ended-t>.1 then return projectile_reject(p,request,'trace_expired')end
 trajectory.segment=segment;trajectory.distance=trajectory.distance+length;trajectory.endpoint=copy(target)
 if scenery and (not actor_distance or scenery.dist<=actor_distance+.001)then
  projectile_close(p,id);return projectile_reply(p,request,'scenery','',scenery.pos,scenery.normal)
 end
 if a then
  local current=actor(a.entity)
  if not same(a,current) or not current.alive or distance(a.lo,current.lo)>.03 or distance(a.hi,current.hi)>.03 then return projectile_reject(p,request,'target_changed')end
  local found;for old_token,old in pairs(p.actors)do if same(old,current)then found=old_token;break end end
  if not found then
   if p.next_token>256 then return projectile_reject(p,request,'actor_capacity')end
   found=p.next_token;p.next_token=p.next_token+1;p.actors[found]=current
  end
  current.token=found
  trajectory.collision={time=ended,actor=current,point=point,normal=normal,origin=copy(origin),direction=direction,length=length}
  return projectile_reply(p,request,'actor','',point,normal,current)
 end
 return projectile_reply(p,request,'clear','',target,{x=0,y=0,z=0})
end
function MineCome.GameplayProjectileImpact(run,sequence,id,segment,actor_token,fraction)
 local request={sequence,'projectile_impact',id,segment,actor_token,fraction}
 local p,t=projectile_request(run,request);if not p then return t=='duplicate',t end
 local trajectory=p.projectiles[id];local collision=trajectory and trajectory.collision
 projectile_close(p,id) -- Consume before any native damage setter, including errors.
 if not integer(actor_token,1,256) or not finite(fraction) or fraction<=0 or fraction>50 then return projectile_reply(p,request,'rejected','invalid_damage')end
 if not trajectory or trajectory.segment~=segment or not collision or collision.actor.token~=actor_token or t-collision.time>FRESH then return projectile_reply(p,request,'rejected','stale_impact')end
 local current=actor(collision.actor.entity)
 if not same(collision.actor,current) or not same(p.actors[actor_token],current) or not current.alive then return projectile_reply(p,request,'rejected','target_changed')end
 local point,length,normal=segment_contact(collision.origin,collision.direction,collision.length,current)
 if not point or distance(point,collision.point)>.15 then return projectile_reply(p,request,'rejected','target_changed')end
 local scene_ok,scenery=projectile_scenery(p,collision.origin,collision.direction,length,current.id)
 if not scene_ok then return projectile_reply(p,request,'rejected','scenery_unknown')end
 if scenery and scenery.dist<length-.001 then return projectile_reply(p,request,'rejected','occluded')end
 local ended,why=valid(p);if not ended then stop(p,why);return false,why end
 local again=actor(current.entity)
 if ended-t>.1 or ended-collision.time>FRESH or not same(current,again) or not again.alive or distance(current.lo,again.lo)>.03 or distance(current.hi,again.hi)>.03 then return projectile_reply(p,request,'rejected','target_changed')end
 again.token=actor_token
 local before=again.health;local damage=math.min(before,fraction*again.max_health)
 local applied=pcall(again.soul.DealDamage,again.soul,0,damage,p.player_wuid,false)
 local after=read(again.soul,'GetState','health')
 if not applied or not finite(after) or after<0 or after>before+.01 then return projectile_reply(p,request,'rejected','damage_unconfirmed',point,normal,again,before,after)end
 again.health=after;again.alive=after>0 and read(again.entity.actor,'IsDead')==false
 return projectile_reply(p,request,after<before and 'damaged' or 'no_damage','',point,normal,again,before,after)
end
-- Owned vanilla TNT uses its explosion centre, never the current melee eye.
-- Prepare freezes a native actor/exposure grant for at most one second. Commit
-- checks the same actor generations before damage. Scenery exposure belongs to
-- the detonation snapshot too; later collider movement cannot undo that event.
-- Hit reactions may animate bounds during transport; damage belongs to the
-- frozen detonation volume, not the actor's later pose or position.
-- This separate grant does not extend the existing .3s melee/arrow snapshots.
local function blast_reply(p,request,result,reason,actors,outcomes)
 local prepare=request[2]=='blast_prepare' and request[1] or request[5]
 local extra=',"seq":'..request[1]..',"explosion":"'..request[3]..'","owner":"'..request[4]..'","prepare_seq":'..prepare..',"center":'..point_json({x=request[6],y=request[7],z=request[8]})..',"power":'..request[9]..',"reason":"'..(reason or '')..'","actors":['..table.concat(actors or {},',')..'],"outcomes":['..table.concat(outcomes or {},',')..']'
 p.blast_last={request=request,event=request[2],result=result,extra=extra}
 if not emit(p,request[2],result,extra)then stop(p,'log_failed');return false,'log_failed'end
 return true,result
end
local function blast_request(run,request)
 local p=state.active;if not p or p.run~=run then return nil,'session_missing'end
 local t,why=valid(p);if not t then stop(p,why);return nil,why end
 if not integer(request[1],1,10000000) or not token(request[3]) or not token(request[4]) or not integer(request[5],0,10000000) or
  not vector({x=request[6],y=request[7],z=request[8]}) or request[9]~=4 or type(request[10])~='string' or #request[10]>512 then return nil,'invalid_blast'end
 if p.blast_owner and p.blast_owner~=request[4]then return nil,'owner_changed'end
 if request[1]==p.blast_ack and p.blast_last then
  local old=p.blast_last;for i=1,10 do if request[i]~=old.request[i]then return nil,'request_changed'end end
  emit(p,old.event,old.result,old.extra);return nil,'duplicate'
 end
 if request[1]~=p.blast_ack+1 then return nil,'replayed_request'end
 p.blast_ack=request[1];p.blast_owner=request[4];p.received=t;return p,t
end
local function float32(v)
 -- Proxy dimensions are Java floats. Round positive normal doubles to nearest
 -- even IEEE754 binary32 without depending on unavailable Lua5.3 pack APIs.
 local m,e=math.frexp(v);local scaled=m*16777216;local n=math.floor(scaled);local tail=scaled-n
 if tail>.5 or tail==.5 and n%2==1 then n=n+1 end
 return math.ldexp(n,e-24)
end
local function blast_exposure(p,a,center)
 local width,height=float32(a.width),float32(a.height)
 local dx,dy=1/(2*width+1),1/(2*height+1);local offset=(1-math.floor(1/dx)*dx)/2
 local samples={};local x=0
 while x<=1 do local y=0;while y<=1 do local z=0;while z<=1 do
  if #samples>=128 then return nil,'exposure_capacity'end
  -- Pinned Explosion.getExposure iterates MC X,Y,Z; native axes are X,-Z,Y.
  local point={x=a.x-width/2+x*width+offset,y=a.y+width/2-z*width-offset,z=a.z+y*height}
  local length=distance(point,center);local visible=true
  if length>.000001 then
   local direction={x=(center.x-point.x)/length,y=(center.y-point.y)/length,z=(center.z-point.z)/length}
   local ok,hit=projectile_scenery(p,point,direction,length,a.id);if not ok then return nil,'scenery_unknown'end
   visible=not hit or hit.dist>=length-.001
  end
  samples[#samples+1]=visible and '1' or '0';z=z+dx
 end;y=y+dy end;x=x+dx end
 return table.concat(samples)
end
local function blast_current(old)
 if not old or type(System.GetEntity)~='function'then return nil end
 local ok,entity=pcall(System.GetEntity,old.id)
 if not ok or entity~=old.entity then return nil end
 local current=actor(entity);return same(old,current) and current.alive and current or nil
end
function MineCome.GameplayBlastPrepare(run,sequence,id,owner,cx,cy,cz,power)
 local request={sequence,'blast_prepare',id,owner,0,cx,cy,cz,power,''}
 local p,t=blast_request(run,request);if not p then return t=='duplicate',t end
 if p.blasts[id]then return blast_reply(p,request,'rejected','explosion_reused')end
 if p.blast_count>=4096 then return blast_reply(p,request,'rejected','explosion_capacity')end
 local active=0;for _,grant in pairs(p.blasts)do if not grant.done then if t-grant.time>1 then grant.done=true;grant.actors={}else active=active+1 end end end
 if active>=16 then return blast_reply(p,request,'rejected','explosion_capacity')end
 local center={x=cx,y=cy,z=cz};local grant={time=t,done=true,owner=owner,sequence=sequence,center=center,actors={}}
 p.blasts[id]=grant;p.blast_count=p.blast_count+1
 local ok,entities=pcall(System.GetEntitiesInSphere,copy(center),8);if not ok or type(entities)~='table'then return blast_reply(p,request,'rejected','actors_unknown')end
 local list,seen={},{};local count=0
 for _,entity in pairs(entities)do count=count+1;if count>128 then return blast_reply(p,request,'rejected','actors_unknown')end
  local a=actor(entity);if a and a.alive and not seen[entity] and distance(center,{x=a.x,y=a.y,z=a.z})<=8 then seen[entity]=true;list[#list+1]=a end
 end
 if #list>8 then return blast_reply(p,request,'rejected','actor_capacity')end
 table.sort(list,function(a,b)return a.raw<b.raw end);local rows={}
 for _,a in ipairs(list)do
  local mask,why=blast_exposure(p,a,center);if not mask then return blast_reply(p,request,'rejected',why)end
  local current=blast_current(a);if not current then return blast_reply(p,request,'rejected','target_changed')end
  local found;for old_token,old in pairs(p.actors)do if same(old,current)then found=old_token;break end end
  if not found then if p.next_token>256 then return blast_reply(p,request,'rejected','actor_capacity')end;found=p.next_token;p.next_token=p.next_token+1;p.actors[found]=current end
  a.token=found;a.exposure=mask;grant.actors[found]=a
  rows[#rows+1]=actor_json(a):sub(1,-2)..',"exposure":"'..mask..'"}'
 end
 local ended,why=valid(p);if not ended then stop(p,why);return false,why end
 if ended-t>.25 then return blast_reply(p,request,'rejected','prepare_expired')end
 grant.done=false -- Age starts at the original prepare clock, including ray work.
 return blast_reply(p,request,'prepared','',rows)
end
function MineCome.GameplayBlastCommit(run,sequence,id,owner,prepare,cx,cy,cz,power,packed)
 local request={sequence,'blast_commit',id,owner,prepare,cx,cy,cz,power,packed}
 local p,t=blast_request(run,request);if not p then return t=='duplicate',t end
 local grant=p.blasts[id]
 if not grant or grant.done or grant.sequence~=prepare or grant.owner~=owner or t-grant.time>1 or distance(grant.center,{x=cx,y=cy,z=cz})>.000001 then return blast_reply(p,request,'rejected','stale_explosion')end
 grant.done=true -- Consume the entire UUID before any setter, even on failure.
 local targets,seen={},{}
 if packed~='' then
  for row in (packed..';'):gmatch('(.-);')do
   local a,b=row:match('^(%d+):([%d%.eE%+%-]+)$');a,b=tonumber(a),tonumber(b)
   if not integer(a,1,256) or not finite(b) or b<=0 or b>50 or seen[a] or #targets>=8 then grant.actors={};return blast_reply(p,request,'rejected','invalid_targets')end
   seen[a]=true;targets[#targets+1]={token=a,fraction=b}
  end
 end
 local outcomes={}
 for _,target in ipairs(targets)do
  local old=grant.actors[target.token];local current=blast_current(old);local reason
  if not current or not same(p.actors[target.token],current)then reason='target_changed'
  elseif not old.exposure:find('1',1,true)then reason='occluded'end
  local ended,why=valid(p);if not ended then stop(p,why);return false,why end
  if ended-grant.time>1 then reason='stale_explosion'end
  local again=blast_current(old)
  if not reason and not same(current,again)then reason='target_changed'end
  local result,before,after='rejected',nil,nil
  if not reason then
   before=again.health;local damage=math.min(before,target.fraction*old.max_health)
   local applied=pcall(again.soul.DealDamage,again.soul,0,damage,p.player_wuid,false)
   after=read(again.soul,'GetState','health')
   if not applied or not finite(after) or after<0 or after>before+.01 then reason='damage_unconfirmed'
   else result=after<before and 'damaged' or 'no_damage';reason=''end
  end
  outcomes[#outcomes+1]='{"actor_token":'..target.token..',"result":"'..result..'","reason":"'..reason..'","before":'..number(before)..',"after":'..number(after)..'}'
 end
 grant.actors={};return blast_reply(p,request,'applied','',nil,outcomes)
end
function MineCome.GameplayCombatEnd(run)
 local p=state.active
 if not p then if state.last and state.last.run==run then emit(state.last,'terminal',state.last.reason);return state.last.cleanup_complete==true end;return false,'session_missing'end
 if p.run~=run then return false,'session_owned'end;return stop(p,'explicit_stop')
end
