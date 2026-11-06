# Sustained HUD/inventory, with an explicit Minecraft walking profile.
[CmdletBinding()]
param([string]$BundleDirectory,[string]$InstanceDirectory,[string]$JavaHome='C:/Program Files/Java/jdk-24',
 [ValidateRange(0,300)][int]$SmokeSeconds=0,[switch]$PreflightOnly,[switch]$Movement,[switch]$Blocks,[switch]$Explore,[switch]$Chat,[switch]$Flight,[switch]$Hands,[string]$GroundPatchFile)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay session failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'GameplayMovementHost.ps1')
if($Hands){$Flight=$true};if($Flight){$Chat=$true}
if($Explore -or $Chat){$Blocks=$true};if($Blocks){$Movement=$true}
if(-not $Movement -and $GroundPatchFile){throw 'GroundPatchFile requires Movement.'}
if(-not $BundleDirectory){$BundleDirectory=Join-Path $root $(if($Chat){'runtime/hud-compositor-gameplay-chat'}elseif($Blocks){'runtime/hud-compositor-gameplay-blocks'}elseif($Movement){'runtime/hud-compositor-gameplay-movement'}else{'runtime/hud-compositor-gameplay'})}
$installation=Get-MineComeGameplayInstallation -BundleDirectory $BundleDirectory -RequireUnarmed -Movement:$Movement -Blocks:$Blocks -Chat:$Chat
$context=Get-MineComeProbeContext
if($context.GamePath -ine $installation.ToolsExe){throw 'Installed HUD and running game differ.'}
if(-not $InstanceDirectory){$InstanceDirectory=Join-Path $root 'runtime/gameplay/instance'}
$InstanceDirectory=[IO.Path]::GetFullPath($InstanceDirectory)
if(-not $InstanceDirectory.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Gameplay instance must stay inside the project.'}
if(-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))){throw 'Select an installed JDK.'}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'"|Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$root+'*')})
if($clients.Count){throw 'A MineCome client is already open; preserving its session.'}
if($PreflightOnly){Write-Output 'GAMEPLAY_SESSION_PREFLIGHT_PASS no_changes=true';return}
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/gameplay-kcd-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$targetStart=$context.GameStartedUtc.ToFileTimeUtc().ToString()
$expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+86400000L
$arm=Join-Path $installation.ToolsBin $installation.Profile.arm_config_relative_path
$renderLog=Join-Path $installation.ToolsBin 'ReShade.log'
$logOffset=if(Test-Path -LiteralPath $renderLog){(Get-Item -LiteralPath $renderLog).Length}else{0L}
$helper=$null;$armText=$null;$armWritten=$false;$passed=$false;$failure=$null;$smokeStop=$false
$hostFollower=$null;$hostProof=$null;$patch=$null
try{
 if($Movement){
  $bindingDirectory=Join-Path $InstanceDirectory 'saves/MineCome-Gameplay/minecome-terrain'
  $cached=Join-Path $bindingDirectory 'ground-patch.json'
  if(Test-Path -LiteralPath $bindingDirectory){
   # A persisted capture keeps its origin across launches. It is not represented
   # as a new capture from this process; the native follower checks local bounds.
   $binding=Read-MineComeGameplayJson (Join-Path $bindingDirectory 'binding.json')
   $data=Read-MineComeGameplayJson $cached;$hash=Get-MineComeGameplayHash $cached
   if($binding.schema -ne 1 -or $binding.kind -cne 'minecome_gameplay_terrain_v1' -or
      $binding.patch_sha256 -cne $hash -or $binding.patch_run -cne $data.run -or
      $data.provenance.kind -cne 'live_kcd_ground_patch' -or $data.provenance.game_exe_hash -ine $context.GameHash){throw 'Saved gameplay terrain identity differs.'}
   if($GroundPatchFile -and (Get-MineComeGameplayHash $GroundPatchFile) -cne $hash){throw 'This save is already bound to different terrain; preserving it.'}
   $patch=[pscustomobject]@{Path=$cached;Hash=$hash;Run=$data.run;Data=$data}
  }else{
   if(-not $GroundPatchFile){
    $capture=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch -WideWalking | ForEach-Object {
     if($_ -isnot [string] -and $_.PSObject.Properties['GroundPatchFile']){$_}elseif($_ -is [string]){Add-Content -LiteralPath (Join-Path $directory 'terrain-capture.log') -Value $_ -Encoding utf8}
    })
    if($capture.Count -ne 1){throw 'No complete live terrain capture.'};$GroundPatchFile=$capture[0].GroundPatchFile
   }
   $patch=Read-HudLiveGroundPatch $GroundPatchFile $root $context -WideWalking
  }
 }
 $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-GameplayClient.ps1'),'-EvidenceDirectory',$directory,
  '-InstanceDirectory',$InstanceDirectory,'-Run',$run,'-TargetPid',[string]$context.GamePid,'-TargetStart',$targetStart,
  '-Expires',[string]$expires,'-JavaHome',$JavaHome,'-Connected')
 if($Movement){$arguments+=@('-Movement','-GroundPatchFile',$patch.Path)}
 if($Blocks){$arguments+='-Blocks'}
 if($Explore){$arguments+='-Explore'}
 if($Chat){$arguments+='-Chat'}
 if($Flight){$arguments+='-Flight'}
 if($Hands){$arguments+='-Hands'}
 $quoted=@($arguments|ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
 $helper=Start-Process -FilePath (Get-MineComePowerShell7) -ArgumentList ([string]::Join(' ',$quoted)) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'client.log') -RedirectStandardError (Join-Path $directory 'client-errors.log')
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$ready=$null
 $readyPath=Join-Path $directory 'capture/stream-ready.json'
 do{
  if((Test-Path -LiteralPath $readyPath) -and (Test-Path -LiteralPath (Join-Path $directory 'gameplay-ready.json'))){$ready=Get-Content -LiteralPath $readyPath -Raw|ConvertFrom-Json;break}
  if($helper.HasExited){throw 'Gameplay client exited before readiness; inspect its logs.'}
  Start-Sleep -Milliseconds 50
 }while([DateTime]::UtcNow -lt $deadline)
 if(-not $ready -or $ready.schema -ne 3 -or $ready.session_kind -cne 'gameplay' -or $ready.run -cne $run -or
  $ready.save -cne 'MineCome-Gameplay' -or $ready.target_pid -ne $context.GamePid -or $ready.target_start_filetime -cne $targetStart -or $ready.expires_utc_ms -ne $expires){throw 'Gameplay stream readiness identity differs.'}
 if($ready.ui_input_protocol -ne $(if($Chat){6}elseif($Blocks){5}elseif($Movement){4}else{3})){throw 'Gameplay input profile differs.'}
 $producer=Get-Process -Id $ready.producer_pid
 try{if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $ready.producer_start_filetime -or $producer.Path -ine (Join-Path $JavaHome 'bin/java.exe')){throw 'Gameplay producer identity changed.'}}finally{$producer.Dispose()}
 Assert-MineComeProbeContext $context
 if($Movement){
  $guest=Read-MineComeGameplayJson (Join-Path $directory 'gameplay-ready.json')
  $hostFollower=Start-GameplayMovementHost -Context $context -Run $run -WorldId $guest.world_id -Patch $patch -PoseFile (Join-Path $directory 'gameplay-pose.json') -ViewFile (Join-Path $directory 'host-view.json') -ExpiresUtcMs $expires -Blocks:$Blocks -Explore:$Explore -TerrainCacheFile (Join-Path $bindingDirectory 'coverage.json') -Flight:$Flight
  $movementPath=Join-Path $directory 'gameplay-movement-ready.json';$until=[DateTime]::UtcNow.AddSeconds(12)
  while(-not (Test-Path -LiteralPath $movementPath)){
   $state=Get-GameplayMovementHostState $hostFollower
   if($state.Failure -or $state.Stopped){throw "Gameplay follower failed during attachment: $($state.Failure)"}
   if($helper.HasExited -or [DateTime]::UtcNow -gt $until){throw 'Gameplay terrain attachment did not become ready.'}
   Start-Sleep -Milliseconds 20
  }
  $attached=Read-MineComeGameplayJson $movementPath
  if(-not $attached.ready -or $attached.fixture -or $attached.run -cne $run -or $attached.world_id -cne $guest.world_id -or $attached.patch_sha256 -cne $patch.Hash){throw 'Gameplay movement attachment proof differs.'}
 }
 $armText="[HudStream]`nSchema=3`nRun=$run`nTargetPid=$($context.GamePid)`nTargetStart=$targetStart`nProducerPid=$($ready.producer_pid)`nProducerStart=$($ready.producer_start_filetime)`nExpiresUtcMs=$expires`n"
 $file=[IO.FileStream]::new($arm,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try{$bytes=[Text.Encoding]::UTF8.GetBytes($armText);$file.Write($bytes,0,$bytes.Length);$file.Flush($true);$armWritten=$true}finally{$file.Dispose()}
 [IO.File]::WriteAllText((Join-Path $directory 'arm.ini'),$armText)
 Write-Output "GAMEPLAY_READY run=$run stop_file=$(Join-Path $directory 'session.stop')"
 if($Explore){Write-Output 'Terrain grows automatically toward your movement, up to 64 captured tiles. Saved terrain and construction keep their original coordinates.'}
 if($Chat){Write-Output 'T opens Minecraft chat; / opens commands. Type a command and press Enter; Escape cancels. Walking and mining pause while chat is open.'}
 if($Hands){Write-Output 'Minecraft first-person hands and held items share the HUD stream. Inventory hides them; this profile does not yet render third-person Steve or general world blocks.'}
 if($Flight){Write-Output 'Creative flight: /gamemode creative, double-tap Space to toggle; Space rises, Shift descends, Ctrl sprints. Flight stays within captured terrain and its vertical limit; F8 saves airborne position.'}
 Write-Output $(if($Blocks){'Focus KCD2 with controls released. Walking, HUD and stone controls activate automatically: right-click places held stone, left-click mines owned stone. E opens inventory; F8 stops and saves. Terrain coverage and owned stone capacity are bounded.'}elseif($Movement){'Focus KCD2 with controls released. Minecraft walking and HUD activate automatically. F8 stops and saves at the last safe position. Walking is limited to the captured terrain; blocks, commands and flight are not connected in this path yet.'}else{'Focus KCD2 with controls released. HUD activates automatically; F8 stops and saves. KCD owns walking; Minecraft commands/flight are not connected yet.'})
 $smokeDeadline=[DateTime]::UtcNow.AddSeconds($SmokeSeconds)
 while(-not $helper.HasExited){
  if($hostFollower){
   $stoppingPath=Join-Path $directory 'gameplay-stopping.json'
   if(-not $hostFollower.Final -and (Test-Path -LiteralPath $stoppingPath)){
    $stopping=Read-MineComeGameplayJson $stoppingPath
    if($stopping.schema -ne 1 -or $stopping.kind -cne 'minecome_gameplay_stopping_v1' -or $stopping.run -cne $run){throw 'Gameplay stop notice identity differs.'}
    $hostProof=Stop-GameplayMovementHost $hostFollower
   }
   $state=Get-GameplayMovementHostState $hostFollower
   # A normal guest shutdown stops pose publication first. Let its existing
   # stop receipt finish; an unexpected follower failure stops/saves the guest.
   if(($state.Failure -or $state.Stopped) -and -not $hostFollower.Final -and -not $smokeStop){throw "Gameplay follower stopped: $($state.Failure)"}
  }
  if($SmokeSeconds -gt 0 -and -not $smokeStop -and [DateTime]::UtcNow -ge $smokeDeadline){
   [IO.File]::WriteAllText((Join-Path $directory 'session.stop'),'automated smoke complete');$smokeStop=$true
  }
  if($smokeStop -and [DateTime]::UtcNow -gt $smokeDeadline.AddSeconds(15)){throw 'Smoke stop did not finish normal save/shutdown.'}
  Start-Sleep -Milliseconds 100
 }
 if($helper.ExitCode -ne 0){throw "Gameplay client exit code $($helper.ExitCode)."}
 $stream=Get-Content -LiteralPath (Join-Path $directory 'capture/stream-result.json') -Raw|ConvertFrom-Json -Depth 24
 $session=Get-Content -LiteralPath (Join-Path $directory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
 if($stream.schema -ne 3 -or $stream.result -cne 'stopped' -or $session.run -cne $run -or $session.failure -or
  -not $session.producer_finished -or $session.producer_failure -or -not $session.controls_released -or -not $session.normal_shutdown_requested -or
  -not $session.input_connected -or -not $session.input_armed_seen){throw 'Gameplay native input/save/shutdown proof failed.'}
 if($Movement -and (-not $session.movement.ready -or $session.movement.failure -or -not $session.movement.cleanup_complete)){throw 'Gameplay movement/save/cleanup proof failed.'}
 if($Blocks -and (-not $session.blocks.ready -or $session.blocks.failure -or -not $session.blocks.cleanup_complete)){throw 'Gameplay block ledger/save proof failed.'}
 if($SmokeSeconds -gt 0 -and (-not $smokeStop -or $session.active_ms -lt $SmokeSeconds*1000)){throw 'Gameplay smoke ended before the requested sustained duration.'}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 if($helper -and -not $helper.HasExited){[IO.File]::WriteAllText((Join-Path $directory 'session.stop'),'launcher cleanup');[void]$helper.WaitForExit(10000)}
 if($hostFollower){
  try{
   $hostProof=Stop-GameplayMovementHost $hostFollower
   $hostProof|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $directory 'host-movement.json') -Encoding utf8NoBOM
   if(-not $hostProof.ResourcesClosed -or -not $hostProof.Terminal -or $hostProof.PoseCount -lt 1 -or $hostProof.Failure){$passed=$false;$failure='Gameplay host cleanup/pose proof incomplete: '+$hostProof.Failure}
   if($Blocks -and (-not $hostProof.Blocks -or -not $hostProof.Blocks.CleanupComplete -or $hostProof.Blocks.Failure)){$passed=$false;$failure='Gameplay native block cleanup proof incomplete.'}
   if($Explore -and (-not $hostProof.Terrain -or -not $hostProof.Terrain.CleanupComplete -or $hostProof.Terrain.Failure)){$passed=$false;$failure='Gameplay native terrain cleanup proof incomplete.'}
  }catch{$passed=$false;$failure='Gameplay host cleanup: '+$_.Exception.Message}
 }
 if($armWritten -and (Test-Path -LiteralPath $arm)){
  if([IO.File]::ReadAllText($arm) -ceq $armText){Remove-Item -LiteralPath $arm}else{$passed=$false;$failure='Arm changed; preserved instead of removing it.'}
 }
 if(Test-Path -LiteralPath $renderLog){
  $reader=[IO.FileStream]::new($renderLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  try{
   if($reader.Length -ge $logOffset -and $reader.Length-$logOffset -le 8MB){
    $reader.Position=$logOffset;$copy=[IO.StreamReader]::new($reader);try{[IO.File]::WriteAllText((Join-Path $directory 'native-hud.log'),$copy.ReadToEnd())}finally{$copy.Dispose()}
   }
  }finally{$reader.Dispose()}
 }
 [ordered]@{schema=1;kind='minecome_gameplay_kcd_session_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  target_pid=$context.GamePid;target_start_filetime=$targetStart;instance=$InstanceDirectory;smoke_seconds=$SmokeSeconds;
  minecraft_movement_connected=[bool]($Movement -and $passed);movement_profile=[bool]$Movement;blocks_profile=[bool]$Blocks;explore_profile=[bool]$Explore;chat_profile=[bool]$Chat;flight_profile=[bool]$Flight;hands_profile=[bool]$Hands;host_command_typing_verified=$false;normal_client_exit=($helper -and $helper.HasExited -and $helper.ExitCode -eq 0)}|
  ConvertTo-Json|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
if(-not $passed){throw $failure}
Write-Output "GAMEPLAY_SESSION_SAVED evidence=$directory"
