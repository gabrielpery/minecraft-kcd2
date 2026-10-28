#Requires -Version 7.3
# Controller/sidecar filesystem fixture only; no game, deployment or input.
param([string]$CompletedEvidenceDirectory)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudRepeatSession.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
function Clone($Value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 32)}
function Assert-MineComeProbeContext($Context){}
function Get-Process {param($Id,$ErrorAction) return $null}
$directory=Join-Path $root ('runtime/evidence/hud-repeat-fixture-'+[guid]::NewGuid().ToString('N'))
$capture=Join-Path $directory 'capture'
$bin=Join-Path $directory 'game'
$armPath=Join-Path $bin 'minecome-hud/addons/MineComeHudWalkingRepeat.ini'
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($armPath))
$null=[IO.Directory]::CreateDirectory($capture)
$started=[DateTime]::UtcNow.AddMinutes(-1)
$context=[pscustomobject]@{GamePid=10;GameStartedUtc=$started;GamePath=(Join-Path $bin 'KingdomCome.exe')}
$arm=[pscustomobject]@{schema=1;kind='minecome_hud_stream_arm_v1';run=('a'*32);arm_sha256=('b'*64);repeat_session=$true;session_generation=1;
    game_pid=10;game_start_filetime=$started.ToFileTimeUtc().ToString();producer_pid=20;producer_start_filetime='12345';arm_path=$armPath;expires_utc_ms=9999999999999}
$guest=[pscustomobject]@{run=$arm.run;producer_pid=20;producer_start_filetime='12345';target_pid=10;target_start_filetime=$arm.game_start_filetime;
    result='input_completed';closed_published=$true;mapping_unmapped=$true;mapping_handle_closed=$true;mutex_handle_closed=$true;
    lab_evidence=[pscustomobject]@{controls_released=$true;input_handles_closed=$true;closed_acknowledgement_published=$true;normal_shutdown_requested=$true;
        physical_movement=[pscustomobject]@{completed=$true;trace_closed=$true;controls_released=$true;client_proxy_released=$true;server_proxy_released=$true}}}
$verification=[pscustomobject]@{schema=1;kind='minecome_hud_walking_aimed_controller_v1';run=$arm.run;result='passed';failure=$null;target_pid=10;target_start_filetime=$arm.game_start_filetime;
    compositor_armed=$true;restoration_verified=$true;trace_passed=$true;camera_worker=[pscustomobject]@{Stopped=$true;ResourcesClosed=$true;Failure=$null};
    host_gpu_budget=[pscustomobject]@{restoration_verified=$true};guest=$guest}
$aimed=[pscustomobject]@{schema=1;kind='minecome_hud_walking_aimed_cleanup_v1';run=$arm.run;aim_cleanup_before_follower_finish=$true;
    relay=[pscustomobject]@{run=$arm.run;failure=$null;cleanup_failure=$null;exit_code=0;exit_observed=$true;cleanup_verified=$true;input_cleanup_verified=$true;guest_world_cleanup_complete=$true}}
