#requires -Version 5.1
# SPDX-License-Identifier: GPL-3.0-or-later
# Synthetic timing/receipt admission only. No KCD, renderer or physical input.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/AimedWorldClicks.ps1')
$run='0123456789abcdef0123456789abcdef'
$checks=0
function Check([bool]$Ok,[string]$Label){if(-not $Ok){throw "Aimed click check failed: $Label"};$script:checks++}
function Click([long]$Sequence,[long]$Time,[int]$Action=2){[pscustomobject]@{sequence=$Sequence;utc_ms=$Time;action=$Action}}
function Permit($State,[long]$Id,[long]$At){Add-MineComeAimedPermitLine $State "AIM_PERMIT_READY run=$run arena=1 permit=$Id installed_utc_ms=$At"}
function Refuses([scriptblock]$Code,[string]$Label){$rejected=$false;try{& $Code | Out-Null}catch{$rejected=$true};Check $rejected $Label}

$state=New-MineComeAimedClickLedger $run
Permit $state 1 1000
Permit $state 2 1100
$bound=Select-MineComeAimedClickPermit $state (Click 1 1050) 1110
Check ($bound.accepted -and $bound.permit -ceq '1') 'newer permit cannot attach to older click'
Check ($bound.command -ceq "#MineCome.AimedIntent('$run','1','1','1',2)") 'literal original identities reach Lua'
$bound=Select-MineComeAimedClickPermit $state (Click 2 1150 1) 1160
Check ($bound.accepted -and $bound.permit -ceq '2' -and $bound.action -eq 1) 'next physical click uses its earlier permit'
$bound=Select-MineComeAimedClickPermit $state (Click 3 1170) 1180
Check (-not $bound.accepted -and $bound.reason -ceq 'no_preclick_permit') 'ambiguous dispatch never reuses a spent permit'

$state=New-MineComeAimedClickLedger $run
Permit $state 1 2000
Check ((Select-MineComeAimedClickPermit $state (Click 1 1999) 2010).reason -ceq 'no_preclick_permit') 'click predates all acknowledgements'
Check ((Select-MineComeAimedClickPermit $state (Click 2 2050) 2301).reason -ceq 'stale_edge') 'old physical edge rejected'
Check ((Select-MineComeAimedClickPermit $state (Click 3 2310) 2351).reason -ceq 'no_preclick_permit') 'old acknowledged permit rejected'
Check ((Select-MineComeAimedClickPermit $state (Click 4 2401) 2400).reason -ceq 'future_edge') 'future physical edge rejected'
Refuses {Select-MineComeAimedClickPermit $state (Click 5 2400) 2399} 'controller clock rollback fails ledger'
Refuses {Permit $state 2 2450} 'failed ledger cannot resume'

foreach($line in @(
    "AIM_PERMIT_READY run=$run arena=1 permit=0 installed_utc_ms=1000",
    "AIM_PERMIT_READY run=$run arena=1 permit=9007199254740992 installed_utc_ms=1000",
    "AIM_PERMIT_READY run=$run arena=1 permit=1 installed_utc_ms=9223372036854775808",
    "AIM_PERMIT_READY run=$run arena=1 permit=1 installed_utc_ms=1000 extra=true",
    "AIM_PERMIT_READY run=ffffffffffffffffffffffffffffffff arena=1 permit=1 installed_utc_ms=1000"
)){$state=New-MineComeAimedClickLedger $run;Refuses {Add-MineComeAimedPermitLine $state $line} 'malformed or wrong-run permit'}
$state=New-MineComeAimedClickLedger $run;Permit $state 1 1000
Refuses {Permit $state 1 1100} 'replayed permit'
$state=New-MineComeAimedClickLedger $run;Permit $state 1 1000
Refuses {Permit $state 2 999} 'ack clock rollback'
$state=New-MineComeAimedClickLedger $run;Permit $state 1 1000
Refuses {Add-MineComeAimedPermitLine $state "AIM_PERMIT_READY run=$run arena=2 permit=2 installed_utc_ms=1100"} 'arena changes require a new owner'
$state=New-MineComeAimedClickLedger $run
Refuses {Select-MineComeAimedClickPermit $state (Click 2 1000) 1000} 'skipped physical sequence'
$state=New-MineComeAimedClickLedger $run
Refuses {Select-MineComeAimedClickPermit $state (Click 1 1000 3) 1000} 'invalid action'
$state=New-MineComeAimedClickLedger $run
1..20|ForEach-Object {Permit $state $_ (1000+$_)}
Check ($state.Permits.Count -eq 16 -and $state.Permits[0].permit -eq 5) 'bounded sixteen-permit history'
$state=New-MineComeAimedClickLedger $run;Permit $state 1 1000
Check ((Select-MineComeAimedClickPermit $state (Click 1 1000) 1010).reason -ceq 'no_preclick_permit') 'same-millisecond ACK does not prove pre-click installation'
$state=New-MineComeAimedClickLedger $run;Permit $state 1 1000;Permit $state 2 1100
Refuses {Select-MineComeAimedClickPermit $state (Click 1 1050) 1099} 'clock rollback behind an observed ACK cannot fall back to an older permit'
Write-Output "Aimed world click admission: $checks checks passed (synthetic, no game calls)."
