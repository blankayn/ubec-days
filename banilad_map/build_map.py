"""
Build a detailed 3D city of Banilad, Cebu City from OpenStreetMap data.

Rather than extruding flat-topped boxes, this generates the forms that actually
make up the district: hip-roofed low-rise with terracotta and painted metal
roofs, parapeted commercial blocks with window bands, glazed towers, kerbed
sidewalks, painted road markings, street lighting, power poles, trees and
parked vehicles.

Run headlessly:
    blender --background --python build_map.py
"""

import json
import math
import pathlib
import random
import sys

import bpy

HERE = pathlib.Path(__file__).parent
OSM_FILE = HERE / "banilad_osm.json"
OUT_DIR = HERE / "export"

# Centre of the captured area, used as the local origin (0, 0, 0).
LAT0 = 10.3345
LON0 = 123.9115

# Large enough to hold the whole Overpass bbox, whose south edge now reaches
# past Cebu IT Park (the southernmost building sits at about y = -1173).
GROUND_HALF = 1250.0
METRES_PER_DEG_LAT = 110574.0
METRES_PER_DEG_LON = 111320.0 * math.cos(math.radians(LAT0))

LEVEL_HEIGHT = 3.3
SEED = 20260731

DEFAULT_HEIGHTS = {
    "yes": 6.0, "house": 4.5, "residential": 7.0, "apartments": 18.0,
    "commercial": 14.0, "retail": 9.0, "office": 20.0, "hotel": 22.0,
    "university": 14.0, "school": 10.0, "warehouse": 8.0, "industrial": 9.0,
    "church": 12.0, "roof": 3.5, "tent": 3.0, "terrace": 6.0,
    "construction": 8.0, "garage": 3.0, "hut": 3.0,
}

ROAD_WIDTHS = {
    "primary": 16.0, "secondary": 13.0, "secondary_link": 8.0,
    "tertiary": 10.0, "tertiary_link": 7.0, "unclassified": 7.5,
    "residential": 6.5, "service": 4.0, "living_street": 6.0,
    "pedestrian": 5.0, "footway": 2.0, "path": 1.6, "steps": 1.6,
    "track": 3.0,
}

MAJOR_ROADS = {"primary", "secondary", "secondary_link", "tertiary", "tertiary_link"}
FOOT_ROADS = {"footway", "path", "steps", "pedestrian"}
GREEN_TAGS = {
    "grass", "forest", "meadow", "village_green", "recreation_ground",
    "park", "garden", "pitch", "golf_course", "cemetery", "farmland",
}

# Zoned districts that must not receive procedural shanty infill. This is what
# keeps houses out of the mall car park and out of the IT Park towers' plazas,
# both of which are mapped as commercial landuse.
NOFILL_TAGS = {
    "commercial", "retail", "industrial", "military", "construction",
    "brownfield", "railway", "quarry",
}

# Draw order. Overlapping features inside a layer are separated by layer_z.
Z_GROUND = 0.0
Z_BUILDING_BASE = 0.0
Z_LANDUSE = 0.02
Z_WATER = -0.60
Z_FOOTWAY = 0.05
Z_ROAD_MINOR = 0.09
Z_ROAD_MAJOR = 0.13
Z_MARKING = 0.17
Z_SIDEWALK = 0.15

# Physics reads one flat plane instead of the layered visual ribbons (see
# Roads_Collision below). Sitting it on the major-road surface keeps cars level
# with the tarmac they mostly drive on: on minor roads they float at most 4 cm,
# on major roads they sink at most 3 cm, neither visible at vehicle scale.
Z_ROAD_COLLISION = Z_ROAD_MAJOR

LAYER_STEP = 0.002
LAYER_SLOTS = 16

SIDEWALK_WIDTH = 2.6
KERB_HEIGHT = 0.15

# Colours are the intended on-screen sRGB values. build_materials converts them
# to linear for Blender; prep_godot.py converts them again for Godot's importer.
PALETTE = {
    "Ground": (0.33, 0.32, 0.28),
    "Landuse_Green": (0.28, 0.42, 0.22),
    "Landuse_Urban": (0.36, 0.35, 0.33),
    "Water": (0.14, 0.30, 0.40),
    "Road_Major": (0.22, 0.22, 0.24),
    "Road_Minor": (0.28, 0.28, 0.30),
    "Footway": (0.46, 0.44, 0.41),
    "Sidewalk": (0.52, 0.51, 0.48),
    "Marking_White": (0.86, 0.86, 0.83),
    "Marking_Yellow": (0.80, 0.66, 0.20),

    # Low-rise walls. The aerial shows mostly unpainted or long-faded hollow
    # block, so these run grey and weathered rather than fresh pastel.
    "Wall_0": (0.72, 0.70, 0.65),
    "Wall_1": (0.62, 0.61, 0.58),
    "Wall_2": (0.68, 0.65, 0.58),
    "Wall_3": (0.55, 0.55, 0.53),
    "Wall_4": (0.65, 0.64, 0.62),
    "Wall_5": (0.58, 0.57, 0.52),
    "Wall_6": (0.50, 0.50, 0.48),
    "Wall_Concrete_0": (0.64, 0.63, 0.60),
    "Wall_Concrete_1": (0.56, 0.56, 0.54),
    "Wall_Concrete_2": (0.70, 0.70, 0.68),

    # Tower cladding. Read off the reference aerial of IT Park: the district is
    # white and pale grey concrete with charcoal glass towers among it. There is
    # essentially no saturated blue there, so these stay neutral -- a cool tint
    # in the glazing was what made the whole skyline read blue.
    "Tower_White": (0.81, 0.81, 0.80),
    "Tower_Pale": (0.72, 0.72, 0.71),
    "Tower_Concrete": (0.62, 0.62, 0.60),
    "Tower_Steel": (0.46, 0.47, 0.49),
    "Tower_Graphite": (0.30, 0.31, 0.33),
    "Tower_Charcoal": (0.19, 0.20, 0.22),
    # Glazing, paired with the cladding below so the banding always contrasts.
    "Tower_Glass_Dark": (0.21, 0.22, 0.24),   # punched windows on pale concrete
    "Tower_Glass_Mid": (0.35, 0.36, 0.38),
    "Tower_Glass_Pale": (0.63, 0.64, 0.65),   # lit glazing on charcoal cladding

    # Roofs. The dense barangay fabric is roughly half faded galvanised sheet
    # and half oxidised red, with only occasional painted colour -- the bright
    # terracotta-and-teal mix this used to ship read as a map key, not a city.
    "Roof_Rust_0": (0.45, 0.24, 0.18),
    "Roof_Rust_1": (0.52, 0.30, 0.22),
    "Roof_Rust_2": (0.38, 0.21, 0.17),
    "Roof_Galv_0": (0.56, 0.56, 0.54),
    "Roof_Galv_1": (0.47, 0.48, 0.48),
    "Roof_Galv_2": (0.63, 0.62, 0.59),
    "Roof_Galv_3": (0.52, 0.53, 0.52),
    "Roof_Weathered": (0.66, 0.64, 0.60),
    "Roof_Paint_Blue": (0.31, 0.39, 0.45),
    "Roof_Paint_Green": (0.30, 0.38, 0.31),
    "Roof_Clay": (0.55, 0.30, 0.21),
    "Roof_Flat": (0.46, 0.45, 0.43),
    "Roof_Deck": (0.40, 0.40, 0.39),

    "Window": (0.12, 0.16, 0.20),
    "Pole": (0.34, 0.34, 0.33),
    "Lamp": (0.85, 0.82, 0.66),
    "Tree_Trunk": (0.26, 0.19, 0.13),
    "Tree_Canopy_0": (0.20, 0.36, 0.16),
    "Tree_Canopy_1": (0.26, 0.42, 0.20),
    "Tree_Canopy_2": (0.16, 0.30, 0.14),
    "Car_0": (0.72, 0.72, 0.70),
    "Car_1": (0.55, 0.13, 0.13),
    "Car_2": (0.16, 0.28, 0.46),
    "Car_3": (0.20, 0.20, 0.22),
    "Car_4": (0.66, 0.62, 0.18),

    # Hand-authored landmarks. These two are the only buildings the player is
    # meant to recognise, so they get their own palette instead of the
    # procedural wall/roof rotations.
    "Mall_Wall": (0.86, 0.82, 0.72),        # cream stucco
    "Mall_Trim": (0.93, 0.91, 0.85),        # cornice and pier caps
    "Mall_Arcade": (0.34, 0.30, 0.26),      # shadow inside the arch openings
    # Clay tile. Three tones so the complex does not read as one flat slab of
    # colour, and pulled back from the old orange so it sits with the muted
    # galvanised roofs around it instead of glowing against them.
    "Mall_Roof": (0.56, 0.29, 0.19),
    "Mall_Roof_Alt": (0.50, 0.27, 0.19),
    "Mall_Roof_Dark": (0.44, 0.23, 0.17),   # cineplex block, shaded slopes
    "Mall_Walkway": (0.74, 0.37, 0.20),     # covered walkway spine roof
    "Lot_Asphalt": (0.27, 0.26, 0.25),
    "Lot_Stripe": (0.78, 0.77, 0.71),

    "UC_Band": (0.85, 0.85, 0.83),          # pale concrete structural bands
    # Neutral grey-blue, not saturated: on the reference the campus reads as a
    # pale concrete block with dark glazing, and a brighter blue turned the
    # banding into painted stripes.
    "UC_Glass": (0.31, 0.36, 0.41),         # bowed curtain wall
    "UC_Glass_Dark": (0.22, 0.26, 0.30),    # courtyard-facing glazing
    "UC_Podium": (0.76, 0.75, 0.71),
    "UC_Deck": (0.44, 0.44, 0.42),

    # Cebu IT Park. Office towers all share the base/crown/plant treatment;
    # the Central Bloc complex gets its own cladding colours.
    "Tower_Base": (0.33, 0.33, 0.36),       # darker podium storeys
    "Tower_Crown": (0.28, 0.30, 0.35),      # capping band under the parapet
    "Tower_Plant": (0.38, 0.38, 0.40),      # rooftop plant and lift overruns
    "Bloc_Podium": (0.47, 0.37, 0.39),      # Ayala Malls mauve cladding
    "Bloc_Sign": (0.86, 0.63, 0.28),        # lit signage band
    "Bloc_Tower_Dark": (0.21, 0.23, 0.27),  # Corporate Center One
    "Bloc_Tower_Light": (0.66, 0.67, 0.68), # Corporate Center Two
    "Bloc_Hotel": (0.63, 0.59, 0.55),       # Seda
}

WALL_LOW = ["Wall_0", "Wall_1", "Wall_2", "Wall_3", "Wall_4", "Wall_5", "Wall_6"]
WALL_MID = ["Wall_Concrete_0", "Wall_Concrete_1", "Wall_Concrete_2"]

