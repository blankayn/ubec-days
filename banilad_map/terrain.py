"""Roads-authoritative terrain: solve road heights, then sample ground from them.

CITY_MASTER_PLAN.md section 6.3. The short version of why this exists:

**Do not drape roads on the DEM.** SRTM is a 30 m *surface* model, so over a
dense block it reads building tops. Sampled straight onto a centreline it
ripples by several metres over a few hundred -- measured on Osmena Boulevard as
32, 35, 29, 30, 33, 28, 21 m. Drape that and cars bounce, sidewalks kink, and
the flat road-collision plane stops being flat, which reintroduces the
VehicleWheel3D chatter that Roads_Collision exists to prevent.

Invert it instead, the way road engineering does:

  1. Sample the DEM at every road-graph NODE (junctions and way ends).
  2. Smooth those heights across the graph, which kills surface noise while
     keeping the real long-range profile.
  3. Clamp the grade of each edge. This is aimed at DEM *artifacts* -- a 30 m
     cell filled by a tall building yields an impossible 50% ramp -- not at
     real hills, so the limits are deliberately generous. Cebu genuinely has
     steep streets and they should stay steep.
  4. Treat each edge as a straight ramp between its two node heights.

Junction reconciliation is then free: a junction IS one node, so every way
meeting there necessarily agrees. That is the whole reason heights live on
nodes rather than on per-way polylines.

Ground away from the carriageway is inverse-distance weighted from the solved
road heights, falling back to the DEM lattice where no road is near. There is
no scipy on this machine, so IDW replaces the Delaunay interpolation the plan
originally assumed; for a ground mesh the difference is not visible.
"""

import json
import math
import pathlib
import sys

HERE = pathlib.Path(__file__).parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from geo import project  # noqa: E402

PROJECT = HERE.parent
ELEVATION_FILE = HERE / "elevation.json"
ROAD_GRAPH = PROJECT / "assets" / "maps" / "cebu_road_graph.json"

# Nearest DEM samples averaged for one query. 3 smooths the 30 m posting
# without dragging in a neighbouring hillside.
DEM_NEIGHBOURS = 3

# Graph smoothing. Few passes on purpose: enough to remove the metre-scale
# surface noise, not enough to flatten the 24 m Fuente-to-Colon descent.
SMOOTH_PASSES = 4
SMOOTH_WEIGHT = 0.45

# Grade limits, as rise over run. Generous by design -- these catch DEM
# artifacts, not real hills.
GRADE_ARTERIAL = 0.10
GRADE_LOCAL = 0.18
GRADE_PASSES = 24
ARTERIAL = {"primary", "primary_link", "secondary", "secondary_link",
            "tertiary", "tertiary_link"}

# Ground interpolation.
IDW_RADIUS = 220.0     # roads beyond this do not influence ground height
IDW_NEIGHBOURS = 8
IDW_POWER = 2.0


class PointField:
    """Uniform-grid index over scattered (x, y, value) samples.

    A linear scan is far too slow here: the height solve queries ~9k road nodes
    against ~12k DEM samples, and the ground mesh queries tens of thousands
    more.
    """

    def __init__(self, samples, cell=250.0):
        self.cell = cell
        self.buckets = {}
        for x, y, value in samples:
            self.buckets.setdefault(self._key(x, y), []).append((x, y, value))

    def _key(self, x, y):
        return (int(math.floor(x / self.cell)), int(math.floor(y / self.cell)))

    def near(self, x, y, rings=1):
        cx, cy = self._key(x, y)
        out = []
        for dx in range(-rings, rings + 1):
            for dy in range(-rings, rings + 1):
                out.extend(self.buckets.get((cx + dx, cy + dy), ()))
        return out

    def nearest(self, x, y, count):
        """Mean value of the `count` nearest samples, widening until some land."""
        rings = 1
        found = self.near(x, y, rings)
        while not found and rings < 24:
            rings += 1
            found = self.near(x, y, rings)
        if not found:
            return None
        found.sort(key=lambda s: (s[0] - x) ** 2 + (s[1] - y) ** 2)
        chosen = found[:count]
        return sum(s[2] for s in chosen) / len(chosen)


def load_dem():
    """DEM samples reprojected into Blender XY metres."""
    if not ELEVATION_FILE.exists():
        raise SystemExit(
            "{!s} missing - run fetch_elevation.py".format(ELEVATION_FILE))
    doc = json.loads(ELEVATION_FILE.read_text(encoding="utf-8"))
    samples = []
    for key, value in doc["samples"].items():
        if value is None:
            continue
        lat_text, lon_text = key.split(",")
        x, y = project(float(lat_text), float(lon_text))
        samples.append((x, y, float(value)))
    if not samples:
        raise SystemExit("elevation cache holds no usable samples")
    return samples


