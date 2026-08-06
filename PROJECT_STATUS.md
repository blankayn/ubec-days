# Project status & pivot plan

Self-contained handoff. Read this first in a new session — it replaces the
chat history it was written from.

**Repo:** `C:\Users\Ariel\Documents\New project` · branch `master` ·
first commit `4148d22` (676 files tracked, clean tree).

---

## 1. What this project is

Godot 4.7 game set on a **real OSM-derived map of Cebu City** — the Gov. M.
Cuenco Avenue corridor in Banilad, extending south-west across **Cebu IT Park**.

It is branded *"UBEC - Days"*. It began as a first-person school-horror game;
**horror was removed in Milestone 3** and it is being pivoted into a GTA-style
open-world crime sandbox.

### Three maps exist

| Scene | Script | What it is |
|---|---|---|
| `main.tscn` | `world.gd` (1163 L) | UBEC story map: 3 placeholder chapters. First-person `player.gd`. Horror-free. |
| `cblock_map.tscn` | `cblock_map.gd` | Procedural 156×116 m sandbox district. Third-person. Horror-free. |
| **`banilad_city.tscn`** | `banilad_city.gd` | **The real Cebu map — the pivot target.** Third-person. Horror-free. |

`banilad_city.tscn` loads `assets/maps/banilad_map.glb` under a
`NavigationRegion3D`, spawns the player on Cuenco Ave at
`Vector3(12.79, 1.2, -554.24)`, and shows a proximity landmark HUD from
`assets/maps/banilad_landmarks.json` (110 landmarks, 19 flagged `key`).

---

## 2. The map pipeline

Everything in `banilad_map/`. Three headless steps:

```bash
python banilad_map/fetch_osm.py
```

```bash
"C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P banilad_map/build_map.py
```

```bash
"C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P banilad_map/prep_godot.py
```

Then re-import into Godot (otherwise the game runs the *old* map):

```bash
.tools/godot/Godot_v4.7-stable_win64.exe --headless --path . --import
```

- `fetch_osm.py` — only needed when the bbox in `overpass_query.txt` changes.
- `build_map.py` — projects OSM to metres, builds roads/landuse/buildings/
  infill/props, writes `banilad_map.blend` + GLB. The ~2276 infill houses now
  mix `shed_roof()` (58%) with `hip_roof()`, draw wall and roof colours from
  the palettes at *random* rather than indexing them by `placed` (which walked
  in lockstep with the lattice and banded whole blocks one colour), and use two
  size classes so most filler is small single-storey stock.

### Vertex colour (the look pass)

Every batch carries an optional per-vertex colour, written into a Blender
`FLOAT_COLOR` attribute named `Col` and exported as glTF `COLOR_0`. It drives
the per-building tint, the grime that darkens each wall toward its base, and
the ground/landuse mottling. Three things about it are load-bearing and easy to
break:

1. **The materials must reference the attribute.** `wire_vertex_tint()` puts a
   Color Attribute node through a multiply into Base Color. Without that wiring
   Blender's exporter writes a *white dummy* `COLOR_0` and dumps the real values
   into `COLOR_1`, which Godot ignores — the tint silently does nothing, and
   nothing anywhere reports an error.
2. **Base Color's own `default_value` is dead.** The authored constant now lives
   on the multiply node's A socket. `prep_godot.py::check_palette()` reads it
   from there and also verifies the wiring, so a broken tint chain fails loudly
   instead of passing vacuously.
3. **Godot needs `vertex_color_use_as_albedo` set.** Its glTF importer sets this
   for most materials but *not all* — on the current map it flags 38 of the 39
   that carry colour and misses `Ground`, the largest surface in the world.
   `scripts/vertex_albedo.gd` closes that gap at load, for the base scene and
   for each streamed tile. It normally reports **1**; that number is the size of
   the importer's blind spot, not the size of the job.

Meshes that write no colour cost nothing — the exporter omits `COLOR_0` for
them, and an unwired mesh reads as white through the wired materials rather
than black (verified; the opposite would have turned every prop and road
black).

### Districts

