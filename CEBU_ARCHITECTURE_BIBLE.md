# Cebu Architecture Bible — the building-design language

Companion to `CITY_MASTER_PLAN.md` and `PROJECT_STATUS.md`. Those record where
the city **goes** and what it **is**. This one records what its **buildings are
made of** — the Cebu-specific architectural language every generated building
must speak, and the modular kit that lets us speak it without modelling ten
thousand boxes by hand.

**Status: design only. No geometry or code is produced by this document.** It is
the approval gate before the modular kit (`banilad_map/parts.py`) is written and
before any building is upgraded on the map. Read §0 first — it is the single
most important constraint and the one most likely to be broken by a designer
arriving fresh.

---

## 0. The design law (read this before anything else)

Four constraints override every aesthetic instinct. They come from the engine
this game actually ships on, not from taste, and every rule downstream obeys
them.

1. **PSX / flat-shaded, no textures.** The game is PS1-retro: flat-shaded,
   low-poly, hard vertex lighting, `Closest` texture filtering. The map today
   has **76 flat-colour materials and zero UVs** (`PROJECT_STATUS.md` §2). A
   building's identity is therefore carried by **its silhouette and its
   material bands**, never by a brick texture or a normal map, because those do
   not exist in this renderer. The one planned exception is a **single signage
   atlas** (`CITY_MASTER_PLAN.md` §6.5) for Colon/Carbon shopfronts — that is
   the only texturing this whole project will do.

2. **Geometry for silhouette, material bands for detail.** This is the rule the
   existing landmark builders already follow (`banilad_map/landmarks.py` docstring).
   Massing, roof form, and anything that changes the outline against the sky are
   **real polygons**. Mullions, cornices, arcades, floor lines, signage,
   glazing — anything that is a change of *colour* not *shape* — is a thin band
   standing slightly **proud** of the wall (a recessed band is invisible: it
   sits inside the solid wall — see `PROJECT_STATUS.md` §3 bug 4). Balconies,
   awnings and stairs sit on the edge: proud enough to break the silhouette,
   cheap enough to spend on every building.

3. **Triangle budget is the currency.** The city is 20.78 km², streamed as
   364 × 250 m tiles, peak ~21 tiles resident (`PROJECT_STATUS.md` §2). The
   whole current map is 170k triangles. Every module below is costed in
   triangles. `tower_detail()` articulates a whole tower for "a few dozen
   triangles"; a balcony module must be in the same register. **If a detail
   costs more than the silhouette it buys, it is a texture's job, and we do not
   have textures — so it is cut.**

4. **Determinism.** Every choice — variant, colour jitter, weathering, which
   AC unit sits where — is seeded off the **OSM way id**, never off placement
   order. A placement counter walks in lockstep with the lattice and bands whole
   blocks one colour (`PROJECT_STATUS.md` §2, the tint bug). Landmark identity is
   the way id, not the `name` (Blender suffixes duplicates `.001`). A rebuild
   must reproduce the city vertex-for-vertex.

**What this Bible is *not*.** It is not a call to hand-model 105 buildings. The
brief's "105 concepts" is the *coverage target* — the range the kit must be able
to express — not a modelling to-do list. We express that range through
**architectural families + a parts kit + per-building variation**, exactly as
`CITY_MASTER_PLAN.md` §6.5's three-tier plan (S bespoke / A kitbash / B
procedural) already frames it. This document is the missing content of that
plan: the actual taxonomy, the actual kit, the actual variation rules.

### Current state vs. target (be honest about the gap)

The map is **already populated** — 840 buildings, procedurally. Today a typical
building is: extrude the OSM footprint → pick a wall colour and a roof kind from
the district palette → add `window_bands()` → maybe a `shopfront_band()` → scatter
`roof_clutter_field()`. That is genuinely good massing and **wrong-to-thin
detail**: no balconies, no awnings over the street, no exterior stairs, no
compound walls, no capiz windows, one signage colour where Colon needs a wall of
tarpaulins. This Bible defines the upgrade from *box + bands* to *box + bands +
the Cebu detail kit*, district by district. Nothing here throws away the massing
that works.

---

## 1. What makes it read as Cebu (not "generic Asian city")

The brief's core fear is a generic Southeast-Asian look. These are the specific,
falsifiable things that separate Cebu from Bangkok, Jakarta or Manila, ranked by
how cheaply they read in this renderer:

1. **The roofscape is half faded galvanised sheet, half oxidised red.** Not
   bright terracotta, not blue tile. This is already measured into the palette
   (`Roof_Galv_*`, `Roof_Rust_*`, weighted 50/50 in `districts._GALV_ROOFS`).
   From any elevated view this single fact *is* the barangay.
2. **Hollow-block (CHB) walls, unpainted or long-faded.** Grey, weathered,
   patched — not pastel. Fresh saturated paint is the exception (a repainted
   sari-sari store), never the field. Palette runs `Wall_0..6` grey on purpose.
3. **Zero-setback commercial party walls downtown.** Colon and Carbon buildings
   share side walls and rise straight off the lot line — a continuous block face,
   not freestanding boxes with gaps. This is a *generator* property (perimeter
   block, §5-A) as much as a building property.
4. **The signage canyon.** Colon is defined by tarpaulin banners and stacked
   painted shopfronts, not by its massing. Carbon is umbrellas and hand-lettered
   boards over an invisible road surface. This is the signage atlas's job and the
   one place massing alone cannot win.
