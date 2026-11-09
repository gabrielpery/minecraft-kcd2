-- SPDX-License-Identifier: GPL-3.0-or-later
-- Observe real native hostile melee; never issues player damage, movement or health refunds.
-- Official buff.xml:150 + CombatDebug.lua:207-212 support owned immortality.
-- SinglePlayer.lua:291-298 forwards Client.OnHit; player/switch/switch.xml:106-107
-- stores hitReaction. ai_types.xml:1640-1644 / ai_enums.xml:923-931 bound its fields.
MineCome=MineCome or {}
MineCome._combat_retaliation_probe=MineCome._combat_retaliation_probe or {}
local state=MineCome._combat_retaliation_probe
local BUFF='44e1ccc9-9252-48a9-922d-2ae4523c69a3'
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function n(v)return finite(v) and string.format('%.12g',v) or 'null'end
local function b(v)return type(v)=='boolean' and tostring(v) or 'null'end
local function require_true(v,why)if not v then error(why,0)end end
local function clean(v)return tostring(v):gsub('[^a-zA-Z0-9_ :./-]','_'):sub(1,160)end
local function wuid(e)
 local id=type(e)=='table' and type(e.this)=='table' and e.this.id
 if (type(id)=='userdata' or (type(id)=='string' and #id>0) or (finite(id) and id>0)) and (__null==nil or id~=__null)then return id end
end
local function owned_player(p)
 return player==p.player and player.id==p.player_id and player.soul==p.soul and player.actor==p.actor and wuid(player)==p.player_wuid and System.GetEntity(p.player_id)==p.player
end
local function owned_npc(p)
 local f=MineCome._gameplay_combat_fixture and MineCome._gameplay_combat_fixture.active
 return p.fixture and f==p.fixture and f.run==p.run and f.mode=='hostile' and f.entity==p.npc and
  p.npc.id==p.npc_id and p.npc.soul==p.npc_soul and wuid(p.npc)==p.npc_wuid and
  System.GetEntity(p.npc_id)==p.npc and System.GetEntityByName(f.name)==p.npc
end
local function fixture_removed(p)
 if not p.spawn_attempted then return true end
 local s=MineCome._gameplay_combat_fixture
 local f=s and s.last
 return f and f.run==p.run and f.mode=='hostile' and f.removed==true and f.path_restored==true and s.active~=f
end
local function emit(p)
 local hits={}
 for _,h in ipairs(p.hits)do hits[#hits+1]='{"damage":'..n(h.damage)..',"shooter_matches":'..b(h.shooter_matches)..',"target_matches":'..b(h.target_matches)..'}'end
 System.LogAlways('[MineComeRetaliation] {"schema":1,"run":"'..p.run..'","completed":'..b(p.completed)..',"reason":"'..clean(p.reason)..'","before":'..n(p.before)..',"after":'..n(p.after)..',"maximum":'..n(p.maximum)..',"health_loss":'..n(p.before and p.after and math.max(0,p.before-p.after))..',"health_loss_observed":'..b(p.health_loss_observed==true)..',"attack_observed":'..b(p.matching_damage_callback==true or p.brain_attack_observed==true)..',"callback_count":'..p.callback_count..',"callbacks_truncated":'..b(p.callback_count>#p.hits)..',"hits":['..table.concat(hits,',')..'],"brain_type":"'..clean(p.brain_type or 'unread')..'","brain_attacker_matches":'..b(p.brain_attacker_matches)..',"brain_hit_strength":'..n(p.brain_strength)..',"brain_attack_observed":'..b(p.brain_attack_observed==true)..',"lock_before":'..b(p.lock_before)..',"lock_seen":'..b(p.lock_seen==true)..',"samples":'..p.samples..',"fixture_removed":'..b(p.fixture_removed==true)..',"buff_removed":'..b(p.buff_removed==true)..',"protection_retained":'..b(p.buff_attempted==true and p.buff_removed~=true)..',"callback_restored":'..b(p.callback_restored==true)..',"timers_cancelled":'..b(p.timer==nil)..',"direct_player_damage":false,"health_refund":false,"movement_writes":0}')
end
local function finish(p,reason,completed)
 if p.finished then return end
 p.finished=true;p.reason=reason
 if p.timer then local ok,v=pcall(Script.KillTimer,p.timer);if ok and v~=false then p.timer=nil end end;p.timer_data=nil
 -- Include any last native damage while deferred NPC removal was pending.
 if p.before and owned_player(p) then
  local ok,hp=pcall(p.soul.GetState,p.soul,'health')
  p.final_health_read=ok and finite(hp) and hp>0 and hp<=p.maximum
  if p.final_health_read then p.after=hp;p.health_loss_observed=p.health_loss_observed or hp<p.before end
 end
 if p.client_copy then
  if owned_player(p) and rawget(p.player,'Client')==p.client_copy then p.player.Client=p.original_client_raw end
  p.callback_restored=owned_player(p) and rawget(p.player,'Client')==p.original_client_raw and p.player.Client==p.original_client
 else p.callback_restored=true end
 p.fixture_removed=fixture_removed(p)==true
 if p.buff_attempted then
  -- Removing protection while our hostile actor may still be alive is unsafe.
  if p.fixture_removed and owned_player(p) and p.buff_instance and not p.buff_remove_attempted then
   p.buff_remove_attempted=true
   local ok=pcall(p.soul.RemoveBuff,p.soul,p.buff_instance)
   local read_ok,present=pcall(p.soul.HasBuffDebug,p.soul,BUFF)
   p.buff_removed=ok and read_ok and present==false
  else p.buff_removed=false end
 else p.buff_removed=true end
 if state.active==p then state.active=nil end;state.last=p
 p.completed=completed==true and p.final_health_read==true and p.fixture_removed and p.buff_removed and p.callback_restored and p.timer==nil
 if not (p.fixture_removed and p.buff_removed and p.callback_restored and p.timer==nil)then p.reason=reason..'_cleanup_unconfirmed'end
 emit(p)
end
local function schedule(p,delay)
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,delay,'MineCome_RetaliationTick',data,true)
 if not ok or id==nil or id==false then return false end;p.timer=id;p.timer_data=data;return true
end
local function cleanup(p,reason,complete)
 if p.finished then return end
 if not p.cleaning then
  p.cleaning=true;p.reason=reason;p.observation_complete=complete==true;p.cleanup_polls=0
  if p.timer then local ok,v=pcall(Script.KillTimer,p.timer);if ok and v~=false then p.timer=nil end end;p.timer_data=nil
  if p.spawn_attempted then pcall(MineCome.GameplayCombatFixtureEnd,p.run)end
 end
 if fixture_removed(p)then return finish(p,p.reason,p.observation_complete)end
 p.cleanup_polls=p.cleanup_polls+1
 local t=System.GetCurrTime()
 if p.timer~=nil or not finite(t) or t<p.started or t-p.started>=20 or p.cleanup_polls>=80 or not schedule(p,100)then finish(p,p.reason,false)end
end
local function sample(p)
 require_true(owned_player(p) and owned_npc(p),'identity_changed')
 local hp=p.soul:GetState('health');local dead=p.actor:IsDead()
 require_true(finite(hp) and hp>=0 and hp<=p.maximum and type(dead)=='boolean','health_unavailable')
 p.after=hp;p.samples=p.samples+1;p.health_loss_observed=p.health_loss_observed or hp<p.before
 require_true(not dead and hp>0,'protected_player_dead')
 local getter=p.player.player and p.player.player.IsLockedToOpponent
 if type(getter)=='function' then
  local ok,value=pcall(getter,p.player.player,p.npc_id)
  if ok and type(value)=='boolean'then if p.samples==1 then p.lock_before=value end;p.lock_seen=p.lock_seen or value end
 end
 local ok,brain=pcall(XGenAIModule.GetBrainVariable,p.player_wuid,'hitReaction')
 p.brain_type=ok and type(brain) or 'error'
 if ok and type(brain)=='table' then
  local matched=brain.attacker==p.npc_wuid;local strength=brain.hitStrength
  p.brain_attacker_matches=matched
  if finite(strength) and strength==math.floor(strength) and strength>=0 and strength<=7 then
   p.brain_strength=strength
   -- Healing=1 and Zero=0 are not attack observations. No event count is inferred.
   if matched and strength>=2 then p.brain_attack_observed=true end
  end
 end
end
function MineCome_RetaliationTick(data)
 local p=type(data)=='table' and data.owner
 if not p or state.active~=p or p.timer_data~=data or p.finished then return end;p.timer=nil;p.timer_data=nil
 if p.cleaning then return cleanup(p,p.reason,p.observation_complete)end
 local ok,why=pcall(function()
  local t=System.GetCurrTime();require_true(finite(t) and t>=p.last and t-p.started<20,'clock_or_deadline');p.last=t
  require_true(owned_player(p),'player_identity_changed')
  require_true(p.soul:HasBuffDebug(BUFF)==true,'owned_protection_missing')
  if not p.spawn_attempted then
   p.spawn_attempted=true
   local spawned,reason=MineCome.GameplayCombatFixtureBegin(p.run,15000,p.spawn.x,p.spawn.y,p.spawn.z,'hostile')
   local fs=MineCome._gameplay_combat_fixture
   -- Fixture preflight refusals cannot own a hostile. A post-spawn unknown
   -- outcome leaves its active/last record and is deliberately not waived.
   if not spawned and not (fs and ((fs.active and fs.active.run==p.run) or (fs.last and fs.last.run==p.run))) and System.GetEntityByName('MineComeCombat_'..p.run..'_fixture')==nil then p.spawn_attempted=false end
   require_true(spawned,'fixture_'..tostring(reason))
   p.fixture=MineCome._gameplay_combat_fixture.active;p.npc=p.fixture and p.fixture.entity
   p.npc_id=p.npc and p.npc.id;p.npc_soul=p.npc and p.npc.soul;p.npc_wuid=wuid(p.npc)
   require_true(p.npc_wuid~=nil,'npc_wuid_missing');p.observation_started=t
  end
  sample(p)
  if t-p.observation_started>=10 then cleanup(p,'observed',true)
  else require_true(schedule(p,100),'timer_unavailable')end
 end)
 if not ok then cleanup(p,clean(why),false)end
end
function MineCome.GameplayRetaliationProbe(run)
 if type(run)~='string' or #run~=32 or not run:match('^[0-9a-f]+$')then return false,'invalid_run'end
 if state.active or (MineCome._gameplay_combat_fixture and MineCome._gameplay_combat_fixture.active)then return false,'probe_owned'end
 local p={run=run,player=player,player_id=player and player.id,player_wuid=wuid(player),soul=player and player.soul,actor=player and player.actor,hits={},callback_count=0,samples=0}
 state.active=p
 local ok,why=pcall(function()
  require_true(p.player_wuid and type(p.soul)=='table' and type(p.actor)=='table','player_unavailable')
  require_true(System and type(System.GetCurrTime)=='function' and type(System.GetEntity)=='function' and type(System.GetEntityByName)=='function' and type(System.LogAlways)=='function' and Script and type(Script.SetTimerForFunction)=='function' and type(Script.KillTimer)=='function' and XGenAIModule and type(XGenAIModule.GetBrainVariable)=='function' and type(MineCome.GameplayCombatFixtureBegin)=='function' and type(MineCome.GameplayCombatFixtureEnd)=='function','api_missing')
  p.started=System.GetCurrTime();p.last=p.started;require_true(finite(p.started) and owned_player(p),'identity_or_clock_missing')
  require_true(type(p.soul.HasBuffDebug)=='function' and type(p.soul.AddBuff)=='function' and type(p.soul.RemoveBuff)=='function' and type(p.soul.GetState)=='function' and type(p.actor.GetMaxHealth)=='function' and type(p.actor.IsDead)=='function','player_api_missing')
  p.maximum=p.actor:GetMaxHealth();p.before=p.soul:GetState('health');p.after=p.before
  require_true(finite(p.maximum) and p.maximum>0 and p.maximum<=1000000 and finite(p.before) and p.before==p.maximum and p.actor:IsDead()==false,'fresh_player_health_required')
  require_true(p.soul:HasBuffDebug(BUFF)==false,'buff_absent_baseline_unconfirmed')
  local pos=p.player:GetWorldPos();local d=p.actor:GetHeadDir()
  require_true(type(pos)=='table' and type(d)=='table' and finite(pos.x) and finite(pos.y) and finite(pos.z) and finite(d.x) and finite(d.y),'pose_invalid')
  local length=math.sqrt(d.x*d.x+d.y*d.y);require_true(length>.1,'view_vertical')
  p.spawn={x=pos.x+d.x/length*2,y=pos.y+d.y/length*2,z=pos.z}
  p.original_client_raw=rawget(p.player,'Client');p.original_client=p.player.Client
  require_true(p.original_client==nil or type(p.original_client)=='table','client_table_invalid')
  local original=p.original_client and p.original_client.OnHit
  require_true(original==nil or type(original)=='function','client_callback_invalid')
  p.client_copy={};for key,value in pairs(p.original_client or {})do p.client_copy[key]=value end
  p.client_copy.OnHit=function(target,hit,...)
   if target==p.player and not p.finished and owned_player(p) and owned_npc(p)then
    p.callback_count=p.callback_count+1
    local h=type(hit)=='table' and hit or {};local amount=finite(h.damage) and h.damage or nil
    local source=h.shooter==p.npc or h.shooterId==p.npc_id;local victim=h.target==p.player or h.targetId==p.player_id
    if source and victim and amount and amount>0 then p.matching_damage_callback=true end
    if #p.hits<8 then p.hits[#p.hits+1]={damage=amount,shooter_matches=source,target_matches=victim}end
   end
   if original then return original(target,hit,...)end
  end
  require_true(owned_player(p) and p.soul:HasBuffDebug(BUFF)==false,'baseline_changed')
  p.player.Client=p.client_copy;p.buff_attempted=true
  local instance=p.soul:AddBuff(BUFF)
  require_true(type(instance)=='userdata' or (type(instance)=='string' and #instance>0) or (finite(instance) and instance>0),'buff_instance_unknown')
  p.buff_instance=instance;require_true(schedule(p,200),'timer_unavailable')
 end)
 if not ok then cleanup(p,clean(why),false);return false,clean(why)end
 return true,'scheduled'
end
function MineCome.GameplayRetaliationEnd(run)
 local p=state.active
 if p then if p.run~=run then return false end;cleanup(p,'explicit_stop',false);return true end
 return state.last~=nil and state.last.run==run and state.last.finished
end
