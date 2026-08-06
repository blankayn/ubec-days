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
import re
import sys

import bpy

HERE = pathlib.Path(__file__).parent
PROJECT = HERE.parent
BLEND = HERE / "banilad_map.blend"
MAP_DIR = PROJECT / "assets" / "maps"
GLB_OUT = MAP_DIR / "banilad_map.glb"
LANDMARK_OUT = MAP_DIR / "banilad_landmarks.json"

# Streaming output. TILES_DIR holds one GLB per 250 m tile; BASE_OUT holds the
# meshes that must never be unloaded (ground, road collision, skyline).
# banilad_map.glb is still written alongside these so the current runtime keeps
# working until the streamer replaces it.
TILES_DIR = MAP_DIR / "tiles"
BASE_OUT = MAP_DIR / "banilad_base.glb"
TILES_MANIFEST = MAP_DIR / "tiles.json"

# Must match TILE_SIZE in build_map.py; the tile keys are meaningless otherwise.
TILE_SIZE = 250.0

# Meshes the player must not walk through. Everything else stays decorative.
# Flat decals and overhead foliage must not become collision, or the player
# snags on painted lines and the navmesh grows floating polygons in tree tops.
#
# The carriageway ribbons are decorative too: build_map.py stacks them across
# 3 cm to stop them z-fighting, which physics reads as a pile of overlapping
# surfaces. Roads_Collision replaces the lot with one flat plane.
#
# Skyline is a duplicate silhouette standing exactly where the real buildings
# are. Giving it collision would wrap invisible prisms around UC and Central
# Bloc for the player to walk into.
# Sea is here for the obvious reason: collision on it would let the player walk
# out across the harbour. They should fall in and land on the seabed, which is
# real terrain and does collide.
NO_COLLIDE = {"Water", "Landuse", "Markings", "Windows", "Props_Foliage",
              "Mall_Car_Park", "Roads_Major", "Roads_Minor", "Footways",
              "Skyline", "Sea"}

# Exported for their collision only: Godot drops the mesh at import and keeps
# the shape, so these never render.
COLLISION_ONLY = {"Roads_Collision"}

# The batched city meshes. Everything else is a named building worth exporting
# to gameplay code as a landmark.
STRUCTURAL_MESHES = {
    "Ground", "Landuse", "Water", "Roads_Major", "Roads_Minor", "Footways",
    "Sidewalks", "Markings", "Buildings", "Buildings_Infill", "Windows",
    "Props_Solid", "Props_Foliage", "Mall_Car_Park", "Roads_Collision",
    "Mall_Walkway", "Skyline", "Sea",
}

# Godot only honours these when they are the very end of the node name.
# "-col" keeps the mesh and adds a collider; "-colonly" keeps only the collider.
COL_SUFFIX = "-col"
COLONLY_SUFFIX = "-colonly"

def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


# Mirrors build_map.py. Duplicated rather than imported for the same reason
# srgb_to_linear above is: build_map.py ends in a bare main() call, so importing
# it would rebuild the entire map. check_palette() below fails loudly if these
# ever stop matching what the .blend actually contains, which is the point.
TINT_LAYER = "Col"
TINT_ATTR_NODE = "VertexTint"
TINT_MIX_NODE = "TintMultiply"

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

