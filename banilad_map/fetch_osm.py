"""Re-download the OSM extract from Overpass using overpass_query.txt.

The bounding box in the query file is the single source of truth for the map's
extent; build_map.py projects whatever it finds. Run this only when the bbox
changes -- the committed banilad_osm.json is otherwise the stable input.

    python fetch_osm.py
"""

import pathlib
import sys
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).parent
QUERY_FILE = HERE / "overpass_query.txt"
OUT_FILE = HERE / "banilad_osm.json"

# Mirrors are tried in order; the main instance rate-limits aggressively.
ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]


def fetch(query):
    payload = query.encode("utf-8")
    last = None
    for url in ENDPOINTS:
        for attempt in range(3):
            try:
                print("[osm] POST {:s} (attempt {:d})".format(url, attempt + 1))
                req = urllib.request.Request(
                    url, data=payload,
                    headers={"User-Agent": "ucb-inday-map-build/1.0"},
                )
                with urllib.request.urlopen(req, timeout=300) as resp:
                    return resp.read()
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                last = exc
                print("[osm]   failed: {:s}".format(str(exc)))
                time.sleep(5 * (attempt + 1))
    raise SystemExit("all Overpass endpoints failed: {!s}".format(last))


def main():
    query = QUERY_FILE.read_text(encoding="utf-8")
    raw = fetch(query)
    text = raw.decode("utf-8")
    if '"elements"' not in text:
        raise SystemExit("response is not an Overpass JSON payload:\n" + text[:500])
    OUT_FILE.write_bytes(raw)
    print("[osm] wrote {:s} ({:,d} bytes)".format(OUT_FILE.name, len(raw)))


if __name__ == "__main__":
    sys.exit(main())
