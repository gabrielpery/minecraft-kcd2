#Requires -Version 5.1
# Original tools-only update of the owned, disabled MineCome HUD installation.
# Does not start/stop a game. Preflight is read-only, including when the game is open.
[CmdletBinding()]
param([string]$BundleDirectory, [string]$PreviousBundleDirectory, [switch]$PreflightOnly, [switch]$LiveMouse, [switch]$WorldClicks, [switch]$SelectiveMouse, [ValidateSet(1,2,3,4)][int]$SelectiveRevision=1, [switch]$PhysicalMovement, [switch]$WalkingAimed, [switch]$RepeatSession, [switch]$FromWalkingAimedRepeat, [switch]$FromPhysicalMovement)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($FromWalkingAimedRepeat -and -not $PhysicalMovement){throw 'FromWalkingAimedRepeat requires the explicit PhysicalMovement destination profile.'}
if($FromPhysicalMovement -and (-not $WalkingAimed -or -not $RepeatSession -or $FromWalkingAimedRepeat)){throw 'FromPhysicalMovement requires the explicit WalkingAimed RepeatSession destination.'}
if($RepeatSession -and -not $WalkingAimed){throw 'RepeatSession requires the WalkingAimed profile.'}
if($WalkingAimed -and ($PhysicalMovement -or $LiveMouse -or $WorldClicks -or $SelectiveMouse -or $SelectiveRevision -ne 1)){throw 'WalkingAimed is a separate update profile.'}
if($PhysicalMovement -and ($LiveMouse -or $WorldClicks -or $SelectiveMouse -or $SelectiveRevision -ne 1)){throw 'PhysicalMovement is a separate update profile.'}
if($WorldClicks -and -not $LiveMouse){throw 'World clicks update requires explicit LiveMouse mode.'}
if($SelectiveMouse -and (-not $WorldClicks -or -not $LiveMouse)){throw 'Selective mouse update requires explicit LiveMouse and WorldClicks modes.'}
if($SelectiveRevision -ge 2 -and -not $SelectiveMouse){throw 'A selective revision update requires explicit SelectiveMouse mode.'}
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeRoot=Join-Path $projectRoot 'runtime'
if(-not $BundleDirectory){$BundleDirectory=Join-Path $runtimeRoot $(if($SelectiveMouse -and $SelectiveRevision -eq 4){'hud-compositor-selective-r4'}elseif($SelectiveMouse -and $SelectiveRevision -eq 3){'hud-compositor-selective-r3'}elseif($SelectiveMouse -and $SelectiveRevision -eq 2){'hud-compositor-selective-r2'}elseif($SelectiveMouse){'hud-compositor-selective'}elseif($WorldClicks){'hud-compositor-world'}elseif($LiveMouse){'hud-compositor-mouse'}else{'hud-compositor-resetfix'})}
if(-not $PreviousBundleDirectory){$PreviousBundleDirectory=Join-Path $runtimeRoot $(if($SelectiveMouse -and $SelectiveRevision -eq 4){'hud-compositor-selective-r3'}elseif($SelectiveMouse -and $SelectiveRevision -eq 3){'hud-compositor-selective-r2'}elseif($SelectiveMouse -and $SelectiveRevision -eq 2){'hud-compositor-selective'}elseif($SelectiveMouse){'hud-compositor-world'}elseif($WorldClicks){'hud-compositor-mouse'}else{'hud-compositor'})}
$exeHash='a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a'
$proxyHash='0cee63f9c9f13f3ac909c5b4903f4dbb4b719a7ab3b4f13b0deaf83c814b94f7'
$previousProxyHash=$proxyHash
if($WalkingAimed){
    . (Join-Path $PSScriptRoot 'HudWalkingAimedProfile.ps1')
    $mouseProfile=Get-MineComeWalkingAimedProfile -RepeatSession:$RepeatSession;$proxyHash=$mouseProfile.runtime_sha256
    if(-not $PSBoundParameters.ContainsKey('BundleDirectory')){$BundleDirectory=Join-Path $runtimeRoot $(if($RepeatSession){'hud-compositor-walking-repeat'}else{'hud-compositor-walking-aimed'})}
    if(-not $PSBoundParameters.ContainsKey('PreviousBundleDirectory')){$PreviousBundleDirectory=Join-Path $runtimeRoot $(if($RepeatSession -and -not $FromPhysicalMovement){'hud-compositor-walking-aimed'}else{'hud-compositor-walking'})}
}elseif($PhysicalMovement){
    . (Join-Path $PSScriptRoot 'HudPhysicalMovement.ps1')
    if($FromWalkingAimedRepeat){. (Join-Path $PSScriptRoot 'HudWalkingAimedProfile.ps1')}
    $mouseProfile=Get-MineComePhysicalMovementProfile;$proxyHash=$mouseProfile.runtime_sha256
    if(-not $PSBoundParameters.ContainsKey('BundleDirectory')){$BundleDirectory=Join-Path $runtimeRoot 'hud-compositor-walking'}
    if(-not $PSBoundParameters.ContainsKey('PreviousBundleDirectory')){$PreviousBundleDirectory=Join-Path $runtimeRoot $(if($FromWalkingAimedRepeat){'hud-compositor-walking-repeat'}else{'hud-compositor-selective-r4'})}
}elseif($LiveMouse){. (Join-Path $PSScriptRoot 'HudMouseProfile.ps1');$mouseProfile=Get-MineComeMouseProfile -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse -SelectiveRevision $SelectiveRevision;$proxyHash=$mouseProfile.runtime_sha256}
$supportedAddonHashes=@('a9bb60999fb526df64b3c61975431aed7c0b85728dc21a30db91b41bfccea484',
    '819499b52971d5027745be24e136b4a428975d108870ee0f70c1edfdf60b69cb')
