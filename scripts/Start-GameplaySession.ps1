# Sustained HUD/inventory, with an explicit Minecraft walking profile.
[CmdletBinding()]
param([string]$BundleDirectory,[string]$InstanceDirectory,[string]$JavaHome='C:/Program Files/Java/jdk-24',
 [ValidateRange(0,300)][int]$SmokeSeconds=0,[switch]$PreflightOnly,[switch]$HideNativeVitals,[switch]$Movement,[switch]$Blocks,[switch]$Explore,[switch]$Chat,[switch]$Flight,[switch]$Hands,[switch]$WorldBlocks,[switch]$Combat,[switch]$CombatCheck,[switch]$IncomingCombatCheck,[ValidateSet('unarmed','sword','bow','crossbow')][string]$IncomingWeapon='unarmed',[switch]$ProjectileCheck,[string]$CombatFixtureRun,[string]$GroundPatchFile,[switch]$ThirdPersonWalkingCheck,[switch]$DropsCheck,[switch]$CraftingCheck,[switch]$FurnaceCheck,[switch]$TntCheck,[switch]$TntCombatCheck,[switch]$RespawnCheck,[ValidateRange(0,1)][int]$InitialTerrainRadius=0)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay session failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
. (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'GameplayMovementHost.ps1')
. (Join-Path $PSScriptRoot 'GameplayHudSessionGuard.ps1')
if($TntCombatCheck){$TntCheck=$true;$Combat=$true;$InitialTerrainRadius=1}
if($IncomingCombatCheck){$InitialTerrainRadius=1}
elseif($IncomingWeapon -cne 'unarmed'){throw 'IncomingWeapon requires IncomingCombatCheck.'}
if($RespawnCheck){$InitialTerrainRadius=1}
if($InitialTerrainRadius -eq 1){$Explore=$true}
if($ProjectileCheck -and -not $CombatCheck){throw 'ProjectileCheck requires the owned CombatCheck.'}
if($CombatCheck -or $TntCombatCheck -or $IncomingCombatCheck){if($CombatFixtureRun -cnotmatch '^[0-9a-f]{32}$'){throw 'Use the Test-Kcd combat wrapper to own the isolated NPC lifecycle.'};$Combat=$true}
elseif($CombatFixtureRun){throw 'CombatFixtureRun requires the owned automated combat or TNT combat check.'}
if($Combat){$WorldBlocks=$true};if($WorldBlocks){$Hands=$true};if($Hands){$Flight=$true};if($Flight){$Chat=$true}
if($Explore -or $Chat){$Blocks=$true};if($Blocks){$Movement=$true}
if($IncomingCombatCheck -and ($SmokeSeconds -ne 0 -or $CombatCheck -or $ProjectileCheck -or $TntCheck -or $TntCombatCheck -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck -or $FurnaceCheck -or $RespawnCheck)){throw 'IncomingCombatCheck owns its bounded session; omit other checks/SmokeSeconds.'}
if($CombatCheck -and ($SmokeSeconds -ne 0 -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck -or $FurnaceCheck -or $RespawnCheck)){throw 'CombatCheck owns its bounded session; omit other checks/SmokeSeconds.'}
if($RespawnCheck -and (-not $WorldBlocks -or $SmokeSeconds -ne 0 -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck -or $FurnaceCheck)){throw 'RespawnCheck requires WorldBlocks and owns its bounded duration; omit other checks/SmokeSeconds.'}
if($TntCheck -and (-not $WorldBlocks -or $SmokeSeconds -ne 0 -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck -or $FurnaceCheck -or $RespawnCheck -or $CombatCheck)){throw 'TntCheck requires WorldBlocks and owns its bounded duration; omit other checks/SmokeSeconds.'}
if($FurnaceCheck -and (-not $WorldBlocks -or $SmokeSeconds -ne 0 -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck)){throw "FurnaceCheck requires WorldBlocks and owns its bounded duration; omit other checks/SmokeSeconds."}
if($CraftingCheck -and (-not $WorldBlocks -or $SmokeSeconds -ne 0 -or $ThirdPersonWalkingCheck -or $DropsCheck)){throw "CraftingCheck requires WorldBlocks and owns its bounded duration; omit other checks/SmokeSeconds."}
if($DropsCheck -and (-not $WorldBlocks -or $SmokeSeconds -ne 0 -or $ThirdPersonWalkingCheck)){throw "DropsCheck requires WorldBlocks and owns its bounded duration; omit other checks/SmokeSeconds."}
if($ThirdPersonWalkingCheck -and (-not $WorldBlocks -or $SmokeSeconds -ne 0)){throw 'ThirdPersonWalkingCheck requires WorldBlocks and owns its bounded duration; omit SmokeSeconds.'}
if($HideNativeVitals -and -not $Movement){throw 'HideNativeVitals requires the movement session that owns its cleanup lease.'}
if(-not $Movement -and $GroundPatchFile){throw 'GroundPatchFile requires Movement.'}
if(-not $BundleDirectory){$BundleDirectory=Join-Path $root $(if($Chat){'runtime/hud-compositor-gameplay-chat'}elseif($Blocks){'runtime/hud-compositor-gameplay-blocks'}elseif($Movement){'runtime/hud-compositor-gameplay-movement'}else{'runtime/hud-compositor-gameplay'})}
$installation=Get-MineComeGameplayInstallation -BundleDirectory $BundleDirectory -RequireUnarmed -Movement:$Movement -Blocks:$Blocks -Chat:$Chat
$context=Get-MineComeProbeContext
if($context.GamePath -ine $installation.ToolsExe){throw 'Installed HUD and running game differ.'}
Assert-GameplayHudSessionUnused $context $installation.ToolsBin
if(-not $InstanceDirectory){$InstanceDirectory=Join-Path $root 'runtime/gameplay/instance'}
$InstanceDirectory=[IO.Path]::GetFullPath($InstanceDirectory)
if(-not $InstanceDirectory.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Gameplay instance must stay inside the project.'}
if(-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))){throw 'Select an installed JDK.'}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'"|Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$root+'*')})
if($clients.Count){throw 'A MineCome client is already open; preserving its session.'}
if($PreflightOnly){Write-Output 'GAMEPLAY_SESSION_PREFLIGHT_PASS no_changes=true';return}
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/gameplay-kcd-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$targetStart=$context.GameStartedUtc.ToFileTimeUtc().ToString()
$expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+86400000L
$arm=Join-Path $installation.ToolsBin $installation.Profile.arm_config_relative_path
$renderLog=Join-Path $installation.ToolsBin 'ReShade.log'
$logOffset=if(Test-Path -LiteralPath $renderLog){(Get-Item -LiteralPath $renderLog).Length}else{0L}
$helper=$null;$armText=$null;$armWritten=$false;$passed=$false;$failure=$null;$smokeStop=$false
$hostFollower=$null;$hostProof=$null;$patch=$null
$incomingFixtureProbe=$null;$incomingFixtureStarted=$false;$incomingFixtureRemoved=$false
function Stop-IncomingCombatFixture {
 if(-not $incomingFixtureStarted -or $script:incomingFixtureRemoved){return}
 Invoke-MineComeProbeConsole $context "#MineCome.GameplayCombatFixtureEnd('$CombatFixtureRun')"|Out-Null
 $until=[DateTime]::UtcNow.AddSeconds(3)
 do{
  Invoke-MineComeProbeConsole $context "#System.LogAlways('[MineComeIncomingFixtureCleanup] $CombatFixtureRun')"|Out-Null
  $records=@(Get-MineComeProbeReceipts (Read-MineComeProbeLog $context $incomingFixtureProbe.Offset) 'MineComeCombatFixture' $CombatFixtureRun)
  $script:incomingFixtureRemoved=@($records|Where-Object {$_.event -ceq 'terminal' -and $_.removed -eq $true -and $_.path_restored -eq $true -and $_.active -eq $false}).Count -gt 0
  if(-not $script:incomingFixtureRemoved){Start-Sleep -Milliseconds 50}
 }while(-not $script:incomingFixtureRemoved -and [DateTime]::UtcNow -lt $until)
 [ordered]@{schema=1;run=$CombatFixtureRun;started=$incomingFixtureStarted;removed=$script:incomingFixtureRemoved;receipts=$records}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $directory 'incoming-fixture-native.json') -Encoding utf8NoBOM
 if(-not $script:incomingFixtureRemoved){throw 'Incoming combat fixture removal was not confirmed.'}
}
try{
 if($IncomingCombatCheck){$incomingFixtureProbe=New-MineComeProbeRun $context 'incoming-combat-fixture' (Join-Path $root 'kcd2/gameplay/combat_fixture.lua') 'GameplayCombatFixtureBegin'}
 if($Movement){
  $bindingDirectory=Join-Path $InstanceDirectory 'saves/MineCome-Gameplay/minecome-terrain'
  $cached=Join-Path $bindingDirectory 'ground-patch.json'
  if(Test-Path -LiteralPath $bindingDirectory){
   # A persisted capture keeps its origin across launches. It is not represented
   # as a new capture from this process; the native follower checks local bounds.
   $binding=Read-MineComeGameplayJson (Join-Path $bindingDirectory 'binding.json')
   $data=Read-MineComeGameplayJson $cached;$hash=Get-MineComeGameplayHash $cached
   if($binding.schema -ne 1 -or $binding.kind -cne 'minecome_gameplay_terrain_v1' -or
      $binding.patch_sha256 -cne $hash -or $binding.patch_run -cne $data.run -or
      $data.provenance.kind -cne 'live_kcd_ground_patch' -or $data.provenance.game_exe_hash -ine $context.GameHash){throw 'Saved gameplay terrain identity differs.'}
   if($GroundPatchFile -and (Get-MineComeGameplayHash $GroundPatchFile) -cne $hash){throw 'This save is already bound to different terrain; preserving it.'}
   $patch=[pscustomobject]@{Path=$cached;Hash=$hash;Run=$data.run;Data=$data}
  }else{
   if(-not $GroundPatchFile){
    $capture=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch -WideWalking | ForEach-Object {
     if($_ -isnot [string] -and $_.PSObject.Properties['GroundPatchFile']){$_}elseif($_ -is [string]){Add-Content -LiteralPath (Join-Path $directory 'terrain-capture.log') -Value $_ -Encoding utf8}
    })
    if($capture.Count -ne 1){throw 'No complete live terrain capture.'};$GroundPatchFile=$capture[0].GroundPatchFile
   }
   $patch=Read-HudLiveGroundPatch $GroundPatchFile $root $context -WideWalking
  }
 }
 $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-GameplayClient.ps1'),'-EvidenceDirectory',$directory,
  '-InstanceDirectory',$InstanceDirectory,'-Run',$run,'-TargetPid',[string]$context.GamePid,'-TargetStart',$targetStart,
  '-Expires',[string]$expires,'-JavaHome',$JavaHome,'-Connected')
 if($Movement){$arguments+=@('-Movement','-GroundPatchFile',$patch.Path)}
 if($Blocks){$arguments+='-Blocks'}
 if($Explore){$arguments+='-Explore'}
 if($Chat){$arguments+='-Chat'}
 if($Flight){$arguments+='-Flight'}
 if($Hands){$arguments+='-Hands'};if($WorldBlocks){$arguments+='-WorldBlocks'};if($Combat){$arguments+='-Combat'}
 if($CombatCheck){$arguments+='-CombatCheck'};if($ProjectileCheck){$arguments+='-ProjectileCheck'}
 if($IncomingCombatCheck){$arguments+=@('-IncomingCombatCheck','-IncomingWeapon',$IncomingWeapon)}
 if($RespawnCheck){$arguments+='-RespawnCheck'}
 if($TntCheck){$arguments+='-TntCheck'}
 if($TntCombatCheck){$arguments+='-TntCombatCheck'}
 if($FurnaceCheck){$arguments+='-FurnaceCheck'}
 if($CraftingCheck){$arguments+='-CraftingCheck'}
 if($DropsCheck){$arguments+='-DropsCheck'}
 if($ThirdPersonWalkingCheck){$arguments+='-ThirdPersonWalkingCheck'}
 $quoted=@($arguments|ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
 $helper=Start-Process -FilePath (Get-MineComePowerShell7) -ArgumentList ([string]::Join(' ',$quoted)) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'client.log') -RedirectStandardError (Join-Path $directory 'client-errors.log')
 $deadline=[DateTime]::UtcNow.AddSeconds(120);$ready=$null
 $readyPath=Join-Path $directory 'capture/stream-ready.json'
 do{
  if((Test-Path -LiteralPath $readyPath) -and (Test-Path -LiteralPath (Join-Path $directory 'gameplay-ready.json'))){$ready=Get-Content -LiteralPath $readyPath -Raw|ConvertFrom-Json;break}
  if($helper.HasExited){throw 'Gameplay client exited before readiness; inspect its logs.'}
  Start-Sleep -Milliseconds 50
 }while([DateTime]::UtcNow -lt $deadline)
 if(-not $ready -or $ready.schema -ne 3 -or $ready.session_kind -cne 'gameplay' -or $ready.run -cne $run -or
  $ready.save -cne 'MineCome-Gameplay' -or $ready.target_pid -ne $context.GamePid -or $ready.target_start_filetime -cne $targetStart -or $ready.expires_utc_ms -ne $expires){throw 'Gameplay stream readiness identity differs.'}
 if($ready.ui_input_protocol -ne $(if($Chat){6}elseif($Blocks){5}elseif($Movement){4}else{3})){throw 'Gameplay input profile differs.'}
 if($ready.frame_format -ne $(if($WorldBlocks){2}else{1}) -or $ready.mapping_bytes -ne (256+1920*1080*12)){throw 'Gameplay frame layout differs.'}
 $producer=Get-Process -Id $ready.producer_pid
 try{if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $ready.producer_start_filetime -or $producer.Path -ine (Join-Path $JavaHome 'bin/java.exe')){throw 'Gameplay producer identity changed.'}}finally{$producer.Dispose()}
 Assert-MineComeProbeContext $context
 if($Movement){
  $guest=Read-MineComeGameplayJson (Join-Path $directory 'gameplay-ready.json')
  if($TntCombatCheck){
   $fixtureOffset=(Get-Item -LiteralPath $context.GameLog).Length
   Invoke-MineComeProbeConsole $context ("#local ok,why=MineCome.GameplayTntCombatFixtureBegin('$CombatFixtureRun',120000);System.LogAlways('[MineComeTntCombatFixtureCall] $CombatFixtureRun '..tostring(ok)..' '..tostring(why))")
   $fixtureUntil=[DateTime]::UtcNow.AddSeconds(2);$fixtureSpawned=$false
   do{
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeTntCombatFixtureFlush] $CombatFixtureRun')")
    $fixtureReceipts=@(Get-MineComeProbeReceipts (Read-MineComeProbeLog $context $fixtureOffset) 'MineComeTntCombatFixture' $CombatFixtureRun)
    $fixtureSpawned=@($fixtureReceipts|Where-Object {$_.event -ceq 'begin' -and $_.result -ceq 'spawned' -and @($_.actors).Count -eq 2}).Count -eq 1
    if($fixtureSpawned){break};Start-Sleep -Milliseconds 25
   }while([DateTime]::UtcNow -lt $fixtureUntil)
   if(-not $fixtureSpawned){throw 'The isolated TNT NPCs were not confirmed; combat was not armed.'}
  }
  if($CombatCheck){
   # The official test NPC's behaviour eventually despawns it. Create it only
   # after Minecraft has loaded, keeping the real attack inside its lifetime.
   $fixtureOffset=(Get-Item -LiteralPath $context.GameLog).Length
   Invoke-MineComeProbeConsole $context ("#local p=player:GetWorldPos();local h=player.actor:GetHeadPos();local d=player.actor:GetHeadDir();local ok,why=MineCome.GameplayCombatFixtureBegin('$CombatFixtureRun',120000,h.x+d.x*1.5,h.y+d.y*1.5,p.z);System.LogAlways('[MineComeCombatFixtureCall] $CombatFixtureRun '..tostring(ok)..' '..tostring(why))")
   $fixtureUntil=[DateTime]::UtcNow.AddSeconds(2);$fixtureSpawned=$false
   do{
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeCombatFixtureFlush] $CombatFixtureRun')")
    $fixtureReceipts=@(Get-MineComeProbeReceipts (Read-MineComeProbeLog $context $fixtureOffset) 'MineComeCombatFixture' $CombatFixtureRun)
    $fixtureSpawned=@($fixtureReceipts|Where-Object {$_.event -ceq 'begin' -and $_.result -ceq 'spawned'}).Count -eq 1
    if($fixtureSpawned){break};Start-Sleep -Milliseconds 25
   }while([DateTime]::UtcNow -lt $fixtureUntil)
   if(-not $fixtureSpawned){throw 'The isolated NPC was not confirmed; combat was not armed.'}
  }
  $hostFollower=Start-GameplayMovementHost -Context $context -Run $run -WorldId $guest.world_id -Patch $patch -PoseFile (Join-Path $directory 'gameplay-pose.json') -ViewFile (Join-Path $directory 'host-view.json') -ExpiresUtcMs $expires -Blocks:$Blocks -Explore:$Explore -TerrainCacheFile (Join-Path $bindingDirectory 'coverage.json') -Flight:$Flight -WorldBlocks:$WorldBlocks -InitialTerrainRadius $InitialTerrainRadius -Combat:$Combat -HideNativeVitals:$HideNativeVitals
  $movementPath=Join-Path $directory 'gameplay-movement-ready.json';$until=[DateTime]::UtcNow.AddSeconds(12)
  while(-not (Test-Path -LiteralPath $movementPath)){
   $state=Get-GameplayMovementHostState $hostFollower
   if($state.Failure -or $state.Stopped){throw "Gameplay follower failed during attachment: $($state.Failure)"}
   if($helper.HasExited -or [DateTime]::UtcNow -gt $until){throw 'Gameplay terrain attachment did not become ready.'}
   Start-Sleep -Milliseconds 20
  }
  $attached=Read-MineComeGameplayJson $movementPath
  if(-not $attached.ready -or $attached.fixture -or $attached.run -cne $run -or $attached.world_id -cne $guest.world_id -or $attached.patch_sha256 -cne $patch.Hash){throw 'Gameplay movement attachment proof differs.'}
 }
 $armText="[HudStream]`nSchema=3`nRun=$run`nTargetPid=$($context.GamePid)`nTargetStart=$targetStart`nProducerPid=$($ready.producer_pid)`nProducerStart=$($ready.producer_start_filetime)`nExpiresUtcMs=$expires`n"
 $file=[IO.FileStream]::new($arm,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try{$bytes=[Text.Encoding]::UTF8.GetBytes($armText);$file.Write($bytes,0,$bytes.Length);$file.Flush($true);$armWritten=$true}finally{$file.Dispose()}
 [IO.File]::WriteAllText((Join-Path $directory 'arm.ini'),$armText)
 Write-Output "GAMEPLAY_READY run=$run stop_file=$(Join-Path $directory 'session.stop')"
 if($ProjectileCheck){Write-Output 'AUTOMATED_PROJECTILE_CHECK: actual vanilla bow arrows against native NPCs and scenery; no physical input or reciprocal native damage claim.'}
 elseif($CombatCheck){Write-Output 'AUTOMATED_COMBAT_CHECK: production native NPC snapshots and vanilla primary melee; no physical input or reciprocal native damage claim.'}
 if($RespawnCheck){Write-Output 'AUTOMATED_RESPAWN_CHECK: keep KCD2 focused; scripted guest walking, death and a real Respawn-button click verify native relocation and continued play. Physical input is not claimed.'}
 if($TntCheck){Write-Output 'AUTOMATED_TNT_CHECK: actual vanilla priming, chain explosions, owned block destruction and saved cleanup; no physical input or native geometry destruction claim.'}
 if($FurnaceCheck){Write-Output 'AUTOMATED_FURNACE_CHECK: keep KCD2 focused; actual guest UI clicks load fuel/input, smelt and collect output, then save. Physical input is not claimed.'}
 if($CraftingCheck){Write-Output 'AUTOMATED_CRAFTING_CHECK: keep KCD2 focused; real guest UI clicks craft ingredients/table/tool, verify unused-input return, then save. Physical input is not claimed.'}
 if($DropsCheck){Write-Output 'AUTOMATED_DROPS_CHECK: keep KCD2 focused and controls released; scripted guest actions mine, render and walk to collect a drop, then save. Physical mouse/keys are not claimed.'}
 if($ThirdPersonWalkingCheck){Write-Output 'AUTOMATED_THIRD_PERSON_WALKING_CHECK: keep KCD2 focused and controls released; the guest will test back/front walking, inventory suppression and first-person return, then save and close. Physical keyboard input is not claimed by this check.'}
 if($Explore){Write-Output 'Terrain grows automatically toward your movement, up to 64 captured tiles. Saved terrain and construction keep their original coordinates.'}
 if($Chat){Write-Output 'T opens Minecraft chat; / opens commands. Type a command and press Enter; Escape cancels. Walking and mining pause while chat is open.'}
 if($Hands){Write-Output $(if($WorldBlocks){'Minecraft hands and Steve use the layered HUD stream. F5 requests first/back/front perspective while inventory and chat are closed; the view changes after native camera acknowledgement.'}else{'Minecraft first-person hands and held items share the HUD stream. Inventory hides them; use WorldBlocks for Steve and F5 perspective controls.'})}
 if($Flight){Write-Output 'Creative flight: /gamemode creative, double-tap Space to toggle; Space rises, Shift descends, Ctrl sprints. Flight stays within captured terrain and its vertical limit; F8 saves airborne position.'}
 Write-Output $(if($WorldBlocks){'Minecraft models render owned solid blocks. Right-click places supported held blocks; left-click mines. E opens inventory; F8 saves. Captured ground occludes blocks. Native scenery depth is used when camera/projection checks match.'}elseif($Blocks){'Focus KCD2 with controls released. Walking, HUD and stone controls activate automatically: right-click places held stone, left-click mines owned stone. E opens inventory; F8 stops and saves. Terrain coverage and owned stone capacity are bounded.'}elseif($Movement){'Focus KCD2 with controls released. Minecraft walking and HUD activate automatically. F8 stops and saves at the last safe position. Walking is limited to the captured terrain; blocks, commands and flight are not connected in this path yet.'}else{'Focus KCD2 with controls released. HUD activates automatically; F8 stops and saves. KCD owns walking; Minecraft commands/flight are not connected yet.'})
 $smokeDeadline=[DateTime]::UtcNow.AddSeconds($SmokeSeconds);$projectileFixtureRemoved=$false
 while(-not $helper.HasExited){
  if($IncomingCombatCheck -and -not $incomingFixtureStarted -and (Test-Path -LiteralPath (Join-Path $directory 'incoming-fixture-ready.json'))){
   $readyFixture=Read-MineComeGameplayJson (Join-Path $directory 'incoming-fixture-ready.json')
   Assert-GameplayCombatKeys $readyFixture @('schema','kind','world_id')
   if($readyFixture.schema -ne 1 -or $readyFixture.kind -cne 'minecome_native_incoming_fixture_ready_v1' -or $readyFixture.world_id -cne $guest.world_id){throw 'Incoming fixture readiness identity differs.'}
   $incomingState=Get-GameplayMovementHostState $hostFollower
   if($incomingState.Combat -and $incomingState.Combat.Incoming -and $incomingState.Combat.Incoming.Begin){
    $incomingFixtureStarted=$true
    $incomingMode=if($IncomingWeapon -ceq 'unarmed'){'hostile'}else{'hostile_'+$IncomingWeapon}
    $incomingDistance=if($IncomingWeapon -cin @('bow','crossbow')){6}else{2}
    Invoke-MineComeProbeConsole $context "#local p=player:GetWorldPos();local d=player.actor:GetHeadDir();local len=math.sqrt(d.x*d.x+d.y*d.y);if len>.1 then local ok,why=MineCome.GameplayCombatFixtureBegin('$CombatFixtureRun',60000,p.x+d.x/len*$incomingDistance,p.y+d.y/len*$incomingDistance,p.z,'$incomingMode');System.LogAlways('[MineComeIncomingFixtureSpawn] '..tostring(ok)..' '..tostring(why)) end"|Out-Null
    $spawnDeadline=[DateTime]::UtcNow.AddSeconds(2);$spawned=$false
    do{
     Invoke-MineComeProbeConsole $context "#System.LogAlways('[MineComeIncomingFixtureReady] $CombatFixtureRun')"|Out-Null
     $spawnReceipts=@(Get-MineComeProbeReceipts (Read-MineComeProbeLog $context $incomingFixtureProbe.Offset) 'MineComeCombatFixture' $CombatFixtureRun)
     $spawned=@($spawnReceipts|Where-Object {$_.event -ceq 'begin' -and $_.mode -ceq $incomingMode -and $_.active -eq $true}).Count -eq 1
     if(-not $spawned){Start-Sleep -Milliseconds 50}
    }while(-not $spawned -and [DateTime]::UtcNow -lt $spawnDeadline)
    if(-not $spawned){throw 'Incoming hostile spawn was not confirmed; use a horizontal native view.'}
   }
  }
  if($IncomingCombatCheck -and $incomingFixtureStarted -and -not $incomingFixtureRemoved -and (Test-Path -LiteralPath (Join-Path $directory 'incoming-fixture-remove.json'))){
   $remove=Read-MineComeGameplayJson (Join-Path $directory 'incoming-fixture-remove.json')
   Assert-GameplayCombatKeys $remove @('schema','kind','world_id')
   if($remove.schema -ne 1 -or $remove.kind -cne 'minecome_native_incoming_fixture_remove_v1' -or $remove.world_id -cne $guest.world_id){throw 'Incoming fixture removal identity differs.'}
   Stop-IncomingCombatFixture
   $text=[ordered]@{schema=1;world_id=$guest.world_id;removed=$true}|ConvertTo-Json -Compress
   $temporary=Join-Path $directory 'incoming-fixture-removed.tmp';[IO.File]::WriteAllText($temporary,$text);[IO.File]::Move($temporary,(Join-Path $directory 'incoming-fixture-removed.json'),$false)
  }
  if($ProjectileCheck -and -not $projectileFixtureRemoved -and (Test-Path -LiteralPath (Join-Path $directory 'projectile-fixture-remove.json'))){
   $remove=Read-MineComeGameplayJson (Join-Path $directory 'projectile-fixture-remove.json')
   Assert-GameplayCombatKeys $remove @('schema','kind','world_id','actor_token')
   if($remove.schema -ne 1 -or $remove.kind -cne 'minecome_native_projectile_fixture_remove_v1' -or $remove.world_id -cne $guest.world_id -or $remove.actor_token -ne 1){throw 'Projectile fixture removal identity differs.'}
   $removeOffset=(Get-Item -LiteralPath $context.GameLog).Length
   Invoke-MineComeProbeConsole $context "#MineCome.GameplayCombatFixtureEnd('$CombatFixtureRun')"|Out-Null
   $removeDeadline=[DateTime]::UtcNow.AddSeconds(3)
   do{
    Invoke-MineComeProbeConsole $context "#System.LogAlways('[MineComeProjectileFixtureRemove] $CombatFixtureRun')"|Out-Null
    $removedReceipts=@(Get-MineComeProbeReceipts (Read-MineComeProbeLog $context $removeOffset) 'MineComeCombatFixture' $CombatFixtureRun)
    $projectileFixtureRemoved=@($removedReceipts|Where-Object {$_.event -ceq 'terminal' -and $_.removed -eq $true -and $_.path_restored -eq $true -and $_.active -eq $false}).Count -gt 0
    if(-not $projectileFixtureRemoved){Start-Sleep -Milliseconds 50}
   }while(-not $projectileFixtureRemoved -and [DateTime]::UtcNow -lt $removeDeadline)
   if(-not $projectileFixtureRemoved){throw 'Owned NPC removal before ground shot was not confirmed.'}
   $removedText=[ordered]@{schema=1;world_id=$guest.world_id;removed=$true}|ConvertTo-Json -Compress
   $removedTemporary=Join-Path $directory 'projectile-fixture-removed.tmp'
   [IO.File]::WriteAllText($removedTemporary,$removedText);[IO.File]::Move($removedTemporary,(Join-Path $directory 'projectile-fixture-removed.json'),$false)
  }
  if($hostFollower){
   $stoppingPath=Join-Path $directory 'gameplay-stopping.json'
   if(-not $hostFollower.Final -and (Test-Path -LiteralPath $stoppingPath)){
    $stopping=Read-MineComeGameplayJson $stoppingPath
    if($stopping.schema -ne 1 -or $stopping.kind -cne 'minecome_gameplay_stopping_v1' -or $stopping.run -cne $run){throw 'Gameplay stop notice identity differs.'}
    if($IncomingCombatCheck){Stop-IncomingCombatFixture}
    $hostProof=Stop-GameplayMovementHost $hostFollower
   }
   $state=Get-GameplayMovementHostState $hostFollower
   # A normal guest shutdown stops pose publication first. Let its existing
   # stop receipt finish; an unexpected follower failure stops/saves the guest.
   if(($state.Failure -or $state.Stopped) -and -not $hostFollower.Final -and -not $smokeStop){throw "Gameplay follower stopped: $($state.Failure)"}
  }
  if($SmokeSeconds -gt 0 -and -not $smokeStop -and [DateTime]::UtcNow -ge $smokeDeadline){
   [IO.File]::WriteAllText((Join-Path $directory 'session.stop'),'automated smoke complete');$smokeStop=$true
  }
  if($smokeStop -and [DateTime]::UtcNow -gt $smokeDeadline.AddSeconds(15)){throw 'Smoke stop did not finish normal save/shutdown.'}
  Start-Sleep -Milliseconds 100
 }
 if($helper.ExitCode -ne 0){throw "Gameplay client exit code $($helper.ExitCode)."}
 $stream=Get-Content -LiteralPath (Join-Path $directory 'capture/stream-result.json') -Raw|ConvertFrom-Json -Depth 24
 $session=Get-Content -LiteralPath (Join-Path $directory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
 if($stream.schema -ne 3 -or $stream.result -cne 'stopped' -or $session.run -cne $run -or $session.failure -or
  -not $session.producer_finished -or $session.producer_failure -or -not $session.controls_released -or -not $session.normal_shutdown_requested -or
  -not $session.input_connected -or -not $session.input_armed_seen){throw 'Gameplay native input/save/shutdown proof failed.'}
 if($Movement -and (-not $session.movement.ready -or $session.movement.failure -or -not $session.movement.cleanup_complete)){throw 'Gameplay movement/save/cleanup proof failed.'}
 if($Blocks -and (-not $session.blocks.ready -or $session.blocks.failure -or -not $session.blocks.cleanup_complete)){throw 'Gameplay block ledger/save proof failed.'}
 if($Combat -and (-not $session.combat.cleanup_complete -or $session.combat.pending -or ($session.combat.PSObject.Properties['failure'] -and $session.combat.failure))){throw 'Gameplay combat cleanup/acknowledgment proof incomplete.'}
 if($ThirdPersonWalkingCheck){
  $f=$session.fixture
  if($f.kind -cne 'minecome_native_third_person_walking_v1' -or $f.result -cne 'passed' -or $f.failure -or -not $f.actual_minecraft -or -not $f.scripted_guest_input -or $f.physical_native_keys_verified -or $f.position_writes_used -or $f.velocity_writes_used -or $f.camera_writes_used -or
   -not $f.back_walking_verified -or -not $f.front_walking_verified -or -not $f.inventory_suppression_verified -or -not $f.first_person_return_verified -or @($f.images).Count -ne 8 -or $session.movement.movement_events -lt 2 -or $session.movement.held_ticks -lt 8 -or -not $session.native_perspective_connected -or $session.native_perspective_last_acknowledged -ne 0){throw 'Native third-person walking acceptance proof incomplete.'}
 }
 if($RespawnCheck){
  $f=$session.fixture;$r=$session.respawn;$m=$session.movement
  if($f.kind -cne 'minecome_gameplay_respawn_fixture_v1' -or $f.mode -cne 'respawn-native' -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or $f.standalone_scripted -or $f.native_input_verified -or $f.position_writes_used -or $f.direct_respawn_request_used){throw 'Native respawn fixture identity/scope differs.'}
  foreach($flag in @('construction_placement_verified','death_verified','death_drops_verified','respawn_button_verified','respawn_verified','construction_preserved_verified','walking_after_respawn_verified','render_pixels_verified','client_player_replaced','server_player_replaced')){
   if($f.$flag -ne $true){throw "Native respawn capability missing: $flag"}
  }
  if(-not $r.native_required -or $r.pending -or ($r.PSObject.Properties['failure'] -and $r.failure) -or $f.respawn_epoch -ne 1 -or $f.respawn_pending -or
   $r.death_ack_epoch -ne 1 -or $r.respawn_ack_epoch -ne 1 -or $r.client_rebound_epoch -ne 1 -or
   $m.death_pending -or $m.respawn_pending -or $m.server_respawns -ne 1 -or $m.client_respawns -ne 1 -or $m.death_acknowledged -ne 1 -or $m.respawn_acknowledged -ne 1){throw 'Native respawn replacement/acknowledgment proof incomplete.'}
 }
 if($TntCheck){
  if(-not $session.PSObject.Properties['fixture']){throw "Native TNT check ended before completion: stop_reason=$($session.stop_reason). Inspect native-hud.log and gameplay-session.json."}
  $f=$session.fixture
  if($f.kind -cne 'minecome_gameplay_tnt_fixture_v1' -or $f.mode -cne $(if($TntCombatCheck){'tnt-combat-native'}else{'tnt-native'}) -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or $f.standalone_scripted -or $f.native_input_verified -or $f.position_writes_used){throw 'Native TNT fixture identity/scope differs.'}
  foreach($flag in @('tnt_placement_verified','ignition_verified','fuse_verified','chain_reaction_verified','fragile_destruction_verified','resistant_preservation_verified','tool_durability_verified','ledger_removal_verified','render_pixels_verified')){
   if($f.$flag -ne $true){throw "Native TNT capability missing: $flag"}
  }
 }
 if($FurnaceCheck){
  $f=$session.fixture
  if($f.kind -cne 'minecome_gameplay_furnace_fixture_v1' -or $f.mode -cne 'furnace-native' -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or $f.standalone_scripted -or $f.native_input_verified -or $f.position_writes_used){throw 'Native furnace fixture identity/scope differs.'}
  foreach($flag in @('furnace_placement_verified','furnace_open_verified','smelting_verified','fuel_consumption_verified','inventory_suppression_verified','output_collection_verified','render_pixels_verified')){
   if($f.$flag -ne $true){throw "Native furnace capability missing: $flag"}
  }
 }
 if($CraftingCheck){
  $f=$session.fixture
  if($f.kind -cne 'minecome_gameplay_crafting_fixture_v1' -or $f.mode -cne 'crafting-native' -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or $f.standalone_scripted -or $f.native_input_verified -or $f.position_writes_used){throw 'Native crafting fixture identity/scope differs.'}
  foreach($flag in @('inventory_crafting_verified','table_placement_verified','table_open_verified','table_crafting_verified','ingredient_return_verified','inventory_suppression_verified','render_pixels_verified')){
   if($f.$flag -ne $true){throw "Native crafting capability missing: $flag"}
  }
 }
 if($DropsCheck){
  $f=$session.fixture
  if($f.kind -cne 'minecome_gameplay_drops_fixture_v1' -or $f.mode -cne 'drops-native' -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or $f.standalone_scripted -or $f.native_input_verified -or $f.position_writes_used){throw 'Native drop fixture identity/scope differs.'}
  foreach($flag in @('survival_placement_verified','survival_mining_verified','real_drop_verified','drop_ground_collision_verified','render_pixels_verified','walking_pickup_verified','durability_verified')){
   if($f.$flag -ne $true){throw "Native drop capability missing: $flag"}
  }
 }
 if($SmokeSeconds -gt 0 -and (-not $smokeStop -or $session.active_ms -lt $SmokeSeconds*1000)){throw 'Gameplay smoke ended before the requested sustained duration.'}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 if($IncomingCombatCheck){try{Stop-IncomingCombatFixture}catch{$passed=$false;$failure=$_.Exception.Message}}
 if($helper -and -not $helper.HasExited){[IO.File]::WriteAllText((Join-Path $directory 'session.stop'),'launcher cleanup');[void]$helper.WaitForExit(10000)}
 if($hostFollower){
  try{
   $hostProof=Stop-GameplayMovementHost $hostFollower
   $hostProof|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $directory 'host-movement.json') -Encoding utf8NoBOM
   if(-not $hostProof.ResourcesClosed -or -not $hostProof.Terminal -or $hostProof.PoseCount -lt 1 -or $hostProof.Failure){$passed=$false;$failure='Gameplay host cleanup/pose proof incomplete: '+$hostProof.Failure}
   if($Blocks -and -not $WorldBlocks -and (-not $hostProof.Blocks -or -not $hostProof.Blocks.CleanupComplete -or $hostProof.Blocks.Failure)){$passed=$false;$failure='Gameplay native block cleanup proof incomplete.'}
   if($Combat -and (-not $hostProof.Combat -or -not $hostProof.Combat.CleanupComplete -or $hostProof.Combat.Failure)){$passed=$false;$failure='Gameplay native combat cleanup proof incomplete.'}
   if($Explore -and (-not $hostProof.Terrain -or -not $hostProof.Terrain.CleanupComplete -or $hostProof.Terrain.Failure)){$passed=$false;$failure='Gameplay native terrain cleanup proof incomplete.'}
  }catch{$passed=$false;$failure='Gameplay host cleanup: '+$_.Exception.Message}
 }
 if($armWritten -and (Test-Path -LiteralPath $arm)){
  if([IO.File]::ReadAllText($arm) -ceq $armText){Remove-Item -LiteralPath $arm}else{$passed=$false;$failure='Arm changed; preserved instead of removing it.'}
 }
 if(Test-Path -LiteralPath $renderLog){
  $reader=[IO.FileStream]::new($renderLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  try{
   if($reader.Length -ge $logOffset -and $reader.Length-$logOffset -le 8MB){
    $reader.Position=$logOffset;$copy=[IO.StreamReader]::new($reader);try{[IO.File]::WriteAllText((Join-Path $directory 'native-hud.log'),$copy.ReadToEnd())}finally{$copy.Dispose()}
   }
  }finally{$reader.Dispose()}
 }
 [ordered]@{schema=1;kind='minecome_gameplay_kcd_session_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  target_pid=$context.GamePid;target_start_filetime=$targetStart;instance=$InstanceDirectory;smoke_seconds=$SmokeSeconds;
  minecraft_movement_connected=[bool]($Movement -and $passed);movement_profile=[bool]$Movement;blocks_profile=[bool]$Blocks;explore_profile=[bool]$Explore;chat_profile=[bool]$Chat;flight_profile=[bool]$Flight;hands_profile=[bool]$Hands;world_blocks_profile=[bool]$WorldBlocks;drops_check=[bool]$DropsCheck;crafting_check=[bool]$CraftingCheck;furnace_check=[bool]$FurnaceCheck;tnt_check=[bool]$TntCheck;tnt_combat_check=[bool]$TntCombatCheck;respawn_check=[bool]$RespawnCheck;combat_profile=[bool]$Combat;combat_check=[bool]$CombatCheck;hide_native_vitals=[bool]$HideNativeVitals;host_command_typing_verified=$false;normal_client_exit=($helper -and $helper.HasExited -and $helper.ExitCode -eq 0)}|
  ConvertTo-Json|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
if(-not $passed){throw $failure}
Write-Output "GAMEPLAY_SESSION_SAVED evidence=$directory"
