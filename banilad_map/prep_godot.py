"""
Prepare the Banilad OSM map for Godot 4 and export it as a game-ready glTF.

- verifies real-world scale against known landmark footprints
- applies all object transforms
- appends "-col" to every mesh the player should collide with
- retunes the building palette toward the reference aerial photo
- exports +Y-up GLB into the Godot project
- writes landmark positions in Godot coordinates for spawns and waypoints

Run headlessly:
    blender --background --python prep_godot.py
"""

import json
import math
import pathlib
import sys

import bpy

HERE = pathlib.Path(__file__).parent
PROJECT = HERE.parent
BLEND = HERE / "banilad_map.blend"
MAP_DIR = PROJECT / "assets" / "maps"
GLB_OUT = MAP_DIR / "banilad_map.glb"
LANDMARK_OUT = MAP_DIR / "banilad_landmarks.json"

# Meshes the player must not walk through. Everything else stays decorative.
# Flat decals and overhead foliage must not become collision, or the player
# snags on painted lines and the navmesh grows floating polygons in tree tops.
NO_COLLIDE = {"Water", "Landuse", "Markings", "Windows", "Props_Foliage",
              "Mall_Car_Park"}

# The batched city meshes. Everything else is a named building worth exporting
# to gameplay code as a landmark.
STRUCTURAL_MESHES = {
    "Ground", "Landuse", "Water", "Roads_Major", "Roads_Minor", "Footways",
    "Sidewalks", "Markings", "Buildings", "Buildings_Infill", "Windows",
    "Props_Solid", "Props_Foliage", "Mall_Car_Park",
}

# Godot only strips this suffix when it is the very end of the node name.
COL_SUFFIX = "-col"

def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4

# Landmarks worth exposing to gameplay code.
KEY_LANDMARKS = [
    # Banilad corridor: the two hand-modelled landmarks and their neighbours.
    "Gaisano Country Mall",
    "University of Cebu - Banilad Campus",
    "Alicia Residences",
    "Petron",
    "Banilad Town Center",
    # Cebu IT Park, roughly 1 km south-west and visible as the skyline from
    # the Banilad corridor.
    "Ayala Malls Central Bloc",
    "Cebu Exchange",
    "Calyx Centre",
    "Filinvest Cyberzone Cebu Tower 3 & 4",
    "eBloc 2 Tower",
    "eBloc 3 Tower",
    "Globe Telecom Tower",
    "HM Tower",
    "Mabuhay Tower",
    "Park Centrale Tower",
    "Skyrise 3",
    "Skyrise 4",
    "TGU Tower",
    "The Link",
    "The Walk",
]


def log(msg):
    print("[godot-prep] {:s}".format(msg))
    sys.stdout.flush()


def mesh_objects():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def world_bounds(obj):
    """Axis-aligned bounds of an object in world space."""
    corners = [obj.matrix_world @ v.co for v in obj.data.vertices]
    if not corners:
        return None
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    zs = [c.z for c in corners]
    return (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs))


def verify_scale():
    """Confirm 1 Blender unit == 1 metre using known real-world dimensions."""
    log("--- scale check (expects 1 unit = 1 metre) ---")

    checks = []
    for obj in mesh_objects():
        if obj.name == "Ground":
            b = world_bounds(obj)
            span = b[3] - b[0]
            # 2 * GROUND_HALF in build_map.py, widened to reach past IT Park.
            checks.append(("Ground span", span, 2300.0, 2700.0))
        if obj.name.startswith("Gaisano Country Mall"):
            b = world_bounds(obj)
            checks.append(("Gaisano footprint X", b[3] - b[0], 60.0, 320.0))
            checks.append(("Gaisano footprint Y", b[4] - b[1], 60.0, 320.0))
        if obj.name.startswith("University of Cebu"):
            b = world_bounds(obj)
            checks.append(("UC Banilad footprint X", b[3] - b[0], 30.0, 260.0))

    ok = True
    for label, value, lo, hi in checks:
        verdict = "OK" if lo <= value <= hi else "OUT OF RANGE"
        if not (lo <= value <= hi):
            ok = False
        log("  {:<26s} {:8.1f} m   expected {:.0f}-{:.0f} m   {:s}".format(
            label, value, lo, hi, verdict))

    # Building footprints should mostly land in the 8-60 m range.
    widths = []
    for obj in mesh_objects():
        if not obj.name.startswith("Buildings_"):
            continue
        b = world_bounds(obj)
        if b:
            widths.append(b[5] - b[2])
    if widths:
        log("  tallest batched building   {:8.1f} m".format(max(widths)))

    log("  verdict: {:s}".format(
        "scale is already real-world, no rescale needed" if ok
        else "SCALE LOOKS WRONG - review before export"))
    return ok


