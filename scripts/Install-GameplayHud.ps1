#Requires -Version 5.1
# Explicit reversible tools-only replacement. Never launches/stops games or arms HUD.
[CmdletBinding()]
param([string]$BundleDirectory,[switch]$PreflightOnly,[switch]$Restore,[switch]$Movement)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
if(-not $BundleDirectory){$BundleDirectory=Join-Path $script:mcGameplayRoot $(if($Movement){'runtime/hud-compositor-gameplay-movement'}else{'runtime/hud-compositor-gameplay'})}
$bundle=Resolve-MineComeGameplayPath $BundleDirectory -InRuntime;$profile=Get-MineComeGameplayProfile -Movement:$Movement;$manifest=Assert-MineComeGameplayBundle $bundle $profile
$bin=Get-MineComeGameplayToolsBin $profile;$exe=Join-Path $bin 'KingdomCome.exe'
$previous=Resolve-MineComeGameplayPath (Join-Path $script:mcGameplayRoot $profile.previous_bundle) -InRuntime
$oldManifestPath=Join-Path $previous 'bundle.json';$oldReceiptPath=Join-Path $previous 'installed.json'
if((Get-MineComeGameplayHash $oldManifestPath) -cne $profile.previous_manifest_sha256 -or (Get-MineComeGameplayHash $oldReceiptPath) -cne $profile.previous_receipt_sha256){throw 'Previous owned deployment metadata changed.'}
$old=Read-MineComeGameplayJson $oldManifestPath;$oldReceipt=Read-MineComeGameplayJson $oldReceiptPath
if($old.kind -cne 'minecome_hud_compositor_bundle_v1' -or $oldReceipt.kind -cne 'minecome_hud_install_v1' -or $oldReceipt.target_exe -ine $exe -or $oldReceipt.exe_sha256 -cne $profile.tools_exe_sha256 -or $oldReceipt.bundle -ine $previous){throw 'Previous deployment is not the exact owned tools installation.'}
Assert-MineComeGameplayRecords $old.files;Assert-MineComeGameplayRecords $oldReceipt.files
foreach($record in $old.files){$installed=@($oldReceipt.files|Where-Object{$_.path -ceq $record.path})[0];if($record.sha256 -cne $installed.sha256 -or $record.bytes -ne $installed.bytes){throw 'Previous bundle and installed receipt differ.'}}
$installedPath=Join-Path $bundle 'installed.json';$restorePath=Join-Path $bundle 'restored.json'
$receipt=$null
if($Restore){$current=Get-MineComeGameplayInstallation -BundleDirectory $bundle -RequireUnarmed -Movement:$Movement;$receipt=$current.InstalledReceipt}
elseif(Test-Path -LiteralPath $installedPath){$null=Get-MineComeGameplayInstallation -BundleDirectory $bundle -RequireUnarmed -Movement:$Movement;Write-Output "GAMEPLAY_HUD_ALREADY_INSTALLED verified=true bundle=$bundle no_changes=true";return}
Assert-MineComeGameplayNoArms $bin
if(Test-Path -LiteralPath (Join-Path $bin 'dxgi.dll.minecome-disabled')){throw 'Conflicting disabled proxy preserved; expected the exact active owned installation.'}
$entries=@()
foreach($next in $profile.files){
    $before=@($old.files|Where-Object{$_.path -ceq $next.path})[0]
    $target=Resolve-MineComeGameplayPath (Join-Path $bin $next.path)
    if($Restore){$backupRoot=Resolve-MineComeGameplayPath $receipt.backup_directory -InRuntime;$source=Resolve-MineComeGameplayPath (Join-Path $backupRoot $next.path) -InRuntime;$expected=$next;$replacement=$before}
    else{$source=Join-Path $bundle $next.path;$expected=$before;$replacement=$next}
    Assert-MineComeGameplayFile $target $expected;Assert-MineComeGameplayFile $source $replacement
    $entries+=[pscustomobject]@{Relative=$next.path;Target=$target;Source=$source;Old=$expected;New=$replacement;Backup=$null;Temp=$null}
}
$gameOpen=@(Get-Process KingdomCome -ErrorAction SilentlyContinue).Count -ne 0
if($PreflightOnly){[ordered]@{kind='minecome_gameplay_hud_preflight_v1';restore=[bool]$Restore;target_exe=$exe;bundle=$bundle;verified_current_files=6;verified_replacement_files=6;game_open=$gameOpen;requires_game_closed=$true;armed=$false;files_changed=$false}|ConvertTo-Json;Write-Output 'GAMEPLAY_HUD_PREFLIGHT_PASS no_changes=true';return}
function Assert-GameplayMutationReady {
    if(@(Get-Process KingdomCome -ErrorAction SilentlyContinue).Count){throw 'Close KCD2 normally before changing renderer files; no process will be stopped.'}
    if((Get-MineComeGameplayHash $exe) -cne $profile.tools_exe_sha256){throw 'Tools executable changed.'}
    $addonEntry=@($entries|Where-Object{$_.Relative -ceq 'minecome-hud/addons/MineComeHudCompositor.addon64'})[0]
    if($addonEntry.Temp -and (Test-Path -LiteralPath $addonEntry.Temp)){
        if($addonEntry.Temp -cne ($addonEntry.Target+'.minecome-gameplay-'+$run+'.tmp')){throw 'Unexpected transaction temporary-file path.'}
        Assert-MineComeGameplayNoArms $bin $addonEntry.Temp $addonEntry.New
    }else{Assert-MineComeGameplayNoArms $bin}
}
Assert-GameplayMutationReady
$run=[guid]::NewGuid().ToString('N');$evidence=Resolve-MineComeGameplayPath (Join-Path $script:mcGameplayRoot ('runtime/evidence/gameplay-hud-'+$(if($Restore){'restore-'}else{'install-'})+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)) -InRuntime
$backup=Join-Path $evidence 'backup';[IO.Directory]::CreateDirectory($backup)|Out-Null
# Every original is copied and verified before the first game-directory write.
foreach($entry in $entries){$entry.Backup=Join-Path $backup $entry.Relative;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($entry.Backup))|Out-Null;Assert-MineComeGameplayFile $entry.Target $entry.Old;[IO.File]::Copy($entry.Target,$entry.Backup,$false);Assert-MineComeGameplayFile $entry.Backup $entry.Old}
[IO.File]::Copy($oldManifestPath,(Join-Path $evidence 'previous-bundle.json'),$false)
[IO.File]::Copy($oldReceiptPath,(Join-Path $evidence 'previous-installed.json'),$false)
[IO.File]::Copy((Join-Path $bundle 'bundle.json'),(Join-Path $evidence 'gameplay-bundle.json'),$false)
Write-MineComeGameplayJson (Join-Path $evidence 'prepared.json') ([ordered]@{schema=1;kind='minecome_gameplay_hud_transaction_v1';run=$run;restore=[bool]$Restore;target_exe=$exe;backup_directory=$backup;old_files=@($entries|ForEach-Object{$_.Old});new_files=@($entries|ForEach-Object{$_.New});game_launched=$false;armed=$false})
$attempted=[Collections.Generic.List[object]]::new();$rollback=@()
try{
    foreach($entry in $entries){
        Assert-GameplayMutationReady;Assert-MineComeGameplayFile $entry.Target $entry.Old;Assert-MineComeGameplayFile $entry.Source $entry.New
        $entry.Temp=Resolve-MineComeGameplayPath ($entry.Target+'.minecome-gameplay-'+$run+'.tmp')
        [IO.File]::Copy($entry.Source,$entry.Temp,$false);Assert-MineComeGameplayFile $entry.Temp $entry.New
        Assert-GameplayMutationReady;Assert-MineComeGameplayFile $entry.Target $entry.Old
        $attempted.Add($entry);[IO.File]::Replace($entry.Temp,$entry.Target,[NullString]::Value);Assert-MineComeGameplayFile $entry.Target $entry.New
    }
    Assert-GameplayMutationReady;foreach($entry in $entries){Assert-MineComeGameplayFile $entry.Target $entry.New}
    if($Restore){
        Write-MineComeGameplayJson $restorePath ([ordered]@{schema=1;kind='minecome_gameplay_hud_restore_v1';utc=[DateTime]::UtcNow.ToString('o');installation_receipt=$installedPath;target_exe=$exe;evidence=$evidence;files=$old.files;armed=$false;game_launched=$false})
    }else{
        Write-MineComeGameplayJson $installedPath ([ordered]@{schema=1;kind='minecome_gameplay_hud_install_v1';status='installed_unarmed';utc=[DateTime]::UtcNow.ToString('o');profile_sha256=$manifest.profile_sha256;target_exe=$exe;exe_sha256=$profile.tools_exe_sha256;bundle=$bundle;files=$profile.files;previous_manifest_sha256=$profile.previous_manifest_sha256;previous_receipt_sha256=$profile.previous_receipt_sha256;previous_bundle=$previous;backup_directory=$backup;evidence=$evidence;armed=$false;game_launched=$false;live_kcd_compositing_verified=$false})
    }
}catch{
    $failure=$_.Exception.Message
    for($i=$attempted.Count-1;$i-ge 0;$i--){$entry=$attempted[$i];try{
        Assert-GameplayMutationReady
        if((Get-MineComeGameplayHash $entry.Target) -ceq $entry.Old.sha256){continue}
        Assert-MineComeGameplayFile $entry.Target $entry.New;Assert-MineComeGameplayFile $entry.Backup $entry.Old
        $temporary=Resolve-MineComeGameplayPath ($entry.Target+'.minecome-rollback-'+$run+'.tmp');[IO.File]::Copy($entry.Backup,$temporary,$false);[IO.File]::Replace($temporary,$entry.Target,[NullString]::Value);Assert-MineComeGameplayFile $entry.Target $entry.Old
        $rollback+=[ordered]@{path=$entry.Relative;restored=$true}
    }catch{$rollback+=[ordered]@{path=$entry.Relative;restored=$false;error=$_.Exception.Message}}}
    Write-MineComeGameplayJson (Join-Path $evidence 'failed.json') ([ordered]@{failure=$failure;rollback=$rollback;backups=$backup;game_launched=$false;armed=$false})
    throw "Gameplay HUD change failed; verified backups retained at $backup. $failure"
}finally{
    foreach($entry in $entries){if($entry.Temp -and (Test-Path -LiteralPath $entry.Temp) -and (Get-MineComeGameplayHash $entry.Temp) -ceq $entry.New.sha256){[IO.File]::Delete($entry.Temp)}}
}
Write-Output "GAMEPLAY_HUD_CHANGE_COMPLETE restore=$([bool]$Restore) bundle=$bundle evidence=$evidence armed=false game_launched=false"
