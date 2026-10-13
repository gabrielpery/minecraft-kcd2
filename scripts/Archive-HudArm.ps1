#Requires -Version 5.1
# Archive only a receipt-owned, expired arm after every KCD process has closed.
# Never starts/stops a process, deletes game data or overwrites existing evidence.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReceiptPath,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$evidenceRoot=Join-Path $root 'runtime/evidence'
$exeHash='a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a'
function Assert-Unlinked([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked archive path refused: $cursor"}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-Bounded([string]$Path){
    $null=Assert-Unlinked $Path
    $item=Get-Item -LiteralPath $Path
    if($item.PSIsContainer -or $item.Length -lt 2 -or $item.Length -gt 64KB){throw 'Invalid bounded arm metadata.'}
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}
function Game-Open{return @(Get-CimInstance Win32_Process -Filter "Name='KingdomCome.exe'" -ErrorAction Stop).Count -ne 0}
$ReceiptPath=Assert-Unlinked $ReceiptPath
if(-not $ReceiptPath.StartsWith($evidenceRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Ownership receipt must remain in workspace evidence.'}
$receipt=Read-Bounded $ReceiptPath
if($receipt.schema -ne 1 -or $receipt.kind -cnotin @('minecome_hud_preview_arm_v1','minecome_hud_stream_arm_v1') -or $receipt.run -cnotmatch '^[0-9a-f]{32}$' -or $receipt.arm_sha256 -cnotmatch '^[0-9a-f]{64}$' -or $receipt.expires_utc_ms -ge [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){throw 'Expected owned expired HUD arm receipt.'}
$inventory=Read-Bounded (Join-Path $root 'runtime/environment.json')
$tools=@($inventory.steam.relevant_apps | Where-Object {$_.role -ceq 'official_tools' -and $_.installed -eq $true -and $_.distribution -ceq 'Steam' -and $_.app_id -eq '2429020'})
if($tools.Count -ne 1){throw 'One discovered official tools installation required.'}
$bin=Assert-Unlinked (Join-Path $tools[0].install_path 'Bin/Win64ReleaseSteamLTO_DLL')
$gameExe=Assert-Unlinked (Join-Path $bin 'KingdomCome.exe')
if((Get-FileHash -LiteralPath $gameExe).Hash -ine $exeHash){throw 'Exact tools executable changed.'}
$arm=Assert-Unlinked $receipt.arm_path
$allowed=@('MineComeHud.ini','MineComeHudStream.ini','MineComeHudInput.ini','MineComeHudMouse.ini','MineComeHudWorld.ini') | ForEach-Object {[IO.Path]::GetFullPath((Join-Path $bin ('minecome-hud/addons/'+$_)))}
if(-not @($allowed | Where-Object {$_.Equals($arm,[StringComparison]::OrdinalIgnoreCase)}).Count){throw 'Receipt arm path is outside the exact tools addon directory.'}
$directory=[IO.Path]::GetDirectoryName($ReceiptPath)
$archive=Assert-Unlinked (Join-Path $directory ([IO.Path]::GetFileNameWithoutExtension($arm)+'.expired.ini'))
if(-not $archive.StartsWith($directory+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Archive target escaped its evidence directory.'}
function Assert-Owned([string]$Path){
    $null=Assert-Unlinked $Path;$item=Get-Item -LiteralPath $Path
    if($item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt 64KB -or (Get-FileHash -LiteralPath $Path).Hash -ine $receipt.arm_sha256){throw 'Owned arm changed; preserving it.'}
}
$gameOpen=Game-Open
if(-not(Test-Path -LiteralPath $arm)){
    Assert-Owned $archive
    Write-Output 'HUD_ARM_ALREADY_ARCHIVED no_changes=true'
    return
}
Assert-Owned $arm
if(Test-Path -LiteralPath $archive){throw 'Archive destination exists; preserving both paths.'}
if(Test-Path -LiteralPath (Join-Path $directory 'arm-archive.json')){throw 'Archive receipt exists; preserving all paths.'}
if($PreflightOnly){Write-Output "HUD_ARM_ARCHIVE_PREFLIGHT_PASS game_open=$gameOpen no_changes=true";return}
if($gameOpen -or (Game-Open)){throw 'Close KCD normally before archiving the expired arm.'}
Assert-Owned $arm
if((Get-FileHash -LiteralPath $gameExe).Hash -ine $exeHash){throw 'Tools executable changed before archive.'}
[IO.File]::Move($arm,$archive)
Assert-Owned $archive
$result=[ordered]@{schema=1;kind='minecome_expired_arm_archive_v1';utc=[DateTime]::UtcNow.ToString('o');run=$receipt.run;ownership_receipt=$ReceiptPath;old_path=$arm;archive_path=$archive;sha256=$receipt.arm_sha256;game_closed=$true;game_launched=$false}
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($result | ConvertTo-Json -Depth 4)+[Environment]::NewLine)
$file=[IO.FileStream]::new((Join-Path $directory 'arm-archive.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
Write-Output "HUD_ARM_ARCHIVED path=$archive"
