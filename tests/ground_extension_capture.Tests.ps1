# Pure capture-document checks; no game/process/HTTP calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Test-KcdGroundExtension.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
$definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'ConvertTo-MineComeGroundExtension'},$true)
Invoke-Expression $definition.Extent.Text
$definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Wait-MineComeGroundExtensionEndpoint'},$true)
Invoke-Expression $definition.Extent.Text
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
function Clone($Value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 12)}
$run='a'*32;$source='b'*64
$context=[pscustomobject]@{GamePid=123;GameStartedUtc=[datetime]::SpecifyKind([datetime]'2026-10-29T20:00:00',[DateTimeKind]::Utc);GameHash=('c'*64)}
$summary=[pscustomobject]@{schema=1;run=$run;result='sampled';anchor=[pscustomobject]@{x=120.0;y=2040.0;z=56.0};tile_count=3;offset_x=4;grid_size=9;spacing=1;
    point_count=243;valid_count=243;ray_count=243;mask_name='ent_terrain';mask=256;stable_player=$true;approximate_heightfield=$true;full_collision_export_verified=$false}
$points=@(for($tile=0;$tile -lt 3;$tile++){for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 9;$col++){
    $x=$tile*4+$col-4;$y=$row-4;$normal=[Math]::Sqrt(1+.02*.02+.01*.01)
    [pscustomobject]@{schema=1;run=$run;tile=$tile;index=1+$row*9+$col;x=120.0+$x;y=2040.0+$y;z=56.0+.02*$x+.01*$y;
        nx=-.02/$normal;ny=-.01/$normal;nz=1/$normal;mask=256;valid=$true;result='hit';approximate_heightfield=$true;full_collision_export_verified=$false}
}}})
$document=ConvertTo-MineComeGroundExtension $summary $points $context $source $run
$manifest=$document.Json | ConvertFrom-Json
Check (($manifest.PSObject.Properties.Name -join ',') -ceq 'schema,kind,run,tiles') 'Strict manifest key contract'
Check ($manifest.tiles.Count -eq 3) 'Exactly three tiles'
for($tile=0;$tile -lt 3;$tile++){
    $entry=$manifest.tiles[$tile];$decoded=$entry.json | ConvertFrom-Json
    Check ($decoded.run -ceq $run -and $decoded.center.x -eq 120+4*$tile -and $decoded.center.z -eq 56) 'Immutable anchor and shared capture identity'
    Check ($decoded.provenance.kind -ceq 'live_kcd_ground_patch' -and $decoded.points.Count -eq 81) 'Explicit captured provenance'
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($entry.json))).ToLowerInvariant()
    Check ($hash -ceq $entry.sha256 -and $hash -ceq $document.TileHashes[$tile]) 'Exact embedded byte hash'
}
foreach($change in @('unstable','partial','mask','run','schema','offset','anchor')){
    $bad=Clone $summary
    switch($change){unstable{$bad.stable_player=$false}partial{$bad.valid_count=242}mask{$bad.mask=0}run{$bad.run='d'*32}schema{$bad.schema='1'}offset{$bad.offset_x=8}anchor{$bad.anchor.x=10000000}}
    Reject {ConvertTo-MineComeGroundExtension $bad $points $context $source $run} "Reject bad summary $change"
}
foreach($change in @('duplicate','tile','index','run','mask','invalid','coordinate','normal','step','overlap','nonadjacent-overlap')){
    $bad=Clone $points
    switch($change){duplicate{$bad[1].index=1}tile{$bad[0].tile=3}index{$bad[0].index=0}run{$bad[0].run='d'*32}mask{$bad[0].mask=287}
        invalid{$bad[0].valid=$false}coordinate{$bad[81].x+=.1}normal{$bad[0].nz=0}step{$bad[0].z+=1}overlap{$bad[162].z+=.0002}nonadjacent-overlap{$bad[85].z+=.000075;$bad[162].z+=.00015}}
    Reject {ConvertTo-MineComeGroundExtension $summary $bad $context $source $run} "Reject bad point $change"
}
Reject {ConvertTo-MineComeGroundExtension $summary $points[0..241] $context $source $run} 'Reject missing point'
function Assert-MineComeProbeContext($Context){if($script:changed){throw 'Captured tools process identity changed.'};$script:identityChecks++}
function Get-MineComeToolsConsoleBinding {
    $script:attempts++
    if($script:attempts -le $script:failures){throw $script:endpointError}
    return [pscustomobject]@{StatusCode=200;Body='ExecuteString'}
}
function Start-Sleep {param($Milliseconds)}
$script:changed=$false;$script:identityChecks=0;$script:attempts=0;$script:failures=2
$script:endpointError='Official tools request exceeded its absolute timeout'
$ready=Wait-MineComeGroundExtensionEndpoint $context
Check ($ready.attempts -eq 3 -and $script:attempts -eq 3 -and $script:identityChecks -eq 6) 'Read-only startup retry keeps identity checks and finite attempts'
$script:attempts=0;$script:failures=3
Reject {Wait-MineComeGroundExtensionEndpoint $context} 'Third timeout remains failure'
Check ($script:attempts -eq 3) 'Retry bound is exact'
$script:attempts=0;$script:endpointError='Official tools returned HTTP 403; redirects are disabled'
Reject {Wait-MineComeGroundExtensionEndpoint $context} 'Other HTTP errors are never retried'
Check ($script:attempts -eq 1) 'Unexpected HTTP error aborts immediately'
$script:changed=$true;$script:attempts=0
Reject {Wait-MineComeGroundExtensionEndpoint $context} 'Process change is fatal before query'
Check ($script:attempts -eq 0) 'No endpoint call after process change'
Write-Output "GROUND_EXTENSION_CAPTURE_TESTS_PASS checks=$script:checks no_game_started=true"