# Key landmarks whose OSM `name` is not unique inside the extent, pinned to the
# feature actually meant. Anything not listed here matches on name alone.
#
# Petron: three fuel stations carry the name. The landmark is the one on
# Gov. M. Cuenco Avenue, ~340 m south of the spawn -- banilad_smoke_test.gd
# navigates to it by coordinate as PATH_TO.
#
# Cebu Exchange: two adjacent commercial footprints of the same IT Park
# development; this is the one nearest the centroid that was key before.
# Mabuhay Tower: slice 3 brought a second building of that name onto the map
# near Fuente, and both were flagged. The one meant is in IT Park -- an
# unpinned duplicate flags EVERY instance, so any name that later collides has
# to be added here.
KEY_LANDMARK_WAYS = {
    "Petron": 132902360,
    "Cebu Exchange": 616355742,
    "Mabuhay Tower": 539906301,
}


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
    ground_bounds = None
    content_bounds = None
    for obj in mesh_objects():
        b = world_bounds(obj)
        if not b:
            continue
        if obj.name == "Ground":
            ground_bounds = b
            # Deliberately a very wide band. The ground plane is now sized from
            # the data by build_map.py, so pinning it to a narrow range would
            # just fail every time the bbox moves. This only has to catch a
            # catastrophic unit error; the coverage check below is the real one.
            checks.append(("Ground span", b[3] - b[0], 1500.0, 20000.0))
        else:
            content_bounds = b if content_bounds is None else (
                min(content_bounds[0], b[0]), min(content_bounds[1], b[1]),
                min(content_bounds[2], b[2]), max(content_bounds[3], b[3]),
                max(content_bounds[4], b[4]), max(content_bounds[5], b[5]),
            )
        if obj.name.startswith("Gaisano Country Mall"):
            checks.append(("Gaisano footprint X", b[3] - b[0], 60.0, 320.0))
            checks.append(("Gaisano footprint Y", b[4] - b[1], 60.0, 320.0))
        if obj.name.startswith("University of Cebu"):
            checks.append(("UC Banilad footprint X", b[3] - b[0], 30.0, 260.0))

    ok = True
    for label, value, lo, hi in checks:
        verdict = "OK" if lo <= value <= hi else "OUT OF RANGE"
        if not (lo <= value <= hi):
            ok = False
        log("  {:<26s} {:8.1f} m   expected {:.0f}-{:.0f} m   {:s}".format(
            label, value, lo, hi, verdict))

    # Does the ground actually reach under everything built on it? Roads that
    # run off the edge of the plane hang over void, which is exactly what the
    # old hand-maintained GROUND_HALF let happen.
    if ground_bounds and content_bounds:
        overhang = max(
            ground_bounds[0] - content_bounds[0],   # content reaches further -X
            ground_bounds[1] - content_bounds[1],   # ...             further -Y
            content_bounds[3] - ground_bounds[3],   # ...             further +X
            content_bounds[4] - ground_bounds[4],   # ...             further +Y
        )
        covered = overhang <= 0.0
        if not covered:
            ok = False
        log("  {:<26s} {:8.1f} m   expected <= 0 m       {:s}".format(
            "geometry past ground edge", overhang,
            "OK" if covered else "GROUND PLANE TOO SMALL"))

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


_TILE_SUFFIX = re.compile(r"__r-?\d+c-?\d+$")


def strip_tile_suffix(name):
    """Tiled batches are named "<Category>__r<row>c<col>"."""
    return _TILE_SUFFIX.sub("", name)


def category_of(name):
    """Which batch a mesh belongs to, ignoring tile and collision suffixes.

    Every category set in this file is keyed on the bare category name. Once
    build_map.py started splitting batches across tiles, matching on the raw
    object name silently stopped working -- and the specific consequence was
    that "Roads_Major__r-3c-6" fell out of NO_COLLIDE and would have been given
    collision, putting the layered visual ribbons back under the wheels and
    undoing the whole reason Roads_Collision exists.
    """
    return strip_tile_suffix(strip_col_suffix(name))


def wants_collision(name):
    return category_of(name) not in NO_COLLIDE


def strip_col_suffix(name):
    for suffix in (COLONLY_SUFFIX, COL_SUFFIX):
        if name.endswith(suffix):
            return name[:-len(suffix)]
    return name


_DUP_SUFFIX = re.compile(r"\.\d{3}$")


def strip_dup_suffix(name):
    """Blender appends .001/.002 to duplicate object names, in creation order."""
    return _DUP_SUFFIX.sub("", name)


def _is_key(name, osm_way):
    """Key-landmark test, resolved by OSM way id where the name is ambiguous.

    Matching on the name alone is not stable. Cebu has three Petrons inside the
    current extent; Blender gives one of them the bare name "Petron" and the
    others "Petron.001"/".002", and which one is which changes whenever the
    bbox moves. That silently re-pointed the key Petron 1.3 km, from the
    station on Gov. M. Cuenco Avenue to one in Lahug.
    """
    base = strip_dup_suffix(name)
    if base not in KEY_LANDMARKS:
        return False
    pinned = KEY_LANDMARK_WAYS.get(base)
    if pinned is None:
        return True
    return osm_way is not None and int(osm_way) == pinned


def tag_collision():
    collided = 0
    col_only = []
    skipped = []
    for obj in mesh_objects():
        if obj.name.endswith(COL_SUFFIX) or obj.name.endswith(COLONLY_SUFFIX):
            continue
        if category_of(obj.name) in COLLISION_ONLY:
            obj.name = obj.name + COLONLY_SUFFIX
            col_only.append(obj.name)
        elif wants_collision(obj.name):
            obj.name = obj.name + COL_SUFFIX
            collided += 1
        else:
            skipped.append(category_of(obj.name))
    log("tagged {:d} meshes with '{:s}'".format(collided, COL_SUFFIX))
    log("collision-only (invisible): {:s}".format(
        ", ".join(sorted(col_only)) if col_only else "none"))
    # Reported by category: tiling turns each of these into dozens of meshes.
    log("left decorative (no collision): {:s}".format(
        ", ".join("{:s} x{:d}".format(n, skipped.count(n))
                  for n in sorted(set(skipped)))))
    if not col_only:
        log("  WARNING: no Roads_Collision mesh found - rebuild with build_map.py")


