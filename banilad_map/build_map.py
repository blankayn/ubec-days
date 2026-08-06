"""
Build a detailed 3D city of Banilad, Cebu City from OpenStreetMap data.

Rather than extruding flat-topped boxes, this generates the forms that actually
make up the district: hip-roofed low-rise with terracotta and painted metal
roofs, parapeted commercial blocks with window bands, glazed towers, kerbed
sidewalks, painted road markings, street lighting, power poles, trees and
parked vehicles.

Run headlessly:
    blender --background --python build_map.py
"""

import json
import math
import pathlib
import random
import sys

import bpy

HERE = pathlib.Path(__file__).parent
# Blender's `-P` does not put the script's own directory on sys.path, so the
# shared pipeline modules sitting beside this file are not importable without
# help. Everything below the insert is a deliberately late import.
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import terrain  # noqa: E402
from districts import SLUM_PAD, district_at, in_any_slum  # noqa: E402
import landmarks  # noqa: E402
from geo import project  # noqa: E402

PROJECT = HERE.parent
OSM_FILE = HERE / "banilad_osm.json"
OUT_DIR = HERE / "export"

# The road graph is derived from OSM, not from the .blend, so it is written
# straight to the shipped location rather than staged through export/ and
# re-emitted by prep_godot.py like the meshes are.
ROAD_GRAPH_OUT = PROJECT / "assets" / "maps" / "cebu_road_graph.json"

# The ground plane is derived from the data, not hand-maintained.
#
# It used to be GROUND_HALF = 1250.0, and it had already fallen behind the map:
# `out geom` returns whole ways that merely clip the Overpass bbox, so road
# geometry reached x = -1432 while the plane stopped at 1250 -- tarmac hanging
# over void at the western edge. Deriving it means the plane cannot lag the
# extent again the next time the bbox moves.
GROUND_MARGIN = 60.0    # clear of kerbs, markings and street furniture
GROUND_QUANTUM = 50.0   # round up, so small data edits do not resize the world

# Streaming tiles.
#
# 250 m rather than 500: the player is on foot as often as driving, it matches
# the real block size in Cebu Business Park, and a tile stays small enough to
# rebuild and inspect on its own. Tiles are generated, not authored, so a few
# hundred of them costs nothing.
TILE_SIZE = 250.0
TILES_DIR = PROJECT / "assets" / "maps" / "tiles"

# Anything at least this tall also goes into the always-resident skyline mesh:
# silhouettes only, no props, no markings, no glazing. Without it the IT Park
# towers pop in at the streaming radius and the city has no readable horizon.
SKYLINE_MIN_HEIGHT = 25.0

# Ground mesh cell size. The ground is always-resident (it ships in
# banilad_base.glb and never streams out), so this trades fidelity against a
# mesh that is never unloaded. At 100 m the grid still meets the carriageways
# cleanly, because ground height near a road is interpolated almost entirely
# from that road.
GROUND_CELL = 100.0

# How far a building's walls carry below its lowest ground corner, so a slope
# never opens a gap under a facade.
PLINTH_MARGIN = 0.6

# Mean sea level IS the datum: elevation.json is metres above it, so the sea
# surface sits at exactly zero and needs no offset of its own.
SEA_LEVEL = 0.0

LEVEL_HEIGHT = 3.3
SEED = 20260731

DEFAULT_HEIGHTS = {
    "yes": 6.0, "house": 4.5, "residential": 7.0, "apartments": 18.0,
    "commercial": 14.0, "retail": 9.0, "office": 20.0, "hotel": 22.0,
    "university": 14.0, "school": 10.0, "warehouse": 8.0, "industrial": 9.0,
    "church": 12.0, "roof": 3.5, "tent": 3.0, "terrace": 6.0,
    "construction": 8.0, "garage": 3.0, "hut": 3.0,
}

ROAD_WIDTHS = {
    "primary": 16.0, "primary_link": 8.0,
    "secondary": 13.0, "secondary_link": 8.0,
    "tertiary": 10.0, "tertiary_link": 7.0, "unclassified": 7.5,
    "residential": 6.5, "service": 4.0, "living_street": 6.0,
    "pedestrian": 5.0, "footway": 2.0, "path": 1.6, "steps": 1.6,
    "track": 3.0,
    # Not a street: the go-kart circuit off Cuenco. Listed so it stops falling
    # through to the 5.0 m default, and kept out of MAJOR_ROADS so traffic
    # never routes onto it.
    "raceway": 6.0,
}

# Lane and speed fallbacks for the road graph, used only where OSM is silent.
# Cebu tags `lanes` on 236 of 1351 highway ways and `maxspeed` on 167, so these
# carry most of the network. They do not affect geometry -- ROAD_WIDTHS still
# owns the ribbon width.
DEFAULT_LANES = {
    "primary": 4, "secondary": 2, "secondary_link": 1,
    "tertiary": 2, "tertiary_link": 1, "unclassified": 2,
    "residential": 2, "service": 1, "living_street": 1, "track": 1,
    "pedestrian": 0, "footway": 0, "path": 0, "steps": 0,
}
DEFAULT_SPEEDS = {
    "primary": 60, "secondary": 50, "secondary_link": 40,
    "tertiary": 40, "tertiary_link": 30, "unclassified": 30,
    "residential": 30, "service": 20, "living_street": 20, "track": 20,
    "pedestrian": 0, "footway": 0, "path": 0, "steps": 0,
}

# Roads that must not be built at all.
#
# ERA: this map is circa-2019 Cebu, before the Cebu BRT works (see the header
# of overpass_query.txt). Current OSM carries 14 `highway=busway` ways named
# "Cebu Bus Rapid Transit" running about 2.5 km down the Osmena corridor. Left
# in they fall through ROAD_WIDTHS to the 5 m default and lay a phantom
# collidable lane along the boulevard -- and they are the single biggest
# era-sensitive feature the plan flagged for override.
EXCLUDED_ROAD_CLASSES = {"busway"}

# primary_link was missing here and from ROAD_WIDTHS: a ramp off a primary was
# being built 5.0 m wide as a *minor* road, with no sidewalks and no markings.
MAJOR_ROADS = {"primary", "primary_link", "secondary", "secondary_link",
               "tertiary", "tertiary_link"}
FOOT_ROADS = {"footway", "path", "steps", "pedestrian"}
GREEN_TAGS = {
    "grass", "forest", "meadow", "village_green", "recreation_ground",
    "park", "garden", "pitch", "golf_course", "cemetery", "farmland",
}

# Zoned districts that must not receive procedural shanty infill. This is what
# keeps houses out of the mall car park and out of the IT Park towers' plazas,
# both of which are mapped as commercial landuse.
NOFILL_TAGS = {
    "commercial", "retail", "industrial", "military", "construction",
    "brownfield", "railway", "quarry",
}

# Draw order. Overlapping features inside a layer are separated by layer_z.
Z_GROUND = 0.0
Z_BUILDING_BASE = 0.0
Z_LANDUSE = 0.02
Z_WATER = -0.60
Z_FOOTWAY = 0.05
Z_ROAD_MINOR = 0.09
Z_ROAD_MAJOR = 0.13
Z_MARKING = 0.17
Z_SIDEWALK = 0.15

# Physics reads one flat plane instead of the layered visual ribbons (see
# Roads_Collision below). Sitting it on the major-road surface keeps cars level
# with the tarmac they mostly drive on: on minor roads they float at most 4 cm,
# on major roads they sink at most 3 cm, neither visible at vehicle scale.
Z_ROAD_COLLISION = Z_ROAD_MAJOR

LAYER_STEP = 0.002
LAYER_SLOTS = 16

SIDEWALK_WIDTH = 2.6
KERB_HEIGHT = 0.15

# Colours are the intended on-screen sRGB values. build_materials converts them
# to linear for Blender; prep_godot.py converts them again for Godot's importer.
PALETTE = {
    "Ground": (0.33, 0.32, 0.28),
    "Landuse_Green": (0.28, 0.42, 0.22),
    "Landuse_Urban": (0.36, 0.35, 0.33),
    "Water": (0.14, 0.30, 0.40),
    "Road_Major": (0.22, 0.22, 0.24),
    "Road_Minor": (0.28, 0.28, 0.30),
    "Footway": (0.46, 0.44, 0.41),
    "Sidewalk": (0.52, 0.51, 0.48),
    "Marking_White": (0.86, 0.86, 0.83),
    "Marking_Yellow": (0.80, 0.66, 0.20),

    # Low-rise walls. The aerial shows mostly unpainted or long-faded hollow
    # block, so these run grey and weathered rather than fresh pastel.
    "Wall_0": (0.72, 0.70, 0.65),
    "Wall_1": (0.62, 0.61, 0.58),
    "Wall_2": (0.68, 0.65, 0.58),
    "Wall_3": (0.55, 0.55, 0.53),
    "Wall_4": (0.65, 0.64, 0.62),
    "Wall_5": (0.58, 0.57, 0.52),
    "Wall_6": (0.50, 0.50, 0.48),
    "Wall_Concrete_0": (0.64, 0.63, 0.60),
    "Wall_Concrete_1": (0.56, 0.56, 0.54),
    "Wall_Concrete_2": (0.70, 0.70, 0.68),

    # Tower cladding. Read off the reference aerial of IT Park: the district is
    # white and pale grey concrete with charcoal glass towers among it. There is
    # essentially no saturated blue there, so these stay neutral -- a cool tint
    # in the glazing was what made the whole skyline read blue.
    "Tower_White": (0.81, 0.81, 0.80),
    "Tower_Pale": (0.72, 0.72, 0.71),
    "Tower_Concrete": (0.62, 0.62, 0.60),
    "Tower_Steel": (0.46, 0.47, 0.49),
    "Tower_Graphite": (0.30, 0.31, 0.33),
    "Tower_Charcoal": (0.19, 0.20, 0.22),
    # Glazing, paired with the cladding below so the banding always contrasts.
    "Tower_Glass_Dark": (0.21, 0.22, 0.24),   # punched windows on pale concrete
    "Tower_Glass_Mid": (0.35, 0.36, 0.38),
    "Tower_Glass_Pale": (0.63, 0.64, 0.65),   # lit glazing on charcoal cladding

    # Roofs. The dense barangay fabric is roughly half faded galvanised sheet
    # and half oxidised red, with only occasional painted colour -- the bright
    # terracotta-and-teal mix this used to ship read as a map key, not a city.
    "Roof_Rust_0": (0.45, 0.24, 0.18),
    "Roof_Rust_1": (0.52, 0.30, 0.22),
    "Roof_Rust_2": (0.38, 0.21, 0.17),
    "Roof_Galv_0": (0.56, 0.56, 0.54),
    "Roof_Galv_1": (0.47, 0.48, 0.48),
    "Roof_Galv_2": (0.63, 0.62, 0.59),
    "Roof_Galv_3": (0.52, 0.53, 0.52),
    "Roof_Weathered": (0.66, 0.64, 0.60),
    "Roof_Paint_Blue": (0.31, 0.39, 0.45),
    "Roof_Paint_Green": (0.30, 0.38, 0.31),
    "Roof_Clay": (0.55, 0.30, 0.21),
    "Roof_Flat": (0.46, 0.45, 0.43),
    "Roof_Deck": (0.40, 0.40, 0.39),

    "Window": (0.12, 0.16, 0.20),
    # Ground-floor shopfront: the dark recessed opening, then the sign fascia
    # above it. The sign colours are the faded primaries a Philippine commercial
    # street actually runs on -- sun-bleached rather than saturated, so they add
    # incident rather than turning the street into bunting.
    "Shopfront_Glass": (0.15, 0.16, 0.17),
    "Roof_Tank": (0.50, 0.49, 0.46),

    # --- Hand-authored landmarks (landmarks.py) --------------------------
    # Fort San Pedro: coral-stone walls, weathered grey-buff rather than the
    # warm sandstone a European fort would be.
    "Fort_Stone": (0.62, 0.59, 0.51),
    "Fort_Shadow": (0.42, 0.40, 0.35),
    "Fort_Court": (0.55, 0.52, 0.45),
    # Fuente Osmena and the Colon obelisk: painted concrete, near-white.
    "Fountain_Stone": (0.78, 0.77, 0.73),
    # Magellan's Cross Pavilion: cream render, terracotta tile, dark hardwood.
    "Pavilion_Wall": (0.80, 0.76, 0.66),
    "Pavilion_Roof": (0.52, 0.28, 0.19),
    "Cross_Timber": (0.31, 0.21, 0.14),
    # Basilica del Santo Nino: the belfry is dark weathered coral stone with
    # paler dressed trim, which is what makes it read against the sky.
    "Church_Stone": (0.55, 0.52, 0.46),
    "Church_Trim": (0.72, 0.70, 0.64),
    "Church_Opening": (0.14, 0.13, 0.12),
    "Church_Roof": (0.38, 0.36, 0.34),
    # Carbon Market: painted hall, galvanised roof, and the tarpaulin colours
    # the stall field actually runs on -- sun-faded, not saturated.
    "Market_Wall": (0.72, 0.70, 0.64),
    "Market_Roof": (0.54, 0.54, 0.52),
    "Market_Crate": (0.46, 0.35, 0.22),
    "Canopy_Blue": (0.26, 0.38, 0.55),
    "Canopy_Red": (0.60, 0.26, 0.22),
    "Canopy_Green": (0.28, 0.45, 0.31),
    "Canopy_Orange": (0.72, 0.47, 0.20),
    "Canopy_White": (0.78, 0.77, 0.72),
    # Cebu Port: warehouse sheds, container stacks, gantry cranes.
    "Warehouse_Wall": (0.66, 0.66, 0.63),
    "Warehouse_Roof": (0.50, 0.51, 0.51),
    "Container_Red": (0.52, 0.24, 0.20),
    "Container_Blue": (0.20, 0.32, 0.46),
    "Container_Green": (0.24, 0.40, 0.28),
    "Container_Grey": (0.55, 0.55, 0.53),
    "Crane_Steel": (0.72, 0.66, 0.32),
    # Ayala Center Cebu.
    "Ayala_Wall": (0.76, 0.74, 0.70),
    "Ayala_Glass": (0.30, 0.34, 0.38),
    "Ayala_Rail": (0.66, 0.64, 0.60),
    # Metro Colon: pale cream concrete with almost no glazing above the arcade,
    # because the upper facade is a billboard wall.
    "Metro_Wall": (0.80, 0.78, 0.71),
    "Metro_Trim": (0.86, 0.84, 0.78),
    "Metro_Reveal": (0.26, 0.25, 0.23),
    # The chamfered corner block opposite: grey concrete, dark banded glazing.
    "Corner_Wall": (0.58, 0.57, 0.55),
    "Corner_Band": (0.22, 0.23, 0.25),
    # Vinyl banner stock. Faded rather than saturated -- these are printed
    # sheets two years into tropical sun, not fresh ink.
    "Banner_Green": (0.29, 0.44, 0.35),
    "Banner_Blue": (0.24, 0.36, 0.54),
    "Banner_Red": (0.61, 0.27, 0.24),
    "Banner_Yellow": (0.76, 0.65, 0.26),
    # Must NOT match Metro_Wall (0.80, 0.78, 0.71). A cream banner on cream
    # concrete is geometry that renders as nothing -- it was authored at almost
    # exactly the wall colour first and simply could not be seen.
    "Banner_Cream": (0.58, 0.54, 0.47),
    "Sign_Red": (0.56, 0.22, 0.19),
    "Sign_Blue": (0.20, 0.34, 0.50),
    "Sign_Yellow": (0.72, 0.60, 0.22),
    "Sign_Green": (0.24, 0.42, 0.30),
    "Sign_White": (0.76, 0.75, 0.71),
    "Pole": (0.34, 0.34, 0.33),
    "Lamp": (0.85, 0.82, 0.66),
    "Tree_Trunk": (0.26, 0.19, 0.13),
    "Tree_Canopy_0": (0.20, 0.36, 0.16),
    "Tree_Canopy_1": (0.26, 0.42, 0.20),
    "Tree_Canopy_2": (0.16, 0.30, 0.14),
    "Car_0": (0.72, 0.72, 0.70),
    "Car_1": (0.55, 0.13, 0.13),
    "Car_2": (0.16, 0.28, 0.46),
    "Car_3": (0.20, 0.20, 0.22),
    "Car_4": (0.66, 0.62, 0.18),

    # Hand-authored landmarks. These two are the only buildings the player is
    # meant to recognise, so they get their own palette instead of the
    # procedural wall/roof rotations.
    "Mall_Wall": (0.86, 0.82, 0.72),        # cream stucco
    "Mall_Trim": (0.93, 0.91, 0.85),        # cornice and pier caps
    "Mall_Arcade": (0.34, 0.30, 0.26),      # shadow inside the arch openings
    # Clay tile. Three tones so the complex does not read as one flat slab of
    # colour, and pulled back from the old orange so it sits with the muted
    # galvanised roofs around it instead of glowing against them.
    "Mall_Roof": (0.56, 0.29, 0.19),
    "Mall_Roof_Alt": (0.50, 0.27, 0.19),
    "Mall_Roof_Dark": (0.44, 0.23, 0.17),   # cineplex block, shaded slopes
    "Mall_Walkway": (0.74, 0.37, 0.20),     # covered walkway spine roof
    "Lot_Asphalt": (0.27, 0.26, 0.25),
    "Lot_Stripe": (0.78, 0.77, 0.71),

    "UC_Band": (0.85, 0.85, 0.83),          # pale concrete structural bands
    # Neutral grey-blue, not saturated: on the reference the campus reads as a
    # pale concrete block with dark glazing, and a brighter blue turned the
    # banding into painted stripes.
    "UC_Glass": (0.31, 0.36, 0.41),         # bowed curtain wall
    "UC_Glass_Dark": (0.22, 0.26, 0.30),    # courtyard-facing glazing
    "UC_Podium": (0.76, 0.75, 0.71),
    "UC_Deck": (0.44, 0.44, 0.42),

    # Cebu IT Park. Office towers all share the base/crown/plant treatment;
    # the Central Bloc complex gets its own cladding colours.
    "Tower_Base": (0.33, 0.33, 0.36),       # darker podium storeys
    "Tower_Crown": (0.28, 0.30, 0.35),      # capping band under the parapet
    "Tower_Plant": (0.38, 0.38, 0.40),      # rooftop plant and lift overruns
    "Bloc_Podium": (0.47, 0.37, 0.39),      # Ayala Malls mauve cladding
    "Bloc_Sign": (0.86, 0.63, 0.28),        # lit signage band
    "Bloc_Tower_Dark": (0.21, 0.23, 0.27),  # Corporate Center One
    "Bloc_Tower_Light": (0.66, 0.67, 0.68), # Corporate Center Two
    "Bloc_Hotel": (0.63, 0.59, 0.55),       # Seda
}

SIGN_COLOURS = ["Sign_Red", "Sign_Blue", "Sign_Yellow", "Sign_Green",
                "Sign_White"]

# OSM tags that mean "this building has a shop in the bottom of it". Anything
# tagged commercial, retail or with a shop/amenity key gets the shopfront
# course; a plain `building=house` does not.
COMMERCIAL_BUILDING_VALUES = {
    "commercial", "retail", "shop", "supermarket", "kiosk", "hotel",
    "restaurant", "office", "mall", "warehouse", "industrial", "public",
}
COMMERCIAL_KEYS = ("shop", "amenity", "office", "tourism", "craft")


def is_commercial(tags):
    if tags.get("building") in COMMERCIAL_BUILDING_VALUES:
        return True
    if tags.get("building:use") in COMMERCIAL_BUILDING_VALUES:
        return True
    return any(k in tags for k in COMMERCIAL_KEYS)


