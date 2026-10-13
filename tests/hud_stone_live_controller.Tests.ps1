#Requires -Version 7.3
# Run production mode and receipt guards without starting a controller or game.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message='Invalid live stone evidence accepted'){
    $rejected=$false;try{& $Action}catch{$rejected=$true}
    Check $rejected $Message
}
function Parse-Production([string]$Relative){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Relative),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Syntax errors in $Relative"
    return $ast
}
function Get-ProductionFunction($Ast,[string]$Name){
    $node=$Ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true)
    if(-not $node){throw "Production function missing: $Name"}
    return [scriptblock]::Create($node.Extent.Text)
}
$controller=Parse-Production 'scripts/Start-HudInputLab.ps1'
. (Get-ProductionFunction $controller 'Assert-HudStoneMode')
. (Get-ProductionFunction $controller 'Assert-HudStoneConfiguration')
. (Get-ProductionFunction $controller 'Assert-HudSelectiveArm')
. (Get-ProductionFunction $controller 'Get-HudStonePreviewAction')
. (Get-ProductionFunction $controller 'Test-HudStonePreviewEnginePlace')
. (Get-ProductionFunction $controller 'Assert-HudStoneLivePreview')
. (Get-ProductionFunction $controller 'Assert-HudWorldClickGuest')
. (Get-ProductionFunction $controller 'Assert-HudLiveArming')
. (Get-ProductionFunction $controller 'Assert-LiveMouseGuestProof')

$arming=[pscustomobject]@{host_armed=$true;input_events_applied=0}
Assert-HudLiveArming $arming $true;Check $true 'World actions can complete without any UI key events'
Reject {Assert-HudLiveArming $arming $false} 'Ordinary UI mode accepted no UI actions'
$arming.input_events_applied=2;Assert-HudLiveArming $arming $false;Check $true 'Ordinary UI activity remains accepted'
foreach($invalid in @(-1,'0',$true,$null)){$arming.input_events_applied=$invalid;Reject {Assert-HudLiveArming $arming $true} 'Invalid world UI count accepted'}
$arming.input_events_applied=0
foreach($invalid in @($false,'true',1,$null)){$arming.host_armed=$invalid;Reject {Assert-HudLiveArming $arming $true} 'World actions accepted without genuine arming'}

# Neither marker can be inferred: all three explicit Boolean fields must agree
# with the requested ordinary, fixture, or live mode.
foreach($fixtureExpected in @($false,$true)){
    foreach($liveExpected in @($false,$true)){
        foreach($bridge in @($false,$true)){
            foreach($fixture in @($false,$true)){
                foreach($live in @($false,$true)){
                    $receipt=[pscustomobject]@{ui_input_stone_bridge=$bridge;ui_input_stone_fixture=$fixture;ui_input_stone_live=$live}
                    $valid=(-not($fixtureExpected -and $liveExpected) -and $bridge -eq ($fixtureExpected -or $liveExpected) -and $fixture -eq $fixtureExpected -and $live -eq $liveExpected)
                    if($valid){Assert-HudStoneMode $receipt $fixtureExpected $liveExpected;Check $true 'Valid stone mode'}
                    else{Reject {Assert-HudStoneMode $receipt $fixtureExpected $liveExpected} 'Conflicting stone mode accepted'}
                }
            }
        }
    }
}
foreach($expectedMode in @('ordinary','fixture','live')){
    foreach($field in @('ui_input_stone_bridge','ui_input_stone_fixture','ui_input_stone_live')){
        foreach($invalid in @('true','false',0,1,$null)){
            $receipt=[pscustomobject]@{ui_input_stone_bridge=($expectedMode -ne 'ordinary');ui_input_stone_fixture=($expectedMode -eq 'fixture');ui_input_stone_live=($expectedMode -eq 'live')}
            $receipt.$field=$invalid
            Reject {Assert-HudStoneMode $receipt ($expectedMode -eq 'fixture') ($expectedMode -eq 'live')} 'Non-Boolean stone marker accepted'
        }
        $receipt=[pscustomobject]@{ui_input_stone_bridge=($expectedMode -ne 'ordinary');ui_input_stone_fixture=($expectedMode -eq 'fixture');ui_input_stone_live=($expectedMode -eq 'live')}
        $receipt.PSObject.Properties.Remove($field)
        Reject {Assert-HudStoneMode $receipt ($expectedMode -eq 'fixture') ($expectedMode -eq 'live')} 'Missing stone marker accepted'
    }
}

