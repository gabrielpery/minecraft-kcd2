#Requires -Version 5.1
# Pure profile/receipt checks and owned-file replacement/rollback in a fresh
# workspace directory. No game access, deployment or process launches.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudMouseProfile.ps1')
$checks=0
function Check([bool]$Value,[string]$Why){$script:checks++;if(-not $Value){throw $Why}}
function Reject([scriptblock]$Action,[string]$Why){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Why}
$profile=[pscustomobject]@{runtime_sha256=('a'*64);addon_sha256=('b'*64);shader_sha256=('c'*64);build_receipt_sha256=('d'*64)}
function New-Manifest {
    [ordered]@{mouse_capture_api=1;stream_protocol=1;ui_input_protocol=1;arm_config_relative_path='minecome-hud/addons/MineComeHudMouse.ini';runtime=[ordered]@{reshade64_sha256=('a'*64);build_receipt_sha256=('d'*64)};files=@(
        [ordered]@{path='dxgi.dll';sha256=('a'*64)},[ordered]@{path='minecome-hud/addons/MineComeHudCompositor.addon64';sha256=('b'*64)},[ordered]@{path='minecome-hud/shaders/MineComeHud.fx';sha256=('c'*64)})}
}
$manifest=New-Manifest;Assert-MineComeMouseBundle $manifest $profile;Check $true 'Ordered manifest accepted'
Assert-MineComeMouseBundle ($manifest|ConvertTo-Json -Depth 6|ConvertFrom-Json) $profile;Check $true 'JSON manifest accepted'
foreach($field in @('mouse_capture_api','stream_protocol','ui_input_protocol')){
    $manifest=New-Manifest;$manifest[$field]=2;Reject {Assert-MineComeMouseBundle $manifest $profile} "Reject changed $field"
    $manifest=New-Manifest;$manifest.Remove($field);Reject {Assert-MineComeMouseBundle $manifest $profile} "Reject missing $field"
}
$manifest=New-Manifest;$manifest.arm_config_relative_path='minecome-hud/addons/MineComeHudInput.ini';Reject {Assert-MineComeMouseBundle $manifest $profile} 'Keyboard arm refused'
$manifest=New-Manifest;$manifest.runtime.build_receipt_sha256='e'*64;Reject {Assert-MineComeMouseBundle $manifest $profile} 'Foreign build receipt refused'
$manifest=New-Manifest;$manifest.runtime.reshade64_sha256='e'*64;Reject {Assert-MineComeMouseBundle $manifest $profile} 'Foreign runtime refused'
for($i=0;$i -lt 3;$i++){
    $manifest=New-Manifest;$manifest.files[$i].sha256='e'*64;Reject {Assert-MineComeMouseBundle $manifest $profile} 'Changed artifact refused'
    $manifest=New-Manifest;$manifest.files+=@($manifest.files[$i]);Reject {Assert-MineComeMouseBundle $manifest $profile} 'Duplicate artifact refused'
}
$scriptPath=Join-Path $PSScriptRoot '../scripts/Update-HudCompositor.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Update syntax valid'
foreach($name in @('Assert-Unlinked','Assert-File','Replace-OwnedFile','Restore-OwnedFile')){
    $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    Invoke-Expression $node.Extent.Text
}
$directory=Join-Path $PSScriptRoot ('../runtime/evidence/hud-mouse-profile-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($directory)|Out-Null
function Record([string]$Path){[pscustomobject]@{sha256=(Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $Path).Length}}
$oldPath=Join-Path $directory 'owned.txt';$newPath=Join-Path $directory 'staged.txt'
[IO.File]::WriteAllText($oldPath,'verified old');[IO.File]::WriteAllText($newPath,'verified new')
$entry=[pscustomobject]@{Target=$oldPath;Source=$newPath;Old=(Record $oldPath);New=(Record $newPath);Backup=(Join-Path $directory 'backup.txt');Temp=(Join-Path $directory 'pending.tmp')}
Replace-OwnedFile $entry {};Check ((Record $oldPath).sha256 -eq $entry.New.sha256) 'Owned replacement applied';Check ((Record $entry.Backup).sha256 -eq $entry.Old.sha256) 'Backup preserved'
$restored=Restore-OwnedFile $entry {};Check ($restored -eq 'restored_old' -and (Record $oldPath).sha256 -eq $entry.Old.sha256) 'Rollback restored exact original'
[IO.File]::WriteAllText($oldPath,'foreign change')
Reject {Restore-OwnedFile $entry {}} 'Rollback preserves externally changed target'
Check ([IO.File]::ReadAllText($oldPath) -eq 'foreign change') 'External file unchanged'
[ordered]@{checks=$checks;passed=$true;game_accessed=$false;deployment=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding UTF8
Write-Output "HUD_MOUSE_PROFILE_TEST_PASS checks=$checks evidence=$directory no_game=true"
