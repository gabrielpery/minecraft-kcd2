#Requires -Version 7.3
# Validate observed-frame proof without loading any game-facing probe code.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$checks=0
function Check([bool]$Value,[string]$Reason){$script:checks++;if(-not $Value){throw $Reason}}
function Reject([scriptblock]$Work,[string]$Reason){$failed=$false;try{& $Work | Out-Null}catch{$failed=$true};Check $failed $Reason}
function Clone($Value){$Value | ConvertTo-Json -Depth 16 | ConvertFrom-Json}
$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Test-KcdPhysicalFollower.ps1'),[ref]$null,[ref]$errors)
Check ($errors.Count -eq 0) 'Probe syntax failed'
foreach($name in @('Distance','Assert-InterpolationReceipt')){
    $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
    . ([scriptblock]::Create($function.Extent.Text))
}
$from=[pscustomobject]@{x=0.0;y=0.0;z=0.0};$target=[pscustomobject]@{x=.6;y=0.0;z=0.0}
Check ((Distance $from ([pscustomobject]@{x=3;y=4;z=12})) -eq 13) 'All three distance axes must be evaluated'
$samples=@(for($index=1;$index -le 6;$index++){
    $point=[pscustomobject]@{x=.6*$index/6;y=0.0;z=0.0}
    [pscustomobject]@{fraction=$index/6;requested=$point;actual=$point;written_engine_seconds=10+$index/60;observed_engine_seconds=10+($index+1)/60;write_performed=$true;readback_error=0.0}
})
$receipt=[pscustomobject]@{seq=1;position_mode='timed_interpolation';interpolation_ms=100;readback=$true;physical_movement=$true;camera_basis_valid=$true;
    target=$target;player=$target;target_receipt_age_ms=117;sampled_engine_seconds=10+7/60;segment_start_engine_seconds=10.0;segment_update_count=6;segment_observation_count=6;
    segment_max_readback_error=0.0;segment_observed_samples_truncated=$false;endpoint_write_performed=$true;segment_observed_samples=$samples}
$proof=Assert-InterpolationReceipt $receipt $from $target
Check ($proof.updates -eq 6 -and $proof.observations -eq 6 -and $proof.median_observation_gap_ms -lt 17) 'Normal frame proof rejected'
$bad=Clone $receipt;$bad.segment_observed_samples[2].observed_engine_seconds=$bad.segment_observed_samples[2].written_engine_seconds
Reject {Assert-InterpolationReceipt $bad $from $target} 'Same-frame observations cannot prove motion'
$bad=Clone $receipt;$bad.segment_observed_samples[2].requested.y=.1
Reject {Assert-InterpolationReceipt $bad $from $target} 'An off-path target passed'
$bad=Clone $receipt;$bad.segment_observed_samples[2].actual.y=.051
Reject {Assert-InterpolationReceipt $bad $from $target} 'Actual drift hidden by a zero error summary passed'
$bad=Clone $receipt;$bad.segment_observed_samples[2].fraction=1.1
Reject {Assert-InterpolationReceipt $bad $from $target} 'Extrapolated fraction passed'
$bad=Clone $receipt;$bad.segment_observed_samples_truncated=$true
Reject {Assert-InterpolationReceipt $bad $from $target} 'Omitted frames were claimed as complete probe proof'
$bad=Clone $receipt;$bad.segment_update_count=5
Reject {Assert-InterpolationReceipt $bad $from $target} 'Setter count disagrees with observed frames'
$bad=Clone $receipt;$bad.target_receipt_age_ms=401
Reject {Assert-InterpolationReceipt $bad $from $target} 'Expired target acknowledgement passed'
$bad=Clone $receipt;$bad.sampled_engine_seconds+=.1
Reject {Assert-InterpolationReceipt $bad $from $target} 'Endpoint timestamp differs from last observation'
$bad=Clone $receipt;$bad.segment_start_engine_seconds+=.01
Reject {Assert-InterpolationReceipt $bad $from $target} 'Fractions not matching engine time passed'
$bad=Clone $receipt;$bad.segment_start_engine_seconds-=.1
Reject {Assert-InterpolationReceipt $bad $from $target} 'A segment starting before target acceptance passed'
$bad=Clone $receipt;$bad.segment_max_readback_error=-.1
Reject {Assert-InterpolationReceipt $bad $from $target} 'Negative summary error passed'
$bad=Clone $receipt;$bad.segment_observed_samples=@($bad.segment_observed_samples[2],$bad.segment_observed_samples[5]);$bad.segment_update_count=2;$bad.segment_observation_count=2
Reject {Assert-InterpolationReceipt $bad $from $target} 'Old two-step motion passed the frame-cadence requirement'
$stationary=Clone $receipt;$stationary.segment_update_count=0;$stationary.segment_observation_count=1;$stationary.endpoint_write_performed=$false
$stationary.segment_observed_samples=@($stationary.segment_observed_samples[-1]);$stationary.segment_observed_samples[0].write_performed=$false
$idle=Assert-InterpolationReceipt $stationary $target $target
Check ($idle.stationary -and $idle.updates -eq 0) 'Observed stationary endpoint must not require a setter'
$bad=Clone $stationary;$bad.segment_update_count=1;$bad.endpoint_write_performed=$true;$bad.segment_observed_samples[0].write_performed=$true
Reject {Assert-InterpolationReceipt $bad $target $target} 'Unnecessary stationary setter passed'
Write-Output "HUD_FOLLOWER_INTERPOLATION_TESTS_PASS checks=$checks game_calls=false"
