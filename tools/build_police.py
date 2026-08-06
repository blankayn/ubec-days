"""Build the UBEC police officer and export it as a skinned GLB.

    "C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P tools/build_police.py

Writes `assets/npcs/police.glb`.

Why it starts from an FBX instead of building an armature from scratch:
`cblock_player.gd` / `police_npc_prop.gd` retarget the Mixamo clips by copying
**rotation keys untouched** onto the target skeleton, so the target's bone rest
orientations have to match Mixamo's exactly. Rather than hand-author 19 bones
and hope, this imports `animation mixamo/Idle.fbx` and skins onto the armature
that comes with it: the rig *is* a Mixamo rig, so it cannot drift out of spec.

The Idle clip is **kept and baked into the GLB** as the officer's default
loop. Walking still retargets from `Walking.fbx` at runtime
(`police_npc_prop.gd`), so a baked walk would only fight it; idle is safe to
bake because it never competes with anything.

The body is rigid-bound: every part is weighted 1.0 to a single bone, the way
PS1-era characters were skinned. It suits the faceted look, it costs nothing at
runtime, and it removes the usual failure mode of scripted rigging (bone-heat
weighting quietly failing on the small detached props -- badge, buttons,
handcuffs -- and dumping them at the origin). Limb segments overlap at the
joints so elbows and knees do not open a gap when they bend.

Geometry is authored in the armature's own space: centimetres, +Y up, +Z the
way the officer faces, +X his LEFT (that is where `LeftUpLeg` sits). Vertices
are pushed through the armature's world matrix on the way into the mesh, so the
object itself stays at identity in Blender's metre-scale Z-up world.
"""

import math
import pathlib
import sys

import bmesh
import bpy
import mathutils

HERE = pathlib.Path(__file__).resolve().parent
PROJECT = HERE.parent
SOURCE_FBX = PROJECT / "animation mixamo" / "Idle.fbx"
OUTPUT_GLB = PROJECT / "assets" / "npcs" / "police.glb"

BONE_PREFIX = "mixamorig1:"

# --- Palette, read off the reference render -------------------------------
# Linear-ish sRGB triples; the GLB carries them as base colours.
COLOURS = {
    "skin":       (0.898, 0.706, 0.522),
    "skin_dark":  (0.820, 0.616, 0.435),   # hands, under the sleeve
    "hair":       (0.208, 0.118, 0.086),
    "shirt":      (0.357, 0.447, 0.529),
    "shirt_dark": (0.298, 0.376, 0.451),   # pocket flaps, collar underside
    "epaulette":  (0.729, 0.176, 0.145),
    "badge":      (0.878, 0.573, 0.184),
    "belt":       (0.078, 0.078, 0.090),
    "pants":      (0.106, 0.145, 0.322),
    "shoe":       (0.043, 0.043, 0.055),
    "metal":      (0.545, 0.565, 0.596),
    "holster":    (0.118, 0.118, 0.137),
}

# Cross-section detail. Eight sides reads as "faceted but not blocky" at the
# distance NPCs are actually seen from, and keeps the whole officer near 1.4k
# triangles.
LIMB_SIDES = 8


def log(message):
    print("[police] {:s}".format(message))
    sys.stdout.flush()


# ---------------------------------------------------------------------------
# Mesh building
# ---------------------------------------------------------------------------

class Builder:
    """Accumulates vertices/faces tagged with a material and a bone."""

    def __init__(self, to_world):
        self.to_world = to_world
        self.verts = []
        self.faces = []
        self.face_material = []
        self.groups = {}        # bone name -> [vertex index, ...]
        self.materials = []     # ordered material names
        self._material_index = {}

    def _material(self, name):
        if name not in self._material_index:
            self._material_index[name] = len(self.materials)
            self.materials.append(name)
        return self._material_index[name]

    def add(self, verts, faces, material, bone):
        """Append one part. `faces` index into `verts` locally."""
        base = len(self.verts)
        for v in verts:
            self.verts.append(self.to_world @ mathutils.Vector(v))
        for face in faces:
            self.faces.append([base + i for i in face])
            self.face_material.append(self._material(material))
        bone_name = BONE_PREFIX + bone
        self.groups.setdefault(bone_name, []).extend(
            range(base, base + len(verts))
        )


