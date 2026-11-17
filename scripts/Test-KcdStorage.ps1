# Scripted Minecraft gameplay through the live KCD camera/HUD session; no physical input claim.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(Mandatory,ParameterSetName='Live')][string]$BundleDirectory,[Parameter(Mandatory,ParameterSetName='Live')][string]$InstanceDirectory,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native storage check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot;$saved=$null
if($PSCmdlet.ParameterSetName -ceq 'Verify'){$saved=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path}
else{
 & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -WorldBlocks -StorageCheck | ForEach-Object {
  if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
  Write-Host $_
 }
}
if(-not $saved){throw 'Native storage did not produce a saved session.'}
$s=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 30
$hostProof=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 30
$native=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json
$f=$s.fixture
if($native.kind -cne 'minecome_gameplay_kcd_session_v1' -or -not $native.storage_check -or
 $native.run -cne $s.run -or $hostProof.Terminal.run -cne $s.run -or $f.world_id -cne $s.world_id -or
 $f.kind -cne 'minecome_gameplay_storage_fixture_v1' -or $f.mode -cne 'storage-native' -or $f.result -cne 'passed' -or $f.failure){throw 'Native storage receipt identity/result differs.'}
foreach($flag in @('barrel_placement_verified','barrel_open_verified','deposit_verified','contents_persistence_verified','inventory_suppression_verified','retrieval_verified','render_pixels_verified','survival_mining_verified','contents_drops_verified')){
 if($f.$flag -ne $true){throw "Missing native storage capability: $flag"}
}
if($native.result -cne 'passed' -or -not $native.normal_client_exit -or $hostProof.Failure -or -not $hostProof.ResourcesClosed -or
 $hostProof.Terminal.result -cne 'explicit_stop' -or ($hostProof.Terminal.camera_override_changed -and -not $hostProof.Terminal.camera_restored) -or -not $hostProof.Terminal.body_restore_dispatched -or
 $hostProof.Terminal.body_hidden -or $hostProof.ViewCount -lt 5 -or $hostProof.Terminal.applied_seq -le 0){throw 'Native storage camera/save/cleanup proof incomplete.'}
if(-not $f.live_kcd_connected -or $f.scripted_view_writes -ne 0 -or $f.direct_world_inventory_entity_writes -or $f.position_writes_used -or
 $s.blocks.barrel_opens -lt 2 -or $s.blocks.owned_count -ne 0 -or $s.blocks.survival_breaks -ne 1 -or
 ($f.images.stage -join '|') -cne 'stored|closed|reopened|dropped'){throw 'Native storage did not use the real connected world/view and gameplay path.'}
if($f.final_state.axe_damage -ne 1 -or $f.final_state.diamond_count -ne 2 -or $f.final_state.block_entity_present -or $f.final_state.cursor_count -ne 0){throw 'Native storage final inventory differs.'}
$counts=@{};foreach($drop in $f.final_state.drops){if(-not $counts.ContainsKey($drop.item)){$counts[$drop.item]=0};$counts[$drop.item]+=$drop.count}
if($counts.Count -ne 3 -or $counts['minecraft:barrel'] -ne 1 -or $counts['minecraft:diamond'] -ne 5 -or $counts['minecraft:cobblestone'] -ne 16){throw 'Native barrel contents drops differ.'}
foreach($capture in $f.images){
 if($capture.file -cne ('storage-'+$capture.stage+'.png') -or
  (Get-FileHash -LiteralPath (Join-Path $saved $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or
  $capture.metadata.world_id -cne $s.world_id -or $capture.metadata.storage_fixture_stage -cne $capture.stage -or
  $capture.metadata.frame_format -ne 2 -or -not $capture.metadata.PSObject.Properties['world_camera']){throw 'Native storage image bytes/camera identity differs.'}
}
$storageImage=@($f.images|Where-Object stage -CEQ 'stored')[0]
if($storageImage.metadata.screen_kind -cne 'GenericContainerScreen' -or $storageImage.metadata.screen -ne 1 -or $storageImage.hud_pixels -lt 1000){throw 'Missing actual storage UI pixels.'}
$start=[long]$f.native_storage_started_utc_ms;$end=[long]$f.native_storage_completed_utc_ms
if($end-$start -lt 11000){throw 'Native storage dwell was too short to verify compositor progress.'}
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
if($depthSamples.Count -lt 2){throw 'Missing two native world-pass samples during the storage screen dwell.'}
$composited=$depthSamples[-1].composited-$depthSamples[0].composited
$reprojected=$depthSamples[-1].reprojected-$depthSamples[0].reprojected
if($composited -lt 1 -or $reprojected -lt 1){throw 'Native world composition did not advance during the storage screen dwell.'}
[ordered]@{schema=1;kind='minecome_native_storage_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;
 actual_minecraft=$true;scripted_guest_input=$true;scripted_aim=$true;live_kcd_camera_acknowledged=$true;physical_native_keys_verified=$false;
 direct_world_inventory_entity_writes=$false;fixture_camera_writes_used=$false;storage_hud_pixels=$storageImage.hud_pixels;
 native_composited_during_storage=$composited;native_reprojected_during_storage=$reprojected;
 native_depth_samples=$depthSamples;native_log_sha256=(Get-FileHash -LiteralPath $nativeLog).Hash.ToLowerInvariant();
 final_state=$f.final_state;normal_client_exit=$native.normal_client_exit;
 camera_restore_needed=$hostProof.Terminal.camera_override_changed;camera_restored=$hostProof.Terminal.camera_restored;body_restored=$hostProof.Terminal.body_restore_dispatched}|
 ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $saved 'native-storage-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_STORAGE_PASS evidence=$saved"
