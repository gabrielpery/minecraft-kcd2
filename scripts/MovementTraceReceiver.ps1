#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Pure bounded receiver for terrain/MovementTraceSink.java. No game/process calls.
# File provenance authentication remains the starter/controller's responsibility.
. (Join-Path $PSScriptRoot 'HudWalkingSession.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingArea.ps1')

function Assert-MineComeTraceJsonTree {
    param([System.Text.Json.JsonElement]$Element,[int]$Depth,[ref]$Count,[int]$MaximumMembers=1024)
    $Count.Value++
    if($Depth -gt 12 -or $Count.Value -gt $MaximumMembers) { throw 'JSON depth/member budget exceeded.' }
    if($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($property in $Element.EnumerateObject()) {
            if(-not $names.Add($property.Name)) { throw "Duplicate JSON field: $($property.Name)" }
            Assert-MineComeTraceJsonTree $property.Value ($Depth+1) $Count $MaximumMembers
        }
    } elseif($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach($item in $Element.EnumerateArray()) { Assert-MineComeTraceJsonTree $item ($Depth+1) $Count $MaximumMembers }
    } elseif($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Number) {
        $number=$Element.GetDouble()
        if([double]::IsNaN($number) -or [double]::IsInfinity($number)) { throw 'Nonfinite JSON number.' }
    }
}

