# Real vanilla death/button respawn through live KCD camera/relocation; scripted guest input.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(Mandatory,ParameterSetName='Live')][string]$BundleDirectory,[Parameter(Mandatory,ParameterSetName='Live')][string]$InstanceDirectory,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native respawn check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$saved=$null
if($PSCmdlet.ParameterSetName -ceq 'Verify'){$saved=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path}
else{
 & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -WorldBlocks -RespawnCheck | ForEach-Object {
  if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
  Write-Host $_
 }
}
if(-not $saved){throw 'Native respawn did not produce a saved session.'}
$s=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 30
$hostProof=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 30
$native=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json
$ackFile=Join-Path $saved 'respawn-ack.json';$ack=Get-Content -LiteralPath $ackFile -Raw|ConvertFrom-Json
$f=$s.fixture;$m=$s.movement;$r=$s.respawn
if($native.kind -cne 'minecome_gameplay_kcd_session_v1' -or -not $native.respawn_check -or
 $native.run -cne $s.run -or $hostProof.Terminal.run -cne $s.run -or $f.world_id -cne $s.world_id -or
 $f.kind -cne 'minecome_gameplay_respawn_fixture_v1' -or $f.mode -cne 'respawn-native' -or $f.result -cne 'passed' -or $f.failure){throw 'Native respawn receipt identity/result differs.'}
foreach($flag in @('construction_placement_verified','death_verified','death_drops_verified','respawn_button_verified','respawn_verified','construction_preserved_verified','walking_after_respawn_verified','render_pixels_verified','client_player_replaced','server_player_replaced')){
 if($f.$flag -ne $true){throw "Missing native respawn capability: $flag"}
}
if($native.result -cne 'passed' -or -not $native.normal_client_exit -or $hostProof.Failure -or -not $hostProof.ResourcesClosed -or
 $hostProof.Terminal.result -cne 'explicit_stop' -or ($hostProof.Terminal.camera_override_changed -and -not $hostProof.Terminal.camera_restored) -or -not $hostProof.Terminal.body_restore_dispatched -or
 $hostProof.Terminal.body_hidden -or $hostProof.ViewCount -lt 5 -or $hostProof.Terminal.applied_seq -le 0){throw 'Native respawn camera/save/cleanup proof incomplete.'}
if(-not $f.live_kcd_connected -or $f.scripted_view_writes -ne 0 -or $f.direct_world_inventory_entity_writes -or $f.position_writes_used -or $f.direct_respawn_request_used -or
 -not $f.native_camera_preserved -or $f.native_input_verified -or $f.standalone_scripted -or $f.respawn_epoch -ne 1 -or $f.respawn_pending -or
 $s.blocks.places -ne 1 -or $s.blocks.owned_count -ne 1 -or $s.blocks.client_respawns -ne 1 -or $s.blocks.server_respawns -ne 1 -or
 ($f.images.stage -join '|') -cne 'dead|respawned'){throw 'Native respawn did not use the connected world/view and production gameplay path.'}
if(-not $r.native_required -or $r.pending -or ($r.PSObject.Properties['failure'] -and $r.failure) -or
 $r.death_ack_epoch -ne 1 -or $r.respawn_ack_epoch -ne 1 -or $r.client_rebound_epoch -ne 1 -or
 $m.failure -or -not $m.cleanup_complete -or -not $m.controls_released -or $m.fixture -or $m.death_pending -or $m.respawn_pending -or
 $m.respawn_epoch -ne 1 -or $m.server_respawns -ne 1 -or $m.client_respawns -ne 1 -or $m.death_acknowledged -ne 1 -or $m.respawn_acknowledged -ne 1 -or
 $m.movement_events -lt 2 -or $m.held_ticks -lt 2){throw 'Native death/respawn admission and continued movement proof incomplete.'}
$ackKeys=@('schema','kind','run','world_id','target_pid','target_start_filetime','patch_run','patch_sha256','lifecycle','respawn_epoch','from','target','utc_ms')|Sort-Object
if((($ack.PSObject.Properties.Name|Sort-Object)-join '|') -cne ($ackKeys-join '|') -or $ack.schema -ne 1 -or $ack.kind -cne 'minecome_gameplay_respawn_ack_v1' -or
 $ack.run -cne $s.run -or $ack.world_id -cne $s.world_id -or $ack.target_pid -ne $native.target_pid -or $ack.target_start_filetime -cne $native.target_start_filetime -or
 $ack.patch_run -cne $m.patch_run -or $ack.patch_sha256 -cne $m.patch_sha256 -or $ack.lifecycle -cne 'respawn' -or $ack.respawn_epoch -ne 1){throw 'Native relocation acknowledgment identity/epoch differs.'}
