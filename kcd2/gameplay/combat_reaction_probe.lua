-- SPDX-License-Identifier: GPL-3.0-or-later
-- Bounded observation, never a forced animation. Official bindings: Soul.DealDamage
-- (stamina,health,attackerId,suppressHitreaction,bodyPart), Actor.GetCurrentAnimationState()
-- and Entity.GetCurAnimation(). Native source evidence is in docs/research/KCD-COMBAT.md.
MineCome=MineCome or {}
MineCome._combat_reaction_probe=MineCome._combat_reaction_probe or {}
local state=MineCome._combat_reaction_probe
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function token(v)return type(v)=='string' and #v==32 and v:match('^[0-9a-f]+$')~=nil end
local function number(v)return finite(v) and string.format('%.12g',v) or 'null'end
local function quoted(v)
 if type(v)~='string' then return 'null'end
 v=v:sub(1,160):gsub('\\','\\\\'):gsub('"','\\"'):gsub('[%z\1-\31]','?')
 return '"'..v..'"'
end
local function read(object,key)
 if type(object)~='table' or type(object[key])~='function' then return nil,'missing'end
 local ok,value=pcall(object[key],object);if not ok then return nil,'error'end
 return value,type(value)
end
local function wuid(e)
 local id=type(e)=='table' and type(e.this)=='table' and e.this.id
 if (type(id)=='string' and id~='') or (type(id)=='number' and finite(id) and id>0) or type(id)=='userdata' then
  if __null==nil or id~=__null then return id end
 end
end
local function owned(p)
 local fixture=MineCome._gameplay_combat_fixture and MineCome._gameplay_combat_fixture.active
 return player==p.player and player.id==p.player_id and wuid(player)==p.player_wuid and fixture==p.fixture and fixture.run==p.run and
  fixture.entity==p.entity and System.GetEntity(p.id)==p.entity and System.GetEntityByName(p.name)==p.entity and
  p.entity.id==p.id and p.entity.soul==p.soul and p.entity.actor==p.actor
end
local function emit(p,event,result,extra)
 System.LogAlways('[MineComeCombatReaction] {"schema":1,"run":"'..p.run..'","event":"'..event..'","result":"'..result..'","suppress":'..tostring(p.suppress)..',"damage_fraction":'..number(p.fraction)..',"body_part":'..quoted(p.body_part)..',"attacker_identity":"player_wuid"'..(extra or '')..'}')
end
local function finish(p,reason)
 if p.stopped then return p.reason=='sampled'end
 p.stopped=true;p.reason=reason
 if p.timer then local ok,result=pcall(Script.KillTimer,p.timer);if ok and result~=false then p.timer=nil else p.reason='timer_cleanup_failed'end end
 p.data=nil
 -- Fixture performs exact-identity removal and restores its owned path wrapper.
 local ok,result=pcall(MineCome.GameplayCombatFixtureEnd,p.run)
 p.cleanup_requested=ok and result==true
 if state.active==p then state.active=nil end;state.last=p
 emit(p,'terminal',p.reason,',"samples":'..p.samples..',"hit_called":'..tostring(p.hit_called==true)..',"before":'..number(p.before)..',"after":'..number(p.after)..',"maximum":'..number(p.maximum)..',"timers_cancelled":'..tostring(p.timer==nil)..',"fixture_cleanup_requested":'..tostring(p.cleanup_requested))
 return p.reason=='sampled' and p.cleanup_requested and p.timer==nil
end
local function sample(p,now)
 local animation,animation_type=read(p.entity,'GetCurAnimation')
 local current,current_type=read(p.actor,'GetCurrentAnimationState')
 local brain,brain_type=nil,'missing'
 if wuid(p.entity) and XGenAIModule and type(XGenAIModule.GetBrainVariable)=='function' then
  local ok,value=pcall(XGenAIModule.GetBrainVariable,wuid(p.entity),'hitReaction')
  brain_type=ok and type(value) or 'error';if ok and type(value)=='table' then brain=value end
 end
 -- This is only a retained brain-variable snapshot, never an event counter.
 -- Read two source-backed fields; don't traverse or serialize native objects.
 local attacker=brain and brain.attacker;local hit_type=brain and brain.hitType
 local matches=attacker~=nil and tostring(attacker==p.player_wuid) or 'null'
 p.samples=p.samples+1
 emit(p,'sample',p.hit_called and 'post_hit' or 'baseline',',"seq":'..p.samples..',"elapsed_ms":'..number((now-p.began)*1000)..',"animation_type":"'..animation_type..'","animation":'..quoted(animation)..',"state_type":"'..current_type..'","animation_state":'..quoted(current)..',"brain_hit_reaction_type":"'..brain_type..'","brain_attacker_type":"'..type(attacker)..'","brain_attacker_matches_player":'..matches..',"brain_hit_type":'..(finite(hit_type) and number(hit_type) or quoted(hit_type)))
