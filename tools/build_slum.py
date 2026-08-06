"""Build the Banilad informal-settlement districts and export them as a GLB.

    "C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P tools/build_slum.py

Writes `assets/buildings/banilad_slum.glb`,
`assets/buildings/banilad_slum_graffiti.png` and
`assets/maps/banilad_slum_alleys.json`.

Why this exists: `place_infill_housing()` in `banilad_map/build_map.py` fills the
map with thousands of jittered boxes, each one `walls()` + `hip_roof()`. Every
house is the same primitive at a different size, which is what makes the city
read as a block city. This builds dense barangays out of a real modular house
kit instead, with winding alleys, corrugated roofing and wall tags.

Source kit: `C:/Users/Ariel/Downloads/house-pack-assets/source/house pack.blend`.
Facts about it that are not obvious from the object names, all verified headless:

  * Objects carry rotations, so `obj.dimensions` is local and misleading. The
    wall panels stand upright in *world* space: width along Y, thickness along
    X, height along Z. `kit_piece()` re-origins them to width-X / depth-Y /
    height-Z with the base at z=0, which is what the placement code assumes.
  * Face counts are wildly uneven. `plain wall 1` is a single quad; `wall two
    windows 2` is 516 faces and `house 2` is 15497. Naively instancing the
    assembled houses would cost millions of triangles, so this uses only the
    cheap window/door modules and builds blank walls as thin boxes.
  * Blank walls are boxes rather than the kit's zero-thickness `plain wall`
    quad because the export is `-col` tagged: a paper-thin trimesh collider is
    something the player can clip through.
  * The kit has no corrugated roof. Rusted GI sheet ("yero") is the defining
    feature of Philippine informal housing, so `corrugated()` generates it.
  * All kit materials are flat colours with no textures, in a generic
    brown/grey/purple palette. `CEBU_PALETTE` remaps them to faded paint, bare
    hollow block and weathered ply; set it False to keep the kit's own colours.

Each district carries its own `kit` probability. Kit modules cost 83-192 faces
against 6 for a box, so only the flagship district spends them on every bay;
the outer sitios use them sometimes and box the rest. That is also what keeps
five districts inside a sane file size.

Graffiti is generated, not painted by hand: `graffiti_atlas()` scrawls a 4x4
sheet of tags with numpy and the houses carry decal quads UV'd into one cell
each. Alpha mode is CLIP (glTF MASK) rather than BLEND so there is no
transparency sort order to get wrong against the walls behind them.

Districts are built at ABSOLUTE map coordinates and the whole GLB is instanced
at `Vector3.ZERO` in `banilad_city.gd`, the same contract
`gaisano_country_mall.glb` already uses. Blender (x, y) maps to Godot (x, 0, -y).

Placement is checked against `banilad_map/banilad_osm.json` directly rather than
against a hand-read map, so a house can never land on a carriageway or inside an
OSM building footprint.
"""

import json
import math
import pathlib
import random
import sys

import bpy
import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
PROJECT = HERE.parent
# The shared pipeline modules live beside the map builder, and Blender's `-P`
# puts nothing on sys.path for us.
if str(PROJECT / "banilad_map") not in sys.path:
    sys.path.insert(0, str(PROJECT / "banilad_map"))

from districts import SLUM_DISTRICTS  # noqa: E402
from geo import project  # noqa: E402

KIT_BLEND = pathlib.Path(
    r"C:/Users/Ariel/Downloads/house-pack-assets/source/house pack.blend")
OSM_FILE = PROJECT / "banilad_map" / "banilad_osm.json"
LANDMARKS = PROJECT / "assets" / "maps" / "banilad_landmarks.json"
OUTPUT_GLB = PROJECT / "assets" / "buildings" / "banilad_slum.glb"
OUTPUT_PNG = PROJECT / "assets" / "buildings" / "banilad_slum_graffiti.png"
OUTPUT_ALLEYS = PROJECT / "assets" / "maps" / "banilad_slum_alleys.json"

SEED = 20260802
CEBU_PALETTE = True

# Clear pockets found by rasterising the OSM occupancy grid: no buildings, no
# landmarks, no water, but touching a real street. build_map.py has to keep its
# procedural infill and street furniture out of these same rects, so both
# scripts read one definition from banilad_map/districts.py.
DISTRICTS = SLUM_DISTRICTS

MODULE = 2.2                    # one kit wall panel scaled to a storey
MIN_ALLEY_SEP = 11.0            # 1.4 m of path plus a house depth each side
ALLEY_HALF = 0.7                # eskinita half-width; 1.4 m of walking room
YAW_JITTER = 0.07               # nothing in a settlement lines up squarely
# The walkability test is a hair narrower than placement. Frontage houses sit
# with their edge ON the corridor boundary, so testing at the full width
# rejects every one of them the moment the yaw jitter tips a corner inward.
CORRIDOR_HALF = ALLEY_HALF - 0.05
ROAD_CLEARANCE = 7.0
BUILDING_CLEARANCE = 6.0
GROUND_CELL = 0.7

GRAFFITI_CHANCE = 0.34
ATLAS_PX = 512
ATLAS_CELLS = 4

FACE_CAP_PER_HOUSE = 1400
FACE_BUDGET = 260000

