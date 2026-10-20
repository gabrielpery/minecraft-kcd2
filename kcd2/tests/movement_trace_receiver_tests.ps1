#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Standalone synthetic fixtures, not authenticated KCD or Minecraft evidence.
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $projectRoot 'scripts/MovementTraceReceiver.ps1')
$fixtureDirectory=Join-Path $projectRoot ('runtime/evidence/trace-receiver-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureDirectory | Out-Null
'Standalone synthetic parser fixture; the live label is required syntax only. No game was called.' | Set-Content -LiteralPath (Join-Path $fixtureDirectory 'FIXTURE-NOT-LIVE.txt')
$patchPath=Join-Path $fixtureDirectory 'synthetic-patch.json'
$points=for($row=0;$row -lt 5;$row++) { for($column=0;$column -lt 5;$column++) {
    [ordered]@{index=1+$row*5+$column;x=120+$column-2;y=2040+$row-2;z=56;nx=0;ny=0;nz=1;valid=$true;result='hit'}
}}
$patch=[ordered]@{schema=1;run='abc123';center=[ordered]@{x=120;y=2040;z=56};grid_size=5;spacing=1;point_count=25;valid_count=25;stable_player=$true;approximate_heightfield=$true;full_collision_export_verified=$false;points=@($points);provenance=[ordered]@{kind='live_kcd_ground_patch';testing_only=$true;live_game_verified=$false}}
$patch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $patchPath -Encoding utf8
$patchHash=(Get-FileHash -LiteralPath $patchPath).Hash.ToLowerInvariant()
$world='af640918-0d21-4b3c-b32a-dfae04e1045c'
$script:traceTestsPassed=0
function Assert-Equal($Actual,$Expected) { if($Actual -cne $Expected) { throw "Expected $Expected, got $Actual" } }
function Assert-Close($Actual,$Expected) { if([Math]::Abs($Actual-$Expected) -gt 0.000000001) { throw "Expected $Expected, got $Actual" } }
function New-TestState { return New-MineComeTraceReceiver $patchPath 1000 }
function New-TestRecord([string]$Kind,[int]$Seq,[string]$Phase='WALKING',[long]$Utc=1100,[long]$ServerSeq=1) {
    $record=[ordered]@{schema=1;kind=$Kind;run='abc123';patch_sha256=$patchHash;source_kind='live_kcd_ground_patch';save='MineCome-Ground-'+$world;world=$world;seq=$Seq;utc_ms=$Utc;phase=$Phase}
    switch($Kind) {
        begin { $record.phase='SETTLING';$record.started_monotonic_ns=1000000000;$record.center=[ordered]@{x=120;y=2040;z=56};$record.anchor_mc=[ordered]@{x=0;y=64;z=0};$record.approximate_heightfield=$true;$record.full_collision_export_verified=$false }
        sample {
            $record.monotonic_ns=1100000000;$record.server_seq=$ServerSeq;$record.server_age_ns=1000000
            $record.client=[ordered]@{x=0.4;y=64.1;z=0.8;vx=0.1;vy=0;vz=0.2;on_ground=$true;proxy_support=$true}
            $record.server=[ordered]@{x=0.7;y=64.3;z=-0.2;vx=0.1;vy=0;vz=0.2;on_ground=$true;proxy_support=$true}
        }
        end { $record.result='passed';$record.reason='Synthetic standalone completion';$record.last_server_seq=$ServerSeq }
    }
    return $record
}
function Convert-TestLine($Record) { return $Record | ConvertTo-Json -Depth 8 -Compress }
function Start-TestState {
    $state=New-TestState
    $answer=Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord begin 1 SETTLING 1000)) 1000
    Assert-Equal $answer.Kind 'begin'
    return $state
}
function Assert-Rejected($State,[string]$Line,$Now=1100) {
    $before=$State | ConvertTo-Json -Depth 5 -Compress
    $rejected=$false
    try { Receive-MineComeMovementTrace $State $Line $Now | Out-Null } catch { $rejected=$true }
    if(-not $rejected) { throw 'Expected receiver rejection.' }
    Assert-Equal ($State | ConvertTo-Json -Depth 5 -Compress) $before
}
function Test-TraceReceiver([string]$Name,[scriptblock]$Body) {
    & $Body
    $script:traceTestsPassed++
    Write-Output "PASS $Name"
}