`districts.py` now holds `CITY_DISTRICTS` alongside the slum rectangles — the
table from `CITY_MASTER_PLAN.md` §5, as bands in Blender y (the negation of the
plan's Godot z). Each row drives wall/roof palette, tint spread, prop density
and shopfront rate, which is what stops Ayala, Colon and Banilad sharing one
look. Rows are checked in order, so a district bounded in x must be listed
before a wider one it sits inside — Parian is inside Colon's y range and
swallows it otherwise.

The old global `WALL_LOW` and `ROOF_PITCHED` lists in `build_map.py` are gone:
`DEFAULT_DISTRICT` carries exactly their contents and weighting, so
unclassified ground is unchanged, and there is again only one copy of the list.
`WALL_MID` stays, because the district `walls` are chosen for one- to
three-storey stock and a 20 m slab in painted hollow block reads wrong;
districts whose identity turns on their mid-rise give an explicit `walls_mid`.

**The infill houses go through all of this too.** They are a separate generator
(`place_infill_housing`) and were originally missed — no tint, no windows, no
shopfronts, and the global palettes rather than the district's. They now get
each of those, on a smaller window course than the OSM low-rise, because 55% of
infill is 2.4–3.6 m single-storey and the shophouse numbers clear no floors at
all on a 2.4 m wall. Their tint is seeded off the quantised lattice POSITION
rather than a placement counter: a counter walks in lockstep with the lattice,
which is the same correlation that banded the palettes into stripes before.
The informal-settlement districts are a **fourth, separate step**, only needed
when the slum changes (it does not depend on OSM being re-fetched):

```bash
"C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P tools/build_slum.py
```

- `tools/build_slum.py` — builds **five** dense Cebu-style barangays from the
  modular house kit at
  `C:/Users/Ariel/Downloads/house-pack-assets/source/house pack.blend`: winding
  eskinita alleys, packed lots, generated corrugated GI roofs and generated
  spray-tag decals. Writes `assets/buildings/banilad_slum.glb`,
  `assets/buildings/banilad_slum_graffiti.png` and
  `assets/maps/banilad_slum_alleys.json`.
  It is **not** baked into the map GLB; `banilad_city.gd::_place_slum()` instances
  it at the origin, the same absolute-coordinates contract the mall uses.
  `build_map.py` keeps `SLUM_DISTRICTS` free of procedural infill, trees and
  poles — **`DISTRICTS` there and `SLUM_DISTRICTS` in `build_map.py` are the
  same five rects duplicated; change one and you must change the other.**
  Vehicles are deliberately *not* excluded: a road runs through Kamagayan and
  Lorega, houses keep 7 m off carriageways, so traffic through a barangay is
  correct rather than a bug.

- `prep_godot.py` — verifies real-world scale, tags collision meshes with
  `-col`, exports `assets/maps/banilad_map.glb` + `banilad_landmarks.json`.
  **Read its verdict lines after every rebuild.**

Previews (one Blender process per shot — a single process crashes partway):

```bash
python banilad_map/render_all.py
```

**Derived artifacts are gitignored** (`banilad_map/*.blend`, `*.blend1`,
`banilad_map/export/`, `captures/`). Source of truth is `build_map.py` +
`banilad_osm.json`. The runtime GLB, landmarks JSON and navmesh **are** tracked,
so a fresh clone runs.

### Key geometry facts

- Local origin `LAT0=10.3345, LON0=123.9115`, now shared from
  `banilad_map/geo.py` — do not redeclare it (`geo_consistency_test.py` fails
  the build if you do).
- The ground plane is **derived from the data** by `ground_half_extent()`, not
  hardcoded. It was `GROUND_HALF = 1250`, which had fallen ~600 m behind the
  map and left roads hanging over void; `prep_godot.py` now asserts the ground
  covers everything built on it.
- **The extent is COMPLETE.** All six slices, bbox
  `10.2890 123.8860 10.3410 123.9190`, **20.78 km²** — Banilad, IT Park,
  Lahug, Business Park + Ayala, Escario/Capitol/Fuente, Osmeña Blvd +
  University Belt, Colon/Parian, and Carbon + the Port.
- `assets/maps/cebu_road_graph.json` is the routable network (9426 nodes,
  11770 edges, 425 named streets, 116 signals, 561 crossings, Fuente Osmeña
  Circle as 12 roundabout edges) that Phases 6–7 drive traffic and pedestrians
  along.
- **Rebuilding after an extent change is a THREE-step sequence**, not two:
  `build_map.py` → `fetch_elevation.py` → `build_map.py` → `prep_godot.py`.
  The graph must exist before elevation can be sampled for its new nodes, and
  new nodes built before sampling do not fail — `PointField.nearest` widens its
  search until it finds *something*, so they silently inherit heights from
  kilometres inland. Skipping the second build cost 143 spurious grade
  corrections on the Port.
- **Do not chain two Blender invocations in one shell command.** It exits 4
  partway with no traceback; run them as separate commands.
- **Terrain (Phase 2) is half landed.** `banilad_map/elevation.json` holds
  11,615 real SRTM 30 m samples (`fetch_elevation.py`, no API key needed), and
  `banilad_map/terrain.py` solves them onto the road graph: DEM sample per
  node → smooth across the graph → clamp grade → each edge is a straight ramp
  between its node heights. Junction reconciliation is free because a junction
  *is* one node. `build_map.py` runs the solve inline, so node `y` now carries
  real heights (−0.4 … 165.7 m) instead of the flat 0.13 placeholder.
  - Measured: Fuente 32.9 m, Colon 11.4 m, Osmeña Boulevard drops 22.8 m over
    2,476 m. Smoothing moves a node 0.59 m on average; only 0.9% move more
    than 5 m, and those are hill roads where the grade clamp bites.
  - **The geometry is draped too.** Ground is a 102 × 102 interpolated grid
    spanning −2.7 … 646.3 m (that ceiling is the Busay hills behind the city).
    Roads, sidewalks, markings, landuse and water go through `drape()`, which
    ADDS terrain height to each vertex so kerbs stay 0.15 m proud and the
    layer_z stagger survives. Buildings deliberately do NOT drape — that would
    tilt a roof down the hill — they take a base height plus a plinth to the
    lowest corner.
  - **Known open: junction overlap.** Two carriageways crossing are draped from
    the same field at different tessellations, so their collision surfaces sit
    5–46 mm apart. Tessellating the collision mesh to 4 m was tried and
    reverted: it only reached 19 mm and grew a never-unloaded mesh from 66k to
    251k triangles (3.5 → 14 MB). The fix is junction fill quads, see
    `CITY_MASTER_PLAN.md` §3.2. `banilad_smoke_test`'s chatter guard now counts
    surfaces in the band rather than measuring pairwise gaps, because on
    terrain a gap no longer distinguishes the artifact from a real overlap.
  - **Walking on gradients is verified.** `scripts/tools/slope_smoke_test.gd`
    locates the steepest drivable edges from the road graph (spread 400 m apart
    so they are not all one hillside) and walks the real map. Measured on
    10.8–13.7% grades: 87% of walk speed, grounded 81–100% of frames, capsule
    seated 0.92 m above the surface. `max_step_height 0.45` does not snag on
    the terrain tessellation.
  - **Driving on gradients is still unverified.** `vehicle_smoke_test` builds a
    synthetic *flat* scene, so suspension tuned for gravity 18.0 has never met
    a slope. The navmesh is also stale — baked from flat geometry, now invalid
    against its own 20° limit, though nothing consumes it yet.
- **Monuments: one gap closed, one still open.**
  - `node["historic"]` is now in the query and brings 47 monuments that were
    never fetched before: the Cross of Magellan, Fort of San Pedro, the
    Legazpi Monument, the Veterans Memorial, Plaza Independencia's cannons.
  - Magellan's Cross had been blamed on that gap. **That diagnosis was wrong.**
    The thing that renders it is `way 94081127 "Magellan's Cross Pavilion"`,
    which carries `building=yes` and would always have been drawn — it sat at
    Godot z +4526, i.e. 37 m south of slice 5's boundary. It was an extent
    problem, not a query problem, and slice 6 fixed it by arriving.
  - **Still open:** `build_map.py` only extrudes ways tagged `building`, so
    historic ways without one (Colon Obelisk, Rajah Humabon Monument) and all
    47 historic *nodes* are fetched and then silently dropped. Rendering them
    is Phase 5 landmark work.
- **`EXCLUDED_ROAD_CLASSES` in `build_map.py` enforces the circa-2019 era.**
  It currently drops `highway=busway` — 14 ways named "Cebu Bus Rapid Transit"
  running ~2.5 km down the Osmeña corridor. Left in, `busway` falls through
  `ROAD_WIDTHS` to the 5 m default and lays a phantom *collidable* lane along
  the boulevard. Carbon Market is the other era-sensitive site, still to come.
- **Verify a street's OSM name before writing an override for it.** Escario is
  `N. Escario Street`, Jones Avenue only exists as `old_name` on Osmeña
  Boulevard, and `M.J. Cuenco Avenue` has no space after the `M.`. See
  `CITY_MASTER_PLAN.md` §4.1.
- **The map is streamed.** `banilad_city.tscn` loads
  `assets/maps/banilad_base.glb` (ground, the flat road-collision plane, the
  skyline silhouette — 0.5 MB, never unloaded) and `scripts/tile_streamer.gd`
  streams 364 × 250 m tiles from `assets/maps/tiles/` using
  `assets/maps/tiles.json`. Peak ~21 tiles resident of 43 MB total — and that
  peak never moved across six slices while the map grew from 4.88 to 20.78 km²
  and tiles from 114 to 364. The never-unloaded base went 3.47 → 3.76 MB over
  the same 4.3x growth. That is the whole point: resident cost tracks view
  radius, not map size.
  `banilad_map.glb` is still written but nothing loads it.
  - Ground and road collision are deliberately **not** tiled, which is what
    makes "car falls through an unloaded tile" impossible rather than a race.
  - `prep_godot.py::category_of()` strips the `__rXcY` suffix before any
    category lookup. Without it `Roads_Major__r-3c-6` falls out of `NO_COLLIDE`
    and the layered visual ribbons get collision again, which is exactly the
    wheel-chatter `Roads_Collision` exists to prevent.
- Landmark identity is the `osm` way id, **not** `name` — Blender suffixes
  duplicates `.001`/`.002` in creation order, so names re-point whenever the
  bbox moves.
- Blender `(x, y)` → Godot `(x, 0, -y)`.
- Gov. M. Cuenco Ave runs at bearing **80.7°** (Blender XY). Mall is **west**
  of it, UC is **east**. (The README's "UC south / Gaisano north" is wrong.)
- Banilad is at negative Godot Z; **IT Park is at positive Godot Z (~+419)**.

| Landmark | Godot position | roof | footprint |
|---|---|---|---|
| UC Banilad Campus | `(51.11, 0, -449.14)` | 41.1 m | 72.3 × 75.7 |
| Gaisano Country Mall | `(-87.35, 0, -519.4)` | 16.4 m | 182.8 × 193.4 |
| Ayala Malls Central Bloc | `(-461.86, 0, 419.09)` | 74.2 m | 195.1 × 184.2 |

---

## 3. What was built recently (all committed)

**Three hand-authored landmarks** in `build_map.py`; everything else procedural.

- **`build_uc_banilad`** — ten-level ring around a real open courtyard, bowed
  glass curtain wall on the avenue, per-floor banding, roof plant, entrance
  podium. OSM stores UC as two overlapping C-shaped ways; the naive extruder
  filled them solid and erased the courtyard.
- **`build_country_mall`** — driven from **9 surveyed OSM footprints** (one
  named way + 8 unnamed arcade strips). Arcaded wings, clay roofs, 205 parking
  bays, and the real covered walkway (`93839864`, runs *east* to the avenue).
- **`build_central_bloc`** — Ayala Malls podium with signage band and 70-unit
  plant deck, two corporate towers, Seda Hotel.

**IT Park** — the Overpass bbox was slicing its southern third off. Re-pulled
wider: 174 → **301 buildings** (Cebu Exchange, The Link, i2/i3, TGU, Mabuhay,
Metro Sports). Every building over `TOWER_MIN_HEIGHT` (26 m) gets a podium base,
curtain walling, crown band and rooftop plant — 49 towers.

**Palette** — retuned from map-key colours to measured reference values:
barangay roofs are ~half faded galvanised / half oxidised red (not bright
terracotta); low-rise walls grey and weathered; towers use `TOWER_SCHEMES`
pairing each cladding with a contrasting glazing so IT Park reads white/pale
concrete with charcoal glass, **no saturated blue**.

### Bugs found and fixed

1. **`offset_polyline` sign is inverted from intuition** — for a
   counter-clockwise ring, a *negative* distance **grows** it. The UC courtyard
   was being built 13.5 m *outside* the building.
2. **`parapet_roof` passed `-inset`**, so every flat roof in the map overhung
   its own walls instead of stepping in.
3. **Ring offsets left one corner wrong.** `offset_polyline` works on an *open*
   polyline, so the `ring + [ring[0]]` trick gave the seam vertex a plain
   perpendicular offset instead of a corner mitre — one corner of *every* ring
   was misplaced. Fixed by adding **`offset_ring`** (cyclic mitre), now used by
   `parapet_roof`, `band_ring` and `shallow_hip`.
4. **A recessed facade band is invisible** — it sits inside the solid wall.
   Bands must stand slightly *proud*, as `window_bands` already did via `bulge`.
5. **`hip_roof` builds over the bounding rectangle**, so L-shaped mall wings got
   roofs that swallowed the car park. Added **`shallow_hip`**, which follows the
   true outline.

---

## 4. Current state

Working and verified:

- Map builds clean: **840 buildings, 153,419 verts / 170,567 tris**, 76
  materials verified, GLB **8.66 MB**, 110 landmarks (19 key). (Up from
  143,477 / 162,875 / 8.39 MB — the difference is the 2a collision mesh.)
- Godot re-imports cleanly; `banilad_city.tscn` instances the GLB as `Level`.
- Menu entry **"BANILAD · Real Street Map"** (`main_menu.gd:153`) loads it.
- All 10 previews current.

### Known open issues

- **Navmesh does not cover IT Park.** `scripts/tools/bake_banilad_navmesh.gd`
  bakes `origin(-450,-6,-880) size(900,10,760)` → Godot x −450…450, z −880…−120.
  **IT Park at z ≈ +419 is entirely outside it.** Re-baked against the current
  map and the slum (21 449 polys), so it is no longer stale, but nothing
  consumes it yet (`NavigationAgent3D` appears nowhere). Note the bake has to
  instance `banilad_slum.glb` explicitly — the slum is not in the map GLB, and
  without it the navmesh lays walkable floor through 168 houses.
- **21 named IT Park buildings have no OSM height** and use type defaults.
  Central Bloc was overridden from a night aerial (the only non-OSM heights in
  the file); the rest would need references or upstream OSM tags.

---

## 5. Pivot plan

Owner's decisions: **GTA-style crime sandbox** · horror removed · UBEC's
`SchoolBuilding` and `MallBuilding` **replace** the UC and C-Mall blocks in the
real map and are **enterable** · interiors **seamless, no loading screens** ·
driving is **physics-sim** (`VehicleBody3D`) · **vehicles first**.

### ✅ Step 0 — Version control — DONE
First commit `4148d22`. Commit at the end of each milestone.

### ✅ Milestone 1 — Foundations — DONE
- **1a. InputMap — done.** 20 actions with keyboard, mouse and gamepad
  bindings. `scripts/tools/setup_input_map.gd` is the **source of truth**: edit
  its action table and re-run it, never hand-edit the `[input]` block. Both
  free-roam maps and `cblock_player.gd` now read actions; `player.gd` and
  `main_menu.gd` still use keycodes and are left alone.
  - Two engine details that cost time: **key/mouse events carry a device tag**
    (`16` keyboard, `32` mouse) and `InputMap` compares device IDs, so events
    built with `device = 0` match nothing — the engine's own `ui_*` actions use
    the same tags. Pad events must be written with **`device = -1`**
    (any device) or only controller #1 works.
- **1b. Interaction in third person — done.** `cblock_player.gd` gained a
  `prompt_changed` signal, a camera-aimed probe (`_probe_interactable`) and
  `_try_interact`. The ray reaches `camera→player distance + INTERACT_RANGE`
  so the orbit camera's distance does not eat the player's 3 m of reach.
  `interactable.gd` is untouched; targets are matched by duck-typing.
  The prompt names its key by reading it back out of the InputMap, so a rebind
  cannot leave the HUD lying. Both maps show it on a new `HUD/Interact` label.
  **Melee still resolves against nothing** — deliberately left for Milestone 6.
- **1c. UI-lock mismatch — done.** `cblock_player.gd` now answers to
  `set_ui_locked()` / `is_ui_locked()` as well as `set_controls_enabled()`.
- **1d. Pause menu — done.** `scripts/pause_menu.gd`, built in code and
  instanced by both maps. `PROCESS_MODE_ALWAYS` (not `WHEN_PAUSED`, which would
  stop it seeing the key that opens it). Controls list is generated from the
  InputMap. It sits below the map root so it sees input first — the CBlock
  character picker calls `set_pause_blocked(true)` to claim Esc while up.

**Watch out:** a `class_name` reference fails to parse in a headless
`--script` run, because the global class cache is not built yet — the scene
then instantiates with a **null script and the smoke test still passes**. Map
scripts therefore `preload()` the pause menu instead. `banilad_smoke_test.gd`
now asserts the root script attached.

### Milestone 2 — Drivable vehicles
- **✅ 2a. Road collision — DONE.** `build_map.py` now emits `Roads_Collision`,
  one flat mesh at `Z_ROAD_COLLISION` (= `Z_ROAD_MAJOR`, 0.13) built from the
  1125 non-footway entries in `road_lines`. `prep_godot.py` exports it as
  **`-colonly`** (Godot drops the mesh, keeps the shape, so it never renders)
  and moves `Roads_Major`, `Roads_Minor` and `Footways` into `NO_COLLIDE`.
  - Measured, not assumed. Sweeping a 160 × 400 m window of the corridor for
    points with two collision surfaces within 5 cm — the gap a wheel ray flips
    between — gives **294 before, 42 after**. `(28, -682)` presented two
    surfaces **2 mm** apart (exactly the `layer_z` stagger); `(40, -696)` had
    three inside 4.6 cm. Both are now a single plane.
  - Cost: +9,942 tris, GLB 8.39 → 8.66 MB. Player rest height dropped
    1.06 → 1.03 (it used to stand on the topmost stacked ribbon).
- **✅ 2a-2. Junction clipping — DONE** (found by driving it; the remaining 42
  chatter points were the visible half of a worse bug).
  - Sidewalks and lane markings were generated along each way's **whole
    length**, so at every junction they carried straight over the crossing
    road. For a sidewalk that is a **kerbed slab lying across the
    carriageway** — a 0.15 m step the car hits, not just something that looks
    wrong. It was plainly visible from the driver's seat.
  - `clip_against_carriageways()` in `build_map.py` breaks a polyline wherever
    it enters another road's tarmac, using a `SpatialIndex` of every
    non-footway centreline built in a new first pass. `margin` is how far the
    feature reaches either side of the line being tested, so a sidewalk clears
    the road by its own half-width instead of stopping with half of itself
    still over it. Runs under 2.5 m are dropped as slivers, and an uncrossed
    line is handed back with its original vertices rather than a resampled
    copy.
  - **199 sidewalk lines broken at junctions**; geometry *fell* 170,567 →
    165,299 tris. Chatter points in the survey window went **42 → 0**: the
    sidewalk overlaps were the last source, so this closed 2a's open issue as
    a side effect rather than needing a separate `Sidewalks_Collision`.
  - 15 points in the window still have a kerb over the drive plane (0.09% of
    samples), where a sidewalk runs alongside a road just inside the margin.
    Not visible while driving; left alone.
- **✅ 2b. Drivable vehicle — DONE.** `scripts/vehicle_body.gd` builds a
  `VehicleBody3D` + 4 `VehicleWheel3D` on the existing `assets/psx-vehicles`
  models. Wheel positions come from the **measured** GLB bounds (cars
  4.96 × 1.98 × 2.46, jeepneys 6.32 × 2.72 × 2.72, both on y = 0) — the box
  dims quoted in `street_vehicle_prop.gd` are a deliberately smaller
  player-safe hull, not the model. AWD: rear-drive spins out on kerbed OSM
  geometry.
  - **Suspension must be sized for this project's 18 m/s² gravity**, not the
    9.8 Godot's defaults assume. Godot's spring force is proportional to
    `stiffness × compression × mass`, so holding the car up needs a compression
    of `gravity / (4 × stiffness)`. At 9.8-era stiffness both vehicles bottomed
    out — the car rested **0.159 m into the road** — and lost most of their
    traction with it. 64 (car) / 56 (jeepney) settle within 4 and 9 cm of the
    height their baked wheels are drawn at.
  - ⚠️ **A positive `engine_force` accelerates a `VehicleBody3D` toward +Z**,
    the opposite of the −Z forward convention every other node uses. Godot
    builds each wheel's drive axis as `axle × direction` = +Z and never flips
    it; verified on a bare `VehicleBody3D` with no script (+900 → **+15.67 m in
    Z**). The first version assumed −Z, so its own "rolling backwards" branch
    braked the car it was accelerating and it crawled 1.5 m at 2 km/h.
    `ENGINE_FORCE_SIGN` negates the throttle instead of inverting the node, so
    the nose stays at −Z for the chase camera. **The steering sign is not
    inverted** — it was asserted, not assumed.
- **✅ 2c. Enter / exit — DONE.** Parked cars are picked up by the 1b probe by
  duck-typing (`get_interaction_prompt` / `interact`), so they needed
  `collision_layer = 1 | 4` to be visible to a mask-1 ray. `E` hands over:
  `cblock_player.set_stowed(true)` hides the body, disables its collision and
  **stops it writing to the camera rig** (`set_camera_enabled`), and the car
  takes the same `CameraRig`/`SpringArm3D` for a chase camera that lerps behind
  the nose. `E` again gets out beside the driver's door. Three vehicles park on
  Cuenco Ave near the spawn.
  - No entry/exit animations exist, so it snaps. Mouse-orbit while driving is
    not wired — the chase camera is locked behind the car.

### ✅ Milestone 3 — Remove horror and rebrand — DONE
The estimate held: **no `.tscn` referenced any horror script**, it was all
runtime-instantiated from `world.gd`, so nothing had to be re-authored by hand.

- **Deleted:** `scare_manager.gd` (521 L), `horror_creature_prop.gd` (242 L),
  `hide_spot.gd` (46 L), `vhs_system.gd` (128 L), `assets/psx-horror-creature/`.
- **Deleted as dead code:** `world.gd`'s unreachable `_build_interior` /
  `_start_flicker` tail (192 L, the planned `:1375-1566`) and the equally
  unreachable `_build_commercial_center` (40 L), which carried the old
  "UCB INDAY" facade sign.
- **Stripped:** `world.gd` 1566 → 1163 L, `story_manager.gd` 400 → 336 L,
  `player.gd` 440 → 372 L, `hud.gd` 171 → 142 L, `survival_door.gd` 178 → 102 L.
- **Rebranded to "UBEC - Days"**: `project.godot` name, `main.tscn` root node,
  menu title/subtitle, loading and boot overlay copy, HUD objective header,
  chapter 3's title, and the `"inday"` / `"ucb"` chapter-select passwords (now
  `1994` or `ubec`). `main_menu.gd` had already lost its horror button; the two
  remaining `horror_playthrough` writes went with the static itself.
- **Kept, as planned:** `phone_ui.gd`, the day/night lighting presets, the
  quest-marker glow, and the chapter/objective/SMS framework — the three
  chapters now carry neutral placeholder copy for Milestone 6 to replace.
- **Reversed:** the three named NPCs (Edward, Mulet, Jholo) are out of
  `_day_only_nodes` and **stay in the world at night**.
- Guarded by `scripts/tools/story_map_smoke_test.gd` (see §5 tests).

Two judgement calls worth knowing:
- **`survival_door.gd` was stripped, not deleted.** It was not on the delete
  list, but 76 of its 178 lines were the creature chase — `creature_arrived()`,
  the BANG escalation, the BARRICADABLE / BARRICADED / BROKEN states. Kept: the
  keyed lock, open/close, and `set_chapter_access`. Only the keyed faculty door
  is placed now; the barricadable classroom door is gone.
- **Flashlight and battery stayed** (owner's call), so `hud.gd` keeps its
  battery panel and `world.gd` keeps the six battery pickups. What went was the
  noise system end to end — the player's `noise_emitted`, the HUD noise
  indicator, and the door noise — since its only consumer was the creature's
  hearing.

Left behind on purpose: `_character_part`, `_low_poly_sphere` and `_shop_color`
in `world.gd` are now unreferenced but neutral, and `phone_ui.set_no_signal()`
lost its only caller (chapter 3's no-signal beat) but `phone_ui.gd` was on the
keep list and is untouched.

### Milestone 4 — UC + mall interiors in the city
- **4a.** Suppress the GLB shells via `LANDMARK_WAY_IDS` in `build_map.py`
  (drop `UC_WAY_IDS` and `MALL_WINGS`); keep car park, walkway, parcel.
- **4b.** Instantiate `SchoolBuilding` / `MallBuilding` in `banilad_city.gd`
  (both have `build()` / `build_async()`; `world.gd:529` shows the pattern) at
  the coordinates in §2. Both are **smaller than their sites** (school
  52×31.5 vs 72×76; mall 60×26 vs 183×193) — accepted, enterable beats exact.
  Their dimensions are hardcoded `const`, not exported. Rotation ≈
  `deg_to_rad(-7.8)`; add `PI` if the facade faces away — verify visually.
- **4c. Seamless-interior performance** (heaviest option, chosen against
  advice): per-floor `visible` toggling by player Y using the existing
  `LEVEL_ELEVATIONS` / `level_y()`, disable hidden floors' collision,
  `visibility_range_begin/end` on interior props, `OccluderInstance3D` on the
  shell, keep `build_async()`. **Fallback if framerate fails:** ground-floor
  seamless / upper floors loaded — needs no rework of 4a/4b.

### Milestone 5 — City life
- **5a.** Re-bake the navmesh to cover IT Park (see §4 open issues).
  `AGENT_MAX_CLIMB = 0.35` already clears the 0.15 m kerbs.
- **5b.** Pedestrians/traffic. Best template is `cblock_edward_npc.gd`
  (waypoint patrol, rest-pose-corrected Mixamo retarget, auto-scale, foot
  grounding). Spawn around the player, not across 2.5 km.
- **5c.** Move the character picker (hardcoded in `cblock_map.gd:88-163`) to
  Banilad — `banilad_city.gd:50-60` only handles `M` and `R`.

### Milestone 6 — Crime loop
Money, wanted level, police, missions on the surviving `story_manager`
framework + `dialogue_choice_ui.gd`. Melee animates in
`cblock_player.gd:155-168` but resolves against nothing.

**The police officer already exists** — model, rig and placement are done, so
6's police work starts from a body that is already in the world.

- `tools/build_police.py` — Blender script, headless, writes
  `assets/npcs/police.glb` (~1.4k tris, 12 material slots, no textures).
  Run it the same way as the map scripts:

  ```bash
  "C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P tools/build_police.py
  ```

  - It **imports `animation mixamo/Idle.fbx` and skins onto that armature**
    rather than authoring bones. The retargeters copy rotation keys *untouched*
    (`cblock_player.gd:_retarget_clip`), so the target rest pose has to match
    Mixamo's exactly — reusing the real rig makes that true by construction
    instead of by luck. It also means the 65 bones already carry
    `mixamorig1_` names, so retargeting is a plain re-path with no bone map.
  - Rigid-bound: every part is weighted 1.0 to one bone, PS1 style. Bone-heat
    auto-weighting fails on the detached props (badge, buttons, handcuffs) and
    drops them at the origin.
  - Geometry is authored in the rig's own space (cm, +Y up, +Z forward,
    **+X is his left** — that is where `LeftUpLeg` sits).
  - ⚠️ **The imported FBX rig must be normalised before export.** Mixamo's FBX
    arrives as an armature at **0.01 scale with a Y-up→Z-up rotation on the
    object**, and that rotation cancels against the glTF exporter's own Z-up→
    Y-up conversion. Exported verbatim, Godot reads a skeleton at 0.01 scale
    lying on its back: bone span 23.5 cm (his *thickness*), not 1.76 m.
    `import_rig()` now applies the object transform, giving an identity rig at
    metre scale — the same shape Gusion has.
    - This is what made the **playable officer 500x too big**.
      `cblock_player._scale_and_align_visual` sizes a character by measuring
      raw vertex arrays, which for a skinned mesh sit in bind space: it read
      the 3.5 mm front-to-back thickness as his height and scaled by
      `1.78 / 0.0036`. It now measures 1.7636 m and scales by **1.009**.
    - `transform_apply` rescales bone rests but **not** an action's location
      curves, and bone translation lives in the bone's own space. The baked
      idle threw the hips ~100 m up and rendered an empty frame until those
      curves were scaled to match. Rotation curves need no fix — they are
      parent-relative, and rotating every bone equally preserves that.
    - Do not trust a skinned mesh's bind AABB as a size check. It reported a
      healthy 1.76 m throughout, which is why the first version of
      `police_city_smoke_test.gd` passed while the officer was broken. Both
      police tests now measure crown-to-sole from the bones, through the
      transform chain.
  - One more trap: `tube()` stacks its rings in Y, so a two-ring "disc" at one
    height collapses edge-on — the badge is built with `limb()` along +Z.
- `scripts/police_npc_prop.gd` — the NPC wrapper (auto-scale to 1.80 m, facing
  derived from the toe bone, interaction body via `uc_kiosk_npc_interact.gd`,
  `play_idle()` / `play_walk()`). Idle comes from the clip baked into the GLB,
  walk retargets from `Walking.fbx`; **both go through the same re-path**, since
  a baked clip's tracks are written against the GLB root and resolve to nothing
  from the prop's own player — which reports `is_playing() == true` while he
  stands in the T-pose, with nothing logged.
- Playable: he is in `cblock_character_roster.gd` as "PO1 Ramirez" and in
  `cblock_player.gd`'s scene table, so the character picker can drive him with
  all six clips.
- Placed in `banilad_city.gd:_spawn_street_npcs` as `BaniladPolice`, standing
  his post on the east sidewalk ~4 m up the avenue from the player spawn.
- Guarded by three tests in §5: `police_smoke_test.gd` (GLB clips + prop),
  `police_playable_smoke_test.gd` (roster + `switch_character`) and
  `police_city_smoke_test.gd` (spawns in the map, and bones actually leave the
  rest pose). All green.

---

## 6. Assets worth knowing about

- **Slum districts** (`assets/buildings/banilad_slum.glb`, 5.85 MB, 417 houses
  across 5 sitios, 60 k faces) — built by `tools/build_slum.py`. Banilad,
  Talamban, Kamagayan, Mabolo and Lorega, all 218–391 m from the player spawn.
  Collision comes from the `-col` mesh suffix at import, not
  `create_trimesh_collision()`. Each district carries a `kit` probability:
  Banilad is fully kitted, the outer sitios spend a kit module on a front bay
  only sometimes and box the rest, which is what keeps five districts inside a
  sane file size.
  The house kit is a *modular* pack, not finished houses: its wall panels are
  authored width-along-Y with rotations applied, so `obj.dimensions` lies, and
  face counts run from 1 (`plain wall 1`) to 15497 (`house 2`) — the build uses
  only the cheap modules and boxes the blank walls.
  Two tuning traps, both of which produced near-empty districts: alley branches
  must be seeded from points **already on the network** (free-floating seeds
  grow islands that get dropped as unreachable), and `MIN_ALLEY_SEP` must leave
  a house depth either side of the path (11 m) or the corridor test rejects
  nearly every lot and the block comes out all footpath.
- **Graffiti** (`assets/buildings/banilad_slum_graffiti.png`) — a 4×4 atlas of
  spray tags scrawled with numpy at build time, drawn into the walls as decal
  quads UV'd to one cell each. Alpha mode is CLIP (glTF MASK), not BLEND, so
  there is no transparency sort order against the wall behind. Texture
  filtering is `Closest` for the PSX look, same as `image_to_building.py`.
- **Player controller `cblock_player.gd` (685 L) is good** — orbit SpringArm
  camera, sprint, jump, punch, runtime Mixamo retargeting onto any humanoid rig,
  auto-scale to 1.78 m, foot grounding, live `switch_character()`.
- **Gusion** (`assets/characters/gusion/gusion_dimension_w_rigged.glb`) has all
  6 baked clips and works today. **Duterte** rig retargets from the 6 FBX clips
  in `animation mixamo/`.
- Reusable: `dialogue_choice_ui.gd`, `interactable.gd` (51 L),
  10-floor elevator (`elevator_ui.gd` + `school_building.gd:1799-1863`),
  threaded loading screen (`main_menu.gd:500-528`), PSX shaders.
- Missing: strafe/jump/vehicle animations, `AnimationTree`/blend spaces,
  player health, save/load, minimap, time-of-day clock.

## 7. Tests

All run as `--headless --path . --script res://<path>`:

```bash
.tools/godot/Godot_v4.7-stable_win64.exe --headless --path . --script res://scripts/tools/third_person_smoke_test.gd
```

- `scripts/tools/input_map_smoke_test.gd` — every action exists and a realistic
  device event still matches it (guards the device-tag trap in §5, 1a).
- `scripts/tools/vehicle_smoke_test.gd` — both vehicle kinds settle upright on
  four wheels at the height their model is drawn at, pull away under throttle,
  stop under the handbrake, and **steer left when left is pressed**.
- `scripts/tools/third_person_smoke_test.gd` — builds a synthetic scene and
  asserts the interaction prompt, the `interact` action firing an
  `Interactable`, the UI lock, and the pause menu pausing the tree. Fast.
- `scripts/tools/curb_step_smoke_test.gd` — walks the third-person body into a
  0.30 m kerb (the map's sidewalk height) and asserts it steps up without a
  jump, then swaps the kerb for a 2.5 m wall and asserts it is still stopped.
- `scripts/tools/banilad_smoke_test.gd` — headless map assertions, plus the
  road-collision guard: it walks a ray down through every surface at four
  junctions that measurably had the stacking bug and fails if any two sit
  within `CHATTER_BAND` (5 cm). Verified to fail on the pre-2a GLB — probes on
  straight stretches passed on both, which is why the probe points are
  specifically junctions.
- `scripts/tools/fast_travel_smoke_test.gd` — every fast-travel destination in
  `banilad_city.gd::TELEPORTS` resolves real ground AND a body-sized capsule
  fits there without hitting the world. Both halves matter: the anchors store
  XZ only and take their height from a ray, so one outside the collision
  surface drops the player past `FALL_LIMIT`; and **ten of the fifteen anchors
  were inside an OSM building footprint when first written** and had to be
  nudged into the open, so a rebuild that grows a footprint can put one back
  inside. Nothing else in the suite would notice either failure.

- `scripts/tools/slum_smoke_test.gd` — instances `banilad_slum.glb` and sphere-
  probes every alley vertex from `banilad_slum_alleys.json`, asserting none is
  inside a house and that the `-col` suffixes actually produced collision. This
  catches what the build script's own check cannot: `build_slum.py` tests its
  in-memory lots, this tests the GLB that ships. It found a real bug the build
  passed — at an alley bend the two segment rectangles leave the outer corner
  uncovered, so a house could pinch the turn shut.
- `scripts/mechanics_smoke_test.gd` — **the only regression guard on the
  2710-line `school_building.gd`** (all 10 levels' slabs, corridors, elevator
  landings, stair collision). Critical once the school moves into the city.
  Its horror asserts were replaced in Milestone 3 by guards that the horror
  systems stay deleted.
  - ⚠️ **Currently failing, and it was already failing at `4148d22`** (verified
    against a clean tree — not caused by Milestone 1). Line 59:
    *"UC's left-side street entrance must stay passable"* — a `DayLocker`
    StaticBody3D blocks the route from `(12, 1.2, 18)` to `(12, 1.2, 25.5)`.
  - A failed GDScript `assert()` halts `_initialize` **before its `quit()`**, so
    the run does not fail — it **hangs forever** at ~0% CPU. Always run this one
    under a timeout. Worth converting to the `_failures` + `quit(1)` pattern the
    other tests use. Fix before the school is moved in Milestone 4.
- `scripts/player_controller_smoke_test.gd` — asserts first-person setup; retire
  with `player.gd`.
- `scripts/tools/police_smoke_test.gd` / `police_playable_smoke_test.gd` /
  `police_city_smoke_test.gd` — the beat cop: his GLB clips and prop wiring,
  his roster entry driven through `switch_character`, and his placement in
  `banilad_city.tscn`. The city one is the important guard — it checks the idle
  tracks *resolve* and that a bone has left its rest pose, the two things that
  fail silently. **All green.** (`police_smoke_test.gd` uses `assert()`, so run
  it under a timeout.)
- `scripts/tools/measure_bounds.gd` — prints mesh bounds and the scale factor
  to 1.78 m for the police and Gusion rigs. Handy when a new character imports
  at the wrong size.
- `scripts/tools/story_map_smoke_test.gd` — Milestone 3's guard on `main.tscn`:
  the deleted horror systems must stay deleted, the survivors (phone, battery,
  keyed door, chapter framework) must still work, and the three named NPCs must
  stay in the world at night. Uses the `_failures` + `quit(1)` pattern, so it
  reports instead of hanging. **Runs green.**
