"""Hand-authored massing for the landmarks a Cebuano recognises on sight.

`build_map.py` extrudes ten thousand OSM footprints into prisms, which is right
for the fabric and wrong for the dozen places that carry the city's identity.
Fort San Pedro is a triangular bastion fort, not a 6 m box on a triangular
outline; Fuente Osmeña is a fountain in a rotunda, and OSM stores it as three
overlapping circular carriageways with nothing in the middle at all.

This module holds the exceptions. It follows the rule the existing landmark
builders set: **geometry for silhouette, material bands for detail.** Massing,
roof form and anything that changes the outline against the sky are real
polygons; mullions, arcades and signage are recessed or proud bands.

Everything here is BREADTH-first -- correct footprint, correct height, correct
silhouette, plausible materials. None of it is at the surveyed-wing fidelity of
`build_country_mall`. That is deliberate and is the agreed scope: nine places
that read as themselves beats two that are perfect while Colon is still a row
of white boxes.

Dimensions come from the OSM footprints the map already draws (so the buildings
land exactly where the roads and terrain put them) plus published figures for
heights, which OSM almost never carries here. Sources for the non-obvious ones
are cited at each builder.

Coordinates are Blender XY metres; Godot z is the negation of y. Every builder
takes a batch already wrapped so that z=0 is the local ground -- callers pass a
`LiftedBatch`, exactly as the UC and mall builders are called.
"""

import math

# ---------------------------------------------------------------------------
# OSM way ids. These are the identities that must survive an OSM re-fetch;
# `name` tags are not stable (Cebu has many "Carbon Unit 3" style duplicates and
# Blender appends .001 to repeated object names).
# ---------------------------------------------------------------------------

METRO_COLON_WAY = 230174493        # "Metro Department Store", 7 levels
COLON_CORNER_BLOCK_WAY = 964503684  # the chamfered corner block opposite it

FORT_SAN_PEDRO_WAY = 332819231
MAGELLAN_PAVILION_WAY = 94081127
BASILICA_BELFRY_WAY = 1332378587
COLON_OBELISK_WAY = 1290814817

CARBON_HALL_WAYS = (
    241568591,    # Carbon Unit 3 Public Market
    335725378,    # Carbon Unit 1 Public Market
    335725779,    # Carbon Interim Public Market
)

PIER_WAYS = (
    1424897881,   # Cebu Port Pier 1
    1425051611,   # Cebu Pier 2
)

# The MALL BUILDING, not the 80,154 m2 commercial parcel (1290804007) that
# carries the same name -- extruding the parcel doubles the footprint and
# swallows the car parks and service yards around it.
AYALA_CENTER_WAY = 29261598        # building=yes, levels=5, 45,311 m2
# Cebu IT Park, a DIFFERENT district 1.4 km north of Ayala Center.
IT_PARK_GARDEN_WAY = 392888930     # "Garden Bloc", leisure=park, 16,814 m2

# Fuente Osmeña is a rotunda, not a building: OSM has only the three circular
# carriageway ways. The park is whatever they enclose, so the centre and radius
# are measured from the largest of them rather than looked up.
FUENTE_CIRCLE_WAYS = (235634863, 1081706278, 1081706277)

LANDMARK_WAYS = (
    {FORT_SAN_PEDRO_WAY, MAGELLAN_PAVILION_WAY, BASILICA_BELFRY_WAY,
     COLON_OBELISK_WAY, AYALA_CENTER_WAY, IT_PARK_GARDEN_WAY,
     METRO_COLON_WAY, COLON_CORNER_BLOCK_WAY}
    | set(CARBON_HALL_WAYS) | set(PIER_WAYS)
)


# ---------------------------------------------------------------------------
# Small geometry helpers. build_map.py owns the shared primitives; these are the
# few shapes only landmarks need, kept here so the main module does not grow a
# cylinder function used exactly twice.
# ---------------------------------------------------------------------------

def ring_of(cx, cy, radius, segments, rotate=0.0):
    """A regular polygon, as a list of XY points."""
    return [(cx + radius * math.cos(rotate + 2.0 * math.pi * i / segments),
             cy + radius * math.sin(rotate + 2.0 * math.pi * i / segments))
            for i in range(segments)]


def prism(ring, z0, z1, cap_top=True, cap_bottom=False):
    """Extrude a closed XY ring between two heights."""
    n = len(ring)
    verts = [(x, y, z0) for x, y in ring] + [(x, y, z1) for x, y in ring]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, j + n, i + n))
    if cap_top:
        faces.append(tuple(range(n, 2 * n)))
    if cap_bottom:
        faces.append(tuple(reversed(range(n))))
    return verts, faces


def taper(ring, cx, cy, z0, z1, scale_top):
    """Extrude a ring while shrinking it toward a centre -- an obelisk shaft."""
    n = len(ring)
    verts = [(x, y, z0) for x, y in ring]
    verts += [(cx + (x - cx) * scale_top, cy + (y - cy) * scale_top, z1)
              for x, y in ring]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, j + n, i + n))
    faces.append(tuple(range(n, 2 * n)))
    return verts, faces


def pyramid(ring, cx, cy, z0, apex_z):
    """Close a ring to a single apex point -- a spire or an obelisk cap."""
    n = len(ring)
    verts = [(x, y, z0) for x, y in ring] + [(cx, cy, apex_z)]
    return verts, [(i, (i + 1) % n, n) for i in range(n)]


def centroid(ring):
    return (sum(p[0] for p in ring) / len(ring),
            sum(p[1] for p in ring) / len(ring))


def bounds(ring):
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return min(xs), min(ys), max(xs), max(ys)


def shrink(ring, cx, cy, factor):
    return [(cx + (x - cx) * factor, cy + (y - cy) * factor) for x, y in ring]


def long_axis(ring):
    """Bearing of the footprint's longest edge, for aligning sheds and cranes."""
    best = (0.0, 0.0)
    for i in range(len(ring)):
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % len(ring)]
        length = math.hypot(bx - ax, by - ay)
        if length > best[0]:
            best = (length, math.atan2(by - ay, bx - ax))
    return best[1]