function Live-Configuration {
    @{Mode='Live';StoneFixture=$false;StoneLive=$true;LiveMouse=$true;OffscreenPresentation=$true;OffscreenTrial=$false;HostGpuBudget=$true;PointerFixture=$false;DelayFixture=$false;BackgroundTrial=$false;HideHostHud=$false}
}
$config=Live-Configuration;Assert-HudStoneConfiguration @config;Check $true 'Capped live mouse stone mode accepted'
$config=Live-Configuration;$config.WorldClicks=$true;Assert-HudStoneConfiguration @config;Check $true 'Explicit world clicks accepted with combined live prerequisites'
$config=Live-Configuration;$config.WorldClicks=$true;$config.SelectiveMouse=$true;Assert-HudStoneConfiguration @config;Check $true 'Explicit selective capture accepted with all combined prerequisites'
foreach($required in @('WorldClicks','StoneLive','LiveMouse','OffscreenPresentation','HostGpuBudget')){
    $config=Live-Configuration;$config.WorldClicks=$true;$config.SelectiveMouse=$true;$config[$required]=$false
    Reject {Assert-HudStoneConfiguration @config} "SelectiveMouse accepted without $required"
}
foreach($incompatible in @('StoneFixture','OffscreenTrial','PointerFixture','DelayFixture','BackgroundTrial')){
    $config=Live-Configuration;$config.WorldClicks=$true;$config.SelectiveMouse=$true;$config[$incompatible]=$true
    Reject {Assert-HudStoneConfiguration @config} "SelectiveMouse accepted with $incompatible"
}
$config=Live-Configuration;$config.WorldClicks=$true;$config.SelectiveMouse=$true;$config.Mode='Fixture';Reject {Assert-HudStoneConfiguration @config} 'Selective capture cannot target a standalone fixture'
foreach($expected in @($false,$true)){
    foreach($representation in @('direct','hashtable','json')){
        # Preserve Arm-HudStream's actual pipeline shape for the direct case.
        $makeReceipt={param($value,$missing=$false)
            $receipt=[ordered]@{schema=1;kind='minecome_hud_stream_arm_v1'}
            if(-not $missing){$receipt.selective_mouse=$value}
            if($representation -eq 'json'){return ($receipt|ConvertTo-Json|ConvertFrom-Json)}
            if($representation -eq 'hashtable'){$receipt=@{};if(-not $missing){$receipt.selective_mouse=$value}}
            Write-Output $receipt
        }
        Assert-HudSelectiveArm (& $makeReceipt $expected) $expected;Check $true 'Matching direct/stored capture arm receipt accepted'
        foreach($invalid in @((-not $expected),'true','false',0,1,$null)){Reject {Assert-HudSelectiveArm (& $makeReceipt $invalid) $expected} 'Mismatched/untyped selective arm receipt rejected'}
        Reject {Assert-HudSelectiveArm (& $makeReceipt $null $true) $expected} 'Missing selective provenance rejected'
    }
}
$bundleNode=$controller.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if(-not $BundleDirectory)') -and $n.Extent.Text.Contains('runtime/hud-compositor-selective')},$true)
$SelectiveRevision=1
Check ($null -ne $bundleNode) 'Controller has an explicit separate selective bundle default'
$bundleSelector=[scriptblock]::Create($bundleNode.Extent.Text)
foreach($bundleCase in @(
    @($true,$true,$true,'hud-compositor-selective'),@($false,$true,$true,'hud-compositor-world'),
    @($false,$false,$true,'hud-compositor-mouse'),@($false,$false,$false,'hud-compositor-input-waitfix'))){
    & {
        $SelectiveMouse=$bundleCase[0];$WorldClicks=$bundleCase[1];$LiveMouse=$bundleCase[2];$BundleDirectory=$null
        . $bundleSelector;Check ($BundleDirectory -ceq (Join-Path $root ('runtime/'+$bundleCase[3]))) 'Capture mode chooses its own matching bundle'
        $BundleDirectory='explicit-owned-bundle';. $bundleSelector;Check ($BundleDirectory -ceq 'explicit-owned-bundle') 'Explicit bundle selection preserved for downstream hash validation'
    }
}
$config=Live-Configuration;$config.WorldClicks=$true;$config.StoneLive=$false;Reject {Assert-HudStoneConfiguration @config} 'World clicks without the real combined relay accepted'
$config=Live-Configuration;$config.HideHostHud=$true;Assert-HudStoneConfiguration @config;Check $true 'Optional host HUD visibility accepted'
foreach($required in @('LiveMouse','OffscreenPresentation','HostGpuBudget')){
    $config=Live-Configuration;$config[$required]=$false
    Reject {Assert-HudStoneConfiguration @config} "StoneLive accepted without $required"
}
foreach($incompatible in @('StoneFixture','OffscreenTrial','PointerFixture','DelayFixture','BackgroundTrial')){
    $config=Live-Configuration;$config[$incompatible]=$true
    Reject {Assert-HudStoneConfiguration @config} "StoneLive accepted with $incompatible"
}
$config=Live-Configuration;$config.Mode='Fixture';Reject {Assert-HudStoneConfiguration @config} 'Fixture target accepted live stone mode'
$fixtureConfig=@{Mode='Fixture';StoneFixture=$true;StoneLive=$false;LiveMouse=$false;OffscreenPresentation=$false;OffscreenTrial=$true;HostGpuBudget=$false;PointerFixture=$false;DelayFixture=$false;BackgroundTrial=$false;HideHostHud=$false}
Assert-HudStoneConfiguration @fixtureConfig;Check $true 'Standalone fixture remains accepted before offscreen normalization'
foreach($invalidFlag in @('StoneLive','LiveMouse','HostGpuBudget','PointerFixture','DelayFixture','BackgroundTrial','HideHostHud')){
    $config=$fixtureConfig.Clone();$config[$invalidFlag]=$true
    Reject {Assert-HudStoneConfiguration @config} "StoneFixture accepted with $invalidFlag"
}
$config=$fixtureConfig.Clone();$config.Mode='Live';Reject {Assert-HudStoneConfiguration @config} 'Live target accepted stone fixture'
$config=$fixtureConfig.Clone();$config.OffscreenTrial=$false;Reject {Assert-HudStoneConfiguration @config} 'Stone fixture accepted without standalone offscreen trial'

