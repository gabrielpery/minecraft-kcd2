# Automatic actual-Minecraft crossing with a pinned KCD player/camera follower.
[CmdletBinding()]
param([switch]$LaunchTestWorld,[switch]$PreflightOnly,[switch]$IncludeJump,[switch]$PhysicalController,[switch]$KeepTestWorld)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($code -ne 0){throw "Coupled corridor failed with exit code $code"};return
}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
if($KeepTestWorld -and -not $LaunchTestWorld){throw 'KeepTestWorld applies only to a world owned by LaunchTestWorld.'}
if($PhysicalController -and $IncludeJump){throw 'Physical corridor controller exercise is walk-only.'}
$owned=$null;$ownedStart=$null;$ownedPath=$null
try{
    if($LaunchTestWorld){
        if($PreflightOnly){throw 'LaunchTestWorld cannot be combined with read-only preflight.'}
        $launch=@(& (Join-Path $PSScriptRoot 'Start-Kcd2ToolsTest.ps1'))
        $launch | Write-Host
        $match=[regex]::Match(($launch -join "`n"),'Started process ([0-9]+)\.')
        if(-not $match.Success){throw 'Launch did not identify the owned test process.'}
        $owned=Get-Process -Id ([int]$match.Groups[1].Value)
        $ownedStart=$owned.StartTime.ToUniversalTime()
        $ownedPath=$owned.Path
        $gameRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ownedPath))
        $log=Join-Path $gameRoot 'kcd.log'
        $deadline=[DateTime]::UtcNow.AddSeconds(180);$loaded=$false
        do{
            if($owned.HasExited){throw 'KCD exited during loading.'}
            if((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).LastWriteTimeUtc -ge $ownedStart){
                $loaded=([string](Get-Content -LiteralPath $log -Raw)).Contains("'LEVEL_LOAD_COMPLETE'->'RUNNING'")
            }
            if($loaded){break};Start-Sleep -Milliseconds 500
        }while([DateTime]::UtcNow -lt $deadline)
        if(-not $loaded){throw 'KCD world readiness timed out.'}
        Start-Sleep -Seconds 8
        $context=Get-MineComeProbeContext
        if($context.GamePid -ne $owned.Id -or $context.GameStartedUtc -ne $ownedStart){throw 'Test launch identity changed.'}
    }
    if($PhysicalController){
        if($PreflightOnly){
            $null=Get-MineComeProbeContext
            & (Join-Path $PSScriptRoot 'Test-HudPhysicalMovementFixture.ps1') -ExtendedWalking -CorridorWalking -PreflightOnly
        }else{
            $capture=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundCorridor.ps1') | Where-Object {$_ -isnot [string] -and $_.PSObject.Properties['GroundCorridorFile']})
            if($capture.Count -ne 1){throw 'Expected one live corridor capture.'}
            $budget=New-MineComeHudGpuBudget (Get-MineComeProbeContext)
            try{
                Start-MineComeHudGpuBudget $budget
                $fixture=@(& (Join-Path $PSScriptRoot 'Test-HudPhysicalMovementFixture.ps1') -ExtendedWalking -CorridorWalking -GroundPatchFile $capture[0].GroundCorridorFile | ForEach-Object {
                    if($_ -isnot [string] -and $_.PSObject.Properties['EvidenceDirectory']){$_}else{Write-Host $_}
                })
                if($fixture.Count -ne 1){throw 'Expected one completed real Minecraft controller fixture.'}
            }finally{Stop-MineComeHudGpuBudget $budget}
            if(-not $budget.BudgetValid){throw 'Fixture GPU budget was not restored before native replay.'}
            & (Join-Path $PSScriptRoot 'Test-KcdBufferedReplay.ps1') -CorridorWalking -TraceDirectory $fixture[0].EvidenceDirectory -GroundCorridorFile $capture[0].GroundCorridorFile
        }
    }else{
    & (Join-Path $PSScriptRoot 'Test-CoupledMovement.ps1') -HudWorld -CorridorWalking -CorridorWalkOnly:(-not $IncludeJump) -PreflightOnly:$PreflightOnly
    }
}finally{
    # Only a process launched by this invocation is closed, using its normal window close.
    if($owned -and $KeepTestWorld){Write-Host "Owned KCD test world kept open: PID $($owned.Id).";$owned.Dispose()}
    elseif($owned){
        $current=Get-Process -Id $owned.Id -ErrorAction SilentlyContinue
        try{
            if($current -and $current.StartTime.ToUniversalTime() -eq $ownedStart -and $current.Path -ieq $ownedPath){
                if(-not $current.CloseMainWindow() -or -not $current.WaitForExit(15000)){throw 'Owned KCD test world is still closing; no force stop was used.'}
                Write-Host 'Owned KCD corridor test world closed normally.'
            }
        }finally{if($current){$current.Dispose()};$owned.Dispose()}
    }
}
