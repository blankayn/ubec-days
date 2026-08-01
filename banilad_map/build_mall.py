"""Detailed model of Gaisano Country Mall.

The plan comes from OSM -- nine surveyed footprints forming an arcaded ring
around the car park -- and the elevation comes from the reference photo. Only
the treatment is authored: bay rhythm, arch profile, storey heights, roof pitch.

Unlike the low-poly version in build_map.py, the arcades here are real openings.
Each bay is built additively from a pier, a segmented round arch and a spandrel,
with a dark back wall behind, so you can see into the arcade instead of at a
painted band.

    blender --background --python build_mall.py

Writes assets/buildings/gaisano_country_mall.glb, built at absolute map
coordinates so Godot can instance it at the origin: no placement maths, no
rotation to get wrong, and it sits on z=0 like the rest of the map.
"""

import json
import math
import pathlib
import sys

import bpy

HERE = pathlib.Path(__file__).parent
PROJECT = HERE.parent
OSM = HERE / "banilad_osm.json"
OUT = PROJECT / "assets" / "buildings" / "gaisano_country_mall.glb"

# Same local projection as build_map.py, so the model lands on the map.
LAT0 = 10.3345
LON0 = 123.9115
METRES_PER_DEG_LAT = 110540.0
METRES_PER_DEG_LON = 111320.0 * math.cos(math.radians(LAT0))

#   way id: (ground floor height, eaves height, arcade tiers)
WINGS = {
    93839848:   (5.2, 10.6, 2),
    1279791577: (5.2, 10.4, 2),
    93839827:   (4.8, 9.2, 2),
    93839832:   (4.6, 8.8, 2),
    93839836:   (4.6, 8.8, 2),
    93839839:   (4.6, 9.4, 2),
    93839843:   (4.6, 9.4, 2),
    93839855:   (4.4, 7.8, 1),
    93839860:   (4.4, 7.4, 1),
}
PARCEL_WAY = 1364251197
MAIN_BAR = 93839848

# The surveyed footprints are solid blocks, not a thin ring, and the car park
# is outside them on the avenue side. So the arcade fronts east, the way it
# does in the reference photo -- not inward toward the parcel centre, which is
# buried inside the mass.
FRONT_DIRECTION = (0.985, 0.174)   # east, tilted to the avenue's bearing
FRONT_DOT = 0.30

# --- Elevation, read off the reference photo -------------------------------
BAY_TARGET = 5.4          # arches repeat about every 5.4 m
PIER_WIDTH = 1.05
PIER_DEPTH = 0.85
ARCH_SEGMENTS = 7         # per half arch; 7 reads as round without wasting tris
ARCH_RISE_RATIO = 0.46    # arch springs to this fraction of the opening width
ARCADE_DEPTH = 2.6        # how far the arcade is recessed behind the piers
BAND_HEIGHT = 0.55        # floor band between storeys
CORNICE_HEIGHT = 0.7
BALUSTRADE_HEIGHT = 1.0
BALUSTER_STEP = 0.55
ROOF_PITCH = 0.42         # rise per metre of run on the clay tile roofs
ROOF_OVERHANG = 1.3

# --- Palette, sampled from the reference -----------------------------------
PALETTE = {
    "Mall_Stucco":   (0.902, 0.867, 0.796),
    "Mall_Trim":     (0.957, 0.941, 0.906),
    "Mall_Tile":     (0.741, 0.353, 0.184),
    "Mall_TileDark": (0.573, 0.259, 0.133),
    "Mall_Shadow":   (0.129, 0.114, 0.102),
    "Mall_Glass":    (0.243, 0.290, 0.310),
    "Mall_Sign":     (0.545, 0.161, 0.129),
    "Mall_Stone":    (0.510, 0.478, 0.443),
    # The flat part of the roof behind the tiled skirt. Tiling it too makes a
    # 95 m footprint read as one enormous tent.
    "Mall_Deck":     (0.412, 0.400, 0.376),
}


def log(msg):
    print("[mall] {:s}".format(msg))
    sys.stdout.flush()


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

