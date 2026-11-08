# Scripted Minecraft gameplay through the live KCD camera/HUD session; no physical input claim.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(Mandatory,ParameterSetName='Live')][string]$BundleDirectory,[Parameter(Mandatory,ParameterSetName='Live')][string]$InstanceDirectory,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native crafting check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot;$saved=$null
if($PSCmdlet.ParameterSetName -ceq 'Verify'){$saved=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path}
else{
 & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -WorldBlocks -CraftingCheck | ForEach-Object {
  if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
  Write-Host $_
 }
}
if(-not $saved){throw 'Native crafting did not produce a saved session.'}
$s=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 30
$hostProof=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 30
$native=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json
$f=$s.fixture
if($native.kind -cne 'minecome_gameplay_kcd_session_v1' -or -not $native.crafting_check -or
 $native.run -cne $s.run -or $hostProof.Terminal.run -cne $s.run -or $f.world_id -cne $s.world_id -or
 $f.kind -cne 'minecome_gameplay_crafting_fixture_v1' -or $f.mode -cne 'crafting-native' -or $f.result -cne 'passed' -or $f.failure){throw 'Native crafting receipt identity/result differs.'}
foreach($flag in @('inventory_crafting_verified','table_placement_verified','table_open_verified','table_crafting_verified','ingredient_return_verified','inventory_suppression_verified','render_pixels_verified')){
 if($f.$flag -ne $true){throw "Missing native crafting capability: $flag"}
}
if($native.result -cne 'passed' -or -not $native.normal_client_exit -or $hostProof.Failure -or -not $hostProof.ResourcesClosed -or
 $hostProof.Terminal.result -cne 'explicit_stop' -or ($hostProof.Terminal.camera_override_changed -and -not $hostProof.Terminal.camera_restored) -or -not $hostProof.Terminal.body_restore_dispatched -or
 $hostProof.Terminal.body_hidden -or $hostProof.ViewCount -lt 5 -or $hostProof.Terminal.applied_seq -le 0){throw 'Native crafting camera/save/cleanup proof incomplete.'}
if(-not $f.live_kcd_connected -or $f.scripted_view_writes -ne 0 -or $f.direct_world_inventory_entity_writes -or $f.position_writes_used -or
 $s.blocks.crafting_opens -lt 1 -or $s.blocks.owned_count -ne 1 -or
 ($f.images.stage -join '|') -cne 'inventory_recipe|table_recipe|closed'){throw 'Native crafting did not use the real connected world/view and gameplay path.'}
foreach($capture in $f.images){
 if($capture.file -cne ('crafting-'+$capture.stage+'.png') -or
  (Get-FileHash -LiteralPath (Join-Path $saved $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or
  $capture.metadata.world_id -cne $s.world_id -or $capture.metadata.crafting_fixture_stage -cne $capture.stage -or
  $capture.metadata.frame_format -ne 2 -or -not $capture.metadata.PSObject.Properties['world_camera']){throw 'Native crafting image bytes/camera identity differs.'}
}
$table=@($f.images|Where-Object stage -CEQ 'table_recipe')[0]
if($table.metadata.screen_kind -cne 'CraftingScreen' -or $table.metadata.screen -ne 1 -or $table.hud_pixels -lt 1000){throw 'Missing actual crafting table UI pixels.'}
$start=[long]$f.native_crafting_started_utc_ms;$end=[long]$f.native_crafting_completed_utc_ms
if($end-$start -lt 11000){throw 'Native crafting dwell was too short to verify compositor progress.'}
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
if($depthSamples.Count -lt 2){throw 'Missing two native world-pass samples during the crafting screen dwell.'}
$composited=$depthSamples[-1].composited-$depthSamples[0].composited
$reprojected=$depthSamples[-1].reprojected-$depthSamples[0].reprojected
if($composited -lt 1 -or $reprojected -lt 1){throw 'Native world composition did not advance during the crafting screen dwell.'}
[ordered]@{schema=1;kind='minecome_native_crafting_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;
 actual_minecraft=$true;scripted_guest_input=$true;scripted_aim=$true;live_kcd_camera_acknowledged=$true;physical_native_keys_verified=$false;
 direct_world_inventory_entity_writes=$false;fixture_camera_writes_used=$false;crafting_hud_pixels=$table.hud_pixels;
 native_composited_during_crafting=$composited;native_reprojected_during_crafting=$reprojected;
 native_depth_samples=$depthSamples;native_log_sha256=(Get-FileHash -LiteralPath $nativeLog).Hash.ToLowerInvariant();
 final_state=$f.final_state;normal_client_exit=$native.normal_client_exit;
 camera_restore_needed=$hostProof.Terminal.camera_override_changed;camera_restored=$hostProof.Terminal.camera_restored;body_restored=$hostProof.Terminal.body_restore_dispatched}|
 ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $saved 'native-crafting-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_CRAFTING_PASS evidence=$saved"