function Distance($a,$b){
 $sum=0.0
 foreach($axis in @('x','y','z')){
  foreach($value in @($a.$axis,$b.$axis)){if($value -isnot [ValueType] -or [double]::IsNaN([double]$value) -or [double]::IsInfinity([double]$value)){throw 'Invalid respawn point.'}}
  $sum+=[Math]::Pow([double]$a.$axis-[double]$b.$axis,2)
 }
 return [Math]::Sqrt($sum)
}
foreach($point in @($ack.from,$ack.target)){if((($point.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'x,y,z'){throw 'Invalid relocation point fields.'}}
if((Distance $ack.from $ack.target) -lt 2){throw 'Native respawn did not prove relocation from the distant death site.'}
if((Distance $f.death_position $f.respawn_position) -lt 2 -or (Distance $f.initial_position $f.respawn_position) -gt .2 -or
 (Distance $f.final_state.position $f.respawn_position) -lt .25){throw 'Respawn fixture did not return to its anchor then walk again.'}
if($f.final_state.health -ne 20 -or $f.final_state.food -ne 20 -or -not $f.final_state.alive -or $f.final_state.deaths -ne 1 -or $f.final_state.diamond_count -ne 0 -or
 $f.dead_state.alive -or $f.dead_state.health -ne 0 -or $f.dead_state.diamond_count -ne 0 -or $f.dead_state.deaths -ne 1){throw 'Vanilla survival death/replacement state differs.'}
$drops=@($f.final_state.drops|Where-Object {$_.id -ceq $f.drop_id -and $_.item -ceq 'minecraft:diamond' -and $_.count -eq 3})
if($drops.Count -ne 1){throw 'The real death-drop identity/count was not preserved.'}
foreach($capture in $f.images){
 if($capture.file -cne ('respawn-'+$capture.stage+'.png') -or
  (Get-FileHash -LiteralPath (Join-Path $saved $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or
  $capture.metadata.world_id -cne $s.world_id -or $capture.metadata.respawn_fixture_stage -cne $capture.stage -or
  $capture.metadata.frame_format -ne 2 -or -not $capture.metadata.PSObject.Properties['world_camera']){throw 'Native respawn image bytes/camera identity differs.'}
}
$deathImage=@($f.images|Where-Object stage -CEQ 'dead')[0]
if($deathImage.metadata.screen_kind -cne 'DeathScreen' -or $deathImage.metadata.screen -ne 1 -or $deathImage.hud_pixels -lt 1000){throw 'Missing actual vanilla death-screen pixels.'}
$start=[long]$f.native_respawn_started_utc_ms;$end=[long]$f.native_respawn_completed_utc_ms
if($end-$start -lt 11000 -or $ack.utc_ms -lt $end -or $ack.utc_ms -gt $end+15000){throw 'Native death dwell or relocation acknowledgment timing differs.'}
$nativeLog=Join-Path $saved 'native-hud.log'
$localDay=[DateTimeOffset]::FromUnixTimeMilliseconds($start).LocalDateTime.Date
$depthSamples=@(foreach($line in [IO.File]::ReadLines($nativeLog)){
 if($line -match '^(\d{2}:\d{2}:\d{2}:\d{3}).*\[MineComeHudInput\] (\{.*\})$'){
  $time=$Matches[1];$record=$Matches[2]|ConvertFrom-Json
  if($record.PSObject.Properties['event'] -and $record.event -ceq 'host_depth' -and $record.run -ceq $s.run){
   $clock=[DateTime]::ParseExact($time,'HH:mm:ss:fff',[Globalization.CultureInfo]::InvariantCulture).TimeOfDay
   $utc=[TimeZoneInfo]::ConvertTimeToUtc([DateTime]::SpecifyKind($localDay.Add($clock),[DateTimeKind]::Unspecified),[TimeZoneInfo]::Local)
   $ms=[DateTimeOffset]::new($utc).ToUnixTimeMilliseconds()
   if($ms -ge $start -and $ms -le $end){[pscustomobject]@{utc_ms=$ms;composited=[long]$record.composited;reprojected=[long]$record.reprojected;considered=[long]$record.considered}}
  }
 }
})
if($depthSamples.Count -lt 2){throw 'Missing two native world-pass samples during the death-screen dwell.'}
$composited=$depthSamples[-1].composited-$depthSamples[0].composited
$reprojected=$depthSamples[-1].reprojected-$depthSamples[0].reprojected
if($composited -lt 1 -or $reprojected -lt 1){throw 'Native world composition did not advance during the death-screen dwell.'}
[ordered]@{schema=1;kind='minecome_native_respawn_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;
 actual_minecraft=$true;scripted_guest_input=$true;scripted_aim=$true;physical_native_keys_verified=$false;direct_respawn_request_used=$false;
 fixture_position_writes_used=$false;production_respawn_relocation_acknowledged=$true;respawn_ack=$ack;respawn_ack_sha256=(Get-FileHash -LiteralPath $ackFile).Hash.ToLowerInvariant();
 death_hud_pixels=$deathImage.hud_pixels;native_composited_during_death=$composited;native_reprojected_during_death=$reprojected;
 native_depth_samples=$depthSamples;native_log_sha256=(Get-FileHash -LiteralPath $nativeLog).Hash.ToLowerInvariant();
 final_state=$f.final_state;normal_client_exit=$native.normal_client_exit;
 camera_restore_needed=$hostProof.Terminal.camera_override_changed;camera_restored=$hostProof.Terminal.camera_restored;body_restored=$hostProof.Terminal.body_restore_dispatched}|
 ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $saved 'native-respawn-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_RESPAWN_PASS evidence=$saved"
