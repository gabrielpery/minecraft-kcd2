#Requires -Version 7.3
# Pure profile/trace regressions. Synthetic patch only; no game or process calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
function Clone($Value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 12)}
function Parse([string]$Relative){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Relative),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Syntax errors in $Relative"
    return $ast
}
function Import-Function($Ast,[string]$Name){
    $node=$Ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true)
    if(-not $node){throw "Missing production function $Name"}
    return [scriptblock]::Create($node.Extent.Text)
}
$profileAst=Parse 'scripts/HudPhysicalMovement.ps1'
. (Import-Function $profileAst 'Assert-MineComePhysicalMovementBundle')
. (Import-Function $profileAst 'Assert-HudPhysicalMovementReady')
. (Join-Path $root 'scripts/MovementTraceReceiver.ps1')
foreach($file in @('scripts/Test-HudWalking.ps1','scripts/Prepare-HudWalking.ps1','scripts/Start-HudWalkingLab.ps1',
    'scripts/MovementTraceReceiver.ps1','scripts/Arm-HudStream.ps1','scripts/Update-HudCompositor.ps1','scripts/Run-HudStreamClient.ps1')){
    $null=Parse $file
}
$ready=[pscustomobject]@{ui_input_protocol=2;ui_input_physical_movement=$true}
Assert-HudPhysicalMovementReady $ready $true
Check $true 'Explicit physical v2 readiness accepted'
foreach($value in @($true,$false,'true',0,$null)){
    $bad=Clone $ready;$bad | Add-Member -NotePropertyName ui_physical_controller_fixture -NotePropertyValue $value
    Reject {Assert-HudPhysicalMovementReady $bad $true} 'Fixture-labelled readiness accepted as live physical input'
}
foreach($value in @($true,'true',0,$null)){
    $bad=Clone $ready;$bad | Add-Member -NotePropertyName scripted_input -NotePropertyValue $value
    Reject {Assert-HudPhysicalMovementReady $bad $true} 'Scripted or malformed input provenance accepted as physical input'
}
$live=Clone $ready;$live | Add-Member -NotePropertyName scripted_input -NotePropertyValue $false
Assert-HudPhysicalMovementReady $live $true
Check $true 'Explicit non-scripted readiness accepted'
foreach($value in @($false,0,1,'true','false',$null)){
    $bad=Clone $ready;$bad.ui_input_physical_movement=$value
    Reject {Assert-HudPhysicalMovementReady $bad $true} 'Missing/malformed physical marker accepted'
}
Reject {Assert-HudPhysicalMovementReady ([pscustomobject]@{ui_input_protocol=2}) $true} 'Absent physical marker accepted'
foreach($protocol in @(1,3,0)){
    $bad=Clone $ready;$bad.ui_input_protocol=$protocol
    Reject {Assert-HudPhysicalMovementReady $bad $true} 'Wrong input protocol accepted'
}
Reject {Assert-HudPhysicalMovementReady $ready $false} 'Physical producer accepted by legacy controller'
Assert-HudPhysicalMovementReady ([pscustomobject]@{ui_input_protocol=1}) $false
Assert-HudPhysicalMovementReady ([pscustomobject]@{ui_input_protocol=1;ui_input_physical_movement=$false}) $false
Check $true 'Legacy absent/false physical marker remains accepted'
foreach($value in @(1,'false',$null)){
    Reject {Assert-HudPhysicalMovementReady ([pscustomobject]@{ui_input_physical_movement=$value}) $false} 'Malformed marker accepted by legacy mode'
}
$profile=[pscustomobject]@{runtime_sha256='a'*64;addon_sha256='b'*64;shader_sha256='c'*64;build_receipt_sha256='d'*64}
$bundle=[pscustomobject]@{schema=1;kind='minecome_hud_compositor_bundle_v1';tools_only=$true;physical_movement=$true
    stream_protocol=1;ui_input_protocol=2;mouse_capture_api=2;arm_config_relative_path='minecome-hud/addons/MineComeHudMovement.ini'
    runtime=[pscustomobject]@{reshade64_sha256=$profile.runtime_sha256;build_receipt_sha256=$profile.build_receipt_sha256}
    files=@(
        [pscustomobject]@{path='dxgi.dll';sha256=$profile.runtime_sha256},
        [pscustomobject]@{path='minecome-hud/addons/MineComeHudCompositor.addon64';sha256=$profile.addon_sha256},
        [pscustomobject]@{path='minecome-hud/shaders/MineComeHud.fx';sha256=$profile.shader_sha256},
        [pscustomobject]@{path='ReShade.ini';sha256='e'*64},
        [pscustomobject]@{path='MineComeHudPreset.ini';sha256='e'*64},
        [pscustomobject]@{path='ReShade-LICENSE.txt';sha256='e'*64})}
