#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
function Test-MineComeInputLabMarker {
    param(
        [Parameter(Mandatory)][string]$Log,
        [Parameter(Mandatory)][ValidateSet('READY','PASS')][string]$Event,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$Run,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ViewHash,
        [Parameter(Mandatory)][ValidateSet('standalone_fixture','live_kcd_view_seed')][string]$ViewKind
    )
    $pattern='(?m)^[^\r\n]*\bEXTERNAL_INPUT_LAB_'+$Event+' inputRun='+$Run+' (?<fields>[^\r\n]*)\r?$'
    $markers=[regex]::Matches($Log,$pattern)
    if($markers.Count -ne 1){return $false}
    $fields=$markers[0].Groups['fields'].Value
    $required=[ordered]@{viewSeedSha256=$ViewHash.ToLowerInvariant();viewSeedKind=$ViewKind;initialClientViewVerified='true';initialServerViewVerified='true';initialViewSnapshotOnly='true'}
    if($Event -ceq 'PASS'){
        $required.actualVanillaMCInputApplication='true';$required.inputNeutralAfterEnd='true';$required.fullWorldMovementAuthorityVerified='false'
    }
    foreach($key in $required.Keys){
        $values=[regex]::Matches($fields,'(?:^|\s)'+$key+'=(?<value>\S+)')
        if($values.Count -ne 1 -or $values[0].Groups['value'].Value -cne $required[$key]){return $false}
    }
    return $true
}
