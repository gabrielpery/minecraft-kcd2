#Requires -Version 7.3
# On-demand heightfield tiles integrated into the single gameplay console worker.
# Only the Minecraft store writes persistent coverage. This helper publishes one
# admission at a time and advances coverage only after the matching durable ack.
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')

function Test-GameplayTerrainNumber($Value){return $Value -is [ValueType] -and $Value -isnot [bool] -and [double]::IsFinite([double]$Value)}
function Test-GameplayTerrainInteger($Value,[long]$Min,[long]$Max){return (Test-GameplayTerrainNumber $Value) -and $Value -ge $Min -and $Value -le $Max -and $Value -eq [Math]::Floor([double]$Value)}
function Assert-GameplayTerrainFields($Value,[string[]]$Names){
    if($Value -isnot [pscustomobject] -or (($Value.PSObject.Properties.Name|Sort-Object -CaseSensitive)-join ',') -cne (($Names|Sort-Object -CaseSensitive)-join ',')){throw 'Terrain record fields differ.'}
}
function ConvertFrom-GameplayTerrainJson([string]$Text,[int]$MaxBytes=65536){
    if([Text.Encoding]::UTF8.GetByteCount($Text) -gt $MaxBytes){throw 'Terrain JSON exceeds its byte bound.'}
    $options=[Text.Json.JsonDocumentOptions]::new();$options.MaxDepth=12;$doc=[Text.Json.JsonDocument]::Parse($Text,$options)
    function Unique-GameplayTerrainMembers($Element){
        if($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object){
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($p in $Element.EnumerateObject()){if(-not $seen.Add($p.Name)){throw 'Duplicate terrain JSON field.'};Unique-GameplayTerrainMembers $p.Value}
        }elseif($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($v in $Element.EnumerateArray()){Unique-GameplayTerrainMembers $v}}
    }
    try{Unique-GameplayTerrainMembers $doc.RootElement;return ($Text|ConvertFrom-Json -Depth 12)}finally{$doc.Dispose()}
}
function Get-GameplayTerrainHash([string]$Text){return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()}
function Get-GameplayTerrainDigest([string]$BaseHash,$Tiles){
    $text="minecome_gameplay_coverage_v1`n$BaseHash`n"
    foreach($tile in $Tiles){$text+=([string]$tile.Tx)+','+([string]$tile.Tz)+':'+$tile.Sha256+"`n"}
    return Get-GameplayTerrainHash $text
}
function Read-GameplayTerrainJsonFile([string]$Path,[int]$MaxBytes){
    $file=$null
    try{
        $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if($file.Length -lt 2 -or $file.Length -gt $MaxBytes){throw 'Terrain file exceeds its byte bound.'}
        $bytes=[byte[]]::new([int]$file.Length);$file.ReadExactly($bytes);if($file.ReadByte() -ne -1){throw 'Terrain file changed size.'}
        return ConvertFrom-GameplayTerrainJson ([Text.UTF8Encoding]::new($false,$true).GetString($bytes)) $MaxBytes
    }catch [IO.IOException]{if(($_.Exception.HResult -band 0xffff) -in @(2,3,32,33,303)){return $null};throw}
    finally{if($file){$file.Dispose()}}
}
function ConvertTo-GameplayTerrainTile([int]$Tx,[int]$Tz,[string]$Json,[string]$Hash,$Base){
    if($Tx -lt -8 -or $Tx -gt 8 -or $Tz -lt -8 -or $Tz -gt 8 -or $Hash -cnotmatch '^[a-f0-9]{64}$' -or (Get-GameplayTerrainHash $Json) -cne $Hash){throw 'Terrain tile coordinates/hash differ.'}
    $tile=ConvertFrom-GameplayTerrainJson $Json
    if(-not(Test-GameplayTerrainInteger $tile.schema 1 1) -or -not(Test-GameplayTerrainInteger $tile.grid_size 9 9) -or
        -not(Test-GameplayTerrainInteger $tile.spacing 1 1) -or $tile.walking_area -cne 'wide' -or $tile.run -cnotmatch '^[a-f0-9]{32}$' -or
        $tile.provenance.kind -cne $Base.Data.provenance.kind -or @($tile.points).Count -ne 81){throw 'Terrain tile grid/provenance differs.'}
    if($tile.provenance.kind -ceq 'live_kcd_ground_patch' -and ($tile.provenance.game_exe_hash -inotmatch '^[a-f0-9]{64}$' -or $tile.provenance.game_exe_hash -ine $Base.Data.provenance.game_exe_hash)){throw 'Terrain tile executable provenance differs.'}
    if(($tile.PSObject.Properties['stable_player'] -and ($tile.stable_player -isnot [bool] -or -not $tile.stable_player)) -or
        ($tile.PSObject.Properties['point_count'] -and -not(Test-GameplayTerrainInteger $tile.point_count 81 81)) -or
        ($tile.PSObject.Properties['valid_count'] -and -not(Test-GameplayTerrainInteger $tile.valid_count 81 81))){throw 'Terrain tile is partial or unstable.'}
    Assert-GameplayTerrainFields $tile.center @('x','y','z')
    $expected=@{x=[double]$Base.Data.center.x+8*$Tx;y=[double]$Base.Data.center.y-8*$Tz;z=[double]$Base.Data.center.z}
    foreach($axis in @('x','y','z')){if(-not(Test-GameplayTerrainNumber $tile.center.$axis) -or [double]$tile.center.$axis -ne $expected[$axis]){throw 'Terrain tile moved the saved origin.'}}
    for($i=0;$i -lt 81;$i++){
        $p=$tile.points[$i];$row=[Math]::Floor($i/9);$col=$i%9
        if(($p.PSObject.Properties['valid'] -and ($p.valid -isnot [bool] -or -not $p.valid)) -or ($p.PSObject.Properties['result'] -and $p.result -cne 'hit')){throw 'Terrain point is not a valid hit.'}
        if(-not(Test-GameplayTerrainInteger $p.index ($i+1) ($i+1))){throw 'Terrain point index differs.'}
        foreach($field in @('x','y','z','nx','ny','nz')){if(-not(Test-GameplayTerrainNumber $p.$field)){throw 'Terrain point is not finite.'}}
        if([Math]::Abs($p.x-($tile.center.x+$col-4)) -gt .0001 -or [Math]::Abs($p.y-($tile.center.y+$row-4)) -gt .0001 -or
            [Math]::Abs($p.z-$tile.center.z) -gt 8 -or [Math]::Abs($p.nx*$p.nx+$p.ny*$p.ny+$p.nz*$p.nz-1) -gt .05 -or $p.nz -lt .5){throw 'Terrain point geometry differs.'}
        if(($col -gt 0 -and [Math]::Abs($p.z-$tile.points[$i-1].z) -gt .5) -or ($row -gt 0 -and [Math]::Abs($p.z-$tile.points[$i-9].z) -gt .5)){throw 'Terrain height step exceeds0.5m.'}
    }
    [pscustomobject]@{Tx=$Tx;Tz=$Tz;Json=$Json;Sha256=$Hash;Data=$tile}
}
function Test-GameplayTerrainConnection($Known,$Candidate){
    $adjacent=$false
    foreach($other in $Known.Values){
        $dx=$Candidate.Tx-$other.Tx;$dz=$Candidate.Tz-$other.Tz
        if([Math]::Abs($dx)+[Math]::Abs($dz) -ne 1){continue};$adjacent=$true
        for($i=0;$i -lt 9;$i++){
            if($dx -eq 1){$a=$Candidate.Data.points[$i*9];$b=$other.Data.points[$i*9+8]}
            elseif($dx -eq -1){$a=$Candidate.Data.points[$i*9+8];$b=$other.Data.points[$i*9]}
            elseif($dz -eq 1){$a=$Candidate.Data.points[72+$i];$b=$other.Data.points[$i]}
            else{$a=$Candidate.Data.points[$i];$b=$other.Data.points[72+$i]}
            foreach($f in @('x','y','z','nx','ny','nz')){if([Math]::Abs([double]$a.$f-[double]$b.$f) -gt .0001){return $false}}
        }
    }
    return $adjacent
}
function Read-GameplayTerrainCoverage([string]$Path,$Identity,$Base){
    $tiles=[Collections.Generic.List[object]]::new();$known=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $tiles.Add($Base);$known.Add('0,0',$Base)
    if([IO.File]::Exists($Path)){
        $saved=Read-GameplayTerrainJsonFile $Path 8388608;if(-not $saved){throw 'Saved terrain coverage is not readable.'}
        Assert-GameplayTerrainFields $saved @('schema','kind','world_id','patch_run','patch_sha256','generation','digest','tiles')
        if(-not(Test-GameplayTerrainInteger $saved.schema 1 1) -or $saved.kind -cne 'minecome_gameplay_coverage_v1' -or
            $saved.world_id -cne $Identity.WorldId -or $saved.patch_run -cne $Identity.PatchRun -or $saved.patch_sha256 -cne $Identity.PatchHash -or
            -not(Test-GameplayTerrainInteger $saved.generation 0 63) -or $saved.generation -ne @($saved.tiles).Count){throw 'Saved terrain coverage identity differs.'}
        foreach($entry in $saved.tiles){
            Assert-GameplayTerrainFields $entry @('tx','tz','sha256','json')
            if(-not(Test-GameplayTerrainInteger $entry.tx -8 8) -or -not(Test-GameplayTerrainInteger $entry.tz -8 8) -or $entry.json -isnot [string]){throw 'Saved tile entry differs.'}
            $tile=ConvertTo-GameplayTerrainTile $entry.tx $entry.tz $entry.json $entry.sha256 $Base;$key=([string]$entry.tx)+','+([string]$entry.tz)
            if($known.ContainsKey($key) -or -not(Test-GameplayTerrainConnection $known $tile)){throw 'Saved tile duplicates or changes an admitted edge.'}
            $known.Add($key,$tile);$tiles.Add($tile)
        }
        if((Get-GameplayTerrainDigest $Identity.PatchHash $tiles) -cne $saved.digest){throw 'Saved terrain coverage digest differs.'}
    }
    [pscustomobject]@{Tiles=$tiles;Known=$known;Generation=$tiles.Count-1;Digest=(Get-GameplayTerrainDigest $Identity.PatchHash $tiles)}
}
function New-GameplayTerrainHost {
    param($Context,[string]$Run,[string]$WorldId,$Patch,[string]$CacheFile,[string]$AdmissionFile,[string]$AckFile,[long]$ExpiresUtcMs)
    if($Run -cnotmatch '^[a-f0-9]{32}$' -or $WorldId -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' -or $Patch.Run -cnotmatch '^[a-f0-9]{32}$' -or $Patch.Hash -cnotmatch '^[a-f0-9]{64}$'){throw 'Gameplay terrain identity differs.'}
    Assert-MineComeProbeContext $Context
    $AdmissionFile=Resolve-HudMovementEvidencePath $AdmissionFile $Context.ProjectRoot;$AckFile=Resolve-HudMovementEvidencePath $AckFile $Context.ProjectRoot
    $CacheFile=Resolve-MineComeGameplayPath $CacheFile -InRuntime
    if([IO.File]::Exists($AdmissionFile) -or [IO.File]::Exists($AckFile) -or [IO.File]::Exists($AdmissionFile+'.'+$Run+'.tmp')){throw 'Terrain session transport already exists.'}
    $json=[IO.File]::ReadAllText($Patch.Path,[Text.UTF8Encoding]::new($false,$true));if((Get-GameplayTerrainHash $json) -cne $Patch.Hash){throw 'Base terrain bytes changed.'}
    $data=ConvertFrom-GameplayTerrainJson $json
    if($data.run -cne $Patch.Run -or $data.provenance.kind -cne 'live_kcd_ground_patch' -or $data.provenance.game_exe_hash -ine $Context.GameHash){throw 'Base terrain is not a capture of the pinned game.'}
    $base=[pscustomobject]@{Tx=0;Tz=0;Json=$json;Sha256=$Patch.Hash;Data=$data};$base=ConvertTo-GameplayTerrainTile 0 0 $json $Patch.Hash $base
    $identity=[pscustomobject]@{Run=$Run;WorldId=$WorldId;Pid=$Context.GamePid;Start=$Context.GameStartedUtc.ToFileTimeUtc().ToString();PatchRun=$Patch.Run;PatchHash=$Patch.Hash}
    $coverage=Read-GameplayTerrainCoverage $CacheFile $identity $base
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();if($ExpiresUtcMs-$now -lt 1000 -or $ExpiresUtcMs-$now -gt 86400000){throw 'Gameplay terrain expiry differs.'}
    $probe=New-MineComeProbeRun $Context 'gameplay-terrain' (Join-Path $Context.ProjectRoot 'kcd2/gameplay/terrain_session.lua') 'GameplayTerrainBegin'
    [pscustomobject]@{Identity=$identity;Context=$Context;Base=$base;Tiles=$coverage.Tiles;Known=$coverage.Known;Generation=$coverage.Generation;Digest=$coverage.Digest;
        CacheFile=$CacheFile;AdmissionFile=$AdmissionFile;AckFile=$AckFile;ExpiresUtcMs=$ExpiresUtcMs;Probe=$probe;BeginSent=$false;Begin=$null;Terminal=$null;Stopping=$false;Failure=$null;
        LastSendUtcMs=0L;Sequence=0L;Pending=$null;LastPose=$null;Refused=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);LastRefusal=$null;CapacityReached=$false;Captures=0L;Admissions=0L}
}
function Find-GameplayTerrainFrontier($State,$Pose){
    if(-not $Pose){return $null};$old=$State.LastPose;$State.LastPose=$Pose
    if(-not $old -or $Pose.seq -le $old.seq -or $Pose.utc_ms-$old.utc_ms -gt 500 -or $Pose.utc_ms -lt $old.utc_ms){return $null}
    $x=[double]$Pose.position.x-$State.Base.Data.center.x;$z=$State.Base.Data.center.y-[double]$Pose.position.y
    $dx=[double]$Pose.position.x-$old.position.x;$dz=[double]$old.position.y-$Pose.position.y
    $tx=[int][Math]::Floor(($x+4)/8);$tz=[int][Math]::Floor(($z+4)/8)
    if(-not $State.Known.ContainsKey("$tx,$tz")){return $null}
    $candidates=[Collections.Generic.List[object]]::new()
    foreach($v in @(@{dx=1;dz=0;motion=$dx;distance=8*$tx+4-$x},@{dx=-1;dz=0;motion=-$dx;distance=$x-(8*$tx-4)},@{dx=0;dz=1;motion=$dz;distance=8*$tz+4-$z},@{dx=0;dz=-1;motion=-$dz;distance=$z-(8*$tz-4)})){
        $nx=$tx+$v.dx;$nz=$tz+$v.dz;$key="$nx,$nz"
        # Request before GameplayBoundary's conservative long-air-coast brake;
        # actual vanilla walking reaches that brake around1.3m on an8m tile.
        if($v.motion -gt .001 -and $v.distance -le 3.25 -and $nx -ge -8 -and $nx -le 8 -and $nz -ge -8 -and $nz -le 8 -and -not $State.Known.ContainsKey($key) -and -not $State.Refused.Contains($key)){
            $candidates.Add([pscustomobject]@{Tx=$nx;Tz=$nz;Score=$v.distance/$v.motion})
        }
    }
    return ($candidates|Sort-Object Score|Select-Object -First 1)
}
function Test-GameplayTerrainCell($State,[int]$X,[int]$Z){
    if($X -lt -68 -or $X -gt 67 -or $Z -lt -68 -or $Z -gt 67){return $false}
    $tx=[int][Math]::Floor(($X+4)/8);$tz=[int][Math]::Floor(($Z+4)/8)
    return $State.Known.ContainsKey("$tx,$tz")
}
function Test-GameplayTerrainPose($State,$Pose){
    foreach($a in @('x','y','z')){if(-not(Test-GameplayTerrainNumber $Pose.position.$a)){return $false}}
    $x=[double]$Pose.position.x-$State.Base.Data.center.x;$z=$State.Base.Data.center.y-[double]$Pose.position.y
    if([Math]::Abs($x) -gt 68 -or [Math]::Abs($z) -gt 68){return $false}
    # Match GameplayTerrain.containsFeet: all touched integer columns, with an
    # exclusive maximum edge. Checking only the centre accepts unknown terrain.
    for($cx=[int][Math]::Floor($x-.31);$cx -lt [Math]::Ceiling($x+.31);$cx++){
        for($cz=[int][Math]::Floor($z-.31);$cz -lt [Math]::Ceiling($z+.31);$cz++){
            if(-not(Test-GameplayTerrainCell $State $cx $cz)){return $false}
        }
    }
    return $true
}
function Read-GameplayTerrainAck($State){
    $ack=Read-GameplayTerrainJsonFile $State.AckFile 4096;if(-not $ack){return}
    Assert-GameplayTerrainFields $ack @('schema','kind','run','world_id','patch_run','patch_sha256','target_pid','target_start_filetime','generation','tx','tz','tile_sha256','status','coverage_digest')
    $id=$State.Identity
    if(-not(Test-GameplayTerrainInteger $ack.schema 1 1) -or $ack.kind -cne 'minecome_gameplay_terrain_ack_v1' -or $ack.run -cne $id.Run -or $ack.world_id -cne $id.WorldId -or
        $ack.patch_run -cne $id.PatchRun -or $ack.patch_sha256 -cne $id.PatchHash -or -not(Test-GameplayTerrainInteger $ack.target_pid $id.Pid $id.Pid) -or
        $ack.target_start_filetime -isnot [string] -or $ack.target_start_filetime -cne $id.Start -or -not(Test-GameplayTerrainInteger $ack.generation 1 63) -or
        -not(Test-GameplayTerrainInteger $ack.tx -8 8) -or -not(Test-GameplayTerrainInteger $ack.tz -8 8) -or $ack.tile_sha256 -cnotmatch '^[a-f0-9]{64}$' -or $ack.coverage_digest -cnotmatch '^[a-f0-9]{64}$'){throw 'Terrain admission acknowledgement identity differs.'}
    if($ack.generation -le $State.Generation){return}
    $pending=$State.Pending
    if(-not $pending -or -not $pending.Tile -or $ack.generation -ne $State.Generation+1 -or $ack.tx -ne $pending.Tx -or $ack.tz -ne $pending.Tz -or
        $ack.tile_sha256 -cne $pending.Tile.Sha256 -or $ack.status -cne 'admitted'){throw 'Terrain admission acknowledgement differs.'}
    $next=[Collections.Generic.List[object]]::new();foreach($t in $State.Tiles){$next.Add($t)};$next.Add($pending.Tile)
    $digest=Get-GameplayTerrainDigest $id.PatchHash $next;if($ack.coverage_digest -cne $digest){throw 'Terrain acknowledgement coverage digest differs.'}
    $State.Tiles.Add($pending.Tile);$State.Known.Add((([string]$pending.Tx)+','+([string]$pending.Tz)),$pending.Tile);$State.Generation++;$State.Digest=$digest;$State.Admissions++;$State.Pending=$null
}
function Get-GameplayTerrainCommands($State,[long]$Now,$Pose=$null){
    if($State.Failure){throw $State.Failure};if($State.Stopping){return ''};if($Now -ge $State.ExpiresUtcMs){throw 'Terrain session expired.'}
    $run=$State.Identity.Run
    if(-not $State.BeginSent){
        $State.BeginSent=$true;$State.LastSendUtcMs=$Now;$duration=[Math]::Min(86400000,$State.ExpiresUtcMs-$Now)
        $values=@($duration,$State.Base.Data.center.x,$State.Base.Data.center.y,$State.Base.Data.center.z)|ForEach-Object {([double]$_).ToString('R',[Globalization.CultureInfo]::InvariantCulture)}
        return "MineCome.GameplayTerrainBegin('$run',$([string]::Join(',',$values)))"
    }
    if(-not $State.Begin){if($Now-$State.LastSendUtcMs -gt 1500){throw 'Terrain begin acknowledgement expired.'};return ''}
    if($State.Pending -and $State.Pending.Tile){Read-GameplayTerrainAck $State}
    $frontier=Find-GameplayTerrainFrontier $State $Pose
    if($State.Pending){
        if($Now-$State.Pending.RequestedUtcMs -gt 5000){throw 'Terrain capture/admission acknowledgement expired.'}
    }elseif($frontier -and $State.Known.Count -lt 64 -and -not $State.CapacityReached){
        $State.Sequence++;$State.Pending=[pscustomobject]@{Request=$State.Sequence;Tx=$frontier.Tx;Tz=$frontier.Tz;RequestedUtcMs=$Now;Tile=$null;Points=[Collections.Generic.List[object]]::new()};$State.LastSendUtcMs=$Now
        return "MineCome.GameplayTerrainCapture('$run',$($State.Sequence),$($frontier.Tx),$($frontier.Tz))"
    }
    if($Now-$State.LastSendUtcMs -ge 250){$State.LastSendUtcMs=$Now;return "MineCome.GameplayTerrainHeartbeat('$run')"};return ''
}
function Publish-GameplayTerrainAdmission($State,[string]$Text){
    $temp=$State.AdmissionFile+'.'+$State.Identity.Run+'.tmp';$watch=[Diagnostics.Stopwatch]::StartNew()
    [IO.File]::WriteAllText($temp,$Text,[Text.UTF8Encoding]::new($false))
    while($true){try{[IO.File]::Move($temp,$State.AdmissionFile,$true);return}catch{
        $cause=$_.Exception.GetBaseException();if(($cause -isnot [IO.IOException] -and $cause -isnot [UnauthorizedAccessException]) -or ($cause.HResult -band 0xffff) -notin @(5,32,33) -or $watch.ElapsedMilliseconds -ge 100){throw};Start-Sleep -Milliseconds 5
    }}
}
function Accept-GameplayTerrainReceipt($State,$Receipt,[long]$Now){
    if(-not(Test-GameplayTerrainInteger $Receipt.schema 1 1) -or $Receipt.run -cne $State.Identity.Run){throw 'Native terrain receipt identity differs.'}
    switch -CaseSensitive ($Receipt.event){
        'begin'{if($State.Begin -or $Receipt.result -cne 'ready' -or $Receipt.active -ne $true){throw 'Native terrain begin differs.'};$State.Begin=$Receipt}
        'terminal'{$State.Terminal=$Receipt;if(-not $State.Stopping -or $Receipt.result -cne 'explicit_stop' -or $Receipt.active -ne $false -or $Receipt.timers_cancelled -ne $true){$State.Failure='Native terrain stopped: '+$Receipt.result}}
        {$_ -cin @('samples','captured','refused')}{
            $p=$State.Pending
            if(-not $p -or $p.Tile -or -not(Test-GameplayTerrainInteger $Receipt.request $p.Request $p.Request) -or
                -not(Test-GameplayTerrainInteger $Receipt.tx $p.Tx $p.Tx) -or -not(Test-GameplayTerrainInteger $Receipt.tz $p.Tz $p.Tz) -or
                -not(Test-GameplayTerrainInteger $Receipt.ray_count 0 81) -or -not(Test-GameplayTerrainInteger $Receipt.mask 1 2147483647) -or $Receipt.active -ne $true){throw 'Native terrain capture identity differs.'}
            if($Receipt.event -ceq 'refused'){
                if($Receipt.result -cnotmatch '^(terrain_miss|terrain_hit_invalid|terrain_step_invalid|capture_expired|capacity_reached)$'){throw 'Native terrain refusal differs.'}
                if($Receipt.result -ceq 'capacity_reached'){$State.CapacityReached=$true}
                [void]$State.Refused.Add("$($p.Tx),$($p.Tz)");$State.LastRefusal=$Receipt.result;$State.Pending=$null;return
            }
            if($Receipt.event -ceq 'samples'){
                $first=$p.Points.Count+1
                if($Receipt.result -cne 'sampling' -or -not(Test-GameplayTerrainInteger $Receipt.first $first $first) -or
                    -not(Test-GameplayTerrainInteger $Receipt.count 9 9) -or @($Receipt.points).Count -ne 9 -or $first+8 -gt 81 -or $Receipt.ray_count -ne $first+8 -or $Now-$p.RequestedUtcMs -gt 5000){throw 'Native terrain sample sequence differs.'}
                for($i=0;$i -lt 9;$i++){
                    $point=$Receipt.points[$i];Assert-GameplayTerrainFields $point @('index','x','y','z','nx','ny','nz')
                    if(-not(Test-GameplayTerrainInteger $point.index ($first+$i) ($first+$i))){throw 'Native terrain sample index differs.'}
                    foreach($field in @('x','y','z','nx','ny','nz')){if(-not(Test-GameplayTerrainNumber $point.$field)){throw 'Native terrain sample is not finite.'}}
                }
                foreach($point in $Receipt.points){$p.Points.Add($point)};return
            }
            if($Receipt.result -cne 'sampled' -or $Receipt.ray_count -ne 81 -or $p.Points.Count -ne 81 -or $Receipt.PSObject.Properties['points'] -or $Now-$p.RequestedUtcMs -gt 5000){throw 'Incomplete/expired native terrain tile.'}
            Assert-GameplayTerrainFields $Receipt.anchor @('x','y','z')
            foreach($a in @('x','y','z')){if(-not(Test-GameplayTerrainNumber $Receipt.anchor.$a) -or $Receipt.anchor.$a -ne $State.Base.Data.center.$a){throw 'Native terrain anchor differs.'}}
            $tile=[ordered]@{schema=1;run=$State.Identity.Run;grid_size=9;spacing=1;walking_area='wide';center=[ordered]@{x=$State.Base.Data.center.x+8*$p.Tx;y=$State.Base.Data.center.y-8*$p.Tz;z=$State.Base.Data.center.z};point_count=81;valid_count=81;
                approximate_heightfield=$true;full_collision_export_verified=$false;stable_player_identity=$true;points=@($p.Points.ToArray());
                provenance=[ordered]@{kind=$State.Base.Data.provenance.kind;game_pid=$State.Identity.Pid;game_start_filetime=$State.Identity.Start;game_exe_hash=$State.Context.GameHash.ToLowerInvariant();source_sha256=$State.Probe.SourceHash.ToLowerInvariant()}}
            $json=$tile|ConvertTo-Json -Depth 8 -Compress;$hash=Get-GameplayTerrainHash $json;$candidate=ConvertTo-GameplayTerrainTile $p.Tx $p.Tz $json $hash $State.Base
            if(-not(Test-GameplayTerrainConnection $State.Known $candidate)){[void]$State.Refused.Add("$($p.Tx),$($p.Tz)");$State.LastRefusal='shared_edge_changed';$State.Pending=$null;return}
            $p.Tile=$candidate;$id=$State.Identity
            $admission=[ordered]@{schema=1;kind='minecome_gameplay_terrain_admission_v1';run=$id.Run;world_id=$id.WorldId;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;target_pid=$id.Pid;target_start_filetime=$id.Start;
                generation=$State.Generation+1;tx=$p.Tx;tz=$p.Tz;tile_sha256=$hash;tile_json=$json;utc_ms=$p.RequestedUtcMs}
            Publish-GameplayTerrainAdmission $State ($admission|ConvertTo-Json -Depth 6 -Compress);$State.Captures++
        }
        default{throw 'Unknown native terrain event.'}
    }
}
function Get-GameplayTerrainStopCommand($State){$State.Stopping=$true;return "MineCome.GameplayTerrainEnd('$($State.Identity.Run)')"}
function Get-GameplayTerrainHostState($State){
    [pscustomobject]@{Run=$State.Identity.Run;Failure=$State.Failure;Generation=$State.Generation;CoverageDigest=$State.Digest;TileCount=$State.Known.Count;Captures=$State.Captures;Admissions=$State.Admissions;
        RefusedCount=$State.Refused.Count;LastRefusal=$State.LastRefusal;CapacityReached=$State.CapacityReached;Pending=($null -ne $State.Pending);Begin=$State.Begin;Terminal=$State.Terminal;
        CleanupComplete=(-not $State.BeginSent -or ($State.Terminal -and $State.Terminal.result -ceq 'explicit_stop' -and -not $State.Terminal.active -and $State.Terminal.timers_cancelled))}
}
