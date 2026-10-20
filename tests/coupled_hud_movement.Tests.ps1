#requires -Version 7.3
# Synthetic receipt and append-only file tests. No game/process launch.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
. (Join-Path $root 'scripts/CoupledMovementProof.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
function Clone-Receipt($Value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 12)}
foreach($file in @('scripts/Test-CoupledMovement.ps1','scripts/CoupledMovementProof.ps1','scripts/MovementTraceReceiver.ps1','scripts/Start-HudCoupledMovementLab.ps1')){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Invalid PowerShell syntax: $file"
}
$run='0123456789abcdef0123456789abcdef';$patchRun='a'*32;$hash='b'*64
$save='MineCome-HudStream-12345678-1234-1234-1234-123456789abc'
$start='134363864241979118';$trace='C:\synthetic\movement.ndjson'
$ready=[pscustomobject]@{schema=1;run=$run;source_kind='minecraft_vanilla_ui_stream_v1';mapping_bytes=8294656
    mapping_name='Local\MineComeHud_'+$run;mutex_name='Local\MineComeHudLock_'+$run;target_pid=321;target_start_filetime=$start
    producer_pid=123;producer_start_filetime=$start;save=$save;expires_utc_ms=181000
    standalone=$true;ui_ground_movement_coupled=$true}
Assert-CoupledHudReady $ready 321 $start 1000
Check $true 'Exact readiness accepted'
foreach($field in @('run','source_kind','mapping_name','mutex_name','target_pid','target_start_filetime','producer_pid','producer_start_filetime','save','expires_utc_ms')){
    $bad=Clone-Receipt $ready;$bad.$field='incorrect'
    Reject {Assert-CoupledHudReady $bad 321 $start 1000} "Bad readiness $field accepted"
}
foreach($field in @('standalone','ui_ground_movement_coupled')){
    foreach($value in @($false,1,'true',$null)){
        $bad=Clone-Receipt $ready;$bad.$field=$value
        Reject {Assert-CoupledHudReady $bad 321 $start 1000} "Bad readiness marker $field accepted"
    }
}
$proof=[pscustomobject]@{schema=1;kind='minecome_hud_ground_movement_coupled_v1';save=$save
    patch_run=$patchRun;patch_sha256=$hash;ground_source_kind='live_kcd_ground_patch';phase='PASSED'
    hud_run=$run;trace_file=$trace;trace_records=8;trace_closed=$true;trace_result='passed'
    synthetic_input=$true;kcd_calls=$false;kcd_movement_applied=$false;physical_input_verified=$false
    client_walk=0.6;server_walk=0.6;client_air=$true;server_air=$true;client_land=$true;server_land=$true
    client_proxy_queries=40;server_proxy_queries=40;post_settle_corrections=0
    client_proxy_released=$true;server_proxy_released=$true;controls_released=$true
    frame_captures=[pscustomobject]@{WALKING=3;JUMPING=0;LANDING=5}
    approximate_heightfield=$true;full_collision_export_verified=$false}
$guest=[pscustomobject]@{run=$run;result='passed';save=$save;standalone=$true;ui_ground_movement_coupled=$true
    lab_evidence=[pscustomobject]@{ground_movement=$proof}}
$receiver=[pscustomobject]@{ExpectedRun=$patchRun;PatchHash=$hash;Save=$save;Ended=$true;Records=8}
$verification=[pscustomobject]@{schema=1;kind='minecome_hud_stream_controller_v1';result='passed';failure=$null;run=$run
    target_kind='standalone_controller';target_pid=321;target_start_filetime=$start;target_sha256=$hash
    ground_patch_run=$patchRun;ground_patch_sha256=$hash;movement_trace_file=$trace
    ground_movement_fixture=$false;compositor_armed=$false;composite_requested=$false;kcd_compositing_verified=$false
    kcd_launched=$false;kcd_stopped=$false;ground_movement_coupled=$true;ground_movement=$proof}
