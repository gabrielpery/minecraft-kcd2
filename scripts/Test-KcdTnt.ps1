# Actual TNT through the live KCD camera/world pass; scripted Minecraft input.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(Mandatory,ParameterSetName='Live')][string]$BundleDirectory,[Parameter(Mandatory,ParameterSetName='Live')][string]$InstanceDirectory,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native TNT check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot;$saved=$null
if($PSCmdlet.ParameterSetName -ceq 'Verify'){$saved=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path}
else{
 & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -WorldBlocks -TntCheck | ForEach-Object {
  if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
  Write-Host $_
 }
}
if(-not $saved){throw 'Native TNT did not produce a saved session.'}
$s=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 30
$hostProof=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 30
$native=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json
$ready=Get-Content -LiteralPath (Join-Path $saved 'capture/stream-ready.json') -Raw|ConvertFrom-Json
$aim=Get-Content -LiteralPath (Join-Path $saved 'gameplay-aim.json') -Raw|ConvertFrom-Json
$f=$s.fixture;$m=$s.movement;$b=$s.blocks;$t=$b.tnt
if($native.kind -cne 'minecome_gameplay_kcd_session_v1' -or -not $native.tnt_check -or
 $native.run -cne $s.run -or $hostProof.Terminal.run -cne $s.run -or $f.world_id -cne $s.world_id -or
 $f.kind -cne 'minecome_gameplay_tnt_fixture_v1' -or $f.mode -cne 'tnt-native' -or $f.result -cne 'passed' -or $f.failure){throw 'Native TNT receipt identity/result differs.'}
if($ready.run -cne $s.run -or $ready.target_pid -ne $native.target_pid -or $ready.target_start_filetime -cne $native.target_start_filetime -or
 $aim.run -cne $s.run -or $aim.world_id -cne $s.world_id -or $aim.target_pid -ne $native.target_pid -or $aim.target_start_filetime -cne $native.target_start_filetime -or
 $aim.patch_run -cne $m.patch_run -or $aim.patch_sha256 -cne $m.patch_sha256 -or $m.run -cne $s.run -or $m.world_id -cne $s.world_id){throw 'Native TNT renderer/camera process, world or terrain identity differs.'}
foreach($flag in @('tnt_placement_verified','ignition_verified','fuse_verified','chain_reaction_verified','fragile_destruction_verified','resistant_preservation_verified','tool_durability_verified','ledger_removal_verified','render_pixels_verified')){
 if($f.$flag -ne $true){throw "Missing native TNT capability: $flag"}
}
if($native.result -cne 'passed' -or -not $native.normal_client_exit -or $hostProof.Failure -or -not $hostProof.ResourcesClosed -or
 $hostProof.Terminal.result -cne 'explicit_stop' -or ($hostProof.Terminal.camera_override_changed -and -not $hostProof.Terminal.camera_restored) -or -not $hostProof.Terminal.body_restore_dispatched -or
 $hostProof.Terminal.body_hidden -or $hostProof.ViewCount -lt 5 -or $hostProof.Terminal.applied_seq -le 0 -or
 $s.failure -or $s.producer_failure -or -not $s.producer_finished -or -not $s.controls_released -or
 $m.failure -or -not $m.cleanup_complete -or -not $m.controls_released -or -not $m.terrain_cells_valid -or
 $b.failure -or $b.pending -or -not $b.cleanup_complete -or -not $b.controls_released -or
 $t.failure -or -not $t.cleanup_complete -or $t.active -ne 0 -or $t.frozen_on_stop -ne 0){throw 'Native TNT camera/save/entity cleanup proof incomplete.'}
if(-not $f.actual_minecraft -or -not $f.live_kcd_connected -or $f.standalone_scripted -or $f.native_input_verified -or $f.scripted_view_writes -ne 0 -or $f.direct_world_inventory_entity_writes -or $f.position_writes_used -or
 $b.places -ne 4 -or $b.tnt_ignitions -ne 1 -or $b.owned_count -ne 1 -or $t.primed -ne 2 -or $t.chain_primed -ne 1 -or $t.explosions -ne 2 -or $s.tnt_render_frames -lt 1 -or
 ($f.images.stage -join '|') -cne 'primed|after'){throw 'Native TNT did not use the connected world/view and production explosion path.'}
$final=$f.final_state;$resistant=$f.positions.resistant;$ledger=@($b.blocks)
if($final.primed_count -ne 0 -or $final.flint_count -ne 1 -or $final.flint_damage -ne 1 -or -not $f.protection_restored -or $f.fuse_writes_used -or
 $final.states.primary -cne 'minecraft:air' -or $final.states.chain -cne 'minecraft:air' -or $final.states.fragile -cne 'minecraft:air' -or $final.states.resistant -cne 'minecraft:obsidian' -or
 $ledger.Count -ne 1 -or $ledger[0].state -cne 'minecraft:obsidian' -or $ledger[0].x -ne $resistant.x -or $ledger[0].y -ne $resistant.y -or $ledger[0].z -ne $resistant.z){throw 'Native TNT actual destruction, tool damage or remaining ledger cell differs.'}
