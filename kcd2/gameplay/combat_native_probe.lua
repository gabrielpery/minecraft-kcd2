-- SPDX-License-Identifier: GPL-3.0-or-later
-- Explicit, bounded real-engine check using the production combat path and
-- official owned NPC fixture. Loading this source does not execute it.
MineCome=MineCome or {}
function MineCome.GameplayCombatNativeProbe(run,projectile_check)
 local result={ok=false,reason='not_started',projectile_check=projectile_check==true}
 local function require_true(ok,reason)if not ok then error(reason)end end
 local ok,err=pcall(function()
  local pos=player:GetWorldPos();local forward=player.actor:GetHeadDir()
  local horizontal=math.sqrt(forward.x*forward.x+forward.y*forward.y)
  require_true(horizontal>.1,'native_view_vertical')
  local spawned,why=MineCome.GameplayCombatFixtureBegin(run,10000,pos.x+forward.x/horizontal*2,pos.y+forward.y/horizontal*2,pos.z)
  require_true(spawned,'fixture_'..tostring(why))
  local begun,reason=MineCome.GameplayMovementBegin(run,10000,pos.x-5,pos.x+5,pos.y-5,pos.y+5,pos.z-2,pos.z+3,false,true)
  require_true(begun,'movement_'..tostring(reason))
  require_true(MineCome.GameplayCombatBegin(run,10000,16,8),'combat_begin')
  require_true(MineCome.GameplayCombatSample(run,1),'combat_sample')
  local p=MineCome._gameplay_combat.active;local a=p and p.samples[1].actors[1]
  local fixture=MineCome._gameplay_combat_fixture.active
  require_true(a and fixture and a.entity==fixture.entity,'fixture_target_identity')
  local view=MineCome.GameplayMovementCombatView(run);require_true(view~=nil,'native_view_unavailable')
  -- Intersect the conservative proxy exactly as Minecraft will. The production
  -- handler independently intersects the real rectangle and traces scenery.
  local lo={x=a.x-a.width/2,y=a.y-a.width/2,z=a.z}
  local hi={x=a.x+a.width/2,y=a.y+a.width/2,z=a.z+a.height}
  local entry,exit=0,4.5
  for _,axis in ipairs({'x','y','z'})do local o,d=view.origin[axis],view.direction[axis]
   if math.abs(d)<.00000001 then require_true(o>=lo[axis] and o<=hi[axis],'native_ray_miss')
   else local first,last=(lo[axis]-o)/d,(hi[axis]-o)/d;if first>last then first,last=last,first end
    entry=math.max(entry,first);exit=math.min(exit,last);require_true(entry<=exit,'native_ray_miss')
   end
  end
  require_true(entry>=.05 and entry<=4.5,'native_ray_reach')
  local origin=view.origin;local target={x=origin.x+view.direction.x*entry,y=origin.y+view.direction.y*entry,z=origin.z+view.direction.z*entry}
  result.before=a.entity.soul:GetState('health');result.maximum=a.entity.actor:GetMaxHealth()
  require_true(MineCome.GameplayCombatHit(run,1,1,1,.35,origin.x,origin.y,origin.z,target.x,target.y,target.z),'native_hit_call')
  result.after=a.entity.soul:GetState('health');result.hit_result=p.last_hit and p.last_hit.result
  require_true(result.hit_result=='damaged','native_hit_'..tostring(result.hit_result))
  require_true(math.abs(result.after-math.max(0,result.before-result.maximum*.35))<.001,'native_health_delta')
  require_true(MineCome.GameplayCombatHit(run,1,1,1,.35,origin.x,origin.y,origin.z,target.x,target.y,target.z),'duplicate_ack')
  result.duplicate_after=a.entity.soul:GetState('health');require_true(result.duplicate_after==result.after,'native_hit_replayed')
  if result.projectile_check then
   local arrow='11111111111111111111111111111111'
   local endpoint={x=origin.x+view.direction.x*3,y=origin.y+view.direction.y*3,z=origin.z+view.direction.z*3}
   require_true(MineCome.GameplayProjectileTrace(run,1,arrow,1,origin.x,origin.y,origin.z,endpoint.x,endpoint.y,endpoint.z),'projectile_trace_call')
   local traced=p.projectile_last;local trajectory=p.projectiles[arrow]
   require_true(traced and traced.result=='actor' and trajectory and trajectory.collision and trajectory.collision.actor.entity==a.entity,'projectile_native_actor_contact')
   local actor_token=trajectory.collision.actor.token
   result.projectile_before=a.entity.soul:GetState('health')
   require_true(MineCome.GameplayProjectileImpact(run,2,arrow,1,actor_token,.2),'projectile_impact_call')
   result.projectile_after=a.entity.soul:GetState('health')
   require_true(p.projectile_last.result=='damaged' and math.abs(result.projectile_after-math.max(0,result.projectile_before-result.maximum*.2))<.001,'projectile_native_damage')
   require_true(MineCome.GameplayProjectileImpact(run,2,arrow,1,actor_token,.2),'projectile_duplicate_ack')
   result.projectile_duplicate_after=a.entity.soul:GetState('health')
   require_true(result.projectile_duplicate_after==result.projectile_after,'projectile_damage_replayed')
   result.projectile_damage_verified=true
   -- Scripted contiguous native segments verify the real scenery binding, not
   -- Minecraft ballistics. The coupled fixture separately shoots actual arrows.
   -- Launch beside the player, then sample downward before reaching the NPC;
   -- the player is excluded by the same production trace implementation.
   local scenery_arrow='22222222222222222222222222222222'
   local from={x=origin.x+view.direction.x*.25,y=origin.y+view.direction.y*.25,z=origin.z+view.direction.z*.25}
   require_true(MineCome.GameplayProjectileTrace(run,3,scenery_arrow,1,origin.x,origin.y,origin.z,from.x,from.y,from.z),'projectile_scenery_launch')
   require_true(p.projectile_last.result=='clear','projectile_scenery_launch_obstructed')
   require_true(MineCome.GameplayProjectileTrace(run,4,scenery_arrow,2,from.x,from.y,from.z,from.x,from.y,from.z-3.5),'projectile_scenery_trace')
   require_true(p.projectile_last.result=='scenery','projectile_native_ground_missing')
   result.projectile_scenery_verified=true
  end
  local movement=MineCome._gameplay_movement.active
  require_true(movement and movement.writes==0 and not movement.camera_owned,'probe_moved_native_player')
  result.ok=true;result.reason=result.projectile_check and 'native_melee_projectile_and_scenery_verified' or 'native_melee_and_dedup_verified'
 end)
 if not ok then result.reason=tostring(err):gsub('[^a-zA-Z0-9_ :./-]','_')end
 pcall(MineCome.GameplayCombatEnd,run);pcall(MineCome.GameplayMovementEnd,run);pcall(MineCome.GameplayCombatFixtureEnd,run)
 local function n(v)return type(v)=='number' and tostring(v) or 'null'end
 System.LogAlways('[MineComeCombatNativeProbe] {"schema":1,"run":"'..run..'","ok":'..tostring(result.ok)..',"reason":"'..result.reason..'","before":'..n(result.before)..',"maximum":'..n(result.maximum)..',"after":'..n(result.after)..',"duplicate_after":'..n(result.duplicate_after)..',"projectile_check":'..tostring(result.projectile_check)..',"projectile_damage_verified":'..tostring(result.projectile_damage_verified==true)..',"projectile_scenery_verified":'..tostring(result.projectile_scenery_verified==true)..',"projectile_before":'..n(result.projectile_before)..',"projectile_after":'..n(result.projectile_after)..',"projectile_duplicate_after":'..n(result.projectile_duplicate_after)..',"actual_minecraft_projectile":false}')
 return result.ok,result.reason
end
