#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Synthetic native mirror lifecycle only. No Minecraft placements, player
# movement, input capture, asset installation or game launch.
[CmdletBinding()]
param([string]$InstanceDirectory,[ValidateRange(0,2147483647)][int]$ExpectedGamePid=0)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayBlocksHost.ps1')
$context=Get-MineComeProbeContext;$root=$context.ProjectRoot
if($ExpectedGamePid -gt 0 -and $context.GamePid -ne $ExpectedGamePid){throw 'Expected tools process differs.'}
if(-not $InstanceDirectory){$InstanceDirectory=Join-Path $root 'runtime/gameplay/blocks-instance'}
$bindingDirectory=Join-Path $InstanceDirectory 'saves/MineCome-Gameplay/minecome-terrain'
$binding=Get-Content -LiteralPath (Join-Path $bindingDirectory 'binding.json') -Raw|ConvertFrom-Json
$patchFile=Join-Path $bindingDirectory 'ground-patch.json'
$patch=Get-Content -LiteralPath $patchFile -Raw|ConvertFrom-Json -Depth 16
$patchHash=(Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant()
if($binding.schema -ne 1 -or $binding.kind -cne 'minecome_gameplay_terrain_v1' -or $binding.patch_sha256 -cne $patchHash -or
    $binding.patch_run -cne $patch.run -or $patch.provenance.kind -cne 'live_kcd_ground_patch' -or $patch.provenance.game_exe_hash -ine $context.GameHash -or
    $patch.grid_size -ne 9 -or $patch.spacing -ne 1 -or @($patch.points).Count -ne 81){throw 'Saved live terrain binding differs.'}
$assets=Test-GameplayBlocksAssets $context
$probe=New-MineComeProbeRun $context 'gameplay-block-mirror' (Join-Path $root 'kcd2/gameplay/blocks_session.lua') 'GameplayBlocksBegin' -PrepareOnly
$run=$probe.Run;$watch=[Diagnostics.Stopwatch]::StartNew();$lastSend=0L;$began=$false;$stopping=$false;$passed=$false;$failure=$null
$begin=$null;$two=$null;$one=$null;$terminal=$null;$geometry=$null
function Send-MirrorCode([string]$Code){
    Assert-MineComeProbeContext $context
    $command='#'+$Code+";System.LogAlways('[MineComeGameplayMirrorFlush] $run')"
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($command)) -TimeoutMilliseconds 500|Out-Null
    $script:lastSend=$watch.ElapsedMilliseconds
}
function Send-MirrorCall([string]$Call){
    Send-MirrorCode "local ok,why=$Call;if ok==false then if type(why)~='string' or not why:match('^[a-z_]+$') then why='invalid_reason' end;System.LogAlways('[MineComeGameplayBlocksMirror] {`"schema`":1,`"run`":`"$run`",`"event`":`"rejected`",`"result`":`"'..why..'`"}') end"
}
function Wait-MirrorReceipt([string]$Tag,[string]$Event,[int]$Revision=-1,[int]$TimeoutMilliseconds=1200){
    $until=$watch.ElapsedMilliseconds+$TimeoutMilliseconds
    do{
        $log=Read-MineComeProbeLog $context $probe.Offset
        $rejected=@(Get-MineComeProbeReceipts $log 'MineComeGameplayBlocksMirror' $run|Where-Object {$_.event -ceq 'rejected'})
        if($rejected.Count){throw ('Native mirror request rejected: '+$rejected[-1].result)}
        $records=@(Get-MineComeProbeReceipts $log $Tag $run|Where-Object {$_.event -ceq $Event -and ($Revision -lt 0 -or $_.revision -eq $Revision)})
        if($records.Count){return $records[-1]}
        if($watch.ElapsedMilliseconds-$lastSend -ge 100){
            if($began -and -not $stopping){Send-MirrorCall "MineCome.GameplayBlocksHeartbeat('$run')"}
            else{Send-MirrorCode "System.LogAlways('[MineComeGameplayCleanupFlush] $run')"}
        }
        Start-Sleep -Milliseconds 20
    }while($watch.ElapsedMilliseconds -lt $until -and $watch.ElapsedMilliseconds -lt 9500)
    throw "Native mirror $Event receipt missing."
}
function Require-Point($Actual,[double]$X,[double]$Y,[double]$Z){
    foreach($axis in @(@('x',$X),@('y',$Y),@('z',$Z))){if(-not [double]::IsFinite([double]$Actual.($axis[0])) -or [Math]::Abs([double]$Actual.($axis[0])-$axis[1]) -gt .001){throw 'Native mirror bounding box differs.'}}
}
try{
    Initialize-MineComeProbeRun $context $probe
    $numbers=@($patch.center.x,$patch.center.y,$patch.center.z)|ForEach-Object {([double]$_).ToString('R',[Globalization.CultureInfo]::InvariantCulture)}
    # Keep the owned native lease short even if the host is interrupted.
    $began=$true;Send-MirrorCall "MineCome.GameplayBlocksBegin('$run',5000,$([string]::Join(',',$numbers)),-4,3,-4,3)"
    $begin=Wait-MirrorReceipt 'MineComeGameplayBlocks' 'begin'
    if($begin.result -cne 'ready' -or -not $begin.active -or $begin.count -ne 0){throw 'Native mirror begin differs.'}
    Send-MirrorCall "MineCome.GameplayBlocksApply('$run',0,{2,64,0,2,65,0})"
    $two=Wait-MirrorReceipt 'MineComeGameplayBlocks' 'applied' 0
    if($two.result -cne 'mirrored' -or $two.count -ne 2 -or $two.spawned -ne 2 -or $two.removed -ne 0){throw 'Two-cell native mirror differs.'}
    $sample=@'
local p=MineCome._gameplay_blocks.active;local rows={};local function v(a)return string.format('{"x":%.17g,"y":%.17g,"z":%.17g}',a.x,a.y,a.z)end;assert(p and p.run=='__RUN__');for key,r in pairs(p.owned)do local e=System.GetEntity(r.id);assert(e and System.GetEntityByName(r.name)==e);local a,b=e:GetLocalBBox();local wa,wb=e:GetWorldBBox();rows[#rows+1]='{"key":"'..key..'","position":'..v(e:GetWorldPos())..',"angles":'..v(e:GetWorldAngles())..',"local_min":'..v(a)..',"local_max":'..v(b)..',"world_min":'..v(wa)..',"world_max":'..v(wb)..'}' end;System.LogAlways('[MineComeGameplayBlocksMirror] {"schema":1,"run":"__RUN__","event":"geometry","rows":['..table.concat(rows,',')..'] }')
'@
    Send-MirrorCode ($sample.Replace('__RUN__',$run))
    $geometry=Wait-MirrorReceipt 'MineComeGameplayBlocksMirror' 'geometry'
    if(@($geometry.rows).Count -ne 2){throw 'Native geometry readback count differs.'}
    foreach($y in @(64,65)){
        $row=@($geometry.rows|Where-Object {$_.key -ceq "2:${y}:0"});if($row.Count -ne 1){throw 'Owned native geometry identity differs.'};$row=$row[0]
        $x=[double]$patch.center.x+2;$nativeY=[double]$patch.center.y;$z=[double]$patch.center.z+$y-64
        Require-Point $row.position $x $nativeY $z;Require-Point $row.angles 0 0 0
        Require-Point $row.local_min 0 -1 0;Require-Point $row.local_max 1 0 1
        Require-Point $row.world_min $x ($nativeY-1) $z;Require-Point $row.world_max ($x+1) $nativeY ($z+1)
    }
    Send-MirrorCall "MineCome.GameplayBlocksApply('$run',1,{2,64,0})"
    $one=Wait-MirrorReceipt 'MineComeGameplayBlocks' 'applied' 1
    if($one.result -cne 'mirrored' -or $one.count -ne 1 -or $one.spawned -ne 2 -or $one.removed -ne 1){throw 'Native differential removal differs.'}
    $passed=$true
}catch{$failure=$_.Exception.Message}
finally{
    if($began){try{
        $stopping=$true;Send-MirrorCall "MineCome.GameplayBlocksEnd('$run')"
        $terminal=Wait-MirrorReceipt 'MineComeGameplayBlocks' 'terminal' -TimeoutMilliseconds 2500
        if($terminal.result -cne 'explicit_stop' -or $terminal.count -ne 0 -or $terminal.active -or -not $terminal.timers_cancelled -or $terminal.removed -ne 2){throw 'Native mirror cleanup was not verified.'}
    }catch{$passed=$false;if(-not $failure){$failure=$_.Exception.Message}}}
    $log=Read-MineComeProbeLog $context $probe.Offset
    [IO.File]::WriteAllText((Join-Path $probe.Directory 'game.log'),$log)
    $proof=[ordered]@{schema=1;kind='minecome_gameplay_native_mirror_smoke_v1';result=$(if($passed -and -not $failure){'passed'}else{'failed'});failure=$failure;run=$run;game_pid=$context.GamePid;game_started_utc=$context.GameStartedUtc;patch_run=$patch.run;patch_sha256=$patchHash;elapsed_ms=$watch.ElapsedMilliseconds;synthetic_native_cells=$true;actual_minecraft_placement_verified=$false;player_movement_requested=$false;assets=$assets;begin=$begin;two_cells=$two;geometry=$geometry;one_cell=$one;terminal=$terminal;source_sha256=$probe.SourceHash}
    $proof|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
}
if($failure){throw "$failure Evidence: $($probe.Directory)"}
[pscustomobject]@{Result='passed';EvidenceDirectory=$probe.Directory;ElapsedMs=$watch.ElapsedMilliseconds;Scope='Synthetic native mirror only; no actual Minecraft placement claim'}