def wants_shopfront(tags, district, oid):
    """Whether this building gets the ground-floor shop course.

    A tagged shop always does. Everything else falls back to the district rate,
    because OSM's retail coverage in Cebu is very thin and uneven -- Colon is
    a solid wall of shops on the ground and almost none of it is tagged, so
    trusting the tags alone would leave the signage canyon looking residential.
    """
    if is_commercial(tags):
        return True
    return hash_unit(oid * 2246822519 + 7) < district["shopfront"]


# Low-rise wall and pitched-roof palettes now live per district in
# districts.py; DEFAULT_DISTRICT carries what the global WALL_LOW and
# ROOF_PITCHED lists used to hold, so unclassified ground looks exactly as it
# did. They are not duplicated here, for the same reason the slum rectangles
# are not: two copies of one list is how they drift apart.
WALL_MID = ["Wall_Concrete_0", "Wall_Concrete_1", "Wall_Concrete_2"]

# Tower cladding paired with its glazing. Picking the two independently let a
# concrete tower end up with concrete-coloured "glass", which erased the
# banding; keeping them as schemes guarantees the curtain wall reads.
# Weighted the way the reference reads: mostly pale concrete with dark punched
# windows, charcoal glass towers standing among them, mid greys in between.
TOWER_SCHEMES = [
    ("Tower_White", "Tower_Glass_Dark"),
    ("Tower_Charcoal", "Tower_Glass_Pale"),
    ("Tower_Pale", "Tower_Glass_Dark"),
    ("Tower_Concrete", "Tower_Glass_Dark"),
    ("Tower_White", "Tower_Glass_Mid"),
    ("Tower_Graphite", "Tower_Glass_Pale"),
    ("Tower_Pale", "Tower_Glass_Mid"),
    ("Tower_Steel", "Tower_Glass_Dark"),
]

# Towers identifiable by label in the reference aerial of IT Park, so their
# cladding is set rather than left to the scheme rotation. Everything not
# listed here keeps the rotation -- guessing at the rest would be inventing
# detail, not adding accuracy.
TOWER_SCHEME_BY_NAME = {
    "Skyrise 1": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Skyrise 2": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Skyrise 3": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Skyrise 3B": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Skyrise 4": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Avida Towers Cebu": ("Tower_White", "Tower_Glass_Mid"),
    "Metro Park Hotel": ("Tower_White", "Tower_Glass_Mid"),

    # Cebu IT Park (Asiatown), Lahug. This is a BPO campus built in one go, so
    # unlike the rest of the city its towers really are a matched set of glass
    # curtain wall over pale concrete. Left to the oid rotation they drew
    # rusted-sheet and painted-render schemes at random, which is the one thing
    # IT Park does not look like.
    #
    # NOTE these are IT Park, NOT Ayala Center -- two separate districts 1.4 km
    # apart. Ayala Malls Central Bloc is the confusing one: it is an Ayala mall
    # standing in IT Park, and has nothing to do with Ayala Center Cebu.
    "eBloc 1 Tower": ("Tower_Pale", "Tower_Glass_Dark"),
    "eBloc 2 Tower": ("Tower_White", "Tower_Glass_Dark"),
    "eBloc 3 Tower": ("Tower_Pale", "Tower_Glass_Mid"),
    "eBloc 4 Tower": ("Tower_White", "Tower_Glass_Dark"),
    "TGU Tower": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "HM Tower": ("Tower_Pale", "Tower_Glass_Dark"),
    "Aegis": ("Tower_White", "Tower_Glass_Mid"),
    "i2": ("Tower_Pale", "Tower_Glass_Dark"),
    "Calyx Centre": ("Tower_White", "Tower_Glass_Mid"),
    "Filinvest Cyberzone Cebu Tower 1": ("Tower_Pale", "Tower_Glass_Dark"),
    "Filinvest Cyberzone Cebu Tower 3 & 4": ("Tower_Charcoal", "Tower_Glass_Pale"),
    "Central Bloc Corporate Center One": ("Tower_White", "Tower_Glass_Dark"),
    "Central Bloc Corporate Center Two": ("Tower_White", "Tower_Glass_Dark"),
    "Avída Towers Riala": ("Tower_Pale", "Tower_Glass_Mid"),
}

CAR_COLOURS = ["Car_0", "Car_1", "Car_2", "Car_3", "Car_4"]
CANOPY_COLOURS = ["Tree_Canopy_0", "Tree_Canopy_1", "Tree_Canopy_2"]

# A pitched roof only suits house-and-shophouse scale. Big commercial sheds
# such as Gaisano are low but wide, and in reality carry flat or very shallow
# roofs, so they are excluded by footprint area rather than by height alone.
PITCHED_ROOF_MAX = 11.0
PITCHED_ROOF_MAX_AREA = 700.0

# OpenStreetMap only maps a fraction of Banilad's houses, which leaves most
# blocks as bare ground. Infill fills the gaps with small hip-roofed dwellings
# so the density reads like the real district. Bounds are the playable core.
INFILL_BOUNDS = (-720.0, -120.0, 720.0, 1060.0)
INFILL_SPACING = 13.0
INFILL_LIMIT = 3200
INFILL_ROAD_CLEARANCE = 4.0     # metres beyond the carriageway edge
INFILL_ROAD_MAX_DISTANCE = 60.0  # houses cluster along streets
INFILL_BUILDING_CLEARANCE = 7.0
INFILL_WATER_CLEARANCE = 8.0

# The informal-settlement districts are authored separately from the house kit
# by `tools/build_slum.py` and instanced over the map by `banilad_city.gd`.
# Nothing here draws them, but without the keep-out the lattice would grow 3200
# boxes straight through the settlement and street furniture would plant trees
# and poles inside the huts -- so infill and props test against the same rects.
#
# Both scripts now read one definition from `districts.py`. SLUM_PAD is the
# margin that keeps procedural houses off the alley mouths.


def log(msg):
    print("[city] {:s}".format(msg))
    sys.stdout.flush()


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

def way_points(el):
    geom = el.get("geometry")
    if not geom:
        return []
    return [project(p["lat"], p["lon"]) for p in geom if p]


def ground_half_extent(ways):
    """Half-width of a ground plane that covers every projected way."""
    reach = 0.0
    for el in ways:
        for p in el.get("geometry") or []:
            x, y = project(p["lat"], p["lon"])
            reach = max(reach, abs(x), abs(y))
    if reach <= 0.0:
        return 1250.0
    return math.ceil((reach + GROUND_MARGIN) / GROUND_QUANTUM) * GROUND_QUANTUM


# ---------------------------------------------------------------------------
# Road graph
#
# The mesh builder resolves every way into a centreline and a width and then
# throws everything else away -- `lanes` only ever widened a ribbon, and
# `oneway`, `name`, `junction` and all node tags were never read at all. Traffic
# (Phase 6) and pedestrians (Phase 7) would otherwise have to re-derive a lane
# network from triangle soup, which is lossy and miserable.
#
# So the same OSM pass also emits assets/maps/cebu_road_graph.json:
#
#   nodes  junctions and way ends, with traffic_signals / crossing / stop flags
#   edges  the run of road between two nodes, with class, name, width, lane
#          count, one-way direction, roundabout flag and speed
#
# Consumers derive what they need from the edge geometry:
#   lane centreline  = edge +/- (lane_index - (lanes - 1) / 2) * lane_width
#   sidewalk centre  = edge +/- (width / 2 + 1.3) m   <- the offset the kerbs
#                                                        below are built at, so
#                                                        a walker is guaranteed
#                                                        to be on the sidewalk
# ---------------------------------------------------------------------------

def road_width(cls, tags):
    """Carriageway width. Shared by the ribbon builder and the graph so the
    two cannot drift -- the sidewalk offset depends on them agreeing."""
    width = ROAD_WIDTHS.get(cls, 5.0)
    try:
        lanes = float(tags.get("lanes", 0))
        if lanes:
            width = max(width, lanes * 3.4)
    except (TypeError, ValueError):
        pass
    return width


def parse_oneway(tags):
    """0 two-way, 1 along the edge, -1 against it."""
    value = str(tags.get("oneway", "")).strip().lower()
    if value in ("yes", "true", "1"):
        return 1
    if value in ("-1", "reverse"):
        return -1
    # A roundabout is one-way by definition; OSM rarely bothers to tag it.
    if str(tags.get("junction", "")).strip().lower() == "roundabout":
        return 1
    return 0


def parse_lanes(cls, tags):
    try:
        count = int(float(str(tags.get("lanes", "")).strip()))
        if count > 0:
            return count
    except (TypeError, ValueError):
        pass
    return DEFAULT_LANES.get(cls, 2)


def parse_speed(cls, tags):
    digits = "".join(ch for ch in str(tags.get("maxspeed", "")) if ch.isdigit())
    if digits:
        try:
            return int(digits)
        except ValueError:
            pass
    return DEFAULT_SPEEDS.get(cls, 30)


def build_road_graph(elements):
    """Split OSM ways at shared nodes into a real network.

    An OSM way is an editing convenience, not a graph edge: one way can run
    through a dozen junctions, and two ways meet by *sharing a node id*, not by
    having coincident coordinates. Splitting on shared ids is what turns the
    way list into something a vehicle can be routed along.

    Coordinates are emitted in GODOT space (x, z), matching
    banilad_landmarks.json, so nothing downstream has to remember to negate y.
    """
    ways = [e for e in elements
            if e.get("type") == "way"
            and (e.get("tags") or {}).get("highway")
            and (e.get("tags") or {}).get("highway") not in EXCLUDED_ROAD_CLASSES]

    # Traffic control lives on nodes, and this is the data the Overpass query
    # was missing entirely until Phase 0 added node["highway"].
    control = {}
    for el in elements:
        if el.get("type") != "node":
            continue
        kind = (el.get("tags") or {}).get("highway")
        if kind:
            control[el["id"]] = kind

    # A node referenced by two or more ways is a junction. Way endpoints are
    # always graph nodes even when nothing else touches them.
    uses = {}
    for el in ways:
        for node_id in el.get("nodes") or []:
            uses[node_id] = uses.get(node_id, 0) + 1

    node_slot = {}
    nodes = []
    edges = []
    skipped = 0

    def slot_for(node_id, point):
        if node_id in node_slot:
            return node_slot[node_id]
        kind = control.get(node_id, "")
        x, y = project(point["lat"], point["lon"])
        node_slot[node_id] = len(nodes)
        nodes.append({
            "osm": node_id,
            "p": [round(x, 3), round(-y, 3)],
            # Flat for now. Phase 2 replaces this with the sampled road height;
            # every consumer should read it rather than assume a constant.
            "y": round(Z_ROAD_COLLISION, 3),
            "signal": kind == "traffic_signals",
            "crossing": kind in ("crossing", "zebra_crossing"),
            "stop": kind in ("stop", "give_way"),
        })
        return node_slot[node_id]

    for el in ways:
        tags = el.get("tags") or {}
        cls = tags["highway"]
        ids = el.get("nodes") or []
        geom = el.get("geometry") or []
        # `out body geom` returns these as parallel arrays. If they ever are
        # not, splitting on index would silently attach the wrong coordinates.
        if len(ids) != len(geom) or len(ids) < 2:
            skipped += 1
            continue

        width = road_width(cls, tags)
        lanes = parse_lanes(cls, tags)
        # Lane width is published rather than assumed. A nominal 3.4 m does not
        # survive contact with Cebu: a residential street is 6.5 m wide and
        # genuinely carries two lanes, so 2 x 3.4 would put the outer lane
        # centreline 15 cm past the kerb. Dividing the real carriageway keeps
        # every lane inside the tarmac by construction.
        shared = {
            "cls": cls,
            "name": tags.get("name", ""),
            "width": round(width, 2),
            "lanes": lanes,
            "lane_width": round(width / lanes, 3) if lanes > 0 else 0.0,
            "oneway": parse_oneway(tags),
            "roundabout": str(tags.get("junction", "")).lower() == "roundabout",
            "speed": parse_speed(cls, tags),
            "way": el["id"],
        }

        cuts = [0]
        for i in range(1, len(ids) - 1):
            if uses.get(ids[i], 0) >= 2:
                cuts.append(i)
        cuts.append(len(ids) - 1)

        for k in range(len(cuts) - 1):
            i0, i1 = cuts[k], cuts[k + 1]
            a = slot_for(ids[i0], geom[i0])
            b = slot_for(ids[i1], geom[i1])
            if a == b:
                # A closed loop with no junction on it; nothing can traverse it.
                skipped += 1
                continue
            pts = []
            for point in geom[i0:i1 + 1]:
                x, y = project(point["lat"], point["lon"])
                pts.append([round(x, 3), round(-y, 3)])
            edge = dict(shared)
            edge["a"] = a
            edge["b"] = b
            edge["pts"] = pts
            edges.append(edge)

    return {"nodes": nodes, "edges": edges}, skipped


def is_closed(pts):
    return len(pts) >= 4 and math.dist(pts[0], pts[-1]) < 0.5


def signed_area(pts):
    total = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        total += x0 * y1 - x1 * y0
    return total * 0.5


def dedupe(pts, eps=0.05):
    out = []
    for p in pts:
        if not out or math.dist(out[-1], p) > eps:
            out.append(p)
    return out


def layer_z(base, index):
    return base + (index % LAYER_SLOTS) * LAYER_STEP


def convex_hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts

    def half(seq):
        out = []
        for p in seq:
            while len(out) >= 2:
                ax, ay = out[-1][0] - out[-2][0], out[-1][1] - out[-2][1]
                bx, by = p[0] - out[-2][0], p[1] - out[-2][1]
                if ax * by - ay * bx <= 0:
                    out.pop()
                else:
                    break
            out.append(p)
        return out

    return half(pts)[:-1] + half(reversed(pts))[:-1]


def min_area_rect(points):
    """Smallest-area oriented bounding rectangle, via rotating calipers.

    Returns (centre, axis_u, half_u, half_v) where axis_u is a unit vector
    along the rectangle's longer side.
    """
    hull = convex_hull(points)
    if len(hull) < 3:
        xs = [p[0] for p in points]
        ys = [p[1] for p in points]
        cx, cy = (min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5
        return (cx, cy), (1.0, 0.0), max(0.5, (max(xs) - min(xs)) * 0.5), \
            max(0.5, (max(ys) - min(ys)) * 0.5)

    best = None
    for i in range(len(hull)):
        x0, y0 = hull[i]
        x1, y1 = hull[(i + 1) % len(hull)]
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy)
        if length < 1e-9:
            continue
        ux, uy = dx / length, dy / length
        vx, vy = -uy, ux

        us = [p[0] * ux + p[1] * uy for p in hull]
        vs = [p[0] * vx + p[1] * vy for p in hull]
        area = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or area < best[0]:
            cu = (max(us) + min(us)) * 0.5
            cv = (max(vs) + min(vs)) * 0.5
            best = (
                area,
                (cu * ux + cv * vx, cu * uy + cv * vy),
                (ux, uy),
                (max(us) - min(us)) * 0.5,
                (max(vs) - min(vs)) * 0.5,
            )

    _, centre, axis, half_u, half_v = best
    if half_v > half_u:
        axis = (-axis[1], axis[0])
        half_u, half_v = half_v, half_u
    return centre, axis, max(half_u, 0.5), max(half_v, 0.5)


def miter_offsets(pts, half):
    """Per-point offset vectors that keep a strip a constant width."""
    def normal(p0, p1):
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        length = math.hypot(dx, dy)
        if length < 1e-9:
            return None
        return (-dy / length, dx / length)

    n = len(pts)
    offsets = []
    for i, p in enumerate(pts):
        if i == 0:
            nrm = normal(pts[0], pts[1])
            off = None if nrm is None else (nrm[0] * half, nrm[1] * half)
        elif i == n - 1:
            nrm = normal(pts[-2], pts[-1])
            off = None if nrm is None else (nrm[0] * half, nrm[1] * half)
        else:
            n0, n1 = normal(pts[i - 1], p), normal(p, pts[i + 1])
            if n0 is None or n1 is None:
                off = None
            else:
                mx, my = n0[0] + n1[0], n0[1] + n1[1]
                mlen = math.hypot(mx, my)
                if mlen < 1e-6:
                    off = (n0[0] * half, n0[1] * half)
                else:
                    mx, my = mx / mlen, my / mlen
                    scale = max(0.35, mx * n0[0] + my * n0[1])
                    off = (mx * half / scale, my * half / scale)
        if off is None:
            off = offsets[-1] if offsets else (0.0, half)
        offsets.append(off)
    return offsets


# Terrain height lookup, installed once the road graph has been solved. Flat
# until then, so the module still works with no elevation cache.
GROUND_AT = None


def ground_at(x, y):
    return 0.0 if GROUND_AT is None else GROUND_AT(x, y)


def drape(verts):
    """Sit geometry on the terrain, keeping its own vertical structure.

    Terrain height is ADDED to each vertex's existing z rather than replacing
    it, so a kerb stays 0.15 m proud and the layer_z stagger that stops the
    road ribbons z-fighting survives intact. Everything that should follow the
    ground -- carriageways, sidewalks, markings, landuse, water -- goes through
    here.

    Buildings deliberately do NOT: draping a footprint would tilt its roof down
    the hill. They take an explicit base height instead, with a plinth down to
    the lowest corner, which is how Cebu actually builds on a slope.
    """
    if GROUND_AT is None:
        return verts
    return [(x, y, z + GROUND_AT(x, y)) for x, y, z in verts]


class LiftedBatch:
    """Adds a constant height to everything written through it.

    Lets a builder that draws from z=0 -- tower_detail, the infill houses -- be
    placed on terrain without touching its internals, and keeps the result
    rigid, so flat roofs stay flat.
    """

    def __init__(self, batch, dz):
        self.batch = batch
        self.dz = dz

    def add(self, verts, faces, material, colors=None):
        self.batch.add([(x, y, z + self.dz) for x, y, z in verts], faces,
                       material, colors)


class DrapedBatch:
    """Sits everything written through it on the terrain.

    For props only. A pole or a tree is narrow enough that draping translates
    it; a parked car picks up a slight tilt down the slope, which is right.
    """

    def __init__(self, batch):
        self.batch = batch

    def add(self, verts, faces, material, colors=None):
        self.batch.add(drape(verts), faces, material, colors)


# Untinted vertices. Named because it appears once per vertex of every batch.
WHITE = (1.0, 1.0, 1.0, 1.0)

# Height grime. Walls darken toward their base by GRIME_STRENGTH, fading out
# over GRIME_HEIGHT metres. This is doing two jobs: it reads as the accumulated
# street dirt every Cebu wall has, and it fakes the contact occlusion the
# Compatibility renderer cannot compute -- there is no SSAO there at all, so
# without it every building meets the ground with a hard, flat, weightless
# seam.
GRIME_HEIGHT = 4.0
GRIME_STRENGTH = 0.22


def tint_of(seed, hue=0.03, value=0.04):
    """A small deterministic HSV jitter, as an RGB multiplier.

    Keyed off the OSM way id so a building keeps its shade across rebuilds, and
    so neighbours differ even when the palette hands them the same material.
    That is the actual fix for the banding: indexing a seven-entry wall list by
    `oid % len(list)` gives seven buckets over ten thousand buildings, and a
    whole street lands in one.

    Deliberately tiny. The palette was desaturated on purpose after a brighter
    version read as a map key rather than a city, and the point here is variety,
    not carnival.
    """
    h = hash_unit(seed)
    v = hash_unit(seed * 2654435761 + 1)
    dh = (h - 0.5) * 2.0 * hue
    dv = 1.0 + (v - 0.5) * 2.0 * value
    # Rotate hue by nudging the channels against each other rather than a full
    # RGB->HSV->RGB round trip: at this amplitude the two are indistinguishable
    # and this runs once per building instead of once per vertex.
    return (max(0.0, dv * (1.0 + dh)),
            max(0.0, dv),
            max(0.0, dv * (1.0 - dh)))


