import json
import collections
import pathlib

data = json.loads(pathlib.Path("banilad_osm.json").read_text(encoding="utf-8"))
els = data["elements"]

print("total elements:", len(els))
print("by type:", collections.Counter(e["type"] for e in els))

buildings = [e for e in els if "building" in e.get("tags", {})]
highways = [e for e in els if "highway" in e.get("tags", {}) and e["type"] == "way"]
waterways = [e for e in els if "waterway" in e.get("tags", {})]
landuse = [e for e in els if "landuse" in e.get("tags", {})]
leisure = [e for e in els if "leisure" in e.get("tags", {})]

print("buildings:", len(buildings))
print("highway ways:", len(highways))
print("waterways:", len(waterways))
print("landuse:", len(landuse))
print("leisure:", len(leisure))

print("\nhighway classes:", collections.Counter(h["tags"]["highway"] for h in highways).most_common())
print("\nbuilding values:", collections.Counter(b["tags"]["building"] for b in buildings).most_common(15))

with_height = [b for b in buildings if "height" in b.get("tags", {})]
with_levels = [b for b in buildings if "building:levels" in b.get("tags", {})]
print("\nbuildings with height tag:", len(with_height))
print("buildings with levels tag:", len(with_levels))

named = [b for b in buildings if "name" in b.get("tags", {})]
print("\nnamed buildings:", len(named))
for b in named[:25]:
    t = b["tags"]
    print("  -", t["name"], "|", t.get("building"), "| levels:", t.get("building:levels"))

print("\nnamed roads sample:")
seen = set()
for h in highways:
    n = h["tags"].get("name")
    if n and n not in seen:
        seen.add(n)
print("  ", sorted(seen)[:40])

print("\nwaterway names:", sorted({w["tags"].get("name", "?") for w in waterways}))
