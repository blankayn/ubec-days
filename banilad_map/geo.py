"""Shared local projection for the Cebu City map pipeline.

Every script that turns OpenStreetMap lat/lon into map metres imports this.
Four copies of these constants used to live in `build_map.py`, `build_mall.py`,
`find_spawn.py` and `tools/build_slum.py`, and they had already drifted:
`build_mall.py` carried `METRES_PER_DEG_LAT = 110540.0` against everyone else's
`110574.0`.

That is 0.03%, and it is proportional to distance from the origin. Measured on
the rebuild, it had been placing Gaisano Country Mall 0.13-0.19 m north of the
very OSM footprints `build_map.py` drew it against. At the current map's south
edge the same error is 0.36 m, and at the Port it would be about 1.5 m. One
definition, one bug fixed.

The projection is a plain local tangent plane (equirectangular about `LAT0`):
no UTM, no proj4, no Web Mercator. The longitude scale is frozen at the origin
latitude, so distortion grows with distance north or south of it -- about 0.06%
at the southern (Port) edge, well under a metre. That is acceptable, and it
keeps the transform invertible in two lines.

    1 Blender unit = 1 metre
    Blender (x, y, z) -> Godot (x, z, -y)
"""

import math

# Local origin: Gov. M. Cuenco Avenue, Banilad -- the point the existing map was
# built around.
#
# It now sits at the NORTH-EAST CORNER of the target extent rather than its
# centre, which looks untidy and is deliberate. Moving it would invalidate every
# hand-tuned position downstream: SPAWN_POSITION, MALL_GROUND_PROBE and
# SLUM_GROUND_PROBE in banilad_city.gd, the five district rects, the navmesh
# bake volume, and all 110 entries in banilad_landmarks.json. float32 precision
# 6 km from the origin is about half a millimetre, so there is nothing to buy.
LAT0 = 10.3345
LON0 = 123.9115

METRES_PER_DEG_LAT = 110574.0
METRES_PER_DEG_LON = 111320.0 * math.cos(math.radians(LAT0))


def project(lat, lon):
    """OSM (lat, lon) -> Blender (x, y) metres."""
    return ((lon - LON0) * METRES_PER_DEG_LON, (lat - LAT0) * METRES_PER_DEG_LAT)


def unproject(x, y):
    """Blender (x, y) metres -> OSM (lat, lon). The inverse of `project`."""
    return (y / METRES_PER_DEG_LAT + LAT0, x / METRES_PER_DEG_LON + LON0)


def to_godot(x, y, z=0.0):
    """Blender (x, y, z) -> Godot (x, y, z). Blender is Z-up, Godot is Y-up."""
    return (x, z, -y)


def project_godot(lat, lon, height=0.0):
    """OSM (lat, lon) straight to Godot (x, y, z) metres."""
    x, y = project(lat, lon)
    return to_godot(x, y, height)