# --- Palette, sRGB ---------------------------------------------------------
PAINTS = [
    ("Slum_Mint",   (0.62, 0.74, 0.65)),
    ("Slum_Blue",   (0.60, 0.70, 0.76)),
    ("Slum_Pink",   (0.80, 0.62, 0.60)),
    ("Slum_Ochre",  (0.78, 0.66, 0.42)),
    ("Slum_Cream",  (0.82, 0.78, 0.66)),
    ("Slum_Green",  (0.52, 0.60, 0.48)),
    ("Slum_CHB",    (0.62, 0.61, 0.58)),   # bare hollow block, unpainted
    ("Slum_CHB2",   (0.55, 0.54, 0.52)),
]
ROOFS = [
    ("Slum_Rust",     (0.42, 0.26, 0.18)),
    ("Slum_Rust2",    (0.55, 0.34, 0.22)),
    ("Slum_Galv",     (0.58, 0.59, 0.58)),
    ("Slum_TinRed",   (0.48, 0.28, 0.24)),
    ("Slum_TinGreen", (0.38, 0.46, 0.44)),
]
EXTRA = {
    "Slum_Glass": (0.24, 0.30, 0.34),
    "Slum_Metal": (0.52, 0.52, 0.50),
    "Slum_Ply":   (0.45, 0.34, 0.24),
    "Slum_Dirt":  (0.44, 0.40, 0.34),
}
# Spray colours, sRGB. Cheap rattle-can stock: white, black, and whatever red
# or blue was on the shelf.
TAG_INK = [
    (0.94, 0.94, 0.92), (0.09, 0.09, 0.10), (0.78, 0.16, 0.16),
    (0.16, 0.31, 0.68), (0.92, 0.78, 0.18), (0.20, 0.56, 0.32),
]

# kit material name -> role. Anything unlisted becomes the house's wall paint.
KIT_ROLE = {
    "window": "Slum_Glass", "window blue ": "Slum_Glass",
    "window col": "Slum_Glass", "metal": "Slum_Metal",
    "wood color": "Slum_Ply", "wood light": "Slum_Ply", "brown ": "Slum_Ply",
}

# Cheap kit modules only. `wall two windows 2` (516 faces), `door 2` (192) and
# the assembled `house 1/2/3` (up to 15497) are deliberately excluded; the
# window list is weighted toward `plain wall decoration 1` at 68 faces.
KIT_MODULES = ["wall -door 1", "wall one window 1", "plain wall decoration 1"]
WINDOW_MODULES = ["plain wall decoration 1", "plain wall decoration 1",
                  "wall one window 1"]


def log(msg):
    print("[slum] {:s}".format(msg))
    sys.stdout.flush()


def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def xform(verts, cx, cy, cz, yaw, sx=1.0, sy=1.0, sz=1.0):
    """Scale, rotate about Z, then translate a vert list."""
    c, s = math.cos(yaw), math.sin(yaw)
    out = []
    for x, y, z in verts:
        x, y, z = x * sx, y * sy, z * sz
        out.append((cx + x * c - y * s, cy + x * s + y * c, cz + z))
    return out


