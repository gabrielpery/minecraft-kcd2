#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Scripted, sub-metre engine probe. No Minecraft, physical keys or HUD arm.
[CmdletBinding()]
param([switch]$PreflightOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingReceipts.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
$context=Get-MineComeProbeContext
if($PreflightOnly){Write-Output 'PHYSICAL_FOLLOWER_PREFLIGHT_PASS no_changes=true';return}
$probe=$null;$cursor=$null;$budget=$null;$budgetEvidence=$null;$failure=$null
$requested=$false;$restored=$false;$passed=$false;$receipts=@();$origin=$null
$targets=[Collections.Generic.List[object]]::new();$applied=[Collections.Generic.List[object]]::new()
$segments=[Collections.Generic.List[object]]::new()
function Console([string]$Code,[int]$Timeout=1000){
    Assert-MineComeProbeContext $context
    $command='#'+$Code+"; System.LogAlways('[MineComePhysicalFollowerFlush] $($probe.Run)')"
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($command)) -TimeoutMilliseconds $Timeout | Out-Null
}
function Read-Receipts([string]$Tag){return @(Read-HudWalkingReceipts $cursor $Tag)}
function Setup-Receipt([string]$Tag){
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do{
        $values=@(Read-Receipts $Tag)
        if($values.Count -eq 1){return $values[0]}
        if($values.Count -gt 1){throw 'Ambiguous scripted follower setup receipt.'}
        Start-Sleep -Milliseconds 15
    }while($clock.ElapsedMilliseconds -lt 3000)
    throw "Missing scripted follower setup receipt: $Tag"
}
function Distance($A,$B){
    $sum=0.0
    foreach($axis in @('x','y','z')){
        if($null -eq $A -or $null -eq $B -or $null -eq $A.$axis -or $null -eq $B.$axis){throw 'Missing observed position.'}
        $axisA=[double]$A.$axis;$axisB=[double]$B.$axis
        if(-not [double]::IsFinite($axisA) -or -not [double]::IsFinite($axisB)){throw 'Nonfinite observed position.'}
        $sum+=($axisA-$axisB)*($axisA-$axisB)
    }
    return [Math]::Sqrt($sum)
}
function Assert-InterpolationReceipt($Receipt,$From,$Target){
    if($Receipt.position_mode -cne 'timed_interpolation' -or $Receipt.interpolation_ms -ne 100 -or
        $Receipt.readback -ne $true -or $Receipt.physical_movement -ne $true -or $Receipt.camera_basis_valid -ne $true -or
        (Distance $Receipt.target $Target) -gt .0001 -or (Distance $Receipt.player $Target) -gt .05 -or
        $null -eq $Receipt.target_receipt_age_ms -or $Receipt.target_receipt_age_ms -le 0 -or $Receipt.target_receipt_age_ms -gt 400){
        throw 'The timed segment did not reach its exact fresh endpoint.'
    }
    $samples=@($Receipt.segment_observed_samples)
    foreach($name in @('segment_update_count','segment_observation_count','segment_max_readback_error','segment_max_observation_gap_ms','target_receipt_age_ms','sampled_engine_seconds','segment_start_engine_seconds')){
        if($Receipt.$name -isnot [ValueType] -or $Receipt.$name -is [bool] -or -not [double]::IsFinite([double]$Receipt.$name)){
            throw 'Invalid segment summary number.'
        }
    }
    $observations=[double]$Receipt.segment_observation_count;$updates=[double]$Receipt.segment_update_count
    $truncated=$Receipt.segment_observed_samples_truncated
    $maxGap=[double]$Receipt.segment_max_observation_gap_ms
    if($samples.Count -lt 1 -or $samples.Count -gt 8 -or $observations -lt $samples.Count -or $observations -gt 8192 -or
        $observations -ne [Math]::Floor($observations) -or $updates -ne [Math]::Floor($updates) -or
        $truncated -isnot [bool] -or $truncated -ne ($observations -gt $samples.Count) -or
        $Receipt.endpoint_write_performed -isnot [bool] -or
        $updates -lt 0 -or $updates -gt 511 -or $updates -gt $observations -or $maxGap -le 0 -or $maxGap -gt 400 -or
        $Receipt.segment_max_readback_error -lt 0 -or $Receipt.segment_max_readback_error -gt .05){throw 'Invalid bounded segment observation summary.'}
    $stationary=(Distance $From $Target) -lt .000001
    $accepted=[double]$Receipt.sampled_engine_seconds-[double]$Receipt.target_receipt_age_ms/1000
    $started=[double]$Receipt.segment_start_engine_seconds
    if($started -lt $accepted-.00001 -or $started -gt $samples[0].written_engine_seconds){throw 'Interpolation starts before target acceptance or after its first update.'}
    $previousFraction=-1.0;$previousObserved=-1.0;$gaps=[Collections.Generic.List[double]]::new()
    foreach($sample in $samples){
        foreach($name in @('fraction','written_engine_seconds','observed_engine_seconds','readback_error')){
            if($sample.$name -isnot [ValueType] -or $sample.$name -is [bool] -or -not [double]::IsFinite([double]$sample.$name)){
                throw 'Invalid segment sample number.'
            }
        }
        $fraction=[double]$sample.fraction
        $timedFraction=[Math]::Min(1.0,([double]$sample.written_engine_seconds-$started)/.1)
        if(-not $stationary -and [Math]::Abs($fraction-$timedFraction) -gt .00001){throw 'Interpolation fraction does not match its engine-time duration.'}
        if($fraction -le $previousFraction -or $fraction -lt 0 -or $fraction -gt 1 -or
            $sample.observed_engine_seconds -le $sample.written_engine_seconds -or
            $sample.written_engine_seconds -lt $previousObserved -or $sample.readback_error -lt 0 -or $sample.readback_error -gt .05 -or
            $sample.write_performed -isnot [bool] -or $Receipt.segment_max_readback_error+.000001 -lt $sample.readback_error){throw 'Segment observations must follow distinct normal frames in order.'}
        $expected=[pscustomobject]@{x=$From.x+($Target.x-$From.x)*$fraction;y=$From.y+($Target.y-$From.y)*$fraction;z=$From.z+($Target.z-$From.z)*$fraction}
        if((Distance $sample.requested $expected) -gt .0001 -or (Distance $sample.actual $sample.requested) -gt .05){
            throw 'Observed segment position differs from the bounded linear path.'
        }
        $delay=1000.0*($sample.observed_engine_seconds-$sample.written_engine_seconds)
        if($maxGap+.001 -lt $delay){throw 'The aggregate observation gap hides a retained delayed frame.'}
        $gaps.Add($delay)
        $previousFraction=$fraction;$previousObserved=[double]$sample.observed_engine_seconds
    }
    $ordered=@($gaps | Sort-Object);$median=$ordered[[int][Math]::Floor($ordered.Count/2)]
    $retainedSetters=@($samples | Where-Object write_performed -EQ $true).Count
    $omitted=$observations-$samples.Count
    if($previousFraction -ne 1 -or $Receipt.sampled_engine_seconds -ne $previousObserved -or
        (-not $stationary -and $samples[-1].written_engine_seconds -lt $started+.1-.00001) -or
        $Receipt.endpoint_write_performed -ne $samples[-1].write_performed -or
        $updates -lt $retainedSetters -or $updates-$retainedSetters -gt $omitted -or
        (-not $truncated -and [Math]::Abs($maxGap-$ordered[-1]) -gt .001)){
        throw 'Last observed sample or aggregate count/gap differs from the acknowledged endpoint.'
    }
    if($stationary){
        if($Receipt.segment_update_count -ne 0 -or $Receipt.endpoint_write_performed -ne $false -or
            @($samples | Where-Object write_performed -EQ $true).Count){throw 'An already stationary target caused position writes.'}
    }elseif($updates -lt 4 -or $maxGap -gt 25){
        throw 'The segment did not demonstrate smaller updates at normal frame cadence.'
    }
    # The native log has a strict line-size limit. Its complete counters and
    # maximum gap cover every observation; the retained median covers only the
    # serialized subset when intermediate samples had to be omitted.
    return [pscustomobject]@{seq=$Receipt.seq;stationary=$stationary;updates=$Receipt.segment_update_count;
        observations=$Receipt.segment_observation_count;retained_observations=$samples.Count;CompleteObservations=(-not $truncated);
        median_observation_gap_ms=$(if(-not $truncated){$median}else{$null});median_retained_observation_gap_ms=$median;
        max_observation_gap_ms=$maxGap;max_retained_observation_gap_ms=$ordered[-1]}
}
function Wait-Restoration {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do{
        Console "System.LogAlways('[MineComePhysicalFollowerRestore] $($probe.Run)')" 250
        $script:receipts=@(Read-Receipts 'MineComeMovementFollower')
        $terminal=@($script:receipts | Where-Object terminal -EQ $true)
        if($terminal.Count -eq 1){
            $r=$terminal[0]
            $script:restored=$r.event -ceq 'restored' -and $r.result -ceq 'restored' -and $r.readback -eq $true -and
                $r.timers_cancelled -eq $true -and $r.physical_movement -eq $true -and $r.camera_basis_valid -eq $true -and
                $r.end_result -ceq 'explicit_end' -and (Distance $r.player $origin) -le .05
            return
        }
        if($terminal.Count -gt 1){throw 'Ambiguous follower terminal state.'}
        Start-Sleep -Milliseconds 25
    }while($clock.ElapsedMilliseconds -lt 3000)
}
try{
    $probe=New-MineComeProbeRun $context 'physical-follower-scripted' (Join-Path $context.ProjectRoot 'kcd2/probes/movement_probe.lua') 'BeginPhysicalMovementFollower'
    $cursor=New-HudWalkingReceiptCursor $context.GameLog $probe.Offset $probe.Run -KeepOpen
    Console "MineCome.ProbeMovementCapabilities('$($probe.Run)')"
    $cap=Setup-Receipt 'MineComeMovementCapabilities'
    if($cap.identity_stable -ne $true -or $cap.linked_kind -notin @('nil','number_zero') -or $cap.position.ok -ne $true -or $cap.position.finite -ne $true){throw 'Verified actor position and no-link contract required.'}
    $origin=$cap.position.value
    Console "MineCome.VerifyMovementNoLinkContract('$($probe.Run)','$($cap.linked_kind)')"
    if((Setup-Receipt 'MineComeMovementContract').result -cne 'verified'){throw 'No-link contract was not acknowledged.'}
    $budget=New-MineComeHudGpuBudget $context;Start-MineComeHudGpuBudget $budget
    $seq=0;$previous=$origin
    foreach($offset in @(.2,.4,.1,-.1,0.0,0.0)){
        $seq++
        $target=[pscustomobject]@{x=[double]$origin.x+$offset;y=[double]$origin.y;z=[double]$origin.z}
        $targets.Add([pscustomobject]@{seq=$seq;target=$target})
        $culture=[Globalization.CultureInfo]::InvariantCulture
        $x=$target.x.ToString('R',$culture);$y=$target.y.ToString('R',$culture);$z=$target.z.ToString('R',$culture)
        $code="MineCome.ApplyMovementFollower('$($probe.Run)',$seq,$x,$y,$z)"
        if(-not $requested){
            $ox=([double]$origin.x).ToString('R',$culture);$oy=([double]$origin.y).ToString('R',$culture);$oz=([double]$origin.z).ToString('R',$culture)
            $code="local p=player and player:GetWorldPos(); if p and (p.x-($ox))^2+(p.y-($oy))^2+(p.z-($oz))^2<=0.01 then if MineCome.BeginPhysicalMovementFollower('$($probe.Run)') then $code end end"
        }
        $requested=$true;Console $code 150
        $wait=[Diagnostics.Stopwatch]::StartNew();$receipt=$null;$lastFlush=-1000L
        do{
            # The log cursor can poll locally. Repeated console requests must
            # not become the dominant work in this frame-cadence measurement.
            if($wait.ElapsedMilliseconds-$lastFlush -ge 100){
                Console "System.LogAlways('[MineComePhysicalFollowerReadback] $($probe.Run)')" 150
                $lastFlush=$wait.ElapsedMilliseconds
            }
            $receipts=@(Read-Receipts 'MineComeMovementFollower')
            if(@($receipts | Where-Object terminal -EQ $true).Count){throw 'Follower stopped during the scripted target sequence.'}
            $matching=@($receipts | Where-Object {$_.event -ceq 'applied' -and $_.seq -eq $seq})
            if($matching.Count -gt 1){throw 'Duplicate target readback.'}
            if($matching.Count -eq 1){$receipt=$matching[0];break}
            Start-Sleep -Milliseconds 15
        }while($wait.ElapsedMilliseconds -lt 300)
        if(-not $receipt){throw 'Missing timely delayed target readback.'}
        if($seq -eq 1){
            $begins=@($receipts | Where-Object {$_.event -ceq 'begin' -and $_.result -ceq 'awaiting_first_pose'})
            if($begins.Count -ne 1 -or (Distance $begins[0].player $origin) -gt .1001){throw 'Missing or moved follower origin.'}
            # The engine owns the origin captured at Begin. Capability sampling
            # can precede a small idle adjustment; it must not redefine restore.
            $origin=$begins[0].player;$previous=$origin
        }
        $segments.Add((Assert-InterpolationReceipt $receipt $previous $target))
        $applied.Add($receipt);$previous=$target
    }
    Console "MineCome.EndMovementFollower('$($probe.Run)')" 150
    Wait-Restoration
    if(-not $restored){throw 'Scripted follower restoration was not verified.'}
    $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
    if($requested -and -not $restored){
        try{Console "MineCome.EndMovementFollower('$($probe.Run)')" 250;Wait-Restoration}
        catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
    }
    if($cursor){Close-HudWalkingReceiptCursor $cursor}
    if($budget){
        try{Stop-MineComeHudGpuBudget $budget;if(-not $budget.RestorationVerified -or -not $budget.BudgetValid){throw 'Temporary FPS budget restoration failed.'}}
        catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
        $budgetEvidence=Get-MineComeHudGpuBudgetEvidence $budget
    }
    if($probe){
        ConvertTo-Json -InputObject $receipts -Depth 10 | Set-Content -LiteralPath (Join-Path $probe.Directory 'kcd-receipts.json') -Encoding utf8NoBOM
        ConvertTo-Json -InputObject $targets.ToArray() -Depth 5 | Set-Content -LiteralPath (Join-Path $probe.Directory 'scripted-targets.json') -Encoding utf8NoBOM
        [ordered]@{schema=1;kind='minecome_scripted_physical_follower_probe_v1';run=$probe.Run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
            scripted_targets=$true;physical_input_verified=$false;minecraft_connected=$false;hud_armed=$false;visual_smoothness_verified=$false;
            target_pid=$context.GamePid;source_sha256=$probe.SourceHash;selected_targets=$targets.Count;delayed_readbacks=$applied.Count;
            frame_interpolation_verified=($passed -and $applied.Count -eq 6);segments=$segments.ToArray();restoration_verified=$restored;host_gpu_budget=$budgetEvidence} |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
        Write-Output "PHYSICAL_FOLLOWER_SCRIPTED_RESULT passed=$passed observed_segments=$($applied.Count) restored=$restored evidence=$($probe.Directory)"
    }
}
if(-not $passed){throw 'Scripted physical follower check did not complete.'}