function Read-MineComeTraceJson {
    param([string]$Json,[int]$MaximumBytes,[ValidateSet(1024,2048)][int]$MaximumMembers=1024)
    $encoding=[Text.UTF8Encoding]::new($false,$true)
    if([string]::IsNullOrEmpty($Json) -or $encoding.GetByteCount($Json) -gt $MaximumBytes) { throw 'JSON byte bound exceeded or empty JSON.' }
    $options=[System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth=12
    $options.AllowTrailingCommas=$false
    $options.CommentHandling=[System.Text.Json.JsonCommentHandling]::Disallow
    $document=[System.Text.Json.JsonDocument]::Parse($Json,$options)
    try {
        $count=0
        Assert-MineComeTraceJsonTree $document.RootElement 0 ([ref]$count) $MaximumMembers
        return $document
    } catch { $document.Dispose();throw }
}

function Get-MineComeTraceField {
    param([System.Text.Json.JsonElement]$Object,[string]$Name)
    $value=[System.Text.Json.JsonElement]::new()
    if($Object.ValueKind -ne [System.Text.Json.JsonValueKind]::Object -or -not $Object.TryGetProperty($Name,[ref]$value)) { throw "Missing JSON field: $Name" }
    return $value
}

function Assert-MineComeTraceKeys {
    param([System.Text.Json.JsonElement]$Object,[string[]]$Names)
    if($Object.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'Expected JSON object.' }
    $allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($name in $Names) { [void]$allowed.Add($name) }
    $count=0
    foreach($property in $Object.EnumerateObject()) {
        $count++
        if(-not $allowed.Contains($property.Name)) { throw "Unexpected JSON field: $($property.Name)" }
    }
    if($count -ne $Names.Count) { throw 'Incomplete JSON object.' }
}

function Get-MineComeTraceString {
    param([System.Text.Json.JsonElement]$Object,[string]$Name)
    $value=Get-MineComeTraceField $Object $Name
    if($value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) { throw "Expected JSON string: $Name" }
    return $value.GetString()
}

function Get-MineComeTraceNumber {
    param([System.Text.Json.JsonElement]$Object,[string]$Name,[double]$Minimum,[double]$Maximum)
    $value=Get-MineComeTraceField $Object $Name
    if($value.ValueKind -ne [System.Text.Json.JsonValueKind]::Number) { throw "Expected JSON number: $Name" }
    $number=$value.GetDouble()
    if([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt $Minimum -or $number -gt $Maximum) { throw "Numeric bound exceeded: $Name" }
    return $number
}

function Get-MineComeTraceInteger {
    param([System.Text.Json.JsonElement]$Object,[string]$Name,[long]$Minimum,[long]$Maximum)
    $value=Get-MineComeTraceField $Object $Name
    $integer=[long]0
    if($value.ValueKind -ne [System.Text.Json.JsonValueKind]::Number -or -not $value.TryGetInt64([ref]$integer) -or $integer -lt $Minimum -or $integer -gt $Maximum) { throw "Expected bounded JSON integer: $Name" }
    return $integer
}

function Get-MineComeTraceBoolean {
    param([System.Text.Json.JsonElement]$Object,[string]$Name)
    $value=Get-MineComeTraceField $Object $Name
    if($value.ValueKind -ne [System.Text.Json.JsonValueKind]::True -and $value.ValueKind -ne [System.Text.Json.JsonValueKind]::False) { throw "Expected JSON boolean: $Name" }
    return $value.GetBoolean()
}

function Convert-MineComeTraceValue {
    param([System.Text.Json.JsonElement]$Element)
    switch($Element.ValueKind) {
        Object {
            $result=[ordered]@{}
            foreach($property in $Element.EnumerateObject()) { $result[$property.Name]=Convert-MineComeTraceValue $property.Value }
            return [pscustomobject]$result
        }
        Array {
            $result=@(foreach($item in $Element.EnumerateArray()) { Convert-MineComeTraceValue $item })
            return ,$result
        }
        String { return $Element.GetString() }
        Number { $integer=[long]0; if($Element.TryGetInt64([ref]$integer)) { return $integer };return $Element.GetDouble() }
        True { return $true }
        False { return $false }
        Null { return $null }
        default { throw 'Unsupported JSON value.' }
    }
}

function Assert-MineComeTraceClock {
    param($Value)
    if($Value -isnot [byte] -and $Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [uint32] -and $Value -isnot [uint64] -and $Value -isnot [double] -and $Value -isnot [decimal]) { throw 'Clock must be a numeric integer.' }
    if($Value -lt 0 -or $Value -gt [long]::MaxValue -or [double]::IsInfinity([double]$Value) -or [double]::IsNaN([double]$Value) -or $Value -ne [Math]::Floor([double]$Value)) { throw 'Invalid clock.' }
}

function Read-MineComeTraceCorridor([string]$Json,[string]$Hash,[string]$Path,$Corridor){
    # The controller authenticates the capture against the running game. Here
    # independently bind those authenticated bytes to one complete shared grid.
    if($Corridor.Captured -isnot [bool] -or -not $Corridor.Captured -or
        $Corridor.Path -ine $Path -or $Corridor.Hash -cne $Hash){throw 'Corridor differs from the authenticated live capture.'}
    $document=Read-MineComeTraceJson $Json 196608
    try{
        $root=$document.RootElement
        Assert-MineComeTraceKeys $root @('schema','kind','run','tiles')
        [void](Get-MineComeTraceInteger $root 'schema' 1 1)
        if((Get-MineComeTraceString $root 'kind') -cne 'minecome_ground_corridor_v1'){throw 'Invalid corridor manifest kind.'}
        $run=Get-MineComeTraceString $root 'run'
        if($run -cnotmatch '^[0-9a-f]{32}$' -or $run -cne $Corridor.Run){throw 'Corridor capture run differs.'}
        $tiles=Get-MineComeTraceField $root 'tiles'
        if($tiles.ValueKind -ne [System.Text.Json.JsonValueKind]::Array -or $tiles.GetArrayLength() -ne 2 -or @($Corridor.TileHashes).Count -ne 2){throw 'Exactly two captured corridor tiles are required.'}
        $center=$null;$tileIndex=0;$unique=@{}
        foreach($tile in $tiles.EnumerateArray()){
            Assert-MineComeTraceKeys $tile @('sha256','json')
            $tileHash=Get-MineComeTraceString $tile 'sha256';$rawJson=Get-MineComeTraceString $tile 'json'
            $raw=[Text.UTF8Encoding]::new($false,$true).GetBytes($rawJson)
            $actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($raw)).ToLowerInvariant()
            if($tileHash -cnotmatch '^[0-9a-f]{64}$' -or $tileHash -cne $actual -or $tileHash -cne $Corridor.TileHashes[$tileIndex]){throw 'Corridor raw tile hash differs.'}
            $tileDocument=Read-MineComeTraceJson $rawJson 65536 2048
            try{
                $p=$tileDocument.RootElement
                [void](Get-MineComeTraceInteger $p 'schema' 1 1)
                [void](Get-MineComeTraceInteger $p 'grid_size' 9 9);[void](Get-MineComeTraceNumber $p 'spacing' 1 1)
                if((Get-MineComeTraceString $p 'run') -cne $run -or (Get-MineComeTraceString $p 'walking_area') -cne 'wide' -or
                    (Get-MineComeTraceString (Get-MineComeTraceField $p 'provenance') 'kind') -cne 'live_kcd_ground_patch' -or
                    -not (Get-MineComeTraceBoolean $p 'stable_player') -or -not (Get-MineComeTraceBoolean $p 'approximate_heightfield') -or
                    (Get-MineComeTraceBoolean $p 'full_collision_export_verified')){throw 'Corridor tile provenance differs.'}
                [void](Get-MineComeTraceInteger $p 'point_count' 81 81);[void](Get-MineComeTraceInteger $p 'valid_count' 81 81)
                $c=Get-MineComeTraceField $p 'center';Assert-MineComeTraceKeys $c @('x','y','z')
                foreach($axis in @('x','y','z')){[void](Get-MineComeTraceNumber $c $axis -10000000 10000000)}
                $tileCenter=Convert-MineComeTraceValue $c
                if($tileIndex -eq 0){$center=$tileCenter}
                if($tileCenter.x -ne $center.x+4*$tileIndex -or $tileCenter.y -ne $center.y -or $tileCenter.z -ne $center.z){throw 'Corridor tile center moved its shared coordinate anchor.'}
                $points=Get-MineComeTraceField $p 'points'
                if($points.ValueKind -ne [System.Text.Json.JsonValueKind]::Array -or $points.GetArrayLength() -ne 81){throw 'Complete wide tiles are required.'}
                $seen=[Collections.Generic.HashSet[long]]::new()
                foreach($point in $points.EnumerateArray()){
                    $index=Get-MineComeTraceInteger $point 'index' 1 81
                    if(-not $seen.Add($index)){throw 'Repeated corridor point index.'}
                    $col=($index-1)%9+4*$tileIndex;$row=[int][Math]::Floor(($index-1)/9)
                    $x=Get-MineComeTraceNumber $point 'x' -10000000 10000000;$y=Get-MineComeTraceNumber $point 'y' -10000000 10000000
                    [void](Get-MineComeTraceNumber $point 'z' ($center.z-6.05) ($center.z+2.05))
                    if([Math]::Abs($x-($center.x+$col-4)) -gt .0001 -or [Math]::Abs($y-($center.y+$row-4)) -gt .0001 -or
                        -not (Get-MineComeTraceBoolean $point 'valid') -or (Get-MineComeTraceString $point 'result') -cne 'hit'){throw 'Corridor grid coverage is invalid.'}
                    $normalSquared=0.0
                    foreach($axis in @('nx','ny','nz')){$n=Get-MineComeTraceNumber $point $axis -1.01 1.01;$normalSquared+=$n*$n}
                    if([Math]::Abs([Math]::Sqrt($normalSquared)-1) -gt .05 -or (Get-MineComeTraceNumber $point 'nz' -1.01 1.01) -lt .5){throw 'Corridor normal is not a supported surface.'}
                    $sample=Convert-MineComeTraceValue $point;$key="$col,$row"
                    if($unique.ContainsKey($key)){
                        foreach($axis in @('x','y','z','nx','ny','nz')){if([Math]::Abs($sample.$axis-$unique[$key].$axis) -gt .0001){throw 'Corridor tile overlap disagrees.'}}
                    }else{$unique[$key]=$sample}
                }
            }finally{$tileDocument.Dispose()}
            $tileIndex++
        }
        if($unique.Count -ne 117){throw 'Corridor grid has gaps.'}
        for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 13;$col++){
            $z=$unique["$col,$row"].z
            if(($col -lt 12 -and [Math]::Abs($z-$unique["$($col+1),$row"].z) -gt .5) -or
                ($row -lt 8 -and [Math]::Abs($z-$unique["$col,$($row+1)"].z) -gt .5)){throw 'Corridor adjacent height step exceeds0.5m.'}
        }}
        foreach($axis in @('x','y','z')){if($center.$axis -ne $Corridor.Anchor.$axis){throw 'Corridor center differs from its authenticated anchor.'}}
        # Match GroundSurface.groundForFeet(0,0,.3): the player's footprint
        # overlaps these four slabs, and vanilla settles on their highest top.
        $initialGroundY=[double]::NegativeInfinity
        foreach($row in @(3,4)){foreach($col in @(3,4)){
            $height=($unique["$col,$row"].z+$unique["$($col+1),$row"].z+
                $unique["$col,$($row+1)"].z+$unique["$($col+1),$($row+1)"].z)/4
            $initialGroundY=[Math]::Max($initialGroundY,64+$height-$center.z)
        }}
        return [pscustomobject]@{Run=$run;Center=$center;InitialGroundY=$initialGroundY}
    }finally{$document.Dispose()}
}