$supportedStreamAddonHashes=@('d7ebc92b59f7971998f1eafb5afe433b5bc44b84a272bcfc9840c49e1d1e6fd8')
$supportedInputAddonHashes=@('d7de884b798c6480efc24981ce409821192a7fcd56f6c2361ff32ec2755eefca',
    '56fb1cca6806a1cca41c9e1875da56ec1895e9781d0251bf6153d880cbd0bb80',
    'ef224499d2c5a331e5f8ee011761e4bced2a3709fb2ba3b6471aa598ea07ab74')
$expected=@('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt',
    'minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')
$utf8=[Text.UTF8Encoding]::new($false,$true)

function Assert-Unlinked([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked update path refused: $cursor"}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Assert-InRuntime([string]$Path){
    $full=Assert-Unlinked $Path
    if(-not $full.StartsWith($runtimeRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Update metadata and backups must remain in this workspace runtime.'}
    return $full
}
function Read-Json([string]$Path){
    $null=Assert-Unlinked $Path
    $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($file.Length-lt 1 -or $file.Length-gt 64KB){throw 'Update metadata exceeded its64KiB bound.'}
        $bytes=[byte[]]::new([int]$file.Length);$offset=0
        while($offset-lt $bytes.Length){$n=$file.Read($bytes,$offset,$bytes.Length-$offset);if($n-eq 0){throw 'Update metadata shrank.'};$offset+=$n}
        if($file.ReadByte()-ne -1){throw 'Update metadata grew.'}
        $text=$utf8.GetString($bytes)
        if($text.Length-gt 0 -and $text[0]-eq[char]0xfeff){$text=$text.Substring(1)}
        return ($text|ConvertFrom-Json)
    }finally{$file.Dispose()}
}
function Write-NewJson([string]$Path,$Value){
    $null=Assert-Unlinked $Path
    $bytes=$utf8.GetBytes(($Value|ConvertTo-Json -Depth 10)+"`n")
    if($bytes.Length-gt 64KB){throw 'Update receipt exceeded its64KiB bound.'}
    $file=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
}
function Assert-Record($Record){
    if($Record.sha256-cnotmatch'^[0-9a-f]{64}$' -or ($Record.bytes-isnot[int] -and $Record.bytes-isnot[long]) -or $Record.bytes-lt 1 -or $Record.bytes-gt 64MB){throw 'Invalid bounded update file record.'}
}
function Get-MineComePhysicalUpdatePreviousProfile($Manifest,$Receipt,[bool]$FromWalkingAimedRepeat){
    # An explicit transition, never inferred from a pathname or a bundle marker.
    # Each branch retains its original exact runtime/addon/shader pins and all
    # six installed file identities. The caller separately checks their bytes
    # in the pinned tools installation before performing any replacement.
    if($FromWalkingAimedRepeat){
        $profile=Get-MineComeWalkingAimedProfile -RepeatSession
        Assert-MineComeWalkingAimedInstalledBundle $Manifest $Receipt $profile
    }else{
        $profile=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 4
        Assert-MineComeMouseInstalledBundle $Manifest $Receipt $profile -WorldClicks -SelectiveMouse -SelectiveRevision 4
    }
    return $profile
}
function Get-MineComeWalkingAimedUpdatePreviousProfile($Manifest,$Receipt,[bool]$RepeatSession,[bool]$FromPhysicalMovement){
    if($FromPhysicalMovement -and -not $RepeatSession){throw 'Direct physical predecessor is explicit only for the repeat-session destination.'}
    if($RepeatSession -and -not $FromPhysicalMovement){
        $profile=Get-MineComeWalkingAimedProfile
        Assert-MineComeWalkingAimedInstalledBundle $Manifest $Receipt $profile
    }else{
        $profile=Get-MineComePhysicalMovementProfile
        Assert-MineComePhysicalMovementBundle $Manifest $profile
    }
    if($Receipt.schema -ne 1 -or $Receipt.kind -cne 'minecome_hud_install_v1' -or @($Receipt.files).Count -ne 6){throw 'Previous walking installation requires its exact six-file receipt.'}
    foreach($relative in @('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt',
        'minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')){
        $staged=@($Manifest.files | Where-Object path -CEQ $relative);$owned=@($Receipt.files | Where-Object path -CEQ $relative)
        if($staged.Count -ne 1 -or $owned.Count -ne 1){throw 'Previous walking bundle requires six exact installed files.'}
        Assert-Record $staged[0];Assert-Record $owned[0]
        if($staged[0].sha256 -cne $owned[0].sha256 -or $staged[0].bytes -ne $owned[0].bytes){throw 'Previous walking bundle differs from its installation receipt.'}
    }
    return $profile
}
function Assert-File([string]$Path,$Record){
    $null=Assert-Unlinked $Path
    $item=Get-Item -LiteralPath $Path -Force
    if($item.PSIsContainer -or $item.Length-ne $Record.bytes -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash-ine $Record.sha256){throw "Owned/staged file differs; preserved: $Path"}
}
function Get-GameOpen{
    $candidates=@();$queryErrors=@()
    try{
        $candidates=@(Get-Process -Name KingdomCome -ErrorAction SilentlyContinue -ErrorVariable queryErrors)
        foreach($errorRecord in $queryErrors){if($errorRecord.FullyQualifiedErrorId-notlike'NoProcessFoundForGivenName,*'){throw 'Cannot establish KingdomCome process state.'}}
        $open=$false
        foreach($candidate in $candidates){$candidate.Refresh();if(-not $candidate.HasExited){$open=$true}}
        return $open
    }finally{foreach($candidate in $candidates){$candidate.Dispose()}}
}
function Assert-Closed{if(Get-GameOpen){throw 'Close every KingdomCome process normally before updating. No process is stopped.'}}
function Assert-Exe{
    $null=Assert-Unlinked $script:gameExe;$v=(Get-Item -LiteralPath $script:gameExe).VersionInfo
    if((Get-FileHash -LiteralPath $script:gameExe -Algorithm SHA256).Hash-ine $exeHash -or $v.FileVersion-cne'1.5.5.0' -or $v.ProductVersion-cne'1.5.5.0' -or
       $v.FileMajorPart-ne 1 -or $v.FileMinorPart-ne 0 -or $v.FileBuildPart-ne 0 -or $v.FilePrivatePart-ne 0){throw 'Exact pinned fixed1.0.0.0/display1.5.5.0 official tools executable required.'}
}
function Replace-OwnedFile($Entry,[scriptblock]$BeforeMutation){
    Assert-File $Entry.Target $Entry.Old
    Assert-File $Entry.Source $Entry.New
    $null=Assert-Unlinked $Entry.Backup;$null=Assert-Unlinked $Entry.Temp
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Entry.Backup))|Out-Null
    [IO.File]::Copy($Entry.Target,$Entry.Backup,$false)
    Assert-File $Entry.Backup $Entry.Old
    [IO.File]::Copy($Entry.Source,$Entry.Temp,$false)
    Assert-File $Entry.Temp $Entry.New
    Assert-File $Entry.Target $Entry.Old
    if($null-ne $BeforeMutation){& $BeforeMutation}
    # Temp and target are siblings: File.Replace is an atomic same-volume replacement.
    # NullString avoids PowerShell coercing a null string argument to an empty path.
    [IO.File]::Replace($Entry.Temp,$Entry.Target,[NullString]::Value)
    Assert-File $Entry.Target $Entry.New
}
function Restore-OwnedFile($Entry,[scriptblock]$BeforeMutation){
    $null=Assert-Unlinked $Entry.Target
    if((Get-FileHash -LiteralPath $Entry.Target -Algorithm SHA256).Hash-ieq $Entry.Old.sha256){Assert-File $Entry.Target $Entry.Old;return 'already_old'}
    Assert-File $Entry.Target $Entry.New
    Assert-File $Entry.Backup $Entry.Old
    $restore=$Entry.Temp+'.restore';$null=Assert-Unlinked $restore
    [IO.File]::Copy($Entry.Backup,$restore,$false)
    try{Assert-File $restore $Entry.Old;Assert-File $Entry.Target $Entry.New;if($null-ne $BeforeMutation){& $BeforeMutation};[IO.File]::Replace($restore,$Entry.Target,[NullString]::Value);Assert-File $Entry.Target $Entry.Old}
    finally{if((Test-Path -LiteralPath $restore -PathType Leaf) -and (Get-FileHash -LiteralPath $restore -Algorithm SHA256).Hash-ieq $Entry.Old.sha256){[IO.File]::Delete($restore)}}
    return 'restored_old'
}

