# Explicit controller proof for the separate two-session native profile.
# No engine calls or input generation. Native independently retires its ownership.
function Assert-HudRepeatPath([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked repeat-session path refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-HudRepeatBytes([string]$Path,[int]$Maximum=1048576){
    $null=Assert-HudRepeatPath $Path
    $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($file.Length -lt 1 -or $file.Length -gt $Maximum){throw 'Repeat-session evidence exceeds its size bound.'}
        $bytes=[byte[]]::new([int]$file.Length);$file.ReadExactly($bytes)
        if($file.ReadByte() -ne -1){throw 'Repeat-session evidence changed while reading.'}
        return ,$bytes
    }finally{$file.Dispose()}
}
function Get-HudRepeatHash([byte[]]$Bytes){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()}
function ConvertFrom-HudRepeatJson([byte[]]$Bytes){[Text.UTF8Encoding]::new($false,$true).GetString($Bytes) | ConvertFrom-Json -Depth 64}
function Assert-HudRepeatTrue($Value,[string]$Name){if($Value -isnot [bool] -or -not $Value){throw "Repeat-session cleanup is incomplete: $Name"}}
function Get-HudRepeatIdentity($Arm){
    if($Arm.schema -ne 1 -or $Arm.kind -cne 'minecome_hud_stream_arm_v1' -or
        $Arm.run -cnotmatch '^[0-9a-f]{32}$' -or $Arm.arm_sha256 -cnotmatch '^[0-9a-f]{64}$') {throw 'Exact repeat-session arm receipt required.'}
    Assert-HudRepeatTrue $Arm.repeat_session 'explicit repeat profile'
    if($Arm.session_generation -notin @(1,2)){throw 'Invalid repeat-session generation.'}
    foreach($field in @('game_pid','game_start_filetime','producer_pid','producer_start_filetime')){
        if([string]$Arm.$field -cnotmatch '^[1-9][0-9]{0,19}$'){throw 'Invalid repeat-session identity.'}
    }
    return [ordered]@{Schema='1';RunId=$Arm.run;ArmSha256=$Arm.arm_sha256;TargetPid=[string]$Arm.game_pid;
        TargetStartFileTime=[string]$Arm.game_start_filetime;ProducerPid=[string]$Arm.producer_pid;ProducerStartFileTime=[string]$Arm.producer_start_filetime}
}
function Assert-HudRepeatCompletion($Arm,$Verification,$Aimed){
    $null=Get-HudRepeatIdentity $Arm
    if($Verification.schema -ne 1 -or $Verification.kind -cne 'minecome_hud_walking_aimed_controller_v1' -or
        $Verification.run -cne $Arm.run -or $Verification.result -cne 'passed' -or $Verification.failure -or
        [string]$Verification.target_pid -cne [string]$Arm.game_pid -or
        [string]$Verification.target_start_filetime -cne [string]$Arm.game_start_filetime){throw 'Successful matching controller completion required.'}
    foreach($field in @('compositor_armed','restoration_verified','trace_passed')){Assert-HudRepeatTrue $Verification.$field $field}
    foreach($field in @('Stopped','ResourcesClosed')){Assert-HudRepeatTrue $Verification.camera_worker.$field "camera $field"}
    if($Verification.camera_worker.Failure){throw 'Camera worker failed.'}
    Assert-HudRepeatTrue $Verification.host_gpu_budget.restoration_verified 'host FPS restored'
    $guest=$Verification.guest
    if($guest.run -cne $Arm.run -or [string]$guest.producer_pid -cne [string]$Arm.producer_pid -or
        [string]$guest.producer_start_filetime -cne [string]$Arm.producer_start_filetime -or
        [string]$guest.target_pid -cne [string]$Arm.game_pid -or
        [string]$guest.target_start_filetime -cne [string]$Arm.game_start_filetime -or $guest.result -cne 'input_completed'){throw 'Matching completed Minecraft producer required.'}
    foreach($field in @('closed_published','mapping_unmapped','mapping_handle_closed','mutex_handle_closed')){Assert-HudRepeatTrue $guest.$field $field}
    foreach($field in @('controls_released','input_handles_closed','closed_acknowledgement_published','normal_shutdown_requested')){Assert-HudRepeatTrue $guest.lab_evidence.$field $field}
    foreach($field in @('completed','trace_closed','controls_released','client_proxy_released','server_proxy_released')){Assert-HudRepeatTrue $guest.lab_evidence.physical_movement.$field $field}
    if($Aimed.schema -ne 1 -or $Aimed.kind -cne 'minecome_hud_walking_aimed_cleanup_v1' -or $Aimed.run -cne $Arm.run -or
        $Aimed.relay.run -cne $Arm.run -or $Aimed.relay.failure -or $Aimed.relay.cleanup_failure -or $Aimed.relay.exit_code -ne 0){throw 'Matching successful aimed cleanup required.'}
    Assert-HudRepeatTrue $Aimed.aim_cleanup_before_follower_finish 'aim cleanup before movement restoration'
    foreach($field in @('exit_observed','cleanup_verified','input_cleanup_verified','guest_world_cleanup_complete')){Assert-HudRepeatTrue $Aimed.relay.$field "aimed $field"}
}
function ConvertTo-HudRepeatIni([string]$Section,$Fields){
    $lines=@('['+$Section+']')+@($Fields.Keys | ForEach-Object {$_+'='+$Fields[$_]})
    return [Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n")+"`n")
}
function Read-HudRepeatIni([string]$Path,[string]$Section,[string[]]$Keys){
    $text=[Text.UTF8Encoding]::new($false,$true).GetString((Read-HudRepeatBytes $Path 4096))
    $lines=@($text -split '\r?\n' | Where-Object {$_ -cne ''})
    if($lines.Count -ne $Keys.Count+1 -or $lines[0] -cne ('['+$Section+']')){throw 'Invalid repeat-session sidecar shape.'}
    $fields=@{}
    foreach($line in $lines[1..($lines.Count-1)]){
        if($line -cnotmatch '^([A-Za-z0-9]+)=([A-Za-z0-9]+)$' -or $Matches[1] -cnotin $Keys -or $fields.ContainsKey($Matches[1])){throw 'Unknown, duplicate or malformed repeat-session field.'}
        $fields[$Matches[1]]=$Matches[2]
    }
    return $fields
}
function Assert-HudRepeatFields($Actual,$Expected){
    foreach($key in $Expected.Keys){if($Actual[$key] -cne [string]$Expected[$key]){throw "Repeat-session sidecar mismatch: $key"}}
}
function Write-HudRepeatNewFile([string]$Path,[byte[]]$Bytes){
    $null=Assert-HudRepeatPath $Path
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $file=[IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$file.Write($Bytes);$file.Flush($true)}finally{$file.Dispose()}
    try{[IO.File]::Move($temp,$Path,$false)}finally{
        if((Test-Path -LiteralPath $temp) -and (Get-HudRepeatHash (Read-HudRepeatBytes $temp)) -ceq (Get-HudRepeatHash $Bytes)){[IO.File]::Delete($temp)}
    }
}
function Publish-HudRepeatCleanup($Arm,[string]$VerificationPath,[string]$AimedVerificationPath,$Context){
    $verificationBytes=Read-HudRepeatBytes $VerificationPath
    $verification=ConvertFrom-HudRepeatJson $verificationBytes
    $aimed=ConvertFrom-HudRepeatJson (Read-HudRepeatBytes $AimedVerificationPath)
    Assert-HudRepeatCompletion $Arm $verification $aimed
    Assert-MineComeProbeContext $Context
    if([string]$Context.GamePid -cne [string]$Arm.game_pid -or $Context.GameStartedUtc.ToFileTimeUtc().ToString() -cne [string]$Arm.game_start_filetime){throw 'Repeat-session target changed.'}
    if(Get-Process -Id ([int]$Arm.producer_pid) -ErrorAction SilentlyContinue){throw 'Previous Minecraft producer PID is still present.'}
    $expected=Join-Path ([IO.Path]::GetDirectoryName($Context.GamePath)) 'minecome-hud/addons/MineComeHudWalkingRepeat.ini'
    $armPath=Assert-HudRepeatPath $Arm.arm_path
    if(-not $armPath.Equals([IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase) -or
        (Get-HudRepeatHash (Read-HudRepeatBytes $armPath 8192)) -cne $Arm.arm_sha256){throw 'Repeat arm ownership changed.'}
    $prefix=$armPath+'.'+$Arm.run
    $fields=Get-HudRepeatIdentity $Arm
    $fields.VerificationSha256=Get-HudRepeatHash $verificationBytes
    foreach($name in @('Verified','AimedCleanup','MovementRestored','GuestCleanup')){$fields[$name]='1'}
    # Publish the exact checked JSON first; the INI is the native commit marker.
    Write-HudRepeatNewFile ($prefix+'.verification.json') $verificationBytes
    Assert-MineComeProbeContext $Context
    Write-HudRepeatNewFile ($prefix+'.cleanup.ini') (ConvertTo-HudRepeatIni 'MineComeRearmCleanup' $fields)
    Write-Output "HUD_REPEAT_CLEANUP_PUBLISHED run=$($Arm.run) awaiting_native_retirement=true"
}
function Assert-HudRepeatRetired($Arm,$Fields,[string]$VerificationHash){
    $expected=Get-HudRepeatIdentity $Arm
    $expected.VerificationSha256=$VerificationHash
    $expected.Generation=[string]$Arm.session_generation
    $expected.State='idle'
    if($Arm.session_generation -ne 1){throw 'Two-session profile is exhausted; restart KCD2 before another session.'}
    Assert-HudRepeatFields $Fields $expected
}
function Wait-HudRepeatRetirement($Arm,$Context){
    $expected=Get-HudRepeatIdentity $Arm
    $prefix=$Arm.arm_path+'.'+$Arm.run
    $expected.VerificationSha256=Get-HudRepeatHash (Read-HudRepeatBytes ($prefix+'.verification.json'))
    $expected.Generation=[string]$Arm.session_generation
    $expected.State=if($Arm.session_generation -eq 1){'idle'}else{'exhausted'}
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    while(-not(Test-Path -LiteralPath ($prefix+'.retired.ini'))){
        if([DateTime]::UtcNow -ge $deadline){throw 'Native retirement is not acknowledged; preserve the arm and restart KCD2 before retrying.'}
        Start-Sleep -Milliseconds 50
    }
    Assert-MineComeProbeContext $Context
    $ack=Read-HudRepeatIni ($prefix+'.retired.ini') 'MineComeRearmRetired' @($expected.Keys)
    Assert-HudRepeatFields $ack $expected
    Write-Output "HUD_REPEAT_RETIRED run=$($Arm.run) generation=$($Arm.session_generation) state=$($expected.State)"
}
function Complete-HudRepeatPreviousArm([string]$ReceiptPath,$Context,[switch]$PreflightOnly){
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $receiptPath=Assert-HudRepeatPath $ReceiptPath
    $evidenceRoot=[IO.Path]::GetFullPath((Join-Path $root 'runtime/evidence'))+[IO.Path]::DirectorySeparatorChar
    if(-not $receiptPath.StartsWith($evidenceRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($receiptPath) -cne 'stream-arming.json'){throw 'Previous arm receipt must be workspace-owned capture evidence.'}
    $arm=ConvertFrom-HudRepeatJson (Read-HudRepeatBytes $receiptPath 65536)
    $identity=Get-HudRepeatIdentity $arm
    Assert-MineComeProbeContext $Context
    if([string]$Context.GamePid -cne [string]$arm.game_pid -or $Context.GameStartedUtc.ToFileTimeUtc().ToString() -cne [string]$arm.game_start_filetime){throw 'Same KCD process is required for rearm.'}
    if(Get-Process -Id ([int]$arm.producer_pid) -ErrorAction SilentlyContinue){throw 'Previous Minecraft producer PID is still present.'}
    $armPath=Assert-HudRepeatPath $arm.arm_path
    $expected=Join-Path ([IO.Path]::GetDirectoryName($Context.GamePath)) 'minecome-hud/addons/MineComeHudWalkingRepeat.ini'
    if(-not $armPath.Equals([IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)){throw 'Previous arm is outside the repeat profile.'}
    $prefix=$armPath+'.'+$arm.run
    $proof=Read-HudRepeatBytes ($prefix+'.verification.json')
    $verificationHash=Get-HudRepeatHash $proof
    $directory=[IO.Path]::GetDirectoryName($receiptPath)
    $controllerDirectory=[IO.Path]::GetDirectoryName($directory)
    if([IO.Path]::GetFileName($directory) -cne 'capture'){throw 'Previous controller evidence layout differs.'}
    if((Get-HudRepeatHash (Read-HudRepeatBytes (Join-Path $controllerDirectory 'verification.json'))) -cne $verificationHash){throw 'Original controller verification differs from native proof.'}
    Assert-HudRepeatCompletion $arm (ConvertFrom-HudRepeatJson $proof) (ConvertFrom-HudRepeatJson (Read-HudRepeatBytes (Join-Path $controllerDirectory 'aimed-verification.json')))
    $cleanupExpected=$identity;$cleanupExpected.VerificationSha256=$verificationHash
    foreach($field in @('Verified','AimedCleanup','MovementRestored','GuestCleanup')){$cleanupExpected[$field]='1'}
    $cleanup=Read-HudRepeatIni ($prefix+'.cleanup.ini') 'MineComeRearmCleanup' @($cleanupExpected.Keys)
    Assert-HudRepeatFields $cleanup $cleanupExpected
    $ackKeys=@('Schema','RunId','ArmSha256','TargetPid','TargetStartFileTime','ProducerPid','ProducerStartFileTime','VerificationSha256','Generation','State')
    $ack=Read-HudRepeatIni ($prefix+'.retired.ini') 'MineComeRearmRetired' $ackKeys
    Assert-HudRepeatRetired $arm $ack $verificationHash
    $archive=Assert-HudRepeatPath (Join-Path $directory 'MineComeHudWalkingRepeat.retired.ini')
    $source=if(Test-Path -LiteralPath $armPath){$armPath}else{$archive}
    if((Get-HudRepeatHash (Read-HudRepeatBytes $source 8192)) -cne $arm.arm_sha256){throw 'Previous arm changed; preserving it.'}
    if(-not $PreflightOnly -and $source -ceq $armPath){
        Assert-MineComeProbeContext $Context
        if(Get-Process -Id ([int]$arm.producer_pid) -ErrorAction SilentlyContinue){throw 'Previous producer PID reappeared.'}
        [IO.File]::Move($armPath,$archive,$false)
    }
    return [pscustomobject]@{Generation=2;PreviousRun=$arm.run;PreviousProducerPid=$arm.producer_pid;PreviousProducerStart=$arm.producer_start_filetime;ArmPath=$armPath;Archived=(-not $PreflightOnly)}
}