end
local function schedule(p)
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,50,'MineCome_CombatReactionTick',data,true)
 if not ok or id==nil or id==false then return false end;p.timer=id;p.data=data;return true
end
function MineCome_CombatReactionTick(data)
 local p=type(data)=='table' and data.owner
 if not p or state.active~=p or p.data~=data then return end;p.timer=nil;p.data=nil
 local ok,err=pcall(function()
  local now=System.GetCurrTime()
  if not finite(now) or now<p.last or now-p.began>5 then return finish(p,'clock_or_deadline')end;p.last=now
  if not owned(p)then return finish(p,'owner_changed')end
  if not p.hit_called and now-p.began>=.5 then
   local before=p.soul:GetState('health');local maximum=p.actor:GetMaxHealth()
   if not finite(before) or not finite(maximum) or maximum<=0 or before<=maximum*p.fraction or p.actor:IsDead()~=false then return finish(p,'actor_health_invalid')end
   p.before=before;p.maximum=maximum;p.hit_called=true;p.hit_at=now
   -- Production API/normalization, optionally selecting the documented DB torso.
   -- Default nil preserves production's unspecified body part. Never replay it.
   local damaged=pcall(p.soul.DealDamage,p.soul,0,maximum*p.fraction,p.player_wuid,p.suppress,p.body_part)
   p.after=p.soul:GetState('health')
   if not damaged or not finite(p.after) or math.abs(p.after-(before-maximum*p.fraction))>.01 then return finish(p,'damage_unconfirmed')end
  end
  sample(p,now)
  if p.hit_at and now-p.hit_at>=2 then return finish(p,'sampled')end
  if not schedule(p)then return finish(p,'timer_unavailable')end
 end)
 if not ok then finish(p,'sampling_failed')end
end
function MineCome.GameplayCombatReactionProbe(run,suppress,fraction,body_part)
 if fraction==nil then fraction=.35 end
 if not token(run) or type(suppress)~='boolean' or not finite(fraction) or fraction<.01 or fraction>.5 or (body_part~=nil and body_part~='torso')then return false,'invalid_begin'end
 if state.active or (MineCome._gameplay_combat_fixture and MineCome._gameplay_combat_fixture.active)then return false,'probe_owned'end
 if not player or not player.id or not wuid(player) or not player.actor or type(player.GetWorldPos)~='function' or type(player.actor.GetHeadDir)~='function' or not System or type(System.GetCurrTime)~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' or type(MineCome.GameplayCombatFixtureBegin)~='function' or type(MineCome.GameplayCombatFixtureEnd)~='function' then return false,'api_missing'end
 local now=System.GetCurrTime();if not finite(now)then return false,'clock_missing'end
 local pos=player:GetWorldPos();local forward=player.actor:GetHeadDir()
 if type(pos)~='table' or type(forward)~='table' or not finite(pos.x) or not finite(pos.y) or not finite(pos.z) or not finite(forward.x) or not finite(forward.y)then return false,'pose_invalid'end
 local horizontal=math.sqrt(forward.x^2+forward.y^2);if horizontal<.1 then return false,'view_vertical'end
 local p={run=run,suppress=suppress,fraction=fraction,body_part=body_part,player=player,player_id=player.id,player_wuid=wuid(player),began=now,last=now,samples=0}
 local spawned,reason=MineCome.GameplayCombatFixtureBegin(run,10000,pos.x+forward.x/horizontal*2,pos.y+forward.y/horizontal*2,pos.z)
 if not spawned then return false,'fixture_'..tostring(reason)end
 local fixture=MineCome._gameplay_combat_fixture.active
 p.fixture=fixture;p.entity=fixture.entity;p.id=fixture.id;p.name=fixture.name;p.soul=fixture.soul;p.actor=fixture.entity.actor
 state.active=p
 if not owned(p)then finish(p,'owner_changed');return false,'owner_changed'end
 sample(p,now)
 if not schedule(p)then finish(p,'timer_unavailable');return false,'timer_unavailable'end
 emit(p,'begin','ready');return true
end
function MineCome.GameplayCombatReactionEnd(run)
 local p=state.active
 if not p then return state.last and state.last.run==run and state.last.stopped or false end
 if p.run~=run then return false end;return finish(p,'explicit_stop')
end
