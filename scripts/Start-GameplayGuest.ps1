# Persistent guest foundation. Actual Minecraft window; no KCD launch or input capture.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$InstanceDirectory,
 [string]$EvidenceDirectory,[string]$ReceiverPath,[ValidateSet('','create','resume','walking','walking-resume','blocks','blocks-resume','blocks-survival','food','food-resume','drops','drops-resume','terrain','terrain-resume','chat','chat-resume','flight','flight-resume','flight-fall','flight-fall-resume','hands','world-blocks','world-blocks-resume','shapes','shapes-resume','depth','connected','connected-resume','shape-walking','player')][string]$FixturePhase='',
 [switch]$Movement,[switch]$Blocks,[switch]$Explore,[switch]$Chat,[switch]$Flight,[switch]$Hands,[switch]$WorldBlocks,[string]$GroundPatchFile,[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay guest failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
if($WorldBlocks){$Hands=$true};if($Hands){$Flight=$true};if($Flight){$Chat=$true}
if($Explore -or $Chat){$Blocks=$true};if($Blocks){$Movement=$true}
if($FixturePhase.StartsWith('flight') -and -not $Flight){throw 'Flight fixture requires -Flight.'}
if(($FixturePhase.StartsWith('drops') -or $FixturePhase.StartsWith('world-blocks') -or $FixturePhase.StartsWith('shapes') -or $FixturePhase -eq 'depth' -or $FixturePhase.StartsWith('connected') -or $FixturePhase -eq 'shape-walking' -or $FixturePhase -eq 'player') -and -not $WorldBlocks){throw 'World block fixtures require -WorldBlocks.'};if($FixturePhase -eq 'hands' -and -not $Hands){throw 'Hands fixture requires -Hands.'}
if($FixturePhase.StartsWith('terrain') -and -not $Explore){throw 'Terrain fixture requires -Explore.'}
if($FixturePhase.StartsWith('chat') -and -not $Chat){throw 'Chat fixture requires -Chat.'}
if(($FixturePhase.StartsWith('blocks') -or $FixturePhase.StartsWith('food')) -and -not $Blocks){throw 'Block fixtures require -Blocks.'}
if($Movement){
 if(-not $GroundPatchFile){throw 'Gameplay movement requires its persistent captured ground patch.'}
 $GroundPatchFile=[IO.Path]::GetFullPath($GroundPatchFile)
 if(-not (Test-Path -LiteralPath $GroundPatchFile -PathType Leaf)){throw 'Gameplay ground patch does not exist.'}
}elseif($GroundPatchFile -or $FixturePhase.StartsWith('walking')){throw 'Ground patches and walking fixtures require -Movement.'}
if(-not $InstanceDirectory){$InstanceDirectory=Join-Path $root 'runtime/gameplay/instance'}
$InstanceDirectory=[IO.Path]::GetFullPath($InstanceDirectory)
if(-not $InstanceDirectory.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Gameplay instance must stay inside the project.'}
if(-not $ReceiverPath){$ReceiverPath=Join-Path $root 'build/native/kcd2/hud/stream/Release/minecome_hud_stream_receiver.exe'}
if(-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe')) -or -not (Test-Path -LiteralPath $ReceiverPath)){throw 'Build the gameplay receiver and select an installed JDK first.'}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'"|Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$root+'*')})
if($clients.Count){throw 'A MineCome client is already open; preserving its session.'}
if($PreflightOnly){Write-Output 'GAMEPLAY_GUEST_PREFLIGHT_PASS no_changes=true';return}
$run=[guid]::NewGuid().ToString('N')
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path $root ('runtime/evidence/gameplay-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)}
$EvidenceDirectory=Resolve-HudMovementEvidencePath $EvidenceDirectory $root
if(Test-Path -LiteralPath $EvidenceDirectory){throw 'Use a new evidence directory; the gameplay world is reused separately.'}
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$self=Get-Process -Id $PID
try{$targetStart=$self.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()}finally{$self.Dispose()}
$expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+86400000L
$powerShell=Get-MineComePowerShell7
$helper=$null;$receiver=$null;$ready=$null;$passed=$false;$failure=$null
function Start-GameplayChild([string]$File,[string[]]$Arguments,[string]$Name){
 $quoted=@($Arguments|ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
 return Start-Process -FilePath $File -ArgumentList ([string]::Join(' ',$quoted)) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $EvidenceDirectory "$Name.log") -RedirectStandardError (Join-Path $EvidenceDirectory "$Name-errors.log")
}
try{
 $childArgs=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-GameplayClient.ps1'),'-EvidenceDirectory',$EvidenceDirectory,
 '-InstanceDirectory',$InstanceDirectory,'-Run',$run,'-TargetPid',[string]$PID,'-TargetStart',$targetStart,'-Expires',[string]$expires,'-JavaHome',$JavaHome)
 if($FixturePhase){$childArgs+=@('-FixturePhase',$FixturePhase)}
 if($Movement){$childArgs+=@('-Movement','-GroundPatchFile',$GroundPatchFile)}
 if($Blocks){$childArgs+='-Blocks'}
 if($Explore){$childArgs+='-Explore'}
 if($Chat){$childArgs+='-Chat'}
 if($Flight){$childArgs+='-Flight'}
 if($Hands){$childArgs+='-Hands'};if($WorldBlocks){$childArgs+='-WorldBlocks'}
 $helper=Start-GameplayChild $powerShell $childArgs 'client'
 $deadline=[DateTime]::UtcNow.AddSeconds(120)
 $readyPath=Join-Path $EvidenceDirectory 'capture/stream-ready.json'
 do{
  if(Test-Path -LiteralPath $readyPath){$ready=Get-Content -LiteralPath $readyPath -Raw|ConvertFrom-Json;break}
  if($helper.HasExited){throw 'Gameplay client exited before readiness; inspect client-errors.log and client.log.'}
  Start-Sleep -Milliseconds 50
 }while([DateTime]::UtcNow -lt $deadline)
 if(-not $ready -or $ready.schema -ne 3 -or $ready.session_kind -cne 'gameplay' -or $ready.run -cne $run -or
  $ready.save -cne 'MineCome-Gameplay' -or $ready.target_pid -ne $PID -or $ready.target_start_filetime -cne $targetStart -or $ready.expires_utc_ms -ne $expires){throw 'Gameplay readiness identity does not match this session.'}
 $producer=Get-Process -Id $ready.producer_pid
 try{if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $ready.producer_start_filetime -or $producer.Path -ine (Join-Path $JavaHome 'bin/java.exe')){throw 'Gameplay producer process identity changed.'}}finally{$producer.Dispose()}
 $receiverOutput=Join-Path $EvidenceDirectory 'receiver.json'
 $receiver=Start-GameplayChild $ReceiverPath @('--gameplay','--run',$run,'--target-pid',[string]$PID,'--target-start',$targetStart,
  '--producer-pid',[string]$ready.producer_pid,'--producer-start',[string]$ready.producer_start_filetime,'--expires',[string]$expires,'--output',$receiverOutput) 'receiver'
 Write-Output "GAMEPLAY_READY persistent_world=MineCome-Gameplay stop_file=$(Join-Path $EvidenceDirectory 'session.stop')"
 Write-Output 'The guest window uses normal Minecraft controls. Close it normally to save; no KCD connection is claimed by this entry.'
 $fixtureDeadline=[DateTime]::UtcNow.AddSeconds(90)
 while(-not $helper.HasExited){
  if($receiver.HasExited){
   if($receiver.ExitCode -ne 0){throw 'Gameplay receiver failed while the Minecraft session was open.'}
   if(-not $helper.WaitForExit(10000)){throw 'Stream closed but Minecraft did not finish its normal save/shutdown.'}
   break
  }
  if($FixturePhase -and [DateTime]::UtcNow -gt $fixtureDeadline){throw 'Gameplay fixture did not finish normally.'}
  Start-Sleep -Milliseconds 100
 }
 if($helper.ExitCode -ne 0){throw "Gameplay client exit code $($helper.ExitCode)."}
 if(-not $receiver.WaitForExit(5000) -or $receiver.ExitCode -ne 0){throw 'Gameplay receiver did not verify a normal closed stream.'}
 $stream=Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'capture/stream-result.json') -Raw|ConvertFrom-Json -Depth 24
 $received=Get-Content -LiteralPath $receiverOutput -Raw|ConvertFrom-Json
 # Gson's stream snapshot omits null fields; use the final receipt for shutdown
 # and failure checks, after the client has finished saving and draining frames.
 $session=Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
 if($stream.schema -ne 3 -or $stream.result -cne 'stopped' -or $session.kind -cne 'minecome_gameplay_session_v1' -or
  $session.run -cne $run -or $session.world_id -cne $stream.lab_evidence.world_id -or
  $session.failure -or $session.producer_failure -or -not $session.producer_finished -or
  -not $session.normal_shutdown_requested -or -not $session.controls_released -or
  -not $session.persistent_world -or $received.result -cne 'passed' -or $received.stream_schema -ne 3 -or -not $received.closed_seen){throw 'Gameplay close/persistence/transport proof failed.'}
 if($FixturePhase -and $session.fixture.result -cne 'passed'){throw 'Gameplay fixture failed.'}
 if($Movement -and ($session.movement.failure -or -not $session.movement.cleanup_complete -or
  -not $session.movement.controls_released -or -not $session.movement.client_collision_released -or
  -not $session.movement.server_collision_released -or $session.movement.blocks_written -ne 0 -or
  -not $session.movement.terrain_cells_valid)){throw 'Gameplay movement did not release its controls and ephemeral collision cleanly.'}
 if($Blocks -and ($session.blocks.failure -or -not $session.blocks.cleanup_complete -or -not $session.blocks.controls_released)){throw 'Gameplay block ledger did not save or release controls cleanly.'}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 if($helper -and -not $helper.HasExited){
  Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'session.stop') -Value 'stop' -Encoding utf8NoBOM
  [void]$helper.WaitForExit(10000)
 }
 [ordered]@{schema=1;kind='minecome_gameplay_guest_session_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  instance=$InstanceDirectory;fixture=$FixturePhase;movement=[bool]$Movement;blocks=[bool]$Blocks;explore=[bool]$Explore;chat=[bool]$Chat;flight=[bool]$Flight;hands=[bool]$Hands;world_blocks=[bool]$WorldBlocks;kcd_connected=$false;normal_client_exit=($helper -and $helper.HasExited -and $helper.ExitCode -eq 0)}|
  ConvertTo-Json|Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'verification.json') -Encoding utf8NoBOM
}
[pscustomobject]@{EvidenceDirectory=$EvidenceDirectory;VerificationFile=(Join-Path $EvidenceDirectory 'verification.json')}
