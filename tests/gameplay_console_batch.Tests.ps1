#Requires -Version 7.3
# Real request construction and worker/runspace; simulated console and receipts.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/GameplayMovementHost.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action){$threw=$false;try{& $Action|Out-Null}catch{$threw=$true};Check $threw 'Invalid batch accepted'}
$run='a'*32
$worker=(Get-GameplayMovementWorker).ToString()
# Use the actual production rejection wrapper, not a parallel implementation.
$ast=[Management.Automation.Language.Parser]::ParseInput($worker,[ref]$null,[ref]$null)
$wrapper=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'RejectWrapper'},$true)
Invoke-Expression $wrapper.Extent.Text
$calls=@("MineCome.GameplayTerrainHeartbeat('$run')","MineCome.GameplayBlocksHeartbeat('$run')",
 "MineCome.GameplayMovementPose('$run',279,17850,120.17870330810547,2040.6510009765625,56.405808448791504)","MineCome.GameplayMovementSample('$run',109,true)")
$parts=@($calls|ForEach-Object {RejectWrapper $_})
$old='#'+[string]::Join(';',$parts)+";System.LogAlways('[MineComeGameplayFlush] $run')"
Check (('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($old)).Length -gt 2108) 'Regression no longer reproduces oversized encoded request'
$requests=@(ConvertTo-GameplayMovementRequests $run $parts)
Check ($requests.Count -eq 2) 'Four simultaneous idle calls were not split'
Check (@($requests|Where-Object {$_.PathAndQuery.Length -gt 2000}).Count -eq 0) 'Actual encoded path exceeds bound'
$suffix=";System.LogAlways('[MineComeGameplayFlush] $run')"
$joined=(@($requests|ForEach-Object {$_.Command.Substring(1,$_.Command.Length-1-$suffix.Length)}) -join ';')
Check ($joined -ceq [string]::Join(';',$parts)) 'Splitting changed or reordered complete Lua statements'
foreach($request in $requests){Check ([Uri]::UnescapeDataString($request.PathAndQuery.Substring('/api/System/Console/ExecuteString?command='.Length)) -ceq $request.Command) 'Encoded request roundtrip changed command'}
$cells=(0..63|ForEach-Object {'-68,80,'+(-68+$_)}) -join ','
$maximum=RejectWrapper "MineCome.GameplayBlocksApply('$run',10000000,{$cells})"
$maximumRequests=@(ConvertTo-GameplayMovementRequests $run @($maximum))
Check ($maximumRequests.Count -eq 1 -and $maximumRequests[0].PathAndQuery.Length -le 2000) 'Full 64-block snapshot no longer fits'
$unicode="System.LogAlways('"+('é'*240)+"')"
Check (@(ConvertTo-GameplayMovementRequests $run @($unicode))[0].PathAndQuery.Length -le 2000) 'UTF8 percent encoding not measured'
Reject {ConvertTo-GameplayMovementRequests $run @(' ')}
Reject {ConvertTo-GameplayMovementRequests 'invalid' @('return')}
$script:emitted=[Collections.Generic.List[object]]::new()
Reject {ConvertTo-GameplayMovementRequests $run @($parts[0],("System.LogAlways('"+('é'*500)+"')")) | ForEach-Object {$script:emitted.Add($_)}}
Check ($script:emitted.Count -eq 0) 'Oversized later statement partially emitted an invalid batch'

$directory=Join-Path $root ('runtime/evidence/gameplay-console-batch-tests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$fake=Join-Path $directory 'fake.ps1'
@'
$script:requestCounter=0
function Assert-MineComeProbeContext($Context){}
function Read-GameplayMovementPose($Path,$Identity,$Bounds,$LastSequence,$LastSource,$Now){
 [pscustomobject]@{seq=$LastSequence+1;source_ms=$LastSource+50;utc_ms=$Now;position=[pscustomobject]@{x=120.17870330810547;y=2040.6510009765625;z=56.405808448791504}}
}
function Get-GameplayTerrainCommands($State,$Now,$Pose){"MineCome.GameplayTerrainHeartbeat('$run')"}
function Test-GameplayTerrainPose($State,$Pose){$true}
function Get-GameplayBlocksCommands($State,$Now){"MineCome.GameplayBlocksHeartbeat('$run')"}
function Get-GameplayBlocksHostState($State){[pscustomobject]@{CleanupComplete=$true}}
function Get-GameplayTerrainHostState($State){[pscustomobject]@{CleanupComplete=$true}}
function Invoke-MineComeToolsRequest([string]$PathAndQuery,[int]$TimeoutMilliseconds){
 if($PathAndQuery.Length -gt 2000 -or $TimeoutMilliseconds -ne 150){throw 'Unbounded simulated dispatch'}
 $code=[Uri]::UnescapeDataString($PathAndQuery.Substring('/api/System/Console/ExecuteString?command='.Length));$script:requestCounter++
 [IO.File]::AppendAllText((Join-Path $Context.GameRoot 'commands.txt'),($code+"`n"))
 $r=[ordered]@{schema=1;run=$run;event='';result='';seq=0;active=$true;camera_basis_valid=$true;forward=@{x=1;y=0;z=0};up=@{x=0;y=0;z=1};camera=@{x=1;y=2;z=3};aim=@{range=4.5;known=$true;distance=-1;terrain_hit=$false}}
 if($code -match 'MineCome.GameplayMovementBegin\('){$r.event='begin';$r.result='ready'}
 elseif($code -match "MineCome.GameplayMovementSample\('[a-f0-9]+',([0-9]+),true\)"){$r.event='view';$r.result='sampled';$r.seq=[long]$Matches[1]}
 elseif($code -match 'MineCome.GameplayMovementEnd\('){$r.event='terminal';$r.result='explicit_stop';$r.active=$false}
 if($r.event){[IO.File]::AppendAllText($Context.GameLog,('[MineComeGameplayMovement] '+($r|ConvertTo-Json -Depth 5 -Compress)+"`n"))}
}
'@ | Set-Content -LiteralPath $fake -Encoding utf8NoBOM
$context=[pscustomobject]@{GameRoot=$directory;GameLog=(Join-Path $directory 'game.log')}
[IO.File]::WriteAllText($context.GameLog,'')
$identity=[pscustomobject]@{Run=$run;WorldId=[guid]::NewGuid().ToString();Pid=42;Start='123';PatchRun=$run;PatchHash=('b'*64)}
$bounds=[pscustomobject]@{MinX=116;MaxX=124;MinY=2036;MaxY=2044;MinZ=55;MaxZ=60}
$shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new([StringComparer]::Ordinal)
$cancel=[Threading.CancellationTokenSource]::new();$space=[RunspaceFactory]::CreateRunspace();$pipeline=[PowerShell]::Create()
$inject=". (Join-Path `$ProjectRoot 'scripts/GameplayMovementHost.ps1')"
$worker=$worker.Replace($inject,($inject+"`n. '"+$fake.Replace("'","''")+"'"))
try{
 $space.Open();$pipeline.Runspace=$space
 $dummy=[pscustomobject]@{BeginSent=$false}
 $null=$pipeline.AddScript($worker).AddArgument($context).AddArgument($identity).AddArgument($bounds).AddArgument((Join-Path $directory 'pose.json')).AddArgument((Join-Path $directory 'view.json')).AddArgument(([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+15000)).AddArgument(0L).AddArgument($shared).AddArgument($cancel.Token).AddArgument($root).AddArgument($dummy).AddArgument($dummy)
 $async=$pipeline.BeginInvoke();$deadline=[DateTime]::UtcNow.AddSeconds(5)
 do{Start-Sleep -Milliseconds 10;if($shared.ContainsKey('Snapshot')){$state=$shared['Snapshot'];if($state.Stopped -or $state.ViewCount -ge 4){break}}}while([DateTime]::UtcNow -lt $deadline)
 $cancel.Cancel();Check ($async.AsyncWaitHandle.WaitOne(4000)) 'Worker did not clean up'
 $null=$pipeline.EndInvoke($async)
 Check ($pipeline.Streams.Error.Count -eq 0) ([string]($pipeline.Streams.Error|Out-String))
 $state=$shared['Snapshot']
 Check ($state.Stopped -and -not $state.Failure -and $state.ViewCount -ge 4 -and $state.PoseCount -ge 4) ('Real worker failed: '+$state.Failure)
 Check ($state.MaxRequestPathLength -le 2000 -and $state.RequestCount -gt $state.ViewCount -and $state.LastDispatch.EncodedPathLength -le 2000) 'Worker dispatch evidence lost encoded bounds'
 Check ($state.Terminal.result -ceq 'explicit_stop' -and $state.LastDispatch.Command -notmatch 'GameplayMovementEnd') 'Cleanup overwrote last gameplay dispatch'
 $state|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}finally{$cancel.Cancel();$pipeline.Dispose();$space.Dispose();$cancel.Dispose()}
Write-Output "PASS $script:checks gameplay console batching checks (simulated endpoint); evidence=$directory"