# Exercise real child argument guards in isolation: these AST statements precede
# Gradle invocation and contain no process or file operations.
$child=Parse-Production 'scripts/Run-HudStreamClient.ps1'
$childTry=$child.EndBlock.Statements | Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]} | Select-Object -First 1
$guardStatements=@()
foreach($statement in $childTry.Body.Statements){
    if($statement -isnot [Management.Automation.Language.IfStatementAst]){break}
    $guardStatements+=$statement.Extent.Text
}
Check ($guardStatements.Count -ge 10) 'All child configuration guards extracted'
$childGuards=[scriptblock]::Create('$PSBoundParameters=@{};if($ExplicitPort){$PSBoundParameters["StonePort"]=38765}' + "`n" + ($guardStatements -join "`n"))
function Child-Configuration {
    @{StoneLive=$true;StoneFixture=$false;InputMode=$true;LiveMouse=$true;OffscreenPresentation=$true;InputFixture=$false;InputOffscreenTrial=$false;InputPointerFixture=$false;InputDelayFixture=$false;InputBackgroundTrial=$false;StoneTokenFile='owned-token-path';ExplicitPort=$true}
}
function Test-ChildConfiguration($Config){
    foreach($key in $Config.Keys){Set-Variable -Name $key -Value $Config[$key] -Scope Local}
    $PSBoundParameters=@{};if($ExplicitPort){$PSBoundParameters['StonePort']=38765}
    & $childGuards
}
$config=Child-Configuration;Test-ChildConfiguration $config;Check $true 'Child accepts explicit combined live mode'
foreach($required in @('InputMode','LiveMouse','OffscreenPresentation')){
    $config=Child-Configuration;$config[$required]=$false;Reject {Test-ChildConfiguration $config} "Child accepted missing $required"
}
$config=Child-Configuration;$config.StoneTokenFile='';Reject {Test-ChildConfiguration $config} 'Child accepted no owned token'
foreach($incompatible in @('StoneFixture','InputFixture','InputOffscreenTrial','InputPointerFixture','InputDelayFixture','InputBackgroundTrial')){
    $config=Child-Configuration;$config[$incompatible]=$true;Reject {Test-ChildConfiguration $config} "Child accepted $incompatible"
}
$config=Child-Configuration;$config.StoneLive=$false;Reject {Test-ChildConfiguration $config} 'Child accepted connection without explicit stone mode'
$config=Child-Configuration;$config.StoneLive=$false;$config.StoneTokenFile='';Reject {Test-ChildConfiguration $config} 'Child accepted explicit port without stone mode'
$config=Child-Configuration;$config.StoneLive=$false;$config.StoneTokenFile='';$config.ExplicitPort=$false;Test-ChildConfiguration $config;Check $true 'Existing live mouse child remains accepted'

# Arming has an independent guard: an explicit live controller cannot arm a
# fixture guest, and an ordinary arm cannot silently enable live stone input.
$arm=Parse-Production 'scripts/Arm-HudStream.ps1'
$markerLoop=$arm.Find({param($n)$n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Extent.Text.Contains("'ui_input_stone_bridge'")},$true)
Check ($null -ne $markerLoop) 'Independent arming markers found'
$armMarkers=[scriptblock]::Create($markerLoop.Extent.Text)
foreach($stoneLive in @($false,$true)){
    $ready=[pscustomobject]@{ui_input_stone_bridge=$stoneLive;ui_input_stone_fixture=$false;ui_input_stone_live=$stoneLive}
    & $armMarkers;Check $true 'Matching arm markers accepted'
    foreach($field in @('ui_input_stone_bridge','ui_input_stone_fixture','ui_input_stone_live')){
        foreach($invalid in @('true','false',0,1,$null)){
            $ready=[pscustomobject]@{ui_input_stone_bridge=$stoneLive;ui_input_stone_fixture=$false;ui_input_stone_live=$stoneLive};$ready.$field=$invalid
            Reject {& $armMarkers} 'Arm accepted non-Boolean stone marker'
        }
        $ready=[pscustomobject]@{ui_input_stone_bridge=$stoneLive;ui_input_stone_fixture=$false;ui_input_stone_live=$stoneLive};$ready.$field=(-not $ready.$field)
        Reject {& $armMarkers} 'Arm accepted conflicting stone marker'
        if($stoneLive){
            $ready=[pscustomobject]@{ui_input_stone_bridge=$true;ui_input_stone_fixture=$false;ui_input_stone_live=$true};$ready.PSObject.Properties.Remove($field)
            Reject {& $armMarkers} 'Live stone arm accepted missing marker'
        }
    }
}

