"""Re-download the OSM extract from Overpass using overpass_query.txt.

`overpass_query.txt` stays the single source of truth for both the map's extent
and which tags come back. This script reads its `bbox:` and `tiles:` header
directives, subdivides the bbox, fetches each tile separately, caches it, and
merges the tiles into `banilad_osm.json`. `build_map.py` projects whatever it
finds there.

Tiling exists because the Phase 1 extent is 20.8 km2 of dense downtown Cebu --
about 6.3x the current area at much higher density -- and one Overpass request
for that reliably times out at 300 s. Tiling also means re-pulling Carbon does
not re-pull Banilad.

Ways straddling a tile boundary come back whole from every tile they touch
(`out geom` returns full geometries), so the merge dedupes on `(type, id)`.
First occurrence wins and **source order is preserved** -- do not sort, or the
geometry order inside the exported GLB churns on every fetch for no reason.

With a single tile the raw response is written through unchanged, so the
shipped 1x1 configuration behaves byte-for-byte like the pre-tiling script.

    python fetch_osm.py                # fetch any tile that is not cached
    python fetch_osm.py --force        # ignore the cache, re-fetch everything
    python fetch_osm.py --tile r0c1    # re-fetch one tile, then re-merge
    python fetch_osm.py --list         # print the tile grid and exit

The committed banilad_osm.json is the stable input; run this only when the
bbox or the tag set changes.
"""

import argparse
import collections
import hashlib
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).parent
QUERY_FILE = HERE / "overpass_query.txt"
OUT_FILE = HERE / "banilad_osm.json"
CACHE_DIR = HERE / ".osm_cache"

# Mirrors are tried in order; the main instance rate-limits aggressively.
# Whichever one answers first is then used for every remaining tile -- see
# fetch() for why mixing them corrupts the snapshot.
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

# Pause between tile requests. Overpass returns 429 quickly without it, and at
# 18+ tiles that matters a lot: one forced mirror fallback taints the whole
# merged extract, so a couple of extra minutes of politeness is far cheaper
# than a re-fetch.
TILE_DELAY = 14.0


def parse_query(text):
    """Split the query file into (bbox, (rows, cols), body).

    Lines starting with `#` are stripped here and never reach Overpass --
    Overpass QL has no `#` comment, so the query file's annotations only work
    because this function removes them.
    """
    bbox = None
    tiles = (1, 1)
    body = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("#"):
            continue
        lowered = stripped.lower()
        if lowered.startswith("bbox:"):
            parts = stripped.split(":", 1)[1].split()
            if len(parts) != 4:
                raise SystemExit("bbox: needs 4 numbers (south west north east)")
            bbox = tuple(float(p) for p in parts)
            continue
        if lowered.startswith("tiles:"):
            parts = stripped.split(":", 1)[1].split()
            if len(parts) != 2:
                raise SystemExit("tiles: needs 2 integers (rows cols)")
            tiles = (int(parts[0]), int(parts[1]))
            continue
        body.append(raw)

    if bbox is None:
        raise SystemExit("overpass_query.txt has no `bbox:` directive")
    if bbox[0] >= bbox[2] or bbox[1] >= bbox[3]:
        raise SystemExit("bbox must be south west north east, with south < north "
                         "and west < east (got {!r})".format(bbox))
    if tiles[0] < 1 or tiles[1] < 1:
        raise SystemExit("tiles: rows and cols must both be >= 1")

    joined = "\n".join(body).strip() + "\n"
    if "{bbox}" not in joined:
        raise SystemExit("the query body has no {bbox} placeholder to substitute")
    return bbox, tiles, joined


def fmt(value):
    return "{:.7f}".format(value).rstrip("0").rstrip(".")


def tile_grid(bbox, tiles):
    """Row-major list of (name, (south, west, north, east)) covering bbox."""
    south, west, north, east = bbox
    rows, cols = tiles
    grid = []
    for r in range(rows):
        lat0 = south + (north - south) * r / rows
        lat1 = south + (north - south) * (r + 1) / rows
        for c in range(cols):
            lon0 = west + (east - west) * c / cols
            lon1 = west + (east - west) * (c + 1) / cols
            grid.append(("r{:d}c{:d}".format(r, c), (lat0, lon0, lat1, lon1)))
    return grid


def cache_path(name, query):
    """Cache key covers the whole substituted query, not just the tile name.

    Keying on the name alone is wrong and was caught the first time the grid
    changed: a 1x1 fetch writes r0c0 for the WHOLE bbox, then a 2x2 fetch asks
    for r0c0 meaning the south-west quadrant and is silently handed the old
    full-extent response. The merge then looks healthy while missing a quarter
    of the map. Hashing the query also invalidates the cache when the tag set
    in overpass_query.txt changes, which has exactly the same failure mode.
    """
    digest = hashlib.sha1(query.encode("utf-8")).hexdigest()[:12]
    return CACHE_DIR / "{:s}_{:s}.json".format(name, digest)


