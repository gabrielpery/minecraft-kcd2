#Requires -Version 7.3
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudInputPrompt.ps1')
$checks=0
function Check($Value,[string]$Why){$script:checks++;if(-not $Value){throw $Why}}
function Reject([scriptblock]$Action,[string]$Why){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Why}
function Clone($Value){$Value|ConvertTo-Json -Depth 8|ConvertFrom-Json}
$run='a'*32;$now=1793201500000L
$ready=[pscustomobject]@{schema=1;run=$run;save='test-owned-save';ui_input_walking_aimed=$true;movement_session='extended';
    target_pid=1;target_start_filetime='123';expires_utc_ms=$now+180000;producer_pid=2;producer_start_filetime='456'}
$physical=[pscustomobject]@{schema=1;kind='minecome_hud_physical_ready_v1';ready=$true;run=$run;save=$ready.save;
    movement_session='extended';target_pid=1;target_start_filetime='123';utc_ms=$now-1000;
    stream_started_utc_ms=$now-10000;activation_deadline_utc_ms=$now+50000}
$prompt=[pscustomobject]@{schema=1;kind='minecome_hud_input_prompt_v1';run=$run;sampled_utc_ms=$now;controller_deadline_utc_ms=$now+100000}
function Window($R=$ready,$P=$physical,$M=$prompt,[long]$At=$now,[int]$Minimum=15){Get-HudInputPromptWindow $R $P $M $run $At $Minimum}
$w=Window;Check ($w.can_prompt -and $w.remaining_seconds -eq 50) 'Fresh exact deadline rejected'
Check (-not $w.activation_state_checked) 'Helper must not claim native F8 state'
$w=Window -At ($now+47000);Check (-not $w.can_prompt -and $w.remaining_seconds -eq 3) 'Buffered READY incorrectly renewed countdown'
$w=Window -At ($now+50000);Check (-not $w.can_prompt -and $w.remaining_seconds -eq 0) 'Expired activation accepted'
Check (Window -At ($now+35000)).can_prompt 'Exact15-second minimum rejected'
Check (-not (Window -At ($now+35001)).can_prompt) 'Fractional remaining time rounded up'
$late=Clone $physical;$late.stream_started_utc_ms=$now-57000;$late.activation_deadline_utc_ms=$now+3000
Check (-not (Window -P $late).can_prompt) 'Late physical-ready restarted guest60-second budget'
$short=Clone $prompt;$short.controller_deadline_utc_ms=$now+45000
$w=Window -M $short;Check (-not $w.can_prompt -and $w.remaining_seconds -eq 10) 'Controller35-second margin lost'
$lease=Clone $ready;$lease.expires_utc_ms=$now+45000
Check (-not (Window -R $lease).can_prompt) 'Lease lacks full session/cleanup margin'
foreach($field in @('stream_started_utc_ms','activation_deadline_utc_ms')){
    $p=Clone $physical;$p.PSObject.Properties.Remove($field);Reject {Window -P $p} "Legacy missing $field accepted"
    $p=Clone $physical;$p.$field=[double]$p.$field;Reject {Window -P $p} "Nonintegral metadata $field accepted"
}
$p=Clone $physical;$p.activation_deadline_utc_ms++;Reject {Window -P $p} 'Changed60-second guest budget accepted'
$p=Clone $physical;$p.utc_ms=$now+1;Reject {Window -P $p} 'Future readiness accepted'
$p=Clone $physical;$p.utc_ms=$p.stream_started_utc_ms-1;Reject {Window -P $p} 'Readiness before guest start accepted'
$m=Clone $prompt;$m.sampled_utc_ms=$now+1;Reject {Window -M $m} 'Future prompt observation accepted'
Reject {Window -At ($now-1)} 'Clock regression accepted'
$r=Clone $ready;$r.run='b'*32;Reject {Window -R $r} 'Different producer run accepted'
$p=Clone $physical;$p.run='b'*32;Reject {Window -P $p} 'Different physical run accepted'
$m=Clone $prompt;$m.run='b'*32;Reject {Window -M $m} 'Different prompt run accepted'
$p=Clone $physical;$p.target_start_filetime='124';Reject {Window -P $p} 'Different target identity accepted'
$p=Clone $physical;$p.ready='true';Reject {Window -P $p} 'String readiness accepted'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$directory=Join-Path $root ('runtime/evidence/hud-input-prompt-test-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($directory)
function Save([string]$Name,$Value){$Value|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $directory $Name) -Encoding utf8NoBOM}
try{
    $liveNow=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$self=Get-Process -Id $PID
    $r=Clone $ready;$r.target_pid=$PID;$r.producer_pid=$PID;$r.target_start_filetime=$self.StartTime.ToUniversalTime().ToFileTimeUtc().ToString();$r.producer_start_filetime=$r.target_start_filetime;$r.expires_utc_ms=$liveNow+180000;$self.Dispose()
    $p=Clone $physical;$p.target_pid=$PID;$p.target_start_filetime=$r.target_start_filetime;$p.utc_ms=$liveNow-100;$p.stream_started_utc_ms=$liveNow-1000;$p.activation_deadline_utc_ms=$liveNow+59000
    $m=Clone $prompt;$m.sampled_utc_ms=$liveNow;$m.controller_deadline_utc_ms=$liveNow+100000
    Save 'stream-ready.json' $r;Save 'physical-ready.json' $p;Save 'input-prompt.json' $m
    $w=Read-HudInputPromptWindow $directory $run
    Check ($w.can_prompt -and $w.remaining_seconds -le 59 -and $w.sampled_utc_ms -ge $liveNow) 'Live immutable receipt read failed'
    Save 'walking-aim-ready.json' @{};$w=Read-HudInputPromptWindow $directory $run
    Check (-not $w.can_prompt -and $w.decline_reason -eq 'session_already_active_or_terminal') 'Started movement accepted another prompt'
    Remove-Item -LiteralPath (Join-Path $directory 'walking-aim-ready.json')
    Save 'stream-result.json' @{};Check (-not (Read-HudInputPromptWindow $directory $run).can_prompt) 'Terminal session accepted prompt'
    Remove-Item -LiteralPath (Join-Path $directory 'stream-result.json')
    $r.producer_start_filetime='1';Save 'stream-ready.json' $r;$w=Read-HudInputPromptWindow $directory $run
    Check (-not $w.can_prompt -and $w.decline_reason -eq 'session_process_not_alive') 'Reused producer PID accepted'
    $r.producer_start_filetime=$r.target_start_filetime;$r.producer_pid=[int]::MaxValue;Save 'stream-ready.json' $r
    Check (-not (Read-HudInputPromptWindow $directory $run).can_prompt) 'Missing producer accepted'
    Reject {Read-HudInputPromptWindow $root $run} 'Prompt reader escaped evidence directory'
}finally{
    $resolved=[IO.Path]::GetFullPath($directory)
    if(-not $resolved.StartsWith((Join-Path $root 'runtime/evidence/hud-input-prompt-test-'),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup target'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "HUD_INPUT_PROMPT_TESTS_PASS checks=$checks no_games=true"
