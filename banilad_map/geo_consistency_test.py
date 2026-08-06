"""Guard: one georeference, used by everything.

    python banilad_map/geo_consistency_test.py

The pipeline once carried four copies of the local projection -- in
`build_map.py`, `build_mall.py`, `find_spawn.py` and `tools/build_slum.py` --
and they had silently drifted apart. `build_mall.py` used
`METRES_PER_DEG_LAT = 110540.0` where everything else used `110574.0`, which
put Gaisano Country Mall 0.13-0.19 m north of the OSM footprints it was
modelled from. Nothing failed; the mall was just wrong, and the error grows
with distance from the origin -- 0.36 m at the current map's south edge, about
1.5 m at the Port.

A numeric test cannot catch that on its own -- each script was internally
consistent. So the real guard here is the SOURCE SCAN: no file in the pipeline
may define its own origin or metres-per-degree. They must import `geo`.

The Blender scripts cannot be imported outside Blender (`import bpy`), which is
the other reason this checks source text rather than runtime values.
"""

import math
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
PROJECT = HERE.parent
sys.path.insert(0, str(HERE))

import geo  # noqa: E402

# Every .py in these trees must go through geo.py.
SCAN_DIRS = [HERE, PROJECT / "tools"]
SCAN_EXEMPT = {"geo.py", "geo_consistency_test.py"}

# A definition of any of these outside geo.py is the bug coming back.
FORBIDDEN = [
    (re.compile(r"^\s*LAT0\s*[,=]"), "defines its own LAT0"),
    (re.compile(r"^\s*LON0\s*[,=]"), "defines its own LON0"),
    (re.compile(r"^\s*(METRES_PER_DEG_LAT|MPD_LAT|M_LAT)\s*="),
     "defines its own metres-per-degree-latitude"),
    (re.compile(r"^\s*(METRES_PER_DEG_LON|MPD_LON|M_LON)\s*="),
     "defines its own metres-per-degree-longitude"),
    (re.compile(r"=.*\b(110574|110540|111320)\b"),
     "hard-codes an earth-radius constant"),
]

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def strip_comment(line):
    return line.split("#", 1)[0]


# --- The projection itself --------------------------------------------------

check(geo.project(geo.LAT0, geo.LON0) == (0.0, 0.0),
      "the origin must project to (0, 0)")

# One degree of latitude north, and back again.
lat, lon = geo.unproject(*geo.project(10.2925, 123.8988))
check(abs(lat - 10.2925) < 1e-9 and abs(lon - 123.8988) < 1e-9,
      "project/unproject must round-trip (got %.9f, %.9f)" % (lat, lon))

# 1 km due north of the origin must land at y = 1000 m, to the millimetre.
north = geo.project(geo.LAT0 + 1000.0 / geo.METRES_PER_DEG_LAT, geo.LON0)
check(abs(north[1] - 1000.0) < 1e-3 and abs(north[0]) < 1e-9,
      "1 km north must project to y=1000 (got %r)" % (north,))

# Pin the axis convention: Blender (x, y, z) -> Godot (x, z, -y).
check(geo.to_godot(3.0, 7.0, 2.0) == (3.0, 2.0, -7.0),
      "to_godot must map Blender (x, y, z) to Godot (x, z, -y)")

# --- Known positions, cross-checked against the shipped map -----------------
#
# These are read back from PROJECT_STATUS.md and banilad_city.gd. If the
# projection changes, the existing map, its landmarks JSON, the navmesh bake
# volume and every hand-tuned spawn position all silently stop lining up.
KNOWN = [
    # (name, lat, lon, godot_x, godot_z, tolerance_m)
    ("player spawn, Gov. M. Cuenco Ave", 10.33952, 123.91162, 12.79, -554.24, 25.0),
    ("Ayala Malls Central Bloc", 10.33071, 123.90728, -461.86, 419.09, 25.0),
]
for name, klat, klon, gx, gz, tol in KNOWN:
    px, py = geo.project(klat, klon)
    got = geo.to_godot(px, py)
    offset = math.dist((got[0], got[2]), (gx, gz))
    check(offset < tol,
          "%s should land within %.0f m of (%.2f, %.2f), got (%.2f, %.2f) -- %.1f m off"
          % (name, tol, gx, gz, got[0], got[2], offset))

# --- The source scan: the actual regression guard ---------------------------

scanned = 0
for directory in SCAN_DIRS:
    if not directory.is_dir():
        continue
    for path in sorted(directory.rglob("*.py")):
        if path.name in SCAN_EXEMPT:
            continue
        scanned += 1
        for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = strip_comment(raw)
            for pattern, why in FORBIDDEN:
                if pattern.search(line):
                    failures.append("%s:%d %s -- import it from geo.py instead"
                                    % (path.relative_to(PROJECT), number, why))

check(scanned > 0, "the source scan found no files to check")

# --- Report -----------------------------------------------------------------

print("[geo] scanned %d pipeline script(s)" % scanned)
print("[geo] origin  : %.4f, %.4f" % (geo.LAT0, geo.LON0))
print("[geo] scale   : %.1f m/deg lat, %.1f m/deg lon"
      % (geo.METRES_PER_DEG_LAT, geo.METRES_PER_DEG_LON))

if failures:
    for message in failures:
        print("[geo] FAIL: %s" % message)
    print("GEO_CONSISTENCY_FAIL: %d problem(s)" % len(failures))
    sys.exit(1)

print("GEO_CONSISTENCY_OK")
