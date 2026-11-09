# Offline acceptance for two ordinary launcher sessions, separated by a KCD restart.
# Save identity/resume and native composition only; inventory retention and physical input are not claimed.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$FirstEvidenceDirectory,[Parameter(Mandatory)][string]$SecondEvidenceDirectory)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Launcher verification failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function Assert-PlayTrue($Value,[string]$Label){if($Value -isnot [bool] -or -not $Value){throw "Launcher proof missing: $Label"}}
function Read-PlayJson([string]$Directory,[string]$Name){Get-Content -LiteralPath (Join-Path $Directory $Name) -Raw|ConvertFrom-Json -Depth 48}
function Assert-PlayNear([double]$Actual,[double]$Expected,[string]$Label){if(-not [double]::IsFinite($Actual) -or -not [double]::IsFinite($Expected) -or [Math]::Abs($Actual-$Expected) -gt .04){throw "Launcher resume differs: $Label"}}
function Get-PlayLedger($Blocks){@($Blocks.blocks|Sort-Object x,y,z|ForEach-Object {"$($_.x),$($_.y),$($_.z):$($_.state)"}) -join '|'}
function Read-PlaySession([string]$Path){
 $directory=(Resolve-Path -LiteralPath $Path).Path
 $v=Read-PlayJson $directory 'verification.json';$s=Read-PlayJson $directory 'gameplay-session.json';$h=Read-PlayJson $directory 'host-movement.json';$stream=Read-PlayJson $directory 'capture/stream-result.json';$launch=Read-PlayJson $directory 'play-launch.json'
 if($v.kind -cne 'minecome_gameplay_kcd_session_v1' -or $v.result -cne 'passed' -or $v.failure -or $v.run -cnotmatch '^[0-9a-f]{32}$' -or
  $s.kind -cne 'minecome_gameplay_session_v1' -or $s.run -cne $v.run -or $s.save -cne 'MineCome-Gameplay' -or $s.standalone -or $s.failure -or $s.producer_failure -or
  $s.stop_reason -cne 'stop_requested' -or $s.PSObject.Properties['fixture'] -or $v.smoke_seconds -lt 12 -or $s.active_ms -lt $v.smoke_seconds*1000 -or
  $stream.schema -ne 3 -or $stream.result -cne 'stopped' -or $stream.lab_evidence.run -cne $s.run -or $stream.lab_evidence.world_id -cne $s.world_id){throw 'Ordinary timed launcher session identity/shutdown differs.'}
 [void][guid]::ParseExact($s.world_id,'D')
 if($v.target_pid -le 0 -or $v.target_start_filetime -cnotmatch '^[0-9]{1,19}$'){throw 'Native process identity missing.'}
 if($launch.schema -ne 1 -or $launch.kind -cne 'minecome_play_saved_v1' -or $launch.run -cne $s.run -or $launch.target_pid -ne $v.target_pid -or
  $launch.target_start_filetime -cne $v.target_start_filetime -or [IO.Path]::GetFullPath($launch.instance) -ine [IO.Path]::GetFullPath($v.instance)){throw 'Play launcher receipt does not own the saved session.'}
 foreach($key in @('normal_client_exit','movement_profile','blocks_profile','explore_profile','chat_profile','flight_profile','hands_profile','world_blocks_profile','combat_profile','hide_native_vitals')){Assert-PlayTrue $v.$key $key}
 foreach($key in @('persistent_world','input_connected','input_armed_seen','producer_finished','normal_shutdown_requested','controls_released','input_cleanup_complete','inventory_prepared_before_input','kcd_movement_connected','combat_enabled','world_blocks_enabled')){Assert-PlayTrue $s.$key $key}
 $m=$s.movement;$b=$s.blocks;$c=$s.combat
 if($m.run -cne $s.run -or $m.world_id -cne $s.world_id -or $m.fixture -or $m.failure -or $m.terrain_failure -or $m.terrain_transition -or
  $b.run -cne $s.run -or $b.world_id -cne $s.world_id -or $b.failure -or $b.pending -or $b.persisted_revision -ne $b.revision -or $b.owned_count -ne @($b.blocks).Count -or
  $c.pending -or $c.incoming_pending -ne 0 -or ($c.PSObject.Properties['failure'] -and $c.failure) -or $c.incoming_arrow_adapters_active -ne 0){throw 'Launcher movement/block/combat state did not settle.'}
 foreach($key in @('ready','controls_released','client_collision_released','server_collision_released','shutdown_prepared','cleanup_complete','terrain_cells_valid','resume_checkpoint_present')){Assert-PlayTrue $m.$key ('movement '+$key)}
 foreach($key in @('ready','controls_released','cleanup_complete')){Assert-PlayTrue $b.$key ('blocks '+$key)}
 Assert-PlayTrue $c.cleanup_complete 'combat cleanup'
 if($h.Failure -or $h.Terminal.run -cne $s.run -or $h.Terminal.result -cne 'explicit_stop' -or $h.Terminal.active -or $h.Terminal.body_hidden -or
  ($h.Terminal.camera_override_changed -and -not $h.Terminal.camera_restored) -or $h.ViewCount -lt 2 -or $h.Combat.Failure -or $h.Terrain.Failure -or $h.Terrain.Pending){throw 'Native launcher lifecycle did not close normally.'}
 foreach($key in @('Stopped','ResourcesClosed')){Assert-PlayTrue $h.$key ('host '+$key)}
 Assert-PlayTrue $h.Terminal.timers_cancelled 'native timers cancelled';Assert-PlayTrue $h.Terminal.body_restore_dispatched 'native body restore'
 Assert-PlayTrue $h.Combat.CleanupComplete 'native combat cleanup';Assert-PlayTrue $h.Terrain.CleanupComplete 'native terrain cleanup'
 $hud=$h.Hud
 foreach($receipt in @($hud.Begin,$hud.Terminal)){
  if($receipt.schema -ne 1 -or $receipt.run -cne $s.run -or $receipt.backend -cne 'ui_movieclip' -or $receipt.element -cne 'hud' -or $receipt.instance -ne 0 -or $receipt.clip -cne 'Stats' -or
   $receipt.original_visible -isnot [bool] -or $receipt.current_visible -isnot [bool]){throw 'Native health/stamina HUD readback identity differs.'}
 }
 if($hud.Begin.event -cne 'begin' -or $hud.Terminal.event -cne 'terminal' -or $hud.Begin.current_visible -or $hud.Terminal.active -isnot [bool] -or $hud.Terminal.active -or
  $hud.Terminal.original_visible -ne $hud.Begin.original_visible -or $hud.Terminal.current_visible -ne $hud.Begin.original_visible){throw 'Native health/stamina HUD did not restore its original visibility.'}
 Assert-PlayTrue $hud.Begin.active 'native HUD suppression active';Assert-PlayTrue $hud.Begin.hidden 'native HUD hidden';Assert-PlayTrue $hud.Terminal.restored 'native HUD restored'
 $started=[long]$s.input.first_connected_utc_ms;$ended=[long]$s.input.closed_ack_written_utc_ms
 if($started -le 0 -or $ended-$started -lt 12000 -or $ended-$started -gt 360000 -or $s.input.closed_ack_failure -cne 'none'){throw 'Native input observation interval differs.'}
 $anchor=[DateTimeOffset]::FromUnixTimeMilliseconds($started).ToLocalTime();$depth=[Collections.Generic.List[object]]::new();$ends=@();$closed=@()
 foreach($line in [IO.File]::ReadLines((Join-Path $directory 'native-hud.log'))){
  if($line -notmatch '^(?<clock>[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{3}) .*\[MineComeHudInput\] (?<json>\{.*\})$'){continue}
  $clock=$Matches.clock;$record=$Matches.json|ConvertFrom-Json
  if(-not $record.PSObject.Properties['run'] -or $record.run -cne $s.run -or -not $record.PSObject.Properties['event']){continue}
  if($record.event -ceq 'session_end'){$ends+=,$record};if($record.event -ceq 'input_closed'){$closed+=,$record}
  if($record.event -cne 'host_depth'){continue}
  $time=[TimeSpan]::ParseExact($clock,'hh\:mm\:ss\:fff',[Globalization.CultureInfo]::InvariantCulture)
  $utc=@(foreach($day in @(-1,0,1)){[DateTimeOffset]::new($anchor.Date.AddDays($day).Add($time),$anchor.Offset).ToUnixTimeMilliseconds()})|Sort-Object {[Math]::Abs($_-$started)}|Select-Object -First 1
  if($utc -lt $started -or $utc -gt $ended){continue}
  foreach($key in @('composited','reprojected')){if($record.$key -isnot [ValueType] -or $record.$key -is [bool] -or $record.$key -lt 0 -or $record.$key -ne [Math]::Floor($record.$key)){throw 'Native composition counter type/bound invalid.'}}
  $depth.Add([pscustomobject]@{utc_ms=[long]$utc;composited=[long]$record.composited;reprojected=[long]$record.reprojected})
 }
 if($ends.Count -ne 1 -or $ends[0].result -cne 'closed' -or $closed.Count -ne 1 -or $closed[0].reason -cne 'guest_closed' -or
  $closed[0].host_state -ne 2 -or $closed[0].guest_state -ne 2 -or $closed[0].events_sent -ne $closed[0].events_acknowledged -or $depth.Count -lt 2){throw 'Native composition or input close evidence missing.'}
 for($i=1;$i -lt $depth.Count;$i++){if($depth[$i].utc_ms -le $depth[$i-1].utc_ms -or $depth[$i].composited -lt $depth[$i-1].composited -or $depth[$i].reprojected -lt $depth[$i-1].reprojected){throw 'Native composition counter time/order regressed.'}}
 $composited=$depth[-1].composited-$depth[0].composited;$reprojected=$depth[-1].reprojected-$depth[0].reprojected
 if($composited -lt 1 -or $reprojected -lt 1){throw 'Native HUD did not continue compositing/reprojecting.'}
 $hashes=[ordered]@{};foreach($name in @('verification.json','gameplay-session.json','host-movement.json','capture/stream-result.json','native-hud.log','play-launch.json')){$hashes[$name]=(Get-FileHash -LiteralPath (Join-Path $directory $name)).Hash.ToLowerInvariant()}
 [pscustomobject]@{Directory=$directory;Session=$s;Verification=$v;Host=$h;Launch=$launch;Ledger=(Get-PlayLedger $b);Proof=[ordered]@{directory=$directory;run=$s.run;world_id=$s.world_id;new_world=$s.new_world;target_pid=$v.target_pid;target_start_filetime=$v.target_start_filetime;active_ms=$s.active_ms;owned_blocks=$b.owned_count;block_revision=$b.revision;native_hud_hidden=$true;native_hud_restored=$true;native_hud_original_visible=$hud.Begin.original_visible;native_composited_delta=$composited;native_reprojected_delta=$reprojected;native_counter_samples=$depth.ToArray();evidence_sha256=$hashes}}
}
$first=Read-PlaySession $FirstEvidenceDirectory;$second=Read-PlaySession $SecondEvidenceDirectory
if($first.Directory -ieq $second.Directory -or $first.Session.run -ceq $second.Session.run -or
 [IO.Path]::GetFullPath($first.Verification.instance) -ine [IO.Path]::GetFullPath($second.Verification.instance) -or $first.Session.world_id -cne $second.Session.world_id -or
 $first.Launch.level -cne $second.Launch.level -or $second.Session.new_world){throw 'Launcher did not reopen the same owned save in a new session.'}
