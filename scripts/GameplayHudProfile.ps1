#Requires -Version 5.1
# Exact tools-only gameplay staging/installation helpers. No game or file changes.
$script:mcGameplayRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:mcGameplayFiles=@('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt','minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')
function Resolve-MineComeGameplayPath([string]$Path,[switch]$InRuntime){
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor){if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked gameplay path refused: $cursor"};$cursor=[IO.Path]::GetDirectoryName($cursor)}
    if($InRuntime -and -not $full.StartsWith((Join-Path $script:mcGameplayRoot 'runtime')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Gameplay staging/receipts must stay in workspace runtime.'}
    return $full
}
function Get-MineComeGameplayHash([string]$Path){$null=Resolve-MineComeGameplayPath $Path;return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Read-MineComeGameplayJson([string]$Path){$null=Resolve-MineComeGameplayPath $Path;if((Get-Item -LiteralPath $Path).Length -gt 1MB){throw "Oversized gameplay metadata: $Path"};return (Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json)}
function Write-MineComeGameplayJson([string]$Path,$Value){
    $null=Resolve-MineComeGameplayPath $Path -InRuntime
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 12)+"`n")
    $file=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
}
function Assert-MineComeGameplayRecords($Records){
    if(@($Records).Count -ne 6 -or ((@($Records|ForEach-Object{$_.path})|Sort-Object)-join '|') -cne (($script:mcGameplayFiles|Sort-Object)-join '|')){throw 'Expected exactly the six known HUD file paths.'}
    foreach($r in $Records){if($r.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $r.bytes -lt 1 -or $r.bytes -gt 64MB){throw 'Invalid gameplay file hash/size.'}}
}
function Assert-MineComeGameplayFile([string]$Path,$Record){
    $null=Resolve-MineComeGameplayPath $Path
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -ne $Record.bytes -or (Get-MineComeGameplayHash $Path) -cne $Record.sha256){throw "Exact owned gameplay file differs: $Path"}
}
function Get-MineComeGameplayProfile {
    $profilePath=Join-Path $script:mcGameplayRoot 'config/hud-gameplay-profile-v5.json';$p=Read-MineComeGameplayJson $profilePath
    if($p.schema -ne 1 -or $p.kind -cne 'minecome_gameplay_hud_profile_v5' -or $p.tools_exe_sha256 -cne 'a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a' -or
       $p.upstream_commit -cne '18deaa52de0c425a78b329e9cb3c497281cd00ec' -or $p.arm_config_relative_path -cne 'minecome-hud/addons/MineComeHudGameplay.ini'){throw 'Unknown gameplay profile.'}
    Assert-MineComeGameplayRecords $p.files
    foreach($name in @('build_receipt_sha256','previous_manifest_sha256','previous_receipt_sha256')){if($p.$name -cnotmatch '^[0-9a-f]{64}$'){throw "Unfrozen gameplay pin: $name"}}
    foreach($name in @('build_receipt','addon_source','previous_bundle')){if([IO.Path]::IsPathRooted($p.$name) -or $p.$name -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Profile path must be relative to this workspace.'}}
    return $p
}
function Get-MineComeGameplayToolsBin($Profile){
    $inventory=Read-MineComeGameplayJson (Join-Path $script:mcGameplayRoot 'runtime/environment.json')
    $tools=@($inventory.steam.relevant_apps|Where-Object{$_.role -eq 'official_tools' -and $_.installed -and $_.app_id -eq '2429020' -and $_.distribution -eq 'Steam'})
    if($tools.Count -ne 1){throw 'Expected one discovered official Steam tools installation.'}
    $bin=Resolve-MineComeGameplayPath (Join-Path $tools[0].install_path 'Bin/Win64ReleaseSteamLTO_DLL');$exe=Join-Path $bin 'KingdomCome.exe';$v=(Get-Item -LiteralPath $exe).VersionInfo
    if((Get-MineComeGameplayHash $exe) -cne $Profile.tools_exe_sha256 -or $v.FileVersion -ne '1.5.5.0' -or $v.ProductVersion -ne '1.5.5.0'){throw 'Unsupported tools executable; no changes performed.'}
    return $bin
}
function Assert-MineComeGameplayNoArms([string]$Bin,[string]$AllowedTemporaryPath,$AllowedTemporaryRecord){
    $addons=Resolve-MineComeGameplayPath (Join-Path $Bin 'minecome-hud/addons')
    foreach($f in @(Get-ChildItem -LiteralPath $addons -File -ErrorAction Stop)){
        $null=Resolve-MineComeGameplayPath $f.FullName
        if($f.Name -ceq 'MineComeHudCompositor.addon64'){continue}
        if($AllowedTemporaryPath -and $f.FullName -ieq $AllowedTemporaryPath){
            if(-not $AllowedTemporaryRecord -or $f.Name -cnotmatch '^MineComeHudCompositor\.addon64\.minecome-gameplay-[a-f0-9]{32}\.tmp$'){throw 'Invalid transaction temporary-file exception.'}
            Assert-MineComeGameplayFile $f.FullName $AllowedTemporaryRecord;continue
        }
        # Old repeat-controller evidence has unique names and is never loaded as an arm.
        if($f.Name -cmatch '^MineComeHudWalkingRepeat(?:\.ini)?\.[a-f0-9]{32}\.(cleanup\.ini|retired\.ini|verification\.json)$'){continue}
        throw "Existing arm or unowned addon-directory file preserved: $($f.FullName)"
    }
}
function Assert-MineComeGameplayBundle([string]$BundleDirectory,$Profile){
    $bundle=Resolve-MineComeGameplayPath $BundleDirectory -InRuntime;$m=Read-MineComeGameplayJson (Join-Path $bundle 'bundle.json')
    if($m.schema -ne 3 -or $m.kind -cne 'minecome_gameplay_hud_bundle_v3' -or $m.stream_protocol -ne 3 -or $m.ui_input_protocol -ne 3 -or $m.gameplay_keyboard_api -ne 5 -or
       $m.tools_only -ne $true -or $m.arm_config_relative_path -cne $Profile.arm_config_relative_path -or $m.profile_sha256 -cne (Get-MineComeGameplayHash (Join-Path $script:mcGameplayRoot 'config/hud-gameplay-profile-v5.json'))){throw 'Gameplay bundle profile differs.'}
    Assert-MineComeGameplayRecords $m.files
    foreach($r in $Profile.files){$record=@($m.files|Where-Object{$_.path -ceq $r.path})[0];if($record.sha256 -cne $r.sha256 -or $record.bytes -ne $r.bytes){throw "Gameplay bundle pin differs: $($r.path)"};Assert-MineComeGameplayFile (Join-Path $bundle $r.path) $r}
    if(Test-Path -LiteralPath (Join-Path $bundle $Profile.arm_config_relative_path)){throw 'Prepared gameplay bundle must remain unarmed.'}
    return $m
}
function Get-MineComeGameplayInstallation {
    param([string]$BundleDirectory=(Join-Path $script:mcGameplayRoot 'runtime/hud-compositor-gameplay'),[switch]$RequireUnarmed)
    $p=Get-MineComeGameplayProfile;$bundle=Resolve-MineComeGameplayPath $BundleDirectory -InRuntime;$m=Assert-MineComeGameplayBundle $bundle $p;$bin=Get-MineComeGameplayToolsBin $p
    $receipt=Read-MineComeGameplayJson (Join-Path $bundle 'installed.json')
    if($receipt.schema -ne 1 -or $receipt.kind -cne 'minecome_gameplay_hud_install_v1' -or $receipt.status -cne 'installed_unarmed' -or
       $receipt.profile_sha256 -cne $m.profile_sha256 -or $receipt.target_exe -ine (Join-Path $bin 'KingdomCome.exe') -or $receipt.bundle -ine $bundle -or
       (Test-Path -LiteralPath (Join-Path $bundle 'restored.json'))){throw 'Gameplay installation receipt does not match this deployment.'}
    Assert-MineComeGameplayRecords $receipt.files
    foreach($r in $p.files){$record=@($receipt.files|Where-Object{$_.path -ceq $r.path})[0];if($record.sha256 -cne $r.sha256 -or $record.bytes -ne $r.bytes){throw 'Installed receipt files differ from the gameplay profile.'};Assert-MineComeGameplayFile (Join-Path $bin $r.path) $r}
    if(Test-Path -LiteralPath (Join-Path $bin 'dxgi.dll.minecome-disabled')){throw 'Conflicting disabled proxy preserved.'}
    if($RequireUnarmed){Assert-MineComeGameplayNoArms $bin}
    return [pscustomobject]@{Profile=$p;Manifest=$m;InstalledReceipt=$receipt;BundleDirectory=$bundle;ToolsExe=(Join-Path $bin 'KingdomCome.exe');ToolsBin=$bin}
}