$null=Assert-CoupledHudCompletion $verification $ready $guest $receiver $trace 321 $start $hash
Check $true 'Exact trace and HUD completion accepted'
foreach($field in @('run','result','target_pid','target_start_filetime','target_sha256','ground_patch_run','ground_patch_sha256','movement_trace_file')){
    $bad=Clone-Receipt $verification;$bad.$field='incorrect'
    Reject {Assert-CoupledHudCompletion $bad $ready $guest $receiver $trace 321 $start $hash} "Bad completion $field accepted"
}
foreach($field in @('ground_movement_fixture','compositor_armed','composite_requested','kcd_compositing_verified','kcd_launched','kcd_stopped')){
    $bad=Clone-Receipt $verification;$bad.$field=$true
    Reject {Assert-CoupledHudCompletion $bad $ready $guest $receiver $trace 321 $start $hash} "Incompatible completion $field accepted"
}
$bad=Clone-Receipt $receiver;$bad.Records=7
Reject {Assert-CoupledHudCompletion $verification $ready $guest $bad $trace 321 $start $hash} 'Mismatched trace record count accepted'
$bad=Clone-Receipt $receiver;$bad.Save='MineCome-Ground-12345678-1234-1234-1234-123456789abc'
Reject {Assert-CoupledHudCompletion $verification $ready $guest $bad $trace 321 $start $hash} 'Different trace save accepted'
$bad=Clone-Receipt $guest;$bad.lab_evidence.ground_movement.trace_closed=$false
Reject {Assert-CoupledHudCompletion $verification $ready $bad $receiver $trace 321 $start $hash} 'Open trace accepted'
$center=[pscustomobject]@{x=120.0;y=2040.0;z=56.0}
$forwarded=@(
    [pscustomobject]@{TraceSeq=2;Phase='WALKING';Target=[pscustomobject]@{x=120.0;y=2040.0;z=56.0}}
    [pscustomobject]@{TraceSeq=3;Phase='WALKING';Target=[pscustomobject]@{x=120.4;y=2040.0;z=56.0}}
    [pscustomobject]@{TraceSeq=4;Phase='JUMPING';Target=[pscustomobject]@{x=120.5;y=2040.0;z=56.8}}
)
$receipts=@([pscustomobject]@{schema=1;run=$run;event='begin';result='awaiting_first_pose';terminal=$false;player=$center})
foreach($frame in $forwarded){
    $projected=[pscustomobject]@{}
    foreach($axis in @('x','y','z')){$projected | Add-Member -NotePropertyName $axis -NotePropertyValue ([double][single]$frame.Target.$axis)}
    $receipts+=[pscustomobject]@{schema=1;run=$run;event='applied';result='applied_readback';terminal=$false
        seq=$frame.TraceSeq;target=$projected;readback=$true;follow_error=0.05}
}
$receipts+=[pscustomobject]@{schema=1;run=$run;event='heartbeat';result='holding_latest';terminal=$false;seq=4;target=$receipts[-1].target;readback=$true;follow_error=0.04}
$receipts+=[pscustomobject]@{schema=1;run=$run;event='restoring';result='restored_position_pending_camera';terminal=$false;readback=$true;end_result='explicit_end'}
$receipts+=[pscustomobject]@{schema=1;run=$run;event='restored';result='restored';terminal=$true;readback=$true;timers_cancelled=$true;end_result='explicit_end';follow_error=0.02}
$applied=@(Assert-CoupledFollowerProof $receipts $forwarded $run $center)
Check ($applied.Count -eq 3) 'Normal intermediate restoring/heartbeat and exact applied samples accepted'
foreach($change in @(
    {param($r)$r[1].seq=99},
    {param($r)$r[2].seq=2},
    {param($r)$r[1].target.x=120.02},
    {param($r)$r[1].follow_error=[double]::NaN},
    {param($r)$r[1].follow_error=0.151},
    {param($r)$r[1].readback=$false},
    {param($r)$r[0].player.x=120.101},
    {param($r)$r[4].seq=3},
    {param($r)$r[5].result='different'},
    {param($r)$r[6].end_result='input_expired'},
    {param($r)$r[6].timers_cancelled=$false},
    {param($r)$r[1].event='rejected'},
    {param($r)$r[1].run='different'},
    {param($r)$r[1].terminal=$true})){
    $bad=Clone-Receipt $receipts;& $change $bad
    Reject {Assert-CoupledFollowerProof $bad $forwarded $run $center} 'Invalid follower proof accepted'
}
$bad=Clone-Receipt $receipts;$bad[0].player.x=120.1
Check (@(Assert-CoupledFollowerProof $bad $forwarded $run $center).Count -eq 3) 'Exact origin distance bound accepted'
Reject {Assert-CoupledFollowerProof @($receipts[0..4]+$receipts[6]) $forwarded $run $center} 'Missing intermediate restoration accepted'
# Actual original doubles from saved run 010ae6c7...; projected expectations
# are independently spelled out, not generated with the production conversion.
foreach($sample in @(
    [pscustomobject]@{Axis='x';Original=120.4291952933163;Projected=120.42919158935547}
    [pscustomobject]@{Axis='x';Original=120.051796921857;Projected=120.05179595947266}
    [pscustomobject]@{Axis='y';Original=2040.1510009765625;Projected=2040.1510009765625}
    [pscustomobject]@{Axis='z';Original=56.33080863952637;Projected=56.330810546875}
)){
    $frames=Clone-Receipt $forwarded;$observed=Clone-Receipt $receipts
    $frames[1].Target.($sample.Axis)=$sample.Original
    $observed[2].target.($sample.Axis)=$sample.Projected
    Check (@(Assert-CoupledFollowerProof $observed $frames $run $center).Count -eq 3) 'Exact measured float32 projection rejected'
    if($sample.Original -ne $sample.Projected){
        $bad=Clone-Receipt $observed;$bad[2].target.($sample.Axis)=$sample.Original
        Reject {Assert-CoupledFollowerProof $bad $frames $run $center} 'Unprojected double admitted instead of exact engine target'
    }
    $bits=[BitConverter]::SingleToInt32Bits([single]$sample.Projected)
    foreach($offset in @(-1,1)){
        $bad=Clone-Receipt $observed
        $bad[2].target.($sample.Axis)=[double][BitConverter]::Int32BitsToSingle($bits+$offset)
        Reject {Assert-CoupledFollowerProof $bad $frames $run $center} 'Adjacent wrong float32 target accepted'
    }
}
# Heartbeats carry the same projected last-owned target and cannot relax it.
$bad=Clone-Receipt $receipts
$bad[4].target.x=[double][BitConverter]::Int32BitsToSingle([BitConverter]::SingleToInt32Bits([single]$bad[4].target.x)+1)
Reject {Assert-CoupledFollowerProof $bad $forwarded $run $center} 'Adjacent wrong heartbeat float32 target accepted'
$dir=Join-Path $root ('runtime/evidence/coupled-hud-pure-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
'SYNTHETIC ONLY; no Minecraft or KCD calls.' | Set-Content (Join-Path $dir 'FIXTURE.txt')
$path=Join-Path $dir 'trace.ndjson'
$reader=[pscustomobject]@{Path=$path;Stream=$null;Bytes=[byte[]]::new(0)}
try{
    Check (@(Read-CoupledTraceLines $reader).Count -eq 0) 'Missing trace treated as not ready'
    [IO.File]::WriteAllText($path,"first`npar",[Text.UTF8Encoding]::new($false))
    Check (@(Read-CoupledTraceLines $reader).Count -eq 1) 'Partial tail held'
    [IO.File]::AppendAllText($path,"tial`n",[Text.UTF8Encoding]::new($false))
    $lines=@(Read-CoupledTraceLines $reader)
    Check ($lines.Count -eq 2 -and $lines[1] -ceq 'partial') 'Append completed tail once'
    $writer=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    try{$writer.WriteByte(88);$writer.Flush()}finally{$writer.Dispose()}
    Reject {Read-CoupledTraceLines $reader} 'Same-length consumed prefix rewrite accepted'
}finally{if($reader.Stream){$reader.Stream.Dispose()}}
foreach($text in @("`n",('x'*65537))){
    [IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
    $reader=[pscustomobject]@{Path=$path;Stream=$null;Bytes=[byte[]]::new(0)}
    try{Reject {Read-CoupledTraceLines $reader} 'Malformed/oversized trace accepted'}finally{if($reader.Stream){$reader.Stream.Dispose()}}
}
Write-Output "COUPLED_HUD_PURE_PASS checks=$script:checks no_game_calls=true"
