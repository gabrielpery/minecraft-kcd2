#requires -Version 7.0
# Pure receipt/append-only file checks shared by the bounded follower controller.
# Callers authenticate the live patch and processes; these helpers do not call games.
. (Join-Path $PSScriptRoot 'HudWalkingSession.ps1')
function Assert-CoupledHudReady($Ready,[int]$HelperPid,[string]$HelperStart,[long]$MinimumUtcMs,[switch]$WideWalking) {
    Assert-HudGroundMovementMarkers $Ready $false $true -WideWalking:$WideWalking
    $world=[Guid]::Empty
    if($Ready.schema -ne 1 -or $Ready.run -cnotmatch '^[0-9a-f]{32}$' -or
        $Ready.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or $Ready.mapping_bytes -ne 8294656 -or
        $Ready.mapping_name -cne ('Local\MineComeHud_'+$Ready.run) -or $Ready.mutex_name -cne ('Local\MineComeHudLock_'+$Ready.run) -or
        [string]$Ready.target_pid -cne [string]$HelperPid -or [string]$Ready.target_start_filetime -cne $HelperStart -or
        $Ready.save -cnotmatch '^MineCome-HudStream-(.+)$' -or
        -not [Guid]::TryParseExact($Matches[1],'D',[ref]$world) -or $Ready.save -cne ('MineCome-HudStream-'+$world.ToString('D')) -or
        ($Ready.producer_pid -isnot [int] -and $Ready.producer_pid -isnot [long]) -or $Ready.producer_pid -lt 1 -or
        [string]$Ready.producer_start_filetime -cnotmatch '^[1-9][0-9]{15,17}$' -or
        ($Ready.expires_utc_ms -isnot [long] -and $Ready.expires_utc_ms -isnot [int]) -or
        $Ready.expires_utc_ms -le $MinimumUtcMs -or $Ready.expires_utc_ms -gt $MinimumUtcMs+185000) {
        throw 'HUD readiness does not bind the exact standalone helper, producer and save.'
    }
}
function Assert-CoupledHudCompletion($Verification,$Ready,$Guest,$Receiver,[string]$TraceFile,[int]$HelperPid,[string]$HelperStart,[string]$HelperHash,[switch]$WideWalking) {
    foreach($receipt in @($Verification,$Ready)){Assert-HudWalkingArea $receipt ([bool]$WideWalking)}
    if($Verification.schema -ne 1 -or $Verification.kind -cne 'minecome_hud_stream_controller_v1' -or
        $Verification.result -cne 'passed' -or $Verification.failure -or $Verification.run -cne $Ready.run -or
        $Verification.target_kind -cne 'standalone_controller' -or [string]$Verification.target_pid -cne [string]$HelperPid -or
        [string]$Verification.target_start_filetime -cne $HelperStart -or $Verification.target_sha256 -ine $HelperHash -or
        $Verification.ground_patch_run -cne $Receiver.ExpectedRun -or $Verification.ground_patch_sha256 -cne $Receiver.PatchHash -or
        $Verification.movement_trace_file -ine $TraceFile -or $Guest.save -cne $Ready.save -or $Receiver.Save -cne $Ready.save -or
        -not $Receiver.Ended -or $Guest.run -cne $Ready.run) {throw 'HUD completion does not match the exact helper, trace and captured terrain.'}
    foreach($field in @('ground_movement_fixture','compositor_armed','composite_requested','kcd_compositing_verified','kcd_launched','kcd_stopped')) {
        if($Verification.$field -isnot [bool] -or $Verification.$field){throw 'HUD helper claims an incompatible operation.'}
    }
    if($Verification.ground_movement_coupled -isnot [bool] -or -not $Verification.ground_movement_coupled){throw 'HUD helper did not verify coupled movement.'}
    $proof=Assert-HudGroundMovementProof $Guest $Ready.run $Receiver.PatchHash $true $Receiver.ExpectedRun $TraceFile -WideWalking:$WideWalking
    if($proof.trace_records -ne $Receiver.Records -or
        ($Verification.ground_movement | ConvertTo-Json -Depth 12 -Compress) -cne ($proof | ConvertTo-Json -Depth 12 -Compress)){
        throw 'HUD and trace completion proofs disagree.'
    }
    return $proof
}
function Read-CoupledTraceLines($Reader,[switch]$ExtendedWalking) {
    # Keep this handle open without FileShare.Delete: the leaf cannot be swapped
    # while following it. Comparing every observed byte also detects rewriting a
    # partial tail or any previously consumed record, not just a shrinking file.
    if(-not $Reader.Stream) {
        if(-not (Test-Path -LiteralPath $Reader.Path)){return @()}
        $item=Get-Item -LiteralPath $Reader.Path -Force
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid movement trace file.'}
        $Reader.Stream=[IO.FileStream]::new($Reader.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    }
    $stream=$Reader.Stream;$length=$stream.Length
    $session=Get-HudWalkingSession -ExtendedWalking:$ExtendedWalking
    if($length -gt $session.TraceBytes -or $length -lt $Reader.Bytes.Length){throw 'Movement trace was truncated or exceeded its selected byte budget.'}
    $bytes=[byte[]]::new([int]$length);$stream.Position=0;$read=0
    while($read -lt $bytes.Length) {
        $n=$stream.Read($bytes,$read,$bytes.Length-$read)
        if($n -eq 0){throw 'Movement trace was truncated during read.'};$read+=$n
    }
    for($i=0;$i -lt $Reader.Bytes.Length;$i++){if($Reader.Bytes[$i] -ne $bytes[$i]){throw 'Movement trace bytes were rewritten.'}}
    $Reader.Bytes=$bytes
    $last=$bytes.Length-1
    while($last -ge 0 -and $bytes[$last] -ne 10){$last--}
    if($last -lt 0){return @()}
    $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes,0,$last+1)
    $lines=$text.Split([char]10)
    for($i=0;$i -lt $lines.Length-1;$i++){
        if($lines[$i].Length -eq 0){throw 'Empty movement trace record.'}
        $lines[$i]
    }
}
function Assert-CoupledFollowerProof($Receipts,$Forwarded,[string]$Run,$Center,[switch]$WideWalking) {
    $begin=@($Receipts | Where-Object event -CEQ 'begin')
    $terminal=@($Receipts | Where-Object terminal -EQ $true)
    if($begin.Count -ne 1 -or $begin[0].result -cne 'awaiting_first_pose' -or
        $terminal.Count -ne 1 -or $terminal[0].event -cne 'restored' -or $terminal[0].result -cne 'restored' -or
        $terminal[0].end_result -cne 'explicit_end' -or $terminal[0].readback -ne $true -or $terminal[0].timers_cancelled -ne $true){
        throw 'Follower lacks one acknowledged begin and explicit verified restoration.'
    }
    $restoring=@($Receipts | Where-Object event -CEQ 'restoring')
    if($restoring.Count -ne 1 -or $Receipts[0].event -cne 'begin' -or $Receipts[-1].event -cne 'restored' -or
        $Receipts[-2].event -cne 'restoring' -or $restoring[0].result -cne 'restored_position_pending_camera' -or
        $restoring[0].end_result -cne 'explicit_end' -or $restoring[0].terminal -ne $false -or $restoring[0].readback -ne $true){
        throw 'Follower restoration stages are incomplete or out of order.'
    }
    foreach($receipt in $Receipts) {
        Assert-HudWalkingArea $receipt ([bool]$WideWalking)
        if($receipt.PSObject.Properties['physical_movement']){throw 'Scripted coupled proof cannot claim physical movement.'}
        if($receipt.schema -ne 1 -or $receipt.run -cne $Run -or $receipt.event -cnotin @('begin','applied','heartbeat','restoring','restored') -or
            $receipt.terminal -isnot [bool] -or ($receipt.event -cne 'restored' -and $receipt.terminal)){
            throw 'Follower contains an uncorrelated or rejected operation.'
        }
    }
    $distance2=0.0
    foreach($axis in @('x','y','z')){
        $value=$begin[0].player.$axis
        if($value -isnot [double] -and $value -isnot [int] -and $value -isnot [long]){throw 'Follower origin is not finite.'}
        if(-not [double]::IsFinite([double]$value)){throw 'Follower origin is not finite.'}
        $distance2+=($value-$Center.$axis)*($value-$Center.$axis)
    }
    if($distance2 -gt 0.01000001){throw 'Follower began away from the captured terrain center.'}
    $sent=@{};$last=[long]0
    foreach($frame in $Forwarded){
        if($frame.TraceSeq -le $last -or $sent.ContainsKey([long]$frame.TraceSeq)){throw 'Forwarded trace identity repeated.'}
        $sent[[long]$frame.TraceSeq]=$frame;$last=[long]$frame.TraceSeq
    }
    $applied=@($Receipts | Where-Object event -CEQ 'applied');$last=[long]0
    foreach($receipt in @($Receipts | Where-Object {$_.event -cin @('applied','heartbeat','restored')})){
        if($receipt.readback -isnot [bool] -or -not $receipt.readback -or
            ($receipt.follow_error -isnot [double] -and $receipt.follow_error -isnot [int] -and $receipt.follow_error -isnot [long]) -or
            -not [double]::IsFinite([double]$receipt.follow_error) -or $receipt.follow_error -lt 0 -or $receipt.follow_error -gt 0.15){
            throw 'Follower camera/player readback did not pass.'
        }
        if($receipt.event -cin @('applied','heartbeat')){
            $expectedResult=if($receipt.event -ceq 'applied'){'applied_readback'}else{'holding_latest'}
            if($receipt.result -cne $expectedResult -or -not $sent.ContainsKey([long]$receipt.seq) -or
                ($receipt.event -ceq 'applied' -and $receipt.seq -le $last) -or
                ($receipt.event -ceq 'heartbeat' -and ($receipt.seq -ne $last -or $last -eq 0))){
                throw 'Follower applied an unknown or repeated trace sample.'
            }
            $frame=$sent[[long]$receipt.seq]
            foreach($axis in @('x','y','z')){
                $value=$receipt.target.$axis
                # The official binding is Entity.SetWorldPos(Vec3); the local
                # libKCD2/Cry_Vector3.h:828 declaration makes Vec3 float32, and
                # IScriptSystem.h:107,112 stores script numbers/vectors as float.
                # These headers corroborate representation, not a native ABI.
                # Pinned tools run 010ae6c7... independently showed every
                # applied/heartbeat target equal this exact float32 projection.
                # Preserve the original server double in Forwarded; compare its
                # single projection exactly, accepting neither an epsilon band
                # nor an adjacent float32 value nor an unprojected double.
                $forwardedValue=$frame.Target.$axis
                if(($value -isnot [double] -and $value -isnot [int] -and $value -isnot [long]) -or
                    ($forwardedValue -isnot [double] -and $forwardedValue -isnot [int] -and $forwardedValue -isnot [long]) -or
                    -not [double]::IsFinite([double]$value) -or -not [double]::IsFinite([double]$forwardedValue) -or
                    [Math]::Abs([double]$forwardedValue) -gt 10000000 -or
                    [double]$value -ne [double][single]$forwardedValue){
                    throw 'Follower target differs from the actual forwarded server sample.'
                }
            }
            if($receipt.event -ceq 'applied'){$last=[long]$receipt.seq}
        }
    }
    if($applied.Count -lt 3){throw 'Insufficient delayed follower readbacks.'}
    $phases=@($applied | ForEach-Object {$sent[[long]$_.seq].Phase})
    if('WALKING' -cnotin $phases -or ('JUMPING' -cnotin $phases -and 'LANDING' -cnotin $phases)){
        throw 'Walking and airborne trace phases were not both reflected in KCD.'
    }
    $x=$applied.target.x | Measure-Object -Minimum -Maximum
    $z=$applied.target.z | Measure-Object -Minimum -Maximum
    if($x.Maximum-$x.Minimum -lt 0.3 -or $z.Maximum-$z.Minimum -lt 0.5){throw 'Follower did not reflect sufficient real walk/jump displacement.'}
    if($WideWalking -and @($applied | Where-Object {
        ($_.target.x-$Center.x)*($_.target.x-$Center.x)+($_.target.y-$Center.y)*($_.target.y-$Center.y) -gt 4
    }).Count -eq 0){throw 'No applied KCD readback crossed the old two-metre boundary.'}
    return $applied
}
