#Requires -Version 7.3
# An observational comparison; health loss alone never establishes a visible flinch.
[CmdletBinding()]
param([Parameter(Mandatory)][int]$ExpectedPid,[ValidateRange(.01,.5)][double]$DamageFraction=.35,[ValidateSet('torso')][string]$BodyPart)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function Test-MineComeReactionFraction {
 param($Observed,[double]$Requested)
 # Engine Lua uses a native float; 0.35 is emitted as 0.34999999404.
 # Reject absent/non-numeric/non-finite values and genuine parameter changes.
 if($Observed -isnot [ValueType] -or $Observed -is [bool]){return $false}
 try{$value=[double]$Observed}catch{return $false}
 return [double]::IsFinite($value) -and [double]::IsFinite($Requested) -and [Math]::Abs($value-$Requested) -le 1e-6
}
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$ctx=Get-MineComeProbeContext;if($ctx.GamePid -ne $ExpectedPid){throw 'Combat reaction target PID differs.'}
Get-MineComeToolsConsoleBinding|Out-Null
$fixtureModule=New-MineComeProbeRun $ctx 'combat-reaction-fixture' (Join-Path $ctx.ProjectRoot 'kcd2/gameplay/combat_fixture.lua') 'GameplayCombatFixtureBegin'
$probe=New-MineComeProbeRun $ctx 'combat-reaction' (Join-Path $ctx.ProjectRoot 'kcd2/gameplay/combat_reaction_probe.lua') 'GameplayCombatReactionProbe'
$fractionText=$DamageFraction.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
$bodyPartLua=if($BodyPart){"'torso'"}else{'nil'};$requestedBodyPart=if($BodyPart){$BodyPart}else{$null}
$cases=[Collections.Generic.List[object]]::new();$success=$false;$failure=$null
try{
 foreach($suppress in @($false,$true)){
  $run=[guid]::NewGuid().ToString('N');$offset=(Get-Item -LiteralPath $ctx.GameLog).Length;$receipts=@();$cleanup=@();$log=''
  try{
   Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatReactionProbe('$run',$($suppress.ToString().ToLowerInvariant()),$fractionText,$bodyPartLua)"
   $until=[DateTime]::UtcNow.AddSeconds(7)
   do{
    Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeReactionFlush] $run')"
    $log=Read-MineComeProbeLog $ctx $offset;$receipts=@(Get-MineComeProbeReceipts $log 'MineComeCombatReaction' $run)
    $terminal=@($receipts|Where-Object event -CEQ 'terminal')
    $cleanup=@(Get-MineComeProbeReceipts $log 'MineComeCombatFixture' $run|Where-Object {$_.event -ceq 'terminal' -and $_.removed -eq $true -and $_.path_restored -eq $true})
    if($terminal.Count -gt 0 -and $cleanup.Count -gt 0){break};Start-Sleep -Milliseconds 50
   }while([DateTime]::UtcNow -lt $until)
  }finally{
   Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatReactionEnd('$run');MineCome.GameplayCombatFixtureEnd('$run')"
   $until=[DateTime]::UtcNow.AddSeconds(2)
   do{
    Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeReactionFinal] $run')"
    $log=Read-MineComeProbeLog $ctx $offset;$receipts=@(Get-MineComeProbeReceipts $log 'MineComeCombatReaction' $run)
    $cleanup=@(Get-MineComeProbeReceipts $log 'MineComeCombatFixture' $run|Where-Object {$_.event -ceq 'terminal' -and $_.removed -eq $true -and $_.path_restored -eq $true})
    if($cleanup.Count -gt 0){break};Start-Sleep -Milliseconds 50
   }while([DateTime]::UtcNow -lt $until)
   [IO.File]::WriteAllText((Join-Path $probe.Directory ($run+'.log')),$log)
   $cases.Add([pscustomobject]@{run=$run;suppress=$suppress;damage_fraction=$DamageFraction;body_part=$requestedBodyPart;receipts=$receipts;fixture_cleanup=$cleanup})
  }
  $terminal=@($receipts|Where-Object event -CEQ 'terminal');$samples=@($receipts|Where-Object event -CEQ 'sample')
  if($terminal.Count -ne 1 -or $terminal[0].result -cne 'sampled' -or -not (Test-MineComeReactionFraction $terminal[0].damage_fraction $DamageFraction) -or $terminal[0].body_part -cne $requestedBodyPart -or -not $terminal[0].hit_called -or -not $terminal[0].timers_cancelled -or -not $terminal[0].fixture_cleanup_requested -or $cleanup.Count -lt 1 -or
      $samples.Count -lt 20 -or @($samples|Where-Object result -CEQ 'baseline').Count -lt 3 -or @($samples|Where-Object result -CEQ 'post_hit').Count -lt 15 -or
      [Math]::Abs($terminal[0].before-$terminal[0].after-$terminal[0].maximum*$DamageFraction) -gt .01){throw 'Native reaction sampling/damage/cleanup comparison incomplete.'}
 }
 $success=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 # Exact named fragments/tags from official action/hit_reaction.xml and
 # hit_reaction_type.xml. General state changes or numeric IDs are not proof.
 $named=@(foreach($case in $cases){foreach($sample in $case.receipts|Where-Object event -CEQ 'sample'){
  foreach($name in @($sample.animation,$sample.animation_state)){if($name -is [string] -and $name -match '(?i)(^|[^a-z])(HitDeath|weak_hit|minor_hit|major_hit)([^a-z]|$)'){
   [pscustomobject]@{suppress=$case.suppress;phase=$sample.result;name=$name;seq=$sample.seq}
  }}
 }})
 $namedVerified=$success -and @($named|Where-Object {$_.suppress -eq $false -and $_.phase -ceq 'post_hit'}).Count -gt 0 -and
  @($named|Where-Object {$_.phase -ceq 'baseline' -or $_.suppress -eq $true}).Count -eq 0
 [ordered]@{schema=1;kind='minecome_native_combat_reaction_observation_v1';result=$(if($success){'sampled'}else{'failed'});failure=$failure;pid=$ctx.GamePid;damage_fraction=$DamageFraction;body_part=$requestedBodyPart;
  named_reaction_verified=[bool]$namedVerified;visual_animation_verified=$false;actual_native_damage=$success;forced_animation=$false;player_health_or_camera_writes=$false;
  named_observations=$named;cases=$cases;modules=@($fixtureModule,$probe)}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $probe.Directory 'result.json') -Encoding utf8NoBOM
}
Write-Output "NATIVE_COMBAT_REACTION_SAMPLED named_reaction_verified=$namedVerified evidence=$($probe.Directory)"
