# Project status & pivot plan

Self-contained handoff. Read this first in a new session — it replaces the
chat history it was written from.

**Repo:** `C:\Users\Ariel\Documents\New project` · branch `master` ·
first commit `4148d22` (676 files tracked, clean tree).

---

## 1. What this project is

Godot 4.7 game set on a **real OSM-derived map of Cebu City** — the Gov. M.
Cuenco Avenue corridor in Banilad, extending south-west across **Cebu IT Park**.

It is currently branded *"Cuenca Ave · UC Banilad · After Dark"*, a first-person
school-horror game. **It is being pivoted into a GTA-style open-world crime
sandbox.** Horror is being removed.

### Three maps exist

| Scene | Script | What it is |
|---|---|---|
| `main.tscn` | `world.gd` (1566 L) | UBEC school-horror story. First-person `player.gd`. **All horror lives here.** |
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
  infill/props, writes `banilad_map.blend` + GLB.
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

- Local origin `LAT0=10.3345, LON0=123.9115`; ground half-extent 1250 m.
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

- Map builds clean: **840 buildings, 143,477 verts / 162,875 tris**, 76
  materials verified, GLB **8.39 MB**, 110 landmarks (19 key).
- Godot re-imports cleanly; `banilad_city.tscn` instances the GLB as `Level`.
- Menu entry **"BANILAD · Real Street Map"** (`main_menu.gd:153`) loads it.
- All 10 previews current.

### Known open issues

- **Navmesh is stale and incomplete.** `scripts/tools/bake_banilad_navmesh.gd`
  bakes `origin(-450,-6,-880) size(900,10,760)` → Godot x −450…450, z −880…−120.
  **IT Park at z ≈ +419 is entirely outside it.** It also predates the OSM
  re-pull and the rebuilt landmarks. Nothing consumes it yet
  (`NavigationAgent3D` appears nowhere), so it is harmless until NPCs land.
- **21 named IT Park buildings have no OSM height** and use type defaults.
  Central Bloc was overridden from a night aerial (the only non-OSM heights in
  the file); the rest would need references or upstream OSM tags.
- Project still branded for horror.

---

## 5. Pivot plan

Owner's decisions: **GTA-style crime sandbox** · horror removed · UBEC's
`SchoolBuilding` and `MallBuilding` **replace** the UC and C-Mall blocks in the
real map and are **enterable** · interiors **seamless, no loading screens** ·
driving is **physics-sim** (`VehicleBody3D`) · **vehicles first**.

### ✅ Step 0 — Version control — DONE
First commit `4148d22`. Commit at the end of each milestone.

### Milestone 1 — Foundations (blocking)
- **1a. InputMap.** No `[input]` section exists; every control is a hardcoded
  `Input.is_physical_key_pressed(KEY_*)`. Define real actions before vehicles
  add more. Unlocks gamepad + rebinding.
- **1b. Port interaction into third person.** *The biggest structural gap:*
  `cblock_player.gd` (used by **both** free-roam maps) has **no raycast, no `E`,
  no prompt**. The system exists only in first-person `player.gd:374-441`
  (`_update_prompt`, `_try_interact`, `_try_melee`, `_apply_melee_hit`).
  Reuse `interactable.gd` unchanged. Raycast **from the camera**, ~3 m.
- **1c. UI-lock mismatch.** `dialogue_choice_ui.gd:57` calls
  `player.set_ui_locked()`, implemented only by `player.gd`;
  `cblock_player.gd` has `set_controls_enabled()`. Add an alias.
- **1d. Pause menu.**

### Milestone 2 — Drivable vehicles
- **2a. Fix road collision first — blocks physics wheels.** Roads are separate
  overlapping ribbons nudged by `layer_z(base,i) = base + (i%16)*0.002`. At a
  junction that stacks **16 collidable surfaces across 3 cm**, with the
  collidable ground plane 13 cm below (ground `0.0`, minor road `0.09–0.12`,
  major `0.13–0.16`, sidewalk `0.15` + 0.15 kerb). `VehicleWheel3D` will
  chatter. Emit a single flat `Roads_Collision` mesh from the `road_lines`
  already collected in `build_map.py:main()`; add the visual road meshes to
  `NO_COLLIDE` in `prep_godot.py`.
- **2b.** `scripts/vehicle_body.gd` — `VehicleBody3D` + 4 `VehicleWheel3D`,
  reusing the 4 `street_car*.glb` + 2 `jeepney_*.glb`. Wheels aren't separate
  nodes; place them from the box dims in `street_vehicle_prop.gd:110-129`
  (cars 4.6×1.55×1.9, jeepneys 6.2×2.15×2.15). Anti-flip: low centre of mass,
  generous suspension travel, upright-assist above a roll threshold.
- **2c.** Enter/exit via 1b. No entry/exit animations exist — snap into the
  seat, hide the player mesh, hand the `CameraRig` SpringArm to the car, add a
  `driving` branch to the existing state machine.

### Milestone 3 — Remove horror and rebrand
Horror is far less entangled than it looks: **no `.tscn` references any horror
script**; it's all runtime-instantiated from `world.gd`.
- Delete: `scare_manager.gd` (521 L), `horror_creature_prop.gd` (242 L),
  `hide_spot.gd` (46 L), `assets/psx-horror-creature/`.
- Delete dead code `world.gd:1375-1566` (already unreachable).
- Strip ~150 L wiring from `world.gd`, ~200 L content from `story_manager.gd`
  (keep the chapter/objective/SMS framework), ~120 L from `player.gd`,
  ~60 L from `hud.gd`.
- `main_menu.gd`: drop the horror button (`:157`, `:574-577`), the `"inday"`
  password (`:316`), chapter names (`:371-380`), retitle.
- **Keep:** `phone_ui.gd` (clean SMS inbox, zero horror), day/night lighting
  presets `world.gd:389-467`, quest-marker glow `world.gd:1035-1073`.
- Reverse one horror decision: the three named NPCs sit in `_day_only_nodes`
  (`world.gd:898,925,953`) and **despawn at night**.

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

---

## 6. Assets worth knowing about

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

- `scripts/tools/banilad_smoke_test.gd` — headless map assertions.
- `scripts/mechanics_smoke_test.gd:35-113` — **the only regression guard on the
  2710-line `school_building.gd`** (all 10 levels' slabs, corridors, elevator
  landings, stair collision). Keep these; cut only the horror asserts at
  `:22-33` and `:114-133`. Critical once the school moves into the city.
- `scripts/player_controller_smoke_test.gd` — asserts first-person setup; retire
  with `player.gd`.
