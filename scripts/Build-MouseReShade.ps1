#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the original mouse-capture patch in a new private checkout. Never deploy.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselineReceipt,
    [Parameter(Mandatory)][string]$MSBuild,
    [Parameter(Mandatory)][string]$DumpBin,
    [string]$WindowsSdkVersion='10.0.26100.0',
    [string]$PlatformToolset='v143',
    [string]$VisualStudioVersion='17.0',
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pin='18deaa52de0c425a78b329e9cb3c497281cd00ec'
$reference=Join-Path $root 'external/reshade'
$pristine=Join-Path $root 'runtime/dependencies/reshade-minecome-6.8.0/source'
$pristineScript=Join-Path $PSScriptRoot 'Build-CustomReShade.ps1'
$workspace=Join-Path $root 'runtime/dependencies/reshade-mouse-6.8.0'
$id=[Guid]::NewGuid().ToString('N')
$source=Join-Path $workspace ('source-'+$id.Substring(0,12))
$run=Join-Path $workspace ('evidence/'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$id)
$proxy='C:/Program Files (x86)/Steam/steamapps/common/KCD2Mod/Bin/Win64ReleaseSteamLTO_DLL/dxgi.dll'
$patch=Join-Path $root 'kcd2/reshade/mouse-capture.patch'
$copies=[ordered]@{
    'kcd2/hud/mouse_capture_api.hpp'='source/windows/mouse_capture_api.hpp'
    'kcd2/hud/mouse_capture_policy.hpp'='source/windows/mouse_capture_policy.hpp'
    'kcd2/reshade/mouse_capture_adapter.hpp'='source/windows/mouse_capture_adapter.hpp'
}
$commands=[Collections.Generic.List[object]]::new()
$result=[ordered]@{schema=1;kind='minecome_mouse_reshade_build_v1';upstream='https://github.com/crosire/reshade';commit=$pin;configuration='Release';platform='x64';source=$source;evidence=$run;status='failed';failure=$null;game_launched=$false;deployed=$false;hook_changes=$true;created_utc=[DateTime]::UtcNow.ToString('o');bit_reproducibility_verified=$false}
function Assert-PlainPath([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked build path refused: $cursor"}
        $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
    }
}
function Relative-Path([string]$Base,[string]$Relative) {
    if([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)'){throw "Unsafe manifest path: $Relative"}
    $full=[IO.Path]::GetFullPath((Join-Path $Base $Relative))
    if(-not $full.StartsWith([IO.Path]::GetFullPath($Base).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Manifest path escapes source: $Relative"}
    Assert-PlainPath $full
    return $full
}
function Hash([string]$Path) {return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Run([string]$Executable,[string[]]$Arguments,[string]$Name) {
    $commands.Add([ordered]@{executable=$Executable;arguments=$Arguments;cwd=(Get-Location).Path})
    $log=Join-Path $run ($Name+'.log')
    & $Executable @Arguments 2>&1 | Tee-Object -FilePath $log | Write-Output
    if($LASTEXITCODE -ne 0){throw "$Name failed with exit code $LASTEXITCODE; see $log"}
}
function Clean-Pin([string]$Path) {
    $head=& git -C $Path rev-parse HEAD
    if($LASTEXITCODE -ne 0 -or $head -cne $pin){return $false}
    $status=@(& git -C $Path status --porcelain=v1)
    return $LASTEXITCODE -eq 0 -and $status.Count -eq 0
}
function Write-GladGuard([string]$Path,[string[]]$Expected) {
    $lines=@('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">', '<Target Name="MineComeRequireVerifiedGlad" BeforeTargets="GenerateGladSources" Condition="''$(MSBuildProjectName)'' == ''glad''">')
    foreach($relative in $Expected){$local=$relative.Substring('deps/'.Length).Replace('/','\');$lines+=('<Error Condition="!Exists(''$(MSBuildProjectDirectory)\'+$local+''')" Text="Verified GLAD output missing; generation is disabled in this build profile." />')}
    $lines+=@('</Target>','</Project>');$lines | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}
foreach($path in @($workspace,$source,$run,$pristine,$reference,$BaselineReceipt,$pristineScript,$patch)){Assert-PlainPath $path}
if(Test-Path -LiteralPath $source){throw 'Private source directory already exists; existing work was preserved.'}
[IO.Directory]::CreateDirectory($run) | Out-Null
$proxyBefore=if(Test-Path -LiteralPath $proxy){Hash $proxy}else{$null}
$pristineScriptBefore=Hash $pristineScript
$oldPipIndex=$env:PIP_NO_INDEX;$oldPythonPath=$env:PYTHONPATH;$oldPythonHome=$env:PYTHONHOME
$baseline=$null;$sourceFingerprint=$null;$inputHashes=@()
try {
    $MSBuild=(Resolve-Path -LiteralPath $MSBuild).Path;$DumpBin=(Resolve-Path -LiteralPath $DumpBin).Path
    $BaselineReceipt=(Resolve-Path -LiteralPath $BaselineReceipt).Path
    $baseline=Get-Content -LiteralPath $BaselineReceipt -Raw | ConvertFrom-Json
    if($baseline.kind -cne 'minecome_pristine_reshade_build_v1' -or $baseline.status -cne 'built' -or $baseline.commit -cne $pin -or [IO.Path]::GetFullPath($baseline.source) -ine $pristine){throw 'Expected a successful receipt for the exact pristine checkout.'}
    foreach($flag in @('glad_reproducible','glad_platform_headers_match_pinned','installed_proxy_unchanged','reference_unchanged')){if($baseline.$flag -isnot [bool] -or $baseline.$flag -ne $true){throw "Baseline verification flag missing: $flag"}}
    if($baseline.source_status.Count -ne 0 -or -not(Clean-Pin $reference) -or -not(Clean-Pin $pristine)){throw 'Protected reference and pristine checkout must be clean and pinned.'}
    Assert-PlainPath $baseline.output
    if((Hash $baseline.output) -cne $baseline.output_sha256 -or $pristineScriptBefore -cne $baseline.build_script_sha256){throw 'Pristine binary or build recipe no longer matches its receipt.'}
    $result.baseline_receipt=$BaselineReceipt;$result.baseline_receipt_sha256=Hash $BaselineReceipt;$result.baseline_output_sha256=$baseline.output_sha256
    Copy-Item -LiteralPath $BaselineReceipt -Destination (Join-Path $run 'baseline-verification.json')
    $generated=@($baseline.glad_generated_files)
    $expected=@('deps/glad/target/include/glad/gl.h','deps/glad/target/include/glad/vulkan.h','deps/glad/target/include/glad/wgl.h','deps/glad/target/include/KHR/khrplatform.h','deps/glad/target/include/vk_platform.h','deps/glad/target/src/gl.c','deps/glad/target/src/vulkan.c','deps/glad/target/src/wgl.c')
    $observedPaths=($generated | ForEach-Object {$_.path.Replace('\','/')} | Sort-Object) -join '|'
    if($generated.Count -ne $expected.Count -or $observedPaths -cne (($expected | Sort-Object) -join '|')){throw 'Unexpected pristine GLAD output manifest.'}
    foreach($entry in @($baseline.glad_generator_inputs)+$generated){if((Hash (Relative-Path $pristine $entry.path)) -cne $entry.sha256){throw "Pristine GLAD input/output changed: $($entry.path)"}}
    $inputHashes=@(@($patch)+@($copies.Keys | ForEach-Object {Join-Path $root $_}) | ForEach-Object {Assert-PlainPath $_;[ordered]@{path=$_;sha256=Hash $_}})
    $result.original_inputs=$inputHashes
    Copy-Item -LiteralPath $patch -Destination (Join-Path $run 'mouse-capture.patch')
    Run git @('clone','--no-hardlinks','--no-checkout',$reference,$source) 'clone'
    Run git @('-C',$source,'config','core.autocrlf','false') 'checkout-line-endings'
    Run git @('-C',$source,'checkout','--detach',$pin) 'checkout'
    Run git @('-c','core.longpaths=true','-C',$source,'submodule','update','--init','--recursive','--jobs','4') 'submodules'
    $submodules=@(& git -C $source submodule status --recursive)
    if($LASTEXITCODE -ne 0 -or @($submodules | Where-Object {$_ -notmatch '^ [0-9a-f]{40} '}).Count){throw 'Submodule state does not match pinned gitlinks.'}
    $submodules | Set-Content -LiteralPath (Join-Path $run 'submodules.lock') -Encoding utf8NoBOM
    # Reuse only generated sources verified above, never pristine object files.
    foreach($entry in $generated){$target=Relative-Path $source $entry.path;[IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null;Copy-Item -LiteralPath (Relative-Path $pristine $entry.path) -Destination $target;if((Hash $target) -cne $entry.sha256){throw 'Copied GLAD output differs from its receipt.'}}
    Run git @('-C',$source,'apply','--check','--index',$patch) 'patch-check'
    Run git @('-C',$source,'apply','--index',$patch) 'patch-apply'
    foreach($relative in $copies.Keys){$target=Relative-Path $source $copies[$relative];if(Test-Path -LiteralPath $target){throw "Patch overlaps a separately hashed input: $target"};Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $target;Run git @('-C',$source,'add','--',$copies[$relative]) ('stage-'+[IO.Path]::GetFileNameWithoutExtension($relative))}
    # Freeze the exact patched index, including copied ABI/policy headers.
    $sourceFingerprint=& git -C $source write-tree
    if($LASTEXITCODE -ne 0){throw 'Cannot fingerprint patched source.'}
    $result.patched_tree=$sourceFingerprint
    & git -C $source diff --cached --binary ('--output='+(Join-Path $run 'complete-source.patch'))
    if($LASTEXITCODE -ne 0){throw 'Cannot save complete patched source.'}
    $result.complete_source_patch_sha256=Hash (Join-Path $run 'complete-source.patch')
    $result.patched_paths=@(& git -C $source diff --cached --name-only)
    $allowedPaths=@('source/windows/dinput8.cpp')+@($copies.Values)
    if((($result.patched_paths | Sort-Object) -join '|') -cne (($allowedPaths | Sort-Object) -join '|')){throw 'The patch must change only dinput8.cpp and the three separately hashed headers.'}
    $result.patched_files=@($result.patched_paths | ForEach-Object {$path=Relative-Path $source $_;[ordered]@{path=$_;sha256=Hash $path;includes=@(Select-String -LiteralPath $path -Pattern '^\s*#include\s' | ForEach-Object {$_.Line.Trim()})}})
    $version=Relative-Path $source 'res/version.h'
    @('#pragma once','','#define VERSION_FULL 6.8.0.2','#define VERSION_MAJOR 6','#define VERSION_MINOR 8','#define VERSION_REVISION 0','#define VERSION_BUILD 2','','#define VERSION_STRING_FILE "6.8.0.2"','#define VERSION_STRING_PRODUCT "6.8.0 MINECOME MOUSE UNOFFICIAL"') | Set-Content -LiteralPath $version -Encoding ascii
    if($PrepareOnly){$result.status='prepared'}
    else {
        # Fail before upstream GLAD could regenerate anything. The VC target
        # import hook is process-local and leaves the project file untouched.
        $guard=Join-Path $run 'verified-glad-only.targets'
        Write-GladGuard $guard $expected
        $result.generator_guard=$guard;$result.generator_guard_sha256=Hash $guard
        $env:PIP_NO_INDEX='1';$env:PYTHONPATH=$null;$env:PYTHONHOME=$null
        Push-Location $source
        try {Run $MSBuild @('ReShade.vcxproj','/m:4','/t:Build','/p:Configuration=Release','/p:Platform=x64',('/p:PlatformToolset='+$PlatformToolset),('/p:VisualStudioVersion='+$VisualStudioVersion),('/p:WindowsTargetPlatformVersion='+$WindowsSdkVersion),('/p:SolutionDir='+$source+'\'),'/p:BuildingSetupTool=true','/p:GladReproducible=true',('/p:ForceImportBeforeCppTargets='+$guard),('/bl:'+(Join-Path $run 'build.binlog')),'/v:minimal') 'build'} finally {Pop-Location}
        $output=Join-Path $run 'ReShade64-minecome-mouse-6.8.0.dll'
        Copy-Item -LiteralPath (Relative-Path $source 'bin/x64/Release/ReShade64.dll') -Destination $output
        Run $DumpBin @('/headers','/exports',$output) 'pe-headers-exports'
        $pe=Get-Content -LiteralPath (Join-Path $run 'pe-headers-exports.log') -Raw
        foreach($required in @('8664 machine (x64)','ReShadeRegisterAddon','ReShadeRegisterEvent','DirectInput8Create','MineComeGetMouseCaptureApi')){if(-not $pe.Contains($required)){throw "Expected PE header/export missing: $required"}}
        $result.output=$output;$result.output_sha256=Hash $output;$result.output_bytes=(Get-Item -LiteralPath $output).Length;$result.version=(Get-Item -LiteralPath $output).VersionInfo.FileVersion
        $result.msbuild=$MSBuild;$result.msbuild_version=(Get-Item -LiteralPath $MSBuild).VersionInfo.FileVersion;$result.dumpbin=$DumpBin;$result.sdk=$WindowsSdkVersion;$result.toolset=$PlatformToolset
        $result.generated_outputs_unchanged=$true
        foreach($entry in $generated){if((Hash (Relative-Path $source $entry.path)) -cne $entry.sha256){$result.generated_outputs_unchanged=$false;throw "Reused GLAD output changed: $($entry.path)"}}
        $licenses=Join-Path $run 'licenses';[IO.Directory]::CreateDirectory($licenses) | Out-Null
        $licenseFiles=@(& git -C $source ls-files | Where-Object {$_ -match '(^|/)(LICENSE[^/]*|COPYING[^/]*|NOTICE[^/]*)$'})
        foreach($line in $submodules){$sub=($line -split ' ')[2];foreach($file in @(& git -C (Join-Path $source $sub) ls-files | Where-Object {$_ -match '(^|/)(LICENSE[^/]*|COPYING[^/]*|NOTICE[^/]*)$'})){$licenseFiles+=($sub+'/'+$file)}}
        $licenseFiles+=@('deps/stb/README.md','deps/fpng/src/fpng.cpp','deps/glad/glad/files/khrplatform.h','deps/glad/glad/files/vk_platform.h')
        foreach($relative in $licenseFiles){$target=Relative-Path $licenses $relative;[IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null;Copy-Item -LiteralPath (Relative-Path $source $relative) -Destination $target}
        $licenseFiles | Set-Content -LiteralPath (Join-Path $run 'license-files.txt') -Encoding utf8NoBOM
        Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $licenses 'MINECOME-LICENSE')
        $result.original_patch_license_sha256=Hash (Join-Path $licenses 'MINECOME-LICENSE')
        $result.license_files=@(Get-ChildItem -LiteralPath $licenses -Recurse -File | Sort-Object FullName | ForEach-Object {[ordered]@{path=[IO.Path]::GetRelativePath($licenses,$_.FullName);sha256=Hash $_.FullName;bytes=$_.Length}})
        $result.status='built'
    }
    if((& git -C $source write-tree) -cne $sourceFingerprint -or @(& git -C $source diff --name-only).Count -or @(& git -C $source ls-files --others --exclude-standard).Count){throw 'Build altered the frozen patched source.'}
    foreach($entry in $result.patched_files){if((Hash (Relative-Path $source $entry.path)) -cne $entry.sha256){throw "Patched source changed during build: $($entry.path)"}}
    $result.patched_source_unchanged=$true
    foreach($entry in $inputHashes){if((Hash $entry.path) -cne $entry.sha256){throw "Original patch/API/policy changed during build: $($entry.path)"}}
} catch {$result.status='failed';$result.failure=$_.Exception.Message;throw}
finally {
    $env:PIP_NO_INDEX=$oldPipIndex;$env:PYTHONPATH=$oldPythonPath;$env:PYTHONHOME=$oldPythonHome
    $proxyAfter=if(Test-Path -LiteralPath $proxy){Hash $proxy}else{$null}
    $result.installed_proxy_sha256_before=$proxyBefore;$result.installed_proxy_sha256_after=$proxyAfter;$result.installed_proxy_unchanged=$proxyBefore -ceq $proxyAfter
    $result.reference_unchanged=Clean-Pin $reference;$result.pristine_source_unchanged=Clean-Pin $pristine;$result.pristine_script_unchanged=(Hash $pristineScript) -ceq $pristineScriptBefore
    if(-not $result.installed_proxy_unchanged -or -not $result.reference_unchanged -or -not $result.pristine_source_unchanged -or -not $result.pristine_script_unchanged){$result.status='failed';$result.failure='A protected reference, pristine script/source, or installed proxy changed.'}
    $result.finished_utc=[DateTime]::UtcNow.ToString('o');$result.build_script_sha256=Hash $PSCommandPath
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $run 'Build-MouseReShade.ps1')
    $commands | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'commands.json') -Encoding utf8NoBOM
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'verification.json') -Encoding utf8NoBOM
    Write-Output ('MOUSE_RESHADE_BUILD_RESULT '+(Join-Path $run 'verification.json'))
}
if($result.status -ne 'built' -and -not($PrepareOnly -and $result.status -eq 'prepared')){throw $result.failure}
