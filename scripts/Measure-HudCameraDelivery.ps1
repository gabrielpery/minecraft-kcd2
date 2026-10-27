#Requires -Version 7.3
# Read-only sampling by default; an explicit switch applies/restores the existing
# temporary 60 FPS budget. This never arms a HUD, starts a follower, or moves an actor.
[CmdletBinding()]
param([ValidateRange(1,60)][int]$Samples=60,[ValidateRange(1,20)][int]$MaximumSeconds=20,[switch]$UseHudGpuBudget)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingReceipts.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$context=Get-MineComeProbeContext
$probe=$null;$failure=$null;$temporary=$null;$rows=[Collections.Generic.List[object]]::new()
$budget=$null;$budgetEvidence=$null;$cleanupFailure=$null
$clock=[Diagnostics.Stopwatch]::StartNew()
function Elapsed([long]$Start){([Diagnostics.Stopwatch]::GetTimestamp()-$Start)*1000.0/[Diagnostics.Stopwatch]::Frequency}
function Send-Console([string]$Code){
    Assert-MineComeProbeContext $context
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString('#'+$Code+"; System.LogAlways('[MineComeCameraProfileFlush] $($probe.Run)')")) -TimeoutMilliseconds 1000 | Out-Null
}
function Wait-SetupReceipt([string]$Tag){
    $until=[DateTime]::UtcNow.AddSeconds(4)
    do{
        $values=@(Read-HudWalkingReceipts $cursor $Tag)
        if($values.Count -eq 1){return $values[0]}
        if($values.Count -gt 1){throw 'Ambiguous camera profiling setup receipt.'}
        Start-Sleep -Milliseconds 10
    }while([DateTime]::UtcNow -lt $until)
    throw "Camera profiling setup receipt missing: $Tag"
}
function Statistics([object[]]$Values){
    if(-not $Values.Count){return $null}
    $sorted=@($Values | Sort-Object)
    [ordered]@{count=$sorted.Count;median_ms=$sorted[[int][Math]::Floor(($sorted.Count-1)/2)];p95_ms=$sorted[[Math]::Max(0,[int][Math]::Ceiling($sorted.Count*.95)-1)];max_ms=$sorted[-1]}
}
try{
    $probe=New-MineComeProbeRun $context 'hud-camera-profile' (Join-Path $root 'kcd2/probes/movement_probe.lua') 'SamplePhysicalHudView'
    $cursor=New-HudWalkingReceiptCursor $context.GameLog $probe.Offset $probe.Run
    Send-Console "MineCome.ProbeMovementCapabilities('$($probe.Run)')"
    $cap=Wait-SetupReceipt 'MineComeMovementCapabilities'
    if($cap.identity_stable -ne $true -or $cap.linked_kind -notin @('nil','number_zero')){throw 'Verified actor/no-link contract required.'}
    Send-Console "MineCome.VerifyMovementNoLinkContract('$($probe.Run)','$($cap.linked_kind)')"
    $contract=Wait-SetupReceipt 'MineComeMovementContract'
    if($contract.result -cne 'verified'){throw 'No-link contract was not verified.'}
    if($UseHudGpuBudget){
        # Retain ownership before dispatch so even an uncertain Start outcome restores.
        $budget=New-MineComeHudGpuBudget $context
        Start-MineComeHudGpuBudget $budget
    }
    $target=Join-Path $probe.Directory 'diagnostic-camera.json'
    $temporary=$target+'.tmp'
    $sequence=0L;$engine=-1.0;$profileStart=[Diagnostics.Stopwatch]::GetTimestamp()
    Write-Output "HUD_CAMERA_PROFILE_START run=$($probe.Run) samples=$Samples actor_position_written=false evidence=$($probe.Directory)"
    while($rows.Count -lt $Samples -and (Elapsed $profileStart) -lt $MaximumSeconds*1000){
        $loopStart=[Diagnostics.Stopwatch]::GetTimestamp()
        $stage=[Diagnostics.Stopwatch]::GetTimestamp();Assert-MineComeProbeContext $context;$loopGuardMs=Elapsed $stage
        # Exactly one request is outstanding, and its UTC is never rebased at receipt/publication.
        $requestUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$requestStart=[Diagnostics.Stopwatch]::GetTimestamp()
        $stage=[Diagnostics.Stopwatch]::GetTimestamp();Assert-MineComeProbeContext $context;$guardMs=Elapsed $stage
        $stage=[Diagnostics.Stopwatch]::GetTimestamp()
        $command="#MineCome.SamplePhysicalHudView('$($probe.Run)'); System.LogAlways('[MineComeCameraProfileFlush] $($probe.Run)')"
        $remainingProfileMs=$MaximumSeconds*1000-(Elapsed $profileStart)
        if($remainingProfileMs -le 0){break}
        Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($command)) -TimeoutMilliseconds ([Math]::Max(1,[int][Math]::Min(1000,[Math]::Floor($remainingProfileMs)))) | Out-Null
        $httpMs=Elapsed $stage
        $receiptStart=[Diagnostics.Stopwatch]::GetTimestamp();$lookupMs=0.0;$polls=0
        do{
            $stage=[Diagnostics.Stopwatch]::GetTimestamp()
            $values=@(Read-HudWalkingReceipts $cursor 'MineComeHudPhysicalView' | Where-Object {$_.seq -gt $sequence})
            $lookupMs+=Elapsed $stage;$polls++
            if($values.Count){break}
            if((Elapsed $requestStart) -ge 1000 -or (Elapsed $profileStart) -ge $MaximumSeconds*1000){throw 'Camera profiling request exceeded its request/profile deadline.'}
            Start-Sleep -Milliseconds 5
        }while($true)
        $receiptWallMs=Elapsed $receiptStart;$receiptUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if($values.Count -ne 1){throw 'Camera profiling requires one acknowledgement per request.'}
        $sample=$values[0]
        if($sample.seq -ne $sequence+1 -or $sample.result -cne 'sampled' -or $sample.physical_movement -ne $true -or $sample.camera_basis_valid -ne $true -or $sample.sampled_engine_seconds -le $engine){throw 'Camera profiling actor/basis/sequence/clock contract failed.'}
        $sequence=[long]$sample.seq;$engine=[double]$sample.sampled_engine_seconds
        $stage=[Diagnostics.Stopwatch]::GetTimestamp()
        # Deliberately not a production host-view envelope: no consumer may use this diagnostic.
        $record=[ordered]@{schema=1;kind='minecome_camera_delivery_diagnostic_sample_v1';run=$probe.Run;seq=$sequence;requested_utc_ms=$requestUtc;forward=$sample.camera.forward;up=$sample.camera.up;target_pid=$context.GamePid}
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Depth 5 -Compress))
        if($bytes.Length -gt 4096){throw 'Camera diagnostic exceeds bound.'}
        $serializeMs=Elapsed $stage
        $stage=[Diagnostics.Stopwatch]::GetTimestamp();$null=Resolve-HudMovementEvidencePath $target $root;$pathMs=Elapsed $stage
        $stage=[Diagnostics.Stopwatch]::GetTimestamp()
        $file=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$file.Write($bytes);$file.Flush($true)}finally{$file.Dispose()}
        $writeFlushMs=Elapsed $stage
        $stage=[Diagnostics.Stopwatch]::GetTimestamp()
        if(Test-Path -LiteralPath $target){[IO.File]::Replace($temporary,$target,[NullString]::Value)}else{[IO.File]::Move($temporary,$target,$false)}
        $replaceMs=Elapsed $stage;$publishedUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $rows.Add([pscustomobject]@{seq=$sequence;requested_utc_ms=$requestUtc;receipt_utc_ms=$receiptUtc;published_utc_ms=$publishedUtc;loop_guard_ms=$loopGuardMs;console_guard_ms=$guardMs;http_ms=$httpMs;receipt_lookup_ms=$lookupMs;receipt_wait_ms=$receiptWallMs;receipt_polls=$polls;serialize_ms=$serializeMs;path_validation_ms=$pathMs;write_flush_ms=$writeFlushMs;replace_ms=$replaceMs;request_to_receipt_ms=$receiptUtc-$requestUtc;request_to_publication_ms=$publishedUtc-$requestUtc;total_ms=(Elapsed $loopStart)})
        $remaining=90-(Elapsed $loopStart)
        $remaining=[Math]::Min($remaining,$MaximumSeconds*1000-(Elapsed $profileStart))
        if($remaining -gt 0){Start-Sleep -Milliseconds ([int][Math]::Ceiling($remaining))}
    }
    if(-not $rows.Count){throw 'No camera samples completed inside the profiling window.'}
}catch{$failure=$_.Exception.Message;throw}
finally{
    if($budget){
        try{
            Stop-MineComeHudGpuBudget $budget
            if(-not $budget.RestorationVerified -or -not $budget.BudgetValid){throw 'Camera profile temporary FPS budget was not restored under its owned lifecycle.'}
        }catch{
            if(-not $failure){$failure=$_.Exception.Message;$cleanupFailure=$failure}
        }
        $budgetEvidence=Get-MineComeHudGpuBudgetEvidence $budget
    }
    if($probe){
        if($temporary -and (Test-Path -LiteralPath $temporary)){Remove-Item -LiteralPath $temporary}
        $statistics=[ordered]@{}
        foreach($name in @('loop_guard_ms','console_guard_ms','http_ms','receipt_lookup_ms','receipt_wait_ms','serialize_ms','path_validation_ms','write_flush_ms','replace_ms','request_to_receipt_ms','request_to_publication_ms','total_ms')){
            $statistics[$name]=Statistics @($rows | ForEach-Object {$_.$name})
        }
        $summary=[ordered]@{schema=1;kind='minecome_hud_camera_delivery_profile_v1';run=$probe.Run;result=$(if($failure){'failed'}else{'profiled'});failure=$failure;requested_samples=$Samples;completed_samples=$rows.Count;profile_seconds_limit=$MaximumSeconds;elapsed_ms=$clock.Elapsed.TotalMilliseconds;target_pid=$context.GamePid;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();source_sha256=$probe.SourceHash;actor_position_written=$false;hud_armed=$false;follower_started=$false;original_request_timestamp_preserved=$true;temporary_frame_cap_requested=[bool]$UseHudGpuBudget;host_gpu_budget=$budgetEvidence;statistics=$statistics}
        ConvertTo-Json -InputObject $rows.ToArray() -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'samples.json') -Encoding utf8NoBOM
        $summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
        Write-Output "HUD_CAMERA_PROFILE_RESULT result=$($summary.result) samples=$($rows.Count) evidence=$($probe.Directory)"
        [pscustomobject]$summary
    }
    if($cleanupFailure){throw $cleanupFailure}
}
