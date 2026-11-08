local run=string.rep('b',32);local checks=0
local function check(v,m)checks=checks+1;if not v then error(m,2)end end
local function setup(options)
 options=options or {};local env={now=0,timers={},next_timer=0,logs={},damage_calls=0,add_calls=0,remove_calls=0,original_calls=0,removed=false,soul_damage_calls=0,normal_hit_calls=0}
 player={id=99,this={id='player-wuid'},actor={GetHeadDir=function()return{x=0,y=1,z=0}end},GetWorldPos=function()return{x=0,y=0,z=0}end}
 env.original=function(target,hit,extra)env.original_calls=env.original_calls+1;check(extra=='sentinel','callback varargs changed');return 'original_result'end
 env.shared={OnHit=env.original,Other='untouched'}
 System={GetCurrTime=function()return env.now end,LogAlways=function(s)env.logs[#env.logs+1]=s end,
  GetEntity=function(id)return env.entity and env.entity.id==id and env.entity or nil end,
  GetEntityByName=function(name)return env.entity and env.entity.name==name and env.entity or nil end}
 Script={SetTimerForFunction=function(delay,name,data)env.next_timer=env.next_timer+1;env.timers[env.next_timer]={delay=delay,name=name,data=data};return env.next_timer end,
  KillTimer=function(id)env.timers[id]=nil end}
 g_gameRules={game={ServerHit=function()end},CreateHit=function(self,target,shooter,weapon,amount,radius,material,part,kind)
  env.normal_hit_calls=env.normal_hit_calls+1
  check(self==g_gameRules and target==env.entity.id and target~=player.id and shooter==player.id and weapon==player.id and radius==nil and material==nil and part==nil and kind=='normal','normal hit signature/target changed')
  if not options.ignore_normal then return env.native_damage(env.entity.soul,0,amount,shooter,false)end
 end}
 if options.no_rules then g_gameRules.CreateHit=nil end
 MineCome={_gameplay_combat_fixture={}}
 MineCome.GameplayCombatFixtureBegin=function(r,duration,x,y,z)
  check(r==run and duration==10000 and y==2,'fixture bounds changed')
  local e={id=1,name='fixture',Client=env.shared,actor={}};local hp=100;local buff=false;local dead=false;local instance='owned-instance'
  e.soul={GetState=function(_,key)check(key=='health','unrelated soul state');return hp end,
   HasBuffDebug=function(_,guid)check(guid=='44e1ccc9-9252-48a9-922d-2ae4523c69a3','wrong buff');if env.add_calls==0 and options.unknown_baseline then return nil end;if options.preexisting then return true end;return buff end,
   AddBuff=function()env.add_calls=env.add_calls+1;buff=not options.no_presence;if options.bad_instance then return nil end;return instance end,
   RemoveBuff=function(_,id)check(id==instance,'foreign buff removed');env.remove_calls=env.remove_calls+1;if options.remove_fails then error('remove failed')end;buff=false end,
   DealDamage=function(_,stamina,amount,attacker,suppress)
    env.damage_calls=env.damage_calls+1;check(env.entity==e and e~=player and stamina==0 and suppress==false,'nonowned/incorrect native damage')
    hp=math.max(options.no_protection and 0 or 1,hp-amount);dead=hp==0
    if not options.no_callbacks then check(e.Client.OnHit(e,{target=e,targetId=e.id,shooter=player,shooterId=player.id,damage=amount,type='melee'},'sentinel')=='original_result','original return changed')end
   end}
  env.native_damage=e.soul.DealDamage;e.soul.DealDamage=function(...)check(select(4,...)==player.this.id and select(4,...)~=player.id,'soul damage used entity handle instead of WUID');env.soul_damage_calls=env.soul_damage_calls+1;return env.native_damage(...)end
  e.actor={GetMaxHealth=function()return 100 end,IsDead=function()return dead end}
  env.entity=e;env.original_entity=e;MineCome._gameplay_combat_fixture.active={run=r,entity=e,name=e.name};return true
 end
 MineCome.GameplayCombatFixtureEnd=function(r)
  check(r==run,'foreign fixture ended');if env.entity and env.entity==env.original_entity then env.restored_client=env.entity.Client;env.entity=nil;env.removed=true end;MineCome._gameplay_combat_fixture.active=nil;return env.removed
 end
 dofile(MINECOME_MODULE_PATH)
 function env.step()
  local id,t=next(env.timers);check(id~=nil,'missing bounded stage timer');env.timers[id]=nil;env.now=env.now+t.delay/1000;_G[t.name](t.data)
 end
 function env.drain()for i=1,8 do if not next(env.timers)then return end;env.step()end;error('unbounded timers')end
 function env.result()return MineCome._combat_protection_probe.last end
 return env
end
local e=setup();check(MineCome.GameplayCombatProtectionProbe(run),'valid experiment refused');check(e.shared.OnHit==e.original,'shared callback overwritten');e.drain()
local p=e.result();check(p.completed and p.protection_observed and p.nonlethal_after==90 and p.lethal_after==1 and not p.lethal_dead,'protected health observation differs')
check(p.callback_count==2 and p.hits[1].damage==10 and p.hits[2].damage==200,'real callback observations lost')
check(p.buff_removed and p.callback_restored and p.timer==nil and e.removed and e.remove_calls==1,'owned cleanup incomplete')
check(e.original_calls==2 and e.restored_client==e.shared and e.shared.Other=='untouched','original callback/table not preserved')
check(not MineCome._combat_protection_probe.active and MineCome.GameplayCombatProtectionEnd(run),'terminal/idempotent end differs')
e=setup({no_callbacks=true,no_protection=true});check(MineCome.GameplayCombatProtectionProbe(run),'negative experiment refused');e.drain();p=e.result()
check(p.completed and not p.protection_observed and p.lethal_dead and p.callback_count==0,'negative result overstated protection/notifications')
for _,options in ipairs({{preexisting=true},{unknown_baseline=true}})do
 e=setup(options);check(not MineCome.GameplayCombatProtectionProbe(run),'unconfirmed absent baseline accepted');p=e.result()
 check(e.add_calls==0 and e.damage_calls==0 and e.remove_calls==0 and e.removed and not p.completed,'baseline failure mutated buff or health')
end
e=setup({bad_instance=true});check(not MineCome.GameplayCombatProtectionProbe(run),'unknown instance accepted');p=e.result()
check(e.remove_calls==0 and e.damage_calls==0 and not p.buff_removed and p.callback_restored and e.removed,'unknown instance cleanup overclaimed')
e=setup({no_presence=true});check(MineCome.GameplayCombatProtectionProbe(run),'fixture begin refused');e.drain();p=e.result()
check(not p.completed and e.damage_calls==0 and p.buff_removed and p.callback_restored,'unconfirmed applied buff allowed damage')
e=setup({remove_fails=true});check(MineCome.GameplayCombatProtectionProbe(run),'fixture begin refused');e.drain();p=e.result()
check(not p.completed and not p.buff_removed and e.removed and e.remove_calls==1,'remove failure hidden/retried')
e=setup();check(MineCome.GameplayCombatProtectionProbe(run),'begin refused');local foreign={OnHit=function()end};e.entity.Client=foreign;e.drain();p=e.result()
check(not p.completed and not p.callback_restored and e.restored_client==foreign,'foreign callback overwritten or claimed restored')
e=setup();check(MineCome.GameplayCombatProtectionProbe(run),'begin refused');local replacement={id=1,name='fixture',soul={},Client={}};e.entity=replacement;e.drain();p=e.result()
check(not p.completed and e.damage_calls==0 and e.remove_calls==0 and e.entity==replacement,'replacement NPC modified')
e=setup();check(MineCome.GameplayCombatProtectionProbe(run),'begin refused');check(MineCome.GameplayCombatProtectionEnd(run),'early end failed');p=e.result()
check(not p.completed and e.damage_calls==0 and p.buff_removed and p.callback_restored and next(e.timers)==nil,'early cancellation failed cleanup')
e=setup();check(not MineCome.GameplayCombatProtectionProbe(run,'unknown'),'unvalidated damage mode accepted');check(e.add_calls==0 and not MineCome._combat_protection_probe.active,'invalid mode mutated state')
e=setup();check(MineCome.GameplayCombatProtectionProbe(run,'normal_hit'),'normal hit experiment refused');e.drain();p=e.result()
check(p.completed and p.damage_mode=='normal_hit' and p.protection_observed and p.nonlethal_damage_observed and p.lethal_damage_observed,'normal hit protection result incomplete')
check(e.normal_hit_calls==2 and e.soul_damage_calls==0 and p.callback_count==2,'normal mode used direct soul damage or lost callbacks')
e=setup({ignore_normal=true});check(MineCome.GameplayCombatProtectionProbe(run,'normal_hit'),'ignored normal hit refused');e.drain();p=e.result()
check(p.completed and p.nonlethal_after==100 and p.lethal_after==100 and not p.protection_observed and not p.nonlethal_damage_observed and not p.lethal_damage_observed and p.callback_count==0,'ignored ServerHit falsely verified immunity')
e=setup({no_rules=true});check(not MineCome.GameplayCombatProtectionProbe(run,'normal_hit'),'missing normal hit API accepted');check(e.add_calls==0 and e.damage_calls==0,'missing API mutated native actor')
e=setup();check(MineCome.GameplayCombatProtectionProbe(run,'normal_hit'),'normal hit begin refused');g_gameRules={};e.drain();p=e.result()
check(not p.completed and e.normal_hit_calls==0 and e.damage_calls==0 and p.buff_removed and p.callback_restored,'changed game rules used or cleanup lost')
e=setup();player.this=nil;check(not MineCome.GameplayCombatProtectionProbe(run),'missing player WUID accepted');check(e.entity==nil and e.add_calls==0 and e.damage_calls==0,'missing WUID permitted mutations')
e=setup();check(MineCome.GameplayCombatProtectionProbe(run),'WUID identity test begin refused');player.this.id='replacement';e.drain();p=e.result()
check(not p.completed and e.damage_calls==0 and p.buff_removed and p.callback_restored,'changed WUID allowed first hit or leaked cleanup')
e=setup();check(MineCome.GameplayCombatProtectionProbe(run),'second-hit identity test begin refused');e.step();check(e.damage_calls==1,'first hit not observed');player.this.id='replacement';e.drain();p=e.result()
check(not p.completed and e.damage_calls==1 and p.buff_removed and p.callback_restored,'changed WUID allowed second hit or leaked cleanup')
e=setup();player.this=nil;check(MineCome.GameplayCombatProtectionProbe(run,'normal_hit'),'normal hit incorrectly required WUID');e.drain();p=e.result()
check(p.completed and p.attacker_identifier_kind=='entity_handle' and e.normal_hit_calls==2 and e.soul_damage_calls==0,'normal hit attribution changed')
e=setup();check(MineCome.GameplayCombatProtectionProbe(run),'soul attribution evidence begin refused');e.drain();p=e.result()
check(p.completed and p.attacker_identifier_kind=='wuid' and e.soul_damage_calls==2 and e.normal_hit_calls==0,'soul attribution evidence differs')
print('PASS native NPC protection probe: '..checks..' checks; simulated engine, no live protection/notification claim')
