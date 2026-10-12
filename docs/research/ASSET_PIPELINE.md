# Official KCD2 asset compiler proof

Verified locally on 2026-10-11 with the installed official KCD2 Modding Tools (Steam app 2429020, installed game executable version 1.5.5.0). Compiler success proves conversion only. The user's later screenshot and matching logs separately verify a visible Minecraft stone block in the live KCD2 world. A second user screenshot and explicit confirmation verify the sharper revision below. Depth, collision and full camera calibration remain separate checks.

## Actual inputs and output

The running Fabric Minecraft 1.21.1 client exported its vanilla stone `BakedModel` quads and the stitched GPU block atlas into the ignored `minecraft/run/minecome-export/stone` directory. Source OBJ: 24 vertices, six quads, 12 triangles, one `minecraft_atlas` material. Actual atlas: 1024 × 512 pixels. The exporter reads the installed game assets; no Minecraft asset files are checked in.

`tools/Convert-BlockAsset.ps1` discovers the official Resource Compiler through the read-only Steam inventory and calls the original Python converter. Python 3.10+ and Pillow must already exist; an explicit `-PythonPath` can select them. No installers, deployment, or game process launches are performed. Generated output is restricted to a subdirectory of this project's ignored `runtime/` or `build/` directory.

```powershell
.\tools\Convert-BlockAsset.ps1 -PythonPath <existing-python.exe>
```

Original successful output, before the sharpness revision, below `runtime/compiled-block/Data/objects/minecome`:

| File | Actual size | Purpose |
| --- | ---: | --- |
| `stone.cgf` | 2356 bytes | PC-compiled native static mesh |
| `stone.mtl` | 435 bytes | Original CryEngine XML material, stock `Illum` shader |
| `block-atlas.dds` | 2097288 bytes | Original Minecraft atlas RGB, uncompressed DDS |

The generated material uses the atlas as its diffuse texture, zero specular, and one submaterial matching the original model. It contains no collision proxy or custom shader. The runtime render therefore uses KCD2's lighting and filtering, even though geometry and texture originate in Minecraft.

## Original compiler pipeline

The shipped `Tools/rc/rc.exe` loads `ResourceCompilerFBX.dll`, `ResourceCompilerPC.dll`, and `ResourceCompilerImage.dll`. These are installed Warhorse/CryEngine tools, separate from the MineCome sources. The tested RC executable SHA-256 is recorded in the installation-specific `runtime/compiled-block/provenance.json`, alongside all source/output hashes and arguments.

1. Parse exported OBJ vertices and UV indices. Convert Minecraft `(x,y,z)` to KCD2 `(x,-z,y)`; one block becomes one meter. Compute per-face normals from the actual exported winding.
2. Write original ASCII FBX 7.4 geometry, normals, material indices and UVs. Declare right-handed `-Y+Z` axes and meter units. Retain OBJ/FBX bottom-left V coordinates. No artist application, Autodesk SDK install, or third-party mesh library is required.
3. Write an XML import request:

```xml
<asset assettype="static_mesh" filetype="fbx" filename="stone.fbx"
       sourceunitsize="meters" scale="1" origin="/world" />
```

4. Run RC from the generated import directory, with the request filename and `/overwriteextension=fbx /setmtl=objects/minecome/stone /p=pc /refresh /userdialog=0 /wait=0 /logprefix=<project-log-prefix>`. Actual exit code: **0**. Its log reports meter units and `-Y+Z` to `-Y+Z`. Output `stone.import.cgf`: 2428 bytes. This FBX converter places the file beside the request; `/targetroot` does not relocate that initial output in this version.
5. Run the regular PC CGF converter on `stone.import.cgf`, with `/targetroot=<generated-asset-directory>` and the same explicit material path/platform/log options. Actual exit code: **0**. Its output is 2356 bytes, renamed to `stone.cgf`. This separate step produces the PC runtime mesh.
6. Convert the exported PNG to a plain RGB TIFF with Pillow. Run RC with `/preset=Albedo /pixelformat=X8R8G8B8 /mipmaps=0 /reduce=0 /streaming=0` plus the common platform/refresh/dialog/log options. Actual exit code: **0**. The compiler's `Albedo` preset is present in its installed `rc.ini`. Compare every DDS RGB pixel with the original PNG: **identical**. The atlas has opaque stone pixels; alpha for unrelated atlas sprites is not preserved in this scoped stone proof.
7. Write the original material XML and compilation provenance. `live_draw_verified` remains `false`; asset compilation cannot set that field to true.

Directly passing OBJ/FBX as an RC input is insufficient: this particular FBX converter expects the XML import request, indicated by its actual diagnostic `Asset converter: failed to load asset xml file`. The Autodesk ASCII parser also requires each field after braces on a new line; terse one-line compound fields produced an empty scene until corrected. A `.cryasset` editor metadata file was not required for these direct compiler invocations. The final native load/material path remains a separate engine-side test.

The native CGF contains the top-left UV pair `(0.328155518, 0.874938965)` while the matching source OBJ/FBX pair is `(0.328155518, 0.125061035)`. This verifies the actual RC's V conversion. Its generated CGF uses position values of one meter; RC's optional OBJ export multiplies positions by 100 for its centimeter-oriented export convention.

