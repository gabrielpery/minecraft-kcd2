#Requires -Version 7.3
# Offline parser/policy initialization only; no games, permits, or HTTP calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot '../scripts/HudCameraDelivery.ps1')
. (Join-Path $PSScriptRoot '../scripts/HudWalkingAimed.ps1')
$checks=0
function Check($Value,[string]$Why){$script:checks++;if(-not $Value){throw $Why}}
function Reject([scriptblock]$Action,[string]$Why){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Why}
function Send-MineComeHudAimedIntent{throw 'Warmup attempted to send an intent.'}
function Invoke-MineComeToolsRequest{throw 'Warmup attempted HTTP.'}
function Invoke-MineComeProbeConsole{throw 'Warmup attempted game dispatch.'}
function Select-MineComeAimedClickPermit{throw 'Warmup attempted to consume a permit.'}
function New-MineComeAimedClickLedger{throw 'Warmup attempted to create live click state.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$directory=Join-Path $root ('runtime/evidence/hud-aim-admission-offline-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($directory)
$live=Join-Path $directory 'host-view.json'
[IO.File]::WriteAllText($live,'{"sentinel":"not a warmup input"}')
$liveHash=(Get-FileHash -LiteralPath $live).Hash
$context=[pscustomobject]@{GamePid=$PID};$contextJson=$context|ConvertTo-Json -Compress
$receipt=Initialize-HudWalkingAimedAdmissionWarmup $directory $root $context
Check ($receipt.diagnostic_only -and $receipt.synthetic_policy_state -and -not $receipt.live_authority_granted -and -not $receipt.input_generated) 'Warmup represented diagnostic work as live authority'
Check ($receipt.permits_issued -eq 0 -and $receipt.http_requests -eq 0 -and -not $receipt.game_input_latency_measured) 'Warmup invented transport/input evidence'
Check ($receipt.measurements.Count -eq 2 -and $receipt.measurements[0].iteration -eq 1 -and $receipt.measurements[1].iteration -eq 2) 'Missing bounded first/repeated measurements'
foreach($row in $receipt.measurements){foreach($field in @('snapshot_ms','foreground_ms','settled_policy_ms')){Check ($row.$field -ge 0 -and -not [double]::IsInfinity($row.$field) -and -not [double]::IsNaN($row.$field)) "Invalid diagnostic $field"}}
Check ((Get-FileHash -LiteralPath $live).Hash -ceq $liveHash) 'Warmup overwrote live view path'
Check (($context|ConvertTo-Json -Compress) -ceq $contextJson) 'Warmup mutated supplied live context'
$snapshot=Get-Content -LiteralPath $receipt.diagnostic_snapshot -Raw|ConvertFrom-Json
Check ($snapshot.kind -ceq 'minecome_hud_diagnostic_aim_view_v1' -and $snapshot.diagnostic_only) 'Disposable snapshot lacked diagnostic identity'
$diagnosticHash=(Get-FileHash -LiteralPath $receipt.diagnostic_snapshot).Hash
Reject {Initialize-HudWalkingAimedAdmissionWarmup $directory $root $context} 'Repeated warmup replaced existing evidence'
Check ((Get-FileHash -LiteralPath $receipt.diagnostic_snapshot).Hash -ceq $diagnosticHash) 'Rejected repeat overwrote owned diagnostic snapshot'
Reject {Initialize-HudWalkingAimedAdmissionWarmup $root $root $context} 'Diagnostic snapshot escaped evidence root'
$output=Join-Path $directory 'warmup-comparison.json'
$receipt|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $output -Encoding utf8NoBOM
Write-Output "HUD_AIM_ADMISSION_WARMUP_TESTS_PASS checks=$checks no_games=true retained_diagnostic=$output"
Write-Output ($receipt.measurements|ConvertTo-Json -Compress)
