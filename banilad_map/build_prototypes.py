"""Build representative building prototypes on a flat test plane and render them.

    blender --background --python build_prototypes.py
    blender --background --python build_prototypes.py -- colon_row

Proves ``banilad_map/parts.py`` before any of it touches ``build_map.py`` or the
streamed tiles (CEBU_ARCHITECTURE_BIBLE.md s8, the Stage-4 prototype step). Each
prototype is built from the kit on a bare ground plane with the game's
flat-shaded, vertex-tinted materials, then rendered from a street camera.

Standalone on purpose: it does NOT import ``build_map.py`` (that would trigger a
full 15-min build via its bare ``main()``), so it carries a LEAN copy of the
material/batch plumbing. That plumbing is throwaway prototype scaffolding; the
geometry that matters lives once, in ``parts.py``.

Renders and the .blend go to LOCAL TEMP, not the repo -- the project sits under
OneDrive, which intermittently rejects writes with OSError 22 (see the
banilad-map-build-verify-pipeline memory). The absolute output paths are printed
at the end.
"""

import math
import pathlib
import sys
import tempfile

import bpy

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
import parts  # noqa: E402  (after sys.path insert)

OUT_DIR = pathlib.Path(tempfile.gettempdir()) / "cebu_proto"
OUT_DIR.mkdir(exist_ok=True)


# ---------------------------------------------------------------------------
# Palette subset (sRGB, copied from build_map.py PALETTE) + the new materials
# the Bible s7 proposes. Muted, value-separated register.
# ---------------------------------------------------------------------------

PALETTE = {
    # walls
    "Wall_0": (0.72, 0.70, 0.65), "Wall_2": (0.68, 0.65, 0.58),
    "Wall_4": (0.65, 0.64, 0.62), "Wall_5": (0.58, 0.57, 0.52),
    "Wall_Concrete_0": (0.64, 0.63, 0.60), "Wall_Concrete_1": (0.56, 0.56, 0.54),
    "Wall_Concrete_2": (0.70, 0.70, 0.68),
    # shopfront + signage
    "Shopfront_Glass": (0.15, 0.16, 0.17), "Window": (0.12, 0.16, 0.20),
    "Sign_Red": (0.56, 0.22, 0.19), "Sign_Blue": (0.20, 0.34, 0.50),
    "Sign_Yellow": (0.72, 0.60, 0.22), "Sign_Green": (0.24, 0.42, 0.30),
    "Sign_White": (0.76, 0.75, 0.71),
    # roofscape
    "Roof_Tank": (0.50, 0.49, 0.46), "Tower_Plant": (0.38, 0.38, 0.40),
    "Pole": (0.34, 0.34, 0.33),
    # Metro reveal (dark, reused as banner/sign backing)
    "Metro_Reveal": (0.26, 0.25, 0.23),
    # ground context
    "Sidewalk": (0.52, 0.51, 0.48), "Road_Major": (0.22, 0.22, 0.24),
    "Marking_Yellow": (0.80, 0.66, 0.20),
    # --- new materials (Bible s7) ---
    "Rail_Metal": (0.40, 0.40, 0.42), "Rail_Solid": (0.66, 0.64, 0.60),
    "Awning_Steel": (0.50, 0.48, 0.45), "Awning_Canvas": (0.62, 0.58, 0.50),
    "Shutter_Steel": (0.48, 0.47, 0.45),
}


# ---------------------------------------------------------------------------
# Lean copy of build_map.py's Blender plumbing (see module docstring)
# ---------------------------------------------------------------------------

WHITE = (1.0, 1.0, 1.0, 1.0)
GRIME_HEIGHT = 4.0
GRIME_STRENGTH = 0.22
TINT_LAYER = "Col"