# Tower cladding paired with its glazing. Picking the two independently let a
# concrete tower end up with concrete-coloured "glass", which erased the
# banding; keeping them as schemes guarantees the curtain wall reads.
# Weighted the way the reference reads: mostly pale concrete with dark punched
# windows, charcoal glass towers standing among them, mid greys in between.
TOWER_SCHEMES = [
    ("Tower_White", "Tower_Glass_Dark"),
    ("Tower_Charcoal", "Tower_Glass_Pale"),
    ("Tower_Pale", "Tower_Glass_Dark"),
    ("Tower_Concrete", "Tower_Glass_Dark"),
    ("Tower_White", "Tower_Glass_Mid"),
    ("Tower_Graphite", "Tower_Glass_Pale"),
    ("Tower_Pale", "Tower_Glass_Mid"),
    ("Tower_Steel", "Tower_Glass_Dark"),
]

# Towers identifiable by label in the reference aerial of IT Park, so their
# cladding is set rather than left to the scheme rotation. Everything not
# listed here keeps the rotation -- guessing at the rest would be inventing
# detail, not adding accuracy.
TOWER_SCHEME_BY_NAME = {
    "Skyrise 1": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Skyrise 2": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Skyrise 3": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Skyrise 3B": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Skyrise 4": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Avida Towers Cebu": ("Tower_White", "Tower_Glass_Mid"),
    "Metro Park Hotel": ("Tower_White", "Tower_Glass_Mid"),
}

# Roof mix measured off the reference aerial of the barangay behind UC: faded
# galvanised sheet and oxidised red in roughly equal share, everything else
# occasional. Repeats set the weighting.
ROOF_PITCHED = [
    "Roof_Rust_0", "Roof_Rust_1", "Roof_Rust_2", "Roof_Rust_0", "Roof_Rust_1",
    "Roof_Galv_0", "Roof_Galv_1", "Roof_Galv_2", "Roof_Galv_3",
    "Roof_Galv_0", "Roof_Galv_1",
    "Roof_Weathered", "Roof_Weathered",
    "Roof_Paint_Blue", "Roof_Paint_Green", "Roof_Clay",
]
CAR_COLOURS = ["Car_0", "Car_1", "Car_2", "Car_3", "Car_4"]
CANOPY_COLOURS = ["Tree_Canopy_0", "Tree_Canopy_1", "Tree_Canopy_2"]

# A pitched roof only suits house-and-shophouse scale. Big commercial sheds
# such as Gaisano are low but wide, and in reality carry flat or very shallow
# roofs, so they are excluded by footprint area rather than by height alone.
PITCHED_ROOF_MAX = 11.0
PITCHED_ROOF_MAX_AREA = 700.0

# OpenStreetMap only maps a fraction of Banilad's houses, which leaves most
# blocks as bare ground. Infill fills the gaps with small hip-roofed dwellings
# so the density reads like the real district. Bounds are the playable core.
INFILL_BOUNDS = (-720.0, -120.0, 720.0, 1060.0)
INFILL_SPACING = 13.0
INFILL_LIMIT = 3200
INFILL_ROAD_CLEARANCE = 4.0     # metres beyond the carriageway edge
INFILL_ROAD_MAX_DISTANCE = 60.0  # houses cluster along streets
INFILL_BUILDING_CLEARANCE = 7.0
INFILL_WATER_CLEARANCE = 8.0


def log(msg):
    print("[city] {:s}".format(msg))
    sys.stdout.flush()


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def project(lat, lon):
    return ((lon - LON0) * METRES_PER_DEG_LON, (lat - LAT0) * METRES_PER_DEG_LAT)


def way_points(el):
    geom = el.get("geometry")
    if not geom:
        return []
    return [project(p["lat"], p["lon"]) for p in geom if p]


def is_closed(pts):
    return len(pts) >= 4 and math.dist(pts[0], pts[-1]) < 0.5


def signed_area(pts):
    total = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        total += x0 * y1 - x1 * y0
    return total * 0.5


def dedupe(pts, eps=0.05):
    out = []
    for p in pts:
        if not out or math.dist(out[-1], p) > eps:
            out.append(p)
    return out


def layer_z(base, index):
    return base + (index % LAYER_SLOTS) * LAYER_STEP


def convex_hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2:
                ax, ay = out[-1][0] - out[-2][0], out[-1][1] - out[-2][1]
                bx, by = p[0] - out[-2][0], p[1] - out[-2][1]
                if ax * by - ay * bx <= 0:
                    out.pop()
                else:
                    break
            out.append(p)
        return out

    return half(pts)[:-1] + half(reversed(pts))[:-1]


def min_area_rect(points):
    """Smallest-area oriented bounding rectangle, via rotating calipers.

    Returns (centre, axis_u, half_u, half_v) where axis_u is a unit vector
    along the rectangle's longer side.
    """
    hull = convex_hull(points)
    if len(hull) < 3:
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        cx, cy = (min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5
        return (cx, cy), (1.0, 0.0), max(0.5, (max(xs) - min(xs)) * 0.5), \
            max(0.5, (max(ys) - min(ys)) * 0.5)

    best = None
    for i in range(len(hull)):
        x0, y0 = hull[i]
        x1, y1 = hull[(i + 1) % len(hull)]
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy)
        if length < 1e-9:
            continue
        ux, uy = dx / length, dy / length
        vx, vy = -uy, ux

        us = [p[0] * ux + p[1] * uy for p in hull]
        vs = [p[0] * vx + p[1] * vy for p in hull]
        area = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or area < best[0]:
            cu = (max(us) + min(us)) * 0.5
            cv = (max(vs) + min(vs)) * 0.5
            best = (
                area,
                (cu * ux + cv * vx, cu * uy + cv * vy),
                (ux, uy),
                (max(us) - min(us)) * 0.5,
                (max(vs) - min(vs)) * 0.5,
            )

    _, centre, axis, half_u, half_v = best
    if half_v > half_u:
        axis = (-axis[1], axis[0])
        half_u, half_v = half_v, half_u
    return centre, axis, max(half_u, 0.5), max(half_v, 0.5)


def miter_offsets(pts, half):
    """Per-point offset vectors that keep a strip a constant width."""
    def normal(p0, p1):
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        length = math.hypot(dx, dy)
        if length < 1e-9:
            return None
        return (-dy / length, dx / length)

    n = len(pts)
    offsets = []
    for i, p in enumerate(pts):
        if i == 0:
            nrm = normal(pts[0], pts[1])
            off = None if nrm is None else (nrm[0] * half, nrm[1] * half)
        elif i == n - 1:
            nrm = normal(pts[-2], pts[-1])
            off = None if nrm is None else (nrm[0] * half, nrm[1] * half)
        else:
            n0, n1 = normal(pts[i - 1], p), normal(p, pts[i + 1])
            if n0 is None or n1 is None:
                off = None
            else:
                mx, my = n0[0] + n1[0], n0[1] + n1[1]
                mlen = math.hypot(mx, my)
                if mlen < 1e-6:
                    off = (n0[0] * half, n0[1] * half)
                else:
                    mx, my = mx / mlen, my / mlen
                    scale = max(0.35, mx * n0[0] + my * n0[1])
                    off = (mx * half / scale, my * half / scale)
        if off is None:
            off = offsets[-1] if offsets else (0.0, half)
        offsets.append(off)
    return offsets


def ribbon(pts, width, z):
    pts = dedupe(pts)
    if len(pts) < 2:
        return [], []
    offsets = miter_offsets(pts, width * 0.5)
    n = len(pts)
    left = [(p[0] + o[0], p[1] + o[1], z) for p, o in zip(pts, offsets)]
    right = [(p[0] - o[0], p[1] - o[1], z) for p, o in zip(pts, offsets)]
    return left + right, [(i, n + i, n + i + 1, i + 1) for i in range(n - 1)]


def raised_ribbon(pts, width, z, height):
    """A strip lifted to `height` with vertical kerb faces down its edges."""
    pts = dedupe(pts)
    if len(pts) < 2:
        return [], []
    offsets = miter_offsets(pts, width * 0.5)
    n = len(pts)
    top_l = [(p[0] + o[0], p[1] + o[1], z + height) for p, o in zip(pts, offsets)]
    top_r = [(p[0] - o[0], p[1] - o[1], z + height) for p, o in zip(pts, offsets)]
    bot_l = [(v[0], v[1], z) for v in top_l]
    bot_r = [(v[0], v[1], z) for v in top_r]

    verts = top_l + top_r + bot_l + bot_r
    faces = []
    for i in range(n - 1):
        faces.append((i, n + i, n + i + 1, i + 1))                       # top
        faces.append((2 * n + i, i, i + 1, 2 * n + i + 1))               # kerb left
        faces.append((n + i, 3 * n + i, 3 * n + i + 1, n + i + 1))       # kerb right
    return verts, faces


def offset_polyline(pts, distance):
    pts = dedupe(pts)
    if len(pts) < 2:
        return []
    offsets = miter_offsets(pts, abs(distance))
    sign = 1.0 if distance >= 0 else -1.0
    return [(p[0] + o[0] * sign, p[1] + o[1] * sign) for p, o in zip(pts, offsets)]


def polyline_arc_table(pts):
    table = [0.0]
    for i in range(len(pts) - 1):
        table.append(table[-1] + math.dist(pts[i], pts[i + 1]))
    return table


def point_at_arc(pts, table, s):
    for i in range(len(pts) - 1):
        if s <= table[i + 1] or i == len(pts) - 2:
            span = table[i + 1] - table[i]
            t = 0.0 if span <= 1e-9 else (s - table[i]) / span
            t = min(1.0, max(0.0, t))
            a, b = pts[i], pts[i + 1]
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    return pts[-1]


def sub_polyline(pts, table, s0, s1):
    """The piece of a polyline between two arc lengths, original corners kept."""
    out = [point_at_arc(pts, table, s0)]
    for i in range(1, len(pts) - 1):
        if s0 < table[i] < s1:
            out.append(pts[i])
    out.append(point_at_arc(pts, table, s1))
    return dedupe(out)


def on_other_carriageway(x, y, index, way_index, margin):
    for p0, p1, half, owner in index.near(x, y):
        if owner == way_index:
            continue
        distance, _ = point_segment_distance(x, y, p0, p1)
        if distance <= half + margin:
            return True
    return False


def clip_against_carriageways(line, index, way_index, margin,
                              step=1.5, min_run=2.5):
    """Break a polyline wherever it runs over another road's tarmac.

    Sidewalks and lane markings are generated along a way's whole length, so
    at a junction they carry straight over the crossing road. For a sidewalk
    that means a kerbed slab lying across the carriageway -- a step the car
    hits, not just something that looks wrong.

    `margin` is how far the feature reaches either side of the line being
    tested, so a sidewalk clears the tarmac by its own half-width rather than
    stopping with half of itself still over the road. Runs shorter than
    `min_run` are dropped as slivers.
    """
    pts = dedupe(line)
    if len(pts) < 2:
        return []
    table = polyline_arc_table(pts)
    total = table[-1]
    if total <= 1e-6:
        return []

    steps = max(1, int(math.ceil(total / step)))
    runs = []
    start = None
    last = 0.0
    for k in range(steps + 1):
        s = total * k / steps
        px, py = point_at_arc(pts, table, s)
        if on_other_carriageway(px, py, index, way_index, margin):
            if start is not None and last - start >= min_run:
                runs.append((start, last))
            start = None
        else:
            if start is None:
                start = s
            last = s
    if start is not None and last - start >= min_run:
        runs.append((start, last))

    # Nothing crossed it: hand back the original vertices rather than a
    # resampled copy, so untouched streets keep their original vertex count.
    if len(runs) == 1 and runs[0][0] <= 1e-6 and runs[0][1] >= total - 1e-6:
        return [pts]
    return [sub_polyline(pts, table, a, b) for a, b in runs]


