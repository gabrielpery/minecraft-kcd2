#Requires -Version 7.3
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayCombatHost.ps1')
$dir=Join-Path ([IO.Path]::GetTempPath()) ('minecome-combat-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$id=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash='c'*64}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$file=Join-Path $dir 'combat.json'
function Require([bool]$c,[string]$m){if(-not $c){throw $m}}
function Refuses([scriptblock]$action){$bad=$false;try{& $action|Out-Null}catch{$bad=$true};Require $bad 'Invalid combat payload accepted.'}
$hit=[ordered]@{seq=1;token=1;damage_mc=2.;damage_fraction=.1;weapon='minecraft:iron_sword';source_seq=1;origin=@{x=0.;y=0.;z=1.6};target=@{x=0.;y=1.7;z=1.6}}
$valid=[ordered]@{schema=1;kind='minecome_gameplay_combat_guest_v1';run=$id.Run;world_id=$id.WorldId;target_pid=$id.Pid;target_start_filetime=$id.Start;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;seq=1;utc_ms=$now;hurt_ack=0;hit=$hit}
function Write-Snapshot($v){[IO.File]::WriteAllText($file,($v|ConvertTo-Json -Depth 8 -Compress))}
try{
 Write-Snapshot $valid;$s=Read-GameplayCombatSnapshot $file $id $now;Require ($s.hit.damage_fraction -eq .1) 'Damage fraction changed.'
 Require ($null -eq (Read-GameplayCombatSnapshot $file $id ($now+501))) 'Stale guest renewed.'
 foreach($field in @('schema','target_pid','seq','utc_ms','hurt_ack')){$old=$valid[$field];$valid[$field]=[string]$old;Write-Snapshot $valid;Refuses {Read-GameplayCombatSnapshot $file $id $now};$valid[$field]=$old}
 $hit.damage_fraction=.2;Write-Snapshot $valid;Refuses {Read-GameplayCombatSnapshot $file $id $now};$hit.damage_fraction=.1
 $hit.token=257;Write-Snapshot $valid;Refuses {Read-GameplayCombatSnapshot $file $id $now};$hit.token=1
 $raw=($valid|ConvertTo-Json -Depth 8 -Compress).Replace('"token":1','"token":1,"token":2');[IO.File]::WriteAllText($file,$raw);Refuses {Read-GameplayCombatSnapshot $file $id $now}
 $state=New-GameplayCombatState $id $dir ($now+10000)
 Require ((Get-GameplayCombatCommands $state $now) -like '*Begin*') 'Begin missing.'
 foreach($policy in @($false,'True')){Refuses {Accept-GameplayCombatReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='begin';result='ready';active=$true;lock_policy_active=$policy}) $now}}
 Accept-GameplayCombatReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='begin';result='ready';active=$true;lock_policy_active=$true}) $now
 [IO.File]::Delete($file)
 Require ((Get-GameplayCombatCommands $state ($now+100)) -like '*Sample*') 'Sample missing.'
 $actor=[pscustomobject]@{token=1;x=0.;y=2.;z=0.;width=.6;height=1.8;health=100.;max_health=100.;alive=$true}
 Accept-GameplayCombatReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='sample';result='sampled';active=$true;seq=1;actors=@($actor);hit_ack=0}) ($now+100)
 $published=Get-Content -LiteralPath $state.HostFile -Raw|ConvertFrom-Json;Require ($published.actors.Count -eq 1 -and $published.hurts.Count -eq 0) 'Native snapshot/unsupported hurt differs.'
 $valid.utc_ms=$now+101;Write-Snapshot $valid
 Require ((Get-GameplayCombatCommands $state ($now+101)) -like '*Hit*0.1*') 'Fresh attributed hit missing.'
 Require ((Get-GameplayCombatCommands $state ($now+102)) -eq '') 'Pending attack repeated.'
 Accept-GameplayCombatReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='hit';result='damaged';active=$true;seq=1;hit_ack=1;before=100.;after=90.}) ($now+110)
 Require ($state.DamageCount -eq 1 -and $state.HitAck -eq 1) 'Native damage unacknowledged.'
 Require ((Get-GameplayCombatCommands $state ($now+111)) -eq '') 'Acknowledged attack repeated.'
 $hit.seq=2;$valid.seq=2;$valid.utc_ms=$now+450;Write-Snapshot $valid
 $command=Get-GameplayCombatCommands $state ($now+450);Require ($command -notlike '*Hit*' -and $state.HitAck -eq 2) 'Stale source attacked.'
 $valid.seq=1;Write-Snapshot $valid;Refuses {Get-GameplayCombatCommands $state ($now+451)}
 Require ((Get-GameplayCombatStopCommand $state) -like '*End*') 'Missing stop.'
 Accept-GameplayCombatReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='terminal';result='explicit_stop';timers_cancelled=$true;lock_policy_restored=$true}) ($now+460)
 Require ((Get-GameplayCombatHostState $state).CleanupComplete) 'Combat cleanup failed.'
 foreach($restored in @($false,'True')){
  $badState=New-GameplayCombatState $id $dir ($now+10000);$badState.BeginSent=$true;$badState.Stopping=$true
  Accept-GameplayCombatReceipt $badState ([pscustomobject]@{schema=1;run=$id.Run;event='terminal';result='explicit_stop';timers_cancelled=$true;lock_policy_restored=$restored}) ($now+461)
  Require (-not (Get-GameplayCombatHostState $badState).CleanupComplete -and [bool]$badState.Failure) 'Unrestored or malformed lock cleanup accepted.'
 }
 # Exercise a real Windows sharing conflict. The bounded failed attempt leaves
 # both old destination and original new bytes intact; retry only replaces bytes.
 $source=Join-Path $dir 'share.tmp';$destination=Join-Path $dir 'share.json'
 [IO.File]::WriteAllText($source,'new');[IO.File]::WriteAllText($destination,'old')
 $held=[IO.FileStream]::new($destination,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{Refuses {Publish-GameplayCombatFile $source $destination 10};Require ([IO.File]::ReadAllText($source) -ceq 'new') 'Failed replacement consumed original bytes.'}finally{$held.Dispose()}
 Publish-GameplayCombatFile $source $destination
 Require ([IO.File]::ReadAllText($destination) -ceq 'new' -and -not [IO.File]::Exists($source)) 'Replacement retry failed.'
 [IO.File]::WriteAllText($state.HostFile+'.tmp','pending');$state.TemporaryClean=$false;Get-GameplayCombatStopCommand $state|Out-Null
 Require ($state.TemporaryClean -and -not [IO.File]::Exists($state.HostFile+'.tmp')) 'Stop left temporary publication.'
 # Native incoming integration: exact name generation -> GUID pin -> immutable
 # hurt, retained attacker after disappearance, and cumulative Minecraft ACK.
 [IO.File]::Delete($file)
 $incoming=New-GameplayCombatState $id $dir ($now+10000);$incoming.BeginSent=$true;$incoming.Begin=[pscustomobject]@{result='ready'}
 $incoming.Incoming.Enabled=$true;$incoming.Incoming.EpochRoot=($dir+'/incoming-epochs').Replace('\','/')
 [void][IO.Directory]::CreateDirectory($incoming.Incoming.EpochRoot+'/000000')
 Require ((Get-GameplayCombatCommands $incoming $now) -like '*IncomingBegin*') 'Incoming native begin missing.'
 Accept-GameplayIncomingReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='begin';player_name='Dude';native_clock_ms=1000.;native_maximum=100.;path=$incoming.Incoming.EpochRoot+'/000000/'}) ($now+10)
 # First combat Sample was dispatched alongside incoming Begin.
 Accept-GameplayIncomingReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='identity';seq=1;player_name='Dude';native_clock_ms=1100.;actors=@([pscustomobject]@{token=1;name='Enemy';first_seen_ms=1100.})}) ($now+100)
 Accept-GameplayCombatReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='sample';result='sampled';active=$true;seq=1;actors=@($actor);hit_ack=0}) ($now+100)
 $event=[ordered]@{t='2026-11-09T13:26:11';gt=1350;pt=.1;cause=@{name='CombatHit';attacker=@{guid='22222222-2222-4222-8222-222222222222';name='Enemy'};victim=@{guid='11111111-1111-4111-8111-111111111111';name='Dude'};attackType=6;damageType=4};effects=@(
  @{name='SoulState';soul=@{guid='11111111-1111-4111-8111-111111111111'};selector='health';oldState=100.;newState=96.;value=-4.},
  @{name='HealthValue';soul=@{guid='11111111-1111-4111-8111-111111111111'};opponent=@{guid='22222222-2222-4222-8222-222222222222'};value=-4.;deathReason='DR_Combat'})}
 [IO.File]::WriteAllText($incoming.Incoming.EpochRoot+'/000000/eventlog_test.json',(ConvertTo-Json -InputObject @($event) -Depth 10 -Compress))
 Require ((Get-GameplayIncomingCommands $incoming ($now+400)) -like '*IncomingRotate*') 'Incoming native rotate missing.'
 Accept-GameplayIncomingReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='closed_segment';sequence=1;native_clock_ms=1400.;closed_path=$incoming.Incoming.EpochRoot+'/000000/';next_path=$incoming.Incoming.EpochRoot+'/000001/'}) ($now+410)
 Update-GameplayIncomingEpochs $incoming ($now+440)
 Require ($incoming.Incoming.HurtSequence -eq 1 -and $incoming.Incoming.Pending[0].Hurt.damage -eq .8 -and $incoming.Incoming.Pending[0].Hurt.source_utc_ms -eq $now+350) 'Native damage fraction/source timestamp changed.'
 Require ($incoming.Incoming.PlayerGuid -ceq '11111111-1111-4111-8111-111111111111' -and $incoming.Incoming.Identities[1].Guid -ceq '22222222-2222-4222-8222-222222222222') 'Native exact-name GUID pin missing.'
 $null=Get-GameplayCombatCommands $incoming ($now+500)
 Accept-GameplayIncomingReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='identity';seq=2;player_name='Dude';native_clock_ms=1500.;actors=@()}) ($now+510)
 Accept-GameplayCombatReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='sample';result='sampled';active=$true;seq=2;actors=@();hit_ack=0}) ($now+510)
 $packet=Get-Content -LiteralPath $incoming.HostFile -Raw|ConvertFrom-Json
 Require ($packet.hurts.Count -eq 1 -and $packet.actors.Count -eq 1 -and $packet.actors[0].token -eq 1) 'Pending hurt lost its captured attacker.'
 Refuses {Accept-GameplayIncomingAck $incoming 2}
 Accept-GameplayIncomingAck $incoming 1
 Require ($incoming.Incoming.Pending.Count -eq 0 -and $incoming.Incoming.HurtAck -eq 1) 'Incoming hurt was not retired by original ACK.'
 Refuses {Accept-GameplayIncomingAck $incoming 0}
 $notification=Get-GameplayIncomingAppliedCommand $incoming ($now+520)
 Require ($notification -ceq "MineCome.GameplayCombatIncomingApplied('$($id.Run)',1)") 'Consumed hurt ACK was not sent to native.'
 Require ((Get-GameplayIncomingAppliedCommand $incoming ($now+550)) -ceq '') 'Pending applied notification retried too frequently.'
 Require ((Get-GameplayIncomingAppliedCommand $incoming ($now+600)) -ceq $notification -and $incoming.Incoming.AppliedPendingSinceUtcMs -eq $now+520) 'Retry changed or renewed the original applied notification.'
 $applied=[pscustomobject]@{schema=1;run=$id.Run;event='applied';ack=1;native_clock_ms=1600.}
 Accept-GameplayIncomingReceipt $incoming $applied ($now+610)
 Accept-GameplayIncomingReceipt $incoming $applied ($now+615)
 Require ($incoming.Incoming.AppliedAck -eq 1 -and $incoming.Incoming.AppliedReceipts.Count -eq 1 -and (Get-GameplayIncomingAppliedCommand $incoming ($now+620)) -ceq '') 'Repeated applied ACK reopened its native reaction window.'
 $applied.native_clock_ms=1601.;Refuses {Accept-GameplayIncomingReceipt $incoming $applied ($now+621)};$applied.native_clock_ms=1600.
 $incoming.Incoming.HurtSequence=3;Accept-GameplayIncomingAck $incoming 3
 Require ((Get-GameplayIncomingAppliedCommand $incoming ($now+650)) -like '*Applied*3)') 'Coalesced consumed ACK was lost.'
 Refuses {Get-GameplayIncomingAppliedCommand $incoming ($now+1651)}
 Accept-GameplayIncomingReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='applied';ack=3;native_clock_ms=1650.}) ($now+660)
 # The camera-ACK wait may forward only a fresh owned guest ACK, without
 # advancing combat sample cadence or dispatching its pending melee request.
 $incoming.Incoming.HurtSequence=4;$valid.seq=1;$valid.utc_ms=$now+680;$valid.hurt_ack=4;$valid.hit=$null;Write-Snapshot $valid
 $previousSequence=$incoming.Sequence
 Require ((Get-GameplayCombatUrgentCommands $incoming ($now+690)) -like '*Applied*4)' -and $incoming.Sequence -eq $previousSequence -and -not $incoming.PendingHit) 'Urgent applied ACK changed normal combat cadence.'
 Accept-GameplayIncomingReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='applied';ack=4;native_clock_ms=1690.}) ($now+700)
 $incoming.Stopping=$true
 Accept-GameplayIncomingReceipt $incoming ([pscustomobject]@{schema=1;run=$id.Run;event='terminal';cvars_restored=$true;buff_restored=$true;health_restored=$true}) ($now+550)
 Require ((Get-GameplayIncomingHostState $incoming).CleanupComplete) 'Incoming native restoration not acknowledged.'
 'PASS combat host strict identity, numeric bounds, duplicates, stale/replayed attack, atomic publication and cleanup (no game/network)'
}finally{
 $resolved=[IO.Path]::GetFullPath($dir);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'minecome-combat-*'){throw 'Unexpected test cleanup directory.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
