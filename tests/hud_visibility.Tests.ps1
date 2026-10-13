#Requires -Version 7.3
# Exercise production lifecycle/cleanup with simulated engine receipts only.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudVisibility.ps1')
$testRoot=Join-Path $PSScriptRoot ('../runtime/evidence/hud-visibility-controller-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$checks=0;$failures=[Collections.Generic.List[string]]::new()
function Check($Condition,[string]$Message){$script:checks++;if(-not $Condition){$script:failures.Add($Message)}}
function Parse-Source([string]$Path){
    $errors=$null;$tokens=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw "Test source did not parse: $Path"};return $ast
}
# Reuse the real schema/run log filter without dot-sourcing game HTTP helpers.
$helpers=Parse-Source (Join-Path $PSScriptRoot '../scripts/KcdToolsProbeHelpers.ps1')
$filter=$helpers.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-MineComeProbeReceipts'},$true)
. ([scriptblock]::Create($filter.Extent.Text))
function Get-MineComeToolsConsoleBinding {}
function New-MineComeProbeRun($Context,$Name,$Source,$Entry){
    if($script:case.behavior -eq 'probe_failure'){throw 'simulated probe preparation failure'}
    $directory=Join-Path $script:testRoot $script:case.name
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $script:activeRun=[guid]::NewGuid().ToString('N')
    [pscustomobject]@{Run=$script:activeRun;Directory=$directory;Offset=0;SourceHash=('b'*64);SnapshotHash=('b'*64)}
}
function Invoke-MineComeProbeConsole($Context,[string]$Command){
    $script:commands.Add($Command)
    if($Command -match 'EndHudVisibility'){
        $script:ended=$true
        if($script:case.behavior -eq 'end_transport_failure'){throw 'simulated End transport failure'}
    }
    if($Command -match 'BeginHudVisibility' -and $script:case.behavior -eq 'begin_transport_failure'){throw 'simulated ambiguous Begin transport failure'}
}
function Read-MineComeProbeLog($Context,$Offset){
    $hidden=$script:case.original -eq 0
    $applied=@{schema=1;run=$script:activeRun;stage='applied';original_hud=$script:case.original;current_hud=0;requested_hud=0;active=$true;applied=$true;already_hidden=$hidden;owned_write=(-not $hidden);write_attempted=(-not $hidden);timer_armed=$true;duration_ms=$script:case.duration}
    $terminal=@{schema=1;run=$script:activeRun;stage='terminal';original_hud=$script:case.original;current_hud=$script:case.original;requested_hud=0;active=$false;applied=$true;already_hidden=$hidden;owned_write=(-not $hidden);write_attempted=(-not $hidden);timer_armed=$false;duration_ms=$script:case.duration;restored=$true;restore_result=$(if($hidden){'already_hidden'}else{'restored'});expired=$false;reason='requested_end';timer_cancelled=$true}
    foreach($key in $script:case.applied.Keys){$applied[$key]=$script:case.applied[$key]}
    foreach($key in $script:case.terminal.Keys){$terminal[$key]=$script:case.terminal[$key]}
    $records=@($applied)
    if($script:case.behavior -eq 'duplicate_applied'){$records+=@($applied)}
    if($script:case.behavior -in @('expired_before_work','rollback_before_work')){$records+=@($terminal)}
    if($script:ended -and $script:case.behavior -ne 'missing_terminal'){$records+=@($terminal)}
    return (($records | ForEach-Object {'[MineComeHudVisibility] '+($_ | ConvertTo-Json -Compress -Depth 5)}) -join "`n")+"`n"
}
function Case([string]$Name,[hashtable]$Applied=@{},[hashtable]$Terminal=@{},[int]$Original=1,[bool]$StartFails=$false,[bool]$Restored=$true,[bool]$Valid=$false,[string]$Behavior='normal',[int]$Duration=120000){
    @{name=$Name;applied=$Applied;terminal=$Terminal;original=$Original;startFails=$StartFails;restored=$Restored;valid=$Valid;behavior=$Behavior;duration=$Duration}
}
$cases=@(
    (Case 'visible_success' -Valid $true),
    (Case 'already_hidden_success' -Original 0 -Valid $true),
    (Case 'short_lease_success' -Duration 5000 -Valid $true),
    (Case 'bad_apply_readback' -Applied @{current_hud=1} -StartFails $true),
    (Case 'bad_original_type' -Applied @{original_hud='1'} -StartFails $true),
    (Case 'bad_current_type' -Applied @{current_hud='0'} -StartFails $true),
    (Case 'bad_active_type' -Applied @{active='True'} -StartFails $true),
    (Case 'bad_applied_type' -Applied @{applied='True'} -StartFails $true),
    (Case 'bad_timer_type' -Applied @{timer_armed='True'} -StartFails $true),
    (Case 'bad_requested_type' -Applied @{requested_hud='0'} -StartFails $true),
    (Case 'bad_duration_type' -Applied @{duration_ms='120000'} -StartFails $true),
    (Case 'bad_duration' -Applied @{duration_ms=119999} -StartFails $true),
    (Case 'bad_owned_write' -Applied @{owned_write=$false} -StartFails $true),
    (Case 'hidden_wrong_write' -Original 0 -Applied @{owned_write=$true;write_attempted=$true} -StartFails $true),
    (Case 'wrong_run_filtered' -Applied @{run=('f'*32)} -StartFails $true),
    (Case 'wrong_schema_filtered' -Applied @{schema=2} -StartFails $true),
    (Case 'duplicate_applied' -Behavior 'duplicate_applied' -StartFails $true),
    (Case 'expired_before_work' -Behavior 'expired_before_work' -Terminal @{expired=$true;reason='timer_expired'} -StartFails $true),
    (Case 'rollback_before_work' -Behavior 'rollback_before_work' -Applied @{current_hud=1;applied=$false} -Terminal @{reason='apply_failed'} -StartFails $true),
    (Case 'expired_during_work' -Terminal @{expired=$true;reason='timer_expired'}),
    (Case 'external_change' -Terminal @{restored=$false;restore_result='external_change_preserved';current_hud=1} -Restored $false),
    (Case 'external_changed_back' -Terminal @{restore_result='already_original'}),
    (Case 'mismatched_original' -Terminal @{original_hud=0;current_hud=0} -Restored $false),
    (Case 'malformed_terminal_value' -Terminal @{current_hud='1'} -Restored $false),
    (Case 'malformed_terminal_restored' -Terminal @{restored='True'} -Restored $false),
    (Case 'malformed_terminal_active' -Terminal @{active='False'} -Restored $false),
    (Case 'malformed_terminal_expired' -Terminal @{expired='False'}),
    (Case 'malformed_terminal_timer' -Terminal @{timer_cancelled='True'}),
    (Case 'malformed_terminal_requested' -Terminal @{requested_hud='0'}),
    (Case 'malformed_terminal_duration' -Terminal @{duration_ms='120000'}),
    (Case 'mismatched_terminal_duration' -Terminal @{duration_ms=119999}),
    (Case 'wrong_terminal_owner' -Terminal @{owned_write=$false}),
    (Case 'begin_transport_failure' -Behavior 'begin_transport_failure' -StartFails $true),
    (Case 'end_transport_failure' -Behavior 'end_transport_failure' -Restored $false),
    (Case 'missing_terminal' -Behavior 'missing_terminal' -Restored $false),
    (Case 'probe_failure' -Behavior 'probe_failure' -StartFails $true -Restored $false)
)
$context=[pscustomobject]@{ProjectRoot=(Split-Path $PSScriptRoot);GamePid=42;GameStartedUtc='2026-10-13T12:00:00Z';GameHash=('c'*64)}
foreach($script:case in $cases){
    $script:ended=$false;$script:activeRun='';$script:commands=[Collections.Generic.List[string]]::new()
    $session=New-MineComeHudVisibility $context -DurationMs $case.duration
    $startFailed=$false;try{Start-MineComeHudVisibility $session}catch{$startFailed=$true}
    Check ($startFailed -eq $case.startFails) "$($case.name): unexpected Start outcome"
    Check ($session.HiddenVerified -eq (-not $case.startFails)) "$($case.name): incorrect hidden verification"
    Stop-MineComeHudVisibility $session
    Check ($session.RestorationVerified -eq $case.restored) "$($case.name): incorrect restoration claim"
    Check ($session.VisibilityValid -eq $case.valid) "$($case.name): incorrect interval validity"
    $ends=@($commands | Where-Object {$_ -match 'EndHudVisibility'}).Count
    Check ($ends -eq $(if($case.behavior -eq 'probe_failure'){0}else{1})) "$($case.name): finally must attempt End exactly once"
    Stop-MineComeHudVisibility $session
    Check (@($commands | Where-Object {$_ -match 'EndHudVisibility'}).Count -eq $ends) "$($case.name): cleanup must be idempotent"
    $rejected=$false;try{Start-MineComeHudVisibility $session}catch{$rejected=$true}
    Check $rejected "$($case.name): consumed session reused"
    $proof=Get-MineComeHudVisibilityEvidence $session
    Check ($proof.hidden_verified -eq $session.HiddenVerified -and $proof.restoration_verified -eq $session.RestorationVerified -and $proof.visibility_valid -eq $session.VisibilityValid) "$($case.name): receipt differs from lifecycle outcome"
    Check ($proof.visual_suppression_verified -eq $false -and $proof.input_suppression_provided -eq $false) "$($case.name): settings receipt must not claim visual/input proof"
    if($session.Probe){
        $saved=Get-Content -LiteralPath (Join-Path $session.Probe.Directory 'visibility-verification.json') -Raw | ConvertFrom-Json
        Check ($saved.visibility_valid -eq $session.VisibilityValid -and $saved.restoration_verified -eq $session.RestorationVerified) "$($case.name): saved outcome differs"
    }
}
$script:case=Case 'closed_before_start';$script:commands=[Collections.Generic.List[string]]::new()
$closed=New-MineComeHudVisibility $context;Stop-MineComeHudVisibility $closed
$rejected=$false;try{Start-MineComeHudVisibility $closed}catch{$rejected=$true}
Check $rejected 'An already stopped session cannot start a mutation whose cleanup will be skipped'
Check (@($commands | Where-Object {$_ -match 'BeginHudVisibility'}).Count -eq 0) 'Stopped session must never dispatch Begin'