$first=@($f.observed_tnt|Where-Object id -CEQ $f.tnt_id);$chain=@($f.observed_tnt|Where-Object id -CEQ $f.chain_tnt_id)
if(@($f.observed_tnt).Count -ne 2 -or $f.tnt_id -ceq $f.chain_tnt_id -or $first.Count -ne 1 -or $chain.Count -ne 1 -or
 $first[0].first_fuse -lt 60 -or $first[0].first_fuse -gt 80 -or $first[0].first_fuse-$first[0].minimum_fuse -lt 10 -or $chain[0].first_fuse -lt 1 -or $chain[0].first_fuse -gt 29){throw 'Native TNT vanilla fuse/chain observations differ.'}
foreach($capture in $f.images){
 if($capture.file -cne ('tnt-'+$capture.stage+'.png') -or
  (Get-FileHash -LiteralPath (Join-Path $saved $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or
  $capture.world_file -cne ('tnt-'+$capture.stage+'-world.png') -or (Get-FileHash -LiteralPath (Join-Path $saved $capture.world_file)).Hash.ToLowerInvariant() -cne $capture.world_sha256 -or
  $capture.metadata.world_id -cne $s.world_id -or $capture.metadata.tnt_fixture_stage -cne $capture.stage -or
  $capture.metadata.frame_format -ne 2 -or -not $capture.metadata.PSObject.Properties['world_camera']){throw 'Native TNT image bytes/camera identity differs.'}
 $camera=$capture.metadata.world_camera
 if($camera.utc_ms -le 0 -or $camera.utc_ms -gt $capture.metadata.captured_utc_ms){throw 'Native TNT captured camera timestamp differs.'}
}
$primed=@($f.images|Where-Object stage -CEQ 'primed')[0];$after=@($f.images|Where-Object stage -CEQ 'after')[0]
if($primed.world_pixels -lt 1 -or $primed.world_with_depth_pixels -lt 1 -or
 $primed.metadata.tnt_render_count -lt 1 -or $primed.metadata.tnt_render_count -gt 16 -or @($primed.metadata.tnt).Count -ne $primed.metadata.tnt_render_count -or
 $primed.metadata.rendered_world_blocks -ne 0 -or $primed.metadata.dropped_item_render_count -ne 0 -or $primed.metadata.projectile_render_count -ne 0 -or $primed.metadata.player_pixels -or
 @($primed.metadata.tnt|Where-Object {$_.id -ceq $f.tnt_id -and $_.fuse -gt 0}).Count -ne 1 -or
 $after.metadata.tnt_render_count -ne 0 -or @($after.metadata.tnt).Count -ne 0){throw 'Primed/exploded TNT colour/depth evidence differs.'}
$start=[long]$f.native_tnt_started_utc_ms;$end=[long]$f.native_tnt_completed_utc_ms
if($start -le 0 -or $end-$start -lt 11000){throw 'Native post-explosion dwell was too short to verify compositor progress.'}
$nativeLog=Join-Path $saved 'native-hud.log';$localDay=[DateTimeOffset]::FromUnixTimeMilliseconds($start).LocalDateTime.Date
$depthSamples=@(foreach($line in [IO.File]::ReadLines($nativeLog)){
 if($line -match '^(\d{2}:\d{2}:\d{2}:\d{3}).*\[MineComeHudInput\] (\{.*\})$'){
  $time=$Matches[1];$record=$Matches[2]|ConvertFrom-Json
  if($record.PSObject.Properties['event'] -and $record.event -ceq 'host_depth' -and $record.run -ceq $s.run){
   $clock=[DateTime]::ParseExact($time,'HH:mm:ss:fff',[Globalization.CultureInfo]::InvariantCulture).TimeOfDay
   $utc=[TimeZoneInfo]::ConvertTimeToUtc([DateTime]::SpecifyKind($localDay.Add($clock),[DateTimeKind]::Unspecified),[TimeZoneInfo]::Local)
   $ms=[DateTimeOffset]::new($utc).ToUnixTimeMilliseconds()
   if($ms -lt $start-43200000){$ms+=86400000}
   if($ms -ge $start -and $ms -le $end){[pscustomobject]@{utc_ms=$ms;composited=[long]$record.composited;reprojected=[long]$record.reprojected;considered=[long]$record.considered}}
  }
 }
})
if($depthSamples.Count -lt 2){throw 'Missing two native world-pass samples after TNT exploded.'}
$composited=$depthSamples[-1].composited-$depthSamples[0].composited;$reprojected=$depthSamples[-1].reprojected-$depthSamples[0].reprojected
if($composited -lt 1 -or $reprojected -lt 1){throw 'Native world composition did not advance after TNT exploded.'}
[ordered]@{schema=1;kind='minecome_native_tnt_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;
 actual_minecraft=$true;scripted_guest_input=$true;scripted_aim=$true;live_kcd_camera_acknowledged=$true;physical_native_keys_verified=$false;
 direct_world_inventory_entity_writes=$false;fixture_camera_writes_used=$false;primed_tnt=$primed.metadata.tnt;primed_world_pixels=$primed.world_pixels;
 native_composited_after_explosion=$composited;native_reprojected_after_explosion=$reprojected;native_depth_samples=$depthSamples;
 native_log_sha256=(Get-FileHash -LiteralPath $nativeLog).Hash.ToLowerInvariant();final_state=$f.final_state;tnt=$t;normal_client_exit=$native.normal_client_exit;
 camera_restore_needed=$hostProof.Terminal.camera_override_changed;camera_restored=$hostProof.Terminal.camera_restored;body_restored=$hostProof.Terminal.body_restore_dispatched}|
 ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $saved 'native-tnt-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_TNT_PASS evidence=$saved"