Test-TraceReceiver 'fresh begin and authoritative server target match inverse basis' {
    $state=Start-TestState
    Assert-Equal $state.ExpectedRun 'abc123';Assert-Equal $state.PatchHash $patchHash
    Assert-Equal $state.World $world;Assert-Equal $state.Save ('MineCome-Ground-'+$world)
    $answer=Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2)) 1100
    Assert-Equal $answer.Kind 'sample';Assert-Close $answer.Target.x 120.7;Assert-Close $answer.Target.y 2040.2;Assert-Close $answer.Target.z 56.3
    Assert-Equal $state.LastSeq 2;Assert-Equal $state.LastServerSeq 1;Assert-Equal $state.GroundProved $true
}

Test-TraceReceiver 'settling and unproved jump never authorize a target' {
    $state=Start-TestState
    $answer=Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2 SETTLING)) 1100
    Assert-Equal $answer.Kind 'observe';Assert-Equal $answer.PSObject.Properties['Target'] $null
    $answer=Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 3 JUMPING 1100 2)) 1100
    Assert-Equal $answer.Kind 'observe';Assert-Equal $state.GroundProved $false
}

Test-TraceReceiver 'first walking/resting needs ground and proxy proof before airborne phases' {
    $state=Start-TestState;$record=New-TestRecord sample 2;$record.server.on_ground=$false
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1100).Kind 'observe'
    $record=New-TestRecord sample 3 RESTING 1100 2;$record.server.proxy_support=$false
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1100).Kind 'observe'
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 4 RESTING 1100 3)) 1100).Kind 'sample'
    $record=New-TestRecord sample 5 JUMPING 1100 4;$record.server.on_ground=$false;$record.server.proxy_support=$false;$record.server.y=65
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1100).Kind 'sample'
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 6 LANDING 1100 5)) 1100).Kind 'sample'
}

Test-TraceReceiver 'stale UTC consumes sequence without target or establishing ground' {
    $state=Start-TestState
    $answer=Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2 WALKING 1000)) 1301
    Assert-Equal $answer.Kind 'stale';Assert-Equal $answer.PSObject.Properties['Target'] $null
    Assert-Equal $state.GroundProved $false;Assert-Equal $state.LastSeq 2;Assert-Equal $state.LastServerSeq 1
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 3 WALKING 1301 2)) 1301).Kind 'sample'
}

Test-TraceReceiver 'compound300ms observation age and50ms future limits accept at bounds' {
    $state=Start-TestState
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2 WALKING 1000)) 1299).Kind 'sample'
    $state=Start-TestState
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2 WALKING 1000)) 1300).Kind 'stale'
    $state=Start-TestState;$record=New-TestRecord sample 2 WALKING 1000;$record.server_age_ns=250000000
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1050).Kind 'sample'
    $state=Start-TestState
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1051).Kind 'stale'
    $state=Start-TestState
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2 WALKING 1150)) 1100).Kind 'sample'
    $state=Start-TestState;Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 2 WALKING 1151))
    Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 2 WALKING 999))
}

Test-TraceReceiver 'record and server replay gaps and premature sample reject transactionally' {
    $state=New-TestState;Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 1))
    $state=Start-TestState
    Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 3))
    Assert-Rejected $state (Convert-TestLine (New-TestRecord begin 2))
    Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2)) 1100 | Out-Null
    Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 2))
    Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 3 WALKING 1100 1))
    Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 3 WALKING 1100 1000001))
}

Test-TraceReceiver 'run hash source world save and canonical UUID are immutable' {
    foreach($name in @('run','patch_sha256','source_kind','world','save')) {
        $state=Start-TestState;$record=New-TestRecord sample 2;$record[$name]='different'
        Assert-Rejected $state (Convert-TestLine $record)
    }
    $state=Start-TestState;$record=New-TestRecord sample 2
    $record.world='f521d7b5-4bd5-4c7c-b79e-e869eac275e8';$record.save='MineCome-Ground-'+$record.world
    Assert-Rejected $state (Convert-TestLine $record)
    $state=New-TestState;$record=New-TestRecord begin 1;$record.world=$world.ToUpperInvariant();$record.save='MineCome-Ground-'+$record.world
    Assert-Rejected $state (Convert-TestLine $record)
}

