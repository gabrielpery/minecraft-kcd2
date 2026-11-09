#Requires -Version 7.3
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayCombatHost.ps1')
$dir=Join-Path ([IO.Path]::GetTempPath()) ('minecome-projectiles-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$id=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash='c'*64}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$file=Join-Path $dir 'projectiles.json';$checks=0
function Require([bool]$condition,[string]$message){$script:checks++;if(-not $condition){throw $message}}
function Refuses([scriptblock]$action){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Require $failed 'Invalid projectile payload accepted.'}
$request=[ordered]@{operation='trace';projectile='d'*32;segment=1;from=@{x=120.;y=2040.;z=57.6};to=@{x=120.;y=2043.;z=57.6};actor_token=0;damage_mc=0.;damage_fraction=0.}
$document=[ordered]@{schema=1;kind='minecome_gameplay_projectiles_guest_v1';run=$id.Run;world_id=$id.WorldId;target_pid=$id.Pid;target_start_filetime=$id.Start;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;seq=1;utc_ms=$now;request=$request}
function Write-Request{[IO.File]::WriteAllText($file,($document|ConvertTo-Json -Depth 8 -Compress))}
function Receipt([string]$Result='clear'){
    [pscustomobject]@{schema=1;run=$id.Run;event=('projectile_'+$request.operation);active=$true;seq=$document.seq;projectile=$request.projectile;segment=$request.segment;result=$Result;reason='';actor_token=0;contact=[pscustomobject]@{x=120.;y=2043.;z=57.6};normal=[pscustomobject]@{x=0.;y=0.;z=0.};actor=$null;before=$null;after=$null}
}
try{
 Write-Request;$parsed=Read-GameplayProjectileRequest $file $id $now;Require ($parsed.request.projectile -ceq $request.projectile) 'Projectile identity changed.'
 foreach($field in @('schema','target_pid','seq','utc_ms')){$original=$document[$field];$document[$field]=[string]$original;Write-Request;Refuses {Read-GameplayProjectileRequest $file $id $now};$document[$field]=$original}
 foreach($field in @('segment','actor_token','damage_mc','damage_fraction')){$original=$request[$field];$request[$field]=[string]$original;Write-Request;Refuses {Read-GameplayProjectileRequest $file $id $now};$request[$field]=$original}
 foreach($field in @('run','world_id','target_start_filetime','patch_run','patch_sha256')){$original=$document[$field];$document[$field]='wrong';Write-Request;Refuses {Read-GameplayProjectileRequest $file $id $now};$document[$field]=$original}
 foreach($bad in @(('D'*32),('d'*31),"x');")){$request.projectile=$bad;Write-Request;Refuses {Read-GameplayProjectileRequest $file $id $now}};$request.projectile='d'*32
 $request.damage_mc=1.;$request.damage_fraction=.05;Write-Request;Refuses {Read-GameplayProjectileRequest $file $id $now};$request.damage_mc=0.;$request.damage_fraction=0.
 $request.to.y=2045.;Write-Request;Refuses {Read-GameplayProjectileRequest $file $id $now};$request.to.y=2043.
 $request.from.x=[double]::NaN;Write-Request;Refuses {Read-GameplayProjectileRequest $file $id $now};$request.from.x=120.
 $raw=($document|ConvertTo-Json -Depth 8 -Compress).Replace('"segment":1','"segment":1,"segment":2');[IO.File]::WriteAllText($file,$raw);Refuses {Read-GameplayProjectileRequest $file $id $now}
 Write-Request;$state=New-GameplayProjectilesState $id $dir
 Require ((Get-GameplayProjectileCommands $state $now) -ceq "MineCome.GameplayProjectileTrace('$($id.Run)',1,'$($request.projectile)',1,120,2040,57.6,120,2043,57.6)") 'Trace command differs.'
 Require ((Get-GameplayProjectileCommands $state ($now+1)) -ceq '') 'Pending trace replayed.'
 $document.utc_ms++;Write-Request;Refuses {Get-GameplayProjectileCommands $state ($now+2)};$document.utc_ms=$now;Write-Request
 $document.seq=2;Write-Request;Refuses {Get-GameplayProjectileCommands $state ($now+2)};$document.seq=1;Write-Request
 $clear=Receipt;Accept-GameplayProjectileReceipt $state $clear ($now+20)
 $response=Get-Content -LiteralPath $state.HostFile -Raw|ConvertFrom-Json -Depth 8
 Require ($response.seq -eq 1 -and $response.utc_ms -eq $now+20 -and $response.request_utc_ms -eq $now -and $response.reply.operation -ceq 'trace' -and $state.Pending -eq $null) 'Trace response identity/time differs.'
 $published=Get-Content -LiteralPath $state.HostFile -Raw;Accept-GameplayProjectileReceipt $state $clear ($now+30)
 Require ((Get-Content -LiteralPath $state.HostFile -Raw) -ceq $published) 'Duplicate receipt refreshed response timestamp.'
 Require ((Get-GameplayProjectileCommands $state ($now+40)) -ceq '') 'Acknowledged request replayed.'
 $document.seq=2;$document.utc_ms=$now+50;$request.operation='impact';$request.actor_token=1;$request.damage_mc=7.;$request.damage_fraction=.35;Write-Request
 Refuses {Get-GameplayProjectileCommands $state ($now+50)}
 $request.operation='trace';$request.actor_token=0;$request.damage_mc=0.;$request.damage_fraction=0.;$request.segment=2;$request.from.y=2043.;$request.to.y=2046.;Write-Request
 Get-GameplayProjectileCommands $state ($now+50)|Out-Null
 $actor=Receipt 'actor';$actor.actor_token=1;$actor.contact.y=2045.;$actor.normal.y=-1.;$actor.actor=[pscustomobject]@{token=1;x=120.;y=2045.;z=56.;width=.6;height=1.8;health=100.;max_health=100.;alive=$true}
 $actor.actor.alive='true';Refuses {Accept-GameplayProjectileReceipt $state $actor ($now+60)};$actor.actor.alive=$true
 $actor.projectile='e'*32;Refuses {Accept-GameplayProjectileReceipt $state $actor ($now+60)};$actor.projectile=$request.projectile
 $actor.normal.y=2.;Refuses {Accept-GameplayProjectileReceipt $state $actor ($now+60)};$actor.normal.y=-1.
 $actor.contact.x=121.;Refuses {Accept-GameplayProjectileReceipt $state $actor ($now+60)};$actor.contact.x=120.
 Accept-GameplayProjectileReceipt $state $actor ($now+60);Require ($state.TraceGrants.Count -eq 1 -and $state.Actors -eq 1) 'Native contact grant missing.'
 $document.seq=3;$document.utc_ms=$now+70;$request.operation='impact';$request.actor_token=1;$request.damage_mc=7.;$request.damage_fraction=.35;Write-Request
 $impact=Get-GameplayProjectileCommands $state ($now+70);Require ($impact -ceq "MineCome.GameplayProjectileImpact('$($id.Run)',3,'$($request.projectile)',2,1,0.35)") 'Impact command differs.'
 Require ((Get-GameplayProjectileCommands $state ($now+71)) -ceq '') 'Pending native damage replayed.'
 $damage=Receipt 'damaged';$damage.actor_token=1;$damage.actor=$actor.actor;$damage.actor.health=65.;$damage.normal.y=-1.;$damage.contact.y=2045.;$damage.before=100.;$damage.after=65.
 $damage.after=101.;Refuses {Accept-GameplayProjectileReceipt $state $damage ($now+80)};$damage.after=65.
 Accept-GameplayProjectileReceipt $state $damage ($now+80);Require ($state.Damaged -eq 1 -and $state.Impacts -eq 1 -and $state.TraceGrants.Count -eq 0) 'Native damage proof missing.'
 $lethal=New-GameplayProjectilesState $id $dir;$lethal.Pending=($document|ConvertTo-Json -Depth 8 -Compress|ConvertFrom-Json -Depth 8);$lethal.PendingSinceUtcMs=$now+70
 $lethalDamage=($damage|ConvertTo-Json -Depth 8 -Compress|ConvertFrom-Json -Depth 8);$lethalDamage.after=0.;$lethalDamage.actor.health=0.;$lethalDamage.actor.alive=$false
 Accept-GameplayProjectileReceipt $lethal $lethalDamage ($now+80);Require ($lethal.Damaged -eq 1 -and $lethal.LastReply.reply.actor.health -eq 0) 'Lethal native impact refused.'
 $document.seq=4;$document.utc_ms=$now+90;Write-Request;Refuses {Get-GameplayProjectileCommands $state ($now+90)}
 $request.operation='trace';$request.actor_token=0;$request.damage_mc=0.;$request.damage_fraction=0.;$request.projectile='e'*32;$request.segment=1;Write-Request
 $expired=New-GameplayProjectilesState $id $dir;$document.seq=1;Write-Request;Refuses {Get-GameplayProjectileCommands $expired ($now+591)}
 $document.utc_ms=$now+100;Write-Request;$timeout=New-GameplayProjectilesState $id $dir;Get-GameplayProjectileCommands $timeout ($now+100)|Out-Null
 Refuses {Get-GameplayProjectileCommands $timeout ($now+1601)}
 Stop-GameplayProjectilesHost $timeout;Require ((Get-GameplayProjectilesHostState $timeout).CleanupComplete -and $timeout.Abandoned -eq 1) 'Abandoned trace cleanup missing.'
 $late=Receipt 'clear';$lastPublished=Get-Content -LiteralPath $state.HostFile -Raw;Accept-GameplayProjectileReceipt $timeout $late ($now+1700)
 Require ($timeout.AbandonedReceipt.seq -eq 1 -and (Get-Content -LiteralPath $state.HostFile -Raw) -ceq $lastPublished) 'Late acknowledgement was lost or republished.'
 [IO.File]::WriteAllText($state.HostFile+'.tmp','partial');$state.TemporaryClean=$false;Stop-GameplayProjectilesHost $state
 Require ((Get-GameplayProjectilesHostState $state).CleanupComplete -and -not [IO.File]::Exists($state.HostFile+'.tmp')) 'Projectile temporary cleanup missing.'
 "PASS projectile host: $checks strict identity/payload/immutability/ack/contact/damage/cleanup checks (no game/network)"
}finally{
 $resolved=[IO.Path]::GetFullPath($dir);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'minecome-projectiles-*'){throw 'Unexpected projectile test cleanup directory.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
