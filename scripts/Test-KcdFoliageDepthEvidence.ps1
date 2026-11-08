# Saved native depth evidence only; never starts or controls either game.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$EvidenceDirectory)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Foliage depth verification failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Owned-Path([string]$Path){
 $full=[IO.Path]::GetFullPath($Path);$base=(Join-Path $root 'runtime/evidence').TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
 Require ($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) 'Evidence path leaves runtime/evidence.'
 $part=$full;while($part.Length -ge $base.Length){if(Test-Path -LiteralPath $part){Require (-not ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Evidence path traverses a link.'};$part=Split-Path -Parent $part}
 return $full
}
function Check-Json($Element,[int]$Depth=0){
 Require ($Depth -le 32) 'Evidence JSON nesting exceeds32.'
 if($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object){$names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($p in $Element.EnumerateObject()){Require ($names.Add($p.Name)) 'Duplicate evidence JSON field.';Check-Json $p.Value ($Depth+1)}}
 elseif($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($v in $Element.EnumerateArray()){Check-Json $v ($Depth+1)}}
}
function Parse-Json([string]$Text){$doc=[Text.Json.JsonDocument]::Parse($Text);try{Require ($doc.RootElement.ValueKind -eq [Text.Json.JsonValueKind]::Object) 'Evidence JSON is not an object.';Check-Json $doc.RootElement}finally{$doc.Dispose()};return $Text|ConvertFrom-Json -Depth 32}
function Read-Json([string]$Path){$path=Owned-Path $Path;$item=Get-Item -LiteralPath $path;Require (-not $item.PSIsContainer -and $item.Length -ge 2 -and $item.Length -le 2MB) 'Evidence JSON size differs.';return Parse-Json ([IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false,$true)))}
function Counter($Value){Require ($Value -is [ValueType] -and $Value -isnot [bool] -and [double]::IsFinite([double]$Value) -and $Value -ge 0 -and $Value -le 9007199254740991 -and $Value -eq [Math]::Floor([double]$Value)) 'Depth counter/timestamp is not a nonnegative exact integer.';return [long]$Value}
function True-Flag($Value,[string]$Message){Require ($Value -is [bool] -and $Value) $Message}
$directory=Owned-Path $EvidenceDirectory;Require (Test-Path -LiteralPath $directory -PathType Container) 'Evidence directory is missing.'
$output=Join-Path $directory 'foliage-depth-verification.json';Require (-not (Test-Path -LiteralPath $output)) 'Foliage depth verification already exists; refusing to overwrite evidence.'
$proof=[ordered]@{schema=1;kind='minecome_native_foliage_depth_verification_v1';result='failed';failure=$null;run=$null;world_id=$null;actual_native_depth_counters=$true;physical_input_verified=$false;subjective_foliage_appearance_verified=$false}
try{
 $nativePath=Join-Path $directory 'verification.json';$walkingPath=Join-Path $directory 'native-walking-verification.json';$sessionPath=Join-Path $directory 'gameplay-session.json'
 $native=Read-Json $nativePath;$walking=Read-Json $walkingPath;$session=Read-Json $sessionPath
 $run=[string]$walking.run;$proof.run=$run;$proof.world_id=$walking.world_id
 Require ($run -cmatch '^[0-9a-f]{32}$' -and $native.run -ceq $run -and $session.run -ceq $run -and $session.world_id -ceq $walking.world_id) 'Saved native/walking/session identities differ.'
 Require ($native.kind -ceq 'minecome_gameplay_kcd_session_v1' -and $native.result -ceq 'passed' -and -not $native.failure -and -not $session.failure) 'Native gameplay verification did not pass.'
 Require ($walking.kind -ceq 'minecome_native_third_person_walking_verification_v1' -and $walking.result -ceq 'passed' -and $session.fixture.result -ceq 'passed') 'Native walking verification did not pass.'
 foreach($name in @('actual_minecraft','live_kcd_camera_acknowledged','normal_client_exit','camera_restored','body_restored')){True-Flag $walking.$name "Walking proof lacks $name."}
 True-Flag $native.normal_client_exit 'Native client did not exit normally.'
 $start=Counter $walking.stationary_back_started_utc_ms;$end=Counter $walking.stationary_back_completed_utc_ms;$dwell=Counter $walking.stationary_back_dwell_ms
 Require ($dwell -ge 12000 -and $end-$start -ge 12000 -and [Math]::Abs(($end-$start)-$dwell) -le 100) 'Stationary dwell does not prove12 seconds with consistent clocks.'
 foreach($name in @('stationary_back_started_utc_ms','stationary_back_completed_utc_ms','stationary_back_dwell_ms')){Require ($walking.$name -eq $session.fixture.$name) 'Walking/session stationary interval differs.'}
 $proof.stationary_started_utc_ms=$start;$proof.stationary_completed_utc_ms=$end;$proof.stationary_dwell_ms=$dwell
 $zone=[TimeZoneInfo]::Local;$anchor=[DateTimeOffset]::FromUnixTimeMilliseconds($start+($end-$start)/2);$localDay=[TimeZoneInfo]::ConvertTime($anchor,$zone).Date
 $proof.timestamp_timezone=$zone.Id
 function Resolve-LogUtc([string]$Clock){
  $time=[TimeSpan]::ParseExact($Clock,'hh\:mm\:ss\:fff',[Globalization.CultureInfo]::InvariantCulture);Require ($time.TotalHours -lt 24) 'Log clock is outside its local day.'
  $candidates=@(foreach($offset in -1,0,1){
   $local=[DateTime]::SpecifyKind($localDay.AddDays($offset).Add($time),[DateTimeKind]::Unspecified)
   if($zone.IsInvalidTime($local)){continue}
   $ambiguous=$zone.IsAmbiguousTime($local)
   $utc=[DateTimeOffset]::new([TimeZoneInfo]::ConvertTimeToUtc($local,$zone)).ToUnixTimeMilliseconds()
   [pscustomobject]@{Utc=$utc;Distance=[Math]::Abs($utc-$anchor.ToUnixTimeMilliseconds());Ambiguous=$ambiguous}
  });$candidates=@($candidates|Sort-Object Distance)
  Require ($candidates.Count -gt 0 -and -not $candidates[0].Ambiguous -and ($candidates.Count -eq 1 -or $candidates[0].Distance -ne $candidates[1].Distance)) 'Log date/time mapping is ambiguous.'
  return [long]$candidates[0].Utc
 }
 $logPath=Owned-Path (Join-Path $directory 'native-depth-addon.log');$logItem=Get-Item -LiteralPath $logPath
 Require (-not $logItem.PSIsContainer -and $logItem.Length -gt 0 -and $logItem.Length -le 32MB) 'Native depth log size differs.'
 $logHash=(Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()
 $names=@('reflected','reflection_rejected','mapped','map_failed','non_upload','view_rejected','accepted','submitted','composited','considered','no_sample','bad_view','bad_source','ready_changes','sample_age','camera_age','position','basis','projection','other_view')
 $failureNames=@('map_failed','no_sample','bad_view','bad_source','sample_age','camera_age','position','basis','projection','other_view')
 $records=[Collections.Generic.List[object]]::new();$arm=$null;$closed=$null;$lastUtc=-1L;$lines=0
 foreach($line in [IO.File]::ReadLines($logPath)){
  $lines++;Require ($lines -le 100000 -and $line.Length -le 16384) 'Native depth log exceeds its line/count bound.'
  if($line -notmatch '^(\d{2}:\d{2}:\d{2}:\d{3})\s+.*\[MineComeHudInput\]\s+(\{[^\r\n]*\})\s*$'){Require (-not $line.Contains('"event":"host_depth"')) 'Malformed depth counter line.';continue}
  $clockText=$Matches[1];$r=Parse-Json $Matches[2]
  if($r.event -ceq 'host_depth'){Require ($r.run -ceq $run) 'Depth log contains another run.'}
  if($r.run -cne $run){continue}
  $utc=Resolve-LogUtc $clockText;Require ($utc -ge $lastUtc) 'Native log timestamps regressed.';$lastUtc=$utc
  if($r.event -ceq 'arm'){Require ($null -eq $arm -and $r.result -ceq 'accepted') 'Native depth arm identity differs.';$arm=$utc}
  elseif($r.event -ceq 'session_end'){Require ($null -eq $closed -and $r.result -ceq 'closed') 'Native depth session did not close once.';$closed=$utc}
  elseif($r.event -ceq 'first_input_close'){Require ([Math]::Abs((Counter $r.closed_utc_ms)-$utc) -le 1000) 'Local log date differs from explicit native close UTC.'}
  if($r.event -cne 'host_depth'){continue}
  $counts=[ordered]@{};foreach($name in $names){$counts[$name]=Counter $r.$name;if($records.Count){Require ($counts[$name] -ge $records[-1].Counts[$name]) "Cumulative native depth counter regressed: $name"}}
  Require ($counts.considered -eq $counts.composited+$counts.no_sample+$counts.bad_view+$counts.bad_source) 'Native composition counters do not reconcile.'
  Require ($counts.bad_view -eq $counts.sample_age+$counts.camera_age+$counts.position+$counts.basis+$counts.projection+$counts.other_view) 'Native view failure reasons do not reconcile.'
  $records.Add([pscustomobject]@{Utc=$utc;Counts=$counts})
 }
 Require ($null -ne $arm -and $null -ne $closed -and $arm -le $start -and $closed -ge $end -and $closed-$arm -le (Counter $session.active_ms)+5000) 'Stationary interval is outside the acknowledged native run.'
 foreach($record in $records){Require ($record.Utc -ge $arm -and $record.Utc -le $closed) 'Depth counter is outside the acknowledged native run.'}
 $intervals=[Collections.Generic.List[object]]::new();$totals=[ordered]@{};foreach($name in $names){$totals[$name]=0L};$covered=0L
 for($i=1;$i -lt $records.Count;$i++){
  $a=$records[$i-1];$b=$records[$i]
  if($a.Utc -lt $start -or $b.Utc -gt $end){continue}
  $duration=$b.Utc-$a.Utc;Require ($duration -gt 0) 'Depth counter interval has no duration.'
  if($duration -lt 4000){continue}
  $delta=[ordered]@{};foreach($name in $names){$delta[$name]=$b.Counts[$name]-$a.Counts[$name];$totals[$name]+=$delta[$name]}
  $covered+=$duration;$intervals.Add([ordered]@{started_utc_ms=$a.Utc;completed_utc_ms=$b.Utc;duration_ms=$duration;counters=$delta})
 }
 $proof.complete_stationary_intervals=$intervals.ToArray();$proof.covered_ms=$covered;$proof.counters=$totals
 $proof.composited_fraction=$(if($totals.considered){$totals.composited/[double]$totals.considered}else{0.})
 Require ((Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $logHash) 'Native depth log changed during verification.'
 $proof.source_sha256=[ordered]@{native_depth_log=$logHash;walking=(Get-FileHash -LiteralPath $walkingPath).Hash.ToLowerInvariant();native=(Get-FileHash -LiteralPath $nativePath).Hash.ToLowerInvariant();session=(Get-FileHash -LiteralPath $sessionPath).Hash.ToLowerInvariant()}
 Require ($intervals.Count -ge 1 -and $covered -ge 4000 -and $totals.considered -ge 120) 'Insufficient fully-contained stationary depth evidence: need4 seconds and120 considered frames.'
 $failed=@($failureNames|Where-Object {$totals[$_] -ne 0})
 Require ($totals.composited -eq $totals.considered -and $totals.ready_changes -eq 0 -and $failed.Count -eq 0) ("Stationary depth was unstable: composited=$($totals.composited)/$($totals.considered), ready_changes=$($totals.ready_changes), "+(($failed|ForEach-Object {"$_=$($totals[$_])"})-join ', '))
 $proof.result='passed'
}catch{$proof.failure=$_.Exception.Message}
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($proof|ConvertTo-Json -Depth 12))
$file=[IO.FileStream]::new($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$file.Write($bytes);$file.Flush($true)}finally{$file.Dispose()}
if($proof.result -cne 'passed'){throw "Foliage depth evidence failed: $($proof.failure) Saved $output"}
Write-Output "NATIVE_FOLIAGE_DEPTH_PASS evidence=$directory considered=$($proof.counters.considered) stationary_ms=$($proof.covered_ms)"
