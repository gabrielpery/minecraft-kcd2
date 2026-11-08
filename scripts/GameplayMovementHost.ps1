#Requires -Version 7.3
# Owned ongoing movement/view worker. The caller starts the exact tools process;
# this helper never starts a game or modifies persistent game settings.
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'GameplayBlocksHost.ps1')
. (Join-Path $PSScriptRoot 'GameplayTerrainHost.ps1')
. (Join-Path $PSScriptRoot 'GameplayCombatHost.ps1')

function Get-GameplayMovementBounds($Patch){
    $data=Get-Content -LiteralPath $Patch.Path -Raw|ConvertFrom-Json -Depth 16
    $tiles=if($data.PSObject.Properties['tiles']){@($data.tiles|ForEach-Object {$_.json|ConvertFrom-Json -Depth 12})}else{@($data)}
    $points=@($tiles|ForEach-Object {$_.points}|Where-Object {$_.valid -eq $true})
    if($points.Count -lt 4){throw 'Captured gameplay ground has insufficient valid points.'}
    [pscustomobject]@{MinX=($points.x|Measure-Object -Minimum).Minimum+.31;MaxX=($points.x|Measure-Object -Maximum).Maximum-.31;
        MinY=($points.y|Measure-Object -Minimum).Minimum+.31;MaxY=($points.y|Measure-Object -Maximum).Maximum-.31;
        MinZ=($points.z|Measure-Object -Minimum).Minimum-.5;MaxZ=($points.z|Measure-Object -Maximum).Maximum+2.5}
}
function Test-GameplayHostNumber($Value){$Value -is [ValueType] -and $Value -isnot [bool] -and [double]::IsFinite([double]$Value)}
function ConvertTo-GameplayMovementRequests([string]$Run,[string[]]$Bodies){
    # The live tools endpoint truncates long URL-encoded commands before Lua
    # parsing. Bound the actual encoded request, including the path and flush;
    # split only between complete caller-supplied statements, never Lua text.
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or -not $Bodies -or $Bodies.Count -gt 8){throw 'Invalid gameplay console batch.'}
    $prefix='/api/System/Console/ExecuteString?command='
    $suffix=";System.LogAlways('[MineComeGameplayFlush] $Run')"
    $requests=[Collections.Generic.List[object]]::new();$pending=''
    foreach($body in $Bodies){
        if([string]::IsNullOrWhiteSpace($body)){throw 'Empty gameplay console statement.'}
        $single='#'+$body+$suffix
        if(($prefix+[Uri]::EscapeDataString($single)).Length -gt 2000){throw 'One gameplay console statement exceeds the encoded request bound.'}
        $candidate=if($pending){$pending+';'+$body}else{$body}
        $code='#'+$candidate+$suffix;$path=$prefix+[Uri]::EscapeDataString($code)
        if($path.Length -gt 2000){
            $previous='#'+$pending+$suffix
            $requests.Add([pscustomobject]@{Command=$previous;PathAndQuery=($prefix+[Uri]::EscapeDataString($previous))})
            $pending=$body
        }else{$pending=$candidate}
    }
    $code='#'+$pending+$suffix
    $requests.Add([pscustomobject]@{Command=$code;PathAndQuery=($prefix+[Uri]::EscapeDataString($code))})
    # Construct every request before dispatch: an oversized later statement
    # must not partially send an otherwise invalid batch.
    return $requests.ToArray()
}
function Test-GameplayPublicationRetry([Exception]$PublicationException){
    $cause=$PublicationException.GetBaseException();$code=$cause.HResult -band 0xffff
    # ReplaceFileW's 1175 leaves both file names intact. Do NOT retry 1176/1177:
    # those failures may already have moved/deleted the destination.
    # https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew
    return (($cause -is [IO.IOException] -or $cause -is [UnauthorizedAccessException]) -and $code -in @(5,32,33,1175))
}
function Publish-GameplayMovementView([string]$Temporary,[string]$Destination,[ValidateRange(1,100)][int]$RetryMilliseconds=100){
    # Windows can briefly deny replacement while another process opens the old
    # snapshot. Retry only sharing/access conflicts, using the original bytes
    # and capture UTC. This worker never renews a stale camera observation.
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true){
        try{
            if([IO.File]::Exists($Destination)){[IO.File]::Replace($Temporary,$Destination,[NullString]::Value)}else{[IO.File]::Move($Temporary,$Destination,$false)}
            return
        }catch{
            $cause=$_.Exception.GetBaseException();$code=$cause.HResult -band 0xffff
            if(-not (Test-GameplayPublicationRetry $_.Exception) -or $watch.ElapsedMilliseconds -ge $RetryMilliseconds){
                throw [IO.IOException]::new("Gameplay snapshot publication failed for '$Destination' (Win32 $code, $($watch.ElapsedMilliseconds) ms): $($cause.Message)",$cause)
            }
            Start-Sleep -Milliseconds ([int][Math]::Max(0,[Math]::Min(5,$RetryMilliseconds-$watch.ElapsedMilliseconds)))
        }
    }
}
function Read-GameplayMovementPose([string]$Path,$Identity,$Bounds,[long]$LastSequence,[double]$LastSource,[long]$Now,[bool]$WorldBlocks=$false){
    if(-not [IO.File]::Exists($Path)){return $null}
    $file=$null
    try{
        $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $maximum=if($WorldBlocks){20480}else{4096}
        if($file.Length -lt 2 -or $file.Length -gt $maximum){throw 'Gameplay pose exceeds its byte bound.'}
        $bytes=[byte[]]::new([int]$file.Length);$file.ReadExactly($bytes)
        if($file.ReadByte() -ne -1){throw 'Gameplay pose changed size.'}
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        $document=[Text.Json.JsonDocument]::Parse($json)
        try{
            if($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'Gameplay pose must be an object.'}
            $objects=@($document.RootElement,$document.RootElement.GetProperty('position'))
            if($WorldBlocks){$objects+=@($document.RootElement.GetProperty('camera_collision'),$document.RootElement.GetProperty('camera_collision').GetProperty('origin'))}
            $from=[Text.Json.JsonElement]::new();if($document.RootElement.TryGetProperty('respawn_from',[ref]$from)){$objects+=@($from)}
            foreach($element in $objects){
                if($element.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'Gameplay pose position must be an object.'}
                $names=@($element.EnumerateObject()|ForEach-Object {$_.Name})
                if(@($names|Select-Object -Unique).Count -ne $names.Count){throw 'Gameplay pose contains duplicate fields.'}
            }
        }finally{$document.Dispose()}
        $p=$json|ConvertFrom-Json -Depth 6
    }catch [IO.IOException]{if(($_.Exception.HResult -band 0xffff) -in @(2,3,32,33,303)){return $null};throw}
    finally{if($file){$file.Dispose()}}
    $keys=@('schema','kind','run','world_id','target_pid','target_start_filetime','patch_run','patch_sha256','seq','utc_ms','source_ms','position')
    if($WorldBlocks){$keys+=@('perspective_request','camera_collision')}
    if($WorldBlocks -and $p.PSObject.Properties['lifecycle']){
        $keys+=@('lifecycle','respawn_epoch')
        if($p.lifecycle -cnotin @('dead','respawn') -or -not(Test-GameplayHostNumber $p.respawn_epoch) -or $p.respawn_epoch -lt 1 -or $p.respawn_epoch -gt 10000000 -or $p.respawn_epoch -ne [Math]::Floor($p.respawn_epoch)){throw 'Invalid gameplay lifecycle epoch.'}
        if($p.lifecycle -ceq 'respawn'){
            $keys+=@('respawn_from')
            if($p.respawn_from -isnot [pscustomobject] -or (($p.respawn_from.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'x,y,z'){throw 'Invalid respawn previous target.'}
            foreach($axis in @('x','y','z')){if(-not(Test-GameplayHostNumber $p.respawn_from.$axis) -or [Math]::Abs($p.respawn_from.$axis) -ge 10000000){throw 'Invalid respawn previous target.'}}
        }
    }
    if($p -isnot [pscustomobject] -or (($p.PSObject.Properties.Name|Sort-Object)-join ',') -cne (($keys|Sort-Object)-join ',') -or
        $p.schema -ne 1 -or $p.kind -cne 'minecome_gameplay_pose_v1' -or $p.run -cne $Identity.Run -or $p.world_id -cne $Identity.WorldId -or
        $p.target_pid -ne $Identity.Pid -or $p.target_start_filetime -cne $Identity.Start -or $p.patch_run -cne $Identity.PatchRun -or $p.patch_sha256 -cne $Identity.PatchHash){throw 'Gameplay pose identity differs.'}
    foreach($key in @('schema','target_pid','seq','utc_ms','source_ms')){if(-not(Test-GameplayHostNumber $p.$key)){throw "Invalid gameplay pose number: $key"}}
    if($p.target_start_filetime -isnot [string]){throw 'Gameplay target start must be a string.'}
    if($WorldBlocks -and (-not(Test-GameplayHostNumber $p.perspective_request) -or $p.perspective_request -notin @(0,1,2))){throw 'Invalid gameplay perspective request.'}
    if($WorldBlocks){
        $c=$p.camera_collision
        if($c -isnot [pscustomobject] -or (($c.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'boxes,complete,generation,origin' -or
           -not(Test-GameplayHostNumber $c.generation) -or $c.generation -lt 1 -or $c.generation -gt 10000000 -or $c.generation -ne [Math]::Floor($c.generation) -or
           $c.complete -isnot [bool] -or $c.boxes -isnot [string] -or $c.boxes.Length -gt 12288 -or $c.boxes.Length%24 -ne 0 -or $c.boxes -cmatch '[^0-9a-f]' -or
           (-not $c.complete -and $c.boxes.Length -ne 0) -or $c.origin -isnot [pscustomobject] -or (($c.origin.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'x,y,z'){throw 'Invalid gameplay camera collision snapshot.'}
        foreach($axis in @('x','y','z')){if(-not(Test-GameplayHostNumber $c.origin.$axis) -or [Math]::Abs($c.origin.$axis) -ge 10000000 -or
            -not $Identity.PSObject.Properties['CameraOrigin'] -or -not(Test-GameplayHostNumber $Identity.CameraOrigin.$axis) -or
            $c.origin.$axis -ne $Identity.CameraOrigin.$axis){throw 'Invalid camera collision origin.'}}
        for($offset=0;$offset -lt $c.boxes.Length;$offset+=24){
            $q=@(for($i=0;$i -lt 6;$i++){$n=[Convert]::ToInt32($c.boxes.Substring($offset+$i*4,4),16);if($n -ge 32768){$n-=65536};$n})
            for($i=0;$i -lt 3;$i++){if($q[$i] -ge $q[$i+3] -or $q[$i+3]-$q[$i] -gt 32){throw 'Invalid camera collision box.'}}
        }
    }
    if($p.seq -lt 1 -or $p.seq -gt 10000000 -or $p.seq -ne [Math]::Floor($p.seq) -or $p.utc_ms -le 0 -or $p.utc_ms -ne [Math]::Floor($p.utc_ms) -or $p.utc_ms -gt $Now+50 -or $p.source_ms -lt 0 -or $p.source_ms -gt 86400000){throw 'Gameplay pose clock/sequence differs.'}
    if($p.position -isnot [pscustomobject] -or (($p.position.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'x,y,z'){throw 'Gameplay position differs.'}
    foreach($axis in @('x','y','z')){if(-not(Test-GameplayHostNumber $p.position.$axis)){throw 'Gameplay position is not finite.'}}
    if($p.position.x -lt $Bounds.MinX -or $p.position.x -gt $Bounds.MaxX -or $p.position.y -lt $Bounds.MinY -or $p.position.y -gt $Bounds.MaxY -or $p.position.z -lt $Bounds.MinZ -or $p.position.z -gt $Bounds.MaxZ){throw 'Gameplay pose leaves captured coverage.'}
    if($p.seq -lt $LastSequence -or ($p.seq -gt $LastSequence -and $p.source_ms -le $LastSource)){throw 'Gameplay pose sequence/source clock regressed.'}
    if($p.seq -eq $LastSequence -or $Now-$p.utc_ms -gt 250){return $null}
    return $p
}
function New-GameplayRespawnHostState {
    return [pscustomobject]@{Epoch=0L;Phase='alive';From=$null;Target=$null;FirstSequence=0L;LastSequence=0L;StartedUtc=0L;Acked=$false}
}
function Test-GameplayRespawnPoint($A,$B){
    foreach($axis in @('x','y','z')){if($null -eq $A -or $null -eq $B -or -not(Test-GameplayHostNumber $A.$axis) -or -not(Test-GameplayHostNumber $B.$axis) -or $A.$axis -ne $B.$axis){return $false}}
    return $true
}
function Test-GameplayRespawnNativePoint($Observed,$Requested){
    # KCD's Lua/native vector handoff rounds to float32. Accept only the exact
    # requested number or its exact float representation, never a distance
    # tolerance that could acknowledge another requested target.
    foreach($axis in @('x','y','z')){
        if($null -eq $Observed -or $null -eq $Requested -or -not(Test-GameplayHostNumber $Observed.$axis) -or -not(Test-GameplayHostNumber $Requested.$axis) -or
           ($Observed.$axis -ne $Requested.$axis -and $Observed.$axis -ne [double][single]$Requested.$axis)){return $false}
    }
    return $true
}
function Get-GameplayRespawnCoverage($Patch){
    $data=Get-Content -LiteralPath $Patch.Path -Raw|ConvertFrom-Json -Depth 16
    $tiles=if($data.PSObject.Properties['tiles']){@($data.tiles|ForEach-Object {$_.json|ConvertFrom-Json -Depth 12})}else{@($data)}
    foreach($tile in $tiles){
        $n=[int]$tile.grid_size;$step=[double]$tile.spacing
        if($n -lt 2 -or $n -gt 129 -or $step -le 0 -or $step -gt 4 -or @($tile.points).Count -ne $n*$n){throw 'Respawn capture grid differs.'}
        $valid=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$x=[double]$tile.points[0].x;$y=[double]$tile.points[0].y
        for($row=0;$row -lt $n-1;$row++){for($col=0;$col -lt $n-1;$col++){
            $complete=$true
            foreach($dy in @(0,1)){foreach($dx in @(0,1)){
                $p=$tile.points[($row+$dy)*$n+$col+$dx]
                if($p.valid -isnot [bool] -or -not $p.valid -or -not(Test-GameplayHostNumber $p.x) -or -not(Test-GameplayHostNumber $p.y) -or -not(Test-GameplayHostNumber $p.z) -or -not(Test-GameplayTerrainCoordinate $p.x ($x+($col+$dx)*$step)) -or -not(Test-GameplayTerrainCoordinate $p.y ($y+($row+$dy)*$step))){$complete=$false}
            }}
            if($complete){[void]$valid.Add("$col,$row")}
        }}
        [pscustomobject]@{X=$x;Y=$y;Step=$step;Size=$n-1;Valid=$valid}
    }
}
function Test-GameplayRespawnCoverage($Coverage,$Position){
    # Conservative non-streaming path: the complete player footprint must fit
    # one captured grid and every touched cell must have four captured corners.
    # Explore uses its durable acknowledged tile coverage check instead.
    foreach($tile in $Coverage){
        $x0=($Position.x-.31-$tile.X)/$tile.Step;$x1=($Position.x+.31-$tile.X)/$tile.Step
        $y0=($Position.y-.31-$tile.Y)/$tile.Step;$y1=($Position.y+.31-$tile.Y)/$tile.Step
        if($x0 -lt 0 -or $y0 -lt 0 -or $x1 -gt $tile.Size -or $y1 -gt $tile.Size){continue}
        $covered=$true
        for($row=[int][Math]::Floor($y0);$row -lt [Math]::Ceiling($y1);$row++){for($col=[int][Math]::Floor($x0);$col -lt [Math]::Ceiling($x1);$col++){if(-not $tile.Valid.Contains("$col,$row")){$covered=$false}}}
        if($covered){return $true}
    }
    return $false
}
function Update-GameplayRespawnHostPose($State,$Pose,[long]$Now){
    $phase=if($Pose.PSObject.Properties['lifecycle']){[string]$Pose.lifecycle}else{'alive'}
    if($phase -ceq 'alive'){
        if($State.Phase -cne 'alive' -and ($State.Phase -cne 'respawn' -or -not $State.Acked)){throw 'Gameplay resumed before acknowledged respawn.'}
        $State.Phase='alive';return
    }
    $epoch=[long]$Pose.respawn_epoch
    if($phase -ceq 'dead' -and ($State.Phase -ceq 'alive' -or ($State.Phase -ceq 'respawn' -and $State.Acked))){
        if($epoch -le $State.Epoch){throw 'Gameplay death epoch replayed.'}
        $State.Epoch=$epoch;$State.Phase='dead';$State.From=$Pose.position;$State.Target=$Pose.position;$State.FirstSequence=[long]$Pose.seq;$State.StartedUtc=$Now;$State.Acked=$false
    }elseif($epoch -ne $State.Epoch){throw 'Gameplay respawn epoch differs.'}
    elseif($phase -ceq 'respawn' -and $State.Phase -ceq 'dead'){
        if(-not $State.Acked -or -not(Test-GameplayRespawnPoint $Pose.respawn_from $State.From)){throw 'Gameplay respawn lacks an acknowledged frozen origin.'}
        $State.Phase='respawn';$State.Target=$Pose.position;$State.FirstSequence=[long]$Pose.seq;$State.StartedUtc=$Now;$State.Acked=$false
    }elseif($phase -cne $State.Phase -or -not(Test-GameplayRespawnPoint $Pose.position $State.Target) -or ($phase -ceq 'respawn' -and -not(Test-GameplayRespawnPoint $Pose.respawn_from $State.From))){throw 'Gameplay lifecycle target changed or replayed.'}
    $State.LastSequence=[long]$Pose.seq
    if($State.Phase -ceq 'respawn' -and -not $State.Acked -and $Now-$State.StartedUtc -gt 2000){throw 'Gameplay respawn acknowledgement expired.'}
}
function Accept-GameplayRespawnReceipt($State,$Receipt,$Identity,[long]$Now){
    if($State.Phase -ceq 'alive' -or $State.Acked -or -not(Test-GameplayHostNumber $Receipt.schema) -or $Receipt.schema -ne 1 -or $Receipt.run -cne $Identity.Run -or $Receipt.event -cne 'lifecycle' -or $Receipt.result -cne 'applied' -or $Receipt.active -isnot [bool] -or -not $Receipt.active -or
       $Receipt.lifecycle -cne $State.Phase -or -not(Test-GameplayHostNumber $Receipt.respawn_epoch) -or $Receipt.respawn_epoch -ne $State.Epoch -or -not(Test-GameplayHostNumber $Receipt.seq) -or $Receipt.seq -lt $State.FirstSequence -or $Receipt.seq -gt $State.LastSequence -or $Receipt.seq -ne [Math]::Floor($Receipt.seq) -or
       -not(Test-GameplayHostNumber $Receipt.applied_seq) -or $Receipt.applied_seq -ne $Receipt.seq -or -not(Test-GameplayHostNumber $Receipt.pose_seq) -or $Receipt.pose_seq -ne $Receipt.seq -or
       -not(Test-GameplayRespawnNativePoint $Receipt.from $State.From) -or -not(Test-GameplayRespawnNativePoint $Receipt.target $State.Target) -or ($State.Phase -ceq 'respawn' -and $Now-$State.StartedUtc -gt 2000)){throw 'Native gameplay lifecycle acknowledgement differs or replayed.'}
    if(-not(Test-GameplayRespawnNativePoint $Receipt.player $State.Target)){throw 'Native respawn position was not verified.'}
    $State.Acked=$true
    return [ordered]@{schema=1;kind='minecome_gameplay_respawn_ack_v1';run=$Identity.Run;world_id=$Identity.WorldId;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;lifecycle=$State.Phase;respawn_epoch=$State.Epoch;from=$State.From;target=$State.Target;utc_ms=$Now}
}
function Get-GameplayMovementWorker {
    return {
        param($Context,$Identity,$Bounds,[string]$PoseFile,[string]$ViewFile,[long]$ExpiresUtcMs,[long]$LogOffset,$Shared,$Token,[string]$ProjectRoot,$BlocksState,$TerrainState,[bool]$Flight=$false,[bool]$WorldBlocks=$false,$CombatState=$null)
        $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
        . (Join-Path $ProjectRoot 'scripts/GameplayMovementHost.ps1')
        $run=$Identity.Run;$stopwatch=[Diagnostics.Stopwatch]::StartNew();$limit=$ExpiresUtcMs-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $log=$null;$position=$LogOffset;$lastLength=$LogOffset;$begin=$null;$terminal=$null;$latestView=$null
        $sequence=0L;$source=-1.0;$viewSequence=0L;$views=0L;$poses=0L;$lastPoseUtc=0L;$lastPoseAt=0.0;$lastViewAt=-1000.0;$failure=$null;$started=$false;$stage='starting'
        $requestCount=0L;$maxRequestPathLength=0;$lastDispatch=$null
        $viewTiming=[ordered]@{Count=0L;MaxDispatchMs=0.0;MaxAckAgeMs=0L;MaxPublicationMs=0L;Samples=[Collections.Generic.Queue[object]]::new()}
        $pendingViewTiming=$null;$pendingViewRequest=$null;$viewHttpCompletedUtc=0L;$viewHttpElapsedMs=0.0
        $cameraGeometry=$null;$cameraGeometryText=$null;$cameraGeometryNext=1;$cameraGeometryChunks=0
        $temp=$ViewFile+'.'+$run+'.tmp'
        $aimFile=Join-Path (Split-Path -Parent $ViewFile) 'gameplay-aim.json';$aimTemp=$aimFile+'.'+$run+'.tmp'
        $respawnFile=Join-Path (Split-Path -Parent $PoseFile) 'respawn-ack.json';$respawnTemp=$respawnFile+'.'+$run+'.tmp';$respawnState=New-GameplayRespawnHostState
        function Publish([bool]$Stopped=$false){$Shared['Snapshot']=[pscustomobject]@{Stopped=$Stopped;Failure=$failure;Stage=$stage;PoseCount=$poses;ViewCount=$views;LastPoseSequence=$sequence;LastPoseUtcMs=$lastPoseUtc;RequestCount=$requestCount;MaxRequestPathLength=$maxRequestPathLength;LastDispatch=$lastDispatch;ViewTiming=$viewTiming;Begin=$begin;Terminal=$terminal;LastView=$latestView;Blocks=$(if($BlocksState){Get-GameplayBlocksHostState $BlocksState}else{$null});Terrain=$(if($TerrainState){Get-GameplayTerrainHostState $TerrainState}else{$null});Combat=$(if($CombatState){Get-GameplayCombatHostState $CombatState}else{$null})}}
        function Numeric($v){([double]$v).ToString('R',[Globalization.CultureInfo]::InvariantCulture)}
        function New-ViewTiming {return [ordered]@{FirstLogBytesUtcMs=0L;ViewReceiptParsedUtcMs=0L;ReceiptReadCalls=0L;ReceiptReadBytes=0L;ReceiptReadMs=0.0;ReceiptParseCount=0L;ReceiptParseMs=0.0}}
        function Capture-ViewRequest([long]$LoopUtc,[double]$DispatchMs){
            if($null -eq $requestedUtc){throw 'Native gameplay sample was not dispatched.'}
            $at=$stopwatch.Elapsed.TotalMilliseconds
            return [pscustomobject]@{Sequence=$viewSequence;LoopStartedUtcMs=$LoopUtc;RequestedUtcMs=$requestedUtc;DispatchMs=$DispatchMs;ViewHttpCompletedUtcMs=$viewHttpCompletedUtc;ViewHttpElapsedMs=$viewHttpElapsedMs;Timing=$pendingViewTiming;DeadlineAt=$at+300;LastFlushAt=$at}
        }
        function Publish-Aim($Receipt,$Request){
            if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$Request.RequestedUtcMs -gt 250){return 0L}
            $aim=[ordered]@{schema=1;kind='minecome_gameplay_aim_v1';run=$run;world_id=$Identity.WorldId;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;seq=$Request.Sequence;utc_ms=$Request.RequestedUtcMs;origin=$Receipt.camera;direction=$Receipt.forward;range=$Receipt.aim.range;known=$Receipt.aim.known;distance=$Receipt.aim.distance;terrain_hit=$Receipt.aim.terrain_hit}
            if($WorldBlocks){
                $aim.schema=3;$aim.kind='minecome_gameplay_aim_v3';$aim.origin=$Receipt.eye;$aim.direction=$Receipt.aim_direction
                $aim.camera_origin=$Receipt.camera;$aim.camera_direction=$Receipt.camera_forward;$aim.camera_up=$Receipt.camera_up;$aim.vertical_fov=$Receipt.fov;$aim.perspective=$Receipt.perspective
            }
            [IO.File]::WriteAllText($aimTemp,($aim|ConvertTo-Json -Depth 5 -Compress),[Text.UTF8Encoding]::new($false))
            if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$Request.RequestedUtcMs -gt 250){[IO.File]::Delete($aimTemp);return 0L}
            Publish-GameplayMovementView $aimTemp $aimFile
            return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        }
        function Send([string[]]$Bodies,[string]$ViewCall=''){
            $requests=@(ConvertTo-GameplayMovementRequests $run $Bodies)
            foreach($request in $requests){
                Assert-MineComeProbeContext $Context
                Set-Variable -Name requestCount -Value ($requestCount+1) -Scope 1
                Set-Variable -Name maxRequestPathLength -Value ([Math]::Max($maxRequestPathLength,$request.PathAndQuery.Length)) -Scope 1
                if($stage -ne 'stopping'){Set-Variable -Name lastDispatch -Value ([pscustomobject]@{UtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();EncodedPathLength=$request.PathAndQuery.Length;Command=$request.Command}) -Scope 1}
                # Timestamp this new sample at its actual dispatch boundary, not
                # before file parsing, identity checks or earlier split batches.
                # Lua has not executed it yet, so this remains a conservative
                # lower bound. Flushes/old ACKs never renew the timestamp.
                if($ViewCall -and $request.Command.Contains($ViewCall)){
                    Set-Variable -Name requestedUtc -Value ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Scope 1
                }
                $httpStartedAt=$stopwatch.Elapsed.TotalMilliseconds
                Invoke-MineComeToolsRequest -PathAndQuery $request.PathAndQuery -TimeoutMilliseconds 150|Out-Null
                if($ViewCall -and $request.Command.Contains($ViewCall)){
                    Set-Variable -Name viewHttpCompletedUtc -Value ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Scope 1
                    Set-Variable -Name viewHttpElapsedMs -Value ($stopwatch.Elapsed.TotalMilliseconds-$httpStartedAt) -Scope 1
                }
            }
        }
        function Receipts {
            $readAt=$stopwatch.Elapsed.TotalMilliseconds
            $length=$log.Length
            if($length -lt $lastLength -or $length-$position -gt 2MB){throw 'Gameplay game-log identity/unread bound changed.'}
            if($pendingViewTiming){
                $pendingViewTiming.ReceiptReadCalls++
                if($length -gt $position -and $pendingViewTiming.FirstLogBytesUtcMs -eq 0){$pendingViewTiming.FirstLogBytesUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
            }
            $log.Position=$position;$bytes=[byte[]]::new([int]($length-$position));$offset=0
            while($offset -lt $bytes.Length){$n=$log.Read($bytes,$offset,$bytes.Length-$offset);if($n -eq 0){throw 'Gameplay log shrank.'};$offset+=$n}
            $parseAt=$stopwatch.Elapsed.TotalMilliseconds
            if($pendingViewTiming){$pendingViewTiming.ReceiptReadMs+=$parseAt-$readAt;$pendingViewTiming.ReceiptReadBytes+=$bytes.Length}
            $lf=[Array]::LastIndexOf($bytes,[byte]10)
            $result=[Collections.Generic.List[object]]::new()
            if($lf -ge 0){
                $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes,0,$lf+1)
                foreach($m in [regex]::Matches($text,'\[MineComeGameplay(Movement|Blocks|Terrain|Combat)\] (\{[^\r\n]*\})\r?\n')){
                    if($m.Groups[2].Length -gt 4096){throw 'Gameplay native receipt exceeded bound.'}
                    $r=$m.Groups[2].Value|ConvertFrom-Json -Depth 6
                    if($pendingViewTiming){
                        $pendingViewTiming.ReceiptParseCount++
                        if($m.Groups[1].Value -ceq 'Movement' -and $r.run -ceq $run -and $r.event -ceq 'view' -and $r.seq -eq $viewSequence){$pendingViewTiming.ViewReceiptParsedUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
                    }
                    if($r.schema -ne 1 -or $r.run -cne $run){continue}
                    if($m.Groups[1].Value -ceq 'Blocks'){if($BlocksState){Accept-GameplayBlocksReceipt $BlocksState $r};continue}
                    if($m.Groups[1].Value -ceq 'Terrain'){if($TerrainState){Accept-GameplayTerrainReceipt $TerrainState $r ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())};continue}
                    if($m.Groups[1].Value -ceq 'Combat'){if($CombatState){Accept-GameplayCombatReceipt $CombatState $r ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())};continue}
                    $result.Add($r)
                }
                Set-Variable -Name position -Value ($position+$lf+1) -Scope 1
            }
            Set-Variable -Name lastLength -Value $length -Scope 1
            if($pendingViewTiming){$pendingViewTiming.ReceiptParseMs+=$stopwatch.Elapsed.TotalMilliseconds-$parseAt}
            return $result.ToArray()
        }
        function RejectWrapper([string]$Call){
            "local ok,why=$Call;if ok==false then if type(why)~='string' or not why:match('^[a-z_]+$') then why='invalid_reason' end;System.LogAlways('[MineComeGameplayMovement] {`"schema`":1,`"run`":`"$run`",`"event`":`"rejected`",`"result`":`"'..why..'`"}') end"
        }
        try{
            $log=[IO.FileStream]::new($Context.GameLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete),1,[IO.FileOptions]::None)
            $remaining=[Math]::Min(86400000,$limit)
            $started=$true
            $flightArgument=if($WorldBlocks){',true,true'}elseif($Flight){',true'}else{''}
            Send (RejectWrapper "MineCome.GameplayMovementBegin('$run',$remaining,$(Numeric $Bounds.MinX),$(Numeric $Bounds.MaxX),$(Numeric $Bounds.MinY),$(Numeric $Bounds.MaxY),$(Numeric $Bounds.MinZ),$(Numeric $Bounds.MaxZ)$flightArgument)")
            $until=$stopwatch.Elapsed.TotalMilliseconds+1000
            do{foreach($r in @(Receipts)){if($r.event -ceq 'begin'){$begin=$r}elseif($r.event -in @('rejected','terminal')){throw "Native gameplay begin rejected: $($r.result)"}};if($begin){break};Start-Sleep -Milliseconds 5}while($stopwatch.Elapsed.TotalMilliseconds -lt $until)
            if(-not $begin -or $begin.result -cne 'ready' -or -not $begin.active){throw 'No native gameplay begin acknowledgement.'}
            $stage='running';Publish
            while(-not $Token.IsCancellationRequested){
                $utc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$elapsed=$stopwatch.Elapsed.TotalMilliseconds
                if($utc -ge $ExpiresUtcMs -or $elapsed -ge $limit){throw 'Gameplay host identity expired.'}
                $pose=Read-GameplayMovementPose $PoseFile $Identity $Bounds $sequence $source $utc $WorldBlocks
                $parts=[Collections.Generic.List[string]]::new()
                if($WorldBlocks -and $pose){
                    $collision=$pose.camera_collision;$text=$collision|ConvertTo-Json -Depth 4 -Compress
                    if($cameraGeometry -and ($collision.generation -lt $cameraGeometry.generation -or ($collision.generation -eq $cameraGeometry.generation -and $text -cne $cameraGeometryText))){throw 'Gameplay camera collision generation regressed or changed.'}
                    if(-not $cameraGeometry -or $collision.generation -gt $cameraGeometry.generation){
                        $cameraGeometry=$collision;$cameraGeometryText=$text;$cameraGeometryNext=1
                        $cameraGeometryChunks=[int][Math]::Max(1,[Math]::Ceiling($collision.boxes.Length/768.0))
                    }
                }
                if($WorldBlocks -and $cameraGeometry -and $cameraGeometryNext -le $cameraGeometryChunks){
                    $offset=($cameraGeometryNext-1)*768;$count=[Math]::Min(768,$cameraGeometry.boxes.Length-$offset)
                    $packed=$cameraGeometry.boxes.Substring($offset,$count);$complete=([string]$cameraGeometry.complete).ToLowerInvariant();$origin=$cameraGeometry.origin
                    $parts.Add((RejectWrapper "MineCome.GameplayCameraGeometry('$run',$($cameraGeometry.generation),$cameraGeometryNext,$cameraGeometryChunks,$(Numeric $origin.x),$(Numeric $origin.y),$(Numeric $origin.z),$complete,'$packed')"))
                    $cameraGeometryNext++
                }
                # Consume durable terrain acknowledgements before admitting any
                # pose or block snapshot that uses newly installed collision.
                if($TerrainState){$command=Get-GameplayTerrainCommands $TerrainState $utc $pose;if($command){$parts.Add((RejectWrapper $command))}}
                if($pose -and $TerrainState -and -not(Test-GameplayTerrainPose $TerrainState $pose)){throw 'Gameplay pose leaves acknowledged terrain.'}
                if($pose -and $pose.PSObject.Properties['lifecycle'] -and $pose.lifecycle -ceq 'respawn' -and -not $TerrainState -and
                   (-not $Identity.PSObject.Properties['RespawnCoverage'] -or -not(Test-GameplayRespawnCoverage $Identity.RespawnCoverage $pose.position))){throw 'Gameplay respawn leaves captured cells.'}
                if($pose){Update-GameplayRespawnHostPose $respawnState $pose $utc}
                if($BlocksState){$command=Get-GameplayBlocksCommands $BlocksState $utc;if($command){$parts.Add((RejectWrapper $command))}}
                if($CombatState){$command=Get-GameplayCombatCommands $CombatState $utc;if($command){$parts.Add((RejectWrapper $command))}}
                if($pose){
                    $perspectiveArgument=if($WorldBlocks){','+[string]$pose.perspective_request+','+[string]$pose.camera_collision.generation}else{''}
                    if($pose.PSObject.Properties['lifecycle']){
                        $perspectiveArgument+=",'$($pose.lifecycle)',$($pose.respawn_epoch)"
                        if($pose.lifecycle -ceq 'respawn'){$perspectiveArgument+=",$(Numeric $pose.respawn_from.x),$(Numeric $pose.respawn_from.y),$(Numeric $pose.respawn_from.z)"}
                    }
                    $parts.Add((RejectWrapper "MineCome.GameplayMovementPose('$run',$($pose.seq),$(Numeric $pose.source_ms),$(Numeric $pose.position.x),$(Numeric $pose.position.y),$(Numeric $pose.position.z)$perspectiveArgument)"))
                }
                $startView=$null -eq $pendingViewRequest -and $elapsed-$lastViewAt -ge 40
                $viewCall=''
                if($startView){
                    $viewSequence++;$requestedUtc=$null;$viewHttpCompletedUtc=0L;$viewHttpElapsedMs=0.0
                    # Timing observations never participate in expiry/authority.
                    # FirstLogBytes can precede this ACK (for example pose logs);
                    # ViewReceiptParsed identifies the matching sequence exactly.
                    $pendingViewTiming=New-ViewTiming
                    $aimArgument=if($BlocksState -or $WorldBlocks){',true'}else{''};$viewCall="MineCome.GameplayMovementSample('$run',$viewSequence$aimArgument)";$parts.Add((RejectWrapper $viewCall));$lastViewAt=$elapsed
                }
                $dispatchAt=$stopwatch.Elapsed.TotalMilliseconds
                if($parts.Count){Send $parts.ToArray() $viewCall;if($pose){$sequence=[long]$pose.seq;$source=[double]$pose.source_ms;$poses++;$lastPoseUtc=[long]$pose.utc_ms;$lastPoseAt=$elapsed}}
                $dispatchMs=$stopwatch.Elapsed.TotalMilliseconds-$dispatchAt
                if($startView){$pendingViewRequest=Capture-ViewRequest $utc $dispatchMs}
                if($poses -gt 0 -and $elapsed-$lastPoseAt -gt 350){throw 'Gameplay guest pose expired.'}
                $requestView=$null -ne $pendingViewRequest
                $until=if($requestView){$pendingViewRequest.DeadlineAt}else{$stopwatch.Elapsed.TotalMilliseconds}
                do{
                    if($requestView -and -not $Token.IsCancellationRequested -and $stopwatch.Elapsed.TotalMilliseconds -ge $until){throw 'Native gameplay camera acknowledgement expired.'}
                    foreach($r in @(Receipts)){
                        if($r.event -ceq 'terminal'){$terminal=$r;throw "Native gameplay stopped: $($r.result)"}
                        if($r.event -ceq 'rejected'){throw "Native gameplay request rejected: $($r.result)"}
                        if($r.event -ceq 'lifecycle'){
                            $ack=Accept-GameplayRespawnReceipt $respawnState $r $Identity ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
                            [IO.File]::WriteAllText($respawnTemp,($ack|ConvertTo-Json -Depth 5 -Compress),[Text.UTF8Encoding]::new($false));Publish-GameplayMovementView $respawnTemp $respawnFile
                        }
                        if($r.event -ceq 'view'){
                            if(-not $requestView -or $r.seq -ne $pendingViewRequest.Sequence -or $r.result -cne 'sampled' -or -not $r.active -or -not $r.camera_basis_valid){throw 'Native gameplay view acknowledgement differs.'}
                            if($stopwatch.Elapsed.TotalMilliseconds -ge $pendingViewRequest.DeadlineAt){throw 'Native gameplay camera acknowledgement expired.'}
                            if($WorldBlocks){
                                if(-not(Test-GameplayHostNumber $r.fov) -or $r.fov -le .05 -or $r.fov -ge ([Math]::PI-.05)){throw 'World block camera FOV unavailable.'}
                                if($r.perspective -notin @(0,1,2)){throw 'Native gameplay perspective missing.'}
                            }
                            $latestView=$r
                            $accepted=$pendingViewRequest;$ackUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                            $pendingViewRequest=$null;$pendingViewTiming=$null;$requestView=$false
                            # Renderer/depth freshness is the critical path:
                            # expose the validated native camera before either
                            # another HTTP dispatch or legacy movement-view I/O.
                            $aimPublicationUtc=0L;$viewPublicationUtc=0L
                            if($WorldBlocks){$aimPublicationUtc=Publish-Aim $r $accepted}
                            # Only one native query may be outstanding. Once its
                            # real ACK is validated, overlap the next query's
                            # native/log wait with publication of this old ACK.
                            # Process the next ACK only after the outer pose and
                            # cancellation pass; never create an inner view chain.
                            $prefetchAt=$stopwatch.Elapsed.TotalMilliseconds;$prefetchUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                            if($WorldBlocks -and -not $Token.IsCancellationRequested -and $prefetchUtc -lt $ExpiresUtcMs -and $prefetchAt -lt $limit -and $prefetchAt-$lastViewAt -ge 40){
                                $viewSequence++;$requestedUtc=$null;$viewHttpCompletedUtc=0L;$viewHttpElapsedMs=0.0;$pendingViewTiming=New-ViewTiming
                                $nextCall="MineCome.GameplayMovementSample('$run',$viewSequence,true)";$lastViewAt=$prefetchAt
                                Send (RejectWrapper $nextCall) $nextCall
                                $pendingViewRequest=Capture-ViewRequest $prefetchUtc ($stopwatch.Elapsed.TotalMilliseconds-$prefetchAt)
                            }
                            # Prefetch dispatch may be slow: recheck the saved
                            # original timestamp instead of renewing its lease.
                            $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$published=$now-$accepted.RequestedUtcMs -le 250
                            if($published){
                                $value=[ordered]@{schema=1;source_kind='live_kcd_hud_view_v1';run=$run;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;seq=$accepted.Sequence;utc_ms=$accepted.RequestedUtcMs;forward=$r.forward;up=$r.up}
                                $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($value|ConvertTo-Json -Depth 5 -Compress))
                                $f=[IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                                try{$f.Write($bytes);$f.Flush($false)}finally{$f.Dispose()}
                                $published=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$accepted.RequestedUtcMs -le 250
                                if($published){
                                    Publish-GameplayMovementView $temp $ViewFile;$viewPublicationUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                                    if($BlocksState -and -not $WorldBlocks){$aimPublicationUtc=Publish-Aim $r $accepted}
                                    $views++
                                }else{
                                    [IO.File]::Delete($temp)
                                }
                            }
                            $publishedUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                            $viewTiming.Count++;$viewTiming.MaxDispatchMs=[Math]::Max($viewTiming.MaxDispatchMs,$accepted.DispatchMs)
                            $viewTiming.MaxAckAgeMs=[Math]::Max($viewTiming.MaxAckAgeMs,$ackUtc-$accepted.RequestedUtcMs)
                            $viewTiming.MaxPublicationMs=[Math]::Max($viewTiming.MaxPublicationMs,$publishedUtc-$ackUtc)
                            if($viewTiming.Samples.Count -ge 64){$null=$viewTiming.Samples.Dequeue()}
                            $timing=$accepted.Timing
                            $viewTiming.Samples.Enqueue([pscustomobject]@{Sequence=$accepted.Sequence;LoopStartedUtcMs=$accepted.LoopStartedUtcMs;RequestedUtcMs=$accepted.RequestedUtcMs;DispatchMs=$accepted.DispatchMs;ViewHttpCompletedUtcMs=$accepted.ViewHttpCompletedUtcMs;ViewHttpElapsedMs=$accepted.ViewHttpElapsedMs;
                                FirstLogBytesUtcMs=$timing.FirstLogBytesUtcMs;ViewReceiptParsedUtcMs=$timing.ViewReceiptParsedUtcMs;ReceiptReadCalls=$timing.ReceiptReadCalls;ReceiptReadBytes=$timing.ReceiptReadBytes;ReceiptReadMs=$timing.ReceiptReadMs;ReceiptParseCount=$timing.ReceiptParseCount;ReceiptParseMs=$timing.ReceiptParseMs;
                                AckUtcMs=$ackUtc;AimPublicationUtcMs=$aimPublicationUtc;AimPublished=($aimPublicationUtc -gt 0);ViewPublicationUtcMs=$viewPublicationUtc;PublicationUtcMs=$publishedUtc;Published=$published})
                        }
                    }
                    if(-not $requestView){break}
                    # Perspective reset/readback can acknowledge from a later
                    # engine timer, after the original console flush. Delimit
                    # that buffered line without resampling, renewing its UTC
                    # or extending the existing acknowledgement deadline.
                    if(-not $Token.IsCancellationRequested -and $stopwatch.Elapsed.TotalMilliseconds-$pendingViewRequest.LastFlushAt -ge 15){
                        Send "System.LogAlways('[MineComeGameplayViewFlush] $run')"
                        $pendingViewRequest.LastFlushAt=$stopwatch.Elapsed.TotalMilliseconds
                    }
                    Start-Sleep -Milliseconds 5
                }while($stopwatch.Elapsed.TotalMilliseconds -lt $until -and -not $Token.IsCancellationRequested)
                if($requestView -and -not $Token.IsCancellationRequested){throw 'Native gameplay camera acknowledgement expired.'}
                Publish
                # A prefetched camera query already has its original deadline.
                # Return through the outer pose/cancellation pass immediately;
                # its pending-receipt loop retains the bounded 5ms polling wait.
                # Keep the idle wait when no query is outstanding.
                if($null -eq $pendingViewRequest){Start-Sleep -Milliseconds 10}
            }
        }catch{$failure=$_.Exception.Message}
        finally{
            $stage='stopping'
            if($started){
                $blocksStarted=$BlocksState -and $BlocksState.BeginSent
                $terrainStarted=$TerrainState -and $TerrainState.BeginSent
                $combatStarted=$CombatState -and $CombatState.BeginSent
                # Each subsystem stops independently; combat must stop before its movement authority.
                if($combatStarted){try{Send (RejectWrapper (Get-GameplayCombatStopCommand $CombatState))}catch{if(-not $failure){$failure=$_.Exception.Message}}}
                # A failed block request must never skip the movement stop.
                if($blocksStarted){try{Send (RejectWrapper (Get-GameplayBlocksStopCommand $BlocksState))}catch{if(-not $failure){$failure=$_.Exception.Message}}}
                if($terrainStarted){try{Send (RejectWrapper (Get-GameplayTerrainStopCommand $TerrainState))}catch{if(-not $failure){$failure=$_.Exception.Message}}}
                try{Send (RejectWrapper "MineCome.GameplayMovementEnd('$run')")}catch{if(-not $failure){$failure=$_.Exception.Message}}
                try{
                # Owned block removal retries may take two seconds. Keep the
                # receipt reader alive through that full native cleanup lease.
                $until=$stopwatch.Elapsed.TotalMilliseconds+$(if($blocksStarted){2500}else{750})
                $lastCleanupFlush=$stopwatch.Elapsed.TotalMilliseconds
                do{
                    foreach($r in @(Receipts)){if($r.event -ceq 'terminal'){$terminal=$r}}
                    if($terminal -and (-not $blocksStarted -or $BlocksState.Terminal) -and (-not $terrainStarted -or $TerrainState.Terminal) -and (-not $combatStarted -or $CombatState.Terminal)){break}
                    # The timer emits block cleanup after End's synchronous
                    # flush. KCD can leave its latest line unterminated until
                    # the next log message; solicit that delimiter explicitly.
                    if($stopwatch.Elapsed.TotalMilliseconds-$lastCleanupFlush -ge 100){
                        try{Send "System.LogAlways('[MineComeGameplayCleanupFlush] $run')"}catch{if(-not $failure){$failure=$_.Exception.Message}}
                        $lastCleanupFlush=$stopwatch.Elapsed.TotalMilliseconds
                    }
                    Start-Sleep -Milliseconds 10
                }while($stopwatch.Elapsed.TotalMilliseconds -lt $until)
                if(-not $terminal -and -not $failure){$failure='Native gameplay terminal acknowledgement missing.'}
                if($terminal -and -not $failure){
                    if($terminal.result -cne 'explicit_stop' -or $terminal.active -isnot [bool] -or $terminal.active){$failure='Native gameplay cleanup acknowledgement differs: '+[string]$terminal.result}
                    elseif($WorldBlocks){
                        foreach($field in @('camera_override_changed','camera_restored','body_visible_baseline_owned','body_restore_dispatched','body_hidden')){
                            if(-not $terminal.PSObject.Properties[$field] -or $terminal.$field -isnot [bool]){$failure='Native gameplay camera/body cleanup proof missing.';break}
                        }
                        if(-not $failure -and $terminal.camera_override_changed -and -not $terminal.camera_restored){$failure='Native gameplay camera cleanup incomplete.'}
                        if(-not $failure -and $terminal.body_visible_baseline_owned -and (-not $terminal.body_restore_dispatched -or $terminal.body_hidden)){$failure='Native gameplay body cleanup incomplete.'}
                    }
                }
                if($combatStarted -and -not (Get-GameplayCombatHostState $CombatState).CleanupComplete -and -not $failure){$failure='Native combat cleanup incomplete.'}
                if($blocksStarted -and -not (Get-GameplayBlocksHostState $BlocksState).CleanupComplete -and -not $failure){$failure='Native block cleanup incomplete.'}
                if($terrainStarted -and -not (Get-GameplayTerrainHostState $TerrainState).CleanupComplete -and -not $failure){$failure='Native terrain cleanup incomplete.'}
            }catch{if(-not $failure){$failure=$_.Exception.Message}}}
            if($log){$log.Dispose()}
            if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
            if([IO.File]::Exists($aimTemp)){[IO.File]::Delete($aimTemp)}
            if([IO.File]::Exists($respawnTemp)){[IO.File]::Delete($respawnTemp)}
            $stage='stopped';Publish $true
        }
    }
}
function Start-GameplayMovementHost {
    param($Context,[string]$Run,[string]$WorldId,$Patch,[string]$PoseFile,[string]$ViewFile,[long]$ExpiresUtcMs,$Bounds,[switch]$Blocks,[switch]$Explore,[string]$TerrainCacheFile,[switch]$Flight,[switch]$WorldBlocks,[switch]$Combat,[ValidateRange(0,1)][int]$InitialTerrainRadius=0)
    if($Combat){$WorldBlocks=$true}
    if($Flight -or $WorldBlocks){$Blocks=$true}
    if($InitialTerrainRadius -gt 0 -and -not $Explore){throw 'Initial terrain capture requires Explore and its owned terrain cache.'}
    if($Explore){$Blocks=$true;if(-not $TerrainCacheFile){throw 'Explore requires the owned terrain cache path.'}}
    $root=$Context.ProjectRoot
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $WorldId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or $Patch.Run -cnotmatch '^[0-9a-f]{32}$' -or $Patch.Hash -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid gameplay host identity.'}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();if($ExpiresUtcMs-$now -lt 1000 -or $ExpiresUtcMs-$now -gt 86400000){throw 'Gameplay host expiry differs.'}
    $PoseFile=Resolve-HudMovementEvidencePath $PoseFile $root;$ViewFile=Resolve-HudMovementEvidencePath $ViewFile $root
    $respawnFile=Join-Path (Split-Path -Parent $PoseFile) 'respawn-ack.json'
    if([IO.File]::Exists($respawnFile) -or [IO.File]::Exists($respawnFile+'.'+$Run+'.tmp')){throw 'Gameplay host respawn path already exists.'}
    if([IO.File]::Exists($ViewFile) -or [IO.File]::Exists($ViewFile+'.'+$Run+'.tmp')){throw 'Gameplay host view path already exists.'}
    $aimFile=Join-Path (Split-Path -Parent $ViewFile) 'gameplay-aim.json'
    if($Blocks -and ([IO.File]::Exists($aimFile) -or [IO.File]::Exists($aimFile+'.'+$Run+'.tmp'))){throw 'Gameplay host aim path already exists.'}
    if((Get-FileHash -LiteralPath $Patch.Path).Hash -ine $Patch.Hash){throw 'Gameplay capture changed.'}
    if(-not $Bounds){$Bounds=Get-GameplayMovementBounds $Patch}
    if($Explore){$c=$Patch.Data.center;$Bounds=[pscustomobject]@{MinX=[double]$c.x-67.69;MaxX=[double]$c.x+67.69;MinY=[double]$c.y-67.69;MaxY=[double]$c.y+67.69;MinZ=[double]$c.z-9;MaxZ=[double]$c.z+19}}
    if($Blocks){$Bounds.MaxZ=[Math]::Max($Bounds.MaxZ,[double]$Patch.Data.center.z+19)}
    foreach($name in @('MinX','MaxX','MinY','MaxY','MinZ','MaxZ')){if(-not(Test-GameplayHostNumber $Bounds.$name)){throw 'Invalid gameplay coverage bounds.'}}
    $probe=New-MineComeProbeRun $Context 'gameplay-movement' (Join-Path $root 'kcd2/gameplay/movement_session.lua') 'GameplayMovementBegin'
    $evidenceDirectory=Split-Path -Parent $PoseFile
    $terrainState=if($Explore){New-GameplayTerrainHost -Context $Context -Run $Run -WorldId $WorldId -Patch $Patch -CacheFile $TerrainCacheFile -AdmissionFile (Join-Path $evidenceDirectory 'terrain-admission.json') -AckFile (Join-Path $evidenceDirectory 'terrain-ack.json') -ExpiresUtcMs $ExpiresUtcMs -InitialTerrainRadius $InitialTerrainRadius}else{$null}
    $blocksState=if($Blocks -and -not $WorldBlocks){New-GameplayBlocksHost -Context $Context -Run $Run -WorldId $WorldId -Patch $Patch -SnapshotFile (Join-Path $evidenceDirectory 'gameplay-blocks.json') -ExpiresUtcMs $ExpiresUtcMs -TerrainState $terrainState}else{$null}
    $identity=[pscustomobject]@{Run=$Run;WorldId=$WorldId;Pid=$Context.GamePid;Start=$Context.GameStartedUtc.ToFileTimeUtc().ToString();PatchRun=$Patch.Run;PatchHash=$Patch.Hash}
    $combatState=if($Combat){New-GameplayCombatHost -Context $Context -Identity $identity -Directory $evidenceDirectory -ExpiresUtcMs $ExpiresUtcMs}else{$null}
    if($combatState){Initialize-MineComeProbeRun $Context $combatState.Probe}
    if($WorldBlocks){$identity|Add-Member -NotePropertyName CameraOrigin -NotePropertyValue ([pscustomobject]@{x=[double]$Patch.Data.center.x;y=[double]$Patch.Data.center.y;z=[double]$Patch.Data.center.z-64.0})}
    if($WorldBlocks -and -not $Explore){$identity|Add-Member -NotePropertyName RespawnCoverage -NotePropertyValue @(Get-GameplayRespawnCoverage $Patch)}
    $shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new([StringComparer]::Ordinal)
    $shared['Snapshot']=[pscustomobject]@{Stopped=$false;Failure=$null;Stage='starting';PoseCount=0L;ViewCount=0L;LastPoseSequence=0L;LastPoseUtcMs=0L;RequestCount=0L;MaxRequestPathLength=0;LastDispatch=$null;ViewTiming=$null;Begin=$null;Terminal=$null;LastView=$null;Blocks=$null;Terrain=$null;Combat=$null}
    $cancellation=[Threading.CancellationTokenSource]::new();$runspace=[RunspaceFactory]::CreateRunspace();$pipeline=[PowerShell]::Create()
    try{
        $runspace.Open();$pipeline.Runspace=$runspace
        $null=$pipeline.AddScript((Get-GameplayMovementWorker).ToString()).AddArgument($Context).AddArgument($identity).AddArgument($Bounds).AddArgument($PoseFile).AddArgument($ViewFile).AddArgument($ExpiresUtcMs).AddArgument((Get-Item -LiteralPath $Context.GameLog).Length).AddArgument($shared).AddArgument($cancellation.Token).AddArgument($root).AddArgument($blocksState).AddArgument($terrainState).AddArgument([bool]$Flight).AddArgument([bool]$WorldBlocks).AddArgument($combatState)
        $async=$pipeline.BeginInvoke()
        return [pscustomobject]@{Runspace=$runspace;PowerShell=$pipeline;Async=$async;Shared=$shared;Cancellation=$cancellation;Probe=$probe;Final=$null;Disposed=$false;Bounds=$Bounds;Identity=$identity}
    }catch{$cancellation.Cancel();$pipeline.Dispose();$runspace.Dispose();$cancellation.Dispose();throw}
}
function Get-GameplayMovementHostState($Session){
    if($Session.Final){return $Session.Final};$snapshot=$Session.Shared['Snapshot']
    if($Session.Async.IsCompleted -and -not $snapshot.Stopped){throw 'Gameplay host worker ended without cleanup evidence.'}
    return $snapshot
}
function Stop-GameplayMovementHost($Session){
    if($Session.Final){return $Session.Final}
    $Session.Cancellation.Cancel()
    if(-not $Session.Async.AsyncWaitHandle.WaitOne(4000)){throw 'Gameplay host worker did not finish bounded cleanup.'}
    $errorText=$null;try{$null=$Session.PowerShell.EndInvoke($Session.Async)}catch{$errorText=$_.Exception.Message}
    $s=$Session.Shared['Snapshot'];if(-not $errorText -and $Session.PowerShell.Streams.Error.Count -gt 0){$errorText=[string]$Session.PowerShell.Streams.Error[0]}
    $Session.Final=[pscustomobject]@{Stopped=$s.Stopped;Failure=$(if($s.Failure){$s.Failure}else{$errorText});Stage=$s.Stage;PoseCount=$s.PoseCount;ViewCount=$s.ViewCount;LastPoseSequence=$s.LastPoseSequence;LastPoseUtcMs=$s.LastPoseUtcMs;RequestCount=$s.RequestCount;MaxRequestPathLength=$s.MaxRequestPathLength;LastDispatch=$s.LastDispatch;ViewTiming=$s.ViewTiming;Begin=$s.Begin;Terminal=$s.Terminal;LastView=$s.LastView;Blocks=$s.Blocks;Terrain=$s.Terrain;Combat=$s.Combat;ResourcesClosed=$true}
    $Session.PowerShell.Dispose();$Session.Runspace.Dispose();$Session.Cancellation.Dispose();$Session.Disposed=$true
    $Session.Final|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Session.Probe.Directory 'verification.json') -Encoding utf8NoBOM
    return $Session.Final
}
