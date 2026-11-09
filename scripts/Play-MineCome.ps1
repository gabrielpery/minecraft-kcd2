# One entry point for the persistent, full gameplay profile.
[CmdletBinding()]
param([string]$BundleDirectory,[string]$InstanceDirectory,[string]$JavaHome='C:/Program Files/Java/jdk-24',
 [ValidateSet('trosecko','kutnohorsko','klaster')][string]$Level='trosecko',
 [ValidateRange(0,300)][int]$SmokeSeconds=0,[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $playExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($playExit -ne 0){throw "MineCome exited with code $playExit."};return
}
if($PSVersionTable.PSVersion -lt [version]'7.3'){throw 'MineCome requires PowerShell 7.3 or newer. Use the bundled runtime or update PowerShell 7.'}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PlayMineComeHelpers.ps1')
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'GameplayHudSessionGuard.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $InstanceDirectory){$InstanceDirectory=Join-Path $root 'runtime/gameplay/play/instance'}
$InstanceDirectory=Resolve-MineComeGameplayPath $InstanceDirectory -InRuntime
$worldIdentityPath=Join-Path $InstanceDirectory 'minecome-play-world.json'
if(Test-Path -LiteralPath $worldIdentityPath){
 $worldIdentity=Read-MineComeGameplayJson $worldIdentityPath
 if($worldIdentity.schema -ne 1 -or $worldIdentity.kind -cne 'minecome_play_world_v1' -or $worldIdentity.level -cne $Level){throw 'This persistent MineCome instance belongs to a different KCD2 level. Use its original -Level or a different -InstanceDirectory.'}
}
if(-not(Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe') -PathType Leaf)){throw "Java is missing at $JavaHome. Set -JavaHome to your installed JDK; administrator mode is unnecessary."}
$plan=Get-MineComePlayPlan $BundleDirectory
$gameRoot=Split-Path -Parent (Split-Path -Parent $plan.ToolsBin)
if(-not(Test-Path -LiteralPath (Join-Path $gameRoot 'Mods/minecome/Data/minecome-diagnostics.pak'))){throw 'The MineCome diagnostics package is missing from the official tools installation.'}
function Assert-PlayNoClient {
 $clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$root+'*')})
 if($clients.Count){throw 'A MineCome Minecraft session is already running. Return to KCD2 and use F8 to save and stop it first.'}
}
function Get-PlayGame {
 $games=@(Get-Process KingdomCome -ErrorAction SilentlyContinue | Where-Object {
  try{
   # Keep an OS process handle before inspecting Path. During normal shutdown,
   # enumeration may still return a process whose executable has disappeared.
   if($_.HasExited){$false}
   elseif(-not $_.Path -and $_.WaitForExit(250)){$false}
   else{$true}
  }catch [InvalidOperationException]{$false}
 })
 if($games.Count -gt 1){throw 'Multiple KCD2 games are open; close them normally before using MineCome.'}
 if($games.Count -eq 0){return $null}
 if($games[0].Path -ine $plan.ToolsExe){throw 'Another KCD2 installation is open. Close it normally before using MineCome; it was left untouched.'}
 return $games[0]
}
function Wait-PlayGameClosed($Game){
 if($Game.HasExited){return}
 Write-Host 'Close KCD2 normally. MineCome will continue automatically when it closes.'
 $nextNotice=[DateTime]::UtcNow.AddSeconds(30)
 while(-not $Game.WaitForExit(500)){
  if([DateTime]::UtcNow -ge $nextNotice){Write-Host 'Still waiting for KCD2 to close normally. No confirmation message is needed.';$nextNotice=[DateTime]::UtcNow.AddSeconds(30)}
 }
}
Assert-PlayNoClient
$game=Get-PlayGame
if($PreflightOnly){
 [pscustomobject]@{kind='minecome_play_preflight_v1';bundle=$plan.Bundle;installed=$plan.Installed;tools_exe=$plan.ToolsExe;instance=$InstanceDirectory;game_open=($null -ne $game);requires_installation=(-not $plan.Installed);combat=$true;explore=$true;hide_native_vitals=$true;smoke_seconds=$SmokeSeconds;files_changed=$false;game_launched=$false}
 Write-Output 'MINECOME_PLAY_PREFLIGHT_PASS no_changes=true';return
}
$rootHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())))
$playMutex=[Threading.Mutex]::new($false,('Local\MineComePlay_'+$rootHash));$playLocked=$false
try{
 try{$playLocked=$playMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$playLocked=$true}
 if(-not $playLocked){throw 'MineCome Play is already preparing or running a session. Use its existing window.'}
Write-Host 'MineCome: preparing your saved Minecraft world inside KCD2.'
Write-Host 'This uses the separate KCD2 development world; retail saves are not loaded.'
if(-not $plan.Installed){
 if($game){Wait-PlayGameClosed $game;$game=$null}
 Write-Host 'Preparing the verified gameplay HUD. Existing installation receipts and backups are kept.'
 & (Join-Path $PSScriptRoot 'Prepare-GameplayHud.ps1') -BundleDirectory $plan.Bundle -WorldBlocks
 & (Join-Path $PSScriptRoot 'Install-GameplayHud.ps1') -BundleDirectory $plan.Bundle -WorldBlocks
}
$installation=Get-MineComeGameplayInstallation -BundleDirectory $plan.Bundle -RequireUnarmed -Chat
$restartChecked=$false
while($true){
 $game=Get-PlayGame
 if(-not $game){
  Write-Host 'Starting the KCD2 development world. Leave this window open; setup continues after loading.'
  & (Join-Path $PSScriptRoot 'Start-Kcd2ToolsTest.ps1') -GameRoot $gameRoot -Level $Level | Out-Null
  $restartChecked=$true
 }
 $game=Get-PlayGame;if(-not $game){throw 'KCD2 exited before its world was ready.'}
 $expectedPid=$game.Id;$expectedStart=$game.StartTime.ToUniversalTime()
 $deadline=[DateTime]::UtcNow.AddMinutes(4);$nextNotice=[DateTime]::UtcNow.AddSeconds(15);$context=$null;$ready=$false
 while([DateTime]::UtcNow -lt $deadline){
  $game=Get-PlayGame;if(-not $game){throw 'KCD2 exited before its world was ready. Its log remains in the official tools folder.'}
  if($game.Id -ne $expectedPid -or $game.StartTime.ToUniversalTime() -ne $expectedStart){throw 'The KCD2 process changed during loading; the replacement was left untouched.'}
  if(-not $context){try{$context=Get-MineComeProbeContext}catch{
   $message=$_.Exception.Message
   # Absence of the endpoint is normal during boot. A listener owned by any
   # other process, changed executable, or changed process identity is not.
   $missingEndpoint=$message -ceq 'The captured tools process does not own the numeric loopback endpoint; no request sent.' -and
    @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()|Where-Object Port -eq 1403).Count -eq 0
   if(-not $missingEndpoint -and $message -cne 'Current tools game log is missing.'){throw}
   if([DateTime]::UtcNow -ge $nextNotice){Write-Host 'Waiting for KCD2 to finish starting its development interface...';$nextNotice=[DateTime]::UtcNow.AddSeconds(15)}
   Start-Sleep -Milliseconds 500;continue
  }}
  Assert-MineComeProbeContext $context
  if(-not $restartChecked){
   $consumed=Get-GameplayHudConsumedRun $context $plan.ToolsBin;$restartChecked=$true
   if($consumed){
    # The official CommandExecutor/test_capture_cutscene.xml:20 uses normal
    # console 'quit'. Only a confirmed saved session of this exact persistent
    # instance permits it here; active/failed/foreign sessions are preserved.
    $savedPath=Join-Path $root ('runtime/evidence/gameplay-kcd-*-'+$consumed+'/verification.json')
    $saved=@(Get-ChildItem -Path $savedPath -File -ErrorAction SilentlyContinue)
    $playReceiptPath=if($saved.Count -eq 1){Join-Path $saved[0].DirectoryName 'play-launch.json'}else{''}
    if($saved.Count -eq 1 -and (Test-Path -LiteralPath $playReceiptPath) -and (Test-MineComePlaySavedProcess (Read-MineComeGameplayJson $saved[0].FullName) (Read-MineComeGameplayJson $playReceiptPath) $context $consumed $InstanceDirectory)){
     Assert-PlayNoClient;Assert-MineComeGameplayNoArms $plan.ToolsBin
     Write-Host 'Restarting the completed KCD2 session normally so the HUD can open again.'
     try{Invoke-MineComeProbeConsole $context 'quit'}catch{Write-Host 'Waiting for the normal KCD2 shutdown.'}
     # Wait on the captured process handle, not PID enumeration. A reused PID
     # or a dying process with Path=null must never be treated as a new game.
     [void]$game.WaitForExit(15000)
    }
    Wait-PlayGameClosed $game
    break
   }
  }
  $nonce=[guid]::NewGuid().ToString('N');$offset=(Get-Item -LiteralPath $context.GameLog).Length
  $command="#System.LogAlways('[MineComePlayPose] $nonce begin'); local ok=MineCome and type(MineCome.SamplePose)=='function' and MineCome.SamplePose(); System.LogAlways('[MineComePlayPose] $nonce end '..tostring(ok))"
  try{
   Invoke-MineComeProbeConsole $context $command
   # An additional harmless log line flushes the preceding original pose receipt.
   Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComePlayFlush] $nonce')")
  }catch{
   if(-not(Test-MineComePlayReadOnlyRetry $_)){throw}
   # Recheck exact process AND endpoint ownership after a timeout before any
   # subsequent read-only retry. A fresh nonce excludes delayed old replies.
   Assert-MineComeProbeContext $context
   if([DateTime]::UtcNow -ge $nextNotice){Write-Host 'KCD2 is still loading; waiting for its player pose...';$nextNotice=[DateTime]::UtcNow.AddSeconds(15)}
   Start-Sleep -Milliseconds 500;continue
  }
  $poseDeadline=[DateTime]::UtcNow.AddSeconds(1)
  do{
   if(Test-MineComePlayPoseReceipt (Read-MineComeProbeLog $context $offset) $nonce){$ready=$true;break}
   Start-Sleep -Milliseconds 50
  }while([DateTime]::UtcNow -lt $poseDeadline)
  if($ready){break}
  if([DateTime]::UtcNow -ge $nextNotice){Write-Host 'Waiting for the KCD2 world and player to finish loading...';$nextNotice=[DateTime]::UtcNow.AddSeconds(15)}
  Start-Sleep -Milliseconds 500
 }
 if($ready){break}
 if(Get-PlayGame){throw 'KCD2 did not produce a fresh ready-player pose within four minutes. Finish any launcher/loading prompt and run Play-MineCome again.'}
}
Write-Host 'World ready. Loading Minecraft; keep KCD2 in front with menus and console closed.'
Write-Host 'Controls: WASD move | mouse look | left-click mine/attack | right-click use/place'
Write-Host 'E inventory | 1-9/wheel hotbar | T or / commands | Space jump | F5 perspective'
Write-Host 'Creative flight: /gamemode creative, double-tap Space; Space up, Shift down.'
Write-Host 'F8 saves and stops MineCome. There is no activation countdown. Leave this window open.'
if(-not(Test-Path -LiteralPath $worldIdentityPath)){
 [void][IO.Directory]::CreateDirectory($InstanceDirectory)
 Write-MineComeGameplayJson $worldIdentityPath ([ordered]@{schema=1;kind='minecome_play_world_v1';level=$Level})
}
$savedDirectory=$null
& (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $plan.Bundle -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -Combat -Explore -HideNativeVitals -SmokeSeconds $SmokeSeconds | ForEach-Object {
 if($_ -is [string] -and $_ -cmatch '^GAMEPLAY_SESSION_SAVED evidence=(.+)$'){$savedDirectory=Resolve-MineComeGameplayPath $Matches[1] -InRuntime}
 Write-Output $_
}
if(-not $savedDirectory){throw 'The session ended without a confirmed save receipt. Its existing evidence and world were preserved.'}
$verification=Read-MineComeGameplayJson (Join-Path $savedDirectory 'verification.json')
$playReceipt=[ordered]@{schema=1;kind='minecome_play_saved_v1';run=$verification.run;target_pid=$context.GamePid;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();instance=$InstanceDirectory;level=$Level;bundle=$plan.Bundle}
if(-not(Test-MineComePlaySavedProcess $verification ([pscustomobject]$playReceipt) $context $verification.run $InstanceDirectory)){throw 'The completed session save identity did not match this launcher.'}
Write-MineComeGameplayJson (Join-Path $savedDirectory 'play-launch.json') $playReceipt
Write-Host 'MineCome saved and stopped. Run Play-MineCome.cmd again to reopen this same world.'
Write-Host 'The completed KCD2 development session can now be closed normally.'
}finally{
 if($playLocked){$playMutex.ReleaseMutex()}
 $playMutex.Dispose()
}