5. **Catholic silhouette markers.** A colonial belfry (four diminishing stages,
   `landmarks.build_basilica_belfry`), an octagonal tiled pavilion (Magellan's
   Cross), a neoclassical dome (Capitol). One per district, tall enough to read
   over the roofline, is worth a hundred generic boxes.
6. **The AC-unit / water-tank / cable roofscape.** Every occupied Cebu roof
   carries a squat water tank and a scatter of split-type AC boxes. Already in
   `roof_clutter_field()`; must extend to wall-hung AC units (§4-K) which read
   from the *street*, not just from above.
7. **Rooftop extensions and unfinished top floors.** The half-built third storey
   with rebar stubs and hollow-block infill is a Philippine signature (owners
   build vertically as money allows). §6 imperfection system.
8. **Jeepney-scale ground floor.** Rolling steel shutters, a 2.4–3.0 m shop
   opening, a concrete apron, a tangle of meter boxes and drop wires at the
   corner. The street reads Filipino at eye level before the massing does.

Everything in §§4–6 exists to deliver these eight things.

---

## 2. Taxonomy → the real map

The brief's categories A–O are **not** a new zoning scheme — they are building
*types*, and the map already has a **district** scheme (`districts.CITY_DISTRICTS`,
11 bands from Banilad to the Port). The job is to state which types populate which
districts, so the district picker knows what kit to reach for. This table is the
bridge; the per-type detail is §4.

| Brief category | District(s) it populates (Godot z, from master plan) | Landmark anchors it sits around |
|---|---|---|
| **A — Old downtown commercial** | Downtown Colon (+4000…+4500), Parian (+4200…+4500) | Metro Colon, Gaisano Main, Colon Obelisk, Basilica |
| **B — Cebu mixed commercial** (the workhorse) | Fuente (+2400…+2900), University Belt (+2900…+3900), Lahug (+700…+1400), Banilad (−1170…−200) | *the fabric between* every landmark |
| **C — Filipino urban residential** | Kamputhaw/Capitol (+1900…+2400), Banilad edges, Lahug slopes | Country Club edge, walled compounds |
| **C-low — informal settlement** | 5 `SLUM_DISTRICTS` (Banilad, Talamban, Kamagayan, Mabolo, Lorega) | *built* — `tools/build_slum.py` |
| **D — Apartments / boarding houses** | University Belt, Fuente, Lahug | around USC/USJ-R/UC |
| **E — Old Cebu commercial (Art-Deco/pre-war)** | Downtown Colon, Parian | Colon corridor |
| **F — Modern mid-rise** | Fuente (hotels/hospitals), Lahug, Business Park edge | Crown Regency, Chong Hua, Waterfront |
| **G — IT Park architecture** | Cebu IT Park (+200…+800) | Central Bloc (*built*), eBloc, TGU, Skyrise |
| **H — Cebu Business Park** | Cebu Business Park (+1400…+2000) | Ayala Center (*built massing*), Ayala Triangle |
| **I — Malls** | Business Park, Banilad, IT Park | Ayala Center, Gaisano Country (*built*), Central Bloc |
| **J — Markets** | Carbon (+4500…+4750), Port edge | Carbon Units 1–3 (*built massing*), Pasil |
| **K — Religious** | Parian, one per residential barangay | Basilica (*built*), Metro Cathedral, Redemptorist |
| **L — Schools** | University Belt, one per residential district | USC, USJ-R, UC Main, Cebu Normal |
| **M — Barangay / government** | every district, low-rise | Capitol, City Hall, Palace of Justice |
| **N — Industrial / port** | Port District (+4400…+4800) | Piers 1–4 (*built massing*), warehouses |
| **O — Hillside** | Lahug/Busay slopes (backing 60–660 m terrain) | retaining-wall terraces above Salinas Dr |

**Reading the table:** categories B and C are ~70% of the city by footprint and
get the most kit attention. A, E, J are the "reads as Cebu" money districts and
depend on the signage atlas. G, H, I, N mostly have *good OSM massing already* and
need the tower/warehouse kit plus material discipline, not new silhouettes.

---

## 3. Proportion & material constants (the numbers everything inherits)

These extend the constants already in `build_map.py`. New ones are proposed;
existing ones are cited so the kit stays consistent with what is built.

| Constant | Value | Source / note |
|---|---|---|
| `LEVEL_HEIGHT` | **3.3 m** | existing. Residential/office floor. |
| Commercial ground floor | **3.6–4.6 m** | existing `first_floor=3.6`; Metro arcade 4.6 |
| Department-store floor | **3.7 m** | existing `METRO_FLOOR` |
| `PLINTH_MARGIN` | **0.6 m** | existing. Extra plinth below lowest corner on slopes. |
| `PITCHED_ROOF_MAX` / `_MAX_AREA` | **11 m / 700 m²** | existing. Above this → flat/parapet, not hip. |
| `TOWER_MIN_HEIGHT` | **26 m** | existing. Above this → `tower_detail()` kit. |
| Shophouse lot width | **4–6 m** | *new.* Colon/Carbon party-wall bay module width. |
| CHB course | **0.2 m** | *new.* Hollow-block reference for wall banding rhythm. |
| Balcony depth | **1.0–1.4 m** | *new.* Cantilever from façade. |
| Awning projection | **1.2–2.0 m** | *new.* Over sidewalk (master plan §3.1). |
| Compound wall height | **1.8–2.4 m** | *new.* Residential fence + gate. |

