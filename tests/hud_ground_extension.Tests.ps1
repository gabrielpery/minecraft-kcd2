# Pure immutable extension validation. No process/HTTP/game calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
. (Join-Path $root 'scripts/HudGroundExtension.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Call,[string]$Message){$failed=$false;try{& $Call | Out-Null}catch{$failed=$true};Check $failed $Message}
function Clone($Value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 20) -Depth 20}
$directory=Join-Path $root ('runtime/evidence/extension-input-fixture-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($directory) | Out-Null
$run='a'*32;$path=Join-Path $directory 'extension.json'
function Save($Value){ConvertTo-Json -InputObject $Value -Depth 10 -Compress | Set-Content -LiteralPath $path -Encoding utf8NoBOM}
function Tile($Manifest,[int]$Index,[scriptblock]$Change){
    $tile=ConvertFrom-Json -InputObject $Manifest.tiles[$Index].json -Depth 10
    & $Change $tile
    $Manifest.tiles[$Index].json=ConvertTo-Json -InputObject $tile -Depth 10 -Compress
    $Manifest.tiles[$Index].sha256=Get-HudExtensionHash ([Text.Encoding]::UTF8.GetBytes($Manifest.tiles[$Index].json))
}
$manifest=New-HudGroundExtensionFixture $run;Save $manifest
$inputRecord=Read-HudGroundExtensionInput $path $root $false
Check ($inputRecord.Run -ceq $run -and $inputRecord.TileHashes.Count -eq 3 -and $inputRecord.Anchor.x -eq 120 -and $inputRecord.Path -ceq $path) 'Three-tile fixture has exact source identity and unchanged origin'
Check ($inputRecord.InitialHash -cmatch '^[0-9a-f]{64}$' -and $inputRecord.InitialHash -cne $inputRecord.Hash) 'Initial corridor hash is distinct from the full extension plan'
Reject {Read-HudGroundExtensionInput $path $root $true} 'Synthetic provenance cannot become live capture'
foreach($change in @('hash','run','kind','schema','missing','extra','entry-extra','provenance','center','height-anchor','point-count','index','coordinate','normal','height-step','first-overlap','second-overlap','nonadjacent-overlap','bad-number')){
    $bad=Clone $manifest
    switch($change){
        hash{$bad.tiles[2].sha256='0'*64}
        run{$bad.run='b'*32}
        kind{$bad.kind='minecome_ground_corridor_v1'}
        schema{$bad.schema='1'}
        missing{$bad.tiles=@($bad.tiles[0],$bad.tiles[1])}
        extra{$bad | Add-Member unexpected 1}
        entry-extra{$bad.tiles[2] | Add-Member unexpected 1}
        provenance{Tile $bad 2 {param($p)$p.provenance.kind='live_kcd_ground_patch'}}
        center{Tile $bad 2 {param($p)$p.center.x+=4}}
        height-anchor{Tile $bad 2 {param($p)$p.center.z+=.1}}
        point-count{Tile $bad 2 {param($p)$p.points=@($p.points[0..79])}}
        index{Tile $bad 2 {param($p)$p.points[0].index=0}}
        coordinate{Tile $bad 2 {param($p)$p.points[0].x+=.1}}
        normal{Tile $bad 2 {param($p)$p.points[0].nz=0}}
        height-step{Tile $bad 2 {param($p)$p.points[8].z+=1}}
        first-overlap{Tile $bad 1 {param($p)$p.points[0].z+=.0002}}
        second-overlap{Tile $bad 2 {param($p)$p.points[0].z+=.0002}}
        nonadjacent-overlap{Tile $bad 1 {param($p)$p.points[4].z+=.000075};Tile $bad 2 {param($p)$p.points[0].z+=.00015}}
        bad-number{Tile $bad 2 {param($p)$p.spacing='1'}}
    }
    Save $bad;Reject {Read-HudGroundExtensionInput $path $root $false} "Reject extension mutation $change"
}
$json=ConvertTo-Json -InputObject $manifest -Depth 10 -Compress
('{"schema":2,'+$json.Substring(1)) | Set-Content -LiteralPath $path -Encoding utf8NoBOM
Reject {Read-HudGroundExtensionInput $path $root $false} 'Duplicate outer keys rejected before conversion'
$bad=Clone $manifest;$bad.tiles[2].json='{"schema":2,'+$bad.tiles[2].json.Substring(1)
$bad.tiles[2].sha256=Get-HudExtensionHash ([Text.Encoding]::UTF8.GetBytes($bad.tiles[2].json));Save $bad
Reject {Read-HudGroundExtensionInput $path $root $false} 'Duplicate embedded keys rejected even with a matching hash'
[IO.File]::WriteAllBytes($path,[byte[]]::new(288KB+1))
Reject {Read-HudGroundExtensionInput $path $root $false} 'Extension input bound enforced'
# Leave one valid bounded fixture artifact for reproducibility.
Save $manifest
Write-Output "HUD_GROUND_EXTENSION_TESTS_PASS checks=$script:checks no_game_started=true"
