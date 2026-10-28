# Explicit fixed capture area. Larger files never grant wider movement by themselves.
function Get-HudWalkingArea([switch]$WideWalking){
    if($WideWalking){return [pscustomobject]@{Grid=9;Points=81;HalfWidth=4;Radius=4;JsonMembers=2048}}
    return [pscustomobject]@{Grid=5;Points=25;HalfWidth=2;Radius=2;JsonMembers=1024}
}
function Assert-HudWalkingArea($Receipt,[bool]$Expected){
    if($Receipt -is [Collections.IDictionary]){
        $present=$Receipt.Contains('walking_area');$value=if($present){$Receipt['walking_area']}else{$null}
    }else{
        $property=$Receipt.PSObject.Properties['walking_area'];$present=$null -ne $property
        $value=if($present){$property.Value}else{$null}
    }
    if(($Expected -and (-not $present -or $value -isnot [string] -or $value -cne 'wide')) -or
        (-not $Expected -and $present)){throw 'Walking area does not match the explicitly selected profile.'}
}