def solve_node_heights(graph, dem_field):
    """Fill every graph node's `y` with a solved ground height. Mutates graph."""
    nodes = graph["nodes"]
    edges = graph["edges"]

    # --- 1. raw DEM height per node ---------------------------------------
    heights = []
    for node in nodes:
        x, y = node["p"][0], -node["p"][1]        # Godot (x, z) -> Blender (x, y)
        value = dem_field.nearest(x, y, DEM_NEIGHBOURS)
        heights.append(0.0 if value is None else value)
    raw = list(heights)

    # --- adjacency, with edge lengths and per-edge grade limits ------------
    neighbours = [[] for _ in nodes]
    spans = []
    for edge in edges:
        pts = edge["pts"]
        length = 0.0
        for i in range(len(pts) - 1):
            length += math.dist(pts[i], pts[i + 1])
        length = max(length, 1.0)
        limit = GRADE_ARTERIAL if edge["cls"] in ARTERIAL else GRADE_LOCAL
        a, b = edge["a"], edge["b"]
        neighbours[a].append((b, length))
        neighbours[b].append((a, length))
        spans.append((a, b, length, limit))

    # --- 2. smooth across the graph ---------------------------------------
    # Nearer neighbours pull harder, so a long edge out to an unrelated part of
    # the network does not drag a junction with it.
    for _ in range(SMOOTH_PASSES):
        updated = list(heights)
        for index, links in enumerate(neighbours):
            if not links:
                continue
            total = 0.0
            weight_sum = 0.0
            for other, length in links:
                weight = 1.0 / length
                total += heights[other] * weight
                weight_sum += weight
            average = total / weight_sum
            updated[index] = (heights[index] * (1.0 - SMOOTH_WEIGHT)
                              + average * SMOOTH_WEIGHT)
        heights = updated

    # --- 3. clamp grades ---------------------------------------------------
    clamped = 0
    for _ in range(GRADE_PASSES):
        worst = 0.0
        for a, b, length, limit in spans:
            drop = heights[b] - heights[a]
            allowed = limit * length
            if abs(drop) <= allowed:
                continue
            excess = (abs(drop) - allowed) * 0.5
            worst = max(worst, abs(drop) / length)
            if drop > 0:
                heights[b] -= excess
                heights[a] += excess
            else:
                heights[b] += excess
                heights[a] -= excess
            clamped += 1
        if worst == 0.0:
            break

    for node, value in zip(nodes, heights):
        node["y"] = round(value, 3)

    moved = [abs(h - r) for h, r in zip(heights, raw)]
    return {
        "nodes": len(nodes),
        "min": round(min(heights), 2),
        "max": round(max(heights), 2),
        "mean_shift": round(sum(moved) / len(moved), 3),
        "max_shift": round(max(moved), 2),
        "grade_fixes": clamped,
    }


def road_field(graph):
    """Index of solved road heights, for querying ground near a carriageway.

    Built from edge endpoints plus interpolated interior points, so a long edge
    still influences the ground along its whole length rather than only at its
    junctions.
    """
    nodes = graph["nodes"]
    samples = []
    for edge in graph["edges"]:
        pts = edge["pts"]
        ha = nodes[edge["a"]]["y"]
        hb = nodes[edge["b"]]["y"]
        runs = [0.0]
        for i in range(len(pts) - 1):
            runs.append(runs[-1] + math.dist(pts[i], pts[i + 1]))
        total = runs[-1] or 1.0
        for point, run in zip(pts, runs):
            height = ha + (hb - ha) * (run / total)
            samples.append((point[0], -point[1], height))
    return PointField(samples, cell=200.0)


def ground_sampler(graph, dem_field):
    """Return f(x, y) -> ground height, roads authoritative, DEM as fallback."""
    roads = road_field(graph)

    def sample(x, y):
        near = roads.near(x, y, rings=1)
        weighted = 0.0
        weights = 0.0
        if near:
            near.sort(key=lambda s: (s[0] - x) ** 2 + (s[1] - y) ** 2)
            for sx, sy, value in near[:IDW_NEIGHBOURS]:
                distance = math.dist((sx, sy), (x, y))
                if distance <= 0.01:
                    return value
                if distance > IDW_RADIUS:
                    continue
                weight = 1.0 / (distance ** IDW_POWER)
                weighted += value * weight
                weights += weight
        if weights > 0.0:
            return weighted / weights
        fallback = dem_field.nearest(x, y, DEM_NEIGHBOURS)
        return 0.0 if fallback is None else fallback

    return sample


def main():
    graph = json.loads(ROAD_GRAPH.read_text(encoding="utf-8"))
    dem_field = PointField(load_dem())
    report = solve_node_heights(graph, dem_field)
    ROAD_GRAPH.write_bytes(json.dumps(graph).encode("utf-8"))
    print("[terrain] solved {nodes:,d} node heights".format(**report))
    print("[terrain] range {min:.1f} .. {max:.1f} m".format(**report))
    print("[terrain] smoothing moved nodes {mean_shift:.2f} m on average, "
          "{max_shift:.1f} m at most".format(**report))
    print("[terrain] grade corrections applied: {grade_fixes:,d}".format(**report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