def box(w, d, h):
    """Axis-aligned box centred on XY, base at z=0."""
    hx, hy = w * 0.5, d * 0.5
    v = [(-hx, -hy, 0.0), (hx, -hy, 0.0), (hx, hy, 0.0), (-hx, hy, 0.0),
         (-hx, -hy, h), (hx, -hy, h), (hx, hy, h), (-hx, hy, h)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
         (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return v, f


def corrugated(w, d, z_front, z_back, pitch=0.34, rib=0.04, thick=0.05):
    """A ribbed GI sheet: the ribs run down the slope, the way yero is laid."""
    n = max(3, int(round(w / pitch)))
    verts, faces = [], []
    for i in range(n + 1):
        x = -w * 0.5 + w * i / n
        r = rib if i % 2 == 0 else 0.0
        verts.append((x, -d * 0.5, z_front + r))
        verts.append((x, d * 0.5, z_back + r))
        verts.append((x, -d * 0.5, z_front + r - thick))
        verts.append((x, d * 0.5, z_back + r - thick))

    def vid(i, k):
        return i * 4 + k

    for i in range(n):
        faces.append((vid(i, 0), vid(i, 1), vid(i + 1, 1), vid(i + 1, 0)))
        faces.append((vid(i, 2), vid(i + 1, 2), vid(i + 1, 3), vid(i, 3)))
        faces.append((vid(i, 0), vid(i + 1, 0), vid(i + 1, 2), vid(i, 2)))
        faces.append((vid(i, 1), vid(i, 3), vid(i + 1, 3), vid(i + 1, 1)))
    faces.append((vid(0, 0), vid(0, 2), vid(0, 3), vid(0, 1)))
    faces.append((vid(n, 0), vid(n, 1), vid(n, 3), vid(n, 2)))
    return verts, faces


def quad(pts, z):
    """A flat quad wound CCW so its normal faces up whichever way pts ran."""
    area = sum(pts[i][0] * pts[(i + 1) % 4][1] - pts[(i + 1) % 4][0] * pts[i][1]
               for i in range(4))
    if area < 0.0:
        pts = pts[::-1]
    return [(p[0], p[1], z) for p in pts], [(0, 1, 2, 3)]


# ---------------------------------------------------------------------------
# Graffiti
# ---------------------------------------------------------------------------

def _disc(buf, x, y, r, rgba):
    size = buf.shape[0]
    x0, x1 = max(0, int(x - r)), min(size, int(x + r) + 1)
    y0, y1 = max(0, int(y - r)), min(size, int(y + r) + 1)
    if x1 <= x0 or y1 <= y0:
        return
    ys, xs = np.mgrid[y0:y1, x0:x1]
    mask = (xs - x) ** 2 + (ys - y) ** 2 <= r * r
    buf[y0:y1, x0:x1][mask] = rgba


def _stroke(buf, pts, r, rgba):
    for a, b in zip(pts, pts[1:]):
        span = math.hypot(b[0] - a[0], b[1] - a[1])
        steps = max(2, int(span / max(1.0, r * 0.4)))
        for i in range(steps + 1):
            t = i / steps
            _disc(buf, a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, r, rgba)


def graffiti_atlas(rng):
    """A 4x4 sheet of spray tags. Transparent everywhere the can did not go.

    Pixels go in as LINEAR because the image is a byte buffer in sRGB space:
    Blender converts on write, so authoring the sRGB values directly would come
    out washed out.
    """
    buf = np.zeros((ATLAS_PX, ATLAS_PX, 4), dtype=np.float32)
    cell = ATLAS_PX // ATLAS_CELLS
    for cy in range(ATLAS_CELLS):
        for cx in range(ATLAS_CELLS):
            ox, oy = cx * cell, cy * cell
            ink = TAG_INK[rng.randrange(len(TAG_INK))]
            rgba = (*[srgb_to_linear(c) for c in ink], 1.0)
            outline = (0.02, 0.02, 0.02, 1.0)
            pad = cell * 0.14
            for _ in range(rng.randint(2, 4)):
                n = rng.randint(4, 7)
                pts = []
                px = ox + pad + rng.uniform(0.0, cell * 0.2)
                py = oy + rng.uniform(pad, cell - pad)
                for _i in range(n):
                    px += (cell - 2 * pad) / n * rng.uniform(0.6, 1.5)
                    py += rng.uniform(-cell * 0.22, cell * 0.22)
                    pts.append((min(px, ox + cell - pad),
                                min(max(py, oy + pad), oy + cell - pad)))
                width = rng.uniform(cell * 0.035, cell * 0.075)
                _stroke(buf, pts, width * 1.55, outline)
                _stroke(buf, pts, width, rgba)
    return buf


def graffiti_material(rng):
    buf = graffiti_atlas(rng)
    img = bpy.data.images.new("SlumGraffiti", ATLAS_PX, ATLAS_PX, alpha=True)
    img.pixels.foreach_set(buf.reshape(-1))
    OUTPUT_PNG.parent.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(OUTPUT_PNG)
    img.file_format = "PNG"
    img.save()

    mat = bpy.data.materials.new("Slum_Graffiti")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.95
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"          # PSX look, same as image_to_building
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    # CLIP -> glTF alphaMode MASK. BLEND would make every tag a transparent
    # surface the renderer has to sort against the wall right behind it.
    mat.blend_method = "CLIP"
    mat.alpha_threshold = 0.5
    log("graffiti atlas {:d}px, {:d} tags -> {:s}".format(
        ATLAS_PX, ATLAS_CELLS * ATLAS_CELLS, OUTPUT_PNG.name))
    return mat


# ---------------------------------------------------------------------------
# Kit loading
# ---------------------------------------------------------------------------

def append_kit(names):
    section = str(KIT_BLEND) + "\\Object\\"
    for name in names:
        bpy.ops.wm.append(filepath=section + name,
                          directory=section, filename=name)


def kit_piece(name):
    """World-space geometry re-origined to width-X, thickness-Y, base at z=0.

    The kit authors panels with width along Y and thickness along X, so this
    rotates +90 deg about Z. That is a proper rotation, not a coordinate swap -
    swapping two axes would mirror the piece and invert every face winding.
    """
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError("kit piece missing: {!r}".format(name))
    mesh = obj.data
    world = [obj.matrix_world @ v.co for v in mesh.vertices]
    mnx, mxx = min(v.x for v in world), max(v.x for v in world)
    mny, mxy = min(v.y for v in world), max(v.y for v in world)
    mnz = min(v.z for v in world)
    cx, cy = (mnx + mxx) * 0.5, (mny + mxy) * 0.5
    verts = [(v.y - cy, -(v.x - cx), v.z - mnz) for v in world]

    groups = {}
    for poly in mesh.polygons:
        slot = obj.material_slots[poly.material_index] if obj.material_slots else None
        key = slot.material.name if slot and slot.material else ""
        groups.setdefault(key, []).append(tuple(poly.vertices))
    return {
        "verts": verts, "groups": groups,
        "width": mxy - mny,
        "height": max(v.z for v in world) - mnz,
        "faces": len(mesh.polygons),
    }


class Batch:
    """Accumulates features into one multi-material mesh (cf. build_map.py)."""

    def __init__(self):
        self.verts, self.faces, self.slots_of_face = [], [], []
        self.uvs = []
        self.slots, self._slot = [], {}
        self.has_uv = False

    def slot(self, mat):
        if mat.name not in self._slot:
            self._slot[mat.name] = len(self.slots)
            self.slots.append(mat)
        return self._slot[mat.name]

    def add(self, verts, faces, mat, uvs=None):
        if not faces:
            return
        s = self.slot(mat)
        off = len(self.verts)
        self.verts.extend(verts)
        self.uvs.extend(uvs if uvs else [(0.0, 0.0)] * len(verts))
        if uvs:
            self.has_uv = True
        for f in faces:
            self.faces.append(tuple(i + off for i in f))
            self.slots_of_face.append(s)

    def to_object(self, name):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        for mat in self.slots:
            mesh.materials.append(mat)
        for poly, s in zip(mesh.polygons, self.slots_of_face):
            poly.material_index = s
        if self.has_uv:
            # UVs are per-loop in Blender; every decal owns its verts, so the
            # per-vertex value maps straight onto each corner.
            layer = mesh.uv_layers.new(name="UVMap")
            for loop in mesh.loops:
                layer.data[loop.index].uv = self.uvs[loop.vertex_index]
        mesh.validate()
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# ---------------------------------------------------------------------------
# Site clearance, straight off the OSM dump
# ---------------------------------------------------------------------------

CLEAR_CELL = 2.0
_OSM_CACHE = []


def osm_ways():
    if not _OSM_CACHE:
        data = json.loads(OSM_FILE.read_text(encoding="utf-8"))
        for e in data["elements"]:
            if e.get("type") != "way":
                continue
            tags = e.get("tags", {}) or {}
            # Overpass was queried with `out geom`, so ways carry their own
            # coords - there is no separate node table to join against.
            pts = [project(g["lat"], g["lon"])
                   for g in e.get("geometry", []) or []]
            if len(pts) >= 2:
                _OSM_CACHE.append((tags, pts))
    return _OSM_CACHE


def build_clearance(bounds):
    """Grid over a district: 1 = too close to a road, building or landmark."""
    x0, y0, x1, y1 = bounds
    pad = 12.0
    x0, y0, x1, y1 = x0 - pad, y0 - pad, x1 + pad, y1 + pad
    nx = int((x1 - x0) / CLEAR_CELL) + 1
    ny = int((y1 - y0) / CLEAR_CELL) + 1
    grid = bytearray(nx * ny)

    def stamp(px, py, rad):
        ci, cj = int((px - x0) / CLEAR_CELL), int((py - y0) / CLEAR_CELL)
        rr = int(rad / CLEAR_CELL) + 1
        for j in range(max(0, cj - rr), min(ny, cj + rr + 1)):
            for i in range(max(0, ci - rr), min(nx, ci + rr + 1)):
                gx, gy = x0 + i * CLEAR_CELL, y0 + j * CLEAR_CELL
                if (gx - px) ** 2 + (gy - py) ** 2 <= rad * rad:
                    grid[j * nx + i] = 1

    def walk(pts, rad):
        for a, b in zip(pts, pts[1:]):
            dist = math.hypot(b[0] - a[0], b[1] - a[1])
            if dist > 500.0:
                continue
            steps = max(1, int(dist / (CLEAR_CELL * 0.5)))
            for s in range(steps + 1):
                t = s / steps
                stamp(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, rad)

    for tags, pts in osm_ways():
        if max(p[0] for p in pts) < x0 or min(p[0] for p in pts) > x1:
            continue
        if max(p[1] for p in pts) < y0 or min(p[1] for p in pts) > y1:
            continue
        if "highway" in tags:
            walk(pts, ROAD_CLEARANCE)
        elif "building" in tags:
            walk(pts + pts[:1], BUILDING_CLEARANCE)
        elif tags.get("natural") == "water" or "waterway" in tags:
            walk(pts, 10.0)

    for m in json.loads(LANDMARKS.read_text(encoding="utf-8")):
        gx, _, gz = m["godot_position"]
        stamp(gx, -gz, max(m["footprint"]) * 0.5 + BUILDING_CLEARANCE)

    def blocked(px, py):
        i, j = int((px - x0) / CLEAR_CELL), int((py - y0) / CLEAR_CELL)
        if i < 0 or j < 0 or i >= nx or j >= ny:
            return True
        return grid[j * nx + i] == 1

    return blocked


# ---------------------------------------------------------------------------
# Alleys and lots
# ---------------------------------------------------------------------------

def inside(p, bounds):
    return bounds[0] <= p[0] <= bounds[2] and bounds[1] <= p[1] <= bounds[3]


def find_entry(bounds, wanted, blocked):
    """Nearest free spot to the intended alley mouth, spiralling outward."""
    if not blocked(*wanted) and inside(wanted, bounds):
        return wanted
    for ring in range(1, 26):
        for k in range(ring * 8):
            ang = math.tau * k / (ring * 8)
            p = (wanted[0] + math.cos(ang) * ring * 2.0,
                 wanted[1] + math.sin(ang) * ring * 2.0)
            if inside(p, bounds) and not blocked(*p):
                return p
    raise RuntimeError("no free entry near {!r}".format(wanted))


def grow_alleys(rng, blocked, bounds, entry, heading):
    """Random-walk footpaths that bend, branch and dead-end - not a grid."""
    alleys = []
    segs = []

    def crowded(q):
        return any(seg_point_dist(q[0], q[1], *s) < MIN_ALLEY_SEP for s in segs)

    def grow(p, head, depth, budget):
        pts = [p]
        for i in range(budget):
            head += rng.uniform(-0.42, 0.42)
            step = rng.uniform(2.6, 4.2)
            q = (p[0] + math.cos(head) * step, p[1] + math.sin(head) * step)
            if not inside(q, bounds) or blocked(q[0], q[1]):
                break
            # Hold alleys apart. Without this the warren becomes a mesh, the
            # corridor test rejects nearly every lot, and the district comes
            # out as all footpath and no houses. Skipped for the first couple
            # of steps because a branch is seeded ON an existing alley.
            if i >= 2 and crowded(q):
                break
            pts.append(q)
            p = q
            if depth < 3 and rng.random() < 0.15 and budget > 6:
                grow(p, head + rng.choice((-1.0, 1.0)) * rng.uniform(0.7, 1.3),
                     depth + 1, max(4, budget // 2))
        if len(pts) > 2:
            alleys.append(pts)
            segs.extend((a[0], a[1], b[0], b[1]) for a, b in zip(pts, pts[1:]))

    # A few trunks off the mouth: one walk can dead-end early against the
    # clearance mask and leave the district with a stub for a spine.
    for k in range(3):
        grow(entry, math.radians(heading) + rng.uniform(-0.9, 0.9), 0, 34)

    # Secondary growth is seeded from points ALREADY on the network, never from
    # free-floating grid points. Grid seeds grow their own islands, and since
    # unreachable alleys get dropped, whole districts came out with one alley
    # and 17 discarded.
    for _ in range(13):
        if not alleys:
            break
        poly = alleys[rng.randrange(len(alleys))]
        p = poly[rng.randrange(len(poly))]
        grow(p, rng.uniform(0.0, math.tau), 1, 20)
    return alleys


def seg_point_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    if L <= 1e-9:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L))
    return math.hypot(px - (ax + dx * t), py - (ay + dy * t))


def obb_corners(cx, cy, w, d, yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    hx, hy = w * 0.5, d * 0.5
    return [(cx + x * c - y * s, cy + x * s + y * c)
            for x, y in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy))]


def obb_overlap(a, b):
    """Separating-axis test. Touching counts as clear, so party walls can meet."""
    for poly in (a, b):
        for i in range(4):
            ax, ay = poly[i]
            bx, by = poly[(i + 1) % 4]
            nx, ny = -(by - ay), bx - ax
            L = math.hypot(nx, ny)
            if L < 1e-9:
                continue
            nx, ny = nx / L, ny / L
            amin = min(nx * p[0] + ny * p[1] for p in a)
            amax = max(nx * p[0] + ny * p[1] for p in a)
            bmin = min(nx * p[0] + ny * p[1] for p in b)
            bmax = max(nx * p[0] + ny * p[1] for p in b)
            if amax <= bmin + 1e-6 or bmax <= amin + 1e-6:
                return False
    return True


def polyline_points(poly, spacing):
    out = []
    for a, b in zip(poly, poly[1:]):
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        head = math.atan2(b[1] - a[1], b[0] - a[0])
        n = max(1, int(seg / spacing))
        for i in range(n):
            t = i / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, head))
    return out


