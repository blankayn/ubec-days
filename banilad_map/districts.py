"""Districts, shared by the map and slum builders.

Two things live here. The informal-settlement rectangles (`SLUM_DISTRICTS`,
below) are keep-out zones for the procedural infill. `CITY_DISTRICTS` is the
wider table from CITY_MASTER_PLAN.md section 5 -- the mechanism that stops
Ayala, Colon and Banilad sharing one look.

A district is a band in Blender y. The master plan states each district's
extent as a range of Godot z, and Blender y is its negation, so a district
listed at Godot z +4000..+4500 is Blender y -4500..-4000. The city runs
essentially north-south along one corridor, so bands are enough; `x` is
optional and only given where a district is genuinely narrower than the map.

Each row carries the things that actually differ between districts:

* `walls` / `roofs` -- the palette entries the buildings there draw from, so
  Colon can run to painted commercial stock while Kamputhaw runs to plain
  render behind walls.
* `tint` -- how far the per-building colour jitter is allowed to stray. Formal
  business districts are built to one spec and should stay tight; an
  organically grown district should not.
* `props` -- multiplier on tree and vehicle density.
* `shopfront` -- how much of the frontage gets the ground-floor shop course,
  independent of what OSM happens to have tagged. OSM's shop coverage in Cebu
  is very uneven, and Colon being untagged does not make it residential.
"""

# ---------------------------------------------------------------------------
# Informal settlements
#
# `tools/build_slum.py` places the houses. `banilad_map/build_map.py` has to
# keep procedural infill, trees and power poles out of the same rectangles, or
# the 13 m lattice grows boxes straight through the settlement and street
# furniture plants trees inside the huts.
#
# The two scripts used to carry separate copies of the same five rects, each
# with a comment warning that changing one meant changing the other. This is
# that one definition.
#
# Bounds are Blender XY metres, `(x0, y0, x1, y1)`; Godot z is the negation of
# y. `entry` is the alley mouth and `heading` its bearing in degrees. `kit` is
# how often a front bay spends a real house-kit module instead of a plain box
# -- the flagship is fully kitted, the outer sitios only sometimes.
#
# Vehicles are deliberately *not* excluded from these rects: real roads run
# through Kamagayan and Lorega and the houses keep 7 m off any carriageway, so
# traffic through a barangay is correct rather than a bug.
# ---------------------------------------------------------------------------

SLUM_DISTRICTS = [
    {"name": "Sitio Banilad",   "bounds": (170.0, 505.0, 265.0, 585.0),
     "entry": (172.0, 546.0),  "heading": 8.0,  "kit": 1.00},
    {"name": "Sitio Talamban",  "bounds": (40.0, 715.0, 130.0, 805.0),
     "entry": (44.0, 758.0),   "heading": 4.0,  "kit": 0.45},
    {"name": "Sitio Kamagayan", "bounds": (-245.0, 640.0, -155.0, 730.0),
     "entry": (-241.0, 682.0), "heading": -6.0, "kit": 0.35},
    {"name": "Sitio Mabolo",    "bounds": (205.0, 655.0, 295.0, 745.0),
     "entry": (209.0, 698.0),  "heading": 12.0, "kit": 0.40},
    {"name": "Sitio Lorega",    "bounds": (-380.0, 505.0, -290.0, 595.0),
     "entry": (-376.0, 548.0), "heading": -3.0, "kit": 0.35},
]

# Infill, trees and poles stay this far clear of a district edge so they do not
# crowd the alley mouths.
SLUM_PAD = 8.0


def slum_bounds():
    """Just the rectangles, for the keep-out tests in `build_map.py`."""
    return [d["bounds"] for d in SLUM_DISTRICTS]


def in_rect(x, y, rect, pad=0.0):
    return (rect[0] - pad <= x <= rect[2] + pad
            and rect[1] - pad <= y <= rect[3] + pad)


def in_any_slum(x, y, pad=0.0):
    return any(in_rect(x, y, d["bounds"], pad) for d in SLUM_DISTRICTS)


