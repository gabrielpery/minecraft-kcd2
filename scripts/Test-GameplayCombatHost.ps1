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
 Accept-GameplayCombatReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='begin';result='ready';active=$true}) $now
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
 Accept-GameplayCombatReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='terminal';result='explicit_stop';timers_cancelled=$true}) ($now+460)
 Require ((Get-GameplayCombatHostState $state).CleanupComplete) 'Combat cleanup failed.'
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
 'PASS combat host strict identity, numeric bounds, duplicates, stale/replayed attack, atomic publication and cleanup (no game/network)'
}finally{
 $resolved=[IO.Path]::GetFullPath($dir);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'minecome-combat-*'){throw 'Unexpected test cleanup directory.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
