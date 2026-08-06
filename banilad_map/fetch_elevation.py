"""Sample real ground elevation for the map, and cache it.

    python banilad_map/fetch_elevation.py            # sample what is missing
    python banilad_map/fetch_elevation.py --stats    # summarise the cache only

Phase 2 of CITY_MASTER_PLAN.md is roads-authoritative terrain: road centreline
heights are smoothed and grade-clamped, then the ground between roads is
interpolated from them. The useful consequence is that **no raster DEM is
needed** -- only point elevations at the road-graph nodes, plus a coarse grid
so ground far from any road still has real data behind it.

That matters practically: Copernicus/SRTM rasters are Cloud-Optimized GeoTIFFs
and this machine has no rasterio, no GDAL and no scipy. Point queries need
none of them.

Source is opentopodata.org's public SRTM 30 m endpoint: no API key, 100
locations per request, 1 request/second, 1000 requests/day. The whole map fits
in roughly 120 requests.

SRTM is a surface model, so it reads high where a 30 m cell is filled by
buildings. The road-height solve in 2b smooths and grade-clamps along each way,
which is what turns noisy surface samples into a usable road profile -- see
CITY_MASTER_PLAN.md section 6.3 for why draping raw DEM on roads does not work.

The result is committed, like banilad_osm.json: it is a stable input, and
re-sampling costs a rate-limited round trip for no benefit.
"""

import argparse
import json
import math
import pathlib
import sys
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from geo import LAT0, LON0, METRES_PER_DEG_LAT, METRES_PER_DEG_LON, unproject  # noqa: E402

PROJECT = HERE.parent
ROAD_GRAPH = PROJECT / "assets" / "maps" / "cebu_road_graph.json"
OUT_FILE = HERE / "elevation.json"

DATASET = "srtm30m"
ENDPOINT = "https://api.opentopodata.org/v1/{:s}"
BATCH = 100          # locations per request, the service maximum
REQUEST_DELAY = 1.1  # the service allows 1/second

# Coordinates are rounded to this many decimals as the cache key. 5 decimals is
# about 1.1 m -- far finer than SRTM's 30 m posting, and enough that two graph
# nodes at the same junction collapse to one sample.
KEY_DECIMALS = 5

# Coarse fallback lattice so ground away from any road still has real data.
# 200 m is well inside SRTM's own resolution for interpolation purposes.
GRID_SPACING = 200.0


def key_of(lat, lon):
    return "{:.5f},{:.5f}".format(round(lat, KEY_DECIMALS), round(lon, KEY_DECIMALS))


def load_cache():
    if not OUT_FILE.exists():
        return {}
    doc = json.loads(OUT_FILE.read_text(encoding="utf-8"))
    return doc.get("samples", {})


def save_cache(samples):
    OUT_FILE.write_bytes(json.dumps({
        "dataset": DATASET,
        "note": "ground elevation in metres, keyed 'lat,lon' to 5 decimals",
        "samples": samples,
    }).encode("utf-8"))


def graph_points():
    """Every road-graph node, back-projected to lat/lon."""
    if not ROAD_GRAPH.exists():
        raise SystemExit("{!s} missing - run build_map.py first".format(ROAD_GRAPH))
    graph = json.loads(ROAD_GRAPH.read_text(encoding="utf-8"))
    out = []
    for node in graph["nodes"]:
        # Graph positions are Godot (x, z); Blender y is the negation of z.
        lat, lon = unproject(node["p"][0], -node["p"][1])
        out.append((lat, lon))
    return out


def grid_points(half_extent):
    """A coarse lattice over the whole ground plane."""
    out = []
    steps = int(math.ceil(half_extent / GRID_SPACING))
    for row in range(-steps, steps + 1):
        for col in range(-steps, steps + 1):
            lat, lon = unproject(col * GRID_SPACING, row * GRID_SPACING)
            out.append((lat, lon))
    return out


def ground_half_extent():
    """Mirror build_map.py's derived plane, so the lattice covers all of it."""
    graph = json.loads(ROAD_GRAPH.read_text(encoding="utf-8"))
    reach = 0.0
    for node in graph["nodes"]:
        reach = max(reach, abs(node["p"][0]), abs(node["p"][1]))
    return reach + 200.0