Assert-MineComePhysicalMovementBundle $bundle $profile
Check $true 'Exact physical profile accepted'
foreach($field in @('tools_only','physical_movement')){
    foreach($value in @($false,1,'true',$null)){
        $bad=Clone $bundle;$bad.$field=$value
        Reject {Assert-MineComePhysicalMovementBundle $bad $profile} "Malformed bundle $field accepted"
    }
}
foreach($field in @('world_clicks','selective_mouse','selective_revision')){
    $bad=Clone $bundle;$bad | Add-Member -NotePropertyName $field -NotePropertyValue $false
    Reject {Assert-MineComePhysicalMovementBundle $bad $profile} 'Mixed input profile accepted even with false marker'
}
foreach($change in @(
    {param($b)$b.ui_input_protocol=1},
    {param($b)$b.mouse_capture_api=1},
    {param($b)$b.arm_config_relative_path='minecome-hud/addons/MineComeHudSelective.ini'},
    {param($b)$b.runtime.reshade64_sha256='f'*64},
    {param($b)$b.runtime.build_receipt_sha256='f'*64},
    {param($b)$b.files[0].sha256='f'*64},
    {param($b)$b.files[1].sha256='f'*64},
    {param($b)$b.files[2].sha256='f'*64},
    {param($b)$b.files[3]=$b.files[1]}
)){
    $bad=Clone $bundle;& $change $bad
    Reject {Assert-MineComePhysicalMovementBundle $bad $profile} 'Mismatched profile artifact accepted'
}

$patchRun='a'*32;$world='12345678-1234-1234-1234-123456789abc'
$save='MineCome-HudStream-'+$world
$center=[pscustomobject]@{x=120.0;y=2040.0;z=56.0}
$points=@(for($i=1;$i -le 25;$i++){
    [pscustomobject]@{index=$i;x=120+(($i-1)%5)-2;y=2040+[Math]::Floor(($i-1)/5)-2;z=56;nx=0;ny=0;nz=1;valid=$true;result='hit'}
})
$patch=[pscustomobject]@{schema=1;run=$patchRun;grid_size=5;spacing=1;point_count=25;valid_count=25
    stable_player=$true;approximate_heightfield=$true;full_collision_export_verified=$false
    center=$center;points=$points;provenance=[pscustomobject]@{kind='live_kcd_ground_patch'}}