def srgb_to_linear(c):
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def wire_vertex_tint(mat, linear):
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = TINT_LAYER
    attr.location = (-560, 260)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.location = (-300, 260)
    mix.inputs["Factor"].default_value = 1.0
    mix.inputs[6].default_value = (*linear, 1.0)
    nt.links.new(attr.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def build_materials():
    mats = {}
    for name, srgb in PALETTE.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        linear = tuple(srgb_to_linear(c) for c in srgb)
        bsdf.inputs["Base Color"].default_value = (*linear, 1.0)
        wire_vertex_tint(mat, linear)
        bsdf.inputs["Roughness"].default_value = 0.85
        mat.diffuse_color = (*linear, 1.0)
        mats[name] = mat
    return mats


class MeshBatch:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.face_slots = []
        self.slots = []
        self._slot_of = {}
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

    def to_object(self, name):
        if not self.faces:
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
            layer = mesh.color_attributes.new(
                name=TINT_LAYER, type="FLOAT_COLOR", domain="POINT")
            for i, c in enumerate(self.colors):
                layer.data[i].color = c
            mesh.color_attributes.active_color = layer
            mesh.color_attributes.render_color_index = 0
        # flat shading for the PSX look
        mesh.shade_flat() if hasattr(mesh, "shade_flat") else None
        for p in mesh.polygons:
            p.use_smooth = False
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


class TintedBatch:
    """Per-building tint + base grime, written into every vertex colour."""

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


# ---------------------------------------------------------------------------
# Prototype 01 -- Colon party-wall shophouse row
# ---------------------------------------------------------------------------

def build_colon_row(batch, mats):
    """A 5-bay, zero-setback Category-A block. Front faces +y (the street)."""
    along = (1.0, 0.0)
    out = (0.0, 1.0)

    # Faded painted commercial stock -- widest colour spread in the city.
    specs = [
        # width, height, wall,               sign,         awning,         banner
        (7.2, 15.0, "Wall_2",           "Sign_Yellow", "Awning_Steel",  True),
        (5.6, 18.5, "Wall_Concrete_2",  "Sign_Red",    "Awning_Canvas", False),
        (6.8, 12.5, "Wall_0",           "Sign_Blue",   "Awning_Steel",  True),
        (5.0, 16.0, "Wall_Concrete_0",  "Sign_Green",  "Awning_Steel",  False),
        (7.6, 13.5, "Wall_4",           "Sign_White",  "Awning_Canvas", True),
    ]
    x = 0.0
    for i, (w, h, wall, sign, awn, banner) in enumerate(specs):
        seed = 4100 + i * 7
        # faded-paint tint: a warm off-white, jittered per bay off the seed
        j = parts.hash_unit(seed * 13 + 1)
        tint = (0.88 + 0.10 * j, 0.86 + 0.10 * j, 0.82 + 0.09 * j)
        tb = TintedBatch(batch, tint, 0.0)
        ring = parts.party_wall_bay(
            tb, mats, (x, 0.0), along, out, w, 11.0, h,
            wall, sign, awn, seed, ground_h=4.4,
            has_shutter=True, banner=banner)
        # a couple of bays carry a cantilevered balcony on an upper floor
        if i in (0, 3):
            a, b, o = ring[0], ring[1], out
            parts.balcony(tb, mats, a, b, o, 7.6, 0.18, 0.82,
                          depth=1.2, rail_h=1.0)
        # one bay has grown an unfinished top-floor extension
        if i == 2:
            parts.roof_extension(tb, mats, ring, h, "Wall_Concrete_1",
                                 "Roof_Tank", coverage=0.5, seed=seed)
        x += w
    return x  # total run length


# ---------------------------------------------------------------------------
# Scene assembly
# ---------------------------------------------------------------------------

def ground_plane(batch, mats, x0, x1):
    """Sidewalk + kerb + road + centre line in front of the row (street at +y)."""
    # sidewalk slab, 3 m deep, 0.15 m proud
    sw = [(x0 - 6, 0.0), (x1 + 6, 0.0), (x1 + 6, 3.0), (x0 - 6, 3.0)]
    v, f = parts.walls(sw, -0.4, 0.15)
    batch.add(v, f, mats["Sidewalk"])
    v, f = parts.flat_polygon(sw, 0.15)
    batch.add(v, f, mats["Sidewalk"])
    # road beyond the kerb
    rd = [(x0 - 20, 3.0), (x1 + 20, 3.0), (x1 + 20, 18.0), (x0 - 20, 18.0)]
    v, f = parts.flat_polygon(rd, 0.0)
    batch.add(v, f, mats["Road_Major"])
    # a broken centre line
    cx = (x0 + x1) * 0.5
    dash = cx - 24
    while dash < cx + 24:
        seg = [(dash, 10.3), (dash + 3.0, 10.3), (dash + 3.0, 10.7), (dash, 10.7)]
        v, f = parts.flat_polygon(seg, 0.02)
        batch.add(v, f, mats["Marking_Yellow"])
        dash += 6.0
    # ground apron behind the row
    bg = [(x0 - 20, -18.0), (x1 + 20, -18.0), (x1 + 20, 0.0), (x0 - 20, 0.0)]
    v, f = parts.flat_polygon(bg, -0.02)
    batch.add(v, f, mats["Wall_5"])


def add_sun():
    data = bpy.data.lights.new("Sun", "SUN")
    data.energy = 3.2
    data.angle = math.radians(2.0)
    obj = bpy.data.objects.new("Sun", data)
    obj.rotation_euler = (math.radians(52.0), math.radians(8.0), math.radians(-56.0))
    bpy.context.scene.collection.objects.link(obj)


def set_world():
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.62, 0.66, 0.72, 1.0)  # pale tropical sky
    bg.inputs[1].default_value = 1.0
    bpy.context.scene.world = world


def add_camera(name, loc, target, lens=38.0):
    empty = bpy.data.objects.new(name + "_tgt", None)
    empty.location = target
    bpy.context.scene.collection.objects.link(empty)
    data = bpy.data.cameras.new(name)
    data.lens = lens
    cam = bpy.data.objects.new(name, data)
    cam.location = loc
    con = cam.constraints.new("TRACK_TO")
    con.target = empty
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    bpy.context.scene.collection.objects.link(cam)
    return cam


def main():
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    final = "--final" in wanted
    wanted = [w for w in wanted if not w.startswith("--")]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = build_materials()

    batch = MeshBatch()
    run = build_colon_row(batch, mats)
    ground_plane(batch, mats, 0.0, run)
    batch.to_object("ColonRow_Proto01")

    add_sun()
    set_world()

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 96 if final else 40
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    # Faithful palette: show the authored sRGB rather than AgX tone-mapping it.
    scene.view_settings.view_transform = "Standard"

    mid = run * 0.5
    shots = [
        ("colon_row_3q", (-10.0, 34.0, 12.0), (mid + 6, -3.0, 12.0), 40.0),
        ("colon_row_face", (mid, 40.0, 16.0), (mid, -5.0, 15.0), 34.0),
        ("colon_row_eye", (-4.0, 12.0, 2.4), (run * 0.7, -2.0, 6.0), 30.0),
    ]
    if wanted:
        shots = [s for s in shots if s[0] in wanted]

    written = []
    for name, loc, target, lens in shots:
        cam = add_camera(name, loc, target, lens)
        scene.camera = cam
        out = OUT_DIR / (name + ".png")
        scene.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)
        written.append(out)
        print("[proto] wrote {} ({} bytes)".format(out, out.stat().st_size))
        sys.stdout.flush()

    blend = OUT_DIR / "prototypes.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    print("[proto] saved {}".format(blend))
    print("[proto] DONE ->", " ".join(str(w) for w in written))


main()
