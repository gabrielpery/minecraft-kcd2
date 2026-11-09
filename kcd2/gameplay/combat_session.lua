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
 if p.timer then local ok,v=pcall(Script.KillTimer,p.timer);if ok and v~=false then p.timer=nil else p.reason='timer_cleanup_failed'end end
 if not restore_lock_policy(p)then p.reason='lock_policy_cleanup_unconfirmed'end
 p.cleanup_complete=p.timer==nil and p.lock_policy_restored==true
 p.timer_data=nil;state.active=nil;state.last=p
 emit(p,'terminal',p.reason);return p.cleanup_complete
end
local function valid(p)
 local t=clock();if not t or t<p.last_clock or t>=p.deadline or t-p.received>LEASE then return nil,'lease_expired'end
 if player~=p.player or player.id~=p.player_id or player.soul~=p.player_soul or wuid(player)~=p.player_wuid then return nil,'player_changed'end
 if read(player.actor,'IsDead')~=false then return nil,'player_unavailable'end
 if not lock_policy_owned(p)then return nil,'lock_policy_changed'end
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
 if not System or type(System.GetEntitiesInSphere)~='function' or type(System.GetCurrTime)~='function' or type(System.LogAlways)~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' or not Physics or type(Physics.RayWorldIntersection)~='function' or not integer(ent_all,1,2147483647) then return false,'api_unavailable'end
 if type(player)~='table' or not player.id or not wuid(player) or type(player.soul)~='table' or read(player.actor,'IsDead')~=false then return false,'player_unavailable'end
 local t=clock();if not t then return false,'clock_unavailable'end
 local p={run=run,deadline=t+duration_ms/1000,received=t,last_clock=t,player=player,player_id=player.id,player_wuid=wuid(player),player_soul=player.soul,radius=radius,max_actors=max_actors,next_token=1,actors={},samples={},sequence=0,hit_ack=0}
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
   found=p.next_token;p.next_token=p.next_token+1;p.actors[found]=a
  end
  a.token=found;sample.actors[found]=a
  rows[#rows+1]='{"token":'..found..',"x":'..number(a.x)..',"y":'..number(a.y)..',"z":'..number(a.z)..',"width":'..number(a.width)..',"height":'..number(a.height)..',"health":'..number(a.health)..',"max_health":'..number(a.max_health)..',"alive":'..tostring(a.alive)..'}'
 end
 p.samples[sequence]=sample;for id,s in pairs(p.samples)do if t-s.time>FRESH or id<sequence-4 then p.samples[id]=nil end end
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
function MineCome.GameplayCombatEnd(run)
 local p=state.active
 if not p then if state.last and state.last.run==run then emit(state.last,'terminal',state.last.reason);return state.last.cleanup_complete==true end;return false,'session_missing'end
 if p.run~=run then return false,'session_owned'end;return stop(p,'explicit_stop')
end
