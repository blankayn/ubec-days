"""Harvest rigid head accessories from the Creative Characters FREE pack.

    python tools/harvest_accessories.py [--source <dir>]

Reads the pack's GLB files, lifts the accessory meshes into the citizen's
authoring space, and writes `tools/citizen_accessories.json`.
`tools/build_citizen.py` picks that file up if it exists and emits each entry
as another wearable mesh; if it is absent the citizen builds without them, so
the repo never hard-depends on an external download.

WHY THIS WORKS AT ALL, WHEN THE REST OF THE PACK DOES NOT
---------------------------------------------------------
The pack's body cannot be used here: it is an A-pose rig with ~30 degrees of
arm droop, bare (unprefixed) Mixamo bone names and no Spine2, while
`cblock_player.gd` copies Mixamo rotation keys onto the target skeleton
untouched and therefore needs an exact Mixamo T-pose.

None of that matters for a hat. Every accessory in this pack is weighted 100%
to `Head` and nothing else (verified, and re-asserted below on every run), so
it is a RIGID PROP. A rigid prop has no rest pose to disagree about -- it only
has to be moved and scaled from their skull onto ours.

THE TWO SKULLS ARE NOT THE SAME SHAPE
-------------------------------------
Theirs is a cartoon head: 29.9 cm wide, 33.0 cm tall, 29.0 deep. Ours is
realistic: 16.8 x 22.4 x 20.0. So a straight parent-to-the-head-bone transplant
puts a cap's brim down around the mouth. Two things fix that:

  * uniform scale from the mean of the width and depth ratios (~0.60), because
    an accessory's fit is dominated by the skull's cross-section, and
  * a per-accessory ANCHOR that pins one feature of the accessory to the
    matching feature of our head -- a hat's underside to the brow, glasses'
    centre to the eye line, a moustache's top to the base of the nose.

Anchoring beats proportional remapping because the two heads are stylistically
different, not merely different sizes: a cartoon hat legitimately sits low on a
big round skull, and mapping that proportionally reproduces the low brim
instead of correcting it.

LICENCE
-------
Creative Characters FREE, Superhive (formerly Blender Market), Standard
Royalty Free: commercial use is permitted, redistribution and repackaging are
NOT. The geometry this writes is derived from that product -- see the note in
PROJECT_STATUS.md about keeping it out of a public repository.
"""

import argparse
import json
import math
import pathlib
import struct
import sys

HERE = pathlib.Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import citizen_spec as spec  # noqa: E402

DEFAULT_SOURCE = pathlib.Path(
    r"C:/Users/Ariel/Downloads/Separate_assets_glb/Separate_assets_glb"
)
OUTPUT = HERE / "citizen_accessories.json"

COMPONENT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
             5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def log(message):
    print("[harvest] {:s}".format(message))


# ---------------------------------------------------------------------------
# glTF reading -- deliberately dependency-free
# ---------------------------------------------------------------------------

def read_glb(path):
    blob = path.read_bytes()
    if blob[:4] != b"glTF":
        raise SystemExit("not a GLB: {:s}".format(path.name))
    json_length = struct.unpack("<I", blob[12:16])[0]
    document = json.loads(blob[20:20 + json_length])
    offset = 20 + json_length
    binary_length = struct.unpack("<I", blob[offset:offset + 4])[0]
    return document, blob[offset + 8:offset + 8 + binary_length]