Test-TraceReceiver 'begin center anchor and approximation flags must match exactly' {
    foreach($change in @({param($r)$r.center.x=120.01},{param($r)$r.anchor_mc.y=64.01},{param($r)$r.approximate_heightfield=$false},{param($r)$r.full_collision_export_verified=$true})) {
        $state=New-TestState;$record=New-TestRecord begin 1;& $change $record
        Assert-Rejected $state (Convert-TestLine $record)
    }
}

Test-TraceReceiver 'strict number and boolean types reject coercion and finite/bounds violations' {
    foreach($change in @({param($r)$r.seq='2'},{param($r)$r.server.x='0.7'},{param($r)$r.server.on_ground='true'},
        {param($r)$r.server.proxy_support=1},{param($r)$r.client.x=2.01},{param($r)$r.server.z=-2.01},
        {param($r)$r.server.y=76.01},{param($r)$r.server.y=51.99},{param($r)$r.server.vx=4.01},
        {param($r)$r.server.x=[double]::NaN},{param($r)$r.server_age_ns=-1},{param($r)$r.server_age_ns=250000001},
        {param($r)$r.server_age_ns='0'},{param($r)$r.server_seq=1.5})) {
        $state=Start-TestState;$record=New-TestRecord sample 2;& $change $record
        Assert-Rejected $state (Convert-TestLine $record)
    }
    $state=Start-TestState;$line=Convert-TestLine (New-TestRecord sample 2)
    Assert-Rejected $state ($line.Replace('"x":0.7','"x":1e309'))
}

Test-TraceReceiver 'malformed partial duplicate root nested and concatenated JSON reject' {
    $state=Start-TestState;$line=Convert-TestLine (New-TestRecord sample 2)
    Assert-Rejected $state ($line.Substring(0,$line.Length-1))
    Assert-Rejected $state ($line+$line)
    Assert-Rejected $state ($line.Replace('"seq":2','"seq":2,"seq":2'))
    Assert-Rejected $state ($line.Replace('"x":0.7','"x":0.7,"x":0.7'))
    Assert-Rejected $state ($line+"`n")
    Assert-Rejected $state ($line.Replace('"phase":"WALKING"','"phase":"walk"'))
}

Test-TraceReceiver 'JSON depth byte and member limits reject without consuming state' {
    $state=Start-TestState;$nested=('['*14)+'0'+(']'*14)
    Assert-Rejected $state ('{"extra":'+$nested+'}')
    Assert-Rejected $state ('{"pad":"'+('é'*2100)+'"}')
    Assert-Rejected $state ('{"members":['+(('0,'*1024)+'0')+']}')
    $state=Start-TestState;$state.Bytes=65535
    Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 2))
}

Test-TraceReceiver 'end requires matching last server sequence and forbids later append/replay' {
    $state=Start-TestState
    Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2)) 1100 | Out-Null
    Assert-Rejected $state (Convert-TestLine (New-TestRecord end 3 PASSED))
    Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 3 PASSED 1100 2)) 1100 | Out-Null
    Assert-Rejected $state (Convert-TestLine (New-TestRecord end 4 PASSED 1100 0))
    Assert-Rejected $state (Convert-TestLine (New-TestRecord end 4 FAILED 1100 2))
    $answer=Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord end 4 PASSED 1100 2)) 1100
    Assert-Equal $answer.Kind 'end';Assert-Equal $state.Ended $true
    Assert-Equal $answer.PSObject.Properties['Target'] $null
    Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 5 WALKING 1100 3))
    Assert-Rejected $state (Convert-TestLine (New-TestRecord end 4 PASSED 1100 2))
}

