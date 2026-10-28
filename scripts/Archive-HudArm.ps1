#Requires -Version 5.1
# Archive a receipt-owned expired arm; live cleanup requires explicit prior-process proof.
# Never starts/stops a process, deletes game data or overwrites existing evidence.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReceiptPath,[switch]$PreflightOnly,[switch]$ExpiredPriorProcess)
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
function Assert-ExpiredPriorProcessAuthority($Receipt,[string]$ArmText,[object[]]$Games,[object[]]$OriginalProcesses,[string]$GamePath,[long]$Now,$PinnedCurrent=$null){
    function Positive-Decimal($Value,[long]$Maximum=[long]::MaxValue){
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [string]) -or [string]$Value -cnotmatch '^[1-9][0-9]{0,18}$'){throw 'Prior-process identity must be a positive decimal integer.'}
        $number=[long]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture)
        if($number -gt $Maximum){throw 'Prior-process identity exceeds its bound.'}
        return $number
    }
    if($Receipt.schema -ne 1 -or $Receipt.kind -cne 'minecome_hud_stream_arm_v1' -or $Receipt.run -cnotmatch '^[0-9a-f]{32}$'){throw 'Prior-process cleanup requires an owned stream arm.'}
    $target=Positive-Decimal $Receipt.game_pid ([uint32]::MaxValue);$targetStart=Positive-Decimal $Receipt.game_start_filetime
    $producer=Positive-Decimal $Receipt.producer_pid ([uint32]::MaxValue);$producerStart=Positive-Decimal $Receipt.producer_start_filetime
    $expiry=Positive-Decimal $Receipt.expires_utc_ms
    if($Now -le 0 -or $expiry -ge $Now){throw 'Prior-process arm must already be expired.'}
    $lines=@($ArmText -split '\r?\n' | Where-Object {$_ -cne ''})
    if($lines.Count -ne 8 -or $lines[0] -cne '[HudStream]'){throw 'Expected exact bounded stream arm text.'}
    $fields=@{}
    foreach($line in $lines[1..7]){
        if($line -cnotmatch '^(Schema|Run|TargetPid|TargetStart|ProducerPid|ProducerStart|ExpiresUtcMs)=([^\r\n]+)$' -or $fields.ContainsKey($Matches[1])){throw 'Stream arm has unknown or repeated identity fields.'}
        $fields[$Matches[1]]=$Matches[2]
    }
    $expected=@{Schema='1';Run=$Receipt.run;TargetPid=[string]$target;TargetStart=[string]$targetStart;ProducerPid=[string]$producer;ProducerStart=[string]$producerStart;ExpiresUtcMs=[string]$expiry}
    foreach($name in $expected.Keys){if($fields[$name] -cne $expected[$name]){throw 'Hashed stream arm identity differs from its ownership receipt.'}}
    # Refuse even a recycled original PID: no inference about an old producer or
    # target is necessary while either numeric process identifier is occupied.
    foreach($process in $OriginalProcesses){if($process.Id -eq $target -or $process.Id -eq $producer){throw 'Original target or producer PID is still present.'}}
    if($Games.Count -ne 1){throw 'Exactly one fresh official-tools process is required.'}
    $current=$Games[0];$currentPid=Positive-Decimal $current.Id ([uint32]::MaxValue);$currentStart=Positive-Decimal $current.StartFileTime
    if($current.Path -isnot [string] -or -not $current.Path.Equals($GamePath,[StringComparison]::OrdinalIgnoreCase) -or $currentPid -eq $target -or $currentPid -eq $producer -or $currentStart -le $targetStart){throw 'Current game is not a different fresh exact-tools process.'}
    $startedUtc=[DateTimeOffset]::new([DateTime]::FromFileTimeUtc($currentStart)).ToUnixTimeMilliseconds()
    if($startedUtc -le $expiry -or $startedUtc -gt $Now){throw 'Current game must have started after the old arm expired.'}
    if($null -ne $PinnedCurrent -and ($PinnedCurrent.current_pid -ne $currentPid -or $PinnedCurrent.current_start_filetime -cne [string]$currentStart -or $PinnedCurrent.current_path -ine $current.Path)){throw 'Pinned current game identity changed before archive.'}
    [pscustomobject]@{current_pid=$currentPid;current_start_filetime=[string]$currentStart;current_path=$current.Path;old_target_pid=$target;old_target_start_filetime=[string]$targetStart;old_producer_pid=$producer;old_producer_start_filetime=[string]$producerStart;expired_utc_ms=$expiry}
}
function Get-ExpiredPriorProcessAuthority($PinnedCurrent=$null){
    $games=@(Get-Process KingdomCome -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{Id=$_.Id;Path=$_.Path;StartFileTime=$_.StartTime.ToUniversalTime().ToFileTimeUtc()}
    })
    $originals=@(Get-Process -Id ([int]$receipt.game_pid),([int]$receipt.producer_pid) -ErrorAction SilentlyContinue | Select-Object Id)
    Assert-ExpiredPriorProcessAuthority $receipt ([IO.File]::ReadAllText($arm)) $games $originals $gameExe ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) $PinnedCurrent
}
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
$allowed=@('MineComeHud.ini','MineComeHudStream.ini','MineComeHudInput.ini','MineComeHudMouse.ini','MineComeHudWorld.ini','MineComeHudSelective.ini','MineComeHudMovement.ini','MineComeHudWalkingAimed.ini','MineComeHudWalkingRepeat.ini') | ForEach-Object {[IO.Path]::GetFullPath((Join-Path $bin ('minecome-hud/addons/'+$_)))}
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
$priorProcess=$null
if($ExpiredPriorProcess){$priorProcess=Get-ExpiredPriorProcessAuthority}
if(Test-Path -LiteralPath $archive){throw 'Archive destination exists; preserving both paths.'}
if(Test-Path -LiteralPath (Join-Path $directory 'arm-archive.json')){throw 'Archive receipt exists; preserving all paths.'}
if($PreflightOnly){Write-Output "HUD_ARM_ARCHIVE_PREFLIGHT_PASS game_open=$gameOpen no_changes=true";return}
if(-not $ExpiredPriorProcess -and ($gameOpen -or (Game-Open))){throw 'Close KCD normally before archiving the expired arm.'}
Assert-Owned $arm
if((Get-FileHash -LiteralPath $gameExe).Hash -ine $exeHash){throw 'Tools executable changed before archive.'}
if($ExpiredPriorProcess){$null=Get-ExpiredPriorProcessAuthority $priorProcess}
[IO.File]::Move($arm,$archive)
Assert-Owned $archive
$result=[ordered]@{schema=1;kind='minecome_expired_arm_archive_v1';utc=[DateTime]::UtcNow.ToString('o');run=$receipt.run;ownership_receipt=$ReceiptPath;old_path=$arm;archive_path=$archive;sha256=$receipt.arm_sha256;game_closed=(-not [bool]$ExpiredPriorProcess);expired_prior_process=[bool]$ExpiredPriorProcess;prior_process_authority=$priorProcess;game_launched=$false}
$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($result | ConvertTo-Json -Depth 4)+[Environment]::NewLine)
$file=[IO.FileStream]::new((Join-Path $directory 'arm-archive.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
Write-Output "HUD_ARM_ARCHIVED path=$archive"
