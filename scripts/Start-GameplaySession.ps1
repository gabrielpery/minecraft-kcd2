# Sustained HUD/inventory foundation. KCD still owns world movement in this profile.
[CmdletBinding()]
param([string]$BundleDirectory,[string]$InstanceDirectory,[string]$JavaHome='C:/Program Files/Java/jdk-24',
 [ValidateRange(0,300)][int]$SmokeSeconds=0,[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay session failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
if(-not $BundleDirectory){$BundleDirectory=Join-Path $root 'runtime/hud-compositor-gameplay'}
$installation=Get-MineComeGameplayInstallation -BundleDirectory $BundleDirectory -RequireUnarmed
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
$arm=Join-Path $installation.ToolsBin 'minecome-hud/addons/MineComeHudGameplay.ini'
$renderLog=Join-Path $installation.ToolsBin 'ReShade.log'
$logOffset=if(Test-Path -LiteralPath $renderLog){(Get-Item -LiteralPath $renderLog).Length}else{0L}
$helper=$null;$armText=$null;$armWritten=$false;$passed=$false;$failure=$null;$smokeStop=$false
try{
 $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-GameplayClient.ps1'),'-EvidenceDirectory',$directory,
  '-InstanceDirectory',$InstanceDirectory,'-Run',$run,'-TargetPid',[string]$context.GamePid,'-TargetStart',$targetStart,
  '-Expires',[string]$expires,'-JavaHome',$JavaHome,'-Connected')
 $quoted=@($arguments|ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
 $helper=Start-Process -FilePath (Get-MineComePowerShell7) -ArgumentList ([string]::Join(' ',$quoted)) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'client.log') -RedirectStandardError (Join-Path $directory 'client-errors.log')
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$ready=$null
 $readyPath=Join-Path $directory 'capture/stream-ready.json'
 do{
  if(Test-Path -LiteralPath $readyPath){$ready=Get-Content -LiteralPath $readyPath -Raw|ConvertFrom-Json;break}
  if($helper.HasExited){throw 'Gameplay client exited before readiness; inspect its logs.'}
  Start-Sleep -Milliseconds 50
 }while([DateTime]::UtcNow -lt $deadline)
 if(-not $ready -or $ready.schema -ne 3 -or $ready.session_kind -cne 'gameplay' -or $ready.run -cne $run -or
  $ready.save -cne 'MineCome-Gameplay' -or $ready.target_pid -ne $context.GamePid -or $ready.target_start_filetime -cne $targetStart -or $ready.expires_utc_ms -ne $expires){throw 'Gameplay stream readiness identity differs.'}
 $producer=Get-Process -Id $ready.producer_pid
 try{if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $ready.producer_start_filetime -or $producer.Path -ine (Join-Path $JavaHome 'bin/java.exe')){throw 'Gameplay producer identity changed.'}}finally{$producer.Dispose()}
 Assert-MineComeProbeContext $context
 $armText="[HudStream]`nSchema=3`nRun=$run`nTargetPid=$($context.GamePid)`nTargetStart=$targetStart`nProducerPid=$($ready.producer_pid)`nProducerStart=$($ready.producer_start_filetime)`nExpiresUtcMs=$expires`n"
 $file=[IO.FileStream]::new($arm,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try{$bytes=[Text.Encoding]::UTF8.GetBytes($armText);$file.Write($bytes,0,$bytes.Length);$file.Flush($true);$armWritten=$true}finally{$file.Dispose()}
 [IO.File]::WriteAllText((Join-Path $directory 'arm.ini'),$armText)
 Write-Output "GAMEPLAY_READY run=$run stop_file=$(Join-Path $directory 'session.stop')"
 Write-Output 'Focus KCD2 with controls released. HUD activates automatically; F8 stops and saves. KCD owns walking; Minecraft commands/flight are not connected yet.'
 $smokeDeadline=[DateTime]::UtcNow.AddSeconds($SmokeSeconds)
 while(-not $helper.HasExited){
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
 if($SmokeSeconds -gt 0 -and (-not $smokeStop -or $session.active_ms -lt $SmokeSeconds*1000)){throw 'Gameplay smoke ended before the requested sustained duration.'}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 if($helper -and -not $helper.HasExited){[IO.File]::WriteAllText((Join-Path $directory 'session.stop'),'launcher cleanup');[void]$helper.WaitForExit(10000)}
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
  minecraft_movement_connected=$false;host_command_typing_verified=$false;normal_client_exit=($helper -and $helper.HasExited -and $helper.ExitCode -eq 0)}|
  ConvertTo-Json|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
if(-not $passed){throw $failure}
Write-Output "GAMEPLAY_SESSION_SAVED evidence=$directory"
