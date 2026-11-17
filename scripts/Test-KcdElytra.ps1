# Scripted vanilla Elytra through the live KCD camera/HUD session; no physical input claim.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(Mandatory,ParameterSetName='Live')][string]$BundleDirectory,[Parameter(Mandatory,ParameterSetName='Live')][string]$InstanceDirectory,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native Elytra check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$saved=$null
if($PSCmdlet.ParameterSetName -ceq 'Verify'){$saved=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path}
else{
 & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -WorldBlocks -ElytraCheck -InitialTerrainRadius 1 | ForEach-Object {
  if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
  Write-Host $_
 }
}
if(-not $saved){throw 'Native Elytra did not produce a saved session.'}
$s=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 30
$hostProof=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 30
$native=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json
$f=$s.fixture;$movement=$s.movement
if($native.kind -cne 'minecome_gameplay_kcd_session_v1' -or $native.elytra_check -ne $true -or
 $native.run -cne $s.run -or $hostProof.Terminal.run -cne $s.run -or $f.world_id -cne $s.world_id -or
 $f.kind -cne 'minecome_gameplay_elytra_fixture_v1' -or $f.mode -cne 'elytra-native' -or $f.result -cne 'passed' -or $f.failure){throw 'Native Elytra receipt identity/result differs.'}
foreach($flag in @('creative_takeoff_verified','glide_verified','glide_pose_verified','inventory_hold_verified','glide_resumed_verified','gliding_save_verified')){
 if($f.$flag -isnot [bool] -or -not $f.$flag){throw "Missing native Elytra capability: $flag"}
}
if(-not $f.actual_minecraft -or $f.standalone_scripted -or -not $f.live_kcd_connected -or -not $f.native_camera_preserved -or
 $f.native_input_verified -or $f.live_kcd_verified -or $f.scripted_view_writes -ne 0 -or
 $f.direct_command_api_used -or $f.ability_writes_used -or $f.position_writes_used -or $f.glide_flag_writes_used -or
 $f.game_mode -cne 'survival' -or -not $s.flight_enabled -or $f.glide_ticks -lt 10 -or $f.inventory_ticks -lt 10 -or
 $f.max_altitude -lt 3 -or $f.health -le 0 -or -not $f.server_gliding){throw 'Native Elytra did not use live camera input and authoritative vanilla flight.'}
foreach($command in @('/item replace entity @s armor.chest with minecraft:elytra','/gamemode survival')){
 if($command -cnotin @($f.submitted_commands)){throw "Missing vanilla chat command: $command"}
}
foreach($point in @('glide_started','held_inventory','native_resumed')){
 $p=$f.points.$point
 if(-not $p.gliding -or $p.flying -or $p.grounded -or [Math]::Abs([double]$p.eye_height-.4) -gt .0001){throw "Missing actual prone glide pose: $point"}
}
$displacement=[Math]::Sqrt([Math]::Pow($f.points.native_resumed.x-$f.points.glide_started.x,2)+[Math]::Pow($f.points.native_resumed.y-$f.points.glide_started.y,2)+[Math]::Pow($f.points.native_resumed.z-$f.points.glide_started.z,2))
if($displacement -lt .03){throw 'Actual Elytra did not travel between start and inventory resume.'}
if($movement.failure -or $movement.world_id -cne $s.world_id -or -not $movement.flight_enabled -or
 -not $movement.cleanup_complete -or -not $movement.controls_released -or -not $movement.client_collision_released -or -not $movement.server_collision_released -or
 -not $movement.ground_cells_air -or -not $movement.terrain_cells_valid -or -not $movement.resume_checkpoint_present -or
 -not $movement.resume_checkpoint.gliding -or $movement.resume_checkpoint.flying -or $movement.resume_checkpoint.falling -or
 $s.blocks.failure -or -not $s.blocks.cleanup_complete){throw 'Native Elytra save/collision cleanup differs.'}
$pose=Get-Content -LiteralPath (Join-Path $saved 'gameplay-pose.json') -Raw|ConvertFrom-Json
if($pose.kind -cne 'minecome_gameplay_pose_v1' -or $pose.run -cne $s.run -or $pose.world_id -cne $s.world_id -or
 -not $pose.gliding -or [Math]::Abs([double]$pose.eyeHeight-.4) -gt .0001){throw 'Final Elytra pose publication differs.'}
if($native.result -cne 'passed' -or -not $native.normal_client_exit -or $hostProof.Failure -or -not $hostProof.ResourcesClosed -or
 $hostProof.Terminal.result -cne 'explicit_stop' -or $hostProof.Terminal.active -or -not $hostProof.Terminal.timers_cancelled -or
 -not $hostProof.Terminal.camera_override_changed -or -not $hostProof.Terminal.camera_restored -or -not $hostProof.Terminal.body_restore_dispatched -or
 $hostProof.Terminal.body_hidden -or $hostProof.ViewCount -lt 5 -or $hostProof.Terminal.applied_seq -le 1 -or $hostProof.Terminal.writes -lt 1){throw 'Native Elytra camera/movement/cleanup proof incomplete.'}
