# Cebu City Master Plan — Banilad → Port Corridor

Companion to `PROJECT_STATUS.md`. That document records what the project **is**;
this one records where the city **goes** and in what order. Read `PROJECT_STATUS.md`
first for pipeline commands, engine traps and the current milestone state.

## Context

`UBEC - Days` already has a working OSM→Blender→Godot city pipeline covering
1.75 × 1.88 km of Banilad and Cebu IT Park. This plan extends it south-west
across the Ayala / Fuente / Colon / Carbon / Port corridor — the historic and
commercial core of Cebu City.

This is **not** a greenfield build. The pipeline is mature and its hard-won
details (junction sidewalk clipping, the flat road-collision plane, the
sRGB→linear→Godot palette round-trip, gravity-18 physics tuning) must survive.
The job is to scale it ~6× in area at much higher urban density, and to add the
three things it structurally lacks: **elevation**, **spatial partitioning**, and
a **road graph**.

Four decisions are locked from the planning conversation:

| Decision | Choice |
|---|---|
| Terrain | **DEM heightfield** — Copernicus GLO-30, roads authoritative |
| Scope shape | **Contiguous corridor, staged** north→south |
| Renderer | **Stay `gl_compatibility`** — hand-rolled tile streaming |
| Era | **Circa 2019 Cebu** — pre-redevelopment Carbon, pre-BRT Osmeña |

**This document is planning only. No assets or code are produced by it.**

---

## 0. What already exists (do not rebuild)

| Asset | State |
|---|---|
| `banilad_map/build_map.py` (2346 L) | OSM → roads, sidewalks, markings, buildings, infill, props. **The core engine.** |
| `banilad_map/prep_godot.py` | Scale verification, `-col`/`-colonly` tagging, GLB + landmark JSON export |
| `banilad_map/fetch_osm.py` + `overpass_query.txt` | Overpass fetch. bbox is the single source of truth for extent |
| `tools/build_slum.py` | 5 informal-settlement barangays, 417 houses, alley JSON |
| `banilad_map/build_mall.py` | Gaisano Country Mall from 9 surveyed OSM footprints |
| `scripts/vehicle_body.gd` | Working physics driving, `VehicleBody3D`, 2 vehicle kinds |
| `scripts/cblock_player.gd` | Third-person controller, step-up, Mixamo runtime retargeting |
| 12 headless smoke tests | The regression net. Extend these, do not replace them |

Georeference: `LAT0 = 10.3345, LON0 = 123.9115`, equirectangular local-tangent
projection, 1 BU = 1 m, Blender `(x, y)` → Godot `(x, 0, -y)`.

**Keep the origin exactly where it is.** It now sits at the NE corner of the new
bbox rather than the centre, which is aesthetically untidy and completely
harmless — float32 precision at 6 km is ~0.5 mm. Moving it would invalidate
`SPAWN_POSITION`, `MALL_GROUND_PROBE`, `SLUM_GROUND_PROBE`, the five
`SLUM_DISTRICTS` rects, `BAKE_ORIGIN`, and all 110 entries in
`banilad_landmarks.json` — hundreds of hand-tuned numbers, for zero benefit.

---

## 1. Master Plan — target extent

**New Overpass bbox: `10.2890, 123.8860, 10.3410, 123.9190`**

| | Metres | vs current |
|---|---|---|
| N–S span | 5,750 m | 3.1× |
| E–W span | 3,614 m | 2.1× |
| Area | **20.8 km²** | **6.3×** |

Everything lands in Godot coordinates as:
`x = (lon − 123.9115) × 109514`, `z = −(lat − 10.3345) × 110574`

| Anchor | Real lat/lon | Godot (x, z) | Ground elev. |
|---|---|---|---|
| Gaisano Country Mall (built) | 10.3392, 123.9035 | −87, −519 | ~38 m |
| Player spawn (built) | 10.3395, 123.9116 | 13, −554 | ~40 m |
| Ayala Malls Central Bloc (built) | 10.3307, 123.9073 | −462, +419 | ~42 m |
| Cebu IT Park core | 10.3305, 123.9060 | **−602, +442** | ~40 m |
| Waterfront Hotel / Salinas Dr | 10.3272, 123.9040 | **−821, +807** | ~32 m |
| Cebu Country Club | 10.3230, 123.9090 | **−274, +1271** | ~22 m |
| Cebu Business Park core | 10.3185, 123.9070 | **−493, +1769** | ~18 m |
| Ayala Center Cebu | 10.3181, 123.9053 | **−679, +1814** | ~18 m |
| Cebu Provincial Capitol | 10.3157, 123.8925 | **−2081, +2079** | ~24 m |
| Fuente Osmeña Circle | 10.3103, 123.8917 | **−2168, +2676** | ~15 m |
| Colon Street (midpoint) | 10.2955, 123.9005 | **−1205, +4312** | ~5 m |
| Carbon Market | 10.2925, 123.8988 | **−1391, +4644** | ~3 m |
| Basilica del Santo Niño | 10.2945, 123.9019 | **−1051, +4423** | ~4 m |
| Fort San Pedro | 10.2925, 123.9055 | **−657, +4644** | ~2 m |
| Cebu Port, Pier 1 | 10.2945, 123.9075 | **−438, +4423** | ~2 m |

**MEASURED, and not where this plan first assumed.** The `Ground elev.` column
above was estimated. Real SRTM 30 m samples (`banilad_map/elevation.json`,
11,615 points) say:

| Point | Estimated | **Measured** |
|---|---|---|
| Cebu IT Park | ~40 m | **38.0 m** |
| Gaisano Country Mall | ~38 m | **36.3 m** |
| Provincial Capitol | ~24 m | **36.0 m** |
| Banilad spawn | ~40 m | **33.7 m** |
| Fuente Osmeña | ~15 m | **33.0 m** |
| Ayala Center Cebu | ~18 m | **22.7 m** |
| Cebu Business Park | ~18 m | **14.3 m** |
| Colon Street | ~5 m | **11.3 m** |
| Basilica del Santo Niño | ~4 m | **10.7 m** |

The correction that matters: **Fuente and the Capitol sit at ~33–36 m, level
with Banilad — not in a valley.** The drop is not spread along the corridor as
assumed. It is concentrated in the ~1.2 km of Osmeña Boulevard between Fuente
(33 m) and Colon (11 m), measured at 33 → 21 → 16 → 9 m: a ~24 m descent at
roughly 1.7%. That single stretch is where terrain will read, and it is
continuous and legible exactly as hoped — just in one place rather than five.

The raw profile is also visibly noisy (32, 35, 29, 30, 33, 28, 21 …) because
SRTM is a *surface* model reading building tops. That is the empirical case for
§6.3's smooth-and-clamp step over draping raw DEM.