def hash_unit(n):
    """Deterministic [0, 1) from an integer. Stable across runs and platforms.

    Python's hash() is salted per process for str/bytes, so it cannot be used
    for anything that has to reproduce; this is a plain integer mix.
    """
    n = int(n) & 0xFFFFFFFF
    n = (n ^ 61) ^ (n >> 16)
    n = (n + (n << 3)) & 0xFFFFFFFF
    n = n ^ (n >> 4)
    n = (n * 0x27D4EB2D) & 0xFFFFFFFF
    n = n ^ (n >> 15)
    return n / 4294967296.0


class TintedBatch:
    """Gives everything written through it a per-building tint and base grime.

    Wrapping rather than threading a `colors=` argument through every call site:
    a building's walls, roof, windows, podium, crown and plant are emitted by
    six different functions, and all of them should share one tint without
    knowing it exists. Same reason LiftedBatch and DrapedBatch are wrappers.

    `base_z` is the building's own ground level, so grime is measured up the
    wall rather than from sea level. Compose it INSIDE a LiftedBatch --
    `LiftedBatch(TintedBatch(target, tint, base), base)` -- so the lift happens
    first and this still sees absolute z.
    """

    def __init__(self, batch, tint, base_z, grime=GRIME_STRENGTH):
        self.batch = batch
        self.tint = tint
        self.base_z = base_z
        self.grime = grime

    def add(self, verts, faces, material, colors=None):
        if colors is None:
            colors = [self.color_at(v[2]) for v in verts]
        self.batch.add(verts, faces, material, colors)

    def color_at(self, z):
        h = (z - self.base_z) / GRIME_HEIGHT
        shade = 1.0 - self.grime * (1.0 - max(0.0, min(1.0, h)))
        r, g, b = self.tint
        return (r * shade, g * shade, b * shade, 1.0)


def coastline_segments(ways):
    """Directed coastline segments in map metres.

    OSM orients `natural=coastline` with LAND ON THE LEFT and open water on the
    right. That convention is the whole reason 'which side is the sea' is
    answerable at all: the coastline is an open polyline, not a closed polygon,
    so there is nothing to run a point-in-polygon test against without first
    stitching it shut along the bbox edges.
    """
    segments = []
    for el in ways:
        if (el.get("tags") or {}).get("natural") != "coastline":
            continue
        pts = way_points(el)
        for i in range(len(pts) - 1):
            if math.dist(pts[i], pts[i + 1]) > 0.01:
                segments.append((pts[i], pts[i + 1]))
    return segments


def seaward(x, y, segments):
    """True if the point lies on the water side of the nearest coastline."""
    best = None
    for p0, p1 in segments:
        distance, _heading = point_segment_distance(x, y, p0, p1)
        if best is None or distance < best[0]:
            best = (distance, p0, p1)
    if best is None:
        return False
    _distance, p0, p1 = best
    # Cross product of the segment's direction with the offset out to the
    # point. Positive is left of travel, which by the OSM convention is land.
    cross = ((p1[0] - p0[0]) * (y - p0[1])
             - (p1[1] - p0[1]) * (x - p0[0]))
    return cross < 0.0


def build_sea(batch, material, segments, half_extent, cell):
    """Water at the y = 0 datum, filling seaward of the coastline.

    The mask is deliberately GENEROUS: a cell is filled when any of its corners
    is on the water side. Over-covering is free, because terrain above sea
    level occludes the plane from above -- so the visible waterline ends up
    wherever the ground actually crosses y = 0, not wherever this grid happens
    to fall. That is what keeps the shore smooth at a 100 m cell.
    """
    if not segments:
        return 0
    steps = int(math.ceil(2 * half_extent / cell))
    wet = []
    for row in range(steps + 1):
        y = -half_extent + row * cell
        wet.append([seaward(-half_extent + col * cell, y, segments)
                    for col in range(steps + 1)])

    verts = []
    faces = []
    filled = 0
    for row in range(steps):
        for col in range(steps):
            if not (wet[row][col] or wet[row][col + 1]
                    or wet[row + 1][col] or wet[row + 1][col + 1]):
                continue
            x0 = -half_extent + col * cell
            y0 = -half_extent + row * cell
            x1 = x0 + cell
            y1 = y0 + cell
            base = len(verts)
            verts.extend([(x0, y0, SEA_LEVEL), (x1, y0, SEA_LEVEL),
                          (x1, y1, SEA_LEVEL), (x0, y1, SEA_LEVEL)])
            faces.append((base, base + 1, base + 2, base + 3))
            filled += 1
    if faces:
        batch.add(verts, faces, material)
    return filled


def densify(pts, max_step):
    """Insert points so no segment is longer than `max_step`.

    Draping a long segment onto curved ground leaves the quad chording across
    it: the mesh sags below the true surface by roughly
    curvature * length^2 / 8. Two roads crossing at a junction chord in
    different directions, so their surfaces disagree by centimetres even though
    both are sampled from the same field -- which is the stacked-surface
    condition that makes a wheel ray chatter. Shortening the segments makes the
    error vanish quadratically.
    """
    if len(pts) < 2:
        return pts
    out = [pts[0]]
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        span = math.hypot(x1 - x0, y1 - y0)
        steps = int(math.ceil(span / max_step)) if span > max_step else 1
        for s in range(1, steps + 1):
            t = s / steps
            out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    return out


def lift(verts, dz):
    """Translate geometry vertically, rigidly. Flat stays flat."""
    if not dz:
        return verts
    return [(x, y, z + dz) for x, y, z in verts]


def ground_span(pts):
    """(lowest, highest) terrain under a footprint."""
    if GROUND_AT is None:
        return 0.0, 0.0
    heights = [GROUND_AT(x, y) for x, y in pts]
    return min(heights), max(heights)


def ribbon(pts, width, z):
    pts = dedupe(pts)
    if len(pts) < 2:
        return [], []
    offsets = miter_offsets(pts, width * 0.5)
    n = len(pts)
    left = [(p[0] + o[0], p[1] + o[1], z) for p, o in zip(pts, offsets)]
    right = [(p[0] - o[0], p[1] - o[1], z) for p, o in zip(pts, offsets)]
    return left + right, [(i, n + i, n + i + 1, i + 1) for i in range(n - 1)]


def raised_ribbon(pts, width, z, height):
    """A strip lifted to `height` with vertical kerb faces down its edges."""
    pts = dedupe(pts)
    if len(pts) < 2:
        return [], []
    offsets = miter_offsets(pts, width * 0.5)
    n = len(pts)
    top_l = [(p[0] + o[0], p[1] + o[1], z + height) for p, o in zip(pts, offsets)]
    top_r = [(p[0] - o[0], p[1] - o[1], z + height) for p, o in zip(pts, offsets)]
    bot_l = [(v[0], v[1], z) for v in top_l]
    bot_r = [(v[0], v[1], z) for v in top_r]

    verts = top_l + top_r + bot_l + bot_r
    faces = []
    for i in range(n - 1):
        faces.append((i, n + i, n + i + 1, i + 1))                       # top
        faces.append((2 * n + i, i, i + 1, 2 * n + i + 1))               # kerb left
        faces.append((n + i, 3 * n + i, 3 * n + i + 1, n + i + 1))       # kerb right
    return verts, faces


def offset_polyline(pts, distance):
    pts = dedupe(pts)
    if len(pts) < 2:
        return []
    offsets = miter_offsets(pts, abs(distance))
    sign = 1.0 if distance >= 0 else -1.0
    return [(p[0] + o[0] * sign, p[1] + o[1] * sign) for p, o in zip(pts, offsets)]


def polyline_arc_table(pts):
    table = [0.0]
    for i in range(len(pts) - 1):
        table.append(table[-1] + math.dist(pts[i], pts[i + 1]))
    return table


def point_at_arc(pts, table, s):
    for i in range(len(pts) - 1):
        if s <= table[i + 1] or i == len(pts) - 2:
            span = table[i + 1] - table[i]
            t = 0.0 if span <= 1e-9 else (s - table[i]) / span
            t = min(1.0, max(0.0, t))
            a, b = pts[i], pts[i + 1]
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    return pts[-1]


def sub_polyline(pts, table, s0, s1):
    """The piece of a polyline between two arc lengths, original corners kept."""
    out = [point_at_arc(pts, table, s0)]
    for i in range(1, len(pts) - 1):
        if s0 < table[i] < s1:
            out.append(pts[i])
    out.append(point_at_arc(pts, table, s1))
    return dedupe(out)


def on_other_carriageway(x, y, index, way_index, margin):
    for p0, p1, half, owner in index.near(x, y):
        if owner == way_index:
            continue
        distance, _ = point_segment_distance(x, y, p0, p1)
        if distance <= half + margin:
            return True
    return False


def clip_against_carriageways(line, index, way_index, margin,
                              step=1.5, min_run=2.5):
    """Break a polyline wherever it runs over another road's tarmac.

    Sidewalks and lane markings are generated along a way's whole length, so
    at a junction they carry straight over the crossing road. For a sidewalk
    that means a kerbed slab lying across the carriageway -- a step the car
    hits, not just something that looks wrong.

    `margin` is how far the feature reaches either side of the line being
    tested, so a sidewalk clears the tarmac by its own half-width rather than
    stopping with half of itself still over the road. Runs shorter than
    `min_run` are dropped as slivers.
    """
    pts = dedupe(line)
    if len(pts) < 2:
        return []
    table = polyline_arc_table(pts)
    total = table[-1]
    if total <= 1e-6:
        return []

    steps = max(1, int(math.ceil(total / step)))
    runs = []
    start = None
    last = 0.0
    for k in range(steps + 1):
        s = total * k / steps
        px, py = point_at_arc(pts, table, s)
        if on_other_carriageway(px, py, index, way_index, margin):
            if start is not None and last - start >= min_run:
                runs.append((start, last))
            start = None
        else:
            if start is None:
                start = s
            last = s
    if start is not None and last - start >= min_run:
        runs.append((start, last))

    # Nothing crossed it: hand back the original vertices rather than a
    # resampled copy, so untouched streets keep their original vertex count.
    if len(runs) == 1 and runs[0][0] <= 1e-6 and runs[0][1] >= total - 1e-6:
        return [pts]
    return [sub_polyline(pts, table, a, b) for a, b in runs]


def offset_ring(pts, distance):
    """Offset a closed ring, mitring every corner including the seam.

    offset_polyline works on an open polyline, so feeding it `ring + [ring[0]]`
    gives the seam vertex a plain perpendicular offset instead of a corner
    mitre and leaves one corner of every ring in the wrong place. Positive
    distance shrinks a counter-clockwise ring, matching offset_polyline.
    """
    ring = dedupe(pts[:-1] if is_closed(pts) else pts)
    n = len(ring)
    if n < 3:
        return []

    def normal(p0, p1):
        dx, dy = p1[0] - p0[0], p1[1] - p0[1]
        length = math.hypot(dx, dy)
        if length < 1e-9:
            return None
        return (-dy / length, dx / length)

    out = []
    for i, p in enumerate(ring):
        n0 = normal(ring[i - 1], p)
        n1 = normal(p, ring[(i + 1) % n])
        if n0 is None or n1 is None:
            nrm = n0 or n1
            if nrm is None:
                out.append(p)
                continue
            mx, my, scale = nrm[0], nrm[1], 1.0
        else:
            mx, my = n0[0] + n1[0], n0[1] + n1[1]
            length = math.hypot(mx, my)
            if length < 1e-6:          # doubled back on itself
                out.append(p)
                continue
            mx, my = mx / length, my / length
            # The sharper the corner, the further the mitre has to reach.
            # Clamped so a near-spike does not fling the vertex across the map.
            scale = 1.0 / max(0.25, mx * n0[0] + my * n0[1])
        out.append((p[0] + mx * distance * scale, p[1] + my * distance * scale))
    return out


def flat_polygon(pts, z):
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]
    return [(x, y, z) for x, y in pts], [tuple(range(len(pts)))]


def point_in_polygon(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if (y0 > y) != (y1 > y):
            xint = (x1 - x0) * (y - y0) / (y1 - y0) + x0
            if x < xint:
                inside = not inside
    return inside


def box(cx, cy, z0, z1, half_x, half_y, angle=0.0):
    ca, sa = math.cos(angle), math.sin(angle)
    corners = []
    for dx, dy in ((-half_x, -half_y), (half_x, -half_y), (half_x, half_y), (-half_x, half_y)):
        corners.append((cx + dx * ca - dy * sa, cy + dx * sa + dy * ca))
    verts = [(x, y, z0) for x, y in corners] + [(x, y, z1) for x, y in corners]
    faces = [(3, 2, 1, 0), (4, 5, 6, 7)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((i, j, j + 4, i + 4))
    return verts, faces


# ---------------------------------------------------------------------------
# Building forms
# ---------------------------------------------------------------------------

def walls(pts, base_z, top_z):
    """Vertical wall band around a footprint, open at top and bottom."""
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]
    n = len(pts)
    verts = [(x, y, base_z) for x, y in pts] + [(x, y, top_z) for x, y in pts]
    faces = [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    faces.append(tuple(range(n - 1, -1, -1)))
    return verts, faces


def hip_roof(pts, eave_z, overhang=0.55):
    """Four-sided hip roof over the footprint's oriented bounding box."""
    (cx, cy), (ux, uy), half_u, half_v = min_area_rect(pts)
    vx, vy = -uy, ux
    hu = half_u + overhang
    hv = half_v + overhang
    rise = min(2.4, max(0.9, hv * 0.55))

    def at(du, dv, dz):
        return (cx + ux * du + vx * dv, cy + uy * du + vy * dv, eave_z + dz)

    # Eave corners, then the ridge shortened by the roof's half-width.
    e0 = at(-hu, -hv, 0.0)
    e1 = at(hu, -hv, 0.0)
    e2 = at(hu, hv, 0.0)
    e3 = at(-hu, hv, 0.0)
    ridge = max(0.0, hu - hv)
    r0 = at(-ridge, 0.0, rise)
    r1 = at(ridge, 0.0, rise)

    verts = [e0, e1, e2, e3, r0, r1]
    faces = [
        (0, 1, 5, 4),   # long slope
        (2, 3, 4, 5),   # long slope
        (1, 2, 5),      # hip end
        (3, 0, 4),      # hip end
        (3, 2, 1, 0),   # soffit
    ]
    return verts, faces, rise


def shed_roof(pts, eave_z, overhang=0.45):
    """Single-slope tin roof as a thin slab.

    The informal-settlement form, and the reason the infill stopped reading as
    2000 copies of one house: a hip roof on every single dwelling is what made
    the filler blocks look stamped out.
    """
    (cx, cy), (ux, uy), half_u, half_v = min_area_rect(pts)
    vx, vy = -uy, ux
    hu, hv = half_u + overhang, half_v + overhang
    rise = min(1.5, max(0.4, hv * 0.36))
    thick = 0.12

    def at(du, dv, dz):
        return (cx + ux * du + vx * dv, cy + uy * du + vy * dv, eave_z + dz)

    top = [at(-hu, -hv, 0.0), at(hu, -hv, 0.0), at(hu, hv, rise), at(-hu, hv, rise)]
    low = [(p[0], p[1], p[2] - thick) for p in top]
    verts = low + top
    faces = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7),
    ]
    return verts, faces, rise


