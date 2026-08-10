"""The Cebu modular building kit -- pure geometry, no ``bpy``.

This is the ``parts.py`` that ``CITY_MASTER_PLAN.md`` s6.5 and
``CEBU_ARCHITECTURE_BIBLE.md`` s4 call for: one library that generates the whole
Cebu building taxonomy. Everything here returns ``(verts, faces)`` tuples or
writes through a ``batch`` with an ``.add(verts, faces, material, colors=None)``
method -- the exact convention ``build_map.py`` and ``landmarks.py`` already use
-- so a caller supplies the Blender plumbing and this module stays a pure,
importable, testable leaf (``import math`` only).

Two kinds of function live here:

* **[HAVE]** -- primitives and modules copied VERBATIM from ``build_map.py`` so
  the eventual rewire (``build_map.py`` ``from parts import ...``) is a clean
  delete-and-import with byte-identical geometry. **These are duplicated with
  ``build_map.py`` for now**, on purpose: writing them here first lets the kit be
  proven on the test plane before the 4200-line working generator is touched.
  When the rewire lands, ``build_map.py``'s copies are deleted, not these.
* **[NEW]** -- the Cebu detail vocabulary the map lacks entirely: party-wall
  shophouse bays, punched windows, awnings, signage bands, rolling shutters,
  cantilevered balconies, roof extensions.

Design law (``CEBU_ARCHITECTURE_BIBLE.md`` s0): PSX flat-shaded, no textures.
Detail is silhouette geometry plus material bands standing slightly PROUD of the
wall -- a recessed band is invisible, buried inside the solid wall. Every module
is costed in a few dozen triangles.

Coordinates are local metres; z is up. Modules build from a base of z=0 and are
placed by wrapping the batch in a ``LiftedBatch`` (the caller's job), exactly as
``tower_detail`` and the infill houses are.
"""

import math

# ---------------------------------------------------------------------------
# Constants (mirrored from build_map.py so the [HAVE] modules match verbatim)
# ---------------------------------------------------------------------------

# Ground-floor shopfront courses.
SHOPFRONT_SILL = 0.35
SHOPFRONT_HEAD = 2.7
SIGN_HEIGHT = 0.75
SIGN_COLOURS = ["Sign_Red", "Sign_Blue", "Sign_Yellow", "Sign_Green",
                "Sign_White"]

TOWER_BASE_HEIGHT = 7.5

ROOF_CLUTTER_MIN_AREA = 55.0
ROOF_CLUTTER_CHANCE = 0.62


# ===========================================================================
# [HAVE] Low-level primitives -- verbatim from build_map.py
# ===========================================================================

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


def hash_unit(n):
    """Deterministic [0, 1) from an integer. Stable across runs and platforms."""
    n = int(n) & 0xFFFFFFFF
    n = (n ^ 61) ^ (n >> 16)
    n = (n + (n << 3)) & 0xFFFFFFFF
    n = n ^ (n >> 4)
    n = (n * 0x27D4EB2D) & 0xFFFFFFFF
    n = n ^ (n >> 15)
    return n / 4294967296.0


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
                    scale = half / max(0.25, (mx / mlen) * n0[0] + (my / mlen) * n0[1])
                    off = (mx / mlen * scale, my / mlen * scale)
        if off is None:
            off = offsets[-1] if offsets else (0.0, 0.0)
        offsets.append(off)
    return offsets


def offset_polyline(pts, distance):
    pts = dedupe(pts)
    if len(pts) < 2:
        return []
    offsets = miter_offsets(pts, abs(distance))
    sign = 1.0 if distance >= 0 else -1.0
    return [(p[0] + o[0] * sign, p[1] + o[1] * sign) for p, o in zip(pts, offsets)]


