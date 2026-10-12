#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Offline recording validator only. No game/process calls or follower authorization.
. (Join-Path $PSScriptRoot 'MovementTraceReceiver.ps1')

function Read-MineComePoseEvidenceFile {
    param([string]$Path,[int]$MaximumBytes)
    $resolved=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $stream=[IO.File]::OpenRead($resolved)
    try {
        if($stream.Length -lt 1 -or $stream.Length -gt $MaximumBytes) { throw 'Evidence file byte bound exceeded.' }
        $bytes=[byte[]]::new([int]$stream.Length);$offset=0
        while($offset -lt $bytes.Length) {
            $n=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if($n -eq 0) { throw 'Evidence file truncated while reading.' }
            $offset+=$n
        }
        if($stream.ReadByte() -ne -1 -or $stream.Length -ne $bytes.Length) { throw 'Evidence file changed while reading.' }
        $hasher=[Security.Cryptography.SHA256]::Create()
        try { $hash=[BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
        finally { $hasher.Dispose() }
        $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        if($text.StartsWith([char]0xfeff)) { throw 'Evidence UTF8 BOM is unsupported.' }
        return [pscustomobject]@{Path=$resolved;Sha256=$hash;Text=$text;Bytes=$bytes.Length}
    } finally { $stream.Dispose() }
}

function Get-MineComePoseEvidenceU64 {
    param([System.Text.Json.JsonElement]$Object,[string]$Name,[bool]$AllowZero=$false)
    $text=Get-MineComeTraceString $Object $Name
    $pattern=if($AllowZero){'^(?:0|[1-9][0-9]{0,19})$'}else{'^[1-9][0-9]{0,19}$'}
    if($text -cnotmatch $pattern) { throw "Noncanonical unsigned64 token: $Name" }
    $number=[Numerics.BigInteger]::Parse($text,[Globalization.CultureInfo]::InvariantCulture)
    if($number -gt [Numerics.BigInteger]::Parse('18446744073709551615')) { throw "Unsigned64 bound exceeded: $Name" }
    return [pscustomobject]@{Text=$text;Number=$number}
}

function Get-MineComePoseEvidenceVector {
    param([System.Text.Json.JsonElement]$Object,[string]$Name,[double]$Minimum,[double]$Maximum)
    $vector=Get-MineComeTraceField $Object $Name
    Assert-MineComeTraceKeys $vector @('x','y','z')
    return [pscustomobject]@{x=(Get-MineComeTraceNumber $vector 'x' $Minimum $Maximum);y=(Get-MineComeTraceNumber $vector 'y' $Minimum $Maximum);z=(Get-MineComeTraceNumber $vector 'z' $Minimum $Maximum)}
}

function Assert-MineComePoseEvidenceClose {
    param([double]$Actual,[double]$Expected,[double]$Tolerance=0.0000001)
    if(-not [double]::IsFinite($Actual) -or -not [double]::IsFinite($Expected) -or [Math]::Abs($Actual-$Expected) -gt $Tolerance) { throw 'Stored coordinate/view mapping does not match patch space.' }
}

function Get-MineComePoseEvidenceMotion {
    param([System.Text.Json.JsonElement]$Object,[string]$Name)
    $motion=Get-MineComeTraceField $Object $Name
    Assert-MineComeTraceKeys $motion @('x','y','z','vx','vy','vz','on_ground','proxy_support','yaw','pitch')
    $yaw=Get-MineComeTraceNumber $motion 'yaw' -180 180
    if($yaw -ge 180) { throw 'Yaw must be wrapped to [-180,180).' }
    return [pscustomobject]@{
        x=(Get-MineComeTraceNumber $motion 'x' -2 2);y=(Get-MineComeTraceNumber $motion 'y' 52 76);z=(Get-MineComeTraceNumber $motion 'z' -2 2)
        vx=(Get-MineComeTraceNumber $motion 'vx' -4 4);vy=(Get-MineComeTraceNumber $motion 'vy' -4 4);vz=(Get-MineComeTraceNumber $motion 'vz' -4 4)
        on_ground=(Get-MineComeTraceBoolean $motion 'on_ground');proxy_support=(Get-MineComeTraceBoolean $motion 'proxy_support')
        yaw=$yaw;pitch=(Get-MineComeTraceNumber $motion 'pitch' -90 90)
    }
}

function Test-MineComeExternalInputPoseEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$InputRun,
        [Parameter(Mandatory)][long]$TargetPid,
        [Parameter(Mandatory)][string]$TargetStartFiletime,
        [Parameter(Mandatory)][string]$PatchFile,
        [Parameter(Mandatory)][string]$ViewSeedFile,
        [Parameter(Mandatory)][bool]$Fixture
    )
    if($InputRun -cnotmatch '^[0-9a-f]{32}$' -or $TargetPid -lt 1 -or $TargetPid -gt 4294967295 -or $TargetStartFiletime -cnotmatch '^[1-9][0-9]{0,19}$' -or
        [Numerics.BigInteger]::Parse($TargetStartFiletime) -gt [Numerics.BigInteger]::Parse('18446744073709551615')) { throw 'Invalid expected input/process identity.' }
    $patch=Read-MineComePoseEvidenceFile $PatchFile 65536
    $patchDocument=Read-MineComeTraceJson $patch.Text 65536
    try {
        $root=$patchDocument.RootElement
        [void](Get-MineComeTraceInteger $root 'schema' 1 1)
        [void](Get-MineComeTraceInteger $root 'grid_size' 5 5)
        [void](Get-MineComeTraceNumber $root 'spacing' 1 1)
        [void](Get-MineComeTraceInteger $root 'point_count' 25 25)
        [void](Get-MineComeTraceInteger $root 'valid_count' 25 25)
        if(-not (Get-MineComeTraceBoolean $root 'stable_player') -or -not (Get-MineComeTraceBoolean $root 'approximate_heightfield') -or (Get-MineComeTraceBoolean $root 'full_collision_export_verified')) { throw 'Unsupported ground-patch flags.' }
        $patchRun=Get-MineComeTraceString $root 'run'
        if($patchRun -cnotmatch '^[A-Za-z0-9_-]{1,128}$') { throw 'Invalid patch run.' }
        $groundKind=Get-MineComeTraceString (Get-MineComeTraceField $root 'provenance') 'kind'
        if($groundKind -cnotin @('standalone_fixture','live_kcd_ground_patch') -or (-not $Fixture -and $groundKind -cne 'live_kcd_ground_patch')) { throw 'Ground source/fixture mismatch.' }
        $center=Get-MineComePoseEvidenceVector $root 'center' -10000000 10000000
        $points=Get-MineComeTraceField $root 'points'
        if($points.ValueKind -ne [System.Text.Json.JsonValueKind]::Array -or $points.GetArrayLength() -ne 25) { throw 'Complete25-point patch required.' }
        $indices=[Collections.Generic.HashSet[long]]::new()
        foreach($point in $points.EnumerateArray()) {
            $index=Get-MineComeTraceInteger $point 'index' 1 25
            if(-not $indices.Add($index) -or -not (Get-MineComeTraceBoolean $point 'valid') -or (Get-MineComeTraceString $point 'result') -cne 'hit') { throw 'Invalid patch point identity/result.' }
            $x=Get-MineComeTraceNumber $point 'x' -10000000 10000000
            $y=Get-MineComeTraceNumber $point 'y' -10000000 10000000
            Assert-MineComePoseEvidenceClose $x ($center.x+(($index-1)%5)-2) -Tolerance 0.0001
            Assert-MineComePoseEvidenceClose $y ($center.y+[Math]::Floor(($index-1)/5)-2) -Tolerance 0.0001
            [void](Get-MineComeTraceNumber $point 'z' ($center.z-8) ($center.z+8))
            foreach($axis in @('nx','ny','nz')) { [void](Get-MineComeTraceNumber $point $axis -1.01 1.01) }
        }
    } finally { $patchDocument.Dispose() }
    $view=Read-MineComePoseEvidenceFile $ViewSeedFile 4096
    $viewDocument=Read-MineComeTraceJson $view.Text 4096
    try {
        $root=$viewDocument.RootElement
        Assert-MineComeTraceKeys $root @('schema','run','source_kind','patch_sha256','target_pid','target_start_filetime','captured_utc_ms','player','forward','up')
        [void](Get-MineComeTraceInteger $root 'schema' 1 1)
        [void](Get-MineComeTraceInteger $root 'captured_utc_ms' 1 ([long]::MaxValue))
        $expectedViewKind=if($Fixture){'standalone_fixture'}else{'live_kcd_view_seed'}
        if((Get-MineComeTraceString $root 'run') -cne $InputRun -or (Get-MineComeTraceString $root 'source_kind') -cne $expectedViewKind -or
            (Get-MineComeTraceString $root 'patch_sha256') -cne $patch.Sha256 -or (Get-MineComeTraceInteger $root 'target_pid' 1 4294967295) -ne $TargetPid -or
            (Get-MineComePoseEvidenceU64 $root 'target_start_filetime').Text -cne $TargetStartFiletime) { throw 'Expected view seed identity/hash mismatch.' }
        $viewPlayer=Get-MineComePoseEvidenceVector $root 'player' -10000000 10000000
        if([Math]::Sqrt([Math]::Pow($viewPlayer.x-$center.x,2)+[Math]::Pow($viewPlayer.y-$center.y,2)+[Math]::Pow($viewPlayer.z-$center.z,2)) -gt 0.1) { throw 'View seed differs from ground origin.' }
        $forward=Get-MineComePoseEvidenceVector $root 'forward' -1.01 1.01
        $up=Get-MineComePoseEvidenceVector $root 'up' -1.01 1.01
        # Match HostViewSeed: normalized orthogonality and projected world+Z roll.
        $forwardLength=[Math]::Sqrt($forward.x*$forward.x+$forward.y*$forward.y+$forward.z*$forward.z)
        $upLength=[Math]::Sqrt($up.x*$up.x+$up.y*$up.y+$up.z*$up.z)
        if($forwardLength -lt 0.99 -or $forwardLength -gt 1.01 -or $upLength -lt 0.99 -or $upLength -gt 1.01) { throw 'View seed forward/up must be unit vectors within0.01.' }
        $fx=$forward.x/$forwardLength;$fy=$forward.y/$forwardLength;$fz=$forward.z/$forwardLength
        $ux=$up.x/$upLength;$uy=$up.y/$upLength;$uz=$up.z/$upLength
        if([Math]::Abs($fx*$ux+$fy*$uy+$fz*$uz) -gt 0.01) { throw 'View seed forward/up are not orthogonal.' }
        if([Math]::Sqrt($fx*$fx+$fy*$fy) -lt 0.01) { throw 'Near-vertical view seed unsupported.' }
        $px=-$fx*$fz;$py=-$fy*$fz;$pz=1-$fz*$fz
        $projectedLength=[Math]::Sqrt($px*$px+$py*$py+$pz*$pz)
        $upDot=[Math]::Max(-1.0,[Math]::Min(1.0,($ux*$px+$uy*$py+$uz*$pz)/$projectedLength))
        if($upDot -lt [Math]::Cos([Math]::PI/180)) { throw 'View seed camera roll exceeds1degree.' }
    } finally { $viewDocument.Dispose() }
    $file=Read-MineComePoseEvidenceFile $Path 1048576
    if(-not $file.Text.EndsWith("`n")) { throw 'Pose recording must end with a complete LF record.' }
    $lines=$file.Text.Split("`n",[StringSplitOptions]::None)
    $recordCount=$lines.Count-1
    if($recordCount -lt 3 -or $recordCount -gt 512) { throw 'Pose recording requires3..512 records.' }
    $common=@('schema','kind','source_kind','audit_only','follower_eligible','control_ownership_verified','kcd_movement_applied','coordinate_space','run','target_pid','target_start_filetime','patch_run','patch_sha256','view_seed_sha256','ground_source_kind','fixture','save','world','seq','utc_ms')
    $lastSeq=[long]0;$lastServer=[long]0;$lastUtc=[long]0;$watermark=[Numerics.BigInteger]::Zero
    $begun=$false;$ended=$false;$world=$null;$save=$null;$samples=0;$first=$null;$last=$null;$previousKind=$null
    for($index=0;$index -lt $recordCount;$index++) {
        $line=$lines[$index]
        if([Text.UTF8Encoding]::new($false,$true).GetByteCount($line)+1 -gt 4096) { throw 'Pose record exceeds4096bytes including LF.' }
        if($line.EndsWith("`r")) { $line=$line.Substring(0,$line.Length-1) }
        if($line.Contains("`r") -or [string]::IsNullOrWhiteSpace($line) -or $ended) { throw 'Empty/partial/appended pose record.' }
        $document=Read-MineComeTraceJson $line 4096
        try {
            $root=$document.RootElement;$kind=Get-MineComeTraceString $root 'kind'
            switch -CaseSensitive ($kind) {
                begin { $keys=$common+@('center','anchor_mc','initial_mc_baseline','view_kind') }
                sample { $keys=$common+@('server_seq','server_age_ns','input_dispatch_watermark','client','server','kcd_target') }
                end { $keys=$common+@('result','reason','last_server_seq','last_input_dispatch_watermark') }
                default { throw 'Unknown pose recording kind.' }
            }
            Assert-MineComeTraceKeys $root $keys
            [void](Get-MineComeTraceInteger $root 'schema' 1 1)
            if((Get-MineComeTraceString $root 'source_kind') -cne 'external_input_mc_pose_v1' -or (Get-MineComeTraceString $root 'coordinate_space') -cne 'patch_space' -or
                (Get-MineComeTraceString $root 'run') -cne $InputRun -or (Get-MineComeTraceInteger $root 'target_pid' 1 4294967295) -ne $TargetPid -or
                (Get-MineComePoseEvidenceU64 $root 'target_start_filetime').Text -cne $TargetStartFiletime -or (Get-MineComeTraceString $root 'patch_run') -cne $patchRun -or
                (Get-MineComeTraceString $root 'patch_sha256') -cne $patch.Sha256 -or (Get-MineComeTraceString $root 'view_seed_sha256') -cne $view.Sha256 -or
                (Get-MineComeTraceString $root 'ground_source_kind') -cne $groundKind -or (Get-MineComeTraceBoolean $root 'fixture') -ne $Fixture) { throw 'Pose recording expected identity/hash mismatch.' }
            if(-not (Get-MineComeTraceBoolean $root 'audit_only') -or (Get-MineComeTraceBoolean $root 'follower_eligible') -or
                (Get-MineComeTraceBoolean $root 'control_ownership_verified') -or (Get-MineComeTraceBoolean $root 'kcd_movement_applied')) { throw 'Pose recording must remain audit-only and ineligible for a follower.' }
            $currentWorld=Get-MineComeTraceString $root 'world';$currentSave=Get-MineComeTraceString $root 'save';$uuid=[Guid]::Empty
            if(-not [Guid]::TryParseExact($currentWorld,'D',[ref]$uuid) -or $currentWorld -cne $uuid.ToString('D') -or $currentSave -cne ('MineCome-ExternalInput-'+$currentWorld)) { throw 'Noncanonical external-input world/save identity.' }
            if($begun -and ($currentWorld -cne $world -or $currentSave -cne $save)) { throw 'Pose world/save changed.' }
            $seq=Get-MineComeTraceInteger $root 'seq' 1 512
            $utc=Get-MineComeTraceInteger $root 'utc_ms' 1 ([long]::MaxValue)
            if($seq -ne $lastSeq+1 -or $utc -lt $lastUtc) { throw 'Pose sequence/recorded UTC regressed or skipped.' }
            if(-not $begun -and $kind -cne 'begin') { throw 'Pose recording requires begin first.' }
            switch -CaseSensitive ($kind) {
                begin {
                    if($begun -or $seq -ne 1) { throw 'Repeated pose begin.' }
                    $recordCenter=Get-MineComePoseEvidenceVector $root 'center' -10000000 10000000
                    $anchor=Get-MineComePoseEvidenceVector $root 'anchor_mc' 0 64
                    foreach($axis in @('x','y','z')) { Assert-MineComePoseEvidenceClose $recordCenter.$axis $center.$axis -Tolerance 0 }
                    if($anchor.x -ne 0 -or $anchor.y -ne 64 -or $anchor.z -ne 0 -or (Get-MineComeTraceString $root 'view_kind') -cne 'vanilla_player_yaw_pitch') { throw 'Unexpected coordinate anchor/view contract.' }
                    $baseline=Get-MineComePoseEvidenceVector $root 'initial_mc_baseline' -76 76
                    if([Math]::Abs($baseline.x) -gt 2 -or [Math]::Abs($baseline.z) -gt 2 -or $baseline.y -lt 52 -or $baseline.y -gt 76) { throw 'Initial baseline outside patch-space bounds.' }
                    $world=$currentWorld;$save=$currentSave;$begun=$true
                }
                sample {
                    $serverSeq=Get-MineComeTraceInteger $root 'server_seq' 1 ([long]::MaxValue)
                    [void](Get-MineComeTraceInteger $root 'server_age_ns' 0 250000000)
                    $currentWatermark=Get-MineComePoseEvidenceU64 $root 'input_dispatch_watermark' $true
                    if($serverSeq -le $lastServer -or $currentWatermark.Number -lt $watermark) { throw 'Server sequence/dispatch watermark replay or regression.' }
                    [void](Get-MineComePoseEvidenceMotion $root 'client')
                    $server=Get-MineComePoseEvidenceMotion $root 'server'
                    $target=Get-MineComeTraceField $root 'kcd_target'
                    Assert-MineComeTraceKeys $target @('x','y','z','forward')
                    Assert-MineComePoseEvidenceClose (Get-MineComeTraceNumber $target 'x' -10000004 10000004) ($center.x+$server.x)
                    Assert-MineComePoseEvidenceClose (Get-MineComeTraceNumber $target 'y' -10000004 10000004) ($center.y-$server.z)
                    Assert-MineComePoseEvidenceClose (Get-MineComeTraceNumber $target 'z' -10000012 10000012) ($center.z+$server.y-64)
                    $forward=Get-MineComePoseEvidenceVector $target 'forward' -1 1
                    $yaw=$server.yaw*[Math]::PI/180;$pitch=$server.pitch*[Math]::PI/180
                    Assert-MineComePoseEvidenceClose $forward.x (-[Math]::Sin($yaw)*[Math]::Cos($pitch))
                    Assert-MineComePoseEvidenceClose $forward.y (-[Math]::Cos($yaw)*[Math]::Cos($pitch))
                    Assert-MineComePoseEvidenceClose $forward.z (-[Math]::Sin($pitch))
                    $snapshot=[pscustomobject]@{Seq=$seq;ServerSeq=$serverSeq;UtcMs=$utc;InputDispatchWatermark=$currentWatermark.Text;Server=$server;KcdTarget=(Convert-MineComeTraceValue $target)}
                    if($null -eq $first) { $first=$snapshot };$last=$snapshot;$samples++
                    $lastServer=$serverSeq;$watermark=$currentWatermark.Number
                }
                end {
                    $reason=Get-MineComeTraceString $root 'reason'
                    $codepoints=0
                    for($reasonIndex=0;$reasonIndex -lt $reason.Length;$reasonIndex++) {
                        if([char]::IsHighSurrogate($reason[$reasonIndex])) {
                            if($reasonIndex+1 -ge $reason.Length -or -not [char]::IsLowSurrogate($reason[$reasonIndex+1])) { throw 'Invalid Unicode end reason.' }
                            $reasonIndex++
                        } elseif([char]::IsLowSurrogate($reason[$reasonIndex])) { throw 'Invalid Unicode end reason.' }
                        if(++$codepoints -gt 160) { throw 'End reason exceeds160Unicode codepoints.' }
                    }
                    $endWatermark=Get-MineComePoseEvidenceU64 $root 'last_input_dispatch_watermark' $true
                    if($previousKind -cne 'sample' -or $samples -lt 1 -or (Get-MineComeTraceString $root 'result') -cne 'passed' -or
                        (Get-MineComeTraceInteger $root 'last_server_seq' 1 ([long]::MaxValue)) -ne $lastServer -or $endWatermark.Number -ne $watermark) { throw 'Passed terminal does not match its immediately preceding final sample.' }
                    if($index -ne $recordCount-1) { throw 'Pose end must be the last record.' };$ended=$true
                }
            }
            $lastSeq=$seq;$lastUtc=$utc;$previousKind=$kind
        } finally { $document.Dispose() }
    }
    if(-not $ended) { throw 'Passed complete terminal record is required.' }
    return [pscustomobject]@{Kind='Validated stored external-input pose recording';Path=$file.Path;Sha256=$file.Sha256;Run=$InputRun;World=$world;Save=$save;Records=$recordCount;Samples=$samples;First=$first;Last=$last;Result='passed';AuditOnly=$true;FollowerEligible=$false;ControlOwnershipVerified=$false;KcdMovementApplied=$false;FreshNowVerified=$false;FileAuthenticityVerified=$false}
}