def ring(centre, radius_x, radius_z, sides=LIMB_SIDES, twist=0.0):
    """One horizontal ring of points around `centre` (x, y, z)."""
    cx, cy, cz = centre
    out = []
    for i in range(sides):
        angle = twist + (i / sides) * math.tau
        out.append((cx + math.cos(angle) * radius_x,
                    cy,
                    cz + math.sin(angle) * radius_z))
    return out


def tube(sections, sides=LIMB_SIDES, cap_bottom=True, cap_top=True):
    """Loft a closed tube through `sections` = [(centre, rx, rz), ...]."""
    verts = []
    for centre, rx, rz in sections:
        verts.extend(ring(centre, rx, rz, sides))
    faces = []
    for s in range(len(sections) - 1):
        lower = s * sides
        upper = (s + 1) * sides
        for i in range(sides):
            j = (i + 1) % sides
            faces.append([lower + i, lower + j, upper + j, upper + i])
    if cap_bottom:
        faces.append(list(range(sides - 1, -1, -1)))
    if cap_top:
        top = (len(sections) - 1) * sides
        faces.append([top + i for i in range(sides)])
    return verts, faces


def limb(start, end, start_radius, end_radius, sides=LIMB_SIDES):
    """A tapered tube from `start` to `end`, both (x, y, z)."""
    start_vec = mathutils.Vector(start)
    end_vec = mathutils.Vector(end)
    axis = end_vec - start_vec
    length = axis.length
    if length < 1e-6:
        return [], []
    axis.normalize()
    # Any vector not parallel to the axis works as the seed for the frame.
    seed = mathutils.Vector((0.0, 0.0, 1.0))
    if abs(axis.dot(seed)) > 0.95:
        seed = mathutils.Vector((1.0, 0.0, 0.0))
    side = axis.cross(seed).normalized()
    up = side.cross(axis).normalized()

    verts = []
    for centre, radius in ((start_vec, start_radius), (end_vec, end_radius)):
        for i in range(sides):
            angle = (i / sides) * math.tau
            offset = side * (math.cos(angle) * radius) + up * (math.sin(angle) * radius)
            verts.append(tuple(centre + offset))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append([i, j, sides + j, sides + i])
    faces.append(list(range(sides - 1, -1, -1)))
    faces.append([sides + i for i in range(sides)])
    return verts, faces


