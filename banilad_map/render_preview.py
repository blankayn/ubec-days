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
scene.cycles.samples = 24
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
]

wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
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
