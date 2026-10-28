#Requires -Version 7.3
# Production guards and physical-edge routing, without starting either game.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action}catch{$threw=$true};Check $threw $Message}
function Parse-Production([string]$Relative){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Relative),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Syntax errors in $Relative"
    return $ast
}
function Import-Function($Ast,[string]$Name){
    $node=$Ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true)
    if(-not $node){throw "Production function missing: $Name"}
    [scriptblock]::Create($node.Extent.Text)
}
$controller=Parse-Production 'scripts/Start-HudInputLab.ps1'
$arm=Parse-Production 'scripts/Arm-HudStream.ps1'
$child=Parse-Production 'scripts/Run-HudStreamClient.ps1'
foreach($name in @('Assert-HudStoneMode','Assert-HudStoneConfiguration','Update-HudAimedPermitLedger','Invoke-HudAimedWorldClicks','Assert-HudAimedWorldClicks','Get-HudAimedCurrentDecline')){. (Import-Function $controller $name)}
. (Import-Function $arm 'Assert-HudAimedArmMode')
. (Join-Path $root 'scripts/AimedWorldClicks.ps1')
. (Join-Path $root 'scripts/HudWorldClicks.ps1')

function Config {
    @{Mode='Live';AimedStone=$true;StoneFixture=$false;StoneLive=$true;LiveMouse=$true;OffscreenPresentation=$true;OffscreenTrial=$false;HostGpuBudget=$true;PointerFixture=$false;DelayFixture=$false;BackgroundTrial=$false;HideHostHud=$false;WorldClicks=$true;SelectiveMouse=$true;SelectiveRevision=3}
}
$config=Config;Assert-HudStoneConfiguration @config;Check $true 'Explicit capped revision3 aimed profile accepted'
foreach($flag in @('StoneLive','WorldClicks','SelectiveMouse','LiveMouse','OffscreenPresentation','HostGpuBudget')){
    $config=Config;$config[$flag]=$false;Reject {Assert-HudStoneConfiguration @config} "Aimed profile accepted missing $flag"
}
foreach($flag in @('StoneFixture','OffscreenTrial','PointerFixture','DelayFixture','BackgroundTrial')){
    $config=Config;$config[$flag]=$true;Reject {Assert-HudStoneConfiguration @config} "Aimed profile accepted $flag"
}
foreach($revision in @(1,2)){$config=Config;$config.SelectiveRevision=$revision;Reject {Assert-HudStoneConfiguration @config} 'Earlier renderer capture revision accepted'}
$config=Config;$config.Mode='Fixture';Reject {Assert-HudStoneConfiguration @config} 'Aimed mode accepted standalone fixture target'
$armGuardText=@();foreach($statement in $arm.EndBlock.Statements){
    if($statement -is [Management.Automation.Language.IfStatementAst]){$armGuardText+=$statement.Extent.Text}
    elseif($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text -ceq '$inputProtocol'){continue}
    elseif($armGuardText.Count){break}
}
$armGuards=[scriptblock]::Create($armGuardText -join "`n")
function Check-Arm($Config){$InputMode=$true;$PhysicalMovement=$false;$WalkingAimed=$false;foreach($key in $Config.Keys){Set-Variable $key $Config[$key]};& $armGuards}
$config=Config;Check-Arm $config;Check $true 'Direct arming accepts explicit aimed revision3 mode'
foreach($flag in @('StoneLive','WorldClicks','SelectiveMouse','LiveMouse','OffscreenPresentation')){$config=Config;$config[$flag]=$false;Reject {Check-Arm $config} "Direct aimed arm accepted missing $flag"}
foreach($revision in @(1,2)){$config=Config;$config.SelectiveRevision=$revision;Reject {Check-Arm $config} 'Direct aimed arm accepted earlier capture revision'}

function Ready {
    [pscustomobject]@{ui_input_stone_bridge=$true;ui_input_stone_fixture=$false;ui_input_stone_live=$true;ui_input_aimed_stone_bridge=$true}
}
$ready=Ready;Assert-HudStoneMode $ready $false $true $true;Assert-HudAimedArmMode $ready $true;Check $true 'Aimed readiness accepted by both controller and arm'
Reject {Assert-HudStoneMode $ready $false $true} 'Legacy controller accepted aimed readiness'
Reject {Assert-HudAimedArmMode $ready $false} 'Direct legacy arm accepted aimed readiness'
foreach($value in @($false,'true',1,$null)){
    $ready=Ready;$ready.ui_input_aimed_stone_bridge=$value
    Reject {Assert-HudStoneMode $ready $false $true $true} 'Aimed controller accepted missing/invalid marker'
    Reject {Assert-HudAimedArmMode $ready $true} 'Aimed arm accepted missing/invalid marker'
}
$ready=Ready;$ready.PSObject.Properties.Remove('ui_input_aimed_stone_bridge')
Reject {Assert-HudStoneMode $ready $false $true $true} 'Aimed controller accepted no marker'
Reject {Assert-HudAimedArmMode $ready $true} 'Aimed arm accepted no marker'
Assert-HudStoneMode $ready $false $true;Assert-HudAimedArmMode $ready $false;Check $true 'Older legacy receipts still accepted only by legacy mode'