def check_palette():
    """Confirm the round trip to Godot will land on the intended colours.

    build_map.py stores the wanted sRGB colour and writes its linear value into
    the shader. Blender exports that as the glTF baseColorFactor and Godot
    re-encodes it into albedo_color, so Godot's albedo_color should read back
    as the intended sRGB number with nothing re-authored here.

    Since vertex tinting landed, Base Color is a LINKED socket -- it is driven
    by `intended x COLOR_0` through a multiply node -- and its own
    default_value is dead. Reading it would make this check vacuous: it would
    keep passing while the colour that actually ships came from somewhere else
    entirely. So the authored constant is read from the multiply node's A
    socket, and the wiring itself is verified too, because a broken tint chain
    is the other way this silently stops being true.
    """
    checked = 0
    drifted = []
    unwired = []
    for mat in bpy.data.materials:
        intended = mat.get("intended_srgb")
        if intended is None:
            continue
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF") if nt else None
        if bsdf is None:
            continue
        mix = nt.nodes.get(TINT_MIX_NODE)
        attr = nt.nodes.get(TINT_ATTR_NODE)
        base_socket = bsdf.inputs["Base Color"]

        if mix is None or attr is None:
            # No tint chain: the constant still drives albedo directly.
            unwired.append(mat.name)
            authored = base_socket.default_value
        else:
            # Compare by name, not identity: bpy returns a fresh Python wrapper
            # on every attribute access, so `from_node is mix` is False even
            # when they are the same node -- which would report every material
            # as broken.
            wired = (base_socket.is_linked
                     and base_socket.links[0].from_node.name == TINT_MIX_NODE
                     and mix.inputs[7].is_linked
                     and mix.inputs[7].links[0].from_node.name == TINT_ATTR_NODE
                     and attr.layer_name == TINT_LAYER
                     and abs(mix.inputs["Factor"].default_value - 1.0) < 1e-6
                     and mix.blend_type == "MULTIPLY")
            if not wired:
                unwired.append(mat.name)
            authored = mix.inputs[6].default_value

        for i, want in enumerate(intended):
            if abs(authored[i] - srgb_to_linear(want)) > 0.01:
                drifted.append(mat.name)
                break
        checked += 1
    log("palette: {:d} materials verified against intended sRGB "
        "(read from the tint multiply, not the dead Base Color socket)".format(
            checked))
    if drifted:
        log("  DRIFTED: {:s}".format(", ".join(sorted(set(drifted)))))
    if unwired:
        log("  TINT CHAIN BROKEN, vertex colour will not reach albedo: "
            "{:s}".format(", ".join(sorted(set(unwired)))))


def export_landmarks():
    """Record landmark centroids in Godot space (glTF +Y up)."""
    entries = []
    for obj in mesh_objects():
        if category_of(obj.name) in STRUCTURAL_MESHES:
            continue
        clean = strip_col_suffix(obj.name)
        b = world_bounds(obj)
        if not b:
            continue
        cx = (b[0] + b[3]) * 0.5
        cy = (b[1] + b[4]) * 0.5
        top = b[5]
        # The OSM way id, where build_map.py stamped one. `name` carries
        # Blender's .001/.002 suffix for duplicates and so is NOT a stable
        # identity; prefer `osm` for anything that has to survive a re-fetch.
        osm_way = obj.get("osm_way")
        # Blender Z-up -> Godot Y-up: (x, y, z) becomes (x, z, -y)
        entries.append({
            # Display label only -- the HUD prints this. Duplicates are fine and
            # expected (three Petrons); `osm` carries the identity. Blender's
            # .001/.002 suffix is stripped so the HUD does not say "Petron.002".
            "name": strip_dup_suffix(clean),
            "osm": int(osm_way) if osm_way is not None else None,
            "godot_position": [round(cx, 2), 0.0, round(-cy, 2)],
            "roof_height": round(top, 2),
            "footprint": [round(b[3] - b[0], 1), round(b[4] - b[1], 1)],
            "key": _is_key(clean, osm_way),
        })

    entries.sort(key=lambda e: (not e["key"], e["name"]))
    MAP_DIR.mkdir(parents=True, exist_ok=True)
    LANDMARK_OUT.write_text(json.dumps(entries, indent=2), encoding="utf-8")
    log("wrote {:d} landmarks ({:d} key) to {:s}".format(
        len(entries), sum(1 for e in entries if e["key"]), LANDMARK_OUT.name))

    for e in entries[:8]:
        log("  {:<38s} {:s}".format(e["name"], str(e["godot_position"])))
    return entries