**Colour discipline (the single most-broken rule).** The palette is
*deliberately desaturated* — measured off reference aerials, pulled back from
"map-key" colours (`PROJECT_STATUS.md` §3, palette retune). Every new material
proposed in §7 must sit in that muted register. A saturated blue turned the
whole IT Park skyline blue once; a cream banner on cream wall rendered as nothing
once. **Contrast is carried by value (light/dark), not by saturation.** When in
doubt, desaturate and separate by lightness.

---

## 4. The modular kit — `banilad_map/parts.py`

The deliverable that makes Tier-A kitbash possible (`CITY_MASTER_PLAN.md` §6.5).
Master plan's instruction stands: **extract the parts that already exist inside
`build_map.py` and `build_mall.py` rather than rewriting them**, then add the
missing Cebu-specific ones. Each module below is tagged:

- **[HAVE]** — already in the codebase, extract as-is into `parts.py`.
- **[NEW]** — must be written. Costed in triangles and given a signature.

Every module takes a `batch` (a `MeshBatch`/`LiftedBatch`) and a `mats` dict, and
adds proud bands or edge geometry — the established call convention
(`landmarks.py`, `tower_detail`).

### 4.1 WALL modules
- **[HAVE] `walls(pts, base_z, top_z)`** — the base extrusion. Everything sits on
  this.
- **[HAVE] `ring_solid(outer, inner, z0, z1)`** — walls with a real cavity
  (courtyard buildings, the Fort). Keep for U/C/L-shaped footprints so the
  extruder stops filling courtyards solid (the UC bug).
- **[NEW] `party_wall_bay(batch, mats, edge, width, floors, seed)`** — one
  4–6 m bay of a zero-setback commercial block: blank CHB side returns, a
  glazed/shuttered ground opening, window course above. The unit the perimeter-
  block generator (§5) tiles along a street frontage. **~30 tris/bay.** This is
  category A/E's core.
- **[NEW] `compound_wall(batch, mats, ring, height, gate_edge, seed)`** — the
  1.8–2.4 m perimeter fence around a residential lot, with one gate opening
  (sliding or swing, a darker recessed panel) and optional pier caps. Category
  C/M. Capitol district's "assets needed: compound walls + gates" (master plan
  §5). **~2 tris/m + gate.**

### 4.2 WINDOW & DOOR modules
- **[HAVE] `window_bands(...)`** — recessed glazing, one band per floor, tuned
  low-rise vs mid-rise. Keep both presets.
- **[NEW] `punched_windows(batch, mats, edge, floors, ratio, seed)`** — discrete
  window *boxes* (proud dark quads) instead of a continuous band, for façades
  where individual openings read (residential, 1950s–70s small-window stock).
  A band says "office"; punched holes say "apartment." **~2 tris/window.**
- **[NEW] `capiz_bay(batch, mats, edge, floors)`** — the heritage window: a
  sliding wood-framed grid of capiz (translucent shell) panes over a stone base.
  In this renderer it is a pale warm band (`Heritage_Capiz`) divided by a thin
  proud mullion grid, over a `Heritage_Stone` course. Parian only (master plan
  §5, §8 "heritage kit"). **~12 tris/bay** — the most expensive residential
  module, spent only where it defines the district.
- **[NEW] `door_recess(batch, mats, edge, t, kind)`** — a single proud/recessed
  entrance: shop roll-up shutter, residential gate door, glazed corporate lobby.
  Cheap silhouette break at the pedestrian's eye. **~6 tris.**

### 4.3 BALCONY module
- **[NEW] `balcony(batch, mats, edge, t0, t1, floor_z, depth, rail_kind, seed)`**
  — a cantilevered slab (proud box, 1.0–1.4 m deep) with a railing above it
  (thin proud band: `Rail_Metal` bars or `Rail_Solid` CHB balustrade). The
  single most-missing Cebu detail: mixed commercial (B) and apartments (D) are
  defined by irregular stacked balconies with laundry, plants and mismatched
  rails. Placed on street-facing edges, upper floors only, with per-floor jitter
  so no two stack identically. **~10 tris/balcony.**

### 4.4 SHOPFRONT & AWNING modules
- **[HAVE] `shopfront_band(batch, mats, ring, base_z, seed)`** — dark recessed
  opening + sign fascia at ground level. Keep; it is the district shopfront rate
  driver.
- **[NEW] `awning(batch, mats, edge, t0, t1, z, projection, kind)`** — the
  projecting sidewalk cover every commercial frontage carries: sloped steel sheet
  (`Awning_Steel`), flat concrete slab, or fabric (`Awning_Canvas`). Master plan
  §3.1/§6.4 flags awning/signage bands as a needed new road-frontage feature.
  This is what makes a Colon street section read correct. **~4 tris.**
- **[NEW] `signage_band(batch, mats, edge, t0, t1, z0, z1, atlas_uv)`** — the
  UV-mapped façade quad into the **signage atlas** (the project's one texturing
  job, master plan §6.5). Requires `MeshBatch.add()` to stop discarding UVs.
  Until the atlas exists, it degrades to a flat `Sign_*` colour band (what the
  map does now). Category A/E/J. This is the highest visual-return module and the
  only one blocked on new engine capability.