def fetch_batch(batch):
    locations = "|".join("{:.6f},{:.6f}".format(lat, lon) for lat, lon in batch)
    url = ENDPOINT.format(DATASET) + "?locations=" + locations
    last = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "ucb-inday-map-build/1.0"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = exc
            print("[dem]   failed: {:s}".format(str(exc)))
            time.sleep(min(60.0, 5.0 * (2 ** attempt)))
    raise SystemExit("elevation service unreachable: {!s}".format(last))


def summarise(samples):
    values = [v for v in samples.values() if v is not None]
    if not values:
        print("[dem] cache is empty")
        return
    values.sort()
    print("[dem] {:,d} samples ({:,d} with no data)".format(
        len(samples), len(samples) - len(values)))
    print("[dem] min {:.1f} m   median {:.1f} m   max {:.1f} m".format(
        values[0], values[len(values) // 2], values[-1]))

    # Landmarks worth eyeballing against local knowledge.
    #
    # Looked up by NEAREST sample, not by exact key: a hand-typed coordinate
    # essentially never lands on a road node or a lattice point, so an exact
    # lookup silently prints nothing and the sanity check quietly does not
    # happen. It did exactly that the first time this ran.
    located = []
    for cache_key, value in samples.items():
        if value is None:
            continue
        lat_text, lon_text = cache_key.split(",")
        located.append((float(lat_text), float(lon_text), value))

    for name, lat, lon in (
        ("Banilad spawn", 10.33950, 123.91160),
        ("Cebu IT Park", 10.33050, 123.90600),
        ("Ayala Center", 10.31810, 123.90530),
        ("Fuente Osmena", 10.31030, 123.89170),
        ("Colon Street", 10.29550, 123.90050),
        ("Fort San Pedro", 10.29250, 123.90550),
    ):
        best = min(located, key=lambda s: (s[0] - lat) ** 2 + (s[1] - lon) ** 2)
        away = math.dist(
            ((best[1] - lon) * METRES_PER_DEG_LON, (best[0] - lat) * METRES_PER_DEG_LAT),
            (0.0, 0.0))
        print("   {:<16s} {:6.1f} m   (nearest sample {:.0f} m away)".format(
            name, best[2], away))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stats", action="store_true",
                        help="summarise the cached samples and exit")
    args = parser.parse_args()

    samples = load_cache()
    if args.stats:
        summarise(samples)
        return 0

    wanted = {}
    for lat, lon in graph_points():
        wanted[key_of(lat, lon)] = (lat, lon)
    road_keys = len(wanted)
    for lat, lon in grid_points(ground_half_extent()):
        wanted.setdefault(key_of(lat, lon), (lat, lon))

    missing = [(k, v) for k, v in wanted.items() if k not in samples]
    print("[dem] {:,d} distinct points ({:,d} from the road graph, {:,d} lattice)".format(
        len(wanted), road_keys, len(wanted) - road_keys))
    print("[dem] {:,d} already cached, {:,d} to fetch, {:,d} request(s)".format(
        len(wanted) - len(missing), len(missing),
        (len(missing) + BATCH - 1) // BATCH))
    if not missing:
        summarise(samples)
        return 0

    for start in range(0, len(missing), BATCH):
        chunk = missing[start:start + BATCH]
        payload = fetch_batch([coords for _key, coords in chunk])
        if payload.get("status") != "OK":
            raise SystemExit("elevation service said: {!s}".format(payload))
        results = payload.get("results", [])
        if len(results) != len(chunk):
            raise SystemExit("asked for {:d} points, got {:d}".format(
                len(chunk), len(results)))
        for (cache_key, _coords), result in zip(chunk, results):
            samples[cache_key] = result.get("elevation")
        done = min(start + BATCH, len(missing))
        print("[dem] {:,d}/{:,d}".format(done, len(missing)))
        # Save as we go: the service is rate limited and a crash halfway
        # through should not throw away a hundred round trips.
        save_cache(samples)
        if done < len(missing):
            time.sleep(REQUEST_DELAY)

    save_cache(samples)
    print("[dem] wrote {:s} ({:,d} bytes)".format(
        OUT_FILE.name, OUT_FILE.stat().st_size))
    summarise(samples)
    return 0


if __name__ == "__main__":
    sys.exit(main())