def parapet_roof(pts, top_z, parapet=0.85, inset=0.4):
    """Flat roof slab with a raised parapet wall around the edge."""
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]

    # A positive distance shrinks a counter-clockwise ring. This used to pass
    # -inset, which grew it instead, so every flat roof overhung its own walls
    # by `inset` rather than stepping in from them.
    inner = offset_ring(pts, inset)
    if len(inner) != len(pts):
        inner = pts

    n = len(pts)
    verts = []
    verts += [(x, y, top_z) for x, y in inner]                    # slab
    verts += [(x, y, top_z + parapet) for x, y in pts]            # outer top
    verts += [(x, y, top_z + parapet) for x, y in inner]          # inner top

    faces = [tuple(range(n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((n + i, n + j, 2 * n + j, 2 * n + i))        # parapet cap
        faces.append((2 * n + i, 2 * n + j, j, i))                # parapet inner
    return verts, faces


def window_bands(pts, base_z, top_z, floor_height=3.3, band=1.5, bulge=0.06,
                 first_floor=3.6, min_edge=2.0, inset=0.85):
    """Recessed glazing bands, one per floor, wrapped around the walls.

    The defaults are tuned for mid-rise. Low-rise passes a lower `first_floor`,
    a shorter `band` and a smaller `min_edge`, because a 6 m shophouse has its
    first window course about 2 m up and walls only a few metres long -- on the
    mid-rise numbers it clears no floors at all and every small building in the
    city stays a blank box.
    """
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]

    verts = []
    faces = []
    n = len(pts)
    floor = base_z + first_floor
    guard = 0
    while floor + band < top_z - 0.6 and guard < 40:
        guard += 1
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            dx, dy = x1 - x0, y1 - y0
            length = math.hypot(dx, dy)
            if length < min_edge:
                continue
            # Inset the band a little from each corner so it reads as a window.
            t = min(inset / length, 0.3)
            ax, ay = x0 + dx * t, y0 + dy * t
            bx, by = x1 - dx * t, y1 - dy * t
            nx, ny = -dy / length * bulge, dx / length * bulge
            base = len(verts)
            verts += [
                (ax + nx, ay + ny, floor),
                (bx + nx, by + ny, floor),
                (bx + nx, by + ny, floor + band),
                (ax + nx, ay + ny, floor + band),
            ]
            faces.append((base, base + 1, base + 2, base + 3))
        floor += floor_height
    return verts, faces


# ---------------------------------------------------------------------------
# Hand-authored landmarks
#
# UC Banilad and Gaisano Country Mall are the two buildings the player is meant
# to recognise on sight, so they are modelled by hand instead of being extruded
# from their OSM footprints like everything else. OSM has both of them wrong in
# ways that matter: UC is stored as two overlapping C-shaped ways that a naive
# extrude fills in solid, erasing the courtyard, and the mall is a single wing
# with none of the arcade rows, parking court or covered walkway.
#
# Plans below are in local metres and were measured off the OSM ways plus the
# aerial reference. Detail follows the "geometry for silhouette, texture for
# detail" rule: massing, roofs and the courtyard void are real geometry, while
# the arcade arches and curtain-wall mullions are recessed material bands.
# ---------------------------------------------------------------------------

# The corridor's controlling angle. Gov. M. Cuenco Avenue runs at this bearing
# past both landmarks, and every frontage here is parallel to it.
AVENUE_BEARING = math.radians(80.7)
AVENUE_U = (math.cos(AVENUE_BEARING), math.sin(AVENUE_BEARING))

# University of Cebu, stored as two overlapping C-shaped ways that together
# trace the courtyard ring. Their combined extent drives the hand-built block.
UC_WAY_IDS = {132902349, 132902350}

# Gaisano Country Mall. OSM names only the main north bar, but the surveyed
# ring of unnamed arcade strips around the car park is correct and is far more
# accurate than anything traced by eye, so the plan comes from the data and
# only the treatment -- arcade band, clay roof, storey heights -- is authored.
#   way id: (ground floor height, eaves height, arcade tiers)
MALL_WINGS = {
    93839848:   (5.2, 10.6, 2),   # main north bar and west wing (the named one)
    1279791577: (5.2, 10.4, 2),   # central block facing the court
    93839827:   (4.8, 9.2, 2),    # south and west arcade strip
    93839832:   (4.6, 8.8, 2),    # east arcade, surveyed as four segments
    93839836:   (4.6, 8.8, 2),
    93839839:   (4.6, 9.4, 2),
    93839843:   (4.6, 9.4, 2),
    93839855:   (4.4, 7.8, 1),    # west annex
    93839860:   (4.4, 7.4, 1),
}
MALL_WALKWAY_WAY = 93839864    # covered walkway from the avenue into the mall
MALL_PARCEL_WAY = 1364251197   # commercial parcel; its open part is the car park

# The campus block is not covered by any OSM landuse polygon, so infill is kept
# off it explicitly. Padded a few metres beyond the surveyed footprint.
UC_CAMPUS_BLOCK = [(11.0, 409.0), (88.0, 405.0), (94.0, 492.0), (15.0, 497.0)]

UC_LEVELS = 10
UC_LEVEL_HEIGHT = 3.65
UC_WING_DEPTH = 13.5          # depth of the occupied ring around the courtyard
UC_FACADE_BOW = 3.2           # how far the curtain wall bulges toward the avenue

MALL_WALKWAY_HEIGHT = 3.6      # underside of the covered walkway canopy
# Outer face of the scanned mall's entrance bay, in Blender XY. The canopy is
# slid along until its inner end meets this, so it reads as running out of the
# entrance rather than starting beside it. This is the one place the mall
# departs from the surveyed OSM line.
#
# It has to be a constant because the entrance is placed by build_mall.py,
# which runs separately; re-derive it from that script's placement if the
# entrance ever moves.
MALL_WALKWAY_ANCHOR = (-39.33, 522.85)
# Sliding the canopy also slid its outer end onto Cuenco Avenue, so the far end
# is trimmed back until it clears the carriageway by this margin. Only the
# avenue counts: the canopy is meant to bridge the mall's own service drives.
MALL_WALKWAY_ROAD_CLEARANCE = 2.5

# --- Cebu IT Park ----------------------------------------------------------
# Ayala Malls Central Bloc opened after the aerial imagery most sources still
# ship, so OSM carries the footprints but almost no heights: both corporate
# towers fall back to the 14 m "commercial" default and vanish from the
# skyline. These heights are read off a night aerial of the finished complex,
# not from OSM, and are the one place in this file where that is true.
CENTRAL_BLOC = {
    # way id: (height, wall material, glazing material or None)
    156416254:  (26.0, "Bloc_Podium", None),            # Ayala Malls podium
    1293810435: (22.0, "Bloc_Podium", None),            # retail wing
    # Corporate Center One is charcoal-clad, so its glazing has to be lighter
    # than the wall or the banding disappears into it.
    1082683047: (70.0, "Bloc_Tower_Dark", "Bloc_Tower_Light"),
    1082683046: (60.0, "Bloc_Tower_Light", "UC_Glass"), # Corporate Center Two
    1323519298: (45.0, "Bloc_Hotel", "UC_Glass_Dark"),  # Seda Central Bloc
}
CENTRAL_BLOC_MALL = 156416254        # the podium that carries the signage band

# Anything at least this tall is treated as an office tower and gets the base,
# crown and rooftop plant that stop it reading as a plain extruded box.
TOWER_MIN_HEIGHT = 26.0
TOWER_BASE_HEIGHT = 7.5

# main() skips all of these in the generic building loop but still records their
# footprints so infill housing keeps clear of them.
LANDMARK_WAY_IDS = (UC_WAY_IDS | set(MALL_WINGS) | {MALL_WALKWAY_WAY}
                    | set(CENTRAL_BLOC) | landmarks.LANDMARK_WAYS)


def oriented_rect(centre, axis, half_u, half_v):
    """Four corners of a rectangle given a centre, a unit axis and half sizes."""
    (cx, cy), (ux, uy) = centre, axis
    vx, vy = -uy, ux
    return [
        (cx - ux * half_u - vx * half_v, cy - uy * half_u - vy * half_v),
        (cx + ux * half_u - vx * half_v, cy + uy * half_u - vy * half_v),
        (cx + ux * half_u + vx * half_v, cy + uy * half_u + vy * half_v),
        (cx - ux * half_u + vx * half_v, cy - uy * half_u + vy * half_v),
    ]


def bow_edge(a, b, bulge, segments=6):
    """Replace a straight edge with an arc bulging to its left by `bulge`."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)
    if length < 1e-6 or abs(bulge) < 1e-6:
        return [a]
    nx, ny = -dy / length, dx / length
    out = []
    for i in range(segments):
        t = i / float(segments)
        # Half-sine gives a shallow, even bow with no kink at the ends.
        k = math.sin(t * math.pi)
        out.append((ax + dx * t + nx * bulge * k, ay + dy * t + ny * bulge * k))
    return out


def inset_in_frame(pts, centre, axis, half_u, half_v, depth):
    """Shrink a footprint by `depth` inside its own oriented bounding box.

    offset_polyline mitres each corner independently, which on a ring with a
    bowed edge folds over at the corners and leaves holes in the roof. Scaling
    in the rectangle's own frame instead is exactly a constant inset for a
    rectangle, keeps the vertex count, and cannot self-intersect while
    `depth` stays under both half sizes.
    """
    (cx, cy), (ux, uy) = centre, axis
    vx, vy = -uy, ux
    if depth >= half_u or depth >= half_v:
        return None
    su = (half_u - depth) / half_u
    sv = (half_v - depth) / half_v
    out = []
    for x, y in pts:
        dx, dy = x - cx, y - cy
        u = (dx * ux + dy * uy) * su
        v = (dx * vx + dy * vy) * sv
        out.append((cx + ux * u + vx * v, cy + uy * u + vy * v))
    return out


def ring_solid(outer, inner, z0, z1):
    """Closed ring between two polygons: outer skin, inner skin and a top cap.

    Both rings must wind the same way and have the same vertex count, which is
    what the courtyard builder produces by construction.
    """
    n = len(outer)
    if n < 3 or len(inner) != n:
        return [], []
    verts = ([(x, y, z0) for x, y in outer] + [(x, y, z1) for x, y in outer]
             + [(x, y, z0) for x, y in inner] + [(x, y, z1) for x, y in inner])
    o0, o1, i0, i1 = 0, n, 2 * n, 3 * n
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((o0 + i, o0 + j, o1 + j, o1 + i))      # outer skin
        faces.append((i1 + i, i1 + j, i0 + j, i0 + i))      # courtyard skin
        faces.append((o1 + i, o1 + j, i1 + j, i1 + i))      # roof ring
        faces.append((i0 + i, i0 + j, o0 + j, o0 + i))      # soffit ring
    return verts, faces


def band_ring(pts, z0, z1, offset=0.12):
    """Horizontal band wrapped around a footprint, standing proud of the wall.

    A positive offset pushes the band away from the footprint's centre, which
    is what makes it visible on an outward-facing wall; use a negative offset
    on a courtyard ring, whose visible face points the other way. The band must
    always sit slightly proud -- recessing it buries it inside the solid wall,
    exactly as window_bands avoids by bulging its glazing outward.

    Note that offset_polyline grows a counter-clockwise ring on a *negative*
    distance, so the sign is flipped on the way in.
    """
    pts = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(pts) < 3:
        return [], []
    if signed_area(pts) < 0:
        pts = pts[::-1]
    shifted = offset_ring(pts, -offset)
    if len(shifted) != len(pts):
        shifted = pts
    n = len(shifted)
    verts = [(x, y, z0) for x, y in shifted] + [(x, y, z1) for x, y in shifted]
    faces = [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return verts, faces


# Ground-floor shopfront. Two courses: a dark recessed opening at street level
# and a bright sign board above it, which together are what makes a Philippine
# commercial street read as commercial. This approximates Colon's signage
# canyon with geometry the pipeline already has -- when the signage atlas lands
# the sign course is the band it gets mapped onto.
SHOPFRONT_SILL = 0.35
SHOPFRONT_HEAD = 2.7
SIGN_HEIGHT = 0.75


def shopfront_band(batch, mats, ring, base_z, tint_seed):
    """Dark shopfront opening plus a sign fascia above it, around a footprint.

    Applied to commercial frontage only. On a residential house it would read
    as a shop that is not there, and the whole point of the district work is
    that Colon should not look like Banilad.
    """
    v, f = band_ring(ring, base_z + SHOPFRONT_SILL, base_z + SHOPFRONT_HEAD,
                     offset=0.05)
    if not f:
        return 0
    batch.add(v, f, mats["Shopfront_Glass"])
    v, f = band_ring(ring, base_z + SHOPFRONT_HEAD,
                     base_z + SHOPFRONT_HEAD + SIGN_HEIGHT, offset=0.14)
    # The sign colour is picked per building rather than per face: a whole
    # frontage shares one board in a way that a per-face pick would not.
    sign = SIGN_COLOURS[tint_seed % len(SIGN_COLOURS)]
    batch.add(v, f, mats[sign])
    return 1


def build_uc_banilad(batch, mats, uc_rings):
    """Ten-level courtyard block with the bowed glass frontage on the avenue.

    `uc_rings` is the list of OSM footprints for the campus; their combined
    extent sets the outer wall so the building still lands exactly where the
    surveyed roads and driveways expect it.
    """
    points = [p for ring in uc_rings for p in ring]
    if len(points) < 4:
        log("UC: no footprint available, skipped")
        return 0.0

    centre, axis, half_u, half_v = min_area_rect(points)
    outer_rect = oriented_rect(centre, axis, half_u, half_v)

    # The avenue runs down the west side, so the bowed curtain wall goes on
    # whichever face points that way.
    cx, cy = centre
    to_avenue = (-1.0, 0.0)
    best, best_dot = 0, -2.0
    for i in range(4):
        ax, ay = outer_rect[i]
        bx, by = outer_rect[(i + 1) % 4]
        mx, my = (ax + bx) * 0.5 - cx, (ay + by) * 0.5 - cy
        length = math.hypot(mx, my) or 1.0
        dot = (mx / length) * to_avenue[0] + (my / length) * to_avenue[1]
        if dot > best_dot:
            best, best_dot = i, dot

    # Walk the rectangle, bowing the avenue face outward.
    outer = []
    for i in range(4):
        a = outer_rect[i]
        b = outer_rect[(i + 1) % 4]
        if i == best:
            bulge = UC_FACADE_BOW if signed_area(outer_rect) > 0 else -UC_FACADE_BOW
            outer.extend(bow_edge(a, b, -bulge, segments=7))
        else:
            outer.append(a)
    outer = dedupe(outer)
    if signed_area(outer) < 0:
        outer = outer[::-1]

    inner = inset_in_frame(outer, centre, axis, half_u, half_v, UC_WING_DEPTH)
    if inner is not None and abs(signed_area(inner)) < 60.0:
        inner = None    # footprint too slim for a courtyard; solid block instead

    top = UC_LEVELS * UC_LEVEL_HEIGHT
    if inner:
        v, f = ring_solid(outer, inner, Z_BUILDING_BASE, top)
        batch.add(v, f, mats["UC_Band"])
        v, f = band_ring(inner, top, top + 0.9, offset=0.0)
        batch.add(v, f, mats["UC_Band"])                     # courtyard parapet
    else:
        v, f = walls(outer, Z_BUILDING_BASE, top)
        batch.add(v, f, mats["UC_Band"])
        v, f = parapet_roof(outer, top)
        batch.add(v, f, mats["UC_Deck"])

    # Glazing: one band per level on the street skin, a darker one on the
    # courtyard skin. This is what carries the curtain-wall read.
    for level in range(1, UC_LEVELS):
        z0 = level * UC_LEVEL_HEIGHT + 0.85
        z1 = z0 + UC_LEVEL_HEIGHT - 1.55
        v, f = band_ring(outer, z0, z1, offset=0.10)
        batch.add(v, f, mats["UC_Glass"])
        if inner:
            # The courtyard skin faces inward, so its band goes the other way.
            v, f = band_ring(inner, z0, z1, offset=-0.10)
            batch.add(v, f, mats["UC_Glass_Dark"])

    # Ground-floor colonnade and the entrance canopy on the avenue face.
    v, f = band_ring(outer, 0.5, 3.6, offset=0.12)
    batch.add(v, f, mats["UC_Glass_Dark"])

    # Roof-deck plant room, offset toward the back of the block so it breaks
    # the silhouette the way the real lift overrun does.
    (ux, uy) = axis
    vx, vy = -uy, ux
    px = cx + ux * (half_u * 0.34) + vx * (half_v * 0.52)
    py = cy + uy * (half_u * 0.34) + vy * (half_v * 0.52)
    v, f = box(px, py, top + 0.9, top + 4.6, 6.5, 4.2, math.atan2(uy, ux))
    batch.add(v, f, mats["UC_Podium"])

    # Two-level podium wing along the avenue at the south end (the covered
    # entrance ramp and the Rose Pharmacy shopfront row). It hangs off the same
    # face the curtain wall bows out of, and may only project far enough to
    # clear the building line -- Cuenco Avenue's sidewalk starts a few metres
    # further out, and anything deeper ends up standing in the carriageway.
    ax, ay = outer_rect[best]
    bx, by = outer_rect[(best + 1) % 4]
    ex, ey = bx - ax, by - ay
    edge_len = math.hypot(ex, ey) or 1.0
    ex, ey = ex / edge_len, ey / edge_len
    # Outward normal of that face, pointing away from the building centre.
    nx, ny = -ey, ex
    if nx * ((ax + bx) * 0.5 - cx) + ny * ((ay + by) * 0.5 - cy) < 0.0:
        nx, ny = -nx, -ny

    podium_depth = 3.0
    mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
    qx = mx - ex * (edge_len * 0.30) + nx * (podium_depth + UC_FACADE_BOW * 0.5)
    qy = my - ey * (edge_len * 0.30) + ny * (podium_depth + UC_FACADE_BOW * 0.5)
    podium = oriented_rect((qx, qy), (ex, ey), edge_len * 0.24, podium_depth)
    v, f = walls(podium, Z_BUILDING_BASE, 7.4)
    batch.add(v, f, mats["UC_Podium"])
    v, f = parapet_roof(podium, 7.4, parapet=0.6)
    batch.add(v, f, mats["UC_Deck"])
    v, f = band_ring(podium, 0.6, 3.4, offset=-0.16)
    batch.add(v, f, mats["UC_Glass_Dark"])

    log("UC Banilad: {:d} levels, {:.0f} m tall, courtyard {:s}".format(
        UC_LEVELS, top, "yes" if inner else "no (fallback block)"))
    return top


def shallow_hip(pts, eave_z, rise=1.7, overhang=0.9):
    """Low clay-tile roof that follows the real footprint.

    hip_roof builds over the footprint's bounding rectangle, which suits a
    house but roofs straight across the courtyard of an L- or C-shaped mall
    wing and swallows the car park. This keeps the plan exact: an eave skirt
    around the true outline, a flat cap, and a soffit under the overhang.
    """
    ring = dedupe(pts[:-1] if is_closed(pts) else pts)
    if len(ring) < 3:
        return [], []
    if signed_area(ring) < 0:
        ring = ring[::-1]
    # A negative distance grows a counter-clockwise ring, giving the overhang.
    eave = offset_ring(ring, -overhang)
    if len(eave) != len(ring):
        eave = ring

    n = len(ring)
    verts = ([(x, y, eave_z) for x, y in eave]
             + [(x, y, eave_z + rise) for x, y in ring]
             + [(x, y, eave_z) for x, y in ring])
    faces = [tuple(range(n, 2 * n))]                     # flat cap
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))               # sloping skirt
        faces.append((2 * n + i, 2 * n + j, j, i))       # soffit
    return verts, faces


def _arcaded_wing(batch, mats, plan, ground_h, upper_h, roof_mat, tiers=2):
    """Cream arcade block with a clay hip roof, as used by every mall wing."""
    ring = dedupe(plan)
    if signed_area(ring) < 0:
        ring = ring[::-1]

    v, f = walls(ring, Z_BUILDING_BASE, upper_h)
    batch.add(v, f, mats["Mall_Wall"])

    # Ground arcade: the dark band reads as the row of round arches.
    v, f = band_ring(ring, 0.7, ground_h - 0.9, offset=0.10)
    batch.add(v, f, mats["Mall_Arcade"])
    v, f = band_ring(ring, ground_h - 0.9, ground_h - 0.35, offset=0.22)
    batch.add(v, f, mats["Mall_Trim"])          # string course between tiers

    if tiers > 1 and upper_h > ground_h + 2.5:
        v, f = band_ring(ring, ground_h + 0.5, upper_h - 1.1, offset=0.10)
        batch.add(v, f, mats["Mall_Arcade"])    # upper arcade

    # Cornice, then the tile roof.
    v, f = band_ring(ring, upper_h - 0.55, upper_h, offset=0.32)
    batch.add(v, f, mats["Mall_Trim"])
    v, f = shallow_hip(ring, upper_h)
    batch.add(v, f, roof_mat)


def tower_detail(batch, mats, ring, height, glass=None, base_mat="Tower_Base",
                 crown_mat="Tower_Crown", plant=True):
    """Base, glazing, crown and rooftop plant for a tall building.

    Without this an office tower is a bare extruded prism, which is what made
    the whole IT Park district read as a field of plain boxes. Everything here
    is a band standing slightly proud of the wall plus one plant box, so the
    cost is a few dozen triangles per tower.
    """
    if height < 12.0 or len(ring) < 3:
        return

    # Darker podium storeys at street level.
    base_h = min(TOWER_BASE_HEIGHT, height * 0.28)
    v, f = band_ring(ring, 0.0, base_h, offset=0.18)
    batch.add(v, f, mats[base_mat])
    v, f = band_ring(ring, base_h, base_h + 0.45, offset=0.34)
    batch.add(v, f, mats["Tower_Crown"])          # sill course over the podium

    # Curtain wall: one band per floor between the podium and the crown. The
    # band is kept well under the floor pitch so a pale tower still reads as
    # concrete with windows punched into it rather than as zebra stripes.
    if glass:
        floor = base_h + 1.6
        guard = 0
        while floor + 1.5 < height - 3.0 and guard < 60:
            guard += 1
            v, f = band_ring(ring, floor, floor + 1.5, offset=0.10)
            batch.add(v, f, mats[glass])
            floor += 3.4

    # Capping band, then the lift overrun and plant deck on the roof.
    v, f = band_ring(ring, height - 2.6, height - 0.3, offset=0.22)
    batch.add(v, f, mats[crown_mat])

    if plant:
        centre, axis, half_u, half_v = min_area_rect(ring)
        # A lift overrun, not a second storey: keep it small enough that the
        # roof still reads as a roof from the towers looking down on it.
        pu = min(6.5, max(2.2, half_u * 0.18))
        pv = min(6.5, max(2.2, half_v * 0.18))
        v, f = box(centre[0], centre[1], height + 0.85, height + 4.2,
                   pu, pv, math.atan2(axis[1], axis[0]))
        batch.add(v, f, mats["Tower_Plant"])


# Low-rise roof clutter. Water tanks, aircon boxes and antennas -- the
# roofscape is most of what is visible from anywhere elevated, and a city of
# bare flat slabs reads as a model however good the walls are.
ROOF_CLUTTER_MIN_AREA = 55.0
ROOF_CLUTTER_CHANCE = 0.62


def roof_clutter_field(batch, mats, ring, top_z, seed, limit=6):
    """Scatter tanks and boxes on one small flat roof.

    Deliberately not roof_plant_field(): that walks a grid at 12 m spacing over
    a mall podium and would put nothing at all on a 9 m house. This places a
    handful of units against the footprint's own centroid instead, and picks
    kinds and offsets off the way id so a rebuild reproduces them exactly.
    """
    area = abs(signed_area(ring))
    if area < ROOF_CLUTTER_MIN_AREA:
        return 0
    if hash_unit(seed * 7919 + 13) > ROOF_CLUTTER_CHANCE:
        return 0
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    cx = sum(xs) / len(xs)
    cy = sum(ys) / len(ys)
    span = min(max(xs) - min(xs), max(ys) - min(ys))
    if span < 3.5:
        return 0

    count = 1 + int(hash_unit(seed * 104729) * min(limit, 1 + area / 90.0))
    placed = 0
    for i in range(count):
        ox = (hash_unit(seed * 31 + i * 977) - 0.5) * span * 0.55
        oy = (hash_unit(seed * 37 + i * 1013) - 0.5) * span * 0.55
        px, py = cx + ox, cy + oy
        if not point_in_polygon(px, py, ring):
            continue
        kind = int(hash_unit(seed * 41 + i * 613) * 3)
        if kind == 0:
            # Water tank: the squat cylinder-ish box every Cebu roof carries.
            r = 0.55 + hash_unit(seed + i) * 0.3
            v, f = box(px, py, top_z, top_z + 1.1 + hash_unit(seed + i * 3) * 0.5,
                       r, r)
            batch.add(v, f, mats["Roof_Tank"])
        elif kind == 1:
            w = 0.6 + hash_unit(seed + i * 5) * 0.5
            d = 0.5 + hash_unit(seed + i * 7) * 0.4
            v, f = box(px, py, top_z, top_z + 0.7, w, d)
            batch.add(v, f, mats["Tower_Plant"])
        else:
            # Antenna mast: a thin pole, the cheapest silhouette break there is.
            v, f = box(px, py, top_z, top_z + 1.8 + hash_unit(seed + i * 11) * 1.4,
                       0.06, 0.06)
            batch.add(v, f, mats["Pole"])
        placed += 1
    return placed


def roof_plant_field(batch, mats, ring, top_z, spacing=12.0, limit=70):
    """Scatter small plant units over a wide flat roof.

    A mall podium roof is the one surface the surrounding towers look straight
    down onto, and in the reference it is packed with air-handling units. One
    big box in the middle reads as another storey instead.
    """
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    placed = 0
    gy = 0
    y = min(ys) + spacing * 0.5
    while y < max(ys) and placed < limit:
        gx = 0
        x = min(xs) + spacing * 0.5
        while x < max(xs) and placed < limit:
            gx += 1
            cx, cy = x, y
            x += spacing
            # Stay clear of the parapet so nothing pokes through the edge.
            if not all(point_in_polygon(cx + dx, cy + dy, ring)
                       for dx, dy in ((0, 0), (5, 0), (-5, 0), (0, 5), (0, -5))):
                continue
            # Deterministic jitter: the build must be reproducible.
            h = (gx * 7 + gy * 13) % 5
            w = 1.8 + (h % 3) * 0.7
            d = 1.6 + ((h + 1) % 3) * 0.6
            v, f = box(cx, cy, top_z + 0.6, top_z + 1.5 + h * 0.35, w, d)
            batch.add(v, f, mats["Tower_Plant"])
            placed += 1
        gy += 1
        y += spacing
    return placed


def build_central_bloc(batch, mats, rings):
    """Ayala Malls Central Bloc: mall podium, two office towers and the hotel."""
    built = 0
    for way_id, (height, wall_key, glass_key) in sorted(CENTRAL_BLOC.items()):
        ring = rings.get(way_id)
        if not ring or len(ring) < 3:
            continue

        v, f = walls(ring, Z_BUILDING_BASE, height)
        batch.add(v, f, mats[wall_key])
        v, f = parapet_roof(ring, height, parapet=1.2)
        batch.add(v, f, mats["Roof_Deck"])

        # Curtain walling is what separates a tower from a podium here, not
        # height: the Ayala Malls block is tall but is still a mall roof.
        if glass_key:
            tower_detail(batch, mats, ring, height, glass=glass_key,
                         crown_mat="Tower_Crown")
        else:
            # Podium blocks: a deep parapet and a plant-covered roof rather
            # than curtain walling, which is how they read from above.
            v, f = band_ring(ring, height - 3.2, height - 0.6, offset=0.16)
            batch.add(v, f, mats["Window"])
            units = roof_plant_field(batch, mats, ring, height)
            log("  {:d} plant units on the {:.0f} m podium roof".format(
                units, height))

        if way_id == CENTRAL_BLOC_MALL:
            # The lit signage strip that fronts the mall in the night aerial.
            v, f = band_ring(ring, height - 7.0, height - 4.6, offset=0.30)
            batch.add(v, f, mats["Bloc_Sign"])
        built += 1

    log("Central Bloc: {:d} of {:d} blocks built (heights from the night "
        "aerial, not OSM)".format(built, len(CENTRAL_BLOC)))
    return built


def _trim_off_avenue(inner, outer, width, road_lines):
    """Shorten inner->outer until the far end is clear of a major road.

    Both far corners are tested, not just the centreline point, because the
    canopy is wide enough that a corner reaches the tarmac well before the
    centre does.
    """
    avenues = [(pts, w) for pts, w, cls in road_lines if cls in MAJOR_ROADS]
    if not avenues:
        return outer

    length = math.dist(inner, outer)
    if length < 1e-6:
        return outer
    ux, uy = ((outer[0] - inner[0]) / length, (outer[1] - inner[1]) / length)
    nx, ny = -uy, ux

    step = 0.5
    travelled = length
    while travelled > 8.0:
        ex, ey = inner[0] + ux * travelled, inner[1] + uy * travelled
        corners = [(ex + nx * width * 0.5, ey + ny * width * 0.5),
                   (ex - nx * width * 0.5, ey - ny * width * 0.5)]
        if all(point_segment_distance(cx, cy, pts[i], pts[i + 1])[0]
               >= w * 0.5 + MALL_WALKWAY_ROAD_CLEARANCE
               for cx, cy in corners
               for pts, w in avenues
               for i in range(len(pts) - 1)):
            break
        travelled -= step
    return (inner[0] + ux * travelled, inner[1] + uy * travelled)


def build_country_mall(solid, lot_batch, walk_batch, mats, rings, road_lines):
    """Arcaded wings around the open car park, plus the covered walkway.

    `rings` maps OSM way id to footprint for every part of the complex.

    The walkway goes into its own batch because the wings can be swapped for a
    scanned asset at runtime (see banilad_city.gd), and the walkway has to
    survive that: it is not in frame in any photo of the mall.
    """
    wings = 0
    for way_id, (ground_h, upper_h, tiers) in sorted(MALL_WINGS.items()):
        ring = rings.get(way_id)
        if not ring or len(ring) < 3:
            continue
        roof_mat = mats["Mall_Roof" if wings % 2 == 0 else "Mall_Roof_Alt"]
        _arcaded_wing(solid, mats, ring, ground_h, upper_h, roof_mat,
                      tiers=tiers)
        wings += 1

    # --- Car park ----------------------------------------------------------
    # The commercial parcel is the whole block; the wings are drawn on top of
    # it, so whatever tarmac still shows through is exactly the open court.
    stripes = 0
    parcel = rings.get(MALL_PARCEL_WAY)
    if parcel and len(parcel) >= 3:
        lot = dedupe(parcel)
        if signed_area(lot) < 0:
            lot = lot[::-1]
        v, f = flat_polygon(lot + [lot[0]], 0.05)
        lot_batch.add(v, f, mats["Lot_Asphalt"])

        blockers = [rings[w] for w in MALL_WINGS if rings.get(w)]
        blockers += [rings[MALL_WALKWAY_WAY]] if rings.get(MALL_WALKWAY_WAY) else []

        # Bay stripes run along the avenue axis, skipping anything built on.
        ux, uy = AVENUE_U
        vx, vy = -uy, ux
        cx = sum(p[0] for p in lot) / len(lot)
        cy = sum(p[1] for p in lot) / len(lot)
        for row in range(-9, 10):
            base = row * 11.5
            for slot in range(-22, 23):
                along = slot * 2.7
                sx = cx + ux * along + vx * base
                sy = cy + uy * along + vy * base
                ex, ey = sx + vx * 5.0, sy + vy * 5.0
                if not (point_in_polygon(sx, sy, lot)
                        and point_in_polygon(ex, ey, lot)):
                    continue
                mid = ((sx + ex) * 0.5, (sy + ey) * 0.5)
                if any(point_in_polygon(mid[0], mid[1], b) for b in blockers):
                    continue
                v, f = ribbon([(sx, sy), (ex, ey)], 0.16, 0.07)
                lot_batch.add(v, f, mats["Lot_Stripe"])
                stripes += 1

    # --- Covered walkway ---------------------------------------------------
    # Surveyed as a thin loop running out to the Cuenco Avenue sidewalk, so its
    # long axis gives the centreline the canopy and posts follow.
    walk_length = 0.0
    walk = rings.get(MALL_WALKWAY_WAY)
    if walk and len(walk) >= 3:
        wcentre, waxis, whalf_u, whalf_v = min_area_rect(walk)
        wx, wy = waxis
        a = (wcentre[0] - wx * whalf_u, wcentre[1] - wy * whalf_u)
        b = (wcentre[0] + wx * whalf_u, wcentre[1] + wy * whalf_u)
        # Slide the whole canopy so whichever end is nearer the mall lands on
        # the entrance bay's face, keeping its surveyed length and bearing.
        inner = a if (math.dist(a, MALL_WALKWAY_ANCHOR)
                      < math.dist(b, MALL_WALKWAY_ANCHOR)) else b
        outer = b if inner is a else a
        shift = (MALL_WALKWAY_ANCHOR[0] - inner[0],
                 MALL_WALKWAY_ANCHOR[1] - inner[1])
        a = MALL_WALKWAY_ANCHOR
        b = (outer[0] + shift[0], outer[1] + shift[1])
        width = max(3.0, 2.0 * whalf_v)
        # The surveyed line ran out to the sidewalk; the shifted one overshoots
        # onto the avenue, so pull the far end back to the kerb.
        b = _trim_off_avenue(a, b, width, road_lines)
        walk_length = math.dist(a, b)

        nx, ny = -wy, wx
        posts = max(1, int(walk_length // 8.0))
        for i in range(posts + 1):
            t = i / float(posts)
            px = a[0] + (b[0] - a[0]) * t
            py = a[1] + (b[1] - a[1]) * t
            for side in (-width * 0.42, width * 0.42):
                v, f = box(px + nx * side, py + ny * side,
                           Z_BUILDING_BASE, MALL_WALKWAY_HEIGHT, 0.16, 0.16)
                walk_batch.add(v, f, mats["Mall_Trim"])
        v, f = raised_ribbon([a, b], width, MALL_WALKWAY_HEIGHT, 0.5)
        walk_batch.add(v, f, mats["Mall_Walkway"])
        v, f = ribbon([a, b], width * 0.85, 0.06)
        lot_batch.add(v, f, mats["Sidewalk"])

        # No entrance pediment. It stood at the inner end of the canopy and
        # read as a windowless building stuck on the end of a walkway; the
        # scanned mall's own entrance bay does that job now.

    log("Country Mall: {:d} surveyed wings, {:d} parking stripes, "
        "{:.0f} m covered walkway".format(wings, stripes, walk_length))


# ---------------------------------------------------------------------------
# Props
# ---------------------------------------------------------------------------

def tree(x, y, rng):
    """Low-poly broadleaf: tapered trunk plus a faceted canopy."""
    height = rng.uniform(4.0, 8.5)
    trunk_h = height * 0.42
    radius = rng.uniform(1.6, 3.0)
    trunk = box(x, y, 0.0, trunk_h, 0.22, 0.22, rng.uniform(0, 1.5))

    sides = 6
    ring_z = trunk_h + radius * 0.35
    ring = []
    for i in range(sides):
        a = 2 * math.pi * i / sides + rng.uniform(0, 0.4)
        ring.append((x + math.cos(a) * radius, y + math.sin(a) * radius, ring_z))
    verts = ring + [(x, y, trunk_h - 0.3), (x, y, height)]
    bottom = sides
    top = sides + 1
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, top))
        faces.append((j, i, bottom))
    return trunk, (verts, faces)


def palm(x, y, rng):
    """Coconut palm: leaning trunk with radiating fronds."""
    height = rng.uniform(6.0, 11.0)
    lean = rng.uniform(0.0, 0.9)
    lean_dir = rng.uniform(0, 2 * math.pi)
    tipx = x + math.cos(lean_dir) * lean
    tipy = y + math.sin(lean_dir) * lean

    trunk_verts = [
        (x - 0.22, y - 0.22, 0.0), (x + 0.22, y - 0.22, 0.0),
        (x + 0.22, y + 0.22, 0.0), (x - 0.22, y + 0.22, 0.0),
        (tipx - 0.14, tipy - 0.14, height), (tipx + 0.14, tipy - 0.14, height),
        (tipx + 0.14, tipy + 0.14, height), (tipx - 0.14, tipy + 0.14, height),
    ]
    trunk_faces = [(3, 2, 1, 0), (4, 5, 6, 7)]
    for i in range(4):
        j = (i + 1) % 4
        trunk_faces.append((i, j, j + 4, i + 4))

    verts = []
    faces = []
    fronds = 7
    for i in range(fronds):
        a = 2 * math.pi * i / fronds + rng.uniform(0, 0.3)
        reach = rng.uniform(2.4, 3.6)
        ex, ey = tipx + math.cos(a) * reach, tipy + math.sin(a) * reach
        px, py = -math.sin(a) * 0.42, math.cos(a) * 0.42
        base = len(verts)
        verts += [
            (tipx + px, tipy + py, height),
            (tipx - px, tipy - py, height),
            (ex - px * 0.3, ey - py * 0.3, height - rng.uniform(1.0, 2.0)),
            (ex + px * 0.3, ey + py * 0.3, height - rng.uniform(1.0, 2.0)),
        ]
        faces.append((base, base + 1, base + 2, base + 3))
    return (trunk_verts, trunk_faces), (verts, faces)


def street_light(x, y, angle):
    """Pole with a cantilevered arm, arm points along `angle`."""
    height = 8.0
    pole = box(x, y, 0.0, height, 0.16, 0.16)
    ax, ay = math.cos(angle), math.sin(angle)
    arm_len = 2.4
    arm = box(x + ax * arm_len * 0.5, y + ay * arm_len * 0.5,
              height - 0.28, height, arm_len * 0.5, 0.12, angle)
    lamp = box(x + ax * arm_len, y + ay * arm_len,
               height - 0.5, height - 0.24, 0.5, 0.24, angle)
    return pole, arm, lamp


def power_pole(x, y, angle):
    height = 9.5
    pole = box(x, y, 0.0, height, 0.18, 0.18)
    cross = box(x, y, height - 1.1, height - 0.9, 1.5, 0.1, angle)
    cross2 = box(x, y, height - 2.0, height - 1.85, 1.1, 0.09, angle)
    return pole, cross, cross2


def vehicle(x, y, angle, rng):
    """Two-box car, roughly 4.3 x 1.8 m."""
    length = rng.uniform(3.9, 4.8)
    width = rng.uniform(1.7, 1.95)
    body = box(x, y, 0.18, 0.85, length * 0.5, width * 0.5, angle)
    cabin = box(x - math.cos(angle) * length * 0.06,
                y - math.sin(angle) * length * 0.06,
                0.85, 1.42, length * 0.28, width * 0.44, angle)
    return body, cabin


# ---------------------------------------------------------------------------
# Blender plumbing
# ---------------------------------------------------------------------------

def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


# The colour attribute every tinted mesh writes, and the two nodes that read it
# back into albedo. prep_godot.py::check_palette() looks these up by name, so
# renaming any of them breaks the palette tripwire rather than silently
# disabling it.
TINT_LAYER = "Col"
TINT_ATTR_NODE = "VertexTint"
TINT_MIX_NODE = "TintMultiply"


def wire_vertex_tint(mat, linear):
    """Route a per-vertex colour attribute into Base Color as a multiplier.

    Base Color stops being a constant and becomes `intended x vertex`, which is
    what lets one material carry a whole district's worth of variation. Three
    things make this safe:

    * A mesh with NO "Col" attribute reads as white here, not black, so props,
      roads and markings that never write one are unaffected -- verified, since
      the opposite would have turned every untinted surface black.
    * The glTF exporter only promotes a colour attribute to COLOR_0 when the
      node tree actually reads it. Without this wiring it writes a white dummy
      COLOR_0 and dumps the real values into COLOR_1, which Godot ignores --
      i.e. the tint would silently do nothing in game.
    * The intended colour moves to the mix node's A socket, so it is still an
      authored constant that check_palette() can verify. Base Color's own
      default_value is dead after this and must NOT be trusted.
    """
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.name = TINT_ATTR_NODE
    attr.label = TINT_ATTR_NODE
    attr.layer_name = TINT_LAYER
    attr.location = (-560, 260)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.name = TINT_MIX_NODE
    mix.label = TINT_MIX_NODE
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.location = (-300, 260)
    mix.inputs["Factor"].default_value = 1.0
    # ShaderNodeMix carries a Factor/A/B triple per data type; the RGBA pair is
    # inputs 6 and 7 and output 2. Indices, because the names repeat.
    mix.inputs[6].default_value = (*linear, 1.0)
    nt.links.new(attr.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    return mix


def build_materials():
    mats = {}
    for name, srgb in PALETTE.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        linear = tuple(srgb_to_linear(c) for c in srgb)
        bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
        wire_vertex_tint(mat, linear)
        if name.startswith("Tower_Glass") or name in (
                "Tower_Charcoal", "Tower_Graphite", "UC_Glass",
                "UC_Glass_Dark", "Bloc_Tower_Dark", "Bloc_Tower_Light"):
            bsdf.inputs["Roughness"].default_value = 0.22
            bsdf.inputs["Metallic"].default_value = 0.1
        elif name == "Water":
            bsdf.inputs["Roughness"].default_value = 0.15
        elif name.startswith("Car_"):
            bsdf.inputs["Roughness"].default_value = 0.35
        else:
            bsdf.inputs["Roughness"].default_value = 0.85
        mat.diffuse_color = (*linear, 1.0)
        # prep_godot.py re-reads this to correct for Godot's importer.
        mat["intended_srgb"] = list(srgb)
        mats[name] = mat
    return mats


class MeshBatch:
    """Accumulates many features into one multi-material mesh."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.face_slots = []
        self.slots = []
        self._slot_of = {}
        # Parallel to self.verts, and only written out if something actually
        # asked for a tint. A mesh with no colour attribute costs nothing in
        # the GLB and reads as white through the wired materials, so untinted
        # geometry -- props, markings, the skyline -- stays exactly as it was.
        self.colors = []
        self.has_color = False

    def _slot(self, material):
        key = material.name
        if key not in self._slot_of:
            self._slot_of[key] = len(self.slots)
            self.slots.append(material)
        return self._slot_of[key]

    def add(self, verts, faces, material, colors=None):
        if not faces:
            return
        slot = self._slot(material)
        offset = len(self.verts)
        self.verts.extend(verts)
        if colors:
            self.colors.extend(colors)
            self.has_color = True
        else:
            self.colors.extend([WHITE] * len(verts))
        for f in faces:
            self.faces.append(tuple(i + offset for i in f))
            self.face_slots.append(slot)

    def is_empty(self):
        return not self.faces

    def to_object(self, name, collection):
        if self.is_empty():
            return None
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.validate(verbose=False)
        for material in self.slots:
            mesh.materials.append(material)
        if len(self.slots) > 1:
            for poly, slot in zip(mesh.polygons, self.face_slots):
                poly.material_index = slot
        if self.has_color:
            # POINT domain: every add() appends its own fresh vertices, so no
            # two features ever share one, and a per-vertex value needs no
            # per-loop fan-out. (build_slum.py writes UVs per loop for the same
            # reason -- there the layer is per-loop, so it has to.)
            layer = mesh.color_attributes.new(
                name=TINT_LAYER, type="FLOAT_COLOR", domain="POINT")
            for i, c in enumerate(self.colors):
                layer.data[i].color = c
            mesh.color_attributes.active_color = layer
            mesh.color_attributes.render_color_index = 0
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        return obj


def value_noise(x, y, period, seed):
    """Smoothed lattice noise in [0, 1]. One octave, bilinear, no gradients.

    Enough for ground mottling and cheaper than importing a Perlin: the ground
    grid is a few thousand vertices and this is called twice per vertex.
    """
    fx, fy = x / period, y / period
    x0, y0 = math.floor(fx), math.floor(fy)
    tx, ty = fx - x0, fy - y0
    # Smoothstep, so cell boundaries do not show as a lattice of creases.
    tx = tx * tx * (3.0 - 2.0 * tx)
    ty = ty * ty * (3.0 - 2.0 * ty)

    def corner(ix, iy):
        return hash_unit((ix * 73856093) ^ (iy * 19349663) ^ (seed * 83492791))

    a = corner(x0, y0) + (corner(x0 + 1, y0) - corner(x0, y0)) * tx
    b = corner(x0, y0 + 1) + (corner(x0 + 1, y0 + 1) - corner(x0, y0 + 1)) * tx
    return a + (b - a) * ty


# Ground mottling. Two octaves so the break-up has both a district-scale drift
# and a block-scale grain; kept low-amplitude because the ground reads mostly
# as a backdrop and banding here would be worse than the flatness it replaces.
GROUND_NOISE_COARSE = 420.0
GROUND_NOISE_FINE = 110.0
GROUND_NOISE_AMOUNT = 0.13
# How much darker the ground runs where it meets the road network. At a 100 m
# grid this cannot be a kerb-tight band -- that edge belongs to the sidewalk
# geometry, which already exists -- so it reads instead as the built-up core
# being dirtier than the green edges of the map, which is the honest effect
# available at this resolution.
GROUND_ROAD_DARKEN = 0.12
GROUND_ROAD_RADIUS = 120.0


def ground_colors(verts, road_field):
    """Per-vertex tint for the ground grid: mottling plus a road-side darkening.

    One flat colour over a 5 km square is the single largest uniform surface in
    the map, and it is what makes aerial shots read as a diagram. This does not
    add a triangle.
    """
    out = []
    for x, y, _z in verts:
        n = (value_noise(x, y, GROUND_NOISE_COARSE, 7) * 0.65
             + value_noise(x, y, GROUND_NOISE_FINE, 31) * 0.35)
        shade = 1.0 + (n - 0.5) * 2.0 * GROUND_NOISE_AMOUNT

        near = road_field.near(x, y, rings=1)
        if near:
            best = min(math.dist((sx, sy), (x, y)) for sx, sy, _v in near)
            if best < GROUND_ROAD_RADIUS:
                closeness = 1.0 - best / GROUND_ROAD_RADIUS
                shade *= 1.0 - GROUND_ROAD_DARKEN * closeness
        # Green channel lags red slightly so the mottling drifts toward dry
        # earth rather than staying a pure value ramp.
        out.append((shade, shade * (1.0 - (n - 0.5) * 0.05), shade * 0.985, 1.0))
    return out


LANDUSE_NOISE_PERIOD = 90.0
LANDUSE_NOISE_AMOUNT = 0.10


def _landuse_color(x, y, parcel_tint):
    n = value_noise(x, y, LANDUSE_NOISE_PERIOD, 53)
    shade = 1.0 + (n - 0.5) * 2.0 * LANDUSE_NOISE_AMOUNT
    r, g, b = parcel_tint
    return (r * shade, g * shade, b * shade, 1.0)


def tile_of(x, y):
    """Tile index for a Blender XY point. Row runs with +y, column with +x."""
    return (int(math.floor(y / TILE_SIZE)), int(math.floor(x / TILE_SIZE)))


def tile_key(row, col):
    return "r{:d}c{:d}".format(row, col)


def stamp_tile(obj):
    """Assign an already-built object to a tile by its own centroid.

    Everything is modelled at absolute map coordinates with the object sitting
    at the origin, so the mesh vertices are world positions.
    """
    if obj is None or not obj.data.vertices:
        return obj
    verts = obj.data.vertices
    cx = sum(v.co.x for v in verts) / len(verts)
    cy = sum(v.co.y for v in verts) / len(verts)
    obj["tile"] = tile_key(*tile_of(cx, cy))
    return obj


class TiledBatch:
    """A MeshBatch per 250 m tile, routed by each feature's centroid.

    A feature straddling a boundary is assigned whole to one tile rather than
    being clipped. The overdraw at a seam is a few metres and costs nothing;
    clipping would mean splitting polygons, and for the road ribbons it would
    also break the single-flat-surface-per-carriageway property that stops
    VehicleWheel3D chattering.
    """

    def __init__(self, name):
        self.name = name
        self.tiles = {}

    def add(self, verts, faces, material, colors=None):
        if not faces or not verts:
            return
        cx = sum(v[0] for v in verts) / len(verts)
        cy = sum(v[1] for v in verts) / len(verts)
        key = tile_of(cx, cy)
        batch = self.tiles.get(key)
        if batch is None:
            batch = MeshBatch()
            self.tiles[key] = batch
        batch.add(verts, faces, material, colors)

    def face_count(self):
        return sum(len(b.faces) for b in self.tiles.values())

    def to_objects(self, collection):
        made = []
        for (row, col), batch in sorted(self.tiles.items()):
            key = tile_key(row, col)
            obj = batch.to_object("{:s}__{:s}".format(self.name, key), collection)
            if obj is not None:
                obj["tile"] = key
                made.append(obj)
        return made


def skyline_silhouette(batch, obj, material):
    """Add a coarse prism for a hand-authored landmark tall enough to matter.

    The procedural building loop feeds the skyline with real footprints. The
    three hand-modelled landmarks are single finished meshes by the time we get
    here, so they contribute a convex-hull extrusion instead -- blobby up close,
    indistinguishable at the kilometre where it is the only thing being drawn.
    """
    if obj is None or not obj.data.vertices:
        return False
    verts = obj.data.vertices
    top = max(v.co.z for v in verts)
    if top < SKYLINE_MIN_HEIGHT:
        return False
    ring = convex_hull([(round(v.co.x, 1), round(v.co.y, 1)) for v in verts])
    if len(ring) < 3:
        return False
    v, f = walls(ring, Z_BUILDING_BASE, top)
    batch.add(v, f, material)
    v, f = parapet_roof(ring, top)
    batch.add(v, f, material)
    return True


def new_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def parse_height(tags):
    raw = tags.get("height")
    if raw:
        try:
            return max(2.5, float(str(raw).lower().replace("m", "").strip()))
        except ValueError:
            pass
    levels = tags.get("building:levels")
    if levels:
        try:
            return max(2.5, float(levels) * LEVEL_HEIGHT + 1.0)
        except ValueError:
            pass
    return DEFAULT_HEIGHTS.get(tags.get("building", "yes"), 6.0)


def safe_name(tags, fallback):
    name = tags.get("name")
    if not name:
        return fallback
    return "".join(ch for ch in name if ch.isprintable())[:56]


# ---------------------------------------------------------------------------
# Main build
# ---------------------------------------------------------------------------

def main():
    rng = random.Random(SEED)
    log("clearing scene")
    bpy.ops.wm.read_factory_settings(use_empty=True)

    data = json.loads(OSM_FILE.read_text(encoding="utf-8"))
    elements = data["elements"]
    ways = [e for e in elements if e["type"] == "way"]
    log("loaded {:d} OSM elements".format(len(elements)))

    mats = build_materials()
    col_ground = new_collection("Ground")
    col_roads = new_collection("Roads")
    col_water = new_collection("Water")
    col_buildings = new_collection("Buildings")
    col_landmarks = new_collection("Landmarks")
    col_props = new_collection("Props")

    # --- Road graph and terrain --------------------------------------------
    # Both come first: the graph carries the solved ground heights, and every
    # piece of geometry below is placed on them. Solving it inline rather than
    # as a post-step matters because the graph is rebuilt from scratch on every
    # run, so anything written to it afterwards is overwritten next time.
    global GROUND_AT
    graph, graph_skipped = build_road_graph(elements)
    height_report = None
    try:
        dem_field = terrain.PointField(terrain.load_dem())
        height_report = terrain.solve_node_heights(graph, dem_field)
        GROUND_AT = terrain.ground_sampler(graph, dem_field)
    except SystemExit as exc:
        # No elevation cache: build the old flat map rather than fail outright,
        # and say so loudly enough that nobody ships it by accident.
        GROUND_AT = None
        log("WARNING: terrain unavailable ({!s}); building FLAT".format(exc))

    # --- Ground ------------------------------------------------------------
    g = ground_half_extent(ways)
    ground = MeshBatch()
    if GROUND_AT is None:
        ground.add([(-g, -g, Z_GROUND), (g, -g, Z_GROUND),
                    (g, g, Z_GROUND), (-g, g, Z_GROUND)],
                   [(0, 1, 2, 3)], mats["Ground"])
        log("ground plane: {:.0f} x {:.0f} m, flat (no elevation data)".format(2 * g, 2 * g))
    else:
        # A grid rather than one quad, sampled from the solved road heights.
        # 100 m cells: fine enough that the ground meets the carriageways
        # cleanly (IDW near a road is dominated by that road), coarse enough
        # that this stays affordable as an always-resident mesh -- it is in
        # banilad_base.glb and never streams out.
        steps = int(math.ceil(2 * g / GROUND_CELL))
        verts = []
        for row in range(steps + 1):
            y = -g + row * GROUND_CELL
            for col in range(steps + 1):
                x = -g + col * GROUND_CELL
                verts.append((x, y, ground_at(x, y)))
        stride = steps + 1
        faces = []
        for row in range(steps):
            for col in range(steps):
                base = row * stride + col
                faces.append((base, base + 1, base + stride + 1, base + stride))
        ground.add(verts, faces, mats["Ground"],
                   ground_colors(verts, terrain.road_field(graph)))
        lows = [v[2] for v in verts]
        log("ground plane: {:.0f} x {:.0f} m, {:d} x {:d} cells, {:.1f}..{:.1f} m".format(
            2 * g, 2 * g, steps, steps, min(lows), max(lows)))
    ground.to_object("Ground", col_ground)

    # --- Sea ---------------------------------------------------------------
    # Always resident alongside Ground: it is a flat plane with one material,
    # and a horizon that streams in and out would be worse than useless.
    sea = MeshBatch()
    coast = coastline_segments(ways)
    sea_cells = build_sea(sea, mats["Water"], coast, g, GROUND_CELL)
    sea.to_object("Sea", col_water)
    log("sea: {:d} coastline segments, {:d} cells filled at y={:.1f}".format(
        len(coast), sea_cells, SEA_LEVEL))
    if not coast:
        log("  WARNING: no natural=coastline ways in the extract - the harbour "
            "will render as ground. Check overpass_query.txt.")

    # --- Landuse -----------------------------------------------------------
    landuse = TiledBatch("Landuse")
    green_polys = []
    nofill_polys = [UC_CAMPUS_BLOCK]
    parcel_rings = {}
    landuse_count = 0
    for el in ways:
        tags = el.get("tags", {})
        kind = tags.get("landuse") or tags.get("leisure")
        if not kind or "building" in tags:
            continue
        pts = way_points(el)
        if not is_closed(pts):
            continue
        verts, faces = flat_polygon(pts, layer_z(Z_LANDUSE, landuse_count))
        if not faces:
            continue
        is_green = kind in GREEN_TAGS
        draped = drape(verts)
        # Per-parcel tint plus the same mottling the ground carries, so a park
        # is not one flat green slab and two adjacent parcels of the same kind
        # do not merge into a single shape.
        parcel = tint_of(el["id"], hue=0.05 if is_green else 0.02, value=0.06)
        landuse.add(draped, faces,
                    mats["Landuse_Green" if is_green else "Landuse_Urban"],
                    [_landuse_color(x, y, parcel) for x, y, _z in draped])
        if is_green:
            green_polys.append(dedupe(pts[:-1]))
        elif kind in NOFILL_TAGS:
            nofill_polys.append(dedupe(pts[:-1]))
        if el["id"] == MALL_PARCEL_WAY:
            parcel_rings[MALL_PARCEL_WAY] = dedupe(pts[:-1])
        landuse_count += 1
    landuse.to_objects(col_ground)
    log("landuse areas: {:d} ({:d} no-infill districts)".format(
        landuse_count, len(nofill_polys)))

    # --- Water -------------------------------------------------------------
    water = TiledBatch("Water")
    water_lines = []
    water_count = 0
    for el in ways:
        tags = el.get("tags", {})
        pts = way_points(el)
        if len(pts) < 2:
            continue
        zw = layer_z(Z_WATER, water_count)
        if tags.get("natural") == "water" and is_closed(pts):
            verts, faces = flat_polygon(pts, zw)
        elif "waterway" in tags:
            if is_closed(pts):
                verts, faces = flat_polygon(pts, zw)
            else:
                width = 14.0 if tags["waterway"] in ("river", "stream") else 8.0
                try:
                    width = max(width, float(tags.get("width", 0)))
                except ValueError:
                    pass
                verts, faces = ribbon(pts, width, zw)
                water_lines.append((dedupe(pts), width))
        else:
            continue
        water.add(drape(verts), faces, mats["Water"])
        water_count += 1
    water.to_objects(col_water)
    log("water features: {:d}".format(water_count))

    # --- Roads, sidewalks and markings -------------------------------------
    roads_major = TiledBatch("Roads_Major")
    roads_minor = TiledBatch("Roads_Minor")
    footways = TiledBatch("Footways")
    sidewalks = TiledBatch("Sidewalks")
    markings = TiledBatch("Markings")

    road_lines = []      # (points, width, class) reused for props
    road_count = 0

    # Pass 1: resolve every centreline and width up front, so pass 2 can ask
    # "is this point on another road's tarmac?" while it builds.
    resolved = []
    for el in ways:
        tags = el.get("tags", {})
        cls = tags.get("highway")
        if not cls or cls in EXCLUDED_ROAD_CLASSES:
            continue
        pts = dedupe(way_points(el))
        if len(pts) < 2:
            continue

        resolved.append((pts, road_width(cls, tags), cls))

    carriageways = SpatialIndex()
    for way_index, (pts, width, cls) in enumerate(resolved):
        if cls in FOOT_ROADS:
            continue
        for i in range(len(pts) - 1):
            carriageways.add_segment(
                pts[i], pts[i + 1], (pts[i], pts[i + 1], width * 0.5, way_index)
            )

    clipped_walks = 0
    for way_index, (pts, width, cls) in enumerate(resolved):
        if cls in MAJOR_ROADS:
            target, z, mat = roads_major, Z_ROAD_MAJOR, mats["Road_Major"]
        elif cls in FOOT_ROADS:
            target, z, mat = footways, Z_FOOTWAY, mats["Footway"]
        else:
            target, z, mat = roads_minor, Z_ROAD_MINOR, mats["Road_Minor"]

        rz = layer_z(z, road_count)
        verts, faces = ribbon(pts, width, rz)
        target.add(drape(verts), faces, mat)

        # Kerbed sidewalks and centre lines only on driveable streets.
        #
        # Both are generated along the way's whole length, so without clipping
        # they run straight over every road that crosses them -- a raised kerb
        # slab lying across the avenue, which is a step the car hits as well as
        # something that looks wrong. Breaking them where they enter another
        # carriageway leaves the gap a real junction has.
        if cls in MAJOR_ROADS or cls in ("unclassified", "residential"):
            walk_offset = width * 0.5 + SIDEWALK_WIDTH * 0.5
            for side in (walk_offset, -walk_offset):
                line = offset_polyline(pts, side)
                if len(line) < 2:
                    continue
                runs = clip_against_carriageways(
                    line, carriageways, way_index, SIDEWALK_WIDTH * 0.5 + 0.15
                )
                if len(runs) > 1:
                    clipped_walks += 1
                for run in runs:
                    v, f = raised_ribbon(run, SIDEWALK_WIDTH,
                                         layer_z(Z_SIDEWALK, road_count), KERB_HEIGHT)
                    sidewalks.add(drape(v), f, mats["Sidewalk"])

        if cls in MAJOR_ROADS:
            for run in clip_against_carriageways(pts, carriageways, way_index, 0.3):
                v, f = dashed_line(run, layer_z(Z_MARKING, road_count))
                markings.add(drape(v), f, mats["Marking_White"])
            for side in (width * 0.5 - 0.5, -(width * 0.5 - 0.5)):
                edge = offset_polyline(pts, side)
                if len(edge) < 2:
                    continue
                for run in clip_against_carriageways(edge, carriageways, way_index, 0.3):
                    v, f = ribbon(run, 0.18, layer_z(Z_MARKING, road_count))
                    markings.add(drape(v), f, mats["Marking_Yellow"])

        road_lines.append((pts, width, cls))
        road_count += 1

    # One flat collision surface for every carriageway.
    #
    # The visual ribbons are nudged apart by layer_z so they do not z-fight,
    # which at a junction stacks up to LAYER_SLOTS collidable surfaces inside
    # 3 cm, with the ground plane a further 13 cm below. VehicleWheel3D rays
    # would hit a different one of those every frame and chatter. Physics reads
    # this single coplanar mesh instead; prep_godot.py marks the visual road
    # meshes no-collide and exports this one as collision-only, so it never
    # renders.
    #
    # Footways are skipped: at 5 cm they are close enough to the ground plane
    # that walking on the ground underneath is indistinguishable.
    road_collision = MeshBatch()
    collision_ways = 0
    for pts, width, cls in road_lines:
        if cls in FOOT_ROADS:
            continue
        # Draped like the visual ribbons, and for the same reason it was flat
        # before: it stays ONE surface per carriageway. Physics reads this, not
        # the layer_z-staggered visuals, so a wheel ray still finds exactly one
        # hit per road no matter how the terrain runs beneath it.
        #
        # Deliberately NOT densified. Tessellating to 4 m was tried to shrink
        # the millimetre disagreement between crossing ribbons; it took the
        # gaps from 46 mm to 19 mm but grew this mesh -- which is never
        # unloaded -- from 66k triangles to 251k, 3.5 MB to 14 MB. That is a
        # bad trade for a partial fix. The real answer is junction fill quads
        # (CITY_MASTER_PLAN.md section 3.2): one flat patch of tarmac per
        # junction, replacing the overlap rather than tessellating around it.
        v, f = ribbon(pts, width, Z_ROAD_COLLISION)
        road_collision.add(drape(v), f, mats["Road_Major"])
        collision_ways += 1

    roads_major.to_objects(col_roads)
    roads_minor.to_objects(col_roads)
    footways.to_objects(col_roads)
    sidewalks.to_objects(col_roads)
    markings.to_objects(col_roads)
    # NOT tiled: physics must never be missing under a moving car, and this
    # mesh is flat untextured ribbons, so it is cheap to keep resident.
    road_collision.to_object("Roads_Collision", col_roads)
    log("road ways: {:d}".format(road_count))
    log("sidewalks broken at junctions: {:d}".format(clipped_walks))
    log("drive collision ways: {:d} (flat at z={:.3f})".format(
        collision_ways, Z_ROAD_COLLISION))

    # --- Road graph report -------------------------------------------------
    # The graph itself is built at the top of main(), because the terrain
    # solved from it is what every piece of geometry above is draped onto.
    ROAD_GRAPH_OUT.parent.mkdir(parents=True, exist_ok=True)
    ROAD_GRAPH_OUT.write_text(json.dumps(graph), encoding="utf-8")
    signals = sum(1 for n in graph["nodes"] if n["signal"])
    crossings = sum(1 for n in graph["nodes"] if n["crossing"])
    stops = sum(1 for n in graph["nodes"] if n["stop"])
    oneways = sum(1 for e in graph["edges"] if e["oneway"])
    roundabouts = sum(1 for e in graph["edges"] if e["roundabout"])
    named = sorted({e["name"] for e in graph["edges"] if e["name"]})
    log("road graph: {:d} nodes, {:d} edges, {:d} named streets".format(
        len(graph["nodes"]), len(graph["edges"]), len(named)))
    log("road graph: {:d} signals, {:d} crossings, {:d} stop/give-way".format(
        signals, crossings, stops))
    log("road graph: {:d} one-way edges, {:d} roundabout edges, {:d} skipped".format(
        oneways, roundabouts, graph_skipped))
    if height_report:
        log("road graph: heights {min:.1f}..{max:.1f} m, smoothing moved nodes "
            "{mean_shift:.2f} m mean / {max_shift:.1f} m max, {grade_fixes:,d} "
            "grade corrections".format(**height_report))
    log("road graph: wrote {:s}".format(ROAD_GRAPH_OUT.name))

    # --- Buildings ---------------------------------------------------------
    building_batch = TiledBatch("Buildings")
    window_batch = TiledBatch("Windows")
    # Always resident, never tiled: the distant-city silhouette.
    skyline = MeshBatch()
    skyline_count = 0
    building_count = 0
    landmark_count = 0
    pitched = 0
    towers = 0
    shopfronts = 0
    roof_clutter = 0
    footprints = []

    # Footprints the hand-authored landmark builders need, keyed by OSM way id.
    landmark_rings = {}

    for el in ways:
        tags = el.get("tags", {})
        if "building" not in tags and "building:part" not in tags:
            continue
        pts = way_points(el)
        if not is_closed(pts):
            continue
        ring = dedupe(pts[:-1])
        if len(ring) < 3:
            continue

        height = parse_height(tags)
        oid = el["id"]
        footprints.append(ring)

        # The two landmarks are modelled by hand further down. Their footprints
        # still count above so infill housing keeps off them.
        if oid in LANDMARK_WAY_IDS:
            landmark_rings[oid] = ring
            continue

        # Named buildings become their own object so gameplay can find them;
        # the rest are batched. Windows follow whichever mesh owns the walls.
        named = "name" in tags
        owner = MeshBatch() if named else building_batch
        window_owner = owner if named else window_batch

        # Sit the building on the HIGH corner of its footprint and carry the
        # walls down to the low one. Founding it on the mean would bury the
        # uphill side; the extra wall below ground level is a plinth, which is
        # exactly how Cebu builds on a slope.
        low, high = ground_span(ring)
        base = high
        plinth = (high - low) + PLINTH_MARGIN

        # Which district this building stands in decides its palette, how far
        # its colour may stray and whether it gets a shopfront. Measured at the
        # footprint centroid so a building never straddles two answers.
        cxr = sum(p[0] for p in ring) / len(ring)
        cyr = sum(p[1] for p in ring) / len(ring)
        district = district_at(cxr, cyr)

        # One tint per building, shared by walls, roof, windows and any tower
        # detail, so the whole massing reads as one painted structure rather
        # than a stack of independently coloured parts.
        tint = tint_of(oid, hue=0.03 * district["tint"],
                       value=0.04 * district["tint"])
        target = TintedBatch(owner, tint, base)
        windows = TintedBatch(window_owner, tint, base)

        area = abs(signed_area(ring))
        if height <= PITCHED_ROOF_MAX and area <= PITCHED_ROOF_MAX_AREA:
            # Palette comes from the district, not one global list. `oid %` is
            # kept as the index so a given building keeps its material across
            # rebuilds; the banding it used to cause is handled by the tint,
            # which is continuous rather than seven buckets.
            walls_list = district["walls"]
            roofs_list = district["roofs"]
            wall_mat = mats[walls_list[oid % len(walls_list)]]
            roof_mat = mats[roofs_list[oid % len(roofs_list)]]
            eave = height
            v, f = walls(ring, Z_BUILDING_BASE - plinth, eave)
            target.add(lift(v, base), f, wall_mat)
            v, f, _rise = hip_roof(ring, eave)
            target.add(lift(v, base), f, roof_mat)
            pitched += 1

            # Most of Cebu is one to three storeys, and until now all of it was
            # a blank painted box from ground to eaves. A shorter band starting
            # lower is what a shophouse actually has; the mid-rise defaults
            # clear no floors at all on a 6 m wall.
            shop = wants_shopfront(tags, district, oid) and eave >= 3.4
            # Where there is a shopfront the residential window course has to
            # start above the sign fascia. Both stand proud of the same wall by
            # about the same 5-6 cm, so an overlap in z is not a stacking
            # order -- it is two near-coplanar surfaces that z-fight.
            first = SHOPFRONT_HEAD + SIGN_HEIGHT + 0.25 if shop else 2.2
            v, f = window_bands(ring, Z_BUILDING_BASE, eave,
                                floor_height=3.0, band=1.0, first_floor=first,
                                min_edge=1.4, inset=0.55)
            windows.add(lift(v, base), f, mats["Window"])
            if shop:
                shopfront_band(windows, mats, ring, base + Z_BUILDING_BASE, oid)
                shopfronts += 1
        else:
            is_tower = height >= TOWER_MIN_HEIGHT
            if is_tower:
                cladding, glazing = TOWER_SCHEME_BY_NAME.get(
                    safe_name(tags, ""), TOWER_SCHEMES[oid % len(TOWER_SCHEMES)])
                wall_mat = mats[cladding]
                roof_mat = mats["Roof_Deck"]
            else:
                # Mid-rise keeps its own list: the district `walls` are chosen
                # for one- to three-storey stock, and a 20 m slab in painted
                # hollow block reads wrong. Districts whose identity actually
                # turns on their mid-rise give an explicit `walls_mid`.
                mid = district.get("walls_mid") or WALL_MID
                wall_mat = mats[mid[oid % len(mid)]]
                roof_mat = mats["Roof_Flat"]
            wall_v, wall_f = walls(ring, Z_BUILDING_BASE - plinth, height)
            wall_v = lift(wall_v, base)
            target.add(wall_v, wall_f, wall_mat)
            roof_v, roof_f = parapet_roof(ring, height)
            roof_v = lift(roof_v, base)
            target.add(roof_v, roof_f, roof_mat)

            # Tall enough to read from across the city: contribute the bare
            # massing to the always-resident skyline. Real footprint, no
            # windows, no crown, no plant -- this is only ever seen at range.
            if height >= SKYLINE_MIN_HEIGHT:
                skyline.add(wall_v, wall_f, wall_mat)
                skyline.add(roof_v, roof_f, roof_mat)
                skyline_count += 1

            if is_tower:
                # Podium, curtain wall, crown and plant. Without this the IT
                # Park district is a field of bare prisms.
                tower_detail(LiftedBatch(target, base), mats, ring, height,
                             glass=glazing)
                towers += 1
            else:
                v, f = window_bands(ring, Z_BUILDING_BASE, height)
                windows.add(lift(v, base), f, mats["Window"])
                # Flat roofs only -- these are the ones a tower or a hillside
                # actually looks down onto. A hip roof sheds, so nothing stands
                # on it.
                roof_clutter += roof_clutter_field(
                    target, mats, ring, base + height, oid)
                # Mid-rise glazing starts at 3.6 m, clear of the 3.45 m top of
                # the sign fascia, so no extra separation is needed here.
                if wants_shopfront(tags, district, oid):
                    shopfront_band(windows, mats, ring,
                                   base + Z_BUILDING_BASE, oid)
                    shopfronts += 1

        building_count += 1

        if named:
            landmark_obj = owner.to_object(
                safe_name(tags, "Building_{:d}".format(oid)), col_landmarks)
            # Stable identity. The Blender object name is the OSM `name` tag,
            # and Blender appends .001/.002 to duplicates in creation order --
            # so "Petron" means a different petrol station the moment another
            # one enters the extract, and every downstream reference silently
            # re-points. Cebu has many Petrons, Shells and Jollibees, so this
            # gets worse with every slice. The way id never moves.
            if landmark_obj is not None:
                landmark_obj["osm_way"] = oid
                stamp_tile(landmark_obj)
            landmark_count += 1

    log("buildings: {:d} ({:d} pitched roofs, {:d} detailed towers, "
        "{:d} named landmarks)".format(
            building_count, pitched, towers, landmark_count))
    log("  {:d} shopfront frontages, {:d} roof clutter units".format(
        shopfronts, roof_clutter))

    # --- Hand-authored landmarks -------------------------------------------
    landmark_rings.update(parcel_rings)
    # landmarks.LANDMARK_WAYS is excluded here: those are collected by id inside
    # build_city_landmarks() further down, because most of them carry no
    # `building` tag and so never reach landmark_rings from the loop above.
    # Each reports its own absence there.
    missing = sorted((LANDMARK_WAY_IDS - landmarks.LANDMARK_WAYS
                      | {MALL_PARCEL_WAY}) - set(landmark_rings))
    if missing:
        log("WARNING: landmark ways absent from the OSM extract: {:s}".format(
            ", ".join(str(m) for m in missing)))

    # The hand-authored landmarks are drawn from z=0 like everything else, so
    # each is seated on the terrain under its own footprint. One height per
    # building, not per vertex: these are flat-platform structures and draping
    # would warp their floor plates.
    uc_seat = ground_at(51.0, 449.0)
    mall_seat = ground_at(-87.0, 519.0)
    bloc_seat = ground_at(-462.0, -419.0)

    uc_batch = MeshBatch()
    build_uc_banilad(LiftedBatch(uc_batch, uc_seat), mats,
                     [landmark_rings[w] for w in sorted(UC_WAY_IDS)
                      if w in landmark_rings])
    uc_obj = uc_batch.to_object("University of Cebu - Banilad Campus", col_landmarks)

    mall_batch = MeshBatch()
    mall_lot = TiledBatch("Mall_Car_Park")
    mall_walk = MeshBatch()
    # The car park is DRAPED, not lifted: it is a ground surface spanning ~197 m
    # over 4.2 m of fall, so a rigid slab at one height floats clear of the
    # tarmac at the low end and buries it at the high end. The mall itself and
    # its covered walkway stay rigid -- they have floor plates.
    build_country_mall(LiftedBatch(mall_batch, mall_seat),
                       DrapedBatch(mall_lot),
                       LiftedBatch(mall_walk, mall_seat), mats, landmark_rings,
                       road_lines)
    mall_obj = mall_batch.to_object("Gaisano Country Mall", col_landmarks)
    walk_obj = mall_walk.to_object("Mall_Walkway", col_landmarks)

    bloc_batch = MeshBatch()
    build_central_bloc(LiftedBatch(bloc_batch, bloc_seat), mats, landmark_rings)
    bloc_obj = bloc_batch.to_object("Ayala Malls Central Bloc", col_landmarks)

    landmark_objs = build_city_landmarks(ways, landmark_rings, mats,
                                         col_landmarks, rng)
    # Named like the other batched decals, not like a landmark: it is a flat
    # slab of tarmac and paint that must never become collision geometry.
    mall_lot.to_objects(col_ground)

    # The hand-authored landmarks are finished single meshes by now, so they
    # cannot feed the skyline from the building loop. Tall ones contribute a
    # hull extrusion instead. Ayala Malls Central Bloc is the one that matters:
    # at 74 m and ~1 km from the Banilad spawn it is the horizon.
    for obj in [uc_obj, mall_obj, walk_obj, bloc_obj] + landmark_objs:
        stamp_tile(obj)
        if skyline_silhouette(skyline, obj, mats["Wall_Concrete_1"]):
            skyline_count += 1

    infill_batch = TiledBatch("Buildings_Infill")
    infill_count, infill_shops = place_infill_housing(
        infill_batch, mats, road_lines, water_lines,
        footprints, green_polys, nofill_polys, rng)
    infill_batch.to_objects(col_buildings)
    log("infill houses: {:d} ({:d} with a shopfront)".format(
        infill_count, infill_shops))

    building_batch.to_objects(col_buildings)
    window_batch.to_objects(col_buildings)
    skyline.to_object("Skyline", col_buildings)
    log("skyline: {:d} masses at or above {:.0f} m".format(
        skyline_count, SKYLINE_MIN_HEIGHT))

    # --- Props -------------------------------------------------------------
    # Trunks, poles and vehicles block the player; canopies and lamp heads are
    # kept separate so they never become collision or floating navmesh.
    solid = TiledBatch("Props_Solid")
    foliage = TiledBatch("Props_Foliage")
    # Props are narrow enough to drape: a pole or trunk just translates, and a
    # parked car picks up a slight tilt down the slope, which is correct.
    draped_solid = DrapedBatch(solid)
    draped_foliage = DrapedBatch(foliage)
    trees_placed = place_trees(draped_solid, draped_foliage, mats, green_polys,
                               footprints, rng)
    lights_placed, poles_placed = place_street_furniture(
        draped_solid, draped_foliage, mats, road_lines, rng)
    cars_placed = place_vehicles(draped_solid, mats, road_lines, rng)
    solid.to_objects(col_props)
    foliage.to_objects(col_props)
    log("props: {:d} trees, {:d} street lights, {:d} power poles, {:d} vehicles".format(
        trees_placed, lights_placed, poles_placed, cars_placed))

    # --- Lighting, camera, output ------------------------------------------
    setup_scene()
    save_and_export()


def build_city_landmarks(ways, landmark_rings, mats, collection, rng):
    """Hand-authored massing for the places a Cebuano recognises on sight.

    Each is seated on the terrain under its own footprint, like the UC and mall
    builders: one height per structure, not per vertex, because these are flat-
    platform buildings and draping would warp their floor plates.

    Anything whose OSM way is missing from the extract is skipped with a
    warning rather than crashing the build -- the extent has been widened four
    times already and will be again.
    """
    # Collect every footprint these need straight off the extract by id.
    #
    # The building loop cannot supply them: it only records ways carrying a
    # `building` tag, and most of these do not have one. Fort San Pedro is
    # `historic=fort`, the Colon obelisk is `historic=memorial`, Ayala Center is
    # `landuse=commercial`, the piers are untagged, The Terraces is a car park
    # and Fuente Osmena is three carriageways. Keying off the OSM way id rather
    # than a tag is the only thing they have in common.
    wanted = landmarks.LANDMARK_WAYS | set(landmarks.FUENTE_CIRCLE_WAYS)
    for el in ways:
        if el["id"] not in wanted:
            continue
        pts = way_points(el)
        if len(pts) >= 3:
            landmark_rings[el["id"]] = dedupe(
                pts[:-1] if is_closed(pts) else pts)

    made = []
    built = 0

    def emit(name, ring, fn, drape_it=False, skirt_mat="Wall_Concrete_1"):
        """Run one builder into its own object, sitting it on the terrain.

        Two ways to meet the ground, and picking the wrong one is visible from
        across the district:

        * A STRUCTURE keeps a flat floor plate, so it is seated on the HIGHEST
          corner of its footprint and carried down to the lowest on a plinth --
          exactly what the procedural building loop does, and what `drape()`
          explains it deliberately does not do. Seating on the centroid instead
          leaves the low side floating: Ayala Center spans 15 m of fall across
          353 m, so its downhill corner hung nearly 8 m in the air.
        * A GROUND SURFACE -- a park, a plaza, a car park -- has no floor plate
          and must follow the terrain, so it is draped per vertex. Garden Bloc
          is 183 m across 9 m of fall; lifted rigidly its lawn became a slab
          floating 4 m over the low end, and fast-travelling there put the
          player UNDERNEATH it, in the dark.
        """
        nonlocal built
        if ring is None or len(ring) < 3:
            log("  WARNING: {:s} absent from the OSM extract, skipped".format(name))
            return None
        batch = MeshBatch()
        if drape_it:
            fn(DrapedBatch(batch), ring)
        else:
            low, high = ground_span(ring)
            fn(LiftedBatch(batch, high), ring)
            # Plinth down to the low corner, so nothing hangs in the air.
            drop = (high - low) + PLINTH_MARGIN
            if drop > 0.05:
                v, f = landmarks.prism(ring, -drop, 0.05, cap_top=False)
                batch.add(lift(v, high), f, mats[skirt_mat])
        obj = batch.to_object(name, collection)
        if obj is not None:
            made.append(obj)
            built += 1
        return obj

    # offset_ring is passed in rather than imported: build_map imports
    # landmarks, so landmarks cannot import back, and the fort needs a real
    # polygon offset for its inner wall face -- a radial scale distorts a
    # three-lobed outline badly.
    emit("Fort San Pedro", landmark_rings.get(landmarks.FORT_SAN_PEDRO_WAY),
         lambda b, r: landmarks.build_fort_san_pedro(b, mats, r, offset_ring),
         skirt_mat="Fort_Stone")
    emit("Magellan's Cross Pavilion",
         landmark_rings.get(landmarks.MAGELLAN_PAVILION_WAY),
         lambda b, r: landmarks.build_magellans_cross(b, mats, r))
    emit("Basilica Minore del Santo Nino Belfry",
         landmark_rings.get(landmarks.BASILICA_BELFRY_WAY),
         lambda b, r: landmarks.build_basilica_belfry(b, mats, r))
    emit("Colon Obelisk", landmark_rings.get(landmarks.COLON_OBELISK_WAY),
         lambda b, r: landmarks.build_colon_obelisk(b, mats, r))
    emit("Metro Department Store", landmark_rings.get(landmarks.METRO_COLON_WAY),
         lambda b, r: landmarks.build_metro_colon(b, mats, r))
    emit("Colon Corner Block",
         landmark_rings.get(landmarks.COLON_CORNER_BLOCK_WAY),
         lambda b, r: landmarks.build_colon_corner_block(b, mats, r))
    emit("Ayala Center Cebu", landmark_rings.get(landmarks.AYALA_CENTER_WAY),
         lambda b, r: landmarks.build_ayala_center(b, mats, r, rng))
    # Cebu IT Park is a SEPARATE district 1.4 km north of Ayala Center; its
    # towers come from the generic loop with real OSM heights, so what it needs
    # is the campus green at their centre.
    emit("Garden Bloc", landmark_rings.get(landmarks.IT_PARK_GARDEN_WAY),
         lambda b, r: landmarks.build_it_park_garden(b, mats, r, rng),
         drape_it=True)

    for i, way in enumerate(landmarks.CARBON_HALL_WAYS):
        emit("Carbon Market Hall {:d}".format(i + 1), landmark_rings.get(way),
             lambda b, r, s=way: landmarks.build_carbon_hall(b, mats, r, s))

    for i, way in enumerate(landmarks.PIER_WAYS):
        emit("Cebu Port Pier {:d}".format(i + 1), landmark_rings.get(way),
             lambda b, r: landmarks.build_pier(b, mats, r, rng))

    # Fuente Osmena: a rotunda, so the park is the disc the carriageways
    # enclose. Take the largest of them and work from its centre and radius.
    circles = [landmark_rings[w] for w in landmarks.FUENTE_CIRCLE_WAYS
               if w in landmark_rings]
    if circles:
        # Pool every point from all three ways and take the BOUNDING BOX
        # centre, not a centroid. OSM splits the rotunda into arcs rather than
        # one closed circle, and the centroid of an arc is pulled well inside
        # the circle it belongs to -- doing that put the fountain 20 m off,
        # sitting on the kerb instead of in the middle of the park.
        pooled = [p for ring in circles for p in ring]
        xs = [p[0] for p in pooled]
        ys = [p[1] for p in pooled]
        cx = (min(xs) + max(xs)) * 0.5
        cy = (min(ys) + max(ys)) * 0.5
        radius = sum(math.dist(p, (cx, cy)) for p in pooled) / len(pooled)
        batch = MeshBatch()
        landmarks.build_fuente_circle(LiftedBatch(batch, ground_at(cx, cy)),
                                      mats, cx, cy, radius)
        obj = batch.to_object("Fuente Osmena Circle", collection)
        if obj is not None:
            made.append(obj)
            built += 1
        log("  Fuente Osmena: rotunda r={:.1f} m at ({:.0f}, {:.0f})".format(
            radius, cx, cy))
    else:
        log("  WARNING: Fuente Osmena carriageways absent, rotunda skipped")

    # Carbon's stall field, around the midpoint of the three halls. Batched into
    # tiles rather than one object: it is hundreds of small canopies and it
    # should stream with the district.
    halls = [landmark_rings[w] for w in landmarks.CARBON_HALL_WAYS
             if w in landmark_rings]
    stalls = 0
    if halls:
        hx = sum(sum(p[0] for p in r) / len(r) for r in halls) / len(halls)
        hy = sum(sum(p[1] for p in r) / len(r) for r in halls) / len(halls)
        boxes = []
        for r in halls:
            xs = [p[0] for p in r]
            ys = [p[1] for p in r]
            boxes.append((min(xs) - 4.0, min(ys) - 4.0,
                          max(xs) + 4.0, max(ys) + 4.0))

        def blocked(x, y):
            return any(b[0] <= x <= b[2] and b[1] <= y <= b[3] for b in boxes)

        stall_batch = TiledBatch("Carbon_Stalls")
        stalls = landmarks.build_carbon_stalls(
            DrapedBatch(stall_batch), mats, hx, hy, 165.0, rng, blocked)
        stall_batch.to_objects(collection)

    log("landmarks: {:d} hand-authored, {:d} Carbon stall canopies".format(
        built, stalls))
    return made


class SpatialIndex:
    """Uniform grid for 'what is near this point' queries during infill."""

    def __init__(self, cell=28.0):
        self.cell = cell
        self.buckets = {}

    def _key(self, x, y):
        return (int(math.floor(x / self.cell)), int(math.floor(y / self.cell)))

    def add_segment(self, p0, p1, payload):
        steps = max(1, int(math.dist(p0, p1) / self.cell) + 1)
        for i in range(steps + 1):
            t = i / steps
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t
            self.buckets.setdefault(self._key(x, y), []).append(payload)

    def add_point(self, x, y, payload):
        self.buckets.setdefault(self._key(x, y), []).append(payload)

    def near(self, x, y, radius=1):
        cx, cy = self._key(x, y)
        out = []
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                out.extend(self.buckets.get((cx + dx, cy + dy), ()))
        return out


def point_segment_distance(px, py, p0, p1):
    x0, y0 = p0
    x1, y1 = p1
    dx, dy = x1 - x0, y1 - y0
    length_sq = dx * dx + dy * dy
    if length_sq < 1e-9:
        return math.dist((px, py), p0), 0.0
    t = max(0.0, min(1.0, ((px - x0) * dx + (py - y0) * dy) / length_sq))
    return math.dist((px, py), (x0 + dx * t, y0 + dy * t)), math.atan2(dy, dx)


def place_infill_housing(batch, mats, road_lines, water_lines, footprints,
                         green_polys, nofill_polys, rng):
    """Fill unmapped blocks with small houses so the district reads as built up."""
    roads = SpatialIndex()
    for pts, width, cls in road_lines:
        for i in range(len(pts) - 1):
            roads.add_segment(pts[i], pts[i + 1], (pts[i], pts[i + 1], width))

    water = SpatialIndex()
    for pts, width in water_lines:
        for i in range(len(pts) - 1):
            water.add_segment(pts[i], pts[i + 1], (pts[i], pts[i + 1], width))

    existing = SpatialIndex()
    for ring in footprints:
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        bbox = (min(xs), min(ys), max(xs), max(ys))
        cx, cy = (bbox[0] + bbox[2]) * 0.5, (bbox[1] + bbox[3]) * 0.5
        existing.add_point(cx, cy, bbox)
        # Large footprints need registering in more than one bucket.
        existing.add_point(bbox[0], bbox[1], bbox)
        existing.add_point(bbox[2], bbox[3], bbox)

    green_boxes = []
    for poly in green_polys:
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        green_boxes.append(((min(xs), min(ys), max(xs), max(ys)), poly))

    nofill_boxes = []
    for poly in nofill_polys:
        if len(poly) < 3:
            continue
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        nofill_boxes.append(((min(xs), min(ys), max(xs), max(ys)), poly))

    x0, y0, x1, y1 = INFILL_BOUNDS
    placed = 0
    infill_shops = 0
    y = y0
    while y < y1 and placed < INFILL_LIMIT:
        x = x0
        while x < x1 and placed < INFILL_LIMIT:
            px = x + rng.uniform(-3.5, 3.5)
            py = y + rng.uniform(-3.5, 3.5)
            x += INFILL_SPACING

            # The slum districts own these blocks; see SLUM_DISTRICTS.
            if in_any_slum(px, py, SLUM_PAD):
                continue

            # Must sit clear of the carriageway but still front a street.
            best = None
            for p0, p1, width in roads.near(px, py):
                distance, heading = point_segment_distance(px, py, p0, p1)
                clearance = width * 0.5 + INFILL_ROAD_CLEARANCE
                if distance < clearance:
                    best = None
                    break
                if best is None or distance < best[0]:
                    best = (distance, heading)
            if best is None or best[0] > INFILL_ROAD_MAX_DISTANCE:
                continue

            if any(
                point_segment_distance(px, py, p0, p1)[0] < width * 0.5 + INFILL_WATER_CLEARANCE
                for p0, p1, width in water.near(px, py)
            ):
                continue

            if any(
                bbox[0] - INFILL_BUILDING_CLEARANCE < px < bbox[2] + INFILL_BUILDING_CLEARANCE
                and bbox[1] - INFILL_BUILDING_CLEARANCE < py < bbox[3] + INFILL_BUILDING_CLEARANCE
                for bbox in existing.near(px, py, radius=2)
            ):
                continue

            if any(
                box[0] <= px <= box[2] and box[1] <= py <= box[3]
                and point_in_polygon(px, py, poly)
                for box, poly in green_boxes
            ):
                continue

            if any(
                box[0] <= px <= box[2] and box[1] <= py <= box[3]
                and point_in_polygon(px, py, poly)
                for box, poly in nofill_boxes
            ):
                continue

            # Face the house toward the street it fronts.
            angle = best[1] + rng.choice((0.0, math.pi))
            # Mixed stock rather than one size: most of Banilad's filler is
            # small single-storey housing with the odd taller lot among it.
            if rng.random() < 0.55:
                half_x = rng.uniform(2.2, 3.8)
                half_y = rng.uniform(2.0, 3.2)
                height = rng.uniform(2.4, 3.6)
            else:
                half_x = rng.uniform(3.4, 5.6)
                half_y = rng.uniform(2.8, 4.4)
                height = rng.uniform(3.0, 6.4)

            ca, sa = math.cos(angle), math.sin(angle)
            ring = []
            for dx, dy in ((-half_x, -half_y), (half_x, -half_y),
                           (half_x, half_y), (-half_x, half_y)):
                ring.append((px + dx * ca - dy * sa, py + dx * sa + dy * ca))

            # Drawn, not cycled. Indexing the palettes by `placed` walked them
            # in lockstep with the lattice and banded the blocks into visible
            # stripes of one colour. The list is the district's, so infill in
            # Colon is drawn from Colon's stock rather than one global palette.
            district = district_at(px, py)
            wall = mats[rng.choice(district["walls"])]
            roof = mats[rng.choice(district["roofs"])]

            # Seeded off the lattice POSITION, not off `placed`. A counter walks
            # in lockstep with the lattice, which is the same correlation that
            # banded the palettes above; quantised coordinates decorrelate once
            # hashed, and still reproduce exactly on a rebuild.
            seed = (int(px * 100.0) * 73856093) ^ (int(py * 100.0) * 19349663)

            # Lifted rigidly onto the terrain rather than draped: a shed roof
            # follows its own single slope, and draping an 8 m footprint on a
            # hillside would tip it a second time.
            low, high = ground_span(ring)
            seat = high
            tinted = TintedBatch(
                batch,
                tint_of(seed, hue=0.03 * district["tint"],
                        value=0.04 * district["tint"]),
                seat)
            v, f = walls(ring, Z_BUILDING_BASE - (high - low) - PLINTH_MARGIN, height)
            tinted.add(lift(v, seat), f, wall)
            if rng.random() < 0.58:
                v, f, _rise = shed_roof(ring, height, overhang=rng.uniform(0.3, 0.6))
            else:
                v, f, _rise = hip_roof(ring, height, overhang=0.45)
            tinted.add(lift(v, seat), f, roof)

            # Windows, on a smaller course than even the low-rise OSM stock:
            # 55% of infill is 2.4-3.6 m single-storey, and the shophouse
            # numbers used above clear no floors at all on a 2.4 m wall.
            shop = (height >= 4.0
                    and hash_unit(seed * 2246822519 + 7) < district["shopfront"])
            first = SHOPFRONT_HEAD + SIGN_HEIGHT + 0.25 if shop else 1.0
            v, f = window_bands(ring, Z_BUILDING_BASE, height,
                                floor_height=2.7, band=0.7, first_floor=first,
                                min_edge=1.4, inset=0.45)
            tinted.add(lift(v, seat), f, mats["Window"])
            if shop:
                # 4.0 m minimum, so the 3.45 m top of the sign fascia still
                # lands below the eaves instead of floating over the roof.
                shopfront_band(tinted, mats, ring, seat + Z_BUILDING_BASE, seed)
                infill_shops += 1

            existing.add_point(px, py, (px - half_x, py - half_y, px + half_x, py + half_y))
            placed += 1
        y += INFILL_SPACING
    return placed, infill_shops


def dashed_line(pts, z, dash=3.0, gap=4.0, width=0.22):
    """Broken centre line following a polyline."""
    verts = []
    faces = []
    travelled = 0.0
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg < 1e-6:
            continue
        ux, uy = (x1 - x0) / seg, (y1 - y0) / seg
        nx, ny = -uy * width * 0.5, ux * width * 0.5
        pos = 0.0
        while pos < seg:
            phase = math.fmod(travelled + pos, dash + gap)
            if phase < dash:
                run = min(dash - phase, seg - pos)
                ax, ay = x0 + ux * pos, y0 + uy * pos
                bx, by = x0 + ux * (pos + run), y0 + uy * (pos + run)
                base = len(verts)
                verts += [
                    (ax + nx, ay + ny, z), (bx + nx, by + ny, z),
                    (bx - nx, by - ny, z), (ax - nx, ay - ny, z),
                ]
                # Wound the LONG way round on purpose. The vertices above run
                # A-left, B-left, B-right, A-right, and taking them in that
                # order is clockwise seen from above -- which points every dash
                # face DOWNWARD. 12,193 of the 12,214 Marking_White polygons
                # were inverted, while Marking_Yellow (built by ribbon(), which
                # emits left-right-right-left) was correct throughout. Reversing
                # here matches ribbon()'s winding instead of duplicating the
                # vertex list in the other order.
                faces.append((base + 3, base + 2, base + 1, base))
                pos += run
            else:
                pos += (dash + gap) - phase
        travelled += seg
    return verts, faces


def place_trees(solid, foliage, mats, green_polys, footprints, rng, limit=6000):
    """Trees over the green landuse polygons.

    The limit and the per-polygon density were both set when the map was a
    1.75 x 1.88 km slice of Banilad. The extent is now 20.78 km2 -- 6x the area
    -- and 900 trees spread over that is roughly one tree per two hectares,
    which is why parks read as bare paint. Both are scaled to the area they now
    have to cover; trees are tile-streamed, so the cost lands on tiles the
    player is standing in rather than on the always-resident budget.
    """
    placed = 0
    for poly in green_polys:
        if placed >= limit or len(poly) < 3:
            continue
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        area = abs(signed_area(poly))
        # Density follows the district: Capitol is mature trees behind walls,
        # the Port is containers and tarmac.
        density = district_at(sum(xs) / len(xs), sum(ys) / len(ys))["props"]
        wanted = min(90, int(area / 130.0 * density))
        attempts = 0
        made = 0
        while made < wanted and attempts < wanted * 12 and placed < limit:
            attempts += 1
            x = rng.uniform(min(xs), max(xs))
            y = rng.uniform(min(ys), max(ys))
            if not point_in_polygon(x, y, poly):
                continue
            if in_any_slum(x, y):
                continue
            if rng.random() < 0.28:
                trunk, fronds = palm(x, y, rng)
                solid.add(trunk[0], trunk[1], mats["Tree_Trunk"])
                foliage.add(fronds[0], fronds[1], mats[CANOPY_COLOURS[placed % 3]])
            else:
                trunk, canopy = tree(x, y, rng)
                solid.add(trunk[0], trunk[1], mats["Tree_Trunk"])
                foliage.add(canopy[0], canopy[1], mats[CANOPY_COLOURS[placed % 3]])
            made += 1
            placed += 1
    return placed


def _walk_line(pts, spacing, start=0.0):
    """Yield (x, y, heading) at fixed intervals along a polyline."""
    travelled = start
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg < 1e-6:
            continue
        ux, uy = (x1 - x0) / seg, (y1 - y0) / seg
        heading = math.atan2(uy, ux)
        pos = spacing - travelled if travelled < spacing else 0.0
        while pos < seg:
            yield x0 + ux * pos, y0 + uy * pos, heading
            pos += spacing
        travelled = (travelled + seg) % spacing


def place_street_furniture(solid, foliage, mats, road_lines, rng,
                           light_limit=420, pole_limit=520):
    lights = 0
    poles = 0
    for pts, width, cls in road_lines:
        if cls in MAJOR_ROADS and lights < light_limit:
            side = width * 0.5 + 1.4
            flip = True
            for x, y, heading in _walk_line(offset_polyline(pts, side), 38.0):
                if lights >= light_limit:
                    break
                if in_any_slum(x, y):
                    continue
                pole, arm, lamp = street_light(x, y, heading + math.pi * 0.5)
                solid.add(pole[0], pole[1], mats["Pole"])
                foliage.add(arm[0], arm[1], mats["Pole"])
                foliage.add(lamp[0], lamp[1], mats["Lamp"])
                lights += 1
                flip = not flip
        elif cls in ("residential", "unclassified") and poles < pole_limit:
            side = width * 0.5 + 1.1
            for x, y, heading in _walk_line(offset_polyline(pts, side), 46.0):
                if poles >= pole_limit:
                    break
                if in_any_slum(x, y):
                    continue
                a, b, c = power_pole(x, y, heading + math.pi * 0.5)
                solid.add(a[0], a[1], mats["Pole"])
                foliage.add(b[0], b[1], mats["Pole"])
                foliage.add(c[0], c[1], mats["Pole"])
                poles += 1
    return lights, poles


def place_vehicles(solid, mats, road_lines, rng, limit=2200):
    """Parked vehicles down both sides of the drivable network.

    260 cars across 425 named streets is about one car every 1.6 streets, so
    every road read as freshly opened and empty. These are static parked props,
    not traffic, and they stream with their tile.
    """
    placed = 0
    for pts, width, cls in road_lines:
        if placed >= limit:
            break
        if cls not in MAJOR_ROADS and cls not in ("residential", "unclassified"):
            continue
        lane = width * 0.5 - 1.6
        if lane < 1.0:
            continue
        for side in (lane, -lane):
            line = offset_polyline(pts, side)
            if len(line) < 2:
                continue
            for x, y, heading in _walk_line(line, rng.uniform(14.0, 26.0)):
                if placed >= limit:
                    break
                # Parked density by district: Ayala's kerbs are full, the
                # Port's are not.
                if rng.random() < 1.0 - 0.62 * district_at(x, y)["props"]:
                    continue
                body, cabin = vehicle(x, y, heading, rng)
                colour = mats[CAR_COLOURS[placed % len(CAR_COLOURS)]]
                solid.add(body[0], body[1], colour)
                solid.add(cabin[0], cabin[1], colour)
                placed += 1
    return placed


# The Godot scene's sun sits at rotation (-52, -38, 0): 52 degrees above the
# horizon. Blender measures its sun from straight down, so the same elevation is
# a 38 degree x rotation. Matching them means a preview and a screenshot put
# shadows on the same sides of the same buildings, which is the only reason the
# two are worth comparing at all -- the tonemapping and light units will never
# agree (Cycles Filmic at energy 4.0 against Compatibility Filmic at 1.1).
SUN_ELEVATION_DEG = 52.0
SUN_AZIMUTH_DEG = 35.0


def setup_scene():
    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 4.0
    sun_data.angle = math.radians(2.0)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(90.0 - SUN_ELEVATION_DEG), 0.0,
                          math.radians(SUN_AZIMUTH_DEG))
    bpy.context.scene.collection.objects.link(sun)

    cam_data = bpy.data.cameras.new("AerialCamera")
    cam_data.lens = 40.0
    cam_data.clip_end = 8000.0
    cam = bpy.data.objects.new("AerialCamera", cam_data)
    cam.location = (-140.0, -900.0, 620.0)
    cam.rotation_euler = (math.radians(52), 0.0, math.radians(-8))
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    # A physical sky rather than the flat blue constant this used to be. The
    # constant lit every upward-facing surface with exactly the same colour from
    # every direction, which is a large part of why roofs and ground read as
    # cut paper: there was no sky gradient for a surface to catch, and no warm
    # light near the horizon at all.
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    nt = world.node_tree
    background = nt.nodes["Background"]
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(SUN_ELEVATION_DEG)
    # Blender's sky measures its sun rotation from +x anticlockwise; the sun
    # object's z rotation is measured from north. They differ by a quarter turn.
    sky.sun_rotation = math.radians(SUN_AZIMUTH_DEG + 90.0)
    sky.sun_intensity = 0.6      # the Sun lamp does the direct lighting
    sky.sun_size = math.radians(2.0)
    sky.altitude = 20.0
    sky.air_density = 1.3        # slight haze; Cebu is humid and coastal
    sky.dust_density = 1.6
    nt.links.new(sky.outputs["Color"], background.inputs[0])
    background.inputs[1].default_value = 0.7
    bpy.context.scene.world = world

    scene = bpy.context.scene
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 820


def save_and_export():
    OUT_DIR.mkdir(exist_ok=True)
    blend_path = HERE / "banilad_map.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    log("saved blend: {:s}".format(blend_path.name))

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for obj in meshes:
        obj.data.calc_loop_triangles()
    tris = sum(len(o.data.loop_triangles) for o in meshes)
    verts = sum(len(o.data.vertices) for o in meshes)
    log("mesh objects: {:d}   verts: {:d}   tris: {:d}".format(len(meshes), verts, tris))

    bpy.ops.object.select_all(action="SELECT")
    glb_path = OUT_DIR / "banilad_map.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path), export_format="GLB", export_apply=True,
        export_cameras=False, export_lights=False, export_yup=True,
    )
    log("exported glb: {:.2f} MB".format(glb_path.stat().st_size / 1048576))

    fbx_path = OUT_DIR / "banilad_map.fbx"
    bpy.ops.export_scene.fbx(
        filepath=str(fbx_path), apply_scale_options="FBX_SCALE_ALL",
        object_types={"MESH"}, mesh_smooth_type="FACE", path_mode="COPY",
    )
    log("exported fbx: {:.2f} MB".format(fbx_path.stat().st_size / 1048576))
    log("DONE")


main()