# ---------------------------------------------------------------------------
# Fort San Pedro
#
# Triangular bastion fort, begun 1565 and rebuilt in stone by 1738; the oldest
# and smallest in the country. Published figures: walls 6.1 m high and 2.4 m
# thick, towers 9.1 m from ground, 380 m circumference, 2,025 m2 enclosed. Two
# sides face the sea and the third fronts the city, and that land side carries
# the gate. The three bastions are La Concepcion (SW), Ignacio de Loyola (SE)
# and San Miguel (NE).
#
# THE OSM FOOTPRINT ALREADY CONTAINS THE BASTIONS. Way 332819231 is a 31-node
# outline measuring 411 m around against the published 380, enclosing 4,873 m2
# -- which is about what a 2,025 m2 interior plus 2.4 m walls plus three
# bastions comes to. Its radius profile has three clear lobes at NE, SW and SE,
# exactly where the three bastions are.
#
# That matters because the obvious way to build this is wrong twice over:
# stamping generated bastion towers onto the corners duplicates bastions that
# are already in the outline, and shrinking a three-lobed polygon radially to
# get the inner wall face pulls the lobes in far more than the flat curtains
# between them. Both were done here first and the fort came out sprawling. The
# outline is good data; it just has to be read rather than replaced.
# ---------------------------------------------------------------------------

WALL_HEIGHT = 6.1
WALL_THICK = 2.4
TOWER_HEIGHT = 9.1
PARAPET = 1.1

# A vertex this much further from the centre than the mean is on a bastion
# rather than on a curtain wall. 1.12 separates the three lobes cleanly on the
# current outline: the curtains sit at 25-50 m and the bastion faces at 65-79 m.
BASTION_RADIUS_RATIO = 1.12


def build_fort_san_pedro(batch, mats, ring, inset_ring=None):
    """Curtain walls, parapet walk, the three bastions and the land gate.

    `inset_ring(pts, distance)` is build_map.py's polygon offset, passed in
    because build_map imports this module and cannot be imported back. A real
    offset is needed rather than a radial scale -- see the note above. If it
    cannot offset this outline it returns a differently sized ring, and the
    fallback is a conservative scale.
    """
    if len(ring) < 3:
        return 0
    cx, cy = centroid(ring)
    stone = mats["Fort_Stone"]
    dark = mats["Fort_Shadow"]

    inner = None
    if inset_ring is not None:
        candidate = inset_ring(ring, WALL_THICK)
        if len(candidate) == len(ring):
            inner = candidate
    if inner is None:
        inner = shrink(ring, cx, cy,
                       max(0.05, 1.0 - WALL_THICK / _mean_radius(ring, cx, cy)))

    # Curtain wall as a closed band with a real cavity: the outer face on the
    # OSM line, the inner face 2.4 m in, and the courtyard open to the sky.
    v, f = _wall_band(ring, inner, 0.0, WALL_HEIGHT)
    batch.add(v, f, stone)
    # Parapet above the walk, standing slightly proud of the outer face.
    v, f = _wall_band(ring, inner, WALL_HEIGHT, WALL_HEIGHT + PARAPET)
    batch.add(v, f, stone)

    # Courtyard floor, just above ground so it does not z-fight the terrain.
    v, f = _cap(inner, 0.12)
    batch.add(v, f, mats["Fort_Court"])

    # Bastions: raise the lobes the outline already has, rather than adding new
    # ones. Each run of consecutive vertices standing proud of the mean radius
    # is one bastion; closing the run back on itself gives its plan.
    made = 1
    for run in _bastion_runs(ring, cx, cy):
        plan = [ring[i] for i in run]
        if len(plan) < 3:
            continue
        v, f = prism(plan, 0.0, TOWER_HEIGHT)
        batch.add(v, f, stone)
        # A darker course under the cap reads as the embrasures without
        # modelling every merlon.
        bx, by = centroid(plan)
        v, f = prism(shrink(plan, bx, by, 1.03),
                     TOWER_HEIGHT - 1.1, TOWER_HEIGHT, cap_top=False)
        batch.add(v, f, dark)
        made += 1

    # The land gate. Two sides face the sea; the third fronts the city, which
    # from the fort is north-east, so the gate goes on the outline point
    # furthest that way.
    gx, gy = _side_midpoint(ring, cx, cy, math.radians(45.0))
    heading = math.atan2(gy - cy, gx - cx)
    v, f = _box(gx, gy, 0.0, WALL_HEIGHT + 2.6, 5.0, 2.2, heading)
    batch.add(v, f, stone)
    v, f = _box(gx + math.cos(heading) * 1.4, gy + math.sin(heading) * 1.4,
                0.4, 4.2, 1.9, 2.4, heading)
    batch.add(v, f, dark)
    return made


def _bastion_runs(ring, cx, cy):
    """Index runs of consecutive vertices that stand proud of the mean radius.

    Circular, so a bastion straddling index 0 is still one run rather than two.
    """
    radii = [math.dist(p, (cx, cy)) for p in ring]
    mean = sum(radii) / len(radii)
    threshold = mean * BASTION_RADIUS_RATIO
    n = len(ring)
    out = radii[0] > threshold
    # Start scanning at a vertex that is NOT on a bastion, so no run is split.
    start = 0
    if out:
        for i in range(n):
            if radii[i] <= threshold:
                start = i
                break
        else:
            return []

    runs = []
    current = []
    for k in range(n):
        i = (start + k) % n
        if radii[i] > threshold:
            current.append(i)
        elif current:
            runs.append(current)
            current = []
    if current:
        runs.append(current)

    # Widen each run by one vertex at each end. A bastion is an ARROWHEAD, not
    # a bump: on this outline a 28 m edge runs out from the curtain to a narrow
    # 5 m point and a 40 m edge runs back. Only the point itself stands proud of
    # the mean radius, so the raw run is the tip alone and extruding it gives a
    # 5 m sliver instead of a 30 m bastion. The neighbouring vertices are the
    # shoulders where it springs from the curtain wall.
    widened = []
    for r in runs:
        if len(r) < 2:
            continue
        widened.append([(r[0] - 1) % n] + r + [(r[-1] + 1) % n])
    return [r for r in widened if len(r) >= 3]


