# Original PowerShell 5.1-compatible bootstrap. Uses existing runtimes only.
# Dot-source from a launch helper; invoke only when its current host is <7.
# No shell command interpolation, installation, elevation or game operations.
function ConvertTo-MineComeWindowsArgument([string]$Value) {
    # Windows argv quoting: preserve spaces, empty values, quotes and trailing
    # backslashes without asking another shell to interpret argument contents.
    $result=[Text.StringBuilder]::new();[void]$result.Append('"');$slashes=0
    foreach($character in $Value.ToCharArray()){
        if($character -eq '\'){$slashes++;continue}
        if($character -eq '"'){
            [void]$result.Append('\',2*$slashes+1);[void]$result.Append('"')
        }else{
            [void]$result.Append('\',$slashes);[void]$result.Append($character)
        }
        $slashes=0
    }
    [void]$result.Append('\',2*$slashes);[void]$result.Append('"')
    return $result.ToString()
}
function Get-MineComePowerShell7 {
    $candidates=[Collections.Generic.List[string]]::new()
    if($env:USERPROFILE){$candidates.Add((Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe'))}
    $programFiles=[Environment]::GetFolderPath('ProgramFiles')
    if($programFiles){$candidates.Add((Join-Path $programFiles 'PowerShell\7\pwsh.exe'))}
    foreach($command in @(Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue)){$candidates.Add($command.Source)}
    foreach($candidate in @($candidates|Select-Object -Unique)){
        if(-not(Test-Path -LiteralPath $candidate -PathType Leaf)){continue}
        $info=[Diagnostics.ProcessStartInfo]::new([IO.Path]::GetFullPath($candidate))
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.Arguments='-NoLogo -NoProfile -NonInteractive -Command "[Console]::Write($PSVersionTable.PSVersion.Major)"'
        $probe=[Diagnostics.Process]::new();$probe.StartInfo=$info
        try{
            if(-not$probe.Start()){continue}
            $output=$probe.StandardOutput.ReadToEndAsync();$errors=$probe.StandardError.ReadToEndAsync()
            if(-not$probe.WaitForExit(5000)){
                $probe.Kill();[void]$probe.WaitForExit(2000);continue
            }
            $major=$output.GetAwaiter().GetResult();$errorText=$errors.GetAwaiter().GetResult()
            $majorNumber=0
            if($probe.ExitCode -eq 0 -and $errorText.Length -eq 0 -and
                [int]::TryParse($major,[ref]$majorNumber) -and $majorNumber -ge 7){
                return $info.FileName
            }
        }catch{
            # An unavailable fallback is not an installer request.
        }finally{
            try{if($probe.Id -and -not$probe.HasExited){$probe.Kill();[void]$probe.WaitForExit(2000)}}catch{}
            $probe.Dispose()
        }
    }
    throw 'An existing PowerShell 7 runtime was not found. No installation or administrator access was attempted.'
}
function Invoke-MineComePowerShell7([string]$ScriptPath,[Collections.IDictionary]$BoundParameters) {
    $hostPath=Get-MineComePowerShell7
    $arguments=[Collections.Generic.List[string]]::new()
    foreach($argument in @('-NoLogo','-NoProfile','-File',[IO.Path]::GetFullPath($ScriptPath))){$arguments.Add($argument)}
    foreach($name in @('GameRoot','Level','JavaHome','BundleDirectory','PreflightOnly','WithoutMods')){
        if($BoundParameters.Keys -notcontains $name){continue}
        $value=$BoundParameters[$name]
        if($name -eq 'PreflightOnly' -or $name -eq 'WithoutMods'){
            $arguments.Add('-'+$name+':$'+([bool]$value).ToString().ToLowerInvariant())
        }else{
            $arguments.Add('-'+$name);$arguments.Add([string]$value)
        }
    }
    $quoted=@($arguments|ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
    $info=[Diagnostics.ProcessStartInfo]::new($hostPath)
    # No CREATE_NEW_CONSOLE or CREATE_NO_WINDOW: share the user's existing
    # console, matching a direct native pwsh call and preserving visible errors.
    $info.UseShellExecute=$false;$info.CreateNoWindow=$false;$info.Arguments=[string]::Join(' ',$quoted)
    # Standard handles inherit the user's current console. Only the exit code
    # is returned through PowerShell's pipeline; child output stays visible.
    $child=[Diagnostics.Process]::new();$child.StartInfo=$info
    try{
        if(-not$child.Start()){throw 'PowerShell 7 forwarding did not start.'}
        $child.WaitForExit();return $child.ExitCode
    }finally{$child.Dispose()}
}
