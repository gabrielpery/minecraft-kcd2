local run=string.rep('d',32);local checks=0
local function check(v,m)checks=checks+1;if not v then error(m,2)end end
local function setup(options)
 options=options or {};local e={now=0,timers={},next_timer=0,logs={},hp=options.hp or 100,buff=false,add_calls=0,remove_calls=0,spawn_calls=0,original_calls=0,remove_requested=false,npc_removed=false}
 local original=function(target,hit,extra)e.original_calls=e.original_calls+1;check(extra=='sentinel','forwarding changed');return 'original'end
 e.shared={OnHit=original,Other='keep'}
 player={id=99,this={id='player-wuid'},Client=e.shared,actor={},soul={},player={},GetWorldPos=function()return{x=0,y=0,z=0}end}
 e.player=player
 player.actor={GetMaxHealth=function()return 100 end,IsDead=function()return e.hp<=0 end,GetHeadDir=function()return{x=0,y=1,z=0}end}
 player.soul={GetState=function(_,key)check(key=='health','unrelated state read');return e.hp end,
  HasBuffDebug=function(_,id)check(id=='44e1ccc9-9252-48a9-922d-2ae4523c69a3','wrong buff');if options.unknown_baseline then return nil end;if options.preexisting then return true end;return e.buff end,
  AddBuff=function()e.add_calls=e.add_calls+1;e.buff=not options.no_presence;if options.bad_instance then return nil end;return 'owned-instance'end,
  RemoveBuff=function(_,id)check(id=='owned-instance','wrong buff removed');check(not e.npc or e.npc_removed,'protection removed before hostile');e.remove_calls=e.remove_calls+1;if options.remove_fails then error('failed')end;e.buff=false end,
  DealDamage=function()error('probe must never directly damage/heal player')end}
 player.player.IsLockedToOpponent=function(_,id)check(e.npc and id==e.npc.id,'wrong lock target');return e.now>1 and not options.no_attack end
 System={GetCurrTime=function()return e.now end,LogAlways=function(s)check(#s<4000,'native log exceeds bound');e.logs[#e.logs+1]=s end,
  GetEntity=function(id)if id==99 then return e.player elseif e.npc and e.npc.id==id and not e.npc_removed then return e.npc end end,
  GetEntityByName=function(name)if e.npc and e.npc.name==name and not e.npc_removed then return e.npc end end}
 Script={SetTimerForFunction=function(delay,name,data)if options.timer_fail then return nil end;e.next_timer=e.next_timer+1;e.timers[e.next_timer]={at=e.now+delay/1000,name=name,data=data};return e.next_timer end,KillTimer=function(id)e.timers[id]=nil end}
 XGenAIModule={GetBrainVariable=function(id,key)check(id=='player-wuid' and key=='hitReaction','unknown brain read');if not options.brain or e.now<1 then return nil end;return{attacker=options.wrong_attacker and 'other-wuid' or 'npc-wuid',hitStrength=options.healing and 1 or 5}end}
 MineCome={_gameplay_combat_fixture={}}
 MineCome.GameplayCombatFixtureBegin=function(r,duration,x,y,z,mode)
  check(r==run and duration==15000 and y==2 and mode=='hostile','hostile fixture bounds changed');check(e.buff,'hostile spawned before verified protection')
  e.spawn_calls=e.spawn_calls+1;if options.spawn_refused then return false,'fixture_combat_api_missing'end
  e.npc={id=1,this={id='npc-wuid'},name='MineComeCombat_'..run..'_fixture',soul={}}
  e.fixture={run=r,mode=mode,entity=e.npc,name=e.npc.name};MineCome._gameplay_combat_fixture.active=e.fixture;return true
 end
 MineCome.GameplayCombatFixtureEnd=function(r)
  check(r==run,'foreign fixture ended');e.remove_requested=true
  if not e.fixture then return false end
  if not options.remove_delayed and not options.stuck_hostile then e.remove_npc()end
  return true
 end
 function e.remove_npc()
  e.npc_removed=true;e.fixture.removed=true;e.fixture.path_restored=true;MineCome._gameplay_combat_fixture.active=nil;MineCome._gameplay_combat_fixture.last=e.fixture
 end
 dofile(MINECOME_MODULE_PATH)
 function e.step()
  local id,t
  for i,v in pairs(e.timers)do if not t or v.at<t.at then id,t=i,v end end
  check(id~=nil,'expected timer');e.timers[id]=nil;e.now=t.at
  if e.npc and not e.npc_removed and not e.hit and e.now>=1 and not options.no_attack then
   e.hit=true;e.hp=90
   if not options.no_callback then
    local h={target=player,targetId=99,shooter=options.wrong_attacker and {} or e.npc,shooterId=options.wrong_attacker and 2 or 1,damage=10}
    check(player.Client.OnHit(player,h,'sentinel')=='original','callback return lost')
   end
  end
  if e.remove_requested and options.remove_delayed and not options.stuck_hostile and not e.npc_removed then e.remove_npc()end
  _G[t.name](t.data)
 end
 function e.drain()for i=1,220 do if not next(e.timers)then return end;e.step()end;error('unbounded timer')end
 function e.result()return MineCome._combat_retaliation_probe.last end
 return e
end
local e=setup({remove_delayed=true});check(MineCome.GameplayRetaliationProbe(run),'valid begin refused');check(e.spawn_calls==0 and e.buff,'hostile spawned synchronously');check(e.shared.OnHit==e.player.Client.OnHit or e.shared.Other=='keep','shared table mutated');e.drain()
local p=e.result();check(p.completed and p.before==100 and p.after==90 and p.health_loss_observed and p.matching_damage_callback,'real attack evidence incomplete')
check(p.callback_count==1 and e.original_calls==1 and p.lock_seen and p.lock_before==false,'callback/lock observation missing')
check(p.fixture_removed and p.buff_removed and p.callback_restored and e.remove_calls==1 and e.player.Client==e.shared and not next(e.timers),'normal cleanup incomplete')
check(e.now>=10 and e.now<20 and not MineCome._combat_retaliation_probe.active,'deadline/terminal differs')
check(MineCome.GameplayRetaliationEnd(run) and e.remove_calls==1,'terminal end not idempotent')
e=setup({no_attack=true});check(MineCome.GameplayRetaliationProbe(run),'no-attack begin');e.drain();p=e.result()
check(p.completed and not p.health_loss_observed and not p.matching_damage_callback and not p.brain_attack_observed and not p.lock_seen,'absence overstated attack')
e=setup({no_callback=true,brain=true});check(MineCome.GameplayRetaliationProbe(run),'brain begin');e.drain();p=e.result()
check(p.completed and p.callback_count==0 and p.brain_attack_observed and p.brain_attacker_matches and p.brain_strength==5,'source-backed brain observation missing')
for _,options in ipairs({{no_callback=true,brain=true,healing=true},{no_callback=true,brain=true,wrong_attacker=true},{wrong_attacker=true}})do
 e=setup(options);check(MineCome.GameplayRetaliationProbe(run),'negative attribution begin');e.drain();p=e.result()
 check(p.completed and not p.brain_attack_observed and not p.matching_damage_callback,'healing/foreign hit attributed as NPC attack')
end
for _,options in ipairs({{preexisting=true},{unknown_baseline=true},{hp=90}})do
 e=setup(options);check(not MineCome.GameplayRetaliationProbe(run),'malformed/foreign baseline admitted');p=e.result()
 check(e.spawn_calls==0 and e.add_calls==0 and e.remove_calls==0 and not p.completed,'baseline refusal mutated state')
end
e=setup({no_presence=true});check(MineCome.GameplayRetaliationProbe(run),'presence begin');e.drain();p=e.result()
check(not p.completed and e.spawn_calls==0 and p.buff_removed,'unconfirmed protection allowed hostile')
e=setup({bad_instance=true});check(not MineCome.GameplayRetaliationProbe(run),'unknown instance admitted');p=e.result()
check(e.spawn_calls==0 and not p.buff_removed and e.remove_calls==0 and p.callback_restored,'unknown instance removal fabricated')
e=setup({spawn_refused=true});check(MineCome.GameplayRetaliationProbe(run),'preflight begin');e.drain();p=e.result()
check(not p.completed and p.buff_removed and p.fixture_removed and e.remove_calls==1,'fixture preflight leaked protection')
e=setup({remove_fails=true});check(MineCome.GameplayRetaliationProbe(run),'remove-fail begin');e.drain();p=e.result()
check(not p.completed and p.fixture_removed and not p.buff_removed and e.remove_calls==1,'buff removal failure hidden')
e=setup({stuck_hostile=true});check(MineCome.GameplayRetaliationProbe(run),'stuck-hostile begin');e.drain();p=e.result()
check(not p.completed and not p.fixture_removed and not p.buff_removed and e.remove_calls==0 and e.buff and e.now<20,'hostile cleanup removed protection or became unbounded')
e=setup();check(MineCome.GameplayRetaliationProbe(run),'early-cancel begin');check(MineCome.GameplayRetaliationEnd(run),'early cancel failed');p=e.result()
check(not p.completed and e.spawn_calls==0 and p.buff_removed and p.callback_restored and not next(e.timers),'early cancel leaked state')
e=setup();check(MineCome.GameplayRetaliationProbe(run),'identity begin');e.step();player.this.id='replacement';e.drain();p=e.result()
check(not p.completed and p.fixture_removed and not p.buff_removed and e.remove_calls==0,'changed player got cleanup mutation')
e=setup();check(MineCome.GameplayRetaliationProbe(run),'callback ownership begin');e.step();local foreign={OnHit=e.shared.OnHit};player.Client=foreign;e.drain();p=e.result()
check(not p.completed and not p.callback_restored and player.Client==foreign and p.buff_removed,'foreign callback overwritten')
e=setup({timer_fail=true});check(not MineCome.GameplayRetaliationProbe(run),'missing timer admitted');p=e.result()
check(e.spawn_calls==0 and p.buff_removed and p.callback_restored,'timer failure cleanup incomplete')
print('PASS bounded hostile retaliation observation: '..checks..' checks; simulated engine, not incoming gameplay proof')
