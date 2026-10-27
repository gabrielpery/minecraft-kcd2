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
    foreach($offset in @(.2,.4,.1,-.1,0.0)){
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
        $wait=[Diagnostics.Stopwatch]::StartNew();$receipt=$null
        do{
            Console "System.LogAlways('[MineComePhysicalFollowerReadback] $($probe.Run)')" 150
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
        $mid=[pscustomobject]@{x=($previous.x+$target.x)/2;y=($previous.y+$target.y)/2;z=($previous.z+$target.z)/2}
        if($receipt.position_mode -cne 'two_frame_interpolation' -or $receipt.readback -ne $true -or $receipt.camera_basis_valid -ne $true -or
            $null -eq $receipt.midpoint_readback_error -or $receipt.midpoint_readback_error -gt .05 -or
            (Distance $receipt.midpoint_target $mid) -gt .0001 -or (Distance $receipt.midpoint_player $mid) -gt .05 -or
            (Distance $receipt.target $target) -gt .0001 -or (Distance $receipt.player $target) -gt .05 -or
            $receipt.midpoint_sampled_engine_seconds -ge $receipt.sampled_engine_seconds -or
            $receipt.target_receipt_age_ms -le 0 -or $receipt.target_receipt_age_ms -gt 400){throw 'Actual midpoint and endpoint observations did not prove the selected segment.'}
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
            midpoint_readbacks_verified=($passed -and $applied.Count -eq 5);restoration_verified=$restored;host_gpu_budget=$budgetEvidence} |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
        Write-Output "PHYSICAL_FOLLOWER_SCRIPTED_RESULT passed=$passed midpoint_and_endpoint_pairs=$($applied.Count) restored=$restored evidence=$($probe.Directory)"
    }
}
if(-not $passed){throw 'Scripted physical follower check did not complete.'}