class Batch:
    """Accumulates faces into one multi-material mesh."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.slots = []
        self.face_slots = []
        self._slot_of = {}

    def add(self, verts, faces, material):
        if not faces:
            return
        if material not in self._slot_of:
            self._slot_of[material] = len(self.slots)
            self.slots.append(material)
        slot = self._slot_of[material]
        offset = len(self.verts)
        self.verts.extend(verts)
        for f in faces:
            self.faces.append(tuple(i + offset for i in f))
            self.face_slots.append(slot)

    def to_object(self, name):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.update()
        for material_name in self.slots:
            mesh.materials.append(bpy.data.materials[material_name])
        for polygon, slot in zip(mesh.polygons, self.face_slots):
            polygon.material_index = slot
        mesh.validate()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj

    def triangle_count(self):
        return sum(len(f) - 2 for f in self.faces)


def quad(a, b, c, d):
    return [a, b, c, d], [(0, 1, 2, 3)]


def prism(points, z0, z1):
    """Vertical walls plus a flat cap over a closed ring of points."""
    n = len(points)
    verts = [(p[0], p[1], z0) for p in points] + [(p[0], p[1], z1) for p in points]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces.append(tuple(range(n, 2 * n)))
    return verts, faces


def box(cx, cy, z0, z1, half_u, half_v, angle):
    ux, uy = math.cos(angle), math.sin(angle)
    vx, vy = -uy, ux
    ring = [
        (cx - ux * half_u - vx * half_v, cy - uy * half_u - vy * half_v),
        (cx + ux * half_u - vx * half_v, cy + uy * half_u - vy * half_v),
        (cx + ux * half_u + vx * half_v, cy + uy * half_u + vy * half_v),
        (cx - ux * half_u + vx * half_v, cy - uy * half_u + vy * half_v),
    ]
    return prism(ring, z0, z1)


def signed_area(ring):
    total = 0.0
    for i in range(len(ring)):
        x0, y0 = ring[i]
        x1, y1 = ring[(i + 1) % len(ring)]
        total += x0 * y1 - x1 * y0
    return total * 0.5


def as_ccw(ring):
    return ring if signed_area(ring) > 0 else ring[::-1]


def offset_ring(ring, distance):
    """Offset a closed ring, mitring every corner. Positive shrinks a CCW ring."""
    n = len(ring)
    out = []
    for i in range(n):
        prev_p = ring[(i - 1) % n]
        cur = ring[i]
        next_p = ring[(i + 1) % n]
        n0 = edge_normal(prev_p, cur)
        n1 = edge_normal(cur, next_p)
        mx, my = n0[0] + n1[0], n0[1] + n1[1]
        length = math.hypot(mx, my)
        if length < 1e-9:
            out.append(cur)
            continue
        mx, my = mx / length, my / length
        cosine = max(0.35, mx * n0[0] + my * n0[1])
        step = distance / cosine
        out.append((cur[0] - mx * step, cur[1] - my * step))
    return out


def edge_normal(p0, p1):
    """Outward normal of an edge of a counter-clockwise ring."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dy)
    if length < 1e-9:
        return (0.0, 0.0)
    return (dy / length, -dx / length)


def hip_roof(batch, ring, eaves_z, material, edge_material=None,
             pitch=ROOF_PITCH, overhang=ROOF_OVERHANG, max_rise=4.2):
    """Clay tile hip following the true outline, not a bounding rectangle."""
    outer = offset_ring(ring, -overhang)
    inset = min(max_rise / max(pitch, 0.05), _inradius(ring) * 0.72)
    rise = inset * pitch
    inner = offset_ring(ring, inset - overhang)

    n = len(ring)
    verts = [(p[0], p[1], eaves_z) for p in outer]
    verts += [(p[0], p[1], eaves_z + rise) for p in inner]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    batch.add(verts, faces, material)

    ridge_verts = [(p[0], p[1], eaves_z + rise) for p in inner]
    batch.add(ridge_verts, [tuple(range(n))], edge_material or material)
    return eaves_z + rise


def _inradius(ring):
    cx = sum(p[0] for p in ring) / len(ring)
    cy = sum(p[1] for p in ring) / len(ring)
    best = 1e9
    for i in range(len(ring)):
        p0, p1 = ring[i], ring[(i + 1) % len(ring)]
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        length = math.hypot(dx, dy)
        if length < 1e-9:
            continue
        best = min(best, abs((cx - p0[0]) * dy - (cy - p0[1]) * dx) / length)
    return best


def band(batch, ring, z0, z1, material, bulge=0.18):
    """A cornice or floor band standing proud of the wall it sits on.

    Recessed bands are invisible -- they sit inside the wall -- so this always
    steps outward.
    """
    outer = offset_ring(ring, -bulge)
    verts, faces = prism(outer, z0, z1)
    batch.add(verts, faces, material)


# ---------------------------------------------------------------------------
# The arcade: piers, round arches, spandrels
# ---------------------------------------------------------------------------