def alley_corridors(alleys):
    """Each alley segment as a walkable box, for exact overlap tests.

    Segments alone are not enough. Where an alley bends, the union of the two
    segment rectangles leaves the outside of the corner uncovered, and a house
    can sit in that notch and pinch the turn shut. So every vertex also gets a
    box of its own.
    """
    out = []
    for poly in alleys:
        for p in poly:
            out.append({
                "mid": (p[0], p[1]), "reach": CORRIDOR_HALF * 1.5,
                "obb": obb_corners(p[0], p[1], CORRIDOR_HALF * 2.0,
                                   CORRIDOR_HALF * 2.0, 0.0),
            })
        for a, b in zip(poly, poly[1:]):
            mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            length = math.hypot(b[0] - a[0], b[1] - a[1])
            if length < 1e-6:
                continue
            head = math.atan2(b[1] - a[1], b[0] - a[0])
            out.append({
                "mid": (mx, my), "reach": length * 0.5 + ALLEY_HALF,
                "obb": obb_corners(mx, my, length, CORRIDOR_HALF * 2.0, head),
            })
    return out


def try_lot(rng, lots, corridors, blocked, bounds, cx, cy, w, d, yaw):
    """Accept a lot if it is inside, clear, off the footpaths and unoccupied."""
    corners = obb_corners(cx, cy, w, d, yaw)
    if not inside((cx, cy), bounds) or not all(inside(c, bounds) for c in corners):
        return None
    if any(blocked(c[0], c[1]) for c in corners):
        return None
    for lot in lots:
        if obb_overlap(corners, lot["corners"]):
            return None
    # Box-vs-box against the walkable corridor, not point sampling: a house can
    # straddle an alley with all four corners and its centre outside the
    # corridor while an edge cuts straight across it, which walls the player in.
    reach = math.hypot(w, d) * 0.5
    for c in corridors:
        if math.hypot(c["mid"][0] - cx, c["mid"][1] - cy) > reach + c["reach"]:
            continue
        if obb_overlap(corners, c["obb"]):
            return None
    return {
        "x": cx, "y": cy, "w": w, "d": d, "yaw": yaw,
        "bays": max(1, int(round(w / MODULE))),
        "storeys": 1 if rng.random() < 0.62 else 2,
        "corners": corners,
        "paint": rng.randrange(len(PAINTS)),
        "roof": rng.randrange(len(ROOFS)),
    }


