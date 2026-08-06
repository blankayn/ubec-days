"""Render aerial previews of the built map.

    blender --background --python render_preview.py
    blender --background --python render_preview.py -- corridor itpark

Rendering the whole set in one Blender process is unreliable: Cycles builds up
state across shots and the process tends to die outright partway through, which
takes the remaining shots with it and leaves half the previews stale. Naming
shots on the command line lets each one run in its own process, so a crash
costs a single image. render_all.py does exactly that.
"""

import math
import pathlib
import sys

import bpy

HERE = pathlib.Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(HERE / "banilad_map.blend"))

scene = bpy.context.scene
cam = bpy.data.objects["AerialCamera"]

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
# 24 for iteration, 64 for a final shot. The physical sky costs more samples to
# resolve than the flat constant world did -- at 24 the haze near the horizon
# stays visibly grainy even after denoising.
scene.cycles.samples = 64 if "--final" in sys.argv else 24
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 3
scene.cycles.use_fast_gi = True
scene.render.resolution_x = 1400
scene.render.resolution_y = 820

SHOTS = [
    # name, location, rotation in degrees (x, y, z), lens
    ("aerial_match", (-120.0, -880.0, 600.0), (52.0, 0.0, -6.0), 42.0),
    ("district", (60.0, 320.0, 210.0), (62.0, 0.0, 8.0), 38.0),
    ("street", (30.0, 480.0, 26.0), (80.0, 0.0, 12.0), 34.0),
    # Landmark checks. Angles are chosen to match the aerial reference shots so
    # the build can be compared against them side by side.
    ("uc_facade", (-40.0, 330.0, 70.0), (71.4, 0.0, -36.8), 40.0),
    ("uc_courtyard", (49.0, 330.0, 200.0), (36.0, 0.0, 0.0), 50.0),
    ("mall_court", (-80.0, 400.0, 60.0), (74.4, 0.0, 6.5), 38.0),
    ("corridor", (-30.0, 250.0, 160.0), (62.6, 0.0, 2.1), 35.0),
    ("itpark", (-250.0, -1050.0, 260.0), (68.0, 0.0, 45.0), 40.0),
    ("central_bloc", (-250.0, -640.0, 175.0), (66.0, 0.0, 52.0), 45.0),
    ("itpark_skyline", (-180.0, -1080.0, 120.0), (78.0, 0.0, 34.0), 38.0),

    # --- Slices 1-5: the wider city ----------------------------------------
    # Blender y is the negation of Godot z, so downtown sits at large -y.
    # Camera convention: x rotation 0 looks straight down and 90 looks level;
    # z rotation 0 faces north (+y).
    # Top-down. The built area is about 3.9 km east-west by 5.3 km north-south,
    # so the view is turned 90 degrees to lay the long axis across the frame --
    # facing north wastes half the image and overshoots the ground plane edge.
    # Centre follows the built area, which now runs to y = -5100 at the Port.
    ("city_overview", (-950.0, -2150.0, 4500.0), (0.0, 0.0, 90.0), 24.0),
    ("ayala_bizpark", (-695.0, -2250.0, 260.0), (63.0, 0.0, 0.0), 40.0),
    ("fuente_circle", (-2022.0, -3120.0, 210.0), (62.0, 0.0, 0.0), 40.0),
    ("colon_downtown", (-1205.0, -4800.0, 240.0), (64.0, 0.0, 0.0), 40.0),
    # Along Osmena Boulevard from Fuente toward Colon: the 24 m descent that
    # Phase 2 terrain exists to capture, still rendered dead flat.
    ("osmena_descent", (-2206.0, -2380.0, 250.0), (72.0, 0.0, 207.0), 40.0),

    # --- Slice 6: Carbon and the Port --------------------------------------
    # The southern end of the map, all looking north from just seaward.
    ("carbon_market", (-1391.0, -4980.0, 230.0), (63.0, 0.0, 0.0), 40.0),
    ("fort_san_pedro", (-657.0, -4950.0, 190.0), (62.0, 0.0, 0.0), 40.0),
    # Piers 1-4 and the waterfront. This is where the missing sea shows: OSM
    # defines open water by the coastline, and natural=coastline is not in the
    # Overpass query, so the harbour is still ground at about 0 m.
    ("port_piers", (-480.0, -4900.0, 300.0), (58.0, 0.0, 0.0), 35.0),
    # Magellan's Cross Pavilion (way 94081127) with the Basilica behind it.
    # Absent until this slice: it sat 37 m past slice 5's southern boundary.
    ("magellans_cross", (-1030.0, -4740.0, 110.0), (72.0, 0.0, 0.0), 45.0),
]

wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
# A flag, not a shot name; it is read above for the sample count.
wanted = [w for w in wanted if w != "--final"]
if wanted:
    known = {s[0] for s in SHOTS}
    unknown = [w for w in wanted if w not in known]
    if unknown:
        raise SystemExit("unknown shot(s): {:s}\nknown: {:s}".format(
            ", ".join(unknown), ", ".join(sorted(known))))
    SHOTS = [s for s in SHOTS if s[0] in wanted]

for name, loc, rot_deg, lens in SHOTS:
    cam.location = loc
    cam.rotation_euler = tuple(math.radians(a) for a in rot_deg)
    cam.data.lens = lens
    out = HERE / "preview_{:s}.png".format(name)
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    print("[render] wrote {:s} ({:d} bytes)".format(out.name, out.stat().st_size))
    sys.stdout.flush()

print("[render] DONE")
