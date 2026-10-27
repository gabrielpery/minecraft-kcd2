# Pure configuration and evidence checks for the standalone HUD/ground fixture.
function Assert-HudGroundMovementMode([bool]$GroundMovementFixture,[bool]$Standalone,[bool]$Composite,[bool]$Coupled=$false) {
    if(($GroundMovementFixture -and $Coupled) -or (($GroundMovementFixture -or $Coupled) -and (-not $Standalone -or $Composite))) {
        throw 'HUD ground movement requires one explicit mode and a standalone receiver without KCD composition.'
    }
}
function Assert-HudGroundMovementPaths([bool]$Coupled,[string]$PatchFile,[string]$TraceFile) {
    if(($Coupled -and (-not $PatchFile -or -not $TraceFile)) -or (-not $Coupled -and ($PatchFile -or $TraceFile))) {
        throw 'Captured ground and movement trace paths require the explicit coupled HUD mode together.'
    }
}
# Resolve only files/directories inside this workspace's evidence tree. Reject
# reparse points on all existing ancestors before creating a child or reading it.
function Resolve-HudMovementEvidencePath([string]$Path,[string]$ProjectRoot) {
    if(-not [IO.Path]::IsPathFullyQualified($Path)){throw 'HUD movement evidence path must be absolute.'}
    $evidenceRoot=[IO.Path]::GetFullPath((Join-Path $ProjectRoot 'runtime/evidence')).TrimEnd('\')
    $resolved=[IO.Path]::GetFullPath($Path)
    if(-not $resolved.StartsWith($evidenceRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'HUD movement evidence must stay inside runtime/evidence.'}
    $ancestor=$resolved
    while($ancestor){
        # GetAttributes reads the link itself, including dangling junctions.
        # Only absent components are allowed for a new output. Access failures
        # and other I/O errors must not be mistaken for an absent component.
        try{$attributes=[IO.File]::GetAttributes($ancestor)}
        catch [IO.FileNotFoundException]{$attributes=$null}
        catch [IO.DirectoryNotFoundException]{$attributes=$null}
        if($null -ne $attributes -and ($attributes -band [IO.FileAttributes]::ReparsePoint)){
            throw 'HUD movement evidence cannot use reparse points.'
        }
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
    return $resolved
}
function Read-HudMovementJson([string]$Path){
    $item=Get-Item -LiteralPath $Path -Force
    if($item.PSIsContainer -or $item.Length -lt 2 -or $item.Length -gt 65536 -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Invalid bounded HUD movement receipt.'}
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 12
}
# Pure provenance check. The caller supplies the independently measured file
# hashes and the current, executable-pinned KCD process context.
function Assert-HudLivePatchEvidence($Data,$Record,$Receipt,[string]$PatchPath,[string]$PatchHash,
    [string]$SourceHash,[string]$SnapshotHash,$Context,[long]$NowUtcMs) {
    foreach($hash in @($PatchHash,$SourceHash,$SnapshotHash)){if($hash -notmatch '^[0-9a-fA-F]{64}$'){throw 'Invalid captured terrain hash.'}}
    foreach($field in @('Patch','FunctionReloadVerified','EngineReceiptVerified')){
        if($Record.$field -isnot [bool] -or -not $Record.$field){throw 'Terrain capture verification must be explicit Boolean success.'}
    }
    if($Data.schema -ne 1 -or $Data.run -cnotmatch '^[0-9a-f]{32}$' -or $Data.provenance.kind -cne 'live_kcd_ground_patch' -or
        $Record.Patch -ne $true -or $Record.FunctionReloadVerified -ne $true -or $Record.EngineReceiptVerified -ne $true -or $Record.Failure -or
        $Record.GroundPatchFile -ine $PatchPath -or $Record.GroundPatchHash -ine $PatchHash -or $Record.Run -cne $Data.run -or $Receipt.run -cne $Data.run -or
        $SourceHash -ine $SnapshotHash -or $Record.SourceHash -ine $SourceHash -or $Record.SnapshotHash -ine $SourceHash -or
        $Data.provenance.source_sha256 -ine $SourceHash -or $Record.GamePath -ine $Context.GamePath -or
        $Record.GameHash -ine $Context.GameHash -or $Data.provenance.game_exe_hash -ine $Context.GameHash -or
        $Record.GamePid -ne $Context.GamePid -or $Data.provenance.game_pid -ne $Context.GamePid -or
        ([datetime]$Record.GameStartedUtc).ToUniversalTime() -ne $Context.GameStartedUtc -or
        ([datetime]$Data.provenance.game_started_utc).ToUniversalTime() -ne $Context.GameStartedUtc) {
        throw 'HUD ground patch does not match its immutable capture and current pinned KCD process.'
    }
    foreach($entry in @($Data,$Receipt)){
        if($entry.result -cne 'sampled' -or $entry.stable_player -isnot [bool] -or -not $entry.stable_player -or
            $entry.grid_size -ne 5 -or $entry.spacing -ne 1 -or $entry.point_count -ne 25 -or $entry.valid_count -ne 25 -or
            $entry.approximate_heightfield -isnot [bool] -or -not $entry.approximate_heightfield -or
            $entry.full_collision_export_verified -isnot [bool] -or $entry.full_collision_export_verified){throw 'Incomplete terrain capture.'}
    }
    foreach($axis in @('x','y','z')){if($Data.center.$axis -ne $Receipt.center.$axis){throw 'Terrain capture centre changed.'}}
    if(@($Data.points).Count -ne 25){throw 'Incomplete terrain capture points.'}
    $captured=[DateTimeOffset]([datetime]$Data.provenance.captured_utc).ToUniversalTime()
    $age=$NowUtcMs-$captured.ToUnixTimeMilliseconds()
    if($age -lt -5000 -or $age -gt 180000){throw 'HUD coupled mode requires a newly captured terrain patch.'}
}
function Read-HudLiveGroundPatch([string]$Path,[string]$ProjectRoot,$Context) {
    $path=Resolve-HudMovementEvidencePath $Path $ProjectRoot
    $data=Read-HudMovementJson $path
    $captureDirectory=Split-Path -Parent $path
    $recordPath=Resolve-HudMovementEvidencePath (Join-Path $captureDirectory 'verification.json') $ProjectRoot
    $receiptPath=Resolve-HudMovementEvidencePath (Join-Path $captureDirectory 'receipt.json') $ProjectRoot
    $sourcePath=Resolve-HudMovementEvidencePath (Join-Path $captureDirectory 'ground_patch.lua') $ProjectRoot
    $record=Read-HudMovementJson $recordPath;$receipt=Read-HudMovementJson $receiptPath
    $patchHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourceHash=(Get-FileHash -LiteralPath (Join-Path $ProjectRoot 'kcd2/probes/ground_patch.lua') -Algorithm SHA256).Hash.ToLowerInvariant()
    $snapshotHash=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-HudLivePatchEvidence $data $record $receipt $path $patchHash $sourceHash $snapshotHash $Context ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    return [pscustomobject]@{Path=$path;Hash=$patchHash;Run=$data.run;Data=$data}
}
function New-HudGroundMovementPatch([string]$Run) {
    if($Run -cnotmatch '^[0-9a-f]{32}$'){throw 'A fresh fixture run token is required.'}
    $points=for($row=0;$row -lt 5;$row++){for($column=0;$column -lt 5;$column++){
        [ordered]@{schema=1;run=$Run;index=1+$row*5+$column;x=120+$column-2;y=2040+$row-2;z=56;nx=0;ny=0;nz=1;valid=$true;result='hit';mask=256;approximate_heightfield=$true;full_collision_export_verified=$false}
    }}
    return [ordered]@{schema=1;run=$Run;result='sampled';center=@{x=120;y=2040;z=56};grid_size=5;spacing=1;point_count=25;valid_count=25;stable_player=$true;mask=256;approximate_heightfield=$true;full_collision_export_verified=$false;points=@($points);provenance=@{kind='standalone_fixture'}}
}
function Assert-HudGroundMovementMarkers($Receipt,[bool]$Expected,[bool]$Coupled=$false) {
    if($Expected -and $Coupled){throw 'Conflicting HUD ground movement modes.'}
    $markers=@{ui_ground_movement_fixture=$Expected;ui_ground_movement_coupled=$Coupled;standalone=($Expected -or $Coupled)}
    foreach($field in $markers.Keys){
        if($null -eq $Receipt.PSObject.Properties[$field]) {
            if($markers[$field]){throw 'HUD ground movement readiness marker missing.'}
            continue
        }
        # Ordinary standalone streams may also identify their controller.
        if($Receipt.$field -isnot [bool] -or
            ($field -ne 'standalone' -and $Receipt.$field -ne $markers[$field]) -or
            ($markers[$field] -and -not $Receipt.$field)) {
            throw 'HUD ground movement readiness mode mismatch.'
        }
    }
}
function Assert-HudGroundMovementProof($Guest,[string]$Run,[string]$PatchHash,[bool]$Coupled=$false,[string]$PatchRun,[string]$TraceFile) {
    Assert-HudGroundMovementMarkers $Guest (-not $Coupled) $Coupled
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $PatchHash -cnotmatch '^[0-9a-f]{64}$' -or $Guest.run -cne $Run -or $Guest.result -cne 'passed') {throw 'Ground/HUD result does not belong to this completed stream.'}
    if(-not $Coupled){$PatchRun=$Run}
    elseif($PatchRun -cnotmatch '^[0-9a-f]{32}$' -or -not $TraceFile){throw 'Coupled HUD proof requires its captured patch run and trace.'}
    $proof=$Guest.lab_evidence.ground_movement
    $kind=if($Coupled){'minecome_hud_ground_movement_coupled_v1'}else{'minecome_hud_ground_movement_fixture_v1'}
    $source=if($Coupled){'live_kcd_ground_patch'}else{'standalone_fixture'}
    if($proof.schema -ne 1 -or $proof.kind -cne $kind -or
        $proof.save -cne $Guest.save -or $proof.save -cnotmatch '^MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
        $proof.patch_run -cne $PatchRun -or $proof.patch_sha256 -cne $PatchHash -or
        $proof.ground_source_kind -cne $source -or $proof.phase -cne 'PASSED') {
        throw 'Ground/HUD fixture provenance or terminal phase differs.'
    }
    if($Coupled -and ($proof.hud_run -cne $Run -or $proof.trace_file -ine $TraceFile -or
        $proof.trace_closed -isnot [bool] -or -not $proof.trace_closed -or $proof.trace_result -cne 'passed' -or
        ($proof.trace_records -isnot [int] -and $proof.trace_records -isnot [long]) -or $proof.trace_records -lt 4 -or $proof.trace_records -gt 200)){
        throw 'Coupled HUD movement trace did not finish within its original bound.'
    }
    foreach($field in @('synthetic_input','client_air','server_air','client_land','server_land','client_proxy_released','server_proxy_released','controls_released','approximate_heightfield')) {
        if($proof.$field -isnot [bool] -or -not $proof.$field){throw "Ground/HUD completion proof missing: $field"}
    }
    foreach($field in @('kcd_calls','kcd_movement_applied','physical_input_verified','full_collision_export_verified')) {
        if($proof.$field -isnot [bool] -or $proof.$field){throw "Ground/HUD fixture overclaims live evidence: $field"}
    }
    foreach($field in @('client_walk','server_walk')) {
        $value=$proof.$field
        if(($value -isnot [double] -and $value -isnot [int] -and $value -isnot [long] -and $value -isnot [decimal]) -or
            -not [double]::IsFinite([double]$value) -or $value -lt 0.3 -or $value -gt 4){throw 'Vanilla walk was not confirmed inside the bounded patch.'}
    }
    foreach($field in @('client_proxy_queries','server_proxy_queries')){
        if(($proof.$field -isnot [int] -and $proof.$field -isnot [long]) -or $proof.$field -lt 1){throw 'Both game threads must query imported ground collision.'}
    }
    if(($proof.post_settle_corrections -isnot [int] -and $proof.post_settle_corrections -isnot [long]) -or $proof.post_settle_corrections -ne 0){throw 'Unexpected movement correction after settling.'}
    $captures=$proof.frame_captures
    foreach($phase in @('WALKING','JUMPING','LANDING')){
        if(($captures.$phase -isnot [int] -and $captures.$phase -isnot [long]) -or $captures.$phase -lt 0){throw 'Invalid movement-phase capture evidence.'}
    }
    if($captures.WALKING -lt 1 -or $captures.JUMPING+$captures.LANDING -lt 1){throw 'HUD frames did not overlap walk and jump phases.'}
    return $proof
}