def meta_path(cache):
    """Sidecar recording which mirror served a cached tile.

    Knowing a fetch went mixed is not enough to repair it -- you also have to
    know WHICH tiles came from the wrong mirror, or the only remedy is
    re-fetching everything. With this, a repeat run silently re-fetches just
    the odd ones out and converges on a single consistent snapshot.
    """
    return cache.with_suffix(".endpoint")


class FetchError(RuntimeError):
    """Every mirror refused this query. Recoverable: the caller may subdivide."""


# A tile may be halved at most this many times (so at most 16 sub-queries).
MAX_SUBDIVISION = 2


def quarters(tile):
    south, west, north, east = tile
    mid_lat = (south + north) * 0.5
    mid_lon = (west + east) * 0.5
    return [
        (south, west, mid_lat, mid_lon), (south, mid_lon, mid_lat, east),
        (mid_lat, west, north, mid_lon), (mid_lat, mid_lon, north, east),
    ]


def fetch(query, state):
    """Fetch one tile, preferring the endpoint that already served this run.

    Every tile must come from the SAME mirror. Mirrors replicate from OSM
    independently, so two of them can disagree by hours; merging tiles across
    mirrors produced an extract where 36 ways existed in one half of the map
    and not the other, and 114 more carried different tags -- an inconsistent
    snapshot that looks perfectly healthy until something downstream trips over
    a road that is there on one side of a tile seam and gone on the other.
    """
    payload = query.encode("utf-8")
    order = list(ENDPOINTS)
    if state.get("endpoint") in order:
        order.remove(state["endpoint"])
        order.insert(0, state["endpoint"])

    last = None
    for url in order:
        for attempt in range(4):
            try:
                print("[osm] POST {:s} (attempt {:d})".format(url, attempt + 1))
                req = urllib.request.Request(
                    url, data=payload,
                    headers={"User-Agent": "ucb-inday-map-build/1.0"},
                )
                with urllib.request.urlopen(req, timeout=300) as resp:
                    data = resp.read()
                if state.get("endpoint") and state["endpoint"] != url:
                    state["mixed"] = True
                    print("[osm] WARNING: switched mirror to {:s} mid-run. Tiles now "
                          "come from mirrors with different replication lag, so the "
                          "merged extract is not a single consistent snapshot. "
                          "Re-run with --force once the primary is healthy."
                          .format(url))
                state["endpoint"] = url
                return data
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                last = exc
                print("[osm]   failed: {:s}".format(str(exc)))
                # Overpass rate-limits per IP on a slot system, and a linear
                # backoff is not enough to clear it. Exponential, capped.
                time.sleep(min(120.0, 15.0 * (2 ** attempt)))
    raise FetchError(str(last))


def fetch_tile(name, tile, body, state, args, served_by, depth=0):
    """Raw payloads covering `tile`, subdividing it if Overpass will not serve it.

    Overpass answers a too-expensive query with 504, and it answers that way
    from every mirror, so retrying harder never helps -- slice 5 burned eight
    attempts across two mirrors on one tile before giving up. Splitting does
    help: the same ground fetched as four cheaper queries. Sub-tiles merge
    transparently because the merge dedupes on (type, id), and each gets its
    own cache entry keyed by its own bbox.
    """
    query = body.replace("{bbox}", ",".join(fmt(v) for v in tile))
    cached = cache_path(name, query)
    stale = (args.force or args.tile == name
             or served_by.get(name, state["endpoint"]) != state["endpoint"]
             # A cached payload with no recorded mirror predates that
             # bookkeeping and cannot be trusted to match the others.
             or (cached.exists() and name not in served_by))
    if cached.exists() and not stale:
        print("[osm] {:s}: cached ({:,d} bytes)".format(name, cached.stat().st_size))
        return [cached.read_bytes()]

    if state["fetched"]:
        time.sleep(TILE_DELAY)   # be a good citizen; avoids most 429s
    try:
        raw = validate(fetch(query, state))
    except FetchError as exc:
        if depth >= MAX_SUBDIVISION:
            raise
        print("[osm] {:s}: no mirror would serve it ({:s}); splitting into 4"
              .format(name, exc))
        state["split"] += 1
        out = []
        for index, sub in enumerate(quarters(tile)):
            out.extend(fetch_tile("{:s}q{:d}".format(name, index), sub, body,
                                  state, args, served_by, depth + 1))
        return out

    state["fetched"] += 1
    cached.write_bytes(raw)
    meta_path(cached).write_text(state["endpoint"], encoding="utf-8")
    print("[osm] {:s}: fetched ({:,d} bytes) from {:s}".format(
        name, len(raw), state["endpoint"]))
    return [raw]


