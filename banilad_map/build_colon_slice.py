"""Photoreal vertical slice: textured Colon row -> glb + PBR textures + manifest.

    blender --background --python build_colon_slice.py

The Stage-4 proof for the photoreal PIVOT (owner chose 'textured realism, stay
Compatibility', proven in Godot first). This script:

  1. Generates tileable PBR textures procedurally with numpy (plaster, concrete,
     galvanised sheet, steel shutter, asphalt) + a Cebu shopfront signage atlas.
     No PIL (not in Blender's Python) -- everything is numpy arrays written with a
     tiny built-in PNG writer so the bytes are exact and Godot needs no import.
  2. Reuses banilad_map/parts.py for the massing, adds a UV-aware batch, routes
     every element to a named material slot, and gives the signage fascias real
     atlas UVs.
  3. Exports colon_slice.glb + slice_manifest.json describing how Godot should
     build each material (triplanar PBR / signage-UV / solid).

Everything lands in LOCAL TEMP, not the repo: the assets are a throwaway slice,
and the project sits under OneDrive which rejects some writes (see the
banilad-map-build-verify-pipeline memory). Godot loads it all at runtime by
absolute path, so no res:// import step is involved.
"""

import json
import math
import pathlib
import struct
import sys
import tempfile
import zlib

import bpy
import numpy as np

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
import parts  # noqa: E402

OUT = pathlib.Path(tempfile.gettempdir()) / "cebu_slice"
TEX = OUT / "tex"
CC0 = OUT / "tex_cc0"          # CC0 PBR set fetched by scratchpad/fetch_cc0.py
OUT.mkdir(exist_ok=True)
TEX.mkdir(exist_ok=True)

TEX_SIZE = 512
np.seterr(all="ignore")


# ===========================================================================
# Tiny PNG writer (exact 8-bit bytes, no colour management, no Blender image)
# ===========================================================================

def write_png(path, arr):
    a = (np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    h, w = a.shape[:2]
    if a.shape[2] == 3:
        a = np.dstack([a, np.full((h, w), 255, np.uint8)])
    raw = bytearray()
    stride = w * 4
    flat = a.reshape(h, stride)
    for y in range(h):
        raw.append(0)               # filter type 0 for the scanline
        raw.extend(flat[y].tobytes())

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # RGBA8
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
           + chunk(b"IEND", b""))
    path.write_bytes(png)


# ===========================================================================
# Procedural texture helpers
# ===========================================================================

def _rng(seed):
    return np.random.default_rng(seed)


def _blur(a, k=1):
    out = a.astype(np.float64)
    for _ in range(k):
        out = (out * 2.0 + np.roll(out, 1, 0) + np.roll(out, -1, 0)
               + np.roll(out, 1, 1) + np.roll(out, -1, 1)) / 6.0
    return out


