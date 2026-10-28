#Requires -Version 7.3
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){
    $outputs=[Collections.Generic.List[object]]::new();$rejected=$false
    try{& $Action | ForEach-Object{$outputs.Add($_)}}catch{$rejected=$true}
    Check $rejected $Message
    Check ($outputs.Count -eq 0) 'A failed diagnostic warmup emitted pipeline output.'
}
. (Join-Path $root 'scripts/MovementTraceReceiver.ps1')
. (Join-Path $root 'scripts/HudBufferedMovement.ps1')

# Synthetic receiver fixture only. The warmup itself must not create or modify
# any file, and none of these records is live game or source-timing evidence.
$world='12345678-1234-1234-1234-123456789abc'
$save='MineCome-HudStream-'+$world
$minimumUtc=1700000000000L
$points=@(for($i=1;$i -le 25;$i++){
    [pscustomobject]@{index=$i;x=120+(($i-1)%5)-2;y=2040+[Math]::Floor(($i-1)/5)-2;
        z=56;nx=0;ny=0;nz=1;valid=$true;result='hit'}
})
$patch=[pscustomobject]@{schema=1;run=('a'*32);grid_size=5;spacing=1;point_count=25;valid_count=25;
    stable_player=$true;approximate_heightfield=$true;full_collision_export_verified=$false;
    center=[pscustomobject]@{x=120.0;y=2040.0;z=56.0};points=$points;
    provenance=[pscustomobject]@{kind='live_kcd_ground_patch'}}