# ---------------------------------------------------------------------------
# City districts (CITY_MASTER_PLAN.md section 5)
#
# `y` is the Blender band, i.e. the negation of the master plan's Godot z
# range, low value first. Bands are listed north (Banilad, large +y) to south
# (the Port, large -y) and are checked in order, so where two overlap the
# earlier row wins -- Parian and Carbon genuinely interleave with the Port on a
# pure y test and the finer-grained one has to be listed first.
#
# Palettes name entries in build_map.py's PALETTE. A district may repeat an
# entry to weight it: the pick is a plain index into the list, so listing
# "Wall_0" twice makes it twice as likely.
# ---------------------------------------------------------------------------

_GREY_WALLS = ["Wall_0", "Wall_1", "Wall_2", "Wall_3", "Wall_4", "Wall_5",
               "Wall_6"]

# Roof mix measured off the reference aerial of the barangay behind UC: faded
# galvanised sheet and oxidised red in roughly equal share, everything else
# occasional. Repeats set the weighting.
_GALV_ROOFS = ["Roof_Rust_0", "Roof_Rust_1", "Roof_Rust_2",
               "Roof_Rust_0", "Roof_Rust_1",
               "Roof_Galv_0", "Roof_Galv_1", "Roof_Galv_2", "Roof_Galv_3",
               "Roof_Galv_0", "Roof_Galv_1",
               "Roof_Weathered", "Roof_Weathered"]