def offset_ring(pts, distance):
    """Offset a closed ring, mitring every corner including the seam.

    Positive distance shrinks a counter-clockwise ring.
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
            if length < 1e-6:
                out.append(p)
                continue
            mx, my = mx / length, my / length
            scale = 1.0 / max(0.25, mx * n0[0] + my * n0[1])
        out.append((p[0] + mx * distance * scale, p[1] + my * distance * scale))
    return out


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


def flat_polygon(pts, z):
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]
    return [(x, y, z) for x, y in pts], [tuple(range(len(pts)))]


# ===========================================================================
# [HAVE] Building-form modules -- verbatim from build_map.py
# ===========================================================================

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

    e0 = at(-hu, -hv, 0.0)
    e1 = at(hu, -hv, 0.0)
    e2 = at(hu, hv, 0.0)
    e3 = at(-hu, hv, 0.0)
    ridge = max(0.0, hu - hv)
    r0 = at(-ridge, 0.0, rise)
    r1 = at(ridge, 0.0, rise)

    verts = [e0, e1, e2, e3, r0, r1]
    faces = [
        (0, 1, 5, 4),
        (2, 3, 4, 5),
        (1, 2, 5),
        (3, 0, 4),
        (3, 2, 1, 0),
    ]
    return verts, faces, rise


def shed_roof(pts, eave_z, overhang=0.45):
    """Single-slope tin roof as a thin slab."""
    (cx, cy), (ux, uy), half_u, half_v = min_area_rect(pts)
    vx, vy = -uy, ux
    hu, hv = half_u + overhang, half_v + overhang
    rise = min(1.5, max(0.4, hv * 0.36))
    thick = 0.12

    def at(du, dv, dz):
        return (cx + ux * du + vx * dv, cy + uy * du + vy * dv, eave_z + dz)

    top = [at(-hu, -hv, 0.0), at(hu, -hv, 0.0), at(hu, hv, rise), at(-hu, hv, rise)]
    low = [(p[0], p[1], p[2] - thick) for p in top]
    verts = low + top
    faces = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7),
    ]
    return verts, faces, rise


def parapet_roof(pts, top_z, parapet=0.85, inset=0.4):
    """Flat roof slab with a raised parapet wall around the edge."""
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]

    inner = offset_ring(pts, inset)
    if len(inner) != len(pts):
        inner = pts

    n = len(pts)
    verts = []
    verts += [(x, y, top_z) for x, y in inner]
    verts += [(x, y, top_z + parapet) for x, y in pts]
    verts += [(x, y, top_z + parapet) for x, y in inner]

    faces = [tuple(range(n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((n + i, n + j, 2 * n + j, 2 * n + i))
        faces.append((2 * n + i, 2 * n + j, j, i))
    return verts, faces


def window_bands(pts, base_z, top_z, floor_height=3.3, band=1.5, bulge=0.06,
                 first_floor=3.6, min_edge=2.0, inset=0.85):
    """Recessed glazing bands, one per floor, wrapped around the walls."""
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]

    verts = []
    faces = []
    n = len(pts)
    floor = base_z + first_floor
    guard = 0
    while floor + band < top_z - 0.6 and guard < 40:
        guard += 1
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            dx, dy = x1 - x0, y1 - y0
            length = math.hypot(dx, dy)
            if length < min_edge:
                continue
            t = min(inset / length, 0.3)
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


def band_ring(pts, z0, z1, offset=0.12):
    """Horizontal band wrapped around a footprint, standing proud of the wall."""
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


def shopfront_band(batch, mats, ring, base_z, tint_seed):
    """Dark shopfront opening plus a sign fascia above it, around a footprint."""
    v, f = band_ring(ring, base_z + SHOPFRONT_SILL, base_z + SHOPFRONT_HEAD,
                     offset=0.05)
    if not f:
        return 0
    batch.add(v, f, mats["Shopfront_Glass"])
    v, f = band_ring(ring, base_z + SHOPFRONT_HEAD,
                     base_z + SHOPFRONT_HEAD + SIGN_HEIGHT, offset=0.14)
    sign = SIGN_COLOURS[tint_seed % len(SIGN_COLOURS)]
    batch.add(v, f, mats[sign])
    return 1


def tower_detail(batch, mats, ring, height, glass=None, base_mat="Tower_Base",
                 crown_mat="Tower_Crown", plant=True):
    """Base, glazing, crown and rooftop plant for a tall building."""
    if height < 12.0 or len(ring) < 3:
        return

    base_h = min(TOWER_BASE_HEIGHT, height * 0.28)
    v, f = band_ring(ring, 0.0, base_h, offset=0.18)
    batch.add(v, f, mats[base_mat])
    v, f = band_ring(ring, base_h, base_h + 0.45, offset=0.34)
    batch.add(v, f, mats["Tower_Crown"])

    if glass:
        floor = base_h + 1.6
        guard = 0
        while floor + 1.5 < height - 3.0 and guard < 60:
            guard += 1
            v, f = band_ring(ring, floor, floor + 1.5, offset=0.10)
            batch.add(v, f, mats[glass])
            floor += 3.4

    v, f = band_ring(ring, height - 2.6, height - 0.3, offset=0.22)
    batch.add(v, f, mats[crown_mat])

    if plant:
        centre, axis, half_u, half_v = min_area_rect(ring)
        pu = min(6.5, max(2.2, half_u * 0.18))
        pv = min(6.5, max(2.2, half_v * 0.18))
        v, f = box(centre[0], centre[1], height + 0.85, height + 4.2,
                   pu, pv, math.atan2(axis[1], axis[0]))
        batch.add(v, f, mats["Tower_Plant"])


def roof_clutter_field(batch, mats, ring, top_z, seed, limit=6):
    """Scatter tanks, aircon boxes and antenna masts on one small flat roof."""
    area = abs(signed_area(ring))
    if area < ROOF_CLUTTER_MIN_AREA:
        return 0
    if hash_unit(seed * 7919 + 13) > ROOF_CLUTTER_CHANCE:
        return 0
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    cx = sum(xs) / len(xs)
    cy = sum(ys) / len(ys)
    span = min(max(xs) - min(xs), max(ys) - min(ys))
    if span < 3.5:
        return 0

    count = 1 + int(hash_unit(seed * 104729) * min(limit, 1 + area / 90.0))
    placed = 0
    for i in range(count):
        ox = (hash_unit(seed * 31 + i * 977) - 0.5) * span * 0.55
        oy = (hash_unit(seed * 37 + i * 1013) - 0.5) * span * 0.55
        px, py = cx + ox, cy + oy
        if not point_in_polygon(px, py, ring):
            continue
        kind = int(hash_unit(seed * 41 + i * 613) * 3)
        if kind == 0:
            r = 0.55 + hash_unit(seed + i) * 0.3
            v, f = box(px, py, top_z, top_z + 1.1 + hash_unit(seed + i * 3) * 0.5,
                       r, r)
            batch.add(v, f, mats["Roof_Tank"])
        elif kind == 1:
            w = 0.6 + hash_unit(seed + i * 5) * 0.5
            d = 0.5 + hash_unit(seed + i * 7) * 0.4
            v, f = box(px, py, top_z, top_z + 0.7, w, d)
            batch.add(v, f, mats["Tower_Plant"])
        else:
            v, f = box(px, py, top_z, top_z + 1.8 + hash_unit(seed + i * 11) * 1.4,
                       0.06, 0.06)
            batch.add(v, f, mats["Pole"])
        placed += 1
    return placed


# ===========================================================================
# [NEW] Facade helpers -- the frame every new module hangs detail on
# ===========================================================================
#
# A facade edge is given as two ground points ``a`` (left) and ``b`` (right) as
# seen from OUTSIDE, plus an outward unit normal ``out``. A point on that facade
# is (fraction ``t`` along a..b, distance ``proj`` proud of the wall, height
# ``z``). This is the same _panel scheme landmarks.py uses for Metro's banners.

def edge_of(ring, i, outward_from=None):
    """Return (a, b, out) for edge i of a footprint ring.

    ``out`` is the unit normal pointing away from the ring centroid (or from
    ``outward_from`` if given), so detail projects toward the street.
    """
    n = len(ring)
    a = ring[i]
    b = ring[(i + 1) % n]
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy) or 1.0
    nx, ny = dy / length, -dx / length
    if outward_from is None:
        cx = sum(p[0] for p in ring) / n
        cy = sum(p[1] for p in ring) / n
    else:
        cx, cy = outward_from
    mx, my = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
    if (mx + nx - cx) ** 2 + (my + ny - cy) ** 2 < (mx - cx) ** 2 + (my - cy) ** 2:
        nx, ny = -nx, -ny
    return a, b, (nx, ny)


def _fp(a, b, out, t, proj, z):
    """A single point on a facade frame."""
    return (a[0] + (b[0] - a[0]) * t + out[0] * proj,
            a[1] + (b[1] - a[1]) * t + out[1] * proj, z)


def facade_panel(a, b, out, t0, t1, z0, z1, proj):
    """A flat quad standing ``proj`` proud of a facade, between two fractions.

    Wound so the face normal points OUTWARD along ``out``. This matters in a
    backface-culling engine (Godot culls back faces by default): a panel wound
    the wrong way is invisible in-game while still rendering fine in Blender's
    two-sided Cycles, so every window, sign and shutter silently disappears.

    The winding CANNOT be a fixed constant. Ordering the quad bl->br->tr->tl
    gives a normal of (dy, -dx); whether that is the outward direction depends
    on how the caller derived ``out`` -- `edge_of` flips its normal for rings
    wound one way and not the other. Both fixed orders were tried and each is
    correct for exactly half the callers. So the order is chosen here by testing
    the candidate normal against ``out``.

    Vertex order is always 0=bl, 1=br, 2=tr, 3=tl, so callers assigning UVs by
    index are unaffected by the winding choice.
    """
    v = [_fp(a, b, out, t0, proj, z0), _fp(a, b, out, t1, proj, z0),
         _fp(a, b, out, t1, proj, z1), _fp(a, b, out, t0, proj, z1)]
    dx, dy = b[0] - a[0], b[1] - a[1]
    outward = (dy * out[0] - dx * out[1]) >= 0.0
    return v, [(0, 1, 2, 3) if outward else (0, 3, 2, 1)]


def _edge_length(a, b):
    return math.hypot(b[0] - a[0], b[1] - a[1])


# ===========================================================================
# [NEW] Cebu detail modules
# ===========================================================================

def punched_windows(batch, mats, a, b, out, base_z, top_z, floor_h=3.3,
                    first=4.6, cols=None, win_w=1.05, win_h=1.5,
                    mat="Window", proud=0.04, seed=0):
    """Discrete window openings on one facade, as proud dark quads.

    A band says "office"; separate punched holes say "apartment/old commercial".
    Windows are inset from each end and jittered slightly in height off the seed
    so a repainted, added-onto facade does not read as a perfect grid.
    """
    length = _edge_length(a, b)
    if length < 2.0:
        return 0
    if cols is None:
        cols = max(1, int(length // 2.6))
    made = 0
    margin = min(0.9, length * 0.12)
    usable = length - 2 * margin
    pitch = usable / cols
    z = base_z + first
    row = 0
    while z + win_h < top_z - 0.8:
        for c in range(cols):
            centre = (margin + pitch * (c + 0.5)) / length
            half = (win_w * 0.5) / length
            jz = (hash_unit(seed * 131 + row * 17 + c * 7) - 0.5) * 0.25
            v, f = facade_panel(a, b, out, centre - half, centre + half,
                                z + jz, z + jz + win_h, proud)
            batch.add(v, f, mats[mat])
            made += 1
        row += 1
        z += floor_h
    return made


def awning(batch, mats, a, b, out, z, projection=1.6, drop=0.55, thick=0.14,
           mat="Awning_Steel", t0=0.02, t1=0.98):
    """A projecting sidewalk awning: a sloped slab with a small front fascia.

    The single most street-defining Cebu commercial detail -- every frontage
    carries one, and it is what makes a Colon street section read correct.
    """
    inner_z, outer_z = z, z - drop
    il = _fp(a, b, out, t0, 0.0, inner_z)
    ir = _fp(a, b, out, t1, 0.0, inner_z)
    orr = _fp(a, b, out, t1, projection, outer_z)
    ol = _fp(a, b, out, t0, projection, outer_z)
    # underside, dropped by thick
    ilu = (il[0], il[1], il[2] - thick)
    iru = (ir[0], ir[1], ir[2] - thick)
    orru = (orr[0], orr[1], orr[2] - thick)
    olu = (ol[0], ol[1], ol[2] - thick)
    verts = [il, ir, orr, ol, ilu, iru, orru, olu]
    faces = [
        (0, 1, 2, 3),          # top slope
        (4, 7, 6, 5),          # underside
        (3, 2, 6, 7),          # front fascia (the lit edge)
        (0, 3, 7, 4),          # left return
        (1, 5, 6, 2),          # right return
    ]
    batch.add(verts, faces, mats[mat])
    return 1


def signage_band(batch, mats, a, b, out, z0, z1, mat, proud=0.16,
                 t0=0.0, t1=1.0, reveal=None):
    """A proud signage fascia -- the flat-colour stand-in for the atlas quad.

    When the signage atlas lands (CITY_MASTER_PLAN s6.5) this is the band it is
    UV-mapped onto; until then it carries a flat ``Sign_*`` colour, which is what
    the map does today. An optional darker ``reveal`` behind reads it as hung.
    """
    if reveal is not None:
        v, f = facade_panel(a, b, out, max(0.0, t0 - 0.01), min(1.0, t1 + 0.01),
                            z0 - 0.18, z1 + 0.18, proud * 0.5)
        batch.add(v, f, mats[reveal])
    v, f = facade_panel(a, b, out, t0, t1, z0, z1, proud)
    batch.add(v, f, mats[mat])
    return 1


def shutter(batch, mats, a, b, out, z0, z1, mat="Shutter_Steel",
            frame="Metro_Reveal", t0=0.04, t1=0.96):
    """Ground-floor rolling steel shutter: a dark frame with a proud panel.

    The jeepney-scale shop opening every downtown ground floor is made of --
    reads Filipino at eye level before the massing does.
    """
    v, f = facade_panel(a, b, out, t0 - 0.03, t1 + 0.03, z0, z1 + 0.25, 0.02)
    batch.add(v, f, mats[frame])
    v, f = facade_panel(a, b, out, t0, t1, z0 + 0.06, z1, 0.09)
    batch.add(v, f, mats[mat])
    return 1


def balcony(batch, mats, a, b, out, z, t0, t1, depth=1.2, rail_h=1.0,
            slab_mat="Wall_Concrete_2", rail_mat="Rail_Metal", slab_thick=0.28):
    """A cantilevered balcony slab with a railing above it.

    The defining detail of mixed commercial (B) and apartments (D): stacked,
    irregular, mixed rails, implied laundry. Placed on upper street-facing bays.
    """
    # slab: from the wall out to `depth`, a thin box
    bl = _fp(a, b, out, t0, 0.0, z)
    br = _fp(a, b, out, t1, 0.0, z)
    fr = _fp(a, b, out, t1, depth, z)
    fl = _fp(a, b, out, t0, depth, z)
    top = [bl, br, fr, fl]
    low = [(p[0], p[1], p[2] - slab_thick) for p in top]
    verts = top + low
    faces = [(0, 1, 2, 3), (4, 7, 6, 5),
             (0, 3, 7, 4), (1, 5, 6, 2), (3, 2, 6, 7), (0, 4, 5, 1)]
    batch.add(verts, faces, mats[slab_mat])
    # railing: three thin proud panels (front + two returns) standing on the lip
    fr_v, fr_f = facade_panel(a, b, out, t0, t1, z, z + rail_h, depth)
    batch.add(fr_v, fr_f, mats[rail_mat])
    lz = [_fp(a, b, out, t0, 0.0, z), _fp(a, b, out, t0, depth, z),
          _fp(a, b, out, t0, depth, z + rail_h), _fp(a, b, out, t0, 0.0, z + rail_h)]
    batch.add(lz, [(0, 1, 2, 3)], mats[rail_mat])
    rz = [_fp(a, b, out, t1, 0.0, z), _fp(a, b, out, t1, depth, z),
          _fp(a, b, out, t1, depth, z + rail_h), _fp(a, b, out, t1, 0.0, z + rail_h)]
    batch.add(rz, [(0, 1, 2, 3)], mats[rail_mat])
    return 1


def roof_extension(batch, mats, ring, top_z, wall_mat, roof_mat,
                   coverage=0.55, seed=0):
    """A partial unfinished upper floor -- the 'built up as money allowed' tell.

    A smaller box on part of the roof with a shed roof and (often) a different
    wall colour. Ties into the Bible's imperfection system.
    """
    centre, axis, half_u, half_v = min_area_rect(ring)
    ux, uy = axis
    vx, vy = -uy, ux
    cu = math.sqrt(max(0.05, coverage))
    hu = half_u * cu * 0.9
    hv = half_v * cu * 0.9
    # push it to one side of the roof rather than centring it
    push = half_u * (0.3 * (hash_unit(seed * 53 + 3) - 0.5))
    cx = centre[0] + ux * push
    cy = centre[1] + uy * push
    ext_h = 2.6 + hash_unit(seed * 59 + 7) * 0.6
    corners = [
        (cx + ux * hu + vx * hv, cy + uy * hu + vy * hv),
        (cx - ux * hu + vx * hv, cy - uy * hu + vy * hv),
        (cx - ux * hu - vx * hv, cy - uy * hu - vy * hv),
        (cx + ux * hu - vx * hv, cy + uy * hu - vy * hv),
    ]
    v, f = walls(corners, top_z, top_z + ext_h)
    batch.add(v, f, mats[wall_mat])
    v, f, _rise = shed_roof(corners, top_z + ext_h, overhang=0.25)
    batch.add(v, f, mats[roof_mat])
    return 1


# ===========================================================================
# [NEW] party_wall_bay -- the composed Category-A/E workhorse
# ===========================================================================

def party_wall_bay(batch, mats, origin, along, out, width, depth, height,
                   wall_mat, sign_mat, awning_mat, seed,
                   ground_h=4.4, has_shutter=True, banner=False):
    """One zero-setback commercial shophouse bay, articulated on its street face.

    ``origin`` is the front-LEFT ground corner; ``along`` is the unit vector to
    the right along the street; ``out`` is the outward unit normal (toward the
    street). The bay shares side walls with its neighbours, so a row of these
    tiled along ``along`` makes a continuous Colon/Carbon block face.

    Builds from local z=0 -- wrap the batch in a LiftedBatch to place it. Uses
    HAVE modules (walls, parapet_roof, roof_clutter_field) and NEW ones
    (punched_windows, shutter, signage_band, awning). ~120-180 tris per bay.
    """
    ox, oy = origin
    ax, ay = along
    nx, ny = out
    # footprint ring: front-left, front-right, back-right, back-left
    fl = (ox, oy)
    fr = (ox + ax * width, oy + ay * width)
    br = (fr[0] - nx * depth, fr[1] - ny * depth)
    bl = (fl[0] - nx * depth, fl[1] - ny * depth)
    ring = [fl, fr, br, bl]

    # shell + flat roof with parapet
    v, f = walls(ring, 0.0, height)
    batch.add(v, f, mats[wall_mat])
    v, f = parapet_roof(ring, height, parapet=0.7, inset=0.3)
    batch.add(v, f, mats[wall_mat])

    # the street facade frame (front-left -> front-right, outward normal)
    fa, fb, fout = fl, fr, out

    # ground floor: rolling shutter (or glazed opening) under a signage fascia
    if has_shutter:
        shutter(batch, mats, fa, fb, fout, 0.2, ground_h - 1.0)
    signage_band(batch, mats, fa, fb, fout, ground_h - 1.0, ground_h + 0.1,
                 sign_mat, proud=0.16, reveal="Metro_Reveal")
    awning(batch, mats, fa, fb, fout, ground_h - 1.2, projection=1.6,
           drop=0.5, mat=awning_mat)

    # upper floors: punched windows on the street face
    punched_windows(batch, mats, fa, fb, fout, 0.0, height, floor_h=3.3,
                    first=ground_h + 1.6, cols=max(2, int(width // 3.0)),
                    seed=seed)

    # an optional hung vertical banner, the way Colon upper facades carry them
    if banner:
        bt = 0.12 + 0.5 * hash_unit(seed * 71 + 5)
        signage_band(batch, mats, fa, fb, fout, ground_h + 2.0, height - 1.5,
                     SIGN_COLOURS[seed % len(SIGN_COLOURS)], proud=0.3,
                     t0=bt, t1=bt + 0.12, reveal="Metro_Reveal")

    # roofscape
    roof_clutter_field(batch, mats, ring, height, seed)
    return ring
