# Two actual Minecraft launches into the same isolated persistent world.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay persistence failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/gameplay-persistence-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance'
$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
try{
 foreach($phase in @('create','resume')){
  $args=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase}
  if($ReceiverPath){$args.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @args | ForEach-Object {
   if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}
  })
  if($result.Count -ne 1){throw "Missing $phase session result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit){throw "Unverified normal save/shutdown for $phase."}
  $captureFile=Join-Path $result[0].EvidenceDirectory 'capture/stream-result.json'
  $capture=Get-Content -LiteralPath $captureFile -Raw|ConvertFrom-Json -Depth 24
  $session=$capture.lab_evidence
  if($session.fixture.result -cne 'passed' -or $session.save -cne 'MineCome-Gameplay' -or
   $session.kcd_movement_connected -or $session.host_command_typing_verified){throw 'Fixture scope or persistence receipt differs.'}
  if($phase -ceq 'create' -and ($session.active_ms -lt 35000 -or -not $session.new_world)){throw 'Creation did not exercise a sustained new session.'}
  if($phase -ceq 'resume' -and ($session.new_world -or $session.world_id -cne $proofs[0].session.world_id)){throw 'Resume replaced the saved world identity.'}
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;capture_sha256=(Get-FileHash -LiteralPath $captureFile).Hash.ToLowerInvariant();session=$session})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 [ordered]@{schema=1;kind='minecome_gameplay_persistence_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  actual_minecraft=$true;kcd_connected=$false;host_command_typing_verified=$false;instance=$instance;launches=$proofs.ToArray()}|
  ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
Write-Output "GAMEPLAY_PERSISTENCE_PASS evidence=$directory"