def place_lots(rng, alleys, blocked, bounds):
    """Pack lots along both sides of every alley, zero setback."""
    lots = []
    segs = [(a[0], a[1], b[0], b[1]) for poly in alleys for a, b in zip(poly, poly[1:])]
    corridors = alley_corridors(alleys)

    for poly in alleys:
        for side in (1.0, -1.0):
            cursor = rng.uniform(0.0, 2.0)
            walk = polyline_points(poly, 0.5)
            total = len(walk) * 0.5
            while cursor < total - 1.0:
                bays = 1 if rng.random() < 0.55 else 2
                w = bays * MODULE
                d = rng.uniform(3.2, 6.0)
                idx = int((cursor + w * 0.5) / 0.5)
                if idx >= len(walk):
                    break
                px, py, head = walk[idx]
                nx, ny = -math.sin(head), math.cos(head)
                # clear the corridor by however far the yaw jitter can swing a
                # corner of a house this wide, or the frontage all gets rejected
                off = ALLEY_HALF + d * 0.5 + w * 0.5 * math.sin(YAW_JITTER)
                cx = px + side * nx * off
                cy = py + side * ny * off
                yaw = head + rng.uniform(-YAW_JITTER, YAW_JITTER)
                if side < 0.0:
                    yaw += math.pi
                lot = try_lot(rng, lots, corridors, blocked, bounds, cx, cy, w, d, yaw)
                if lot is not None:
                    lots.append(lot)
                    # near-zero gap: neighbours share party walls, which is what
                    # makes a settlement read as packed rather than scattered
                    cursor += w + rng.uniform(0.0, 0.25)
                else:
                    cursor += 0.35

    # Back-lot infill. Frontage alone covers about a quarter of the block, but
    # real settlements build behind the alley face too, reached by gaps between
    # houses. Orient each to the nearest alley so they still face something.
    frontage = len(lots)
    x0, y0, x1, y1 = bounds
    for _ in range(9000):
        cx = rng.uniform(x0 + 2.0, x1 - 2.0)
        cy = rng.uniform(y0 + 2.0, y1 - 2.0)
        if blocked(cx, cy):
            continue
        best, best_d = None, 1e9
        for s in segs:
            dd = seg_point_dist(cx, cy, *s)
            if dd < best_d:
                best_d, best = dd, s
        if best is None or best_d > 21.0:
            continue
        head = math.atan2(best[3] - best[1], best[2] - best[0])
        yaw = head + rng.choice((0.0, math.pi)) + rng.uniform(-0.12, 0.12)
        w = (1 if rng.random() < 0.6 else 2) * MODULE
        lot = try_lot(rng, lots, corridors, blocked, bounds, cx, cy, w,
                      rng.uniform(3.0, 5.4), yaw)
        if lot is not None:
            lots.append(lot)
    return lots, frontage, corridors


