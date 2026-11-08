# Verifies saved native camera readbacks against the exact immutable fixture
# geometry. This script reads evidence only; it never starts or controls a game.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$EvidenceDirectory)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Camera collision verification failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayMovementHost.ps1')
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Owned-Path([string]$Path,[string]$Parent){
 $full=[IO.Path]::GetFullPath($Path);$base=[IO.Path]::GetFullPath($Parent).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
 Require ($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) 'Evidence path leaves its owned project directory.'
 $part=$full;while($part.Length -ge $base.Length){if(Test-Path -LiteralPath $part){Require (-not ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Evidence paths must not traverse links.'};$part=Split-Path -Parent $part}
 return $full
}
function Check-JsonElement($Element,[int]$Depth=0){
 Require ($Depth -le 32) 'Evidence JSON nesting exceeded32.'
 if($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object){
  $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($property in $Element.EnumerateObject()){Require ($names.Add($property.Name)) 'Duplicate evidence JSON field.';Check-JsonElement $property.Value ($Depth+1)}
 }elseif($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($value in $Element.EnumerateArray()){Check-JsonElement $value ($Depth+1)}}
}
function Parse-Json([string]$Text){$document=[Text.Json.JsonDocument]::Parse($Text);try{Require ($document.RootElement.ValueKind -eq [Text.Json.JsonValueKind]::Object) 'Evidence JSON must be an object.';Check-JsonElement $document.RootElement}finally{$document.Dispose()};return $Text|ConvertFrom-Json -Depth 32}
function Read-Json([string]$Path,[long]$Limit){
 $path=Owned-Path $Path $root;$item=Get-Item -LiteralPath $path -Force
 Require (-not $item.PSIsContainer -and $item.Length -ge 2 -and $item.Length -le $Limit) 'Evidence JSON byte bound differs.'
 return Parse-Json ([IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false,$true)))
}
function Vector($Value){
 Require ($Value -is [pscustomobject] -and (($Value.PSObject.Properties.Name|Sort-Object)-join ',') -ceq 'x,y,z') 'Native camera vector fields differ.'
 foreach($axis in 'x','y','z'){Require ((Test-GameplayHostNumber $Value.$axis) -and [Math]::Abs($Value.$axis) -lt 10000000) 'Native camera vector is invalid.'}
 return @([double]$Value.x,[double]$Value.y,[double]$Value.z)
}
function Number($Value){Require (Test-GameplayHostNumber $Value) 'Native camera number is not finite.';return [double]$Value}
function True-Flag($Value,[string]$Message){Require ($Value -is [bool] -and $Value) $Message}
function False-Flag($Value,[string]$Message){Require ($Value -is [bool] -and -not $Value) $Message}
# Earliest entry of a ray into the closed AABB, including starting inside.
# The production controller reserves0.12m around each shape; readback may differ
# by0.03m, so an actual segment may penetrate no further than that tolerance.
function Entry-Distance([double[]]$Origin,[double[]]$Direction,[double[]]$Box,[double]$Length){
 $entry=0.;$leave=$Length
 for($axis=0;$axis -lt 3;$axis++){
  $minimum=$Box[$axis]-.12;$maximum=$Box[$axis+3]+.12;$at=$Origin[$axis];$speed=$Direction[$axis]
  if([Math]::Abs($speed) -lt 1e-10){if($at -lt $minimum -or $at -gt $maximum){return [double]::PositiveInfinity}}
  else{$a=($minimum-$at)/$speed;$b=($maximum-$at)/$speed;if($a -gt $b){$swap=$a;$a=$b;$b=$swap};$entry=[Math]::Max($entry,$a);$leave=[Math]::Min($leave,$b);if($entry -gt $leave){return [double]::PositiveInfinity}}
 }
 return $entry
}
$directory=Owned-Path ([IO.Path]::GetFullPath($EvidenceDirectory)) (Join-Path $root 'runtime/evidence')
$output=Join-Path $directory 'camera-collision-verification.json';Require (-not (Test-Path -LiteralPath $output)) 'Camera verification already exists; preserving its original receipt.'
$result=[ordered]@{schema=1;kind='minecome_native_camera_collision_verification_v1';result='failed';failure=$null;run=$null;actual_native_readbacks=$false;fixture_geometry_only=$true;vanilla_placement_verified=$false}
try{
 $native=Read-Json (Join-Path $directory 'verification.json') 65536
 $session=Read-Json (Join-Path $directory 'gameplay-session.json') 1MB
 $hostProof=Read-Json (Join-Path $directory 'host-movement.json') 65536
 Require ($native.schema -eq 1 -and $native.kind -ceq 'minecome_gameplay_kcd_session_v1' -and $native.run -cmatch '^[0-9a-f]{32}$') 'Original native run identity differs.'
 $run=[string]$native.run;$result.run=$run
 Require ($native.result -ceq 'passed' -and $null -eq $native.failure) 'Original native session did not pass.';True-Flag $native.normal_client_exit 'Minecraft did not exit normally.'
 Require ($session.schema -eq 1 -and $session.kind -ceq 'minecome_gameplay_session_v1' -and $session.run -ceq $run -and $null -eq $session.failure) 'Guest session identity/failure differs.'
 False-Flag $session.standalone 'Standalone output cannot verify native camera collision.'
 foreach($flag in 'normal_shutdown_requested','producer_finished','input_cleanup_complete','world_blocks_enabled','native_perspective_connected'){True-Flag $session.$flag "Missing guest proof: $flag"}
 Require ($null -eq $session.producer_failure -and $null -eq $hostProof.Failure) 'Producer/native host failed.'
 True-Flag $hostProof.Stopped 'Native host is still active.';True-Flag $hostProof.ResourcesClosed 'Native resources were not closed.'
 $terminal=$hostProof.Terminal;Require ($terminal.run -ceq $run -and $terminal.event -ceq 'terminal' -and $terminal.result -ceq 'explicit_stop') 'Native terminal receipt differs.'
 False-Flag $terminal.active 'Native terminal remained active.';True-Flag $terminal.camera_restored 'Native camera not restored.';True-Flag $terminal.body_restore_dispatched 'Native body not restored.';False-Flag $terminal.body_hidden 'Native body remained hidden.'
 $instance=Owned-Path ([string]$native.instance) (Join-Path $root 'runtime/gameplay')
 $fixturePath=Join-Path $instance 'native-depth-fixture.json';$fixture=Read-Json $fixturePath 2MB
 Require ($fixture.schema -eq 1 -and $fixture.kind -ceq 'minecome_native_depth_fixture_preparation_v1' -and $fixture.destination_instance -ceq $instance -and $fixture.world_id -ceq $session.world_id) 'Fixture source identity differs.'
 True-Flag $fixture.fixture_only 'Source is not an isolated fixture.';False-Flag $fixture.vanilla_placement_verified 'Fixture must not claim vanilla placement.'
 $patchPath=Join-Path $instance 'saves/MineCome-Gameplay/minecome-terrain/ground-patch.json';$patch=Read-Json $patchPath 131072
 $patchHash=(Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
 Require ($patch.provenance.kind -ceq 'live_kcd_ground_patch' -and $fixture.patch_run -ceq $patch.run -and $fixture.patch_sha256 -ceq $patchHash) 'Fixture terrain provenance/hash differs.'
 $posePath=Join-Path $directory 'gameplay-pose.json';$savedPose=Read-Json $posePath 20480
 $identity=[pscustomobject]@{Run=$run;WorldId=$session.world_id;Pid=$native.target_pid;Start=$native.target_start_filetime;PatchRun=$patch.run;PatchHash=$patchHash;CameraOrigin=[pscustomobject]@{x=[double]$patch.center.x;y=[double]$patch.center.y;z=[double]$patch.center.z-64.}}
 $bounds=[pscustomobject]@{MinX=-9999999.;MaxX=9999999.;MinY=-9999999.;MaxY=9999999.;MinZ=-9999999.;MaxZ=9999999.}
 $pose=Read-GameplayMovementPose $posePath $identity $bounds 0 -1 ([long]$savedPose.utc_ms) $true;Require ($null -ne $pose) 'Saved geometry pose is unavailable.'
 $geometry=$pose.camera_collision;True-Flag $geometry.complete 'Final camera geometry is incomplete.'
 $boxes=[Collections.Generic.List[double[]]]::new();$mcBoxes=[Collections.Generic.List[string]]::new()
 for($offset=0;$offset -lt $geometry.boxes.Length;$offset+=24){
  $q=@(for($i=0;$i -lt 6;$i++){$n=[Convert]::ToInt32($geometry.boxes.Substring($offset+$i*4,4),16);if($n -ge 32768){$n-=65536};$n/16.0})
  $boxes.Add([double[]]@(($geometry.origin.x+$q[0]),($geometry.origin.y-$q[5]),($geometry.origin.z+$q[1]),($geometry.origin.x+$q[3]),($geometry.origin.y-$q[2]),($geometry.origin.z+$q[4])))
  $mcBoxes.Add(($q -join ','))
 }
 Require ($boxes.Count -eq 8 -and @($fixture.cells).Count -eq 8 -and $session.blocks.owned_count -eq 8 -and $session.blocks.places -eq 0 -and $session.blocks.breaks -eq 0) 'Expected unchanged eight-cell camera walls are missing.'
 $expectedCells=@(foreach($x in -1,0){foreach($y in 65,66){foreach($z in -3,2){"$x,$y,$z,minecraft:magenta_concrete"}}})
 foreach($set in @(@($fixture.cells),@($session.blocks.blocks))){$actual=@($set|ForEach-Object {"$($_.x),$($_.y),$($_.z),$($_.state)"});Require ((($actual|Sort-Object)-join '|') -ceq (($expectedCells|Sort-Object)-join '|')) 'Controlled wall coordinates/state differ.'}
 $expectedBoxes=@($fixture.cells|ForEach-Object {"$($_.x),$($_.y),$($_.z),$($_.x+1),$($_.y+1),$($_.z+1)"})
 Require ((($mcBoxes|Sort-Object)-join '|') -ceq (($expectedBoxes|Sort-Object)-join '|')) 'Packed geometry differs from actual owned fixture cubes.'
 $logPath=Owned-Path (Join-Path $directory 'native-movement.log') $root;$logItem=Get-Item -LiteralPath $logPath
 Require ($logItem.Length -gt 0 -and $logItem.Length -le 32MB) 'Preserved native log size differs.'
 $summary=@{};foreach($mode in 1,2){$summary[$mode]=[ordered]@{samples=0;clipped_samples=0;min_offset=2.53;max_offset=0.;max_penetration=0.}}
 $lastSeq=0L;$lastClock=-1.;$seenCommitted=$false;$viewCount=0;$startupViews=0;$lineCount=0;$terminalSeen=$false
 foreach($line in [IO.File]::ReadLines($logPath)){
  $lineCount++;Require ($lineCount -le 100000 -and $line.Length -le 16384) 'Native log line/count bound differs.'
  if($line -notmatch '\[MineComeGameplayMovement\] (\{[^\r\n]*\})\s*$'){continue}
  $r=Parse-Json $Matches[1];if($r.run -cne $run){continue};Require ($r.schema -eq 1) 'Native receipt schema differs.'
  if($r.event -ceq 'terminal'){Require ($r.result -ceq 'explicit_stop' -and $r.applied_seq -eq $terminal.applied_seq) 'Preserved log terminal differs.';$terminalSeen=$true;continue}
  if($r.event -cne 'view'){continue};Require (-not $terminalSeen) 'Native view appears after terminal.'
  Require ((Number $r.seq) -gt $lastSeq -and $r.seq -eq [Math]::Floor($r.seq)) 'Native view sequence repeated/regressed.';$lastSeq=[long]$r.seq
  $clock=Number $r.sampled_engine_seconds;Require ($clock -ge $lastClock) 'Native engine clock regressed.';$lastClock=$clock
  Require ($r.result -ceq 'sampled') 'Native view is not acknowledged.';True-Flag $r.active 'Native sampled view is inactive.';True-Flag $r.camera_basis_valid 'Native sampled camera basis invalid.'
  Require ($r.perspective -in @(0,1,2)) 'Native perspective differs.'
  if(-not $seenCommitted -and $r.perspective -eq 0 -and $r.camera_collision_generation -eq 0 -and $r.camera_collision_required -eq 0){$startupViews++;continue}
  Require ($r.camera_collision_generation -eq $geometry.generation -and $r.camera_collision_required -eq $geometry.generation) 'Geometry generation changed or is missing; full geometry history is required.'
  True-Flag $r.camera_collision_complete 'A native view used incomplete geometry.';Require ($r.camera_collision_boxes -eq $boxes.Count) 'Native geometry box count differs.';$seenCommitted=$true;$viewCount++
  if($r.perspective -eq 0){continue}
  $eye=Vector $r.eye;$camera=Vector $r.camera;$forward=Vector $r.camera_forward
  $delta=@(for($i=0;$i -lt 3;$i++){$camera[$i]-$eye[$i]});$length=[Math]::Sqrt(($delta|ForEach-Object {$_*$_}|Measure-Object -Sum).Sum)
  Require ($length -le 2.53) 'Actual native camera exceeds2.5m plus readback tolerance.'
  $unitLength=[Math]::Sqrt(($forward|ForEach-Object {$_*$_}|Measure-Object -Sum).Sum);Require ([Math]::Abs($unitLength-1) -le .001) 'Native camera direction is not unit length.'
  $orbitDirection=[double[]]@($forward|ForEach-Object {-$_/$unitLength});$expectedReach=2.5;$penetration=0.
  foreach($box in $boxes){
   $entry=Entry-Distance $eye $orbitDirection $box 2.5;if($entry -le 2.5){$expectedReach=[Math]::Min($expectedReach,[Math]::Max(0,$entry-.03))}
   if($length -gt 1e-9){$direction=[double[]]@($delta|ForEach-Object {$_/$length});$actualEntry=Entry-Distance $eye $direction $box $length;if($actualEntry -le $length){$penetration=[Math]::Max($penetration,$length-$actualEntry)}}
  }
  Require ($penetration -le .030001) 'Actual eye-to-camera segment enters an expanded Minecraft shape beyond readback tolerance.'
  $mode=[int]$r.perspective;$s=$summary[$mode];$s.samples++;$s.min_offset=[Math]::Min($s.min_offset,$length);$s.max_offset=[Math]::Max($s.max_offset,$length);$s.max_penetration=[Math]::Max($s.max_penetration,$penetration)
  if($expectedReach -lt 2.49 -and $length -lt 2.49){$s.clipped_samples++}
 }
 Require ($terminalSeen -and $viewCount -gt 0) 'Native view/terminal log evidence is incomplete.'
 foreach($mode in 1,2){Require ($summary[$mode].samples -gt 0 -and $summary[$mode].clipped_samples -gt 0) "Perspective$mode lacks a native camera sample clipped against the fixture walls."}
 $result.result='passed';$result.actual_native_readbacks=$true;$result.world_id=$session.world_id;$result.target_pid=$native.target_pid;$result.target_start_filetime=$native.target_start_filetime
 $result.geometry_generation=$geometry.generation;$result.geometry_boxes=$boxes.Count;$result.camera_clearance_metres=.12;$result.readback_tolerance_metres=.03;$result.view_samples=$viewCount;$result.pregeometry_first_person_samples=$startupViews
 $result.back=$summary[1];$result.front=$summary[2];$result.fixture_source=$fixturePath;$result.fixture_walls=$fixture.cells;$result.fixture_eight_wall_cells_verified=$true
 $result.source_sha256=[ordered]@{pose=(Get-FileHash $posePath).Hash.ToLowerInvariant();native_log=(Get-FileHash $logPath).Hash.ToLowerInvariant();fixture=(Get-FileHash $fixturePath).Hash.ToLowerInvariant()}
 $result.normal_client_exit=$true;$result.camera_restored=$true;$result.body_restored=$true
}catch{$result.failure=$_.Exception.Message;throw}
finally{$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $output -Encoding utf8NoBOM}
Write-Output "NATIVE_CAMERA_COLLISION_PASS evidence=$directory back=$($summary[1].samples) front=$($summary[2].samples)"
