-- SPDX-License-Identifier: GPL-3.0-or-later
-- Optional isolated test actor. Exact official Scripts/Debug/PathfindDebugUtils
-- 30-58 supplies the NPC shared soul and XGenAIModule.SpawnEntity schema.
-- Hostile opt-in: CombatDebug.lua:539-544/987 (combatEnemy_3), 222-302
-- (novice profile), 675/1088 (unarmed preset). Its npc_basic brain and hostile
-- player faction are declared in soul__test.xml:381 / FactionTree__autotests.xml:19-24.
-- Armed presets: CombatDebug.lua:663-675, weapon_preset.xml:1371-1376/2500-2502.
-- Ranged selection/draw: CombatDebug.lua:1119-1130; inventory readback follows
-- Scripts/Utils/ItemUtils.lua:118. Bow stat22 values follow skill profile4,
-- exceeding the official bow_d item's strength19/agility14 requirements.
-- Owns only the unique newly-created actor, never existing NPCs/player state.
MineCome=MineCome or {}
MineCome._gameplay_combat_fixture=MineCome._gameplay_combat_fixture or {}
local state=MineCome._gameplay_combat_fixture
local configurations={
 hostile={preset='10101010-c8cb-81dd-40f1-2f0554804f83',max_distance=5},
 hostile_sword={preset='9b042396-e438-4a79-ab9d-138c12cda0a6',weapon='9e31a288-7de0-4c0d-81cd-5cf00548d2d5',max_distance=5},
 hostile_bow={preset='540bab62-09ea-41a9-bc44-e30a8cf98d56',weapon='b4a0b9c9-bf92-4cce-ad43-f20f57c892b9',ammo='ad6f0f01-aec4-44d1-982c-1210eb01b74a',melee={'65a211bd-2c7e-40a8-984f-66c8730444e4','55f81ddb-7c17-41c5-a17c-c9948766c1c8'},min_distance=5.5,max_distance=8},
 -- CombatDebug.lua:676 and weapon_preset.xml:426-431: crossbow +65 bolts.
 hostile_crossbow={preset='1a5e4d64-f240-4596-b0c6-49e11c047468',weapon='b77f912a-042b-47ca-8f42-5fddbcad3763',ammo='166b4c7b-5e17-48db-bf0d-02f24eacdcbf',melee={'9aa773b1-ede0-4ff5-bbd8-2595b36c8a1a','a8eb10aa-84eb-416f-8ed2-46d909a26552'},min_distance=5.5,max_distance=8}
}
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function vector(v)return type(v)=='table' and finite(v.x) and finite(v.y) and finite(v.z)end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
local function emit(p,event,result)
 local equipment=''
 if p.configuration then
  equipment=',"weapon_preset":"'..p.configuration.preset..'"'
  if p.configuration.weapon then equipment=equipment..',"weapon_item":"'..p.configuration.weapon..'","weapon_count":'..tostring(p.weapon_count or 0) end
  if p.configuration.ammo then equipment=equipment..',"ammo_item":"'..p.configuration.ammo..'","ammo_count":'..tostring(p.ammo_count or 0)..',"ammo_equip_requested":'..tostring(p.ammo_equip_requested==true)..',"ranged_set_requested":'..tostring(p.ranged_set_requested==true)..',"melee_items_removed":'..tostring(p.melee_items_removed==true) end
 end
 System.LogAlways('[MineComeCombatFixture] {"schema":1,"run":"'..p.run..'","mode":"'..(p.mode or 'passive')..'","event":"'..event..'","result":"'..result..'","active":'..tostring(state.active==p)..',"removed":'..tostring(p.removed==true)..',"path_restored":'..tostring(p.path_restored~=false)..equipment..'}')
end
local function owned(p)
 return p.entity and System.GetEntity(p.id)==p.entity and System.GetEntityByName(p.name)==p.entity and p.entity.id==p.id and p.entity.soul==p.soul
end
local function gone(p)
 return (not p.entity or System.GetEntity(p.id)==nil) and System.GetEntityByName(p.name)==nil and not p.spawn_unknown
