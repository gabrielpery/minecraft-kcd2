#Requires -Version 5.1
# USER-ONLY diagnostic launch. Agents may invoke -PreflightOnly; they must not launch through this script.
# Starts the exact official development executable on fresh trosecko; never loads a save.
# Monitors only the process returned by Start-Process, then leaves a surviving game running.
# -WithoutMods uses the official empty mod_order.txt mechanism; it never changes a mod.
# Source: official KM-A-56 Installing mods (pinned offline wiki).
# Memory ABI: https://learn.microsoft.com/windows/win32/api/psapi/nf-psapi-getperformanceinfo
# Layout/units: https://learn.microsoft.com/windows/win32/api/psapi/ns-psapi-performance_information
[CmdletBinding()]
param([string]$GameRoot, [switch]$PreflightOnly, [switch]$WithoutMods)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $minecomeBootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($minecomeBootstrapExit -ne 0){throw "Forwarded PowerShell 7 helper failed with exit code $minecomeBootstrapExit."}
    return
}
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$minecomeShellProcess=[Diagnostics.Process]::GetCurrentProcess()
try{$minecomeShellPath=$minecomeShellProcess.MainModule.FileName}finally{$minecomeShellProcess.Dispose()}
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$expectedExeHash = 'a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a'
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-UnlinkedPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path); $cursor = $full
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Linked diagnostic path refused: $cursor" }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-LogTail([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [pscustomobject]@{Bytes=$null;Metadata=[ordered]@{path=$Path;missing=$true}} }
    $null = Assert-UnlinkedPath $Path
    $stream = [IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $length = $stream.Length; $offset = [Math]::Max([long]0,$length-8MB)
        $bytes = [byte[]]::new([int]($length-$offset)); $stream.Position=$offset; $read=0
        while ($read -lt $bytes.Length) {
            $count=$stream.Read($bytes,$read,$bytes.Length-$read)
            if ($count -eq 0) { throw 'Game log shrank during bounded tail capture.' }; $read+=$count
        }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
        return [pscustomobject]@{Bytes=$bytes;Metadata=[ordered]@{path=$Path;missing=$false;source_bytes=$length;captured_offset=$offset;captured_bytes=$bytes.Length;tail_truncated=($offset-ne 0);captured_sha256=$hash}}
    } finally { $stream.Dispose() }
}
function Save-NewJson([string]$Path,$Value,[int]$Limit=1048576) {
    $body=$utf8.GetBytes(($Value|ConvertTo-Json -Depth 10)+"`n")
    if ($body.Length -gt $Limit) { throw 'Diagnostic JSON exceeded its byte bound.' }
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try {$stream.Write($body,0,$body.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Test-AllKcdProcessesExited {
    $processes=@();$queryErrors=@()
    try{
        $processes=@(Get-Process -Name KingdomCome -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
        foreach($queryError in $queryErrors){
            # Get-Process emits this expected error when the name has no matches.
            if($queryError.FullyQualifiedErrorId-notlike'NoProcessFoundForGivenName,*'){throw 'Could not establish KingdomCome process state; preserve diagnostic mod order.'}
        }
        $allExited=$true
        foreach($candidate in $processes){
            $candidate.Refresh()
            # A retained handle can keep an exited process enumerable. Count only live processes.
            if(-not$candidate.HasExited){$allExited=$false}
        }
        return $allExited
    }finally{
        foreach($candidate in $processes){$candidate.Dispose()}
    }
}
function Assert-ClosedExactTarget {
    if (-not(Test-AllKcdProcessesExited)) { throw 'Close Kingdom Come normally before this manual diagnostic. No existing process will be stopped.' }
    $version=(Get-Item -LiteralPath $script:gameExe).VersionInfo
    if ((Get-FileHash -LiteralPath $script:gameExe -Algorithm SHA256).Hash -ine $expectedExeHash -or
        $version.FileVersion -cne '1.5.5.0' -or $version.ProductVersion -cne '1.5.5.0' -or
        $version.FileMajorPart -ne 1 -or $version.FileMinorPart -ne 0 -or $version.FileBuildPart -ne 0 -or $version.FilePrivatePart -ne 0) { throw 'The exact pinned official tools executable is required.' }
    if (Test-Path -LiteralPath (Join-Path $script:gameBin 'dxgi.dll')) { throw 'Active tools DXGI proxy still exists. Use the verified rollback before this hook-disabled baseline diagnostic.' }
}
function Assert-ModIsolationAvailable {
    if (-not $WithoutMods) { return }
    $null=Assert-UnlinkedPath $script:modsDirectory
    if (-not (Test-Path -LiteralPath $script:modsDirectory -PathType Container)) { throw 'The discovered tools Mods directory must already exist for -WithoutMods.' }
    $null=Assert-UnlinkedPath $script:modOrderPath
    if (Test-Path -LiteralPath $script:modOrderPath) { throw 'Existing Mods/mod_order.txt refused. This diagnostic will never overwrite a mod order.' }
}

$inventoryPath=Join-Path $projectRoot 'runtime\environment.json'
$null=Assert-UnlinkedPath $inventoryPath
if ((Get-Item -LiteralPath $inventoryPath).Length -gt 1MB) { throw 'Environment inventory exceeds its bound.' }
$inventory=Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8|ConvertFrom-Json
$tools=@($inventory.steam.relevant_apps|Where-Object{$_.role-ceq'official_tools' -and $_.installed-eq$true -and $_.distribution-ceq'Steam' -and $_.app_id-eq'2429020'})
if ($tools.Count-ne 1) { throw 'One discovered official Steam tools installation is required.' }
$discoveredRoot=Assert-UnlinkedPath $tools[0].install_path
if ($GameRoot -and -not ([IO.Path]::GetFullPath($GameRoot).Equals($discoveredRoot,[StringComparison]::OrdinalIgnoreCase))) { throw 'Explicit GameRoot differs from the discovered pinned tools installation.' }
$GameRoot=$discoveredRoot
$gameBin=Assert-UnlinkedPath (Join-Path $GameRoot 'Bin\Win64ReleaseSteamLTO_DLL')
$gameExe=Assert-UnlinkedPath (Join-Path $gameBin 'KingdomCome.exe')
$pinned=@($tools[0].binaries|Where-Object{[IO.Path]::GetFullPath($_.path).Equals($gameExe,[StringComparison]::OrdinalIgnoreCase)})
if ($pinned.Count-ne 1 -or $pinned[0].sha256-ine$expectedExeHash) { throw 'Inventory does not pin this exact development executable.' }
Assert-ClosedExactTarget
$modsDirectory=$null;$modOrderPath=$null
if($WithoutMods){
    $modsDirectory=Assert-UnlinkedPath (Join-Path $GameRoot 'Mods')
    $modOrderPath=Assert-UnlinkedPath (Join-Path $modsDirectory 'mod_order.txt')
    Assert-ModIsolationAvailable
}
if ($PreflightOnly) {
    Write-Output "KCD_TOOLS_DIAGNOSTIC_PREFLIGHT_PASS target=$gameExe level=trosecko game_closed=true active_dxgi_proxy=false without_mods=$([bool]$WithoutMods) no_changes=true"
    return
}
if (-not ('MineCome.Diagnostics.Memory' -as [type])) {
    # Public Windows performance API only. No game memory, native offset, or injection.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MineCome.Diagnostics {
 public static class Memory {
  [StructLayout(LayoutKind.Sequential)] struct PerformanceInformation {
   public uint cb;
   public UIntPtr CommitTotal,CommitLimit,CommitPeak,PhysicalTotal,PhysicalAvailable;
   public UIntPtr SystemCache,KernelTotal,KernelPaged,KernelNonpaged,PageSize;
   public uint HandleCount,ProcessCount,ThreadCount;
  }
  [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
  [DllImport("psapi.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool GetPerformanceInfo(ref PerformanceInformation info,uint size);
  public static ulong[] Read() {
   PerformanceInformation p=new PerformanceInformation();
   p.cb=(uint)Marshal.SizeOf(typeof(PerformanceInformation));
   if(!GetPerformanceInfo(ref p,p.cb))
    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   ulong page=p.PageSize.ToUInt64(),total=p.CommitTotal.ToUInt64(),limit=p.CommitLimit.ToUInt64();
   if(page==0 || limit<total) throw new InvalidOperationException("Invalid system commit snapshot");
   return new ulong[]{checked(total*page),checked(limit*page),checked((limit-total)*page),checked(p.PhysicalAvailable.ToUInt64()*page)};
  }
 }
}
'@
}
if (-not ('MineCome.Diagnostics.FileIdentity' -as [type])) {
    # Independent guard: an earlier diagnostic may already have defined Memory in this PS session.
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MineCome.Diagnostics {
 // File identity is captured from the CREATE_NEW handle and rechecked before cleanup.
 // https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-getfileinformationbyhandle
 public static class FileIdentity {
  [StructLayout(LayoutKind.Sequential)] struct Information {
   public uint Attributes,CreationLow,CreationHigh,AccessLow,AccessHigh,WriteLow,WriteHigh;
   public uint VolumeSerial,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;
  }
  [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
  static extern bool GetFileInformationByHandle(IntPtr handle,out Information info);
  public static string Read(IntPtr handle) {
   Information info;
   if(!GetFileInformationByHandle(handle,out info))
    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   return info.VolumeSerial.ToString("X8")+":"+info.IndexHigh.ToString("X8")+info.IndexLow.ToString("X8");
  }
 }
}
'@
}
$evidenceRoot=Assert-UnlinkedPath (Join-Path $projectRoot 'runtime\evidence')
$run=[guid]::NewGuid().ToString('N')
$directory=Assert-UnlinkedPath (Join-Path $evidenceRoot ('tools-startup-diagnostic-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run))
if (-not $directory.StartsWith($evidenceRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Diagnostic evidence path escaped workspace.' }
[IO.Directory]::CreateDirectory($directory)|Out-Null
$logPaths=@((Join-Path $GameRoot 'kcd.log'),(Join-Path $GameRoot 'kcd_launcher.log'))
$beforeLogs=@()
foreach($path in $logPaths){try{$beforeLogs+=(Read-LogTail $path).Metadata}catch{$beforeLogs+=[ordered]@{path=$path;error=$_.Exception.Message}}}
Save-NewJson (Join-Path $directory 'launch.json') ([ordered]@{
 schema=1;kind='minecome_tools_startup_diagnostic_v1';run=$run;created_utc=[DateTime]::UtcNow.ToString('o');script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
 game_exe=$gameExe;game_exe_sha256=$expectedExeHash;fixed_version='1.0.0.0';display_version='1.5.5.0';working_directory=$GameRoot;arguments=@('-devmode','+map','trosecko')
 powershell_version=$PSVersionTable.PSVersion.ToString();powershell_path=$minecomeShellPath
 monitoring_seconds=120;sample_period_ms=1000;monitor_scope='only_Start-Process_returned_process';active_dxgi_proxy_before_launch=$false;live_world_verified=$false;logs_before=$beforeLogs
 without_mods=[bool]$WithoutMods;mod_order_path=$modOrderPath;mod_isolation_mechanism=$(if($WithoutMods){'official_empty_mod_order'}else{$null})
})
$moduleSnapshots=[Collections.Generic.List[object]]::new()
$afterLogs=@();$memoryErrors=0;$moduleErrors=0;$maxPrivateBytes=[long]0;$minCommitAvailable=$null
$gameProcess=$null;$samples=$null;$status='launch_failed';$failure=$null;$exitSigned=$null;$exitUnsigned=$null;$exitHex=$null;$startUtc=$null;$startFiletime=$null;$sampleCount=0;$moduleBudget=0;$processHandleCaptured=$false
$proxyObserved=$false;$addonObserved=$false;$d3d12Observed=$false;$moduleEnumerationSucceeded=$false
$modIsolation=[ordered]@{requested=[bool]$WithoutMods;path=$modOrderPath;created=$false;file_identity=$null;creation_time_utc=$null;last_write_time_utc=$null;bytes=0;sha256='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';cleanup_status='not_requested';cleanup_required=$false;cleanup_error=$null}
$timer=[Diagnostics.Stopwatch]::new()
try {
    $samples=[IO.FileStream]::new((Join-Path $directory 'memory.ndjson'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    Assert-ClosedExactTarget
    if($WithoutMods){
        Assert-ModIsolationAvailable
        # CREATE_NEW atomically refuses any file which appeared after preflight.
        $ownedOrder=[IO.FileStream]::new($modOrderPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        try{
            $modIsolation.created=$true;$modIsolation.cleanup_required=$true;$modIsolation.cleanup_status='owned_pending_cleanup'
            $ownedOrder.Flush($true)
            $modIsolation.file_identity=[MineCome.Diagnostics.FileIdentity]::Read($ownedOrder.SafeFileHandle.DangerousGetHandle())
        }finally{$ownedOrder.Dispose()}
        $createdOrder=Get-Item -LiteralPath $modOrderPath -Force
        if($createdOrder.Length-ne 0){throw 'New diagnostic mod_order.txt unexpectedly contains data.'}
        $modIsolation.creation_time_utc=$createdOrder.CreationTimeUtc.ToString('o')
        $modIsolation.last_write_time_utc=$createdOrder.LastWriteTimeUtc.ToString('o')
        Save-NewJson (Join-Path $directory 'mod-isolation-created.json') ([ordered]@{schema=1;run=$run;created_utc=[DateTime]::UtcNow.ToString('o');mechanism='official_empty_mod_order';ownership=$modIsolation})
        Write-Output "KCD_TOOLS_DIAGNOSTIC_MOD_EXCLUSION_REQUESTED path=$modOrderPath empty=true startup_mod_exclusion_verified=false"
    }
    Write-Output "Starting exact official tools1.5.5 on fresh trosecko; evidence: $directory"
    Write-Output 'This diagnostic does not load retail saves or send gameplay commands.'
    $gameProcess=Start-Process -FilePath $gameExe -WorkingDirectory $GameRoot -ArgumentList @('-devmode','+map','trosecko') -WindowStyle Normal -PassThru
    # Cache the native handle in this Process object before it can disappear;
    # Process.Dispose below closes our handle without terminating a surviving game.
    $null=$gameProcess.Handle;$processHandleCaptured=$true
    $timer.Start();$status='monitoring'
    try{$startUtc=$gameProcess.StartTime.ToUniversalTime();$startFiletime=$startUtc.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)}catch{}
    while($timer.ElapsedMilliseconds-lt 120000){
        $gameProcess.Refresh()
        if($gameProcess.HasExited){$status='exited';break}
        $now=[DateTime]::UtcNow.ToString('o');$privateBytes=$null;$memory=$null;$sampleError=$null
        try{
            $privateBytes=$gameProcess.PrivateMemorySize64;$memory=[MineCome.Diagnostics.Memory]::Read()
            $maxPrivateBytes=[Math]::Max($maxPrivateBytes,$privateBytes)
            if($null-eq$minCommitAvailable -or $memory[2]-lt$minCommitAvailable){$minCommitAvailable=$memory[2]}
        }catch{$memoryErrors++;$sampleError=$_.Exception.Message}
        $sample=[ordered]@{schema=1;seq=$sampleCount+1;utc=$now;elapsed_ms=$timer.ElapsedMilliseconds;pid=$gameProcess.Id;private_bytes=$privateBytes;commit_used_bytes=$(if($memory){$memory[0]}else{$null});commit_limit_bytes=$(if($memory){$memory[1]}else{$null});commit_available_bytes=$(if($memory){$memory[2]}else{$null});physical_available_bytes=$(if($memory){$memory[3]}else{$null});error=$sampleError}
        $line=$utf8.GetBytes(($sample|ConvertTo-Json -Compress)+"`n")
        if($line.Length-gt 4096 -or $samples.Length+$line.Length-gt 1MB -or $sampleCount-ge 121){throw 'Diagnostic memory record budget exceeded.'}
        $samples.Write($line,0,$line.Length);$samples.Flush();$sampleCount++
        if(($sampleCount-1)%5-eq 0){
            try{
                $rows=@();$moduleTruncated=$false
                foreach($module in $gameProcess.Modules){
                    if($rows.Count-ge 512 -or $module.FileName.Length-gt 4096){$moduleTruncated=$true;break}
                    $path=[IO.Path]::GetFullPath($module.FileName)
                    if($path.Equals((Join-Path $gameBin 'dxgi.dll'),[StringComparison]::OrdinalIgnoreCase) -or $module.ModuleName-imatch '^ReShade(32|64)?\.dll$'){$proxyObserved=$true}
                    if($module.ModuleName-imatch '^MineComeHudCompositor\.(addon64|dll)$'){$addonObserved=$true}
                    if($module.ModuleName-ieq'CryRenderD3D12.dll'){$d3d12Observed=$true}
                    $rows+=[ordered]@{name=$module.ModuleName;path=$path}
                }
                $snapshot=[ordered]@{utc=$now;elapsed_ms=$timer.ElapsedMilliseconds;truncated=$moduleTruncated;modules=$rows}
                $snapshotSize=$utf8.GetByteCount(($snapshot|ConvertTo-Json -Depth 5 -Compress))
                if($moduleBudget+$snapshotSize-gt 900KB){throw 'Module snapshot budget reached.'}
                $moduleSnapshots.Add($snapshot);$moduleBudget+=$snapshotSize
                if(-not $moduleTruncated){$moduleEnumerationSucceeded=$true}
            }catch{$moduleErrors++}
        }
        $remaining=120000-$timer.ElapsedMilliseconds
        if($remaining-gt 0){Start-Sleep -Milliseconds ([int][Math]::Min(1000,$remaining))}
    }
    $gameProcess.Refresh()
    if($gameProcess.HasExited){
        $status='exited';$null=$gameProcess.WaitForExit(0)
        $exitSigned=[int]$gameProcess.ExitCode
        $exitUnsigned=[BitConverter]::ToUInt32([BitConverter]::GetBytes($exitSigned),0)
        $exitHex='0x{0:X8}'-f$exitUnsigned
    }else{$status='monitor_complete_process_alive'}
}catch{$failure=$_.Exception.Message;$status='diagnostic_error'}
finally{
    $timer.Stop();if($samples){$samples.Dispose()}
    $processAlive=$null;$gamePid=$null
    if($gameProcess){$gamePid=$gameProcess.Id;try{$gameProcess.Refresh();$processAlive=-not$gameProcess.HasExited}catch{}}
    if($modIsolation.created){
        try{
            $allGamesClosed=Test-AllKcdProcessesExited
            $ownedGameExited=($null-ne$gameProcess-and$processAlive-eq$false)
            $noGameLaunched=($null-eq$gameProcess-and$allGamesClosed)
            if((-not$ownedGameExited-and-not$noGameLaunched)-or-not$allGamesClosed){
                $modIsolation.cleanup_status='game_alive_or_state_unknown';$modIsolation.cleanup_required=$true
            }else{
                $null=Assert-UnlinkedPath $modsDirectory;$null=Assert-UnlinkedPath $modOrderPath
                if(-not(Test-Path -LiteralPath $modOrderPath -PathType Leaf)){throw 'Owned mod_order.txt is missing or is not a file; no cleanup action taken.'}
                $ownedOrder=[IO.FileStream]::new($modOrderPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
                try{
                    $identity=[MineCome.Diagnostics.FileIdentity]::Read($ownedOrder.SafeFileHandle.DangerousGetHandle())
                    if($null-eq$modIsolation.file_identity-or$identity-cne$modIsolation.file_identity-or$ownedOrder.Length-ne 0){throw 'Owned mod_order.txt identity or empty content changed; preserved without deletion.'}
                    $currentOrder=Get-Item -LiteralPath $modOrderPath -Force
                    if($currentOrder.CreationTimeUtc.ToString('o')-cne$modIsolation.creation_time_utc-or$currentOrder.LastWriteTimeUtc.ToString('o')-cne$modIsolation.last_write_time_utc){throw 'Owned mod_order.txt timestamps changed; preserved without deletion.'}
                }finally{$ownedOrder.Dispose()}
                $null=Assert-UnlinkedPath $modOrderPath
                [IO.File]::Delete($modOrderPath)
                $modIsolation.cleanup_status='removed_unchanged_owned_file';$modIsolation.cleanup_required=$false
            }
        }catch{$modIsolation.cleanup_status='preserved_cleanup_error';$modIsolation.cleanup_required=$true;$modIsolation.cleanup_error=$_.Exception.Message}
        Save-NewJson (Join-Path $directory 'mod-isolation-result.json') ([ordered]@{schema=1;run=$run;completed_utc=[DateTime]::UtcNow.ToString('o');ownership=$modIsolation})
    }
    foreach($path in $logPaths){
        try{
            $captured=Read-LogTail $path
            if($null-ne$captured.Bytes){[IO.File]::WriteAllBytes((Join-Path $directory ([IO.Path]::GetFileName($path))),$captured.Bytes)}
            $afterLogs+=$captured.Metadata
        }catch{$afterLogs+=[ordered]@{path=$path;error=$_.Exception.Message}}
    }
    # Compressed snapshots total <=900KiB; allow bounded4MiB for readable JSON indentation.
    Save-NewJson (Join-Path $directory 'modules.json') ([ordered]@{schema=1;snapshot_count=$moduleSnapshots.Count;module_enumeration_succeeded=$moduleEnumerationSucceeded;enumeration_errors=$moduleErrors;reshade_observed=$proxyObserved;own_addon_observed=$addonObserved;d3d12_observed=$d3d12Observed;snapshots=@($moduleSnapshots.ToArray())}) 4MB
    Save-NewJson (Join-Path $directory 'result.json') ([ordered]@{
        schema=1;run=$run;status=$status;failure=$failure;pid=$gamePid;started_utc=$startUtc;start_filetime=$startFiletime;elapsed_ms=$timer.ElapsedMilliseconds
        exit_code_signed=$exitSigned;exit_code_unsigned=$exitUnsigned;exit_code_hex=$exitHex;process_handle_captured=$processHandleCaptured;process_left_running=$processAlive;process_killed=$false
        memory_samples=$sampleCount;memory_errors=$memoryErrors;max_private_bytes=$maxPrivateBytes;min_system_commit_available_bytes=$minCommitAvailable
        module_enumeration_succeeded=$moduleEnumerationSucceeded;reshade_observed=$proxyObserved;own_addon_observed=$addonObserved;d3d12_observed=$d3d12Observed
        reshade_absence_verified_in_sampled_snapshots=($moduleEnumerationSucceeded-and-not$proxyObserved-and-not$addonObserved);continuous_module_absence_verified=$false;live_world_verified=$false
        log_copies=$afterLogs;evidence_directory=$directory
        mods_isolation=$modIsolation;cleanup_required=[bool]$modIsolation.cleanup_required;startup_mod_exclusion_verified=$false
    })
    if($gameProcess){$gameProcess.Dispose()} # Closes this diagnostic handle only; does not terminate the game.
}
if($status-ceq'exited'){
    Write-Output "KCD_TOOLS_DIAGNOSTIC_EXIT pid=$gamePid code=$exitHex signed=$exitSigned world_verified=false"
}elseif($status-ceq'monitor_complete_process_alive'){
    Write-Output "KCD_TOOLS_DIAGNOSTIC_MONITOR_COMPLETE pid=$gamePid game_left_running=true world_verified=false"
}else{Write-Output "KCD_TOOLS_DIAGNOSTIC_ERROR reason=$failure game_killed=false"}
Write-Output "KCD_TOOLS_DIAGNOSTIC_EVIDENCE $directory"
if($modIsolation.cleanup_required){Write-Output "KCD_TOOLS_DIAGNOSTIC_CLEANUP_REQUIRED path=$modOrderPath status=$($modIsolation.cleanup_status) close_game_before_cleanup=true"}