$BundleDirectory=Assert-InRuntime $BundleDirectory
$PreviousBundleDirectory=Assert-InRuntime $PreviousBundleDirectory
if($BundleDirectory.Equals($PreviousBundleDirectory,[StringComparison]::OrdinalIgnoreCase)){throw 'New and previous bundle directories must differ.'}
$inventory=Read-Json (Join-Path $runtimeRoot 'environment.json')
$tools=@($inventory.steam.relevant_apps|Where-Object{$_.role-ceq'official_tools' -and $_.installed-eq$true -and $_.distribution-ceq'Steam' -and $_.app_id-eq'2429020'})
if($tools.Count-ne 1){throw 'One discovered official Steam tools installation is required.'}
$bin=Assert-Unlinked (Join-Path $tools[0].install_path 'Bin/Win64ReleaseSteamLTO_DLL')
$gameExe=Assert-Unlinked (Join-Path $bin 'KingdomCome.exe');Assert-Exe
$oldReceiptPath=Join-Path $PreviousBundleDirectory 'installed.json';$old=Read-Json $oldReceiptPath
if($old.schema-ne 1 -or $old.kind-cne'minecome_hud_install_v1' -or $old.exe_sha256-ine $exeHash -or
   -not ([IO.Path]::GetFullPath($old.target_exe).Equals($gameExe,[StringComparison]::OrdinalIgnoreCase)) -or
   -not ([IO.Path]::GetFullPath($old.bundle).Equals($PreviousBundleDirectory,[StringComparison]::OrdinalIgnoreCase)) -or @($old.files).Count-ne 6){throw 'Previous receipt does not own this exact six-file tools installation.'}