end
local function finish(p,removed)
 p.removed=removed;p.stopped=true;p.stopping=false
 if p.timer then Script.KillTimer(p.timer);p.timer=nil end;p.timer_data=nil
 if p.path_wrapper then
  if PathfindDebugUtils==p.path_table and p.path_table.FindDataTable==p.path_wrapper then p.path_table.FindDataTable=p.path_original end
  p.path_restored=PathfindDebugUtils==p.path_table and p.path_table.FindDataTable==p.path_original
 else p.path_restored=true end
 if state.active==p then state.active=nil end;state.last=p
 local complete=removed and p.path_restored
 emit(p,'terminal',complete and p.reason or 'cleanup_unconfirmed');return complete
end
local function cleanup_poll(p)
 if gone(p)then return finish(p,true)end
 if not owned(p) or p.cleanup_polls<=0 then return finish(p,false)end
 p.cleanup_polls=p.cleanup_polls-1
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,50,'MineCome_CombatFixtureCleanupTick',data,true)
 if not ok or id==nil or id==false then return finish(p,false)end;p.timer=id;p.timer_data=data;return true
end
function MineCome_CombatFixtureCleanupTick(data)
 local p=type(data)=='table' and data.owner
 if not p or state.active~=p or not p.stopping or p.timer_data~=data then return end
 p.timer=nil;p.timer_data=nil;cleanup_poll(p)
end
local function stop(p,reason)
 if p.stopped then
  -- A prior source version may already have reported an immediate readback
  -- failure. Refresh only disappearance; never issue RemoveEntity twice.
  if not p.removed and gone(p)then p.reason=reason;return finish(p,true)end
  return p.removed
 end
 if p.stopping then return true end
 p.stopping=true;p.reason=reason;p.cleanup_polls=40
 if p.timer then Script.KillTimer(p.timer);p.timer=nil end;p.timer_data=nil
 if gone(p)then return finish(p,true)end
 if not owned(p)then return finish(p,false)end
 -- Native deletion is deferred until an engine update. Issue it exactly once,
 -- retain the original references, and publish terminal only after readback.
 p.remove_requested=true;pcall(System.RemoveEntity,p.id)
 return cleanup_poll(p)
end
function MineCome_CombatFixtureExpire(data)
 local p=type(data)=='table' and data.owner;if p and state.active==p and p.timer_data==data then p.timer=nil;stop(p,'expired')end
