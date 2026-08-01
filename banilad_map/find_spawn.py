"""Pick a spawn point on Gov. M. Cuenco Avenue near Gaisano Country Mall."""

import json
import math
import pathlib

HERE = pathlib.Path(__file__).parent
LAT0, LON0 = 10.3345, 123.9115
M_LAT = 110574.0
M_LON = 111320.0 * math.cos(math.radians(LAT0))

data = json.loads((HERE / "banilad_osm.json").read_text(encoding="utf-8"))


def project(lat, lon):
    return ((lon - LON0) * M_LON, (lat - LAT0) * M_LAT)


# Gaisano centroid in Blender space (Godot z was negated on export).
target = (-104.64, 568.61)

best = None
for el in data["elements"]:
    if el.get("type") != "way":
        continue
    tags = el.get("tags", {})
    if tags.get("name") != "Governor M. Cuenco Avenue":
        continue
    for p in el.get("geometry") or []:
        x, y = project(p["lat"], p["lon"])
        d = math.dist((x, y), target)
        if best is None or d < best[0]:
            best = (d, x, y)

if best is None:
    raise SystemExit("avenue not found")

d, x, y = best
print("nearest avenue point to Gaisano: {:.1f} m away".format(d))
print("blender xy : ({:.2f}, {:.2f})".format(x, y))
print("godot xyz  : ({:.2f}, 1.2, {:.2f})".format(x, -y))

# A second spawn deeper into the dense strip, for variety.
mid = None
for el in data["elements"]:
    if el.get("type") != "way":
        continue
    if el.get("tags", {}).get("name") != "Governor M. Cuenco Avenue":
        continue
    geom = el.get("geometry") or []
    if len(geom) < 2:
        continue
    p = geom[len(geom) // 2]
    x2, y2 = project(p["lat"], p["lon"])
    if mid is None or abs(y2) < abs(mid[1]):
        mid = (x2, y2)

print("avenue centre godot xyz: ({:.2f}, 1.2, {:.2f})".format(mid[0], -mid[1]))