$run='0123456789abcdef0123456789abcdef'
$foreign='fedcba9876543210fedcba9876543210'
$save='MineCome-HudStream-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
$armed="[Render thread/INFO] HUD_INPUT_ARMED run=$run fixture=false"
$stoneReady="[Render thread/INFO] HUD_STONE_READY save=$save target=BlockPos{x=2, y=64, z=0} support=BlockPos{x=2, y=63, z=0} session=1; selected inventory is unchanged"
$readyLog=$armed+"`n"+$stoneReady
function State { [pscustomobject]@{Stage=0;ArmedAtMs=0L;PlaceAtMs=0L;ConfirmedAtMs=0L;PlaceRequestId='';Save=$save} }
function Placed-State { [pscustomobject]@{Stage=1;ArmedAtMs=1000L;PlaceAtMs=3000L;ConfirmedAtMs=0L;PlaceRequestId='17';Save=$save} }
$state=State;Check ((Get-HudStonePreviewAction $state '' $run 1000) -eq 0 -and $state.ArmedAtMs -eq 0) 'No action or clock before F8 arming'
foreach($log in @($stoneReady,($readyLog.Replace($run,$foreign)),($readyLog.Replace('fixture=false','fixture=true')))){
    $state=State;Check ((Get-HudStonePreviewAction $state $log $run 1000) -eq 0 -and $state.ArmedAtMs -eq 0) 'Foreign/fixture/unarmed log cannot begin preview'
}
$state=State;Check ((Get-HudStonePreviewAction $state $readyLog $run 1000) -eq 0 -and $state.ArmedAtMs -eq 1000) 'Actual arming begins dwell clock'
Check ((Get-HudStonePreviewAction $state $readyLog $run 2999) -eq 0) 'No placement before two seconds'
Check ((Get-HudStonePreviewAction $state $armed $run 3000) -eq 0) 'No placement without owned stone readiness'
Check ((Get-HudStonePreviewAction $state ($armed+"`n"+$stoneReady.Replace($save,$save.Replace('aaaaaaaa','bbbbbbbb'))) $run 3000) -eq 0) 'Foreign save readiness refused'
Check ((Get-HudStonePreviewAction $state $readyLog $run 3000) -eq 1 -and $state.Stage -eq 0) 'Placement proposal does not claim request dispatched'
$state=Placed-State
$confirmed="[Render thread/INFO] HUD_STONE_CONFIRMED request=17 action=1 target=BlockPos{x=2, y=64, z=0} selectedSlot=0 selectedItem=minecraft:stone clientAndIntegratedServer=true"
Check ((Get-HudStonePreviewAction $state $readyLog $run 8000) -eq 0) 'Pending confirmation allowed at exact five second boundary'
foreach($log in @($readyLog,($readyLog+"`n"+$confirmed.Replace('request=17','request=18')),($readyLog+"`n"+$confirmed.Replace('action=1','action=2')))){
    Reject {Get-HudStonePreviewAction $state $log $run 8001 $true} 'Missing or unrelated Minecraft place confirmation accepted'
}
$confirmedLog=$readyLog+"`n"+$confirmed
Check ((Get-HudStonePreviewAction $state $confirmedLog $run 3500 $false) -eq 0 -and $state.ConfirmedAtMs -eq 0) 'Minecraft confirmation alone cannot start visible dwell'
Reject {Get-HudStonePreviewAction $state $confirmedLog $run 8001 $false} 'Unconfirmed engine placement accepted'
Check ((Get-HudStonePreviewAction $state $confirmedLog $run 4000 $true) -eq 0 -and $state.ConfirmedAtMs -eq 4000) 'Both actual confirmations start visible dwell'
Check ((Get-HudStonePreviewAction $state $confirmedLog $run 13999 $true) -eq 0 -and $state.ConfirmedAtMs -eq 4000) 'Break waits for ten seconds after confirmation'
Check ((Get-HudStonePreviewAction $state $confirmedLog $run 14000 $true) -eq 2 -and $state.Stage -eq 1) 'Break proposal follows actual matching confirmations'
$state.Stage=2;Check ((Get-HudStonePreviewAction $state $confirmedLog $run 14000) -eq 0) 'Completed preview never repeats actions'
foreach($stage in @(0,1,2)){
    $state=Placed-State;$state.Stage=$stage
    Check ((Get-HudStonePreviewAction $state $confirmedLog $run 21000) -eq 0) 'No new dispatch at twenty second deadline'
    Check ((Get-HudStonePreviewAction $state $confirmedLog $run 40000) -eq 0) 'No new dispatch after deadline'
}
foreach($terminal in @('HUD_INPUT_TERMINAL','HUD_STREAM_TERMINAL')){
    foreach($stage in @(0,1,2)){
        $state=Placed-State;$state.Stage=$stage
        Check ((Get-HudStonePreviewAction $state ($confirmedLog+"`n$terminal run=$run result=closed") $run 13000) -eq 0) 'Own terminal receipt suppresses further actions'
    }
}
$state=Placed-State;$state.ConfirmedAtMs=4000L;Check ((Get-HudStonePreviewAction $state ($confirmedLog+"`nHUD_INPUT_TERMINAL run=$foreign result=closed") $run 14000 $true) -eq 2) 'Foreign terminal cannot cancel owned session'
foreach($invalid in @('',($run.ToUpperInvariant()),'../other','f'*31)){$state=State;Reject {Get-HudStonePreviewAction $state $readyLog $invalid 1000} 'Invalid run accepted'}
foreach($invalid in @(-1,0)){$state=State;Reject {Get-HudStonePreviewAction $state $readyLog $run $invalid} 'Invalid preview clock accepted'}
$state=Placed-State;Reject {Get-HudStonePreviewAction $state $confirmedLog $run 999} 'Backwards arm clock accepted'
$state=Placed-State;Reject {Get-HudStonePreviewAction $state $confirmedLog $run 2999} 'Backwards dispatch clock accepted'
foreach($invalid in @('', '0','-1','1.0','17 extra',('1'*17))){$state=Placed-State;$state.PlaceRequestId=$invalid;Reject {Get-HudStonePreviewAction $state $confirmedLog $run 13000} 'Invalid owned request ID accepted'}
$state=Placed-State;$state.PlaceAtMs=999L;Reject {Get-HudStonePreviewAction $state $confirmedLog $run 13000} 'Dispatch before arm accepted'
$state=Placed-State;$state.Stage=3;Reject {Get-HudStonePreviewAction $state $confirmedLog $run 13000} 'Invalid stage accepted'
$state=Placed-State;$state.ConfirmedAtMs=2999L;Reject {Get-HudStonePreviewAction $state $confirmedLog $run 4000 $true} 'Confirmation before dispatch accepted'
$state=Placed-State;$state.ConfirmedAtMs=4001L;Reject {Get-HudStonePreviewAction $state $confirmedLog $run 4000 $true} 'Future confirmation clock accepted'
foreach($invalid in @('',('MineCome-HudStream-'+$run),$save.ToUpperInvariant(),'MineCome-HudStream-../../foreign')){
    $state=State;$state.Save=$invalid;Reject {Get-HudStonePreviewAction $state $readyLog $run 1000} 'Invalid owned save accepted'
}

