#Requires -Version 7.3
# Pure wrapper argument/proof contracts; no process or game launches.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$script:checks=0
function Check([bool]$value,[string]$why){$script:checks++;if(-not $value){throw $why}}
function Reject([scriptblock]$work,[string]$why){$failed=$false;try{& $work | Out-Null}catch{$failed=$true};Check $failed $why}
function Clone($value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $value -Depth 12)}
$path=Join-Path $root 'scripts/Test-CoupledPhysicalExtension.ps1';$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$errors)
Check ($errors.Count -eq 0) 'Combined entry parses'
foreach($name in @('Get-CoupledPhysicalExtensionFixtureArguments','Get-CoupledPhysicalExtensionReplayArguments','Assert-CoupledPhysicalExtensionProof')){
    $fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$args=Get-CoupledPhysicalExtensionFixtureArguments 'captured-extension.json' 'jdk path'
Check ($args.Count -eq 5 -and $args.ExtendedWalking -and $args.ExtensionWalking -and $args.AimedBlocks -and $args.GroundPatchFile -ceq 'captured-extension.json' -and $args.JavaHome -ceq 'jdk path') 'Combined fixture requires extension, extended movement and blocks'
$preflight=Get-CoupledPhysicalExtensionFixtureArguments '' '' -PreflightOnly
Check ($preflight.Count -eq 4 -and $preflight.PreflightOnly -and -not $preflight.ContainsKey('GroundPatchFile')) 'Preflight uses synthetic validation without captured terrain'
$args=Get-CoupledPhysicalExtensionReplayArguments 'captured-extension.json' 'fixture directory'
Check ($args.Count -eq 3 -and $args.ExtensionWalking -and $args.GroundExtensionFile -ceq 'captured-extension.json' -and $args.TraceDirectory -ceq 'fixture directory') 'Replay retains original capture and exact completed fixture'
$fixtureDir=Join-Path $root 'runtime/evidence/unit-fixture';$captureHash='a'*64;$planHash='b'*64;$traceHash='c'*64
$fixture=Clone @{result='passed';walking_area='extension';movement_session='extended';original_capture_sha256=$captureHash;patch_sha256=$planHash;trace_sha256=$traceHash;
    scripted_input=$true;trace_passed=$true;source_hashes_verified=$true;ui_walking_aimed_fixture=$true;physical_input_verified=$false;kcd_compositing_verified=$false;renderer_armed=$false;reverse_input_mapping_created=$false;
    extension_plan=@{result='passed';patch_sha256=$planHash;aimed_blocks=$true}}
$replay=Clone @{kind='minecome_buffered_extension_movement_replay_v1';result='passed';walking_area='extension';movement_session='extended';target_pid=123;
    original_capture_sha256=$captureHash;fixture_sha256=$planHash;source_trace_sha256=$traceHash;source_evidence=$fixtureDir;scripted_replay=$true;restoration_verified=$true;
    physical_input_verified=$false;minecraft_connected=$false;hud_armed=$false;visual_smoothness_verified=$false;host_gpu_budget=@{cap_verified=$true;restoration_verified=$true;budget_valid=$true}}
Assert-CoupledPhysicalExtensionProof $fixture $replay $captureHash $fixtureDir 123;Check $true 'Sequential recorded replay accepts exact source custody'
foreach($key in @('original_capture_sha256','fixture_sha256','source_trace_sha256')){
    $bad=Clone $replay;$bad.$key='f'*64;Reject {Assert-CoupledPhysicalExtensionProof $fixture $bad $captureHash $fixtureDir 123} 'Replay cannot borrow unrelated evidence'
}
foreach($key in @('restoration_verified','scripted_replay')){
    $bad=Clone $replay;$bad.$key=$false;Reject {Assert-CoupledPhysicalExtensionProof $fixture $bad $captureHash $fixtureDir 123} 'Replay completion must include restoration and scripted ownership'
}
foreach($key in @('minecraft_connected','hud_armed','physical_input_verified','visual_smoothness_verified')){
    $bad=Clone $replay;$bad.$key=$true;Reject {Assert-CoupledPhysicalExtensionProof $fixture $bad $captureHash $fixtureDir 123} 'Sequential replay must not claim unperformed simultaneous/manual checks'
}
$bad=Clone $replay;$bad.host_gpu_budget.budget_valid=$false
Reject {Assert-CoupledPhysicalExtensionProof $fixture $bad $captureHash $fixtureDir 123} 'Expired host cap cannot produce combined pass'
$bad=Clone $fixture;$bad.ui_walking_aimed_fixture=$false
Reject {Assert-CoupledPhysicalExtensionProof $bad $replay $captureHash $fixtureDir 123} 'Blocks cannot be omitted from milestone'
. (Join-Path $root 'scripts/powershell7.ps1')
$argv=@(Get-MineComePowerShell7Arguments $path @{TraceDirectory='C:\trace directory';GroundExtensionFile='C:\extension file.json';ExtensionWalking=$true;CorridorWalking=$false;ExtendedWalking=$true;AimedBlocks=$true;GroundPatchFile='C:\patch file.json';GroundCorridorFile='C:\corridor.json';WideWalking=$false;FacingSeed=$false;LateCutoff=$false;YawDegrees=-90.5;PreflightOnly=$true;Ignored='ignored'})
foreach($entry in @('-TraceDirectory','C:\trace directory','-GroundExtensionFile','C:\extension file.json','-GroundPatchFile','C:\patch file.json','-GroundCorridorFile','C:\corridor.json','-ExtensionWalking:$true','-CorridorWalking:$false','-ExtendedWalking:$true','-AimedBlocks:$true','-WideWalking:$false','-FacingSeed:$false','-LateCutoff:$false','-YawDegrees','-90.5','-PreflightOnly:$true')){
    Check ($argv -ccontains $entry) "PowerShell5 bootstrap preserves $entry"
}
Check ($argv -cnotcontains '-Ignored' -and $argv -cnotcontains 'ignored') 'Bootstrap still restricts forwarded parameter names'
Check ($argv[0] -ceq '-NoLogo' -and $argv[1] -ceq '-NoProfile' -and $argv[2] -ceq '-File' -and $argv[3] -ceq $path) 'Bootstrap remains native argv without command interpolation'
Write-Output "COUPLED_PHYSICAL_EXTENSION_TESTS_PASS checks=$script:checks no_process_started=true"
