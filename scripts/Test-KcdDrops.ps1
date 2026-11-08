# Scripted Minecraft gameplay through the live KCD camera/HUD session; no physical input claim.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(Mandatory,ParameterSetName='Live')][string]$BundleDirectory,[Parameter(Mandatory,ParameterSetName='Live')][string]$InstanceDirectory,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native drops check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot;$saved=$null
if($PSCmdlet.ParameterSetName -ceq 'Verify'){$saved=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path}
else{
 & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -WorldBlocks -DropsCheck | ForEach-Object {
  if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
  Write-Host $_
 }
}
if(-not $saved){throw 'Native drops did not produce a saved session.'}
$s=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 30
$hostProof=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 30
$native=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json
$f=$s.fixture
if($native.kind -cne 'minecome_gameplay_kcd_session_v1' -or -not $native.drops_check -or
 $native.run -cne $s.run -or $hostProof.Terminal.run -cne $s.run -or $f.world_id -cne $s.world_id -or
 $f.kind -cne 'minecome_gameplay_drops_fixture_v1' -or $f.mode -cne 'drops-native' -or $f.result -cne 'passed' -or $f.failure){throw 'Native drops receipt identity/result differs.'}
foreach($flag in @('survival_placement_verified','survival_mining_verified','real_drop_verified','drop_ground_collision_verified','render_pixels_verified','walking_pickup_verified','durability_verified')){
 if($f.$flag -ne $true){throw "Missing native drops capability: $flag"}
}
if($native.result -cne 'passed' -or -not $native.normal_client_exit -or $hostProof.Failure -or -not $hostProof.ResourcesClosed -or
 $hostProof.Terminal.result -cne 'explicit_stop' -or ($hostProof.Terminal.camera_override_changed -and -not $hostProof.Terminal.camera_restored) -or -not $hostProof.Terminal.body_restore_dispatched -or
 $hostProof.Terminal.body_hidden -or $hostProof.Terminal.writes -lt 2 -or $hostProof.ViewCount -lt 5 -or $hostProof.Terminal.applied_seq -le 0){throw 'Native drops camera/save/cleanup proof incomplete.'}
if(-not $f.live_kcd_connected -or $f.scripted_view_writes -ne 0 -or $f.direct_world_inventory_entity_writes -or $f.position_writes_used -or
 $s.dropped_item_render_frames -lt 1 -or $s.movement.movement_events -lt 1 -or $s.blocks.owned_count -ne 0 -or
 ($f.images.stage -join '|') -cne 'empty|dropped|picked_up'){throw 'Native drops did not use the real connected world/view and gameplay path.'}
foreach($capture in $f.images){
 if($capture.file -cne ('drops-'+$capture.stage+'.png') -or
  (Get-FileHash -LiteralPath (Join-Path $saved $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or
  $capture.metadata.world_id -cne $s.world_id -or $capture.metadata.drops_fixture_stage -cne $capture.stage -or
  $capture.metadata.frame_format -ne 2 -or -not $capture.metadata.PSObject.Properties['world_camera']){throw 'Native drop image bytes/camera identity differs.'}
}
$drop=@($f.images|Where-Object stage -CEQ 'dropped')[0]
if($drop.world_pixels -lt 100 -or $drop.world_with_depth_pixels -lt $drop.world_pixels*.9 -or
 -not $drop.depth_finite_unit_range -or $drop.metadata.dropped_item_render_count -ne 1 -or
 $drop.metadata.dropped_items[0].id -cne $f.drop_id){throw 'The mined entity lacked actual same-camera colour/depth pixels.'}
$start=[long]$f.native_drop_started_utc_ms;$end=[long]$f.native_drop_completed_utc_ms
if($end-$start -lt 11000){throw 'Native drop dwell was too short to verify compositor progress.'}
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
if($depthSamples.Count -lt 2){throw 'Missing two native world-pass samples while the mined drop remained visible.'}
$composited=$depthSamples[-1].composited-$depthSamples[0].composited
$reprojected=$depthSamples[-1].reprojected-$depthSamples[0].reprojected
if($composited -lt 1 -or $reprojected -lt 1){throw 'Native world composition did not advance during the drop dwell.'}
[ordered]@{schema=1;kind='minecome_native_drops_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;
 actual_minecraft=$true;scripted_guest_input=$true;scripted_aim=$true;live_kcd_camera_acknowledged=$true;physical_native_keys_verified=$false;
 direct_world_inventory_entity_writes=$false;fixture_camera_writes_used=$false;drop_id=$f.drop_id;drop_pixels=$drop.world_pixels;
 drop_depth_pixels=$drop.world_with_depth_pixels;native_composited_during_drop=$composited;native_reprojected_during_drop=$reprojected;
 native_depth_samples=$depthSamples;native_log_sha256=(Get-FileHash -LiteralPath $nativeLog).Hash.ToLowerInvariant();
 final_state=$f.final_state;normal_client_exit=$native.normal_client_exit;
 camera_restore_needed=$hostProof.Terminal.camera_override_changed;camera_restored=$hostProof.Terminal.camera_restored;body_restored=$hostProof.Terminal.body_restore_dispatched}|
 ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $saved 'native-drops-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_DROPS_PASS evidence=$saved"
