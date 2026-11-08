#Requires -Version 7.3
# Standalone process/log-identity fixture. No running processes or network calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayHudSessionGuard.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('minecome-hud-session-'+[guid]::NewGuid().ToString('N'))
$run='a'*32;$bin=Join-Path $root 'bin';$directory=Join-Path $root "runtime/evidence/gameplay-kcd-20261108-000000-$run"
[void][IO.Directory]::CreateDirectory($directory);[void][IO.Directory]::CreateDirectory($bin)
$context=[pscustomobject]@{ProjectRoot=$root;GamePid=123;GameStartedUtc=[DateTime]::Parse('2026-11-08T19:00:00Z').ToUniversalTime()}
$start=$context.GameStartedUtc.ToFileTimeUtc().ToString();$armPath=Join-Path $directory 'arm.ini';$logPath=Join-Path $bin 'ReShade.log'
$arm="[HudStream]`nSchema=3`nRun=$run`nTargetPid=123`nTargetStart=$start`nProducerPid=456`nProducerStart=134000000000000000`nExpiresUtcMs=1794253857512`n"
function Require([bool]$Value,[string]$Why){if(-not $Value){throw $Why}}
function Log([string]$Event,[string]$Result='accepted'){
    [IO.File]::WriteAllText($logPath,('19:00:00:000 [1] | INFO | [MineComeHudInput] '+(@{schema=1;event=$Event;result=$Result;run=$run}|ConvertTo-Json -Compress)+"`r`n"))
}
try{
    Require ($null -eq (Get-GameplayHudConsumedRun $context $bin)) 'Fresh process without log was rejected.'
    [IO.File]::WriteAllText($armPath,$arm)
    Require ($null -eq (Get-GameplayHudConsumedRun $context $bin)) 'Written unconsumed arm was treated as native acceptance.'
    Log 'arm' 'invalid_config';Require ($null -eq (Get-GameplayHudConsumedRun $context $bin)) 'Rejected native arm counted as consumed.'
    Log 'arm';Require ((Get-GameplayHudConsumedRun $context $bin) -ceq $run) 'Accepted matching arm was missed.'
    $threw=$false;try{Assert-GameplayHudSessionUnused $context $bin}catch{$threw=$_.Exception.Message -like '*Close and restart KCD2*'}
    Require $threw 'Consumed session did not explain the exact restart fix.'
    Log 'session_end' 'producer_identity';Require ((Get-GameplayHudConsumedRun $context $bin) -ceq $run) 'Terminal failure before arm acceptance was missed.'
    foreach($changed in @($arm.Replace('TargetPid=123','TargetPid=124'),$arm.Replace("TargetStart=$start",'TargetStart=134000000000000001'),$arm.Replace('Schema=3','Schema=1'),($arm+"TargetPid=123`n"),$arm.Replace("Run=$run",('Run='+('b'*32))))){
        [IO.File]::WriteAllText($armPath,$changed);Require ($null -eq (Get-GameplayHudConsumedRun $context $bin)) 'Old process, wrong schema, mismatched run or duplicate identity was accepted.'
    }
    [IO.File]::WriteAllText($armPath,$arm);$context.GameStartedUtc=$context.GameStartedUtc.AddMinutes(1)
    Require ($null -eq (Get-GameplayHudConsumedRun $context $bin)) 'Reused PID with a new start was rejected.'
    [IO.File]::WriteAllText($logPath,'[MineComeHudInput] {not valid JSON}'+"`n")
    Require ($null -eq (Get-GameplayHudConsumedRun $context $bin)) 'Malformed receipt was treated as native acceptance.'
    Write-Output 'PASS gameplay HUD session guard (12 identity/readiness cases; no game/network)'
}finally{
    [IO.File]::Delete($armPath);[IO.File]::Delete($logPath)
    [IO.Directory]::Delete($directory);[IO.Directory]::Delete((Join-Path $root 'runtime/evidence'));[IO.Directory]::Delete((Join-Path $root 'runtime'));[IO.Directory]::Delete($bin);[IO.Directory]::Delete($root)
}