### 4.5 ROOF modules
- **[HAVE] `hip_roof` / `shallow_hip`** — four-sided hip (bounding box / true
  outline). Low-rise residential.
- **[HAVE] `shed_roof`** — single-slope tin. Informal + cheap infill; the module
  that broke the "2000 copies of one house" look.
- **[HAVE] `parapet_roof`** — flat slab + parapet. Commercial/mid-rise.
- **[NEW] `roof_extension(batch, mats, ring, top_z, coverage, seed)`** — the
  partial upper-floor add-on: a smaller box on part of the roof (often a
  different wall colour and a shed roof), the "owner built up as money allowed"
  signature. Ties into §6. **~12 tris.**
- **[NEW] `monitor_roof`** — extract from `landmarks.build_carbon_hall`: the
  raised clerestory strip down a market/warehouse ridge. Category J/N.

### 4.6 STAIR module
- **[NEW] `exterior_stair(batch, mats, edge, floors, kind)`** — the external
  concrete staircase (straight run or switchback with a half-landing) serving
  upper-floor apartments/boarding houses directly from the street. Ubiquitous in
  D and low C; almost never in OSM. A strong Filipino-residential silhouette
  marker. **~4 tris/flight.**

### 4.7 ROOFSCAPE modules (AC / TANK / UTILITY)
- **[HAVE] `roof_clutter_field(...)`** — water tanks, AC boxes, antenna masts on
  small roofs, seeded off way id. Keep.
- **[HAVE] `roof_plant_field(...)`** — dense AHU grid on wide mall/tower roofs.
  Keep.
- **[NEW] `wall_ac(batch, mats, edge, floors, density, seed)`** — the split-type
  AC condenser box hung on the *façade* under windows, with a small proud drip
  shelf. Reads from the street where roof clutter does not. Category B/D
  signature. **~6 tris/unit**, budgeted at a low density (not every window).
- **[NEW] `utility_riser(batch, mats, edge, seed)`** — the corner tangle: a meter
  box, a vertical conduit run, and 1–2 drop-wire catenary lines to a pole. Three
  thin proud boxes + a slack line. The cheapest "this is a used building" tell.
  **~8 tris.**
- **[NEW] `water_tank_stand(batch, mats, px, py, top_z)`** — the elevated poly
  tank on a 4-leg steel stand (as opposed to the squat roof tank already in
  `roof_clutter_field`). Reads on the skyline of lower districts. **~14 tris.**

### 4.8 TOWER & PODIUM modules (categories F/G/H)
- **[HAVE] `tower_detail(...)`** — podium base, per-floor curtain-wall band,
  crown, rooftop plant. The whole IT Park articulation. Keep; parameterise the
  scheme per family (§5-G/H).
- **[HAVE] arcade/clay-roof bays in `build_mall.py`** — extract the arcade bay and
  covered-walkway spine for category I and Parian arcades.
- **[NEW] `podium_retail(batch, mats, ring, podium_h)`** — the glazed retail
  ground floor + signage fascia under a tower/mall podium, distinct from the
  low-rise `shopfront_band`. Category F/G/H/I.

**Module count:** 12 HAVE (extract), 15 NEW. The NEW set is the whole brief's
module list (WALL/WINDOW/DOOR/BALCONY/SHOPFRONT/ROOF/STAIR/AWNING/SIGN/AC/TANK/
UTILITY) minus what already exists, plus the two Cebu-specific families the map
lacks entirely (compound wall+gate, capiz heritage bay).

---

## 5. Per-category specification

Each category gives the brief's required fields: **floors · footprint · wall ·
roof · windows · balconies · colours · signs · weathering · age · socioeconomic ·
where on the map.** Materials are named from the existing palette where they
exist; **†** marks a new material proposed in §7. Modules are named from §4.

### A — Old downtown commercial
- **Floors** 2–5. **Footprint** narrow (4–8 m frontage), deep, **zero setback,
  shared party walls**. **Wall** `Wall_Concrete_0/1/2`, faded painted commercial
  stock, widest colour spread in the city (Colon = a century of independent
  repaints). **Roof** flat/parapet, occasional `Roof_Rust`. **Windows**
  `punched_windows`, narrow, some boarded. **Balconies** shallow cantilever with
  metal rail on 2nd floor. **Colours** faded primaries over grey; per-building
  tint spread `tint=1.6` (Colon, highest in the table). **Signs** stacked
  `signage_band` + `awning` — *this is the category*, cannot read without the
  atlas. **Weathering** heavy: stains, patched render, new signs over old.
  **Age** 1950s–1990s mix. **Socioeconomic** working commercial. **Where** Colon,
  around Metro Colon and the Obelisk.
- **Modules:** `party_wall_bay` + `punched_windows` + `awning` + `signage_band` +
  `balcony` + `door_recess(shutter)` + `roof_clutter_field`.