def offset_ring(pts, distance):
    """Offset a closed ring, mitring every corner including the seam.

    offset_polyline works on an open polyline, so feeding it `ring + [ring[0]]`
    gives the seam vertex a plain perpendicular offset instead of a corner
    mitre and leaves one corner of every ring in the wrong place. Positive
    distance shrinks a counter-clockwise ring, matching offset_polyline.
    """
    ring = dedupe(pts[:-1] if is_closed(pts) else pts)
    n = len(ring)
    if n < 3:
        return []

    def normal(p0, p1):
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        length = math.hypot(dx, dy)
        if length < 1e-9:
            return None
        return (-dy / length, dx / length)

    out = []
    for i, p in enumerate(ring):
        n0 = normal(ring[i - 1], p)
        n1 = normal(p, ring[(i + 1) % n])
        if n0 is None or n1 is None:
            nrm = n0 or n1
            if nrm is None:
                out.append(p)
                continue
            mx, my, scale = nrm[0], nrm[1], 1.0
        else:
            mx, my = n0[0] + n1[0], n0[1] + n1[1]
            length = math.hypot(mx, my)
            if length < 1e-6:          # doubled back on itself
                out.append(p)
                continue
            mx, my = mx / length, my / length
            # The sharper the corner, the further the mitre has to reach.
            # Clamped so a near-spike does not fling the vertex across the map.
            scale = 1.0 / max(0.25, mx * n0[0] + my * n0[1])
        out.append((p[0] + mx * distance * scale, p[1] + my * distance * scale))
    return out


def flat_polygon(pts, z):
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]
    return [(x, y, z) for x, y in pts], [tuple(range(len(pts)))]