def arch_bay(batch, p0, p1, normal, z0, z1, materials, with_balustrade=False):
    """One bay of arcade between two pier centres, seen from `normal`.

    Built additively: the opening is the gap left between the pier faces and
    under the arch, with a recessed back wall closing it off.
    """
    ux, uy = p1[0] - p0[0], p1[1] - p0[1]
    span = math.hypot(ux, uy)
    if span < 1e-6:
        return
    ux, uy = ux / span, uy / span
    nx, ny = normal

    opening = span - PIER_WIDTH
    if opening <= 0.6:
        return
    rise = opening * ARCH_RISE_RATIO
    spring_z = z1 - CORNICE_HEIGHT - rise
    if spring_z <= z0 + 1.2:
        spring_z = z0 + max(1.2, (z1 - z0) * 0.45)
        rise = max(0.5, z1 - CORNICE_HEIGHT - spring_z)

    mid = ((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5)
    half = opening * 0.5

    # Recessed back wall, which is what makes the opening read as depth.
    back = (mid[0] - nx * ARCADE_DEPTH, mid[1] - ny * ARCADE_DEPTH)
    verts, faces = box(back[0], back[1], z0, z1,
                       span * 0.5, 0.12, math.atan2(uy, ux))
    batch.add(verts, faces, materials["back"])

    # Arch ring: a strip of quads following the semicircle.
    front = 0.0
    depth = ARCADE_DEPTH
    prev_outer = None
    prev_inner = None
    for step in range(ARCH_SEGMENTS + 1):
        t = step / float(ARCH_SEGMENTS)
        angle = math.pi * t
        ox = mid[0] - ux * half * math.cos(angle)
        oy = mid[1] - uy * half * math.cos(angle)
        oz = spring_z + rise * math.sin(angle)
        outer_pt = (ox, oy, oz)
        inner_pt = (ox - nx * depth, oy - ny * depth, oz)
        if prev_outer is not None:
            batch.add([prev_outer, outer_pt, inner_pt, prev_inner],
                      [(0, 1, 2, 3)], materials["soffit"])
        prev_outer, prev_inner = outer_pt, inner_pt

    # Spandrel above the arch, between its crown and the cornice.
    crown_z = spring_z + rise
    if z1 - CORNICE_HEIGHT > crown_z + 0.05:
        for side in (-1, 1):
            corner = (mid[0] + ux * half * side, mid[1] + uy * half * side)
            batch.add(
                [(corner[0], corner[1], crown_z),
                 (corner[0], corner[1], z1 - CORNICE_HEIGHT),
                 (mid[0], mid[1], z1 - CORNICE_HEIGHT),
                 (mid[0], mid[1], crown_z)],
                [(0, 1, 2, 3)], materials["wall"])

    if with_balustrade:
        balustrade(batch, p0, p1, normal, z0, materials)


def balustrade(batch, p0, p1, normal, z0, materials):
    """Upper-storey railing: a rail on short balusters, as in the photo."""
    ux, uy = p1[0] - p0[0], p1[1] - p0[1]
    span = math.hypot(ux, uy)
    if span < 1e-6:
        return
    ux, uy = ux / span, uy / span
    nx, ny = normal
    inset = 0.15
    a = (p0[0] + ux * PIER_WIDTH * 0.5 - nx * inset,
         p0[1] + uy * PIER_WIDTH * 0.5 - ny * inset)
    b = (p1[0] - ux * PIER_WIDTH * 0.5 - nx * inset,
         p1[1] - uy * PIER_WIDTH * 0.5 - ny * inset)
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    if length < 0.4:
        return

    count = max(2, int(length / BALUSTER_STEP))
    for i in range(count + 1):
        t = i / float(count)
        px = a[0] + (b[0] - a[0]) * t
        py = a[1] + (b[1] - a[1]) * t
        verts, faces = box(px, py, z0, z0 + BALUSTRADE_HEIGHT - 0.14,
                           0.055, 0.055, math.atan2(uy, ux))
        batch.add(verts, faces, materials["trim"])
    mid = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5)
    verts, faces = box(mid[0], mid[1],
                       z0 + BALUSTRADE_HEIGHT - 0.14, z0 + BALUSTRADE_HEIGHT,
                       length * 0.5, 0.13, math.atan2(uy, ux))
    batch.add(verts, faces, materials["trim"])
    verts, faces = box(mid[0], mid[1], z0, z0 + 0.14,
                       length * 0.5, 0.13, math.atan2(uy, ux))
    batch.add(verts, faces, materials["trim"])


