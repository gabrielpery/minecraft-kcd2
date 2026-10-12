#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/InputLabEvidence.ps1')
$run='a'*32;$hash='b'*64;$checks=0
$fields="viewSeedSha256=$hash viewSeedKind=standalone_fixture initialClientViewVerified=true initialServerViewVerified=true initialViewSnapshotOnly=true"
$ready="[test fixture] EXTERNAL_INPUT_LAB_READY inputRun=$run $fields"
$pass="[test fixture] EXTERNAL_INPUT_LAB_PASS inputRun=$run $fields actualVanillaMCInputApplication=true inputNeutralAfterEnd=true fullWorldMovementAuthorityVerified=false"
function Check-Marker([string]$Log,[string]$Event,[bool]$Expected){
    $script:checks++
    $actual=Test-MineComeInputLabMarker -Log $Log -Event $Event -Run $run -ViewHash $hash.ToUpperInvariant() -ViewKind standalone_fixture
    if($actual -ne $Expected){throw "Input lab marker case $script:checks failed"}
}
Check-Marker $ready READY $true
Check-Marker ($ready+"`r`n"+$pass+"`r`n") PASS $true
Check-Marker ($ready.Replace($hash,('c'*64))) READY $false
Check-Marker ($pass.Replace($run,('d'*32))) PASS $false
Check-Marker ($ready.Replace('standalone_fixture','live_kcd_view_seed')) READY $false
Check-Marker ($ready.Replace(' initialServerViewVerified=true','')) READY $false
Check-Marker ($ready.Replace('initialClientViewVerified=true','initialClientViewVerified=false')) READY $false
Check-Marker ($ready.Replace('initialViewSnapshotOnly=true','initialViewSnapshotOnly=false')) READY $false
Check-Marker ($ready+' viewSeedSha256='+$hash) READY $false
Check-Marker ($ready+"`n"+$ready) READY $false
Check-Marker ($pass.Replace('actualVanillaMCInputApplication=true','actualVanillaMCInputApplication=false')) PASS $false
Check-Marker ($pass.Replace('inputNeutralAfterEnd=true','inputNeutralAfterEnd=false')) PASS $false
Check-Marker ($pass.Replace('fullWorldMovementAuthorityVerified=false','fullWorldMovementAuthorityVerified=true')) PASS $false
Check-Marker ($ready+"`n"+'viewSeedSha256='+$hash) PASS $false
Write-Output "INPUT_LAB_EVIDENCE_TEST_PASS checks=$checks synthetic log fixtures only"