def point_in_polygon(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            xint = (x1 - x0) * (y - y0) / (y1 - y0) + x0
            if x < xint:
                inside = not inside
    return inside


def box(cx, cy, z0, z1, half_x, half_y, angle=0.0):
    ca, sa = math.cos(angle), math.sin(angle)
    corners = []
    for dx, dy in ((-half_x, -half_y), (half_x, -half_y), (half_x, half_y), (-half_x, half_y)):
        corners.append((cx + dx * ca - dy * sa, cy + dx * sa + dy * ca))
    verts = [(x, y, z0) for x, y in corners] + [(x, y, z1) for x, y in corners]
    faces = [(3, 2, 1, 0), (4, 5, 6, 7)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((i, j, j + 4, i + 4))
    return verts, faces


# ---------------------------------------------------------------------------
# Building forms
# ---------------------------------------------------------------------------

def walls(pts, base_z, top_z):
    """Vertical wall band around a footprint, open at top and bottom."""
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]
    n = len(pts)
    verts = [(x, y, base_z) for x, y in pts] + [(x, y, top_z) for x, y in pts]
    faces = [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    faces.append(tuple(range(n - 1, -1, -1)))
    return verts, faces


def hip_roof(pts, eave_z, overhang=0.55):
    """Four-sided hip roof over the footprint's oriented bounding box."""
    (cx, cy), (ux, uy), half_u, half_v = min_area_rect(pts)
    vx, vy = -uy, ux
    hu = half_u + overhang
    hv = half_v + overhang
    rise = min(2.4, max(0.9, hv * 0.55))

    def at(du, dv, dz):
        return (cx + ux * du + vx * dv, cy + uy * du + vy * dv, eave_z + dz)

    # Eave corners, then the ridge shortened by the roof's half-width.
    e0 = at(-hu, -hv, 0.0)
    e1 = at(hu, -hv, 0.0)
    e2 = at(hu, hv, 0.0)
    e3 = at(-hu, hv, 0.0)
    ridge = max(0.0, hu - hv)
    r0 = at(-ridge, 0.0, rise)
    r1 = at(ridge, 0.0, rise)

    verts = [e0, e1, e2, e3, r0, r1]
    faces = [
        (0, 1, 5, 4),   # long slope
        (2, 3, 4, 5),   # long slope
        (1, 2, 5),      # hip end
        (3, 0, 4),      # hip end
        (3, 2, 1, 0),   # soffit
    ]
    return verts, faces, rise


def parapet_roof(pts, top_z, parapet=0.85, inset=0.4):
    """Flat roof slab with a raised parapet wall around the edge."""
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]

    # A positive distance shrinks a counter-clockwise ring. This used to pass
    # -inset, which grew it instead, so every flat roof overhung its own walls
    # by `inset` rather than stepping in from them.
    inner = offset_ring(pts, inset)
    if len(inner) != len(pts):
        inner = pts

    n = len(pts)
    verts = []
    verts += [(x, y, top_z) for x, y in inner]                    # slab
    verts += [(x, y, top_z + parapet) for x, y in pts]            # outer top
    verts += [(x, y, top_z + parapet) for x, y in inner]          # inner top

    faces = [tuple(range(n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((n + i, n + j, 2 * n + j, 2 * n + i))        # parapet cap
        faces.append((2 * n + i, 2 * n + j, j, i))                # parapet inner
    return verts, faces


def window_bands(pts, base_z, top_z, floor_height=3.3, band=1.5, bulge=0.06):
    """Recessed glazing bands, one per floor, wrapped around the walls."""
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]

    verts = []
    faces = []
    n = len(pts)
    floor = base_z + 3.6
    guard = 0
    while floor + band < top_z - 0.6 and guard < 40:
        guard += 1
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            dx, dy = x1 - x0, y1 - y0
            length = math.hypot(dx, dy)
            if length < 2.0:
                continue
            # Inset the band a little from each corner so it reads as a window.
            t = min(0.85 / length, 0.3)
            ax, ay = x0 + dx * t, y0 + dy * t
            bx, by = x1 - dx * t, y1 - dy * t
            nx, ny = -dy / length * bulge, dx / length * bulge
            base = len(verts)
            verts += [
                (ax + nx, ay + ny, floor),
                (bx + nx, by + ny, floor),
                (bx + nx, by + ny, floor + band),
                (ax + nx, ay + ny, floor + band),
            ]
            faces.append((base, base + 1, base + 2, base + 3))
        floor += floor_height
    return verts, faces


# ---------------------------------------------------------------------------
# Hand-authored landmarks
#
# UC Banilad and Gaisano Country Mall are the two buildings the player is meant
# to recognise on sight, so they are modelled by hand instead of being extruded
# from their OSM footprints like everything else. OSM has both of them wrong in
# ways that matter: UC is stored as two overlapping C-shaped ways that a naive
# extrude fills in solid, erasing the courtyard, and the mall is a single wing
# with none of the arcade rows, parking court or covered walkway.
#
# Plans below are in local metres and were measured off the OSM ways plus the
# aerial reference. Detail follows the "geometry for silhouette, texture for
# detail" rule: massing, roofs and the courtyard void are real geometry, while
# the arcade arches and curtain-wall mullions are recessed material bands.
# ---------------------------------------------------------------------------

# The corridor's controlling angle. Gov. M. Cuenco Avenue runs at this bearing
# past both landmarks, and every frontage here is parallel to it.
AVENUE_BEARING = math.radians(80.7)
AVENUE_U = (math.cos(AVENUE_BEARING), math.sin(AVENUE_BEARING))

# University of Cebu, stored as two overlapping C-shaped ways that together
# trace the courtyard ring. Their combined extent drives the hand-built block.
UC_WAY_IDS = {132902349, 132902350}

# Gaisano Country Mall. OSM names only the main north bar, but the surveyed
# ring of unnamed arcade strips around the car park is correct and is far more
# accurate than anything traced by eye, so the plan comes from the data and
# only the treatment -- arcade band, clay roof, storey heights -- is authored.
#   way id: (ground floor height, eaves height, arcade tiers)
MALL_WINGS = {
    93839848:   (5.2, 10.6, 2),   # main north bar and west wing (the named one)
    1279791577: (5.2, 10.4, 2),   # central block facing the court
    93839827:   (4.8, 9.2, 2),    # south and west arcade strip
    93839832:   (4.6, 8.8, 2),    # east arcade, surveyed as four segments
    93839836:   (4.6, 8.8, 2),
    93839839:   (4.6, 9.4, 2),
    93839843:   (4.6, 9.4, 2),
    93839855:   (4.4, 7.8, 1),    # west annex
    93839860:   (4.4, 7.4, 1),
}
MALL_WALKWAY_WAY = 93839864    # covered walkway from the avenue into the mall
MALL_PARCEL_WAY = 1364251197   # commercial parcel; its open part is the car park

# The campus block is not covered by any OSM landuse polygon, so infill is kept
# off it explicitly. Padded a few metres beyond the surveyed footprint.
UC_CAMPUS_BLOCK = [(11.0, 409.0), (88.0, 405.0), (94.0, 492.0), (15.0, 497.0)]

UC_LEVELS = 10
UC_LEVEL_HEIGHT = 3.65
UC_WING_DEPTH = 13.5          # depth of the occupied ring around the courtyard
UC_FACADE_BOW = 3.2           # how far the curtain wall bulges toward the avenue

MALL_WALKWAY_HEIGHT = 3.6      # underside of the covered walkway canopy
# Outer face of the scanned mall's entrance bay, in Blender XY. The canopy is
# slid along until its inner end meets this, so it reads as running out of the
# entrance rather than starting beside it. This is the one place the mall
# departs from the surveyed OSM line.
#
# It has to be a constant because the entrance is placed by build_mall.py,
# which runs separately; re-derive it from that script's placement if the
# entrance ever moves.
MALL_WALKWAY_ANCHOR = (-39.33, 522.85)

# --- Cebu IT Park ----------------------------------------------------------
# Ayala Malls Central Bloc opened after the aerial imagery most sources still
# ship, so OSM carries the footprints but almost no heights: both corporate
# towers fall back to the 14 m "commercial" default and vanish from the
# skyline. These heights are read off a night aerial of the finished complex,
# not from OSM, and are the one place in this file where that is true.
CENTRAL_BLOC = {
    # way id: (height, wall material, glazing material or None)
    156416254:  (26.0, "Bloc_Podium", None),            # Ayala Malls podium
    1293810435: (22.0, "Bloc_Podium", None),            # retail wing
    # Corporate Center One is charcoal-clad, so its glazing has to be lighter
    # than the wall or the banding disappears into it.
    1082683047: (70.0, "Bloc_Tower_Dark", "Bloc_Tower_Light"),
    1082683046: (60.0, "Bloc_Tower_Light", "UC_Glass"), # Corporate Center Two
    1323519298: (45.0, "Bloc_Hotel", "UC_Glass_Dark"),  # Seda Central Bloc
}
CENTRAL_BLOC_MALL = 156416254        # the podium that carries the signage band

# Anything at least this tall is treated as an office tower and gets the base,
# crown and rooftop plant that stop it reading as a plain extruded box.
TOWER_MIN_HEIGHT = 26.0
TOWER_BASE_HEIGHT = 7.5

# main() skips all of these in the generic building loop but still records their
# footprints so infill housing keeps clear of them.
LANDMARK_WAY_IDS = (UC_WAY_IDS | set(MALL_WINGS) | {MALL_WALKWAY_WAY}
                    | set(CENTRAL_BLOC))


def oriented_rect(centre, axis, half_u, half_v):
    """Four corners of a rectangle given a centre, a unit axis and half sizes."""
    (cx, cy), (ux, uy) = centre, axis
    vx, vy = -uy, ux
    return [
        (cx - ux * half_u - vx * half_v, cy - uy * half_u - vy * half_v),
        (cx + ux * half_u - vx * half_v, cy + uy * half_u - vy * half_v),
        (cx + ux * half_u + vx * half_v, cy + uy * half_u + vy * half_v),
        (cx - ux * half_u + vx * half_v, cy - uy * half_u + vy * half_v),
    ]


def bow_edge(a, b, bulge, segments=6):
    """Replace a straight edge with an arc bulging to its left by `bulge`."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)
    if length < 1e-6 or abs(bulge) < 1e-6:
        return [a]
    nx, ny = -dy / length, dx / length
    out = []
    for i in range(segments):
        t = i / float(segments)
        # Half-sine gives a shallow, even bow with no kink at the ends.
        k = math.sin(t * math.pi)
        out.append((ax + dx * t + nx * bulge * k, ay + dy * t + ny * bulge * k))
    return out


def inset_in_frame(pts, centre, axis, half_u, half_v, depth):
    """Shrink a footprint by `depth` inside its own oriented bounding box.

    offset_polyline mitres each corner independently, which on a ring with a
    bowed edge folds over at the corners and leaves holes in the roof. Scaling
    in the rectangle's own frame instead is exactly a constant inset for a
    rectangle, keeps the vertex count, and cannot self-intersect while
    `depth` stays under both half sizes.
    """
    (cx, cy), (ux, uy) = centre, axis
    vx, vy = -uy, ux
    if depth >= half_u or depth >= half_v:
        return None
    su = (half_u - depth) / half_u
    sv = (half_v - depth) / half_v
    out = []
    for x, y in pts:
        dx, dy = x - cx, y - cy
        u = (dx * ux + dy * uy) * su
        v = (dx * vx + dy * vy) * sv
        out.append((cx + ux * u + vx * v, cy + uy * u + vy * v))
    return out


def ring_solid(outer, inner, z0, z1):
    """Closed ring between two polygons: outer skin, inner skin and a top cap.

    Both rings must wind the same way and have the same vertex count, which is
    what the courtyard builder produces by construction.
    """
    n = len(outer)
    if n < 3 or len(inner) != n:
        return [], []
    verts = ([(x, y, z0) for x, y in outer] + [(x, y, z1) for x, y in outer]
             + [(x, y, z0) for x, y in inner] + [(x, y, z1) for x, y in inner])
    o0, o1, i0, i1 = 0, n, 2 * n, 3 * n
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((o0 + i, o0 + j, o1 + j, o1 + i))      # outer skin
        faces.append((i1 + i, i1 + j, i0 + j, i0 + i))      # courtyard skin
        faces.append((o1 + i, o1 + j, i1 + j, i1 + i))      # roof ring
        faces.append((i0 + i, i0 + j, o0 + j, o0 + i))      # soffit ring
    return verts, faces


def band_ring(pts, z0, z1, offset=0.12):
    """Horizontal band wrapped around a footprint, standing proud of the wall.

    A positive offset pushes the band away from the footprint's centre, which
    is what makes it visible on an outward-facing wall; use a negative offset
    on a courtyard ring, whose visible face points the other way. The band must
    always sit slightly proud -- recessing it buries it inside the solid wall,
    exactly as window_bands avoids by bulging its glazing outward.

    Note that offset_polyline grows a counter-clockwise ring on a *negative*
    distance, so the sign is flipped on the way in.
    """
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]
    shifted = offset_ring(pts, -offset)
    if len(shifted) != len(pts):
        shifted = pts
    n = len(shifted)
    verts = [(x, y, z0) for x, y in shifted] + [(x, y, z1) for x, y in shifted]
    faces = [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return verts, faces


def build_uc_banilad(batch, mats, uc_rings):
    """Ten-level courtyard block with the bowed glass frontage on the avenue.

    `uc_rings` is the list of OSM footprints for the campus; their combined
    extent sets the outer wall so the building still lands exactly where the
    surveyed roads and driveways expect it.
    """
    points = [p for ring in uc_rings for p in ring]
    if len(points) < 4:
        log("UC: no footprint available, skipped")
        return 0.0

    centre, axis, half_u, half_v = min_area_rect(points)
    outer_rect = oriented_rect(centre, axis, half_u, half_v)

    # The avenue runs down the west side, so the bowed curtain wall goes on
    # whichever face points that way.
    cx, cy = centre
    to_avenue = (-1.0, 0.0)
    best, best_dot = 0, -2.0
    for i in range(4):
        ax, ay = outer_rect[i]
        bx, by = outer_rect[(i + 1) % 4]
        mx, my = (ax + bx) * 0.5 - cx, (ay + by) * 0.5 - cy
        length = math.hypot(mx, my) or 1.0
        dot = (mx / length) * to_avenue[0] + (my / length) * to_avenue[1]
        if dot > best_dot:
            best, best_dot = i, dot

    # Walk the rectangle, bowing the avenue face outward.
    outer = []
    for i in range(4):
        a = outer_rect[i]
        b = outer_rect[(i + 1) % 4]
        if i == best:
            bulge = UC_FACADE_BOW if signed_area(outer_rect) > 0 else -UC_FACADE_BOW
            outer.extend(bow_edge(a, b, -bulge, segments=7))
        else:
            outer.append(a)
    outer = dedupe(outer)
    if signed_area(outer) < 0:
        outer = outer[::-1]

    inner = inset_in_frame(outer, centre, axis, half_u, half_v, UC_WING_DEPTH)
    if inner is not None and abs(signed_area(inner)) < 60.0:
        inner = None    # footprint too slim for a courtyard; solid block instead

    top = UC_LEVELS * UC_LEVEL_HEIGHT
    if inner:
        v, f = ring_solid(outer, inner, Z_BUILDING_BASE, top)
        batch.add(v, f, mats["UC_Band"])
        v, f = band_ring(inner, top, top + 0.9, offset=0.0)
        batch.add(v, f, mats["UC_Band"])                     # courtyard parapet
    else:
        v, f = walls(outer, Z_BUILDING_BASE, top)
        batch.add(v, f, mats["UC_Band"])
        v, f = parapet_roof(outer, top)
        batch.add(v, f, mats["UC_Deck"])

    # Glazing: one band per level on the street skin, a darker one on the
    # courtyard skin. This is what carries the curtain-wall read.
    for level in range(1, UC_LEVELS):
        z0 = level * UC_LEVEL_HEIGHT + 0.85
        z1 = z0 + UC_LEVEL_HEIGHT - 1.55
        v, f = band_ring(outer, z0, z1, offset=0.10)
        batch.add(v, f, mats["UC_Glass"])
        if inner:
            # The courtyard skin faces inward, so its band goes the other way.
            v, f = band_ring(inner, z0, z1, offset=-0.10)
            batch.add(v, f, mats["UC_Glass_Dark"])

    # Ground-floor colonnade and the entrance canopy on the avenue face.
    v, f = band_ring(outer, 0.5, 3.6, offset=0.12)
    batch.add(v, f, mats["UC_Glass_Dark"])

    # Roof-deck plant room, offset toward the back of the block so it breaks
    # the silhouette the way the real lift overrun does.
    (ux, uy) = axis
    vx, vy = -uy, ux
    px = cx + ux * (half_u * 0.34) + vx * (half_v * 0.52)
    py = cy + uy * (half_u * 0.34) + vy * (half_v * 0.52)
    v, f = box(px, py, top + 0.9, top + 4.6, 6.5, 4.2, math.atan2(uy, ux))
    batch.add(v, f, mats["UC_Podium"])

    # Two-level podium wing along the avenue at the south end (the covered
    # entrance ramp and the Rose Pharmacy shopfront row). It hangs off the same
    # face the curtain wall bows out of, and may only project far enough to
    # clear the building line -- Cuenco Avenue's sidewalk starts a few metres
    # further out, and anything deeper ends up standing in the carriageway.
    ax, ay = outer_rect[best]
    bx, by = outer_rect[(best + 1) % 4]
    ex, ey = bx - ax, by - ay
    edge_len = math.hypot(ex, ey) or 1.0
    ex, ey = ex / edge_len, ey / edge_len
    # Outward normal of that face, pointing away from the building centre.
    nx, ny = -ey, ex
    if nx * ((ax + bx) * 0.5 - cx) + ny * ((ay + by) * 0.5 - cy) < 0.0:
        nx, ny = -nx, -ny

    podium_depth = 3.0
    mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
    qx = mx - ex * (edge_len * 0.30) + nx * (podium_depth + UC_FACADE_BOW * 0.5)
    qy = my - ey * (edge_len * 0.30) + ny * (podium_depth + UC_FACADE_BOW * 0.5)
    podium = oriented_rect((qx, qy), (ex, ey), edge_len * 0.24, podium_depth)
    v, f = walls(podium, Z_BUILDING_BASE, 7.4)
    batch.add(v, f, mats["UC_Podium"])
    v, f = parapet_roof(podium, 7.4, parapet=0.6)
    batch.add(v, f, mats["UC_Deck"])
    v, f = band_ring(podium, 0.6, 3.4, offset=-0.16)
    batch.add(v, f, mats["UC_Glass_Dark"])

    log("UC Banilad: {:d} levels, {:.0f} m tall, courtyard {:s}".format(
        UC_LEVELS, top, "yes" if inner else "no (fallback block)"))
    return top


def shallow_hip(pts, eave_z, rise=1.7, overhang=0.9):
    """Low clay-tile roof that follows the real footprint.

    hip_roof builds over the footprint's bounding rectangle, which suits a
    house but roofs straight across the courtyard of an L- or C-shaped mall
    wing and swallows the car park. This keeps the plan exact: an eave skirt
    around the true outline, a flat cap, and a soffit under the overhang.
    """
    ring = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(ring) < 3:
        return [], []
    if signed_area(ring) < 0:
        ring = ring[::-1]
    # A negative distance grows a counter-clockwise ring, giving the overhang.
    eave = offset_ring(ring, -overhang)
    if len(eave) != len(ring):
        eave = ring

    n = len(ring)
    verts = ([(x, y, eave_z) for x, y in eave]
             + [(x, y, eave_z + rise) for x, y in ring]
             + [(x, y, eave_z) for x, y in ring])
    faces = [tuple(range(n, 2 * n))]                     # flat cap
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))               # sloping skirt
        faces.append((2 * n + i, 2 * n + j, j, i))       # soffit
    return verts, faces


def _arcaded_wing(batch, mats, plan, ground_h, upper_h, roof_mat, tiers=2):
    """Cream arcade block with a clay hip roof, as used by every mall wing."""
    ring = dedupe(plan)
    if signed_area(ring) < 0:
        ring = ring[::-1]

    v, f = walls(ring, Z_BUILDING_BASE, upper_h)
    batch.add(v, f, mats["Mall_Wall"])

    # Ground arcade: the dark band reads as the row of round arches.
    v, f = band_ring(ring, 0.7, ground_h - 0.9, offset=0.10)
    batch.add(v, f, mats["Mall_Arcade"])
    v, f = band_ring(ring, ground_h - 0.9, ground_h - 0.35, offset=0.22)
    batch.add(v, f, mats["Mall_Trim"])          # string course between tiers

    if tiers > 1 and upper_h > ground_h + 2.5:
        v, f = band_ring(ring, ground_h + 0.5, upper_h - 1.1, offset=0.10)
        batch.add(v, f, mats["Mall_Arcade"])    # upper arcade

    # Cornice, then the tile roof.
    v, f = band_ring(ring, upper_h - 0.55, upper_h, offset=0.32)
    batch.add(v, f, mats["Mall_Trim"])
    v, f = shallow_hip(ring, upper_h)
    batch.add(v, f, roof_mat)


def tower_detail(batch, mats, ring, height, glass=None, base_mat="Tower_Base",
                 crown_mat="Tower_Crown", plant=True):
    """Base, glazing, crown and rooftop plant for a tall building.

    Without this an office tower is a bare extruded prism, which is what made
    the whole IT Park district read as a field of plain boxes. Everything here
    is a band standing slightly proud of the wall plus one plant box, so the
    cost is a few dozen triangles per tower.
    """
    if height < 12.0 or len(ring) < 3:
        return

    # Darker podium storeys at street level.
    base_h = min(TOWER_BASE_HEIGHT, height * 0.28)
    v, f = band_ring(ring, 0.0, base_h, offset=0.18)
    batch.add(v, f, mats[base_mat])
    v, f = band_ring(ring, base_h, base_h + 0.45, offset=0.34)
    batch.add(v, f, mats["Tower_Crown"])          # sill course over the podium

    # Curtain wall: one band per floor between the podium and the crown. The
    # band is kept well under the floor pitch so a pale tower still reads as
    # concrete with windows punched into it rather than as zebra stripes.
    if glass:
        floor = base_h + 1.6
        guard = 0
        while floor + 1.5 < height - 3.0 and guard < 60:
            guard += 1
            v, f = band_ring(ring, floor, floor + 1.5, offset=0.10)
            batch.add(v, f, mats[glass])
            floor += 3.4

    # Capping band, then the lift overrun and plant deck on the roof.
    v, f = band_ring(ring, height - 2.6, height - 0.3, offset=0.22)
    batch.add(v, f, mats[crown_mat])

    if plant:
        centre, axis, half_u, half_v = min_area_rect(ring)
        # A lift overrun, not a second storey: keep it small enough that the
        # roof still reads as a roof from the towers looking down on it.
        pu = min(6.5, max(2.2, half_u * 0.18))
        pv = min(6.5, max(2.2, half_v * 0.18))
        v, f = box(centre[0], centre[1], height + 0.85, height + 4.2,
                   pu, pv, math.atan2(axis[1], axis[0]))
        batch.add(v, f, mats["Tower_Plant"])


def roof_plant_field(batch, mats, ring, top_z, spacing=12.0, limit=70):
    """Scatter small plant units over a wide flat roof.

    A mall podium roof is the one surface the surrounding towers look straight
    down onto, and in the reference it is packed with air-handling units. One
    big box in the middle reads as another storey instead.
    """
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    placed = 0
    gy = 0
    y = min(ys) + spacing * 0.5
    while y < max(ys) and placed < limit:
        gx = 0
        x = min(xs) + spacing * 0.5
        while x < max(xs) and placed < limit:
            gx += 1
            cx, cy = x, y
            x += spacing
            # Stay clear of the parapet so nothing pokes through the edge.
            if not all(point_in_polygon(cx + dx, cy + dy, ring)
                       for dx, dy in ((0, 0), (5, 0), (-5, 0), (0, 5), (0, -5))):
                continue
            # Deterministic jitter: the build must be reproducible.
            h = (gx * 7 + gy * 13) % 5
            w = 1.8 + (h % 3) * 0.7
            d = 1.6 + ((h + 1) % 3) * 0.6
            v, f = box(cx, cy, top_z + 0.6, top_z + 1.5 + h * 0.35, w, d)
            batch.add(v, f, mats["Tower_Plant"])
            placed += 1
        gy += 1
        y += spacing
    return placed


def build_central_bloc(batch, mats, rings):
    """Ayala Malls Central Bloc: mall podium, two office towers and the hotel."""
    built = 0
    for way_id, (height, wall_key, glass_key) in sorted(CENTRAL_BLOC.items()):
        ring = rings.get(way_id)
        if not ring or len(ring) < 3:
            continue

        v, f = walls(ring, Z_BUILDING_BASE, height)
        batch.add(v, f, mats[wall_key])
        v, f = parapet_roof(ring, height, parapet=1.2)
        batch.add(v, f, mats["Roof_Deck"])

        # Curtain walling is what separates a tower from a podium here, not
        # height: the Ayala Malls block is tall but is still a mall roof.
        if glass_key:
            tower_detail(batch, mats, ring, height, glass=glass_key,
                         crown_mat="Tower_Crown")
        else:
            # Podium blocks: a deep parapet and a plant-covered roof rather
            # than curtain walling, which is how they read from above.
            v, f = band_ring(ring, height - 3.2, height - 0.6, offset=0.16)
            batch.add(v, f, mats["Window"])
            units = roof_plant_field(batch, mats, ring, height)
            log("  {:d} plant units on the {:.0f} m podium roof".format(
                units, height))

        if way_id == CENTRAL_BLOC_MALL:
            # The lit signage strip that fronts the mall in the night aerial.
            v, f = band_ring(ring, height - 7.0, height - 4.6, offset=0.30)
            batch.add(v, f, mats["Bloc_Sign"])
        built += 1

    log("Central Bloc: {:d} of {:d} blocks built (heights from the night "
        "aerial, not OSM)".format(built, len(CENTRAL_BLOC)))
    return built


def build_country_mall(solid, lot_batch, walk_batch, mats, rings):
    """Arcaded wings around the open car park, plus the covered walkway.

    `rings` maps OSM way id to footprint for every part of the complex.

    The walkway goes into its own batch because the wings can be swapped for a
    scanned asset at runtime (see banilad_city.gd), and the walkway has to
    survive that: it is not in frame in any photo of the mall.
    """
    wings = 0
    for way_id, (ground_h, upper_h, tiers) in sorted(MALL_WINGS.items()):
        ring = rings.get(way_id)
        if not ring or len(ring) < 3:
            continue
        roof_mat = mats["Mall_Roof" if wings % 2 == 0 else "Mall_Roof_Alt"]
        _arcaded_wing(solid, mats, ring, ground_h, upper_h, roof_mat,
                      tiers=tiers)
        wings += 1

    # --- Car park ----------------------------------------------------------
    # The commercial parcel is the whole block; the wings are drawn on top of
    # it, so whatever tarmac still shows through is exactly the open court.
    stripes = 0
    parcel = rings.get(MALL_PARCEL_WAY)
    if parcel and len(parcel) >= 3:
        lot = dedupe(parcel)
        if signed_area(lot) < 0:
            lot = lot[::-1]
        v, f = flat_polygon(lot + [lot[0]], 0.05)
        lot_batch.add(v, f, mats["Lot_Asphalt"])

        blockers = [rings[w] for w in MALL_WINGS if rings.get(w)]
        blockers += [rings[MALL_WALKWAY_WAY]] if rings.get(MALL_WALKWAY_WAY) else []

        # Bay stripes run along the avenue axis, skipping anything built on.
        ux, uy = AVENUE_U
        vx, vy = -uy, ux
        cx = sum(p[0] for p in lot) / len(lot)
        cy = sum(p[1] for p in lot) / len(lot)
        for row in range(-9, 10):
            base = row * 11.5
            for slot in range(-22, 23):
                along = slot * 2.7
                sx = cx + ux * along + vx * base
                sy = cy + uy * along + vy * base
                ex, ey = sx + vx * 5.0, sy + vy * 5.0
                if not (point_in_polygon(sx, sy, lot)
                        and point_in_polygon(ex, ey, lot)):
                    continue
                mid = ((sx + ex) * 0.5, (sy + ey) * 0.5)
                if any(point_in_polygon(mid[0], mid[1], b) for b in blockers):
                    continue
                v, f = ribbon([(sx, sy), (ex, ey)], 0.16, 0.07)
                lot_batch.add(v, f, mats["Lot_Stripe"])
                stripes += 1

    # --- Covered walkway ---------------------------------------------------
    # Surveyed as a thin loop running out to the Cuenco Avenue sidewalk, so its
    # long axis gives the centreline the canopy and posts follow.
    walk_length = 0.0
    walk = rings.get(MALL_WALKWAY_WAY)
    if walk and len(walk) >= 3:
        wcentre, waxis, whalf_u, whalf_v = min_area_rect(walk)
        wx, wy = waxis
        a = (wcentre[0] - wx * whalf_u, wcentre[1] - wy * whalf_u)
        b = (wcentre[0] + wx * whalf_u, wcentre[1] + wy * whalf_u)
        # Slide the whole canopy so whichever end is nearer the mall lands on
        # the entrance bay's face, keeping its surveyed length and bearing.
        inner = a if (math.dist(a, MALL_WALKWAY_ANCHOR)
                      < math.dist(b, MALL_WALKWAY_ANCHOR)) else b
        shift = (MALL_WALKWAY_ANCHOR[0] - inner[0],
                 MALL_WALKWAY_ANCHOR[1] - inner[1])
        a = (a[0] + shift[0], a[1] + shift[1])
        b = (b[0] + shift[0], b[1] + shift[1])
        walk_length = 2.0 * whalf_u
        width = max(3.0, 2.0 * whalf_v)

        nx, ny = -wy, wx
        posts = max(1, int(walk_length // 8.0))
        for i in range(posts + 1):
            t = i / float(posts)
            px = a[0] + (b[0] - a[0]) * t
            py = a[1] + (b[1] - a[1]) * t
            for side in (-width * 0.42, width * 0.42):
                v, f = box(px + nx * side, py + ny * side,
                           Z_BUILDING_BASE, MALL_WALKWAY_HEIGHT, 0.16, 0.16)
                walk_batch.add(v, f, mats["Mall_Trim"])
        v, f = raised_ribbon([a, b], width, MALL_WALKWAY_HEIGHT, 0.5)
        walk_batch.add(v, f, mats["Mall_Walkway"])
        v, f = ribbon([a, b], width * 0.85, 0.06)
        lot_batch.add(v, f, mats["Sidewalk"])

        # No entrance pediment. It stood at the inner end of the canopy and
        # read as a windowless building stuck on the end of a walkway; the
        # scanned mall's own entrance bay does that job now.

    log("Country Mall: {:d} surveyed wings, {:d} parking stripes, "
        "{:.0f} m covered walkway".format(wings, stripes, walk_length))


# ---------------------------------------------------------------------------
# Props
# ---------------------------------------------------------------------------

def tree(x, y, rng):
    """Low-poly broadleaf: tapered trunk plus a faceted canopy."""
    height = rng.uniform(4.0, 8.5)
    trunk_h = height * 0.42
    radius = rng.uniform(1.6, 3.0)
    trunk = box(x, y, 0.0, trunk_h, 0.22, 0.22, rng.uniform(0, 1.5))

    sides = 6
    ring_z = trunk_h + radius * 0.35
    ring = []
    for i in range(sides):
        a = 2 * math.pi * i / sides + rng.uniform(0, 0.4)
        ring.append((x + math.cos(a) * radius, y + math.sin(a) * radius, ring_z))
    verts = ring + [(x, y, trunk_h - 0.3), (x, y, height)]
    bottom = sides
    top = sides + 1
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, top))
        faces.append((j, i, bottom))
    return trunk, (verts, faces)


def palm(x, y, rng):
    """Coconut palm: leaning trunk with radiating fronds."""
    height = rng.uniform(6.0, 11.0)
    lean = rng.uniform(0.0, 0.9)
    lean_dir = rng.uniform(0, 2 * math.pi)
    tipx = x + math.cos(lean_dir) * lean
    tipy = y + math.sin(lean_dir) * lean

    trunk_verts = [
        (x - 0.22, y - 0.22, 0.0), (x + 0.22, y - 0.22, 0.0),
        (x + 0.22, y + 0.22, 0.0), (x - 0.22, y + 0.22, 0.0),
        (tipx - 0.14, tipy - 0.14, height), (tipx + 0.14, tipy - 0.14, height),
        (tipx + 0.14, tipy + 0.14, height), (tipx - 0.14, tipy + 0.14, height),
    ]
    trunk_faces = [(3, 2, 1, 0), (4, 5, 6, 7)]
    for i in range(4):
        j = (i + 1) % 4
        trunk_faces.append((i, j, j + 4, i + 4))

    verts = []
    faces = []
    fronds = 7
    for i in range(fronds):
        a = 2 * math.pi * i / fronds + rng.uniform(0, 0.3)
        reach = rng.uniform(2.4, 3.6)
        ex, ey = tipx + math.cos(a) * reach, tipy + math.sin(a) * reach
        px, py = -math.sin(a) * 0.42, math.cos(a) * 0.42
        base = len(verts)
        verts += [
            (tipx + px, tipy + py, height),
            (tipx - px, tipy - py, height),
            (ex - px * 0.3, ey - py * 0.3, height - rng.uniform(1.0, 2.0)),
            (ex + px * 0.3, ey + py * 0.3, height - rng.uniform(1.0, 2.0)),
        ]
        faces.append((base, base + 1, base + 2, base + 3))
    return (trunk_verts, trunk_faces), (verts, faces)


def street_light(x, y, angle):
    """Pole with a cantilevered arm, arm points along `angle`."""
    height = 8.0
    pole = box(x, y, 0.0, height, 0.16, 0.16)
    ax, ay = math.cos(angle), math.sin(angle)
    arm_len = 2.4
    arm = box(x + ax * arm_len * 0.5, y + ay * arm_len * 0.5,
              height - 0.28, height, arm_len * 0.5, 0.12, angle)
    lamp = box(x + ax * arm_len, y + ay * arm_len,
               height - 0.5, height - 0.24, 0.5, 0.24, angle)
    return pole, arm, lamp


def power_pole(x, y, angle):
    height = 9.5
    pole = box(x, y, 0.0, height, 0.18, 0.18)
    cross = box(x, y, height - 1.1, height - 0.9, 1.5, 0.1, angle)
    cross2 = box(x, y, height - 2.0, height - 1.85, 1.1, 0.09, angle)
    return pole, cross, cross2


def vehicle(x, y, angle, rng):
    """Two-box car, roughly 4.3 x 1.8 m."""
    length = rng.uniform(3.9, 4.8)
    width = rng.uniform(1.7, 1.95)
    body = box(x, y, 0.18, 0.85, length * 0.5, width * 0.5, angle)
    cabin = box(x - math.cos(angle) * length * 0.06,
                y - math.sin(angle) * length * 0.06,
                0.85, 1.42, length * 0.28, width * 0.44, angle)
    return body, cabin


# ---------------------------------------------------------------------------
# Blender plumbing
# ---------------------------------------------------------------------------

def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def build_materials():
    mats = {}
    for name, srgb in PALETTE.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        linear = tuple(srgb_to_linear(c) for c in srgb)
        bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
        if name.startswith("Tower_Glass") or name in (
                "Tower_Charcoal", "Tower_Graphite", "UC_Glass",
                "UC_Glass_Dark", "Bloc_Tower_Dark", "Bloc_Tower_Light"):
            bsdf.inputs["Roughness"].default_value = 0.22
            bsdf.inputs["Metallic"].default_value = 0.1
        elif name == "Water":
            bsdf.inputs["Roughness"].default_value = 0.15
        elif name.startswith("Car_"):
            bsdf.inputs["Roughness"].default_value = 0.35
        else:
            bsdf.inputs["Roughness"].default_value = 0.85
        mat.diffuse_color = (*linear, 1.0)
        # prep_godot.py re-reads this to correct for Godot's importer.
        mat["intended_srgb"] = list(srgb)
        mats[name] = mat
    return mats


class MeshBatch:
    """Accumulates many features into one multi-material mesh."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.face_slots = []
        self.slots = []
        self._slot_of = {}

    def _slot(self, material):
        key = material.name
        if key not in self._slot_of:
            self._slot_of[key] = len(self.slots)
            self.slots.append(material)
        return self._slot_of[key]

    def add(self, verts, faces, material):
        if not faces:
            return
        slot = self._slot(material)
        offset = len(self.verts)
        self.verts.extend(verts)
        for f in faces:
            self.faces.append(tuple(i + offset for i in f))
            self.face_slots.append(slot)

    def is_empty(self):
        return not self.faces

    def to_object(self, name, collection):
        if self.is_empty():
            return None
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.validate(verbose=False)
        for material in self.slots:
            mesh.materials.append(material)
        if len(self.slots) > 1:
            for poly, slot in zip(mesh.polygons, self.face_slots):
                poly.material_index = slot
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        return obj


def new_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def parse_height(tags):
    raw = tags.get("height")
    if raw:
        try:
            return max(2.5, float(str(raw).lower().replace("m", "").strip()))
        except ValueError:
            pass
    levels = tags.get("building:levels")
    if levels:
        try:
            return max(2.5, float(levels) * LEVEL_HEIGHT + 1.0)
        except ValueError:
            pass
    return DEFAULT_HEIGHTS.get(tags.get("building", "yes"), 6.0)


def safe_name(tags, fallback):
    name = tags.get("name")
    if not name:
        return fallback
    return "".join(ch for ch in name if ch.isprintable())[:56]


# ---------------------------------------------------------------------------
# Main build
# ---------------------------------------------------------------------------

def main():
    rng = random.Random(SEED)
    log("clearing scene")
    bpy.ops.wm.read_factory_settings(use_empty=True)

    data = json.loads(OSM_FILE.read_text(encoding="utf-8"))
    elements = data["elements"]
    ways = [e for e in elements if e["type"] == "way"]
    log("loaded {:d} OSM elements".format(len(elements)))

    mats = build_materials()
    col_ground = new_collection("Ground")
    col_roads = new_collection("Roads")
    col_water = new_collection("Water")
    col_buildings = new_collection("Buildings")
    col_landmarks = new_collection("Landmarks")
    col_props = new_collection("Props")

    # --- Ground ------------------------------------------------------------
    g = GROUND_HALF
    ground = MeshBatch()
    ground.add([(-g, -g, Z_GROUND), (g, -g, Z_GROUND), (g, g, Z_GROUND), (-g, g, Z_GROUND)],
               [(0, 1, 2, 3)], mats["Ground"])
    ground.to_object("Ground", col_ground)

    # --- Landuse -----------------------------------------------------------
    landuse = MeshBatch()
    green_polys = []
    nofill_polys = [UC_CAMPUS_BLOCK]
    parcel_rings = {}
    landuse_count = 0
    for el in ways:
        tags = el.get("tags", {})
        kind = tags.get("landuse") or tags.get("leisure")
        if not kind or "building" in tags:
            continue
        pts = way_points(el)
        if not is_closed(pts):
            continue
        verts, faces = flat_polygon(pts, layer_z(Z_LANDUSE, landuse_count))
        if not faces:
            continue
        is_green = kind in GREEN_TAGS
        landuse.add(verts, faces, mats["Landuse_Green" if is_green else "Landuse_Urban"])
        if is_green:
            green_polys.append(dedupe(pts[:-1]))
        elif kind in NOFILL_TAGS:
            nofill_polys.append(dedupe(pts[:-1]))
        if el["id"] == MALL_PARCEL_WAY:
            parcel_rings[MALL_PARCEL_WAY] = dedupe(pts[:-1])
        landuse_count += 1
    landuse.to_object("Landuse", col_ground)
    log("landuse areas: {:d} ({:d} no-infill districts)".format(
        landuse_count, len(nofill_polys)))

    # --- Water -------------------------------------------------------------
    water = MeshBatch()
    water_lines = []
    water_count = 0
    for el in ways:
        tags = el.get("tags", {})
        pts = way_points(el)
        if len(pts) < 2:
            continue
        zw = layer_z(Z_WATER, water_count)
        if tags.get("natural") == "water" and is_closed(pts):
            verts, faces = flat_polygon(pts, zw)
        elif "waterway" in tags:
            if is_closed(pts):
                verts, faces = flat_polygon(pts, zw)
            else:
                width = 14.0 if tags["waterway"] in ("river", "stream") else 8.0
                try:
                    width = max(width, float(tags.get("width", 0)))
                except ValueError:
                    pass
                verts, faces = ribbon(pts, width, zw)
                water_lines.append((dedupe(pts), width))
        else:
            continue
        water.add(verts, faces, mats["Water"])
        water_count += 1
    water.to_object("Water", col_water)
    log("water features: {:d}".format(water_count))

    # --- Roads, sidewalks and markings -------------------------------------
    roads_major = MeshBatch()
    roads_minor = MeshBatch()
    footways = MeshBatch()
    sidewalks = MeshBatch()
    markings = MeshBatch()

    road_lines = []      # (points, width, class) reused for props
    road_count = 0

    # Pass 1: resolve every centreline and width up front, so pass 2 can ask
    # "is this point on another road's tarmac?" while it builds.
    resolved = []
    for el in ways:
        tags = el.get("tags", {})
        cls = tags.get("highway")
        if not cls:
            continue
        pts = dedupe(way_points(el))
        if len(pts) < 2:
            continue

        width = ROAD_WIDTHS.get(cls, 5.0)
        try:
            lanes = float(tags.get("lanes", 0))
            if lanes:
                width = max(width, lanes * 3.4)
        except ValueError:
            pass
        resolved.append((pts, width, cls))

    carriageways = SpatialIndex()
    for way_index, (pts, width, cls) in enumerate(resolved):
        if cls in FOOT_ROADS:
            continue
        for i in range(len(pts) - 1):
            carriageways.add_segment(
                pts[i], pts[i + 1], (pts[i], pts[i + 1], width * 0.5, way_index)
            )

    clipped_walks = 0
    for way_index, (pts, width, cls) in enumerate(resolved):
        if cls in MAJOR_ROADS:
            target, z, mat = roads_major, Z_ROAD_MAJOR, mats["Road_Major"]
        elif cls in FOOT_ROADS:
            target, z, mat = footways, Z_FOOTWAY, mats["Footway"]
        else:
            target, z, mat = roads_minor, Z_ROAD_MINOR, mats["Road_Minor"]

        rz = layer_z(z, road_count)
        verts, faces = ribbon(pts, width, rz)
        target.add(verts, faces, mat)

        # Kerbed sidewalks and centre lines only on driveable streets.
        #
        # Both are generated along the way's whole length, so without clipping
        # they run straight over every road that crosses them -- a raised kerb
        # slab lying across the avenue, which is a step the car hits as well as
        # something that looks wrong. Breaking them where they enter another
        # carriageway leaves the gap a real junction has.
        if cls in MAJOR_ROADS or cls in ("unclassified", "residential"):
            walk_offset = width * 0.5 + SIDEWALK_WIDTH * 0.5
            for side in (walk_offset, -walk_offset):
                line = offset_polyline(pts, side)
                if len(line) < 2:
                    continue
                runs = clip_against_carriageways(
                    line, carriageways, way_index, SIDEWALK_WIDTH * 0.5 + 0.15
                )
                if len(runs) > 1:
                    clipped_walks += 1
                for run in runs:
                    v, f = raised_ribbon(run, SIDEWALK_WIDTH,
                                         layer_z(Z_SIDEWALK, road_count), KERB_HEIGHT)
                    sidewalks.add(v, f, mats["Sidewalk"])

        if cls in MAJOR_ROADS:
            for run in clip_against_carriageways(pts, carriageways, way_index, 0.3):
                v, f = dashed_line(run, layer_z(Z_MARKING, road_count))
                markings.add(v, f, mats["Marking_White"])
            for side in (width * 0.5 - 0.5, -(width * 0.5 - 0.5)):
                edge = offset_polyline(pts, side)
                if len(edge) < 2:
                    continue
                for run in clip_against_carriageways(edge, carriageways, way_index, 0.3):
                    v, f = ribbon(run, 0.18, layer_z(Z_MARKING, road_count))
                    markings.add(v, f, mats["Marking_Yellow"])

        road_lines.append((pts, width, cls))
        road_count += 1

    # One flat collision surface for every carriageway.
    #
    # The visual ribbons are nudged apart by layer_z so they do not z-fight,
    # which at a junction stacks up to LAYER_SLOTS collidable surfaces inside
    # 3 cm, with the ground plane a further 13 cm below. VehicleWheel3D rays
    # would hit a different one of those every frame and chatter. Physics reads
    # this single coplanar mesh instead; prep_godot.py marks the visual road
    # meshes no-collide and exports this one as collision-only, so it never
    # renders.
    #
    # Footways are skipped: at 5 cm they are close enough to the ground plane
    # that walking on the ground underneath is indistinguishable.
    road_collision = MeshBatch()
    collision_ways = 0
    for pts, width, cls in road_lines:
        if cls in FOOT_ROADS:
            continue
        v, f = ribbon(pts, width, Z_ROAD_COLLISION)
        road_collision.add(v, f, mats["Road_Major"])
        collision_ways += 1

    roads_major.to_object("Roads_Major", col_roads)
    roads_minor.to_object("Roads_Minor", col_roads)
    footways.to_object("Footways", col_roads)
    sidewalks.to_object("Sidewalks", col_roads)
    markings.to_object("Markings", col_roads)
    road_collision.to_object("Roads_Collision", col_roads)
    log("road ways: {:d}".format(road_count))
    log("sidewalks broken at junctions: {:d}".format(clipped_walks))
    log("drive collision ways: {:d} (flat at z={:.3f})".format(
        collision_ways, Z_ROAD_COLLISION))

    # --- Buildings ---------------------------------------------------------
    building_batch = MeshBatch()
    window_batch = MeshBatch()
    building_count = 0
    landmark_count = 0
    pitched = 0
    towers = 0
    footprints = []

    # Footprints the hand-authored landmark builders need, keyed by OSM way id.
    landmark_rings = {}

    for el in ways:
        tags = el.get("tags", {})
        if "building" not in tags and "building:part" not in tags:
            continue
        pts = way_points(el)
        if not is_closed(pts):
            continue
        ring = dedupe(pts[:-1])
        if len(ring) < 3:
            continue

        height = parse_height(tags)
        oid = el["id"]
        footprints.append(ring)

        # The two landmarks are modelled by hand further down. Their footprints
        # still count above so infill housing keeps off them.
        if oid in LANDMARK_WAY_IDS:
            landmark_rings[oid] = ring
            continue

        # Named buildings become their own object so gameplay can find them;
        # the rest are batched. Windows follow whichever mesh owns the walls.
        named = "name" in tags
        target = MeshBatch() if named else building_batch
        windows = target if named else window_batch

        area = abs(signed_area(ring))
        if height <= PITCHED_ROOF_MAX and area <= PITCHED_ROOF_MAX_AREA:
            wall_mat = mats[WALL_LOW[oid % len(WALL_LOW)]]
            roof_mat = mats[ROOF_PITCHED[oid % len(ROOF_PITCHED)]]
            eave = height
            v, f = walls(ring, Z_BUILDING_BASE, eave)
            target.add(v, f, wall_mat)
            v, f, _rise = hip_roof(ring, eave)
            target.add(v, f, roof_mat)
            pitched += 1
        else:
            is_tower = height >= TOWER_MIN_HEIGHT
            if is_tower:
                cladding, glazing = TOWER_SCHEME_BY_NAME.get(
                    safe_name(tags, ""), TOWER_SCHEMES[oid % len(TOWER_SCHEMES)])
                wall_mat = mats[cladding]
                roof_mat = mats["Roof_Deck"]
            else:
                wall_mat = mats[WALL_MID[oid % len(WALL_MID)]]
                roof_mat = mats["Roof_Flat"]
            v, f = walls(ring, Z_BUILDING_BASE, height)
            target.add(v, f, wall_mat)
            v, f = parapet_roof(ring, height)
            target.add(v, f, roof_mat)

            if is_tower:
                # Podium, curtain wall, crown and plant. Without this the IT
                # Park district is a field of bare prisms.
                tower_detail(target, mats, ring, height, glass=glazing)
                towers += 1
            else:
                v, f = window_bands(ring, Z_BUILDING_BASE, height)
                windows.add(v, f, mats["Window"])

        building_count += 1

        if named:
            target.to_object(safe_name(tags, "Building_{:d}".format(oid)), col_landmarks)
            landmark_count += 1

    log("buildings: {:d} ({:d} pitched roofs, {:d} detailed towers, "
        "{:d} named landmarks)".format(
            building_count, pitched, towers, landmark_count))

    # --- Hand-authored landmarks -------------------------------------------
    landmark_rings.update(parcel_rings)
    missing = sorted((LANDMARK_WAY_IDS | {MALL_PARCEL_WAY}) - set(landmark_rings))
    if missing:
        log("WARNING: landmark ways absent from the OSM extract: {:s}".format(
            ", ".join(str(m) for m in missing)))

    uc_batch = MeshBatch()
    build_uc_banilad(uc_batch, mats,
                     [landmark_rings[w] for w in sorted(UC_WAY_IDS)
                      if w in landmark_rings])
    uc_batch.to_object("University of Cebu - Banilad Campus", col_landmarks)

    mall_batch = MeshBatch()
    mall_lot = MeshBatch()
    mall_walk = MeshBatch()
    build_country_mall(mall_batch, mall_lot, mall_walk, mats, landmark_rings)
    mall_batch.to_object("Gaisano Country Mall", col_landmarks)
    mall_walk.to_object("Mall_Walkway", col_landmarks)

    bloc_batch = MeshBatch()
    build_central_bloc(bloc_batch, mats, landmark_rings)
    bloc_batch.to_object("Ayala Malls Central Bloc", col_landmarks)
    # Named like the other batched decals, not like a landmark: it is a flat
    # slab of tarmac and paint that must never become collision geometry.
    mall_lot.to_object("Mall_Car_Park", col_ground)

    infill_batch = MeshBatch()
    infill_count = place_infill_housing(infill_batch, mats, road_lines, water_lines,
                                        footprints, green_polys, nofill_polys, rng)
    infill_batch.to_object("Buildings_Infill", col_buildings)
    log("infill houses: {:d}".format(infill_count))

    building_batch.to_object("Buildings", col_buildings)
    window_batch.to_object("Windows", col_buildings)

    # --- Props -------------------------------------------------------------
    # Trunks, poles and vehicles block the player; canopies and lamp heads are
    # kept separate so they never become collision or floating navmesh.
    solid = MeshBatch()
    foliage = MeshBatch()
    trees_placed = place_trees(solid, foliage, mats, green_polys, footprints, rng)
    lights_placed, poles_placed = place_street_furniture(solid, foliage, mats, road_lines, rng)
    cars_placed = place_vehicles(solid, mats, road_lines, rng)
    solid.to_object("Props_Solid", col_props)
    foliage.to_object("Props_Foliage", col_props)
    log("props: {:d} trees, {:d} street lights, {:d} power poles, {:d} vehicles".format(
        trees_placed, lights_placed, poles_placed, cars_placed))

    # --- Lighting, camera, output ------------------------------------------
    setup_scene()
    save_and_export()


class SpatialIndex:
    """Uniform grid for 'what is near this point' queries during infill."""

    def __init__(self, cell=28.0):
        self.cell = cell
        self.buckets = {}

    def _key(self, x, y):
        return (int(math.floor(x / self.cell)), int(math.floor(y / self.cell)))

    def add_segment(self, p0, p1, payload):
        steps = max(1, int(math.dist(p0, p1) / self.cell) + 1)
        for i in range(steps + 1):
            t = i / steps
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t
            self.buckets.setdefault(self._key(x, y), []).append(payload)

    def add_point(self, x, y, payload):
        self.buckets.setdefault(self._key(x, y), []).append(payload)

    def near(self, x, y, radius=1):
        cx, cy = self._key(x, y)
        out = []
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                out.extend(self.buckets.get((cx + dx, cy + dy), ()))
        return out


def point_segment_distance(px, py, p0, p1):
    x0, y0 = p0
    x1, y1 = p1
    dx, dy = x1 - x0, y1 - y0
    length_sq = dx * dx + dy * dy
    if length_sq < 1e-9:
        return math.dist((px, py), p0), 0.0
    t = max(0.0, min(1.0, ((px - x0) * dx + (py - y0) * dy) / length_sq))
    return math.dist((px, py), (x0 + dx * t, y0 + dy * t)), math.atan2(dy, dx)


def place_infill_housing(batch, mats, road_lines, water_lines, footprints,
                         green_polys, nofill_polys, rng):
    """Fill unmapped blocks with small houses so the district reads as built up."""
    roads = SpatialIndex()
    for pts, width, cls in road_lines:
        for i in range(len(pts) - 1):
            roads.add_segment(pts[i], pts[i + 1], (pts[i], pts[i + 1], width))

    water = SpatialIndex()
    for pts, width in water_lines:
        for i in range(len(pts) - 1):
            water.add_segment(pts[i], pts[i + 1], (pts[i], pts[i + 1], width))

    existing = SpatialIndex()
    for ring in footprints:
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        bbox = (min(xs), min(ys), max(xs), max(ys))
        cx, cy = (bbox[0] + bbox[2]) * 0.5, (bbox[1] + bbox[3]) * 0.5
        existing.add_point(cx, cy, bbox)
        # Large footprints need registering in more than one bucket.
        existing.add_point(bbox[0], bbox[1], bbox)
        existing.add_point(bbox[2], bbox[3], bbox)

    green_boxes = []
    for poly in green_polys:
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        green_boxes.append(((min(xs), min(ys), max(xs), max(ys)), poly))

    nofill_boxes = []
    for poly in nofill_polys:
        if len(poly) < 3:
            continue
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        nofill_boxes.append(((min(xs), min(ys), max(xs), max(ys)), poly))

    x0, y0, x1, y1 = INFILL_BOUNDS
    placed = 0
    y = y0
    while y < y1 and placed < INFILL_LIMIT:
        x = x0
        while x < x1 and placed < INFILL_LIMIT:
            px = x + rng.uniform(-3.5, 3.5)
            py = y + rng.uniform(-3.5, 3.5)
            x += INFILL_SPACING

            # Must sit clear of the carriageway but still front a street.
            best = None
            for p0, p1, width in roads.near(px, py):
                distance, heading = point_segment_distance(px, py, p0, p1)
                clearance = width * 0.5 + INFILL_ROAD_CLEARANCE
                if distance < clearance:
                    best = None
                    break
                if best is None or distance < best[0]:
                    best = (distance, heading)
            if best is None or best[0] > INFILL_ROAD_MAX_DISTANCE:
                continue

            if any(
                point_segment_distance(px, py, p0, p1)[0] < width * 0.5 + INFILL_WATER_CLEARANCE
                for p0, p1, width in water.near(px, py)
            ):
                continue

            if any(
                bbox[0] - INFILL_BUILDING_CLEARANCE < px < bbox[2] + INFILL_BUILDING_CLEARANCE
                and bbox[1] - INFILL_BUILDING_CLEARANCE < py < bbox[3] + INFILL_BUILDING_CLEARANCE
                for bbox in existing.near(px, py, radius=2)
            ):
                continue

            if any(
                box[0] <= px <= box[2] and box[1] <= py <= box[3]
                and point_in_polygon(px, py, poly)
                for box, poly in green_boxes
            ):
                continue

            if any(
                box[0] <= px <= box[2] and box[1] <= py <= box[3]
                and point_in_polygon(px, py, poly)
                for box, poly in nofill_boxes
            ):
                continue

            # Face the house toward the street it fronts.
            angle = best[1] + rng.choice((0.0, math.pi))
            half_x = rng.uniform(3.4, 5.6)
            half_y = rng.uniform(2.8, 4.4)
            height = rng.uniform(3.0, 6.4)

            ca, sa = math.cos(angle), math.sin(angle)
            ring = []
            for dx, dy in ((-half_x, -half_y), (half_x, -half_y),
                           (half_x, half_y), (-half_x, half_y)):
                ring.append((px + dx * ca - dy * sa, py + dx * sa + dy * ca))

            wall = mats[WALL_LOW[placed % len(WALL_LOW)]]
            roof = mats[ROOF_PITCHED[(placed * 7 + 3) % len(ROOF_PITCHED)]]
            v, f = walls(ring, Z_BUILDING_BASE, height)
            batch.add(v, f, wall)
            v, f, _rise = hip_roof(ring, height, overhang=0.45)
            batch.add(v, f, roof)

            existing.add_point(px, py, (px - half_x, py - half_y, px + half_x, py + half_y))
            placed += 1
        y += INFILL_SPACING
    return placed


def dashed_line(pts, z, dash=3.0, gap=4.0, width=0.22):
    """Broken centre line following a polyline."""
    verts = []
    faces = []
    travelled = 0.0
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg < 1e-6:
            continue
        ux, uy = (x1 - x0) / seg, (y1 - y0) / seg
        nx, ny = -uy * width * 0.5, ux * width * 0.5
        pos = 0.0
        while pos < seg:
            phase = math.fmod(travelled + pos, dash + gap)
            if phase < dash:
                run = min(dash - phase, seg - pos)
                ax, ay = x0 + ux * pos, y0 + uy * pos
                bx, by = x0 + ux * (pos + run), y0 + uy * (pos + run)
                base = len(verts)
                verts += [
                    (ax + nx, ay + ny, z), (bx + nx, by + ny, z),
                    (bx - nx, by - ny, z), (ax - nx, ay - ny, z),
                ]
                faces.append((base, base + 1, base + 2, base + 3))
                pos += run
            else:
                pos += (dash + gap) - phase
        travelled += seg
    return verts, faces


def place_trees(solid, foliage, mats, green_polys, footprints, rng, limit=900):
    placed = 0
    for poly in green_polys:
        if placed >= limit or len(poly) < 3:
            continue
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        area = abs(signed_area(poly))
        wanted = min(28, int(area / 420.0))
        attempts = 0
        made = 0
        while made < wanted and attempts < wanted * 12 and placed < limit:
            attempts += 1
            x = rng.uniform(min(xs), max(xs))
            y = rng.uniform(min(ys), max(ys))
            if not point_in_polygon(x, y, poly):
                continue
            if rng.random() < 0.28:
                trunk, fronds = palm(x, y, rng)
                solid.add(trunk[0], trunk[1], mats["Tree_Trunk"])
                foliage.add(fronds[0], fronds[1], mats[CANOPY_COLOURS[placed % 3]])
            else:
                trunk, canopy = tree(x, y, rng)
                solid.add(trunk[0], trunk[1], mats["Tree_Trunk"])
                foliage.add(canopy[0], canopy[1], mats[CANOPY_COLOURS[placed % 3]])
            made += 1
            placed += 1
    return placed


def _walk_line(pts, spacing, start=0.0):
    """Yield (x, y, heading) at fixed intervals along a polyline."""
    travelled = start
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg < 1e-6:
            continue
        ux, uy = (x1 - x0) / seg, (y1 - y0) / seg
        heading = math.atan2(uy, ux)
        pos = spacing - travelled if travelled < spacing else 0.0
        while pos < seg:
            yield x0 + ux * pos, y0 + uy * pos, heading
            pos += spacing
        travelled = (travelled + seg) % spacing


def place_street_furniture(solid, foliage, mats, road_lines, rng,
                           light_limit=420, pole_limit=520):
    lights = 0
    poles = 0
    for pts, width, cls in road_lines:
        if cls in MAJOR_ROADS and lights < light_limit:
            side = width * 0.5 + 1.4
            flip = True
            for x, y, heading in _walk_line(offset_polyline(pts, side), 38.0):
                if lights >= light_limit:
                    break
                pole, arm, lamp = street_light(x, y, heading + math.pi * 0.5)
                solid.add(pole[0], pole[1], mats["Pole"])
                foliage.add(arm[0], arm[1], mats["Pole"])
                foliage.add(lamp[0], lamp[1], mats["Lamp"])
                lights += 1
                flip = not flip
        elif cls in ("residential", "unclassified") and poles < pole_limit:
            side = width * 0.5 + 1.1
            for x, y, heading in _walk_line(offset_polyline(pts, side), 46.0):
                if poles >= pole_limit:
                    break
                a, b, c = power_pole(x, y, heading + math.pi * 0.5)
                solid.add(a[0], a[1], mats["Pole"])
                foliage.add(b[0], b[1], mats["Pole"])
                foliage.add(c[0], c[1], mats["Pole"])
                poles += 1
    return lights, poles


def place_vehicles(solid, mats, road_lines, rng, limit=260):
    placed = 0
    for pts, width, cls in road_lines:
        if placed >= limit:
            break
        if cls not in MAJOR_ROADS and cls not in ("residential", "unclassified"):
            continue
        lane = width * 0.5 - 1.6
        if lane < 1.0:
            continue
        for side in (lane, -lane):
            line = offset_polyline(pts, side)
            if len(line) < 2:
                continue
            for x, y, heading in _walk_line(line, rng.uniform(30.0, 55.0)):
                if placed >= limit:
                    break
                if rng.random() < 0.45:
                    continue
                body, cabin = vehicle(x, y, heading, rng)
                colour = mats[CAR_COLOURS[placed % len(CAR_COLOURS)]]
                solid.add(body[0], body[1], colour)
                solid.add(cabin[0], cabin[1], colour)
                placed += 1
    return placed


def setup_scene():
    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 4.0
    sun_data.angle = math.radians(2.0)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(48), 0.0, math.radians(35))
    bpy.context.scene.collection.objects.link(sun)

    cam_data = bpy.data.cameras.new("AerialCamera")
    cam_data.lens = 40.0
    cam_data.clip_end = 8000.0
    cam = bpy.data.objects.new("AerialCamera", cam_data)
    cam.location = (-140.0, -900.0, 620.0)
    cam.rotation_euler = (math.radians(52), 0.0, math.radians(-8))
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.55, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.1
    bpy.context.scene.world = world

    scene = bpy.context.scene
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 820


def save_and_export():
    OUT_DIR.mkdir(exist_ok=True)
    blend_path = HERE / "banilad_map.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    log("saved blend: {:s}".format(blend_path.name))

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for obj in meshes:
        obj.data.calc_loop_triangles()
    tris = sum(len(o.data.loop_triangles) for o in meshes)
    verts = sum(len(o.data.vertices) for o in meshes)
    log("mesh objects: {:d}   verts: {:d}   tris: {:d}".format(len(meshes), verts, tris))

    bpy.ops.object.select_all(action="SELECT")
    glb_path = OUT_DIR / "banilad_map.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path), export_format="GLB", export_apply=True,
        export_cameras=False, export_lights=False, export_yup=True,
    )
    log("exported glb: {:.2f} MB".format(glb_path.stat().st_size / 1048576))

    fbx_path = OUT_DIR / "banilad_map.fbx"
    bpy.ops.export_scene.fbx(
        filepath=str(fbx_path), apply_scale_options="FBX_SCALE_ALL",
        object_types={"MESH"}, mesh_smooth_type="FACE", path_mode="COPY",
    )
    log("exported fbx: {:.2f} MB".format(fbx_path.stat().st_size / 1048576))
    log("DONE")


main()