end
function MineCome.GameplayCombatFixtureBegin(run,duration_ms,x,y,z,mode)
 if mode==nil then mode='passive'end
 local configuration=configurations[mode]
 if mode~='passive' and not configuration then return false,'invalid_fixture_mode'end
 if type(run)~='string' or #run~=32 or not run:match('^[0-9a-f]+$') or not finite(duration_ms) or duration_ms~=math.floor(duration_ms) or duration_ms<1000 or duration_ms>120000 or not vector({x=x,y=y,z=z}) then return false,'invalid_fixture'end
 if state.active then return false,'fixture_owned'end
 if not player or type(player.GetWorldPos)~='function' or type(player.GetAngles)~='function' or not XGenAIModule or type(XGenAIModule.SpawnEntity)~='function' or not System or type(System.GetEntity)~='function' or type(System.GetEntityByName)~='function' or type(System.RemoveEntity)~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' then return false,'fixture_api_missing'end
 if mode=='passive' and (type(PathfindDebugUtils)~='table' or type(PathfindDebugUtils.FindDataTable)~='function' or type(PathfindDebugUtils.GetNPCSpeed)~='function') then return false,'fixture_path_api_missing'end
 if configuration and (type(CombatDebug)~='table' or type(CombatDebug.SetSkillProfile)~='function')then return false,'fixture_combat_api_missing'end
 local position={x=x,y=y,z=z};local feet=player:GetWorldPos()
 if not vector(feet) or distance(position,feet)>(configuration and configuration.max_distance or 5) then return false,'fixture_too_far'end
 if configuration and configuration.min_distance and distance(position,feet)<configuration.min_distance then return false,'fixture_too_close'end
 local rotation=player:GetAngles();if not vector(rotation)then return false,'fixture_rotation_invalid'end
 local p={run=run,mode=mode,configuration=configuration,name='MineComeCombat_'..run..'_fixture',position=position,rotation=rotation}
 if mode=='passive' then p.path_table=PathfindDebugUtils;p.path_original=PathfindDebugUtils.FindDataTable
 else p.combat_table=CombatDebug;p.set_profile=CombatDebug.SetSkillProfile end
 if System.GetEntityByName(p.name)then return false,'fixture_name_occupied'end
 state.active=p;local data={owner=p};local ok,timer=pcall(Script.SetTimerForFunction,duration_ms,'MineCome_CombatFixtureExpire',data,true)
 if not ok or timer==nil or timer==false then state.active=nil;return false,'fixture_timer_missing'end;p.timer=timer;p.timer_data=data
 local params={ClassName='NPC',Name=p.name,Properties={},Pos=position,Rot=rotation}
 if mode=='passive' then
  params.SharedSoulGuid='88bee0ec-f164-4282-ae1e-6576a76b9bac';params.PercepDestinationrObjectAI=false;params.PerceptibleObjectAI=false
 else
  params.SharedSoulGuid='d2a3c045-2d43-491c-80a4-96137fcb99de'
  -- Official CombatDebug faces new enemies toward the player (1004-1007).
  params.Rot={x=0,y=0,z=rotation.z+math.pi}
 end
 local spawned,result=pcall(XGenAIModule.SpawnEntity,params)
 local entity=spawned and type(result)=='table' and result or nil
 if spawned and (type(result)=='userdata' or (finite(result) and result>0 and result==math.floor(result)))then entity=System.GetEntity(result)end
 local named=System.GetEntityByName(p.name)
 -- SpawnEntity may create the actor and then fail/return an unexpected shape.
 -- Claim only a newly-created, exact-name NPC whose ID lookup agrees, so it can
 -- be cleaned up; do not report success for an unverified native return value.
 if type(named)=='table' and named.id~=nil and named~=player and named.class=='NPC' and type(named.actor)=='table' and type(named.soul)=='table' and type(named.GetName)=='function' and named:GetName()==p.name and System.GetEntity(named.id)==named then
  p.entity=named;p.id=named.id;p.soul=named.soul
 end
 if not spawned or not p.entity or entity~=p.entity then
  p.spawn_unknown=named~=nil and p.entity==nil;stop(p,'spawn_unconfirmed');return false,'spawn_unconfirmed'
 end
 p.entity=entity;p.id=entity.id;p.soul=entity.soul
 if type(p.soul)~='table' or type(entity.actor)~='table' then stop(p,'actor_unavailable');return false,'actor_unavailable'end
 if configuration then
  if not owned(p) or CombatDebug~=p.combat_table or p.combat_table.SetSkillProfile~=p.set_profile or type(p.soul.SetStatLevelDebug)~='function' or type(p.soul.SetSkillLevelDebug)~='function' or type(entity.actor.EquipWeaponPreset)~='function' then
   stop(p,'fixture_combat_api_missing');return false,'fixture_combat_api_missing'
  end
  if configuration.weapon and (type(entity.inventory)~='table' or type(entity.inventory.GetCountOfClass)~='function' or type(entity.human)~='table' or type(entity.human.DrawWeapon)~='function' or (configuration.ammo and (type(entity.human.ToggleWeaponSet)~='function' or type(entity.inventory.DeleteItemOfClass)~='function' or type(entity.inventory.FindItem)~='function' or type(entity.actor.EquipInventoryItem)~='function')))then
   stop(p,'fixture_weapon_api_missing');return false,'fixture_weapon_api_missing'
  end
  local configured=pcall(function()
   p.set_profile(entity,1)
   if not owned(p)then error('fixture_owner_changed')end
   if configuration.ammo then
    p.soul:SetStatLevelDebug('strength',22);p.soul:SetStatLevelDebug('agility',22);p.soul:SetSkillLevelDebug('marksmanship',22)
    -- CombatDebug.lua:1096 uses courage30 for its explicit brave NPC option.
    p.soul:SetStatLevelDebug('courage',30)
   end
   entity.actor:EquipWeaponPreset(configuration.preset)
   if not owned(p)then error('fixture_owner_changed')end
   if configuration.weapon then
    p.weapon_count=entity.inventory:GetCountOfClass(configuration.weapon)
    if not finite(p.weapon_count) or p.weapon_count<1 or p.weapon_count>1000 then p.weapon_count=nil;error('fixture_weapon_missing')end
    if configuration.ammo then
     p.ammo_count=entity.inventory:GetCountOfClass(configuration.ammo)
     if not finite(p.ammo_count) or p.ammo_count<1 or p.ammo_count>1000 then p.ammo_count=nil;error('fixture_ammo_missing')end
     -- Official ranged presets also supply a melee weapon and shield. Remove those
     -- two newly-created items only, so native weapon automation cannot choose
     -- melee instead of the ranged attack this fixture is intended to verify.
     -- Official C_ScriptBindInventory::DeleteItemOfClass(classIdText,count).
     for _,class in ipairs(configuration.melee)do
      if not owned(p)then error('fixture_owner_changed')end
      local count=entity.inventory:GetCountOfClass(class)
      if not finite(count) or count<0 or count>1 then error('fixture_melee_count_invalid')end
      if count>0 then entity.inventory:DeleteItemOfClass(class,count)end
      if entity.inventory:GetCountOfClass(class)~=0 then error('fixture_melee_removal_failed')end
     end
     p.melee_items_removed=true
     -- Explicit ammo equip follows CombatDebug.lua:73-79. Inventory.FindItem
     -- resolves the exact stack supplied by our own preset (official SDK).
     local ammo=entity.inventory:FindItem(configuration.ammo)
     if ammo==nil or ammo==false or ammo==0 or __null~=nil and ammo==__null then error('fixture_ammo_instance_missing')end
     entity.actor:EquipInventoryItem(ammo);p.ammo_equip_requested=true
     entity.human:ToggleWeaponSet(1);p.ranged_set_requested=true
    end
    if not owned(p)then error('fixture_owner_changed')end
    entity.human:DrawWeapon()
   end
  end)
  if not configured or not owned(p)then stop(p,'fixture_combat_setup_failed');return false,'fixture_combat_setup_failed'end
  -- Native npc_basic perception/combat remains active. No path override or
  -- forced attack is installed; actual retaliation must be observed separately.
  emit(p,'begin','spawned');return true
 end
 if PathfindDebugUtils~=p.path_table or p.path_table.FindDataTable~=p.path_original then stop(p,'fixture_path_changed');return false,'fixture_path_changed'end
 -- Official test_pathfollower_dummy.xml asks this Lua function for its Move
 -- destination after3s. Pin only our fixture's destination to its own spawn;
 -- other test actors retain their original behavior and global Data untouched.
 p.path_wrapper=function(entity_id)
  if entity_id==p.id and owned(p)then return{Pos={x=p.position.x,y=p.position.y,z=p.position.z},Rot={x=p.rotation.x,y=p.rotation.y,z=p.rotation.z}}end
  return p.path_original(entity_id)
 end
 p.path_table.FindDataTable=p.path_wrapper;p.path_restored=false
 emit(p,'begin','spawned');return true
end
function MineCome.GameplayCombatFixtureEnd(run)
 local p=state.active
 if not p then if state.last and state.last.run==run then
  p=state.last;if not p.removed and gone(p)then p.reason='explicit_stop';return finish(p,true)end
  emit(p,'terminal',p.removed and p.path_restored~=false and 'explicit_stop' or 'cleanup_unconfirmed');return p.removed and p.path_restored~=false
 end;return false,'fixture_missing'end
 if p.run~=run then return false,'fixture_owned'end;return stop(p,'explicit_stop')
end
