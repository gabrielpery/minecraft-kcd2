#Requires -Version 7.3
# Entry and plan-custody checks only; starts neither game.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$script:checks=0
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
. (Join-Path $root 'scripts/HudGroundExtension.ps1')
. (Join-Path $root 'scripts/HudPhysicalExtensionProof.ps1')
function Check([bool]$value,[string]$why){$script:checks++;if(-not $value){throw $why}}
function Reject([scriptblock]$work,[string]$why){$failed=$false;try{& $work | Out-Null}catch{$failed=$true};Check $failed $why}
function Clone($value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $value -Depth 16)}
$area=Get-HudWalkingArea -ExtensionWalking
Check ($area.MinX -eq -4 -and $area.MaxX -eq 12 -and $area.SafeMaxX -eq 11.5 -and $area.Points -eq 153) 'Extension has its separate bounded footprint'
foreach($other in @('WideWalking','CorridorWalking')){$flags=@{ExtensionWalking=$true};$flags[$other]=$true;Reject {Get-HudWalkingArea @flags} 'Extension cannot acquire another walking area'}
Assert-HudWalkingArea ([pscustomobject]@{walking_area='extension'}) $false -ExtensionWalking;Check $true 'Explicit extension marker'
Reject {Assert-HudWalkingArea ([pscustomobject]@{walking_area='corridor'}) $false -ExtensionWalking} 'Corridor evidence cannot authorize extension'
Reject {Assert-HudWalkingArea ([pscustomobject]@{walking_area='extension'}) $false -CorridorWalking} 'Extension evidence cannot authorize corridor'
$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Run-HudStreamClient.ps1'),[ref]$null,[ref]$errors)
Check ($errors.Count -eq 0) 'Child entry parses'
$fn=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-HudWalkingAimedChildMode'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
Assert-HudWalkingAimedChildMode $true $true $true $true $false -90 -ExtensionWalking;Check $true 'Extension aimed fixture has explicit eastward heading'
Reject {Assert-HudWalkingAimedChildMode $true $true $true $true $false 0 -ExtensionWalking} 'Extension cannot borrow legacy fixture heading'
$folder=Join-Path $root ('runtime/evidence/physical-extension-entry-tests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($folder);$file=Join-Path $folder 'extension.json'
try{
    New-HudGroundExtensionFixture ('a'*32) | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $file -Encoding utf8NoBOM
    $input=Read-HudGroundExtensionInput $file $root $false
    $geometry=Get-HudPhysicalExtensionGeometry $input
    Check ($geometry.Cells.Count -ge 128 -and $geometry.Cells.Count -le 256 -and $geometry.Cells.Contains('11,63,0')) 'Protected plan includes the new tile'
    Check (-not $geometry.Cells.Contains('-1,63,-5')) 'North build support stays outside imported collision'
    $handoff=@{initial_sha256=$input.InitialHash;tile_sha256=$input.TileHashes;anchor=$input.Anchor;protected_imported_cells=$geometry.Cells.Count;handoff_wait_ms=25;client_max_x=8.6;server_max_x=8.6}
    $move=@{patch_run=$input.Run;patch_sha256=$input.Hash;ground_source_kind='standalone_ground_extension_fixture';anchor_mc=@{x=0;y=64;z=0};extension=$handoff}
    $support=@{x=-1;y=63;z=-5};$seed=@{x=-1;y=64;z=-5}
    $aim=@{support=$support;seed=$seed;confirmations=@(@{target=$seed});arena=@{build_region=@{patch_run=$input.Run;patch_sha256=$input.Hash;protected_imported_cells=$geometry.Cells.Count};confirmations=@(@{target=$seed})}}
    $guest=Clone @{lab_evidence=@{physical_controller_fixture=@{physical_movement=$move;aimed_blocks=$aim}}}
    $verified=Assert-HudPhysicalExtensionManifestProof $guest $input -AimedBlocks
    Check ($verified.result -ceq 'passed' -and $verified.patch_sha256 -ceq $input.Hash) 'Manifest proof binds source geometry and generations'
    $bad=Clone $guest;$bad.lab_evidence.physical_controller_fixture.physical_movement.extension.initial_sha256='f'*64
    Reject {Assert-HudPhysicalExtensionManifestProof $bad $input -AimedBlocks} 'Initial generation cannot be swapped'
    $bad=Clone $guest;$bad.lab_evidence.physical_controller_fixture.physical_movement.extension.anchor.x++
    Reject {Assert-HudPhysicalExtensionManifestProof $bad $input -AimedBlocks} 'Handoff cannot move the origin'
    $bad=Clone $guest;$bad.lab_evidence.physical_controller_fixture.physical_movement.extension.client_max_x=7.5
    Reject {Assert-HudPhysicalExtensionManifestProof $bad $input -AimedBlocks} 'Existing corridor travel cannot claim new tile crossing'
    $bad=Clone $guest;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.build_region.protected_imported_cells=96
    Reject {Assert-HudPhysicalExtensionManifestProof $bad $input -AimedBlocks} 'Build region must reserve full plan before handoff'
    $bad=Clone $guest;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[0].target=[pscustomobject]@{x=11;y=63;z=0}
    Reject {Assert-HudPhysicalExtensionManifestProof $bad $input -AimedBlocks} 'Block actions cannot touch imported future-tile cells'
    $bad=Clone $input;$bad.Hash='f'*64
    Reject {Get-HudPhysicalExtensionGeometry $bad} 'Manifest bytes are hash-bound'
}finally{[IO.File]::Delete($file);[IO.Directory]::Delete($folder)}
Write-Output "HUD_PHYSICAL_EXTENSION_ENTRY_TESTS_PASS checks=$script:checks no_game_started=true"