# ---------------------------------------------------------------------------
# House assembly
# ---------------------------------------------------------------------------

def add_piece(batch, piece, cx, cy, cz, yaw, mats, paint, scale):
    verts = xform(piece["verts"], cx, cy, cz, yaw, scale, scale, scale)
    for kit_mat, faces in piece["groups"].items():
        role = KIT_ROLE.get(kit_mat)
        batch.add(verts, faces, mats[role] if role else paint)


def add_graffiti(batch, mat, cx, cy, yaw, wall_w, wall_y, z0, height, rng):
    """A tag decal standing off the wall face, UV'd into one atlas cell."""
    tw = min(wall_w * 0.82, rng.uniform(1.0, 1.9))
    th = min(height * 0.55, tw * rng.uniform(0.45, 0.72))
    bz = z0 + rng.uniform(0.25, max(0.3, height - th - 0.25))
    ox = rng.uniform(-(wall_w - tw) * 0.5, (wall_w - tw) * 0.5)
    y = wall_y - 0.03                       # stand off, or it z-fights the wall
    a = tw * 0.5
    local = [(ox - a, y, bz), (ox + a, y, bz), (ox + a, y, bz + th), (ox - a, y, bz + th)]
    step = 1.0 / ATLAS_CELLS
    ci, cj = rng.randrange(ATLAS_CELLS), rng.randrange(ATLAS_CELLS)
    u0, v0 = ci * step, cj * step
    uvs = [(u0, v0), (u0 + step, v0), (u0 + step, v0 + step), (u0, v0 + step)]
    batch.add(xform(local, cx, cy, 0.0, yaw), [(0, 1, 2, 3)], mat, uvs)


