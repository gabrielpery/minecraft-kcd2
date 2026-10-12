# Read-only discovery; only -OutputPath writes a JSON snapshot. No game launches,
# installation, account/profile reads, save contents, or registry modifications.
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string[]]$AdditionalMinecraftRoots = @(),
    [switch]$IncludeHashes,
    [switch]$AsObject
)

$ErrorActionPreference = 'Stop'
$discoveryWarnings = [System.Collections.Generic.List[string]]::new()

function Add-ExistingPath {
    param([System.Collections.Generic.HashSet[string]]$Set, [string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Container)) {
        [void]$Set.Add([System.IO.Path]::GetFullPath($Path))
    }
}

function Get-CommandPath {
    param([string]$Name)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

function Get-ExecutableInfo {
    param([string]$Path, [switch]$Hash)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $file = Get-Item -LiteralPath $Path
    $record = [ordered]@{
        path = $file.FullName
        file_version = $file.VersionInfo.FileVersion
        product_version = $file.VersionInfo.ProductVersion
        bytes = $file.Length
    }
    if ($Hash) { $record.sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
    return [pscustomobject]$record
}

function Get-VersionOutput {
    param([string]$Path, [string[]]$Arguments = @('--version'))
    if (-not $Path) { return $null }
    try {
        # No cmd.exe/string-generated command; paths and arguments remain separate.
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $output = @(& $Path @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference
        return [pscustomobject]@{ exit_code = $code; lines = $output }
    } catch {
        $ErrorActionPreference = $oldPreference
        $discoveryWarnings.Add('Could not obtain version from ' + $Path)
        return $null
    }
}

function Get-VdfValue {
    param([string]$Text, [string]$Key)
    $pattern = '"' + [regex]::Escape($Key) + '"\s*"([^"\r\n]*)"'
    $match = [regex]::Match($Text, $pattern)
    if ($match.Success) { return $match.Groups[1].Value.Replace('\\', '\') }
    return $null
}

$vswherePath = Get-CommandPath 'vswhere.exe'
if (-not $vswherePath -and ${env:ProgramFiles(x86)}) {
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $candidate) { $vswherePath = $candidate }
}
$visualStudio = @()
if ($vswherePath) {
    $instances = @(& $vswherePath -all -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json -utf8 | ConvertFrom-Json)
    foreach ($instance in $instances) {
        $bundledCmake = Join-Path $instance.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
        $bundledNinja = Join-Path $instance.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
        $compilerRoot = Join-Path $instance.installationPath 'VC\Tools\MSVC'
        $compilerVersions = @()
        if (Test-Path -LiteralPath $compilerRoot) {
            $compilerVersions = @(Get-ChildItem -LiteralPath $compilerRoot -Directory | ForEach-Object {
                $compiler = Join-Path $_.FullName 'bin\Hostx64\x64\cl.exe'
                if (Test-Path -LiteralPath $compiler) {
                    [pscustomobject]@{ toolset = $_.Name; compiler = Get-ExecutableInfo $compiler }
                }
            })
        }
        $visualStudio += [pscustomobject]@{
            name = $instance.displayName
            version = $instance.installationVersion
            path = $instance.installationPath
            complete = $instance.isComplete
            msvc_x64 = $compilerVersions
            cmake = Get-ExecutableInfo $bundledCmake
            cmake_version = Get-VersionOutput $bundledCmake
            ninja = Get-ExecutableInfo $bundledNinja
        }
    }
} else { $discoveryWarnings.Add('vswhere was not found; Visual Studio inventory is unavailable.') }

$commands = @()
foreach ($name in @('git.exe', 'cmake.exe', 'ninja.exe', 'java.exe', 'javac.exe', 'gradle.bat', 'pwsh.exe', 'python.exe', 'py.exe', 'dotnet.exe')) {
    $path = Get-CommandPath $name
    if ($path) {
        # Windows Store python aliases can launch installation UI; never execute them.
        $commands += [pscustomobject]@{ name = $name; executable = Get-ExecutableInfo $path }
    }
}

$jdkHomes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
Add-ExistingPath $jdkHomes $env:JAVA_HOME
$javaCommand = Get-CommandPath 'java.exe'
if ($javaCommand) {
    $commandHome = Split-Path (Split-Path $javaCommand -Parent) -Parent
    if (Test-Path -LiteralPath (Join-Path $commandHome 'release')) { Add-ExistingPath $jdkHomes $commandHome }
}
foreach ($programRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if (-not $programRoot) { continue }
    foreach ($vendor in @('Java', 'Eclipse Adoptium', 'Microsoft', 'Zulu', 'Amazon Corretto', 'BellSoft')) {
        $vendorRoot = Join-Path $programRoot $vendor
        if (Test-Path -LiteralPath $vendorRoot) {
            foreach ($directory in @(Get-ChildItem -LiteralPath $vendorRoot -Directory -ErrorAction SilentlyContinue)) {
                if (Test-Path -LiteralPath (Join-Path $directory.FullName 'bin\javac.exe')) { Add-ExistingPath $jdkHomes $directory.FullName }
            }
        }
    }
}
$jdkRecords = @()
foreach ($jdkHome in $jdkHomes) {
    $releasePath = Join-Path $jdkHome 'release'
    $version = $null
    $implementor = $null
    if (Test-Path -LiteralPath $releasePath) {
        $releaseText = [System.IO.File]::ReadAllText($releasePath)
        $match = [regex]::Match($releaseText, '(?m)^JAVA_VERSION="([^"]+)"')
        if ($match.Success) { $version = $match.Groups[1].Value }
        $match = [regex]::Match($releaseText, '(?m)^IMPLEMENTOR="([^"]+)"')
        if ($match.Success) { $implementor = $match.Groups[1].Value }
    }
    $jdkRecords += [pscustomobject]@{
        home = $jdkHome; version = $version; implementor = $implementor
        java = Get-ExecutableInfo (Join-Path $jdkHome 'bin\java.exe')
        javac = Get-ExecutableInfo (Join-Path $jdkHome 'bin\javac.exe')
    }
}

$steamRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($registryPath in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
    $key = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
    if ($key) {
        foreach ($property in @('SteamPath', 'InstallPath')) {
            if ($key.PSObject.Properties[$property]) { Add-ExistingPath $steamRoots ([string]$key.$property) }
        }
    }
}
$steamCommand = Get-CommandPath 'steam.exe'
if ($steamCommand) { Add-ExistingPath $steamRoots (Split-Path $steamCommand -Parent) }
$steamLibraries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($steamRoot in $steamRoots) {
    Add-ExistingPath $steamLibraries $steamRoot
    $foldersFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $foldersFile) {
        $text = [System.IO.File]::ReadAllText($foldersFile)
        foreach ($match in [regex]::Matches($text, '"path"\s*"([^"\r\n]+)"')) {
            Add-ExistingPath $steamLibraries $match.Groups[1].Value.Replace('\\', '\')
        }
        # Older Steam library files store an index directly against each path.
        foreach ($match in [regex]::Matches($text, '"[0-9]+"\s*"([A-Za-z]:[^"\r\n]+)"')) {
            Add-ExistingPath $steamLibraries $match.Groups[1].Value.Replace('\\', '\')
        }
    }
}
$gameRecords = @()
foreach ($library in $steamLibraries) {
    $apps = Join-Path $library 'steamapps'
    if (-not (Test-Path -LiteralPath $apps)) { continue }
    foreach ($manifest in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
        $manifestText = [System.IO.File]::ReadAllText($manifest.FullName)
        $name = Get-VdfValue $manifestText 'name'
        $appId = Get-VdfValue $manifestText 'appid'
        # Retail and official tools are separate installations and ABIs.
        if ($appId -notin @('1771300', '2429020') -and $name -notmatch '(?i)Kingdom.*Deliverance.*(II|2)|KCD2') { continue }
        $installDir = Get-VdfValue $manifestText 'installdir'
        if (-not $installDir) { continue }
        $installPath = [System.IO.Path]::GetFullPath((Join-Path $apps ('common\' + $installDir)))
        $binaries = @()
        $binRoot = Join-Path $installPath 'Bin'
        if (Test-Path -LiteralPath $binRoot) {
            foreach ($binary in @(Get-ChildItem -LiteralPath $binRoot -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('KingdomCome.exe', 'WHGame.dll', 'Sandbox.exe') })) {
                $binaries += Get-ExecutableInfo $binary.FullName -Hash:$IncludeHashes
            }
        }
        $cfgVersion = $null
        $systemCfg = Join-Path $installPath 'system.cfg'
        if (Test-Path -LiteralPath $systemCfg) {
            $match = [regex]::Match([System.IO.File]::ReadAllText($systemCfg), '(?m)^\s*wh_sys_version\s*=\s*"([^"\r\n]+)"')
            if ($match.Success) { $cfgVersion = $match.Groups[1].Value }
        }
        $buildMetadata = $null
        $buildFile = Join-Path $installPath 'whdlversions.json'
        if (Test-Path -LiteralPath $buildFile) {
            # Build identity only. This file is shipped game metadata, not a user profile.
            try {
                $shipped = Get-Content -LiteralPath $buildFile -Raw | ConvertFrom-Json
                $buildMetadata = [pscustomobject]@{
                    assembly_id = $shipped.Assembly.Id
                    preset = $shipped.Preset.Name
                    branch = $shipped.Preset.Branch.Name
                    binary_configurations = @($shipped.Configurations | Where-Object { $_.Name -match '^(?i)Bin|Editor' } | ForEach-Object {
                        [pscustomobject]@{ name = $_.Name; version_id = $_.SelectedVersion.versionId }
                    })
                }
            }
            catch { $discoveryWarnings.Add('Could not parse shipped build identity: ' + $buildFile) }
        }
        $loaders = @()
        foreach ($loader in @('dinput8.dll', 'dxgi.dll', 'ReShade64.dll')) {
            foreach ($directory in @($installPath) + @($binaries | ForEach-Object { Split-Path $_.path -Parent } | Select-Object -Unique)) {
                $loaderPath = Join-Path $directory $loader
                if (Test-Path -LiteralPath $loaderPath -PathType Leaf) { $loaders += Get-ExecutableInfo $loaderPath }
            }
        }
        $addressMaps = @()
        $addressDir = Join-Path $installPath 'KCSE\addresslib'
        if (Test-Path -LiteralPath $addressDir) { $addressMaps = @(Get-ChildItem -LiteralPath $addressDir -Filter '*.bin' -File | Select-Object -ExpandProperty FullName) }
        $gameRecords += [pscustomobject]@{
            distribution = 'Steam'; app_id = $appId; name = $name; manifest = $manifest.FullName
            build_id = Get-VdfValue $manifestText 'buildid'; last_updated_unix = Get-VdfValue $manifestText 'LastUpdated'
            install_path = $installPath; installed = Test-Path -LiteralPath $installPath
            role = $(if ($appId -eq '2429020' -or $name -match '(?i)modding|tools') { 'official_tools' } else { 'retail_game' })
            system_cfg_version = $cfgVersion; shipped_build_metadata = $buildMetadata; binaries = $binaries
            existing_loader_files = $loaders; kcse_address_maps = $addressMaps
            debug_http_index = $(if (Test-Path -LiteralPath (Join-Path $installPath 'Data\Libs\CryHttp\player\variantsPlayer\index.html')) { Join-Path $installPath 'Data\Libs\CryHttp\player\variantsPlayer\index.html' } else { $null })
        }
    }
}

$minecraftRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($env:APPDATA) { Add-ExistingPath $minecraftRoots (Join-Path $env:APPDATA '.minecraft') }
foreach ($extraRoot in $AdditionalMinecraftRoots) { Add-ExistingPath $minecraftRoots $extraRoot }
$minecraftRecords = @()
$launcherRuntimeRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($programRoot in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
    if ($programRoot) { Add-ExistingPath $launcherRuntimeRoots (Join-Path $programRoot 'Minecraft Launcher\runtime') }
}
if ($env:LOCALAPPDATA) {
    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packages) {
        foreach ($package in @(Get-ChildItem -LiteralPath $packages -Directory | Where-Object { $_.Name -like 'Microsoft.4297127D64EC6_*' })) {
            Add-ExistingPath $launcherRuntimeRoots (Join-Path $package.FullName 'LocalCache\Local\runtime')
        }
    }
}
foreach ($minecraftRoot in $minecraftRoots) {
    Add-ExistingPath $launcherRuntimeRoots (Join-Path $minecraftRoot 'runtime')
    $versionRecords = @()
    $versionRoot = Join-Path $minecraftRoot 'versions'
    if (Test-Path -LiteralPath $versionRoot) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $versionRoot -Directory)) {
            $metadataFile = Join-Path $directory.FullName ($directory.Name + '.json')
            if (-not (Test-Path -LiteralPath $metadataFile)) { continue }
            try {
                # Read only public version/dependency metadata, never launcher_profiles,
                # launcher_accounts, Microsoft authentication caches or account credentials.
                $metadata = Get-Content -LiteralPath $metadataFile -Raw | ConvertFrom-Json
                $loaderLibraries = @($metadata.libraries | Where-Object { $_.name -match '^(net\.fabricmc:|net\.minecraftforge:|net\.neoforged:)' } | ForEach-Object { $_.name })
                $versionRecords += [pscustomobject]@{
                    directory = $directory.Name; id = $metadata.id; inherits_from = $metadata.inheritsFrom
                    type = $metadata.type; java_major = $metadata.javaVersion.majorVersion; loader_libraries = $loaderLibraries
                    client_jar_present = Test-Path -LiteralPath (Join-Path $directory.FullName ($directory.Name + '.jar'))
                }
            } catch { $discoveryWarnings.Add('Could not parse Minecraft version metadata: ' + $metadataFile) }
        }
    }
    $modNames = @()
    $modsPath = Join-Path $minecraftRoot 'mods'
    if (Test-Path -LiteralPath $modsPath) { $modNames = @(Get-ChildItem -LiteralPath $modsPath -Filter '*.jar' -File | Select-Object -ExpandProperty Name) }
    $minecraftRecords += [pscustomobject]@{ root = $minecraftRoot; versions = $versionRecords; mod_filenames = $modNames }
}
$launcherRuntimeRecords = @()
foreach ($runtimeRoot in $launcherRuntimeRoots) {
    foreach ($releaseFile in @(Get-ChildItem -LiteralPath $runtimeRoot -Filter 'release' -File -Recurse -ErrorAction SilentlyContinue)) {
        $launcherJavaHome = Split-Path $releaseFile.FullName -Parent
        $javaPath = Join-Path $launcherJavaHome 'bin\java.exe'
        if (-not (Test-Path -LiteralPath $javaPath)) { continue }
        $releaseText = [System.IO.File]::ReadAllText($releaseFile.FullName)
        $match = [regex]::Match($releaseText, '(?m)^JAVA_VERSION="([^"]+)"')
        $launcherRuntimeRecords += [pscustomobject]@{
            home = $launcherJavaHome; version = $(if ($match.Success) { $match.Groups[1].Value } else { $null })
            java = Get-ExecutableInfo $javaPath
            javac_present = Test-Path -LiteralPath (Join-Path $launcherJavaHome 'bin\javac.exe')
        }
    }
}

# Record only save directory names and counts; no save files are opened.
$saveRecords = @()
if ($env:USERPROFILE) {
    $savedGamesRoot = Join-Path $env:USERPROFILE 'Saved Games'
    if (Test-Path -LiteralPath $savedGamesRoot) {
        foreach ($saveDirectory in @(Get-ChildItem -LiteralPath $savedGamesRoot -Directory | Where-Object { $_.Name -match '(?i)kingdom|kcd' })) {
            $saveRecords += [pscustomobject]@{
                path = $saveDirectory.FullName
                children = @(Get-ChildItem -LiteralPath $saveDirectory.FullName -Directory | Select-Object -ExpandProperty Name)
            }
        }
    }
}
$kits = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue
$sdkRecords = @()
if ($kits -and $kits.KitsRoot10) {
    $includeRoot = Join-Path $kits.KitsRoot10 'Include'
    if (Test-Path -LiteralPath $includeRoot) { $sdkRecords = @(Get-ChildItem -LiteralPath $includeRoot -Directory | Select-Object -ExpandProperty Name) }
}
$os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$osCaption = $null
try { $osCaption = (Get-CimInstance Win32_OperatingSystem).Caption } catch { }
$gpuRecords = @()
try { $gpuRecords = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM, PNPDeviceID) }
catch { $discoveryWarnings.Add('GPU inventory unavailable: ' + $_.Exception.Message) }
$snapshot = [pscustomobject][ordered]@{
    schema_version = 1
    captured_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    read_only_discovery = $true
    os = [pscustomobject]@{ caption = $osCaption; registry_product_name = $os.ProductName; display_version = $os.DisplayVersion; build = $os.CurrentBuild; revision = $os.UBR; architecture = $env:PROCESSOR_ARCHITECTURE }
    gpu = $gpuRecords
    tool_commands = $commands
    vswhere = $vswherePath
    visual_studio = $visualStudio
    windows_sdk = [pscustomobject]@{ root = $(if ($kits) { $kits.KitsRoot10 } else { $null }); versions = $sdkRecords }
    java = [pscustomobject]@{ java_home_env = $env:JAVA_HOME; path_java_version = Get-VersionOutput $javaCommand @('-version'); jdks = $jdkRecords; launcher_runtimes = $launcherRuntimeRecords }
    steam = [pscustomobject]@{ roots = @($steamRoots); libraries = @($steamLibraries); relevant_apps = $gameRecords }
    minecraft = $minecraftRecords
    save_directories = $saveRecords
    warnings = @($discoveryWarnings)
}
$json = $snapshot | ConvertTo-Json -Depth 20
if ($OutputPath) {
    $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path $resolvedOutput -Parent
    [void][System.IO.Directory]::CreateDirectory($parent)
    [System.IO.File]::WriteAllText($resolvedOutput, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}
if ($AsObject) { return $snapshot }
Write-Output $json