# Execute only the actual controller finally body with simulated sessions. This
# bypasses all process/window/game setup and tests the production cleanup order.
$controller=Parse-Source (Join-Path $PSScriptRoot '../scripts/Start-HudInputLab.ps1')
$outer=$controller.Find({param($node) $node -is [Management.Automation.Language.TryStatementAst] -and $null -ne $node.Finally -and $node.Finally.Extent.Text.Contains('Stop-MineComeHudVisibility')},$true)
if(-not $outer){throw 'Production dual-resource cleanup block not found'}
$finallyText=$outer.Finally.Extent.Text
$cleanup=[scriptblock]::Create($finallyText.Substring(1,$finallyText.Length-2))
function Stop-MineComeHudVisibility($Session){$script:cleanupCalls.Add('hud');if($script:cleanupCase -eq 'hud_stop_throws'){throw 'simulated HUD receipt save failure'}}
function Stop-MineComeHudGpuBudget($Session){$script:cleanupCalls.Add('gpu');if($script:cleanupCase -eq 'gpu_stop_throws'){throw 'simulated GPU End failure'}}
function Get-MineComeHudVisibilityEvidence($Session){if($script:cleanupCase -eq 'hud_evidence_throws'){throw 'simulated HUD evidence failure'};@{visibility_valid=$Session.VisibilityValid}}
function Get-MineComeHudGpuBudgetEvidence($Session){@{budget_valid=$Session.BudgetValid}}
foreach($script:cleanupCase in @('success','hud_stop_throws','hud_evidence_throws','gpu_stop_throws','body_failed','hud_invalid','gpu_invalid')){
    $script:cleanupCalls=[Collections.Generic.List[string]]::new()
    $hostHudSession=[pscustomobject]@{VisibilityValid=($cleanupCase -ne 'hud_invalid');Failure=$null}
    $hostBudgetSession=[pscustomobject]@{BudgetValid=($cleanupCase -ne 'gpu_invalid');Failure=$null}
    $hostHudEvidence=$null;$hostBudgetEvidence=$null;$HideHostHud=$true;$HostGpuBudget=$true
    $LiveMouse=$false;$liveMouseGuestVerified=$false;$pointerEventsApplied=0
    $producerExitObserved=$true;$producerExitCode=0
    $passed=$cleanupCase -ne 'body_failed';$bodyPassed=$passed;$failure=if($passed){$null}else{'simulated input body failure'}
    $run='c'*32;$Mode='Live';$PointerFixture=$false;$DelayFixture=$false;$BackgroundTrial=$false;$OffscreenPresentation=$true;$OffscreenTrial=$false
    $directory=Join-Path $testRoot ('finally-'+$cleanupCase);[IO.Directory]::CreateDirectory($directory) | Out-Null
    $targetPid=42;$targetStart='12345';$fixtureHash=$null;$armEvidence=$true;$Width=1280;$Height=720;$GuiScale=2;$expires=180001
    $client=[pscustomobject]@{};$client | Add-Member -MemberType ScriptMethod -Name Dispose -Value {$script:cleanupCalls.Add('client_disposed')}
    $producer=[pscustomobject]@{};$producer | Add-Member -MemberType ScriptMethod -Name Dispose -Value {$script:cleanupCalls.Add('producer_disposed')}
    $fixture=[pscustomobject]@{};$fixture | Add-Member -MemberType ScriptMethod -Name Dispose -Value {$script:cleanupCalls.Add('fixture_disposed')}
    $cleanupThrew=$false;try{. $cleanup}catch{$cleanupThrew=$true}
    Check ($cleanupCalls.Contains('hud') -and $cleanupCalls.Contains('gpu')) "${cleanupCase}: both resources need cleanup despite another resource failure"
    Check ($cleanupCalls.IndexOf('hud') -lt $cleanupCalls.IndexOf('gpu')) "${cleanupCase}: original HUD restored before host FPS budget"
    Check ($cleanupCalls.Contains('client_disposed') -and $cleanupCalls.Contains('fixture_disposed') -and $cleanupCalls.Contains('producer_disposed')) "${cleanupCase}: process wrappers and retained producer always disposed"
    Check ($cleanupThrew -or ($passed -eq ($cleanupCase -eq 'success'))) "${cleanupCase}: failed body/cleanup must not become a passing input run"
    if(Test-Path -LiteralPath (Join-Path $directory 'verification.json')){
        $saved=Get-Content -LiteralPath (Join-Path $directory 'verification.json') -Raw | ConvertFrom-Json
        Check (($saved.result -ceq 'passed') -eq ($cleanupCase -eq 'success')) "${cleanupCase}: persisted controller outcome differs"
        if($cleanupCase -eq 'body_failed'){Check ($saved.body_passed -eq $false -and $saved.failure -ceq 'simulated input body failure') 'Successful restoration cannot overwrite failed input evidence'}
    }
}
if($failures.Count){$failures | ForEach-Object {Write-Output "FAIL $_"};throw "HUD visibility lifecycle failed $($failures.Count)/$checks checks; evidence=$testRoot"}
Write-Output "HUD_VISIBILITY_CONTROLLER_TEST_PASS checks=$checks simulated_console_only=true evidence=$testRoot"
