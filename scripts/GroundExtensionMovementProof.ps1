# Pure extension receipt checks. No process or game calls.
. (Join-Path $PSScriptRoot 'CoupledMovementProof.ps1')
. (Join-Path $PSScriptRoot 'HudGroundExtensionProof.ps1')
function Assert-CoupledExtensionHudReady($Ready,[int]$HelperPid,[string]$HelperStart,[long]$MinimumUtcMs,[switch]$DelayHandoff) {
    Assert-HudGroundExtensionMarker $Ready $false $true ([bool]$DelayHandoff)
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
function Assert-CoupledExtensionHudCompletion($Verification,$Ready,$Guest,$Receiver,[string]$TraceFile,[int]$HelperPid,[string]$HelperStart,[string]$HelperHash,[switch]$DelayHandoff){
    foreach($receipt in @($Ready,$Guest)){Assert-HudGroundExtensionMarker $receipt $false $true ([bool]$DelayHandoff)}
    if($Verification.schema -ne 1 -or $Verification.kind -cne 'minecome_hud_stream_controller_v1' -or
        $Verification.result -cne 'passed' -or $Verification.failure -or $Verification.run -cne $Ready.run -or
        $Verification.target_kind -cne 'standalone_controller' -or [string]$Verification.target_pid -cne [string]$HelperPid -or
        [string]$Verification.target_start_filetime -cne $HelperStart -or $Verification.target_sha256 -ine $HelperHash -or
        $Verification.ground_patch_run -cne $Receiver.ExpectedRun -or $Verification.ground_patch_sha256 -cne $Receiver.PatchHash -or
        $Verification.movement_trace_file -ine $TraceFile -or $Guest.save -cne $Ready.save -or $Receiver.Save -cne $Ready.save -or
        -not $Receiver.Ended -or $Guest.run -cne $Ready.run -or $Verification.walking_area -cne 'extension' -or
        $Receiver.ExtensionWalking -isnot [bool] -or -not $Receiver.ExtensionWalking -or
        $Verification.ground_extension_coupled -isnot [bool] -or -not $Verification.ground_extension_coupled){throw 'Extension completion is not bound to the exact helper, trace and capture.'}
    foreach($field in @('ground_movement_fixture','ground_movement_coupled','compositor_armed','composite_requested','kcd_compositing_verified','kcd_launched','kcd_stopped')){
        if($Verification.$field -isnot [bool] -or $Verification.$field){throw 'Extension helper claims incompatible authority.'}
    }
    foreach($field in @('ground_extension_fixture','ground_corridor_fixture','ground_corridor_coupled','corridor_walk_only')){
        $member=$Verification.PSObject.Properties[$field]
        if($member -and ($member.Value -isnot [bool] -or $member.Value)){throw 'Extension helper mixes profiles.'}
    }
    $proof=Assert-HudGroundExtensionProof $Guest $Ready.run $Receiver.Extension -Coupled -TraceFile $TraceFile -DelayHandoff:$DelayHandoff
    if($proof.trace_records -ne $Receiver.Records -or $proof.hud_run -cne $Ready.run -or
        ($Verification.ground_movement | ConvertTo-Json -Depth 12 -Compress) -cne ($proof | ConvertTo-Json -Depth 12 -Compress)){throw 'Extension HUD and trace completion differ.'}
    return $proof
}
function Read-CoupledExtensionTraceLines($Reader){
    # Only share the append-only disk reader's identical 256KiB budget. Record
    # identity/source/area validation remains the explicit extension receiver.
    Read-CoupledTraceLines $Reader -CorridorWalking
}
function Assert-CoupledExtensionFollowerProof($Receipts,$Forwarded,[string]$Run,$Center) {
    $ExtensionWalking=$true
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
        if(-not $receipt.PSObject.Properties['walking_area'] -or $receipt.walking_area -cne 'extension'){throw 'Follower extension area differs.'}
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
        if($frame.Phase -cin @('JUMPING','LANDING')){throw 'Walk-only extension cannot forward airborne sequence phases.'}
        if($ExtensionWalking){
            foreach($axis in @('x','y','z')){
                $value=$frame.Target.$axis
                if(($value -isnot [double] -and $value -isnot [int] -and $value -isnot [long]) -or -not [double]::IsFinite([double]$value)){throw 'Invalid extension forwarded coordinate.'}
            }
            $dx=$frame.Target.x-$Center.x;$dy=$frame.Target.y-$Center.y;$dz=$frame.Target.z-$Center.z
            if($dx -lt -3.5 -or $dx -gt 11.5 -or $dy -lt -3.5 -or $dy -gt 3.5 -or $dz -lt -6.1 -or $dz -gt 3.5){throw 'Forwarded extension target leaves the captured rectangle.'}
        }
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
            $playerDistance2=0.0
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
                if($ExtensionWalking){
                    $playerValue=$receipt.player.$axis
                    if(($playerValue -isnot [double] -and $playerValue -isnot [int] -and $playerValue -isnot [long]) -or
                        -not [double]::IsFinite([double]$playerValue)){throw 'Extension applied receipt lacks its actual native player readback.'}
                    $playerDistance2+=[Math]::Pow($playerValue-$value,2)
                }
            }
            if($ExtensionWalking -and $playerDistance2 -gt .002500001){throw 'Extension native player did not reach the forwarded target.'}
            if($receipt.event -ceq 'applied'){$last=[long]$receipt.seq}
        }
    }
    if($applied.Count -lt 3){throw 'Insufficient delayed follower readbacks.'}
    $phases=@($applied | ForEach-Object {$sent[[long]$_.seq].Phase})
    if('WALKING' -cnotin $phases){
        throw 'Walking and airborne trace phases were not both reflected in KCD.'
    }
    $x=$applied.target.x | Measure-Object -Minimum -Maximum
    $z=$applied.target.z | Measure-Object -Minimum -Maximum
    if($x.Maximum-$x.Minimum -lt 0.3){throw 'Follower did not reflect sufficient real walk/jump displacement.'}
    if($ExtensionWalking){
        $crossed=@($applied | Where-Object {$_.player.x-$Center.x -ge 9.5 -and $sent[[long]$_.seq].Phase -cin @('WALKING','RESTING','JUMPING','LANDING')})
        if($crossed.Count -eq 0){throw 'No actual KCD readback crossed the prior extension edge.'}
        $returned=@($applied | Where-Object {$_.seq -gt $crossed[0].seq -and $_.player.x-$Center.x -lt 8 -and $sent[[long]$_.seq].Phase -ceq 'RETURNING'})
        if($returned.Count -eq 0){throw 'No actual KCD readback returned across the prior extension edge.'}
        $rest=@($applied | Where-Object {$_.seq -gt $returned[0].seq -and $sent[[long]$_.seq].Phase -ceq 'RETURN_REST' -and
            [Math]::Pow($_.player.x-$Center.x-.5,2)+[Math]::Pow($_.player.y-$Center.y+.5,2) -le .5625})
        if($rest.Count -eq 0){throw 'No actual KCD readback settled near the original Minecraft start.'}
        foreach($receipt in @($restoring[0],$terminal[0])){
            $restoreDistance2=0.0
            foreach($axis in @('x','y','z')){
                foreach($name in @('target','player')){
                    $value=$receipt.$name.$axis
                    if(($value -isnot [double] -and $value -isnot [int] -and $value -isnot [long]) -or -not [double]::IsFinite([double]$value)){throw 'Extension restoration lacks finite native readbacks.'}
                }
                if([double]$receipt.target.$axis -ne [double][single]$begin[0].player.$axis){throw 'Extension restoration target is not the exact saved native origin.'}
                $restoreDistance2+=[Math]::Pow($receipt.player.$axis-$begin[0].player.$axis,2)
            }
            if($restoreDistance2 -gt .002500001){throw 'Extension restoration player differs from the saved native origin.'}
        }
    }
    return $applied
}