_TILE_KEY = re.compile(r"^r(-?\d+)c(-?\d+)$")


def parse_tile_key(key):
    match = _TILE_KEY.match(key)
    if not match:
        raise SystemExit("unparseable tile key: {!r}".format(key))
    return int(match.group(1)), int(match.group(2))


def triangle_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export_selection(objects, path):
    """Export just these objects to one GLB. Returns the triangle count."""
    if not objects:
        return 0
    bpy.ops.object.select_all(action="DESELECT")
    tris = 0
    for obj in objects:
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        tris += triangle_count(obj)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        use_selection=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
    )
    bpy.ops.object.select_all(action="DESELECT")
    return tris


def export_tiles():
    """One GLB per 250 m tile, plus one for everything always resident.

    build_map.py stamps a "tile" property on every mesh it splits. Anything
    without one is always-resident by construction: the ground plane, the flat
    road-collision surface physics drives on, and the skyline silhouette.
    """
    groups = {}
    always = []
    for obj in mesh_objects():
        key = obj.get("tile")
        if key is None:
            always.append(obj)
        else:
            groups.setdefault(str(key), []).append(obj)

    TILES_DIR.mkdir(parents=True, exist_ok=True)
    # Stale tiles from a previous, larger extent would otherwise be streamed in
    # as ghost geometry that nothing rebuilds.
    for old in TILES_DIR.glob("*.glb"):
        old.unlink()

    tile_tris = 0
    for key in sorted(groups):
        tile_tris += export_selection(groups[key], TILES_DIR / "{:s}.glb".format(key))
    base_tris = export_selection(always, BASE_OUT)

    # Manifest rather than a runtime directory scan: DirAccess over res:// does
    # not see .glb files the same way in an exported build as in the editor,
    # and the streamer needs each tile's footprint anyway to measure distance
    # to the nearest edge instead of to the centre.
    manifest = {
        "tile_size": TILE_SIZE,
        "tiles": [],
    }
    for key in sorted(groups):
        row, col = parse_tile_key(key)
        x0 = col * TILE_SIZE
        y0 = row * TILE_SIZE
        # Blender +y is north; Godot z is its negation, so the row flips.
        manifest["tiles"].append({
            "key": key,
            "min": [x0, -(y0 + TILE_SIZE)],
            "max": [x0 + TILE_SIZE, -y0],
        })
    TILES_MANIFEST.write_text(json.dumps(manifest, indent=1), encoding="utf-8")

    tile_bytes = sum(p.stat().st_size for p in TILES_DIR.glob("*.glb"))
    log("--- tiles ---")
    log("  manifest: {:s} ({:d} entries)".format(
        TILES_MANIFEST.name, len(manifest["tiles"])))
    log("  {:d} tiles, {:,d} triangles, {:.2f} MB".format(
        len(groups), tile_tris, tile_bytes / 1048576))
    log("  always resident: {:d} meshes, {:,d} triangles, {:.2f} MB ({:s})".format(
        len(always), base_tris, BASE_OUT.stat().st_size / 1048576,
        ", ".join(sorted(category_of(o.name) for o in always))))
    return tile_tris, base_tris


def main():
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    log("opened {:s} with {:d} mesh objects".format(BLEND.name, len(mesh_objects())))

    verify_scale()
    apply_all_transforms()
    check_palette()
    tag_collision()
    export_landmarks()

    tile_tris, base_tris = export_tiles()

    MAP_DIR.mkdir(parents=True, exist_ok=True)
    # The legacy single-file map, still what banilad_city.tscn loads until the
    # streamer lands. Skyline is deliberately left out of it: those silhouettes
    # stand exactly where the real buildings do, so without streaming they are
    # just z-fighting duplicates.
    legacy = [o for o in mesh_objects() if category_of(o.name) != "Skyline"]
    legacy_tris = export_selection(legacy, GLB_OUT)
    log("exported {:s} ({:.2f} MB, {:,d} triangles, skyline excluded)".format(
        GLB_OUT.name, GLB_OUT.stat().st_size / 1048576, legacy_tris))

    # Conservation check: the tiles plus the always-resident set must add up to
    # the monolithic export, or splitting dropped or duplicated geometry.
    whole = sum(triangle_count(o) for o in mesh_objects())
    split = tile_tris + base_tris
    log("triangles: monolithic {:,d}  tiles+base {:,d}  {:s}".format(
        whole, split, "OK" if whole == split else "MISMATCH - geometry lost"))
    log("DONE")


main()
