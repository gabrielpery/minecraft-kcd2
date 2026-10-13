#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Pure validation of an already captured diagnostic receipt; no game access.
function Test-MineComeAimNumber($Value) {
    $numeric = $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [short] -or
        $Value -is [ushort] -or $Value -is [int] -or $Value -is [uint] -or
        $Value -is [long] -or $Value -is [ulong] -or $Value -is [single] -or
        $Value -is [double] -or $Value -is [decimal]
    return $numeric -and -not [double]::IsNaN([double]$Value) -and
        -not [double]::IsInfinity([double]$Value)
}

function Assert-MineComeAimFields($Value, [string[]]$Fields) {
    if ($Value -is [Collections.IDictionary]) {
        foreach ($field in $Fields) {
            if (-not $Value.Contains($field)) { throw "Aim receipt field missing: $field" }
        }
    } elseif ($Value -is [pscustomobject]) {
        foreach ($field in $Fields) {
            if ($null -eq $Value.PSObject.Properties[$field]) { throw "Aim receipt field missing: $field" }
        }
    } else { throw 'Aim receipt must contain objects, not arrays or scalar values.' }
}

function Assert-MineComeAimVector($Value) {
    Assert-MineComeAimFields $Value @('x','y','z')
    foreach ($axis in @('x','y','z')) {
        if (-not (Test-MineComeAimNumber $Value.$axis) -or [Math]::Abs([double]$Value.$axis) -gt 10000000) {
            throw 'Aim receipt vector is nonnumeric, nonfinite, or out of bounds.'
        }
    }
}

function Assert-MineComeAimReceipt($Receipt, [string]$Run) {
    Assert-MineComeAimFields $Receipt @('schema','run','result','reason','engine_time',
        'completed_engine_time','origin','forward','direction','range','max_hits','mask_name',
        'mask','skip_player','hit_count','obstruction_known','clear','nearest_position',
        'nearest_distance','diagnostic_only','aiming_verified')
    if ($Run -cnotmatch '^[0-9a-f]{32}$' -or $Receipt.run -isnot [string] -or
        $Receipt.run -cne $Run -or -not (Test-MineComeAimNumber $Receipt.schema) -or $Receipt.schema -ne 1) {
        throw 'Aim receipt schema or exact run identity mismatch.'
    }
    foreach ($field in @('diagnostic_only','aiming_verified','obstruction_known','clear','skip_player')) {
        if ($Receipt.$field -isnot [bool]) { throw 'Aim receipt Boolean contract mismatch.' }
    }
    if (-not $Receipt.diagnostic_only -or $Receipt.aiming_verified -or
        -not (Test-MineComeAimNumber $Receipt.range) -or $Receipt.range -ne 4.5 -or
        -not (Test-MineComeAimNumber $Receipt.max_hits) -or $Receipt.max_hits -ne 16 -or
        $Receipt.mask_name -isnot [string] -or $Receipt.mask_name -cne 'ent_all' -or
        $Receipt.result -isnot [string] -or $Receipt.result -cnotin @('hit','no_hit','unavailable') -or
        $Receipt.reason -isnot [string]) { throw 'Aim receipt diagnostic contract mismatch.' }
    if ($Receipt.result -ceq 'unavailable') {
        if ($Receipt.obstruction_known -or $Receipt.clear -or $null -ne $Receipt.nearest_distance -or
            $null -ne $Receipt.nearest_position) { throw 'Unavailable aim sample incorrectly claims obstruction information.' }
        throw ('Engine aim sample unavailable: ' + $Receipt.reason)
    }
    if (-not $Receipt.obstruction_known -or -not $Receipt.skip_player -or $Receipt.reason -cne 'none' -or
        $Receipt.clear -ne ($Receipt.result -ceq 'no_hit')) { throw 'Aim result and availability flags disagree.' }
    if (-not (Test-MineComeAimNumber $Receipt.mask) -or $Receipt.mask -lt 1 -or
        $Receipt.mask -gt 2147483647 -or $Receipt.mask -ne [Math]::Floor([double]$Receipt.mask)) {
        throw 'Aim receipt physics mask is invalid.'
    }
    foreach ($field in @('engine_time','completed_engine_time')) {
        if (-not (Test-MineComeAimNumber $Receipt.$field) -or $Receipt.$field -lt 0 -or
            $Receipt.$field -gt 1000000000000) { throw 'Aim receipt engine time is invalid.' }
    }
    $elapsed = [double]$Receipt.completed_engine_time - [double]$Receipt.engine_time
    if ($elapsed -lt 0 -or $elapsed -gt 0.25) { throw 'Aim receipt engine interval is reversed or expired.' }
    foreach ($field in @('origin','forward','direction')) { Assert-MineComeAimVector $Receipt.$field }
    $lengthSquared = 0.0
    foreach ($axis in @('x','y','z')) {
        $component = [double]$Receipt.forward.$axis
        $lengthSquared += $component * $component
        if ([Math]::Abs([double]$Receipt.direction.$axis - $component * 4.5) -gt 0.000001) {
            throw 'Aim receipt direction does not match the scaled camera forward vector.'
        }
    }
    if ([Math]::Abs([Math]::Sqrt($lengthSquared) - 1) -gt 0.000001) {
        throw 'Aim receipt camera forward vector is not normalized.'
    }
    if (-not (Test-MineComeAimNumber $Receipt.hit_count) -or $Receipt.hit_count -lt 0 -or
        $Receipt.hit_count -gt 15 -or $Receipt.hit_count -ne [Math]::Floor([double]$Receipt.hit_count)) {
        throw 'Aim receipt hit count is invalid or saturated.'
    }
    if ($Receipt.result -ceq 'no_hit') {
        if ($Receipt.hit_count -ne 0 -or $null -ne $Receipt.nearest_distance -or $null -ne $Receipt.nearest_position) {
            throw 'Clear aim receipt contains hit information.'
        }
        return
    }
    if ($Receipt.hit_count -lt 1 -or -not (Test-MineComeAimNumber $Receipt.nearest_distance) -or
        $Receipt.nearest_distance -lt 0 -or $Receipt.nearest_distance -gt 4.5) {
        throw 'Aim receipt nearest distance is invalid or outside the ray.'
    }
    Assert-MineComeAimVector $Receipt.nearest_position
    $residualSquared = 0.0
    foreach ($axis in @('x','y','z')) {
        $residual = [double]$Receipt.nearest_position.$axis - [double]$Receipt.origin.$axis -
            [double]$Receipt.forward.$axis * [double]$Receipt.nearest_distance
        $residualSquared += $residual * $residual
    }
    if ($residualSquared -gt 0.0001) { throw 'Aim receipt nearest hit is not on its bounded camera ray.' }
}
