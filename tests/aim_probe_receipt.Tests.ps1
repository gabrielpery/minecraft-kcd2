#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Pure receipt fixtures: no engine context, HTTP, processes, or game writes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/AimProbeReceipt.ps1')
$script:checks = 0
$run = '0123456789abcdef0123456789abcdef'
function Check([bool]$Value, [string]$Message) {
    $script:checks++
    if (-not $Value) { throw $Message }
}
function Reject([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Check $failed $Message
}
function New-Receipt([string]$Result = 'hit') {
    $r = [ordered]@{
        schema=1;run=$run;result=$Result;reason='none';engine_time=42.0;completed_engine_time=42.01
        origin=[ordered]@{x=120.0;y=2040.0;z=57.0};forward=[ordered]@{x=0.0;y=1.0;z=0.0}
        direction=[ordered]@{x=0.0;y=4.5;z=0.0};range=4.5;max_hits=16;mask_name='ent_all';mask=287
        skip_player=$true;hit_count=1;obstruction_known=$true;clear=$false
        nearest_position=[ordered]@{x=120.0;y=2042.0;z=57.0};nearest_distance=2.0
        diagnostic_only=$true;aiming_verified=$false
    }
    if ($Result -ne 'hit') { $r.hit_count=0;$r.nearest_position=$null;$r.nearest_distance=$null }
    if ($Result -eq 'no_hit') { $r.clear=$true }
    if ($Result -eq 'unavailable') { $r.obstruction_known=$false;$r.reason='ray_error' }
    return $r
}
foreach ($result in @('hit','no_hit')) {
    foreach ($json in @($false,$true)) {
        $receipt=New-Receipt $result
        if ($json) { $receipt=$receipt | ConvertTo-Json -Depth 5 | ConvertFrom-Json }
        Check (@(Assert-MineComeAimReceipt $receipt $run).Count -eq 0) 'Valid receipt was rejected or returned output.'
    }
}
foreach ($distance in @(0.0,4.5)) {
    $receipt=New-Receipt;$receipt.nearest_distance=$distance;$receipt.nearest_position.y=2040+$distance
    Assert-MineComeAimReceipt $receipt $run;Check $true 'Inclusive ray endpoints rejected.'
}
$receipt=New-Receipt;$receipt.forward.x=0.6;$receipt.forward.y=0.8
$receipt.direction.x=2.7;$receipt.direction.y=3.6
$receipt.nearest_position.x=121.2;$receipt.nearest_position.y=2041.6
Assert-MineComeAimReceipt $receipt $run;Check $true 'Valid oblique geometry rejected.'
$receipt=New-Receipt;$receipt.direction.x=0.0000009
Assert-MineComeAimReceipt $receipt $run;Check $true 'Serialization-scale direction tolerance rejected.'
$receipt=New-Receipt;$receipt.forward.y=1.0000001;$receipt.direction.y=4.50000045
Assert-MineComeAimReceipt $receipt $run;Check $true 'Serialization-scale normalized vector tolerance rejected.'
$receipt=New-Receipt;$receipt.nearest_position.x+=0.0099
Assert-MineComeAimReceipt $receipt $run;Check $true 'Sub-centimetre residual rejected.'
foreach ($time in @(0.0,1000000000000.0)) {
    $receipt=New-Receipt;$receipt.engine_time=$time;$receipt.completed_engine_time=$time
    Assert-MineComeAimReceipt $receipt $run;Check $true 'Inclusive clock bound rejected.'
}
$receipt=New-Receipt;$receipt.completed_engine_time=42.25
Assert-MineComeAimReceipt $receipt $run;Check $true 'Inclusive duration bound rejected.'

$base=New-Receipt
foreach ($field in @($base.Keys)) {
    foreach ($json in @($false,$true)) {
        $receipt=New-Receipt;$receipt.Remove($field)
        if ($json) { $receipt=$receipt | ConvertTo-Json -Depth 5 | ConvertFrom-Json }
        Reject { Assert-MineComeAimReceipt $receipt $run } "Missing field accepted: $field"
    }
}
foreach ($value in @($null,$false,$true,1,'receipt',@(),@(1,2))) {
    Reject { Assert-MineComeAimReceipt $value $run } 'Non-object receipt accepted.'
}
foreach ($field in @('schema','range','max_hits','mask','hit_count','engine_time','completed_engine_time','nearest_distance')) {
    foreach ($bad in @($null,$false,$true,'1',@{},@(1),[double]::NaN,[double]::PositiveInfinity,[double]::NegativeInfinity)) {
        $receipt=New-Receipt;$receipt[$field]=$bad
        Reject { Assert-MineComeAimReceipt $receipt $run } "Nonnumeric/nonfinite field accepted: $field"
    }
}
foreach ($field in @('diagnostic_only','aiming_verified','obstruction_known','clear','skip_player')) {
    foreach ($bad in @($null,0,1,'true','false',@{},@($true))) {
        $receipt=New-Receipt;$receipt[$field]=$bad
        Reject { Assert-MineComeAimReceipt $receipt $run } "Coerced Boolean accepted: $field"
    }
    $receipt=New-Receipt;$receipt[$field]=-not $receipt[$field]
    Reject { Assert-MineComeAimReceipt $receipt $run } "Wrong Boolean flag accepted: $field"
}
foreach ($field in @('origin','forward','direction','nearest_position')) {
    foreach ($bad in @($null,1,'vector',@(1,2,3))) {
        $receipt=New-Receipt;$receipt[$field]=$bad
        Reject { Assert-MineComeAimReceipt $receipt $run } "Malformed vector accepted: $field"
    }
    foreach ($axis in @('x','y','z')) {
        foreach ($bad in @($null,$true,'0',10000001,-10000001,[double]::NaN,[double]::PositiveInfinity)) {
            $receipt=New-Receipt;$receipt[$field][$axis]=$bad
            Reject { Assert-MineComeAimReceipt $receipt $run } "Invalid vector component accepted: $field.$axis"
        }
        $receipt=New-Receipt;$receipt[$field].Remove($axis)
        Reject { Assert-MineComeAimReceipt $receipt $run } "Absent vector component accepted: $field.$axis"
    }
}
foreach ($pair in @(
    @('schema',2),@('range',4.499),@('max_hits',15),@('mask',0),@('mask',-1),@('mask',287.5),@('mask',2147483648),
    @('hit_count',0),@('hit_count',1.5),@('hit_count',16),@('hit_count',-1),@('nearest_distance',-0.01),@('nearest_distance',4.5001),
    @('engine_time',-1),@('engine_time',1000000000001),@('completed_engine_time',41.99),@('completed_engine_time',42.251),
    @('completed_engine_time',1000000000001),@('mask_name','ENT_ALL'),@('result','HIT'),@('reason','other'),@('run',$run.ToUpperInvariant())
)) {
    $receipt=New-Receipt;$receipt[$pair[0]]=$pair[1]
    Reject { Assert-MineComeAimReceipt $receipt $run } "Out-of-contract field accepted: $($pair[0])"
}
foreach ($field in @('run','result','reason','mask_name')) {
    foreach ($bad in @($null,1,$true,@{})) {
        $receipt=New-Receipt;$receipt[$field]=$bad
        Reject { Assert-MineComeAimReceipt $receipt $run } "Nonstrings accepted: $field"
    }
}
foreach ($badRun in @('',('a'*31),('g'*32),($run.ToUpperInvariant()),('a'*32))) {
    Reject { Assert-MineComeAimReceipt (New-Receipt) $badRun } 'Invalid or mismatched captured run accepted.'
}
$receipt=New-Receipt;$receipt.forward.y=0;$receipt.direction.y=0
Reject { Assert-MineComeAimReceipt $receipt $run } 'Zero direction accepted.'
$receipt=New-Receipt;$receipt.forward.y=2;$receipt.direction.y=9
Reject { Assert-MineComeAimReceipt $receipt $run } 'Unnormalized forward accepted.'
$receipt=New-Receipt;$receipt.direction.y=4.500002
Reject { Assert-MineComeAimReceipt $receipt $run } 'Mismatched scaled direction accepted.'
foreach ($axis in @('x','y','z')) {
    $receipt=New-Receipt;$receipt.nearest_position[$axis]+=0.0101
    Reject { Assert-MineComeAimReceipt $receipt $run } 'Hit outside camera ray tolerance accepted.'
}
foreach ($field in @('nearest_distance','nearest_position','hit_count')) {
    $receipt=New-Receipt 'no_hit';$receipt[$field]=(New-Receipt)[$field]
    Reject { Assert-MineComeAimReceipt $receipt $run } 'Clear sample with hit data accepted.'
}
$receipt=New-Receipt 'unavailable'
Reject { Assert-MineComeAimReceipt $receipt $run } 'Unavailable sample became verified.'
foreach ($field in @('obstruction_known','clear')) {
    $receipt=New-Receipt 'unavailable';$receipt[$field]=$true
    Reject { Assert-MineComeAimReceipt $receipt $run } 'Unavailable sample claimed clear/known.'
}

# Inspect call ordering without executing the controller or its game helpers.
$controller=Get-Content -Raw -LiteralPath (Join-Path $root 'scripts/Test-KcdAimProbe.ps1')
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseInput($controller,[ref]$tokens,[ref]$errors) | Out-Null
Check ($errors.Count -eq 0) 'Controller parse failure.'
$save=$controller.IndexOf("Join-Path `$probe.Directory 'receipt.json'")
$validate=$controller.IndexOf('Assert-MineComeAimReceipt $receipt $probe.Run')
$known=$controller.IndexOf('$known=$true')
Check ($save -ge 0 -and $validate -gt $save -and $known -gt $validate) 'Receipt must be preserved, validated, then marked known.'
Write-Output "Aim receipt: $script:checks checks passed (pure mocked receipts; no engine access)."