function Engine-Placement {
    [pscustomobject]@{
        results=@([pscustomobject]@{request_id=17L;action=1;result=1})
        events=@([pscustomobject]@{operation=1;result='spawned';session=100L;sequence=1L})
        engine_acks=@([pscustomobject]@{result='spawned';session='100';sequence='1'})
    }
}
$native=Engine-Placement;Check (Test-HudStonePreviewEnginePlace $native '17') 'Matching actual relay result and engine spawn accepted'
Check (-not(Test-HudStonePreviewEnginePlace $null '17')) 'Missing relay cannot confirm placement'
foreach($id in @('','0','-1','17x','1.0',('9'*17),'18')){
    $native=Engine-Placement;Check (-not(Test-HudStonePreviewEnginePlace $native $id)) 'Missing or another request cannot confirm owned placement'
}
foreach($side in @('results','events','engine_acks')){
    $native=Engine-Placement;$native.$side=@();Check (-not(Test-HudStonePreviewEnginePlace $native '17')) 'Incomplete engine placement proof refused'
    $native=Engine-Placement;$native.$side=@($native.$side[0],$native.$side[0]);Check (-not(Test-HudStonePreviewEnginePlace $native '17')) 'Ambiguous engine placement proof refused'
}
foreach($action in @(0,2,3)){$native=Engine-Placement;$native.results[0].action=$action;Check (-not(Test-HudStonePreviewEnginePlace $native '17')) 'Another native action refused'}
foreach($result in @(0,2,3,4)){$native=Engine-Placement;$native.results[0].result=$result;Check (-not(Test-HudStonePreviewEnginePlace $native '17')) 'Unaccepted native request refused'}
foreach($operation in @(0,2,3)){$native=Engine-Placement;$native.events[0].operation=$operation;Check (-not(Test-HudStonePreviewEnginePlace $native '17')) 'Non-spawn engine event refused'}
foreach($side in @('events','engine_acks')){
    foreach($result in @('removed','failed','Spawned','')){$native=Engine-Placement;$native.$side[0].result=$result;Check (-not(Test-HudStonePreviewEnginePlace $native '17')) 'Non-spawn engine result refused'}
    foreach($field in @('session','sequence')){$native=Engine-Placement;$native.$side[0].$field='999';Check (-not(Test-HudStonePreviewEnginePlace $native '17')) 'Unrelated engine acknowledgement refused'}
}