def fbm(size, seed, base=4, octaves=4, blur=1):
    """Tileable-ish fractal noise in [0,1]."""
    acc = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        c = base * (2 ** o)
        r = _rng(seed + o * 131).random((c, c))
        fy = max(1, size // c)
        up = np.repeat(np.repeat(r, fy, 0), fy, 1)
        if up.shape[0] < size:
            up = np.pad(up, ((0, size - up.shape[0]), (0, size - up.shape[1])), mode="wrap")
        up = up[:size, :size]
        acc += _blur(up, blur) * amp
        tot += amp
        amp *= 0.5
    acc /= tot
    acc -= acc.min()
    m = acc.max()
    return acc / m if m > 1e-6 else acc


def normal_map(height, strength=2.0):
    gx = np.roll(height, -1, 1) - np.roll(height, 1, 1)
    gy = np.roll(height, -1, 0) - np.roll(height, 1, 0)
    nx, ny, nz = -gx * strength, -gy * strength, np.ones_like(height)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.dstack([nx * inv, ny * inv, nz * inv]) * 0.5 + 0.5


def cracks(size, seed, density=0.018):
    cr = fbm(size, seed, base=6, octaves=3)
    mask = (np.abs(cr - 0.5) < density).astype(np.float64)
    return _blur(mask, 1)


# ===========================================================================
# Material textures
# ===========================================================================

def tex_plaster(seed):
    s = TEX_SIZE
    mott = fbm(s, seed, base=6, octaves=5, blur=2)
    grain = _rng(seed + 7).random((s, s))
    stain = fbm(s, seed + 3, base=3, octaves=3)
    streak = fbm(s, seed + 5, base=2, octaves=4)
    vgrad = np.linspace(0.2, 1.0, s)[:, None]
    cr = cracks(s, seed + 11)
    val = (0.93 + 0.10 * (mott - 0.5) + 0.04 * (grain - 0.5)
           - 0.08 * np.clip(stain - 0.55, 0, 1)
           - 0.08 * np.clip(streak - 0.6, 0, 1) * vgrad
           - 0.18 * cr)
    val = np.clip(val, 0.45, 1.05)
    alb = np.dstack([val, val, val])
    h = 0.5 + 0.3 * (grain - 0.5) + 0.2 * (mott - 0.5) - 0.6 * cr
    nrm = normal_map(_blur(h, 1), strength=1.4)
    write_png(TEX / "plaster_alb.png", alb)
    write_png(TEX / "plaster_nrm.png", nrm)


def tex_concrete(seed):
    s = TEX_SIZE
    grain = fbm(s, seed, base=8, octaves=5, blur=2)
    stain = fbm(s, seed + 2, base=3, octaves=3)
    val = np.clip(0.85 + 0.09 * (grain - 0.5) - 0.08 * np.clip(stain - 0.5, 0, 1), 0.5, 1.0)
    # faint horizontal form lines + subtle tie holes
    h = 0.5 + 0.12 * (grain - 0.5)
    ys = np.arange(s)
    form = ((ys % (s // 4)) < 2).astype(float)[:, None]
    val = val - 0.035 * form
    h = h - 0.12 * form
    tie = np.zeros((s, s))
    for gy in range(s // 8, s, s // 4):
        for gx in range(s // 8, s, s // 4):
            tie[gy - 2:gy + 2, gx - 2:gx + 2] = 1.0
    val -= 0.05 * tie
    h -= 0.2 * tie
    cr = cracks(s, seed + 9, density=0.008)
    val -= 0.16 * cr
    h -= 0.3 * cr
    val = np.clip(val, 0.42, 1.0)
    alb = np.dstack([val, val, val * 0.99])
    nrm = normal_map(_blur(h, 1), strength=1.6)
    write_png(TEX / "concrete_alb.png", alb)
    write_png(TEX / "concrete_nrm.png", nrm)


def tex_shutter(seed):
    s = TEX_SIZE
    ys = np.arange(s)[:, None]
    slat = 0.5 + 0.5 * np.sin(ys / (s / 26.0) * 2 * np.pi)      # 26 horizontal slats
    slat = np.repeat(slat, s, axis=1)
    streak = fbm(s, seed, base=2, octaves=3)
    val = np.clip(0.5 + 0.06 * (streak - 0.5) + 0.12 * (slat - 0.5), 0.28, 0.72)
    alb = np.dstack([val, val, val * 1.03])
    h = slat
    nrm = normal_map(h, strength=2.6)
    write_png(TEX / "shutter_alb.png", alb)
    write_png(TEX / "shutter_nrm.png", nrm)


def tex_galv(seed):
    s = TEX_SIZE
    xs = np.arange(s)[None, :]
    corr = 0.5 + 0.5 * np.sin(xs / (s / 34.0) * 2 * np.pi)
    corr = np.repeat(corr, s, axis=0)
    rust = fbm(s, seed, base=4, octaves=4)
    base = np.clip(0.56 + 0.12 * (corr - 0.5), 0.35, 0.72)
    rmask = np.clip(rust - 0.6, 0, 1) * 2.0
    r = base + rmask * 0.0
    g = base - rmask * 0.14
    b = base - rmask * 0.24
    alb = np.clip(np.dstack([r + rmask * 0.06, g, b]), 0, 1)
    nrm = normal_map(corr, strength=2.4)
    write_png(TEX / "galv_alb.png", alb)
    write_png(TEX / "galv_nrm.png", nrm)


def tex_asphalt(seed):
    s = TEX_SIZE
    grain = _rng(seed).random((s, s))
    spk = (_rng(seed + 1).random((s, s)) > 0.95).astype(float)
    val = np.clip(0.19 + 0.05 * (grain - 0.5) + 0.13 * spk, 0.12, 0.42)
    cr = cracks(s, seed + 4, density=0.008)
    val -= 0.08 * cr
    alb = np.dstack([val, val, val * 1.02])
    h = 0.4 * grain + 0.5 * spk - 0.5 * cr
    nrm = normal_map(_blur(h, 1), strength=1.2)
    write_png(TEX / "asphalt_alb.png", alb)
    write_png(TEX / "asphalt_nrm.png", nrm)


# --- signage atlas: 3 x 2 boards -------------------------------------------

def _text_rows(reg, rng, dark_on_light=True, rows=3, top=0.4):
    ch, cw = reg.shape[:2]
    ink = 0.12 if dark_on_light else 0.92
    y = int(ch * top)
    for _ in range(rows):
        x = int(cw * 0.12)
        rowh = max(4, ch // 14)
        while x < cw * 0.88:
            wlen = rng.integers(cw // 12, cw // 4)
            reg[y:y + rowh, x:x + wlen] = ink
            x += wlen + rng.integers(cw // 30, cw // 12)
        y += rowh + max(3, ch // 22)
        if y > ch * 0.85:
            break


def tex_signage():
    cols, rows = 3, 2
    cw = ch = 512
    W, H = cols * cw, rows * ch
    atlas = np.zeros((H, W, 3))
    rng = _rng(99)
    # (bg, accent, dark_on_light, motif)
    boards = [
        ((0.62, 0.12, 0.12), (0.86, 0.72, 0.16), False, None),   # Cebuana-style red/yellow
        ((0.92, 0.92, 0.90), (0.20, 0.55, 0.28), True, "cross"),  # pharmacy green cross
        ((0.14, 0.24, 0.44), (0.90, 0.90, 0.86), False, None),   # pawnshop navy
        ((0.86, 0.60, 0.14), (0.30, 0.16, 0.08), True, None),    # karinderya orange
        ((0.84, 0.72, 0.16), (0.66, 0.14, 0.12), True, None),    # M. Lhuillier yellow/red
        ((0.20, 0.42, 0.42), (0.90, 0.90, 0.86), False, None),   # hardware teal
    ]
    for i, (bg, accent, dol, motif) in enumerate(boards):
        c, r = i % cols, i // cols
        reg = atlas[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw]
        reg[:] = bg
        b = 12
        reg[:b] = 0.08
        reg[-b:] = 0.08
        reg[:, :b] = 0.08
        reg[:, -b:] = 0.08
        reg[b:b + ch // 5] = accent                              # top accent band
        _text_rows(reg, rng, dark_on_light=dol, rows=3, top=0.42)
        if motif == "cross":
            cyx = ch // 5 + (ch - ch // 5) // 2
            reg[cyx - 60:cyx + 60, cw // 2 - 20:cw // 2 + 20] = accent
            reg[cyx - 20:cyx + 20, cw // 2 - 60:cw // 2 + 60] = accent
    write_png(TEX / "signage.png", atlas)


# ===========================================================================
# UV-aware batch + geometry
# ===========================================================================

class Ident(dict):
    def __missing__(self, k):
        return k


class UVBatch:
    def __init__(self):
        self.verts, self.faces, self.face_slots, self.uvs = [], [], [], []
        self.slots, self._slot = [], {}

    def _s(self, name):
        if name not in self._slot:
            self._slot[name] = len(self.slots)
            self.slots.append(name)
        return self._slot[name]

    def add(self, verts, faces, material, colors=None, uvs=None):
        if not faces:
            return
        s = self._s(material)
        off = len(self.verts)
        self.verts.extend((float(x), float(y), float(z)) for x, y, z in verts)
        self.uvs.extend(uvs if uvs is not None else [(0.0, 0.0)] * len(verts))
        for f in faces:
            self.faces.append(tuple(i + off for i in f))
            self.face_slots.append(s)


ATLAS_COLS, ATLAS_ROWS = 3, 2


def add_sign(batch, a, b, out, t0, t1, z0, z1, proud, board):
    v, f = parts.facade_panel(a, b, out, t0, t1, z0, z1, proud)
    col, row = board % ATLAS_COLS, board // ATLAS_COLS
    u0, u1 = col / ATLAS_COLS, (col + 1) / ATLAS_COLS
    # facade_panel v-order: bl, br, tr, tl ; Blender UV v-up, atlas row 0 = top
    vv0 = 1.0 - (row + 1) / ATLAS_ROWS
    vv1 = 1.0 - row / ATLAS_ROWS
    uvs = [(u0, vv0), (u1, vv0), (u1, vv1), (u0, vv1)]
    batch.add(v, f, "Signage", uvs=uvs)


WALL_MATS = ["Plaster_Warm", "Plaster_Blue", "Concrete_Grey",
             "Plaster_Ochre", "Plaster_Green"]


def bay(batch, mats, x0, w, h, wall_name, board, awn_name, seed, banner=False,
        depth=11.0):
    along, out = (1.0, 0.0), (0.0, 1.0)
    fl, fr = (x0, 0.0), (x0 + w, 0.0)
    br, bl = (fr[0], -depth), (fl[0], -depth)
    ring = [fl, fr, br, bl]

    v, f = parts.walls(ring, 0.0, h)
    batch.add(v, f, wall_name)
    v, f = parts.parapet_roof(ring, h, parapet=0.7, inset=0.3)
    batch.add(v, f, wall_name)

    a, b, o = fl, fr, out
    gh = 4.4
    parts.shutter(batch, mats, a, b, o, 0.2, gh - 1.0)
    add_sign(batch, a, b, o, 0.03, 0.97, gh - 1.0, gh + 0.1, 0.16, board)
    parts.awning(batch, mats, a, b, o, gh - 1.2, projection=1.6, drop=0.5, mat=awn_name)
    parts.punched_windows(batch, mats, a, b, o, 0.0, h, first=gh + 1.6,
                          cols=max(2, int(w // 3.0)), seed=seed)
    parts.roof_clutter_field(batch, mats, ring, h, seed)
    if banner:
        bt = 0.10 + 0.5 * parts.hash_unit(seed * 71 + 5)
        add_sign(batch, a, b, o, bt, bt + 0.14, gh + 2.0, h - 1.5, 0.30,
                 (board + 2) % 6)


def ground(batch, mats, x0, x1):
    sw = [(x0 - 6, 0.0), (x1 + 6, 0.0), (x1 + 6, 3.0), (x0 - 6, 3.0)]
    v, f = parts.walls(sw, -0.4, 0.15)
    batch.add(v, f, "Concrete_Side")
    v, f = parts.flat_polygon(sw, 0.15)
    batch.add(v, f, "Concrete_Side")
    rd = [(x0 - 44, 3.0), (x1 + 44, 3.0), (x1 + 44, 40.0), (x0 - 44, 40.0)]
    v, f = parts.flat_polygon(rd, 0.0)
    batch.add(v, f, "Asphalt")
    cx = (x0 + x1) * 0.5
    d = cx - 26
    while d < cx + 26:
        seg = [(d, 11.0), (d + 3.0, 11.0), (d + 3.0, 11.5), (d, 11.5)]
        v, f = parts.flat_polygon(seg, 0.02)
        batch.add(v, f, "Marking_Yellow")
        d += 6.0


def build_colon(batch, mats):
    specs = [
        # w, h, wall,            board, awning,          banner
        (7.2, 15.0, "Plaster_Warm",  0, "Awning_Steel",  True),
        (5.6, 18.5, "Concrete_Grey", 2, "Awning_Canvas", False),
        (6.8, 12.5, "Plaster_Blue",  5, "Awning_Steel",  True),
        (5.0, 16.0, "Plaster_Ochre", 3, "Awning_Steel",  False),
        (7.6, 13.5, "Plaster_Green", 1, "Awning_Canvas", True),
    ]
    x = 0.0
    for i, (w, h, wall, board, awn, banner) in enumerate(specs):
        bay(batch, mats, x, w, h, wall, board, awn, 4100 + i * 7, banner=banner)
        x += w
    ground(batch, mats, 0.0, x)
    return x


# ===========================================================================
# Blender mesh + glb export + manifest
# ===========================================================================

def to_glb(batch, path):
    mesh = bpy.data.meshes.new("ColonSlice")
    mesh.from_pydata(batch.verts, [], batch.faces)
    mesh.validate(verbose=False)
    for name in batch.slots:
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mesh.materials.append(m)
    if len(batch.slots) > 1:
        for poly, slot in zip(mesh.polygons, batch.face_slots):
            poly.material_index = slot
    uvl = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uvl.data[loop.index].uv = batch.uvs[loop.vertex_index]
    for p in mesh.polygons:
        p.use_smooth = False
    mesh.update()
    obj = bpy.data.objects.new("ColonSlice", mesh)
    bpy.context.scene.collection.objects.link(obj)
    verts_n, tris_n = len(batch.verts), sum(len(f) - 2 for f in batch.faces)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB",
                              use_selection=False, export_apply=True,
                              export_yup=True)
    return verts_n, tris_n


MANIFEST_MATERIALS = {
    "Plaster_Warm":  {"tex": "plaster", "tint": [0.96, 0.91, 0.82], "rough": 0.82},
    "Plaster_Blue":  {"tex": "plaster", "tint": [0.66, 0.73, 0.75], "rough": 0.82},
    "Plaster_Ochre": {"tex": "plaster", "tint": [0.90, 0.75, 0.50], "rough": 0.82},
    "Plaster_Green": {"tex": "plaster", "tint": [0.68, 0.75, 0.62], "rough": 0.82},
    "Concrete_Grey": {"tex": "concrete", "tint": [0.88, 0.88, 0.85], "rough": 0.85},
    "Concrete_Side": {"tex": "concrete", "tint": [0.70, 0.69, 0.65], "rough": 0.9},
    "Asphalt":       {"tex": "asphalt", "tint": [0.98, 0.98, 1.0], "rough": 0.95},
    "Shutter_Steel": {"tex": "shutter", "tint": [0.86, 0.86, 0.90], "rough": 0.45, "metal": 0.5},
    "Awning_Steel":  {"tex": "galv", "tint": [0.78, 0.78, 0.80], "rough": 0.5, "metal": 0.3},
    "Awning_Canvas": {"tex": "galv", "tint": [0.82, 0.74, 0.60], "rough": 0.8},
    "Roof_Tank":     {"tex": "galv", "tint": [0.60, 0.59, 0.55], "rough": 0.7},
    "Metro_Reveal":  {"solid": [0.16, 0.15, 0.14], "rough": 0.9},
    "Window":        {"solid": [0.09, 0.12, 0.16], "rough": 0.12, "metal": 0.3},
    "Tower_Plant":   {"solid": [0.38, 0.38, 0.40], "rough": 0.8},
    "Pole":          {"solid": [0.30, 0.30, 0.30], "rough": 0.7},
    "Marking_Yellow": {"solid": [0.80, 0.66, 0.20], "rough": 0.9},
    "Signage":       {"signage": True, "rough": 0.6},
}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # CC0 PBR textures (Poly Haven) supply the tiling materials now; only the
    # Cebu-specific signage atlas is still generated procedurally.
    print("[slice] generating signage atlas ...")
    tex_signage()

    def cc0(short):
        return {"albedo": str(CC0 / (short + "_alb.jpg")),
                "normal": str(CC0 / (short + "_nrm.jpg")),
                "rough": str(CC0 / (short + "_rgh.jpg"))}

    mats = Ident()
    batch = UVBatch()
    run = build_colon(batch, mats)

    glb = OUT / "colon_slice.glb"
    verts_n, tris_n = to_glb(batch, glb)

    manifest = {
        "glb": str(glb),
        "run": run,
        "textures": {
            "plaster": cc0("plaster"),
            "concrete": cc0("concrete"),
            "shutter": cc0("shutter"),
            "galv": cc0("galv"),
            "asphalt": cc0("asphalt"),
            "signage": {"albedo": str(TEX / "signage.png")},
        },
        "materials": MANIFEST_MATERIALS,
    }
    (OUT / "slice_manifest.json").write_text(json.dumps(manifest, indent=2))

    print("[slice] verts={} tris={} slots={}".format(verts_n, tris_n, len(batch.slots)))
    print("[slice] slots:", ", ".join(batch.slots))
    print("[slice] glb ->", glb)
    print("[slice] manifest ->", OUT / "slice_manifest.json")
    print("[slice] DONE")


if __name__ == "__main__":
    main()
