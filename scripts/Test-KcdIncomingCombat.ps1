# Real native hostile attacks -> vanilla health, inventory, and continued HUD composition.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(Mandatory,ParameterSetName='Live')][string]$BundleDirectory,
 [Parameter(ParameterSetName='Live')][string]$InstanceDirectory,[Parameter(ParameterSetName='Live')][string]$GroundPatchFile,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native incoming combat check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$saved=$null
if($PSCmdlet.ParameterSetName -ceq 'Verify'){$saved=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path}
else{
 . (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
 . (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
 . (Join-Path $PSScriptRoot 'GameplayHudSessionGuard.ps1')
 $context=Get-MineComeProbeContext
 $installation=Get-MineComeGameplayInstallation -BundleDirectory $BundleDirectory -RequireUnarmed -Movement -Blocks -Chat
 Assert-GameplayHudSessionUnused $context $installation.ToolsBin
 $run=[guid]::NewGuid().ToString('N')
 if(-not $InstanceDirectory){$InstanceDirectory=Join-Path $context.ProjectRoot ('runtime/gameplay/incoming-combat-native-'+$run)}
 if(-not $GroundPatchFile){
  $capture=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch -WideWalking | Where-Object {$_ -isnot [string] -and $_.PSObject.Properties['GroundPatchFile']})
  if($capture.Count -ne 1){throw 'Incoming combat requires one actual terrain capture.'};$GroundPatchFile=$capture[0].GroundPatchFile
 }
 # The session owns readiness, hostile NPC spawning/removal, and its finally cleanup.
 & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -GroundPatchFile $GroundPatchFile -Combat -IncomingCombatCheck -CombatFixtureRun $run | ForEach-Object {
  if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
  Write-Host $_
 }
 if(-not $saved){throw 'Incoming combat session did not save successfully.'}
}
function Read-IncomingProof([string]$Name){Get-Content -LiteralPath (Join-Path $saved $Name) -Raw|ConvertFrom-Json -Depth 48}
function Assert-IncomingTrue($Value,[string]$Name){if($Value -isnot [bool] -or -not $Value){throw "Incoming verification missing: $Name"}}
function Assert-IncomingNear([double]$Actual,[double]$Expected,[string]$Name,[double]$Tolerance=.01){if(-not [double]::IsFinite($Actual) -or -not [double]::IsFinite($Expected) -or [Math]::Abs($Actual-$Expected) -gt $Tolerance){throw "Incoming verification differs: $Name ($Actual / $Expected)"}}
function Assert-IncomingSourceClock($Source,[long]$OriginalUtcMs){
 if(-not $Source.PSObject.Properties['SourceClock']){throw 'Incoming original source clock proof missing.'}
 foreach($key in @('GameMs','SourceUtcMs','CapturedUtcMs')){
  $value=$Source.$key
  if($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -lt 0 -or $value -ne [Math]::Floor([double]$value)){throw 'Incoming original source timestamp type/bound invalid.'}
 }
 $before=$Source.SourceClock.Before;$after=$Source.SourceClock.After
 foreach($anchor in @($before,$after)){
  foreach($key in @('NativeClockMs','SentUtcMs','ReceivedUtcMs')){
   $value=$anchor.$key
   if($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -lt 0 -or
     ($key -cne 'NativeClockMs' -and ($value -ne [Math]::Floor([double]$value) -or $value -le 0))){throw 'Incoming clock anchor type/bound invalid.'}
  }
  if($anchor.ReceivedUtcMs -lt $anchor.SentUtcMs -or $anchor.ReceivedUtcMs-$anchor.SentUtcMs -gt 250){throw 'Incoming source clock request bracket invalid.'}
 }
 if($after.NativeClockMs -le $before.NativeClockMs -or $after.SentUtcMs -lt $before.SentUtcMs -or $after.SentUtcMs-$before.SentUtcMs -gt 1000 -or
  $after.ReceivedUtcMs -lt $before.ReceivedUtcMs -or $Source.GameMs -lt $before.NativeClockMs -or $Source.GameMs -gt $after.NativeClockMs){throw 'Incoming source clock pair does not enclose the event.'}
 $fraction=([double]$Source.GameMs-$before.NativeClockMs)/($after.NativeClockMs-$before.NativeClockMs)
 $reconstructed=[long][Math]::Floor($before.SentUtcMs+$fraction*($after.SentUtcMs-$before.SentUtcMs))
 if($OriginalUtcMs -ne $reconstructed -or $Source.SourceUtcMs -ne $reconstructed -or $Source.CapturedUtcMs -lt $after.ReceivedUtcMs -or
  $Source.CapturedUtcMs-$reconstructed -gt 2000 -or $reconstructed-$Source.CapturedUtcMs -gt 50){throw 'Incoming original source UTC reconstruction/admission differs.'}
}
$s=Read-IncomingProof 'gameplay-session.json';$h=Read-IncomingProof 'host-movement.json';$v=Read-IncomingProof 'verification.json';$nativeFixture=Read-IncomingProof 'incoming-fixture-native.json'
$f=$s.fixture;$c=$s.combat;$incoming=$h.Combat.Incoming
if($v.result -cne 'passed' -or -not $v.normal_client_exit -or $h.Failure -or -not $h.ResourcesClosed -or -not $h.Combat.CleanupComplete -or
 $s.failure -or $s.producer_failure -or -not $s.normal_shutdown_requested -or -not $s.controls_released -or -not $c.cleanup_complete -or $c.pending -or $c.incoming_pending -ne 0 -or
 ($c.PSObject.Properties['failure'] -and $c.failure)){throw 'Incoming combat normal shutdown/cleanup failed.'}
if($f.kind -cne 'minecome_native_incoming_combat_fixture_v1' -or $f.result -cne 'passed' -or $f.failure -or $f.world_id -cne $s.world_id -or
 -not $f.actual_minecraft -or $f.synthetic_host -or -not $f.scripted_guest_input -or $f.physical_native_keys_verified -or $f.position_writes_used -or $f.velocity_writes_used -or $f.camera_writes_used -or $f.direct_health_inventory_entity_writes){throw 'Incoming native fixture scope/identity differs.'}
foreach($flag in @('readiness_published','two_native_hits_verified','native_hit_in_inventory_verified','inventory_walking_input_absent','native_attacker_removed','render_pixels_verified')){Assert-IncomingTrue $f.$flag $flag}
if($nativeFixture.schema -ne 1 -or $nativeFixture.run -cnotmatch '^[0-9a-f]{32}$' -or -not $nativeFixture.started -or -not $nativeFixture.removed){throw 'Owned hostile fixture lifecycle differs.'}
$fixtureBegin=@($nativeFixture.receipts|Where-Object {$_.event -ceq 'begin' -and $_.mode -ceq 'hostile' -and $_.active -eq $true})
$fixtureEnd=@($nativeFixture.receipts|Where-Object {$_.event -ceq 'terminal' -and $_.mode -ceq 'hostile' -and $_.removed -eq $true -and $_.path_restored -eq $true -and $_.active -eq $false})
if($fixtureBegin.Count -ne 1 -or $fixtureEnd.Count -lt 1 -or @($nativeFixture.receipts|Where-Object {$_.run -cne $nativeFixture.run}).Count -gt 0){throw 'Actual hostile native begin/removal receipts missing.'}
foreach($name in @('incoming-fixture-ready.json','incoming-fixture-remove.json','incoming-fixture-removed.json')){$marker=Read-IncomingProof $name;if($marker.schema -ne 1 -or $marker.world_id -cne $s.world_id){throw 'Incoming fixture marker identity differs.'}}
$guestReceipts=@($c.incoming_receipts)
if($guestReceipts.Count -lt 2 -or $c.hurt_ack -ne $guestReceipts.Count -or $c.incoming_hurts -ne $guestReceipts.Count -or $c.incoming_old_life_skipped -ne 0 -or $c.outgoing_hits -ne 0 -or $c.hit_ack -ne 0){throw 'Incoming guest receipt/ACK ownership differs.'}
$previousHealth=[double]$f.initial_health;$applied=0.;$creative=0;$positive=@()
for($i=0;$i -lt $guestReceipts.Count;$i++){
 $hurt=$guestReceipts[$i]
 if($hurt.seq -ne $i+1 -or $hurt.attacker_token -ne 1 -or $hurt.life -ne 0 -or $hurt.requested_damage -le 0 -or $hurt.source_utc_ms -le 0 -or $hurt.applied_utc_ms -lt $hurt.source_utc_ms-50){throw 'Incoming vanilla receipt identity/timing differs.'}
 Assert-IncomingNear $hurt.health_before $previousHealth 'contiguous vanilla health'
 $delta=[double]$hurt.health_before-[double]$hurt.health_after
 if($delta -lt 0 -or $hurt.health_after -le 0){throw 'Incoming fixture healed/died unexpectedly.'}
 if($delta -gt 0){if($hurt.result -cne 'damaged' -or -not $hurt.vanilla_accepted){throw 'Actual native health loss lacks vanilla acceptance.'};$positive+=,$hurt}
 elseif($hurt.result -ceq 'damaged'){throw 'Vanilla damage receipt has no health loss.'}
 if($hurt.result -ceq 'creative'){$creative++;if($delta -ne 0 -or $hurt.vanilla_accepted){throw 'Creative immunity differed from vanilla outcome.'}}
 elseif($hurt.result -cnotin @('damaged','absorbed','vanilla_rejected')){throw 'Unexpected incoming hit result.'}
 $applied+=$delta;$previousHealth=[double]$hurt.health_after
}
if($c.incoming_creative_skipped -ne $creative){throw 'Creative receipt accounting differs.'}
if($positive.Count -lt 2 -or $f.positive_damage_receipts -lt 2 -or $f.positive_damage_receipts -gt $positive.Count){throw 'At least two real native attacks must reduce Minecraft health.'}
Assert-IncomingNear $f.initial_health 20 'fresh Survival health';Assert-IncomingNear $previousHealth $f.final_health 'final fixture health';Assert-IncomingNear $applied $c.player_damage_applied 'vanilla damage total'
$inventoryHit=@($positive|Where-Object {$_.seq -eq $f.inventory_hit_sequence})
if($inventoryHit.Count -ne 1 -or $inventoryHit[0].seq -le $positive[0].seq -or $f.inventory_receipt.seq -ne $inventoryHit[0].seq -or
 $f.first_receipt.seq -ne $positive[0].seq -or $inventoryHit[0].source_utc_ms -lt $f.inventory_opened_utc_ms-50 -or $inventoryHit[0].applied_utc_ms -lt $f.inventory_opened_utc_ms -or
 $f.inventory_receipt.source_utc_ms -ne $inventoryHit[0].source_utc_ms -or $f.inventory_receipt.applied_utc_ms -ne $inventoryHit[0].applied_utc_ms){throw 'Selected native damage did not occur in inventory.'}
Assert-IncomingNear $f.inventory_receipt.health_after $inventoryHit[0].health_after 'selected inventory receipt health'
$inventoryPoint=@($f.points|Where-Object stage -CEQ 'inventory_hit');$afterPoint=@($f.points|Where-Object stage -CEQ 'after')
if($inventoryPoint.Count -ne 1 -or $afterPoint.Count -ne 1 -or $inventoryPoint[0].screen -cne 'InventoryScreen' -or $afterPoint[0].screen -cne 'none' -or $afterPoint[0].mode -cne 'creative'){throw 'Actual inventory/after observations missing.'}
foreach($point in @($inventoryPoint[0],$afterPoint[0])){Assert-IncomingNear $point.client_health $point.server_health 'client/server health'}
if(($f.images.stage -join '|') -cne 'before|inventory|after'){throw 'Incoming HUD capture sequence incomplete.'}
foreach($capture in $f.images){
 if($capture.file -cne ('incoming-combat-'+$capture.stage+'.png') -or $capture.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
  (Get-FileHash -LiteralPath (Join-Path $saved $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or $capture.hud_pixels -lt 1000 -or
  $capture.metadata.world_id -cne $s.world_id -or -not $capture.metadata.PSObject.Properties['world_camera'] -or
  $capture.metadata.incoming_combat_stage -cne $capture.stage -or $capture.metadata.frame_format -ne 2 -or $capture.metadata.screen -ne $(if($capture.stage -ceq 'inventory'){1}else{0})){throw 'Incoming actual HUD image identity/pixels differ.'}
}
$windowStart=[long]$f.native_composition_window_started_utc_ms;$windowEnd=[long]$f.native_composition_window_completed_utc_ms
if($windowStart -le 0 -or $windowEnd-$windowStart -lt 11000 -or $windowEnd-$windowStart -gt 14000 -or $f.hud_frames_during_dwell -lt 2){throw 'Incoming post-hit composition observation window differs.'}
if($f.images[1].metadata.captured_utc_ms -gt $windowStart -or $f.images[2].metadata.captured_utc_ms -lt $windowEnd){throw 'Incoming composition window does not follow the real inventory capture.'}
# Same local-clock/day anchoring as Test-KcdCombat, independently read from ReShade.
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
if($window.Count -lt 2){throw 'Incoming native composition window lacks two counter samples.'}
for($i=1;$i -lt $window.Count;$i++){if($window[$i].utc_ms -le $window[$i-1].utc_ms -or $window[$i].composited -lt $window[$i-1].composited -or $window[$i].reprojected -lt $window[$i-1].reprojected){throw 'Incoming native composition counters regressed.'}}
$compositedDelta=$window[-1].composited-$window[0].composited;$reprojectedDelta=$window[-1].reprojected-$window[0].reprojected
if($compositedDelta -lt 1 -or $reprojectedDelta -lt 1){throw 'Incoming native HUD composition/reprojection stopped.'}
. (Join-Path $PSScriptRoot 'GameplayIncomingHost.ps1')
if(-not $incoming.Enabled -or -not $incoming.CleanupComplete -or $incoming.Failure -or $incoming.Pending -ne 0 -or
 $incoming.HurtAck -ne $guestReceipts.Count -or $incoming.HurtSequence -ne $guestReceipts.Count -or $incoming.Events -ne $guestReceipts.Count -or
 $incoming.MaxAdmissionAgeMs -gt 2000 -or -not $incoming.Begin -or -not $incoming.Terminal){throw 'Native incoming delivery/lifecycle accounting differs.'}
foreach($flag in @('restored','cvars_restored','buff_restored','health_restored')){Assert-IncomingTrue $incoming.Terminal.$flag ('native '+$flag)}
if($incoming.Begin.run -cne $s.run -or $incoming.Terminal.run -cne $s.run -or $incoming.Begin.native_maximum -le 0 -or -not $incoming.Begin.player_name){throw 'Native incoming baseline identity differs.'}
$hostReceipts=@($incoming.Receipts)
if($hostReceipts.Count -ne $guestReceipts.Count){throw 'Native and Minecraft incoming receipt counts differ.'}
$nativeLines=@(Get-Content -LiteralPath (Join-Path $saved 'incoming-hurts.jsonl')|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json -Depth 32})
if($nativeLines.Count -ne $hostReceipts.Count){throw 'Independent native receipt file count differs.'}
$epochRoot=Join-Path $saved 'incoming-epochs'
if(-not(Test-Path -LiteralPath $epochRoot -PathType Container)){$epochRoot=[IO.Path]::GetFullPath($incoming.EpochRoot)}
$sources=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$parsedFiles=@{};$sourceProof=[Collections.Generic.List[object]]::new();$nativeDamage=0.
for($i=0;$i -lt $hostReceipts.Count;$i++){
 $hostHit=$hostReceipts[$i];$guestHit=$guestReceipts[$i];$source=$hostHit.source;$row=$nativeLines[$i]
 if($hostHit.seq -ne $guestHit.seq -or $row.seq -ne $hostHit.seq -or $hostHit.attacker_token -ne $guestHit.attacker_token -or
  $hostHit.source_utc_ms -ne $guestHit.source_utc_ms -or $row.source_utc_ms -ne $hostHit.source_utc_ms -or $row.source.EventSha256 -cne $source.EventSha256 -or
  $source.AttackerName -cne ('MineComeCombat_'+$nativeFixture.run+'_fixture') -or $source.VictimName -cne $incoming.Begin.player_name -or
  $source.EventSha256 -cnotmatch '^[0-9a-f]{64}$' -or -not $sources.Add($source.SourceId)){throw 'Native event/guest receipt identity or deduplication differs.'}
 Assert-IncomingNear $hostHit.maximum $incoming.Begin.native_maximum 'native maximum health'
 Assert-IncomingSourceClock $source ([long]$hostHit.source_utc_ms)
 Assert-IncomingSourceClock $row.source ([long]$row.source_utc_ms)
 if(($source.SourceClock|ConvertTo-Json -Depth 5 -Compress) -cne ($row.source.SourceClock|ConvertTo-Json -Depth 5 -Compress)){throw 'Independent source clock pair changed.'}
 Assert-IncomingNear $hostHit.damage_mc $guestHit.requested_damage 'host/guest requested damage' .0001
 Assert-IncomingNear $row.damage_mc $hostHit.damage_mc 'independent JSONL damage' .0001
 Assert-IncomingNear $hostHit.damage_mc ($source.AttributedDamage*20./$hostHit.maximum) 'native HealthValue normalized to Minecraft hearts' .0001
 if($source.AttributedDamage -le 0 -or $null -eq $source.Before -or $null -eq $source.After -or $source.Before -le $source.After -or $source.After -lt 0){throw 'Native CombatHit must contain positive independent health loss.'}
 Assert-IncomingNear ($source.Before-$source.After) $source.AttributedDamage 'native HP delta / attributed CombatHit' .01
 if($source.SourceId -cnotmatch ('^'+[regex]::Escape($s.run)+'/(?<epoch>[0-9]{6})/(?<file>eventlog_[A-Za-z0-9_. -]+\.json)#(?<index>[0-9]+)$')){throw 'Native original event cursor malformed.'}
 $epoch=$Matches.epoch;$file=$Matches.file;$index=[int]$Matches.index;$key=$epoch+'/'+$file
 if(-not $parsedFiles.ContainsKey($key)){
  $manifest=@($incoming.SourceFiles|Where-Object {('{0:D6}' -f [int]$_.epoch) -ceq $epoch -and $_.file -ceq $file})
  if($manifest.Count -ne 1 -or $manifest[0].hash -cnotmatch '^[0-9a-f]{64}$'){throw 'Immutable native source manifest missing/duplicated.'}
  $filePath=Join-Path (Join-Path $epochRoot $epoch) $file
  if((Get-FileHash -LiteralPath $filePath).Hash.ToLowerInvariant() -cne $manifest[0].hash){throw 'Native raw event bytes differ from closed epoch hash.'}
  $raw=[IO.File]::ReadAllText($filePath,[Text.UTF8Encoding]::new($false,$true));$parsedFiles[$key]=ConvertFrom-GameplayIncomingTelemetry $raw '' $incoming.Begin.player_name
 }
 $actual=@($parsedFiles[$key].Hits|Where-Object Index -EQ $index)
 if($actual.Count -ne 1 -or $actual[0].EventSha256 -cne $source.EventSha256 -or $actual[0].GameMs -ne $source.GameMs -or
  $actual[0].AttackerGuid -cne $source.AttackerGuid -or $actual[0].VictimGuid -cne $source.VictimGuid -or $actual[0].AttackerName -cne $source.AttackerName){throw 'Raw native CombatHit does not match the forwarded event.'}
 Assert-IncomingNear $actual[0].AttributedDamage $source.AttributedDamage 'raw native attributed damage'
 Assert-IncomingNear $actual[0].Before $source.Before 'raw native prior health';Assert-IncomingNear $actual[0].After $source.After 'raw native resulting health'
 $nativeDamage+=$source.AttributedDamage
 $sourceProof.Add([pscustomobject]@{seq=$hostHit.seq;source_id=$source.SourceId;event_sha256=$source.EventSha256;source_utc_ms=$hostHit.source_utc_ms;source_clock_verified=$true;native_health_before=$source.Before;native_health_after=$source.After;native_damage=$source.AttributedDamage;damage_mc=$hostHit.damage_mc;minecraft_health_before=$guestHit.health_before;minecraft_health_after=$guestHit.health_after;result=$guestHit.result})
}
Assert-IncomingNear $nativeDamage $incoming.AttributedDamage 'native cumulative attributed damage'
[ordered]@{schema=1;kind='minecome_native_incoming_combat_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;fixture_run=$nativeFixture.run;
 actual_minecraft=$true;actual_native_npc=$true;scripted_guest_input=$true;physical_native_input_verified=$false;reciprocal_native_damage_verified=$true;
 native_events=$sourceProof.ToArray();minecraft_health_before=$f.initial_health;minecraft_health_after=$f.final_health;minecraft_damage=$applied;native_hit_in_inventory_verified=$true;inventory_hit_sequence=$f.inventory_hit_sequence;positive_damage_receipts=$positive.Count;
 native_attacker_removed=$true;native_proxy_health_writes=$incoming.Terminal.health_writes;native_proxy_health_restored=$incoming.Terminal.health_restored;
 minecraft_direct_health_writes=$false;native_cleanup_complete=$incoming.CleanupComplete;native_post_hit_composited_frames=$compositedDelta;native_post_hit_reprojected_frames=$reprojectedDelta;
 native_post_hit_counter_samples=$window;native_source_files_verified=$parsedFiles.Count}|
 ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $saved 'native-incoming-combat-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_INCOMING_COMBAT_PASS evidence=$saved"
