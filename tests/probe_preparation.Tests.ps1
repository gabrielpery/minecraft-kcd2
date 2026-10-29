# Shared helper preparation/dispatch contract; all engine calls are mocked.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/KcdToolsProbeHelpers.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($name in @('New-MineComeProbeRun','Initialize-MineComeProbeRun')){
    $definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
    Invoke-Expression $definition.Extent.Text
}
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
function Assert-MineComeProbeContext($Context){if($script:changed){throw 'Captured tools process identity changed.'}}
function Invoke-MineComeProbeConsole($Context,[string]$Command){
    $script:commands.Add($Command)
    if($script:loadTimeout){throw 'Official tools request exceeded its absolute timeout'}
    if($Command -match '\[MineComeProbeContract\] ([0-9a-f]{32})'){$script:lastRun=$Matches[1]}
}
function Read-MineComeProbeLog($Context,[long]$Offset){return "[MineComeProbeContract] $script:lastRun true`n"}
$fixture=Join-Path $root ('runtime/evidence/probe-preparation-fixture-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory((Join-Path $fixture 'runtime/evidence'))
$log=Join-Path $fixture 'game.log';[IO.File]::WriteAllText($log,'captured original extent')
$context=[pscustomobject]@{ProjectRoot=$fixture;GameLog=$log;GamePid=123;GameStartedUtc=[datetime]::SpecifyKind([datetime]'2026-10-29T20:00:00',[DateTimeKind]::Utc)}
$module=Join-Path $root 'kcd2/probes/ground_corridor.lua'
$script:changed=$false;$script:loadTimeout=$false;$script:lastRun='';$script:commands=[Collections.Generic.List[string]]::new()
try{
    $probe=New-MineComeProbeRun $context 'prepare-test' $module 'SampleGroundCorridor' -PrepareOnly
    Check ($script:commands.Count -eq 0 -and -not $probe.FunctionReloadVerified) 'Preparation makes no engine calls'
    Check ((Test-Path -LiteralPath $probe.Snapshot) -and (Get-Item -LiteralPath $probe.Snapshot).IsReadOnly) 'Immutable source exists before dispatch'
    Initialize-MineComeProbeRun $context $probe
    Check ($script:commands.Count -eq 2 -and $probe.FunctionReloadVerified) 'Explicit initialization preserves load/flush contract'
    Reject {Initialize-MineComeProbeRun $context $probe} 'Completed load cannot repeat'
    $before=$script:commands.Count
    $default=New-MineComeProbeRun $context 'default-test' $module 'SampleGroundCorridor'
    Check ($default.FunctionReloadVerified -and $script:commands.Count -eq $before+2) 'Default callers still initialize immediately'
    $probe=New-MineComeProbeRun $context 'timeout-test' $module 'SampleGroundCorridor' -PrepareOnly
    $script:loadTimeout=$true
    Reject {Initialize-MineComeProbeRun $context $probe} 'Ambiguous module timeout propagated'
    $before=$script:commands.Count
    Reject {Initialize-MineComeProbeRun $context $probe} 'Ambiguous module timeout cannot be retried'
    Check ($script:commands.Count -eq $before -and -not $probe.FunctionReloadVerified -and (Test-Path $probe.Snapshot)) 'Failed preparation remains available for evidence'
    $script:loadTimeout=$false
    $probe=New-MineComeProbeRun $context 'changed-test' $module 'SampleGroundCorridor' -PrepareOnly
    $context.GamePid=124
    Reject {Initialize-MineComeProbeRun $context $probe} 'Prepared target PID cannot change'
    $context.GamePid=123;$context.GameStartedUtc=$context.GameStartedUtc.AddSeconds(1)
    Reject {Initialize-MineComeProbeRun $context $probe} 'Prepared target start cannot change'
    $context.GameStartedUtc=$context.GameStartedUtc.AddSeconds(-1)
    (Get-Item -LiteralPath $probe.Snapshot).IsReadOnly=$false
    [IO.File]::AppendAllText($probe.Snapshot,"`n-- changed")
    Reject {Initialize-MineComeProbeRun $context $probe} 'Changed prepared bytes cannot dispatch'
    Write-Output "PROBE_PREPARATION_TESTS_PASS checks=$script:checks no_game_started=true"
}finally{
    $resolved=[IO.Path]::GetFullPath($fixture);$allowed=[IO.Path]::GetFullPath((Join-Path $root 'runtime/evidence'))+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^probe-preparation-fixture-[0-9a-f]{32}$'){throw 'Fixture cleanup escaped owned evidence root'}
    Get-ChildItem -LiteralPath $resolved -File -Recurse | ForEach-Object {$_.IsReadOnly=$false}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