def build_house(batch, roofbatch, decals, lot, pieces, mats, rng, kit_chance,
                graffiti):
    w, d, yaw = lot["w"], lot["d"], lot["yaw"]
    cx, cy = lot["x"], lot["y"]
    paint = mats[PAINTS[lot["paint"]][0]]
    storey = MODULE
    height = lot["storeys"] * storey
    faces_before = len(batch.faces)

    # blank walls as thin boxes: solid for the -col trimesh collider
    t = 0.14
    for (ox, oy, bw, bd) in (
            (0.0, d * 0.5 - t * 0.5, w, t),          # back
            (-w * 0.5 + t * 0.5, 0.0, t, d),         # left
            (w * 0.5 - t * 0.5, 0.0, t, d)):         # right
        v, f = box(bw, bd, height)
        batch.add(xform(v, cx + ox * math.cos(yaw) - oy * math.sin(yaw),
                        cy + ox * math.sin(yaw) + oy * math.cos(yaw),
                        0.0, yaw), f, paint)

    # Front wall. Kit modules are expensive (83-192 faces against 6 for a box),
    # so `kit_chance` decides how often a bay spends one; the ground-floor door
    # bay always does when the district is kitted at all.
    front_y = -d * 0.5 + t * 0.5
    for s in range(lot["storeys"]):
        for b in range(lot["bays"]):
            bx = (b - (lot["bays"] - 1) * 0.5) * storey
            wx = cx + bx * math.cos(yaw) - front_y * math.sin(yaw)
            wy = cy + bx * math.sin(yaw) + front_y * math.cos(yaw)
            name = None
            if rng.random() < kit_chance:
                if s == 0 and b == 0:
                    name = "wall -door 1"
                elif s == 0 or b == 0:
                    name = rng.choice(WINDOW_MODULES)
            if name is None:
                v, f = box(storey, t, storey)
                batch.add(xform(v, wx, wy, s * storey, yaw), f, paint)
                continue
            piece = pieces[name]
            scale = storey / max(piece["width"], piece["height"], 1e-6)
            add_piece(batch, piece, wx, wy, s * storey, yaw, mats, paint, scale)

    if graffiti is not None and rng.random() < GRAFFITI_CHANCE:
        add_graffiti(decals, graffiti, cx, cy, yaw, w, -d * 0.5, 0.0, height, rng)

    # corrugated shed roof, overhanging, leaning a random way
    over = rng.uniform(0.3, 0.6)
    rise = rng.uniform(0.25, 0.7)
    zf, zb = ((height, height + rise) if rng.random() < 0.5
              else (height + rise, height))
    v, f = corrugated(w + over * 2.0, d + over * 2.0, zf, zb)
    roofbatch.add(xform(v, cx, cy, 0.0, yaw + rng.uniform(-0.05, 0.05)), f,
                  mats[ROOFS[lot["roof"]][0]])
    return len(batch.faces) - faces_before


def build_alley_ground(batch, alleys, mats):
    """Packed-dirt path under the footpaths so the eskinita reads.

    Rasterised into unique cells rather than emitted as one quad per segment:
    alleys cross and overlap constantly, and coincident coplanar quads z-fight.
    Stacking them on staggered z instead just turns the path into a visible
    patchwork of stepped plates. A cell set can only ever emit each patch once.
    """
    cells = set()
    reach = int(ALLEY_HALF / GROUND_CELL) + 1
    for poly in alleys:
        for a, b in zip(poly, poly[1:]):
            dist = math.hypot(b[0] - a[0], b[1] - a[1])
            steps = max(1, int(dist / (GROUND_CELL * 0.5)))
            for s in range(steps + 1):
                t = s / steps
                px = a[0] + (b[0] - a[0]) * t
                py = a[1] + (b[1] - a[1]) * t
                bi, bj = math.floor(px / GROUND_CELL), math.floor(py / GROUND_CELL)
                for j in range(bj - reach, bj + reach + 1):
                    for i in range(bi - reach, bi + reach + 1):
                        cx, cy = (i + 0.5) * GROUND_CELL, (j + 0.5) * GROUND_CELL
                        if (cx - px) ** 2 + (cy - py) ** 2 <= ALLEY_HALF ** 2:
                            cells.add((i, j))
    h = GROUND_CELL * 0.5
    for i, j in sorted(cells):
        cx, cy = (i + 0.5) * GROUND_CELL, (j + 0.5) * GROUND_CELL
        v, f = quad([(cx - h, cy - h), (cx + h, cy - h),
                     (cx + h, cy + h), (cx - h, cy + h)], 0.03)
        batch.add(v, f, mats["Slum_Dirt"])


# ---------------------------------------------------------------------------

def reachable_alleys(alleys, entry):
    """Indices of alleys walkable from the mouth."""
    pts = [(ai, p) for ai, poly in enumerate(alleys) for p in poly]
    seen, stack = set(), []
    for idx, (_, p) in enumerate(pts):
        if math.hypot(p[0] - entry[0], p[1] - entry[1]) < 1.0:
            stack.append(idx)
            seen.add(idx)
    while stack:
        cur = stack.pop()
        cai, cp = pts[cur]
        for idx, (ai, p) in enumerate(pts):
            if idx in seen:
                continue
            if math.hypot(p[0] - cp[0], p[1] - cp[1]) < 4.6 or (
                    ai == cai and abs(idx - cur) == 1):
                seen.add(idx)
                stack.append(idx)
    return {pts[i][0] for i in seen}


