#Requires -Version 7.3
# Original bounded vanilla UI control lab. Fixture mode never operates KCD2.
# Live mode arms only an already-running, separately installed keyboard-only addon.
[CmdletBinding()]
param(
    [ValidateSet('Fixture','Live')][string]$Mode='Fixture',
    [string]$JavaHome,[string]$BundleDirectory,[switch]$PreflightOnly,[switch]$DelayFixture,
    [ValidateRange(320,1920)][int]$Width=1280,
    [ValidateRange(240,1080)][int]$Height=720,
    [ValidateRange(1,4)][int]$GuiScale=2
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$evidenceRoot=Join-Path $root 'runtime/evidence'
$fixturePath=Join-Path $root 'build/hud-input-waitfix-20261012/kcd2/hud/input/Release/minecome_hud_input_fixture.exe'
function Assert-Unlinked([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked UI lab path refused: $cursor"}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-Receipt([string]$Path){
    $null=Assert-Unlinked $Path
    $item=Get-Item -LiteralPath $Path
    if($item.PSIsContainer -or $item.Length -lt 2 -or $item.Length -gt 64KB){throw 'Invalid bounded UI receipt.'}
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 16)
}
function Start-Child([string]$Executable,[string[]]$Arguments){
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable;$start.WorkingDirectory=$root
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in $Arguments){$start.ArgumentList.Add($argument)}
    return [Diagnostics.Process]::Start($start)
}
$null=Assert-Unlinked $evidenceRoot
if($DelayFixture -and $Mode -ne 'Fixture'){throw 'Controlled input delays require the standalone fixture.'}
if($Width -lt 320*$GuiScale -or $Height -lt 240*$GuiScale){throw 'UI layout needs at least320x240 logical pixels.'}
$inventory=Read-Receipt (Join-Path $root 'runtime/environment.json')
if(-not $JavaHome){
    foreach($candidate in @($inventory.java.jdks | ForEach-Object home)){
        if((Test-Path -LiteralPath (Join-Path $candidate 'release')) -and [IO.File]::ReadAllText((Join-Path $candidate 'release')) -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")'){$JavaHome=$candidate;break}
    }
}
if(-not $JavaHome){throw 'An installed tested JDK21 or24 is required.'}
$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path
if(-not(Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")'){throw 'An installed tested JDK21 or24 is required.'}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*')})
if($clients.Count){throw 'Existing MineCome Minecraft client preserved.'}
$fixtureHash=$null;$context=$null
if($Mode -eq 'Fixture'){
    $null=Assert-Unlinked $fixturePath
    if(-not(Test-Path -LiteralPath $fixturePath -PathType Leaf)){throw 'Build the separate HUD input fixture first.'}
    $fixtureHash=(Get-FileHash -LiteralPath $fixturePath).Hash.ToLowerInvariant()
}else{
    . (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
    $context=Get-MineComeProbeContext
    if(-not $BundleDirectory){$BundleDirectory=Join-Path $root 'runtime/hud-compositor-input-waitfix'}
    & (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -InputMode -BundleDirectory $BundleDirectory -PreflightOnly
}
if($PreflightOnly){Write-Output "HUD_INPUT_PREFLIGHT_PASS mode=$Mode no_process_started=true";return}
$run=[guid]::NewGuid().ToString('N')
$directory=Assert-Unlinked (Join-Path $evidenceRoot ('hud-input-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run))
if(Test-Path -LiteralPath $directory){throw 'New UI evidence directory required.'}
[IO.Directory]::CreateDirectory($directory)|Out-Null
$expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+180000
$readyPath=Join-Path $directory 'capture/stream-ready.json'
$fixtureReady=Join-Path $directory 'fixture-ready.json'
$fixtureResult=Join-Path $directory 'fixture-result.json'
$fixture=$null;$client=$null;$armEvidence=$null;$failure=$null;$passed=$false;$targetPid=0;$targetStart='';$guest=$null
try{
    if($Mode -eq 'Fixture'){
        if((Get-FileHash -LiteralPath $fixturePath).Hash -ine $fixtureHash){throw 'Fixture changed before launch.'}
        $fixtureArguments=@('--run',$run,'--expires',[string]$expires,'--ready-output',$fixtureReady,'--guest-ready',$readyPath,'--output',$fixtureResult)
        if($DelayFixture){$fixtureArguments+=@('--prearm-delay-ms','1000')}
        $fixture=Start-Child $fixturePath $fixtureArguments
        $readyDeadline=[DateTime]::UtcNow.AddSeconds(10)
        while(-not(Test-Path -LiteralPath $fixtureReady)){
            if($fixture.HasExited -or [DateTime]::UtcNow -ge $readyDeadline){throw 'Fixture did not publish readiness.'}
            Start-Sleep -Milliseconds 50
        }
        $nativeReady=Read-Receipt $fixtureReady
        if($nativeReady.schema -ne 1 -or $nativeReady.kind -cne 'minecome_hud_input_fixture_ready_v1' -or $nativeReady.run -cne $run -or $nativeReady.host_pid -ne $fixture.Id -or [string]$nativeReady.host_start_filetime -cne $fixture.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -or $nativeReady.expires_utc_ms -ne $expires){throw 'Fixture process readiness mismatch.'}
        $targetPid=$fixture.Id;$targetStart=[string]$nativeReady.host_start_filetime
    }else{$targetPid=$context.GamePid;$targetStart=$context.GameStartedUtc.ToFileTimeUtc().ToString()}
    $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,'-TargetPid',[string]$targetPid,'-TargetStart',$targetStart,'-ExpiresUtcMs',[string]$expires,'-JavaHome',$JavaHome,'-Width',[string]$Width,'-Height',[string]$Height,'-GuiScale',[string]$GuiScale,'-InputMode')
    if($Mode -eq 'Fixture'){$arguments+='-InputFixture'}
    if($DelayFixture){$arguments+='-InputDelayFixture'}
    $client=Start-Child (Join-Path $PSHOME 'pwsh.exe') $arguments
    Write-Output "HUD_INPUT_START mode=$Mode run=$run evidence=$directory"
    while(-not(Test-Path -LiteralPath $readyPath)){
        if($client.HasExited){throw "Minecraft exited before UI readiness: $($client.ExitCode)"}
        if($fixture -and $fixture.HasExited){throw 'Fixture exited before Minecraft readiness.'}
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $expires-45000){throw 'UI startup deadline reached.'}
        if($Mode -eq 'Live'){Assert-MineComeProbeContext $context}
        Start-Sleep -Milliseconds 100
    }
    $ready=Read-Receipt $readyPath
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_fixture' -or $ready.ui_input_fixture -isnot [bool] -or $ready.ui_input_fixture -ne ($Mode -eq 'Fixture')){throw 'UI producer fixture/live mode mismatch.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_delay_fixture' -or $ready.ui_input_delay_fixture -isnot [bool] -or $ready.ui_input_delay_fixture -ne [bool]$DelayFixture){throw 'UI producer delay-fixture mode mismatch.'}
    if($ready.schema -ne 1 -or $ready.run -cne $run -or $ready.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or $ready.ui_input_protocol -ne 1 -or $ready.target_pid -ne $targetPid -or [string]$ready.target_start_filetime -cne $targetStart -or $ready.expires_utc_ms -ne $expires){throw 'Genuine UI producer readiness mismatch.'}
    $producer=Get-Process -Id $ready.producer_pid
    try{
        if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne [string]$ready.producer_start_filetime -or -not $producer.Path.Equals((Join-Path $JavaHome 'bin/java.exe'),[StringComparison]::OrdinalIgnoreCase)){throw 'Actual Minecraft process identity mismatch.'}
    }finally{$producer.Dispose()}
    if($Mode -eq 'Live'){$armEvidence=& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -InputMode -BundleDirectory $BundleDirectory -ReadyManifest $readyPath}
    Write-Output "HUD_INPUT_READY mode=$Mode run=$run"
    while(-not $client.HasExited -or ($fixture -and -not $fixture.HasExited)){
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $expires+15000){throw 'UI shutdown deadline reached; any remaining processes are preserved.'}
        Start-Sleep -Milliseconds 200
    }
    if($client.ExitCode -ne 0 -or ($fixture -and $fixture.ExitCode -ne 0)){throw 'UI client or native fixture reported failure.'}
    $guest=Read-Receipt (Join-Path $directory 'capture/stream-result.json')
    if($guest.PSObject.Properties.Name -notcontains 'ui_input_fixture' -or $guest.ui_input_fixture -isnot [bool] -or $guest.ui_input_fixture -ne ($Mode -eq 'Fixture')){throw 'UI result fixture/live mode mismatch.'}
    if($guest.PSObject.Properties.Name -notcontains 'ui_input_delay_fixture' -or $guest.ui_input_delay_fixture -isnot [bool] -or $guest.ui_input_delay_fixture -ne [bool]$DelayFixture){throw 'UI result delay-fixture mode mismatch.'}
    if($guest.run -cne $run -or $guest.ui_input_protocol -ne 1 -or $guest.published_frames -lt 1 -or $guest.closed_published -ne $true -or $guest.mapping_unmapped -ne $true -or $guest.mapping_handle_closed -ne $true -or $guest.mutex_handle_closed -ne $true){throw 'UI stream publication/closure evidence missing.'}
    if($guest.lab_evidence.input_handles_closed -ne $true -or $guest.lab_evidence.closed_acknowledgement_published -ne $true){throw 'UI input acknowledgement/handle closure evidence missing.'}
    if($Mode -eq 'Fixture'){
        $native=Read-Receipt $fixtureResult
        if($native.run -cne $run -or $native.kind -cne 'minecome_hud_input_fixture_result_v1' -or $native.result -cne 'passed' -or $guest.result -cne 'input_passed' -or $guest.lab_evidence.input_fixture -ne $true -or $guest.lab_evidence.server_swap_verified -ne $true -or $guest.lab_evidence.inventory_opened -ne $true -or $guest.lab_evidence.inventory_closed -ne $true -or $guest.lab_evidence.selected_nine_verified -ne $true){throw 'Real vanilla UI fixture evidence incomplete.'}
        if($DelayFixture -and ($native.prearm_delay_fixture -ne $true -or $native.max_prearm_ack_age_ms -le 250 -or $native.prearm_recoveries -lt 1)){throw 'Controlled prearm delay/recovery was not observed.'}
        if($DelayFixture -and ($guest.lab_evidence.input_delay_fixture -ne $true -or $guest.lab_evidence.withheld_ready_ack_ticks -lt 1 -or $guest.lab_evidence.prearm_ack_delay_ms -le 250 -or $guest.lab_evidence.closed_ack_delay_ms -le 250)){throw 'Actual client-tick startup/closure delays were not observed.'}
    }else{
        if($guest.result -cne 'input_completed'){throw 'Live UI session did not complete cleanly.'}
        if($guest.lab_evidence.host_armed -ne $true -or $guest.lab_evidence.input_events_applied -lt 1){throw 'Live UI session closed without observed arming and applied input.'}
        Assert-MineComeProbeContext $context
    }
    $passed=$true
    Write-Output "HUD_INPUT_COMPLETED mode=$Mode run=$run actual_minecraft=true host_input_exclusivity_verified=false"
}catch{$failure=$_.Exception.Message;throw}
finally{
    [ordered]@{schema=1;kind='minecome_hud_input_controller_v1';run=$run;mode=$Mode;delay_fixture=[bool]$DelayFixture;result=$(if($passed){'passed'}else{'failed'});failure=$failure;evidence=$directory;target_pid=$targetPid;target_start_filetime=$targetStart;fixture_sha256=$fixtureHash;compositor_armed=[bool]$armEvidence;width=$Width;height=$Height;gui_scale=$GuiScale;kcd_launched=$false;kcd_stopped=$false;host_input_exclusivity_verified=$false;live_mouse_enabled=$false;created_utc_ms=$expires-180000;expires_utc_ms=$expires} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
    if($client){$client.Dispose()};if($fixture){$fixture.Dispose()}
}
