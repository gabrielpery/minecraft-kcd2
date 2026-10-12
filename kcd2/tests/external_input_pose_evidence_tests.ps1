#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Synthetic stored parser cases. No game, process, physical input or follower calls.
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $projectRoot 'scripts/ExternalInputPoseEvidence.ps1')
$fixtureDirectory=Join-Path $projectRoot ('runtime/evidence/external-pose-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureDirectory | Out-Null
'STANDALONE SYNTHETIC FILES ONLY. No live-game evidence or follower authority.' | Set-Content -LiteralPath (Join-Path $fixtureDirectory 'FIXTURE-NOT-LIVE.txt')
$patchFile=Join-Path $fixtureDirectory 'patch.json';$viewFile=Join-Path $fixtureDirectory 'view.json';$poseFile=Join-Path $fixtureDirectory 'pose.ndjson'
$encoding=[Text.UTF8Encoding]::new($false,$true)
$run='0123456789abcdef0123456789abcdef';$targetPid=1234;$targetStart='134045612345678901'
$world='02e8c9c1-10ee-4a77-9090-9a98b6ec0503'
$points=for($row=0;$row -lt 5;$row++){for($col=0;$col -lt 5;$col++){
    [ordered]@{index=1+$row*5+$col;x=120+$col-2;y=2040+$row-2;z=56;nx=0;ny=0;nz=1;valid=$true;result='hit'}
}}
$patch=[ordered]@{schema=1;run='ground-fixture';center=[ordered]@{x=120;y=2040;z=56};grid_size=5;spacing=1;point_count=25;valid_count=25;stable_player=$true;approximate_heightfield=$true;full_collision_export_verified=$false;points=@($points);provenance=[ordered]@{kind='standalone_fixture';live_game_verified=$false}}
[IO.File]::WriteAllText($patchFile,($patch|ConvertTo-Json -Depth 8),$encoding)
$patchHash=(Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant()
$view=[ordered]@{schema=1;run=$run;source_kind='standalone_fixture';patch_sha256=$patchHash;target_pid=$targetPid;target_start_filetime=$targetStart;captured_utc_ms=1000;player=[ordered]@{x=120;y=2040;z=56};forward=[ordered]@{x=0;y=-1;z=0};up=[ordered]@{x=0;y=0;z=1}}
[IO.File]::WriteAllText($viewFile,($view|ConvertTo-Json -Depth 5),$encoding)
$viewHash=(Get-FileHash -LiteralPath $viewFile).Hash.ToLowerInvariant()
$script:poseEvidenceCases=0
function Assert-PoseEqual($Actual,$Expected){if($Actual -cne $Expected){throw "Expected $Expected, got $Actual"}}
function Test-PoseEvidence([string]$Name,[scriptblock]$Body){& $Body;$script:poseEvidenceCases++;Write-Output "PASS $Name"}
function New-PoseRecord([string]$Kind,[int]$Seq,[int]$ServerSeq=0,[double]$Yaw=45,[double]$Pitch=-30,[string]$Watermark='3') {
    $record=[ordered]@{schema=1;kind=$Kind;source_kind='external_input_mc_pose_v1';audit_only=$true;follower_eligible=$false;control_ownership_verified=$false;kcd_movement_applied=$false;coordinate_space='patch_space';run=$run;target_pid=$targetPid;target_start_filetime=$targetStart;patch_run='ground-fixture';patch_sha256=$patchHash;view_seed_sha256=$viewHash;ground_source_kind='standalone_fixture';fixture=$true;save='MineCome-ExternalInput-'+$world;world=$world;seq=$Seq;utc_ms=1000+$Seq*100}
    switch($Kind){
        begin {$record.center=[ordered]@{x=120;y=2040;z=56};$record.anchor_mc=[ordered]@{x=0;y=64;z=0};$record.initial_mc_baseline=[ordered]@{x=0.5;y=64;z=0.5};$record.view_kind='vanilla_player_yaw_pitch'}
        sample {
            $record.server_seq=$ServerSeq;$record.server_age_ns=250000000;$record.input_dispatch_watermark=$Watermark
            $record.client=[ordered]@{x=0.4;y=64.2;z=-0.1;vx=0.1;vy=0;vz=0;on_ground=$true;proxy_support=$true;yaw=$Yaw;pitch=$Pitch}
            $record.server=[ordered]@{x=0.75;y=64.3;z=-0.2;vx=0.1;vy=0;vz=0;on_ground=$true;proxy_support=$true;yaw=$Yaw;pitch=$Pitch}
            $yr=$Yaw*[Math]::PI/180;$pr=$Pitch*[Math]::PI/180
            $record.kcd_target=[ordered]@{x=120.75;y=2040.2;z=56.3;forward=[ordered]@{x=-[Math]::Sin($yr)*[Math]::Cos($pr);y=-[Math]::Cos($yr)*[Math]::Cos($pr);z=-[Math]::Sin($pr)}}
        }
        end {$record.result='passed';$record.reason='Synthetic stored parser fixture';$record.last_server_seq=$ServerSeq;$record.last_input_dispatch_watermark=$Watermark}
    }
    return $record
}
function New-PoseRecords {return ,@((New-PoseRecord begin 1),(New-PoseRecord sample 2 10),(New-PoseRecord sample 3 12),(New-PoseRecord end 4 12))}
function Save-PoseRecords($Records,[string]$Separator="`n",[bool]$FinalNewline=$true){
    $text=(@($Records|ForEach-Object{$_|ConvertTo-Json -Depth 7 -Compress}) -join $Separator)
    if($FinalNewline){$text+=$Separator};[IO.File]::WriteAllText($poseFile,$text,$encoding)
}
function Invoke-PoseValidation {
    param([string]$ExpectedRun=$run,[long]$ExpectedPid=$targetPid,[string]$ExpectedStart=$targetStart,[bool]$FixtureMode=$true)
    Test-MineComeExternalInputPoseEvidence -Path $poseFile -InputRun $ExpectedRun -TargetPid $ExpectedPid -TargetStartFiletime $ExpectedStart -PatchFile $patchFile -ViewSeedFile $viewFile -Fixture $FixtureMode
}
function Assert-PoseRejected([scriptblock]$Call={Invoke-PoseValidation|Out-Null}){
    $rejected=$false;try{& $Call}catch{$rejected=$true};if(-not $rejected){throw 'Expected stored pose rejection.'}
}

Test-PoseEvidence 'valid recording maps server position and yaw pitch with audit-only summary' {
    Save-PoseRecords (New-PoseRecords)
    $result=@(Invoke-PoseValidation);Assert-PoseEqual $result.Count 1;$result=$result[0]
    Assert-PoseEqual $result.Samples 2;Assert-PoseEqual $result.Records 4;Assert-PoseEqual $result.Result 'passed'
    Assert-PoseEqual $result.Sha256 ((Get-FileHash -LiteralPath $poseFile).Hash.ToLowerInvariant())
    Assert-PoseEqual $result.First.ServerSeq 10;Assert-PoseEqual $result.Last.ServerSeq 12
    Assert-PoseEqual $result.Last.KcdTarget.x 120.75;Assert-PoseEqual $result.Last.KcdTarget.y 2040.2;Assert-PoseEqual $result.Last.KcdTarget.z 56.3
    Assert-PoseEqual $result.AuditOnly $true;Assert-PoseEqual $result.FollowerEligible $false;Assert-PoseEqual $result.FreshNowVerified $false;Assert-PoseEqual $result.FileAuthenticityVerified $false
}
Test-PoseEvidence 'cardinal headings and vertical pitch map without granting authority' {
    foreach($yaw in @(-180,-90,0,90)){foreach($pitch in @(-90,-30,0,30,90)){
        Save-PoseRecords @((New-PoseRecord begin 1),(New-PoseRecord sample 2 1 $yaw $pitch '0'),(New-PoseRecord end 3 1 $yaw $pitch '0'))
        $result=Invoke-PoseValidation;Assert-PoseEqual $result.Samples 1;Assert-PoseEqual $result.KcdMovementApplied $false
    }}
}
Test-PoseEvidence 'watermark handles exact unsigned64 maximum without double rounding' {
    $r=New-PoseRecords;$r[1].input_dispatch_watermark='18446744073709551614';$r[2].input_dispatch_watermark='18446744073709551615';$r[3].last_input_dispatch_watermark='18446744073709551615'
    Save-PoseRecords $r;Assert-PoseEqual (Invoke-PoseValidation).Last.InputDispatchWatermark '18446744073709551615'
}
Test-PoseEvidence 'expected input process and fixture identities reject' {
    Save-PoseRecords (New-PoseRecords)
    Assert-PoseRejected {Invoke-PoseValidation -ExpectedRun ('a'*32)|Out-Null}
    Assert-PoseRejected {Invoke-PoseValidation -ExpectedPid 1235|Out-Null}
    Assert-PoseRejected {Invoke-PoseValidation -ExpectedStart '134045612345678902'|Out-Null}
    Assert-PoseRejected {Invoke-PoseValidation -FixtureMode $false|Out-Null}
}
Test-PoseEvidence 'record identities hashes and source labels remain immutable' {
    foreach($field in @('run','target_start_filetime','patch_run','patch_sha256','view_seed_sha256','ground_source_kind','source_kind','coordinate_space')){
        $r=New-PoseRecords;$r[2][$field]='different';Save-PoseRecords $r;Assert-PoseRejected
    }
    $r=New-PoseRecords;$r[2].target_pid=1235;Save-PoseRecords $r;Assert-PoseRejected
    $r=New-PoseRecords;$r[2].fixture=$false;Save-PoseRecords $r;Assert-PoseRejected
}
Test-PoseEvidence 'zero vertical nonorthogonal and rolled view seed rejects despite matching updated pose hashes' {
    $original=[IO.File]::ReadAllText($viewFile)
    try {
        foreach($corruption in @('zero','vertical','nonorthogonal','roll')) {
            $changed=$original|ConvertFrom-Json -AsHashtable
            switch($corruption) {
                zero { $changed.forward=@{x=0;y=0;z=0};$expected='unit vectors' }
                vertical { $changed.forward=@{x=0;y=0;z=1};$changed.up=@{x=1;y=0;z=0};$expected='vertical' }
                nonorthogonal { $changed.up=@{x=0;y=-1;z=0};$expected='orthogonal' }
                roll { $changed.up=@{x=[Math]::Sin(2*[Math]::PI/180);y=0;z=[Math]::Cos(2*[Math]::PI/180)};$expected='roll' }
            }
            [IO.File]::WriteAllText($viewFile,($changed|ConvertTo-Json -Depth 5),$encoding)
            $script:viewHash=(Get-FileHash -LiteralPath $viewFile).Hash.ToLowerInvariant()
            $records=New-PoseRecords
            foreach($record in $records){Assert-PoseEqual $record.view_seed_sha256 $script:viewHash}
            Save-PoseRecords $records
            $rejected=$false
            try{Invoke-PoseValidation|Out-Null}catch{if($_.Exception.Message -notmatch $expected){throw};$rejected=$true}
            if(-not $rejected){throw "Expected $corruption view geometry rejection with matching content hashes."}
        }
        $changed=$original|ConvertFrom-Json -AsHashtable
        $changed.up=@{x=[Math]::Sin(0.5*[Math]::PI/180);y=0;z=[Math]::Cos(0.5*[Math]::PI/180)}
        [IO.File]::WriteAllText($viewFile,($changed|ConvertTo-Json -Depth 5),$encoding)
        $script:viewHash=(Get-FileHash -LiteralPath $viewFile).Hash.ToLowerInvariant()
        Save-PoseRecords (New-PoseRecords);Assert-PoseEqual (Invoke-PoseValidation).Result 'passed'
    } finally {
        [IO.File]::WriteAllText($viewFile,$original,$encoding)
        $script:viewHash=(Get-FileHash -LiteralPath $viewFile).Hash.ToLowerInvariant()
    }
}
Test-PoseEvidence 'canonical world save and stable pair reject changes' {
    foreach($edit in @('uppercase','different','save')){
        $r=New-PoseRecords
        if($edit -eq 'uppercase'){$r[1].world=$world.ToUpperInvariant();$r[1].save='MineCome-ExternalInput-'+$r[1].world}
        elseif($edit -eq 'different'){$r[2].world='134206a7-8924-48ec-91cb-36d7a7c6c9e8';$r[2].save='MineCome-ExternalInput-'+$r[2].world}
        else{$r[1].save='Another-save'}
        Save-PoseRecords $r;Assert-PoseRejected
    }
}
Test-PoseEvidence 'all audit flags and genuine booleans enforced' {
    foreach($field in @('audit_only','follower_eligible','control_ownership_verified','kcd_movement_applied')){
        $r=New-PoseRecords;$r[1][$field]=$field -ne 'audit_only';Save-PoseRecords $r;Assert-PoseRejected
    }
    $r=New-PoseRecords;$r[1].client.on_ground='true';Save-PoseRecords $r;Assert-PoseRejected
}
Test-PoseEvidence 'sequence begin end replay and final metadata reject' {
    foreach($edit in @('gap','repeat','server','watermark','endserver','endwatermark','failed','utc')){
        $r=New-PoseRecords
        switch($edit){gap{$r[2].seq=4}repeat{$r[2].seq=2}server{$r[2].server_seq=10}watermark{$r[2].input_dispatch_watermark='2'}endserver{$r[3].last_server_seq=11}endwatermark{$r[3].last_input_dispatch_watermark='2'}failed{$r[3].result='failed'}utc{$r[2].utc_ms=1}}
        Save-PoseRecords $r;Assert-PoseRejected
    }
    $r=New-PoseRecords;Save-PoseRecords @($r[1],$r[2],$r[3]);Assert-PoseRejected
    $r=New-PoseRecords;Save-PoseRecords @($r[0],$r[1],$r[2]);Assert-PoseRejected
    $r=New-PoseRecords;Save-PoseRecords @($r[0],$r[1],$r[3],$r[2]);Assert-PoseRejected
}
Test-PoseEvidence 'canonical watermark types bounds and regressions reject' {
    foreach($value in @('01','-1','+1','1e2','18446744073709551616',1,$true)){
        $r=New-PoseRecords;$r[1].input_dispatch_watermark=$value;Save-PoseRecords $r;Assert-PoseRejected
    }
}
Test-PoseEvidence 'recorded server age bounds and numeric motion types reject' {
    foreach($age in @(-1,250000001,'0',$true)){$r=New-PoseRecords;$r[1].server_age_ns=$age;Save-PoseRecords $r;Assert-PoseRejected}
    foreach($edit in @('x','y','velocity','yaw','pitch','string','boolean')){
        $r=New-PoseRecords
        switch($edit){x{$r[1].server.x=2.1}y{$r[1].server.y=76.1}velocity{$r[1].client.vx=4.1}yaw{$r[1].server.yaw=180}pitch{$r[1].client.pitch=90.1}string{$r[1].server.x='0'}boolean{$r[1].client.x=$true}}
        Save-PoseRecords $r;Assert-PoseRejected
    }
    Save-PoseRecords (New-PoseRecords);$text=[IO.File]::ReadAllText($poseFile).Replace('"vx":0.1','"vx":1e999');[IO.File]::WriteAllText($poseFile,$text,$encoding);Assert-PoseRejected
}
Test-PoseEvidence 'stored inverse axes and forward signs cannot be corrupted' {
    foreach($edit in @('x','y','z','forwardx','forwardy','forwardz')){
        $r=New-PoseRecords
        if($edit.StartsWith('forward')){$r[1].kcd_target.forward[$edit.Substring(7)]=0.9}else{$r[1].kcd_target[$edit]+=0.001}
        Save-PoseRecords $r;Assert-PoseRejected
    }
}
Test-PoseEvidence 'strict LF framing rejects partial blank appended BOM and bad UTF8' {
    Save-PoseRecords (New-PoseRecords) -FinalNewline $false;Assert-PoseRejected
    Save-PoseRecords (New-PoseRecords);[IO.File]::AppendAllText($poseFile,"`n",$encoding);Assert-PoseRejected
    Save-PoseRecords (New-PoseRecords);[IO.File]::AppendAllText($poseFile,"{}`n",$encoding);Assert-PoseRejected
    Save-PoseRecords (New-PoseRecords);$bytes=[IO.File]::ReadAllBytes($poseFile);[IO.File]::WriteAllBytes($poseFile,([byte[]]@(239,187,191)+$bytes));Assert-PoseRejected
    [IO.File]::WriteAllBytes($poseFile,[byte[]]@(195,40,10));Assert-PoseRejected
    Save-PoseRecords (New-PoseRecords) -Separator "`r`n";Assert-PoseEqual (Invoke-PoseValidation).Samples 2
}
Test-PoseEvidence 'duplicate unknown JSON and nested fields reject' {
    Save-PoseRecords (New-PoseRecords);$text=[IO.File]::ReadAllText($poseFile).Replace('"client":{"x":','"client":{"x":0,"x":');[IO.File]::WriteAllText($poseFile,$text,$encoding);Assert-PoseRejected
    $r=New-PoseRecords;$r[1].server.extra='unrecognized';Save-PoseRecords $r;Assert-PoseRejected
    $r=New-PoseRecords;$r[1].extra=$false;Save-PoseRecords $r;Assert-PoseRejected
}
Test-PoseEvidence 'Unicode reason codepoints are bounded without extension methods' {
    $r=New-PoseRecords;$r[3].reason=('a'*160);Save-PoseRecords $r;Assert-PoseEqual (Invoke-PoseValidation).Result 'passed'
    $r[3].reason=('a'*161);Save-PoseRecords $r;Assert-PoseRejected
    $face=[char]::ConvertFromUtf32(0x1f642);$r[3].reason=($face*160);Save-PoseRecords $r;Assert-PoseEqual (Invoke-PoseValidation).Result 'passed'
    $r[3].reason=($face*161);Save-PoseRecords $r;Assert-PoseRejected
}
Test-PoseEvidence 'file line and record resource bounds reject before unbounded parsing' {
    [IO.File]::WriteAllText($poseFile,((' '*4096)+"`n"),$encoding);Assert-PoseRejected
    [IO.File]::WriteAllText($poseFile,("{}`n"*513),$encoding);Assert-PoseRejected
    [IO.File]::WriteAllBytes($poseFile,[byte[]]::new(1048577));Assert-PoseRejected
}
Write-Output "EXTERNAL_INPUT_POSE_EVIDENCE_TEST_PASS cases=$script:poseEvidenceCases live_game_verified=false fixtureDirectory=$fixtureDirectory"
