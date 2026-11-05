#Requires -Version 7.3
# Read-only live capture with a scripted frontier request. No Minecraft input,
# native movement, HUD installation or save modification is performed.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$GroundPatchFile,[ValidateRange(-1,1)][int]$Tx=1,[ValidateRange(-1,1)][int]$Tz=0)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if([Math]::Abs($Tx)+[Math]::Abs($Tz) -ne 1){throw 'Choose one cardinal neighbor.'}
. (Join-Path $PSScriptRoot 'GameplayTerrainHost.ps1')
$context=Get-MineComeProbeContext;$root=$context.ProjectRoot
$patch=Read-HudLiveGroundPatch ([IO.Path]::GetFullPath($GroundPatchFile)) $root $context -WideWalking
$run=[guid]::NewGuid().ToString('N');$world=[guid]::NewGuid().ToString()
$directory=Join-Path $root ('runtime/evidence/gameplay-terrain-capture-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$state=New-GameplayTerrainHost -Context $context -Run $run -WorldId $world -Patch $patch -CacheFile (Join-Path $directory 'unused-coverage.json') -AdmissionFile (Join-Path $directory 'terrain-admission.json') -AckFile (Join-Path $directory 'terrain-ack.json') -ExpiresUtcMs ($now+15000)
$watch=[Diagnostics.Stopwatch]::StartNew();$received=0;$passed=$false;$failure=$null;$tile=$null
function Send-Capture([string]$Code){
 Assert-MineComeProbeContext $context
 if(-not $Code){return}
 $command='#'+$Code+";System.LogAlways('[MineComeTerrainCaptureFlush] $run')"
 Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($command)) -TimeoutMilliseconds 500|Out-Null
}
function Receive-Capture {
 $log=Read-MineComeProbeLog $context $state.Probe.Offset
 $rows=@(Get-MineComeProbeReceipts $log 'MineComeGameplayTerrain' $run)
 for($i=$script:received;$i -lt $rows.Count;$i++){$script:received=$i+1;Accept-GameplayTerrainReceipt $state $rows[$i] ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())}
}
try{
 Send-Capture (Get-GameplayTerrainCommands $state $now)
 do{Receive-Capture;if($state.Begin){break};Start-Sleep -Milliseconds 25;Send-Capture "System.LogAlways('[MineComeTerrainCapturePoll] $run')"}while($watch.ElapsedMilliseconds -lt 1500)
 if(-not $state.Begin){throw 'Terrain capture begin not acknowledged.'}
 $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 $pose=[pscustomobject]@{seq=1;utc_ms=$now;position=[pscustomobject]@{x=$patch.Data.center.x;y=$patch.Data.center.y;z=$patch.Data.center.z}}
 Send-Capture (Get-GameplayTerrainCommands $state $now $pose)
 $pose=[pscustomobject]@{seq=2;utc_ms=$now+1;position=[pscustomobject]@{x=$patch.Data.center.x+.8*$Tx;y=$patch.Data.center.y-.8*$Tz;z=$patch.Data.center.z}}
 Send-Capture (Get-GameplayTerrainCommands $state ($now+1) $pose)
 do{
  Receive-Capture
  if($state.Pending -and $state.Pending.Tile){$tile=$state.Pending.Tile;break}
  if($state.LastRefusal){throw ('Terrain neighbor refused: '+$state.LastRefusal)}
  Start-Sleep -Milliseconds 30
  $code=Get-GameplayTerrainCommands $state ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
  Send-Capture $(if($code){$code}else{"System.LogAlways('[MineComeTerrainCapturePoll] $run')"})
 }while($watch.ElapsedMilliseconds -lt 5000)
 if(-not $tile -or $tile.Tx -ne $Tx -or $tile.Tz -ne $Tz -or $state.Captures -ne 1 -or $state.Generation -ne 0){throw 'Live terrain capture did not publish exactly one unacknowledged tile.'}
 [IO.File]::WriteAllText((Join-Path $directory 'captured-tile.json'),$tile.Json,[Text.UTF8Encoding]::new($false))
 $passed=$true
}catch{$failure=$_.Exception.Message}
finally{
 try{
  Send-Capture (Get-GameplayTerrainStopCommand $state)
  $until=$watch.ElapsedMilliseconds+1000
  do{Receive-Capture;if($state.Terminal){break};Start-Sleep -Milliseconds 30;Send-Capture "System.LogAlways('[MineComeTerrainCaptureCleanup] $run')"}while($watch.ElapsedMilliseconds -lt $until)
  if(-not (Get-GameplayTerrainHostState $state).CleanupComplete -or $state.Failure){throw 'Native terrain capture cleanup incomplete.'}
 }catch{$passed=$false;if(-not $failure){$failure=$_.Exception.Message}}
 [IO.File]::WriteAllText((Join-Path $directory 'game.log'),(Read-MineComeProbeLog $context $state.Probe.Offset))
 [ordered]@{schema=1;kind='minecome_gameplay_terrain_capture_verification_v1';result=$(if($passed){'passed'}else{'failed'});failure=$failure;run=$run;game_pid=$context.GamePid;patch_sha256=$patch.Hash;
  scripted_frontier=$true;native_player_moved=$false;minecraft_admission_verified=$false;elapsed_ms=$watch.ElapsedMilliseconds;terrain=(Get-GameplayTerrainHostState $state);tile_sha256=$(if($tile){$tile.Sha256}else{$null})}|
  ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
if(-not $passed){throw "$failure Evidence: $directory"}
[pscustomobject]@{Result='passed';EvidenceDirectory=$directory;CapturedTileFile=(Join-Path $directory 'captured-tile.json')}