$dir=Join-Path $root ('runtime/evidence/physical-hud-pure-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
'SYNTHETIC ONLY. Receiver provenance parsing test; this patch is not authenticated game evidence.' | Set-Content (Join-Path $dir 'FIXTURE.txt')
$patchPath=Join-Path $dir 'patch.json'
$patch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $patchPath -Encoding utf8NoBOM
$hash=(Get-FileHash -LiteralPath $patchPath).Hash.ToLowerInvariant()
function State {New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $save -PhysicalMovement}
function Base([string]$Kind,[int]$Seq,[string]$Phase){
    [ordered]@{schema=1;kind=$Kind;run=$patchRun;patch_sha256=$hash;source_kind='live_kcd_hud_physical_movement'
        save=$save;world=$world;seq=$Seq;utc_ms=1000;phase=$Phase}
}
function Begin {
    $r=Base 'begin' 1 'SETTLING'
    $r.started_monotonic_ns=1000000;$r.center=$center;$r.anchor_mc=[pscustomobject]@{x=0.0;y=63.625;z=0.0}
    $r.approximate_heightfield=$true;$r.full_collision_export_verified=$false
    [pscustomobject]$r
}
function Sample([int]$Seq,[string]$Phase,[double]$X=0,[double]$Y=63.625,[double]$Z=0,[bool]$Ground=$true){
    $r=Base 'sample' $Seq $Phase;$r.monotonic_ns=1000000+$Seq;$r.server_seq=$Seq-1;$r.server_age_ns=0
    $motion=[pscustomobject]@{x=$X;y=$Y;z=$Z;vx=0;vy=0;vz=0;on_ground=$Ground;proxy_support=$Ground}
    $r.client=$motion;$r.server=Clone $motion
    [pscustomobject]$r
}
function Receive($State,$Record,[long]$Now=1000){
    Receive-MineComeMovementTrace $State (ConvertTo-Json -InputObject $Record -Depth 8 -Compress) $Now
}
function Primed {
    $s=State;$null=Receive $s (Begin);$null=Receive $s (Sample 2 'SETTLING');return $s
}
Reject {New-MineComeTraceReceiver $patchPath 1000 -PhysicalMovement} 'Physical receiver without exact HUD save accepted'
foreach($badSave in @('MineCome-Ground-'+$world,'MineCome-HudStream-'+$world.ToUpperInvariant(),'MineCome-HudStream-other')){
    Reject {New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $badSave -PhysicalMovement} 'Noncanonical/mismatched save accepted'
}
$s=Primed
Check ($s.AnchorVerified -and $s.Anchor.y -eq 63.625) 'Actual grounded fractional anchor verified'
$r=Receive $s (Sample 3 'WALKING')
Check ($r.Kind -ceq 'sample' -and $r.Target.x -eq 120 -and $r.Target.y -eq 2040 -and $r.Target.z -eq 56) 'Settled anchor maps to exact host center without startup hop'
$r=Receive $s (Sample 4 'WALKING' 0.4 63.625 -0.3)
Check ([Math]::Abs($r.Target.x-120.4) -lt 1e-9 -and [Math]::Abs($r.Target.y-2040.3) -lt 1e-9 -and $r.Target.z -eq 56) 'Horizontal axes use actual settled anchor'
$r=Receive $s (Sample 5 'JUMPING' 0.4 64.625 -0.3 $false)
Check ($r.Kind -ceq 'sample' -and $r.Target.z -eq 57) 'Airborne delta relative to actual settled height'
foreach($change in @(
    {param($b)$b.run='other'},
    {param($b)$b.patch_sha256='f'*64},
    {param($b)$b.source_kind='live_kcd_ground_patch'},
    {param($b)$b.source_kind='standalone_hud_physical_movement_fixture'},
    {param($b)$b.save='MineCome-Ground-'+$b.world},
    {param($b)$b.anchor_mc.x=0.011},
    {param($b)$b.anchor_mc.y=76.001},
    {param($b)$b.anchor_mc.y=51.999},
    {param($b)$b.anchor_mc.z=-0.011},
    {param($b)$b.anchor_mc.y='63.625'}
)){
    $s=State;$bad=Begin;& $change $bad
    Reject {Receive $s $bad} 'Invalid physical trace begin accepted'
    Check (-not $s.Begun -and $s.LastSeq -eq 0) 'Rejected begin mutated receiver state'
}
foreach($bad in @((Sample 2 'WALKING'),(Sample 2 'SETTLING' 0 63.625 0 $false),(Sample 2 'SETTLING' 0 63.645))){
    $s=State;$null=Receive $s (Begin)
    Reject {Receive $s $bad} 'Ungrounded, moved or wrong-phase first anchor accepted'
    Check (-not $s.AnchorVerified -and $s.LastSeq -eq 1) 'Rejected anchor mutated receiver state'
}
$s=Primed
$r=Receive $s (Sample 3 'WALKING' 0.5) 1301
Check ($r.Kind -ceq 'stale' -and -not $s.GroundProved) 'Stale physical pose cannot establish movement/ground proof'
$r=Receive $s (Sample 4 'WALKING' 0.5)
Check ($r.Kind -ceq 'sample' -and $s.GroundProved) 'Fresh physical pose recovers within unchanged trace clock contract'
foreach($bad in @((Sample 3 'WALKING' 1.9 64.625),(Sample 3 'WALKING' 0 65.126),(Sample 3 'WALKING' 0 62.124),(Sample 3 'WALKING' 1.5 62.125))){
    $s=Primed
    Reject {Receive $s $bad} 'Target beyond exact three-dimensional/vertical follower bound accepted'
    Check ($s.LastSeq -eq 2) 'Rejected target mutated receiver state'
}
$s=Primed
$r=Receive $s (Sample 3 'WALKING' 0.3 63.125)
Check ($r.Kind -ceq 'sample' -and $r.Target.z -eq 55.5) 'Sampled downhill walking is accepted inside the physical sphere'
$r=Receive $s (Sample 4 'WALKING' 0 62.125)
Check ($r.Kind -ceq 'sample' -and $r.Target.z -eq 54.5) 'Exact physical lower envelope accepted'
$r=Receive $s (Sample 5 'WALKING' 0 65.125)
Check ($r.Kind -ceq 'sample' -and $r.Target.z -eq 57.5) 'Exact physical upper envelope accepted'
$s=Primed;$null=Receive $s (Sample 3 'WALKING' 2)
Check ($s.LastSeq -eq 3) 'Exact two-meter target accepted'
$null=Receive $s (Sample 4 'PASSED' 0.5)
$end=Base 'end' 5 'PASSED';$end.result='passed';$end.reason='done';$end.last_server_seq=3
$r=Receive $s ([pscustomobject]$end)
Check ($s.Ended -and $r.Kind -ceq 'end') 'Fresh grounded terminal completes physical trace'
Reject {Receive $s ([pscustomobject]$end)} 'Completed physical trace replay accepted'
$s=Primed;$null=Receive $s (Sample 3 'WALKING' 0.5)
$badEnd=Base 'end' 4 'PASSED';$badEnd.result='passed';$badEnd.reason='done';$badEnd.last_server_seq=2
Reject {Receive $s ([pscustomobject]$badEnd)} 'Passed end without immediate grounded PASSED sample accepted'
$legacy=New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $save
Reject {Receive $legacy (Begin)} 'Legacy receiver accepted physical source kind'
$legacyBegin=Begin;$legacyBegin.source_kind='live_kcd_ground_patch'
Reject {Receive $legacy $legacyBegin} 'Legacy receiver accepted fractional physical anchor'
$legacyBegin.anchor_mc.y=64
$null=Receive $legacy $legacyBegin
Check ($legacy.Begun -and $legacy.Anchor.y -eq 64) 'Legacy receiver retains exact Y64 anchor'
Reject {New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $save -BufferedPhysicalMovement} 'Buffered playback accepted a nonphysical profile'
$s=State;$null=Receive $s (Begin);$r=Receive $s (Sample 2 'SETTLING')
Check ($r.Kind -ceq 'observe') 'Existing physical follower still observes its initial anchor without dispatching it'
$r=Receive $s (Sample 3 'JUMPING' .1 63.55 0 $false)
Check ($r.Kind -ceq 'observe' -and -not $s.GroundProved) 'Legacy physical profile still requires its existing grounded motion proof before airborne dispatch'
function BufferedState {New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $save -PhysicalMovement -BufferedPhysicalMovement}
$s=BufferedState;$null=Receive $s (Begin);$r=Receive $s (Sample 2 'SETTLING')
Check ($r.Kind -ceq 'sample' -and $r.Target.x -eq 120 -and $r.Target.y -eq 2040 -and $r.Target.z -eq 56) 'Buffered timeline includes the genuine initial source anchor'
Check $s.GroundProved 'Fresh verified buffered anchor establishes ground provenance without claiming walking occurred'
$r=Receive $s (Sample 3 'SETTLING')
Check ($r.Kind -ceq 'observe') 'A later settling record cannot restart the playback anchor'
$null=Receive $s (Sample 4 'WALKING' 0.5)
$r=Receive $s (Sample 5 'PASSED' 0.5)
Check ($r.Kind -ceq 'sample' -and $r.Target.x -eq 120.5 -and $s.LastFreshPassedSeq -eq 5) 'Buffered playback includes the final grounded source point'
$s=BufferedState;$null=Receive $s (Begin);$r=Receive $s (Sample 2 'SETTLING') 1301
Check ($r.Kind -ceq 'stale' -and -not $r.PSObject.Properties['Target']) 'Stale initial anchor cannot drive playback'
Check (-not $s.GroundProved) 'Stale anchor must not establish ground provenance'
$r=Receive $s (Sample 3 'JUMPING' .1 63.55 0 $false)
Check ($r.Kind -ceq 'observe' -and -not $s.GroundProved) 'Airborne observation after a stale anchor remains nondriving'
$s=BufferedState;$null=Receive $s (Begin);$null=Receive $s (Sample 2 'SETTLING');$null=Receive $s (Sample 3 'WALKING')
$r=Receive $s (Sample 4 'PASSED' 0.5) 1301
Check ($r.Kind -ceq 'stale' -and $s.LastFreshPassedSeq -eq 0) 'Stale terminal point is excluded from playback'
$s=BufferedState;$null=Receive $s (Begin);$null=Receive $s (Sample 2 'SETTLING');$null=Receive $s (Sample 3 'WALKING')
Reject {Receive $s (Sample 4 'PASSED' 1.9 64.625)} 'Buffered terminal point escaped the same physical sphere'
Check ($s.LastSeq -eq 3) 'Rejected buffered terminal point left the receiver unchanged'
$s=BufferedState;$null=Receive $s (Begin);$null=Receive $s (Sample 2 'SETTLING');$null=Receive $s (Sample 3 'RESTING' .042939163785843 63.625 -.245785430500455)
$transition=Sample 4 'LANDING' .0649484967378493 63.5465999984741 -.371767701641474
$transition.server.proxy_support=$false
$r=Receive $s $transition
Check ($r.Kind -ceq 'sample' -and [Math]::Abs($r.Target.z-55.9215999984741) -lt 1e-9) 'Authoritative downhill transition remains a waypoint after grounded motion proof'
$s=BufferedState;$null=Receive $s (Begin);$null=Receive $s (Sample 2 'SETTLING')
$transition=Sample 3 'LANDING' 0 63.5466 0 $false
$r=Receive $s $transition
Check ($r.Kind -ceq 'sample') 'First airborne transition follows the fresh verified buffered anchor'

# A genuine grounded anchor may be followed immediately by a small descent.
# Every ordered source point must survive, without requiring an intermediate
# WALKING/RESTING point or changing the original clocks and phase labels.
$s=BufferedState;$null=Receive $s (Begin)
Check (-not $s.GroundProved -and -not $s.AnchorVerified) 'Begin metadata alone establishes no grounded observation'
foreach($record in @((Sample 2 'SETTLING'),(Sample 3 'JUMPING' .06 63.625 -.32 $false),
    (Sample 4 'LANDING' .07 63.5466 -.39 $false),(Sample 5 'RESTING' .075 63.47 -.43),(Sample 6 'PASSED' .075 63.47 -.43))){
    $r=Receive $s $record
    Check ($r.Kind -ceq 'sample' -and $r.Record.seq -eq $record.seq -and $r.Record.phase -ceq $record.phase -and $r.Record.monotonic_ns -eq $record.monotonic_ns) 'First-step descent lost or rewrote an immutable source point'
}
$end=Base 'end' 7 'PASSED';$end.result='passed';$end.reason='synthetic descent complete';$end.last_server_seq=5
$r=Receive $s ([pscustomobject]$end)
Check ($r.Kind -ceq 'end' -and $s.Ended) 'Buffered descent can complete with the unchanged fresh grounded PASSED/end handshake'
foreach($bad in @((Sample 2 'JUMPING'),(Sample 2 'SETTLING' 0 63.625 0 $false),(Sample 2 'SETTLING' .02))){
    $s=BufferedState;$null=Receive $s (Begin)
    Reject {Receive $s $bad} 'Invalid buffered anchor gained ground provenance'
    Check (-not $s.GroundProved -and -not $s.AnchorVerified -and $s.LastSeq -eq 1) 'Rejected buffered anchor mutated provenance or sequence'
}
$s=BufferedState;$null=Receive $s (Begin);$bad=Sample 2 'SETTLING';$bad.server.proxy_support='true'
Reject {Receive $s $bad} 'Malformed buffered support flag gained ground provenance'
Check (-not $s.GroundProved -and -not $s.AnchorVerified -and $s.LastSeq -eq 1) 'Malformed buffered anchor mutated receiver state'
# A sustained, labelled stream must cross the old byte budget without changing
# source points, freshness, geometry or the unchanged 200-record ceiling.
. (Join-Path $root 'scripts/CoupledMovementProof.ps1')
Reject {New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $save -PhysicalMovement -ExtendedWalking} 'Extended nonbuffered receiver accepted'
function ExtendedState {New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $save -PhysicalMovement -BufferedPhysicalMovement -ExtendedWalking}
$ext=ExtendedState;$extendedBegin=Begin;$extendedBegin.source_kind='live_kcd_hud_physical_movement_extended'
Reject {Receive (BufferedState) $extendedBegin} 'Extended trace accepted by default receiver'
Reject {Receive $ext (Begin)} 'Short trace accepted by extended receiver'
Check ($ext.LastSeq -eq 0 -and $ext.Bytes -eq 0) 'Cross-profile rejection mutated receiver'
$null=Receive $ext $extendedBegin
$traceLines=[Collections.Generic.List[string]]::new()
$traceLines.Add(($extendedBegin | ConvertTo-Json -Depth 8 -Compress))
for($i=2;$i -le 163;$i++){
    $phase=if($i -eq 2){'SETTLING'}elseif($i -eq 163){'PASSED'}else{'RESTING'}
    $sample=Sample $i $phase
    $sample.source_kind='live_kcd_hud_physical_movement_extended'
    $sample.utc_ms=1000+($i-2)*100;$sample.monotonic_ns=[long]($i-2)*100000000
    $json=$sample | ConvertTo-Json -Depth 8 -Compress
    $r=Receive-MineComeMovementTrace $ext $json $sample.utc_ms
    if($r.Kind -cne 'sample' -or $r.Record.monotonic_ns -ne $sample.monotonic_ns){throw 'Sustained source changed or was omitted'}
    $traceLines.Add($json)
}
Check ($ext.Bytes -gt 65536 -and $ext.Bytes -lt 262144 -and $ext.Records -eq 163) 'Extended receiver did not actually exercise the larger byte budget'
$traceFile=Join-Path $dir 'extended.ndjson'
[IO.File]::WriteAllText($traceFile,([string]::Join("`n",$traceLines)+"`n"),[Text.UTF8Encoding]::new($false))
$reader=[pscustomobject]@{Path=$traceFile;Stream=$null;Bytes=[byte[]]::new(0)}
try{
    Reject {Read-CoupledTraceLines $reader} 'Default file reader accepted extended byte budget'
    Check (@(Read-CoupledTraceLines $reader -ExtendedWalking).Count -eq 163) 'Extended file reader omitted source lines'
    $rewrite=[IO.File]::Open($traceFile,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    try{$rewrite.WriteByte(32)}finally{$rewrite.Dispose()}
    Reject {Read-CoupledTraceLines $reader -ExtendedWalking} 'Extended stream prefix rewrite accepted'
}finally{if($reader.Stream){$reader.Stream.Dispose()}}
$ext.Bytes=262140
$beforeSeq=$ext.LastSeq
Reject {Receive $ext (Sample 164 'RESTING')} 'Extended stream byte bound ignored'
Check ($ext.LastSeq -eq $beforeSeq) 'Byte rejection consumed a source sequence'
$ext=ExtendedState;$null=Receive $ext $extendedBegin
$bad=Sample 2 SETTLING;$bad.source_kind='standalone_hud_physical_movement_extended_fixture'
Reject {Receive $ext $bad} 'Scripted extended fixture accepted as live evidence'
$bad.source_kind='live_kcd_hud_physical_movement_extended'
Check ((Receive $ext $bad 1301).Kind -ceq 'stale' -and -not $ext.GroundProved) 'Extended initial anchor bypassed freshness'
Write-Output "HUD_PHYSICAL_MOVEMENT_TESTS checks=$script:checks PASS"
