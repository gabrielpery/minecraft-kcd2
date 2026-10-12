#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared gate and bounded log/HTTP helpers for explicitly invoked original probes.
if(-not ('MineCome.Probes.TcpOwner' -as [type])) {
    # Public Windows IP Helper ABI, not a game offset/hook. Enumerating only
    # IPv4 listeners keeps per-pose ownership checks within the frame lease.
    # https://learn.microsoft.com/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable
    # https://learn.microsoft.com/windows/win32/api/tcpmib/ns-tcpmib-mib_tcprow_owner_pid
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MineCome.Probes {
 public static class TcpOwner {
  [DllImport("iphlpapi.dll", SetLastError=false)]
  static extern uint GetExtendedTcpTable(IntPtr table,ref int size,bool order,int family,int tableClass,uint reserved);
  public static bool OwnsLoopback(int port,int expectedPid) {
   int size=0; uint result=GetExtendedTcpTable(IntPtr.Zero,ref size,false,2,3,0);
   if(result!=122 || size<4 || size>1048576) throw new InvalidOperationException("IPv4 listener table sizing failed");
   for(int attempt=0;attempt<3;attempt++) {
    int capacity=size;IntPtr buffer=Marshal.AllocHGlobal(capacity);
    try {
     result=GetExtendedTcpTable(buffer,ref size,false,2,3,0);
     if(result==122) {if(size<4 || size>1048576) throw new InvalidOperationException("Listener table bound exceeded");continue;}
     if(result!=0 || size<4 || size>capacity) throw new InvalidOperationException("IPv4 listener table read failed");
     int count=Marshal.ReadInt32(buffer);if(count<0 || count>(size-4)/24) throw new InvalidOperationException("Malformed listener table");
     int matches=0;bool owned=false;
     for(int i=0;i<count;i++) {
      IntPtr row=IntPtr.Add(buffer,4+i*24);uint localPort=unchecked((uint)Marshal.ReadInt32(row,8));
      int decoded=(int)(((localPort&255)<<8)|((localPort>>8)&255));if(decoded!=port)continue;
      matches++;
      owned=Marshal.ReadInt32(row,0)==2 && unchecked((uint)Marshal.ReadInt32(row,4))==0x0100007fU && Marshal.ReadInt32(row,20)==expectedPid;
     }
     return matches==1 && owned;
    } finally {Marshal.FreeHGlobal(buffer);}
   }
   throw new InvalidOperationException("Listener table kept changing");
  }
 }
}
'@
}
function Get-MineComeProbeContext {
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $inventory=Get-Content -LiteralPath (Join-Path $root 'runtime/environment.json') -Raw | ConvertFrom-Json
    $tools=@($inventory.steam.relevant_apps | Where-Object { $_.role -eq 'official_tools' -and $_.installed })
    if($tools.Count -ne 1 -or $tools[0].distribution -ne 'Steam' -or $tools[0].app_id -ne '2429020') { throw 'One discovered official Steam tools installation is required.' }
    $gameRoot=(Resolve-Path -LiteralPath $tools[0].install_path).Path
    $exe=(Resolve-Path -LiteralPath (Join-Path $gameRoot 'Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe')).Path
    $pinned=@($tools[0].binaries | Where-Object { $_.path -eq $exe })
    $version=(Get-Item -LiteralPath $exe).VersionInfo
    $hash=(Get-FileHash -LiteralPath $exe).Hash
    if($pinned.Count -ne 1 -or $pinned[0].sha256 -ne $hash -or $version.FileVersion -ne '1.5.5.0' -or $version.ProductVersion -ne '1.5.5.0' -or
        $version.FileMajorPart -ne 1 -or $version.FileMinorPart -ne 0 -or $version.FileBuildPart -ne 0 -or $version.FilePrivatePart -ne 0) { throw 'The exact pinned fixed1.0.0.0/display1.5.5.0 tools executable is required.' }
    $games=@(Get-Process KingdomCome -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
    if($games.Count -ne 1) { throw 'An already-running official tools test world is required; no game is launched by this probe.' }
    $context=[pscustomobject]@{ProjectRoot=$root;GameRoot=$gameRoot;GamePath=$exe;GameHash=$hash;GamePid=$games[0].Id;GameStartedUtc=$games[0].StartTime.ToUniversalTime();GameLog=(Join-Path $gameRoot 'kcd.log')}
    Assert-MineComeProbeContext $context
    if(-not (Test-Path -LiteralPath $context.GameLog)) { throw 'Current tools game log is missing.' }
    $context
}
function Assert-MineComeProbeContext($Context) {
    $process=Get-Process -Id $Context.GamePid -ErrorAction Stop
    if($process.Path -ne $Context.GamePath -or $process.StartTime.ToUniversalTime() -ne $Context.GameStartedUtc) { throw 'Captured tools process identity changed.' }
    if(-not [MineCome.Probes.TcpOwner]::OwnsLoopback(1403,$Context.GamePid)) { throw 'The captured tools process does not own the numeric loopback endpoint; no request sent.' }
}
function Invoke-MineComeProbeConsole($Context,[string]$Command) {
    Assert-MineComeProbeContext $Context
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($Command)) | Out-Null
}
function Read-MineComeProbeLog($Context,[long]$Offset) {
    $stream=[IO.FileStream]::new($Context.GameLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $length=$stream.Length
        if($length -lt $Offset -or $length-$Offset -gt 8388608) { throw 'Log changed or exceeded the bounded8MiB probe extent.' }
        $stream.Position=$Offset;$bytes=[byte[]]::new([int]($length-$Offset));$read=0
        while($read -lt $bytes.Length) {
            $received=$stream.Read($bytes,$read,$bytes.Length-$read)
            if($received -eq 0) { throw 'The game log was truncated during capture.' }
            $read+=$received
        }
        [Text.Encoding]::UTF8.GetString($bytes)
    } finally { $stream.Dispose() }
}
function New-MineComeProbeRun($Context,[string]$Prefix,[string]$Module,[string]$EntryPoint) {
    if($Prefix -notmatch '^[a-z-]{1,40}$' -or $EntryPoint -notmatch '^[A-Za-z][A-Za-z0-9_]{1,60}$') { throw 'Invalid internal probe identifier.' }
    $run=[Guid]::NewGuid().ToString('N')
    $directory=Join-Path $Context.ProjectRoot ('runtime/evidence/'+$Prefix+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run)
    New-Item -ItemType Directory -Path $directory | Out-Null
    $source=(Resolve-Path -LiteralPath $Module).Path;$sourceHash=(Get-FileHash -LiteralPath $source).Hash
    $snapshot=Join-Path $directory ([IO.Path]::GetFileName($source))
    Copy-Item -LiteralPath $source -Destination $snapshot
    $snapshotHash=(Get-FileHash -LiteralPath $snapshot).Hash
    if($sourceHash -ne $snapshotHash) { throw 'Probe source changed while copying; no module load attempted.' }
    (Get-Item -LiteralPath $snapshot).IsReadOnly=$true
    $offset=(Get-Item -LiteralPath $Context.GameLog).Length
    $path=$snapshot.Replace('\','/').Replace("'","\'")
    Invoke-MineComeProbeConsole $Context ("#local old=MineCome and MineCome.$EntryPoint; Script.LoadScript('$path'); local ok=MineCome and type(MineCome.$EntryPoint)=='function' and MineCome.$EntryPoint~=old; System.LogAlways('[MineComeProbeContract] $run '..tostring(not not ok))")
    Invoke-MineComeProbeConsole $Context ("#System.LogAlways('[MineComeProbeFlush] $run')")
    $deadline=[DateTime]::UtcNow.AddSeconds(4);$verified=$false
    do {
        $fresh=Read-MineComeProbeLog $Context $offset
        if($fresh -match ('\[MineComeProbeContract\] '+$run+' false')) { throw 'Unique source snapshot failed function-reference verification.' }
        $verified=$fresh -match ('\[MineComeProbeContract\] '+$run+' true\r?\n')
        if($verified){break};Start-Sleep -Milliseconds 50
    } while([DateTime]::UtcNow -lt $deadline)
    if(-not $verified) { throw 'No fresh engine source-evaluation contract receipt.' }
    [pscustomobject]@{Run=$run;Directory=$directory;Source=$source;SourceHash=$sourceHash;Snapshot=$snapshot;SnapshotHash=$snapshotHash;Offset=$offset;EntryPoint=$EntryPoint;FunctionReloadVerified=$verified}
}
function Get-MineComeProbeReceipts([string]$Log,[string]$Tag,[string]$Run) {
    if($Tag -notmatch '^[A-Za-z][A-Za-z0-9]{1,60}$' -or $Run -notmatch '^[0-9a-f]{32}$') { throw 'Invalid internal receipt identifier.' }
    foreach($match in [regex]::Matches($Log,('\['+$Tag+'\] (\{[^\r\n]*\})\r?\n'))) {
        $receipt=$match.Groups[1].Value | ConvertFrom-Json
        if($receipt.schema -eq 1 -and $receipt.run -eq $Run) { $receipt }
    }
}
. (Join-Path $PSScriptRoot '../kcd2/tools-http.ps1')
