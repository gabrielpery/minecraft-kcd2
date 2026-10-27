#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Replay a previously verified, bounded server trace. No Minecraft or HUD arm.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$TraceDirectory,[switch]$PreflightOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingReceipts.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
. (Join-Path $PSScriptRoot 'HudBufferedMovement.ps1')
$context=Get-MineComeProbeContext
$evidenceRoot=[IO.Path]::GetFullPath((Join-Path $context.ProjectRoot 'runtime/evidence'))+[IO.Path]::DirectorySeparatorChar
$sourceDirectory=(Resolve-Path -LiteralPath $TraceDirectory).Path
if(-not $sourceDirectory.StartsWith($evidenceRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Replay evidence must be in this project runtime/evidence.'}
$tracePath=Join-Path $sourceDirectory 'movement.ndjson'
$verification=Get-Content -LiteralPath (Join-Path $sourceDirectory 'verification.json') -Raw | ConvertFrom-Json
$oldForwarded=@(Get-Content -LiteralPath (Join-Path $sourceDirectory 'forwarded.json') -Raw | ConvertFrom-Json)
if($verification.result -cne 'passed' -or $verification.trace_passed -ne $true -or
    (Get-FileHash -LiteralPath $tracePath).Hash -ine $verification.trace_sha256 -or
    (Get-Item -LiteralPath $tracePath).Length -gt 65536){throw 'Replay needs a matching, previously passed bounded trace.'}
$trace=@(Get-Content -LiteralPath $tracePath | ForEach-Object {$_ | ConvertFrom-Json})
$begins=@($trace | Where-Object kind -CEQ 'begin');$records=@($trace | Where-Object kind -CEQ 'sample')
if($records.Count -lt 3 -or $records.Count -gt 200 -or $begins.Count -ne 1 -or
    $records[0].phase -cne 'SETTLING' -or $records[-1].phase -cne 'PASSED'){throw 'Replay requires a complete bounded source timeline.'}
$begin=$begins[0];$matched=0
$sourceState=New-HudBufferedSourceState
$plan=@(foreach($record in $records){
    $mapped=[pscustomobject]@{x=$begin.center.x+$record.server.x-$begin.anchor_mc.x;
        y=$begin.center.y-$record.server.z+$begin.anchor_mc.z;z=$begin.center.z+$record.server.y-$begin.anchor_mc.y}
    $old=@($oldForwarded | Where-Object TraceSeq -EQ $record.seq)
    if($old.Count -eq 1){
        if($old[0].ServerSeq -ne $record.server_seq -or $old[0].UtcMs -ne $record.utc_ms){throw 'Replay source record differs from its original dispatch.'}
        foreach($axis in @('x','y','z')){if($old[0].Target.$axis -ne $mapped.$axis){throw 'Original dispatch differs from the hashed source position.'}}
        $matched++
    }elseif($old.Count -ne 0 -or $record.phase -cnotin @('SETTLING','PASSED')){throw 'Replay sample lacks a unique verified original dispatch.'}
    $precise=Get-HudBufferedSourceTime -State $sourceState -Record $record
    [pscustomobject]@{Record=$record;SourceMs=[double][single]$precise;SourcePreciseMs=$precise;
        AtMs=(([decimal]$record.monotonic_ns-[decimal]$records[0].monotonic_ns)/1000000.0);OriginalTarget=$mapped}
})
if($matched -ne $oldForwarded.Count -or $plan[0].AtMs -ne 0 -or $plan[-1].AtMs -gt 6000){throw 'Replay timeline or dispatch coverage differs.'}
if($PreflightOnly){Write-Output "BUFFERED_REPLAY_PREFLIGHT_PASS samples=$($plan.Count) no_changes=true";return}
$probe=$null;$cursor=$null;$budget=$null;$budgetEvidence=$null;$failure=$null
$requested=$false;$restored=$false;$passed=$false;$receipts=@();$origin=$null
$forwarded=[Collections.Generic.List[object]]::new();$summaries=[Collections.Generic.List[object]]::new()
function Console([string]$Code,[int]$Timeout=250){
    Assert-MineComeProbeContext $context
    $command='#'+$Code+"; System.LogAlways('[MineComeBufferedReplayFlush] $($probe.Run)')"
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($command)) -TimeoutMilliseconds $Timeout | Out-Null
}
function Read-Receipts([string]$Tag){return @(Read-HudWalkingReceipts $cursor $Tag)}
function Setup-Receipt([string]$Tag){
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do{
        $found=@(Read-Receipts $Tag)
        if($found.Count -eq 1){return $found[0]}
        if($found.Count -gt 1){throw 'Ambiguous replay setup receipt.'}
        Start-Sleep -Milliseconds 15
    }while($clock.ElapsedMilliseconds -lt 3000)
    throw "Missing replay setup receipt: $Tag"
}
function Distance($A,$B){
    $sum=0.0
    foreach($axis in @('x','y','z')){
        $aValue=[double]$A.$axis;$bValue=[double]$B.$axis
        if(-not [double]::IsFinite($aValue) -or -not [double]::IsFinite($bValue)){throw 'Nonfinite replay coordinate.'}
        $sum+=($aValue-$bValue)*($aValue-$bValue)
    }
    return [Math]::Sqrt($sum)
}
function Wait-Restoration {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do{
        Console "System.LogAlways('[MineComeBufferedReplayRestore] $($probe.Run)')"
        $script:receipts=@(Read-Receipts 'MineComeMovementFollower')
        $terminal=@($script:receipts | Where-Object terminal -EQ $true)
        if($terminal.Count -eq 1){
            $r=$terminal[0]
            $script:restored=$r.event -ceq 'restored' -and $r.result -ceq 'restored' -and $r.readback -eq $true -and
                $r.timers_cancelled -eq $true -and $r.physical_movement -eq $true -and $r.camera_basis_valid -eq $true -and
                $r.end_result -ceq 'explicit_end' -and (Distance $r.player $origin) -le .05
            return
        }
        if($terminal.Count -gt 1){throw 'Ambiguous replay terminal state.'}
        Start-Sleep -Milliseconds 25
    }while($clock.ElapsedMilliseconds -lt 3000)
}
try{
    $probe=New-MineComeProbeRun $context 'buffered-movement-replay' (Join-Path $context.ProjectRoot 'kcd2/probes/movement_probe.lua') 'BeginBufferedPhysicalMovementFollower'
    $cursor=New-HudWalkingReceiptCursor $context.GameLog $probe.Offset $probe.Run -KeepOpen
    Console "MineCome.ProbeMovementCapabilities('$($probe.Run)')"
    $cap=Setup-Receipt 'MineComeMovementCapabilities'
    if($cap.identity_stable -ne $true -or $cap.linked_kind -notin @('nil','number_zero') -or $cap.position.ok -ne $true -or $cap.position.finite -ne $true){throw 'Verified stationary actor and no-link contract required.'}
    $origin=$cap.position.value
    Console "MineCome.VerifyMovementNoLinkContract('$($probe.Run)','$($cap.linked_kind)')"
    if((Setup-Receipt 'MineComeMovementContract').result -cne 'verified'){throw 'No-link contract was not acknowledged.'}
    $budget=New-MineComeHudGpuBudget $context;Start-MineComeHudGpuBudget $budget
    $wall=[Diagnostics.Stopwatch]::StartNew();$culture=[Globalization.CultureInfo]::InvariantCulture
    foreach($item in $plan){
        while($wall.ElapsedMilliseconds -lt $item.AtMs){Start-Sleep -Milliseconds 2}
        if($wall.ElapsedMilliseconds-$item.AtMs -gt 100){throw 'Replay dispatch missed its recorded publication time.'}
        $target=[pscustomobject]@{}
        foreach($axis in @('x','y','z')){
            $value=[double]$origin.$axis+[double]$item.OriginalTarget.$axis-[double]$plan[0].OriginalTarget.$axis
            $target | Add-Member -NotePropertyName $axis -NotePropertyValue $value
        }
        if((Distance $origin $target) -gt 1.8 -or [Math]::Abs($target.z-$origin.z) -gt 1.5){throw 'Replay exceeds the bounded physical path.'}
        $x=$target.x.ToString('R',$culture);$y=$target.y.ToString('R',$culture);$z=$target.z.ToString('R',$culture)
        $sourceText=([double]$item.SourceMs).ToString('R',$culture)
        $code="MineCome.ApplyBufferedMovementFollower('$($probe.Run)',$($item.Record.seq),$x,$y,$z,$sourceText)"
        if(-not $requested){
            $code="local p=player and player:GetWorldPos(); if p and (p.x-($x))^2+(p.y-($y))^2+(p.z-($z))^2<=0.00000001 then if MineCome.BeginBufferedPhysicalMovementFollower('$($probe.Run)') then $code end end"
        }
        $requested=$true;Console $code 150
        $forwarded.Add([pscustomobject]@{TraceSeq=$item.Record.seq;ServerSeq=$item.Record.server_seq;Phase=$item.Record.phase;
            UtcMs=$item.Record.utc_ms;SourceMs=$item.SourceMs;SourcePreciseMs=$item.SourcePreciseMs;Target=$target;DispatchMs=$wall.Elapsed.TotalMilliseconds})
        $receipts=@(Read-Receipts 'MineComeMovementFollower')
        if(@($receipts | Where-Object terminal -EQ $true).Count){throw 'Buffered follower stopped during recorded movement.'}
    }
    Console "MineCome.FinishBufferedMovementFollower('$($probe.Run)',$($forwarded[-1].TraceSeq))" 150
    Wait-Restoration
    if(-not $restored){throw 'Replay actor restoration was not verified.'}
    $observed=@($receipts | Where-Object event -CEQ 'applied')
    if($observed.Count -lt 3){throw 'Too few delayed buffered observations.'}
    $playbackEpoch=$null;$lastCrossed=0;$crossedPoints=0;$previousSourceIndex=-1
    foreach($receipt in $observed){
        $proof=Assert-HudBufferedMovementReceipt -Receipt $receipt -Forwarded $forwarded
        if(($null -ne $playbackEpoch -and $proof.EpochEngineSeconds -ne $playbackEpoch) -or $proof.CrossedSourceSeq -le $lastCrossed){throw 'Replay changed epoch or repeated a source point.'}
        if($proof.SourcePointsCrossed -ne $proof.SourceIndex-$previousSourceIndex){throw 'Replay crossing count differs from actual source progress.'}
        $previousSourceIndex=$proof.SourceIndex
        $playbackEpoch=$proof.EpochEngineSeconds;$lastCrossed=$proof.CrossedSourceSeq;$crossedPoints+=$receipt.source_points_crossed
        $summaries.Add($proof)
    }
    if($lastCrossed -ne $forwarded[-1].TraceSeq -or $crossedPoints -ne $forwarded.Count){throw 'Replay did not drain every submitted source point.'}
    $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
    if($requested -and -not $restored){
        $beforeCleanup=$receipts
        try{
            # A malformed diagnostic must still fail the replay, but must not
            # prevent independent observation of its subsequent cleanup.
            try{
                if($cursor){Close-HudWalkingReceiptCursor $cursor}
                $cursor=New-HudWalkingReceiptCursor $context.GameLog ([IO.FileInfo]::new($context.GameLog).Length) $probe.Run -KeepOpen
            }catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
            $receipts=@()
            Console "MineCome.EndMovementFollower('$($probe.Run)')";Wait-Restoration
        }
        catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
        finally{$receipts=@($beforeCleanup)+@($receipts)}
    }
    if($cursor){try{Close-HudWalkingReceiptCursor $cursor}catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}}
    if($budget){
        try{Stop-MineComeHudGpuBudget $budget;if(-not $budget.RestorationVerified -or -not $budget.BudgetValid){throw 'Temporary FPS budget restoration failed.'}}
        catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
        $budgetEvidence=Get-MineComeHudGpuBudgetEvidence $budget
    }
    if($probe){
        ConvertTo-Json -InputObject $receipts -Depth 15 | Set-Content -LiteralPath (Join-Path $probe.Directory 'kcd-receipts.json') -Encoding utf8NoBOM
        ConvertTo-Json -InputObject $forwarded.ToArray() -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'forwarded.json') -Encoding utf8NoBOM
        [ordered]@{schema=1;kind='minecome_buffered_movement_replay_v1';run=$probe.Run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
            source_evidence=$sourceDirectory;source_trace_sha256=$verification.trace_sha256;scripted_replay=$true;physical_input_verified=$false;
            minecraft_connected=$false;hud_armed=$false;visual_smoothness_verified=$false;target_pid=$context.GamePid;source_sha256=$probe.SourceHash;
            forwarded=$forwarded.Count;observed=$summaries.Count;summaries=$summaries.ToArray();restoration_verified=$restored;host_gpu_budget=$budgetEvidence} |
            ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
        Write-Output "BUFFERED_REPLAY_RESULT passed=$passed observed=$($summaries.Count) restored=$restored evidence=$($probe.Directory)"
    }
}
if(-not $passed){throw $failure}