# Execute the child profile guards independently from its Gradle launch.
$try=$child.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]} | Select-Object -First 1
$guards=@();foreach($statement in $try.Body.Statements){
    if($statement -is [Management.Automation.Language.IfStatementAst]){$guards+=$statement.Extent.Text}
    elseif($guards.Count){break}
}
Check ($guards.Count -ge 10) 'Actual child guards were isolated after the profile helper calls'
. (Import-Function $child 'Assert-HudGroundChildMode')
$childGuards=[scriptblock]::Create($guards -join "`n")
function Child-Config {
    @{AimedStone=$true;StoneLive=$true;StoneFixture=$false;InputMode=$true;LiveMouse=$true;OffscreenPresentation=$true;InputFixture=$false;InputOffscreenTrial=$false;InputPointerFixture=$false;InputDelayFixture=$false;InputBackgroundTrial=$false;StoneTokenFile='owned-token'
        WalkingAimed=$false;ExtendedWalking=$false;PhysicalMovement=$false;PhysicalMovementFixture=$false;Standalone=$false;GroundMovementFixture=$false;GroundMovementCoupled=$false;HostViewFile='';GroundPatchFile='';MovementTraceFile=''}
}
function Check-Child($Config){foreach($key in $Config.Keys){Set-Variable $key $Config[$key]};$PSBoundParameters=@{};& $childGuards}
$config=Child-Config;Check-Child $config;Check $true 'Child accepts aimed live profile'
foreach($flag in @('StoneLive','InputMode','LiveMouse','OffscreenPresentation')){$config=Child-Config;$config[$flag]=$false;Reject {Check-Child $config} "Aimed child accepted missing $flag"}
foreach($flag in @('StoneFixture','InputFixture','InputOffscreenTrial','InputPointerFixture','InputDelayFixture','InputBackgroundTrial')){$config=Child-Config;$config[$flag]=$true;Reject {Check-Child $config} "Aimed child accepted $flag"}
$childFlag=$child.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text -match '^if\(\$AimedStone\)' -and $n.Extent.Text.Contains("'-PminecomeHudAimedStoneBridge'")},$true)
Check ($null -ne $childFlag) 'Explicit guest argument found'
$WalkingAimed=$false
foreach($AimedStone in @($false,$true)){$arguments=@();. ([scriptblock]::Create($childFlag.Extent.Text));Check ($arguments.Count -eq [int]$AimedStone) 'Guest aiming property requires explicit opt-in'}