**The map also backs onto real mountains.** Samples outside the built area
reach **661 m** in the Busay hills to the north-west (p95 415 m) against 336 m
max inside it. That is authentic — Cebu City sits against a steep backdrop —
but it means the ground plane stops being a flat backdrop and becomes the
horizon, which is a visual gain and a triangle-budget question.

### Known exclusions
- **CIT-University** (10.2985, 123.8825) falls ~380 m west of the bbox. Accepted.
- **SM City Cebu** and the North Reclamation Area are north-east and out of scope.
- **Cebu South Coastal Road / SRP** is out of scope.
- Mandaue (A.S. Fortuna, Oakridge) is out of scope.

---

## 2. Development roadmap

Phases are ordered by **dependency**, not by visual payoff. Phases 0–2 unblock
everything downstream and produce almost nothing you can look at; resist the
urge to reorder them.

### Phase 0 — Consolidation (prerequisite, no new content)

The pipeline has four duplicated copies of the georeference and two duplicated
copies of the district rects. At 3.3 km² that is annoying; at 20.8 km² it is a
guaranteed source of silent misalignment.

- Extract `banilad_map/geo.py`: `LAT0`, `LON0`, `METRES_PER_DEG_*`, `project()`,
  `to_godot()`. Import it from `build_map.py`, `build_mall.py`, `find_spawn.py`,
  `tools/build_slum.py`.
  - **This fixes a live bug:** `build_mall.py` uses
    `METRES_PER_DEG_LAT = 110540.0` while `build_map.py` uses `110574.0` — a
    0.03% mismatch, ~0.35 m of drift over the current map and **~1.9 m over the
    new one.**
- Move `SLUM_DISTRICTS` into a shared `districts.py` so `build_map.py` and
  `build_slum.py` read one definition.