def validate(raw):
    text = raw.decode("utf-8", errors="replace")
    if '"elements"' not in text:
        raise SystemExit("response is not an Overpass JSON payload:\n" + text[:500])
    return raw


def merge(payloads):
    """Dedupe on (type, id), preserving first-seen order."""
    seen = set()
    elements = []
    meta = None
    for raw in payloads:
        data = json.loads(raw.decode("utf-8"))
        if meta is None:
            meta = {k: v for k, v in data.items() if k != "elements"}
        for element in data.get("elements", []):
            key = (element.get("type"), element.get("id"))
            if key in seen:
                continue
            seen.add(key)
            elements.append(element)
    merged = dict(meta or {})
    merged["elements"] = elements
    return merged, len(elements)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true",
                        help="ignore the cache and re-fetch every tile")
    parser.add_argument("--tile", metavar="NAME",
                        help="re-fetch just this tile (e.g. r0c1), then re-merge")
    parser.add_argument("--list", action="store_true",
                        help="print the tile grid and exit without fetching")
    parser.add_argument("--endpoint", metavar="URL",
                        help="pin every tile to this Overpass mirror")
    args = parser.parse_args()

    bbox, tiles, body = parse_query(QUERY_FILE.read_text(encoding="utf-8"))
    grid = tile_grid(bbox, tiles)

    print("[osm] bbox  {:s} {:s} {:s} {:s}".format(*[fmt(v) for v in bbox]))
    print("[osm] tiles {:d} x {:d} ({:d} request(s))".format(tiles[0], tiles[1], len(grid)))

    if args.list:
        for name, tile in grid:
            print("  {:s}  {:s} {:s} {:s} {:s}".format(name, *[fmt(v) for v in tile]))
        return 0

    if args.tile and args.tile not in {name for name, _ in grid}:
        raise SystemExit("no tile named {!r}; run --list to see the grid".format(args.tile))

    CACHE_DIR.mkdir(exist_ok=True)

    # Every tile must come from the same mirror. Work out which one the cache
    # already mostly agrees on, then treat any tile served by a different one
    # as stale -- that converges a mixed cache on a consistent snapshot without
    # re-fetching the tiles that were already fine.
    served_by = {}
    for name, tile in grid:
        query = body.replace("{bbox}", ",".join(fmt(v) for v in tile))
        meta = meta_path(cache_path(name, query))
        if meta.exists():
            served_by[name] = meta.read_text(encoding="utf-8").strip()

    if args.endpoint:
        target = args.endpoint
    elif served_by:
        target = collections.Counter(served_by.values()).most_common(1)[0][0]
    else:
        target = ENDPOINTS[0]

    mismatched = sorted(n for n, url in served_by.items() if url != target)
    if mismatched:
        print("[osm] repairing {:d} tile(s) served by another mirror: {:s}".format(
            len(mismatched), ", ".join(mismatched)))
    print("[osm] pinned to {:s}".format(target))

    payloads = []
    state = {"endpoint": target, "fetched": 0, "split": 0}
    try:
        for name, tile in grid:
            payloads.extend(fetch_tile(name, tile, body, state, args, served_by))
    except FetchError as exc:
        raise SystemExit(
            "all Overpass endpoints failed even after subdividing: {!s}\n"
            "Tiles already fetched are cached, so re-running resumes where this "
            "stopped rather than starting over.".format(exc))
    if state["split"]:
        print("[osm] {:d} tile(s) had to be subdivided".format(state["split"]))

    if state.get("mixed"):
        print("[osm] WARNING: this extract was assembled from more than one mirror, "
              "so it is NOT a single consistent snapshot. Run again to repair the "
              "odd tiles out once the mirrors are healthy.")
        return 2

    if len(payloads) == 1:
        # Single tile: write the response through untouched, so the shipped
        # configuration is byte-identical to the pre-tiling script's output.
        OUT_FILE.write_bytes(payloads[0])
        print("[osm] wrote {:s} ({:,d} bytes, verbatim)".format(
            OUT_FILE.name, len(payloads[0])))
        return 0

    merged, count = merge(payloads)
    # Bytes, not write_text: text mode would translate newlines to CRLF on
    # Windows inside a data file, and Python 3.13's pathlib raises EINVAL
    # opening this path in text mode. json.dumps defaults to ensure_ascii, so
    # the payload is pure ASCII and the encode is lossless.
    OUT_FILE.write_bytes(json.dumps(merged).encode("utf-8"))
    print("[osm] wrote {:s} ({:,d} bytes, {:,d} unique elements from {:d} tiles)".format(
        OUT_FILE.name, OUT_FILE.stat().st_size, count, len(payloads)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
