#Requires -Version 7.3
# Test the controller lifecycle with simulated console receipts; no game access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudGpuBudget.ps1')
$testRoot=Join-Path $PSScriptRoot ('../runtime/evidence/hud-budget-controller-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$checks=0
function Check($Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Get-MineComeToolsConsoleBinding {}
function New-MineComeProbeRun($Context,$Name,$Source,$Entry){
    if($script:scenario -eq 'probe_failure'){throw 'simulated probe preparation failure'}
    $directory=Join-Path $script:testRoot $script:scenario
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    [pscustomobject]@{Run=('a'*32);Directory=$directory;Offset=0;SourceHash=('b'*64);SnapshotHash=('b'*64)}
}
function Invoke-MineComeProbeConsole($Context,[string]$Command){
    $script:commands.Add($Command)
    if($Command -match 'EndHudGpuBudget'){
        $script:ended=$true
        if($script:scenario -eq 'end_transport_failure'){throw 'simulated End transport failure'}
    }
    if($Command -match 'BeginHudGpuBudget' -and $script:scenario -eq 'begin_transport_failure'){throw 'simulated ambiguous Begin transport failure'}
}
function Read-MineComeProbeLog($Context,$Offset){'simulated log; no game calls'}
function Read-MineComeHudGpuBudgetReceipts($Session){
    $applied=[pscustomobject]@{stage='applied';current_fps=60;active=$true;timer_armed=$true;duration_ms=120000;original_fps=$script:original}
    $terminal=[pscustomobject]@{stage='terminal';restored=$true;active=$false;current_fps=$script:original;original_fps=$script:original;restore_result='restored';expired=$false;reason='requested_end';timer_cancelled=$true}
    if($script:scenario -eq 'bad_apply'){$applied.current_fps=144}
    if($script:scenario -in @('expired','expired_before_work')){$terminal.expired=$true;$terminal.reason='timer_expired';$terminal.timer_cancelled=$false}
    if($script:scenario -eq 'external_change'){$terminal.restored=$false;$terminal.current_fps=90;$terminal.restore_result='external_change'}
    if($script:scenario -eq 'mismatched_original'){$terminal.original_fps=144;$terminal.current_fps=144}
    if($script:ended){
        if($script:scenario -eq 'missing_terminal'){return @($applied)}
        return @($applied,$terminal)
    }
    if($script:scenario -eq 'expired_before_work'){return @($applied,$terminal)}
    return @($applied)
}
$context=[pscustomobject]@{ProjectRoot=(Split-Path $PSScriptRoot);GamePid=42;GameStartedUtc='2026-10-13T12:00:00Z';GameHash=('c'*64)}
foreach($case in @('success_uncapped','success_capped','bad_apply','expired_before_work','expired','external_change','mismatched_original','begin_transport_failure','end_transport_failure','missing_terminal','probe_failure')){
    $script:scenario=$case;$script:ended=$false;$script:original=if($case -eq 'success_capped'){144}else{-1}
    $script:commands=[Collections.Generic.List[string]]::new()
    $session=New-MineComeHudGpuBudget $context
    $startFailed=$false
    try{Start-MineComeHudGpuBudget $session}catch{$startFailed=$true}
    $expectStartFailure=$case -in @('bad_apply','expired_before_work','begin_transport_failure','probe_failure')
    Check ($startFailed -eq $expectStartFailure) "${case}: unexpected Start outcome"
    Check ($session.CapVerified -eq (-not $expectStartFailure)) "${case}: unverified cap allowed dependent work"
    Stop-MineComeHudGpuBudget $session
    $expectedRestored=$case -notin @('external_change','mismatched_original','end_transport_failure','missing_terminal','probe_failure')
    Check ($session.RestorationVerified -eq $expectedRestored) "${case}: incorrect restoration claim"
    Check ($session.BudgetValid -eq ($case -in @('success_uncapped','success_capped'))) "${case}: invalid cap interval accepted"
    $endCount=@($script:commands | Where-Object {$_ -match 'EndHudGpuBudget'}).Count
    Check ($endCount -eq $(if($case -eq 'probe_failure'){0}else{1})) "${case}: rollback was not dispatched exactly once"
    Stop-MineComeHudGpuBudget $session
    Check (@($script:commands | Where-Object {$_ -match 'EndHudGpuBudget'}).Count -eq $endCount) "${case}: repeated cleanup dispatched another End"
    $duplicateRejected=$false
    try{Start-MineComeHudGpuBudget $session}catch{$duplicateRejected=$true}
    Check $duplicateRejected "${case}: immutable session was reused"
    $proof=Get-MineComeHudGpuBudgetEvidence $session
    Check ($proof.budget_valid -eq $session.BudgetValid -and $proof.restoration_verified -eq $session.RestorationVerified) "${case}: evidence differs from lifecycle outcome"
    if($session.Probe){
        $saved=Get-Content -LiteralPath (Join-Path $session.Probe.Directory 'budget-verification.json') -Raw | ConvertFrom-Json
        Check ($saved.budget_valid -eq $session.BudgetValid -and $saved.restoration_verified -eq $session.RestorationVerified) "${case}: saved evidence claims incorrect success"
    }
}
Write-Output "HUD_GPU_BUDGET_CONTROLLER_TEST_PASS checks=$checks simulated_console_only=true evidence=$testRoot"
