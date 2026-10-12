#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Creates a fresh isolated Minecraft lab; never launches or moves KCD2.
[CmdletBinding(DefaultParameterSetName='Captured')]
param(
    [Parameter(ParameterSetName='Captured')][string]$PatchFile,
    [Parameter(Mandatory=$true,ParameterSetName='Fixture')][switch]$Fixture,
    [string]$JavaHome,
    [string]$TraceFile,
    [switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraftRoot=Join-Path $projectRoot 'minecraft'
if(-not $JavaHome) {
    $inventory=Get-Content -LiteralPath (Join-Path $projectRoot 'runtime/environment.json') -Raw | ConvertFrom-Json
    foreach($candidate in @($env:JAVA_HOME)+@($inventory.java.jdks | ForEach-Object home)) {
        if($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'release')) -and
            [IO.File]::ReadAllText((Join-Path $candidate 'release')) -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') { $JavaHome=$candidate;break }
    }
}
if(-not $JavaHome) { throw 'An existing tested JDK21 or24 is required; no dependency was installed.' }
$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path
if(-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or
    [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') { throw 'Pass the existing tested JDK21 or24.' }
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object { $_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraftRoot+'*') })
if($clients.Count) { throw 'An owned Minecraft development client is already open; preserving it.' }
if($PatchFile) {
    $PatchFile=(Resolve-Path -LiteralPath $PatchFile).Path
    if((Get-Item -LiteralPath $PatchFile).Length -gt 65536) { throw 'Ground patch exceeds the64KiB input bound.' }
}
if($PreflightOnly) { Write-Output 'Movement-lab preflight passed; no world, build or process changes made.';return }

$runToken=[Guid]::NewGuid().ToString('N')
$runDirectory=Join-Path $projectRoot ('runtime/evidence/ground-movement-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$runToken)
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$kind=$null;$capture=$null;$exitCode=$null;$passed=$false;$failure=$null;$started=[DateTime]::UtcNow
$oldJavaHome=$env:JAVA_HOME;$oldGradleHome=$env:GRADLE_USER_HOME
try {
    if($Fixture) {
        # Deliberately synthetic: this proves the Minecraft collision hook and
        # normal movement only. It is never labelled as actual KCD terrain.
        $points=for($row=0;$row -lt 5;$row++) { for($column=0;$column -lt 5;$column++) {
            $dx=$column-2;$dy=$row-2;$normalLength=[Math]::Sqrt(1+0.08*0.08+0.06*0.06)
            [pscustomobject]@{schema=1;run=$runToken;index=1+$row*5+$column;x=120+$dx;y=2040+$dy;z=56+0.08*$dx+0.06*$dy;nx=-0.08/$normalLength;ny=-0.06/$normalLength;nz=1/$normalLength;valid=$true;result='hit';mask=256;approximate_heightfield=$true;full_collision_export_verified=$false}
        }}
        $PatchFile=Join-Path $runDirectory 'standalone-fixture.json'
        [pscustomobject]@{schema=1;run=$runToken;result='sampled';center=@{x=120;y=2040;z=56};grid_size=5;spacing=1;point_count=25;valid_count=25;stable_player=$true;mask=256;approximate_heightfield=$true;full_collision_export_verified=$false;points=@($points);provenance=@{kind='standalone_fixture';captured_utc=[DateTime]::UtcNow.ToString('o')}} |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PatchFile -Encoding utf8
    } elseif(-not $PatchFile) {
        $captureOutput=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch)
        $capture=@($captureOutput | Where-Object { $_ -isnot [string] -and $_.GroundPatchFile })
        if($capture.Count -ne 1) { throw 'One complete engine ground-patch capture is required.' }
        $PatchFile=$capture[0].GroundPatchFile
    }
    if((Get-Item -LiteralPath $PatchFile).Length -gt 65536) { throw 'Ground patch exceeds the64KiB input bound.' }
    $snapshot=Join-Path $runDirectory 'ground-patch.json'
    $sourceHash=(Get-FileHash -LiteralPath $PatchFile).Hash
    Copy-Item -LiteralPath $PatchFile -Destination $snapshot
    $snapshotHash=(Get-FileHash -LiteralPath $snapshot).Hash
    if($sourceHash -ne $snapshotHash) { throw 'The ground patch changed while copying; no Minecraft launch attempted.' }
    (Get-Item -LiteralPath $snapshot).IsReadOnly=$true
    $data=Get-Content -LiteralPath $snapshot -Raw | ConvertFrom-Json
    $kind=$data.provenance.kind
    if($kind -notin @('standalone_fixture','live_kcd_ground_patch')) { throw 'Ground patch must retain explicit live-capture or fixture provenance.' }
    if($kind -eq 'standalone_fixture' -and -not $Fixture) { throw 'A fixture requires the explicit -Fixture option.' }
    if($kind -eq 'live_kcd_ground_patch') {
        # A label alone cannot turn a hand-written input into engine evidence.
        # Keep the exact adjacent capture record and immutable Lua snapshot.
        $captureDirectory=Split-Path -Parent $PatchFile
        $captureRecord=Get-Content -LiteralPath (Join-Path $captureDirectory 'verification.json') -Raw | ConvertFrom-Json
        $captureReceipt=Get-Content -LiteralPath (Join-Path $captureDirectory 'receipt.json') -Raw | ConvertFrom-Json
        $capturedSourceHash=(Get-FileHash -LiteralPath (Join-Path $captureDirectory 'ground_patch.lua')).Hash
        $expectedSourceHash=(Get-FileHash -LiteralPath (Join-Path $projectRoot 'kcd2/probes/ground_patch.lua')).Hash
        $inventory=Get-Content -LiteralPath (Join-Path $projectRoot 'runtime/environment.json') -Raw | ConvertFrom-Json
        $official=@($inventory.steam.relevant_apps | Where-Object { $_.role -eq 'official_tools' -and $_.installed })
        $pinnedExe=@($official.binaries | Where-Object { $_.path -eq $captureRecord.GamePath })
        if($captureRecord.Patch -ne $true -or $captureRecord.FunctionReloadVerified -ne $true -or $captureRecord.EngineReceiptVerified -ne $true -or $captureRecord.Failure -or
            $captureRecord.GroundPatchFile -ne $PatchFile -or $captureRecord.GroundPatchHash -ne $sourceHash -or $captureRecord.Run -ne $data.run -or $captureReceipt.run -ne $data.run -or
            $captureReceipt.stable_player -ne $true -or $captureReceipt.valid_count -ne 25 -or
            $capturedSourceHash -ne $expectedSourceHash -or $captureRecord.SourceHash -ne $capturedSourceHash -or $captureRecord.SnapshotHash -ne $capturedSourceHash -or
            $data.provenance.source_sha256 -ne $capturedSourceHash -or $pinnedExe.Count -ne 1 -or $pinnedExe[0].sha256 -ne $captureRecord.GameHash -or $data.provenance.game_exe_hash -ne $captureRecord.GameHash) {
            throw 'The labelled live patch does not match its pinned, immutable engine capture evidence.'
        }
    }
    $env:JAVA_HOME=$JavaHome;$env:GRADLE_USER_HOME=Join-Path $minecraftRoot '.gradle-user-home'
    $wrapper=Join-Path $minecraftRoot 'gradlew.bat'
    Write-Output "Starting one new owned Minecraft movement lab with source=$kind"
    $arguments=@('-p',$minecraftRoot,'--no-daemon','runClient','-PminecomeGroundMovementLab',"-PminecomeGroundPatchFile=$snapshot")
    if($TraceFile) { $arguments+="-PminecomeMovementTraceFile=$TraceFile" }
    & $wrapper @arguments 2>&1 |
        Tee-Object -FilePath (Join-Path $runDirectory 'minecraft.log')
    $exitCode=$LASTEXITCODE
    $log=Get-Content -LiteralPath (Join-Path $runDirectory 'minecraft.log') -Raw
    $passed=$exitCode -eq 0 -and $log -match 'GROUND_MOVEMENT_LAB_PASS' -and $log -notmatch 'GROUND_MOVEMENT_LAB_FAIL'
    if(-not $passed) { throw 'The real Minecraft lab did not report a successful bounded movement result. Inspect this run before repeating.' }
    Write-Output "Real Minecraft movement lab passed; source=$kind. Evidence: $runDirectory"
} catch { $failure=$_.Exception.Message;throw }
finally {
    $env:JAVA_HOME=$oldJavaHome;$env:GRADLE_USER_HOME=$oldGradleHome
    [pscustomobject]@{Kind='Isolated Minecraft approximate-heightfield movement lab';SourceKind=$kind;StartedUtc=$started;FinishedUtc=[DateTime]::UtcNow;PatchFile=$PatchFile;PatchHash=$(if($snapshotHash){$snapshotHash}else{$null});TraceFile=$TraceFile;MinecraftExit=$exitCode;MinecraftMovementVerified=$passed;FullKcdCollisionExportVerified=$false;KcdPlayerMovementApplied=$false;Failure=$failure} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDirectory 'verification.json')
}