function Guest-Proof {
    $requests=@(for($i=0;$i -lt 2;$i++){[pscustomobject]@{id=17+$i;action=$i+1;result=1;selected_slot=$i;selected_item=$(if($i -eq 0){'minecraft:stone'}else{'minecraft:dirt'});selected_count=$(if($i -eq 0){64}else{32});result_queued=$true;actions_enabled=$true;screen_open=$false;gate=[pscustomobject]@{reason='permitted';transport_result=0}}})
    $confirmations=@(foreach($r in $requests){[pscustomobject]@{id=$r.id;action=$r.action;selected_slot=$r.selected_slot;selected_item=$r.selected_item;selected_count=$r.selected_count;client_and_server=$true;inventory_mutated=$false;server_age_ms=50}})
    [pscustomobject]@{run=$run;save=$save;result='input_completed';ui_input_fixture=$false;ui_input_live_mouse=$true;ui_input_stone_bridge=$true;ui_input_stone_fixture=$false;ui_input_stone_live=$true;ui_input_offscreen_presentation=$true;ui_input_pointer_fixture=$false;ui_input_delay_fixture=$false;ui_input_background_trial=$false;ui_input_offscreen_trial=$false;lab_evidence=[pscustomobject]@{input_fixture=$false;live_mouse=$true;stone_bridge=[pscustomobject]@{
        schema=1;kind='minecome_hud_stone_bridge_v1';save=$save;session=123456789L
        baseline_confirmed=$true;closed=$true;vanilla_dispatch_inventory_unchanged=$true
        failed=$false;pending=$false;confirmed_cell_stone=$false;inventory_mutated=$false;camera_mutated=$false;engine_mirroring_verified=$false;visual_verified=$false
        request_count=2;accepted_dispatches=2;confirmed_actions=2;confirmed_places=1;confirmed_breaks=1;block_events_queued=2
        cancelled_pending=0;unavailable_results=0;stale_results=0;busy_results=0;omitted_requests=0;omitted_confirmations=0
        target=[pscustomobject]@{x=2;y=64;z=0}
        requests=$requests;confirmations=$confirmations
    }}}
}
$guest=Guest-Proof;Assert-HudStoneLivePreview $guest;Check $true 'One completed real guest placement/removal cycle accepted'
$guest=Guest-Proof;Assert-HudWorldClickGuest $guest;Check $true 'Physical mode accepts a completed cycle before separate input/relay correlation'
foreach($field in @('confirmed_places','confirmed_breaks')){
    foreach($invalid in @(0,9,-1,'1',1.0,$true,$null)){
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.$field=$invalid;Reject {Assert-HudWorldClickGuest $guest} 'Physical mode accepted invalid action totals'
    }
}
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmed_places=2;Reject {Assert-HudWorldClickGuest $guest} 'Unmatched placement accepted'
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmed_places=2;$guest.lab_evidence.stone_bridge.confirmed_breaks=2;Reject {Assert-HudWorldClickGuest $guest} 'Fabricated action totals accepted'
foreach($field in @('baseline_confirmed','closed','vanilla_dispatch_inventory_unchanged','failed','pending','confirmed_cell_stone','inventory_mutated','camera_mutated','engine_mirroring_verified','visual_verified')){
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.$field=(-not $guest.lab_evidence.stone_bridge.$field);Reject {Assert-HudWorldClickGuest $guest} 'Physical mode accepted dirty guest completion'
}
foreach($result in @(0,8,'1',1.0,$null)){
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[0].result=$result;Reject {Assert-HudWorldClickGuest $guest} 'Physical mode accepted unknown result'
}
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[0].selected_item='minecraft:dirt';Reject {Assert-HudWorldClickGuest $guest} 'Physical placement accepted non-stone selection'
foreach($result in 2..7){
    $guest=Guest-Proof;$decline=[pscustomobject]@{result=$result;action=1};$guest.lab_evidence.stone_bridge.requests+=,$decline
    Assert-HudWorldClickGuest $guest;Check $true 'Physical mode allows a refused extra click alongside a completed cycle'
}
foreach($field in @('baseline_confirmed','closed','vanilla_dispatch_inventory_unchanged','failed','pending','confirmed_cell_stone','inventory_mutated','camera_mutated','engine_mirroring_verified','visual_verified')){
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.$field=(-not $guest.lab_evidence.stone_bridge.$field);Reject {Assert-HudStoneLivePreview $guest} 'Incomplete or dirty guest proof accepted'
    foreach($invalid in @('true','false',0,1,$null)){
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.$field=$invalid;Reject {Assert-HudStoneLivePreview $guest} 'Non-Boolean guest lifecycle proof accepted'
    }
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.PSObject.Properties.Remove($field);Reject {Assert-HudStoneLivePreview $guest} 'Missing guest lifecycle proof accepted'
}
foreach($field in @('request_count','accepted_dispatches','confirmed_actions','confirmed_places','confirmed_breaks','block_events_queued','cancelled_pending','unavailable_results','stale_results','busy_results','omitted_requests','omitted_confirmations')){
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.$field++;Reject {Assert-HudStoneLivePreview $guest} 'Wrong guest action total accepted'
    foreach($invalid in @('0',$false,$true,0.0,-1,$null)){
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.$field=$invalid;Reject {Assert-HudStoneLivePreview $guest} 'Invalid numeric guest total accepted'
    }
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.PSObject.Properties.Remove($field);Reject {Assert-HudStoneLivePreview $guest} 'Missing guest action total accepted'
}
foreach($field in @('run','save','result')){
    $guest=Guest-Proof;$guest.$field='foreign';Reject {Assert-HudStoneLivePreview $guest} 'Foreign live guest accepted'
    $guest=Guest-Proof;$guest.PSObject.Properties.Remove($field);Reject {Assert-HudStoneLivePreview $guest} 'Missing live guest identity accepted'
}
foreach($field in @('kind','save')){
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.$field='foreign';Reject {Assert-HudStoneLivePreview $guest} 'Foreign live proof accepted'
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.PSObject.Properties.Remove($field);Reject {Assert-HudStoneLivePreview $guest} 'Missing live proof identity accepted'
}
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.save=$save.Replace('aaaaaaaa','bbbbbbbb');Reject {Assert-HudStoneLivePreview $guest} 'Another valid HUD save accepted'
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.save='MineCome-HudStream-'+$run;$guest.save=$guest.lab_evidence.stone_bridge.save;Reject {Assert-HudStoneLivePreview $guest} 'Run-derived non-UUID save accepted'
foreach($field in @('schema','session')){
    foreach($invalid in @('1',$true,$false,1.0,0,-1,$null)){
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.$field=$invalid;Reject {Assert-HudStoneLivePreview $guest} 'Invalid proof identity number accepted'
    }
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.PSObject.Properties.Remove($field);Reject {Assert-HudStoneLivePreview $guest} 'Missing proof identity number accepted'
}
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.schema=2;Reject {Assert-HudStoneLivePreview $guest} 'Future unrecognized schema accepted'
foreach($side in @('requests','confirmations')){
    foreach($count in @(0,1,3)){
        $guest=Guest-Proof;$record=$guest.lab_evidence.stone_bridge.$side[0];$guest.lab_evidence.stone_bridge.$side=@(for($i=0;$i -lt $count;$i++){$record})
        Reject {Assert-HudStoneLivePreview $guest} 'Wrong action record count accepted'
    }
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.PSObject.Properties.Remove($side);Reject {Assert-HudStoneLivePreview $guest} 'Missing action records accepted'
}
for($index=0;$index -lt 2;$index++){
    foreach($field in @('id','action','result','selected_slot','selected_count')){
        foreach($invalid in @('1',$true,$false,1.0,-1,$null)){
            $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[$index].$field=$invalid;Reject {Assert-HudStoneLivePreview $guest} 'Invalid request field accepted'
        }
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[$index].PSObject.Properties.Remove($field);Reject {Assert-HudStoneLivePreview $guest} 'Missing request field accepted'
    }
    foreach($field in @('result_queued','actions_enabled','screen_open')){
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[$index].$field=(-not $guest.lab_evidence.stone_bridge.requests[$index].$field);Reject {Assert-HudStoneLivePreview $guest} 'Inactive/open/unreported request accepted'
        foreach($invalid in @('true','false',0,1,$null)){
            $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[$index].$field=$invalid;Reject {Assert-HudStoneLivePreview $guest} 'Invalid request flag accepted'
        }
    }
    foreach($field in @('id','action','selected_slot','selected_count','server_age_ms')){
        foreach($invalid in @('1',$true,$false,1.0,-1,$null)){
            $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmations[$index].$field=$invalid;Reject {Assert-HudStoneLivePreview $guest} 'Invalid confirmation field accepted'
        }
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmations[$index].PSObject.Properties.Remove($field);Reject {Assert-HudStoneLivePreview $guest} 'Missing confirmation field accepted'
    }
    foreach($field in @('id','action','selected_slot','selected_count')){
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmations[$index].$field++;Reject {Assert-HudStoneLivePreview $guest} 'Confirmation differs from actual request'
    }
    foreach($field in @('client_and_server','inventory_mutated')){
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmations[$index].$field=(-not $guest.lab_evidence.stone_bridge.confirmations[$index].$field);Reject {Assert-HudStoneLivePreview $guest} 'Unconfirmed/mutating operation accepted'
        foreach($invalid in @('true','false',0,1,$null)){
            $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmations[$index].$field=$invalid;Reject {Assert-HudStoneLivePreview $guest} 'Invalid confirmation flag accepted'
        }
    }
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[$index].gate.reason='stale_server';Reject {Assert-HudStoneLivePreview $guest} 'Ungated action accepted'
    foreach($invalid in @('0',$true,$false,0.0,1,-1,$null)){
        $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[$index].gate.transport_result=$invalid;Reject {Assert-HudStoneLivePreview $guest} 'Invalid transport gate accepted'
    }
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[$index].PSObject.Properties.Remove('gate');Reject {Assert-HudStoneLivePreview $guest} 'Missing gate accepted'
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmations[$index].selected_item='minecraft:other';Reject {Assert-HudStoneLivePreview $guest} 'Confirmation selected another item'
    $guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmations[$index].server_age_ms=251;Reject {Assert-HudStoneLivePreview $guest} 'Stale server confirmation accepted'
    foreach($age in @(0,250)){$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.confirmations[$index].server_age_ms=$age;Assert-HudStoneLivePreview $guest;Check $true 'Fresh server age boundary accepted'}
}
foreach($id in @(0,9007199254740992L)){$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[0].id=$id;Reject {Assert-HudStoneLivePreview $guest} 'Unsafe request ID accepted'}
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[1].id=17;Reject {Assert-HudStoneLivePreview $guest} 'Repeated request ID accepted'
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[1].id=16;Reject {Assert-HudStoneLivePreview $guest} 'Reversed request order accepted'
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[0].action=2;Reject {Assert-HudStoneLivePreview $guest} 'Break before place accepted'
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[1].action=1;Reject {Assert-HudStoneLivePreview $guest} 'Two placements accepted'
foreach($result in @(0,2,3,4)){$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[0].result=$result;Reject {Assert-HudStoneLivePreview $guest} 'Non-accepted guest result accepted'}
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[0].selected_slot=9;Reject {Assert-HudStoneLivePreview $guest} 'Invalid hotbar slot accepted'
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[0].selected_count=0;Reject {Assert-HudStoneLivePreview $guest} 'Empty selected stone stack accepted'
foreach($item in @('minecraft:dirt','minecraft:air','stone','Minecraft:stone','',$null)){$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[0].selected_item=$item;Reject {Assert-HudStoneLivePreview $guest} 'Placement without actual stone accepted'}
foreach($item in @('dirt','minecraft:','Minecraft:dirt','',$null)){$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[1].selected_item=$item;Reject {Assert-HudStoneLivePreview $guest} 'Invalid break selected-item record accepted'}
$guest=Guest-Proof;$guest.lab_evidence.stone_bridge.requests[1].selected_item='minecraft:air';$guest.lab_evidence.stone_bridge.requests[1].selected_count=0;$guest.lab_evidence.stone_bridge.confirmations[1].selected_item='minecraft:air';$guest.lab_evidence.stone_bridge.confirmations[1].selected_count=0;Assert-HudStoneLivePreview $guest;Check $true 'Creative break correctly permits an empty selected stack'

