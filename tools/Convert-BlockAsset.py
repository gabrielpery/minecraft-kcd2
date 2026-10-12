"""Compile a user-local Minecraft OBJ/atlas with the installed official KCD2 RC.

Requires Python 3.10+ and Pillow; does not install anything or deploy to a game.
FBX/XML syntax is original project code verified with the shipped RC 1.5.5.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops


def read_obj(path: Path):
    if path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError("Block OBJ exceeds the 4 MiB limit")
    vertices, uvs, faces = [], [], []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        fields = line.split()
        if not fields or fields[0].startswith("#"):
            continue
        if fields[0] == "v":
            if len(fields) != 4:
                raise ValueError("Expected three OBJ position components")
            x, y, z = map(float, fields[1:])
            if not all(math.isfinite(t) and abs(t) <= 16 for t in (x, y, z)):
                raise ValueError("Invalid block vertex")
            # The same right-handed basis as the bridge: MC +Y up -> KCD +Z up.
            vertices.append((x, -z, y))
        elif fields[0] == "vt":
            u, v = map(float, fields[1:3])
            if not all(math.isfinite(t) and 0 <= t <= 1 for t in (u, v)):
                raise ValueError("Invalid atlas UV")
            # OBJ and FBX use bottom-left V. The official RC imports this convention.
            uvs.append((u, v))
        elif fields[0] == "f":
            if len(fields) not in (4, 5):
                raise ValueError("Only triangle/quad block faces are supported")
            face = []
            for field in fields[1:]:
                indices = field.split("/")
                if len(indices) < 2 or not indices[1]:
                    raise ValueError("Every OBJ vertex requires an atlas UV")
                vi, ui = int(indices[0]) - 1, int(indices[1]) - 1
                if not (0 <= vi < len(vertices) and 0 <= ui < len(uvs)):
                    raise ValueError("Invalid OBJ face index")
                face.append((vi, ui))
            faces.append(face)
        elif fields[0] == "usemtl" and fields[1:] != ["minecraft_atlas"]:
            raise ValueError("Only the exported minecraft_atlas material is supported")
    if not vertices or not faces or len(vertices) > 65536 or len(faces) > 16384:
        raise ValueError("Missing or excessive block geometry")
    return vertices, uvs, faces


def write_fbx(path: Path, vertices, uvs, faces):
    indices, uvlist, normals = [], [], []
    for face in faces:
        a, b, c = [vertices[t[0]] for t in face[:3]]
        e1 = [b[i] - a[i] for i in range(3)]
        e2 = [c[i] - a[i] for i in range(3)]
        normal = [e1[1]*e2[2]-e1[2]*e2[1], e1[2]*e2[0]-e1[0]*e2[2], e1[0]*e2[1]-e1[1]*e2[0]]
        length = math.sqrt(sum(t*t for t in normal))
        if length < 1e-12:
            raise ValueError("Degenerate block face")
        normal = [t / length for t in normal]
        for i, (vi, ui) in enumerate(face):
            indices.append(vi if i < len(face)-1 else -vi-1)
            uvlist.extend(uvs[ui])
            normals.extend(normal)
    text = '''; FBX 7.4.0 project file
; Original MineCome conversion of locally exported Minecraft geometry
FBXHeaderExtension: { FBXHeaderVersion: 1003
 FBXVersion: 7400
 Creator: "MineCome"
}
GlobalSettings: { Version: 1000
 Properties70: {
 P: "UpAxis", "int", "Integer", "",2
 P: "UpAxisSign", "int", "Integer", "",1
 P: "FrontAxis", "int", "Integer", "",1
 P: "FrontAxisSign", "int", "Integer", "",-1
 P: "CoordAxis", "int", "Integer", "",0
 P: "CoordAxisSign", "int", "Integer", "",1
 P: "UnitScaleFactor", "double", "Number", "",100
 P: "OriginalUnitScaleFactor", "double", "Number", "",100
 }
}
Documents: { Count: 1
 Document: 1, "", "Scene" { RootNode: 0 }
}
Definitions: { Version: 100
 Count: 3
 ObjectType: "Geometry" { Count: 1 }
 ObjectType: "Model" { Count: 1 }
 ObjectType: "Material" { Count: 1 }
}
Objects: {
 Geometry: 100, "Geometry::MinecraftBlock", "Mesh" {
 GeometryVersion: 124
 Vertices: *VERTCOUNT { a: VERTS }
 PolygonVertexIndex: *INDEXCOUNT { a: INDICES }
 LayerElementNormal: 0 { Version: 101
 Name: ""
 MappingInformationType: "ByPolygonVertex"
 ReferenceInformationType: "Direct"
 Normals: *NORMALCOUNT { a: NORMALS }
 }
 LayerElementUV: 0 { Version: 101
 Name: "minecraft_atlas"
 MappingInformationType: "ByPolygonVertex"
 ReferenceInformationType: "Direct"
 UV: *UVCOUNT { a: UVS }
 }
 LayerElementMaterial: 0 { Version: 101
 Name: ""
 MappingInformationType: "AllSame"
 ReferenceInformationType: "IndexToDirect"
 Materials: *1 { a: 0 }
 }
 Layer: 0 { Version: 100
 LayerElement: { Type: "LayerElementNormal"
 TypedIndex: 0 }
 LayerElement: { Type: "LayerElementUV"
 TypedIndex: 0 }
 LayerElement: { Type: "LayerElementMaterial"
 TypedIndex: 0 }
 }
 }
 Model: 200, "Model::MinecraftBlock", "Mesh" {
 Version: 232
 Properties70: {
 P: "Lcl Translation", "Lcl Translation", "", "A",0,0,0
 P: "Lcl Rotation", "Lcl Rotation", "", "A",0,0,0
 P: "Lcl Scaling", "Lcl Scaling", "", "A",1,1,1
 }
 Shading: T
 Culling: "CullingOff"
 }
 Material: 300, "Material::minecraft_atlas", "" {
 Version: 102
 ShadingModel: "phong"
 MultiLayer: 0
 Properties70: { P: "DiffuseColor", "Color", "", "A",1,1,1 }
 }
}
Connections: {
 C: "OO",100,200
 C: "OO",200,0
 C: "OO",300,200
}
'''
    def array(values):
        return ",".join(f"{i:.9g}" for i in values)
    values = {"VERTCOUNT": str(len(vertices)*3), "VERTS": array(t for v in vertices for t in v),
              "INDEXCOUNT": str(len(indices)), "INDICES": array(indices),
              "NORMALCOUNT": str(len(normals)), "NORMALS": array(normals),
              "UVCOUNT": str(len(uvlist)), "UVS": array(uvlist)}
    for key, value in values.items():
        text = text.replace(key, value)
    # Autodesk's ASCII reader requires the fields after braces on separate lines.
    text = text.replace("{ ", "{\n ").replace(" }", "\n }")
    path.write_text(text, encoding="ascii")


def compile_rc(rc: Path, work: Path, logs: Path, label: str, arguments: list[str]):
    command = [str(rc), *arguments, "/p=pc", "/refresh", "/userdialog=0", "/wait=0",
               f"/logprefix={logs / (label + '-')}" ]
    flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    result = subprocess.run(command, cwd=work, capture_output=True, text=True, errors="replace",
                            timeout=90, creationflags=flags)
    (logs / (label + "-console.txt")).write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Official RC {label} failed ({result.returncode}); see {logs}")
    return {"step": label, "exit_code": result.returncode, "arguments": command[1:]}


def sha256(path: Path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare_stone_texture(atlas: Image.Image, uvs, faces):
    """Isolate the actual sprite, remap its UVs and repeat pixels without blending.

    Stock KCD2 Illum uses a global smooth sampler, so an XML point-filter hint alone
    is insufficient. Repeating each 16x16 sprite pixel 32x32 times in a 512x512
    texture narrows its bilinear transition without changing the source colours.
    This scoped converter requires every stone face to use the same whole sprite.
    """
    boxes = []
    for face in faces:
        coordinates = [uvs[ui] for _, ui in face]
        left = math.floor(min(u for u, _ in coordinates) * atlas.width)
        right = math.ceil(max(u for u, _ in coordinates) * atlas.width)
        top = math.floor((1 - max(v for _, v in coordinates)) * atlas.height)
        bottom = math.ceil((1 - min(v for _, v in coordinates)) * atlas.height)
        boxes.append((left, top, right, bottom))
    if len(set(boxes)) != 1:
        raise ValueError("Stone faces must reference the same complete atlas sprite")
    left, top, right, bottom = boxes[0]
    width, height = right - left, bottom - top
    if not (0 <= left < right <= atlas.width and 0 <= top < bottom <= atlas.height):
        raise ValueError("Stone sprite is outside the source atlas")
    if any(n < 4 or n > 256 or n & (n - 1) for n in (width, height)):
        raise ValueError("Stone sprite must have power-of-two dimensions from 4 to 256")
    remapped = [(0.0, 0.0)] * len(uvs)
    for _, ui in (item for face in faces for item in face):
        u, v = uvs[ui]
        remapped[ui] = ((u * atlas.width - left) / width,
                        (v * atlas.height - (atlas.height - bottom)) / height)
        if not all(0 <= t <= 1 for t in remapped[ui]):
            raise ValueError("Remapped stone UV is outside its sprite")
    sprite = atlas.crop((left, top, right, bottom))
    repeat = 512 // max(width, height)
    prepared = sprite.resize((width * repeat, height * repeat), Image.Resampling.NEAREST)
    pixel_exact = ImageChops.difference(sprite, prepared.resize(sprite.size, Image.Resampling.NEAREST)).getbbox() is None
    if not pixel_exact:
        raise RuntimeError("Nearest-neighbour conversion changed original stone pixels")
    return prepared, remapped, {"atlas_crop_top_left": [left, top, right, bottom],
                               "source_sprite_dimensions": list(sprite.size),
                               "prepared_dimensions": list(prepared.size),
                               "nearest_repeat_factor": repeat,
                               "source_sprite_rgb_sha256": hashlib.sha256(sprite.tobytes()).hexdigest(),
                               "prepared_rgb_sha256": hashlib.sha256(prepared.tobytes()).hexdigest(),
                               "source_sprite_pixel_exact": pixel_exact}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rc", type=Path, required=True)
    args = parser.parse_args()
    source, output, rc = args.source.resolve(), args.output.resolve(), args.rc.resolve()
    project = Path(__file__).resolve().parents[1]
    # Keep generated game assets in ignored project runtime/build, never a game install.
    if not any(output.is_relative_to(project / folder) and output != project / folder for folder in ("runtime", "build")):
        raise ValueError("Output must be a subdirectory of this project's runtime/ or build/")
    if source.is_relative_to(output) or output.is_relative_to(source):
        raise ValueError("Source and output directories must be separate")
    if not rc.is_file():
        raise FileNotFoundError("Official RC executable was not found")
    obj, atlas = source / "stone.obj", source / "block-atlas.png"
    if atlas.stat().st_size > 128 * 1024 * 1024:
        raise ValueError("Atlas file exceeds the 128 MiB limit")
    vertices, uvs, faces = read_obj(obj)
    work, logs = output / "import", output / "logs"
    assets = output / "Data" / "objects" / "minecome"
    for folder in (work, logs, assets):
        folder.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(ET.Element("asset", assettype="static_mesh", filetype="fbx", filename="stone.fbx",
                              sourceunitsize="meters", scale="1", origin="/world")).write(work / "stone.import.xml", encoding="utf-8", xml_declaration=True)
    with Image.open(atlas) as image:
        if max(image.size) > 16384 or any(n <= 0 or n & (n-1) for n in image.size):
            raise ValueError("Atlas must have power-of-two dimensions, at most 16384")
        if image.width * image.height * 4 > 128 * 1024 * 1024:
            raise ValueError("Decoded atlas exceeds the 128 MiB RGBA limit")
        original_rgb = image.convert("RGB")
        prepared_rgb, remapped_uvs, sprite_info = prepare_stone_texture(original_rgb, uvs, faces)
        prepared_rgb.save(work / "block-atlas.tif", compression="raw")
    write_fbx(work / "stone.fbx", vertices, remapped_uvs, faces)
    material_path = "objects/minecome/stone"
    steps = [compile_rc(rc, work, logs, "fbx", ["stone.import.xml", "/overwriteextension=fbx", f"/setmtl={material_path}"])]
    if not (work / "stone.import.cgf").is_file():
        raise RuntimeError("RC returned success without creating the FBX source CGF")
    steps.append(compile_rc(rc, work, logs, "cgf", ["stone.import.cgf", f"/setmtl={material_path}", f"/targetroot={assets}"]))
    shutil.move(str(assets / "stone.import.cgf"), str(assets / "stone.cgf"))
    steps.append(compile_rc(rc, work, logs, "texture", ["block-atlas.tif", "/preset=Albedo", "/pixelformat=X8R8G8B8",
                                                       "/mipmaps=0", "/reduce=0", "/streaming=0"]))
    dds = work / "block-atlas.dds"
    with Image.open(dds) as compiled:
        rgb_exact = compiled.size == prepared_rgb.size and ImageChops.difference(prepared_rgb, compiled.convert("RGB")).getbbox() is None
    if not rgb_exact:
        raise RuntimeError("Compiled DDS RGB differs from the pixel-preserving stone texture")
    shutil.copyfile(dds, assets / dds.name)
    root = ET.Element("Material", MtlFlags="524544", vertModifType="0")
    sub = ET.SubElement(ET.SubElement(root, "SubMaterials"), "Material", Name="minecraft_atlas", MtlFlags="524416",
                        Shader="Illum", GenMask="0", StringGenMask="", Diffuse="1,1,1", Specular="0,0,0",
                        Shininess="0", Opacity="1", SurfaceType="mat_stone", vertModifType="0")
    # CryEngine FILTER_POINT=0 (inspected IRenderer.h). MaterialHelpers reads the
    # Texture Filter attribute directly. Preserve Minecraft's crisp texel edges
    # instead of leaving this low-resolution sprite to the default smooth sampler.
    ET.SubElement(ET.SubElement(sub, "Textures"), "Texture", Map="Diffuse",
                  File="objects/minecome/block-atlas.dds", Filter="0", IsTileU="0", IsTileV="0")
    ET.SubElement(sub, "PublicParams")
    ET.ElementTree(root).write(assets / "stone.mtl", encoding="utf-8", xml_declaration=True)
    provenance = {"schema": 1, "created_utc": datetime.now(timezone.utc).isoformat(), "stage": "asset_compilation",
                  "live_draw_verified": False, "source": {str(p): sha256(p) for p in (obj, atlas)},
                  "compiler": {"path": str(rc), "sha256": sha256(rc)}, "vertices": len(vertices), "faces": len(faces),
                  "triangles": sum(len(f)-2 for f in faces), "coordinate_conversion": "(x,y,z) -> (x,-z,y); one unit = one meter",
                  "uv_convention": "OBJ bottom-left remapped from atlas to isolated sprite; official RC converts to runtime",
                  "atlas_dimensions": original_rgb.size, "dds_rgb_exact": rgb_exact,
                  "dds_rgb_comparison": "Prepared nearest-neighbour stone sprite, not the entire source atlas",
                  "stone_texture": sprite_info,
                  "texture_options": "Isolated stone sprite, nearest-neighbour pixel repetition; uncompressed RGB, no reduction/mips/streaming",
                  "material_texture_filter": {"xml_attribute": "Filter", "value": 0, "mode": "point",
                                              "stock_illum_sampler_may_override": True,
                                              "live_sharpness_verified": False},
                  "source_license": "Minecraft/Mojang game assets; user-local generated output, do not redistribute with this repository",
                  "compiler_license": "Installed official Warhorse/CryEngine tools; binaries are not redistributed",
                  "physics_proxy": False, "steps": steps,
                  "outputs": {str(p.relative_to(output)): {"sha256": sha256(p), "bytes": p.stat().st_size}
                              for p in (assets / "stone.cgf", assets / "stone.mtl", assets / "block-atlas.dds")}}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"compiled_asset": str(assets / "stone.cgf"), "provenance": str(output / "provenance.json"),
                      "dds_rgb_exact": rgb_exact, "live_draw_verified": False}))


if __name__ == "__main__":
    main()