### B — Cebu mixed commercial (THE WORKHORSE, most common type)
- **Floors** 3–6. **Footprint** medium, small-to-no setback. **Wall** painted CHB,
  `Wall_0..6` + `Wall_Concrete_*`, more colour than downtown but still muted.
  **Roof** flat/parapet, some low hip. **Windows** `window_bands` (low-rise
  preset) + `balcony` on street face. **Balconies** the defining feature —
  stacked, irregular, mixed `Rail_Metal`/`Rail_Solid`, laundry & plant clutter
  implied by jitter. **Colours** one repainted ground floor, faded upper floors.
  **Signs** `shopfront_band` + one `awning`; pharmacy/pawnshop/sari-sari/
  carinderia/cellphone/hardware ground floor. **Weathering** medium; AC boxes on
  façade (`wall_ac`), `utility_riser` at corner. **Age** 1980s–2010s. **Socio**
  lower-middle to middle. **Where** Fuente, University Belt, Lahug, Banilad — the
  connective fabric everywhere.
- **Modules:** `walls` + `window_bands` + `balcony` + `shopfront_band` + `awning`
  + `wall_ac` + `utility_riser` + `roof_clutter_field`. **This is the kit's
  reference build — get B right and 70% of the city is right.**

### C — Filipino urban residential (with socioeconomic tiers)
- **LOW** (non-slum poor): 1–2 floors, tiny lots, unfinished CHB (`Wall_5/6`
  grey), `shed_roof` galvanised, `punched_windows` small, improvised extensions,
  patched walls. **LOWER-MIDDLE:** 2 floors, painted CHB, `compound_wall` + metal
  gate, small carport recess, one `balcony`, `Roof_Galv`/`Roof_Clay`,
  `water_tank_stand`. **MIDDLE:** 2–3 floors, larger lot, modern CHB, enclosed
  garage, larger `window_bands`, decorative parapet, landscaped front (a green
  landuse patch). **Roof** hip/shed low, flat on modern. **Signs** none, or a
  sari-sari store attached (one `shopfront_band` on a house). **Age** full spread.
  **Where** Kamputhaw/Capitol (walled compounds, mature trees, `shopfront=0.10`),
  Banilad edges, Lahug slopes.
- **Modules:** `walls` + `compound_wall` + `punched_windows`/`window_bands` +
  `hip_roof`/`shed_roof` + `exterior_stair` + `roof_clutter_field`. Socio tier is
  a **parameter set**, not new geometry (§6 age system pattern).

### C-low — informal settlement — **BUILT**, do not rebuild
`tools/build_slum.py`, 5 sitios, 417 houses, generated corrugated GI + spray-tag
decals. The Bible's only note: keep its `kit` probability discipline (flagship
fully kitted, outer sitios box the blank walls) — it is the reason 5 districts fit
in a sane file size. Extend to Pasil/Ermita per master plan, same kit.

### D — Apartments / boarding houses
- **Floors** 3–5. **Footprint** narrow deep lot. **Wall** CHB, mixed paint (the
  "10–30 years old" look = value-jittered per floor). **Roof** flat/parapet.
  **Windows** dense `punched_windows` or `window_bands`, many identical (rooms).
  **Balconies** many, small, with laundry. **Ground floor** open parking recess
  (`door_recess` wide) + `exterior_stair` to upper floors. **Roofscape** water
  tanks + heavy `wall_ac`. **Signs** small "Rooms for Rent" board. **Age**
  2000s–2020s newer stock alongside 1990s. **Socio** student/working.
  **Where** University Belt, Fuente, Lahug.
- **Modules:** `walls` + `punched_windows` + `balcony`(×many) + `exterior_stair` +
  `wall_ac` + `door_recess(parking)` + `water_tank_stand`.

### E — Old Cebu commercial (Art-Deco / pre-war / post-war)
- **Floors** 2–4. **Footprint** narrow, zero setback. **Wall** `Wall_Concrete_2`
  painted, **vertical signage fin**, simple Deco stepped parapet (a proud stepped
  band — geometry, cheap). **Roof** flat. **Windows** vertical `punched_windows`,
  old proportions. **Colours** cream/ochre faded. **Signs** vertical projecting
  blade sign + `signage_band`. **Weathering** heavy, weathered walls, heritage
  patina. **Age** 1930s–1950s. **Socio** old commercial. **Where** Colon/Parian.
  **Guard rail from the brief:** *do NOT make every old building Spanish
  colonial.* Most are plain old Philippine urban commercial — a Deco parapet and a
  vertical sign, not arches.
- **Modules:** `party_wall_bay` + stepped-parapet variant of `parapet_roof` +
  `punched_windows` + vertical `signage_band`.

### F — Modern mid-rise (offices/hotels/hospitals/condos, 6–15 floors)
- Several **families**, not one design (§5.1). **Wall** `Tower_Pale/Concrete/
  White` + glazing scheme (`TOWER_SCHEMES`). **Roof** flat deck + plant.
  **Podium** `podium_retail` + parking. **Windows** vertical curtain patterns via
  `tower_detail` bands. **Balconies** on condo family only (recessed loggia).
  **Signs** rooftop name sign. **Age** 2000s–2020s. **Socio** corporate/
  medical. **Where** Fuente (Crown Regency, Chong Hua, Rajah Park), Lahug
  (Waterfront dome), Business Park edge.
- **Modules:** `tower_detail` + `podium_retail` + (condo) recessed `balcony`.

