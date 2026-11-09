# A real NPC, vanilla melee or bow impacts, and normal save/cleanup. No physical-input claim.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BundleDirectory,[string]$InstanceDirectory,[string]$GroundPatchFile,
 [string]$JavaHome='C:/Program Files/Java/jdk-24',[switch]$ProjectileCheck)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native combat check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
. (Join-Path $PSScriptRoot 'GameplayHudSessionGuard.ps1')
$context=Get-MineComeProbeContext
$installation=Get-MineComeGameplayInstallation -BundleDirectory $BundleDirectory -RequireUnarmed -Movement -Blocks -Chat
Assert-GameplayHudSessionUnused $context $installation.ToolsBin
$run=[guid]::NewGuid().ToString('N')
if(-not $InstanceDirectory){$InstanceDirectory=Join-Path $context.ProjectRoot ('runtime/gameplay/combat-native-'+$run)}
if(-not $GroundPatchFile){
 $capture=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch -WideWalking | Where-Object {$_ -isnot [string] -and $_.PSObject.Properties['GroundPatchFile']})
 if($capture.Count -ne 1){throw 'Native combat requires one actual terrain capture.'};$GroundPatchFile=$capture[0].GroundPatchFile
}
$probe=New-MineComeProbeRun $context 'gameplay-combat-fixture' (Join-Path $context.ProjectRoot 'kcd2/gameplay/combat_fixture.lua') 'GameplayCombatFixtureBegin'
$saved=$null;$attempted=$false;$removed=$false
try{
 $attempted=$true
 & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -GroundPatchFile $GroundPatchFile -Combat -CombatCheck -ProjectileCheck:$ProjectileCheck -CombatFixtureRun $run | ForEach-Object {
  if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
  Write-Host $_
 }
}finally{
 if($attempted){
  Invoke-MineComeProbeConsole $context ("#MineCome.GameplayCombatFixtureEnd('$run')")
  $until=[DateTime]::UtcNow.AddSeconds(2)
  do{
   Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeCombatFixtureFlush] $run')")
   $log=Read-MineComeProbeLog $context $probe.Offset
   $receipts=@(Get-MineComeProbeReceipts $log 'MineComeCombatFixture' $run)
   $removed=@($receipts|Where-Object {$_.event -ceq 'terminal' -and $_.result -ceq 'explicit_stop' -and $_.removed -eq $true -and $_.active -eq $false -and $_.path_restored -eq $true}).Count -gt 0
   if($removed){break};Start-Sleep -Milliseconds 50
  }while([DateTime]::UtcNow -lt $until)
  [IO.File]::WriteAllText((Join-Path $probe.Directory 'fresh-kcd.log'),$log)
  [ordered]@{schema=1;run=$run;removed=$removed;source_sha256=$probe.SourceHash;receipts=$receipts}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
 }
}
if(-not $removed){throw 'Native combat fixture cleanup was not confirmed.'}
if(-not $saved){throw 'Native combat session did not save successfully.'}
$s=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 32
$h=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 32
$v=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json -Depth 32
$f=$s.fixture;$c=$s.combat
if($v.result -cne 'passed' -or -not $v.normal_client_exit -or $h.Failure -or -not $h.ResourcesClosed -or -not $h.Combat.CleanupComplete){throw 'Native combat cleanup receipt failed.'}
if(-not $ProjectileCheck -and ($h.Combat.Damaged -ne 1 -or $h.Combat.Rejected -ne 0 -or $h.Combat.LastHit.result -cne 'damaged')){throw 'Native melee health receipt failed.'}
if($f.kind -cne 'minecome_native_combat_fixture_v1' -or $f.result -cne 'passed' -or $f.failure -or -not $f.actual_minecraft -or $f.synthetic_host -or $f.physical_native_keys_verified -or $f.position_writes_used -or $f.camera_writes_used -or $f.direct_health_inventory_entity_writes){throw 'Native combat fixture scope/identity differs.'}
foreach($flag in @('native_health_damage_verified','durability_verified','inventory_suppression_verified','native_walking_verified','render_pixels_verified')){if($f.$flag -ne $true){throw "Native combat capability missing: $flag"}}
if($f.inventory_native_eye_horizontal_limit -ne .08 -or $f.inventory_native_eye_horizontal_drift -lt 0 -or $f.inventory_native_eye_horizontal_drift -gt .08){throw 'Native inventory camera suppression was not verified.'}
if(-not $ProjectileCheck -and ($c.outgoing_hits -ne 1 -or $c.hit_ack -ne 1 -or $c.incoming_hurts -ne 0 -or $c.pending -or -not $c.cleanup_complete -or $c.server_applied_damage -ne 7 -or $h.Combat.LastHit.before -ne $f.native_health_before -or [Math]::Abs($h.Combat.LastHit.after-$f.native_health_after) -gt .01)){throw 'Native and vanilla damage evidence disagree.'}
foreach($capture in $f.images){if((Get-FileHash -LiteralPath (Join-Path $saved $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or $capture.metadata.world_id -cne $s.world_id -or -not $capture.metadata.PSObject.Properties['world_camera']){throw 'Native combat image identity differs.'}}
if($ProjectileCheck){
 $p=$c.projectiles;$native=$h.Combat.Projectiles;$impact=$native.LastImpact.reply
 if(-not $f.projectile_check -or -not $f.native_projectile_scenery_verified -or $p.impacts -ne 1 -or $p.scenery_hits -ne 1 -or $p.rejected -ne 0 -or $p.pending -or -not $p.cleanup_complete -or
  $native.Impacts -ne 1 -or $native.Scenery -ne 1 -or $native.Damaged -ne 1 -or $native.Rejected -ne 0 -or $native.Pending -or -not $native.CleanupComplete -or
  $impact.result -cne 'damaged' -or $impact.before -ne $f.native_health_before -or [Math]::Abs($impact.after-$f.native_health_after) -gt .01 -or
  $p.damage -le 0 -or [Math]::Abs($p.damage-$f.vanilla_damage) -gt .001 -or [Math]::Abs(($impact.before-$impact.after)/$f.native_max_health-$p.damage/20) -gt .02 -or
  $native.LastScenery.reply.result -cne 'scenery' -or $c.outgoing_hits -ne 0 -or $c.incoming_hurts -ne 0){throw 'Native scenery/NPC and vanilla projectile evidence disagree.'}
 $sceneCapture=@($f.images|Where-Object stage -CEQ 'scenery')[0]
 $sceneProjectiles=@($sceneCapture.metadata.projectiles)
 if($sceneProjectiles.Count -ne 1 -or $sceneCapture.metadata.projectile_render_count -ne 1 -or $sceneCapture.metadata.projectiles_truncated -or
  $sceneProjectiles[0].id.Replace('-','') -cne $native.LastScenery.reply.projectile -or $sceneProjectiles[0].type -cne 'minecraft:arrow' -or
  $sceneCapture.metadata.player_pixels -or $sceneCapture.metadata.rendered_world_blocks -ne 0 -or $sceneCapture.metadata.dropped_item_render_count -ne 0){throw 'Native scenery frame must isolate the exact contacted arrow.'}
 if($sceneCapture.world_file -cne 'native-combat-scenery-world.png' -or $sceneCapture.world_pixels -lt 1 -or $sceneCapture.world_depth_pixels -lt 1 -or $sceneCapture.metadata.projectile_render_count -lt 1 -or
  (Get-FileHash -LiteralPath (Join-Path $saved $sceneCapture.world_file)).Hash.ToLowerInvariant() -cne $sceneCapture.world_sha256){throw 'Native scenery arrow capture/depth proof differs.'}
}
$expectedCaptures=if($ProjectileCheck){'before|hit|scenery|inventory|walking|after'}else{'before|hit|inventory|walking|after'}
if(($f.images.stage -join '|') -cne $expectedCaptures){throw 'Native combat capture sequence incomplete.'}
$windowStart=[long]$f.native_composition_window_started_utc_ms;$windowEnd=[long]$f.native_composition_window_completed_utc_ms
if($windowStart -le 0 -or $windowEnd-$windowStart -lt 11000 -or $windowEnd-$windowStart -gt 14000){throw 'Native post-walk composition observation window differs.'}
$walkingCapture=@($f.images|Where-Object stage -CEQ 'walking')[0];$afterCapture=@($f.images|Where-Object stage -CEQ 'after')[0]
if($walkingCapture.metadata.captured_utc_ms -gt $windowStart -or $afterCapture.metadata.captured_utc_ms -lt $windowEnd){throw 'Composition observation does not follow the actual walking capture.'}
# host_depth has no payload UTC. ReShade prefixes local HH:mm:ss:fff; anchor
# the date/offset to this fixture window and choose its nearest calendar day.
# This also handles a bounded check that crosses local midnight.
$anchor=[DateTimeOffset]::FromUnixTimeMilliseconds($windowStart).ToLocalTime()
$depth=@(foreach($line in [IO.File]::ReadLines((Join-Path $saved 'native-hud.log'))){
 if($line -match '^(?<clock>[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{3}) .*\[MineComeHudInput\] (?<json>\{.*\})$'){
  $clock=$Matches['clock'];$record=$Matches['json']|ConvertFrom-Json
  if($record.PSObject.Properties['event'] -and $record.event -ceq 'host_depth' -and $record.run -ceq $s.run){
   $time=[TimeSpan]::ParseExact($clock,'hh\:mm\:ss\:fff',[Globalization.CultureInfo]::InvariantCulture)
   $utc=@(foreach($day in @(-1,0,1)){[DateTimeOffset]::new($anchor.Date.AddDays($day).Add($time),$anchor.Offset).ToUnixTimeMilliseconds()})|Sort-Object {[Math]::Abs($_-$windowStart)}|Select-Object -First 1
   [pscustomobject]@{utc_ms=[long]$utc;composited=[long]$record.composited;reprojected=[long]$record.reprojected}
  }
 }
})
$window=@($depth|Where-Object {$_.utc_ms -ge $windowStart -and $_.utc_ms -le $windowEnd})
if($window.Count -lt 2){throw 'Native post-walk composition window lacks two counter samples.'}
for($i=1;$i -lt $window.Count;$i++){if($window[$i].utc_ms -le $window[$i-1].utc_ms -or $window[$i].composited -lt $window[$i-1].composited -or $window[$i].reprojected -lt $window[$i-1].reprojected){throw 'Native post-walk composition counters regressed.'}}
$compositedDelta=$window[-1].composited-$window[0].composited;$reprojectedDelta=$window[-1].reprojected-$window[0].reprojected
if($compositedDelta -lt 1 -or $reprojectedDelta -lt 1){throw 'Native composition/reprojection stopped before the post-walk observation.'}
[ordered]@{schema=1;kind='minecome_native_combat_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;fixture_run=$run;fixture_removed=$removed;
 actual_minecraft=$true;actual_native_npc=$true;scripted_guest_input=$true;physical_native_input_verified=$false;reciprocal_native_damage_verified=$false;hostile_free_aim_verified=$false;
 projectile_check=[bool]$ProjectileCheck;native_damage_receipt=$(if($ProjectileCheck){$h.Combat.Projectiles.LastImpact.reply}else{$h.Combat.LastHit});projectiles=$h.Combat.Projectiles;vanilla_damage=$f.vanilla_damage;walk_distance=$f.walk_distance;fixture_evidence=$probe.Directory;
 native_composited_frames=($depth.composited|Measure-Object -Maximum).Maximum;native_reprojected_frames=($depth.reprojected|Measure-Object -Maximum).Maximum;
 native_post_walk_composited_frames=$compositedDelta;native_post_walk_reprojected_frames=$reprojectedDelta;native_post_walk_counter_samples=$window;
 inventory_native_eye_horizontal_drift=$f.inventory_native_eye_horizontal_drift}|
 ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $saved 'native-combat-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_COMBAT_PASS evidence=$saved"