$view=$hostProof.LastView
if($view.run -cne $s.run -or $view.event -cne 'view' -or $view.result -cne 'sampled' -or -not $view.camera_basis_valid -or
 $view.perspective -ne 0 -or [Math]::Abs(($view.eye.z-$view.player.z)-.4) -gt .0001 -or
 [Math]::Abs($view.eye.x-$view.player.x) -gt .0001 -or [Math]::Abs($view.eye.y-$view.player.y) -gt .0001 -or
 [Math]::Abs($view.camera.z-$view.eye.z) -gt .03 -or [Math]::Abs($view.camera.x-$view.eye.x) -gt .03 -or [Math]::Abs($view.camera.y-$view.eye.y) -gt .03){throw 'Native readback did not acknowledge the Minecraft glide eye.'}
$start=[long]$f.native_elytra_started_utc_ms;$end=[long]$f.native_elytra_completed_utc_ms
if($start -le 0 -or $end-$start -lt 11000 -or $end-$start -gt 120000){throw 'Native Elytra dwell is missing or outside its bounded duration.'}
$nativeLog=Join-Path $saved 'native-hud.log'
$days=@([DateTimeOffset]::FromUnixTimeMilliseconds($start).LocalDateTime.Date,[DateTimeOffset]::FromUnixTimeMilliseconds($end).LocalDateTime.Date)|Select-Object -Unique
$depthSamples=@(foreach($line in [IO.File]::ReadLines($nativeLog)){
 if($line -match '^(\d{2}:\d{2}:\d{2}:\d{3}).*\[MineComeHudInput\] (\{.*\})$'){
  $time=$Matches[1];$record=$Matches[2]|ConvertFrom-Json
  if($record.PSObject.Properties['event'] -and $record.event -ceq 'host_depth' -and $record.run -ceq $s.run){
   $clock=[DateTime]::ParseExact($time,'HH:mm:ss:fff',[Globalization.CultureInfo]::InvariantCulture).TimeOfDay
   foreach($day in $days){
    $utc=[TimeZoneInfo]::ConvertTimeToUtc([DateTime]::SpecifyKind($day.Add($clock),[DateTimeKind]::Unspecified),[TimeZoneInfo]::Local)
    $ms=[DateTimeOffset]::new($utc).ToUnixTimeMilliseconds()
    if($ms -ge $start -and $ms -le $end){[pscustomobject]@{utc_ms=$ms;composited=[long]$record.composited;reprojected=[long]$record.reprojected;considered=[long]$record.considered};break}
   }
  }
 }
})
if($depthSamples.Count -lt 2){throw 'Missing two native world-pass samples during the Elytra/inventory window.'}
for($i=1;$i -lt $depthSamples.Count;$i++){
 if($depthSamples[$i].utc_ms -lt $depthSamples[$i-1].utc_ms -or $depthSamples[$i].composited -lt $depthSamples[$i-1].composited -or $depthSamples[$i].reprojected -lt $depthSamples[$i-1].reprojected){throw 'Native compositor samples regressed.'}
}
$composited=$depthSamples[-1].composited-$depthSamples[0].composited
$reprojected=$depthSamples[-1].reprojected-$depthSamples[0].reprojected
if($composited -lt 1 -or $reprojected -lt 1){throw 'Native world composition did not advance during Elytra/inventory.'}
[ordered]@{schema=1;kind='minecome_native_elytra_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;
 actual_minecraft=$true;scripted_guest_input=$true;live_kcd_camera_acknowledged=$true;physical_native_keys_verified=$false;
 fixture_camera_writes_used=$false;ability_writes_used=$false;position_writes_used=$false;glide_flag_writes_used=$false;
 native_glide_eye_height=($view.eye.z-$view.player.z);minecraft_glide_ticks=$f.glide_ticks;minecraft_glide_displacement=$displacement;
 inventory_hold_verified=$true;glide_resumed_verified=$true;gliding_checkpoint_saved=$true;steve_pose_visually_verified=$false;
 native_composited_during_elytra=$composited;native_reprojected_during_elytra=$reprojected;native_depth_samples=$depthSamples;
 native_log_sha256=(Get-FileHash -LiteralPath $nativeLog).Hash.ToLowerInvariant();normal_client_exit=$native.normal_client_exit;
 camera_restored=$hostProof.Terminal.camera_restored;body_restored=$hostProof.Terminal.body_restore_dispatched}|
 ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $saved 'native-elytra-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_ELYTRA_PASS evidence=$saved"