def arcaded_edge(batch, p0, p1, ground_h, eaves_h, tiers, materials):
    """Fill one footprint edge with bays of arcade, plus the piers between."""
    length = math.dist(p0, p1)
    if length < BAY_TARGET * 0.8:
        return 0
    bays = max(1, int(round(length / BAY_TARGET)))
    normal = edge_normal(p0, p1)
    ux, uy = (p1[0] - p0[0]) / length, (p1[1] - p0[1]) / length

    points = []
    for i in range(bays + 1):
        t = i / float(bays)
        points.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))

    storeys = [(0.0, ground_h, False)]
    if tiers >= 2:
        storeys.append((ground_h, eaves_h, True))

    for z0, z1, upper in storeys:
        for i in range(bays):
            arch_bay(batch, points[i], points[i + 1], normal, z0, z1,
                     materials, with_balustrade=upper)
        for point in points:
            verts, faces = box(point[0], point[1], 0.0, z1,
                               PIER_WIDTH * 0.5, PIER_DEPTH * 0.5,
                               math.atan2(uy, ux))
            batch.add(verts, faces, materials["wall"])
    return bays


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------

def load_rings():
    data = json.loads(OSM.read_text(encoding="utf-8"))
    rings = {}
    for element in data["elements"]:
        if element.get("type") != "way" or "geometry" not in element:
            continue
        pts = [((p["lon"] - LON0) * METRES_PER_DEG_LON,
                (p["lat"] - LAT0) * METRES_PER_DEG_LAT)
               for p in element["geometry"]]
        if len(pts) >= 2 and math.dist(pts[0], pts[-1]) < 0.5:
            pts = pts[:-1]
        rings[element["id"]] = pts
    return rings


def build_materials():
    for name, colour in PALETTE.items():
        material = bpy.data.materials.new(name)
        material.use_nodes = True
        bsdf = material.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (
            srgb_to_linear(colour[0]), srgb_to_linear(colour[1]),
            srgb_to_linear(colour[2]), 1.0)
        bsdf.inputs["Roughness"].default_value = 0.88
        bsdf.inputs["Metallic"].default_value = 0.0


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def court_centre(rings):
    parcel = rings.get(PARCEL_WAY)
    if parcel:
        xs = [p[0] for p in parcel]
        ys = [p[1] for p in parcel]
        return ((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5)
    return (-84.5, 517.4)


def build_mall(batch, rings):
    materials = {
        "wall": "Mall_Stucco",
        "trim": "Mall_Trim",
        "back": "Mall_Shadow",
        "soffit": "Mall_Trim",
        "glass": "Mall_Glass",
    }
    arcade_bays = 0

    for way_id, (ground_h, eaves_h, tiers) in sorted(WINGS.items()):
        ring = rings.get(way_id)
        if not ring or len(ring) < 3:
            continue
        ring = as_ccw(ring)

        # Solid core, so the building is closed from behind.
        core = offset_ring(ring, ARCADE_DEPTH * 0.5)
        if len(core) >= 3 and abs(signed_area(core)) > 25.0:
            verts, faces = prism(core, 0.0, eaves_h)
            batch.add(verts, faces, materials["wall"])

        for i in range(len(ring)):
            p0, p1 = ring[i], ring[(i + 1) % len(ring)]
            normal = edge_normal(p0, p1)
            faces_front = (normal[0] * FRONT_DIRECTION[0] +
                           normal[1] * FRONT_DIRECTION[1]) > FRONT_DOT
            if faces_front:
                arcade_bays += arcaded_edge(batch, p0, p1, ground_h, eaves_h,
                                            tiers, materials)
            else:
                verts, faces = prism([p0, p1,
                                      (p1[0] - normal[0] * 0.4, p1[1] - normal[1] * 0.4),
                                      (p0[0] - normal[0] * 0.4, p0[1] - normal[1] * 0.4)],
                                     0.0, eaves_h)
                batch.add(verts, faces, materials["wall"])

        band(batch, ring, eaves_h - CORNICE_HEIGHT, eaves_h, "Mall_Trim")
        hip_roof(batch, ring, eaves_h, "Mall_Tile", "Mall_Deck")

    log("arcade bays: {:d}".format(arcade_bays))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_materials()
    rings = load_rings()
    batch = Batch()
    build_mall(batch, rings)
    obj = batch.to_object("GaisanoCountryMall")
    log("triangles: {:d}".format(batch.triangle_count()))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(OUT), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True,
        export_cameras=False, export_lights=False, export_materials="EXPORT")
    log("wrote {:s} ({:.2f} MB)".format(OUT.name, OUT.stat().st_size / 1048576))


main()