RC defaults its logs to its own installed executable directory, even when the working directory is elsewhere. The first `/help` inspection created a tool log there; it did not change engine/game data. All subsequent compiler invocations specify `/logprefix` inside the project. The reusable converter always sets this option and waits for the real subprocess exit code; invoking this GUI subsystem executable from PowerShell with `&` alone can return before completion.

## Engine-side handoff

The output directory can be staged as the original MineCome mod's own `Data/objects/minecome` namespace. The Lua engine adapter can load `objects/minecome/stone.cgf` into slot zero of an explicitly spawned static entity using the shipped `LoadObject` binding. Live `GetLocalBBox`/`GetWorldBBox`, the game log, and visual inspection are needed to verify the one-meter dimensions, correct stone tile, placement, scene depth and eventual collision. Compilation by itself does not establish any of those outcomes. No save files are read or written by this converter.

## Texture sharpness revision (current converter)

The initial full-atlas material did not request point filtering. The inspected
libKCD2 `CryEngine/CryCommon/IRenderer.h` defines `FILTER_POINT=0`, and the
[Crytek-derived material reader](https://github.com/aws/lumberyard/blob/master/dev/Code/CryEngine/Cry3DEngine/MaterialHelpers.cpp#L448-L452)
reads the Texture `Filter` integer directly. However, official
[Material Editor documentation](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756816/pages/35259544)
marks this option deprecated. Read-only inspection of the installed KCD2
`Engine/Shaders.pak` found `Illum.cfx:690` → `textureLib.cfi:121/173` →
`FXSamplerDefs.cfi:39`, using shared `ssMaterialAnisoHigh`/`SS_MaterialAnisoHighWrap`.
Consequently, the XML point-filter hint alone is not evidence of an actual point
sampler in this stock shader. No engine shader or global graphics option was changed.

The current converter also isolates the real stone sprite using every source face's
UV bounds. All six faces must reference the same power-of-two sprite; incompatible
geometry is rejected. This export identifies PNG crop `(336,432,352,448)` in the
1024×512 atlas: exactly 16×16 pixels. Original OBJ UVs are remapped with
`u'=(u×1024−336)/16`, `v'=(v×512−64)/16`, retaining face orientation and the
existing UV shrink insets. RC still performs its normal V conversion.

Each source pixel is repeated 32×32 with nearest-neighbour scaling, producing a
512×512 texture without adding or blending colours. This narrows ordinary smooth
magnification transitions to about 1/32 of a Minecraft pixel. It approximates crisp
sampling; it does not replace the sampler. Far/grazing views can still average
colours and the existing no-mip proof may shimmer in the distance. Post-processing
can also soften pixel edges; its enabled state was not established by the screenshot.

The texture filename remains `block-atlas.dds` for compatibility with the existing
package, but its current contents are the isolated, repeated stone sprite. RC
still uses uncompressed RGB and no reduction/mips/streaming. The current outputs
are `stone.cgf` 2356 bytes, `stone.mtl` 470 bytes and DDS 1,048,712 bytes.
Material XML includes `Filter="0"`, `IsTileU="0"`, `IsTileV="0"`.
All three official compiler steps returned zero. Artifact verification compared
all 262,144 compiled pixels with the corresponding original sprite pixels and all
24 UV corners with their original colours. Provenance now records atlas/crop,
replication factor, raw sprite/expanded pixel hashes and output hashes. Its DDS
comparison is against the prepared sprite, not the entire original atlas.
The original blurred material's provenance and deployment were frozen beside the
user's screenshot under `runtime/evidence/live-world-20261011`.

The owned package was updated after its prior hashes matched the deployment record
and KCD2 had closed. The previous package was backed up. The user's second live
screenshot now verifies crisp pixel edges on the front and side faces. The unchanged
installed package hash and frozen provenance are recorded under
`runtime/evidence/sharp-stone-20261011`. This verifies the asset-level result in
that view, not the exact GPU sampler state or distance/occlusion behavior. The
compiler's false live-draw field stays separate from the human verification record.

## Primary references

- [CryEngine Resource Compiler](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756816/pages/44959586): compiler workflow, TIFF/texture conversion, presets, platform/options. The installed RC's `/help` and `rc.ini` are the authority for version-specific options used here.
- [CryEngine asset importers](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756813/pages/26873126): FBX import delegated to RC and image conversion through TIFF. The same documentation explains editor metadata and temporary import directories.
- [CryEngine FBX import tools](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756816/pages/44966294) and [FBX export/import workflow](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756816/pages/25529353): supported formats, import settings, units, UVs and material association. These docs describe broader editor versions; local compiler success above is the direct evidence for this installed build.
- [Autodesk FBX technology](https://help.autodesk.com/cloudhelp/2020/ENU/FBX-Developer-Help/files/welcome_to_the_fbx_sdk/FBX_Developer_Help_welcome_to_the_fbx_sdk_what_is_autodesk_fbx_technology_html.html): ASCII FBX structure and header. The converter code is original, and does not incorporate an Autodesk library.
- [CryEngine material relative paths](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756816/pages/29799264): XML `Material`/`Texture` format and material/texture references. Shipped official KCD2 templates were inspected for the actual stock `Illum` and multi-material flags; their textures/geometry were not copied.

Compiler binaries and locally extracted Minecraft assets retain their vendors' licensing. The repository contains original conversion code, instructions, and provenance tooling; generated game assets remain local and ignored.