if($WalkingAimed){
    $previousManifest=Read-Json (Join-Path $PreviousBundleDirectory 'bundle.json')
    $previousMouseProfile=Get-MineComeWalkingAimedUpdatePreviousProfile $previousManifest $old ([bool]$RepeatSession) ([bool]$FromPhysicalMovement)
    $previousProxyHash=$previousMouseProfile.runtime_sha256
}elseif($PhysicalMovement){
    . (Join-Path $PSScriptRoot 'HudMouseProfile.ps1')
    $previousManifest=Read-Json (Join-Path $PreviousBundleDirectory 'bundle.json')
    $previousMouseProfile=Get-MineComePhysicalUpdatePreviousProfile $previousManifest $old ([bool]$FromWalkingAimedRepeat)
    $previousProxyHash=$previousMouseProfile.runtime_sha256
}elseif($WorldClicks){
    $previousManifest=Read-Json (Join-Path $PreviousBundleDirectory 'bundle.json')
    # Later revisions require the immediately preceding frozen Selective
    # installation; older transitions retain the original World/Mouse chain.
    $previousSelective=[bool]($SelectiveMouse -and $SelectiveRevision -ge 2)
    $previousRevision=if($SelectiveRevision -ge 3){$SelectiveRevision-1}else{1}
    $previousMouseProfile=Get-MineComeMouseProfile -WorldClicks:$SelectiveMouse -SelectiveMouse:$previousSelective -SelectiveRevision $previousRevision
    Assert-MineComeMouseInstalledBundle $previousManifest $old $previousMouseProfile -WorldClicks:$SelectiveMouse -SelectiveMouse:$previousSelective -SelectiveRevision $previousRevision
    $previousProxyHash=$previousMouseProfile.runtime_sha256
}
$newManifestPath=Join-Path $BundleDirectory 'bundle.json';$manifest=Read-Json $newManifestPath
if($WalkingAimed){Assert-MineComeWalkingAimedBundle $manifest $mouseProfile}
elseif($PhysicalMovement){Assert-MineComePhysicalMovementBundle $manifest $mouseProfile}
elseif($LiveMouse){Assert-MineComeMouseBundle $manifest $mouseProfile -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse -SelectiveRevision $SelectiveRevision}
elseif($manifest.PSObject.Properties.Name -contains 'mouse_capture_api' -or $manifest.PSObject.Properties.Name -contains 'world_clicks' -or $manifest.PSObject.Properties.Name -contains 'selective_mouse' -or $manifest.PSObject.Properties.Name -contains 'selective_revision'){throw 'Mouse/world/selective update requires its explicit mode.'}
if($manifest.schema-ne 1 -or $manifest.kind-cne'minecome_hud_compositor_bundle_v1' -or $manifest.tools_only-ne$true -or @($manifest.files).Count-ne 6 -or
   $manifest.runtime.version-cne'6.8.0' -or $manifest.runtime.full_addon_support-ne$true -or $manifest.runtime.reshade64_sha256-cne $proxyHash){throw 'Unexpected pinned ReShade6.8.0 update bundle.'}