$dir=Join-Path $root ('runtime/evidence/buffered-warmup-pure-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
'SYNTHETIC ONLY. Disposable parser warmup tests; no game calls or live trace evidence.' |
    Set-Content -LiteralPath (Join-Path $dir 'FIXTURE.txt') -Encoding utf8NoBOM
$patchPath=Join-Path $dir 'patch.json'
$patch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $patchPath -Encoding utf8NoBOM
$parameters=@{PatchFile=$patchPath;ExpectedHudSave=$save;MinimumUtcMs=$minimumUtc}
$patchBefore=[IO.File]::ReadAllText($patchPath)
$filesBefore=@(Get-ChildItem -LiteralPath $dir -File | Sort-Object Name | ForEach-Object{$_.Name+':'+(Get-FileHash -LiteralPath $_.FullName).Hash}) -join "`n"

# Hold independently created live-shaped state across repeated warmups. The
# helper cannot borrow it, consume its first record or initialize its clock.
$liveReceiver=New-MineComeTraceReceiver @parameters -PhysicalMovement -BufferedPhysicalMovement
$liveSource=New-HudBufferedSourceState
$liveReceiverBefore=ConvertTo-Json -InputObject $liveReceiver -Depth 8 -Compress
$liveSourceBefore=ConvertTo-Json -InputObject $liveSource -Depth 8 -Compress
$script:originalReceive=${function:Receive-MineComeMovementTrace}
$script:diagnosticRecords=[Collections.Generic.List[object]]::new()
$script:diagnosticReceivers=[Collections.Generic.List[object]]::new()
Set-Item -LiteralPath function:Receive-MineComeMovementTrace -Value {
    param($State,[string]$JsonLine,$NowUtcMs)
    $script:diagnosticRecords.Add((ConvertFrom-Json -InputObject $JsonLine))
    $script:diagnosticReceivers.Add($State)
    & $script:originalReceive -State $State -JsonLine $JsonLine -NowUtcMs $NowUtcMs
}
try{
    $first=@(Initialize-HudBufferedMovementPipeline @parameters)
    $second=@(Initialize-HudBufferedMovementPipeline @parameters)
}finally{Set-Item -LiteralPath function:Receive-MineComeMovementTrace -Value $script:originalReceive}
foreach($outputs in @($first,$second)){
    Check ($outputs.Count -eq 1) 'Warmup must emit exactly one summary.'
    $summary=$outputs[0]
    Check ($summary.kind -ceq 'diagnostic_warmup' -and $summary.status -ceq 'completed') 'Warmup was not explicitly diagnostic.'
    Check ($summary.diagnostic_records -eq 3) 'Warmup did not cover begin and both source-time branches.'
    Check ([double]::IsFinite($summary.elapsed_ms) -and $summary.elapsed_ms -ge 0) 'Invalid diagnostic duration.'
    Check ((@($summary.PSObject.Properties.Name | Sort-Object) -join ',') -ceq 'diagnostic_records,elapsed_ms,kind,status') 'Warmup leaked a record, target, clock or receiver.'
}
Check ($script:diagnosticRecords.Count -eq 6) 'Warmup did not process exactly three records per invocation.'
Check (-not [object]::ReferenceEquals($script:diagnosticReceivers[0],$script:diagnosticReceivers[3])) 'Warmup reused receiver state.'
Check (-not [object]::ReferenceEquals($liveReceiver,$script:diagnosticReceivers[0])) 'Warmup borrowed live receiver state.'
Check ($script:diagnosticRecords[0].world -cne $world -and $script:diagnosticRecords[0].save -cne $save) 'Synthetic records named the actual HUD world.'
Check ($script:diagnosticRecords[0].world -cne $script:diagnosticRecords[3].world) 'Warmup reused a diagnostic world identity.'
for($i=0;$i -lt 6;$i++){
    $record=$script:diagnosticRecords[$i]
    $offset=$i%3
    Check ($record.seq -eq $offset+1 -and $record.utc_ms -eq $minimumUtc) 'Diagnostic clocks or record counts were rebased.'
    Check ($record.save -ceq ('MineCome-HudStream-'+$record.world)) 'Diagnostic world/save pair was not canonical.'
    if($offset -eq 0){Check ($record.kind -ceq 'begin' -and $record.phase -ceq 'SETTLING') 'Incorrect diagnostic begin.'}
    else{
        Check ($record.kind -ceq 'sample' -and $record.phase -ceq @('','SETTLING','RESTING')[$offset]) 'Diagnostic sample did not cover its intended branch.'
        Check ($record.server_seq -eq $offset -and $record.monotonic_ns -eq $offset*100000000 -and $record.server_age_ns -eq 0) 'Synthetic source clocks did not advance independently.'
        foreach($motion in @($record.client,$record.server)){
            Check ($motion.x -eq 0 -and $motion.y -eq 64 -and $motion.z -eq 0 -and $motion.vx -eq 0 -and
                $motion.vy -eq 0 -and $motion.vz -eq 0 -and $motion.on_ground -and $motion.proxy_support) 'Diagnostic warmup requested movement.'
        }
    }
}
Check ((ConvertTo-Json -InputObject $liveReceiver -Depth 8 -Compress) -ceq $liveReceiverBefore) 'Warmup changed the existing receiver.'
Check ((ConvertTo-Json -InputObject $liveSource -Depth 8 -Compress) -ceq $liveSourceBefore) 'Warmup changed the existing source clock.'
$freshReceiver=New-MineComeTraceReceiver @parameters -PhysicalMovement -BufferedPhysicalMovement
$freshSource=New-HudBufferedSourceState
Check ((ConvertTo-Json -InputObject $freshReceiver -Depth 8 -Compress) -ceq $liveReceiverBefore) 'New receiver inherited diagnostic observations.'
Check ((ConvertTo-Json -InputObject $freshSource -Depth 8 -Compress) -ceq $liveSourceBefore) 'New source clock inherited diagnostic observations.'
Check (-not $liveReceiver.Begun -and -not $liveReceiver.AnchorVerified -and $liveReceiver.LastSeq -eq 0 -and $liveSource.Count -eq 0) 'Warmup consumed live startup state.'

# A real-shaped fresh sequence still begins at one and normalizes its own first
# server observation to zero, independently of the discarded diagnostic clock.
$actualBegin=$script:diagnosticRecords[0]
$actualBegin.world=$world;$actualBegin.save=$save
$actualSample=$script:diagnosticRecords[1]
$actualSample.world=$world;$actualSample.save=$save;$actualSample.monotonic_ns=-9000000000L
$accepted=Receive-MineComeMovementTrace -State $liveReceiver -JsonLine ($actualBegin | ConvertTo-Json -Depth 8 -Compress) -NowUtcMs $minimumUtc
Check ($accepted.Kind -ceq 'begin') 'Fresh receiver could not start after warmup.'
$accepted=Receive-MineComeMovementTrace -State $liveReceiver -JsonLine ($actualSample | ConvertTo-Json -Depth 8 -Compress) -NowUtcMs $minimumUtc
Check ($accepted.Kind -ceq 'sample') 'Fresh receiver lost its initial anchor after warmup.'
Check ((Get-HudBufferedSourceTime -State $liveSource -Record $actualSample) -eq 0 -and $liveSource.AnchorNs -eq -9000000000L) 'Fresh source clock used the synthetic epoch.'

Reject {Initialize-HudBufferedMovementPipeline -PatchFile (Join-Path $dir 'missing.json') -ExpectedHudSave $save -MinimumUtcMs $minimumUtc} 'Missing patch did not reject warmup.'
Reject {Initialize-HudBufferedMovementPipeline -PatchFile $patchPath -ExpectedHudSave 'invalid-save' -MinimumUtcMs $minimumUtc} 'Invalid save did not reject warmup.'
Reject {Initialize-HudBufferedMovementPipeline -PatchFile $patchPath -ExpectedHudSave $save -MinimumUtcMs '1700000000000'} 'String UTC clock did not reject warmup.'
Reject {Initialize-HudBufferedMovementPipeline -PatchFile $patchPath -ExpectedHudSave $save -MinimumUtcMs -1L} 'Negative UTC clock did not reject warmup.'
Set-Item -LiteralPath function:Receive-MineComeMovementTrace -Value {throw 'Injected receiver failure.'}
try{Reject {Initialize-HudBufferedMovementPipeline @parameters} 'Receiver failure did not propagate.'}
finally{Set-Item -LiteralPath function:Receive-MineComeMovementTrace -Value $script:originalReceive}
$originalSourceTime=${function:Get-HudBufferedSourceTime}
Set-Item -LiteralPath function:Get-HudBufferedSourceTime -Value {throw 'Injected normalizer failure.'}
try{Reject {Initialize-HudBufferedMovementPipeline @parameters} 'Normalizer failure did not propagate.'}
finally{Set-Item -LiteralPath function:Get-HudBufferedSourceTime -Value $originalSourceTime}
Set-Item -LiteralPath function:Get-HudBufferedSourceTime -Value {return 7.0}
try{Reject {Initialize-HudBufferedMovementPipeline @parameters} 'Wrong synthetic source result did not fail closed.'}
finally{Set-Item -LiteralPath function:Get-HudBufferedSourceTime -Value $originalSourceTime}
Check ([IO.File]::ReadAllText($patchPath) -ceq $patchBefore) 'Warmup modified patch bytes.'
$filesAfter=@(Get-ChildItem -LiteralPath $dir -File | Sort-Object Name | ForEach-Object{$_.Name+':'+(Get-FileHash -LiteralPath $_.FullName).Hash}) -join "`n"
Check ($filesAfter -ceq $filesBefore) 'Warmup wrote a trace or changed fixture files.'
Check ($save -ceq ('MineCome-HudStream-'+$world) -and $minimumUtc -eq 1700000000000L) 'Warmup changed caller identity or clock.'

# Restrict the warmup entry point to the checked parser/normalizer and in-memory
# JSON conversion. No dispatch, HTTP, process launch or trace writing is allowed.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/HudBufferedMovement.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Buffered helper contains syntax errors.'
$warmupAst=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Initialize-HudBufferedMovementPipeline'},$true)
$allowed=@('New-MineComeTraceReceiver','New-HudBufferedSourceState','Receive-MineComeMovementTrace','ConvertTo-Json','ConvertFrom-Json','Get-HudBufferedSourceTime','Get-HudWalkingSession')
foreach($command in $warmupAst.Body.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)){
    Check ($command.GetCommandName() -cin $allowed) 'Warmup contains an unapproved external or file-writing command.'
}
foreach($method in $warmupAst.Body.FindAll({param($node)$node -is [Management.Automation.Language.InvokeMemberExpressionAst]},$true)){
    Check ($method.Member.Value -cin @('StartNew','NewGuid','ToString','GetEnumerator','Stop','Round')) 'Warmup contains an unapproved external or file-writing method.'
}
"HUD_BUFFERED_WARMUP_TESTS_PASS checks=$script:checks"
