# Actual vanilla TNT ignition, fuse/chain explosion and saved construction ledger.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(ParameterSetName='Live')][string]$JavaHome='C:/Program Files/Java/jdk-24',[Parameter(ParameterSetName='Live')][string]$ReceiverPath,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "TNT check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$reuse=$PSCmdlet.ParameterSetName -ceq 'Verify';$prior=$null
if($reuse){
 $directory=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path
 $prior=Get-Content -LiteralPath (Join-Path $directory 'verification.json') -Raw|ConvertFrom-Json -Depth 30
 if($prior.kind -cne 'minecome_gameplay_tnt_verification_v1' -or $prior.run -cnotmatch '^[a-f0-9]{32}$'){throw 'Saved TNT verification identity differs.'}
 $run=$prior.run
}else{
 $run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-tnt-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
 [void][IO.Directory]::CreateDirectory($directory)
}
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
if(-not $reuse){New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM}
$hash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
if($reuse -and ($prior.patch_sha256 -cne $hash -or [IO.Path]::GetFullPath($prior.instance) -ine [IO.Path]::GetFullPath($instance))){throw 'Saved TNT patch or instance identity changed.'}
try{
 foreach($phase in @('tnt','tnt-resume')){
  if($reuse){$phaseDirectory=Join-Path $directory $phase;$result=@([pscustomobject]@{EvidenceDirectory=$phaseDirectory;VerificationFile=(Join-Path $phaseDirectory 'verification.json')})}
  else{
   $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;WorldBlocks=$true;GroundPatchFile=$patch}
   if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
   $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
  }
  if($result.Count -ne 1){throw "Missing $phase result."}
  $v=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  $file=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json';$s=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -Depth 30
  $f=$s.fixture;$m=$s.movement;$b=$s.blocks;$t=$b.tnt
  if($v.kind -cne 'minecome_gameplay_guest_session_v1' -or $v.run -cne $s.run -or $v.fixture -cne $phase -or $v.result -cne 'passed' -or -not $v.normal_client_exit -or
   -not $s.world_blocks_enabled -or $s.failure -or $s.producer_failure -or -not $s.controls_released -or -not $s.producer_finished -or
   $f.kind -cne 'minecome_gameplay_tnt_fixture_v1' -or $f.mode -cne $phase -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.live_kcd_connected -or $f.position_writes_used -or $f.direct_world_inventory_entity_writes -or
   $f.world_id -cne $s.world_id -or $s.kcd_movement_connected -or $s.host_command_typing_verified){throw "TNT verification scope differs: $phase"}
  if($m.failure -or -not $m.cleanup_complete -or -not $m.controls_released -or -not $m.terrain_cells_valid -or
   $m.patch_run -cne $run -or $m.patch_sha256 -cne $hash -or (Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $hash -or
   $b.failure -or $b.pending -or $b.owned_count -ne 1 -or -not $b.cleanup_complete -or -not $b.controls_released -or
   $t.failure -or -not $t.cleanup_complete -or $t.active -ne 0 -or $t.frozen_on_stop -ne 0){throw 'TNT terrain/block/entity cleanup differs.'}
  $final=$f.final_state;$resistant=$f.positions.resistant;$ledger=@($b.blocks)
  $stateKeys=@($final.states.PSObject.Properties.Name|Sort-Object -CaseSensitive)
  if(($stateKeys -join '|') -cne 'chain|fragile|primary|resistant'){throw 'Actual TNT cell-state keys differ.'}
  if($final.primed_count -ne 0 -or $final.flint_count -ne 1 -or $final.flint_damage -ne 1 -or -not $f.protection_restored -or $f.fuse_writes_used -or
   $final.states.primary -cne 'minecraft:air' -or $final.states.chain -cne 'minecraft:air' -or $final.states.fragile -cne 'minecraft:air' -or $final.states.resistant -cne 'minecraft:obsidian' -or
   $ledger.Count -ne 1 -or $ledger[0].state -cne 'minecraft:obsidian' -or $ledger[0].x -ne $resistant.x -or $ledger[0].y -ne $resistant.y -or $ledger[0].z -ne $resistant.z){throw 'Actual TNT destruction, tool damage or remaining ledger cell differs.'}
  if($phase -ceq 'tnt'){
   foreach($flag in @('tnt_placement_verified','ignition_verified','fuse_verified','chain_reaction_verified','fragile_destruction_verified','resistant_preservation_verified','tool_durability_verified','ledger_removal_verified','render_pixels_verified')){if($f.$flag -ne $true){throw "Missing TNT capability: $flag"}}
   if(-not $s.new_world -or $b.places -ne 4 -or $b.tnt_ignitions -ne 1 -or $t.primed -ne 2 -or $t.chain_primed -ne 1 -or $t.explosions -ne 2 -or $s.tnt_render_frames -lt 1){throw 'Production placement/ignition/chain/render path was not exercised.'}
   $first=@($f.observed_tnt|Where-Object id -CEQ $f.tnt_id);$chain=@($f.observed_tnt|Where-Object id -CEQ $f.chain_tnt_id)
   if(@($f.observed_tnt).Count -ne 2 -or $f.tnt_id -ceq $f.chain_tnt_id -or $first.Count -ne 1 -or $chain.Count -ne 1 -or
    $first[0].first_fuse -lt 60 -or $first[0].first_fuse -gt 80 -or $first[0].first_fuse-$first[0].minimum_fuse -lt 10 -or $chain[0].first_fuse -lt 1 -or $chain[0].first_fuse -gt 29){throw 'Actual vanilla fuse/chain entity observations differ.'}
   $names=@('primed','after')
  }else{
   if($s.new_world -or -not $f.resume_verified -or $s.world_id -cne $proofs[0].session.world_id -or -not $m.resume_position_restored -or $t.explosions -ne 0 -or $b.places -ne 0){throw 'TNT reload changed its saved world or replayed destruction.'}
   foreach($field in @('player_id','mode','tnt_count','fragile_count','obsidian_count','flint_count','flint_damage','blast_resistance')){
    if(($final.$field|ConvertTo-Json -Depth 5 -Compress) -cne ($proofs[0].session.fixture.final_state.$field|ConvertTo-Json -Depth 5 -Compress)){throw "Saved TNT state changed on reload: $field"}
   }
   $previous=$proofs[0].session.fixture.final_state.states
   if(($stateKeys -join '|') -cne (($previous.PSObject.Properties.Name|Sort-Object -CaseSensitive) -join '|')){throw 'Saved TNT cell-state keys changed on reload.'}
   foreach($key in $stateKeys){if($final.states.$key -isnot [string] -or $previous.$key -isnot [string] -or $final.states.$key -cne $previous.$key){throw "Saved TNT cell state changed on reload: $key"}}
   $names=@('resumed')
  }
  if(($f.images.stage -join '|') -cne ($names -join '|')){throw 'TNT pixel capture stages incomplete.'}
  foreach($capture in $f.images){
   if($capture.file -cne ('tnt-'+$capture.stage+'.png') -or (Get-FileHash -LiteralPath (Join-Path $result[0].EvidenceDirectory $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or
    $capture.world_file -cne ('tnt-'+$capture.stage+'-world.png') -or (Get-FileHash -LiteralPath (Join-Path $result[0].EvidenceDirectory $capture.world_file)).Hash.ToLowerInvariant() -cne $capture.world_sha256 -or
    $capture.metadata.world_id -cne $s.world_id -or $capture.metadata.tnt_fixture_stage -cne $capture.stage -or $capture.metadata.frame_format -ne 2){throw 'TNT capture bytes/identity differ.'}
   if($capture.stage -ceq 'primed'){
    if($capture.metadata.tnt_render_count -lt 1 -or $capture.metadata.tnt_render_count -gt 16 -or @($capture.metadata.tnt).Count -ne $capture.metadata.tnt_render_count -or
     $capture.metadata.rendered_world_blocks -ne 0 -or $capture.metadata.dropped_item_render_count -ne 0 -or $capture.metadata.projectile_render_count -ne 0 -or $capture.metadata.player_pixels -or
     @($capture.metadata.tnt|Where-Object {$_.id -ceq $f.tnt_id -and $_.fuse -gt 0}).Count -ne 1 -or
     $capture.world_pixels -lt 1 -or $capture.world_with_depth_pixels -lt 1){throw 'Primed TNT lacked isolated, admitted-entity colour/depth evidence.'}
   }elseif($capture.metadata.tnt_render_count -ne 0 -or @($capture.metadata.tnt).Count -ne 0){throw 'Exploded TNT survived the after/reload render.'}
  }
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session_sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant();session=$s})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_tnt_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;reused_evidence=$reuse;actual_minecraft=$true;scripted_guest_input=$true;native_input_verified=$false;kcd_connected=$false;instance=$instance;patch_sha256=$hash;launches=$proofs.ToArray()}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_TNT_PASS evidence=$directory"
