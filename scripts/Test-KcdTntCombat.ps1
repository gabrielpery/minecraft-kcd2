# Real owned TNT and vanilla blast damage against two isolated native NPCs.
[CmdletBinding(DefaultParameterSetName='Live')]
param([Parameter(Mandatory,ParameterSetName='Live')][string]$BundleDirectory,
 [Parameter(ParameterSetName='Live')][string]$InstanceDirectory,[Parameter(ParameterSetName='Live')][string]$GroundPatchFile,
 [Parameter(Mandatory,ParameterSetName='Verify')][string]$VerifyEvidenceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native TNT combat check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$saved=$null
if($PSCmdlet.ParameterSetName -ceq 'Verify'){$saved=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path}
else{
 . (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
 . (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
 . (Join-Path $PSScriptRoot 'GameplayHudSessionGuard.ps1')
 $context=Get-MineComeProbeContext
 $installation=Get-MineComeGameplayInstallation -BundleDirectory $BundleDirectory -RequireUnarmed -Movement -Blocks -Chat
 Assert-GameplayHudSessionUnused $context $installation.ToolsBin
 $run=[guid]::NewGuid().ToString('N')
 if(-not $InstanceDirectory){$InstanceDirectory=Join-Path $context.ProjectRoot ('runtime/gameplay/tnt-combat-native-'+$run)}
 $probe=New-MineComeProbeRun $context 'gameplay-tnt-combat-fixture' (Join-Path $context.ProjectRoot 'kcd2/gameplay/tnt_combat_fixture.lua') 'GameplayTntCombatFixtureBegin'
 $attempted=$false;$removed=$false;$receipts=@();$log=''
 try{
  $attempted=$true
  $arguments=@{BundleDirectory=$BundleDirectory;InstanceDirectory=$InstanceDirectory;JavaHome=$JavaHome;TntCombatCheck=$true;CombatFixtureRun=$run}
  if($GroundPatchFile){$arguments.GroundPatchFile=$GroundPatchFile}
  & (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') @arguments | ForEach-Object {
   if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
   Write-Host $_
  }
 }finally{
  if($attempted){
   Invoke-MineComeProbeConsole $context ("#MineCome.GameplayTntCombatFixtureHealth('$run');MineCome.GameplayTntCombatFixtureEnd('$run')")
   $until=[DateTime]::UtcNow.AddSeconds(3)
   do{
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeTntCombatFixtureFlush] $run')")
    $log=Read-MineComeProbeLog $context $probe.Offset
    $receipts=@(Get-MineComeProbeReceipts $log 'MineComeTntCombatFixture' $run)
    $removed=@($receipts|Where-Object {$_.event -ceq 'terminal' -and $_.result -ceq 'explicit_stop' -and $_.removed -eq $true -and $_.active -eq $false -and $_.path_restored -eq $true}).Count -gt 0
    if($removed){break};Start-Sleep -Milliseconds 50
   }while([DateTime]::UtcNow -lt $until)
   [IO.File]::WriteAllText((Join-Path $probe.Directory 'fresh-kcd.log'),$log)
   $actors=[ordered]@{schema=1;kind='minecome_tnt_combat_actors_v1';run=$run;removed=$removed;source_sha256=$probe.SourceHash;receipts=$receipts;fixture_evidence=$probe.Directory}
   $json=$actors|ConvertTo-Json -Depth 12
   $json|Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
   if($saved){$json|Set-Content -LiteralPath (Join-Path $saved 'native-tnt-combat-actors.json') -Encoding utf8NoBOM}
  }
 }
 if(-not $removed){throw 'Native TNT combat NPC removal/path restoration was not confirmed.'}
 if(-not $saved){throw 'Native TNT combat session did not save successfully.'}
}
# Reuse the actual TNT, pixels, terrain, continued composition and save checks.
& (Join-Path $PSScriptRoot 'Test-KcdTnt.ps1') -VerifyEvidenceDirectory $saved
$s=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 40
$h=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 40
$v=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json -Depth 20
$a=Get-Content -LiteralPath (Join-Path $saved 'native-tnt-combat-actors.json') -Raw|ConvertFrom-Json -Depth 20
$f=$s.fixture;$c=$s.combat;$b=$c.blasts;$native=$h.Combat.Blasts
if(-not $v.tnt_combat_check -or $f.mode -cne 'tnt-combat-native' -or -not $f.combat_check -or
 -not $f.native_actor_damage_verified -or -not $f.out_of_radius_verified -or $f.minimum_control_blast_distance -le 8 -or
 $a.kind -cne 'minecome_tnt_combat_actors_v1' -or -not $a.removed){throw 'Native TNT combat fixture scope, blast or actor cleanup proof differs.'}
if($f.combat_initial_host_sequence -le 0 -or $f.combat_committed_host_sequence -lt $f.combat_initial_host_sequence -or
 $f.combat_verified_host_sequence -le $f.combat_committed_host_sequence -or $f.combat_verified_utc_ms -le 0 -or
 $f.combat_verified_utc_ms -gt $f.native_tnt_started_utc_ms -or -not $f.native_control_after.alive -or
 $f.native_near_after.token -ne $f.native_near_before.token -or $f.native_control_after.token -ne $f.native_control_before.token){throw 'Native actors were not freshly verified after both blasts and before the visual dwell.'}
if(($c.PSObject.Properties['failure'] -and $c.failure) -or $c.pending -or -not $c.cleanup_complete -or -not $c.controls_released -or $c.outgoing_hits -ne 0 -or $c.incoming_hurts -ne 0 -or
 ($b.PSObject.Properties['failure'] -and $b.failure) -or $b.pending -or -not $b.cleanup_complete -or $b.prepared -ne 2 -or $b.committed -ne 2 -or $b.rejected -ne 0 -or
 $h.Combat.Failure -or -not $h.Combat.CleanupComplete -or $h.Combat.Terminal.result -cne 'explicit_stop' -or
 -not $h.Combat.Terminal.timers_cancelled -or -not $h.Combat.Terminal.lock_policy_restored -or
 $native.Pending -or -not $native.CleanupComplete -or $native.Prepared -ne 2 -or $native.Commits -ne 2 -or $native.Rejected -ne 0){throw 'Native TNT blast/combat lease cleanup or commit counters differ.'}
$begins=@($a.receipts|Where-Object {$_.event -ceq 'begin' -and $_.result -ceq 'spawned'})
$ends=@($a.receipts|Where-Object {$_.event -ceq 'terminal' -and $_.result -ceq 'explicit_stop' -and $_.removed -and $_.path_restored -and -not $_.active})
if($begins.Count -ne 1 -or $ends.Count -lt 1 -or @($begins[0].actors).Count -ne 2 -or @($ends[-1].actors).Count -ne 2){throw 'Missing isolated native near/control actor receipts.'}
$near=@($begins[0].actors|Where-Object label -CEQ 'near');$control=@($begins[0].actors|Where-Object label -CEQ 'control')
$nearEnd=@($ends[-1].actors|Where-Object label -CEQ 'near');$controlEnd=@($ends[-1].actors|Where-Object label -CEQ 'control')
if($near.Count -ne 1 -or $control.Count -ne 1 -or $nearEnd.Count -ne 1 -or $controlEnd.Count -ne 1 -or
 $near[0].raw_id -eq $control[0].raw_id -or $near[0].raw_id -ne $nearEnd[0].raw_id -or $control[0].raw_id -ne $controlEnd[0].raw_id -or
 -not $nearEnd[0].removed -or -not $controlEnd[0].removed){throw 'Native TNT fixture NPC identity or removal differs.'}
foreach($row in @($near[0],$control[0])){if(-not $row.health_observed -or $row.health_samples -lt 1 -or -not $row.present){throw 'Native actor initial health was not observed on the owned entity.'}}
foreach($pair in @(@($near[0],$nearEnd[0]),@($control[0],$controlEnd[0]))){
 $start=$pair[0];$end=$pair[1]
 if(-not $end.health_observed -or $end.health_samples -le 1 -or $end.health_samples -le $start.health_samples -or $end.present -isnot [bool]){throw 'Native actor final health lacks actual repeated readback.'}
}
foreach($pair in @(@($near[0],$f.native_near_before),@($control[0],$f.native_control_before))){
 $start=$pair[0];$snapshot=$pair[1]
 $distance=[Math]::Sqrt([Math]::Pow($start.x-$snapshot.x,2)+[Math]::Pow($start.y-$snapshot.y,2)+[Math]::Pow($start.z-$snapshot.z,2))
 if($distance -gt .75 -or [Math]::Abs($start.health-$snapshot.health) -gt .01 -or [Math]::Abs($start.max_health-$snapshot.max_health) -gt .01){throw 'Native fixture NPC does not match the admitted Minecraft proxy.'}
}
if([Math]::Abs($control[0].health-$controlEnd[0].health) -gt .01 -or [Math]::Abs($controlEnd[0].health-$f.native_control_after.health) -gt .01 -or
 [Math]::Abs($nearEnd[0].health-$f.native_near_health_after) -gt .02 -or $nearEnd[0].health -ge $near[0].health){throw 'Native final near/control health differs from the blast evidence.'}
$ids=@($f.tnt_id.Replace('-',''),$f.chain_tnt_id.Replace('-',''));$completed=@($native.Completed)
if($completed.Count -ne 2 -or (@($completed.reply.explosion|Sort-Object -Unique).Count -ne 2) -or
 (@($completed.reply.explosion|Sort-Object)-join '|') -cne (@($ids|Sort-Object)-join '|')){throw 'Primary and chain blast commits are missing or duplicated.'}
$receipts=@($b.receipts);$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$damage=0.0;$health=[double]$f.native_near_before.health
foreach($receipt in $receipts){
 $key="$($receipt.explosion):$($receipt.actor_token)"
 # Both arguments must be doubles: PowerShell otherwise chooses Max(int,int)
 # from a literal0 and rounds the real native health before comparison.
 $expectedHealth=[Math]::Max([double]0,[double]($health-$f.native_near_before.max_health*$receipt.damage_fraction))
 if($receipt.explosion -cnotin $ids -or $receipt.actor_token -ne $f.native_near_before.token -or -not $seen.Add($key) -or $receipt.result -cne 'damaged' -or
  $receipt.damage_mc -le 0 -or $receipt.damage_mc -gt 57 -or [Math]::Abs($receipt.damage_fraction-$receipt.damage_mc/20) -gt .000001 -or
  [Math]::Abs($receipt.before-$health) -gt .02 -or [Math]::Abs($receipt.after-$expectedHealth) -gt .02){throw 'Actual vanilla damage was not committed once to its exact native actor.'}
 $matches=@($completed|Where-Object {$_.reply.explosion -ceq $receipt.explosion -and $_.reply.prepare_seq -eq $receipt.prepare_seq})
 if($matches.Count -ne 1){throw 'Native TNT preparation/commit identity differs.'}
 $outcomes=@($matches[0].reply.outcomes|Where-Object actor_token -EQ $receipt.actor_token)
 if($outcomes.Count -ne 1 -or $outcomes[0].result -cne $receipt.result -or [Math]::Abs($outcomes[0].before-$receipt.before) -gt .01 -or [Math]::Abs($outcomes[0].after-$receipt.after) -gt .01){throw 'Native TNT damage reply differs from the actual Minecraft acknowledgment.'}
 $damage+=$receipt.damage_mc;$health=$receipt.after
}
if($receipts.Count -lt 1 -or $receipts.Count -gt 2 -or [Math]::Abs($damage-$f.vanilla_blast_damage) -gt .001 -or [Math]::Abs($damage-$b.damage_mc) -gt .001 -or
 [Math]::Abs($health-$nearEnd[0].health) -gt .02 -or $native.Damaged -ne $receipts.Count){throw 'TNT vanilla/native damage totals differ.'}
[ordered]@{schema=1;kind='minecome_native_tnt_combat_verification_v1';result='passed';run=$s.run;world_id=$s.world_id;fixture_run=$a.run;
 actual_minecraft=$true;actual_native_npcs=$true;scripted_guest_input=$true;physical_native_input_verified=$false;native_scenery_occlusion_live_verified=$false;
 native_actor_damage_verified=$true;out_of_radius_verified=$true;minimum_control_blast_distance=$f.minimum_control_blast_distance;
 vanilla_damage=$damage;near_health_before=$near[0].health;near_health_after=$nearEnd[0].health;control_health=$controlEnd[0].health;
 actor_health_verified_utc_ms=$f.combat_verified_utc_ms;actor_health_verified_host_sequence=$f.combat_verified_host_sequence;
 native_near_health_samples=$nearEnd[0].health_samples;native_control_health_samples=$controlEnd[0].health_samples;
 native_near_present_at_cleanup=$nearEnd[0].present;native_control_present_at_cleanup=$controlEnd[0].present;
 blast_receipts=$receipts;native_commits=$completed;fixture_removed=$true;path_restored=$true;combat_lock_policy_restored=$true;
 shared_tnt_verification_sha256=(Get-FileHash -LiteralPath (Join-Path $saved 'native-tnt-verification.json')).Hash.ToLowerInvariant();
 actors_sha256=(Get-FileHash -LiteralPath (Join-Path $saved 'native-tnt-combat-actors.json')).Hash.ToLowerInvariant()}|
 ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $saved 'native-tnt-combat-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_TNT_COMBAT_PASS evidence=$saved"