Test-TraceReceiver 'stale or ungrounded PASSED samples cannot authorize successful end' {
    foreach($mode in @('stale','ungrounded','delayed_end','intervening')) {
        $state=Start-TestState
        Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 2)) 1100 | Out-Null
        $record=New-TestRecord sample 3 PASSED 1100 2
        if($mode -eq 'ungrounded'){$record.server.on_ground=$false}
        $sampleNow=if($mode -eq 'stale'){1400}else{1100}
        Receive-MineComeMovementTrace $state (Convert-TestLine $record) $sampleNow | Out-Null
        $endSeq=4;$serverSeq=2
        if($mode -eq 'intervening') {
            Receive-MineComeMovementTrace $state (Convert-TestLine (New-TestRecord sample 4 LANDING 1100 3)) 1100 | Out-Null
            $endSeq=5;$serverSeq=3
        }
        $endNow=if($mode -eq 'delayed_end'){1400}else{$sampleNow}
        Assert-Rejected $state (Convert-TestLine (New-TestRecord end $endSeq PASSED 1100 $serverSeq)) $endNow
    }
}

Test-TraceReceiver 'final record slot accepts only end and termination reason is bounded' {
    $state=Start-TestState;$state.LastSeq=199;$state.Records=199
    Assert-Rejected $state (Convert-TestLine (New-TestRecord sample 200))
    $record=New-TestRecord end 200 STOPPED 1100 0;$record.result='stopped'
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1100).Kind 'end'
    $state=Start-TestState;$record=New-TestRecord end 2 STOPPED 1100 0;$record.result='stopped';$record.reason='a'*161
    Assert-Rejected $state (Convert-TestLine $record)
}

Test-TraceReceiver 'patch label does not authenticate fixture and complete finite coverage is required' {
    $fixtureOnly=Join-Path $fixtureDirectory 'fixture-labelled.json'
    $copy=$patch | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable
    $copy.provenance.kind='standalone_fixture';$copy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixtureOnly -Encoding utf8
    $rejected=$false;try { New-MineComeTraceReceiver $fixtureOnly 1000 | Out-Null } catch { $rejected=$true };Assert-Equal $rejected $true
    $copy.provenance.kind='live_kcd_ground_patch';$copy.points[24].index=1
    $copy | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixtureOnly -Encoding utf8
    $rejected=$false;try { New-MineComeTraceReceiver $fixtureOnly 1000 | Out-Null } catch { $rejected=$true };Assert-Equal $rejected $true
}

Test-TraceReceiver 'HUD profile requires explicit canonical exact readiness save and leaves legacy strict' {
    $hudSave='MineCome-HudStream-'+$world
    $record=New-TestRecord begin 1;$record.save=$hudSave
    Assert-Rejected (New-TestState) (Convert-TestLine $record)
    foreach($badSave in @('','MineCome-HudStream-any','MineCome-Ground-'+$world,('MineCome-HudStream-'+$world.ToUpperInvariant()))) {
        $threw=$false
        try{New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $badSave | Out-Null}catch{$threw=$true}
        Assert-Equal $threw $true
    }
    $state=New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave $hudSave
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1100).Kind 'begin'
    Assert-Equal $state.Save $hudSave
    $record=New-TestRecord sample 2
    Assert-Rejected $state (Convert-TestLine $record)
    $record.save=$hudSave
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1100).Kind 'sample'
    $record=New-TestRecord sample 3 PASSED 1100 2;$record.save=$hudSave
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1100).Kind 'observe'
    $record=New-TestRecord end 4 PASSED 1100 2;$record.save=$hudSave
    Assert-Equal (Receive-MineComeMovementTrace $state (Convert-TestLine $record) 1100).Kind 'end'
    $state=New-MineComeTraceReceiver $patchPath 1000 -ExpectedHudSave ('MineCome-HudStream-'+[guid]::NewGuid().ToString('D'))
    $record=New-TestRecord begin 1;$record.save=$hudSave
    Assert-Rejected $state (Convert-TestLine $record)
}
Write-Output "Verified $script:traceTestsPassed standalone movement-trace receiver cases. No game calls. Fixtures: $fixtureDirectory"
