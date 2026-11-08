# Actual vanilla primary melee/cooldown/durability and incoming armour damage; synthetic host only.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Combat check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-combat-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
$terrain=New-HudGroundMovementPatch $run -WideWalking
$terrain|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$hash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$session=$null
try{
 $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory 'combat');FixturePhase='combat';WorldBlocks=$true;Combat=$true;GroundPatchFile=$patch}
 if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
 $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments|ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
 if($result.Count -ne 1){throw 'Missing combat result.'}
 $v=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
 $file=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json';$session=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -Depth 30
 $f=$session.fixture;$m=$session.movement;$b=$session.blocks;$c=$session.combat
 if($v.result -cne 'passed' -or -not $v.normal_client_exit -or -not $session.world_blocks_enabled -or
  $f.kind -cne 'minecome_gameplay_combat_fixture_v1' -or $f.mode -cne 'combat' -or $f.result -cne 'passed' -or $f.failure -or
  -not $f.actual_minecraft -or -not $f.standalone_scripted -or -not $f.synthetic_host -or $f.native_input_verified -or $f.live_kcd_verified -or $f.position_writes_used -or $f.direct_health_inventory_entity_writes -or
  $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or $session.host_command_typing_verified){throw 'Combat verification scope differs.'}
 foreach($flag in @('fist_damage_verified','wooden_sword_verified','diamond_sword_verified','cooldown_verified','durability_verified','inventory_suppression_verified','minecraft_block_occlusion_verified','incoming_damage_verified','armor_verified','render_pixels_verified')){if($f.$flag -ne $true){throw "Missing actual combat capability: $flag"}}
 if($f.hits.Count -ne 4 -or $f.barehand_damage -ne 1 -or $f.wooden_sword_damage -ne 4 -or $f.diamond_sword_damage -ne 7 -or
  $f.rapid_diamond_damage -le 0 -or $f.rapid_diamond_damage -ge $f.diamond_sword_damage -or $f.unarmored_hurt -ne 8 -or $f.armored_hurt -le 0 -or $f.armored_hurt -ge 8 -or
  $f.final_state.held_damage -ne 2 -or $f.final_state.chest_damage -le 0){throw 'Vanilla weapons/cooldown/armour evidence differs.'}
 if($m.failure -or -not $m.cleanup_complete -or -not $m.controls_released -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $hash -or
  $b.failure -or $b.pending -or -not $b.cleanup_complete -or -not $b.controls_released -or ($c.PSObject.Properties['failure'] -and $c.failure) -or -not $c.cleanup_complete -or $c.pending -or
  $c.outgoing_hits -ne 4 -or $c.hit_ack -ne 4 -or $c.hurt_ack -ne 2 -or $c.incoming_hurts -ne 2){throw 'Combat ownership, confirmation or cleanup differs.'}
 if(($f.images.stage -join '|') -cne 'combat'){throw 'Missing actual combat HUD capture.'}
 foreach($capture in $f.images){if($capture.file -cne 'combat-combat.png' -or (Get-FileHash -LiteralPath (Join-Path $result[0].EvidenceDirectory $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or
  $capture.metadata.world_id -cne $session.world_id -or $capture.metadata.combat_fixture_stage -cne 'combat' -or -not $capture.metadata.PSObject.Properties['world_camera']){throw 'Combat capture bytes/identity differ.'}}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_combat_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;synthetic_host=$true;scripted_guest_input=$true;native_input_verified=$false;kcd_connected=$false;instance=$instance;patch_sha256=$hash;session=$session}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_COMBAT_PASS evidence=$directory"