# A keyboard-only stone preview may leave pointer counts at zero; neutral mouse
# cleanup remains mandatory, and ordinary mouse checks still require gestures.
function Pointer-Proof {
    [pscustomobject]@{live_mouse=$true;input_events_applied=2;pointer_events_applied=0;pointer_adapter_after_cleanup=[pscustomobject]@{held_buttons=0;pending_releases=0;active_button=-1}}
}
$proof=Pointer-Proof;Reject {Assert-LiveMouseGuestProof $proof} 'Ordinary live mouse test accepted zero gestures'
$proof=Pointer-Proof;Reject {Assert-LiveMouseGuestProof $proof $true} 'Explicit mouse test accepted zero gestures'
$proof=Pointer-Proof;Check ((Assert-LiveMouseGuestProof $proof $false) -eq 0) 'Stone preview may omit already verified pointer gestures'
foreach($require in @($false,$true)){
    $proof=Pointer-Proof;$proof.pointer_events_applied=1;Check ((Assert-LiveMouseGuestProof $proof $require) -eq 1) 'Actual pointer gestures preserved'
    foreach($invalid in @(-1,3,'0',$true,0.0,$null)){
        $proof=Pointer-Proof;$proof.pointer_events_applied=$invalid;Reject {Assert-LiveMouseGuestProof $proof $require} 'Invalid pointer count accepted'
    }
    foreach($field in @('held_buttons','pending_releases','active_button')){
        foreach($invalid in @(1,'0',$null)){
            $proof=Pointer-Proof;$proof.pointer_events_applied=1;$proof.pointer_adapter_after_cleanup.$field=$invalid
            Reject {Assert-LiveMouseGuestProof $proof $require} 'Non-neutral mouse cleanup accepted'
        }
    }
}

