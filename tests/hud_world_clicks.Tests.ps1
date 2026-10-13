#Requires -Version 7.3
# Production log reader/admission with only game/dispatch boundaries replaced.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudStoneRelay.ps1')
. (Join-Path $PSScriptRoot '../scripts/HudWorldClicks.ps1')
$script:checks=0
function Check($Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Body,[string]$Message){$failed=$false;try{& $Body}catch{$failed=$true};Check $failed $Message}
$root=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))) ('runtime/evidence/hud-world-click-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$run='a'*32;$script:foreground=$true;$script:contextGood=$true;$script:dispatchFailure=$false;$script:delayBeforeDispatch=0;$script:sent=0
$context=[pscustomobject]@{GamePid=42;GameStartedUtc=[DateTime]'2026-10-13T00:00:00Z'}
function Assert-MineComeProbeContext($Context){if(-not $script:contextGood){throw 'Simulated lost exact process context'}}
function Test-MineComeHudWorldForeground($Context){$script:foreground}
function New-Case([string]$Initial="old unrelated line`n"){
    $path=Join-Path $root ([guid]::NewGuid().ToString('N')+'.log');[IO.File]::WriteAllText($path,$Initial)
    $state=New-MineComeHudWorldClicks $context $path $run
    $session=[pscustomobject]@{Run=$run;Context=$context;Intents=[Collections.Generic.List[object]]::new();LastIntentUtcMs=0L;ExpiresUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+180000;Failure=$null}
    [pscustomobject]@{State=$state;Session=$session;Path=$path}
}
function Line([long]$Sequence=1,[int]$Action=1,[long]$Utc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){'[MineComeWorldInput] '+([ordered]@{schema=1;run=$run;sequence=$Sequence;utc_ms=$Utc;action=$Action}|ConvertTo-Json -Compress)}
function Append($Case,[string]$Text){[IO.File]::AppendAllText($Case.Path,$Text,[Text.UTF8Encoding]::new($false))}
function Send-MineComeHudStoneIntent($Session,[int]$Action,[scriptblock]$BeforeDispatch){
    if($script:delayBeforeDispatch){Start-Sleep -Milliseconds $script:delayBeforeDispatch}
    $reason=& $BeforeDispatch;if($reason){return [pscustomobject]@{accepted=$false;declined=$true;reason=$reason}}
    if($script:dispatchFailure){throw 'Simulated ambiguous send'}
    $script:sent++;$r=[pscustomobject]@{ordinal=$Session.Intents.Count+1;request_id=[long](100+$script:sent);action=$Action;accepted=$true}
    $Session.Intents.Add($r);$Session.LastIntentUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$r
}
$valid=Line;$decoded=ConvertFrom-MineComeHudWorldClick $valid $run 0
Check ($decoded.sequence -ceq 1L -and $decoded.action -ceq 1) 'Exact typed click decoded'
Check ($null -eq (ConvertFrom-MineComeHudWorldClick 'Unrelated ReShade status' $run 0)) 'Unrelated logs ignored'
$decoded=ConvertFrom-MineComeHudWorldClick ('12:34:56 [INFO] '+$valid) $run 0
Check ($decoded.sequence -eq 1) 'Standard ReShade prefix accepted'
$badIndex=0;foreach($bad in @(
    $valid.Replace('"schema":1','"schema":"1"'),$valid.Replace('"schema":1','"schema":1.0'),$valid.Replace('"schema":1','"schema":true'),
    $valid.Replace('"schema":1','"schema":2'),$valid.Replace('"action":1','"action":3'),$valid.Replace('"sequence":1','"sequence":0'),
    $valid.Replace('"sequence":1','"sequence":2'),$valid.Replace('"run":"'+$run+'"','"run":"'+('b'*32)+'"'),
    $valid.Replace('"schema":1','"schema":1,"schema":1'),$valid.Replace('"schema":1','"schema":1,"extra":0'),
    $valid.Replace('"schema":1,',''),($valid+' trailing'),'[MineComeWorldInput] nope','[MineComeWorldInput] {bad}',
    $valid.Replace('"sequence":1','"sequence":9223372036854775808'))){Reject {ConvertFrom-MineComeHudWorldClick $bad $run 0} "Malformed/run/order record rejected index=$badIndex : $bad";$badIndex++}
Reject {ConvertFrom-MineComeHudWorldClick (Line 1) $run 1} 'Duplicate sequence rejected'
Reject {ConvertFrom-MineComeHudWorldClick (Line 17) $run 16} 'Seventeenth click rejected'
$c=New-Case;Invoke-MineComeHudWorldClicks $c.State $c.Session
Check ($c.State.Clicks.Count -eq 0) 'Initial log skipped'
$text=Line;Append $c $text.Substring(0,12);Invoke-MineComeHudWorldClicks $c.State $c.Session
Check ($c.State.Clicks.Count -eq 0 -and $c.State.Pending.Length -eq 12) 'Partial new record retained'
Append $c ($text.Substring(12)+"`n");Invoke-MineComeHudWorldClicks $c.State $c.Session
Assert-MineComeHudWorldClicks $c.State $c.Session
Check ($c.State.Clicks.Count -eq 1 -and $c.State.Clicks[0].status -ceq 'sent' -and $c.State.Clicks[0].request_id -eq $c.Session.Intents[0].request_id) 'Complete edge correlates to exact intent'
$e=Get-MineComeHudWorldClickEvidence $c.State $c.Session
Check (-not $e.physical_input_verified -and -not $e.visual_verified -and -not $e.engine_mirroring_verified -and -not $e.os_input_generated) 'Fixture receipt makes no live claims'
Invoke-MineComeHudWorldClicks $c.State $c.Session;Check ($c.State.Clicks.Count -eq 1) 'Repeated poll never replays'
$c=New-Case 'partial old line';Append $c (" appended tail`n"+(Line)+"`n");Invoke-MineComeHudWorldClicks $c.State $c.Session
Check ($c.State.Clicks.Count -eq 1) 'Initial trailing fragment skipped once'
foreach($case in @('stale_edge','future_edge','host_not_foreground','expired_lease','intent_spacing','intent_capacity')){
    $c=New-Case;$utc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    switch($case){
        stale_edge {$utc-=1000}
        future_edge {$utc+=1000}
        host_not_foreground {$script:foreground=$false}
        expired_lease {$c.Session.ExpiresUtcMs=$utc-1}
        intent_spacing {$c.Session.LastIntentUtcMs=$utc}
        intent_capacity {for($i=0;$i -lt 16;$i++){$c.Session.Intents.Add([pscustomobject]@{ordinal=$i+1})}}
    }
    $before=$script:sent;Append $c ((Line -Utc $utc)+"`n");Invoke-MineComeHudWorldClicks $c.State $c.Session
    Check ($c.State.Clicks[0].status -ceq 'declined' -and $c.State.Clicks[0].reason -ceq $case -and $script:sent -eq $before -and $null -eq $c.Session.Failure) "${case}: explicit nonfatal decline before dispatch"
    $script:foreground=$true
}
$c=New-Case;$script:delayBeforeDispatch=300;Append $c ((Line)+"`n");Invoke-MineComeHudWorldClicks $c.State $c.Session;$script:delayBeforeDispatch=0
Check ($c.State.Clicks[0].reason -ceq 'stale_edge' -and $c.Session.Intents.Count -eq 0) 'Freshness rechecked after relay health delay'
$c=New-Case;Append $c ((Line)+"`n"+(Line 2 2)+"`n");Invoke-MineComeHudWorldClicks $c.State $c.Session
Check ($c.State.Clicks.Count -eq 2 -and $c.State.Clicks[1].reason -ceq 'intent_spacing') 'Second click in same batch explicitly declined'
Assert-MineComeHudWorldClicks $c.State $c.Session
$c.Session.Intents[0].request_id++;Reject {Assert-MineComeHudWorldClicks $c.State $c.Session} 'Mismatched physical edge correlation rejected'
foreach($case in @('truncate','replacement','chunk_bound','total_bound','line_bound','partial_bound','duplicate','gap','bad_context','ambiguous_send','owner')){
    $c=New-Case
    switch($case){
        truncate {[IO.File]::WriteAllText($c.Path,'')}
        replacement {$replacement=$c.Path+'.new';[IO.File]::WriteAllText($replacement,'new unrelated log');Move-Item -LiteralPath $c.Path -Destination ($c.Path+'.old');Move-Item -LiteralPath $replacement -Destination $c.Path}
        chunk_bound {Append $c ('x'*(64KB+1))}
        total_bound {$c.State.ReadBytes=2MB;Append $c "x`n"}
        line_bound {Append $c (('x'*4097)+"`n")}
        partial_bound {Append $c ('x'*4097)}
        duplicate {Append $c ((Line)+"`n"+(Line)+"`n")}
        gap {Append $c ((Line 2)+"`n")}
        bad_context {$script:contextGood=$false;Append $c ((Line)+"`n")}
        ambiguous_send {$script:dispatchFailure=$true;Append $c ((Line)+"`n")}
        owner {$c.Session.Run='c'*32}
    }
    Reject {Invoke-MineComeHudWorldClicks $c.State $c.Session} "${case}: fail closed"
    Check ($null -ne $c.State.Failure) "${case}: failure preserved"
    $before=$script:sent;Reject {Invoke-MineComeHudWorldClicks $c.State $c.Session} "${case}: never retry"
    Check ($before -eq $script:sent) "${case}: no replayed dispatch"
    $script:contextGood=$true;$script:dispatchFailure=$false
}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$c=New-Case
foreach($age in @(-100,0,250)){Check ($null -eq (Get-MineComeHudWorldDecline $c.State $c.Session ([pscustomobject]@{utc_ms=$now-$age}) $now)) 'Inclusive freshness/future bounds accepted'}
foreach($age in @(-101,251)){Check ($null -ne (Get-MineComeHudWorldDecline $c.State $c.Session ([pscustomobject]@{utc_ms=$now-$age}) $now)) 'Outside exact time bounds declined'}
# Restore the actual production sender to prove the dynamic callback retains the
# same reader/click while the console and listener boundary remain simulated.
. (Join-Path $PSScriptRoot '../scripts/HudStoneRelay.ps1')
function Assert-MineComeHudStoneRelay($Session){Assert-MineComeProbeContext $Session.Context}
function Invoke-MineComeProbeConsole($Context,[string]$Command){
    if($Command -match '\[MineComeHudStoneIntent\] ([a-f0-9]{32}) ([0-9]+) ([12]) '){[IO.File]::AppendAllText($Context.GameLog,"[MineComeHudStoneIntent] $($Matches[1]) $($Matches[2]) $($Matches[3]) true 201`n")}
}
function Read-MineComeProbeLog($Context,[long]$Offset){[IO.File]::ReadAllText($Context.GameLog).Substring([int]$Offset)}
$c=New-Case;$c.Session.Context=$context.PSObject.Copy();$gameLog=Join-Path $root 'simulated-game.log';[IO.File]::WriteAllText($gameLog,'');$c.Session.Context|Add-Member NoteProperty GameLog $gameLog
Append $c ((Line)+"`n");Invoke-MineComeHudWorldClicks $c.State $c.Session;Assert-MineComeHudWorldClicks $c.State $c.Session
Check ($c.State.Clicks[0].request_id -eq 201 -and $c.Session.Intents[0].action -eq 1 -and $c.State.Clicks[0].status -ceq 'sent') 'Actual sender callback preserves physical edge to engine request correlation'
Write-Output "HUD_WORLD_CLICKS_TEST_PASS checks=$script:checks simulated_receipts_only=true no_game_actions=true evidence=$root"