$inputBundle=$WalkingAimed -or $PhysicalMovement -or $LiveMouse -or $manifest.arm_config_relative_path-ceq'minecome-hud/addons/MineComeHudInput.ini'
$streamBundle=$inputBundle -or $manifest.arm_config_relative_path-ceq'minecome-hud/addons/MineComeHudStream.ini'
if($streamBundle){
    if($manifest.PSObject.Properties.Name -notcontains 'stream_protocol' -or $manifest.stream_protocol-ne 1){throw 'Stream update requires protocol1 provenance.'}
}elseif($manifest.arm_config_relative_path-cne'minecome-hud/addons/MineComeHud.ini' -or $manifest.PSObject.Properties.Name -contains 'stream_protocol'){throw 'Unknown or mixed HUD update mode.'}
if($inputBundle){
    $expectedInputProtocol=if($PhysicalMovement -or $WalkingAimed){2}else{1}
    if($manifest.PSObject.Properties.Name -notcontains 'ui_input_protocol' -or $manifest.ui_input_protocol-ne $expectedInputProtocol){throw 'UI input update requires its explicit protocol provenance.'}
}elseif($manifest.PSObject.Properties.Name -contains 'ui_input_protocol'){throw 'UI input metadata in a non-input bundle.'}
$activeProxy=Assert-Unlinked (Join-Path $bin 'dxgi.dll');$disabledProxy=Assert-Unlinked (Join-Path $bin 'dxgi.dll.minecome-disabled')
$activePresent=Test-Path -LiteralPath $activeProxy -PathType Leaf
$disabledPresent=Test-Path -LiteralPath $disabledProxy -PathType Leaf
if($activePresent -and ($disabledPresent -or -not $PreflightOnly)){throw 'Update requires the active owned proxy to be disabled first; preserved all paths.'}
if(-not $activePresent -and -not $disabledPresent){throw 'Owned proxy is missing.'}
$armPath=Assert-Unlinked (Join-Path $bin $manifest.arm_config_relative_path)
$allArmPaths=@('MineComeHud.ini','MineComeHudStream.ini','MineComeHudInput.ini','MineComeHudMouse.ini','MineComeHudWorld.ini','MineComeHudSelective.ini','MineComeHudMovement.ini','MineComeHudWalkingAimed.ini','MineComeHudWalkingRepeat.ini') | ForEach-Object {Assert-Unlinked (Join-Path $bin ('minecome-hud/addons/'+$_))}
$existingArms=@($allArmPaths | Where-Object {Test-Path -LiteralPath $_})
if($existingArms.Count -and -not $PreflightOnly){throw 'Existing HUD arm configuration preserved. Update requires an unarmed installation.'}
$installedPath=Assert-InRuntime (Join-Path $BundleDirectory 'installed.json')
if(Test-Path -LiteralPath $installedPath){throw 'New bundle already has an installed receipt; preserved without overwrite.'}
$entries=@()
foreach($relative in $expected){
    $before=@($old.files|Where-Object{$_.path-ceq$relative});$after=@($manifest.files|Where-Object{$_.path-ceq$relative})
    if($before.Count-ne 1 -or $after.Count-ne 1){throw "Missing/duplicate owned update record: $relative"}
    Assert-Record $before[0];Assert-Record $after[0]
    $target=Assert-Unlinked (Join-Path $bin $(if($relative-ceq'dxgi.dll' -and -not $activePresent){'dxgi.dll.minecome-disabled'}else{$relative}))
    if(-not $target.StartsWith($bin+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Update target escaped the exact tools binary directory.'}
    $source=Assert-InRuntime (Join-Path $BundleDirectory $relative)
    Assert-File $target $before[0];Assert-File $source $after[0]
    if($relative-ceq'dxgi.dll' -and ($before[0].sha256-cne$previousProxyHash -or $after[0].sha256-cne$proxyHash)){throw 'Only the exact owned previous proxy and pinned new profile may be enabled.'}
    if($relative-ceq'minecome-hud/addons/MineComeHudCompositor.addon64'){
        $allowedHashes=if($WalkingAimed -or $PhysicalMovement -or $LiveMouse){@($mouseProfile.addon_sha256)}elseif($inputBundle){$supportedInputAddonHashes}elseif($streamBundle){$supportedStreamAddonHashes}else{$supportedAddonHashes}
        if($after[0].sha256-cnotin$allowedHashes){throw 'An exact supported addon for the declared static/stream mode is required.'}
    }
    $entries+=[pscustomobject]@{Relative=$relative;Target=$target;Source=$source;Old=$before[0];New=$after[0];Changed=($before[0].sha256-cne$after[0].sha256);Backup=$null;Temp=$null}
}
$builtAddon=Assert-Unlinked $manifest.original_addon_source
if(-not $builtAddon.StartsWith($projectRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Original built addon must remain within this workspace.'}
Assert-File $builtAddon (@($entries|Where-Object{$_.Relative-ceq'minecome-hud/addons/MineComeHudCompositor.addon64'})[0].New)
$gameOpen=Get-GameOpen
$changed=@($entries|Where-Object{$_.Changed})
if($PreflightOnly){
    [ordered]@{schema=1;kind='minecome_hud_update_preflight_v1';game_open=$gameOpen;target_exe=$gameExe;previous_bundle=$PreviousBundleDirectory;new_bundle=$BundleDirectory;verified_old_files=6;verified_new_files=6;changed_files=@($changed|ForEach-Object{$_.Relative});reenable_owned_proxy=$true;requires_game_closed=$true;requires_proxy_disable=$activePresent;existing_arms=$existingArms;files_changed=$false;receipt_written=$false}|ConvertTo-Json -Depth 5
    Write-Output 'HUD_UPDATE_PREFLIGHT_PASS no_changes=true'
    return
}
Assert-Closed
$run=[guid]::NewGuid().ToString('N')
$evidence=Assert-InRuntime (Join-Path $runtimeRoot ('evidence/hud-update-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run))
if(Test-Path -LiteralPath $evidence){throw 'Update evidence directory must be new.'}
[IO.Directory]::CreateDirectory($evidence)|Out-Null
[IO.File]::Copy($oldReceiptPath,(Join-Path $evidence 'previous-installed.json'),$false)
[IO.File]::Copy($newManifestPath,(Join-Path $evidence 'new-bundle.json'),$false)
$attempted=[Collections.Generic.List[object]]::new();$enabled=$false;$installedHash=$null;$failure=$null;$rollback=@();$status='prepared'
$updateReceiptPath=Join-Path $evidence 'update.json'
try{
    foreach($entry in $entries){Assert-File $entry.Target $entry.Old;Assert-File $entry.Source $entry.New}
    foreach($entry in $changed){
        Assert-Closed;Assert-Exe
        $entry.Backup=Assert-InRuntime (Join-Path $evidence ('backup/'+$entry.Relative))
        $entry.Temp=Assert-Unlinked ($entry.Target+'.minecome-update-'+$run+'.tmp')
        $attempted.Add($entry);Replace-OwnedFile $entry {Assert-Closed;Assert-Exe}
    }
    foreach($entry in $entries){Assert-File $entry.Target $entry.New}
    Assert-Closed;Assert-Exe
    if((Test-Path -LiteralPath $activeProxy) -or @($allArmPaths | Where-Object {Test-Path -LiteralPath $_}).Count){throw 'Proxy/arm path appeared during update; no re-enable attempted.'}
    $installation=[ordered]@{schema=1;kind='minecome_hud_install_v1';installed_utc=[DateTime]::UtcNow.ToString('o');target_exe=$gameExe;exe_sha256=$exeHash;bundle=$BundleDirectory;files=$manifest.files;armed=$false;game_launched=$false;live_kcd_compositing_verified=$false;previous_installation=$oldReceiptPath;update_evidence=$evidence}
    Write-NewJson $installedPath $installation
    $installedHash=(Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
    # Final game-directory mutation: enable only after all six fixed files and receipt are verified.
    $null=Assert-Unlinked $activeProxy;$null=Assert-Unlinked $disabledProxy
    Assert-Closed;Assert-Exe
    foreach($entry in $entries){Assert-File $entry.Target $entry.New}
    [IO.File]::Move($disabledProxy,$activeProxy);$enabled=$true
    Assert-File $activeProxy (@($entries|Where-Object{$_.Relative-ceq'dxgi.dll'})[0].New)
    $status='updated_unarmed'
    # Receipt failure is inside the transaction, so it also disables/restores the owned files.
    Write-NewJson $updateReceiptPath ([ordered]@{schema=1;kind='minecome_hud_update_v1';run=$run;utc=[DateTime]::UtcNow.ToString('o');status=$status;failure=$null;target_exe=$gameExe;exe_sha256=$exeHash;previous_bundle=$PreviousBundleDirectory;new_bundle=$BundleDirectory;changed_files=@($changed|ForEach-Object{$_.Relative});proxy_enabled=$enabled;installed_receipt=$installedPath;rollback=@();evidence=$evidence;game_launched=$false;game_stopped=$false;preview_armed=$false;live_kcd_compositing_verified=$false})
}catch{
    $failure=$_.Exception.Message;$status='failed'
    try{
        if($enabled){
            $null=Assert-Unlinked $activeProxy;$null=Assert-Unlinked $disabledProxy
            Assert-File $activeProxy (@($entries|Where-Object{$_.Relative-ceq'dxgi.dll'})[0].New)
            if(Test-Path -LiteralPath $disabledProxy){throw 'Disabled path conflict during rollback; preserved both files.'}
            Assert-Closed;Assert-Exe
            [IO.File]::Move($activeProxy,$disabledProxy);$enabled=$false
        }
    }catch{$rollback+=[ordered]@{path='dxgi.dll';status='preserved_rollback_error';error=$_.Exception.Message}}
    for($i=$attempted.Count-1;$i-ge 0;$i--){
        $entry=$attempted[$i]
        try{Assert-Closed;Assert-Exe;$restored=Restore-OwnedFile $entry {Assert-Closed;Assert-Exe};$rollback+=[ordered]@{path=$entry.Relative;status=$restored}}
        catch{$rollback+=[ordered]@{path=$entry.Relative;status='preserved_rollback_error';error=$_.Exception.Message}}
    }
    if($installedHash -and (Test-Path -LiteralPath $installedPath)){
        try{
            $null=Assert-Unlinked $installedPath
            if((Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash-cne$installedHash){throw 'New receipt changed; preserved.'}
            [IO.File]::Copy($installedPath,(Join-Path $evidence 'failed-installed.json'),$false)
            [IO.File]::Delete($installedPath)
        }catch{$rollback+=[ordered]@{path=$installedPath;status='preserved_rollback_error';error=$_.Exception.Message}}
    }
}finally{
    foreach($entry in $attempted){
        try{if((Test-Path -LiteralPath $entry.Temp -PathType Leaf) -and (Get-FileHash -LiteralPath $entry.Temp -Algorithm SHA256).Hash-ieq $entry.New.sha256){$null=Assert-Unlinked $entry.Temp;[IO.File]::Delete($entry.Temp)}}catch{}
    }
    if($failure){
        # Preserve any partial success receipt as evidence; a separate failure file is CREATE_NEW.
        $updateReceiptPath=Join-Path $evidence 'update-failed.json'
        Write-NewJson $updateReceiptPath ([ordered]@{schema=1;kind='minecome_hud_update_v1';run=$run;utc=[DateTime]::UtcNow.ToString('o');status=$status;failure=$failure;target_exe=$gameExe;exe_sha256=$exeHash;previous_bundle=$PreviousBundleDirectory;new_bundle=$BundleDirectory;changed_files=@($changed|ForEach-Object{$_.Relative});proxy_enabled=$enabled;installed_receipt=$installedPath;rollback=$rollback;evidence=$evidence;game_launched=$false;game_stopped=$false;preview_armed=$false;live_kcd_compositing_verified=$false})
    }
}
Write-Output "HUD_UPDATE_RESULT status=$status proxy_enabled=$enabled evidence=$evidence receipt=$updateReceiptPath"
if($failure){throw "HUD update failed; owned backups/evidence preserved: $failure"}