CITY_DISTRICTS = [
    {
        "name": "Banilad",
        "y": (200.0, 1170.0),
        # Suburban commercial: painted render, mixed sheet and tile roofs.
        "walls": _GREY_WALLS + ["Wall_Concrete_0", "Wall_Concrete_2"],
        "roofs": _GALV_ROOFS + ["Roof_Clay", "Roof_Paint_Blue",
                                "Roof_Paint_Green"],
        "tint": 1.0, "props": 1.0, "shopfront": 0.30,
    },
    {
        "name": "Cebu IT Park",
        "y": (-800.0, -200.0),
        # Glass towers and pale concrete; no rusted sheet anywhere near it.
        "walls": ["Tower_White", "Tower_Pale", "Tower_Concrete",
                  "Wall_Concrete_2", "Wall_Concrete_0"],
        "roofs": ["Roof_Deck", "Roof_Flat", "Roof_Galv_2"],
        "walls_mid": ["Tower_White", "Tower_Pale", "Tower_Concrete"],
        "tint": 0.5, "props": 1.3, "shopfront": 0.20,
    },
    {
        "name": "Lahug / Camputhaw",
        "y": (-1400.0, -700.0),
        "walls": _GREY_WALLS + ["Wall_Concrete_0", "Wall_Concrete_1"],
        "roofs": _GALV_ROOFS + ["Roof_Flat", "Roof_Paint_Blue"],
        "tint": 1.0, "props": 1.0, "shopfront": 0.35,
    },
    {
        "name": "Cebu Business Park",
        "y": (-2000.0, -1400.0),
        # Manicured and corporate: built to one spec, so the jitter is tight.
        "walls": ["Tower_White", "Tower_Pale", "Tower_Concrete",
                  "Wall_Concrete_2"],
        "roofs": ["Roof_Deck", "Roof_Flat"],
        "walls_mid": ["Tower_White", "Tower_Pale", "Wall_Concrete_2"],
        "tint": 0.45, "props": 1.6, "shopfront": 0.25,
    },
    {
        "name": "Kamputhaw / Capitol",
        "y": (-2400.0, -1900.0),
        # Walled compounds and mature trees; plain render, little signage.
        "walls": _GREY_WALLS + ["Wall_0", "Wall_4"],
        "roofs": _GALV_ROOFS + ["Roof_Clay", "Roof_Clay"],
        "tint": 1.1, "props": 1.8, "shopfront": 0.10,
    },
    {
        "name": "Fuente District",
        "y": (-2900.0, -2400.0),
        # Dense mid-rise, hotels and hospitals around the rotunda.
        "walls": _GREY_WALLS + ["Wall_Concrete_0", "Wall_Concrete_1",
                                "Tower_Pale"],
        "roofs": _GALV_ROOFS + ["Roof_Flat", "Roof_Deck"],
        "walls_mid": ["Wall_Concrete_0", "Wall_Concrete_1", "Tower_Pale"],
        "tint": 1.2, "props": 1.4, "shopfront": 0.70,
    },
    {
        "name": "University Belt",
        "y": (-3900.0, -2900.0),
        # Institutional slabs among sari-sari frontage.
        "walls": _GREY_WALLS + ["Wall_Concrete_0", "Wall_Concrete_2"],
        "roofs": _GALV_ROOFS + ["Roof_Flat"],
        "tint": 1.2, "props": 1.2, "shopfront": 0.65,
    },
    {
        "name": "Parian / Heritage",
        # The Basilica / Magellan's Cross / Plaza Independencia pocket, not the
        # whole southern end. The master plan gives Parian and Colon
        # overlapping z ranges because they genuinely abut, so Parian has to be
        # bounded in x as well -- given a wide x range it is listed first and
        # swallows Colon entirely, which is how this was first written.
        "y": (-4780.0, -4600.0),
        "x": (-1120.0, -880.0),
        # Colonial stone and wood, tile roofs, narrow lanes.
        "walls": ["Wall_0", "Wall_2", "Wall_4", "Wall_Concrete_2"],
        "roofs": ["Roof_Clay", "Roof_Clay", "Roof_Rust_0", "Roof_Weathered"],
        "tint": 1.0, "props": 1.1, "shopfront": 0.35,
    },
    {
        "name": "Carbon Market",
        "y": (-4750.0, -4500.0),
        "x": (-1700.0, -1150.0),
        # Tarpaulin and corrugated GI over everything.
        "walls": _GREY_WALLS + ["Wall_3", "Wall_5", "Wall_6"],
        "roofs": _GALV_ROOFS + ["Roof_Rust_0", "Roof_Rust_1", "Roof_Rust_2"],
        "tint": 1.5, "props": 0.7, "shopfront": 0.85,
    },
    {
        "name": "Downtown Colon",
        "y": (-4500.0, -4000.0),
        # The signage canyon. Painted commercial stock, near-total shopfront
        # coverage, and the widest colour spread in the city -- Colon is a
        # century of independent repaints, not one scheme.
        "walls": _GREY_WALLS + ["Wall_Concrete_0", "Wall_Concrete_1",
                                "Wall_Concrete_2"],
        "roofs": _GALV_ROOFS + ["Roof_Flat", "Roof_Paint_Blue",
                                "Roof_Paint_Green"],
        "walls_mid": ["Wall_Concrete_0", "Wall_Concrete_1", "Wall_Concrete_2",
                      "Wall_0", "Wall_2"],
        "tint": 1.6, "props": 1.3, "shopfront": 0.90,
    },
    {
        "name": "Port District",
        "y": (-4800.0, -4400.0),
        # Warehouses and sheds: long sheet roofs, almost no retail frontage.
        "walls": ["Wall_Concrete_0", "Wall_Concrete_1", "Wall_3", "Wall_6"],
        "roofs": ["Roof_Galv_1", "Roof_Galv_3", "Roof_Rust_2", "Roof_Flat"],
        "walls_mid": ["Wall_Concrete_1", "Wall_3", "Wall_6"],
        "tint": 1.1, "props": 0.6, "shopfront": 0.08,
    },
]

# Anywhere the bands do not cover. Deliberately the old global behaviour, so
# unclassified ground looks exactly as it did before districts existed.
DEFAULT_DISTRICT = {
    "name": "Unclassified",
    "walls": _GREY_WALLS,
    "roofs": _GALV_ROOFS + ["Roof_Clay", "Roof_Paint_Blue",
                            "Roof_Paint_Green"],
    "tint": 1.0, "props": 1.0, "shopfront": 0.25,
}


def district_at(x, y):
    """The district covering a Blender XY point, or DEFAULT_DISTRICT."""
    for d in CITY_DISTRICTS:
        y0, y1 = d["y"]
        if not (y0 <= y <= y1):
            continue
        xr = d.get("x")
        if xr is not None and not (xr[0] <= x <= xr[1]):
            continue
        return d
    return DEFAULT_DISTRICT
