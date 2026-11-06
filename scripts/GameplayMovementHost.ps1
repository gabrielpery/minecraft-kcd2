#Requires -Version 7.3
# Owned ongoing movement/view worker. The caller starts the exact tools process;
# this helper never starts a game or modifies persistent game settings.
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'GameplayBlocksHost.ps1')
. (Join-Path $PSScriptRoot 'GameplayTerrainHost.ps1')

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
function Read-GameplayMovementPose([string]$Path,$Identity,$Bounds,[long]$LastSequence,[double]$LastSource,[long]$Now){
    if(-not [IO.File]::Exists($Path)){return $null}
    $file=$null
    try{
        $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if($file.Length -lt 2 -or $file.Length -gt 4096){throw 'Gameplay pose exceeds4096 bytes.'}
        $bytes=[byte[]]::new([int]$file.Length);$file.ReadExactly($bytes)
        if($file.ReadByte() -ne -1){throw 'Gameplay pose changed size.'}
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        $document=[Text.Json.JsonDocument]::Parse($json)
        try{
            if($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'Gameplay pose must be an object.'}
            foreach($element in @($document.RootElement,$document.RootElement.GetProperty('position'))){
                if($element.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'Gameplay pose position must be an object.'}
                $names=@($element.EnumerateObject()|ForEach-Object {$_.Name})
                if(@($names|Select-Object -Unique).Count -ne $names.Count){throw 'Gameplay pose contains duplicate fields.'}
            }
        }finally{$document.Dispose()}
        $p=$json|ConvertFrom-Json -Depth 6
    }catch [IO.IOException]{if(($_.Exception.HResult -band 0xffff) -in @(2,3,32,33,303)){return $null};throw}
    finally{if($file){$file.Dispose()}}
    $keys=@('schema','kind','run','world_id','target_pid','target_start_filetime','patch_run','patch_sha256','seq','utc_ms','source_ms','position')
    if($p -isnot [pscustomobject] -or (($p.PSObject.Properties.Name|Sort-Object)-join ',') -cne (($keys|Sort-Object)-join ',') -or
        $p.schema -ne 1 -or $p.kind -cne 'minecome_gameplay_pose_v1' -or $p.run -cne $Identity.Run -or $p.world_id -cne $Identity.WorldId -or
        $p.target_pid -ne $Identity.Pid -or $p.target_start_filetime -cne $Identity.Start -or $p.patch_run -cne $Identity.PatchRun -or $p.patch_sha256 -cne $Identity.PatchHash){throw 'Gameplay pose identity differs.'}
    foreach($key in @('schema','target_pid','seq','utc_ms','source_ms')){if(-not(Test-GameplayHostNumber $p.$key)){throw "Invalid gameplay pose number: $key"}}
    if($p.target_start_filetime -isnot [string]){throw 'Gameplay target start must be a string.'}
    if($p.seq -lt 1 -or $p.seq -gt 10000000 -or $p.seq -ne [Math]::Floor($p.seq) -or $p.utc_ms -le 0 -or $p.utc_ms -ne [Math]::Floor($p.utc_ms) -or $p.utc_ms -gt $Now+50 -or $p.source_ms -lt 0 -or $p.source_ms -gt 86400000){throw 'Gameplay pose clock/sequence differs.'}
    if($p.position -isnot [pscustomobject] -or (($p.position.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'x,y,z'){throw 'Gameplay position differs.'}
    foreach($axis in @('x','y','z')){if(-not(Test-GameplayHostNumber $p.position.$axis)){throw 'Gameplay position is not finite.'}}
    if($p.position.x -lt $Bounds.MinX -or $p.position.x -gt $Bounds.MaxX -or $p.position.y -lt $Bounds.MinY -or $p.position.y -gt $Bounds.MaxY -or $p.position.z -lt $Bounds.MinZ -or $p.position.z -gt $Bounds.MaxZ){throw 'Gameplay pose leaves captured coverage.'}
    if($p.seq -lt $LastSequence -or ($p.seq -gt $LastSequence -and $p.source_ms -le $LastSource)){throw 'Gameplay pose sequence/source clock regressed.'}
    if($p.seq -eq $LastSequence -or $Now-$p.utc_ms -gt 250){return $null}
    return $p
}
function Get-GameplayMovementWorker {
    return {
        param($Context,$Identity,$Bounds,[string]$PoseFile,[string]$ViewFile,[long]$ExpiresUtcMs,[long]$LogOffset,$Shared,$Token,[string]$ProjectRoot,$BlocksState,$TerrainState,[bool]$Flight=$false,[bool]$WorldBlocks=$false)
        $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
        . (Join-Path $ProjectRoot 'scripts/GameplayMovementHost.ps1')
        $run=$Identity.Run;$stopwatch=[Diagnostics.Stopwatch]::StartNew();$limit=$ExpiresUtcMs-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $log=$null;$position=$LogOffset;$lastLength=$LogOffset;$begin=$null;$terminal=$null;$latestView=$null
        $sequence=0L;$source=-1.0;$viewSequence=0L;$views=0L;$poses=0L;$lastPoseUtc=0L;$lastPoseAt=0.0;$lastViewAt=-1000.0;$failure=$null;$started=$false;$stage='starting'
        $requestCount=0L;$maxRequestPathLength=0;$lastDispatch=$null
        $temp=$ViewFile+'.'+$run+'.tmp'
        $aimFile=Join-Path (Split-Path -Parent $ViewFile) 'gameplay-aim.json';$aimTemp=$aimFile+'.'+$run+'.tmp'
        function Publish([bool]$Stopped=$false){$Shared['Snapshot']=[pscustomobject]@{Stopped=$Stopped;Failure=$failure;Stage=$stage;PoseCount=$poses;ViewCount=$views;LastPoseSequence=$sequence;LastPoseUtcMs=$lastPoseUtc;RequestCount=$requestCount;MaxRequestPathLength=$maxRequestPathLength;LastDispatch=$lastDispatch;Begin=$begin;Terminal=$terminal;LastView=$latestView;Blocks=$(if($BlocksState){Get-GameplayBlocksHostState $BlocksState}else{$null});Terrain=$(if($TerrainState){Get-GameplayTerrainHostState $TerrainState}else{$null})}}
        function Numeric($v){([double]$v).ToString('R',[Globalization.CultureInfo]::InvariantCulture)}
        function Send([string[]]$Bodies){
            $requests=@(ConvertTo-GameplayMovementRequests $run $Bodies)
            foreach($request in $requests){
                Assert-MineComeProbeContext $Context
                Set-Variable -Name requestCount -Value ($requestCount+1) -Scope 1
                Set-Variable -Name maxRequestPathLength -Value ([Math]::Max($maxRequestPathLength,$request.PathAndQuery.Length)) -Scope 1
                if($stage -ne 'stopping'){Set-Variable -Name lastDispatch -Value ([pscustomobject]@{UtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();EncodedPathLength=$request.PathAndQuery.Length;Command=$request.Command}) -Scope 1}
                Invoke-MineComeToolsRequest -PathAndQuery $request.PathAndQuery -TimeoutMilliseconds 150|Out-Null
            }
        }
        function Receipts {
            $length=$log.Length
            if($length -lt $lastLength -or $length-$position -gt 2MB){throw 'Gameplay game-log identity/unread bound changed.'}
            $log.Position=$position;$bytes=[byte[]]::new([int]($length-$position));$offset=0
            while($offset -lt $bytes.Length){$n=$log.Read($bytes,$offset,$bytes.Length-$offset);if($n -eq 0){throw 'Gameplay log shrank.'};$offset+=$n}
            $lf=[Array]::LastIndexOf($bytes,[byte]10)
            $result=[Collections.Generic.List[object]]::new()
            if($lf -ge 0){
                $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes,0,$lf+1)
                foreach($m in [regex]::Matches($text,'\[MineComeGameplay(Movement|Blocks|Terrain)\] (\{[^\r\n]*\})\r?\n')){
                    if($m.Groups[2].Length -gt 4096){throw 'Gameplay native receipt exceeded bound.'}
                    $r=$m.Groups[2].Value|ConvertFrom-Json -Depth 6
                    if($r.schema -ne 1 -or $r.run -cne $run){continue}
                    if($m.Groups[1].Value -ceq 'Blocks'){if($BlocksState){Accept-GameplayBlocksReceipt $BlocksState $r};continue}
                    if($m.Groups[1].Value -ceq 'Terrain'){if($TerrainState){Accept-GameplayTerrainReceipt $TerrainState $r ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())};continue}
                    $result.Add($r)
                }
                Set-Variable -Name position -Value ($position+$lf+1) -Scope 1
            }
            Set-Variable -Name lastLength -Value $length -Scope 1
            return $result.ToArray()
        }
        function RejectWrapper([string]$Call){
            "local ok,why=$Call;if ok==false then if type(why)~='string' or not why:match('^[a-z_]+$') then why='invalid_reason' end;System.LogAlways('[MineComeGameplayMovement] {`"schema`":1,`"run`":`"$run`",`"event`":`"rejected`",`"result`":`"'..why..'`"}') end"
        }
        try{
            $log=[IO.FileStream]::new($Context.GameLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete),1,[IO.FileOptions]::None)
            $remaining=[Math]::Min(86400000,$limit)
            $started=$true
            $flightArgument=if($Flight){',true'}else{''}
            Send (RejectWrapper "MineCome.GameplayMovementBegin('$run',$remaining,$(Numeric $Bounds.MinX),$(Numeric $Bounds.MaxX),$(Numeric $Bounds.MinY),$(Numeric $Bounds.MaxY),$(Numeric $Bounds.MinZ),$(Numeric $Bounds.MaxZ)$flightArgument)")
            $until=$stopwatch.Elapsed.TotalMilliseconds+1000
            do{foreach($r in @(Receipts)){if($r.event -ceq 'begin'){$begin=$r}elseif($r.event -in @('rejected','terminal')){throw "Native gameplay begin rejected: $($r.result)"}};if($begin){break};Start-Sleep -Milliseconds 5}while($stopwatch.Elapsed.TotalMilliseconds -lt $until)
            if(-not $begin -or $begin.result -cne 'ready' -or -not $begin.active){throw 'No native gameplay begin acknowledgement.'}
            $stage='running';Publish
            while(-not $Token.IsCancellationRequested){
                $utc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$elapsed=$stopwatch.Elapsed.TotalMilliseconds
                if($utc -ge $ExpiresUtcMs -or $elapsed -ge $limit){throw 'Gameplay host identity expired.'}
                $pose=Read-GameplayMovementPose $PoseFile $Identity $Bounds $sequence $source $utc
                $parts=[Collections.Generic.List[string]]::new()
                # Consume durable terrain acknowledgements before admitting any
                # pose or block snapshot that uses newly installed collision.
                if($TerrainState){$command=Get-GameplayTerrainCommands $TerrainState $utc $pose;if($command){$parts.Add((RejectWrapper $command))}}
                if($pose -and $TerrainState -and -not(Test-GameplayTerrainPose $TerrainState $pose)){throw 'Gameplay pose leaves acknowledged terrain.'}
                if($BlocksState){$command=Get-GameplayBlocksCommands $BlocksState $utc;if($command){$parts.Add((RejectWrapper $command))}}
                if($pose){$parts.Add((RejectWrapper "MineCome.GameplayMovementPose('$run',$($pose.seq),$(Numeric $pose.source_ms),$(Numeric $pose.position.x),$(Numeric $pose.position.y),$(Numeric $pose.position.z))"))}
                $requestView=$elapsed-$lastViewAt -ge 90
                if($requestView){$viewSequence++;$requestedUtc=$utc;$aimArgument=if($BlocksState -or $WorldBlocks){',true'}else{''};$parts.Add((RejectWrapper "MineCome.GameplayMovementSample('$run',$viewSequence$aimArgument)"));$lastViewAt=$elapsed}
                if($parts.Count){Send $parts.ToArray();if($pose){$sequence=[long]$pose.seq;$source=[double]$pose.source_ms;$poses++;$lastPoseUtc=[long]$pose.utc_ms;$lastPoseAt=$elapsed}}
                if($poses -gt 0 -and $elapsed-$lastPoseAt -gt 350){throw 'Gameplay guest pose expired.'}
                $until=$stopwatch.Elapsed.TotalMilliseconds+$(if($requestView){300}else{0})
                do{
                    foreach($r in @(Receipts)){
                        if($r.event -ceq 'terminal'){$terminal=$r;throw "Native gameplay stopped: $($r.result)"}
                        if($r.event -ceq 'rejected'){throw "Native gameplay request rejected: $($r.result)"}
                        if($r.event -ceq 'view'){
                            if(-not $requestView -or $r.seq -ne $viewSequence -or $r.result -cne 'sampled' -or -not $r.active -or -not $r.camera_basis_valid){throw 'Native gameplay view acknowledgement differs.'}
                            $latestView=$r
                            $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                            if($now-$requestedUtc -le 250){
                                $value=[ordered]@{schema=1;source_kind='live_kcd_hud_view_v1';run=$run;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;seq=$viewSequence;utc_ms=$requestedUtc;forward=$r.forward;up=$r.up}
                                $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($value|ConvertTo-Json -Depth 5 -Compress))
                                $f=[IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                                try{$f.Write($bytes);$f.Flush($false)}finally{$f.Dispose()}
                                Publish-GameplayMovementView $temp $ViewFile
                                if($BlocksState -or $WorldBlocks){
                                    $aim=[ordered]@{schema=1;kind='minecome_gameplay_aim_v1';run=$run;world_id=$Identity.WorldId;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;seq=$viewSequence;utc_ms=$requestedUtc;origin=$r.camera;direction=$r.forward;range=$r.aim.range;known=$r.aim.known;distance=$r.aim.distance;terrain_hit=$r.aim.terrain_hit}
                                    if($WorldBlocks){
                                        if(-not(Test-GameplayHostNumber $r.fov) -or $r.fov -le .05 -or $r.fov -ge ([Math]::PI-.05)){throw 'World block camera FOV unavailable.'}
                                        $aim.schema=2;$aim.kind='minecome_gameplay_aim_v2';$aim.up=$r.up;$aim.vertical_fov=$r.fov
                                    }
                                    [IO.File]::WriteAllText($aimTemp,($aim|ConvertTo-Json -Depth 5 -Compress),[Text.UTF8Encoding]::new($false));Publish-GameplayMovementView $aimTemp $aimFile
                                }
                                $views++
                            }
                            $requestView=$false
                        }
                    }
                    if(-not $requestView){break};Start-Sleep -Milliseconds 5
                }while($stopwatch.Elapsed.TotalMilliseconds -lt $until -and -not $Token.IsCancellationRequested)
                if($requestView -and -not $Token.IsCancellationRequested){throw 'Native gameplay camera acknowledgement expired.'}
                Publish;Start-Sleep -Milliseconds 10
            }
        }catch{$failure=$_.Exception.Message}
        finally{
            $stage='stopping'
            if($started){
                $blocksStarted=$BlocksState -and $BlocksState.BeginSent
                $terrainStarted=$TerrainState -and $TerrainState.BeginSent
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
                    if($terminal -and (-not $blocksStarted -or $BlocksState.Terminal) -and (-not $terrainStarted -or $TerrainState.Terminal)){break}
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
                if($blocksStarted -and -not (Get-GameplayBlocksHostState $BlocksState).CleanupComplete -and -not $failure){$failure='Native block cleanup incomplete.'}
                if($terrainStarted -and -not (Get-GameplayTerrainHostState $TerrainState).CleanupComplete -and -not $failure){$failure='Native terrain cleanup incomplete.'}
            }catch{if(-not $failure){$failure=$_.Exception.Message}}}
            if($log){$log.Dispose()}
            if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
            if([IO.File]::Exists($aimTemp)){[IO.File]::Delete($aimTemp)}
            $stage='stopped';Publish $true
        }
    }
}
function Start-GameplayMovementHost {
    param($Context,[string]$Run,[string]$WorldId,$Patch,[string]$PoseFile,[string]$ViewFile,[long]$ExpiresUtcMs,$Bounds,[switch]$Blocks,[switch]$Explore,[string]$TerrainCacheFile,[switch]$Flight,[switch]$WorldBlocks)
    if($Flight -or $WorldBlocks){$Blocks=$true}
    if($Explore){$Blocks=$true;if(-not $TerrainCacheFile){throw 'Explore requires the owned terrain cache path.'}}
    $root=$Context.ProjectRoot
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $WorldId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or $Patch.Run -cnotmatch '^[0-9a-f]{32}$' -or $Patch.Hash -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid gameplay host identity.'}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();if($ExpiresUtcMs-$now -lt 1000 -or $ExpiresUtcMs-$now -gt 86400000){throw 'Gameplay host expiry differs.'}
    $PoseFile=Resolve-HudMovementEvidencePath $PoseFile $root;$ViewFile=Resolve-HudMovementEvidencePath $ViewFile $root
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
    $terrainState=if($Explore){New-GameplayTerrainHost -Context $Context -Run $Run -WorldId $WorldId -Patch $Patch -CacheFile $TerrainCacheFile -AdmissionFile (Join-Path $evidenceDirectory 'terrain-admission.json') -AckFile (Join-Path $evidenceDirectory 'terrain-ack.json') -ExpiresUtcMs $ExpiresUtcMs}else{$null}
    $blocksState=if($Blocks -and -not $WorldBlocks){New-GameplayBlocksHost -Context $Context -Run $Run -WorldId $WorldId -Patch $Patch -SnapshotFile (Join-Path $evidenceDirectory 'gameplay-blocks.json') -ExpiresUtcMs $ExpiresUtcMs -TerrainState $terrainState}else{$null}
    $identity=[pscustomobject]@{Run=$Run;WorldId=$WorldId;Pid=$Context.GamePid;Start=$Context.GameStartedUtc.ToFileTimeUtc().ToString();PatchRun=$Patch.Run;PatchHash=$Patch.Hash}
    $shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new([StringComparer]::Ordinal)
    $shared['Snapshot']=[pscustomobject]@{Stopped=$false;Failure=$null;Stage='starting';PoseCount=0L;ViewCount=0L;LastPoseSequence=0L;LastPoseUtcMs=0L;RequestCount=0L;MaxRequestPathLength=0;LastDispatch=$null;Begin=$null;Terminal=$null;LastView=$null;Blocks=$null;Terrain=$null}
    $cancellation=[Threading.CancellationTokenSource]::new();$runspace=[RunspaceFactory]::CreateRunspace();$pipeline=[PowerShell]::Create()
    try{
        $runspace.Open();$pipeline.Runspace=$runspace
        $null=$pipeline.AddScript((Get-GameplayMovementWorker).ToString()).AddArgument($Context).AddArgument($identity).AddArgument($Bounds).AddArgument($PoseFile).AddArgument($ViewFile).AddArgument($ExpiresUtcMs).AddArgument((Get-Item -LiteralPath $Context.GameLog).Length).AddArgument($shared).AddArgument($cancellation.Token).AddArgument($root).AddArgument($blocksState).AddArgument($terrainState).AddArgument([bool]$Flight).AddArgument([bool]$WorldBlocks)
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
    $Session.Final=[pscustomobject]@{Stopped=$s.Stopped;Failure=$(if($s.Failure){$s.Failure}else{$errorText});Stage=$s.Stage;PoseCount=$s.PoseCount;ViewCount=$s.ViewCount;LastPoseSequence=$s.LastPoseSequence;LastPoseUtcMs=$s.LastPoseUtcMs;RequestCount=$s.RequestCount;MaxRequestPathLength=$s.MaxRequestPathLength;LastDispatch=$s.LastDispatch;Begin=$s.Begin;Terminal=$s.Terminal;LastView=$s.LastView;Blocks=$s.Blocks;Terrain=$s.Terrain;ResourcesClosed=$true}
    $Session.PowerShell.Dispose();$Session.Runspace.Dispose();$Session.Cancellation.Dispose();$Session.Disposed=$true
    $Session.Final|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Session.Probe.Directory 'verification.json') -Encoding utf8NoBOM
    return $Session.Final
}