def read_accessor(document, binary, index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    fmt, size = COMPONENT[accessor["componentType"]]
    width = COUNTS[accessor["type"]]
    stride = view.get("byteStride") or size * width
    return [
        struct.unpack_from("<" + fmt * width, binary, start + i * stride)
        for i in range(accessor["count"])
    ]


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

def citizen_head_metrics():
    """Skull bounds in the citizen's authoring space (cm), from the spec."""
    head_y = spec.HEAD_ANCHOR_Y
    head_z = spec.HEAD_ANCHOR_Z
    lo_y = head_y + spec.HEAD_STATIONS[0][0]
    hi_y = head_y + spec.HEAD_STATIONS[-1][0]
    width = 2.0 * max(s[1] for s in spec.HEAD_STATIONS)
    depth_lo = min(head_z + s[3] - s[2] for s in spec.HEAD_STATIONS)
    depth_hi = max(head_z + s[3] + s[2] for s in spec.HEAD_STATIONS)
    return {
        "y_lo": lo_y, "y_hi": hi_y, "height": hi_y - lo_y,
        "width": width, "depth": depth_hi - depth_lo,
        "z_centre": (depth_lo + depth_hi) * 0.5,
    }


def anchor_targets(head):
    """Citizen head features an accessory can be pinned to, in cm."""
    y = spec.HEAD_ANCHOR_Y
    return {
        "brow": y + spec.HEAD_STATIONS[6][0],
        "eye": y + spec.HEAD_STATIONS[5][0],
        "ear": y + spec.HEAD_STATIONS[5][0] - 0.6,
        "nose": y + spec.HEAD_STATIONS[4][0],
        "jaw": head["y_lo"],
        "crown": head["y_hi"],
    }


def harvest_one(path, config, head, targets):
    document, binary = read_glb(path)
    joints = [document["nodes"][j].get("name") for j in document["skins"][0]["joints"]]

    verts = []
    faces = []
    slots = []
    for mesh in document["meshes"]:
        for primitive_index, primitive in enumerate(mesh["primitives"]):
            attributes = primitive["attributes"]
            positions = read_accessor(document, binary, attributes["POSITION"])

            # Re-assert rigidity every run. If a future pack revision weights an
            # accessory to anything but Head, the transplant silently stops
            # being valid and the prop would swim under animation.
            bone_ids = read_accessor(document, binary, attributes["JOINTS_0"])
            weights = read_accessor(document, binary, attributes["WEIGHTS_0"])
            for ids, ws in zip(bone_ids, weights):
                for bone, weight in zip(ids, ws):
                    if weight > 0.01 and joints[bone] != "Head":
                        raise SystemExit(
                            "{:s} is weighted to {:s}, not Head alone -- it is not a "
                            "rigid prop and cannot be transplanted this way"
                            .format(path.name, joints[bone])
                        )

            base = len(verts)
            verts.extend([list(p) for p in positions])
            indices = [i[0] for i in read_accessor(document, binary, primitive["indices"])]
            # Primitive 0 is the body of the accessory; any further primitive is
            # its secondary material (a lens, a band) and takes the accent slot.
            slot = config["slot"] if primitive_index == 0 else "accent"
            for i in range(0, len(indices), 3):
                faces.append([base + indices[i], base + indices[i + 1], base + indices[i + 2]])
                slots.append(slot)

    # --- pack space (metres) -> citizen authoring space (centimetres) --------
    scale = 0.5 * (head["width"] / spec.PACK_HEAD_WIDTH_CM
                   + head["depth"] / spec.PACK_HEAD_DEPTH_CM) * 100.0

    # Per-axis trim on top of the uniform fit. Their skull is near-spherical
    # (29.9 x 33.0 x 29.0) where ours is a tall narrow ovoid (16.0 x 22.4 x
    # 18.5), so a hat scaled to fit our WIDTH is still about twice as tall as
    # our brow-to-crown. Squashing a hat vertically still reads as a hat;
    # leaving it uniform reads as a traffic cone.
    sx, sy, sz = config.get("scale", (1.0, 1.0, 1.0))
    scaled = [[v[0] * scale * sx, v[1] * scale * sy, v[2] * scale * sz] for v in verts]
    ys = sorted(v[1] for v in scaled)
    mode, target = config["anchor"]
    if mode.startswith("p"):
        # Percentile, not min. A downturned hat brim hangs several centimetres
        # below the band that actually rests on the skull, so anchoring the
        # lowest vertex to the brow leaves the hat perched above the hair.
        source_y = ys[max(0, min(len(ys) - 1, int(len(ys) * int(mode[1:]) / 100.0)))]
    else:
        source_y = {"min": ys[0], "mid": (ys[0] + ys[-1]) * 0.5, "max": ys[-1]}[mode]
    shift_y = targets[target] + config.get("dy", 0.0) - source_y

    # X is symmetric about the centreline in both rigs. Z maps THEIR skull
    # centre onto OURS, so an accessory keeps its forward projection relative
    # to the face. Using the accessory's own centroid instead pulls glasses
    # back to the middle of the skull and they vanish inside the head.
    pack_z_centre = (spec.PACK_HEAD_Z_CENTRE_CM / 100.0) * scale
    shift_z = head["z_centre"] + config.get("dz", 0.0) - pack_z_centre

    placed = [[v[0], v[1] + shift_y, v[2] + shift_z] for v in scaled]
    return {
        "group": config["group"],
        "slot": config["slot"],
        "verts": [[round(c, 4) for c in v] for v in placed],
        "faces": faces,
        "face_slots": slots,
        "source": path.name,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=str(DEFAULT_SOURCE))
    args = parser.parse_args()
    source = pathlib.Path(args.source)
    if not source.is_dir():
        raise SystemExit("source folder not found: {:s}".format(str(source)))

    head = citizen_head_metrics()
    targets = anchor_targets(head)
    log("citizen skull: {:.1f} w x {:.1f} h x {:.1f} d cm, y {:.1f}..{:.1f}".format(
        head["width"], head["height"], head["depth"], head["y_lo"], head["y_hi"]))
    log("pack skull   : {:.1f} w x {:.1f} h x {:.1f} d cm".format(
        spec.PACK_HEAD_WIDTH_CM, spec.PACK_HEAD_HEIGHT_CM, spec.PACK_HEAD_DEPTH_CM))

    out = {}
    total = 0
    for name, config in spec.ACCESSORY_IMPORT.items():
        path = source / config["src"]
        if not path.exists():
            log("MISSING {:s} -- skipped".format(config["src"]))
            continue
        entry = harvest_one(path, config, head, targets)
        out[name] = entry
        total += len(entry["faces"])
        ys = sorted(v[1] for v in entry["verts"])
        zs = sorted(v[2] for v in entry["verts"])
        # p05 alongside min: if they differ a lot, the lowest vertex is an
        # outlier (a strap, a stray tri) and anchoring on min pushes the visible
        # body of the accessory too high.
        p05 = ys[max(0, int(len(ys) * 0.05))]
        log("{:<18s} {:>5d} tris  y {:6.1f}..{:6.1f} (p05 {:6.1f})  z {:5.1f}..{:5.1f}"
            .format(name, len(entry["faces"]), ys[0], ys[-1], p05, zs[0], zs[-1]))

    OUTPUT.write_text(json.dumps({
        "source_product": "Creative Characters FREE (Superhive) -- Standard Royalty Free",
        "accessories": out,
    }, indent=1), encoding="utf-8")
    log("wrote {:s} ({:d} accessories, {:d} tris)".format(
        OUTPUT.name, len(out), total))


if __name__ == "__main__":
    main()
