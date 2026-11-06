# Actual Minecraft hand/held-item pixels, using the same transparent render path as KCD2.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Gameplay hands check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-hands-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$session=$null;$imageProof=@()
try{
 $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory 'hands');FixturePhase='hands';Hands=$true;GroundPatchFile=$patch}
 if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
 $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
 if($result.Count -ne 1){throw 'Missing hands guest result.'}
 $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
 if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks -or -not $verification.hands){throw 'Hands guest did not save and close normally.'}
 $session=Get-Content -LiteralPath (Join-Path $result[0].EvidenceDirectory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
 $f=$session.fixture;$m=$session.movement
 if($f.kind -cne 'minecome_gameplay_hands_fixture_v1' -or $f.mode -cne 'hands' -or $f.result -cne 'passed' -or $f.failure -or
  -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.direct_command_api_used -or $f.ability_writes_used -or $f.position_writes_used -or
  $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or -not $session.hands_enabled -or -not $session.new_world -or
  -not $f.render_pixels_verified -or -not $f.inventory_hand_suppression_verified -or $f.scripted_swing_calls -lt 1 -or
  $f.game_mode -cne 'creative' -or $f.first_item -cne 'minecraft:stone' -or $f.second_item -cne 'minecraft:diamond_sword' -or $f.selected_slot -ne 8){throw 'Actual hands fixture state/evidence scope differs.'}
 if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
  -not $m.cleanup_complete -or -not $m.ground_cells_air -or -not $m.terrain_cells_valid -or -not $m.controls_released -or
  -not $m.client_collision_released -or -not $m.server_collision_released -or -not $m.resume_checkpoint_present -or
  $session.blocks.failure -or $session.blocks.owned_count -ne 0 -or -not $session.blocks.cleanup_complete){throw 'Hands fixture altered terrain/blocks or did not clean up.'}
 if(($f.submitted_commands -join '|') -cne '/item replace entity @s hotbar.0 with minecraft:stone|/item replace entity @s hotbar.1 with minecraft:diamond_sword'){throw 'Hands fixture did not use the expected actual vanilla item commands.'}
 $names=@('empty','stone','sword','swing','inventory','restored','empty_after')
 if(@($f.images).Count -ne $names.Count -or (@($f.images.stage) -join '|') -cne ($names -join '|')){throw 'Hands capture set incomplete.'}
 foreach($capture in $f.images){
  $file=Join-Path $result[0].EvidenceDirectory $capture.file
  if($capture.file -cne ('hands-'+$capture.stage+'.png') -or -not (Test-Path -LiteralPath $file -PathType Leaf) -or
   (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $capture.sha256 -or
   $capture.metadata.world_id -cne $session.world_id -or $capture.metadata.hands_fixture_stage -cne $capture.stage -or
   -not $capture.metadata.no_world_pixels -or $capture.opaque_pixels -lt 200){throw 'Hands PNG content/identity changed or lacks real rendered content.'}
  $inventory=$capture.stage -ceq 'inventory'
  if([bool]$capture.metadata.hand_pass_rendered -eq $inventory){throw 'Actual HeldItemRenderer pass visibility differs.'}
  if(-not $inventory -and ($capture.hand_region_pixels -lt 200 -or $capture.clear_region_pixels -ne 0 -or $capture.transparent_pixels -lt $capture.pixels*.4)){throw 'Hand pixels absent or world leaked into the transparent layer.'}
  $imageProof+=[pscustomobject]@{stage=$capture.stage;path=$file;sha256=$capture.sha256;hand_region_pixels=$capture.hand_region_pixels;transparent_pixels=$capture.transparent_pixels;hand_pass_rendered=$capture.metadata.hand_pass_rendered}
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_hands_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;scripted_ui=$true;direct_command_api_used=$false;native_input_verified=$false;kcd_connected=$false;instance=$instance;patch_sha256=$patchHash;images=$imageProof;session=$session}|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_HANDS_PASS evidence=$directory"
