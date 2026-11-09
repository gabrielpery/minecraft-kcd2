#Requires -Version 7.3
# Focused launcher selection/readback; no game launch or mutation in this file.
. (Join-Path $PSScriptRoot 'GameplayHudProfile.ps1')
function Get-MineComePlayPlan([string]$BundleDirectory){
 $profile=Get-MineComeGameplayProfile -Chat;$bin=Get-MineComeGameplayToolsBin $profile
 $hash=Get-MineComeGameplayHash (Get-MineComeGameplayProfilePath -Chat)
 $candidates=@()
 if($BundleDirectory){$candidates=@(Resolve-MineComeGameplayPath $BundleDirectory -InRuntime)}
 else{
  $candidates=@(Get-ChildItem -LiteralPath (Join-Path $script:mcGameplayRoot 'runtime') -Directory -Filter 'hud*' | Sort-Object LastWriteTimeUtc -Descending | ForEach-Object {$_.FullName})
 }
 foreach($candidate in $candidates){
  $receiptPath=Join-Path $candidate 'installed.json';$restored=Test-Path -LiteralPath (Join-Path $candidate 'restored.json')
  if($restored){continue}
  if(-not(Test-Path -LiteralPath $receiptPath)){continue}
  $receipt=Read-MineComeGameplayJson $receiptPath
  if(-not $receipt.PSObject.Properties['profile_sha256'] -or $receipt.profile_sha256 -cne $hash){continue}
  # A matching claimed current deployment must validate completely; never skip
  # a damaged receipt or foreign installed file and silently replace it.
  $installed=Get-MineComeGameplayInstallation -BundleDirectory $candidate -RequireUnarmed -Chat
  return [pscustomobject]@{Bundle=$candidate;Installed=$true;Profile=$profile;ToolsBin=$bin;ToolsExe=$installed.ToolsExe}
 }
 if($BundleDirectory -and -not(Test-Path -LiteralPath (Join-Path $BundleDirectory 'restored.json'))){
  $bundle=Resolve-MineComeGameplayPath $BundleDirectory -InRuntime
  if(Test-Path -LiteralPath $bundle){$null=Assert-MineComeGameplayBundle $bundle $profile}
 }else{
  $bundle=Join-Path $script:mcGameplayRoot ('runtime/hud-play-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
 }
 # Verify the exact reversible base deployment before offering installation.
 $previous=Join-Path $script:mcGameplayRoot $profile.previous_bundle
 if((Get-MineComeGameplayHash (Join-Path $previous 'bundle.json')) -cne $profile.previous_manifest_sha256 -or
    (Get-MineComeGameplayHash (Join-Path $previous 'installed.json')) -cne $profile.previous_receipt_sha256){throw 'The recorded base HUD installation changed; its files are preserved.'}
 $old=Read-MineComeGameplayJson (Join-Path $previous 'bundle.json');Assert-MineComeGameplayRecords $old.files
 Assert-MineComeGameplayNoArms $bin
 foreach($record in $old.files){Assert-MineComeGameplayFile (Join-Path $bin $record.path) $record}
 $buildPath=Join-Path $script:mcGameplayRoot $profile.build_receipt
 if((Get-MineComeGameplayHash $buildPath) -cne $profile.build_receipt_sha256){throw 'The recorded gameplay build changed.'}
 $build=Read-MineComeGameplayJson $buildPath
 foreach($record in $profile.files){
  $source=if($record.path -ceq 'dxgi.dll'){$build.output}elseif($record.path -ceq 'minecome-hud/addons/MineComeHudCompositor.addon64'){Join-Path $script:mcGameplayRoot $profile.addon_source}elseif($record.path -ceq 'minecome-hud/shaders/MineComeHud.fx' -and $profile.PSObject.Properties['shader_source']){Join-Path $script:mcGameplayRoot $profile.shader_source}else{Join-Path $previous $record.path}
  Assert-MineComeGameplayFile $source $record
 }
 return [pscustomobject]@{Bundle=$bundle;Installed=$false;Profile=$profile;ToolsBin=$bin;ToolsExe=(Join-Path $bin 'KingdomCome.exe')}
}
function Test-MineComePlayPoseReceipt([string]$Text,[string]$Run){
 if($Run -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid world readiness identity.'}
 $pattern='\[MineComePlayPose\] '+$Run+' begin\r?\n[^\r\n]*\[MineComePose\] (\{[^\r\n]*\})\r?\n[^\r\n]*\[MineComePlayPose\] '+$Run+' end true(?:\r?\n|$)'
 $match=[regex]::Match($Text,$pattern);if(-not $match.Success){return $false}
 try{
  $pose=$match.Groups[1].Value|ConvertFrom-Json -Depth 5
  if($pose.schema -ne 1 -or $null -eq $pose.player -or $pose.fov_raw -isnot [ValueType] -or
     -not[double]::IsFinite([double]$pose.fov_raw) -or $pose.fov_raw -le 0 -or $pose.fov_raw -ge [Math]::PI){return $false}
  foreach($name in @('player','camera','forward','up')){foreach($axis in @('x','y','z')){
   $value=$pose.$name.$axis
   if($value -isnot [ValueType] -or $value -is [bool] -or -not[double]::IsFinite([double]$value)){return $false}
  }}
  $length=[Math]::Sqrt($pose.forward.x*$pose.forward.x+$pose.forward.y*$pose.forward.y+$pose.forward.z*$pose.forward.z)
  return $length -gt .9 -and $length -lt 1.1
 }catch{return $false}
}
function Test-MineComePlaySavedProcess($Verification,$PlayReceipt,$Context,[string]$Run,[string]$Instance){
 try{
  return $Verification.schema -eq 1 -and $Verification.kind -ceq 'minecome_gameplay_kcd_session_v1' -and
   $Verification.run -ceq $Run -and $Verification.result -ceq 'passed' -and $null -eq $Verification.failure -and
   $Verification.normal_client_exit -is [bool] -and $Verification.normal_client_exit -eq $true -and
   $Verification.target_pid -eq $Context.GamePid -and
   $Verification.target_start_filetime -ceq $Context.GameStartedUtc.ToFileTimeUtc().ToString() -and
   [IO.Path]::GetFullPath($Verification.instance) -ieq $Instance -and
   $PlayReceipt.schema -eq 1 -and $PlayReceipt.kind -ceq 'minecome_play_saved_v1' -and
   $PlayReceipt.run -ceq $Run -and $PlayReceipt.target_pid -eq $Context.GamePid -and
   $PlayReceipt.target_start_filetime -ceq $Context.GameStartedUtc.ToFileTimeUtc().ToString() -and
   [IO.Path]::GetFullPath($PlayReceipt.instance) -ieq $Instance
 }catch{return $false}
}
function Test-MineComePlayReadOnlyRetry($Failure){
 # Only use for the read-only binding/pose stage. Never wrap installation,
 # gameplay, normal quit, or another mutating operation with this retry policy.
 $errorException=if($Failure -is [Management.Automation.ErrorRecord]){$Failure.Exception}else{$Failure}
 while($errorException){
  if($errorException.Message -ceq 'Official tools request exceeded its absolute timeout' -or
     $errorException.Message -ceq 'Official tools Console ExecuteString binding is not ready' -or
     $errorException -is [OperationCanceledException]){return $true}
  if($errorException -is [Net.Sockets.SocketException] -and $errorException.SocketErrorCode -in @(
    [Net.Sockets.SocketError]::ConnectionRefused,[Net.Sockets.SocketError]::ConnectionReset,[Net.Sockets.SocketError]::ConnectionAborted,[Net.Sockets.SocketError]::TimedOut)){return $true}
  $errorException=$errorException.InnerException
 }
 return $false
}