### G — Cebu IT Park (BPO campus)
- **Good OSM massing already exists** (49 towers built). **Floors** 7–20
  (**not** 30+ — TGU is 15, eBloc 3 is 7; the brief's own example). **Wall**
  white/pale concrete + **charcoal glass** (`TOWER_SCHEMES`, no saturated blue).
  **Roof** deck + `roof_plant_field`. **Podium** large glazed retail + garden.
  **Signs** corporate `Bloc_Sign` band. **Age** 2010s–2020s clean. **Socio**
  corporate. **Where** IT Park, around Central Bloc (*built*) + Garden Bloc.
  **Guard rail:** *do NOT make it look like BGC.* Cebu proportions — mixed 7–20
  storey, real Garden Bloc void at the centre (`build_it_park_garden`, built), not
  a wall of identical 30-floor slabs.
- **Modules:** `tower_detail` (IT Park scheme) + `podium_retail`. Mostly material
  discipline, not new geometry.

### H — Cebu Business Park
- A **different, wealthier family** from IT Park (master plan §5: manicured, tight
  jitter `tint=0.45`). **Floors** 8–30 premium. **Wall** `Tower_White/Pale` +
  stone/`Wall_Concrete_2`, more solid, less all-glass. **Roof** deck + plant.
  **Podium** landscaped, organized setbacks. **Signs** restrained. **Age**
  2010s–2020s. **Socio** premium corporate/residential. **Where** Business Park,
  around Ayala Center (*built massing* + The Terraces) and Ayala Triangle.
- **Modules:** `tower_detail` (Business Park scheme, stone-biased) + `podium_retail`
  + landscaped podium cap.

### I — Malls
- **Two built** (Gaisano Country surveyed, Ayala Center massing + Terraces). The
  Bible's role is the **variant kit** for the rest: entrance bay, blank service
  wall, loading dock, rooftop `roof_plant_field`, signage zone. **Wall**
  `Mall_Wall` cream / `Bloc_Podium` mauve / big blank `Wall_Concrete`. **Roof**
  clay (`Mall_Roof`, Gaisano) OR flat deck (Ayala). **Signs** large `Bloc_Sign`.
  **Where** Business Park, Banilad, IT Park, N. Bacalso (E-Mall), Gen. Maxilom
  (Robinsons). **Guard rail:** *not a generic American mall* — Philippine malls
  are big-box + covered walkway + jeepney/loading apron, cream stucco or mauve
  cladding, clay OR deck roof.
- **Modules:** extract `build_mall.py` arcade + walkway + parking + `podium_retail`
  + `roof_plant_field` + service-wall variant of `walls`.

### J — Markets (Carbon, wet/public markets)
- **Built massing** (`build_carbon_hall` + stall field). **Floors** 1–2, large low
  footprint. **Wall** `Market_Wall`. **Roof** long `Roof_Galv` + `monitor_roof`
  clerestory + eave overhang. **Storefronts** open, covered walkways, `awning`
  everywhere. **Signs** `Canopy_*` band + hand-lettered. **Weathering** heavy,
  wet, aging. **Where** Carbon, Pasil, neighbourhood markets. **Guard rail:**
  *completely different from a mall* — corrugated, open, invisible road surface
  under tarpaulin (`build_carbon_stalls`, 2.2 m canopy the player walks under).
- **Modules:** `monitor_roof` + `walls`(open) + `awning`(dense) + stall field
  (built) + `signage_band`.

### K — Religious
- **Large church:** distinctive silhouette — colonial belfry (built:
  `build_basilica_belfry`, 4 diminishing stages), or neoclassical/modern. Stone
  base, tile/deck roof, dome or spire. **Small barangay chapel:** simple gabled
  box, cross finial, one bell. **Modern evangelical:** wide low hall, big cross
  sign. **Colours** `Church_Stone` + `Church_Trim` + `Pavilion_Roof` tile.
  **Where** Parian (Basilica, Metro Cathedral, Redemptorist) + one chapel per
  residential barangay. **Cheap-recognition winner** (master plan: Magellan's Cross
  is the best cost/recognition ratio in the whole list).
- **Modules:** belfry (built) + gable + cross finial + `capiz_bay`(heritage) +
  arcade bay.

### L — Schools
- **Floors** 2–5 concrete slabs. **Footprint** long corridor blocks around a yard.
  **Wall** `Wall_Concrete` painted institutional (often two-tone). **Roof** flat/
  low hip. **Windows** long continuous `window_bands` (classroom ribbon) + metal
  rail corridor (proud band). **Yard** covered basketball court (a `monitor_roof`
  shed on posts — the single most Filipino-school object), gate, canteen, admin
  block. **Signs** school name arch over gate. **Age** 1970s–2010s. **Where**
  University Belt (USC, USJ-R, UC, Cebu Normal) + one per district. **Guard rail:**
  *not American school design* — concrete, open corridors with metal railings,
  covered court, perimeter wall + gate. **Note:** `SchoolBuilding`
  (`school_building.gd`, enterable) migrates in here per master plan Milestone 4.
- **Modules:** institutional-slab `walls` + ribbon `window_bands` + corridor rail +
  covered-court `monitor_roof` + `compound_wall` + gate arch.

### M — Barangay / government
- **Floors** 1–3, functional not luxurious. **Wall** `Wall_Concrete` plain,
  often with a painted seal band. **Roof** hip/flat. **Windows** `window_bands`
  regular. **Types** barangay hall, police station (`police.glb` NPC exists),
  fire station (tall door + hose tower), health center. **Flag** + seal + name
  board. **Capitol/City Hall** are the monumental exceptions (Tier-A neoclassical
  dome). **Where** every district; Capitol terminates the Osmeña axis.
- **Modules:** `walls` + `window_bands` + flag/seal band + (fire) tall
  `door_recess`. Capitol = bespoke Tier-A.

### N — Industrial / port
- **Built massing** at the piers (`build_pier`: shed + containers + gantry crane).
  **Floors** 1–2 tall (8–12 m). **Wall** `Warehouse_Wall` corrugated/concrete,
  faded. **Roof** long `Warehouse_Roof` galv + `monitor_roof`. **Openings** big
  loading doors (`door_recess` wide), steel structure. **Signs** faded industrial
  board. **Props** `Container_*` stacks, `Crane_Steel` gantries. **Where** Port
  District, backing the sea plane. **Guard rail:** corrugated metal + concrete +
  large loading doors + faded paint, not glass.
- **Modules:** `walls`(tall) + `monitor_roof` + wide `door_recess` + containers/
  cranes (built) + steel-truss band.

### O — Hillside Cebu
- **Terrain-responsive** (Lahug/Busay slopes, DEM 60–660 m behind the city).
  **Retaining walls** (`compound_wall` tall, stepped down the slope) + houses that
  **step with the grade** (each floor plinth sampled separately — buildings do NOT
  drape, they take a base + plinth, `PROJECT_STATUS.md` §2). Mix of narrow poor
  houses, larger private residences, modern villas, irregular development.
  **Guard rail from the brief:** *do NOT flatten hills to fit buildings* — the
  plinth-to-lowest-corner rule already respects this; extend it with stepped
  retaining walls so a house on a slope reads as terraced, not floating or buried.
  **Where** above Salinas Dr, Lahug/Guadalupe/Busay.
- **Modules:** stepped `compound_wall` (retaining) + `walls` on independent plinths
  + `exterior_stair` + hillside villa variants of C-middle.

### 5.1 Architectural families & anti-repetition

The brief's BAD/GOOD example (A-A-A-A-A vs varied) is the core anti-goal. Three
mechanisms already in the codebase enforce it; the Bible formalises them:

1. **District palette weighting** (`districts.py`) — each district draws walls/
   roofs from a weighted list, so Colon's spread ≠ Business Park's tight scheme.
   Extend with per-district **module sets** (the §4 lists above).
2. **Way-id-seeded variant flags** — each building rolls, off its way id:
   `+balcony? +roof_extension? +awning? which shopfront? which era preset?
   value-jitter amount`. Same footprint → different building. This is the
   "Building A + balcony / Building B + different windows" mechanism, made
   deterministic.
3. **Families, not instances** — B, C, F, G, H each define **3–5 families**
   (different window rhythm, balcony pattern, crown), and the picker chooses a
   family by way-id hash, then applies variant flags within it. Target: **no two
   adjacent buildings share both family and variant.**

---

## 6. Building age system & imperfection system

Both are **parameter sets applied to the same kit**, seeded off way id — not new
geometry. This is how one kit yields 1950s→2020s without five separate kits.

### 6.1 Age presets (era → parameters)

| Era | Floor h | Wall palette bias | Window module | Roof | Roofscape | Value-grime |
|---|---|---|---|---|---|---|
| **1950s–70s** | 3.0 m | grey `Wall_5/6`, faded | small `punched_windows` | hip/flat, `Roof_Rust` | tanks, few AC | heavy |
| **1980s–90s** | 3.2 m | stronger paint, `Wall_2/Concrete_0` | `punched` + `balcony` metal rail | flat/parapet, `Roof_Galv` | tanks + `wall_ac` | medium-heavy |
| **2000s** | 3.3 m | `Wall_Concrete_*`, glass shopfront | `window_bands` + `shopfront` | parapet | more `wall_ac` | medium |
| **2010s** | 3.4 m | `Tower_Pale`, cleaner | `window_bands` wide | deck | plant | light |
| **2020s** | 3.6 m | `Tower_White`, minimal | full-height glazing band | deck | plant | minimal |

The district picker mixes eras per district (Banilad newer, Colon older) so **the
whole city is never one generation** — the brief's explicit "do NOT make the
entire city look newly built."

### 6.2 Imperfection system (used carefully — believable, not dirty)

Hooks into the **existing vertex-colour grime** (`PROJECT_STATUS.md` §2: `Col`
attribute darkens each wall toward its base). Each is a probability rolled off
way id, weighted by era + district `tint`:

- **Value/grime:** darken toward base (have it) + random per-wall value jitter
  (faded paint, stains).
- **Patched wall:** one bay a different wall value (a repaint/repair).
- **Mismatched windows:** one floor's window module differs.
- **Roof extension:** `roof_extension` on part of the roof, different colour
  (unfinished top floor — the strongest Cebu tell).
- **New sign over old:** two overlapping `signage_band` quads, one brighter.
- **Uneven awnings:** per-bay awning jitter in projection/colour.
- **Utility tangle:** `utility_riser` density up in older/denser districts.
- **Rebar stubs:** thin `Pole` verticals on an unfinished parapet (cheap, strong).

**The governor:** imperfection probability scales with district `tint` (Carbon
1.5, Colon 1.6 → busy; Business Park 0.45 → almost none). This is the brief's
"believable, not artificially dirty" — a manicured district stays clean by
construction. **Cap total imperfection modules per building** so no single
building becomes a junk pile.

---

## 7. New materials required

Additions to `PALETTE`. Values sit in the existing **muted, value-separated**
register (§3). sRGB, as the palette stores them. To be reviewed before coding —
proposed, not final.

| Name | sRGB (proposed) | Used by |
|---|---|---|
| `Rail_Metal` | (0.40, 0.40, 0.42) | balcony/corridor railings |
| `Rail_Solid` | (0.66, 0.64, 0.60) | CHB balustrade |
| `Awning_Steel` | (0.50, 0.48, 0.45) | sidewalk awnings |
| `Awning_Canvas` | (0.62, 0.58, 0.50) | fabric awnings/market |
| `Heritage_Stone` | (0.60, 0.57, 0.50) | Parian stone base |
| `Heritage_Capiz` | (0.78, 0.75, 0.66) | capiz window band |
| `Heritage_Wood` | (0.34, 0.24, 0.16) | heritage mullions/posts |
| `AC_Unit` | (0.74, 0.73, 0.70) | wall/roof AC condensers |
| `Meter_Box` | (0.44, 0.42, 0.38) | utility riser |
| `Gate_Metal` | (0.38, 0.37, 0.36) | compound gates |
| `Shutter_Steel` | (0.48, 0.47, 0.45) | shop roll-up doors |
| `Rebar` | (0.40, 0.30, 0.22) | unfinished stubs |
| `Carport_Shade` | (0.30, 0.34, 0.30) | translucent carport roof |

Signage atlas materials are **not** listed — that is a texture + UV job (master
plan §6.5), scoped separately as the one texturing task.

---

## 8. Prototype plan (Stage 4 of the brief) — proposed, awaiting approval

The brief asks for representative prototypes before city-wide expansion, and to
**wait for approval**. Mapped to the master plan's Tier S/A/B and to real map
sites, here is the proposed first set — **~15 prototypes** that together exercise
every §4 module at least once:

| # | Prototype | Category | Tier | Map site (built context) | Modules it proves |
|---|---|---|---|---|---|
| 1 | Mixed-commercial reference block | **B** | A | Fuente / Univ. Belt | walls, window_bands, balcony, shopfront, awning, wall_ac, utility_riser |
| 2 | Colon party-wall shophouse row (×5 bays) | **A** | A | Colon (Metro corner) | party_wall_bay, punched_windows, awning, signage_band, roof_clutter |
| 3 | Lower-middle residential + compound | **C** | A | Kamputhaw | compound_wall, gate, hip_roof, water_tank_stand |
| 4 | Boarding house + exterior stair | **D** | A | Univ. Belt | punched_windows, balcony×n, exterior_stair, door_recess(parking) |
| 5 | Art-Deco vertical-sign commercial | **E** | A | Colon/Parian | party_wall_bay, stepped parapet, vertical signage |
| 6 | Condo mid-rise family | **F** | A | Fuente | tower_detail, podium_retail, recessed balcony |
| 7 | Capiz heritage house | **K/heritage** | A | Parian | capiz_bay, Heritage_Stone, arcade, tile roof |
| 8 | Barangay chapel | **K** | B | residential barangay | gable, cross finial, bell |
| 9 | Institutional school block + covered court | **L** | A | Univ. Belt | slab walls, ribbon windows, corridor rail, monitor_roof court, gate |
| 10 | Barangay hall / police station | **M** | B | any | walls, window_bands, seal band, flag |
| 11 | Warehouse + loading dock | **N** | A | Port | tall walls, monitor_roof, wide door_recess |
| 12 | Hillside terraced house + retaining wall | **O** | A | Lahug slope | stepped compound_wall, independent plinths, exterior_stair |
| 13 | Neighbourhood market hall | **J** | B | Carbon edge | monitor_roof, open walls, dense awning |
| 14 | Mall variant (entrance + service wall) | **I** | A | Banilad | mall arcade, podium_retail, roof_plant, service wall |
| 15 | IT-Park mid tower (7–15 fl) | **G** | B | IT Park | tower_detail (IT scheme), podium_retail |

**Build/verify loop** (from `banilad-map-build-verify-pipeline` memory): each
prototype is a function in `parts.py` exercised by a tiny standalone builder that
drops instances on a flat test plane, exported and viewed via
`render_preview.py`, **before** any of it touches `build_map.py` or the streamed
tiles. This keeps the ~15 min full-city build out of the iteration loop and lets
each prototype be judged in isolation — the brief's "create representative
building prototypes" as a reviewable set, not a city rebuild.

---

## 9. What happens after approval (the Stage-5 gate)

**Nothing is expanded across the master map until this Bible and the prototype set
are approved.** On approval, the ordered work is:

1. Extract the 12 **[HAVE]** modules into `banilad_map/parts.py` (pure refactor,
   guarded by the existing smoke tests — geometry must be byte-identical).
2. Write the 15 **[NEW]** modules + new materials (§4, §7), each with a preview.
3. Build the ~15 prototypes (§8) on the test plane. **Review checkpoint.**
4. Wire per-district **module sets + families + variant flags** (§5.1) into the
   building loop and the perimeter-block infill generator (master plan §8).
5. Roll district by district (slice order, master plan §2), re-verifying the
   full pipeline and previews each time.

The signage atlas (master plan §6.5) is the one parallel track — it unblocks
categories A/E/J and is the highest visual return, but it is a texture+UV job and
is scoped in the master plan, not here.

---

*End. This document defines the language; it does not build the city. Approve or
redirect §§4–8 before `parts.py` is written.*