# PID reuse is legal after a restart; the creation timestamp must change.
if([long]$second.Verification.target_start_filetime -le [long]$first.Verification.target_start_filetime){throw 'Second launcher proof does not follow a fresh KCD process start.'}
if($second.Session.movement.first_attachment -or -not $second.Session.movement.resume_position_restored -or
 $first.Session.movement.patch_run -cne $second.Session.movement.patch_run -or $first.Session.movement.patch_sha256 -cne $second.Session.movement.patch_sha256 -or
 $first.Ledger -cne $second.Ledger -or $first.Session.blocks.revision -ne $second.Session.blocks.revision){throw 'Saved terrain, owned blocks, or checkpoint restoration changed across restart.'}
foreach($axis in @('x','y','z')){Assert-PlayNear $second.Session.movement.initial_position.$axis $first.Session.movement.resume_checkpoint.$axis ('position '+$axis)}
$proof=[ordered]@{schema=1;kind='minecome_launcher_resume_verification_v1';result='passed';world_id=$first.Session.world_id;instance=$first.Verification.instance;
 actual_minecraft=$true;actual_kcd=$true;physical_native_input_verified=$false;normal_save_resume_verified=$true;kcd_process_restart_verified=$true;native_composition_verified=$true;native_health_stamina_hud_hidden_and_restored=$true;
 block_ledger_unchanged=$true;nonempty_block_persistence_verified=($first.Session.blocks.owned_count -gt 0);inventory_persistence_verified=$false;launches=@($first.Proof,$second.Proof)}
$output=Join-Path $second.Directory 'play-verification.json';$proof|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $output -Encoding utf8NoBOM
Write-Output "PLAY_MINECOME_PASS evidence=$output"