def verify(name, lots, alleys, corridors, entry):
    """Fail the build rather than ship a district the player can get stuck in."""
    for i, a in enumerate(lots):
        for b in lots[i + 1:]:
            if obb_overlap(a["corners"], b["corners"]):
                raise RuntimeError("{:s}: houses overlap at ({:.1f},{:.1f})"
                                   .format(name, a["x"], a["y"]))
    for lot in lots:
        reach = math.hypot(lot["w"], lot["d"]) * 0.5
        for c in corridors:
            if math.hypot(c["mid"][0] - lot["x"], c["mid"][1] - lot["y"]) > reach + c["reach"]:
                continue
            if obb_overlap(lot["corners"], c["obb"]):
                raise RuntimeError("{:s}: house blocks an alley at ({:.1f},{:.1f})"
                                   .format(name, lot["x"], lot["y"]))
    orphans = set(range(len(alleys))) - reachable_alleys(alleys, entry)
    if orphans:
        raise RuntimeError("{:s}: {:d} alleys unreachable".format(name, len(orphans)))


def make_materials():
    mats = {}
    table = dict(PAINTS) | dict(ROOFS) | EXTRA
    for name, srgb in table.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        linear = tuple(srgb_to_linear(c) for c in srgb)
        bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
        if name in ("Slum_Metal", "Slum_Galv"):
            bsdf.inputs["Metallic"].default_value = 0.35
            bsdf.inputs["Roughness"].default_value = 0.6
        elif name == "Slum_Glass":
            bsdf.inputs["Roughness"].default_value = 0.25
        mat.diffuse_color = (*linear, 1.0)
        mat["intended_srgb"] = list(srgb)
        mats[name] = mat
    return mats


def main():
    rng = random.Random(SEED)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    wanted = sorted(set(KIT_MODULES + WINDOW_MODULES))
    append_kit(wanted)
    pieces = {n: kit_piece(n) for n in wanted}
    mats = make_materials()
    graffiti = graffiti_material(rng)
    if not CEBU_PALETTE:
        log("CEBU_PALETTE off - keeping the kit's own materials")

    walls, roofs, ground, decals = Batch(), Batch(), Batch(), Batch()
    export_alleys = []
    worst = total_lots = 0

    for spec in DISTRICTS:
        bounds = spec["bounds"]
        blocked = build_clearance(bounds)
        entry = find_entry(bounds, spec["entry"], blocked)
        alleys = grow_alleys(rng, blocked, bounds, entry, spec["heading"])
        # Seeded alleys that never joined the network would get lined with
        # houses the player can never reach, so drop them before any lot lands.
        keep = reachable_alleys(alleys, entry)
        dropped = len(alleys) - len(keep)
        alleys = [a for i, a in enumerate(alleys) if i in keep]
        if not alleys:
            raise RuntimeError("{:s}: no alleys grew".format(spec["name"]))

        lots, frontage, corridors = place_lots(rng, alleys, blocked, bounds)
        if not lots:
            raise RuntimeError("{:s}: no lots placed".format(spec["name"]))
        verify(spec["name"], lots, alleys, corridors, entry)

        for lot in lots:
            cost = build_house(walls, roofs, decals, lot, pieces, mats, rng,
                               spec["kit"], graffiti)
            worst = max(worst, cost)
            if cost > FACE_CAP_PER_HOUSE:
                raise RuntimeError("{:s}: house cost {:d} faces, cap {:d}"
                                   .format(spec["name"], cost, FACE_CAP_PER_HOUSE))
        build_alley_ground(ground, alleys, mats)

        total_lots += len(lots)
        export_alleys.append({
            "name": spec["name"],
            "entry": [entry[0], 0.0, -entry[1]],
            "bounds_godot": [bounds[0], -bounds[3], bounds[2], -bounds[1]],
            "alleys": [[[p[0], -p[1]] for p in poly] for poly in alleys],
        })
        log("{:<16s} kit={:.2f}  {:3d} houses ({:d} frontage)  {:2d} alleys"
            " ({:d} dropped)".format(spec["name"], spec["kit"], len(lots),
                                     frontage, len(alleys), dropped))

    # drop the appended kit originals; only the batched copies ship
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    objs = [walls.to_object("Slum_Walls-col"),
            roofs.to_object("Slum_Roofs"),
            decals.to_object("Slum_Graffiti"),
            ground.to_object("Slum_Ground")]
    counts = [len(o.data.polygons) for o in objs]
    total = sum(counts)
    log("{:d} houses in {:d} districts".format(total_lots, len(DISTRICTS)))
    log("faces: walls {:d}  roofs {:d}  tags {:d}  ground {:d}  total {:d}"
        " (worst house {:d})".format(*counts, total, worst))
    if total > FACE_BUDGET:
        raise RuntimeError("face budget blown: {:d} > {:d}".format(total, FACE_BUDGET))

    OUTPUT_ALLEYS.write_text(json.dumps({
        "width": ALLEY_HALF * 2.0,
        "districts": export_alleys,
    }, indent=1), encoding="utf-8")
    log("wrote {:s}".format(OUTPUT_ALLEYS.name))

    OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
    )
    log("wrote {:s} ({:.2f} MB)".format(
        OUTPUT_GLB.name, OUTPUT_GLB.stat().st_size / 1048576.0))
    log("DONE")


main()