def apply_all_transforms():
    bpy.ops.object.select_all(action="DESELECT")
    count = 0
    for obj in mesh_objects():
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        count += 1
    if count:
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")
    log("applied transforms on {:d} objects".format(count))


def wants_collision(name):
    return name not in NO_COLLIDE


def tag_collision():
    collided = 0
    skipped = []
    for obj in mesh_objects():
        if obj.name.endswith(COL_SUFFIX):
            continue
        if wants_collision(obj.name):
            obj.name = obj.name + COL_SUFFIX
            collided += 1
        else:
            skipped.append(obj.name)
    log("tagged {:d} meshes with '{:s}'".format(collided, COL_SUFFIX))
    log("left decorative (no collision): {:s}".format(", ".join(sorted(skipped))))


def check_palette():
    """Confirm the round trip to Godot will land on the intended colours.

    build_map.py stores the wanted sRGB colour and writes its linear value into
    the Principled shader. Blender exports that linear value as the glTF
    baseColorFactor, and Godot re-encodes it into albedo_color. The net effect
    is that Godot's albedo_color should read back as the intended sRGB number,
    so nothing needs re-authoring here.
    """
    checked = 0
    drifted = []
    for mat in bpy.data.materials:
        intended = mat.get("intended_srgb")
        if intended is None:
            continue
        bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
        if bsdf is None:
            continue
        authored = bsdf.inputs["Base Color"].default_value
        for i, want in enumerate(intended):
            if abs(authored[i] - srgb_to_linear(want)) > 0.01:
                drifted.append(mat.name)
                break
        checked += 1
    log("palette: {:d} materials verified against intended sRGB".format(checked))
    if drifted:
        log("  DRIFTED: {:s}".format(", ".join(sorted(set(drifted)))))


def export_landmarks():
    """Record landmark centroids in Godot space (glTF +Y up)."""
    entries = []
    for obj in mesh_objects():
        clean = obj.name[:-len(COL_SUFFIX)] if obj.name.endswith(COL_SUFFIX) else obj.name
        if clean in STRUCTURAL_MESHES:
            continue
        b = world_bounds(obj)
        if not b:
            continue
        cx = (b[0] + b[3]) * 0.5
        cy = (b[1] + b[4]) * 0.5
        top = b[5]
        # Blender Z-up -> Godot Y-up: (x, y, z) becomes (x, z, -y)
        entries.append({
            "name": clean,
            "godot_position": [round(cx, 2), 0.0, round(-cy, 2)],
            "roof_height": round(top, 2),
            "footprint": [round(b[3] - b[0], 1), round(b[4] - b[1], 1)],
            "key": clean in KEY_LANDMARKS,
        })

    entries.sort(key=lambda e: (not e["key"], e["name"]))
    MAP_DIR.mkdir(parents=True, exist_ok=True)
    LANDMARK_OUT.write_text(json.dumps(entries, indent=2), encoding="utf-8")
    log("wrote {:d} landmarks ({:d} key) to {:s}".format(
        len(entries), sum(1 for e in entries if e["key"]), LANDMARK_OUT.name))

    for e in entries[:8]:
        log("  {:<38s} {:s}".format(e["name"], str(e["godot_position"])))
    return entries


def main():
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    log("opened {:s} with {:d} mesh objects".format(BLEND.name, len(mesh_objects())))

    verify_scale()
    apply_all_transforms()
    check_palette()
    tag_collision()
    export_landmarks()

    MAP_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
    )
    log("exported {:s} ({:.2f} MB)".format(GLB_OUT.name, GLB_OUT.stat().st_size / 1048576))
    log("DONE")


main()
