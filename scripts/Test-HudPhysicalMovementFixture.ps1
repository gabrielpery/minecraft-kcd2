# Actual Minecraft controller/physics/HUD exercise with explicitly scripted edges.
# No KCD commands, renderer arm, reverse-input mapping, or physical-input claims.
[CmdletBinding()]
param([string]$JavaHome,[string]$GroundPatchFile,[ValidateRange(-180,180)][double]$YawDegrees=0,[switch]$PreflightOnly,[switch]$ExtendedWalking,[switch]$AimedBlocks,[switch]$WideWalking,[switch]$FacingSeed,[switch]$CorridorWalking)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $bootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($bootstrapExit -ne 0){throw "Scripted physical controller fixture failed with exit code $bootstrapExit."};return
}
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudGroundCorridor.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingAimed.ps1')
if($CorridorWalking -and (-not $ExtendedWalking -or $WideWalking -or $FacingSeed)){throw 'CorridorWalking requires the separate extended physical fixture.'}
if($CorridorWalking){
    if($PSBoundParameters.ContainsKey('YawDegrees') -and $YawDegrees -ne -90){throw 'Corridor fixture crosses the X edge at yaw -90.'}
    $YawDegrees=-90
}
if($AimedBlocks -and -not $ExtendedWalking){throw 'Combined aimed blocks require the explicit extended standalone walking fixture.'}
if($AimedBlocks -and $YawDegrees -ne $(if($CorridorWalking){-90}else{0})){throw 'Combined aimed blocks require the tested zero-yaw fixture.'}
if($WideWalking -and -not $ExtendedWalking){throw 'Wide walking fixture requires ExtendedWalking.'}
if($FacingSeed -and (-not $WideWalking -or -not $AimedBlocks)){throw 'FacingSeed requires the wide aimed fixture.'}
function Assert-HudWalkingAimedFixtureProof($Aimed,$Fixture,$Guest,[string]$PatchHash,[switch]$WideWalking,[switch]$FacingSeed,[switch]$CorridorWalking) {
    function Flag($Object,[string]$Name,[bool]$Expected){if($Object.$Name -isnot [bool] -or $Object.$Name -ne $Expected){throw "Combined fixture boolean mismatch: $Name"}}
    function Text($Object,[string]$Name,[string]$Expected){if($Object.$Name -isnot [string] -or $Object.$Name -cne $Expected){throw "Combined fixture text mismatch: $Name"}}
    function Count($Object,[string]$Name,[long]$Expected){if(($Object.$Name -isnot [int] -and $Object.$Name -isnot [long]) -or $Object.$Name -ne $Expected){throw "Combined fixture integer mismatch: $Name"}}
    function Number($Value,[double]$Min,[double]$Max){
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) -or -not [double]::IsFinite([double]$Value) -or $Value -lt $Min -or $Value -gt $Max){throw 'Combined fixture finite bounded number required.'}
        return [double]$Value
    }
    function Cell($Value){foreach($axis in @('x','y','z')){if(($Value.$axis -isnot [int] -and $Value.$axis -isnot [long]) -or [Math]::Abs([double]$Value.$axis) -gt 10000000){throw 'Combined fixture integer cell required.'}}}
    function SameCell($Actual,$Expected){Cell $Actual;Cell $Expected;foreach($axis in @('x','y','z')){if($Actual.$axis -ne $Expected.$axis){throw 'Combined fixture cell correlation differs.'}}}
    Text $Aimed kind 'standalone_hud_walking_aimed_fixture_v1'
    Assert-HudWalkingArea $Aimed ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
    if($FacingSeed){Flag $Aimed facing_seed $true;Text $Aimed facing_side 'NORTH'}
    elseif($Aimed.PSObject.Properties['facing_seed']){throw 'Facing fixture proof requires explicit selection.'}
    if(($Fixture.aimed_hud_frames -isnot [int] -and $Fixture.aimed_hud_frames -isnot [long]) -or $Fixture.aimed_hud_frames -lt 2){throw 'Combined fixture lacks actual HUD frames during block interactions.'}
    foreach($name in @('scripted_input','synthetic_host_rays','completed','alignment_before_movement','bootstrap_before_movement','movement_before_interactions','movement_resumed_after_interactions','support_client_server_prepared','support_client_server_restored_air','imported_cells_unchanged','final_client_server_air')){Flag $Aimed $name $true}
    foreach($name in @('physical_input_verified','kcd_connected')){Flag $Aimed $name $false}
    Text $Aimed patch_sha256 $PatchHash;Text $Aimed patch_run $Fixture.physical_movement.patch_run
    foreach($name in @('support_fixture_setup_writes','support_fixture_cleanup_writes')){Count $Aimed $name 1}
    Count $Aimed arena_direct_block_writes 0
    [void](Number $Aimed.walk_before_m .05 4);[void](Number $Aimed.walk_after_m .05 4)
    $seed=$Aimed.seed;Cell $seed
    if($CorridorWalking -and ($seed.x -ne -1 -or $seed.z -ne -5)){throw 'Corridor fixture requires its reachable north perimeter support.'}
    if($FacingSeed){
        if($seed.x -notin @(-1,0) -or $seed.z -ne 4){throw 'Facing fixture support must face the declared zero-yaw direction.'}
    }elseif($WideWalking -and ($seed.x -ne 4 -or $seed.z -ne 0)){throw 'Wide fixture support must remain outside the imported terrain.'}
    if($WideWalking -or $CorridorWalking){
        [void](Number $Aimed.max_host_ray_range 4.5 4.5)
        $topX=$seed.x+$(if($CorridorWalking){.75}elseif($FacingSeed){.5}else{.25});$topZ=$seed.z+$(if($CorridorWalking){.75}elseif($FacingSeed){.25}else{.5})
        [void](Number $Aimed.top_aim_point.x $topX $topX)
        [void](Number $Aimed.top_aim_point.y ($seed.y+1) ($seed.y+1))
        [void](Number $Aimed.top_aim_point.z $topZ $topZ)
    }
    $support=[pscustomobject]@{x=$seed.x;y=$seed.y-1;z=$seed.z};SameCell $Aimed.support $support
    $top=[pscustomobject]@{x=$seed.x;y=$seed.y+1;z=$seed.z};$west=[pscustomobject]@{x=$seed.x-1;y=$seed.y;z=$seed.z}
    if($FacingSeed){$west=[pscustomobject]@{x=$seed.x;y=$seed.y;z=$seed.z-1}}
    if($CorridorWalking){$west=[pscustomobject]@{x=$seed.x+1;y=$seed.y;z=$seed.z}}
    $targets=@($seed,$top,$top,$west,$west,$seed);$hits=@($support,$seed,$top,$seed,$west,$seed)
    $labels=@('bootstrap','top_place','upper_break','west_place','west_break','seed_break');$actions=@(1,1,2,1,2,2)
    $side=if($CorridorWalking){'EAST'}elseif($FacingSeed){'NORTH'}else{'WEST'}
    if($FacingSeed){$labels[3]='side_place';$labels[4]='side_break'}
    if($CorridorWalking){$labels[3]='east_place';$labels[4]='east_break'}
    $arena=$Aimed.arena
    Count $arena schema 1;Text $arena kind 'minecome_aimed_stone_arena_v1';Text $arena save $Guest.save;SameCell $arena.seed $seed
    Count $arena max_owned_count 16
    SameCell $arena.arena_minimum ([pscustomobject]@{x=$seed.x-2;y=$seed.y-2;z=$seed.z-2})
    SameCell $arena.arena_maximum_inclusive ([pscustomobject]@{x=$seed.x+2;y=$seed.y+2;z=$seed.z+2})
    Flag $arena vanilla_outline_raycast $true;Text $arena fluid_raycast 'NONE';Flag $arena live_transport_enabled $false
    $region=$arena.build_region
    Text $region patch_run $Aimed.patch_run;Text $region patch_sha256 $PatchHash;SameCell $region.support $support;Flag $region support_editable $false
    # Each imported half-height slab intersects one or two
    # integer block cells; these cells are protected, not arena-owned stones.
    $slabs=if($CorridorWalking){96}elseif($WideWalking){64}else{16}
    if(($region.protected_imported_cells -isnot [int] -and $region.protected_imported_cells -isnot [long]) -or $region.protected_imported_cells -lt $slabs -or $region.protected_imported_cells -gt 2*$slabs){throw 'Combined fixture protected terrain count is outside the sampled slab bound.'}
    foreach($name in @('block_writes','inventory_writes','camera_writes','owned_count','omitted_receipts')){Count $arena $name 0}
    Flag $arena pending $false
    if($null -ne $arena.failure -or @($arena.owned_cells).Count -ne 0 -or @($Aimed.confirmations).Count -ne 6 -or @($arena.confirmations).Count -ne 6 -or @($arena.requests).Count -ne 6){throw 'Combined fixture requires exactly six confirmed actions and complete arena cleanup.'}
    $last=-30001.0
    for($index=0;$index -lt 6;$index++){
        $row=$Aimed.confirmations[$index];$confirmed=$arena.confirmations[$index];$request=$arena.requests[$index]
        Text $row label $labels[$index];Count $row id ($index+1);Count $row action $actions[$index]
        foreach($name in @('client_and_server','confirmed')){Flag $row $name $true}
        SameCell $row.target $targets[$index];SameCell $row.hit_block $hits[$index]
        if($row.face -isnot [string] -or $row.face -cnotin @('UP','DOWN','NORTH','SOUTH','WEST','EAST')){throw 'Combined fixture face is not cardinal.'}
        if(($index -in @(0,1) -and $row.face -cne 'UP') -or ($index -eq 3 -and $row.face -cne $side)){throw 'Combined fixture placement did not use the intended face.'}
        [void](Number $row.client_server_distance 0 .01)
        Text $row speed_metric 'horizontal_xz'
        foreach($name in @('client_speed','server_speed')){if((Number $row.$name 0 .03) -ge .03){throw 'Combined fixture acted while the player was moving.'}}
        foreach($name in @('client_vertical_velocity','server_vertical_velocity')){if([Math]::Abs((Number $row.$name -.1 .1)) -ge .1){throw 'Combined fixture acted while the player was airborne.'}}
        foreach($name in @('client_on_ground','server_on_ground')){Flag $row $name $true}
        $elapsed=Number $row.elapsed_from_first_movement_ms -30000 15000
        if($elapsed -le $last -or ($index -eq 0 -and $elapsed -ge 0) -or ($index -gt 0 -and ($elapsed -le 0 -or $elapsed -ge 15000))){throw 'Combined fixture action timing is not ordered inside the movement session.'}
        $last=$elapsed
        foreach($component in @($confirmed,$request)){
            Count $component id ($index+1);Count $component action $actions[$index];Text $component status 'confirmed';Flag $component client_and_server $true
            SameCell $component.target $row.target;SameCell $component.hit_block $row.hit_block;Text $component face $row.face
        }
    }
    if($Aimed.confirmations[1].elapsed_from_first_movement_ms -le $Fixture.pulses[2].elapsed_from_first_movement_ms){throw 'Combined block interactions did not follow actual walking.'}
    $downs=@($Fixture.physical_movement.input_timing.events | Where-Object accepted_down -EQ $true)
    $resumedMs=([decimal]$downs[3].received_monotonic_ns-[decimal]$downs[0].received_monotonic_ns)/1000000
    if($resumedMs -le $Aimed.confirmations[-1].elapsed_from_first_movement_ms){throw 'Combined fixture did not resume walking after block interactions.'}
}
function Assert-HudPhysicalFixtureResult($Guest,[string]$Run,[string]$PatchHash,[switch]$ExtendedWalking,[switch]$AimedBlocks,[switch]$WideWalking,[switch]$FacingSeed,[switch]$CorridorWalking) {
    if($FacingSeed -and (-not $WideWalking -or -not $AimedBlocks)){throw 'FacingSeed requires the wide aimed fixture.'}
    if($AimedBlocks -and -not $ExtendedWalking){throw 'Combined aimed blocks require the extended walking fixture.'}
    if($WideWalking -and -not $ExtendedWalking){throw 'Wide walking fixture requires ExtendedWalking.'}
    if($Guest.schema -ne 1 -or $Guest.run -cne $Run -or $Guest.result -cne 'passed' -or $Guest.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or
        $Guest.ui_physical_controller_fixture -isnot [bool] -or -not $Guest.ui_physical_controller_fixture -or $Guest.ui_input_physical_movement -isnot [bool] -or $Guest.ui_input_physical_movement -or
        $Guest.scripted_input -isnot [bool] -or -not $Guest.scripted_input -or $Guest.physical_input_verified -isnot [bool] -or $Guest.physical_input_verified -or
        $Guest.standalone -isnot [bool] -or -not $Guest.standalone -or $Guest.kcd_compositing_verified -isnot [bool] -or $Guest.kcd_compositing_verified -or $Guest.published_frames -lt 30){throw 'Fixture stream identity/provenance/frame evidence differs.'}
    foreach($name in @('closed_published','mapping_unmapped','mapping_handle_closed','mutex_handle_closed')){
        if($Guest.$name -isnot [bool] -or -not $Guest.$name){throw "Fixture stream cleanup missing: $name"}
    }
    $proof=$Guest.lab_evidence.physical_controller_fixture
    foreach($marker in @($Guest,$proof)){
        $field=$marker.PSObject.Properties['ui_walking_aimed_fixture']
        if($AimedBlocks){
            if($null -eq $field -or $field.Value -isnot [bool] -or -not $field.Value){throw 'Combined walking/aimed fixture marker is absent.'}
        }elseif($null -ne $field -and ($field.Value -isnot [bool] -or $field.Value)){throw 'Ordinary walking fixture cannot accept combined aimed blocks.'}
    }
    if(-not $AimedBlocks -and $null -ne $proof.PSObject.Properties['aimed_blocks']){throw 'Unrequested aimed block proof cannot enter ordinary walking evidence.'}
    foreach($number in @($proof.inventory_client_max_displacement,$proof.inventory_server_max_displacement,$proof.physical_movement.client_walk,$proof.physical_movement.server_walk)){
        if($number -isnot [ValueType] -or $number -is [bool] -or -not [double]::IsFinite([double]$number) -or $number -lt 0){throw 'Fixture contains invalid/nonfinite displacement.'}
    }
    if($proof.kind -cne 'standalone_hud_physical_controller_fixture_v1' -or $proof.scripted_input -isnot [bool] -or -not $proof.scripted_input -or
        $proof.physical_input_verified -isnot [bool] -or $proof.physical_input_verified -or $proof.kcd_compositing_verified -isnot [bool] -or $proof.kcd_compositing_verified -or
        $proof.completed -isnot [bool] -or -not $proof.completed -or $proof.camera_worker_stopped -isnot [bool] -or -not $proof.camera_worker_stopped -or
        $proof.inventory_client_max_displacement -gt .01 -or $proof.inventory_server_max_displacement -gt .01 -or $proof.inventory_frames -lt 2 -or $proof.walking_hud_frames -lt 2 -or $proof.synthetic_camera_samples -lt 10){throw 'Fixture did not verify actual inventory suppression, HUD frames and camera cleanup.'}
    $movement=$proof.physical_movement
    foreach($marker in @($Guest,$proof,$movement)){
        Assert-HudWalkingArea $marker ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
        $field=$marker.PSObject.Properties['movement_session']
        if($ExtendedWalking){
            if($null -eq $field -or $field.Value -isnot [string] -or $field.Value -cne 'extended'){throw 'Extended fixture requires its exact session marker.'}
        }elseif($null -ne $field -and ($field.Value -isnot [string] -or $field.Value -cne 'short')){throw 'Short fixture cannot accept another movement session.'}
    }
    if($WideWalking){
        if($proof.wide_boundary_crossed -isnot [bool] -or -not $proof.wide_boundary_crossed){throw 'Wide fixture did not cross the original walking boundary.'}
        foreach($name in @('client_max_horizontal_excursion','server_max_horizontal_excursion')){
            $value=$proof.$name
            if($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -le 2 -or $value -gt 4){throw 'Wide fixture lacks bounded client/server travel beyond two metres.'}
        }
    }
    if($CorridorWalking){
        foreach($name in @('client_max_x','server_max_x')){
            $value=$proof.$name
            if($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -lt 4.5 -or $value -gt 7.5){throw 'Whole player footprint did not cross the old corridor edge.'}
        }
        if($proof.crossing_hud_frames -lt 1){throw 'No actual HUD frames while crossing the old terrain edge.'}
        foreach($name in @('client_return_distance','server_return_distance')){
            $value=$proof.$name
            if($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -lt 0 -or $value -gt .75){throw 'Corridor fixture did not return near its fixed origin.'}
        }
        if($proof.corridor_boundary_crossed -isnot [bool] -or -not $proof.corridor_boundary_crossed){throw 'Corridor fixture did not cross the old four-metre edge.'}
        foreach($name in @('client_max_horizontal_excursion','server_max_horizontal_excursion')){
            $value=$proof.$name
            if($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -le 4 -or $value -gt 7.5){throw 'Corridor excursion outside expected captured bounds.'}
        }
    }
    $keys=if($CorridorWalking -or $WideWalking){@('W','S','W','W','S')}elseif($ExtendedWalking){@('W','W','S','W','S')}else{@('W','W','S')}
    if(@($proof.pulses).Count -ne $keys.Count){throw 'Fixture actual movement pulse count differs.'}
    $lastPulseMs=-1.0
    for($index=0;$index -lt $keys.Count;$index++){
        $pulse=$proof.pulses[$index]
        if($pulse.key -cne $keys[$index] -or $pulse.step_m -isnot [ValueType] -or $pulse.step_m -is [bool] -or -not [double]::IsFinite([double]$pulse.step_m) -or $pulse.step_m -lt .05 -or
            $pulse.server_step_m -isnot [ValueType] -or $pulse.server_step_m -is [bool] -or -not [double]::IsFinite([double]$pulse.server_step_m) -or $pulse.server_step_m -lt .05 -or
            $pulse.client_server_distance -isnot [ValueType] -or $pulse.client_server_distance -is [bool] -or -not [double]::IsFinite([double]$pulse.client_server_distance) -or $pulse.client_server_distance -lt 0 -or $pulse.client_server_distance -gt .1){throw 'Fixture repeated movement/server agreement failed.'}
        if($ExtendedWalking){
            $elapsed=$pulse.elapsed_from_first_movement_ms
            if($elapsed -isnot [ValueType] -or $elapsed -is [bool] -or -not [double]::IsFinite([double]$elapsed) -or $elapsed -le $lastPulseMs -or $elapsed -gt 16000 -or ($index -ge 3 -and $elapsed -le 5000)){throw 'Extended fixture lacks ordered movement beyond the short session.'}
            $lastPulseMs=[double]$elapsed
        }
    }
    if($ExtendedWalking){
        foreach($name in @('post_walk_inventory_opened','post_walk_inventory_closed')){
            if($proof.$name -isnot [bool] -or -not $proof.$name){throw 'Extended fixture did not reopen and close the actual inventory.'}
        }
        foreach($name in @('post_walk_inventory_client_max_displacement','post_walk_inventory_server_max_displacement')){
            $value=$proof.$name
            if($value -isnot [ValueType] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -lt 0 -or $value -gt .01){throw 'Extended fixture moved while the reopened inventory was active.'}
        }
        if(($proof.post_walk_inventory_frames -isnot [int] -and $proof.post_walk_inventory_frames -isnot [long]) -or $proof.post_walk_inventory_frames -lt 2){throw 'Extended fixture lacks reopened inventory frames.'}
        $duration=$movement.duration_ms
        if(($duration -isnot [int] -and $duration -isnot [long]) -or $duration -lt 15000 -or $duration -gt 16000){throw 'Extended fixture did not complete its bounded fifteen-second session.'}
    }
    if($movement.run -cne $Run -or $movement.patch_sha256 -cne $PatchHash -or $movement.ground_source_kind -cne $(if($CorridorWalking){'standalone_corridor_fixture'}else{'standalone_ground_fixture'}) -or
        $movement.input_source -cne 'scripted_hud_physical_controller_fixture' -or $movement.scripted_input -isnot [bool] -or -not $movement.scripted_input -or
        $movement.physical_input_verified -isnot [bool] -or $movement.physical_input_verified -or $movement.trace_result -cne 'passed' -or $movement.post_settle_corrections -ne 0 -or
        $movement.client_walk -lt .15 -or $movement.server_walk -lt .15 -or $movement.held_ticks -lt 3){throw 'Actual controller movement proof differs.'}
    foreach($name in @('started','completed','trace_closed','client_proxy_released','server_proxy_released','controls_released')){
        if($movement.$name -isnot [bool] -or -not $movement.$name){throw "Actual controller completion/cleanup missing: $name"}
    }
    if($Guest.lab_evidence.input_tick_phase -cne 'start_before_vanilla'){throw 'Fixture did not exercise input before vanilla polling.'}
    $timing=$movement.input_timing
    if($timing.kind -cne 'minecome_hud_movement_timing_v1' -or $timing.truncated -ne $false -or
        $timing.native_application_measured -ne $false -or $timing.display_latency_measured -ne $false -or
        $timing.event_count -ne @($timing.events).Count -or $timing.binding_state_count -ne @($timing.binding_states).Count){throw 'Fixture input timing evidence is missing, truncated or claims unsupported proof.'}
    $accepted=@($timing.events | Where-Object accepted_down -EQ $true)
    if($accepted.Count -ne $keys.Count){throw 'Fixture timing must retain every accepted scripted press.'}
    for($index=0;$index -lt $accepted.Count;$index++){
        $expected=if($keys[$index] -ceq 'W'){0x57}else{0x53}
        if($accepted[$index].key -ne $expected){throw 'Accepted scripted keys do not match the observed movement pulses.'}
    }
    if($ExtendedWalking){
        $first=$accepted[0].received_monotonic_ns
        $previous=$null
        for($index=0;$index -lt $accepted.Count;$index++){
            $stamp=$accepted[$index].received_monotonic_ns
            if(($stamp -isnot [long] -and $stamp -isnot [int]) -or ($null -ne $previous -and $stamp -le $previous)){throw 'Extended fixture movement clocks are not ordered integers.'}
            $elapsed=[decimal]$stamp-[decimal]$first
            if($elapsed -lt 0 -or $elapsed -ge 15000000000 -or ($index -ge 3 -and $elapsed -le 5000000000)){throw 'Extended fixture late movement did not occur inside its selected input window.'}
            $previous=$stamp
        }
    }
    $delays=@(foreach($edge in $accepted){
        $bit=if($edge.key -eq 0x57){1}elseif($edge.key -eq 0x53){2}else{throw 'Unexpected scripted movement key.'}
        $binding=@($timing.binding_states | Where-Object {$_.stage -ceq 'before_vanilla_poll' -and $_.after_input_sequence -eq $edge.input_sequence -and ($_.mask -band $bit) -ne 0})
        if($binding.Count -ne 1 -or $binding[0].monotonic_ns -lt $edge.received_monotonic_ns){throw 'Scripted press lacks one real pre-vanilla binding observation.'}
        ([double]([decimal]$binding[0].monotonic_ns-[decimal]$edge.received_monotonic_ns))/1000000
    })
    $proof | Add-Member -NotePropertyName scripted_receive_to_binding_ms -NotePropertyValue $delays -Force
    if($AimedBlocks){Assert-HudWalkingAimedFixtureProof $proof.aimed_blocks $proof $Guest $PatchHash -WideWalking:$WideWalking -FacingSeed:$FacingSeed -CorridorWalking:$CorridorWalking}
    return $proof
}
function Get-HudPhysicalFixtureSources([string]$Root) {
    $files=[Collections.Generic.List[string]]::new()
    foreach($folder in @('minecraft/src/main/java','minecraft/src/main/resources','protocol/java/src/main/java')){
        foreach($file in [IO.Directory]::EnumerateFiles((Join-Path $Root $folder),'*',[IO.SearchOption]::AllDirectories)){
            $files.Add($file.Substring($Root.Length+1).Replace('\','/'))
        }
    }
    foreach($file in @('minecraft/build.gradle','scripts/Test-HudPhysicalMovementFixture.ps1','scripts/Run-HudStreamClient.ps1','scripts/HudWalkingArea.ps1','scripts/HudGroundMovement.ps1','scripts/HudGroundCorridor.ps1','scripts/HudWalkingAimed.ps1')){$files.Add($file)}
    return @($files | Sort-Object -Unique)
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$inventory=Get-Content -LiteralPath (Join-Path $root 'runtime/environment.json') -Raw | ConvertFrom-Json
if(-not $JavaHome){foreach($candidate in @($inventory.java.jdks | ForEach-Object home)){if((Test-Path -LiteralPath (Join-Path $candidate 'release')) -and [IO.File]::ReadAllText((Join-Path $candidate 'release')) -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")'){$JavaHome=$candidate;break}}}
if(-not $JavaHome -or -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")'){throw 'An installed tested JDK21 or24 is required.'}
$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path
$sourceHash=$null
if($CorridorWalking){
    if($GroundPatchFile){
        $inputCorridor=Read-HudGroundCorridorInput $GroundPatchFile $root $true
        $sourceHash=$inputCorridor.Hash
        $patch=Get-Content -LiteralPath $inputCorridor.Path -Raw | ConvertFrom-Json -Depth 12
    }else{
        $patch=New-HudGroundCorridorFixture ('0'*32) | ConvertTo-Json -Depth 12 | ConvertFrom-Json -Depth 12
        $sourceHash=$null
    }
}else{
if($GroundPatchFile){
    $GroundPatchFile=Resolve-HudMovementEvidencePath $GroundPatchFile $root
    if((Get-Item -LiteralPath $GroundPatchFile).Length -gt 65536){throw 'Source terrain patch exceeds64KiB.'}
    $patch=Get-Content -LiteralPath $GroundPatchFile -Raw | ConvertFrom-Json
    $sourceHash=(Get-FileHash -LiteralPath $GroundPatchFile -Algorithm SHA256).Hash.ToLowerInvariant()
}else{
    $gridSize=if($WideWalking){9}else{5};$half=[int](($gridSize-1)/2)
    $points=@(for($row=0;$row -lt $gridSize;$row++){for($column=0;$column -lt $gridSize;$column++){[ordered]@{index=$row*$gridSize+$column+1;x=$column-$half;y=$row-$half;z=10;nx=0;ny=0;nz=1}}})
    $patch=[pscustomobject]@{schema=1;run='pending';grid_size=$gridSize;spacing=1;center=[ordered]@{x=0;y=0;z=10};points=$points;provenance=[ordered]@{kind='standalone_ground_fixture'}}
    if($WideWalking){$patch | Add-Member NoteProperty walking_area 'wide'}
}
Assert-HudWalkingArea $patch ([bool]$WideWalking)
$expectedGrid=if($WideWalking){9}else{5}
if($patch.grid_size -ne $expectedGrid -or $patch.spacing -ne 1 -or @($patch.points).Count -ne $expectedGrid*$expectedGrid){throw 'Supplied terrain must already match the selected fixed walking area; captured terrain is never extended.'}
}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*')})
if($clients.Count){throw 'An existing MineCome Minecraft client is open; preserving it.'}
if($PreflightOnly){Write-Output 'HUD_PHYSICAL_FIXTURE_PREFLIGHT_PASS no_process_started=true kcd_unchanged=true';return}
$run=[guid]::NewGuid().ToString('N');$patchRun=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/hud-physical-fixture-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[IO.Directory]::CreateDirectory($directory) | Out-Null
$patchPath=Join-Path $directory $(if($CorridorWalking){'standalone-ground-corridor.json'}else{'standalone-ground-patch.json'});$tracePath=Join-Path $directory 'movement.ndjson';$viewPath=Join-Path $directory 'fixture-view.json'
$patch.run=$patchRun
if($CorridorWalking){
    foreach($tile in $patch.tiles){
        $sample=$tile.json | ConvertFrom-Json -Depth 12
        $sample.run=$patchRun
        $sample | Add-Member NoteProperty provenance ([ordered]@{kind='standalone_fixture';original_capture_sha256=$sourceHash;numeric_samples_only=$true}) -Force
        $tile.json=$sample | ConvertTo-Json -Depth 12 -Compress
        $tile.sha256=Get-HudCorridorHash ([Text.Encoding]::UTF8.GetBytes($tile.json))
    }
}else{
    $patch | Add-Member -NotePropertyName provenance -NotePropertyValue ([ordered]@{kind='standalone_ground_fixture';original_capture_sha256=$sourceHash;numeric_samples_only=$true}) -Force
}
$patch | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $patchPath -Encoding utf8NoBOM
(Get-Item -LiteralPath $patchPath).IsReadOnly=$true
$patchHash=(Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
$ownProcess=Get-Process -Id $PID
try{$targetStart=$ownProcess.StartTime.ToUniversalTime().ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)}finally{$ownProcess.Dispose()}
$expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+120000
$tracePassed=$false;$traceHash=$null;$passed=$false;$failure=$null;$proof=$null;$sourceHashes=@();$sourceHashesVerified=$false;$corridorBuildProof=$null
try{
    if($AimedBlocks -or $CorridorWalking){
        $sourceHashes=@(foreach($path in Get-HudPhysicalFixtureSources $root){[ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath (Join-Path $root $path) -Algorithm SHA256).Hash.ToLowerInvariant()}})
        [ordered]@{schema=1;kind=$(if($CorridorWalking){'standalone_hud_corridor_physical_source_manifest_v1'}else{'standalone_hud_walking_aimed_source_manifest_v1'});run=$run;ui_walking_aimed_fixture=[bool]$AimedBlocks;files=$sourceHashes} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $directory 'source-hashes.json') -Encoding utf8NoBOM
    }
    Write-Output "HUD_PHYSICAL_FIXTURE_START run=$run evidence=$directory scripted_input=true kcd_unchanged=true"
    & (Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1') -EvidenceDirectory $directory -Run $run -TargetPid $PID -TargetStart $targetStart -ExpiresUtcMs $expires -JavaHome $JavaHome -Standalone -PhysicalMovementFixture -GroundPatchFile $patchPath -MovementTraceFile $tracePath -HostViewFile $viewPath -PhysicalFixtureYaw $YawDegrees -ExtendedWalking:$ExtendedWalking -AimedBlocks:$AimedBlocks -WideWalking:$WideWalking -FacingSeed:$FacingSeed -CorridorWalking:$CorridorWalking
    if($LASTEXITCODE -ne 0){throw "Minecraft fixture child failed: $LASTEXITCODE"}
    $guest=Get-Content -LiteralPath (Join-Path $directory 'capture/stream-result.json') -Raw | ConvertFrom-Json
    if($guest.result -ceq 'failed'){
        $reason=if($guest.PSObject.Properties.Name -contains 'failure'){$guest.failure}elseif($guest.lab_evidence.PSObject.Properties.Name -contains 'failure'){$guest.lab_evidence.failure}else{'Producer reported failure without a diagnostic'}
        throw "Minecraft fixture failed: $reason"
    }
    $proof=Assert-HudPhysicalFixtureResult $guest $run $patchHash -ExtendedWalking:$ExtendedWalking -AimedBlocks:$AimedBlocks -WideWalking:$WideWalking -FacingSeed:$FacingSeed -CorridorWalking:$CorridorWalking
    if($AimedBlocks -and $CorridorWalking){
        $fixtureCorridor=Read-HudGroundCorridorInput $patchPath $root $false
        $corridorBuildProof=Assert-HudWalkingAimedCorridorBuild -Guest $guest -Corridor $fixtureCorridor
    }
    $traceLimit=if($ExtendedWalking){256KB}else{64KB}
    if((Get-Item -LiteralPath $tracePath).Length -gt $traceLimit){throw 'Fixture trace exceeded its selected byte budget.'}
    $records=@(Get-Content -LiteralPath $tracePath | ForEach-Object {$_ | ConvertFrom-Json})
    if($records.Count -lt 5 -or $records.Count -gt 200 -or $records[0].kind -cne 'begin' -or $records[-1].kind -cne 'end' -or $records[-1].result -cne 'passed'){throw 'Fixture actual controller trace did not complete.'}
    $traceKind=if($CorridorWalking){'standalone_hud_physical_movement_corridor_fixture'}elseif($ExtendedWalking){'standalone_hud_physical_movement_extended_fixture'}else{'standalone_hud_physical_movement_fixture'}
    foreach($record in $records){
        Assert-HudWalkingArea $record ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
        if($record.source_kind -cne $traceKind -or $record.run -cne $patchRun -or $record.patch_sha256 -cne $patchHash){throw 'Fixture trace provenance/session differs.'}
    }
    $tracePassed=$true;$traceHash=(Get-FileHash -LiteralPath $tracePath).Hash.ToLowerInvariant()
    foreach($state in @('fixture_inventory_blocked','fixture_scripted_walking')){
        $sample=@($guest.samples | Where-Object state -CEQ $state)
        if($sample.Count -ne 1 -or $sample[0].png_file -notmatch '^sample-[a-z0-9_]+\.png$'){throw 'Fixture real HUD/inventory PNG sample absent.'}
        $png=Join-Path $directory ('capture/'+$sample[0].png_file)
        if((Get-Item -LiteralPath $png).Length -lt 100 -or (Get-FileHash -LiteralPath $png -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sample[0].png_sha256){throw 'Fixture captured PNG hash differs.'}
    }
    if($AimedBlocks -or $CorridorWalking){
        $finalSources=@(Get-HudPhysicalFixtureSources $root)
        if(($finalSources -join "`n") -cne (@($sourceHashes | ForEach-Object path) -join "`n")){throw 'Combined fixture source inventory changed during the run.'}
        foreach($entry in $sourceHashes){if((Get-FileHash -LiteralPath (Join-Path $root $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.sha256){throw "Combined fixture source changed during the run: $($entry.path)"}}
        $sourceHashesVerified=$true
    }
    $passed=$true;Write-Output "HUD_PHYSICAL_FIXTURE_VERIFIED run=$run pulses=$(@($proof.pulses).Count) aimed_blocks=$([bool]$AimedBlocks) inventory_movement_suppressed=true actual_minecraft=true physical_input_verified=false kcd_compositing_verified=false"
}catch{$failure=$_.Exception.Message;throw}
finally{
    $verification=[ordered]@{schema=1;kind='standalone_hud_physical_controller_fixture_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;movement_session=$(if($ExtendedWalking){'extended'}else{'short'});ui_walking_aimed_fixture=[bool]$AimedBlocks;source_hashes_verified=$(if($AimedBlocks -or $CorridorWalking){$sourceHashesVerified}else{$null});scripted_input=$true;physical_input_verified=$false;kcd_compositing_verified=$false;kcd_commands_sent=0;renderer_armed=$false;reverse_input_mapping_created=$false;trace_passed=$tracePassed;trace_sha256=$traceHash;patch_sha256=$patchHash;original_capture_sha256=$sourceHash;yaw_degrees=$YawDegrees;proof=$proof}
    if($WideWalking){$verification.walking_area='wide'}
    if($CorridorWalking){$verification.walking_area='corridor';if($AimedBlocks){$verification.corridor_build=$corridorBuildProof}}
    $verification | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}

if($passed){[pscustomobject]@{EvidenceDirectory=$directory;VerificationFile=(Join-Path $directory 'verification.json');TraceFile=$tracePath}}