# Model native journal and physical log reads, while running the actual selector,
# parser, dispatch loop and final correlation. No OS or engine input is generated.
$run='0123456789abcdef0123456789abcdef'
$context=[pscustomobject]@{GamePid=42;GameStartedUtc=[datetime]'2026-10-13T00:00:00Z'}
function State {
    [pscustomobject]@{Run=$run;Context=$context;Sequence=0L;Failure=$null;Clicks=[Collections.Generic.List[object]]::new();AimedLedger=(New-MineComeAimedClickLedger $run);PermitReader=[pscustomobject]@{Lines=@()};Lines=@()}
}
function Session {
    [pscustomobject]@{Run=$run;Context=$context;Intents=[Collections.Generic.List[object]]::new();ExpiresUtcMs=([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+30000);LastIntentUtcMs=0L}
}
function Read-MineComeHudWorldClickLines($State){$lines=$State.Lines;$State.Lines=@();$lines}
$script:decline=$null;$script:throwDispatch=$false;$script:dispatches=0
function Get-MineComeHudWorldCurrentDecline($State,$Session,$Click){$script:decline}
function Send-MineComeHudAimedIntent($Session,$Selection,$Click,[scriptblock]$BeforeDispatch){
    $reason=& $BeforeDispatch
    if($reason){return [pscustomobject]@{accepted=$false;reason=$reason}}
    $script:dispatches++
    if($script:throwDispatch){throw 'Ambiguous dispatch; never retry'}
    $record=[pscustomobject]@{accepted=$true;ordinal=$Session.Intents.Count+1;request_id=$Selection.sequence;sequence=$Selection.sequence;action=$Selection.action;arena_id=$Selection.arena;permit_id=$Selection.permit;edge_utc_ms=$Selection.edge_utc_ms;installed_utc_ms=$Selection.installed_utc_ms}
    $Session.Intents.Add($record);$record
}
function ClickLine([long]$Sequence,[long]$Utc,[int]$Action=1){'[MineComeWorldInput] '+([ordered]@{schema=1;run=$run;sequence=$Sequence;utc_ms=$Utc;action=$Action}|ConvertTo-Json -Compress)}
function PermitLine([long]$Id,[long]$Utc){"AIM_PERMIT_READY run=$run arena=1 permit=$Id installed_utc_ms=$Utc"}
$state=State;$session=Session;$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$state.PermitReader.Lines=@((PermitLine 1 ($now-80)),(PermitLine 2 ($now-20)))
$state.Lines=@((ClickLine 1 ($now-50)))
Invoke-HudAimedWorldClicks $state $session
Check ($session.Intents.Count -eq 1 -and $session.Intents[0].permit_id -ceq '1' -and $state.Clicks[0].status -ceq 'sent') 'Only the permit acknowledged before the physical edge was sent'
Assert-HudAimedWorldClicks $state $session;Check $true 'Exact edge, permit and native dispatch correlation accepted'
$session.Intents[0].permit_id='2';Reject {Assert-HudAimedWorldClicks $state $session} 'Changed permit accepted by controller evidence';$session.Intents[0].permit_id='1'
$session.Intents[0].edge_utc_ms++;Reject {Assert-HudAimedWorldClicks $state $session} 'Changed physical edge accepted by controller evidence';$session.Intents[0].edge_utc_ms--

$state=State;$session=Session;$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$state.PermitReader.Lines=@((PermitLine 1 ($now-50)));$state.Lines=@((ClickLine 1 ($now-50)))
Invoke-HudAimedWorldClicks $state $session
Check ($session.Intents.Count -eq 0 -and $state.Clicks[0].reason -ceq 'no_preclick_permit') 'Equal millisecond acknowledgement cannot authorize a physical edge'
Assert-HudAimedWorldClicks $state $session;Check $true 'An honestly declined click has complete correlation'

$state=State;$session=Session;$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$script:decline='host_not_foreground'
$state.PermitReader.Lines=@((PermitLine 1 ($now-60)));$state.Lines=@((ClickLine 1 ($now-30)))
Invoke-HudAimedWorldClicks $state $session
Check ($state.AimedLedger.LastClick -eq 1 -and $state.AimedLedger.Permits[0].used -and $session.Intents.Count -eq 0 -and $state.Clicks[0].reason -ceq 'host_not_foreground') 'Foreground refusal consumes edge and original permit without dispatch'
$script:decline=$null;$state.Lines=@((ClickLine 2 ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())))
Invoke-HudAimedWorldClicks $state $session
Check ($state.Clicks[1].reason -ceq 'no_preclick_permit' -and $session.Intents.Count -eq 0) 'Spent permit cannot be reused after foreground returns'

$state=State;$session=Session;$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$script:throwDispatch=$true
$state.PermitReader.Lines=@((PermitLine 1 ($now-60)));$state.Lines=@((ClickLine 1 ($now-30)))
$before=$script:dispatches;Reject {Invoke-HudAimedWorldClicks $state $session} 'Ambiguous HTTP dispatch must fail closed'
Check ($state.AimedLedger.Permits[0].used -and $state.Clicks[0].status -ceq 'failed') 'Ambiguous dispatch preserves spent permit and failed edge record'
Reject {Invoke-HudAimedWorldClicks $state $session} 'Failed controller must not retry'
Check ($script:dispatches -eq $before+1) 'Exactly one dispatch attempt despite retry request'
$script:throwDispatch=$false

$state=State;$session=Session;$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$state.PermitReader.Lines=@((PermitLine 1 ($now-80)),(PermitLine 1 ($now-60)));$state.Lines=@((ClickLine 1 ($now-30)))
Reject {Invoke-HudAimedWorldClicks $state $session} 'Duplicated permit journal must stop admission'
Check ($state.Failure -and $session.Intents.Count -eq 0) 'Invalid native journal causes no click dispatch'
Write-Output "HUD_AIMED_CONTROLLER_TESTS_PASS checks=$script:checks no_game_or_process_started=true"