def _mean_radius(ring, cx, cy):
    return max(1.0, sum(math.dist((x, y), (cx, cy)) for x, y in ring) / len(ring))


def _wall_band(outer, inner, z0, z1):
    """A closed wall of finite thickness between two concentric rings."""
    n = min(len(outer), len(inner))
    verts = []
    faces = []
    for i in range(n):
        j = (i + 1) % n
        ox, oy = outer[i]
        ox2, oy2 = outer[j]
        ix, iy = inner[i]
        ix2, iy2 = inner[j]
        base = len(verts)
        verts += [(ox, oy, z0), (ox2, oy2, z0), (ox2, oy2, z1), (ox, oy, z1),
                  (ix, iy, z0), (ix2, iy2, z0), (ix2, iy2, z1), (ix, iy, z1)]
        faces += [
            (base, base + 1, base + 2, base + 3),              # outer face
            (base + 5, base + 4, base + 7, base + 6),          # inner face
            (base + 3, base + 2, base + 6, base + 7),          # wall head
        ]
    return verts, faces


def _cap(ring, z):
    return [(x, y, z) for x, y in ring], [tuple(range(len(ring)))]


def _side_midpoint(ring, cx, cy, heading):
    """The point on the ring closest to a given bearing from the centre."""
    want = (math.cos(heading), math.sin(heading))
    best = None
    for x, y in ring:
        d = math.hypot(x - cx, y - cy) or 1.0
        dot = ((x - cx) / d) * want[0] + ((y - cy) / d) * want[1]
        if best is None or dot > best[0]:
            best = (dot, x, y)
    return best[1], best[2]


