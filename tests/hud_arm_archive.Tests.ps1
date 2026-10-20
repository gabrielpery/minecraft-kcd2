#Requires -Version 5.1
# Pure prior-process authority checks. No process or filesystem changes.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Archive-HudArm.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Archive helper syntax invalid.'}
$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Assert-ExpiredPriorProcessAuthority'},$true)
. ([scriptblock]::Create($node.Extent.Text))
$script:checks=0
function Check($Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Message}
$gamePath='C:\owned\KingdomCome.exe';$now=1792000000000L
$currentStart=[DateTimeOffset]::FromUnixTimeMilliseconds($now-1000).UtcDateTime.ToFileTimeUtc()
$oldStart=[DateTimeOffset]::FromUnixTimeMilliseconds($now-20000).UtcDateTime.ToFileTimeUtc()
$oldProducerStart=$oldStart+10000
function Receipt {
    [pscustomobject]@{schema=1;kind='minecome_hud_stream_arm_v1';run='0123456789abcdef0123456789abcdef';game_pid=10;game_start_filetime=[string]$oldStart;producer_pid=20;producer_start_filetime=[string]$oldProducerStart;expires_utc_ms=$now-10000}
}
function Arm($Receipt){@('[HudStream]','Schema=1',"Run=$($Receipt.run)","TargetPid=$($Receipt.game_pid)","TargetStart=$($Receipt.game_start_filetime)","ProducerPid=$($Receipt.producer_pid)","ProducerStart=$($Receipt.producer_start_filetime)","ExpiresUtcMs=$($Receipt.expires_utc_ms)") -join "`n"}
function Games {,@([pscustomobject]@{Id=30;Path=$gamePath;StartFileTime=$currentStart})}
$r=Receipt;$text=Arm $r;$games=Games
$pin=Assert-ExpiredPriorProcessAuthority $r $text $games @() $gamePath $now
Check ($pin.current_pid -eq 30 -and $pin.current_start_filetime -ceq [string]$currentStart) 'Fresh different game identity is pinned'
$null=Assert-ExpiredPriorProcessAuthority $r ($text.Replace("`n","`r`n")+"`r`n") $games @() $gamePath $now $pin;Check $true 'Exact repeated identity and CRLF accepted'
foreach($field in @('Run','TargetPid','TargetStart','ProducerPid','ProducerStart','ExpiresUtcMs','Schema')){
    $changed=$text -replace ('(?m)^'+$field+'=.*$'),($field+'=999')
    Reject {Assert-ExpiredPriorProcessAuthority $r $changed $games @() $gamePath $now} "Changed INI identity refused: $field"
}
foreach($bad in @(($text+"`nRun=$($r.run)"),($text+"`nUnknown=1"),$text.Replace('[HudStream]','[HudPreview]'),$text.Replace('TargetPid=10','TargetPid=010'))){Reject {Assert-ExpiredPriorProcessAuthority $r $bad $games @() $gamePath $now} 'Malformed stream arm refused'}
foreach($oldPid in @(10,20)){
    Reject {Assert-ExpiredPriorProcessAuthority $r $text $games @([pscustomobject]@{Id=$oldPid}) $gamePath $now} 'Original/recycled process PID refused'
}
Reject {Assert-ExpiredPriorProcessAuthority $r $text @() @() $gamePath $now} 'Missing current game refused'
Reject {Assert-ExpiredPriorProcessAuthority $r $text @($games[0],$games[0]) @() $gamePath $now} 'Multiple current games refused'
foreach($case in @('oldtarget','oldproducer','foreignpath','oldstart','preexpiry','futurestart')){
    $games=Games
    switch($case){'oldtarget'{$games[0].Id=10};'oldproducer'{$games[0].Id=20};'foreignpath'{$games[0].Path='C:\other\KingdomCome.exe'};'oldstart'{$games[0].StartFileTime=$oldStart};'preexpiry'{$games[0].StartFileTime=[DateTimeOffset]::FromUnixTimeMilliseconds($r.expires_utc_ms).UtcDateTime.ToFileTimeUtc()};'futurestart'{$games[0].StartFileTime=[DateTimeOffset]::FromUnixTimeMilliseconds($now+1).UtcDateTime.ToFileTimeUtc()}}
    Reject {Assert-ExpiredPriorProcessAuthority $r $text $games @() $gamePath $now} "Unsafe new process refused: $case"
}
$games=Games;$games[0].StartFileTime++;Reject {Assert-ExpiredPriorProcessAuthority $r $text $games @() $gamePath $now $pin} 'Same PID with changed start cannot pass final check'
$games=Games;$games[0].Id=31;Reject {Assert-ExpiredPriorProcessAuthority $r $text $games @() $gamePath $now $pin} 'Changed PID cannot pass final check'
$games=Games;$r=Receipt;$r.expires_utc_ms=$now;Reject {Assert-ExpiredPriorProcessAuthority $r (Arm $r) $games @() $gamePath $now} 'Unexpired arm refused'
$r=Receipt;$r.kind='minecome_hud_preview_arm_v1';Reject {Assert-ExpiredPriorProcessAuthority $r (Arm $r) $games @() $gamePath $now} 'Preview arm cannot use live cleanup opt-in'
$r=Receipt;$r.game_pid=$true;Reject {Assert-ExpiredPriorProcessAuthority $r $text $games @() $gamePath $now} 'Untyped identity refused'
Check ($ast.Extent.Text.Contains('if(-not $ExpiredPriorProcess -and ($gameOpen -or (Game-Open)))')) 'Default still refuses open game'
Write-Output "HUD_ARM_ARCHIVE_TESTS_PASS checks=$script:checks no_game_actions=true"
