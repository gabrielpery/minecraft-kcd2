#Requires -Version 7.3
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayCombatHost.ps1')
$dir=Join-Path ([IO.Path]::GetTempPath()) ('minecome-blasts-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$id=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash='c'*64}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$file=Join-Path $dir 'blasts.json';$checks=0
function Require([bool]$ok,[string]$why){$script:checks++;if(-not $ok){throw $why}}
function Refuses([scriptblock]$action){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Require $failed 'Invalid blast request/receipt accepted.'}
$request=[ordered]@{operation='prepare';explosion='d'*32;owner='e'*32;prepare_seq=0;center=@{x=0.;y=100.;z=.5};power=4.;targets=@()}
$document=[ordered]@{schema=1;kind='minecome_gameplay_blasts_guest_v1';run=$id.Run;world_id=$id.WorldId;target_pid=$id.Pid;target_start_filetime=$id.Start;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;seq=1;utc_ms=$now;request=$request}
function Write-Request{[IO.File]::WriteAllText($file,($document|ConvertTo-Json -Depth 8 -Compress))}
function Receipt([string]$Result='prepared'){
 [pscustomobject]@{schema=1;run=$id.Run;event=('blast_'+$request.operation);active=$true;seq=$document.seq;explosion=$request.explosion;owner=$request.owner;
 prepare_seq=$(if($request.operation -ceq 'prepare'){$document.seq}else{$request.prepare_seq});center=[pscustomobject]@{x=0.;y=100.;z=.5};power=4.;result=$Result;reason='';actors=@();outcomes=@()}
}
function Actor([int]$Token,[double]$Y){[pscustomobject]@{token=$Token;x=0.;y=$Y;z=0.;width=.6;height=1.8;health=100.;max_health=100.;alive=$true;exposure=('1'*45)}}
try{
 Write-Request;Require ((Read-GameplayBlastRequest $file $id $now).request.explosion -ceq $request.explosion) 'Blast identity changed.'
 foreach($field in @('schema','seq','utc_ms','target_pid')){$old=$document[$field];$document[$field]=[string]$old;Write-Request;Refuses {Read-GameplayBlastRequest $file $id $now};$document[$field]=$old}
 foreach($field in @('run','world_id','target_start_filetime','patch_run','patch_sha256')){$old=$document[$field];$document[$field]='wrong';Write-Request;Refuses {Read-GameplayBlastRequest $file $id $now};$document[$field]=$old}
 foreach($field in @('explosion','owner')){$old=$request[$field];$request[$field]='X'*32;Write-Request;Refuses {Read-GameplayBlastRequest $file $id $now};$request[$field]=$old}
 $request.power=5.;Write-Request;Refuses {Read-GameplayBlastRequest $file $id $now};$request.power=4.
 $request.prepare_seq='0';Write-Request;Refuses {Read-GameplayBlastRequest $file $id $now};$request.prepare_seq=0
 $raw=($document|ConvertTo-Json -Depth 8 -Compress).Replace('"power":4.0','"power":4.0,"power":4.0');[IO.File]::WriteAllText($file,$raw);Refuses {Read-GameplayBlastRequest $file $id $now}
 Write-Request;$state=New-GameplayBlastsState $id $dir;$command=Get-GameplayBlastCommands $state $now
 Require ($command -ceq "MineCome.GameplayBlastPrepare('$($id.Run)',1,'$($request.explosion)','$($request.owner)',0,100,0.5,4)") 'Native prepare command differs.'
 Require ((Get-GameplayBlastCommands $state ($now+1)) -ceq '') 'Pending blast prepare replayed.'
 $document.utc_ms++;Write-Request;Refuses {Get-GameplayBlastCommands $state ($now+2)};$document.utc_ms=$now;Write-Request
 $document.seq=2;Write-Request;Refuses {Get-GameplayBlastCommands $state ($now+2)};$document.seq=1;Write-Request
 $prepared=Receipt;$prepared.actors=@((Actor 1 102),(Actor 2 104));$prepared.actors[0].exposure='1'*44
 Refuses {Accept-GameplayBlastReceipt $state $prepared ($now+20)};$prepared.actors[0].exposure='1'*45
 $prepared.actors[1].token=1;Refuses {Accept-GameplayBlastReceipt $state $prepared ($now+20)};$prepared.actors[1].token=2
 $prepared.prepare_seq=2;Refuses {Accept-GameplayBlastReceipt $state $prepared ($now+20)};$prepared.prepare_seq=1
 Accept-GameplayBlastReceipt $state $prepared ($now+20);$published=[IO.File]::ReadAllText($state.HostFile)
 Accept-GameplayBlastReceipt $state $prepared ($now+25);Require ([IO.File]::ReadAllText($state.HostFile) -ceq $published) 'Duplicate prepare renewed receipt UTC.'
 Require ($state.Prepared -eq 1 -and $state.LastPrepare.request_utc_ms -eq $now -and $state.LastPrepare.utc_ms -eq $now+20) 'Prepared grant lost original timestamps.'
 $document.seq=2;$document.utc_ms=$now+30;$request.operation='commit';$request.prepare_seq=1
 $request.targets=@(@{actor_token=1;damage_mc=5.;damage_fraction=.25},@{actor_token=2;damage_mc=2.;damage_fraction=.1});Write-Request
 $request.targets[1].actor_token=1;Write-Request;Refuses {Read-GameplayBlastRequest $file $id ($now+30)};$request.targets[1].actor_token=2
 $request.targets[0].damage_fraction=.5;Write-Request;Refuses {Read-GameplayBlastRequest $file $id ($now+30)};$request.targets[0].damage_fraction=.25
 $request.targets[1].actor_token=3;Write-Request;Refuses {Get-GameplayBlastCommands $state ($now+30)};$request.targets[1].actor_token=2
 $request.center.x=.1;Write-Request;Refuses {Get-GameplayBlastCommands $state ($now+30)};$request.center.x=0.
 Write-Request;$command=Get-GameplayBlastCommands $state ($now+30);Require ($command.EndsWith("4,'1:0.25;2:0.1')")) 'Burst fractions changed in native command.'
 Require ((Get-GameplayBlastCommands $state ($now+31)) -ceq '') 'Pending blast setter replayed.'
 $applied=Receipt 'applied';$applied.outcomes=@([pscustomobject]@{actor_token=1;result='damaged';reason='';before=100.;after=75.},[pscustomobject]@{actor_token=2;result='no_damage';reason='';before=100.;after=100.})
 $applied.outcomes[0].after=101.;Refuses {Accept-GameplayBlastReceipt $state $applied ($now+40)};$applied.outcomes[0].after=75.
 Accept-GameplayBlastReceipt $state $applied ($now+40);$published=[IO.File]::ReadAllText($state.HostFile);Accept-GameplayBlastReceipt $state $applied ($now+50)
 Require ($state.Commits -eq 1 -and $state.Damaged -eq 1 -and $state.Completed.Count -eq 1 -and [IO.File]::ReadAllText($state.HostFile) -ceq $published) 'Burst outcome replayed or receipt renewed.'
 $applied.outcomes[0].after=1.;Require ($state.Completed.Peek().reply.outcomes[0].after -eq 75.) 'Historical burst evidence mutated with native receipt.'
 $document.seq=3;$document.utc_ms=$now+60;Write-Request;Refuses {Get-GameplayBlastCommands $state ($now+60)}
 $request.operation='prepare';$request.prepare_seq=0;$request.targets=@();Write-Request;Refuses {Get-GameplayBlastCommands $state ($now+60)}
 # A second TNT reached detonation before the first TNT's later commit UTC.
 # Keep its original source time: a fresh older source is valid, a stale one is not.
 $request.explosion='f'*32;$document.utc_ms=$now-500;Write-Request;Refuses {Get-GameplayBlastCommands $state ($now+60)}
 $document.utc_ms=$now+10;Write-Request;$queued=Get-GameplayBlastCommands $state ($now+60)
 Require ($queued.Contains("GameplayBlastPrepare('$($id.Run)',3,") -and $state.Pending.utc_ms -eq $now+10) 'Fresh queued TNT lost its original earlier source UTC.'
 $document.utc_ms=$now+11;Write-Request;Refuses {Get-GameplayBlastCommands $state ($now+61)};$document.utc_ms=$now+10;Write-Request
 $empty=Receipt;Accept-GameplayBlastReceipt $state $empty ($now+70)
 Require ($state.LastPrepare.request_utc_ms -eq $now+10 -and $state.LastPrepare.utc_ms -eq $now+70) 'Queued TNT receipt renewed its source time.'
 $document.seq=4;$document.utc_ms=$now+80;$request.operation='commit';$request.prepare_seq=3;Write-Request;Get-GameplayBlastCommands $state ($now+80)|Out-Null
 $emptyCommit=Receipt 'applied';Accept-GameplayBlastReceipt $state $emptyCommit ($now+90);Require ($state.Commits -eq 2 -and $state.Completed.Count -eq 2) 'Empty-contact blast did not consume its grant.'
 $document.seq=1;$document.utc_ms=$now;$request.operation='prepare';$request.prepare_seq=0;Write-Request;$expired=New-GameplayBlastsState $id $dir
 Refuses {Get-GameplayBlastCommands $expired ($now+501)}
 Get-GameplayBlastCommands $expired $now|Out-Null;Refuses {Get-GameplayBlastCommands $expired ($now+1501)};Stop-GameplayBlastsHost $expired
 $late=Receipt;$beforeFile=[IO.File]::ReadAllText($state.HostFile);Accept-GameplayBlastReceipt $expired $late ($now+1600)
 Require ($expired.Abandoned -eq 1 -and $expired.AbandonedReceipt.seq -eq 1 -and [IO.File]::ReadAllText($state.HostFile) -ceq $beforeFile) 'Late stopped blast republished or lost evidence.'
 Stop-GameplayBlastsHost $state;Require ((Get-GameplayBlastsHostState $state).CleanupComplete -and $state.Grants.Count -eq 0 -and -not [IO.File]::Exists($state.HostFile+'.tmp')) 'Blast cleanup incomplete.'
 # Actual primary/chain coordinates: console binary32 then native %.12g output.
 foreach($coordinates in @(
  @{x=120.52510953019191;y=2042.1410009860992;z=56.184874802827835;native_y=2042.14099121},
  @{x=120.70454426188014;y=2043.3351285442618;z=56.043533593416214;native_y=2043.33508301})){
  $request.center=@{x=$coordinates.x;y=$coordinates.y;z=$coordinates.z};Write-Request
  $nativeState=New-GameplayBlastsState $id $dir;Get-GameplayBlastCommands $nativeState $now|Out-Null;$nativeReply=Receipt
  foreach($axis in @('x','y','z')){$nativeReply.center.$axis=[double]::Parse(([double][float]$request.center.$axis).ToString('G12',[Globalization.CultureInfo]::InvariantCulture),[Globalization.CultureInfo]::InvariantCulture)}
  $nativeReply.center.y=$request.center.y;Refuses {Accept-GameplayBlastReceipt $nativeState $nativeReply ($now+20)}
  $nativeReply.center.y=[double][MathF]::BitIncrement([float]$request.center.y);Refuses {Accept-GameplayBlastReceipt $nativeState $nativeReply ($now+20)}
  $nativeReply.center.y=$coordinates.native_y;Accept-GameplayBlastReceipt $nativeState $nativeReply ($now+20)
  Require ($nativeState.Prepared -eq 1 -and $nativeState.LastReply.reply.center.y -eq $request.center.y -and $nativeState.LastReply.reply.center.x -eq $request.center.x -and $nativeState.LastReply.reply.center.z -eq $request.center.z) 'Native float centre changed the original source centre in the Java reply.'
  Stop-GameplayBlastsHost $nativeState
 }
 "PASS blast host: $checks strict identity/phase/immutable-clock/exposure/burst/duplicate/cleanup checks (no game/network)"
}finally{
 $resolved=[IO.Path]::GetFullPath($dir);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'minecome-blasts-*'){throw 'Unexpected blast test cleanup directory.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
