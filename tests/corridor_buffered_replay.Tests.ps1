# Pure recorded-controller admission checks. No process, endpoint or game calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/HudBufferedMovement.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Test-KcdBufferedReplay.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Assert-HudCorridorReplayTrace'},$true)
Invoke-Expression $fn.Extent.Text
$checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
function Clone($Object){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Object -Depth 12)}
$origin=[pscustomobject]@{x=120.0;y=2040.0;z=56.0}
$capture=[pscustomobject]@{Hash=('c'*64);Anchor=$origin}
$fixture=[pscustomobject]@{Hash=('f'*64);Run=('a'*32);Anchor=$origin}
$verification=[pscustomobject]@{kind='standalone_hud_physical_controller_fixture_verification_v1';walking_area='corridor';movement_session='extended';
    scripted_input=$true;physical_input_verified=$false;kcd_compositing_verified=$false;kcd_commands_sent=0;renderer_armed=$false;
    reverse_input_mapping_created=$false;source_hashes_verified=$true;original_capture_sha256=$capture.Hash;patch_sha256=$fixture.Hash}
function Record([int]$Seq,[string]$Kind,[string]$Phase){
    return [pscustomobject]@{schema=1;seq=$Seq;kind=$Kind;phase=$Phase;utc_ms=1793300000000L+$Seq;run=$fixture.Run;patch_sha256=$fixture.Hash;
        source_kind='standalone_hud_physical_movement_corridor_fixture';walking_area='corridor';world='11111111-2222-4333-8444-555555555555';
        save='MineCome-HudStream-11111111-2222-4333-8444-555555555555'}
}
function Motion([double]$X){return [pscustomobject]@{x=$X;y=64.03;z=0.0;vx=0.0;vy=0.0;vz=0.0;on_ground=$true;proxy_support=$true}}
$trace=@(Record 1 'begin' 'SETTLING';Record 2 'sample' 'SETTLING';Record 3 'sample' 'WALKING';Record 4 'sample' 'PASSED';Record 5 'end' 'PASSED')
$trace[0] | Add-Member NoteProperty center $origin
$trace[0] | Add-Member NoteProperty anchor_mc ([pscustomobject]@{x=0.0;y=64.03;z=0.0})
for($i=1;$i -le 3;$i++){
    $x=if($i -eq 2){5.5}elseif($i -eq 3){.1}else{0.0}
    $trace[$i] | Add-Member NoteProperty client (Motion $x)
    $trace[$i] | Add-Member NoteProperty server (Motion $x)
}
$trace[-1] | Add-Member NoteProperty result 'passed'
Assert-HudCorridorReplayTrace $trace $verification $fixture $capture;Check $true 'Actual fixture labels and fixed coordinate mapping are admitted'
foreach($name in @('kind','walking_area','movement_session','original_capture_sha256','patch_sha256')){
    $bad=Clone $verification;$bad.$name='wrong'
    Reject {Assert-HudCorridorReplayTrace $trace $bad $fixture $capture} "Reject changed fixture $name"
}
foreach($name in @('physical_input_verified','kcd_compositing_verified','renderer_armed','reverse_input_mapping_created')){
    $bad=Clone $verification;$bad.$name=$true
    Reject {Assert-HudCorridorReplayTrace $trace $bad $fixture $capture} "Replay never inherits live claim $name"
}
$bad=Clone $verification;$bad.scripted_input=1
Reject {Assert-HudCorridorReplayTrace $trace $bad $fixture $capture} 'Typed fixture input proof required'
foreach($change in @('live_label','no_crossing','raw_vertical','relative_vertical','initial_reanchor','velocity','unsupported_end','center','sequence','world','utc','extra_begin')){
    $bad=Clone $trace
    switch($change){
        live_label {$bad[2].source_kind='live_kcd_hud_physical_movement_corridor'}
        no_crossing {$bad[2].client.x=3.9;$bad[2].server.x=3.9}
        raw_vertical {$bad[2].client.y=68.0;$bad[2].server.y=68.0}
        relative_vertical {$bad[2].client.y=57.9;$bad[2].server.y=57.9}
        initial_reanchor {$bad[1].server.y=64.04}
        velocity {$bad[2].server.vx=4.01}
        unsupported_end {$bad[3].server.proxy_support=$false}
        center {$bad[0].center.x=120.01}
        sequence {$bad[2].seq=$bad[1].seq}
        world {$bad[2].world='foreign'}
        utc {$bad[2].utc_ms=$bad[1].utc_ms-1}
        extra_begin {$bad[2].kind='begin'}
    }
    Reject {Assert-HudCorridorReplayTrace $bad $verification $fixture $capture} "Reject $change"
}
$bad=Clone $trace;$bad[0].anchor_mc.x=.005;$bad[1].client.x=.005;$bad[1].server.x=.005
$bad[2].client.x=-3.5;$bad[2].server.x=-3.5
Reject {Assert-HudCorridorReplayTrace $bad $verification $fixture $capture} 'Raw footprint cannot widen the anchor-relative rectangle'
Write-Output "Corridor buffered replay pure checks: $checks passed; no game calls."
