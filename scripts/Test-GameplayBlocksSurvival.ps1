# One new actual Minecraft world: Survival placement, early release and held mining.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay Survival blocks failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/gameplay-blocks-survival-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$hash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant()
$passed=$false;$failure=$null;$session=$null;$sessionHash=$null
try{
 $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory 'session');FixturePhase='blocks-survival';Blocks=$true;GroundPatchFile=$patch}
 if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
 $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {
  if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}
 })
 if($result.Count -ne 1){throw 'Missing Survival blocks session result.'}
 $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
 $sessionFile=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json'
 $sessionHash=(Get-FileHash -LiteralPath $sessionFile).Hash.ToLowerInvariant()
 $session=Get-Content -LiteralPath $sessionFile -Raw|ConvertFrom-Json -Depth 24
 $fixture=$session.fixture;$blocks=$session.blocks;$movement=$session.movement
 if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.blocks -or -not $session.new_world -or
  $fixture.kind -cne 'minecome_gameplay_blocks_fixture_v1' -or $fixture.mode -cne 'blocks-survival' -or $fixture.result -cne 'passed' -or
  -not $fixture.actual_minecraft -or -not $fixture.standalone_scripted -or $fixture.native_input_verified -or $fixture.live_kcd_verified -or
  $session.kcd_movement_connected -or $session.host_command_typing_verified -or $fixture.server_creative){throw 'Survival fixture identity, mode or verification scope differs.'}
 foreach($flag in @('survival_placement_verified','early_release_verified','survival_mining_verified')){if($fixture.$flag -ne $true){throw "Survival capability missing: $flag"}}
 if($fixture.stone_count -ne 63 -or $blocks.places -ne 1 -or $blocks.ground_places -ne 1 -or $blocks.breaks -ne 1 -or $blocks.survival_breaks -ne 1 -or
  $blocks.survival_preserved_ticks -le 2 -or $blocks.cancellations -lt 1 -or $blocks.owned_count -ne 0 -or @($blocks.blocks).Count -ne 0 -or
  $blocks.pending -or $blocks.failure -or -not $blocks.controls_released -or -not $blocks.cleanup_complete -or
  $blocks.minecraft_blocks_removed_on_stop -ne 0 -or $blocks.persisted_revision -ne $blocks.revision){throw 'Survival count consumption, cancellation, held mining or cleanup proof failed.'}
 if($movement.failure -or -not $movement.cleanup_complete -or -not $movement.terrain_cells_valid -or -not $movement.controls_released -or
  $movement.patch_run -cne $run -or $movement.patch_sha256 -cne $hash -or (Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $hash){throw 'Survival fixture terrain identity or cleanup failed.'}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 [ordered]@{schema=1;kind='minecome_gameplay_blocks_survival_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  actual_minecraft=$true;kcd_connected=$false;native_input_verified=$false;host_command_typing_verified=$false;
  instance=$instance;patch_sha256=$hash;session_sha256=$sessionHash;session=$session}|
  ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
Write-Output "GAMEPLAY_BLOCKS_SURVIVAL_PASS evidence=$directory"
