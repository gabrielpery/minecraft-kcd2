local now,timers,logs,entities,names=0,{}, {},{},{}
local timer_id,damage_calls,cleanup_calls=0,0,0
local timer_fail=false;local current_entity;local expected_body_part;local run=string.rep('a',32)
local function check(value,message)if not value then error(message,2)end end
player={id=99,this={id='player-wuid'},actor={GetHeadDir=function()return{x=0,y=1,z=0}end},GetWorldPos=function()return{x=0,y=0,z=0}end}
System={GetCurrTime=function()return now end,GetEntity=function(id)return entities[id]end,GetEntityByName=function(name)return names[name]end,LogAlways=function(s)logs[#logs+1]=s end}
Script={SetTimerForFunction=function(ms,name,data)if timer_fail then return nil end;timer_id=timer_id+1;timers[timer_id]={at=now+ms/1000,name=name,data=data};return timer_id end,KillTimer=function(id)timers[id]=nil end}
MineCome={_gameplay_combat_fixture={}}
function MineCome.GameplayCombatFixtureBegin(id,duration,x,y,z)
 check(MineCome._gameplay_combat_fixture.active==nil,'fixture overlap')
 local e={id=1,this={id='owned-npc-wuid'},name='fixture_'..id,health=100,soul={},actor={}};current_entity=e
 e.soul.GetState=function(_,key)check(key=='health','unexpected soul state');return e.health end
 e.soul.DealDamage=function(_,stamina,health,attacker,suppress,body_part)
  check(stamina==0 and health==35 and attacker==player.this.id and attacker~=player.id and type(suppress)=='boolean','production damage must use player WUID')
  check(body_part==expected_body_part,'body part default or explicit argument differs')
  damage_calls=damage_calls+1;e.health=e.health-health;e.reaction=not suppress;e.hit_at=now
 end
 e.actor.GetMaxHealth=function()return 100 end;e.actor.IsDead=function()return false end
 e.actor.GetCurrentAnimationState=function()return e.reaction and now-e.hit_at<.5 and 'HitDeath' or 'MotionIdle'end
 e.GetCurAnimation=function()return 'idle' end
 entities[1]=e;names[e.name]=e
 MineCome._gameplay_combat_fixture.active={run=id,entity=e,id=e.id,name=e.name,soul=e.soul}
 return true
end
XGenAIModule={GetBrainVariable=function(id,name)
 check(id=='owned-npc-wuid' and name=='hitReaction','wrong brain snapshot selector')
 return current_entity.hit_at and {attacker=player.this.id,hitType='Melee',ignored_native_object=function()error('must not serialize')end} or nil
end}
function MineCome.GameplayCombatFixtureEnd(id)
 local p=MineCome._gameplay_combat_fixture.active
 if not p or p.run~=id then return false end
 cleanup_calls=cleanup_calls+1;MineCome._gameplay_combat_fixture.active=nil
 if entities[p.id]~=p.entity or names[p.name]~=p.entity then return false end
 entities[p.id]=nil;names[p.name]=nil;return true
end
local function step()
 local id,event;for k,v in pairs(timers)do if not event or v.at<event.at then id,event=k,v end end
 check(event~=nil,'expected timer');timers[id]=nil;now=event.at;_G[event.name](event.data)
end
local function finish()local bound=0;while next(timers)do bound=bound+1;check(bound<120,'unbounded timer loop');step()end end
dofile(MINECOME_MODULE_PATH)
check(not MineCome.GameplayCombatReactionProbe('invalid',false),'invalid run accepted')
check(not MineCome.GameplayCombatReactionProbe(run,'false'),'nonboolean accepted')
local player_this=player.this;player.this=nil
check(not MineCome.GameplayCombatReactionProbe(run,false),'missing attacker WUID accepted');player.this=player_this
for _,bad in ipairs({0,.001,.51,1,'0.35',math.huge})do check(not MineCome.GameplayCombatReactionProbe(run,false,bad),'invalid damage fraction accepted')end
for _,bad in ipairs({'head','Torso','',0,true})do check(not MineCome.GameplayCombatReactionProbe(run,false,.35,bad),'unsupported body part accepted')end
for _,suppress in ipairs({false,true})do
 local before=damage_calls;local first=#logs
 check(MineCome.GameplayCombatReactionProbe(run,suppress),'probe did not begin')
 check(not MineCome.GameplayCombatReactionProbe(run,suppress),'overlap accepted')
 check(not MineCome.GameplayCombatReactionEnd(string.rep('b',32)),'foreign stop accepted')
 finish()
 check(damage_calls==before+1,'damage missing/replayed')
 check(logs[#logs]:match('"damage_fraction":0.35') and logs[#logs]:match('"after":65') and logs[#logs]:match('"body_part":null'),'fraction/damage/default body part receipt differs')
 check(logs[#logs-1]:match('"brain_attacker_matches_player":true') and logs[#logs-1]:match('"brain_hit_type":"Melee"'),'source-backed brain snapshot not observed')
 check(MineCome._combat_reaction_probe.active==nil and next(entities)==nil,'owned resources leaked')
 check(logs[#logs]:match('"result":"sampled"') and logs[#logs]:match('"timers_cancelled":true') and logs[#logs]:match('"fixture_cleanup_requested":true'),'terminal cleanup proof missing')
 local baseline,post,named=0,0,0
 for i=first+1,#logs do if logs[i]:match('"event":"sample"')then
  if logs[i]:match('"result":"baseline"')then baseline=baseline+1 else post=post+1 end
  if logs[i]:match('"animation_state":"HitDeath"')then named=named+1 end
 end end
 check(baseline>=3 and post>=15,'bounded baseline/after sampling missing')
 check((suppress and named==0)or(not suppress and named>0),'suppression comparison lost')
 check(MineCome.GameplayCombatReactionEnd(run),'completed idempotent stop refused')
end
expected_body_part='torso'
check(MineCome.GameplayCombatReactionProbe(run,false,.35,'torso'),'documented torso probe failed');finish()
check(logs[#logs]:match('"body_part":"torso"') and logs[#logs]:match('"result":"sampled"'),'explicit body part evidence missing')
expected_body_part=nil
-- Unsupported observation APIs produce explicit missing/null fields, not a
-- fabricated reaction or failure to release the test actor.
check(MineCome.GameplayCombatReactionProbe(run,false),'missing observer probe failed')
current_entity.actor.GetCurrentAnimationState=nil;current_entity.GetCurAnimation=nil;finish()
check(logs[#logs-1]:match('"animation_type":"missing"') and logs[#logs-1]:match('"animation":null'),'unavailable animation invented')
-- Lost identity must stop before mutation and cannot remove the replacement.
local before=damage_calls;check(MineCome.GameplayCombatReactionProbe(run,false),'identity probe failed')
local replacement={id=1};entities[1]=replacement;step()
check(damage_calls==before and entities[1]==replacement,'foreign actor mutated')
check(logs[#logs]:match('"result":"owner_changed"') and logs[#logs]:match('"fixture_cleanup_requested":false'),'lost ownership hidden')
entities={};names={}
local before=damage_calls;check(MineCome.GameplayCombatReactionProbe(run,false),'WUID identity probe failed')
local saved_wuid=player.this.id;player.this.id='changed-player-wuid';step();player.this.id=saved_wuid
check(damage_calls==before and next(entities)==nil and logs[#logs]:match('"result":"owner_changed"'),'changed player WUID admitted')
timer_fail=true;before=cleanup_calls
check(not MineCome.GameplayCombatReactionProbe(run,false),'missing timer accepted')
check(cleanup_calls==before+1 and next(entities)==nil,'failed timer leaked NPC');timer_fail=false
check(MineCome.GameplayCombatReactionProbe(run,false),'explicit stop setup failed');before=damage_calls
MineCome.GameplayCombatReactionEnd(run)
check(next(timers)==nil and next(entities)==nil and damage_calls==before,'explicit stop damaged/leaked')
print('PASS bounded NPC reaction observation: suppression, exact single damage, unavailable animation, ownership and cleanup (simulated engine)')
