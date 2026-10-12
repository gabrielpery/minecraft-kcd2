# Local discovery and asset tools

These tools inspect or compile local files. They do not install dependencies, copy assets into a game installation, launch a game, or change saves. Generated assets and installation-specific JSON belong under the ignored `runtime/` or `build/` directories.

## Windows inventory

```powershell
.\tools\Discover-Environment.ps1 -OutputPath .\runtime\environment.json -IncludeHashes
```

Discovers Visual Studio with `vswhere`, bundled CMake/Ninja/compiler, Windows SDK, Steam library manifests and installed KCD2/tools binaries, JDKs (including launcher runtimes), public Minecraft version files/mod filenames, and save directory names. It does not inspect launcher account/profile files, credentials, or save contents. `-AsObject` returns the inventory to PowerShell; `-AdditionalMinecraftRoots` supports another launcher directory. Without `-OutputPath`, discovery writes no files. Absolute paths in the snapshot are specific to this machine and are excluded from version control.

The native configure/build/test wrapper is `scripts/Build-Native.ps1`. It prefers a discovered VS 2022 x64 installation and its bundled CMake. `-Kcse Auto` enables the adapter if `external/libKCD2/include/KCSE/KCSEAPI.h` exists; otherwise it builds core targets. It performs no loader deployment. Local validation used VS 2022 17.14.37314.3, MSVC 19.44.35227, CMake 3.31.6 and Windows SDK 10.0.28000.0; both CTest checks passed in a separate build directory.

## Actual Minecraft stone conversion

First export the stone model/atlas from the running MineCome Fabric client using `/minecome export-stone`. Then select an **existing** Python 3.10+ interpreter with Pillow and run:

```powershell
.\tools\Convert-BlockAsset.ps1 -PythonPath <existing-python.exe>
```

The wrapper discovers the official KCD2 Modding Tools RC from Steam libraries. Override with `-ResourceCompiler <rc.exe>` if needed. `-SourceDirectory` defaults to `minecraft/run/minecome-export/stone`; `-OutputDirectory` defaults to `runtime/compiled-block`. Output is restricted to a subdirectory of this project's `runtime/` or `build/` directory. OBJ input is limited to 4 MiB; atlas files and decoded RGBA are limited to 128 MiB. This converter supports the exported single-material opaque stone model, not arbitrary Minecraft assets.

Actual validation used the already available Python **3.12.14**, Pillow **12.3.0**, PowerShell **7.6.5**, and official KCD2 Tools **1.5.5.0** (Steam app 2429020). No additional dependency was installed. The Python script uses only its standard library plus Pillow; artist applications and an Autodesk SDK installation are not required.

The compiler produces `Data/objects/minecome/stone.cgf`, `stone.mtl`, and `block-atlas.dds`. Actual FBX import, PC CGF compilation, and TIFF-to-DDS conversion all returned RC exit code zero. Every DDS RGB pixel matched the exported Minecraft PNG. `provenance.json` records source/compiler/output hashes and arguments, and explicitly states `live_draw_verified: false`. Loading, displaying, native scene depth, and collision must be verified separately in KCD2. See [the compiler proof](../docs/research/ASSET_PIPELINE.md) for the exact schema and measured outputs.

The OBJ/PNG and resulting CGF/DDS contain Minecraft-derived game assets. Keep them user-local and out of commits/releases; their vendor ownership remains unchanged. This repository contains the original conversion code and documentation. The mod's Lua/material definitions are original, and the official compiler binaries are neither copied nor redistributed.
