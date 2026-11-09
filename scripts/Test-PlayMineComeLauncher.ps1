#Requires -Version 7.3
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PlayMineComeHelpers.ps1')
function Require([bool]$Result,[string]$Message){if(-not $Result){throw $Message}}
$run='a'*32
$pose=[ordered]@{schema=1;player=@{x=120.;y=2040.;z=56.};camera=@{x=120.;y=2040.;z=57.6};forward=@{x=0.;y=1.;z=0.};up=@{x=0.;y=0.;z=1.};fov_raw=1.26;calibrated=$false}
function Log-Pose($Value){return "[12:00:00] [MineComePlayPose] $run begin`n[12:00:00] [MineComePose] $($Value|ConvertTo-Json -Depth 5 -Compress)`n[12:00:00] [MineComePlayPose] $run end true`n"}
$log=Log-Pose $pose
Require (Test-MineComePlayPoseReceipt $log $run) 'Fresh native player pose refused.'
Require (-not(Test-MineComePlayPoseReceipt $log ('b'*32))) 'An old/foreign readiness receipt was admitted.'
Require (-not(Test-MineComePlayPoseReceipt ($log.Replace('end true','end false')) $run)) 'Failed native pose call admitted.'
$old=$pose.player;$pose.player=$null;Require (-not(Test-MineComePlayPoseReceipt (Log-Pose $pose) $run)) 'Loading/menu camera without player admitted.';$pose.player=$old
$pose.player.x='120';Require (-not(Test-MineComePlayPoseReceipt (Log-Pose $pose) $run)) 'String coordinate admitted.';$pose.player.x=120.
$pose.forward.y=0.;Require (-not(Test-MineComePlayPoseReceipt (Log-Pose $pose) $run)) 'Uninitialized view admitted.';$pose.forward.y=1.
$pose.fov_raw=0.;Require (-not(Test-MineComePlayPoseReceipt (Log-Pose $pose) $run)) 'Uninitialized projection admitted.';$pose.fov_raw=1.26
$instance=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../runtime/gameplay/play/instance'))
$context=[pscustomobject]@{GamePid=123;GameStartedUtc=[DateTime]::SpecifyKind([DateTime]'2026-11-09T12:00:00',[DateTimeKind]::Utc)}
$start=$context.GameStartedUtc.ToFileTimeUtc().ToString()
$saved=[pscustomobject]@{schema=1;kind='minecome_gameplay_kcd_session_v1';run=$run;result='passed';failure=$null;normal_client_exit=$true;target_pid=123;target_start_filetime=$start;instance=$instance}
$play=[pscustomobject]@{schema=1;kind='minecome_play_saved_v1';run=$run;target_pid=123;target_start_filetime=$start;instance=$instance}
Require (Test-MineComePlaySavedProcess $saved $play $context $run $instance) 'Exact completed Play session refused.'
Require (-not(Test-MineComePlaySavedProcess $saved $null $context $run $instance)) 'A session not owned by Play permitted restart.'
$saved.result='failed';Require (-not(Test-MineComePlaySavedProcess $saved $play $context $run $instance)) 'Failed save permitted automatic quit.';$saved.result='passed'
$saved.normal_client_exit='true';Require (-not(Test-MineComePlaySavedProcess $saved $play $context $run $instance)) 'Malformed normal exit permitted automatic quit.';$saved.normal_client_exit=$true
$saved.target_start_filetime='133000000000000000';Require (-not(Test-MineComePlaySavedProcess $saved $play $context $run $instance)) 'Reused PID permitted automatic quit.';$saved.target_start_filetime=$start
$play.run='b'*32;Require (-not(Test-MineComePlaySavedProcess $saved $play $context $run $instance)) 'Foreign launcher receipt permitted automatic quit.';$play.run=$run
Require (-not(Test-MineComePlaySavedProcess $saved $play $context $run ($instance+'-other'))) 'Different saved world permitted automatic quit.'
Require (Test-MineComePlayReadOnlyRetry ([Exception]::new('Official tools request exceeded its absolute timeout'))) 'Loading HTTP timeout was not retryable.'
Require (Test-MineComePlayReadOnlyRetry ([Exception]::new('HTTP wrapper',[Net.Sockets.SocketException]::new(10061)))) 'Read-only connection refusal was not retryable.'
foreach($message in @('Captured tools process identity changed.','The captured tools process does not own the numeric loopback endpoint; no request sent.','Official tools response exceeded the bounded diagnostic size','Official tools returned HTTP 403; redirects are disabled')){
 Require (-not(Test-MineComePlayReadOnlyRetry ([Exception]::new($message)))) "Unrelated or identity failure became retryable: $message"
}
foreach($name in @('Play-MineCome.ps1','PlayMineComeHelpers.ps1')){
 $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name),[ref]$tokens,[ref]$errors)
 Require ($errors.Count -eq 0) "PowerShell syntax failed: $name"
}
Write-Output 'PASS Play readiness identity, menu rejection, save ownership and restart preservation (no games or file changes).'
