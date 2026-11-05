#Requires -Version 5.1
# Stage the exact built v5 proxy and gameplay addon in the workspace only.
[CmdletBinding()]
param([string]$BundleDirectory,[switch]$Movement,[switch]$Blocks,[switch]$Chat,[switch]$Flight)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($Flight){$Chat=$true}
. (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
if(-not $BundleDirectory){$BundleDirectory=Join-Path $script:mcGameplayRoot $(if($Chat){'runtime/hud-compositor-gameplay-chat'}elseif($Blocks){'runtime/hud-compositor-gameplay-blocks'}elseif($Movement){'runtime/hud-compositor-gameplay-movement'}else{'runtime/hud-compositor-gameplay'})}
$bundle=Resolve-MineComeGameplayPath $BundleDirectory -InRuntime;$profile=Get-MineComeGameplayProfile -Movement:$Movement -Blocks:$Blocks -Chat:$Chat
if(Test-Path -LiteralPath $bundle){$null=Assert-MineComeGameplayBundle $bundle $profile;Write-Output "GAMEPLAY_HUD_PREPARED existing_verified=true bundle=$bundle game_changed=false";return}
$previous=Resolve-MineComeGameplayPath (Join-Path $script:mcGameplayRoot $profile.previous_bundle) -InRuntime
if((Get-MineComeGameplayHash (Join-Path $previous 'bundle.json')) -cne $profile.previous_manifest_sha256 -or (Get-MineComeGameplayHash (Join-Path $previous 'installed.json')) -cne $profile.previous_receipt_sha256){throw 'Previous owned bundle/receipt differs from its pinned provenance.'}
$buildPath=Join-Path $script:mcGameplayRoot $profile.build_receipt
if((Get-MineComeGameplayHash $buildPath) -cne $profile.build_receipt_sha256){throw 'Gameplay proxy build receipt changed.'}
$build=Read-MineComeGameplayJson $buildPath
if($build.kind -cne 'minecome_selective_reshade_build_v2' -or $build.status -cne 'built' -or $build.selective_revision -ne 5 -or $build.gameplay_keyboard_api -ne 5 -or $build.commit -cne $profile.upstream_commit -or $build.version -cne '6.8.0.7'){throw 'Exact successful v5 build receipt required.'}
foreach($flag in @('generated_outputs_unchanged','patched_source_unchanged','installed_proxy_unchanged','reference_unchanged','pristine_source_unchanged','pristine_script_unchanged')){if($build.$flag -ne $true){throw "Missing verified build predicate: $flag"}}
foreach($input in $build.original_inputs){if((Get-MineComeGameplayHash $input.path) -ine $input.sha256){throw "Proxy source changed after build: $($input.path)"}}
$sources=@{}
foreach($r in $profile.files){
    $source=if($r.path -ceq 'dxgi.dll'){$build.output}elseif($r.path -ceq 'minecome-hud/addons/MineComeHudCompositor.addon64'){Join-Path $script:mcGameplayRoot $profile.addon_source}else{Join-Path $previous $r.path}
    $null=Resolve-MineComeGameplayPath $source;Assert-MineComeGameplayFile $source $r;$sources[$r.path]=$source
}
[IO.Directory]::CreateDirectory($bundle)|Out-Null
foreach($r in $profile.files){$target=Join-Path $bundle $r.path;[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null;[IO.File]::Copy($sources[$r.path],$target,$false);Assert-MineComeGameplayFile $target $r}
[IO.File]::Copy($buildPath,(Join-Path $bundle 'proxy-build-receipt.json'),$false)
$manifest=[ordered]@{schema=3;kind='minecome_gameplay_hud_bundle_v3';tools_only=$true;stream_protocol=3;ui_input_protocol=(Get-MineComeGameplayInputProtocol $profile);mouse_capture_api=2;gameplay_keyboard_api=5;selective_revision=5;profile_sha256=(Get-MineComeGameplayHash (Get-MineComeGameplayProfilePath -Movement:$Movement -Blocks:$Blocks -Chat:$Chat));arm_config_relative_path=$profile.arm_config_relative_path;files=$profile.files;build_receipt_sha256=$profile.build_receipt_sha256;preview_armed=$false;game_installation_modified=$false;game_launched=$false;live_kcd_compositing_verified=$false;created_utc=[DateTime]::UtcNow.ToString('o')}
Write-MineComeGameplayJson (Join-Path $bundle 'bundle.json') $manifest
$null=Assert-MineComeGameplayBundle $bundle $profile
Write-Output "GAMEPLAY_HUD_PREPARED bundle=$bundle files=6 game_changed=false"
