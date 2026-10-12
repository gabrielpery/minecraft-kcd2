#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only engine camera/player capture tied to one input session and ground patch.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$PatchFile,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$InputRun
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$patch=Get-Content -LiteralPath $PatchFile -Raw|ConvertFrom-Json
$patchHash=(Get-FileHash -LiteralPath $PatchFile).Hash.ToLowerInvariant()
$probe=$null;$receipt=$null;$failure=$null;$capturedUtcMs=$null;$seedFile=$null;$seedHash=$null
try {
    $probe=New-MineComeProbeRun $Context 'input-view' (Join-Path $Context.ProjectRoot 'kcd2/probes/view_seed.lua') 'SampleInputView'
    $capturedUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    Invoke-MineComeProbeConsole $Context ("#MineCome.SampleInputView('"+$probe.Run+"')")
    Invoke-MineComeProbeConsole $Context ("#System.LogAlways('[MineComeInputViewFlush] "+$probe.Run+"')")
    $deadline=[DateTime]::UtcNow.AddSeconds(4)
    do {
        Assert-MineComeProbeContext $Context
        $receipts=@(Get-MineComeProbeReceipts (Read-MineComeProbeLog $Context $probe.Offset) 'MineComeInputView' $probe.Run)
        if($receipts.Count -gt 1){throw 'Duplicate view receipt; refusing ambiguous starting camera.'}
        if($receipts.Count -eq 1){$receipt=$receipts[0];break}
        Start-Sleep -Milliseconds 50
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not $receipt -or $receipt.valid -cne $true -or $receipt.reason -cne 'ok') { throw 'No fresh valid engine camera receipt; inspect input-view evidence.' }
    $distanceSquared=0.0
    foreach($axis in @('x','y','z')) {
        $value=$receipt.player.$axis
        if($value -isnot [ValueType] -or -not [double]::IsFinite([double]$value)) { throw 'Non-numeric view player position.' }
        $difference=[double]$value-[double]$patch.center.$axis
        $distanceSquared+=$difference*$difference
    }
    if($distanceSquared -gt 0.01) { throw 'Player moved more than0.1m from captured ground; capture a new patch.' }
    $seedFile=Join-Path $EvidenceDirectory 'view-seed.json'
    if(Test-Path -LiteralPath $seedFile){throw 'View seed must be a new file.'}
    $seed=[ordered]@{schema=1;run=$InputRun;source_kind='live_kcd_view_seed';patch_sha256=$patchHash;target_pid=$Context.GamePid;target_start_filetime=$Context.GameStartedUtc.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture);captured_utc_ms=$capturedUtcMs;player=$receipt.player;forward=$receipt.forward;up=$receipt.up}
    $bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes(($seed|ConvertTo-Json -Depth 6))
    if($bytes.Length -gt 4096){throw 'View seed exceeds4096bytes.'}
    $stream=[IO.FileStream]::new($seedFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush()}finally{$stream.Dispose()}
    $seedHash=(Get-FileHash -LiteralPath $seedFile).Hash
    (Get-Item -LiteralPath $seedFile).IsReadOnly=$true
    [pscustomobject]@{ViewSeedFile=$seedFile;ViewSeedHash=$seedHash;EvidenceDirectory=$probe.Directory;ProbeRun=$probe.Run;SourceHash=$probe.SourceHash;CapturedUtcMs=$capturedUtcMs}
}catch{$failure=$_.Exception.Message;throw}
finally {
    if($probe) {
        try{Read-MineComeProbeLog $Context $probe.Offset|Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log')}catch{$_|Out-String|Set-Content -LiteralPath (Join-Path $probe.Directory 'capture-error.txt')}
        $receipt|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $probe.Directory 'receipt.json')
        [ordered]@{Kind='Read-only starting-view capture';Run=$probe.Run;InputRun=$InputRun;GamePid=$Context.GamePid;GameStartedUtc=$Context.GameStartedUtc;GamePath=$Context.GamePath;GameHash=$Context.GameHash;SourceHash=$probe.SourceHash;SnapshotHash=$probe.SnapshotHash;FunctionReloadVerified=$probe.FunctionReloadVerified;EngineViewReceiptVerified=($null -ne $seedHash);CapturedUtcMs=$capturedUtcMs;PatchFile=$PatchFile;PatchSha256=$patchHash;ViewSeedFile=$seedFile;ViewSeedHash=$seedHash;PlayerOrCameraMovementApplied=$false;Failure=$failure}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json')
    }
}
