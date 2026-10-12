#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared startup validation; native capture independently validates the same list.
function Get-MineComeInputBindings {
    param([string]$Bindings='W,S,A,D,SPACE,LSHIFT')
    if(-not $Bindings -or $Bindings.Length -gt 64) { throw 'Bindings must contain six canonical key names.' }
    $names=$Bindings.Split(',',[StringSplitOptions]::None)
    if($names.Count -ne 6) { throw 'Bindings require forward,back,left,right,jump,sprint in that order.' }
    $unique=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($name in $names) {
        if($name -cnotmatch '^(?:[A-Z]|UP|DOWN|LEFT|RIGHT|SPACE|LSHIFT|RSHIFT|LCTRL|RCTRL)$' -or -not $unique.Add($name)) {
            throw 'Use six distinct uppercase letters, arrows, SPACE, LSHIFT/RSHIFT or LCTRL/RCTRL. F8 is reserved for arming.'
        }
    }
    [pscustomobject]@{Argument=($names -join ',');Forward=$names[0];Back=$names[1];Left=$names[2];Right=$names[3];Jump=$names[4];Sprint=$names[5]}
}