# Pass one unchanged realistic live receipt through both production contracts.
# The host log is explicit synthetic input; this verifies agreement between
# modules and does not claim actual engine execution or game visibility.
. (Join-Path $root 'scripts/HudStoneRelay.ps1')
$integrationDirectory=Join-Path $root ('runtime/evidence/hud-stone-controller-contract-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($integrationDirectory)|Out-Null
$context=[pscustomobject]@{ProjectRoot=$root;GamePid=42;GameStartedUtc=[DateTime]'2026-10-13T00:00:00Z';GameHash=('a'*64)}
$session=New-MineComeHudStoneRelay $context $integrationDirectory $run ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+180000)
[IO.Directory]::CreateDirectory((Join-Path $session.Home 'runtime/logs'))|Out-Null
$auditLines=@(
    '123 HELLO authenticated; protocol 1.1 session ready; peer role=minecraft',
    '124 STONE_INPUT_AUDIT_SESSION schema=1 connection=1 reset=3',
    '200 STONE_INPUT_AUDIT schema=1 connection=1 reset=3 order=1 sequence=10 request=17 action=1 result=1',
    '300 STONE_INPUT_AUDIT schema=1 connection=1 reset=3 order=2 sequence=12 request=18 action=2 result=1'
)
[IO.File]::WriteAllText((Join-Path $session.Home 'runtime/logs/tools-bridge.log'),($auditLines -join "`n")+"`n")
$nativeLines=@(
    'Official tools console binding verified; waiting for fresh in-game diagnostic log receipt',
    'KCD2_LOG prefix [MineComePose] {"schema":1,"player":{"x":1,"y":2,"z":3},"camera":{"x":1,"y":2,"z":4}}',
    'KCD2_LOG prefix [MineComeInput] {"schema":1,"request":17,"action":1}',
    'STONE_INPUT_DISPATCH request=17 action=1',
    'STONE_INPUT_RESULT request=17 action=1 result=1',
    'STONE_BEGIN_ACK session=1790000000000000',
    'KCD2_LOG prefix [MineComeBlock] {"schema":1,"session":1790000000000000,"sequence":10,"operation":1,"mc":{"x":2,"y":64,"z":0},"position":{"x":1,"y":2,"z":3},"result":"spawned","physics":false,"live_draw_verified":false}',
    'STONE_ENGINE_ACK session=1790000000000000 sequence=10 result=spawned'
)
$placeNative=ConvertFrom-MineComeHudStoneRelayLog (($nativeLines -join "`n")+"`n")
Check (Test-HudStonePreviewEnginePlace $placeNative '17') 'Production parser output satisfies production engine preview gate'
$nativeLines+=@(
    'KCD2_LOG prefix [MineComeInput] {"schema":1,"request":18,"action":2}',
    'STONE_INPUT_DISPATCH request=18 action=2',
    'STONE_INPUT_RESULT request=18 action=2 result=1',
    'KCD2_LOG prefix [MineComeBlock] {"schema":1,"session":1790000000000000,"sequence":12,"operation":2,"mc":{"x":2,"y":64,"z":0},"position":{"x":1,"y":2,"z":3},"result":"removed","physics":false,"live_draw_verified":false}',
    'STONE_ENGINE_ACK session=1790000000000000 sequence=12 result=removed',
    'STONE_CLEANUP_ACK session=1790000000000000',
    'Stone engine acknowledgements: placed=1 removed=1 rejected=0 cleanup_ack=true'
)
[IO.File]::WriteAllText($session.Stdout,($nativeLines -join "`n")+"`n")
$session.ExitObserved=$true;$session.ExitCode=0;$session.CleanupVerified=$true
$guest=Guest-Proof
foreach($request in $guest.lab_evidence.stone_bridge.requests){$session.Intents.Add([pscustomobject]@{ordinal=$request.action;request_id=[long]$request.id;action=$request.action;accepted=$true;sent_utc_ms=1L;failure=$null})}
Assert-HudStoneLivePreview $guest
Assert-MineComeHudStoneRelayGuest $session $guest
Check $session.EngineMirroringVerified 'Same live guest passes controller and relay contracts'
Check ($session.TransportAuthVerified -and $session.Native.events.Count -eq 2) 'Combined contract uses parsed authenticated relay evidence'
# A physical edge admitted at shutdown may be explicitly refused before guest
# dispatch. The same controller still requires actual confirmed place and break.
$session.Intents.Add([pscustomobject]@{ordinal=3;request_id=19L;action=1;accepted=$true;sent_utc_ms=2L;failure=$null})
$nativeText=($nativeLines -join "`n")+"`n"
$nativeText=$nativeText.Replace('STONE_CLEANUP_ACK session=1790000000000000',(
    'KCD2_LOG prefix [MineComeInput] {"schema":1,"request":19,"action":1}'+"`n"+
    'STONE_SESSION_END reason=transport connection or bounded queue reset session=1790000000000000'+"`n"+
    'STONE_INPUT_REJECTED reason=no_ready_world_or_input_peer request=19'+"`n"+
    'STONE_CLEANUP_ACK session=1790000000000000'))
[IO.File]::WriteAllText($session.Stdout,$nativeText)
[IO.File]::WriteAllText((Join-Path $session.Home 'runtime/logs/tools-bridge.log'),($auditLines -join "`n")+"`n400 session ended: graceful peer goodbye`n")
Assert-HudStoneLivePreview $guest
Assert-MineComeHudStoneRelayGuest $session $guest
Check ($session.EngineMirroringVerified -and $session.InputDisposition.terminal_refusals.Count -eq 1 -and $session.Native.results.Count -eq 2) 'Terminal refusal preserves both controller gameplay proof and exact guest result accounting'
foreach($invalidResult in @('input_passed','input_failed','completed')){
    $guest=Guest-Proof;$guest.result=$invalidResult
    Reject {Assert-HudStoneLivePreview $guest} 'Controller accepted non-live terminal result'
    Reject {Assert-MineComeHudStoneRelayGuest $session $guest} 'Relay accepted non-live terminal result'
    Check (-not $session.EngineMirroringVerified) 'Rejected shared terminal contract clears engine verification'
}
Write-Output "HUD_STONE_LIVE_CONTROLLER_TEST_PASS checks=$script:checks no_game_actions=true"