- **Fix `scripts/mechanics_smoke_test.gd`.** It has been failing since the first
  commit (line 62, a `DayLocker` StaticBody3D blocking UC's street entrance) and
  because it uses bare `assert()` it *hangs* instead of failing. It is the only
  guard on the 2710-line `school_building.gd`. Phase 5 moves that building into
  the real city; this must be green first.
- Split `fetch_osm.py` into a tiled fetcher (4×3 sub-bboxes, cached per tile,
  merged). A single Overpass query for 20.8 km² of dense downtown will time out
  at the current 300 s, and a tiled fetcher lets you re-pull one district.
- Extend `overpass_query.txt` (see §3.6).

### Phase 1 — Road network (the requested first deliverable)

Roads before everything. They define the terrain (Phase 2), the district
boundaries (Phase 3), the building frontages (Phase 5), and the traffic and
pedestrian graphs (Phases 6–7). Nothing downstream is stable until the network is.

Two outputs, not one:
1. Road **geometry** — the existing ribbon/sidewalk/marking system, extended.
2. Road **graph** — `assets/maps/cebu_road_graph.json`. **New, and the single
   highest-leverage change in this plan.** See §3.5.

### Phase 2 — Terrain and elevation

DEM ingest, roads-authoritative height solve, terrain mesh generation, and the
refactor of every scalar `z` in `build_map.py` into a sampled height. See §6.3.

### Phase 3 — District layout

Zoning rectangles/polygons that drive infill style, building height
distribution, material palette, prop density, traffic density and NPC density
per district. Currently `SLUM_DISTRICTS` is the only zoning concept; it becomes
one entry in a general district table.

### Phase 4 — Tiling and streaming

250 m tile grid, per-tile GLB export, the `TileStreamer`, and the always-on
skyline mesh. Deliberately *before* landmarks and buildings — build the
container before filling it, or you will rebuild every landmark to fit the
tiles.

### Phase 5 — Buildings and landmarks

Tier S / A / B landmark production (§5), the commercial perimeter-block infill
generator, the signage atlas, and the migration of `SchoolBuilding` /
`MallBuilding` into the real map.

### Phase 6 — Traffic system

Lane graph → kinematic puppet traffic, signal phases, roundabout yield at
Fuente, one-way enforcement.

### Phase 7 — NPC system

Sidewalk pedestrian graph derived from the road graph's sidewalk offsets,
crossing-node behaviour, per-district density, pooling.

### Phase 8 — Optimization

Per-tile navmesh baking, `visibility_range_*` tuning, draw-call budgeting, fog
and view-distance tuning, LOD verification.

### Slice order (contiguous corridor, staged)

Each slice is independently playable when it lands. Slice boundaries follow
real district edges, not arbitrary lines.

| # | Slice | Godot z range | Why here |
|---|---|---|---|
| 0 | Banilad + IT Park | −1170 … +720 | **Exists.** Rebuilt onto terrain + tiles in Phases 2 & 4 |
| 1 | Lahug / Gorordo / Salinas | +720 … +1400 | **The connector.** Ayala and IT Park are unreachable from each other without it |
| 2 | Cebu Business Park + Ayala Center | +1400 … +2000 | Highest-value destination, clean grid, easy geometry |
| 3 | Escario / Capitol / Fuente | +2000 … +2800 | Fuente Osmeña is the city's navigational anchor |
| 4 | Osmeña Blvd / University Belt | +2800 … +4100 | The long descent; connects Fuente to downtown |
| 5 | Colon / Parian / downtown core | +4100 … +4500 | **Hardest.** Needs the signage atlas and commercial infill |
| 6 | Carbon / Port / Fort San Pedro | +4500 … +4800 | **Hardest asset job.** Carbon is a `build_slum.py`-scale project of its own |

---

## 3. Road planning

### 3.1 Hierarchy and widths

The current `ROAD_WIDTHS` table was tuned against suburban Banilad and is too
narrow for downtown arterials and too generous for Carbon's stall-choked lanes.
Keep the class table as the fallback, and add a **name-keyed override table**,
because OSM's `lanes` tag is very sparsely populated in Cebu — the existing
`max(width, lanes * 3.4)` rule almost never fires here.

| Tier | OSM class | Carriageway | Sidewalk | Median | Cebu examples |
|---|---|---|---|---|---|
| **Arterial** | `primary` | 20–24 m (4–6 lanes) | 3.0 m both | Yes, 1.5–3 m planted | Osmeña Blvd, N. Bacalso, M.J. Cuenco, Archbishop Reyes |
| **Secondary** | `secondary` | 14–16 m (4 lanes) | 2.6 m both | Occasional | Gen. Maxilom, Escario, Gorordo, Salinas Dr, Juan Luna |
| **Local street** | `tertiary` / `unclassified` | 9–12 m (2 lanes) | 2.0–2.6 m | No | Colon, Sanciangko, P. del Rosario, Leon Kilat, F. Ramos |
| **Service** | `residential` / `service` | 5–7 m | 1.2 m or none | No | Barangay streets, mall service roads, Carbon's grid |
| **Alleyway** | `footway` / `path` | 1.4–2.5 m | — | — | Eskinita, Parian lanes, Carbon stall aisles |

Overrides worth hand-setting (real corridor widths, not OSM defaults):

```
Osmeña Boulevard        24 m + 2.0 m median      (Capitol→Fuente→Colon)
N. Bacalso Avenue       22 m + 2.5 m median
Archbishop Reyes Ave    20 m + 1.5 m median
Cardinal Rosales Ave    20 m + 3.0 m planted median   (Cebu Business Park)
General Maxilom Ave     16 m                     (Mango Ave — nightlife strip)
Escario Street          15 m
Gorordo Avenue          15 m
Salinas Drive           14 m
M.J. Cuenco Avenue      18 m
Colon Street            11 m, narrow sidewalks, partial one-way
Carbon precinct streets  7 m, effectively pedestrianised by stalls
```

Two new geometry features are needed that the ribbon system does not have:
**planted medians** (a raised centre strip, same `raised_ribbon()` primitive as
the existing kerbs) and **awning/signage bands** over the sidewalk on commercial
frontages (see §5.4).

### 3.2 Intersections

The existing two-pass `clip_against_carriageways()` already handles the hard part
— breaking sidewalks and lane markings where they cross another carriageway.
It survives unchanged. What gets added at junctions:

- **Stop-line + zebra quads** at every node tagged `highway=crossing` or
  `highway=traffic_signals`, generated from the incoming way's width and bearing.
- **Corner kerb radii** — currently corners are mitred to a point. Downtown
  junctions want a 4–8 m radius (arterial) or 2–3 m (local), which also stops
  the mitre from spiking at acute angles. Cheap to add in `miter_offsets()`.
- **Junction fill quads** — a flat patch of tarmac covering the crossing area so
  the two ribbons read as one surface rather than an X.
  - **This is now load-bearing, not cosmetic.** Once terrain landed, two
    carriageways crossing at a junction are draped from the same continuous
    field at different tessellations, so their collision surfaces sit 5–46 mm
    apart — the wheel-chatter condition `Roads_Collision` was built to prevent,
    reached by a new route. Tessellating the collision mesh to 4 m was tried:
    it only got the gaps to 19 mm and grew a never-unloaded mesh from 66k
    triangles to 251k (3.5 → 14 MB), so it was reverted. One flat patch per
    junction replaces the overlap instead of tessellating around it, and costs
    almost nothing.

### 3.3 Roundabouts

**Fuente Osmeña Circle is the only significant roundabout in the target area**,
and it is the single most recognisable piece of urban form in Cebu: a ~60 m
rotary with a fountain island, ringed by Crown Regency, Rajah Park, Chong Hua
Hospital and the Fuente hotel strip. It needs a dedicated generator, not the
generic ribbon path — an annular carriageway, a raised planted island, and
correct approach flares on all six legs (Osmeña N, Osmeña S, Gen. Maxilom,
Fuente Osmeña St, Don Julio Llorente, Jones/Ramos approach).

Treat `junction=roundabout` generically anyway; a handful of small ones exist in
Cebu Business Park.

### 3.4 Traffic control, one-ways and crossings

All of this is **already in OSM and currently thrown away**:

| OSM tag | Where | What it drives |
|---|---|---|
| `highway=traffic_signals` (node) | ~40 downtown junctions | Signal post props + phase groups |
| `highway=crossing` (node) | Osmeña, Colon, Mango | Zebra markings + pedestrian crossing behaviour |
| `oneway=yes` (way) | Colon (partial), Carbon grid, several downtown streets | Traffic direction, lane count |
| `junction=roundabout` (way) | Fuente | Yield behaviour |
| `highway=stop` / `give_way` (node) | Local junctions | Puppet traffic yield |

**None of these are currently read, and `node["highway"]` is not even in the
Overpass query.** Fixing that is a one-line change to `overpass_query.txt`.

### 3.5 The road graph — the highest-leverage change in this plan

`build_map.py` pass 1 already resolves every way into `resolved[(pts, width,
cls)]` and builds a `SpatialIndex` of them. It then **discards everything except
the geometry**. `lanes` is read only to widen the ribbon and thrown away;
`oneway`, `name`, `junction` and all node tags are never read at all.

Emit a graph alongside the mesh — it costs perhaps 150 lines in a script that is
already doing 95% of the work:

```jsonc
// assets/maps/cebu_road_graph.json
{
  "nodes": [
    { "id": 0, "p": [-2168.4, 2676.1], "y": 15.2,
      "signal": true, "crossing": false, "roundabout": false }
  ],
  "edges": [
    { "a": 0, "b": 1, "cls": "primary", "name": "Osmeña Boulevard",
      "width": 24.0, "lanes": 4, "lane_width": 6.0, "oneway": 0,
      "roundabout": false, "speed": 40, "way": 12345 }
  ]
}
```

Every downstream system reads this one file:

- **Phase 6 traffic** — lane centrelines are
  `edge ± (lane_index − (lanes − 1) / 2) × lane_width`. Signals and one-ways
  come free.
  - **`lane_width` is published per edge rather than assumed to be 3.4 m.**
    Built and measured: a Cebu residential street is 6.5 m wide and genuinely
    carries two lanes, so a nominal 3.4 m would put the outer lane centreline
    15 cm past the kerb. Dividing the real carriageway keeps every lane inside
    the tarmac by construction — verified at 100% against the collision mesh.
- **Phase 7 NPCs** — sidewalk centrelines are `edge ± (width/2 + 1.3) m`, the
  exact offset `build_map.py` already uses to place the kerbs. Crossings are the
  `crossing` nodes.
- **Phase 5 buildings** — the commercial infill generator needs street frontage
  to align to. It is already computing "nearest road bearing" for the shanty
  infill; the graph makes that a lookup.
- **Props** — street lights, signals and signage already key off `road_lines`.
- **Missions / navigation** — named streets give you "drive to Colon Street" for
  free.

**If this is not emitted in Phase 1, Phase 6 and 7 must re-derive a lane graph
from triangle soup, which is miserable and lossy.** Do it now.

### 3.6 Overpass query additions

```
node["highway"](bbox);                      // signals, crossings, stops
way["barrier"](bbox);                       // walls, fences, the Fort
way["bridge"](bbox); way["railway"](bbox);
way["man_made"="pier"](bbox);               // Piers 1–4
way["amenity"="marketplace"](bbox);         // Carbon, Pasil
way["historic"](bbox);                      // Fort San Pedro, Parian houses
relation["type"="restriction"](bbox);       // turn restrictions (Phase 6b)
```

---

## 4. Cebu accuracy analysis

### 4.1 Naming traps — all three now CONFIRMED against the slice-3 extract

1. **"Jones Avenue" does not exist as a live name.** It survives only as
   `old_name` on ways `25800031` (`Jones Avenue;Capitol Boulevard`) and
   `1456816228`. The live name is **`Osmeña Boulevard`** — 1,496 m in the
   current graph. Locals still say Jones, so keep it as the in-game display
   name via an alias table, but match on `Osmeña Boulevard`.

2. **Both Cuenco avenues are now on the map at once**, 4 km apart:
   - **`Governor M. Cuenco Avenue`** — Banilad, the spine, 2,107 m.
   - **`M.J. Cuenco Avenue`** — downtown, through Parian and Carbon, 1,717 m.
   Note the real spelling has **no space after `M.`**. Any name-keyed override
   table must disambiguate, or the Banilad spine gets downtown widths.

3. **Escario is `N. Escario Street`**, not "Escario Street" — 2,202 m, the
   fifth-longest street on the map. It was reported as absent for a whole slice
   purely because the lookup used the colloquial name.

4. **N. Bacalso is `Natalio Bacalso Avenue`.**

5. **V. Rama is `Vicente Rama Avenue`** — 2,068 m, and it carries
   `short_name = V. Rama Avenue`.

The lesson generalises: **verify a street's OSM name before writing an override
for it.** Every one of these read as missing data until checked, and four of
the five were found only because a road that should obviously have been present
reported 0 m.

**Build the display-name alias table from OSM, not by hand.** The tags are
already there: `short_name` gives `V. Rama Avenue`, `old_name` gives
`Jones Avenue;Capitol Boulevard` (semicolon-separated — split it). That is
exactly the colloquial name a Cebuano would use, so the HUD and any mission
text should show it while the pipeline matches on `name`.

Also: `Osmeña` and `Santo Niño` carry diacritics in OSM. Normalise on load.

### 4.2 Which roads must be modelled first

| Priority | Road | Why it is first |
|---|---|---|
| 1 | **Archbishop Reyes Avenue** | **The connector.** Ayala Center / Cebu Business Park and IT Park are otherwise disconnected islands. Nothing in slices 1–2 works without it. |
| 2 | **Osmeña Boulevard** | The city's spine. Capitol → Fuente → Colon → Plaza Independencia. Every downtown district hangs off it. Also the elevation spine — the 20 m descent happens along it. |
| 3 | **Salinas Drive** | IT Park's front door; links Archbishop Reyes into the existing built area. Waterfront Hotel sits on it. |
| 4 | **Gorordo Avenue** | The second north–south corridor, Lahug → Fuente. Redundancy for the player and for traffic routing. |
| 5 | **Escario Street** | The bypass locals actually use to avoid Osmeña. Fuente/Capitol → Ayala. |
| 6 | **General Maxilom Ave (Mango)** | Fuente → east. The nightlife strip; high pedestrian value. |
| 7 | **M.J. Cuenco Avenue** | Eastern arterial, Carbon/Parian → Mabolo. Closes the downtown loop. |
| 8 | **Colon Street** | Only 700 m, but it *is* the downtown core. |
| 9 | **N. Bacalso Avenue** | Southern gateway, Elizabeth Mall, the road out of town. |
| 10 | **Cardinal Rosales / Mindanao / Luzon / Samar / Bohol / Panay** | Cebu Business Park's internal grid. Trivial geometry, high destination density. |
| 11 | **Quezon Blvd / Serging Osmeña Blvd** | The port road, Piers 1–4. |
| 12 | **Plaridel, Lapu-Lapu, Calderon, Legaspi** | Carbon precinct. |
| 13 | **Sanciangko, P. del Rosario, Junquera, Pelaez** | University belt. |

### 4.3 Which roads are iconic

Ranked by "a Cebuano would recognise it from one screenshot":

1. **Colon Street** — the oldest street in the Philippines. Recognisable purely
   from its signage canyon, not its geometry.
2. **Fuente Osmeña Circle** — the fountain rotunda. The city's landmark.
3. **Osmeña Boulevard** — the Capitol axis, the median, the descent.
4. **General Maxilom (Mango) Avenue** — neon, bars, the strip.
5. **Carbon's Plaridel / Lapu-Lapu** — stalls, umbrellas, tarpaulins, no visible
   road surface.
6. **Cardinal Rosales Avenue** — the manicured Ayala counterpoint. Its
   *cleanliness* is the recognisable thing, in deliberate contrast to Colon.

### 4.4 Which roads the player will travel most

This determines where sidewalks, markings, signals and traffic density get spent
first — those are the expensive per-metre features.

1. **Osmeña Boulevard** — the backbone. Any north–south trip uses it.
2. **Archbishop Reyes** — IT Park ↔ Ayala, the two highest-value destinations.
3. **Gov. M. Cuenco Avenue** — existing spawn; every session starts here.
4. **Gorordo / Escario** — the parallel alternates; traffic AI needs both or
   everything piles onto Osmeña.
5. **Gen. Maxilom** — the east–west connector between the Fuente and Ayala poles.

Full-detail treatment (medians, both sidewalks, markings, signals, crossings,
street lights) goes to these five plus Colon. Everything else gets carriageway +
single-side sidewalk until Phase 8.

---

## 5. District breakdown

Districts are a **production concept**, not just flavour: each one is a row in a
table that drives infill generator, height distribution, wall palette, prop
density, traffic density and NPC density. This generalises the existing
`SLUM_DISTRICTS` mechanism.

| District | Godot z | Visual identity | Landmarks | Traffic | Peds | Assets needed |
|---|---|---|---|---|---|---|
| **Banilad** (built) | −1170…−200 | Suburban commercial, low-rise, wide avenue | Gaisano Country Mall, UC Banilad | Med | Med | *Done* |
| **Cebu IT Park** | +200…+800 | Glass towers, plazas, wide clean streets, night market | Central Bloc, eBloc 1–4, Skyrise, TGU | Med | **High** | Tower kit, plaza paving, Sugbo Mercado tents |
| **Lahug / Camputhaw** | +700…+1400 | Mixed mid-rise, hotels, schools, sloped streets | Waterfront Hotel & Casino | Med | Med | Mid-rise kit, hotel forms |
| **Cebu Business Park** | +1400…+2000 | Manicured grid, planted medians, corporate towers, low density | Ayala Center, The Terraces, Ayala Triangle | **High** | **High** | Planted medians, palm/landscape props, tower kit |
| **Residential — Kamputhaw / Capitol** | +1900…+2400 | Walled compounds, 2–3 storey, mature trees | Cebu Country Club, Palace of Justice | Low | Low | Compound walls + gates (**new**), tree variety |
| **Fuente District** | +2400…+2900 | Dense mid-rise, hotels, hospitals, neon, the rotunda | Fuente Circle, Crown Regency, Chong Hua, Rajah Park | **Very high** | **Very high** | Roundabout generator, neon signage, hotel towers |
| **University Belt** | +2900…+3900 | 4–6 storey institutional slabs, jeepney chaos, sari-sari, students | USC Main, USJ-R, UC Main, Southwestern, Cebu Normal | **High** | **Very high** | Institutional slab kit, campus walls, jeepney density |
| **Downtown Colon** | +4000…+4500 | **Signage canyon.** 3–6 storey commercial perimeter blocks, tarpaulins, awnings, zero setback | Colon Obelisk, Gaisano Main, Metro Colon, Cebu Coliseum | **Very high** | **Extreme** | **Signage atlas**, awning bands, commercial perimeter-block infill |
| **Parian / Heritage** | +4200…+4500 | Colonial stone + wood, narrow lanes, churches | Basilica, Metropolitan Cathedral, Casa Gorordo, Yap-Sandiego, Heritage Monument | Med | High | **Heritage kit** (capiz windows, stone base, tile roof) |
| **Carbon Market** | +4500…+4750 | Tarpaulin, umbrella, crate, corrugated GI. **Road surface invisible.** | Carbon Units 1–3, Freedom Park, Pasil Fish Market | Low (impassable) | **Extreme** | **Stall generator** — a `build_slum.py`-scale project |
| **Port District** | +4400…+4800 | Warehouses, container stacks, cranes, ferry terminals, sea | Fort San Pedro, Plaza Independencia, Piers 1–4, Malacañang sa Sugbo | Med | Med | Warehouse kit, containers, cranes, **water plane + shoreline** |
| **Informal settlements** (built) | various | Eskinita, packed lots, GI roofs, graffiti | — | Low | High | *Done* — extend `build_slum.py` to Lorega, Pasil, Ermita |

**The Port district introduces sea water**, which the current map has no concept
of beyond small `natural=water` polygons at `Z_WATER = −0.60`. Once terrain
exists, sea level is the datum (y = 0) and the shoreline is where the DEM
crosses it. This is a clean fit and one of the arguments for doing terrain now.

---

## 6. Blender workflow

### 6.1 Scale — keep exactly as is

1 BU = 1 m, enforced by `prep_godot.py::verify_scale()`. Its hardcoded
assertion range (Ground span 2300–2700 m) must widen to the new extent, and it
should gain a per-tile check. **Do not adopt blender-osm or BlenderGIS.** They
would replace a pipeline that already produces better geometry than either, and
you would lose the two-pass junction clipping and the flat collision plane —
both of which were expensive to get right and are load-bearing for driving.

### 6.2 GIS / OpenStreetMap workflow

Unchanged in principle: Overpass → committed JSON → deterministic Blender build.
Changes: tiled fetch (§Phase 0), expanded tag set (§3.6), and per-tile caching so
re-pulling Carbon does not re-pull Banilad.

Keep committing the OSM extract. It is the reproducibility guarantee, and it
freezes the **circa-2019 era** decision — future Overpass pulls would silently
drag in the Carbon redevelopment and BRT works.

### 6.3 Terrain workflow — roads authoritative

Source: **Copernicus DEM GLO-30** (free, 30 m, global) via OpenTopography.
SRTM is noisier; NAMRIA's 5 m IfSAR is the gold standard but access-restricted.
30 m is coarse for street level, which is exactly why the naive approach fails.

**Do not drape roads over the DEM.** At 30 m posting, a road sampled directly
from the DEM ripples by ±1 m over its length — cars bounce, sidewalks kink, and
the road-collision plane stops being flat, which reintroduces the vehicle chatter
problem that was already solved once.

Instead, invert the relationship — the way real road engineering works:

1. **Sample** the DEM along each road centreline at 10 m intervals.
2. **Smooth longitudinally** — moving average over ~60 m, then clamp the
   resulting grade to a maximum (8% local, 6% arterial). This is now the road's
   *authoritative* height profile.
3. **Reconcile at junctions** — every way meeting at a node is forced to that
   node's height, then re-smoothed outward. Otherwise two roads meet at
   different elevations.
4. **Generate terrain from the roads** — build the ground mesh by interpolating
   between road-network heights (Delaunay over the road nodes), falling back to
   the smoothed DEM only far from any road. Roads are flat and level; terrain
   meets them cleanly; blocks between streets get plausible cross-slope.
5. **Buildings** sit on the terrain height sampled at their footprint centroid,
   with a **plinth** extruded down to the lowest corner so nothing floats on a
   slope. Cebu builds this way in reality.

Refactor cost inside `build_map.py`: every scalar `z` becomes a sampled height.
`ribbon(pts, width, z)` → `ribbon(pts, width, heights[])`. `layer_z(base, i)`
becomes an offset *above the local surface* rather than an absolute. `walls(ring,
0, height)` gains a base height. `Z_ROAD_COLLISION` stays a constant *offset*
from the road surface, preserving the single-coplanar-surface-per-road property
that stops the wheel chatter.

**Physics consequences to re-verify:** `cblock_player.gd`'s `max_step_height
0.45` and the `AGENT_MAX_SLOPE 20.0` navmesh setting both interact with real
grades. `vehicle_body.gd`'s suspension is tuned for gravity 18.0 on flat ground.
`curb_step_smoke_test.gd` and `vehicle_smoke_test.gd` need sloped-ground cases.

### 6.4 Modular road system

The ribbon system is already the right architecture. Additions:
- `median_ribbon()` — reuse `raised_ribbon()` with a planted-strip material.
- Corner radii in `miter_offsets()`.
- Junction fill quads, stop lines, zebras.
- Awning/signage band quads over commercial sidewalks (§6.5).
- **Tile-aware `MeshBatch`** — see §7.1. This is the biggest structural change.

### 6.5 Modular building workflow — three fidelity tiers

The project has produced **three** hand-authored landmarks so far (UC Banilad,
Gaisano Country Mall, Central Bloc). Fifty at that fidelity is not a plan, it is
a hazard. Tier the work:

| Tier | Method | Count | Per-unit effort |
|---|---|---|---|
| **S** | Bespoke Blender generator, like `build_mall.py` | 8 | Days |
| **A** | Kitbash from a modular parts library + signage decal + tuned height/material | ~23 | Hours |
| **B** | Existing procedural extrusion + per-name height/material override + name sign | ~19 | Minutes |

**The parts library is the deliverable that makes Tier A possible**: podium,
tower shaft, crown, arcade bay, institutional slab, capiz-window heritage bay,
warehouse bay, mall entrance bay. Several already exist inside `build_map.py`
(`tower_detail()`, `window_bands()`, `hip_roof()`, `parapet_roof()`) and inside
`build_mall.py` (arcades, clay roofs) — extract them into `banilad_map/parts.py`
rather than writing new ones.

**The single biggest new capability: a signage atlas.** The map currently has
**no textures and no UVs at all** — 76 flat-colour materials. Downtown Cebu is
*made of* signage: Colon is a wall of tarpaulins and painted shopfronts, Carbon
is umbrellas and hand-lettered boards. A flat-colour palette physically cannot
read as Colon, no matter how good the massing is.

This does not require full texturing. It requires:
- One 2048² atlas of Filipino shopfront signage, tarpaulins, jeepney livery and
  stall canvas.
- UV support in `MeshBatch.add()` (currently discards UVs entirely).
- Facade band quads at ground and first-floor level on commercial frontages,
  UV-mapped into the atlas by deterministic hash of OSM way id.

**This is the highest visual-return change in the entire plan** and it is scoped
to one atlas plus a UV channel — not a re-texture of the city.

---

## 7. Godot workflow

### 7.1 World streaming — 250 m tiles

The entire city is currently one un-partitioned GLB. At 6× area and higher
density that becomes roughly 1.2–1.8 M triangles in a ~55 MB single mesh, loaded
in one hitch, frustum-culled as a handful of giant multi-material objects.
It will not run.

**`MeshBatch` must become tile-aware.** Every `add()` routes the feature into
the batch for the 250 m tile containing its centroid; features spanning a
boundary are assigned by centroid (small overdraw at edges is fine and far
cheaper than clipping geometry). `prep_godot.py` exports one GLB per non-empty
tile: `assets/maps/tiles/r{row}c{col}.glb`.

Grid: 23 rows × 15 cols = 345 cells, of which perhaps 250 are non-empty.

**Why 250 m and not 500 m:** finer culling granularity in a downtown where the
player is on foot as often as driving; it matches Cebu Business Park's real block
size; and a 250 m tile is small enough to rebuild and inspect in isolation.

**Streaming design:**
- `TileStreamer` node, distance from camera on the XZ plane.
- Hysteresis: load at 400 m, unload at 520 m. Never load and unload on the same
  frame boundary.
- `ResourceLoader.load_threaded_request` — **reuse the pattern already working
  in `scripts/main_menu.gd:484`**, do not write a second threaded loader.
- Budget one tile instanced per frame maximum. Instantiation, not loading, is
  what causes the hitch.

**Two things must not be per-tile:**

1. **Road collision.** If the tile under a moving car is not resident, the car
   falls through the world. Road collision is flat ribbons with no materials and
   is cheap — load it at a **larger radius** (700 m) than visuals, and have the
   streamer guarantee the player's own tile is resident before releasing control.
2. **The skyline mesh.** One always-loaded low-detail mesh of building
   silhouettes only — no props, no markings, no windows, buildings above ~25 m
   only. This is how GTA has always done it. Without it, Crown Regency and the
   IT Park towers pop in at 400 m and the city has no legible skyline from Fuente
   or the port. Generate it in the same Blender pass; it is a second `MeshBatch`
   fed only by tall footprints.

### 7.2 LOD and culling on `gl_compatibility`

Locked decision: stay on Compatibility. That means `OccluderInstance3D` and
SDFGI are off the table. What *is* available and should be used:

- **`meshes/generate_lods=true`** — already on in the importer. Verify it is
  actually producing LODs on the batched meshes (large multi-material meshes
  sometimes decimate poorly; check per-tile after the split, which should
  *improve* this since tiles are smaller).
- **`visibility_range_begin` / `visibility_range_end`** — these are CPU-side per
  `GeometryInstance3D` and **do work in Compatibility**. This is the main
  manual LOD lever. Set per tile-category: props 120 m, markings 150 m,
  sidewalks 250 m, buildings 400 m, skyline ∞.
- **Fog** — the honest way to hide the streaming horizon. `banilad_city.tscn`
  currently has `fog_enabled = false`; `main.tscn` uses density 0.004. Downtown
  wants light haze at ~350–450 m, which is also atmospherically correct for
  Cebu.
- **Camera far** — currently 900 m. Bring it to ~550 m once fog and the skyline
  mesh are in.

### 7.3 Navigation

The current navmesh is 827 KB / 21,449 polys for 3.3 km², and **its bake volume
(`BAKE_ORIGIN` / `BAKE_SIZE`) already excludes IT Park at z ≈ +419** — a live
bug. Six times the area at downtown density would produce a 6–10 MB single
resource with a bake time in the tens of minutes.

**Bake per-tile navmeshes**, one `NavigationRegion3D` per streamed tile, linked
by Godot's edge-connection margin. This scales, parallelises, matches the
streaming lifetime, and structurally eliminates the "outside the bake volume"
class of bug. `bake_banilad_navmesh.gd` becomes a loop over tiles.

Also note: **`NavigationAgent3D` appears nowhere in the project.** The navmesh
currently has no consumer at all. Phase 7 is its first real use.

### 7.4 Traffic AI architecture

`VehicleBody3D` is a full physics sim. Thirty of them is a slideshow; the
citywide target is far more than thirty.

**Two-tier, exactly as GTA does it:**

| Tier | Range | Implementation | Budget |
|---|---|---|---|
| **Simulated** | Player's vehicle + ~4 nearest | Full `VehicleBody3D` (existing `vehicle_body.gd`, unchanged) | 5 |
| **Puppet** | Everything else visible | Kinematic. Transform driven along lane centrelines from the road graph. No physics, no wheels, no suspension. | ~25 visible |
| **Ambient** | Off-screen | Position on the graph only, no node at all. Recycled into puppets on approach. | ~80 citywide |

Promotion/demotion happens at a distance threshold, at rest, with velocity
carried across. Puppets follow lane centrelines
(`edge ± (lane − (lanes − 1) / 2) × lane_width`, both fields published per edge
by the graph), obey `oneway`, stop at `signal` nodes on red, and yield at
Fuente. Density is per
district from the table in §5 — Colon and Fuente saturated, Business Park
moderate, Carbon effectively zero because the road is full of stalls.

Jeepneys should follow **fixed named routes** along the graph rather than
wandering. Cebu's jeepney route codes (01K, 04L, 62B…) on the destination board
are a strong, cheap authenticity signal, and route-following traffic reads far
more like a real city than random walkers.

### 7.5 NPC spawning

Derive the pedestrian graph from the same road graph — sidewalk centrelines are
already `width/2 + 1.3 m` off each side, the exact offset `build_map.py` uses to
place the kerbs, so the walkable line is guaranteed to sit on the sidewalk mesh.
Crossings come from `highway=crossing` nodes.

- **Pool and recycle. Never allocate at runtime.** Pre-instance ~60 pedestrians,
  reposition them ahead of the player on the graph, retire behind.
- Per-district density (§5): Colon and Carbon extreme, University Belt extreme at
  daytime, Business Park high but tidy, residential low.
- `scripts/cblock_edward_npc.gd`'s waypoint walker is the existing template, but
  it lerps linearly with no navmesh and no avoidance. It needs `NavigationAgent3D`
  and RVO avoidance for crowd densities — this is the navmesh's first consumer.
- The existing `PoliceNpcProp` already has `play_walk()` installed but never
  called; wiring it is the cheapest path to a moving pedestrian.

---

## 8. Risk analysis

### Accuracy risks

| Risk | Severity | Mitigation |
|---|---|---|
| **OSM building coverage downtown is far thinner than reality.** Colon and Carbon have a fraction of their true footprints mapped. | **High** | Commercial perimeter-block infill (below). Do not assume OSM density scales with real density. |
| **The existing infill generator is a *shanty* generator.** A 13 m jittered lattice of small hip-roof houses is correct for Banilad and completely wrong for Colon's 5-storey zero-setback commercial blocks. | **High** | Write a second infill mode: perimeter-block, aligned to street frontage from the road graph, zero setback, 3–6 storeys, shared party walls. Select by district. |
| **`height` / `building:levels` almost never tagged in Cebu.** `DEFAULT_HEIGHTS` is doing all the work, as a per-type constant. | Med | Per-district height *distributions*, not per-type constants. Colon 3–6 storeys, Business Park 8–30, Carbon 1–2. |
| 30 m DEM is coarse for street-level grades | Med | Roads-authoritative solve (§6.3). Grade clamping. |
| Era drift — a future Overpass pull silently imports the Carbon redevelopment and BRT works | Med | Keep committing the extract. Freeze it. Document the circa-2019 decision at the top of `overpass_query.txt`. |
| Naming traps (Jones/Osmeña, the two Cuencos) | Low | §4.1. Name-alias table. |

### Asset bottlenecks

1. **Signage (§6.5).** The blocker for Colon, Carbon and the University Belt —
   three of the most iconic districts. No textures or UVs exist today.
2. **Carbon Market.** Not a building; a fabric. Realistically a
   `build_slum.py`-scale generator of its own: stalls, tarpaulin canopies,
   umbrellas, crates, produce. Budget it as a project, not a landmark.
3. **The Tier-S eight.** Fuente Circle, Basilica, Magellan's Cross, Fort San
   Pedro, Carbon, Colon corridor, Ayala Center, Capitol. Three landmarks got the
   project this far; this is a large multiple of all landmark work to date.
4. **The heritage kit.** Parian needs capiz windows, stone bases and tile roofs
   that nothing in the current palette can express.

### Performance risks

| Risk | Mitigation |
|---|---|
| No occlusion culling on `gl_compatibility`, in the one district type where it pays most | Tile streaming + `visibility_range_*` + fog + skyline mesh (§7.1–7.2) |
| Draw calls: 250 resident tiles × several material slots | Keep the per-category batching *within* each tile; do not split further |
| Navmesh bake time and size at 6× area | Per-tile baking (§7.3) |
| `VehicleBody3D` count | Two-tier puppet traffic (§7.4) |
| Streaming hitches | One tile instanced per frame; threaded load; hysteresis |
| **Car falls through an unloaded tile** | Road collision at a larger radius than visuals; block release-of-control until the player's tile is resident (§7.1) |
| Terrain invalidates gravity-18 physics tuning | Sloped-ground cases added to `curb_step_smoke_test.gd` and `vehicle_smoke_test.gd` |

### Scope risks

- **The corridor is not optional.** IT Park and Ayala are 1.4 km apart with
  Lahug between them. You cannot ship "IT Park + Ayala" without slice 1. The
  nine requested areas are one continuous city, not nine islands — this is
  already reflected in the slice order.
- **Phases 0, 2 and 4 produce nothing visible.** Consolidation, terrain and
  tiling are pure infrastructure. There will be pressure to skip them for
  landmarks. Skipping Phase 4 in particular means rebuilding every landmark
  later to fit tile boundaries.
- **Downtown is the hardest work and it is last.** That is correct sequencing
  (it depends on signage, terrain and commercial infill) but it means the most
  motivating district is furthest away. Slice 3 (Fuente) is the morale
  checkpoint — it is genuinely iconic and lands mid-project.
- **`mechanics_smoke_test.gd` is failing and hangs.** It is the only guard on
  `school_building.gd`, which Phase 5 moves into the real city. Fix in Phase 0.

---

## 9. Critical files

| File | Change |
|---|---|
| `banilad_map/overpass_query.txt` | New bbox `10.2890, 123.8860, 10.3410, 123.9190`; node/barrier/pier/historic/restriction tags; era note |
| `banilad_map/fetch_osm.py` | Tiled fetch with per-tile cache and merge |
| **`banilad_map/geo.py`** | **New.** Shared georeference. Fixes the 110540/110574 mismatch |
| **`banilad_map/districts.py`** | **New.** Single district table; absorbs `SLUM_DISTRICTS` |
| **`banilad_map/terrain.py`** | **New.** DEM ingest, road-authoritative height solve, terrain mesh |
| **`banilad_map/parts.py`** | **New.** Extracted from `build_map.py` + `build_mall.py` for Tier-A kitbash |
| `banilad_map/build_map.py` | Tile-aware `MeshBatch`; heights replace scalar z; road graph emit; medians; corner radii; commercial infill mode; UV/atlas; skyline batch |
| `banilad_map/prep_godot.py` | Per-tile GLB export; widen `verify_scale()`; landmark JSON gains tile ids |
| `banilad_map/build_mall.py`, `tools/build_slum.py`, `banilad_map/find_spawn.py` | Import from `geo.py` / `districts.py` |
| **`scripts/tile_streamer.gd`** | **New.** Distance streaming, hysteresis, threaded load, collision radius |
| **`scripts/road_graph.gd`** | **New.** Loads `cebu_road_graph.json`; lane/sidewalk queries |
| **`scripts/traffic_manager.gd`**, **`scripts/ped_manager.gd`** | **New.** Phases 6–7 |
| `scripts/banilad_city.gd` | Streamer wiring; spawn stays at `(12.79, 1.2, −554.24)`, now terrain-sampled |
| `scripts/tools/bake_banilad_navmesh.gd` | Per-tile bake loop; removes the IT Park volume bug |
| `scripts/mechanics_smoke_test.gd` | **Fix the failure**; convert `assert()` → `_check()`/`quit(1)` |

---

## 10. Verification

The project's convention is headless `SceneTree` scripts printing `<NAME>_OK` /
`<NAME>_FAIL` and exiting non-zero. Extend it; do not introduce a framework.

**Two known traps to respect:** bare `assert()` in a `SceneTree` test *hangs*
instead of failing — always use the `_failures` / `_check()` / `quit()` pattern
and always run under a timeout. And `class_name` silently resolves to a null
script in headless `--script` runs, so map scripts must `preload()`.

Existing tests to keep green: `banilad_smoke_test`, `slum_smoke_test`,
`curb_step_smoke_test`, `vehicle_smoke_test`, `third_person_smoke_test`,
`police_city_smoke_test`, `input_map_smoke_test`, `story_map_smoke_test`.

New guards, one per phase:

| Test | Asserts |
|---|---|
| `geo_consistency_test.py` | All four scripts project a known lat/lon to the same metre. Guards the 110540/110574 class of bug |
| `road_graph_smoke_test.gd` | Graph loads; every edge's endpoints exist; every node lies on the road collision mesh; signal count matches OSM; `Osmeña Boulevard` is present and continuous from Capitol to Plaza Independencia |
| `terrain_smoke_test.gd` | Ray down at 30 sample points hits ground within 0.5 m of the DEM-derived height; no road segment exceeds the grade clamp; junction heights agree across all incident ways within 5 cm |
| `tile_stream_smoke_test.gd` | Walk a scripted 3 km route; every frame the player's tile is resident; a downward ray always hits collision; peak resident tile count stays under budget; no frame instances more than one tile |
| `chatter_guard` (extend `banilad_smoke_test`) | The existing 5 cm two-surface check, re-run **on sloped ground** at junctions in slices 3–6 |
| `landmark_coverage_test.gd` | All 50 ranked landmarks present in `banilad_landmarks.json`, within 25 m of their surveyed position, correct tier |
| `traffic_smoke_test.gd` | 200 puppet ticks: no vehicle leaves its lane corridor, none enters a `oneway` backwards, all stop at red |

**End-to-end manual check** after each slice — the full rebuild is:

```bash
python banilad_map/fetch_osm.py
```

```bash
"C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P banilad_map/build_map.py
```

```bash
"C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P banilad_map/prep_godot.py
```

```bash
.tools/godot/Godot_v4.7-stable_win64.exe --headless --path . --import
```

Then drive the slice's spine road end to end and confirm: no chatter, no
fall-through, no pop-in inside 250 m, and the skyline reads from the far end of
the corridor. Read `prep_godot.py`'s verdict lines after every rebuild.

---

## Appendix A — Top 50 landmarks, ranked

Rank is **production priority** (recognition value × navigational usefulness ÷
cost), not size.

### Tier S — bespoke generator (1–8)

| # | Landmark | District | Note |
|---|---|---|---|
| 1 | **Fuente Osmeña Circle** | Fuente | The city's navigational anchor. Roundabout generator + fountain island |
| 2 | **Basilica Minore del Santo Niño** | Parian | Most photographed building in Cebu. Baroque facade, courtyard, pilgrim centre |
| 3 | **Magellan's Cross pavilion** | Parian | ~8 m octagon. Tiny cost, enormous recognition — best ratio in the list |
| 4 | **Carbon Market precinct** | Carbon | Units 1–3 + Freedom Park + Warwick Barracks. A generator, not a building |
| 5 | **Colon Street corridor** | Downtown | A 700 m signage canyon. Depends on the atlas |
| 6 | **Fort San Pedro** | Port | Triangular bastion fort. Procedural walls get ~70% of the way |
| 7 | **Ayala Center Cebu + The Terraces** | Business Park | ~250×200 m. High player dwell time |
| 8 | **Cebu Provincial Capitol** | Capitol | Neoclassical dome. Terminates the Osmeña Blvd axis |

### Tier A — kitbash (9–31)

| # | Landmark | District |
|---|---|---|
| 9 | Crown Regency Hotel & Towers | Fuente — tallest downtown, Sky Experience Adventure |
| 10 | Cebu Metropolitan Cathedral | Parian |
| 11 | Cebu City Hall | Downtown |
| 12 | Ayala Malls Central Bloc | IT Park — **built** |
| 13 | eBloc Towers 1–4 | IT Park |
| 14 | Skyrise 3 / 4A / 4B | IT Park |
| 15 | TGU Tower | IT Park |
| 16 | Park Centrale / Calyx Centre | IT Park |
| 17 | Waterfront Cebu City Hotel & Casino | Lahug — domed skyline anchor |
| 18 | University of San Carlos, Main | University Belt |
| 19 | University of Cebu, Main (Sanciangko) | University Belt |
| 20 | University of San Jose–Recoletos | University Belt |
| 21 | Southwestern University | University Belt |
| 22 | Cebu Normal University | University Belt |
| 23 | Chong Hua Hospital | Fuente |
| 24 | Cebu Doctors' University Hospital | Osmeña Blvd |
| 25 | Perpetual Succour Hospital | Gorordo |
| 26 | Vicente Sotto Memorial Medical Center | B. Rodriguez |
| 27 | Robinsons Galleria Cebu | Gen. Maxilom |
| 28 | Elizabeth Mall (E-Mall) | N. Bacalso |
| 29 | Gaisano Main | Colon |
| 30 | Metro Colon | Colon |
| 31 | Cebu City Sports Center / Abellana | Capitol |

### Tier B — procedural + overrides (32–50)

| # | Landmark | District |
|---|---|---|
| 32 | Malacañang sa Sugbo (Pier 1) | Port |
| 33 | Plaza Independencia | Port |
| 34 | Cebu Port Baseport, Piers 1–4 | Port |
| 35 | Casa Gorordo Museum | Parian |
| 36 | Yap-Sandiego Ancestral House | Parian |
| 37 | Heritage of Cebu Monument | Parian |
| 38 | Colon Obelisk | Colon |
| 39 | Cebu Coliseum | Leon Kilat |
| 40 | Freedom Park | Carbon |
| 41 | Pasil Fish Market | Port |
| 42 | Rizal Memorial Library & Museum | Osmeña Blvd |
| 43 | Redemptorist Church | Queen's Road |
| 44 | Sto. Rosario Church | University Belt |
| 45 | Cebu Country Club | Business Park edge |
| 46 | Ayala Triangle Gardens | Business Park |
| 47 | Asiatown IT Park gate | IT Park |
| 48 | Sugbo Mercado (night market tents) | IT Park — evening only |
| 49 | Rajah Park Hotel | Fuente |
| 50 | Palace of Justice | Capitol |

Already built and outside this ranking: Gaisano Country Mall, UC Banilad Campus.

---

## Appendix B — Rejected alternatives, and why

| Considered | Rejected because |
|---|---|
| Move `LAT0/LON0` to the new bbox centre | Invalidates hundreds of hand-tuned positions for zero benefit. Float32 at 6 km is ~0.5 mm |
| blender-osm / BlenderGIS addon | Would lose the two-pass junction clipping and the flat collision plane, both load-bearing for driving |
| 500 m tiles | Too coarse for on-foot downtown play; poor culling granularity in the densest districts |
| Drape roads directly over the DEM | ±1 m ripple at 30 m posting reintroduces the wheel-chatter problem that was already solved |
| Bake one navmesh for the whole city | 6–10 MB, tens of minutes, and preserves the "outside the bake volume" bug class |
| `VehicleBody3D` for all traffic | Physics cost is prohibitive above ~5 instances |
| Full texturing of the city | Unnecessary. One signage atlas + UVs on facade bands captures nearly all of the visual return |
