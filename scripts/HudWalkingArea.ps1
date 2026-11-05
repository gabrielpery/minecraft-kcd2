# Explicit fixed capture area. Larger files never grant wider movement by themselves.
function Get-HudWalkingArea([switch]$WideWalking,[switch]$CorridorWalking,[switch]$ExtensionWalking){
    if([int][bool]$WideWalking+[int][bool]$CorridorWalking+[int][bool]$ExtensionWalking -gt 1){throw 'Wide, corridor and extension walking are separate areas.'}
    if($ExtensionWalking){return [pscustomobject]@{Kind='extension';Columns=17;Rows=9;Points=153;JsonMembers=2048;
        MinX=-4;MaxX=12;MinZ=-4;MaxZ=4;SafeMinX=-3.5;SafeMaxX=11.5;SafeMinZ=-3.5;SafeMaxZ=3.5;MinY=57.9;MaxY=67.5;MinDeltaY=-6.1;MaxDeltaY=3.5}}
    if($CorridorWalking){return [pscustomobject]@{Kind='corridor';Columns=13;Rows=9;Points=117;JsonMembers=2048;
        MinX=-4;MaxX=8;MinZ=-4;MaxZ=4;SafeMinX=-3.5;SafeMaxX=7.5;SafeMinZ=-3.5;SafeMaxZ=3.5;MinY=57.9;MaxY=67.5;MinDeltaY=-6.1;MaxDeltaY=3.5}}
    if($WideWalking){return [pscustomobject]@{Grid=9;Points=81;HalfWidth=4;Radius=4;JsonMembers=2048}}
    return [pscustomobject]@{Grid=5;Points=25;HalfWidth=2;Radius=2;JsonMembers=1024}
}
function Assert-HudWalkingArea($Receipt,[bool]$Expected,[switch]$CorridorWalking,[switch]$ExtensionWalking){
    if([int]$Expected+[int][bool]$CorridorWalking+[int][bool]$ExtensionWalking -gt 1){throw 'Wide, corridor and extension walking are separate areas.'}
    if($Receipt -is [Collections.IDictionary]){
        $present=$Receipt.Contains('walking_area');$value=if($present){$Receipt['walking_area']}else{$null}
    }else{
        $property=$Receipt.PSObject.Properties['walking_area'];$present=$null -ne $property
        $value=if($present){$property.Value}else{$null}
    }
    $selected=$Expected -or $CorridorWalking -or $ExtensionWalking;$marker=if($ExtensionWalking){'extension'}elseif($CorridorWalking){'corridor'}else{'wide'}
    if(($selected -and (-not $present -or $value -isnot [string] -or $value -cne $marker)) -or
        (-not $selected -and $present)){throw 'Walking area does not match the explicitly selected profile.'}
}
