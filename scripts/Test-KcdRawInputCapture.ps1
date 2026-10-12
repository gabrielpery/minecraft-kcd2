#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Observe a pinned tools window. No game keys, input suppression or engine writes.
[CmdletBinding()]
param(
    [ValidateRange(15,120)][int]$Seconds=30,
    [string]$CaptureExecutable,
    [string]$Bindings='W,S,A,D,SPACE,LSHIFT',
    [switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'InputBindings.ps1')
$bindingSet=Get-MineComeInputBindings $Bindings
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'MovementTraceReceiver.ps1')
$context=Get-MineComeProbeContext
if(-not $CaptureExecutable) { $CaptureExecutable=Join-Path $context.ProjectRoot 'build/native/Release/minecome_input_capture.exe' }
$exe=(Resolve-Path -LiteralPath $CaptureExecutable).Path
$exeHash=(Get-FileHash -LiteralPath $exe).Hash
$targetStart=$context.GameStartedUtc.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)
if($PreflightOnly) {
    [pscustomobject]@{Preflight='passed';GamePid=$context.GamePid;GameHash=$context.GameHash;TargetStartFiletime=$targetStart;CaptureHash=$exeHash}
    return
}
$run=[Guid]::NewGuid().ToString('N')
$directory=Join-Path $context.ProjectRoot ('runtime/evidence/raw-input-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run)
New-Item -ItemType Directory -Path $directory | Out-Null
$snapshot=Join-Path $directory 'minecome_input_capture.exe'
Copy-Item -LiteralPath $exe -Destination $snapshot
if((Get-FileHash -LiteralPath $snapshot).Hash -ne $exeHash) { throw 'Capture executable changed while copying; no observer launched.' }
(Get-Item -LiteralPath $snapshot).IsReadOnly=$true
$sourceHashes=@(Get-ChildItem -LiteralPath (Join-Path $context.ProjectRoot 'tools/input_capture') -File | ForEach-Object {
    [pscustomobject]@{Name=$_.Name;Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
})
$output=Join-Path $directory 'input.ndjson'
$stdout=Join-Path $directory 'capture.stdout.log';$stderr=Join-Path $directory 'capture.stderr.log'
$helper=$null;$helperStartedUtc=$null;$failure=$null;$lifecyclePassed=$false;$records=@();$begunUtc=[DateTime]::UtcNow
try {
    Assert-MineComeProbeContext $context
    $arguments=@('--target-pid',[string]$context.GamePid,'--target-start',$targetStart,'--run',$run,'--output',('"'+$output+'"'),'--seconds',[string]$Seconds,'--bindings',$bindingSet.Argument)
    $helper=Start-Process -FilePath $snapshot -WorkingDirectory $context.ProjectRoot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $helperStartedUtc=$helper.StartTime.ToUniversalTime()
    Write-Output "RAW_INPUT_OBSERVER_STARTED run=$run seconds=$Seconds; read-only, initially disarmed. F8 arms while KCD2 is focused and controls are released."
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds+5)
    while(-not $helper.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if(-not $helper.HasExited) { throw 'Capture helper exceeded its absolute runtime; no game process was stopped.' }
    $helper.WaitForExit()
    if($helper.ExitCode -ne 0) { throw "Capture helper failed with exit code $($helper.ExitCode); inspect its local stderr." }
    $log=Get-Content -LiteralPath $stdout -Raw
    if($log -notmatch ('(?m)^INPUT_CAPTURE_BINDINGS keys='+[regex]::Escape($bindingSet.Argument)+'\r?$')) { throw 'Native helper did not acknowledge the selected bindings.' }
    if($log -notmatch 'INPUT_CAPTURE_REGISTERED classes=2' -or $log -notmatch 'INPUT_CAPTURE_CLEANUP unregistered=true' -or $log -notmatch 'FOCUS_OBSERVER_CLEANUP unhooked=true') { throw 'Actual OS registration, device cleanup or foreground-observer cleanup readbacks are missing.' }
    $file=Get-Item -LiteralPath $output
    if($file.Length -lt 1 -or $file.Length -gt 1048576) { throw 'Capture exceeded its1MiB bound or is empty.' }
    $json=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($output))
    if(-not $json.EndsWith("`n")) { throw 'Capture ended with a partial NDJSON record.' }
    $lines=@($json.Split([char]10) | Where-Object Length -gt 0)
    if($lines.Count -gt 2500 -or $lines.Count -lt 3) { throw 'Capture record count is outside bounds.' }
    $common=@('schema','source_kind','kind','run','seq','utc_ms','monotonic_ms','target_pid','target_start_filetime','focused','armed','held','mouse_dx','mouse_dy')
    $lastMonotonic=[long]0
    $records=@(for($index=0;$index -lt $lines.Count;$index++) {
        $document=Read-MineComeTraceJson $lines[$index] 4096
        try {
            $root=$document.RootElement;$kind=Get-MineComeTraceString $root 'kind'
            $keys=if($kind -ceq 'end'){$common+@('reason')}else{$common}
            Assert-MineComeTraceKeys $root $keys
            [void](Get-MineComeTraceInteger $root 'schema' 1 1)
            if((Get-MineComeTraceString $root 'source_kind') -cne 'windows_raw_input_v1' -or (Get-MineComeTraceString $root 'run') -cne $run -or (Get-MineComeTraceString $root 'target_start_filetime') -cne $targetStart) { throw 'Capture session/creation identity mismatch.' }
            [void](Get-MineComeTraceInteger $root 'target_pid' $context.GamePid $context.GamePid)
            [void](Get-MineComeTraceInteger $root 'seq' ($index+1) ($index+1))
            [void](Get-MineComeTraceInteger $root 'utc_ms' ([DateTimeOffset]::new($begunUtc).ToUnixTimeMilliseconds()-50) ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+50))
            $lastMonotonic=Get-MineComeTraceInteger $root 'monotonic_ms' $lastMonotonic ($Seconds*1000+5000)
            $focused=Get-MineComeTraceBoolean $root 'focused';$armed=Get-MineComeTraceBoolean $root 'armed'
            if($armed -and -not $focused) { throw 'Background capture incorrectly claims armed state.' }
            $held=Get-MineComeTraceField $root 'held';Assert-MineComeTraceKeys $held @('forward','back','left','right','jump','sprint')
            $anyHeld=$false
            foreach($name in @('forward','back','left','right','jump','sprint')) { $pressed=Get-MineComeTraceBoolean $held $name;$anyHeld=$anyHeld -or $pressed }
            $dx=Get-MineComeTraceInteger $root 'mouse_dx' -32767 32767;$dy=Get-MineComeTraceInteger $root 'mouse_dy' -32767 32767
            if(($kind -cne 'sample' -or -not $focused -or -not $armed) -and ($anyHeld -or $dx -ne 0 -or $dy -ne 0)) { throw 'Inactive capture carried live held/mouse input.' }
            $expectedKind=if($index -eq 0){'begin'}elseif($index -eq $lines.Count-1){'end'}else{'sample'}
            if($kind -cne $expectedKind) { throw 'Capture framing must be one begin, samples and one final end.' }
            if($kind -ceq 'begin' -and ($focused -or $armed -or $lastMonotonic -ne 0)) { throw 'Capture begin must be unfocused, disarmed and elapsed0.' }
            if($kind -ceq 'end' -and ((Get-MineComeTraceString $root 'reason') -cne 'duration' -or $focused -or $armed)) { throw 'Capture did not finish with a neutral duration termination.' }
            Convert-MineComeTraceValue $root
        } finally { $document.Dispose() }
    })
    $lifecyclePassed=$true
    $active=@($records | Where-Object { $_.kind -eq 'sample' -and $_.focused -and $_.armed })
    Write-Output "RAW_INPUT_LIFECYCLE_PASS records=$($records.Count) armedSamples=$($active.Count) registration=true cleanup=true. Evidence: $directory"
} catch { $failure=$_.Exception.Message;throw }
finally {
    if($helper -and -not $helper.HasExited) {
        # Only the exact copied helper started by this script is eligible for recovery.
        try {
            $owned=Get-Process -Id $helper.Id -ErrorAction Stop
            if($owned.Path -eq $snapshot -and $owned.StartTime.ToUniversalTime() -eq $helperStartedUtc) { Stop-Process -Id $helper.Id -ErrorAction Stop }
        } catch { $_.Exception.Message|Set-Content -LiteralPath (Join-Path $directory 'helper-recovery-error.txt') }
    }
    [pscustomobject]@{Kind='Read-only Windows Raw Input lifecycle diagnostic';Run=$run;GamePid=$context.GamePid;GamePath=$context.GamePath;GameStartedUtc=$context.GameStartedUtc;GameHash=$context.GameHash;TargetStartFiletime=$targetStart;HelperPid=$(if($helper){$helper.Id}else{$null});CaptureHash=$exeHash;SourceHashes=$sourceHashes;Bindings=$bindingSet;RequestedSeconds=$Seconds;Records=$records.Count;OperatingSystemLifecyclePass=$lifecyclePassed;PhysicalWalkingAndMouseDeliveryVerified=$false;MinecraftInputApplicationVerified=$false;EngineInputWrites=$false;Failure=$failure}|
        ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $directory 'verification.json')
}