function New-MineComeTraceReceiver {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PatchFile,[Parameter(Mandatory)]$MinimumUtcMs,[string]$ExpectedHudSave,[switch]$PhysicalMovement,[switch]$BufferedPhysicalMovement,[switch]$ExtendedWalking,[switch]$WideWalking,[switch]$ScriptedHudCoupled,[switch]$CorridorWalking,$Corridor,[switch]$CorridorWalkOnly)
    if($CorridorWalkOnly -and (-not $CorridorWalking -or $PhysicalMovement)){throw 'Walk-only corridor requires the explicit scripted corridor profile.'}
    if($CorridorWalking -and ($WideWalking -or $ScriptedHudCoupled -or -not $ExpectedHudSave -or $null -eq $Corridor -or
        ($PhysicalMovement -and (-not $BufferedPhysicalMovement -or -not $ExtendedWalking)) -or
        (-not $PhysicalMovement -and ($BufferedPhysicalMovement -or $ExtendedWalking)))){throw 'Corridor requires exclusive scripted or extended buffered physical HUD movement and authenticated capture.'}
    if(-not $CorridorWalking -and $null -ne $Corridor){throw 'Corridor capture requires the explicit corridor profile.'}
    if($ScriptedHudCoupled -and ($PhysicalMovement -or -not $ExpectedHudSave)){throw 'Scripted coupled movement requires an exact HUD save without physical input mode.'}
    if($WideWalking -and -not ($PhysicalMovement -or $ScriptedHudCoupled)){throw 'Wide walking requires explicit physical or scripted coupled HUD movement.'}
    $area=Get-HudWalkingArea -WideWalking:$WideWalking -CorridorWalking:$CorridorWalking
    Assert-MineComeTraceClock $MinimumUtcMs
    if($BufferedPhysicalMovement -and -not $PhysicalMovement){throw 'Buffered playback requires the physical movement profile.'}
    if($ExtendedWalking -and -not $BufferedPhysicalMovement){throw 'Extended walking requires explicit buffered physical movement.'}
    if($PhysicalMovement -and -not $ExpectedHudSave){throw 'Physical movement trace requires one exact HUD save.'}
    if($PSBoundParameters.ContainsKey('ExpectedHudSave')) {
        $saveWorld=[Guid]::Empty
        if($ExpectedHudSave -cnotmatch '^MineCome-HudStream-(.+)$' -or
            -not [Guid]::TryParseExact($Matches[1],'D',[ref]$saveWorld) -or
            $ExpectedHudSave -cne ('MineCome-HudStream-'+$saveWorld.ToString('D'))) {
            throw 'HUD trace profile requires one exact canonical readiness save.'
        }
    }
    $path=(Resolve-Path -LiteralPath $PatchFile -ErrorAction Stop).Path
    $stream=[IO.File]::OpenRead($path)
    try {
        $maximumBytes=if($CorridorWalking){196608}else{65536}
        if($stream.Length -gt $maximumBytes -or $stream.Length -lt 1) { throw 'Ground patch byte bound exceeded.' }
        $bytes=[byte[]]::new([int]$stream.Length);$offset=0
        while($offset -lt $bytes.Length) { $n=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($n -eq 0) { throw 'Ground patch was truncated.' };$offset+=$n }
        $hasher=[Security.Cryptography.SHA256]::Create()
        try { $hash=[BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
        finally { $hasher.Dispose() }
    } finally { $stream.Dispose() }
    $currentHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($hash -cne $currentHash) { throw 'Ground patch changed while reading.' }
    $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
    $initialGroundY=64.0
    if($CorridorWalking){
        $surface=Read-MineComeTraceCorridor $json $hash $path $Corridor
        $run=$surface.Run;$center=$surface.Center;$initialGroundY=$surface.InitialGroundY
    }else{
    $document=Read-MineComeTraceJson $json 65536 $area.JsonMembers
    try {
        $root=$document.RootElement
        if((Get-MineComeTraceInteger $root 'schema' 1 1) -ne 1 -or (Get-MineComeTraceInteger $root 'grid_size' $area.Grid $area.Grid) -ne $area.Grid -or (Get-MineComeTraceNumber $root 'spacing' 1 1) -ne 1) { throw 'Invalid patch grid.' }
        Assert-HudWalkingArea (Convert-MineComeTraceValue $root) ([bool]$WideWalking)
        $run=Get-MineComeTraceString $root 'run'
        if($run -cnotmatch '^[A-Za-z0-9_-]{1,128}$') { throw 'Invalid patch run.' }
        $provenance=Get-MineComeTraceField $root 'provenance'
        if((Get-MineComeTraceString $provenance 'kind') -cne 'live_kcd_ground_patch') { throw 'Receiver requires a labelled live ground patch; authentication belongs to starter.' }
        if(-not (Get-MineComeTraceBoolean $root 'stable_player') -or -not (Get-MineComeTraceBoolean $root 'approximate_heightfield') -or (Get-MineComeTraceBoolean $root 'full_collision_export_verified')) { throw 'Unsupported patch verification flags.' }
        [void](Get-MineComeTraceInteger $root 'point_count' $area.Points $area.Points)
        [void](Get-MineComeTraceInteger $root 'valid_count' $area.Points $area.Points)
        $centerElement=Get-MineComeTraceField $root 'center'
        Assert-MineComeTraceKeys $centerElement @('x','y','z')
        $center=[pscustomobject]@{x=(Get-MineComeTraceNumber $centerElement 'x' -10000000 10000000);y=(Get-MineComeTraceNumber $centerElement 'y' -10000000 10000000);z=(Get-MineComeTraceNumber $centerElement 'z' -10000000 10000000)}
        $points=Get-MineComeTraceField $root 'points'
        if($points.ValueKind -ne [System.Text.Json.JsonValueKind]::Array -or $points.GetArrayLength() -ne $area.Points) { throw 'Complete selected patch required.' }
        $indices=[Collections.Generic.HashSet[long]]::new()
        foreach($point in $points.EnumerateArray()) {
            $index=Get-MineComeTraceInteger $point 'index' 1 $area.Points
            if(-not $indices.Add($index)) { throw 'Duplicate patch point.' }
            $x=Get-MineComeTraceNumber $point 'x' -10000000 10000000
            $y=Get-MineComeTraceNumber $point 'y' -10000000 10000000
            [void](Get-MineComeTraceNumber $point 'z' ($center.z-6.05) ($center.z+2.05))
            if([Math]::Abs($x-($center.x+(($index-1)%$area.Grid)-$area.HalfWidth)) -gt 0.0001 -or [Math]::Abs($y-($center.y+[Math]::Floor(($index-1)/$area.Grid)-$area.HalfWidth)) -gt 0.0001 -or -not (Get-MineComeTraceBoolean $point 'valid') -or (Get-MineComeTraceString $point 'result') -cne 'hit') { throw 'Invalid patch coverage.' }
            foreach($axis in @('nx','ny','nz')) { [void](Get-MineComeTraceNumber $point $axis -1.01 1.01) }
        }
    } finally { $document.Dispose() }
    }
    return [pscustomobject]@{ExpectedRun=$run;PatchHash=$hash;Center=$center;InitialGroundY=$initialGroundY;ExpectedHudSave=$ExpectedHudSave;PhysicalMovement=[bool]$PhysicalMovement;BufferedPhysicalMovement=[bool]$BufferedPhysicalMovement;ExtendedWalking=[bool]$ExtendedWalking;WideWalking=[bool]$WideWalking;ScriptedHudCoupled=[bool]$ScriptedHudCoupled;CorridorWalking=[bool]$CorridorWalking;CorridorWalkOnly=[bool]$CorridorWalkOnly;Corridor=$Corridor;StartedMonotonicNs=[long]0;Anchor=[pscustomobject]@{x=0.0;y=64.0;z=0.0};AnchorVerified=$false;MinimumUtcMs=[long]$MinimumUtcMs;LastSeq=[long]0;LastServerSeq=[long]0;LastFreshPassedSeq=[long]0;LastPassedUtcMs=[long]0;LastPassedServerAgeMs=[double]0;World=$null;Save=$null;Begun=$false;Ended=$false;GroundProved=$false;Bytes=0;Records=0}
}

function Receive-MineComeMovementTrace {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$JsonLine,[Parameter(Mandatory)]$NowUtcMs)
    Assert-MineComeTraceClock $NowUtcMs
    if($State.Ended) { throw 'Trace already ended; appends/replay rejected.' }
    $corridor=$State.PSObject.Properties['CorridorWalking'] -and $State.CorridorWalking
    $physicalCorridor=$corridor -and $State.PhysicalMovement
    $walkOnly=$corridor -and $State.CorridorWalkOnly
    $extent=if($State.WideWalking){4}else{2}
    $minX=if($corridor){-3.5}else{-$extent};$maxX=if($corridor){7.5}else{$extent}
    $minZ=if($corridor){-3.5}else{-$extent};$maxZ=if($corridor){3.5}else{$extent}
    $minY=if($corridor){57.9}else{52};$maxY=if($corridor){67.5}else{76}
    if($JsonLine.IndexOfAny([char[]]@("`r","`n")) -ge 0) { throw 'Receiver accepts one complete NDJSON record without separators.' }
    $lineBytes=[Text.UTF8Encoding]::new($false,$true).GetByteCount($JsonLine)
    $session=Get-HudWalkingSession -ExtendedWalking:$State.ExtendedWalking
    $maxBytes=if($corridor){262144}else{$session.TraceBytes};$maxRecords=if($corridor -and -not $physicalCorridor){256}else{200}
    if($lineBytes -lt 1 -or $lineBytes -gt 4096 -or $State.Bytes+$lineBytes+1 -gt $maxBytes -or $State.Records -ge $maxRecords) { throw 'Trace line/stream budget exceeded.' }
    $document=Read-MineComeTraceJson $JsonLine 4096
    try {
        $root=$document.RootElement
        $kind=Get-MineComeTraceString $root 'kind'
        $base=@('schema','kind','run','patch_sha256','source_kind','save','world','seq','utc_ms','phase')
        if($corridor){
            $base+='walking_area'
            if((Get-MineComeTraceString $root 'walking_area') -cne 'corridor'){throw 'Corridor walking trace marker mismatch.'}
        }elseif($State.WideWalking){
            $base+='walking_area'
            if((Get-MineComeTraceString $root 'walking_area') -cne 'wide'){throw 'Wide walking trace marker mismatch.'}
        }
        switch -CaseSensitive ($kind) {
            begin { $keys=$base+@('started_monotonic_ns','center','anchor_mc','approximate_heightfield','full_collision_export_verified') }
            sample { $keys=$base+@('monotonic_ns','server_seq','server_age_ns','client','server') }
            end { $keys=$base+@('result','reason','last_server_seq') }
            default { throw 'Invalid trace record kind.' }
        }
        Assert-MineComeTraceKeys $root $keys
        [void](Get-MineComeTraceInteger $root 'schema' 1 1)
        $sourceKind=if($physicalCorridor){'live_kcd_hud_physical_movement_corridor'}elseif($walkOnly){'hud_corridor_walk_coupled'}elseif($corridor){'hud_corridor_coupled'}elseif($State.PhysicalMovement){$session.SourceKind}else{'live_kcd_ground_patch'}
        if((Get-MineComeTraceString $root 'run') -cne $State.ExpectedRun -or (Get-MineComeTraceString $root 'patch_sha256') -cne $State.PatchHash -or (Get-MineComeTraceString $root 'source_kind') -cne $sourceKind) { throw 'Trace patch/run/source identity mismatch.' }
        $world=Get-MineComeTraceString $root 'world';$save=Get-MineComeTraceString $root 'save';$uuid=[Guid]::Empty
        $expectedSave=if($State.ExpectedHudSave){$State.ExpectedHudSave}else{'MineCome-Ground-'+$world}
        $prefix=if($State.ExpectedHudSave){'MineCome-HudStream-'}else{'MineCome-Ground-'}
        if(-not [Guid]::TryParseExact($world,'D',[ref]$uuid) -or $world -cne $uuid.ToString('D') -or
            $save -cne $expectedSave -or $save -cne ($prefix+$world)) { throw 'Invalid canonical world/save identity.' }
        if($State.Begun -and ($world -cne $State.World -or $save -cne $State.Save)) { throw 'Trace world/save changed.' }
        $seq=Get-MineComeTraceInteger $root 'seq' 1 $maxRecords
        if($seq -ne $State.LastSeq+1 -or ($seq -eq $maxRecords -and $kind -cne 'end')) { throw 'Noncontiguous trace sequence or missing end slot.' }
        $utc=Get-MineComeTraceInteger $root 'utc_ms' $State.MinimumUtcMs ([long]::MaxValue)
        if($utc -gt $NowUtcMs -and $utc-$NowUtcMs -gt 50) { throw 'Trace timestamp is too far in the future.' }
        $phase=Get-MineComeTraceString $root 'phase'
        $phases=@('SETTLING','WALKING','RESTING','JUMPING','LANDING','PASSED','FAILED','STOPPED')
        if($corridor -and -not $physicalCorridor){$phases+=@('RETURNING','RETURN_REST')}
        if($walkOnly){$phases=@($phases | Where-Object {$_ -cnotin @('JUMPING','LANDING')})}
        if($phase -cnotin $phases) { throw 'Invalid trace phase.' }
        $returnKind=$kind;$target=$null;$serverSeq=$State.LastServerSeq;$groundProved=$State.GroundProved
        $freshPassedSeq=[long]0;$passedUtc=[long]0;$passedServerAgeMs=[double]0
        $anchorValue=$State.Anchor;$anchorVerified=$State.AnchorVerified
        $startMonotonic=[long]0
        if($kind -ceq 'begin') {
            if($State.Begun -or $seq -ne 1 -or $phase -cne 'SETTLING') { throw 'Begin must be first and SETTLING.' }
            $startMonotonic=Get-MineComeTraceInteger $root 'started_monotonic_ns' ([long]::MinValue) ([long]::MaxValue)
            if(-not (Get-MineComeTraceBoolean $root 'approximate_heightfield') -or (Get-MineComeTraceBoolean $root 'full_collision_export_verified')) { throw 'Invalid begin approximation flags.' }
            foreach($name in @('center','anchor_mc')) { Assert-MineComeTraceKeys (Get-MineComeTraceField $root $name) @('x','y','z') }
            $center=Get-MineComeTraceField $root 'center';$anchor=Get-MineComeTraceField $root 'anchor_mc'
            foreach($axis in @('x','y','z')) {
                if((Get-MineComeTraceNumber $center $axis -10000000 10000000) -ne $State.Center.$axis) { throw 'Begin center differs from captured patch.' }
                $expected=if($axis -ceq 'y'){64}else{0}
                if($State.PhysicalMovement){
                    $low=if($axis -ceq 'y'){$minY}else{-0.01};$high=if($axis -ceq 'y'){$maxY}else{0.01}
                    [void](Get-MineComeTraceNumber $anchor $axis $low $high)
                }else{[void](Get-MineComeTraceNumber $anchor $axis $expected $expected)}
            }
            $anchorValue=Convert-MineComeTraceValue $anchor
        } elseif($kind -ceq 'sample') {
            if(-not $State.Begun) { throw 'Sample precedes begin.' }
            $monotonic=Get-MineComeTraceInteger $root 'monotonic_ns' ([long]::MinValue) ([long]::MaxValue)
            if($corridor -and -not $physicalCorridor){
                $elapsed=[decimal]$monotonic-[decimal]$State.StartedMonotonicNs
                if($elapsed -lt 0 -or $elapsed -gt 20000000000L){throw 'Corridor source exceeded its20-second interval.'}
            }
            $serverAgeMs=(Get-MineComeTraceInteger $root 'server_age_ns' 0 250000000)/1000000.0
            $serverSeq=Get-MineComeTraceInteger $root 'server_seq' 1 1000000
            if($serverSeq -le $State.LastServerSeq) { throw 'Server sequence did not advance.' }
            foreach($name in @('client','server')) {
                $motion=Get-MineComeTraceField $root $name
                Assert-MineComeTraceKeys $motion @('x','y','z','vx','vy','vz','on_ground','proxy_support')
                [void](Get-MineComeTraceNumber $motion 'x' $minX $maxX);[void](Get-MineComeTraceNumber $motion 'z' $minZ $maxZ)
                [void](Get-MineComeTraceNumber $motion 'y' $minY $maxY)
                if($physicalCorridor){
                    # Capture coordinates stay tied to tile0; the physical
                    # transform also preserves its actual settled spawn height.
                    # Both bounds apply, so a tiny nonzero anchor cannot expand
                    # the native rectangle at an edge.
                    $dx=(Get-MineComeTraceNumber $motion 'x' $minX $maxX)-$State.Anchor.x
                    $dz=(Get-MineComeTraceNumber $motion 'z' $minZ $maxZ)-$State.Anchor.z
                    $dy=(Get-MineComeTraceNumber $motion 'y' $minY $maxY)-$State.Anchor.y
                    if($dx -lt -3.5 -or $dx -gt 7.5 -or $dz -lt -3.5 -or $dz -gt 3.5 -or $dy -lt -6.1 -or $dy -gt 3.5){throw 'Physical corridor displacement leaves the fixed native bounds.'}
                }
                foreach($axis in @('vx','vy','vz')) { [void](Get-MineComeTraceNumber $motion $axis -4 4) }
                [void](Get-MineComeTraceBoolean $motion 'on_ground');[void](Get-MineComeTraceBoolean $motion 'proxy_support')
            }
            $server=Get-MineComeTraceField $root 'server'
            $grounded=(Get-MineComeTraceBoolean $server 'on_ground') -and (Get-MineComeTraceBoolean $server 'proxy_support')
            if($State.PhysicalMovement -and -not $anchorVerified){
                if($phase -cne 'SETTLING' -or -not $grounded){throw 'Physical movement must first report its grounded initial anchor.'}
                foreach($axis in @('x','y','z')){
                    if([Math]::Abs((Get-MineComeTraceNumber $server $axis -100 100)-$State.Anchor.$axis) -gt 0.01){throw 'Physical movement initial sample differs from its anchor.'}
                }
                $anchorVerified=$true
            }
            $active=$false
            if($phase -cin @('WALKING','RESTING') -and $grounded) { $active=$true;$groundProved=$true }
            elseif($phase -cin @('JUMPING','LANDING') -and $groundProved) { $active=$true }
            elseif($corridor -and -not $physicalCorridor -and $phase -cin @('RETURNING','RETURN_REST') -and $groundProved -and $grounded){$active=$true}
            elseif($State.BufferedPhysicalMovement -and $grounded -and
                (($phase -ceq 'SETTLING' -and -not $State.AnchorVerified) -or ($phase -ceq 'PASSED' -and $groundProved))) {
                # Playback needs the actual initial anchor and terminal source
                # point. Legacy followers continue to observe these phases only.
                $active=$true
                # The already-verified grounded anchor is ground provenance,
                # even when the first real step immediately leaves a slab edge.
                # Waiting for a later WALKING/RESTING point would drop that
                # legitimate airborne waypoint from the immutable timeline.
                # The freshness check below still rolls this proof back on stale data.
                if($phase -ceq 'SETTLING'){$groundProved=$true}
            }
            $observationAgeMs=[Math]::Max([long]0,[long]$NowUtcMs-$utc)+$serverAgeMs
            if($observationAgeMs -gt 300) { $returnKind='stale';$groundProved=$State.GroundProved }
            elseif(-not $active) { $returnKind='observe' }
            else {
                $target=[pscustomobject]@{x=$State.Center.x+(Get-MineComeTraceNumber $server 'x' $minX $maxX)-$State.Anchor.x;y=$State.Center.y-(Get-MineComeTraceNumber $server 'z' $minZ $maxZ)+$State.Anchor.z;z=$State.Center.z+(Get-MineComeTraceNumber $server 'y' $minY $maxY)-$State.Anchor.y}
                # Physical walking follows sampled slopes in either direction;
                # the explicitly selected sphere bounds every submitted target.
                if($State.PhysicalMovement -and -not $physicalCorridor -and (($target.x-$State.Center.x)*($target.x-$State.Center.x)+($target.y-$State.Center.y)*($target.y-$State.Center.y)+($target.z-$State.Center.z)*($target.z-$State.Center.z) -gt ($extent*$extent) -or $target.z-$State.Center.z -lt -1.5 -or $target.z-$State.Center.z -gt 1.5)){throw 'Physical movement target exceeds the physical follower bounds.'}
            }
            if($phase -ceq 'PASSED' -and $returnKind -cne 'stale' -and $groundProved -and $grounded) {
                $freshPassedSeq=$seq;$passedUtc=$utc;$passedServerAgeMs=$serverAgeMs
            }
        } else {
            if(-not $State.Begun) { throw 'End precedes begin.' }
            $result=Get-MineComeTraceString $root 'result'
            if($result -cnotin @('passed','failed','stopped')) { throw 'Invalid trace end result.' }
            if($result -ceq 'passed' -and ($phase -cne 'PASSED' -or $State.LastFreshPassedSeq -ne $State.LastSeq -or $State.LastFreshPassedSeq -eq 0 -or [Math]::Max([long]0,[long]$NowUtcMs-$State.LastPassedUtcMs)+$State.LastPassedServerAgeMs -gt 300)) {
                throw 'Passed end requires the immediately preceding fresh grounded PASSED sample.'
            }
            $reason=Get-MineComeTraceString $root 'reason';$characters=0
            for($i=0;$i -lt $reason.Length;$i++) { $characters++;if([char]::IsHighSurrogate($reason[$i]) -and $i+1 -lt $reason.Length -and [char]::IsLowSurrogate($reason[$i+1])) { $i++ } }
            if($characters -gt 160) { throw 'Trace termination reason exceeds160 codepoints.' }
            if((Get-MineComeTraceInteger $root 'last_server_seq' 0 1000000) -ne $State.LastServerSeq) { throw 'End server sequence mismatch.' }
        }
        $record=Convert-MineComeTraceValue $root
        # Commit only after every parse/identity/bounds check succeeded.
        $State.LastSeq=$seq;$State.LastServerSeq=$serverSeq;$State.Bytes+=$lineBytes+1;$State.Records++
        if($kind -ceq 'begin') { $State.Begun=$true;$State.World=$world;$State.Save=$save;if($corridor){$State.StartedMonotonicNs=$startMonotonic} }
        $State.GroundProved=$groundProved
        $State.Anchor=$anchorValue;$State.AnchorVerified=$anchorVerified
        $State.LastFreshPassedSeq=$freshPassedSeq;$State.LastPassedUtcMs=$passedUtc;$State.LastPassedServerAgeMs=$passedServerAgeMs
        if($kind -ceq 'end') { $State.Ended=$true }
        $answer=[pscustomobject]@{Kind=$returnKind;Record=$record}
        if($returnKind -ceq 'sample') { $answer | Add-Member -NotePropertyName Target -NotePropertyValue $target }
        return $answer
    } finally { $document.Dispose() }
}