def box(centre, size):
    """Axis-aligned box; `centre` and `size` are (x, y, z)."""
    cx, cy, cz = centre
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    verts = [
        (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy - hy, cz + hz), (cx - hx, cy - hy, cz + hz),
        (cx - hx, cy + hy, cz - hz), (cx + hx, cy + hy, cz - hz),
        (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
    ]
    faces = [
        [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
        [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
    ]
    return verts, faces


def wedge_box(centre, size, top_scale_z=1.0, top_scale_x=1.0):
    """Box whose top face is scaled -- used for the shoe and the cap of hair."""
    cx, cy, cz = centre
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    tx, tz = hx * top_scale_x, hz * top_scale_z
    verts = [
        (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
        (cx + hx, cy - hy, cz + hz), (cx - hx, cy - hy, cz + hz),
        (cx - tx, cy + hy, cz - tz), (cx + tx, cy + hy, cz - tz),
        (cx + tx, cy + hy, cz + tz), (cx - tx, cy + hy, cz + tz),
    ]
    faces = [
        [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
        [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
    ]
    return verts, faces


# ---------------------------------------------------------------------------
# The officer
# ---------------------------------------------------------------------------

def build_officer(builder, bones):
    """Lay the body out around the rig's rest positions.

    `bones` maps bone name -> (head, tail) captured before the rig was
    normalised, so everything below stays in the centimetre, +Y up authoring
    space these numbers were measured in.
    """

    def head_of(name):
        return tuple(bones[BONE_PREFIX + name][0])

    hips = head_of("Hips")
    spine = head_of("Spine")
    spine1 = head_of("Spine1")
    spine2 = head_of("Spine2")
    neck = head_of("Neck")
    head = head_of("Head")

    # --- Torso -------------------------------------------------------------
    # Shirt runs hem to collar. It is one tube so the silhouette stays smooth;
    # it binds to Spine1, the bone the retargeted clips twist the least, and
    # the hem overlaps the belt so no gap opens when he bends.
    hem_y = hips[1] - 3.0
    builder.add(*tube([
        ((0.0, hem_y, 0.5), 15.5, 10.5),
        ((0.0, spine[1], 0.0), 15.0, 10.0),
        ((0.0, spine1[1], -1.5), 16.5, 10.5),
        ((0.0, spine2[1], -3.0), 18.5, 11.0),
        ((0.0, spine2[1] + 9.0, -4.5), 19.5, 11.0),
        ((0.0, neck[1] + 1.0, -5.0), 15.0, 9.0),
    ]), "shirt", "Spine1")

    # Collar: a short flared ring sitting proud of the shoulders.
    builder.add(*tube([
        ((0.0, neck[1] - 1.0, -5.0), 9.5, 7.5),
        ((0.0, neck[1] + 3.5, -5.0), 8.0, 6.5),
    ], cap_bottom=False, cap_top=False), "shirt_dark", "Spine2")

    # Button placket down the centre front, plus five buttons.
    builder.add(*box((0.0, (hem_y + neck[1]) * 0.5, 10.6),
                     (2.6, neck[1] - hem_y - 2.0, 0.7)), "shirt_dark", "Spine1")
    for index in range(5):
        button_y = hem_y + 6.0 + index * ((neck[1] - hem_y - 10.0) / 4.0)
        builder.add(*box((0.0, button_y, 11.2), (1.5, 1.5, 0.5)),
                    "belt", "Spine1")

    # Chest pockets with flaps, one either side of the placket.
    for side in (-1, 1):
        pocket_x = side * 8.0
        builder.add(*box((pocket_x, spine1[1] + 7.0, 10.5), (8.0, 8.0, 0.6)),
                    "shirt_dark", "Spine1")
        builder.add(*box((pocket_x, spine1[1] + 11.4, 10.8), (8.6, 2.6, 0.9)),
                    "shirt_dark", "Spine1")

    # Badge on his left chest, above the pocket. Built with `limb` along +Z so
    # it faces front: `tube` stacks its rings in Y, so two rings at one height
    # collapse into a horizontal disc that reads edge-on as a dark sliver.
    # It also stands clear of the shirt -- the torso is an ellipse, so the
    # surface has fallen back to z ~ 8.8 this far off centre.
    builder.add(*limb(
        (9.2, spine1[1] + 14.2, 8.6), (9.2, spine1[1] + 14.2, 10.9),
        4.3, 3.6, sides=10
    ), "badge", "Spine1")

    # --- Arms --------------------------------------------------------------
    # Short sleeve over the top third of the upper arm, then bare skin. The
    # sleeve is bound to the arm bone, not the torso, so it swings with it.
    for side_name, sign in (("Left", 1), ("Right", -1)):
        shoulder = head_of(side_name + "Shoulder")
        arm = head_of(side_name + "Arm")
        fore = head_of(side_name + "ForeArm")
        hand = head_of(side_name + "Hand")
        hand_tail = tuple(bones[BONE_PREFIX + side_name + "Hand"][1])

        # Deltoid cap: fills the corner between torso and sleeve.
        builder.add(*limb(
            (sign * 15.0, shoulder[1] - 1.0, shoulder[2]),
            (sign * 22.0, arm[1], arm[2]), 9.5, 8.6
        ), "shirt", side_name + "Arm")
        sleeve_end = tuple(
            arm[i] + (fore[i] - arm[i]) * 0.42 for i in range(3)
        )
        builder.add(*limb(arm, sleeve_end, 8.6, 7.4), "shirt", side_name + "Arm")
        # Bare upper arm continues out of the cuff.
        builder.add(*limb(
            tuple(arm[i] + (fore[i] - arm[i]) * 0.38 for i in range(3)),
            fore, 6.2, 5.4
        ), "skin", side_name + "Arm")
        builder.add(*limb(fore, hand, 5.4, 4.2), "skin", side_name + "ForeArm")
        # Hand: tapers to the fingertips rather than splaying into a paddle.
        builder.add(*limb(
            hand,
            tuple(hand[i] + (hand_tail[i] - hand[i]) * 1.7 for i in range(3)),
            4.0, 2.4, sides=6
        ), "skin_dark", side_name + "Hand")

        # Epaulette: a red strap along the shoulder seam. It rides on top of
        # the deltoid cap, which otherwise swallows it from the front.
        builder.add(*box(
            (sign * 13.0, shoulder[1] + 4.6, shoulder[2] + 0.5), (13.0, 2.4, 9.4)
        ), "epaulette", "Spine2")

    # --- Belt, holster, handcuffs -----------------------------------------
    belt_y = hips[1] + 1.0
    builder.add(*tube([
        ((0.0, belt_y - 3.0, 0.5), 16.2, 11.2),
        ((0.0, belt_y + 3.0, 0.5), 16.4, 11.4),
    ], cap_bottom=False, cap_top=False), "belt", "Hips")
    builder.add(*box((0.0, belt_y, 11.6), (5.0, 5.0, 1.2)), "metal", "Hips")

    # Holster on his right hip: pouch plus the pistol grip standing out of it.
    builder.add(*box((-15.5, belt_y - 7.0, 2.0), (5.5, 12.0, 8.5)),
                "holster", "Hips")
    builder.add(*box((-15.5, belt_y + 1.5, 3.5), (4.6, 7.0, 6.0)),
                "metal", "Hips")

    # Handcuffs on his left hip: two rings hanging off a short strap.
    builder.add(*box((14.5, belt_y - 4.0, 1.0), (3.0, 6.0, 4.0)),
                "holster", "Hips")
    for ring_index in range(2):
        builder.add(*tube([
            ((14.5, belt_y - 9.0 - ring_index * 3.4, 1.0), 3.2, 3.2),
            ((14.5, belt_y - 7.4 - ring_index * 3.4, 1.0), 3.2, 3.2),
        ], sides=10, cap_bottom=False, cap_top=False), "metal", "Hips")

    # --- Legs --------------------------------------------------------------
    # Hips block bridges the two thighs so the crotch is not an open hole.
    builder.add(*tube([
        ((0.0, hips[1] - 8.0, 0.0), 14.0, 10.0),
        ((0.0, hips[1] + 2.0, 0.5), 15.8, 10.8),
    ]), "pants", "Hips")

    for side_name, sign in (("Left", 1), ("Right", -1)):
        up_leg = head_of(side_name + "UpLeg")
        knee = head_of(side_name + "Leg")
        ankle = head_of(side_name + "Foot")
        toe = head_of(side_name + "ToeBase")

        builder.add(*limb(
            (sign * 8.2, up_leg[1] + 3.0, up_leg[2]), knee, 10.0, 7.6
        ), "pants", side_name + "UpLeg")
        # Trouser leg flares slightly at the ankle, as in the reference.
        builder.add(*limb(
            tuple(up_leg[i] + (knee[i] - up_leg[i]) * 0.92 for i in range(3)),
            (ankle[0], ankle[1] + 1.5, ankle[2]), 7.6, 7.0
        ), "pants", side_name + "Leg")

        # Shoe: sole box plus a rounded upper, running out to the toe. Sized
        # off the reference's chunky black shoes -- a shoe scaled to the bare
        # foot disappears under the trouser cuff.
        shoe_z = (ankle[2] + toe[2]) * 0.5 + 4.0
        builder.add(*wedge_box(
            (ankle[0] * 1.05, 2.2, shoe_z), (11.0, 4.4, 31.0),
            top_scale_z=0.95, top_scale_x=0.96
        ), "shoe", side_name + "Foot")
        builder.add(*wedge_box(
            (ankle[0] * 1.05, 7.0, shoe_z - 5.0), (10.4, 6.4, 20.0),
            top_scale_z=0.74, top_scale_x=0.90
        ), "shoe", side_name + "Foot")

    # --- Head --------------------------------------------------------------
    builder.add(*limb(
        (0.0, neck[1] - 2.0, head[2]), (0.0, head[1] + 1.0, head[2]), 5.6, 6.4
    ), "skin", "Neck")

    # Skull: a stack of rings, wider at the temples than at the jaw.
    builder.add(*tube([
        ((0.0, head[1] + 1.0, head[2] + 0.5), 6.2, 7.0),
        ((0.0, head[1] + 5.0, head[2] + 1.0), 7.4, 8.6),
        ((0.0, head[1] + 11.0, head[2] + 0.5), 8.0, 9.0),
        ((0.0, head[1] + 17.0, head[2] - 0.5), 7.6, 8.4),
        ((0.0, head[1] + 20.5, head[2] - 1.5), 5.4, 6.0),
    ], sides=10), "skin", "Head")

    # Hair: a cap over the crown, cut away at the brow.
    builder.add(*tube([
        ((0.0, head[1] + 13.0, head[2] - 1.0), 8.3, 9.3),
        ((0.0, head[1] + 17.5, head[2] - 0.5), 7.9, 8.7),
        ((0.0, head[1] + 21.0, head[2] - 1.5), 5.6, 6.2),
    ], sides=10), "hair", "Head")
    # Sideburns / back of the head, so the crown is not floating.
    builder.add(*tube([
        ((0.0, head[1] + 8.0, head[2] - 4.5), 7.6, 5.0),
        ((0.0, head[1] + 15.0, head[2] - 4.0), 8.2, 5.4),
    ], sides=8), "hair", "Head")

    # Brows and eyes: flat insets, enough to read a face at NPC distance.
    for sign in (-1, 1):
        builder.add(*box((sign * 3.0, head[1] + 12.6, head[2] + 8.4),
                         (3.2, 1.0, 0.6)), "hair", "Head")
        builder.add(*box((sign * 3.0, head[1] + 11.2, head[2] + 8.4),
                         (2.6, 1.4, 0.5)), "belt", "Head")


# ---------------------------------------------------------------------------
# Scene assembly
# ---------------------------------------------------------------------------

def import_rig():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if not SOURCE_FBX.exists():
        raise SystemExit("missing source rig: {:s}".format(str(SOURCE_FBX)))
    bpy.ops.import_scene.fbx(filepath=str(SOURCE_FBX))
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not armatures:
        raise SystemExit("no armature in {:s}".format(SOURCE_FBX.name))
    armature = armatures[0]
    armature.name = "PoliceRig"
    # Keep the Idle clip that ships with the rig: it becomes the officer's
    # baked idle animation in the GLB. The FBX importer names the action after
    # the file, so pin it to a stable name the exporter can lean on.
    idle_action = None
    for action in list(bpy.data.actions):
        if "mixamo" in action.name:
            idle_action = action
            action.name = "Idle"
    for action in list(bpy.data.actions):
        if action.name != "Idle":
            bpy.data.actions.remove(action)
    # The FBX ships a couple of empties alongside the rig; they would export as
    # stray nodes and confuse the Godot scene.
    for obj in list(bpy.data.objects):
        if obj.type not in {"ARMATURE", "MESH"}:
            bpy.data.objects.remove(obj, do_unlink=True)

    # Snapshot the rest pose in the rig's *imported* space -- centimetres,
    # +Y up, +Z front -- which is the space the body below is authored in, and
    # the matrix that maps it into Blender's metre-scale Z-up world.
    authoring_to_world = armature.matrix_world.copy()
    rest = {}
    for bone in armature.data.bones:
        rest[bone.name] = (bone.head_local.copy(), bone.tail_local.copy())

    # Then normalise the rig: the FBX arrives at 0.01 scale with a Y-up->Z-up
    # rotation on the object, and exporting that verbatim ships a rig Godot
    # reads as a 1/100-scale skeleton lying on its back -- which is what made
    # the playable officer come out 500x too big when `cblock_player.gd` sized
    # him from it. Applying the transform bakes both into the bone rest data,
    # leaving an identity object at metre scale in Z-up: the same shape every
    # other playable rig here already has.
    rig_scale = authoring_to_world.to_scale().x
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # `transform_apply` rescales the bone rest data but leaves any action's
    # location curves alone, and bone translation is expressed in the bone's
    # own (now 100x smaller) space. Left as-is the idle hurls the hips ~100 m
    # into the air and the officer renders as an empty frame. Rotation curves
    # need no such fix: they are parent-relative, and rotating every bone by
    # the same amount leaves those relationships untouched.
    if idle_action is not None:
        for curve in idle_action.fcurves:
            if not curve.data_path.endswith(".location"):
                continue
            for key in curve.keyframe_points:
                key.co.y *= rig_scale
                key.handle_left.y *= rig_scale
                key.handle_right.y *= rig_scale
            curve.update()

    log("rig: {:d} bones, normalised to identity at metre scale "
        "(location curves x{:g})".format(len(armature.data.bones), rig_scale))
    return armature, idle_action, authoring_to_world, rest


def make_material(name):
    material = bpy.data.materials.new("Police_" + name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    red, green, blue = COLOURS[name]
    bsdf.inputs["Base Color"].default_value = (red, green, blue, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.25
    if name in ("metal", "badge"):
        # Kept deliberately low. The game lights these with a couple of Omnis
        # and no reflection probe, and a properly metallic surface with nothing
        # to reflect just renders black -- which is how the badge disappeared.
        bsdf.inputs["Metallic"].default_value = 0.15
        bsdf.inputs["Roughness"].default_value = 0.45
    return material


def main():
    armature, idle_action, authoring_to_world, rest = import_rig()
    # The body is authored in the rig's original centimetre / +Y up space; this
    # matrix carries it into the normalised metre-scale Z-up rig it binds to.
    builder = Builder(authoring_to_world)
    build_officer(builder, rest)

    mesh = bpy.data.meshes.new("PoliceBody")
    mesh.from_pydata([tuple(v) for v in builder.verts], [], builder.faces)
    mesh.validate(verbose=False)

    obj = bpy.data.objects.new("PoliceBody", mesh)
    bpy.context.collection.objects.link(obj)

    for name in builder.materials:
        mesh.materials.append(make_material(name))
    for polygon, material_index in zip(mesh.polygons, builder.face_material):
        polygon.material_index = material_index

    # Outward normals, then flat shading: the faceted look is the point.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = False

    # Rigid bind: one bone per part, weight 1.0.
    for bone_name, indices in builder.groups.items():
        group = obj.vertex_groups.new(name=bone_name)
        group.add(indices, 1.0, "REPLACE")

    # Both objects now sit at identity in the same metre-scale Z-up space, so
    # a plain parent with no parent-inverse is correct.
    obj.parent = armature
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature

    log("body: {:d} verts, {:d} faces, {:d} materials, {:d} bound bones".format(
        len(mesh.vertices), len(mesh.polygons), len(mesh.materials),
        len(builder.groups)))

    # Assign the kept Idle action and give the exporter frames to read. The
    # glTF exporter reads the active action on the armature, and the officer's
    # rest pose lives at frame 0 of the Mixamo clip, so one frame is enough for
    # a no-animation fallback; the full action still exports because
    # export_animations samples it by its own action frame range.
    if idle_action is not None:
        armature.animation_data_create()
        armature.animation_data.action = idle_action
        bpy.context.scene.frame_start = int(idle_action.frame_range[0])
        bpy.context.scene.frame_end = int(idle_action.frame_range[1])
        log("idle: {:s} frames {:d}-{:d}".format(
            idle_action.name, bpy.context.scene.frame_start,
            bpy.context.scene.frame_end))

    OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=False,
        export_apply=False,
        export_animations=True,
        export_skins=True,
        export_yup=True,
    )
    log("wrote {:s} ({:.0f} KB)".format(
        OUTPUT_GLB.name, OUTPUT_GLB.stat().st_size / 1024.0))
    log("DONE")


main()
