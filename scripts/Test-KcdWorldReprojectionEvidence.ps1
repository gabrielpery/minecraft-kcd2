# Evidence only. PASS proves execution, not high coverage or resolved foliage flicker.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$EvidenceDirectory)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "World reprojection verification failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Owned([string]$Path){
 $full=[IO.Path]::GetFullPath($Path);$base=(Join-Path $root 'runtime/evidence').TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
 Require ($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) 'Evidence path leaves runtime/evidence.'
 $part=$full;while($part.Length -ge $base.Length){if(Test-Path -LiteralPath $part){Require (-not ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Evidence path traverses a link.'};$part=Split-Path -Parent $part};return $full
}
function Check-Json($Element,[int]$Depth=0){
 Require ($Depth -le 32) 'Evidence JSON nesting exceeds32.'
 if($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object){$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in $Element.EnumerateObject()){Require ($names.Add($p.Name)) 'Duplicate JSON field.';Check-Json $p.Value ($Depth+1)}}
 elseif($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($v in $Element.EnumerateArray()){Check-Json $v ($Depth+1)}}
}
function Parse([string]$Text){$doc=[Text.Json.JsonDocument]::Parse($Text);try{Require ($doc.RootElement.ValueKind -eq [Text.Json.JsonValueKind]::Object) 'JSON is not an object.';Check-Json $doc.RootElement}finally{$doc.Dispose()};return $Text|ConvertFrom-Json -Depth 32}
function Json([string]$Path){$item=Get-Item -LiteralPath (Owned $Path);Require (-not $item.PSIsContainer -and $item.Length -ge 2 -and $item.Length -le 2MB) 'Evidence JSON size differs.';return Parse ([IO.File]::ReadAllText($item.FullName,[Text.UTF8Encoding]::new($false,$true)))}
function Number($Value){Require ($Value -is [ValueType] -and $Value -isnot [bool] -and [double]::IsFinite([double]$Value) -and $Value -ge 0 -and $Value -le 9007199254740991 -and $Value -eq [Math]::Floor([double]$Value)) 'Counter/timestamp is not an exact nonnegative integer.';return [long]$Value}
function Hash([string]$Path){return (Get-FileHash -LiteralPath (Owned $Path) -Algorithm SHA256).Hash.ToLowerInvariant()}
$directory=Owned $EvidenceDirectory;Require (Test-Path -LiteralPath $directory -PathType Container) 'Evidence directory is missing.'
$output=Join-Path $directory 'world-reprojection-verification.json';Require (-not (Test-Path -LiteralPath $output)) 'World reprojection verification already exists; refusing to overwrite evidence.'
$proof=[ordered]@{schema=1;kind='minecome_native_world_reprojection_verification_v1';result='failed';failure=$null;run=$null;world_id=$null;acceptance_scope='nonzero reprojected execution with current native presentation proof';high_coverage_verified=$false;subjective_foliage_appearance_verified=$false;physical_input_verified=$false;verifier_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()}
try{
 $paths=[ordered]@{foliage=(Join-Path $directory 'foliage-depth-verification.json');walking=(Join-Path $directory 'native-walking-verification.json');native=(Join-Path $directory 'verification.json');session=(Join-Path $directory 'gameplay-session.json');native_depth_log=(Join-Path $directory 'native-depth-addon.log')}
 $foliage=Json $paths.foliage;$walking=Json $paths.walking;$native=Json $paths.native;$session=Json $paths.session
 $run=[string]$walking.run;$proof.run=$run;$proof.world_id=$walking.world_id
 Require ($run -cmatch '^[0-9a-f]{32}$' -and $foliage.run -ceq $run -and $native.run -ceq $run -and $session.run -ceq $run -and $foliage.world_id -ceq $walking.world_id -and $session.world_id -ceq $walking.world_id) 'Evidence identities differ.'
 Require ($native.kind -ceq 'minecome_gameplay_kcd_session_v1' -and $native.result -ceq 'passed' -and -not $native.failure -and $session.kind -ceq 'minecome_gameplay_session_v1' -and -not $session.failure -and $session.fixture.result -ceq 'passed') 'Native gameplay did not pass.'
 Require ($walking.kind -ceq 'minecome_native_third_person_walking_verification_v1' -and $walking.result -ceq 'passed') 'Walking verification did not pass.'
 foreach($name in @('actual_minecraft','live_kcd_camera_acknowledged','normal_client_exit','camera_restored','body_restored')){Require ($walking.$name -is [bool] -and $walking.$name) "Walking proof lacks $name."}
 Require ($foliage.kind -ceq 'minecome_native_foliage_depth_verification_v1' -and ($foliage.result -ceq 'passed' -or ($foliage.result -ceq 'failed' -and $foliage.failure -clike 'Stationary depth was unstable:*'))) 'Foliage receipt did not finish structural validation.'
 # Existing v1 remains immutable. Its failure is allowed only for the separately
 # reported coverage requirement, after all identities/times/counters/hashes passed.
 $hashes=[ordered]@{};foreach($name in $paths.Keys){$hashes[$name]=Hash $paths[$name];if($name -cne 'foliage'){Require ($foliage.source_sha256.$name -cmatch '^[0-9a-f]{64}$' -and $foliage.source_sha256.$name -ceq $hashes[$name]) "Source hash differs from validated foliage receipt: $name"}}
 $proof.source_sha256=$hashes;$proof.foliage_depth_result=$foliage.result;$proof.foliage_depth_failure=$foliage.failure
 $start=Number $walking.stationary_back_started_utc_ms;$end=Number $walking.stationary_back_completed_utc_ms
 Require ($end-$start -ge 12000 -and $foliage.stationary_started_utc_ms -eq $start -and $foliage.stationary_completed_utc_ms -eq $end -and $session.fixture.stationary_back_started_utc_ms -eq $start -and $session.fixture.stationary_back_completed_utc_ms -eq $end) 'Stationary intervals differ.'
 $movingImage=@($session.fixture.images|Where-Object stage -CEQ 'back_walking');$lastStep=@($session.fixture.points|Where-Object stage -CEQ 'front_stride_6')
 Require ($movingImage.Count -eq 1 -and $lastStep.Count -eq 1 -and $walking.back_strides -ge 6 -and $walking.front_strides -ge 6 -and $movingImage[0].metadata.native_walking_motion.client_speed -ge 0.04 -and $movingImage[0].metadata.native_walking_motion.limb_speed -ge 0.1) 'Walking window lacks the verified moving capture and final stride.'
 $movingStart=Number $movingImage[0].metadata.captured_utc_ms;$movingEnd=Number $lastStep[0].native_sample_utc_ms
 Require ($movingStart -ge $end -and $movingEnd-$movingStart -ge 4000 -and $movingEnd-$movingStart -le 30000) 'Walking sequence timestamp window differs.'
 $zone=[TimeZoneInfo]::Local;Require ($foliage.timestamp_timezone -ceq $zone.Id) 'Evidence local timezone differs.'
 $anchor=[DateTimeOffset]::FromUnixTimeMilliseconds($start+($end-$start)/2);$localDay=[TimeZoneInfo]::ConvertTime($anchor,$zone).Date
 function Log-Utc([string]$Clock){
  $time=[TimeSpan]::ParseExact($Clock,'hh\:mm\:ss\:fff',[Globalization.CultureInfo]::InvariantCulture);Require ($time.TotalHours -lt 24) 'Log clock is outside its day.'
  $dates=@(foreach($offset in -1,0,1){$local=[DateTime]::SpecifyKind($localDay.AddDays($offset).Add($time),[DateTimeKind]::Unspecified);if($zone.IsInvalidTime($local)){continue};$utc=[DateTimeOffset]::new([TimeZoneInfo]::ConvertTimeToUtc($local,$zone)).ToUnixTimeMilliseconds();[pscustomobject]@{Utc=$utc;Distance=[Math]::Abs($utc-$anchor.ToUnixTimeMilliseconds());Ambiguous=$zone.IsAmbiguousTime($local)}})|Sort-Object Distance
  Require ($dates.Count -gt 0 -and -not $dates[0].Ambiguous -and ($dates.Count -eq 1 -or $dates[0].Distance -ne $dates[1].Distance)) 'Log UTC mapping is ambiguous.';return [long]$dates[0].Utc
 }
 $item=Get-Item -LiteralPath $paths.native_depth_log;Require (-not $item.PSIsContainer -and $item.Length -gt 0 -and $item.Length -le 32MB) 'Native log size differs.'
 $records=[Collections.Generic.List[object]]::new();$names=@();$arm=$null;$closed=$null;$lastUtc=-1L;$lines=0
 foreach($line in [IO.File]::ReadLines($paths.native_depth_log)){
  $lines++;Require ($lines -le 100000 -and $line.Length -le 16384) 'Native log exceeds its bound.'
  if($line -notmatch '^(\d{2}:\d{2}:\d{2}:\d{3})\s+.*\[MineComeHudInput\]\s+(\{[^\r\n]*\})\s*$'){Require (-not $line.Contains('"event":"host_depth"')) 'Malformed depth record.';continue}
  $clock=$Matches[1];$r=Parse $Matches[2];if($r.event -ceq 'host_depth'){Require ($r.run -ceq $run) 'Native log contains another depth run.'};if($r.run -cne $run){continue}
  $utc=Log-Utc $clock;Require ($utc -ge $lastUtc) 'Native log timestamps regressed.';$lastUtc=$utc
  if($r.event -ceq 'arm'){Require ($null -eq $arm -and $r.result -ceq 'accepted') 'Native arm differs.';$arm=$utc}
  elseif($r.event -ceq 'session_end'){Require ($null -eq $closed -and $r.result -ceq 'closed') 'Native close differs.';$closed=$utc}
  elseif($r.event -ceq 'first_input_close'){Require ([Math]::Abs((Number $r.closed_utc_ms)-$utc) -le 1000) 'Explicit native close UTC differs.'}
  if($r.event -cne 'host_depth'){continue}
  $fields=@($r.PSObject.Properties.Name|Where-Object {$_ -cnotin @('event','run')}|Sort-Object)
  if(-not $records.Count){$names=$fields;foreach($required in @('considered','composited','no_sample','bad_view','bad_source','sample_age','camera_age','position','basis','projection','other_view','reprojected','warp_rejected','presentation_seals','presentation_accepted','presentation_identity','presentation_missing','presentation_ambiguous','presentation_unknown','presentation_overflow','presentation_age')){Require ($required -cin $names) "Native counter missing: $required"}}
  Require (($names -join ',') -ceq ($fields -join ',')) 'Native counter schema changed within the run.'
  $counts=[ordered]@{};foreach($name in $names){$counts[$name]=Number $r.$name;if($records.Count){Require ($counts[$name] -ge $records[-1].Counts[$name]) "Native counter regressed: $name"}}
  Require ($counts.considered -eq $counts.composited+$counts.no_sample+$counts.bad_view+$counts.bad_source -and $counts.bad_view -eq $counts.sample_age+$counts.camera_age+$counts.position+$counts.basis+$counts.projection+$counts.other_view) 'Native depth counters do not reconcile.'
  Require ($counts.reprojected -le $counts.composited -and $counts.presentation_accepted -le $counts.presentation_seals) 'Reprojection/current-presentation counters are inconsistent.'
  # Reasons count take attempts (including attempts before the first seal),
  # while seals count presentation callbacks; they are not a partition of seals.
  if('strict_fallback' -cin $names){Require ($counts.reprojected+$counts.strict_fallback -le $counts.composited) 'Strict fallback and reprojection overlap.'}
  $records.Add([pscustomobject]@{Utc=$utc;Counts=$counts})
 }
 Require ($null -ne $arm -and $null -ne $closed -and $arm -le $start -and $closed -ge $movingEnd -and $closed-$arm -le (Number $session.active_ms)+5000) 'Fixture intervals leave the acknowledged native run.'
 foreach($r in $records){Require ($r.Utc -ge $arm -and $r.Utc -le $closed) 'Counter is outside the native run.'}
 function Window([long]$From,[long]$To){
  $intervals=[Collections.Generic.List[object]]::new();$totals=[ordered]@{};foreach($name in $names){$totals[$name]=0L};$covered=0L
  for($i=1;$i -lt $records.Count;$i++){$a=$records[$i-1];$b=$records[$i];if($a.Utc -lt $From -or $b.Utc -gt $To){continue};$duration=$b.Utc-$a.Utc;Require ($duration -gt 0) 'Counter interval has no duration.';if($duration -lt 4000){continue};$delta=[ordered]@{};foreach($name in $names){$delta[$name]=$b.Counts[$name]-$a.Counts[$name];$totals[$name]+=$delta[$name]};$covered+=$duration;$intervals.Add([ordered]@{started_utc_ms=$a.Utc;completed_utc_ms=$b.Utc;duration_ms=$duration;counters=$delta;reprojected_fraction=$(if($delta.considered){$delta.reprojected/[double]$delta.considered}else{0.})})}
  return [ordered]@{started_utc_ms=$From;completed_utc_ms=$To;covered_ms=$covered;complete_intervals=$intervals.ToArray();counters=$totals;reprojected_fraction=$(if($totals.considered){$totals.reprojected/[double]$totals.considered}else{0.});composited_fraction=$(if($totals.considered){$totals.composited/[double]$totals.considered}else{0.})}
 }
 $stationary=Window $start $end;$moving=Window $movingStart $movingEnd
 $proof.stationary=$stationary;$proof.walking_sequence=$moving;$proof.walking_sequence_includes_release_and_inventory_pauses=$true;$proof.strict_fallback_counter_available=('strict_fallback' -cin $names)
 Require ($stationary.covered_ms -eq $foliage.covered_ms) 'Stationary counter coverage differs from validated foliage receipt.'
 foreach($p in $foliage.counters.PSObject.Properties){Require ($stationary.counters[$p.Name] -eq $p.Value) "Stationary counter differs from validated foliage receipt: $($p.Name)"}
 foreach($window in @($stationary,$moving)){
  Require ($window.covered_ms -ge 4000 -and $window.counters.considered -ge 120) 'Insufficient fully-contained stationary/walking evidence (need4 seconds and120 frames each).'
  foreach($interval in $window.complete_intervals){$c=$interval.counters;Require ($c.reprojected -le $c.composited -and $c.composited -le $c.considered -and ($c.reprojected -eq 0 -or $c.presentation_accepted -gt 0)) 'An interval lacks matching composition/current-presentation evidence.'}
 }
 foreach($name in $paths.Keys){Require ((Hash $paths[$name]) -ceq $hashes[$name]) "Evidence changed during verification: $name"}
 $executed=$stationary.counters.reprojected+$moving.counters.reprojected;$current=$stationary.counters.presentation_accepted+$moving.counters.presentation_accepted
 $proof.reprojected_frames=$executed;$proof.accepted_native_presentations=$current
 Require ($executed -gt 0 -and $current -gt 0) "No reprojected execution with current native presentation proof: reprojected=$executed, native_presentations=$current"
 $proof.result='passed'
}catch{$proof.failure=$_.Exception.Message}
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($proof|ConvertTo-Json -Depth 16));$file=[IO.FileStream]::new($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$file.Write($bytes);$file.Flush($true)}finally{$file.Dispose()}
if($proof.result -cne 'passed'){throw "World reprojection evidence failed: $($proof.failure) Saved $output"}
Write-Output "NATIVE_WORLD_REPROJECTION_EXECUTION_PASS evidence=$directory reprojected=$($proof.reprojected_frames) stationary_fraction=$($proof.stationary.reprojected_fraction) walking_sequence_fraction=$($proof.walking_sequence.reprojected_fraction) high_coverage_verified=false visual_fix_verified=false"
