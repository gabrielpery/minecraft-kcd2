#requires -Version 7.3
# Pure physical corridor parser/warmup tests. Deliberately synthetic capture
# labels exercise syntax only; no KCD, Minecraft, renderer or process calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
. (Join-Path $root 'scripts/HudGroundCorridor.ps1')
. (Join-Path $root 'scripts/MovementTraceReceiver.ps1')
. (Join-Path $root 'scripts/HudBufferedMovement.ps1')
$script:checks=0
function Check([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
$run='a'*32;$world='12345678-1234-1234-1234-123456789abc';$save='MineCome-HudStream-'+$world;$utc=1700000000000L
$dir=Join-Path $root ('runtime/evidence/physical-corridor-pure-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir);$path=Join-Path $dir 'corridor.json'
$manifest=New-HudGroundCorridorFixture $run
for($i=0;$i -lt 2;$i++){
    $tile=$manifest.tiles[$i].json | ConvertFrom-Json
    $tile.provenance.kind='live_kcd_ground_patch'
    $tile | Add-Member approximate_heightfield $true;$tile | Add-Member full_collision_export_verified $false
    $manifest.tiles[$i].json=$tile | ConvertTo-Json -Depth 12 -Compress
    $manifest.tiles[$i].sha256=Get-HudCorridorHash ([Text.Encoding]::UTF8.GetBytes($manifest.tiles[$i].json))
}
[IO.File]::WriteAllText($path,($manifest | ConvertTo-Json -Depth 12 -Compress),[Text.UTF8Encoding]::new($false))
$corridor=[pscustomobject]@{Path=$path;Hash=(Get-FileHash $path).Hash.ToLowerInvariant();Run=$run;
    Anchor=($manifest.tiles[0].json | ConvertFrom-Json).center;TileHashes=@($manifest.tiles.sha256);Captured=$true}
function Receiver(){New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -PhysicalMovement -BufferedPhysicalMovement -ExtendedWalking -CorridorWalking -Corridor $corridor}
function Record($State,[string]$Kind,[int]$Seq,[string]$Phase='RESTING',[double]$X=0,[double]$Y=64.25,[double]$Z=0){
    $record=[ordered]@{schema=1;kind=$Kind;run=$run;patch_sha256=$State.PatchHash;source_kind='live_kcd_hud_physical_movement_corridor';
        walking_area='corridor';save=$save;world=$world;seq=$Seq;utc_ms=$utc;phase=$Phase}
    if($Kind -ceq 'begin'){
        $record.phase='SETTLING';$record.started_monotonic_ns=100L;$record.center=$State.Center;$record.anchor_mc=@{x=$X;y=$Y;z=$Z}
        $record.approximate_heightfield=$true;$record.full_collision_export_verified=$false
    }elseif($Kind -ceq 'end'){$record.result='passed';$record.reason='';$record.last_server_seq=$Seq-2}
    else{
        $record.monotonic_ns=100L+($Seq-2)*100000000L;$record.server_seq=$Seq-1;$record.server_age_ns=0L
        foreach($side in @('client','server')){$record[$side]=@{x=$X;y=$Y;z=$Z;vx=0;vy=0;vz=0;on_ground=$true;proxy_support=$true}}
    }
    return $record
}
function Receive($State,$Record,[long]$Now=$utc){Receive-MineComeMovementTrace $State ($Record | ConvertTo-Json -Depth 8 -Compress) $Now}
function Reject-Record($State,$Record,[string]$Message){
    $before=$State | ConvertTo-Json -Depth 12 -Compress
    Reject {Receive $State $Record} $Message
    Check (($State | ConvertTo-Json -Depth 12 -Compress) -ceq $before) 'Rejected physical corridor record changed state'
}
function Begin($State,[double]$Y=64.25,[double]$X=0,[double]$Z=0){
    $null=Receive $State (Record $State begin 1 SETTLING $X $Y $Z)
    return Receive $State (Record $State sample 2 SETTLING $X $Y $Z)
}
try{
    $area=Get-HudWalkingArea -CorridorWalking
    Check ($area.Columns -eq 13 -and $area.Rows -eq 9 -and $area.Points -eq 117 -and $area.MinX -eq -4 -and $area.MaxX -eq 8 -and -not $area.PSObject.Properties['Radius']) 'Corridor exposes its rectangle, never a misleading radius'
    Reject {Get-HudWalkingArea -CorridorWalking -WideWalking} 'Two area selectors combined'
    Assert-HudWalkingArea ([pscustomobject]@{walking_area='corridor'}) $false -CorridorWalking
    Assert-HudWalkingArea @{walking_area='corridor'} $false -CorridorWalking
    Check $true 'Explicit dictionary and object corridor markers accepted'
    foreach($value in @('wide','Corridor',$null,$true)){
        Reject {Assert-HudWalkingArea ([pscustomobject]@{walking_area=$value}) $false -CorridorWalking} 'Malformed corridor marker accepted'
    }
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -PhysicalMovement -CorridorWalking -Corridor $corridor} 'Physical corridor accepted without buffered extension'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -PhysicalMovement -BufferedPhysicalMovement -CorridorWalking -Corridor $corridor} 'Physical corridor inferred extension'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -PhysicalMovement -BufferedPhysicalMovement -ExtendedWalking -WideWalking -CorridorWalking -Corridor $corridor} 'Physical corridor widened existing wide route'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -PhysicalMovement -BufferedPhysicalMovement -ExtendedWalking -CorridorWalking -CorridorWalkOnly -Corridor $corridor} 'Physical corridor selected scripted walk-only route'
    $state=Receiver;$initial=Begin $state
    Check ([Math]::Abs($state.InitialGroundY-64.015) -lt 1e-10) 'Diagnostic supported height is the highest imported slab under the whole player footprint'
    Check ($state.Anchor.y -eq 64.25 -and $state.AnchorVerified -and $initial.Target.z -eq $corridor.Anchor.z) 'Actual settled support height maps to the unchanged native origin'
    foreach($source in @('standalone_hud_physical_movement_corridor_fixture','live_kcd_hud_physical_movement_extended','hud_corridor_coupled','hud_corridor_walk_coupled')){
        $bad=Record $state sample 3;$bad.source_kind=$source;Reject-Record $state $bad 'Wrong trace authority admitted as live physical corridor'
    }
    foreach($phase in @('RETURNING','RETURN_REST')){Reject-Record $state (Record $state sample 3 $phase) 'Scripted return phase admitted in physical input'}
    foreach($case in @(@('x',7.5001),@('x',-3.5001),@('z',3.5001),@('z',-3.5001),@('y',67.5001),@('y',57.8999))){
        $bad=Record $state sample 3;$bad.server[$case[0]]=$case[1]
        Reject-Record $state $bad 'Raw physical corridor coordinate exceeded the captured envelope'
    }
    $bad=Record $state sample 3 RESTING 0 57.9
    Reject-Record $state $bad 'Raw supported height bypassed settled-anchor displacement limit'
    $accepted=Receive $state (Record $state sample 3 WALKING 5.75 64.55)
    Check ($accepted.Kind -ceq 'sample' -and $accepted.Target.x -eq 125.75 -and [Math]::Abs($accepted.Target.z-56.3) -lt 1e-10) 'Crossing uses the first tile and actual settledY, not scripted64 or a radial limit'
    $null=Receive $state (Record $state sample 4 PASSED 5.75 64.55)
    $null=Receive $state (Record $state end 5 PASSED)
    Check $state.Ended 'Bound physical corridor stream completed'
    $edge=Receiver;$null=Begin $edge 64.25 -.005 0
    Reject-Record $edge (Record $edge sample 3 RESTING 7.5 64.25) 'Tiny horizontal anchor expanded the native rectangle'
    $low=Receiver;$null=Begin $low 63.5
    Reject-Record $low (Record $low sample 3 RESTING 0 67.5) 'Raw upper height bypassed settled-anchor upper displacement'
    $initialState=Receiver;$null=Receive $initialState (Record $initialState begin 1)
    Reject-Record $initialState (Record $initialState sample 2 SETTLING 0 64) 'Initial sample silently rebased settled anchorY'
    $bad=Record $initialState sample 2 SETTLING;$bad.server.on_ground=$false
    Reject-Record $initialState $bad 'Initial physical anchor lacked real-server ground support'
    $stale=Receiver;$null=Receive $stale (Record $stale begin 1)
    Check ((Receive $stale (Record $stale sample 2 SETTLING) ($utc+301)).Kind -ceq 'stale' -and -not $stale.GroundProved) 'Physical corridor retains300ms freshness and does not grant support from stale source'
    $budget=Receiver;$null=Begin $budget;$budget.LastSeq=199;$budget.Records=199
    Reject-Record $budget (Record $budget sample 200) 'Physical corridor inherited scripted256-record allowance'
    $warm=Initialize-HudBufferedMovementPipeline -PatchFile $path -ExpectedHudSave $save -MinimumUtcMs $utc -ExtendedWalking -CorridorWalking -Corridor $corridor
    Check ($warm.status -ceq 'completed' -and $warm.diagnostic_records -eq 3) 'Disposable corridor parser warmup preserves exact terrain/source profile'
    Reject {Initialize-HudBufferedMovementPipeline -PatchFile $path -ExpectedHudSave $save -MinimumUtcMs $utc -CorridorWalking -Corridor $corridor} 'Corridor warmup implicitly extended session'
    $clock=New-HudBufferedSourceState -ExtendedWalking
    $sourceState=Receiver
    $start=Record $sourceState sample 2 SETTLING
    Check ((Get-HudBufferedSourceTime $clock ([pscustomobject]$start)) -eq 0) 'Physical corridor timeline starts at actual initial server observation'
    $last=Record $sourceState sample 3 PASSED;$last.monotonic_ns=$start.monotonic_ns+16000000000L
    Check ((Get-HudBufferedSourceTime $clock ([pscustomobject]$last)) -eq 16000) 'Physical corridor retains16-second source maximum'
    $last.seq=4;$last.server_seq=3;$last.monotonic_ns++
    Reject {Get-HudBufferedSourceTime $clock ([pscustomobject]$last)} 'Physical corridor exceeded source maximum'
    Write-Output "HUD_CORRIDOR_WALKING_TESTS_PASS checks=$script:checks no_game_started=true"
}finally{
    if([IO.File]::Exists($path)){[IO.File]::Delete($path)}
    [IO.Directory]::Delete($dir,$false)
}
