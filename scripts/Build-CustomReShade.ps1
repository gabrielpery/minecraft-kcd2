#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the pristine pinned full-add-on baseline only. Never deploy or launch a game.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Python,
    [Parameter(Mandatory)][string]$MSBuild,
    [string]$WindowsSdkVersion='10.0.26100.0',
    [string]$PlatformToolset='v143',
    [string]$VisualStudioVersion='17.0',
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pin='18deaa52de0c425a78b329e9cb3c497281cd00ec'
$reference=Join-Path $root 'external/reshade'
$workspace=Join-Path $root 'runtime/dependencies/reshade-minecome-6.8.0'
$source=Join-Path $workspace 'source'
$venv=Join-Path $workspace 'python-venv'
$wheels=Join-Path $workspace 'wheels'
$run=Join-Path $workspace ('evidence/'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
$proxy='C:/Program Files (x86)/Steam/steamapps/common/KCD2Mod/Bin/Win64ReleaseSteamLTO_DLL/dxgi.dll'
$commands=[Collections.Generic.List[object]]::new()
$result=[ordered]@{schema=1;kind='minecome_pristine_reshade_build_v1';upstream='https://github.com/crosire/reshade';commit=$pin;configuration='Release';platform='x64';source=$source;evidence=$run;status='failed';failure=$null;game_launched=$false;deployed=$false;hook_changes=$false;created_utc=[DateTime]::UtcNow.ToString('o');bit_reproducibility_verified=$false}
function Assert-BuildPath([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked build path refused: $cursor"}
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if($parent -eq $cursor){break};$cursor=$parent
    }
}
foreach($path in @($workspace,$source,$venv,$wheels,$run,(Join-Path $source 'bin'),(Join-Path $source 'intermediate'),(Join-Path $source 'res/version.h'),(Join-Path $source 'deps/glad/target'),(Join-Path $venv 'Scripts'),(Join-Path $venv 'Lib/site-packages'),(Join-Path $workspace 'pip-cache'))){Assert-BuildPath $path}
foreach($directory in @($workspace,$wheels,$run)){[IO.Directory]::CreateDirectory($directory) | Out-Null}
$oldPath=$env:PATH;$oldPipIndex=$env:PIP_NO_INDEX;$oldPipVersion=$env:PIP_DISABLE_PIP_VERSION_CHECK;$oldPipCache=$env:PIP_CACHE_DIR;$oldPythonPath=$env:PYTHONPATH;$oldPythonHome=$env:PYTHONHOME
function Run([string]$Executable,[string[]]$Arguments,[string]$Name) {
    $commands.Add([ordered]@{executable=$Executable;arguments=$Arguments;cwd=(Get-Location).Path})
    $log=Join-Path $run ($Name+'.log')
    & $Executable @Arguments 2>&1 | Tee-Object -FilePath $log | Write-Output
    if($LASTEXITCODE -ne 0){throw "$Name failed with exit code $LASTEXITCODE; see $log"}
}
$proxyBefore=if(Test-Path -LiteralPath $proxy){(Get-FileHash -LiteralPath $proxy).Hash}else{$null}
$referenceBefore=@(& git -C $reference status --porcelain=v1)
try {
    $Python=(Resolve-Path -LiteralPath $Python).Path;$MSBuild=(Resolve-Path -LiteralPath $MSBuild).Path
    if((& git -C $reference rev-parse HEAD) -cne $pin -or $referenceBefore.Count){throw 'Pinned reference must be pristine at the exact ReShade commit.'}
    if(-not(Test-Path -LiteralPath $source)){
        Run git @('clone','--no-hardlinks','--no-checkout',$reference,$source) 'clone'
        Run git @('-C',$source,'checkout','--detach',$pin) 'checkout'
    }
    if((& git -C $source rev-parse HEAD) -cne $pin -or @(& git -C $source status --porcelain=v1).Count){throw 'Isolated source must be pristine and pinned; existing changes were preserved.'}
    Run git @('-c','core.longpaths=true','-C',$source,'submodule','update','--init','--recursive','--jobs','4') 'submodules'
    $submodules=@(& git -C $source submodule status --recursive)
    if($LASTEXITCODE -ne 0 -or @($submodules | Where-Object {$_ -notmatch '^ [0-9a-f]{40} '}).Count){throw 'Submodule state does not match pinned gitlinks.'}
    $submodules | Set-Content -LiteralPath (Join-Path $run 'submodules.lock') -Encoding utf8NoBOM
    if(-not(Test-Path -LiteralPath (Join-Path $venv 'Scripts/python.exe'))){Run $Python @('-m','venv',$venv) 'venv'}
    $venvPython=Join-Path $venv 'Scripts/python.exe'
    $env:PATH=(Join-Path $venv 'Scripts')+';'+$env:PATH
    $env:PYTHONPATH=$null;$env:PYTHONHOME=$null
    $env:PIP_DISABLE_PIP_VERSION_CHECK='1';$env:PIP_CACHE_DIR=Join-Path $workspace 'pip-cache';$env:PIP_NO_INDEX=$null
    Run $venvPython @('-m','pip','download','--only-binary=:all:','--no-deps','--dest',$wheels,'Jinja2==3.1.6','MarkupSafe==3.0.3') 'pip-download'
    $jinja=@(Get-ChildItem -LiteralPath $wheels -Filter 'jinja2-3.1.6-*.whl')
    $markup=@(Get-ChildItem -LiteralPath $wheels -Filter 'markupsafe-3.0.3-*.whl')
    if($jinja.Count -ne 1 -or $markup.Count -ne 1){throw 'Ambiguous pinned wheel set.'}
    $lock=Join-Path $run 'requirements.lock'
    @(
        ('Jinja2==3.1.6 --hash=sha256:'+((Get-FileHash -LiteralPath $jinja[0].FullName).Hash.ToLowerInvariant()))
        ('MarkupSafe==3.0.3 --hash=sha256:'+((Get-FileHash -LiteralPath $markup[0].FullName).Hash.ToLowerInvariant()))
    ) | Set-Content -LiteralPath $lock -Encoding ascii
    Run $venvPython @('-m','pip','install','--no-index','--find-links',$wheels,'--require-hashes','--force-reinstall','--report',(Join-Path $run 'pip-report.json'),'-r',$lock) 'pip-install'
    Run $venvPython @('-m','pip','freeze','--all') 'pip-freeze'
    Run $venvPython @('-c','import sys; print(sys.version); print(sys.executable)') 'python-version'
    $env:PIP_NO_INDEX='1'
    # Deterministic generated metadata; the upstream pre-build step otherwise
    # increments VERSION_BUILD on every retry. No tracked source is changed.
    $version=Join-Path $source 'res/version.h'
    @('#pragma once','','#define VERSION_FULL 6.8.0.1','#define VERSION_MAJOR 6','#define VERSION_MINOR 8','#define VERSION_REVISION 0','#define VERSION_BUILD 1','','#define VERSION_STRING_FILE "6.8.0.1"','#define VERSION_STRING_PRODUCT "6.8.0 UNOFFICIAL"') | Set-Content -LiteralPath $version -Encoding ascii
    if($PrepareOnly){$result.status='prepared'}
    else {
    # GLAD's reproducible opener normally ignores ReShade's newer pinned XML
    # in deps/khronos. Keep that XML while sourcing platform headers from the
    # pinned GLAD package. This process-local resolver never uses the network
    # and does not modify either checkout.
    $resolver=Join-Path $run 'glad-input-resolver';[IO.Directory]::CreateDirectory($resolver) | Out-Null
    $resolverScript=Join-Path $resolver 'sitecustomize.py'
    @'
import pathlib
import glad.files

_upstream_open = glad.files.StaticFileOpener.urlopen
_xml_root = pathlib.Path(__XML_ROOT__)

def _pinned_open(self, url, data=None, *args, **kwargs):
    if data is None and url in ("file:gl.xml", "file:wgl.xml", "file:vk.xml"):
        return (_xml_root / url[5:]).open("rb")
    return _upstream_open(self, url, data, *args, **kwargs)

glad.files.StaticFileOpener.urlopen = _pinned_open
'@.Replace('__XML_ROOT__',((Join-Path $source 'deps/khronos').Replace('\','/') | ConvertTo-Json -Compress)) | Set-Content -LiteralPath $resolverScript -Encoding utf8NoBOM
    $env:PYTHONPATH=$resolver+';'+(Join-Path $source 'deps/glad')
    Run $venvPython @('-c','from glad.files import StaticFileOpener; import hashlib,pathlib,sys; o=StaticFileOpener(); [(print(n, hashlib.sha256(o.urlopen("file:"+n).read()).hexdigest()), o.urlopen("file:"+n).read()==(pathlib.Path(sys.argv[1])/n).read_bytes() or sys.exit("Pinned XML mismatch: "+n)) for n in ("gl.xml", "wgl.xml", "vk.xml")]',(Join-Path $source 'deps/khronos')) 'glad-pinned-inputs'
    $result.glad_input_resolver=$resolverScript;$result.glad_input_resolver_sha256=(Get-FileHash -LiteralPath $resolverScript).Hash
    $gladInputs=@('deps/khronos/gl.xml','deps/khronos/wgl.xml','deps/khronos/vk.xml')
    $gladInputs+=@(Get-ChildItem -LiteralPath (Join-Path $source 'deps/glad/glad/files') -Filter '*.h' -File | ForEach-Object {[IO.Path]::GetRelativePath($source,$_.FullName)})
    $result.glad_generator_inputs=@($gladInputs | Sort-Object | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $source $_)).Hash}})
    Push-Location $source
    try {
        # Force only the upstream generator's declared outputs to regenerate:
        # otherwise files from an earlier non-reproducible run could survive.
        foreach($relative in @('src/gl.c','src/vulkan.c','src/wgl.c','include/glad/gl.h','include/glad/vulkan.h','include/glad/wgl.h','include/KHR/khrplatform.h','include/vk_platform.h')){Assert-BuildPath (Join-Path $source ('deps/glad/target/'+$relative))}
        # GLAD intentionally retains existing additional headers; its clean
        # target does not remove them. Seed these two from the pinned package.
        $platformHeaders=[ordered]@{'include/KHR/khrplatform.h'='deps/glad/glad/files/khrplatform.h';'include/vk_platform.h'='deps/glad/glad/files/vk_platform.h'}
        foreach($relative in $platformHeaders.Keys){
            $target=Join-Path $source ('deps/glad/target/'+$relative)
            [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
            Copy-Item -LiteralPath (Join-Path $source $platformHeaders[$relative]) -Destination $target
        }
        Run $MSBuild @('deps/glad.vcxproj','/t:CleanGLADSources','/p:Configuration=Release','/p:Platform=x64',('/p:PlatformToolset='+$PlatformToolset),('/p:VisualStudioVersion='+$VisualStudioVersion),('/p:WindowsTargetPlatformVersion='+$WindowsSdkVersion),('/p:SolutionDir='+$source+'\'),'/v:minimal') 'clean-generated-glad'
        Run $MSBuild @('ReShade.vcxproj','/m:4','/t:Build','/p:Configuration=Release','/p:Platform=x64',('/p:PlatformToolset='+$PlatformToolset),('/p:VisualStudioVersion='+$VisualStudioVersion),('/p:WindowsTargetPlatformVersion='+$WindowsSdkVersion),('/p:SolutionDir='+$source+'\'),'/p:BuildingSetupTool=true','/p:GladReproducible=true',('/bl:'+(Join-Path $run 'build.binlog')),'/v:minimal') 'build'
        foreach($relative in $platformHeaders.Keys){
            if((Get-FileHash -LiteralPath (Join-Path $source ('deps/glad/target/'+$relative))).Hash -cne (Get-FileHash -LiteralPath (Join-Path $source $platformHeaders[$relative])).Hash){throw "Generated platform header differs from pinned input: $relative"}
        }
        $result.glad_platform_headers_match_pinned=$true
    } finally {Pop-Location}
    $binary=Join-Path $source 'bin/x64/Release/ReShade64.dll'
    if(-not(Test-Path -LiteralPath $binary)){throw 'Expected ReShade64.dll output is missing.'}
    $output=Join-Path $run 'ReShade64-pristine-addon-6.8.0.dll'
    Copy-Item -LiteralPath $binary -Destination $output
    $licenses=Join-Path $run 'licenses';[IO.Directory]::CreateDirectory($licenses) | Out-Null
    $licenseFiles=@(& git -C $source ls-files | Where-Object {$_ -match '(^|/)(LICENSE[^/]*|COPYING[^/]*|NOTICE[^/]*)$'})
    foreach($line in $submodules){
        $sub=($line -split ' ')[2]
        foreach($file in @(& git -C (Join-Path $source $sub) ls-files | Where-Object {$_ -match '(^|/)(LICENSE[^/]*|COPYING[^/]*|NOTICE[^/]*)$'})){$licenseFiles+=($sub+'/'+$file)}
    }
    # stb publishes its alternatives in its README and individual headers,
    # rather than a repository-root LICENSE file.
    $licenseFiles+='deps/stb/README.md'
    # These dependencies carry their notices inside source/header files.
    $licenseFiles+=@('deps/fpng/src/fpng.cpp','deps/glad/glad/files/khrplatform.h','deps/glad/glad/files/vk_platform.h')
    foreach($relative in $licenseFiles){$target=Join-Path $licenses $relative;[IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null;Copy-Item -LiteralPath (Join-Path $source $relative) -Destination $target}
    $licenseFiles | Set-Content -LiteralPath (Join-Path $run 'license-files.txt') -Encoding utf8NoBOM
    $result.output=$output;$result.output_sha256=(Get-FileHash -LiteralPath $output).Hash;$result.output_bytes=(Get-Item -LiteralPath $output).Length
    $result.version=(Get-Item -LiteralPath $output).VersionInfo.FileVersion;$result.msbuild=$MSBuild;$result.msbuild_version=(Get-Item -LiteralPath $MSBuild).VersionInfo.FileVersion;$result.python=$Python;$result.sdk=$WindowsSdkVersion;$result.toolset=$PlatformToolset
    $result.glad_reproducible=$true
    $result.glad_generated_files=@(Get-ChildItem -LiteralPath (Join-Path $source 'deps/glad/target') -Recurse -File | Sort-Object FullName | ForEach-Object {[ordered]@{path=[IO.Path]::GetRelativePath($source,$_.FullName);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
    $result.source_status=@(& git -C $source status --porcelain=v1)
    if($result.source_status.Count){throw 'The build changed tracked source; inspect evidence.'}
    $result.status='built'
    }
} catch {$result.failure=$_.Exception.Message;throw}
finally {
    $env:PATH=$oldPath;$env:PIP_NO_INDEX=$oldPipIndex;$env:PIP_DISABLE_PIP_VERSION_CHECK=$oldPipVersion;$env:PIP_CACHE_DIR=$oldPipCache;$env:PYTHONPATH=$oldPythonPath;$env:PYTHONHOME=$oldPythonHome
    $proxyAfter=if(Test-Path -LiteralPath $proxy){(Get-FileHash -LiteralPath $proxy).Hash}else{$null}
    $result.installed_proxy_sha256_before=$proxyBefore;$result.installed_proxy_sha256_after=$proxyAfter;$result.installed_proxy_unchanged=$proxyBefore -ceq $proxyAfter
    $result.reference_unchanged=((& git -C $reference rev-parse HEAD) -ceq $pin -and (@(& git -C $reference status --porcelain=v1) -join "`n") -ceq ($referenceBefore -join "`n"))
    if(-not $result.installed_proxy_unchanged -or -not $result.reference_unchanged){$result.status='failed';$result.failure='A protected reference or installed proxy changed during the build.'}
    $result.finished_utc=[DateTime]::UtcNow.ToString('o');$result.build_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    $commands | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'commands.json') -Encoding utf8NoBOM
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'verification.json') -Encoding utf8NoBOM
    Write-Output ('RESHade_BASELINE_RESULT '+(Join-Path $run 'verification.json'))
}
if($result.status -ne 'built' -and -not($PrepareOnly -and $result.status -eq 'prepared')){throw $result.failure}