def _box(cx, cy, z0, z1, half_x, half_y, angle=0.0):
    ca, sa = math.cos(angle), math.sin(angle)
    corners = []
    for dx, dy in ((-half_x, -half_y), (half_x, -half_y),
                   (half_x, half_y), (-half_x, half_y)):
        corners.append((cx + dx * ca - dy * sa, cy + dx * sa + dy * ca))
    verts = [(x, y, z0) for x, y in corners] + [(x, y, z1) for x, y in corners]
    faces = [(3, 2, 1, 0), (4, 5, 6, 7)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((i, j, j + 4, i + 4))
    return verts, faces


# ---------------------------------------------------------------------------
# Metro Colon and the Colon x Osmena Boulevard junction
#
# The busiest corner of the oldest street in the Philippines, and the one place
# a Cebuano will judge this map by. Metro Department Store opened here in 1982
# with three levels and was rebuilt to seven within two years; OSM carries it as
# way 230174493 with `building:levels=7`, which agrees.
#
# What actually identifies this corner is NOT the massing -- it is a seven
# storey slab like a hundred others -- it is that the whole upper facade is a
# BLANK CONCRETE BILLBOARD WALL. Metro's upper floors are almost windowless and
# are hung with enormous vinyl banners, each with a row of floodlights on arms
# above it, over a ground-floor arcade of small shops. Modelling the box and
# skipping the banners would produce something nobody recognises, so the
# banners are geometry here rather than being left for the signage atlas.
#
# Across the junction stands a chamfered corner block, eight levels and 27 m by
# OSM, whose identity is the opposite: strong horizontal floor banding all the
# way up, a yellow signage fascia at street level, and a billboard standing on
# the roof above everything.
# ---------------------------------------------------------------------------

# Faded vinyl, not saturated print: these are two years into tropical sun.
BANNER_COLOURS = ("Banner_Green", "Banner_Blue", "Banner_Red",
                  "Banner_Yellow", "Banner_Cream")

METRO_FLOOR = 3.7          # department-store floors, not flats
METRO_ARCADE = 4.6         # ground-floor shop arcade height


def _ccw(ring):
    s = 0.0
    for i in range(len(ring)):
        j = (i + 1) % len(ring)
        s += ring[i][0] * ring[j][1] - ring[j][0] * ring[i][1]
    return ring if s > 0 else ring[::-1]


def _edges(ring, min_length):
    """Outward-facing edges of a CCW ring, longest first.

    Returns (length, ax, ay, bx, by, nx, ny) with (nx, ny) the outward normal --
    for a counter-clockwise ring that is (dy, -dx) normalised.
    """
    out = []
    n = len(ring)
    for i in range(n):
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        if length < min_length:
            continue
        out.append((length, ax, ay, bx, by, dy / length, -dx / length))
    out.sort(reverse=True)
    return out


def _panel(batch, mat, edge, t0, t1, z0, z1, proud):
    """A flat panel standing proud of one facade edge, between two fractions."""
    _length, ax, ay, bx, by, nx, ny = edge
    dx, dy = bx - ax, by - ay
    x0, y0 = ax + dx * t0 + nx * proud, ay + dy * t0 + ny * proud
    x1, y1 = ax + dx * t1 + nx * proud, ay + dy * t1 + ny * proud
    verts = [(x0, y0, z0), (x1, y1, z0), (x1, y1, z1), (x0, y0, z1)]
    batch.add(verts, [(0, 1, 2, 3)], mat)
    return (x0, y0, x1, y1)


def build_metro_colon(batch, mats, ring, levels=7):
    """Seven-storey department store whose upper facade is a billboard wall."""
    ring = _ccw(ring)
    cx, cy = centroid(ring)
    top = METRO_ARCADE + (levels - 1) * METRO_FLOOR

    wall = mats["Metro_Wall"]
    v, f = prism(ring, 0.0, top)
    batch.add(v, f, wall)
    # Parapet and the shadowed service reveal just under it, both of which show
    # clearly against the sky on this corner.
    v, f = prism(shrink(ring, cx, cy, 1.006), top, top + 1.5)
    batch.add(v, f, mats["Metro_Trim"])
    v, f = prism(shrink(ring, cx, cy, 1.002), top - 2.4, top - 1.0,
                 cap_top=False)
    batch.add(v, f, mats["Metro_Reveal"])

    # Ground-floor arcade: dark recess with a bright shop fascia over it.
    v, f = prism(shrink(ring, cx, cy, 0.995), 0.4, METRO_ARCADE - 1.2,
                 cap_top=False)
    batch.add(v, f, mats["Shopfront_Glass"])
    v, f = prism(shrink(ring, cx, cy, 1.008), METRO_ARCADE - 1.2,
                 METRO_ARCADE + 0.5, cap_top=False)
    batch.add(v, f, mats["Sign_Yellow"])

    # The banners. Only the long street frontages carry them, and they sit on
    # the blank wall between the arcade fascia and the service reveal.
    banners = 0
    band0 = METRO_ARCADE + 2.6
    band1 = top - 3.4
    # EVERY substantial frontage, not just the longest few. Metro occupies a
    # whole corner and is hung on all of its street faces; taking only the top
    # three left the north-east elevation -- the one facing the junction, and
    # the one every photograph of this corner is taken from -- completely bare.
    for e_i, edge in enumerate(_edges(ring, 11.0)[:7]):
        length = edge[0]
        count = max(1, min(3, int(length // 13.0)))
        for k in range(count):
            span = 1.0 / count
            pad = span * 0.16
            t0 = k * span + pad
            t1 = (k + 1) * span - pad
            # Banners are portrait and do not fill the wall height; vary them so
            # the frontage does not read as one repeated element.
            h = (band1 - band0) * (0.52 + 0.12 * ((e_i + k) % 3))
            z0 = band0 + (band1 - band0 - h) * 0.55
            colour = BANNER_COLOURS[(e_i * 3 + k) % len(BANNER_COLOURS)]
            _panel(batch, mats[colour], edge, t0, t1, z0, z0 + h, 0.38)
            # Dark frame just behind, so the banner reads as hung rather than
            # painted straight onto the concrete.
            _panel(batch, mats["Metro_Reveal"], edge, t0 - 0.012, t1 + 0.012,
                   z0 - 0.35, z0 + h + 0.35, 0.18)
            # Floodlights on arms above it.
            _length, ax, ay, bx, by, nx, ny = edge
            for lamp in range(4):
                t = t0 + (t1 - t0) * (0.14 + 0.24 * lamp)
                lx = ax + (bx - ax) * t + nx * 1.05
                ly = ay + (by - ay) * t + ny * 1.05
                v, f = _box(lx, ly, z0 + h + 0.45, z0 + h + 0.75, 0.28, 0.16,
                            math.atan2(by - ay, bx - ax))
                batch.add(v, f, mats["Lamp"])
            banners += 1
    return banners


def build_colon_corner_block(batch, mats, ring, levels=8, height=27.0):
    """Chamfered corner block: horizontal floor banding and a roof billboard."""
    ring = _ccw(ring)
    cx, cy = centroid(ring)
    floor = height / max(1, levels)

    v, f = prism(ring, 0.0, height)
    batch.add(v, f, mats["Corner_Wall"])

    # One recessed glazing band per floor. This banding IS the building -- it is
    # what makes a chamfered concrete block read as this particular one rather
    # than a generic tower.
    for i in range(1, levels):
        z0 = i * floor + 0.55
        z1 = (i + 1) * floor - 0.75
        if z1 <= z0:
            continue
        v, f = prism(shrink(ring, cx, cy, 1.004), z0, z1, cap_top=False)
        batch.add(v, f, mats["Corner_Band"])

    # Yellow fascia over the ground-floor shops.
    v, f = prism(shrink(ring, cx, cy, 1.010), floor - 1.3, floor + 0.2,
                 cap_top=False)
    batch.add(v, f, mats["Sign_Yellow"])
    v, f = prism(shrink(ring, cx, cy, 0.994), 0.4, floor - 1.3, cap_top=False)
    batch.add(v, f, mats["Shopfront_Glass"])

    v, f = prism(shrink(ring, cx, cy, 1.008), height, height + 1.0)
    batch.add(v, f, mats["Metro_Trim"])

    # Rooftop billboard on a frame, facing the junction along the longest edge.
    edges = _edges(ring, 8.0)
    if edges:
        edge = edges[0]
        _length, ax, ay, bx, by, nx, ny = edge
        for t in (0.18, 0.82):
            lx = ax + (bx - ax) * t
            ly = ay + (by - ay) * t
            v, f = _box(lx, ly, height + 1.0, height + 9.5, 0.22, 0.22)
            batch.add(v, f, mats["Crane_Steel"])
        _panel(batch, mats["Banner_Red"], edge, 0.10, 0.90,
               height + 3.2, height + 9.8, 0.30)
        _panel(batch, mats["Metro_Reveal"], edge, 0.08, 0.92,
               height + 2.9, height + 10.1, 0.12)
    return 1


# ---------------------------------------------------------------------------
# Fuente Osmeña Circle
#
# A rotunda park at Jones Avenue and General Maxilom, with a century-old
# fountain at its centre (built 1912 with the city's first waterworks). OSM has
# only the carriageways, so the park is the disc they enclose.
# ---------------------------------------------------------------------------

def build_fuente_circle(batch, mats, cx, cy, radius):
    """Kerbed lawn disc, stepped fountain basin and the central column."""
    park = max(8.0, radius - 7.0)

    # Kerb ring and lawn. The lawn sits 0.15 m proud, the same kerb height the
    # sidewalks use, so a player steps up onto it rather than through it.
    kerb = ring_of(cx, cy, park, 48)
    v, f = prism(kerb, 0.0, 0.15)
    batch.add(v, f, mats["Sidewalk"])
    v, f = _cap(shrink(kerb, cx, cy, 0.97), 0.16)
    batch.add(v, f, mats["Landuse_Green"])

    # Paved apron around the fountain -- the part that is actually plaza.
    apron = ring_of(cx, cy, park * 0.46, 32)
    v, f = _cap(apron, 0.17)
    batch.add(v, f, mats["Footway"])

    # Fountain: three stepped basins. Real ones are round; 24 segments is enough
    # that the silhouette reads as a circle at any distance a player sees it.
    basin_r = max(3.0, park * 0.30)
    for i, (r, z0, z1) in enumerate((
            (basin_r, 0.15, 0.75),
            (basin_r * 0.62, 0.75, 1.35),
            (basin_r * 0.34, 1.35, 1.95))):
        step = ring_of(cx, cy, r, 24)
        v, f = prism(step, z0, z1)
        batch.add(v, f, mats["Fountain_Stone"])
        # Water sits just below each rim.
        v, f = _cap(shrink(step, cx, cy, 0.93), z1 - 0.12)
        batch.add(v, f, mats["Water"])

    # Central column with a finial. Fuente's centrepiece is a slim tiered
    # column, not a statue on a plinth, so it stays a taper plus a cap.
    shaft = ring_of(cx, cy, basin_r * 0.16, 12)
    v, f = taper(shaft, cx, cy, 1.95, 7.4, 0.55)
    batch.add(v, f, mats["Fountain_Stone"])
    v, f = pyramid(shrink(shaft, cx, cy, 0.55), cx, cy, 7.4, 9.2)
    batch.add(v, f, mats["Fountain_Stone"])

    # A ring of lamp posts, which is most of what reads at night and gives the
    # disc a scale reference by day.
    for x, y in ring_of(cx, cy, park * 0.80, 12):
        v, f = _box(x, y, 0.15, 4.2, 0.11, 0.11)
        batch.add(v, f, mats["Pole"])
        v, f = _box(x, y, 4.2, 4.6, 0.30, 0.30)
        batch.add(v, f, mats["Lamp"])
    return 1


# ---------------------------------------------------------------------------
# Colon Street obelisk
#
# The marker for the oldest street in the Philippines. Small, but it is the one
# object at the head of Colon that says which street this is.
# ---------------------------------------------------------------------------

def build_colon_obelisk(batch, mats, ring):
    cx, cy = centroid(ring)
    x0, y0, x1, y1 = bounds(ring)
    half = max(1.1, min(x1 - x0, y1 - y0) * 0.5)

    base = ring_of(cx, cy, half * 1.5, 4, rotate=math.pi / 4.0)
    v, f = prism(base, 0.0, 0.9)
    batch.add(v, f, mats["Fountain_Stone"])
    plinth = ring_of(cx, cy, half * 1.05, 4, rotate=math.pi / 4.0)
    v, f = prism(plinth, 0.9, 3.0)
    batch.add(v, f, mats["Fountain_Stone"])
    shaft = ring_of(cx, cy, half * 0.62, 4, rotate=math.pi / 4.0)
    v, f = taper(shaft, cx, cy, 3.0, 12.0, 0.55)
    batch.add(v, f, mats["Fountain_Stone"])
    v, f = pyramid(shrink(shaft, cx, cy, 0.55), cx, cy, 12.0, 13.6)
    batch.add(v, f, mats["Fountain_Stone"])
    return 1


# ---------------------------------------------------------------------------
# Magellan's Cross Pavilion
#
# The open octagonal kiosk on Magallanes Street housing the cross Magellan
# planted in 1521. Tiled hip roof on open piers, painted ceiling inside.
# ---------------------------------------------------------------------------

def build_magellans_cross(batch, mats, ring):
    cx, cy = centroid(ring)
    x0, y0, x1, y1 = bounds(ring)
    radius = max(3.0, min(x1 - x0, y1 - y0) * 0.5)

    plinth = ring_of(cx, cy, radius * 1.02, 8, rotate=math.pi / 8.0)
    v, f = prism(plinth, 0.0, 0.45)
    batch.add(v, f, mats["Fountain_Stone"])

    # Eight piers rather than a wall: the pavilion is open on every side, and
    # that openness is what makes it recognisable rather than a small shed.
    for x, y in ring_of(cx, cy, radius * 0.88, 8, rotate=math.pi / 8.0):
        v, f = _box(x, y, 0.45, 4.1, 0.26, 0.26,
                    math.atan2(y - cy, x - cx))
        batch.add(v, f, mats["Pavilion_Wall"])

    # Entablature, then a tiled hip roof to a finial.
    eave = ring_of(cx, cy, radius * 1.12, 8, rotate=math.pi / 8.0)
    v, f = prism(eave, 4.1, 4.9)
    batch.add(v, f, mats["Pavilion_Wall"])
    v, f = pyramid(eave, cx, cy, 4.9, 8.2)
    batch.add(v, f, mats["Pavilion_Roof"])
    v, f = pyramid(ring_of(cx, cy, radius * 0.16, 8), cx, cy, 8.2, 9.4)
    batch.add(v, f, mats["Pavilion_Roof"])

    # The cross itself, under the middle of the roof.
    v, f = _box(cx, cy, 0.45, 3.2, 0.16, 0.16)
    batch.add(v, f, mats["Cross_Timber"])
    v, f = _box(cx, cy + 0.0, 2.35, 2.67, 0.70, 0.16)
    batch.add(v, f, mats["Cross_Timber"])
    return 1


# ---------------------------------------------------------------------------
# Basilica Minore del Santo Niño
#
# OSM carries the belfry as its own small way. The church itself is the block
# beside it; the belfry is the part that shows above the roofline from Colon and
# from the Plaza, so it gets the height.
# ---------------------------------------------------------------------------

def build_basilica_belfry(batch, mats, ring):
    cx, cy = centroid(ring)
    x0, y0, x1, y1 = bounds(ring)
    half_x = max(2.4, (x1 - x0) * 0.5)
    half_y = max(2.4, (y1 - y0) * 0.5)

    stone = mats["Church_Stone"]
    # Four diminishing stages, the standard Philippine colonial belfry.
    stages = ((0.0, 9.0, 1.00), (9.0, 16.0, 0.88),
              (16.0, 22.0, 0.76), (22.0, 26.5, 0.64))
    for z0, z1, s in stages:
        v, f = _box(cx, cy, z0, z1, half_x * s, half_y * s)
        batch.add(v, f, stone)
        # Cornice course between stages, standing proud.
        v, f = _box(cx, cy, z1 - 0.5, z1, half_x * s * 1.10, half_y * s * 1.10)
        batch.add(v, f, mats["Church_Trim"])
        # Openings: a dark recess on each face reads as the arched bell stage.
        if z0 >= 9.0:
            v, f = _box(cx, cy, z0 + 1.2, z1 - 1.4,
                        half_x * s * 1.02, half_y * s * 0.55)
            batch.add(v, f, mats["Church_Opening"])
            v, f = _box(cx, cy, z0 + 1.2, z1 - 1.4,
                        half_x * s * 0.55, half_y * s * 1.02)
            batch.add(v, f, mats["Church_Opening"])

    dome = ring_of(cx, cy, min(half_x, half_y) * 0.64, 8)
    v, f = prism(dome, 26.5, 27.6)
    batch.add(v, f, mats["Church_Trim"])
    v, f = pyramid(dome, cx, cy, 27.6, 32.0)
    batch.add(v, f, mats["Church_Roof"])
    return 1


# ---------------------------------------------------------------------------
# Carbon Market
#
# Three public-market halls plus the stall field that spills into every street
# around them. The master plan calls a full stall generator a build_slum.py-scale
# project; this is the breadth-first version -- real halls, and canopies dense
# enough that the district reads as a market rather than three sheds.
# ---------------------------------------------------------------------------

CANOPY_COLOURS = ("Canopy_Blue", "Canopy_Red", "Canopy_Green",
                  "Canopy_Orange", "Canopy_White")


def build_carbon_hall(batch, mats, ring, seed):
    """One market hall: long low shed with a raised monitor roof."""
    cx, cy = centroid(ring)
    angle = long_axis(ring)
    x0, y0, x1, y1 = bounds(ring)
    half_x = (x1 - x0) * 0.5
    half_y = (y1 - y0) * 0.5

    v, f = prism(ring, 0.0, 6.4)
    batch.add(v, f, mats["Market_Wall"])
    # Eaves overhanging the walls, which every wet-market hall has.
    eave = shrink(ring, cx, cy, 1.05)
    v, f = prism(eave, 6.4, 7.0)
    batch.add(v, f, mats["Market_Roof"])
    # Monitor: a raised clerestory strip down the ridge for light and air.
    v, f = _box(cx, cy, 7.0, 9.2, half_x * 0.34, half_y * 0.34, angle)
    batch.add(v, f, mats["Market_Roof"])
    v, f = _box(cx, cy, 7.0, 8.0, half_x * 0.35, half_y * 0.35, angle)
    batch.add(v, f, mats["Church_Opening"])
    # Signage band over the long frontage.
    v, f = prism(shrink(ring, cx, cy, 1.02), 4.6, 6.0, cap_top=False)
    batch.add(v, f, mats[CANOPY_COLOURS[seed % len(CANOPY_COLOURS)]])
    return 1


def build_carbon_stalls(batch, mats, cx, cy, radius, rng, blocked, limit=260):
    """A field of tarpaulin canopies around the halls.

    Canopies, not buildings: 2.2 m to the eaves, so the player walks under them
    and the road surface disappears, which is the single most Carbon thing about
    Carbon. `blocked(x, y)` keeps them out of the halls themselves.
    """
    placed = 0
    step = 4.2
    y = cy - radius
    while y < cy + radius and placed < limit:
        x = cx - radius
        while x < cx + radius and placed < limit:
            px = x + rng.uniform(-0.9, 0.9)
            py = y + rng.uniform(-0.9, 0.9)
            x += step
            if math.dist((px, py), (cx, cy)) > radius:
                continue
            if blocked(px, py):
                continue
            if rng.random() < 0.34:
                continue
            half = rng.uniform(1.5, 2.1)
            top = rng.uniform(2.1, 2.6)
            angle = rng.uniform(0.0, math.pi)
            # Four thin legs and a canopy slab. A crate stack under about half
            # of them gives the field some vertical noise.
            for dx, dy in ((-half * 0.8, -half * 0.8), (half * 0.8, -half * 0.8),
                           (half * 0.8, half * 0.8), (-half * 0.8, half * 0.8)):
                ca, sa = math.cos(angle), math.sin(angle)
                lx = px + dx * ca - dy * sa
                ly = py + dx * sa + dy * ca
                v, f = _box(lx, ly, 0.0, top, 0.045, 0.045)
                batch.add(v, f, mats["Pole"])
            v, f = _box(px, py, top, top + 0.12, half, half, angle)
            batch.add(v, f, mats[CANOPY_COLOURS[placed % len(CANOPY_COLOURS)]])
            if rng.random() < 0.5:
                v, f = _box(px, py, 0.0, rng.uniform(0.5, 0.9),
                            half * 0.45, half * 0.45, angle)
                batch.add(v, f, mats["Market_Crate"])
            placed += 1
        y += step
    return placed


# ---------------------------------------------------------------------------
# Cebu Port
#
# Pier sheds, container stacks and gantry cranes. The cranes matter most: they
# are the only thing on the waterfront tall enough to read from Colon, and they
# are what makes a port look like a port from any distance.
# ---------------------------------------------------------------------------

def build_pier(batch, mats, ring, rng):
    """A pier shed with container stacks and one gantry crane alongside."""
    cx, cy = centroid(ring)
    angle = long_axis(ring)
    x0, y0, x1, y1 = bounds(ring)
    half_x = (x1 - x0) * 0.5
    half_y = (y1 - y0) * 0.5

    # Terminal shed over most of the footprint.
    v, f = prism(ring, 0.0, 11.5)
    batch.add(v, f, mats["Warehouse_Wall"])
    v, f = prism(shrink(ring, cx, cy, 1.03), 11.5, 12.4)
    batch.add(v, f, mats["Warehouse_Roof"])
    v, f = prism(shrink(ring, cx, cy, 1.01), 9.4, 10.6, cap_top=False)
    batch.add(v, f, mats["Canopy_Blue"])

    # Container stacks along the quay edge.
    ca, sa = math.cos(angle), math.sin(angle)
    colours = ("Container_Red", "Container_Blue", "Container_Green",
               "Container_Grey")
    made = 0
    for i in range(-3, 4):
        for j in (-1, 1):
            bx = cx + ca * i * 13.0 - sa * j * (half_y * 0.92 + 9.0)
            by = cy + sa * i * 13.0 + ca * j * (half_y * 0.92 + 9.0)
            layers = rng.randint(1, 3)
            for k in range(layers):
                v, f = _box(bx, by, k * 2.6, (k + 1) * 2.6 - 0.08,
                            6.1, 1.22, angle)
                batch.add(v, f, mats[colours[(i + j + k) % len(colours)]])
            made += 1

    # One gantry crane: two leg frames, a boom across them, and a trolley.
    gx = cx - sa * (half_y * 0.92 + 16.0)
    gy = cy + ca * (half_y * 0.92 + 16.0)
    span = 22.0
    top = 34.0
    for s in (-1, 1):
        for t in (-1, 1):
            lx = gx + ca * s * 9.0 - sa * t * span * 0.5
            ly = gy + sa * s * 9.0 + ca * t * span * 0.5
            v, f = _box(lx, ly, 0.0, top, 0.8, 0.8, angle)
            batch.add(v, f, mats["Crane_Steel"])
    v, f = _box(gx, gy, top, top + 2.4, 9.6, span * 0.5 + 1.0, angle)
    batch.add(v, f, mats["Crane_Steel"])
    # Boom reaching out over the water.
    bx = gx - sa * 26.0
    by = gy + ca * 26.0
    v, f = _box(bx, by, top + 0.6, top + 2.0, 2.2, 26.0, angle)
    batch.add(v, f, mats["Crane_Steel"])
    return made


# ---------------------------------------------------------------------------
# Ayala Center Cebu
#
# A large retail podium whose identity is The Terraces: the stepped, planted
# outdoor dining terraces on its north-west side. Stepping the mass is what
# distinguishes it from any other big-box mall.
# ---------------------------------------------------------------------------

AYALA_LEVEL = 4.3          # retail floors
AYALA_LEVELS = 5           # OSM building:levels on way 29261598


def _perimeter_stations(ring, spacing):
    """Points along a ring at ~`spacing` apart, each with its edge bearing.

    For hanging evenly spaced facade detail -- pilasters -- on an irregular OSM
    footprint without having to know where its corners fall.
    """
    n = len(ring)
    for i in range(n):
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        if length < 1e-6:
            continue
        bearing = math.atan2(dy, dx)
        count = max(1, int(round(length / spacing)))
        for k in range(count):
            t = (k + 0.5) / count
            yield ax + dx * t, ay + dy * t, bearing


def _longest_edge(ring):
    """(midpoint, bearing, outward unit normal) of the footprint's longest edge.

    The main frontage: long enough to carry the entrance and the signage, and
    the normal points away from the centroid so the canopy projects outward.
    """
    cx, cy = centroid(ring)
    best = None
    n = len(ring)
    for i in range(n):
        ax, ay = ring[i]
        bx, by = ring[(i + 1) % n]
        length = math.hypot(bx - ax, by - ay)
        if best is None or length > best[0]:
            mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
            bearing = math.atan2(by - ay, bx - ax)
            nx, ny = math.sin(bearing), -math.cos(bearing)
            if (mx + nx - cx) ** 2 + (my + ny - cy) ** 2 \
                    < (mx - cx) ** 2 + (my - cy) ** 2:
                nx, ny = -nx, -ny
            best = (length, (mx, my), bearing, (nx, ny))
    return best[1], best[2], best[3]


def build_ayala_center(batch, mats, ring, rng=None):
    """Five-level mall with The Terraces cut into its northern flank.

    `ring` MUST be the mall building (way 29261598, 45,311 m2, levels=5), not
    the 80,154 m2 commercial parcel that shares its name -- extruding the parcel
    makes a solid block twice the real footprint and swallows the car parks and
    service yards around it.

    The Terraces is an open-air, multi-level dining enclave that replaced the
    mall's central lagoon in 2008: roughly four stepped levels of restaurants
    around water and planting, open to the sky. It is the one part of Ayala
    Center anybody pictures, and it is a VOID in the massing rather than more
    massing -- so it is cut into the block as a descending court, not stacked
    on top.

    Up close the bare extrusion read as a blank slab, so the frontage is
    articulated the way the real mall is: a glazed ground-floor shopfront, a
    pilaster every few metres to break the horizontal glazing bands, a cornice
    at the parapet, and a canopied main entrance under a lit signage band.
    """
    cx, cy = centroid(ring)
    top = AYALA_LEVELS * AYALA_LEVEL
    radius = _mean_radius(ring, cx, cy)
    wall = mats["Ayala_Wall"]

    v, f = prism(ring, 0.0, top)
    batch.add(v, f, wall)
    v, f = prism(shrink(ring, cx, cy, 0.99), top, top + 1.6)
    batch.add(v, f, mats["Roof_Deck"])

    # Ground-floor shopfront: a taller, darker glazed course so the street level
    # reads as retail frontage rather than blank wall.
    shop_h = AYALA_LEVEL * 0.9
    v, f = prism(shrink(ring, cx, cy, 1.004), 0.4, shop_h, cap_top=False)
    batch.add(v, f, mats["Shopfront_Glass"])
    # Upper glazing courses, one per storey. A 300 m frontage with none reads as
    # one blank slab.
    for level in range(1, AYALA_LEVELS):
        z0 = level * AYALA_LEVEL + 0.9
        z1 = (level + 1) * AYALA_LEVEL - 1.1
        v, f = prism(shrink(ring, cx, cy, 1.003), z0, z1, cap_top=False)
        batch.add(v, f, mats["Ayala_Glass"])

    # Pilasters: one every ~13 m of frontage, standing proud of the glazing from
    # grade to the cornice. This is what breaks the horizontal banding that read
    # as a plain slab up close.
    for px, py, bearing in _perimeter_stations(ring, 13.0):
        v, f = _box(px, py, 0.0, top - 0.6, 0.55, 0.7, bearing)
        batch.add(v, f, wall)
    # Cornice: a capping band proud of the wall, so the parapet reads as a line.
    v, f = prism(shrink(ring, cx, cy, 1.015), top - 1.0, top + 0.6, cap_top=False)
    batch.add(v, f, wall)

    # Main entrance on the longest frontage: a canopy on columns under a lit
    # signage band -- the face people recognise.
    (ex, ey), ebearing, (nx, ny) = _longest_edge(ring)
    ax_, ay_ = math.cos(ebearing), math.sin(ebearing)
    sign_z = top * 0.60
    v, f = _box(ex + nx * 0.4, ey + ny * 0.4, sign_z, sign_z + 2.4, 9.0, 0.5, ebearing)
    batch.add(v, f, mats["Bloc_Sign"])
    v, f = _box(ex + nx * 3.2, ey + ny * 3.2, 4.0, 4.7, 8.5, 3.4, ebearing)
    batch.add(v, f, mats["Roof_Deck"])
    for s in (-7.0, -2.4, 2.4, 7.0):
        v, f = _box(ex + nx * 6.2 + ax_ * s, ey + ny * 6.2 + ay_ * s,
                    0.0, 4.2, 0.35, 0.35, ebearing)
        batch.add(v, f, wall)

    # Roof plant: this roof is what every surrounding office tower looks down on.
    for i, (fx, fy) in enumerate(ring_of(cx, cy, radius * 0.5, 11)):
        v, f = _box(fx, fy, top + 1.6, top + 4.4 + (i % 3) * 0.9, 5.5, 4.2)
        batch.add(v, f, mats["Tower_Plant"])

    # --- The Terraces ----------------------------------------------------
    # A court on the northern side, stepping DOWN from the roof to a water
    # basin at grade. Each level is a planted dining deck set back from the one
    # below, which is what gives it its section.
    tx = cx + radius * 0.10
    ty = cy + radius * 0.46
    half = radius * 0.34
    levels = 4
    for i in range(levels):
        s = 1.0 - i * 0.19
        deck = ring_of(tx, ty, half * s, 4, rotate=math.radians(12.0))
        z = top - (i + 1) * (top / (levels + 0.6))
        # Deck slab and its planted top.
        v, f = prism(deck, max(0.0, z), max(0.0, z) + 0.9)
        batch.add(v, f, mats["Ayala_Wall"])
        v, f = _cap(shrink(deck, tx, ty, 0.97), max(0.0, z) + 0.95)
        batch.add(v, f, mats["Landuse_Green"])
        # Glazed restaurant frontage under each deck's lip.
        v, f = prism(shrink(deck, tx, ty, 1.01),
                     max(0.0, z) - AYALA_LEVEL * 0.62, max(0.0, z),
                     cap_top=False)
        batch.add(v, f, mats["Ayala_Glass"])
        # Balustrade, so the section reads as terraces rather than as slabs.
        v, f = prism(shrink(deck, tx, ty, 1.02),
                     max(0.0, z) + 0.95, max(0.0, z) + 2.0, cap_top=False)
        batch.add(v, f, mats["Ayala_Rail"])

    # The water at the bottom of the court -- what the old lagoon became.
    basin = ring_of(tx, ty, half * 0.30, 16)
    v, f = prism(basin, 0.0, 0.5)
    batch.add(v, f, mats["Fountain_Stone"])
    v, f = _cap(shrink(basin, tx, ty, 0.9), 0.42)
    batch.add(v, f, mats["Water"])

    # Trees on the upper decks.
    if rng is not None:
        for i in range(14):
            a = rng.uniform(0.0, math.tau)
            r = half * rng.uniform(0.45, 0.95)
            px, py = tx + math.cos(a) * r, ty + math.sin(a) * r
            v, f = _box(px, py, 0.5, 2.2, 0.13, 0.13)
            batch.add(v, f, mats["Tree_Trunk"])
            v, f = pyramid(ring_of(px, py, rng.uniform(1.5, 2.6), 6),
                           px, py, 2.2, rng.uniform(5.0, 7.0))
            batch.add(v, f, mats["Tree_Canopy_1"])
    return 1


# ---------------------------------------------------------------------------
# Cebu IT Park (Asiatown), Lahug
#
# A separate district from Ayala Center -- 1.4 km north of it, and the only
# place in the map that is a purpose-built campus rather than accreted city.
# Its towers are already well mapped in OSM with real levels and heights, so
# the generic building loop gets their massing right; what it cannot supply is
# the thing at the middle of the campus.
#
# Garden Bloc (way 392888930) is that: a 16,814 m2 open green at the centre of
# the tower ring, crossed by paths and used for the Sugbo Mercado night market.
# Without it IT Park is a field of towers around nothing.
# ---------------------------------------------------------------------------

def build_it_park_garden(batch, mats, ring, rng):
    """Garden Bloc: lawn, crossing paths, trees and the night-market rows."""
    cx, cy = centroid(ring)
    x0, y0, x1, y1 = bounds(ring)
    half_x = (x1 - x0) * 0.5
    half_y = (y1 - y0) * 0.5

    v, f = _cap(ring, 0.06)
    batch.add(v, f, mats["Landuse_Green"])
    # Two crossing promenades, the way the campus actually routes people.
    v, f = _box(cx, cy, 0.06, 0.15, half_x * 0.94, 3.4)
    batch.add(v, f, mats["Footway"])
    v, f = _box(cx, cy, 0.06, 0.15, 3.4, half_y * 0.94)
    batch.add(v, f, mats["Footway"])

    trees = 0
    for i in range(46):
        a = rng.uniform(0.0, math.tau)
        r = rng.uniform(0.25, 0.92)
        px = cx + math.cos(a) * half_x * r
        py = cy + math.sin(a) * half_y * r
        if abs(px - cx) < 5.0 or abs(py - cy) < 5.0:
            continue          # keep the promenades clear
        v, f = _box(px, py, 0.1, rng.uniform(2.0, 3.0), 0.15, 0.15)
        batch.add(v, f, mats["Tree_Trunk"])
        v, f = pyramid(ring_of(px, py, rng.uniform(2.0, 3.4), 6), px, py,
                       2.4, rng.uniform(6.0, 9.0))
        batch.add(v, f, mats["Tree_Canopy_0"])
        trees += 1

    # Sugbo Mercado: rows of white market tents on one quarter of the green.
    tents = 0
    mx = cx - half_x * 0.42
    my = cy - half_y * 0.42
    for row in range(3):
        for col in range(5):
            px = mx + col * 7.2
            py = my + row * 6.4
            v, f = _box(px, py, 0.0, 2.4, 3.0, 2.6)
            batch.add(v, f, mats["Canopy_White"])
            v, f = pyramid(ring_of(px, py, 3.2, 4, rotate=math.pi / 4.0),
                           px, py, 2.4, 3.6)
            batch.add(v, f, mats["Canopy_White"])
            tents += 1
    return trees + tents
