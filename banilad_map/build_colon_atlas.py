"""Optimized ('atlas') build of the Colon slice: ONE material per building.

    blender --background --python build_colon_atlas.py

Proves the draw-call fix. The pretty build (build_colon_slice.py) splits each
building into ~16 materials -> ~16 draw calls/instance -> 832 for 49 blocks ->
19 fps on the Intel HD 5500. Here every element is re-emitted into a SINGLE
material whose textures live in a Texture2DArray (one layer per material). Per
face we bake:

  * UV     - box-projected world coords x per-layer tile scale, so each layer
             tiles correctly via the array's repeat wrap (no triplanar, no atlas
             bleed -- the tiling problem that a single flat atlas can't solve).
  * COLOR  - rgb = the per-bay paint tint; ALPHA = the layer index / 255,
             decoded in the shader. (Packed into vertex colour so it survives
             the glTF round-trip without a second UV set.)

Result: one surface per building -> ~1 draw call/instance. Geometry is identical
to the pretty build; only the material structure changes. Exports
atlas_slice.glb + atlas_manifest.json (the ordered layer table) to local temp.
"""

import json
import pathlib
import sys

import bpy

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import build_colon_slice as base  # main() is guarded, so this only imports helpers

OUT = base.OUT
CC0 = base.CC0
TEX = base.TEX

# slot name -> array layer
LAYER = {
    "Plaster_Warm": 0, "Plaster_Blue": 0, "Plaster_Ochre": 0, "Plaster_Green": 0,
    "Concrete_Grey": 1, "Concrete_Side": 1,
    "Shutter_Steel": 2,
    "Awning_Steel": 3, "Awning_Canvas": 3, "Roof_Tank": 3,
    "Asphalt": 4,
    "Signage": 5,
    "Window": 6, "Metro_Reveal": 7, "Pole": 8, "Tower_Plant": 9,
    "Marking_Yellow": 10,
}
# tiles-per-metre baked into UV, per layer
TILE = {0: 0.34, 1: 0.34, 2: 0.5, 3: 0.55, 4: 0.2, 5: 0.16,
        6: 0.3, 7: 0.3, 8: 0.5, 9: 0.3, 10: 0.3}
# layer -> CC0 short name (None = solid white, colour comes from vertex tint)
LAYER_TEX = {0: "plaster", 1: "concrete", 2: "shutter", 3: "galv", 4: "asphalt",
             5: "signage"}
N_LAYERS = 11


def tint_of(name):
    d = base.MANIFEST_MATERIALS.get(name, {})
    if "tint" in d:
        return d["tint"]
    if "solid" in d:
        return d["solid"]
    return [1.0, 1.0, 1.0]


def face_axis(vs):
    a, b, c = vs[0], vs[1], vs[2]
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx = abs(uy * vz - uz * vy)
    ny = abs(uz * vx - ux * vz)
    nz = abs(ux * vy - uy * vx)
    if nx >= ny and nx >= nz:
        return 0
    if ny >= nz:
        return 1
    return 2


def box_uv(p, axis, tile):
    if axis == 0:
        return (p[2] * tile, p[1] * tile)
    if axis == 1:
        return (p[0] * tile, p[2] * tile)
    return (p[0] * tile, p[1] * tile)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    base.tex_signage()

    mats = base.Ident()
    batch = base.UVBatch()
    run = base.build_colon(batch, mats)

    verts, faces, uvs, cols = [], [], [], []
    for face, slot in zip(batch.faces, batch.face_slots):
        name = batch.slots[slot]
        layer = LAYER.get(name, 6)
        tile = TILE[layer]
        tint = tint_of(name)
        vs = [batch.verts[i] for i in face]
        axis = face_axis(vs)
        idx0 = len(verts)
        for p in vs:
            verts.append(p)
            uvs.append(box_uv(p, axis, tile))
            cols.append((tint[0], tint[1], tint[2], layer / 255.0))
        faces.append(tuple(range(idx0, idx0 + len(vs))))

    mesh = bpy.data.meshes.new("ColonAtlas")
    mesh.from_pydata(verts, [], faces)
    mesh.validate(verbose=False)
    mesh.materials.append(bpy.data.materials.get("Atlas") or bpy.data.materials.new("Atlas"))
    uvl = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uvl.data[loop.index].uv = uvs[loop.vertex_index]
    col = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    for i, c in enumerate(cols):
        col.data[i].color = c
    mesh.color_attributes.active_color = col
    mesh.color_attributes.render_color_index = 0
    for p in mesh.polygons:
        p.use_smooth = False
    mesh.update()
    obj = bpy.data.objects.new("ColonAtlas", mesh)
    bpy.context.scene.collection.objects.link(obj)

    glb = OUT / "atlas_slice.glb"
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB",
                              use_selection=False, export_apply=True,
                              export_yup=True, export_vertex_color="ACTIVE",
                              export_attributes=True)

    layers = []
    for i in range(N_LAYERS):
        short = LAYER_TEX.get(i)
        if short == "signage":
            layers.append({"albedo": str(TEX / "signage.png")})
        elif short:
            layers.append({"albedo": str(CC0 / (short + "_alb.jpg")),
                           "normal": str(CC0 / (short + "_nrm.jpg")),
                           "rough": str(CC0 / (short + "_rgh.jpg"))})
        else:
            layers.append({"solid": True})
    (OUT / "atlas_manifest.json").write_text(json.dumps(
        {"glb": str(glb), "run": run, "layers": layers}, indent=2))

    tris = sum(len(f) - 2 for f in faces)
    print("[atlas] verts={} tris={} -> ONE material".format(len(verts), tris))
    print("[atlas] glb ->", glb)
    print("[atlas] DONE")


main()