if($CompletedEvidenceDirectory){
    # Replay retained genuine completion in an isolated filesystem fixture. Only
    # the opt-in profile markers and destination path are adapted; gameplay and
    # cleanup observations remain exactly those in the completed run.
    $arm=ConvertFrom-HudRepeatJson (Read-HudRepeatBytes (Join-Path $CompletedEvidenceDirectory 'capture/stream-arming.json'))
    $arm | Add-Member NoteProperty repeat_session $true -Force
    $arm | Add-Member NoteProperty session_generation 1 -Force
    $arm.arm_path=$armPath
    $verification=ConvertFrom-HudRepeatJson (Read-HudRepeatBytes (Join-Path $CompletedEvidenceDirectory 'verification.json'))
    $aimed=ConvertFrom-HudRepeatJson (Read-HudRepeatBytes (Join-Path $CompletedEvidenceDirectory 'aimed-verification.json'))
    $context.GamePid=$arm.game_pid;$context.GameStartedUtc=[DateTime]::FromFileTimeUtc([long]$arm.game_start_filetime)
}
try{
    Assert-HudRepeatCompletion $arm $verification $aimed;Check $true 'Complete combined proof accepted'
    foreach($change in @(
        {param($v)$v.result='failed'}, {param($v)$v.run='c'*32}, {param($v)$v.restoration_verified=$false},
        {param($v)$v.camera_worker.ResourcesClosed=$false}, {param($v)$v.guest.producer_pid=21},
        {param($v)$v.guest.mapping_unmapped=$false}, {param($v)$v.guest.lab_evidence.closed_acknowledgement_published=$false},
        {param($v)$v.guest.lab_evidence.physical_movement.server_proxy_released=$false}
    )){$bad=Clone $verification;& $change $bad;Reject {Assert-HudRepeatCompletion $arm $bad $aimed} 'Incomplete or wrong-generation cleanup refused'}
    $bad=Clone $aimed;$bad.relay.input_cleanup_verified=$false
    Reject {Assert-HudRepeatCompletion $arm $verification $bad} 'Pending aimed authority refused'
    $bad=Clone $arm;$bad.repeat_session=$false
    Reject {Assert-HudRepeatCompletion $bad $verification $aimed} 'One-shot arm cannot publish rearm proof'
    $armText=@('[HudStream]','Schema=1',"Run=$($arm.run)","TargetPid=$($arm.game_pid)","TargetStart=$($arm.game_start_filetime)","ProducerPid=$($arm.producer_pid)","ProducerStart=$($arm.producer_start_filetime)","ExpiresUtcMs=$($arm.expires_utc_ms)") -join "`n"
    $armBytes=[Text.UTF8Encoding]::new($false).GetBytes($armText+"`n")
    $arm.arm_sha256=Get-HudRepeatHash $armBytes
    Write-HudRepeatNewFile $armPath $armBytes
    $receiptPath=Join-Path $capture 'stream-arming.json'
    $verificationPath=Join-Path $directory 'verification.json';$aimedPath=Join-Path $directory 'aimed-verification.json'
    $arm | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
    $verification | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $verificationPath -Encoding utf8NoBOM
    $aimed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $aimedPath -Encoding utf8NoBOM
    Publish-HudRepeatCleanup $arm $verificationPath $aimedPath $context | Out-Null
    $prefix=$armPath+'.'+$arm.run
    $proofHash=Get-HudRepeatHash (Read-HudRepeatBytes ($prefix+'.verification.json'))
    Check ($proofHash -ceq (Get-HudRepeatHash (Read-HudRepeatBytes $verificationPath))) 'Native receives exact verified JSON bytes'
    Reject {Publish-HudRepeatCleanup $arm $verificationPath $aimedPath $context} 'Cleanup publication cannot overwrite evidence'
    Reject {Complete-HudRepeatPreviousArm $receiptPath $context -PreflightOnly} 'Missing native retirement blocks rearm'
    $ack=Get-HudRepeatIdentity $arm;$ack.VerificationSha256=$proofHash;$ack.Generation='1';$ack.State='idle'
    Assert-HudRepeatRetired $arm $ack $proofHash;Check $true 'Exact idle native generation accepted'
    foreach($field in @('RunId','ArmSha256','TargetPid','ProducerStartFileTime','VerificationSha256','Generation','State')){
        $bad=@{};foreach($key in $ack.Keys){$bad[$key]=$ack[$key]};$bad[$field]='wrong'
        Reject {Assert-HudRepeatRetired $arm $bad $proofHash} "Wrong retirement identity refused: $field"
    }
    $bad=Clone $arm;$bad.session_generation=2
    Reject {Assert-HudRepeatRetired $bad $ack $proofHash} 'Third session refused'
    Write-HudRepeatNewFile ($prefix+'.retired.ini') (ConvertTo-HudRepeatIni 'MineComeRearmRetired' $ack)
    $waitResult=Wait-HudRepeatRetirement $arm $context
    Check ($waitResult -like '*generation=1 state=idle') 'Controller waits for matching native retirement before returning'
    $preflight=Complete-HudRepeatPreviousArm $receiptPath $context -PreflightOnly
    Check ($preflight.Generation -eq 2 -and (Test-Path -LiteralPath $armPath)) 'Rearm preflight leaves existing arm in place'
    $completed=Complete-HudRepeatPreviousArm $receiptPath $context
    Check ($completed.Generation -eq 2 -and -not (Test-Path -LiteralPath $armPath)) 'Verified retirement archives old arm in same live process'
    $null=Complete-HudRepeatPreviousArm $receiptPath $context -PreflightOnly
    Check $true 'Owned archive remains valid if next producer preparation must be retried'
    $wrong=Clone $context;$wrong.GamePid=11
    Reject {Complete-HudRepeatPreviousArm $receiptPath $wrong -PreflightOnly} 'Changed target blocks archived authority'
    [IO.File]::AppendAllText(($prefix+'.retired.ini'),"Unknown=1`n")
    Reject {Complete-HudRepeatPreviousArm $receiptPath $context -PreflightOnly} 'Extra acknowledgement fields refused'
    foreach($relative in @('scripts/HudRepeatSession.ps1','scripts/Arm-HudStream.ps1','scripts/Test-HudWalkingAimed.ps1','scripts/Start-HudWalkingAimed.ps1')){
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$errors)
        Check ($errors.Count -eq 0) "Syntax errors: $relative"
    }
    Write-Output "HUD_REPEAT_SESSION_TESTS_PASS checks=$script:checks retained_completion=$([bool]$CompletedEvidenceDirectory)"
}finally{
    $resolved=[IO.Path]::GetFullPath($directory)
    $allowed=[IO.Path]::GetFullPath((Join-Path $root 'runtime/evidence'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('hud-repeat-fixture-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
