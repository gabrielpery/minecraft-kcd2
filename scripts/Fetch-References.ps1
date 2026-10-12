$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$references = @(
    @{Name='libKCD2'; Url='https://github.com/JerryYOJ/libKCD2.git'; Commit='10d20f28faba462c4bf98a01abb48225cc51bb91'},
    @{Name='KCSE-for-kcd2'; Url='https://github.com/JerryYOJ/KCSE-for-kcd2.git'; Commit='47ff1bd75c4df4a3a2145e7ba9908d5b2e7f7aec'},
    @{Name='SkyCraft'; Url='https://github.com/chasmlol/SkyCraft.git'; Commit='bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32'},
    @{Name='EldenCraft'; Url='https://github.com/SocketByte/EldenCraft.git'; Commit='ba7591cdde9fb16e17552cfe53546f44d0fd856e'},
    @{Name='reshade'; Url='https://github.com/crosire/reshade.git'; Commit='18deaa52de0c425a78b329e9cb3c497281cd00ec'},
    @{Name='universal-modder'; Url='https://github.com/rehan-remade/universal-modder.git'; Commit='2c2201437ca676fb4e5f06a18fff6e8db99eef0f'},
    @{Name='kcd2-mod-docs'; Url='https://github.com/muyuanjin/kcd2-mod-docs.git'; Commit='9cb067543245ec5cf4e27b3d21e32485a35db518'}
)
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'external') | Out-Null
foreach ($reference in $references) {
    $destination = Join-Path $projectRoot ('external/' + $reference.Name)
    if (-not (Test-Path -LiteralPath $destination)) {
        & git clone --no-checkout $reference.Url $destination
        if ($LASTEXITCODE -ne 0) { throw "Clone failed: $($reference.Name)" }
        & git -C $destination checkout --detach $reference.Commit
        if ($LASTEXITCODE -ne 0) { throw "Pinned checkout failed: $($reference.Name)" }
    }
    $revision = & git -C $destination rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $revision.Trim() -ne $reference.Commit) { throw "Preserving mismatched reference: $destination" }
    Write-Output "$($reference.Name) pinned to $($reference.Commit)"
}
Write-Output 'Reference material only. Do not package external trees, assets, SDK/game binaries or authentication data.'
