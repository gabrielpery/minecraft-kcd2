#Requires -Version 7.3
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayIncomingHost.ps1')
$checks=0;$victim='11111111-1111-4111-8111-111111111111';$attacker='22222222-2222-4222-8222-222222222222';$other='33333333-3333-4333-8333-333333333333'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('minecome-incoming-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
function Require([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Refuses([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Require $failed 'Invalid native telemetry accepted.'}
function Event([double]$Damage=3.2,[long]$GameMs=1000){
 [ordered]@{t='2026-11-09T09:31:56';gt=$GameMs;pt=.0336729;cause=[ordered]@{name='CombatHit';attacker=@{guid=$attacker};victim=@{guid=$victim};attackType=6;damageType=4};effects=@(
  [ordered]@{name='SoulState';soul=@{guid=$victim};selector='health';oldState=100.;newState=(100.-$Damage);value=-$Damage},
  [ordered]@{name='HealthValue';soul=@{guid=$victim};opponent=@{guid=$attacker};value=-$Damage;subpartId=38;isKill=$false;deathReason='DR_Combat'})}
}
function Json($Events){ConvertTo-Json -InputObject @($Events) -Depth 12 -Compress}
try{
 $e=Event;$json=Json @($e);$batch=ConvertFrom-GameplayIncomingTelemetry $json $victim
 Require ($batch.TotalEvents -eq 1 -and $batch.Hits.Count -eq 1 -and $batch.Hits[0].AttributedDamage -eq 3.2 -and [Math]::Abs($batch.Hits[0].AppliedDamage-3.2) -lt .000001) 'Attributed/applied native damage differs.'
 Require ($batch.Hits[0].GameMs -eq 1000 -and $batch.Hits[0].LoggedWallTime -ceq '2026-11-09T09:31:56' -and $batch.Hits[0].AttackerGuid -ceq $attacker) 'Native source time/identity changed.'
 foreach($pair in @(@(0,4),@(0,5),@(1,5),@(1,6),@(2,4),@(4,4),@(5,4),@(6,4),@(7,4),@(9,4))){
  $e=Event;$e.cause.attackType=$pair[0];$e.cause.damageType=$pair[1]
  $classified=(ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim).Hits[0]
  Require ((Get-GameplayIncomingDamageKind $classified) -ceq 'melee') 'Official melee base/weapon-override pair not classified.'
 }
 foreach($pair in @(@(0,6),@(1,4),@(2,5),@(3,4),@(8,1),@(6,5),@(99,4))){
  Require ((Get-GameplayIncomingDamageKind ([pscustomobject]@{CauseName='CombatHit';AttackType=$pair[0];DamageType=$pair[1]})) -ceq '') 'Unsupported attack pair was guessed.'
 }
 Require ((Get-GameplayIncomingDamageKind ([pscustomobject]@{CauseName='ProjectileHit';AttackType=6;DamageType=4})) -ceq '') 'Unverified projectile source became melee.'
 Require ((ConvertFrom-GameplayIncomingTelemetry '[]' $victim).Hits.Count -eq 0) 'Empty native batch produced damage.'
 Refuses {ConvertFrom-GameplayIncomingTelemetry '{}' $victim}
 Refuses {ConvertFrom-GameplayIncomingTelemetry '[{}]' $victim}
 Refuses {ConvertFrom-GameplayIncomingTelemetry ($json.Replace('"gt":1000','"gt":1000,"gt":1001')) $victim}
 Refuses {ConvertFrom-GameplayIncomingTelemetry ($json.Replace('"gt":1000','"gt":"1000"')) $victim}
 Refuses {ConvertFrom-GameplayIncomingTelemetry ($json.Replace('"gt":1000','"gt":1000.5')) $victim}
 Refuses {ConvertFrom-GameplayIncomingTelemetry ($json.Replace('2026-11-09T09:31:56','invalid-date')) $victim}
 Refuses {ConvertFrom-GameplayIncomingTelemetry ($json.Replace($attacker,$attacker.ToUpperInvariant().Replace('2222-4222','XYZ2-4222'))) $victim}
 $e=Event;$e.effects[1].opponent.guid=$other;Refuses {ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim}
 $e=Event;$e.effects[1].deathReason='DR_Fall';Refuses {ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim}
 $e=Event;$e.effects+=@{};Require ((ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim).Hits.Count -eq 1) 'Native empty non-health effect rejected.'
 $e=Event;$e.effects+=@{value=-3.2};Refuses {ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim}
 $e=Event;$e.effects+= $e.effects[1];Refuses {ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim}
 $e=Event;$e.effects=@($e.effects[0]);Refuses {ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim}
 $e=Event;$e.effects[0].newState=101.;Refuses {ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim}
 $e=Event;$e.cause.victim.guid=$other;Require ((ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim).Hits.Count -eq 0) 'Foreign victim damaged player.'
 $e=Event;$e.cause.name='OtherCause';Require ((ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim).Hits.Count -eq 0) 'Noncombat source produced attack.'
 $e=Event;$e.cause=@{};Require ((ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim).Hits.Count -eq 0) 'Native anonymous maintenance cause became a hit.'
 $e=Event 0;Require ((ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim).Hits.Count -eq 0) 'Zero native damage became hurt.'
 $e=Event;$e.effects[1].value=0.;Refuses {ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim}
 # Synthetic disagreement only tests separate field preservation. Native HP1
 # combat evidence below reports HealthValue0, not pre-clamp attack damage.
 $e=Event;$e.effects[0].oldState=1.;$e.effects[0].newState=1.;$e.effects[0].value=0.
 $clamped=(ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim).Hits[0]
 Require ($clamped.AttributedDamage -eq 3.2 -and $clamped.AppliedDamage -eq 0) 'Synthetic attributed value was replaced by health delta.'
 $e=Event;$e.effects=@($e.effects[1]);$withoutState=(ConvertFrom-GameplayIncomingTelemetry (Json @($e)) $victim).Hits[0]
 Require ($withoutState.AttributedDamage -eq 3.2 -and $null -eq $withoutState.AppliedDamage) 'Missing native health state fabricated delta.'
 $state=New-GameplayIncomingReader $victim 1000
 $hits=@(Add-GameplayIncomingTelemetryBatch $state 'epoch1/file0' $json 10000)
 Require ($hits.Count -eq 1 -and $hits[0].SourceId -ceq 'epoch1/file0#0' -and $hits[0].CapturedUtcMs -eq 10000) 'Native source cursor/capture changed.'
 Require (@(Add-GameplayIncomingTelemetryBatch $state 'epoch1/file0' $json 20000).Count -eq 0 -and $state.Sources['epoch1/file0'].CapturedUtcMs -eq 10000) 'Repeated publication repeated damage or renewed capture.'
 Require (@(Add-GameplayIncomingTelemetryBatch $state 'epoch2/file0' $json 21000).Count -eq 1) 'Distinct immutable source collapsed identical attack.'
 Refuses {Add-GameplayIncomingTelemetryBatch $state 'epoch1/file0' (Json @((Event 4))) 22000}
 $same=@(Add-GameplayIncomingTelemetryBatch $state 'epoch3/file0' (Json @((Event),(Event))) 23000)
 Require ($same.Count -eq 2 -and $same[0].SourceId -cne $same[1].SourceId -and $same[0].EventSha256 -ceq $same[1].EventSha256) 'Actual identical same-frame attacks collapsed.'
 Require (@(Add-GameplayIncomingTelemetryBatch $state 'epoch4/file0' (Json @((Event 3.2 999))) 24000).Count -eq 0 -and $state.OldHits -eq 1) 'Pre-lease event admitted.'
 $file=Join-Path $dir 'partial.json';$reader=New-GameplayIncomingReader $victim 0
 [IO.File]::WriteAllText($file,$json.Substring(0,30))
 Require (-not (Read-GameplayIncomingTelemetryFile $reader $file 'epoch1/a' 10000).Complete) 'Partial JSON published.'
 Require (-not (Read-GameplayIncomingTelemetryFile $reader $file 'epoch1/a' 10400).Complete -and $reader.Incomplete['epoch1/a'] -eq 10000) 'Partial observation renewed deadline.'
 [IO.File]::WriteAllText($file,$json);$complete=Read-GameplayIncomingTelemetryFile $reader $file 'epoch1/a' 10499
 Require ($complete.Complete -and $complete.Hits.Count -eq 1 -and $reader.Incomplete.Count -eq 0) 'Completed native file not admitted.'
 Require ((Read-GameplayIncomingTelemetryFile $reader $file 'epoch1/a' 10500).Hits.Count -eq 0) 'Unchanged file replayed damage.'
 [IO.File]::WriteAllText($file,(Json @((Event 4))));Refuses {Read-GameplayIncomingTelemetryFile $reader $file 'epoch1/a' 10501}
 [IO.File]::WriteAllText($file,'[');$null=Read-GameplayIncomingTelemetryFile $reader $file 'epoch2/a' 11000
 Refuses {Read-GameplayIncomingTelemetryFile $reader $file 'epoch2/a' 11500}
 [IO.File]::WriteAllText($file,$json);Refuses {Read-GameplayIncomingTelemetryFile $reader $file 'epoch2/a' 11501}
 [IO.File]::WriteAllBytes($file,[byte[]]@(0xff,0xff));Refuses {Read-GameplayIncomingTelemetryFile $reader $file 'epoch3/a' 12000}
 [IO.File]::WriteAllText($file,$json)
 $held=[IO.FileStream]::new($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try{Require (-not (Read-GameplayIncomingTelemetryFile $reader $file 'epoch4/a' 13000).Complete) 'Windows sharing conflict was not deferred.'}finally{$held.Dispose()}
 Require ((Read-GameplayIncomingTelemetryFile $reader $file 'epoch4/a' 13010).Hits.Count -eq 1) 'Windows sharing retry failed.'
 [IO.File]::WriteAllText($file,'[');$bounded=New-GameplayIncomingReader $victim 0
 for($n=0;$n -lt 32;$n++){$null=Read-GameplayIncomingTelemetryFile $bounded $file ('partial/'+$n) 14000}
 Refuses {Read-GameplayIncomingTelemetryFile $bounded $file 'partial/33' 14000}
 $epochState=New-GameplayIncomingEpochReader ('a'*32) $victim 1000 10000 10020
 $epochFiles=@([pscustomobject]@{Name='eventlog_test_1.json';Text=(Json @((Event 3.2 1350)))})
 $epochHits=@(Add-GameplayIncomingClosedEpoch $epochState 1 1400 10400 10420 10430 $epochFiles)
 Require ($epochHits.Count -eq 1 -and $epochHits[0].SourceUtcMs -eq 10350 -and $epochHits[0].CapturedUtcMs -eq 10430) 'Original native timestamp did not use its fixed anchor.'
 Require (@(Add-GameplayIncomingClosedEpoch $epochState 1 1400 10900 10920 10930 $epochFiles).Count -eq 0 -and $epochHits[0].SourceUtcMs -eq 10350) 'Epoch reread repeated or renewed original damage.'
 $changed=@([pscustomobject]@{Name='eventlog_test_1.json';Text=(Json @((Event 4.2 1350)))})
 Refuses {Add-GameplayIncomingClosedEpoch $epochState 1 1400 10400 10420 10430 $changed}
 Refuses {Add-GameplayIncomingClosedEpoch $epochState 3 1800 10800 10820 10830 @()}
 Refuses {Add-GameplayIncomingClosedEpoch $epochState 2 1800 11800 11820 11830 @()}
 $badFiles=@($epochFiles[0],[pscustomobject]@{Name='eventlog_test_2.json';Text='[{}]'})
 Refuses {Add-GameplayIncomingClosedEpoch $epochState 2 1800 10800 10820 10830 $badFiles}
 Require ($epochState.LastSequence -eq 1 -and $epochState.Hits -eq 1) 'Invalid whole epoch partially committed.'
 Require (@(Add-GameplayIncomingClosedEpoch $epochState 2 1800 10800 10820 10830 @()).Count -eq 0) 'Empty epoch invented a hit.'
 Refuses {Add-GameplayIncomingClosedEpoch $epochState 1 1400 10400 10420 10430 $epochFiles}
 $buffered=@([pscustomobject]@{Name='eventlog_test_3.json';Text=(Json @((Event 3.2 1700),(Event 3.2 1700)))})
 $bufferedHits=@(Add-GameplayIncomingClosedEpoch $epochState 3 2200 11200 11220 11230 $buffered)
 Require ($bufferedHits.Count -eq 2 -and $bufferedHits[0].SourceUtcMs -eq 10700 -and $bufferedHits[0].SourceId -cne $bufferedHits[1].SourceId) 'Buffered or same-frame native attacks were discarded.'
 $staleState=New-GameplayIncomingEpochReader ('a'*32) $victim 1000 10000 10020
 Refuses {Add-GameplayIncomingClosedEpoch $staleState 1 4000 13000 13020 13030 $epochFiles}
 Refuses {New-GameplayIncomingEpochReader ('a'*32) $victim 1000 10000 10251}
 $future=@([pscustomobject]@{Name='eventlog_test_1.json';Text=(Json @((Event 3.2 1500)))})
 Refuses {Add-GameplayIncomingClosedEpoch $staleState 1 1400 10400 10420 10430 $future}
 $badName=@([pscustomobject]@{Name='../eventlog_test.json';Text='[]'})
 Refuses {Add-GameplayIncomingClosedEpoch $staleState 1 1400 10400 10420 10430 $badName}
 # A real engine clock can run slower than wall time during rendering stalls.
 # Buffered hits use their historical enclosing anchors, never the latest offset.
 $drift=New-GameplayIncomingEpochReader ('a'*32) $victim 1000 10000 10020
 $null=Add-GameplayIncomingClosedEpoch $drift 1 1400 10400 10420 10430 @()
 $null=Add-GameplayIncomingClosedEpoch $drift 2 1800 10900 10920 10930 @()
 $driftHits=@(Add-GameplayIncomingClosedEpoch $drift 3 2200 11400 11420 11430 $buffered)
 Require ($driftHits.Count -eq 2 -and $driftHits[0].SourceUtcMs -eq 10775 -and $driftHits[0].SourceClock.Before.NativeClockMs -eq 1400 -and $driftHits[0].SourceClock.After.NativeClockMs -eq 1800) 'Buffered native event did not use its original enclosing anchors.'
 Require (@(Add-GameplayIncomingClosedEpoch $drift 3 2200 12000 12020 12030 $buffered).Count -eq 0 -and $driftHits[0].SourceUtcMs -eq 10775) 'Rolling anchors renewed an admitted hit timestamp.'
 $null=Add-GameplayIncomingClosedEpoch $drift 4 2600 11900 11920 11930 @()
 Refuses {Add-GameplayIncomingClosedEpoch $drift 5 3000 12901 12921 12930 @()}
 $capture=Join-Path $PSScriptRoot '../runtime/evidence/combat-stream-watch-0ba69e97163c4ec9b8ce3e6d1e681160'
 $capturedHits=0;$capturedDamage=0.
 if(Test-Path -LiteralPath $capture){
  foreach($name in @('000.json','001.json','002.json','003.json','004.json')){
   $actual=ConvertFrom-GameplayIncomingTelemetry ([IO.File]::ReadAllText((Join-Path $capture $name))) '4c2dcffb-dea1-6263-72d7-b39f4db2d8b5'
   $capturedHits+=$actual.Hits.Count;foreach($hit in $actual.Hits){$capturedDamage+=$hit.AttributedDamage}
  }
  Require ($capturedHits -eq 5 -and [Math]::Abs($capturedDamage-21.18691) -lt .00001) 'Actual captured native punch evidence did not parse exactly.'
 }
 $clampCapture=Join-Path $PSScriptRoot '../runtime/evidence/incoming-validation-20261109-131516-bbc1a2c79a1147dbbc666fd4c426b194/epochs/000021/eventlog_xephi_2026-11-09t13-15-24.json'
 if(Test-Path -LiteralPath $clampCapture){
  $actualClamp=ConvertFrom-GameplayIncomingTelemetry ([IO.File]::ReadAllText($clampCapture)) '4c2dcffb-dea1-6263-72d7-b39f4db2d8b5'
  Require ($actualClamp.TotalEvents -eq 1 -and $actualClamp.Hits.Count -eq 0) 'Live HP1 CombatHit invented damage from zero HealthValue.'
 }
 $maintenanceCapture=Join-Path $PSScriptRoot '../runtime/evidence/incoming-validation-20261109-132342-b345dbc14c7148b7b864f4e1796f0335/epochs/000010/eventlog_xephi_2026-11-09t13-23-46.json'
 if(Test-Path -LiteralPath $maintenanceCapture){
  $actualMaintenance=ConvertFrom-GameplayIncomingTelemetry ([IO.File]::ReadAllText($maintenanceCapture)) '4c2dcffb-dea1-6263-72d7-b39f4db2d8b5'
  Require ($actualMaintenance.TotalEvents -eq 2 -and $actualMaintenance.Hits.Count -eq 1 -and $actualMaintenance.Hits[0].AttributedDamage -eq 3.2095) 'Native maintenance mixed refill into attributed damage.'
 }
 "PASS native incoming reader: $checks checks; captured native punches=$capturedHits damage=$capturedDamage; no games/network, no lossless-source claim"
}finally{
 $resolved=[IO.Path]::GetFullPath($dir);$temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'minecome-incoming-*'){throw 'Unexpected incoming test cleanup directory.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
