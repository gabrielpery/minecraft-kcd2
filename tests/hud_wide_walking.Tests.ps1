#Requires -Version 7.3
# Pure synthetic patch/trace tests. No game, renderer arm or process calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
. (Join-Path $root 'scripts/MovementTraceReceiver.ps1')
. (Join-Path $root 'scripts/HudBufferedMovement.ps1')
$world='12345678-1234-1234-1234-123456789abc';$save='MineCome-HudStream-'+$world
$run='a'*32;$minimumUtc=1700000000000L
$narrow=New-HudGroundMovementPatch $run
$wide=New-HudGroundMovementPatch $run -WideWalking
foreach($case in @(@($narrow,5,2),@($wide,9,4))){
    $patch=$case[0];$grid=$case[1];$half=$case[2]
    Check ($patch.grid_size -eq $grid -and $patch.points.Count -eq $grid*$grid) 'Exact fixed footprint/count'
    Check (@($patch.points | Where-Object {
        $_.x -ne 120+(($_.index-1)%$grid)-$half -or $_.y -ne 2040+[Math]::Floor(($_.index-1)/$grid)-$half -or
        $_.z -ne 56 -or $_.nz -ne 1 -or $_.run -cne $run
    }).Count -eq 0) 'Every point remains on one exact anchored grid'
}
Assert-HudWalkingArea $narrow $false;Assert-HudWalkingArea $wide $true
Check ($wide.walking_area -ceq 'wide' -and -not $narrow.Contains('walking_area')) 'Only wide patches carry an area marker'
foreach($receipt in @(@{},[pscustomobject]@{})){Reject {Assert-HudWalkingArea $receipt $true} 'Wide marker must be present'}
foreach($value in @($null,'','Wide','WIDE','narrow',9,$true)){
    foreach($receipt in @(@{walking_area=$value},[pscustomobject]@{walking_area=$value})){
        Reject {Assert-HudWalkingArea $receipt $true} 'Malformed or case-altered marker rejected'
        Reject {Assert-HudWalkingArea $receipt $false} 'Default mode rejects even null/false markers'
    }
}
$dir=Join-Path $root ('runtime/evidence/wide-walking-pure-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
$files=[Collections.Generic.List[string]]::new()
function Save-Patch($Patch,[string]$Name){
    # Authentication is tested elsewhere. This deliberately synthetic file carries
    # the receiver's required label solely to exercise its numeric contract.
    $Patch.provenance.kind='live_kcd_ground_patch'
    $path=Join-Path $dir $Name
    [IO.File]::WriteAllText($path,($Patch | ConvertTo-Json -Depth 12 -Compress),[Text.UTF8Encoding]::new($false))
    if(-not $files.Contains($path)){$files.Add($path)}
    return $path
}
function Receiver([string]$Path,[bool]$Wide){
    New-MineComeTraceReceiver -PatchFile $Path -MinimumUtcMs $minimumUtc -ExpectedHudSave $save -PhysicalMovement -WideWalking:$Wide
}
function Trace($State,[string]$Kind,[long]$Seq,[double]$X=0){
    $record=[ordered]@{schema=1;kind=$Kind;run=$State.ExpectedRun;patch_sha256=$State.PatchHash;
        source_kind=(Get-HudWalkingSession).SourceKind;save=$save;world=$world;seq=$Seq;utc_ms=$minimumUtc;phase='SETTLING'}
    if($State.WideWalking){$record.walking_area='wide'}
    if($Kind -ceq 'begin'){
        $record.started_monotonic_ns=0L;$record.center=$State.Center;$record.anchor_mc=@{x=0.0;y=64.0;z=0.0}
        $record.approximate_heightfield=$true;$record.full_collision_export_verified=$false
    }else{
        if($Seq -gt 2){$record.phase='WALKING'}
        $record.monotonic_ns=$Seq*100000000L;$record.server_seq=$Seq-1;$record.server_age_ns=0L
        foreach($side in @('client','server')){$record[$side]=@{x=$X;y=64.0;z=0.0;vx=0.0;vy=0.0;vz=0.0;on_ground=$true;proxy_support=$true}}
    }
    return $record
}
function Receive($State,$Record){Receive-MineComeMovementTrace -State $State -JsonLine ($Record | ConvertTo-Json -Depth 8 -Compress) -NowUtcMs $minimumUtc}
function Begin-Trace($State){$null=Receive $State (Trace $State begin 1);$null=Receive $State (Trace $State sample 2)}
function Reject-Record($State,$Record,[string]$Message){
    $before=@($State.LastSeq,$State.LastServerSeq,$State.Bytes,$State.Records)
    Reject {Receive $State $Record} $Message
    Check ((@($State.LastSeq,$State.LastServerSeq,$State.Bytes,$State.Records) -join '|') -ceq ($before -join '|')) 'Rejected record leaves sequence/accounting unchanged'
}
try{
    $narrowFile=Save-Patch $narrow 'narrow.json';$wideFile=Save-Patch $wide 'wide.json'
    Reject {Receiver $wideFile $false} 'Default receiver refuses a wide file'
    Reject {Receiver $narrowFile $true} 'Wide receiver refuses a narrow file'
    Reject {New-MineComeTraceReceiver -PatchFile $wideFile -MinimumUtcMs $minimumUtc -ExpectedHudSave $save -WideWalking} 'Wide receiver requires physical movement'
    Reject {New-MineComeTraceReceiver -PatchFile $wideFile -MinimumUtcMs $minimumUtc -PhysicalMovement -WideWalking} 'Wide receiver requires exact HUD save'
    foreach($value in @($null,'Wide','wrong')){
        $wide.walking_area=$value;$badFile=Save-Patch $wide 'bad.json'
        Reject {Receiver $badFile $true} 'Wide file with invalid/null marker rejected'
    }
    $wide.Remove('walking_area');$badFile=Save-Patch $wide 'bad.json'
    Reject {Receiver $badFile $true} 'Wide file without marker rejected'
    $wide.walking_area='wide';$wide.points[80].x+=1;$badFile=Save-Patch $wide 'bad.json'
    Reject {Receiver $badFile $true} 'Misaligned outer wide coordinate rejected'
    $wide.points[80].x-=1
    $state=Receiver $wideFile $true
    $begin=Trace $state begin 1;$begin.walking_area='Wide';Reject-Record $state $begin 'Incorrect begin marker rejected'
    Begin-Trace $state
    $sample=Trace $state sample 3 3.0;$sample.Remove('walking_area');Reject-Record $state $sample 'Missing sample marker rejected'
    $sample.walking_area=$null;Reject-Record $state $sample 'Null sample marker rejected'
    $sample.walking_area='wide';$accepted=Receive $state $sample
    Check ($accepted.Kind -ceq 'sample' -and $accepted.Target.x -eq 123 -and $accepted.Target.y -eq 2040 -and $accepted.Target.z -eq 56) 'Wide x3 sample maps through the unchanged capture anchor'
    Reject-Record $state (Trace $state sample 4 4.01) 'Wide sample beyond 4m rejected'
    $sample=Trace $state sample 4 3;$sample.walking_area='narrow';Reject-Record $state $sample 'Mismatched sample marker rejected'
    $state=Receiver $narrowFile $false;Begin-Trace $state
    Reject-Record $state (Trace $state sample 3 3) 'Default receiver retains old bounds'
    $warmup=Initialize-HudBufferedMovementPipeline -PatchFile $wideFile -ExpectedHudSave $save -MinimumUtcMs $minimumUtc -WideWalking -ExtendedWalking
    Check ($warmup.status -ceq 'completed' -and $warmup.diagnostic_records -eq 3) 'Wide buffered warmup uses disposable valid marked records'
    Write-Output "HUD_WIDE_WALKING_TESTS_PASS checks=$script:checks no_game_started=true"
}finally{
    # Remove only the exact files created above; never recursively delete evidence.
    foreach($path in $files){if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
    [IO.Directory]::Delete($dir,$false)
}
