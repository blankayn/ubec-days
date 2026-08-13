"""Build the customizable citizen and export it as a skinned GLB.

    "C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P tools/build_citizen.py

Writes `assets/characters/citizen/citizen.glb`.

WHY THIS IS NOT tools/build_police.py WITH BIGGER NUMBERS
--------------------------------------------------------
`build_police.py` builds the officer from overlapping rigid-bound tubes: every
part is weighted 1.0 to one bone and limb segments are pushed into each other so
the joints do not open a gap. That is a genuinely good design for a flat-shaded
PS1 officer and a bad one here, for three reasons:

  1. Smooth shading exposes it. Two intersecting tubes have no shared vertices,
     so the shading breaks along the intersection and you see the seam.
  2. You cannot dress it. Clothing that fits an overlapping-tube body has to be
     hand-sized per part, and it will still poke through when the elbow bends.
  3. It cannot deform. Rigid binding means the elbow is a hinge between two
     rigid cylinders, which reads as a doll, not a person.

So the citizen is ONE watertight all-quad manifold with real skin weights. The
two techniques that make that buildable from a script:

THE SOCKET RULE. Delete a k x k patch of quads from a quad grid and the hole's
boundary is exactly 4k vertices -- so it bridges to a 4k-sided limb ring with no
remainder. k=2 gives the 8-sided arm and leg sockets, k=1 the 4-sided thumb.
This is why citizen_spec.SIDES_LIMB is 8 and not "whatever looks right": the
side counts are derived from the socket size, and changing one without the other
opens a hole in the armpit.

PARALLEL-TRANSPORT FRAMES. `build_police.limb()` seeds a fresh orthonormal frame
from an arbitrary vector on every call, so two adjoining segments get frames
rotated relative to each other and their ring vertices do not correspond. That is
precisely why the officer HAS to overlap its tubes -- a bridge between two
independently-seeded rings bowties. `transport_frames()` seeds once at the chain
root and carries the frame with minimal twist, so consecutive rings correspond
and can simply be bridged.

WHAT IS COPIED VERBATIM AND MUST STAY THAT WAY
----------------------------------------------
`import_rig()` is `build_police.import_rig()`, including the fcurve rescale. The
Mixamo FBX arrives at 0.01 scale with a Y-up->Z-up rotation on the object;
`transform_apply` bakes both into the bone rest data but leaves action LOCATION
curves alone, and bone translation is expressed in the bone's own (now 100x
smaller) space. Left unfixed the idle hurls the hips ~100 m into the air. This is
the most expensive bug in this repo's history (PROJECT_STATUS.md, the 500x-too-big
officer); it is not re-derived here.

AUTHORING SPACE: centimetres, +Y up, +Z the way the citizen faces, +X is the
citizen's LEFT. Geometry is placed at the rig's own rest positions, never at
invented coordinates, so the T-pose falls out of the armature for free.
"""

import json
import math
import pathlib
import sys

import bmesh
import bpy
import mathutils

HERE = pathlib.Path(__file__).resolve().parent
PROJECT = HERE.parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import citizen_spec as spec  # noqa: E402

SOURCE_FBX = PROJECT / "animation mixamo" / "Idle.fbx"
OUT_DIR = PROJECT / "assets" / "characters" / "citizen"
OUTPUT_GLB = OUT_DIR / "citizen.glb"
OUTPUT_MANIFEST = OUT_DIR / "citizen_manifest.json"

BONE_PREFIX = "mixamorig1:"

V = mathutils.Vector


def log(message):
    print("[citizen] {:s}".format(message))
    sys.stdout.flush()


# ---------------------------------------------------------------------------
# Frames
# ---------------------------------------------------------------------------

def transport_frames(points, seed_up):
    """Rotation-minimizing frames along a polyline: [(tangent, u, v), ...].

    Seeded once at the root and then carried by the minimal rotation taking
    tangent[i-1] -> tangent[i]. A ring placed with frame i and a ring placed
    with frame i+1 have corresponding vertices, which is the whole point --
    build_police.limb() re-seeds per call and therefore cannot be bridged.
    """
    pts = [V(p) for p in points]
    if len(pts) < 2:
        raise SystemExit("transport_frames needs at least 2 points")

    tangents = []
    for i in range(len(pts)):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        if t.length < 1e-9:
            raise SystemExit("degenerate segment in transport_frames")
        tangents.append(t.normalized())

    u = V(seed_up)
    u = u - tangents[0] * u.dot(tangents[0])
    if u.length < 1e-6:
        # seed_up was parallel to the first tangent; any perpendicular will do.
        u = tangents[0].cross(V((0.0, 0.0, 1.0)))
        if u.length < 1e-6:
            u = tangents[0].cross(V((1.0, 0.0, 0.0)))
    u.normalize()

    frames = []
    for i, t in enumerate(tangents):
        if i > 0:
            u = tangents[i - 1].rotation_difference(t) @ u
            u = u - t * u.dot(t)
            if u.length < 1e-6:
                raise SystemExit("frame collapsed during transport")
            u.normalize()
        v = t.cross(u).normalized()
        frames.append((t, u.copy(), v))
    return frames


def loop_angle(position, centre, u, v):
    """Angle of `position` around `centre` in the (u, v) plane.

    Rings are generated as centre + u*cos(a)*rx + v*sin(a)*rz, so this is the
    exact inverse. Ordering both a generated ring and a carved socket boundary
    through this function is what makes their vertices correspond without any
    hand-written index tables.
    """
    d = V(position) - V(centre)
    return math.atan2(d.dot(v), d.dot(u))


# ---------------------------------------------------------------------------
# Mesh accumulation
# ---------------------------------------------------------------------------

class Ring:
    """A closed loop of vertex indices in canonical (increasing-angle) order."""

    __slots__ = ("indices", "centre", "frame", "region")

    def __init__(self, indices, centre, frame, region):
        self.indices = list(indices)
        self.centre = V(centre)
        self.frame = frame
        self.region = region

    def __len__(self):
        return len(self.indices)


class QuadMesh:
    """Accumulates an all-quad mesh tagged by region and by material slot.

    Two tag streams rather than one because the polygon budget is anatomical
    (`region`: how many quads the head is allowed) while the material is per
    customization slot (`slot`: which colour swatch tints it), and the two do
    not line up -- the torso region carries both `skin` and, once the tee shell
    is built on top of it, `top`.

    Vertices stay in the authoring space (cm) for the whole build so the weight
    solver can measure real distances against the bone rest data; the transform
    into Blender's metre-scale Z-up world happens once, in `to_object`.
    """

    def __init__(self):
        self.verts = []
        self.quads = []
        self.quad_region = []
        self.quad_slot = []
        self.weights = []          # per-vertex {bone: weight}, filled later
        self.vert_region = []

    # -- primitives --------------------------------------------------------

    def add_vert(self, position, region):
        self.verts.append(V(position))
        self.vert_region.append(region)
        self.weights.append({})
        return len(self.verts) - 1

    def add_face(self, indices, region, slot):
        """Any-length face. Harvested accessories arrive as triangles."""
        self.quads.append(tuple(indices))
        self.quad_region.append(region)
        self.quad_slot.append(slot)

    def add_quad(self, a, b, c, d, region, slot):
        self.add_face((a, b, c, d), region, slot)

    def ring(self, centre, frame, rx, rz, sides, region):
        _, u, v = frame
        centre = V(centre)
        indices = []
        for i in range(sides):
            a = (i / sides) * math.tau
            indices.append(self.add_vert(
                centre + u * (math.cos(a) * rx) + v * (math.sin(a) * rz),
                region,
            ))
        return Ring(indices, centre, frame, region)

    def order_loop(self, indices, centre, u, v, positions=None):
        """Sort loose vertex indices into canonical order around `centre`.

        This fixes the CYCLE but not the rotational PHASE -- the loop can still
        start anywhere. Phase is settled at bridge time by `best_shift`,
        because the right criterion is geometric (which pairing is shortest)
        and not angular: an irregular loop like the seat ring, which is seven
        torso vertices plus one invented medial one, has no vertex sitting at a
        meaningful angle to align to.

        `positions` overrides where each index is considered to be, so a shell
        can be ordered by the body vertices it was derived from rather than by
        its own displaced ones.
        """
        at = (lambda i: positions[i]) if positions is not None else (lambda i: self.verts[i])
        return sorted(indices, key=lambda i: loop_angle(at(i), centre, u, v))

    def best_shift(self, ring_a, ring_b):
        """The rotation of `ring_b` that makes the best bridge with `ring_a`.

        A sorted loop and a generated ring agree on winding but not on PHASE --
        neither knows where the other starts. Left unaligned the shoulder
        socket met the sleeve ring three vertices out of step: cross-edges of
        9-14 cm where 3 cm was right, every bridge quad bowtied, and a torn
        hole at the shoulder of every top.

        Scored on the bridge that would actually be produced -- bowties first,
        then total cross-edge length -- rather than on a proxy. Both proxies
        were tried and both are wrong somewhere: nearest-angle-to-zero fixes
        the arm and breaks the leg, whose seat loop is seven torso vertices
        plus an invented medial one and so has no vertex at a meaningful
        angle; nearest-distance breaks it too, because the shortest pairing of
        an irregular loop is not always the untwisted one. n is 4 or 8, so
        evaluating every rotation for real costs nothing.
        """
        n = len(ring_a)
        best, best_score = 0, None
        for shift in range(n):
            bowties = 0
            length = 0.0
            for i in range(n):
                j = (i + 1) % n
                quad = [
                    self.verts[ring_a.indices[i]],
                    self.verts[ring_a.indices[j]],
                    self.verts[ring_b.indices[(j + shift) % n]],
                    self.verts[ring_b.indices[(i + shift) % n]],
                ]
                n1 = (quad[1] - quad[0]).cross(quad[3] - quad[0])
                n2 = (quad[2] - quad[1]).cross(quad[0] - quad[1])
                if n1.length < 1e-9 or n2.length < 1e-9:
                    bowties += 1
                elif n1.normalized().dot(n2.normalized()) < 0.0:
                    bowties += 1
                length += (quad[3] - quad[0]).length
            score = (bowties, length)
            if best_score is None or score < best_score:
                best, best_score = shift, score
        return best

    # -- joining -----------------------------------------------------------

    def bridge(self, ring_a, ring_b, region, slot, shift=0, skip_columns=()):
        """Join two equal-length loops. `shift` rotates the correspondence.

        `skip_columns` is the k=1 socket: it leaves one quad out so a thumb can
        be bridged into the hole.
        """
        n = len(ring_a)
        if n != len(ring_b):
            raise SystemExit(
                "bridge needs equal loops, got {:d} and {:d}".format(n, len(ring_b))
            )
        for i in range(n):
            if i in skip_columns:
                continue
            j = (i + 1) % n
            self.add_quad(
                ring_a.indices[i],
                ring_a.indices[j],
                ring_b.indices[(j + shift) % n],
                ring_b.indices[(i + shift) % n],
                region, slot,
            )

    def stack(self, rings, region, slot, skip=frozenset(), band_slots=None):
        """Bridge a stack of equal-length rings, skipping (band, column) quads.

        `skip` is how sockets are carved: the quads are simply never emitted, so
        there is no delete-and-reindex step and no chance of a stale index.

        `band_slots` overrides the material slot for individual bands, which is
        how a garment gets a horizontal contrast stripe without needing a
        second mesh -- the stripe is the same surface, tagged differently.
        """
        for band in range(len(rings) - 1):
            lower, upper = rings[band], rings[band + 1]
            band_slot = slot if band_slots is None else band_slots.get(band, slot)
            n = len(lower)
            for column in range(n):
                if (band, column) in skip:
                    continue
                nxt = (column + 1) % n
                self.add_quad(
                    lower.indices[column], lower.indices[nxt],
                    upper.indices[nxt], upper.indices[column],
                    region, band_slot,
                )

    def cap_even_ngon(self, loop_indices, region, slot):
        """Strip-fill an n-gon (n even) with n/2 - 1 quads. No fan, no pole."""
        n = len(loop_indices)
        if n % 2 != 0:
            raise SystemExit("cap_even_ngon needs an even loop, got {:d}".format(n))
        for i in range(n // 2 - 1):
            self.add_quad(
                loop_indices[i], loop_indices[i + 1],
                loop_indices[n - 2 - i], loop_indices[n - 1 - i],
                region, slot,
            )

    # -- sockets -----------------------------------------------------------

    def socket_boundary(self, rings, band, column, k):
        """Vertex indices ringing a k x k skipped patch, plus the dead interior.

        Returns (boundary_indices, interior_indices). The interior vertices are
        left unreferenced by any quad and get dropped by `compact()`. The
        boundary is 4k vertices, which is exactly a limb ring -- that identity
        is the whole socket rule.
        """
        n = len(rings[band])
        cols = [(column + i) % n for i in range(k + 1)]
        bands = [band + i for i in range(k + 1)]
        boundary, interior = [], []
        for bi, b in enumerate(bands):
            for ci, c in enumerate(cols):
                index = rings[b].indices[c]
                edge = bi in (0, k) or ci in (0, k)
                (boundary if edge else interior).append(index)
        if len(boundary) != 4 * k:
            raise SystemExit(
                "socket boundary is {:d}, expected {:d}".format(len(boundary), 4 * k)
            )
        return boundary, interior

    def skip_set(self, band, column, k, sides):
        return {
            (band + i, (column + j) % sides)
            for i in range(k) for j in range(k)
        }

    # -- reporting ---------------------------------------------------------

    def counts(self):
        totals = {}
        for region in self.quad_region:
            totals[region] = totals.get(region, 0) + 1
        return totals

    def compact(self):
        """Drop vertices no quad references, remapping everything that stays."""
        used = sorted({i for quad in self.quads for i in quad})
        if len(used) == len(self.verts):
            return 0
        remap = {old: new for new, old in enumerate(used)}
        dropped = len(self.verts) - len(used)
        self.verts = [self.verts[i] for i in used]
        self.vert_region = [self.vert_region[i] for i in used]
        self.weights = [self.weights[i] for i in used]
        self.quads = [tuple(remap[i] for i in quad) for quad in self.quads]
        return dropped


# ---------------------------------------------------------------------------
# Rig import -- copied from tools/build_police.py, see the module docstring
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
    armature.name = "CitizenRig"

    idle_action = None
    for action in list(bpy.data.actions):
        if "mixamo" in action.name:
            idle_action = action
            action.name = "Idle"
    for action in list(bpy.data.actions):
        if action.name != "Idle":
            bpy.data.actions.remove(action)
    for obj in list(bpy.data.objects):
        if obj.type not in {"ARMATURE", "MESH"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)

    authoring_to_world = armature.matrix_world.copy()
    rest = {}
    for bone in armature.data.bones:
        rest[bone.name] = (bone.head_local.copy(), bone.tail_local.copy())

    rig_scale = authoring_to_world.to_scale().x
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if idle_action is not None:
        for curve in idle_action.fcurves:
            if not curve.data_path.endswith(".location"):
                continue
            for key in curve.keyframe_points:
                key.co.y *= rig_scale
                key.handle_left.y *= rig_scale
                key.handle_right.y *= rig_scale
            curve.update()

    log("rig: {:d} bones, normalised to identity at metre scale (location curves x{:g})"
        .format(len(armature.data.bones), rig_scale))
    return armature, idle_action, authoring_to_world, rest


def missing_bones(rest):
    return [n for n in spec.WEIGHT_BONES if BONE_PREFIX + n not in rest]


# ---------------------------------------------------------------------------
# The body
# ---------------------------------------------------------------------------

UP = V((0.0, 1.0, 0.0))
FRONT = V((0.0, 0.0, 1.0))
LEFT = V((1.0, 0.0, 0.0))
BODY_FRAME = (UP, LEFT, FRONT)   # tangent +Y, u +X, v +Z -> index 0 faces LEFT


def build_body(mesh, bones):
    """Lay the body out around the rig's rest positions.

    Returns a dict of landmark rings the clothing shells are derived from.
    """

    def head_of(name):
        return V(bones[BONE_PREFIX + name][0])

    def tail_of(name):
        return V(bones[BONE_PREFIX + name][1])

    n_body = spec.SIDES_BODY
    n_limb = spec.SIDES_LIMB
    k = spec.SOCKET_K_LIMB
    landmarks = {}

    anchors = {
        "Hips": head_of("Hips"),
        "Spine": head_of("Spine"),
        "Spine1": head_of("Spine1"),
        "Spine2": head_of("Spine2"),
        "Neck": head_of("Neck"),
        "Head": head_of("Head"),
    }

    # --- Torso ------------------------------------------------------------
    torso_rings = []
    for name, (anchor, dy), rx, rz, dz in spec.TORSO_STATIONS:
        centre = V((0.0, anchors[anchor].y + dy, dz))
        torso_rings.append(mesh.ring(centre, BODY_FRAME, rx, rz, n_body, "torso"))
    landmarks["torso"] = torso_rings

    # Shoulder sockets. Band index is where the arm leaves the chest; the
    # patch spans bands [band, band+k) so the arm exits between the chest and
    # shoulder rings rather than out of the neck.
    band = spec.SHOULDER_SOCKET_BAND
    left_col = (-(k // 2)) % n_body                 # centred on side 0  (+X, left)
    right_col = (n_body // 2 - k // 2) % n_body     # centred on side n/2 (-X, right)

    skip = mesh.skip_set(band, left_col, k, n_body) | mesh.skip_set(band, right_col, k, n_body)
    mesh.stack(torso_rings, "torso", "skin", skip=skip)

    left_socket, _ = mesh.socket_boundary(torso_rings, band, left_col, k)
    right_socket, _ = mesh.socket_boundary(torso_rings, band, right_col, k)

    # --- Pelvis: the seat ring branches into two leg loops ----------------
    # A 16-vertex seat ring splits into two 8-vertex leg loops (7 verts of the
    # ring's own arc plus one new medial vertex each), leaving the front- and
    # back-centre vertices to close an 8-gon crotch between them. Every seat
    # edge ends up with exactly two faces, so the branch is watertight.
    seat = torso_rings[0]
    quarter = n_body // 4
    front_c, back_c = quarter, 3 * quarter          # +Z front, -Z back
    arc = (n_limb - 1) // 2                         # 3 verts either side of centre

    seat_y = seat.centre.y
    crotch_y = seat_y - spec.CROTCH_DROP_CM
    medial = {}
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        medial[side] = mesh.add_vert(
            V((sign * spec.CROTCH_INSET_CM, crotch_y, seat.centre.z)), "pelvis"
        )

    leg_loops = {}
    for side, centre_col in (("Left", 0), ("Right", n_body // 2)):
        cols = [(centre_col + d) % n_body for d in range(-arc, arc + 1)]
        loop = [seat.indices[c] for c in cols] + [medial[side]]
        leg_loops[side] = loop

    crotch_loop = [
        seat.indices[(front_c - 1) % n_body],
        seat.indices[front_c],
        seat.indices[(front_c + 1) % n_body],
        medial["Right"],
        seat.indices[(back_c - 1) % n_body],
        seat.indices[back_c],
        seat.indices[(back_c + 1) % n_body],
        medial["Left"],
    ]
    mesh.cap_even_ngon(crotch_loop, "pelvis", "skin")

    # --- Neck and head ----------------------------------------------------
    neck_rings = [torso_rings[-1]]
    for dy, rx, rz, dz in spec.NECK_STATIONS:
        neck_rings.append(mesh.ring(
            V((0.0, anchors["Neck"].y + dy, anchors["Neck"].z + dz)),
            BODY_FRAME, rx, rz, n_body, "neck",
        ))
    mesh.stack(neck_rings, "neck", "skin")
    landmarks["neck"] = neck_rings

    head_rings = [neck_rings[-1]]
    for dy, rx, rz, dz in spec.HEAD_STATIONS:
        head_rings.append(mesh.ring(
            V((0.0, anchors["Head"].y + dy, anchors["Head"].z + dz)),
            BODY_FRAME, rx, rz, n_body, "head",
        ))
    mesh.stack(head_rings, "head", "skin")
    mesh.cap_even_ngon(head_rings[-1].indices, "head", "skin")
    landmarks["head"] = head_rings[1:]

    shape_face(mesh, head_rings, n_body)

    # --- Arms -------------------------------------------------------------
    for side, sign, socket in (("Left", 1.0, left_socket), ("Right", -1.0, right_socket)):
        landmarks.update(build_arm(mesh, bones, side, sign, socket, n_limb))

    # --- Legs -------------------------------------------------------------
    for side, sign in (("Left", 1.0), ("Right", -1.0)):
        landmarks.update(build_leg(mesh, bones, side, sign, leg_loops[side], n_limb))

    return landmarks


def shape_face(mesh, head_rings, n_body):
    """Push existing head-ring vertices into a face.

    Relief rather than added geometry: at this density a nose built from new
    faces costs ~20 quads and reads no better than a pushed vertex, and every
    quad spent here is a quad not spent on the joint loops that actually carry
    the deformation.
    """
    quarter = n_body // 4
    front = quarter
    # head_rings[0] is the neck ring; spec.HEAD_STATIONS start at index 1.
    def band(i):
        return head_rings[i + 1]

    def push(ring, column, delta):
        mesh.verts[ring.indices[column % n_body]] += V(delta)

    # Nose: the CENTRE column only, over three bands, so it reads as a ridge in
    # profile. Spreading it onto the neighbouring columns was tried and had to
    # be reverted -- it lifts the vertex at 67.5 degrees ~0.9 cm proud, which is
    # exactly where the eye patch sits, and the resulting facet sliced each eye
    # into a pair of triangles.
    push(band(spec.FACE_NOSE_BAND), front, FRONT * spec.NOSE_PUSH_CM)
    push(band(spec.FACE_NOSE_BAND - 1), front, FRONT * (spec.NOSE_PUSH_CM * 0.55))
    push(band(spec.FACE_NOSE_BAND + 1), front, FRONT * (spec.NOSE_PUSH_CM * 0.40))

    # No brow ridge or eye recess here: those are the detail mesh's job now.
    # Relief in the eye region can only clip the patches that carry the value.
    push(band(spec.FACE_CHIN_BAND), front, FRONT * spec.CHIN_PUSH_CM)


def head_station(station):
    """(dy, rx, rz, dz) at a FRACTIONAL HEAD_STATIONS index, linearly blended.

    Fractional so a brow can be a third of a band tall instead of being forced
    to whichever height the skull's own loops happen to sit at.
    """
    table = spec.HEAD_STATIONS
    low = max(0, min(len(table) - 1, int(math.floor(station))))
    high = min(len(table) - 1, low + 1)
    t = station - low
    return tuple(table[low][k] + (table[high][k] - table[low][k]) * t for k in range(4))


def build_face_detail(bones):
    """Eyes and brows, as their own mesh lifted just off the head surface.

    Evaluated from the same HEAD_STATIONS ellipse the skull is built from, so
    each patch sits on the skin however the bands are retuned -- but positioned
    by angle and fractional height rather than by ring column, so an eye can go
    where an eye goes. Brows take the `hair` slot so they recolour with the
    hairstyle; eyes get their own.

    Kept off the body mesh on purpose: the body has to stay a closed manifold
    for validate_topology, and an eye needs a dark VALUE, which no amount of
    pushed relief can provide.
    """
    detail = QuadMesh()
    head = V(bones[BONE_PREFIX + "Head"][0])

    def surface(station, angle_deg):
        dy, rx, rz, dz = head_station(station)
        a = math.radians(angle_deg)
        return V((math.cos(a) * rx, head.y + dy, head.z + dz + math.sin(a) * rz))

    def patch(station_lo, station_hi, centre_deg, half_deg, push, slot,
              segments=spec.FACE_PATCH_SEGMENTS):
        """A curved strip lying on the skull, not a flat card stuck to it.

        A single quad spanning 22 degrees of a ~9 cm radius skull dips ~1.7 mm
        below the surface at its centre, so with a 1.8 mm lift only the corners
        cleared and each eye rendered as two triangular slivers. Segmenting the
        strip cuts that sag by segments^2.
        """
        rows = ([], [])
        for step in range(segments + 1):
            angle = centre_deg - half_deg + (2.0 * half_deg) * step / segments
            for row, station in zip(rows, (station_lo, station_hi)):
                p = surface(station, angle)
                outward = V((p.x, 0.0, p.z - head.z))
                outward = outward.normalized() if outward.length > 1e-6 else FRONT
                row.append((detail.add_vert(p + outward * push, "face"), outward))

        low, high = rows
        for step in range(segments):
            lifted = [low[step][0], low[step + 1][0],
                      high[step + 1][0], high[step][0]]
            facing = low[step][1] + low[step + 1][1] + high[step + 1][1] + high[step][1]
            # Wind to face outward HERE. These quads are loose, and
            # bmesh.ops.recalc_face_normals only has a defined answer for a
            # closed volume -- on isolated faces it picks arbitrarily, which
            # silently backface-culled one eye and one brow.
            p0, p1, p3 = (detail.verts[i] for i in (lifted[0], lifted[1], lifted[3]))
            if (p1 - p0).cross(p3 - p0).dot(facing) < 0.0:
                lifted.reverse()
            detail.add_quad(lifted[0], lifted[1], lifted[2], lifted[3], "face", slot)

    # 90 degrees is the facial midline; his LEFT is the smaller angle.
    for sign in (-1.0, 1.0):
        centre = 90.0 + sign * spec.EYE_ANGLE_DEG
        patch(spec.EYE_STATION_LO, spec.EYE_STATION_HI, centre,
              spec.EYE_HALF_DEG, spec.FACE_PATCH_PUSH_CM, "eyes")
        patch(spec.BROW_STATION_LO, spec.BROW_STATION_HI, centre,
              spec.BROW_HALF_DEG, spec.FACE_PATCH_PUSH_CM * 1.6, "hair")

    for index in range(len(detail.verts)):
        detail.weights[index] = {"Head": 1.0}
    return detail


def build_arm(mesh, bones, side, sign, socket_indices, n_limb):
    """Loft one arm from the shoulder socket to the mitten tip."""

    def head_of(name):
        return V(bones[BONE_PREFIX + name][0])

    def tail_of(name):
        return V(bones[BONE_PREFIX + name][1])

    arm = head_of(side + "Arm")
    fore = head_of(side + "ForeArm")
    hand = head_of(side + "Hand")
    hand_tail = tail_of(side + "Hand")

    socket_centre = V((0.0, 0.0, 0.0))
    for i in socket_indices:
        socket_centre += mesh.verts[i]
    socket_centre /= len(socket_indices)

    # Seed the chain on the arm's OWN axis, inboard of the shoulder joint --
    # not at the socket centroid, which sits below LeftArm's rest head and
    # would make the first tangent point up the torso. See ARM_ROOT_INSET_CM.
    arm_axis = (fore - arm).normalized()
    points = [arm - arm_axis * spec.ARM_ROOT_INSET_CM]
    profiles = [None]
    for segment, t, rx, rz in spec.ARM_STATIONS:
        a, b = (arm, fore) if segment == "upper" else (fore, hand)
        points.append(a.lerp(b, t))
        profiles.append((rx, rz))

    hand_dir = (hand_tail - hand)
    hand_dir = hand_dir.normalized() if hand_dir.length > 1e-6 else V((sign, 0.0, 0.0))
    for t, rx, rz in spec.HAND_STATIONS:
        points.append(hand + hand_dir * (spec.HAND_LENGTH_CM * t))
        profiles.append((rx, rz))

    frames = transport_frames(points, UP)

    rings = []
    for i in range(1, len(points)):
        rx, rz = profiles[i]
        region = "hand" if i > len(spec.ARM_STATIONS) else "arm"
        rings.append(mesh.ring(points[i], frames[i], rx, rz, n_limb, region))

    n_arm = len(spec.ARM_STATIONS)
    hand_rings = rings[n_arm:]

    # The thumb column has to be found, not tabulated: the right arm's
    # transported frame is mirrored, so a fixed column index would put one
    # thumb on the front of the hand and the other on the back. Picking the
    # palm edge furthest forward in WORLD +Z is correct for both.
    thumb_band = spec.THUMB_SOCKET_BAND
    thumb_column = max(
        range(n_limb),
        key=lambda c: (mesh.verts[hand_rings[thumb_band].indices[c]].z
                       + mesh.verts[hand_rings[thumb_band + 1].indices[c]].z),
    )

    # The socket boundary and the first arm ring are ordered through the same
    # loop_angle() with the same frame, so their vertices correspond and the
    # bridge cannot twist.
    _, u, v = frames[0]
    ordered = mesh.order_loop(socket_indices, socket_centre, u, v)
    root = Ring(ordered, socket_centre, frames[0], "arm")

    mesh.bridge(root, rings[0], "arm", "skin", shift=mesh.best_shift(root, rings[0]))
    for i in range(len(rings) - 1):
        region = rings[i + 1].region
        skip = ()
        if i == n_arm + thumb_band:
            skip = (thumb_column,)
        mesh.bridge(rings[i], rings[i + 1], region, "skin", skip_columns=skip)

    mesh.cap_even_ngon(rings[-1].indices, "hand", "skin")
    build_thumb(mesh, hand_rings, thumb_band, thumb_column, hand_dir)

    return {
        side + "Arm": rings[:n_arm],
        side + "Hand": hand_rings,
    }


def build_thumb(mesh, hand_rings, band, column, finger_dir):
    """Bridge a 4-sided thumb into the 1x1 hole left in the palm.

    k=1 is the degenerate case of the socket rule: the four corners of the one
    skipped quad ARE the boundary, so there is no interior vertex to drop.
    """
    lower, upper = hand_rings[band], hand_rings[band + 1]
    n = len(lower)
    nxt = (column + 1) % n
    socket = [
        lower.indices[column], lower.indices[nxt],
        upper.indices[nxt], upper.indices[column],
    ]

    centre = V((0.0, 0.0, 0.0))
    for i in socket:
        centre += mesh.verts[i]
    centre /= 4.0

    # Mostly forward, angled a little toward the fingertips so it reads as a
    # thumb rather than a spike.
    direction = (FRONT * 0.85 + finger_dir * 0.45).normalized()

    points = [centre]
    profiles = [None]
    for t, rx, rz in spec.THUMB_STATIONS:
        points.append(centre + direction * (spec.THUMB_LENGTH_CM * t))
        profiles.append((rx, rz))

    frames = transport_frames(points, UP)
    rings = []
    for i in range(1, len(points)):
        rx, rz = profiles[i]
        rings.append(mesh.ring(points[i], frames[i], rx, rz, spec.SIDES_THUMB, "hand"))

    _, u, v = frames[0]
    root = Ring(mesh.order_loop(socket, centre, u, v), centre, frames[0], "hand")

    mesh.bridge(root, rings[0], "hand", "skin", shift=mesh.best_shift(root, rings[0]))
    for i in range(len(rings) - 1):
        mesh.bridge(rings[i], rings[i + 1], "hand", "skin")
    mesh.cap_even_ngon(rings[-1].indices, "hand", "skin")


def build_leg(mesh, bones, side, sign, seat_loop, n_limb):
    """Loft one leg from the seat loop to the toe."""

    def head_of(name):
        return V(bones[BONE_PREFIX + name][0])

    up_leg = head_of(side + "UpLeg")
    knee = head_of(side + "Leg")
    ankle = head_of(side + "Foot")
    toe = head_of(side + "ToeBase")

    loop_centre = V((0.0, 0.0, 0.0))
    for i in seat_loop:
        loop_centre += mesh.verts[i]
    loop_centre /= len(seat_loop)

    # Seeded above the hip joint on the leg's own axis, for the same reason the
    # arm is seeded inboard of the shoulder: the seat loop sits below UpLeg's
    # rest head, so seeding there would point the first tangent upward.
    leg_axis = (knee - up_leg).normalized()
    points = [up_leg - leg_axis * spec.LEG_ROOT_INSET_CM]
    profiles = [None]
    for segment, t, rx, rz in spec.LEG_STATIONS:
        a, b = (up_leg, knee) if segment == "thigh" else (knee, ankle)
        points.append(a.lerp(b, t))
        profiles.append((rx, rz))

    for dy, dz, rx, rz in spec.FOOT_STATIONS:
        points.append(V((ankle.x, ankle.y + dy, ankle.z + dz)))
        profiles.append((rx, rz))

    frames = transport_frames(points, FRONT)

    rings = []
    for i in range(1, len(points)):
        rx, rz = profiles[i]
        region = "foot" if i > len(spec.LEG_STATIONS) else "leg"
        rings.append(mesh.ring(points[i], frames[i], rx, rz, n_limb, region))

    _, u, v = frames[0]
    ordered = mesh.order_loop(seat_loop, loop_centre, u, v)
    root = Ring(ordered, loop_centre, frames[0], "leg")

    mesh.bridge(root, rings[0], "leg", "skin", shift=mesh.best_shift(root, rings[0]))
    for i in range(len(rings) - 1):
        mesh.bridge(rings[i], rings[i + 1], rings[i + 1].region, "skin")
    mesh.cap_even_ngon(rings[-1].indices, "foot", "skin")

    flatten_sole(mesh, rings[len(spec.LEG_STATIONS):])

    return {
        side + "Leg": rings[:len(spec.LEG_STATIONS)],
        side + "Foot": rings[len(spec.LEG_STATIONS):],
    }


def flatten_sole(mesh, foot_rings):
    """Clamp the foot's underside to a flat sole at y = SOLE_Y_CM.

    A lofted tube gives a round-bottomed foot, which floats the character on a
    curve and makes SOLE_CLEARANCE in cblock_player.gd meaningless. Clamping is
    enough at this density and costs no extra geometry.
    """
    for ring in foot_rings:
        for index in ring.indices:
            if mesh.verts[index].y < spec.SOLE_Y_CM:
                mesh.verts[index].y = spec.SOLE_Y_CM


# ---------------------------------------------------------------------------
# Weights -- phase 1 placeholder, replaced in phase 3
# ---------------------------------------------------------------------------

def segment_distance(point, head, tail):
    axis = tail - head
    length_sq = axis.length_squared
    if length_sq < 1e-9:
        return (point - head).length
    t = max(0.0, min(1.0, (point - head).dot(axis) / length_sq))
    return (point - (head + axis * t)).length


# ---------------------------------------------------------------------------
# Clothing: offset shells of the body's own rings
# ---------------------------------------------------------------------------

def offset_rings(body, shell, rings, distance, region, slot, quilt=0.0,
                 quilt_skip=frozenset()):
    """Duplicate `rings` pushed out along the TRUE surface normal.

    The normal is built from the loft itself -- the in-ring direction crossed
    with the ring-to-ring direction -- and then flipped to agree with the
    radial direction. Two things make this the right construction:

      * A purely radial offset is horizontal for a horizontal ring, so wherever
        the body tapers steeply (shoulders, the trap-to-collar run, the crown)
        it slides the shell ALONG the surface instead of away from it, and the
        garment interpenetrates the skin. That is exactly what a 0.9 cm tee did
        while a 1.45 cm jacket got away with it.
      * A face-normal average would be unusable here: the QuadMesh's winding is
        not made consistent until recalc_face_normals runs on the Blender mesh,
        so it would point inward for an arbitrary subset of the body. Agreeing
        with the radial direction sidesteps winding entirely.

    Returns (new rings, {shell vertex -> body vertex}).
    """
    new_rings = []
    source = {}
    count = len(rings)
    for r, ring in enumerate(rings):
        width = len(ring.indices)
        lower = rings[max(0, r - 1)]
        upper = rings[min(count - 1, r + 1)]
        indices = []
        for c in range(width):
            body_index = ring.indices[c]
            p = body.verts[body_index]
            radial = p - ring.centre
            tangential = (body.verts[ring.indices[(c + 1) % width]]
                          - body.verts[ring.indices[(c - 1) % width]])
            longitudinal = (body.verts[upper.indices[c]]
                            - body.verts[lower.indices[c]])
            outward = tangential.cross(longitudinal)
            if outward.length < 1e-9:
                outward = radial
            elif outward.dot(radial) < 0.0:
                outward = -outward
            outward = outward.normalized() if outward.length > 1e-9 else UP
            # Quilting: alternate rings sit proud, so the garment reads as
            # stitched horizontal segments rather than as one smooth sleeve.
            # It costs no geometry -- it is the offset that varies, not the
            # ring count.
            #
            # `quilt_skip` holds the rings that form a socket boundary. Letting
            # the quilt run through those makes the boundary alternate in and
            # out by the quilt depth, which distorts the loop enough to twist
            # the bridge -- the build gate caught exactly that, 15 bowtied
            # faces, the first time the puffer was built.
            quilted = quilt if (r % 2 == 1 and r not in quilt_skip) else 0.0
            push = distance + quilted
            index = shell.add_vert(p + outward * push, region)
            source[index] = body_index
            indices.append(index)
        new_rings.append(Ring(indices, ring.centre, ring.frame, region))
    return new_rings, source


def rim(body, shell, shell_ring, body_ring, region, slot):
    """Close a shell's open end back down onto the body ring it came from.

    Without this a sleeve or a hem is an open tube: you see its back faces from
    the inside, and the garment reads as paper rather than cloth.
    """
    indices = []
    source = {}
    for body_index in body_ring.indices:
        index = shell.add_vert(body.verts[body_index], region)
        source[index] = body_index
        indices.append(index)
    inner = Ring(indices, body_ring.centre, body_ring.frame, region)
    shell.bridge(shell_ring, inner, region, slot)
    return source


def inherit_weights(shell, source, body):
    """Copy each shell vertex's weights from the body vertex it was derived from.

    A copy, not a re-solve. Identical weights are what guarantee the shell
    deforms exactly as the surface beneath it, so the offset gap is preserved
    through any pose instead of the garment sinking into the body at a bend.
    """
    for shell_index, body_index in source.items():
        shell.weights[shell_index] = dict(body.weights[body_index])


def _socket_columns():
    n = spec.SIDES_BODY
    k = spec.SOCKET_K_LIMB
    return k, n, (-(k // 2)) % n, (n // 2 - k // 2) % n


def build_top(body, shell, landmarks, style, slot):
    """Torso shell with real armholes, plus sleeves bridged into them.

    The shell mirrors the body's rings one-for-one, so the SAME socket carve
    and the SAME bridge that attach an arm to the torso attach a sleeve to a
    shirt -- no separate garment-fitting code exists or is needed.
    """
    lo, hi = style["torso"]
    rings = landmarks["torso"][lo:hi + 1]
    k, n, left_col, right_col = _socket_columns()
    band = spec.SHOULDER_SOCKET_BAND - lo
    quilt = style.get("quilt", 0.0)
    # A contrast stripe is the SAME surface tagged with the accent slot, not a
    # second mesh -- so it costs nothing and recolours independently.
    band_slots = {b: "accent" for b in style.get("bands", ())}

    shell_rings, source = offset_rings(
        body, shell, rings, style["offset"], "top", slot, quilt=quilt,
        quilt_skip={band, band + 1, band + 2})
    skip = shell.skip_set(band, left_col, k, n) | shell.skip_set(band, right_col, k, n)
    shell.stack(shell_rings, "top", slot, skip=skip, band_slots=band_slots)

    source.update(rim(body, shell, shell_rings[0], rings[0], "top", slot))
    source.update(rim(body, shell, shell_rings[-1], rings[-1], "top", slot))

    sockets = {
        "Left": shell.socket_boundary(shell_rings, band, left_col, k)[0],
        "Right": shell.socket_boundary(shell_rings, band, right_col, k)[0],
    }
    for side in ("Left", "Right"):
        arm_rings = landmarks[side + "Arm"][:style["sleeve"]]
        sleeve, sleeve_source = offset_rings(
            body, shell, arm_rings, style["offset"], "top", slot, quilt=quilt,
            quilt_skip={0})
        source.update(sleeve_source)
        shell.stack(sleeve, "top", slot)

        # Order the armhole by where its vertices sit on the BODY, not where
        # the shell pushed them to.
        #
        # offset_rings moves each vertex along its own surface normal, and at
        # the shoulder those normals splay hard: the torso narrows from rx 19.2
        # at the shoulder ring to 15.4 at the trap, so the normals there tilt
        # steeply upward while the ones a band below still point outward.
        # Sorting the displaced positions by angle scrambled the cycle, and
        # every one of the 8 bridge quads came out bowtied -- which rendered as
        # a hole at the shoulder with an inverted triangle in it.
        #
        # The body's own socket bridge is built from these same vertices and is
        # correct, so reuse its ordering and map back through `source`.
        socket = sockets[side]
        body_at = {index: body.verts[source[index]] for index in socket}
        centre = V((0.0, 0.0, 0.0))
        for point in body_at.values():
            centre += point
        centre /= len(body_at)
        _, u, v = sleeve[0].frame
        ordered = shell.order_loop(socket, centre, u, v, positions=body_at)
        if DEBUG_SOCKET and side == "Left":
            log("socket pairing ({:s}):".format(slot))
            for n, index in enumerate(ordered):
                p = shell.verts[index]
                q = shell.verts[sleeve[0].indices[n]]
                log("   {:d} socket({:6.1f},{:6.1f},{:6.1f}) sleeve({:6.1f},{:6.1f},{:6.1f})"
                    " d={:5.2f} ang={:7.1f}".format(
                        n, p.x, p.y, p.z, q.x, q.y, q.z, (q - p).length,
                        math.degrees(loop_angle(body_at[index], centre, u, v))))
        root = Ring(ordered, centre, sleeve[0].frame, "top")
        shell.bridge(root, sleeve[0], "top", slot,
                     shift=shell.best_shift(root, sleeve[0]))
        source.update(rim(body, shell, sleeve[-1], arm_rings[style["sleeve"] - 1],
                          "top", slot))
    return source


def build_tube_part(body, shell, rings_list, distance, region, slot,
                    cap_first=False, cap_last=False, rim_first=None, rim_last=None):
    """A plain offset tube over one run of rings -- trousers, shoes, hair."""
    shell_rings, source = offset_rings(body, shell, rings_list, distance, region, slot)
    shell.stack(shell_rings, region, slot)
    if cap_first:
        shell.cap_even_ngon(list(reversed(shell_rings[0].indices)), region, slot)
    if cap_last:
        shell.cap_even_ngon(shell_rings[-1].indices, region, slot)
    if rim_first is not None:
        source.update(rim(body, shell, shell_rings[0], rim_first, region, slot))
    if rim_last is not None:
        source.update(rim(body, shell, shell_rings[-1], rim_last, region, slot))
    return source


def build_bottom(body, shell, landmarks, style, slot):
    """Hip tube plus two leg tubes, deliberately overlapping at the crotch.

    Clothing is not required to be manifold, and the alternative -- branching
    the waistband into two legs the way the pelvis branches -- would need the
    seat ring's medial vertices and the 8-gon crotch cap rebuilt at an offset,
    for something no camera ever sees. The leg tubes start above the hip tube's
    lower edge, so the overlap leaves no gap.
    """
    lo, hi = style["torso"]
    hip_rings = landmarks["torso"][lo:hi + 1]
    source = build_tube_part(body, shell, hip_rings, style["offset"], "bottom", slot,
                             cap_first=True, rim_last=hip_rings[-1])
    for side in ("Left", "Right"):
        leg_rings = landmarks[side + "Leg"][:style["leg"]]
        source.update(build_tube_part(
            body, shell, leg_rings, style["offset"], "bottom", slot,
            rim_last=leg_rings[style["leg"] - 1]))
    return source


def build_shoes(body, shell, landmarks, style, slot):
    source = {}
    for side in ("Left", "Right"):
        rings = landmarks[side + "Leg"][len(spec.LEG_STATIONS) - style["ankle"]:] \
            if style["ankle"] else []
        rings = list(rings) + list(landmarks[side + "Foot"][:style["foot"]])
        source.update(build_tube_part(
            body, shell, rings, style["offset"], "shoes", slot,
            cap_last=True, rim_first=rings[0]))
    return source


def build_hair(body, shell, landmarks, style, slot):
    rings = landmarks["head"][style["hair"]:]
    return build_tube_part(body, shell, rings, style["offset"], "hair", slot,
                           cap_last=True, rim_first=rings[0])


def build_part(body, landmarks, name, style):
    """Dispatch one part option into its own QuadMesh."""
    shell = QuadMesh()
    slot = spec.PART_SLOT[name]
    kind = style["kind"]
    if kind == "top":
        source = build_top(body, shell, landmarks, style, slot)
    elif kind == "bottom":
        source = build_bottom(body, shell, landmarks, style, slot)
    elif kind == "shoes":
        source = build_shoes(body, shell, landmarks, style, slot)
    elif kind == "hair":
        source = build_hair(body, shell, landmarks, style, slot)
    else:
        raise SystemExit("unknown part kind '{:s}' for {:s}".format(kind, name))
    return shell, source


def build_accent(body, landmarks, name, style):
    shell = QuadMesh()
    lo, hi = style["torso"]
    rings = landmarks["torso"][lo:hi + 1]
    source = build_tube_part(body, shell, rings, style["offset"], "accent", "accent",
                             rim_first=rings[0], rim_last=rings[-1])
    return shell, source


DEBUG_SOCKET = False

ACCESSORY_DATA = HERE / "citizen_accessories.json"


def build_accessories():
    """Load the harvested head props, if tools/harvest_accessories.py has run.

    Optional by design: the source pack lives outside the repo, so a clone with
    no `citizen_accessories.json` still builds a complete citizen -- it just
    has no hats. Every accessory is bound rigidly to Head, which is what makes
    transplanting from a differently-posed rig valid at all.
    """
    if not ACCESSORY_DATA.exists():
        log("no {:s} -- building without harvested accessories"
            .format(ACCESSORY_DATA.name))
        return {}
    data = json.loads(ACCESSORY_DATA.read_text(encoding="utf-8"))
    out = {}
    for name, entry in data.get("accessories", {}).items():
        mesh = QuadMesh()
        for position in entry["verts"]:
            mesh.add_vert(V(position), "accessory")
        for face, slot in zip(entry["faces"], entry["face_slots"]):
            mesh.add_face(face, "accessory", slot)
        for index in range(len(mesh.verts)):
            mesh.weights[index] = {"Head": 1.0}
        out[name] = mesh
    log("accessories: {:d} loaded from {:s}".format(len(out), ACCESSORY_DATA.name))
    return out


def bone_radius(name):
    """Falloff radius for a bone, matched on the LONGEST suffix.

    Longest wins because the short keys are prefixes of the long ones:
    "LeftForeArm" ends with both "ForeArm" and "Arm", and "LeftUpLeg" with both
    "UpLeg" and "Leg". Shortest-match would give the forearm the upper arm's
    radius and quietly fatten every elbow.
    """
    for key in sorted(spec.BONE_RADII, key=len, reverse=True):
        if name == key or name.endswith(key):
            return spec.BONE_RADII[key]
    raise SystemExit("no BONE_RADII entry matches '{:s}'".format(name))


def compute_weights(mesh, bones):
    """Distance-to-bone-segment falloff, deterministic and gated.

    Chosen over bpy.ops.object.parent_set(type="ARMATURE_AUTO") for two
    reasons. Bone heat fails SILENTLY, which this repo has already been burned
    by (build_police.py's docstring records it dumping detached props at the
    origin). And more decisively, it is solved per object, so clothing shells
    would come out with weights subtly different from the body underneath them
    -- destroying the guarantee that makes the offset-shell design work at all.
    Here the shells copy their source vertex's weights verbatim instead.
    """
    segments = []
    for name in spec.WEIGHT_BONES:
        head, tail = bones[BONE_PREFIX + name]
        segments.append((name, V(head), V(tail), bone_radius(name)))

    fallbacks = []
    extremities = {}
    for side in ("Left", "Right"):
        extremities[side] = (
            V(bones[BONE_PREFIX + side + "Hand"][0]),
            V(bones[BONE_PREFIX + side + "ToeBase"][0]),
        )

    for index, position in enumerate(mesh.verts):
        sign = 1.0 if position.x >= 0.0 else -1.0
        side = "Left" if sign > 0.0 else "Right"
        hand, toe = extremities[side]

        # Mittens and toes do not articulate, and the falloff would otherwise
        # let the forearm drag the fingertips.
        if position.x * sign > hand.x * sign:
            mesh.weights[index] = {side + "Hand": 1.0}
            continue
        if position.z > toe.z and position.y < toe.y + spec.TOE_LOCK_HEIGHT_CM:
            mesh.weights[index] = {side + "ToeBase": 1.0}
            continue

        raw = {}
        for name, head, tail, radius in segments:
            # Side mask: an inner-thigh vertex sits within ~4 cm of BOTH UpLeg
            # segments, so without this the left leg drags the right one along.
            if position.x > spec.SIDE_EPS_CM and name.startswith("Right"):
                continue
            if position.x < -spec.SIDE_EPS_CM and name.startswith("Left"):
                continue
            d = segment_distance(position, head, tail)
            if d >= radius:
                continue
            raw[name] = (1.0 - d / radius) ** spec.FALLOFF_POWER

        if not raw:
            # Nothing in range: fall back to the single nearest bone rather
            # than shipping an unweighted vertex, which collapses to the origin.
            # Counted and reported -- a non-zero count means a hole in
            # BONE_RADII, not a healthy default.
            fallbacks.append(index)
            best = min(segments, key=lambda s: segment_distance(position, s[1], s[2]))
            raw = {best[0]: 1.0}

        top = sorted(raw.items(), key=lambda kv: kv[1], reverse=True)[:spec.MAX_INFLUENCES]
        total = sum(w for _, w in top)
        mesh.weights[index] = {name: w / total for name, w in top}

    if fallbacks:
        log("WARNING: {:d} vertices had no bone in range and fell back to "
            "nearest (check BONE_RADII)".format(len(fallbacks)))


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_faces(mesh, name):
    """Bowtie / degeneracy check for meshes that are NOT closed manifolds.

    Garments legitimately have boundary edges -- a rim band leaves its inner
    ring open -- so they cannot go through validate_topology. But a twisted
    bridge is just as fatal here as on the body, and shows up as a hole with an
    inverted triangle in it rather than as an error.
    """
    bad = []
    for i, face in enumerate(mesh.quads):
        if len(face) < 3 or len(set(face)) != len(face):
            bad.append(i)
            continue
        points = [mesh.verts[v] for v in face]
        normal = None
        for k in range(len(points)):
            a = points[(k + 1) % len(points)] - points[k]
            b = points[(k + 2) % len(points)] - points[(k + 1) % len(points)]
            cross = a.cross(b)
            if cross.length < 1e-9:
                continue
            if normal is None:
                normal = cross.normalized()
            elif cross.normalized().dot(normal) < 0.0:
                bad.append(i)
                break
    # Threshold, not zero. A twisted socket bridge fails every one of its 8
    # quads, so the regression this exists to catch shows up as 8 per shoulder
    # -- 16 on a top. An isolated non-planar quad where a garment's offset
    # bunches at the armpit shows up as 1 and is invisible. Failing at 4 catches
    # the first and tolerates the second, rather than picking zero and having
    # the build cry wolf until someone stops reading it.
    if len(bad) >= spec.MAX_PART_BOWTIES:
        for i in bad[:4]:
            log("    face {:d} at {!r}".format(i, [round(c, 1) for c in mesh.verts[mesh.quads[i][0]]]))
        raise SystemExit(
            "{:s}: {:d} bowtied faces -- a socket bridge is twisted".format(name, len(bad)))
    if bad:
        log("FACE WARN [{:s}]: {:d} bowtied/degenerate faces".format(name, len(bad)))
        for i in bad[:4]:
            face = mesh.quads[i]
            centre = V((0.0, 0.0, 0.0))
            for v in face:
                centre += mesh.verts[v]
            centre /= len(face)
            sides = [(mesh.verts[face[(k + 1) % len(face)]]
                      - mesh.verts[face[k]]).length for k in range(len(face))]
            log("    face {:d} n={:d} at ({:6.1f},{:6.1f},{:6.1f}) edges {:s}".format(
                i, len(face), centre.x, centre.y, centre.z,
                " ".join("%.2f" % s for s in sides)))
    return bad


def describe_verts(mesh, edges):
    """Summarise a set of edges by the regions their vertices were built in.

    Bare vertex indices are useless after compact() remaps them, and chasing
    one back to a ring by hand is how the first iteration of this build was
    debugged. Region names survive remapping and point straight at the culprit.
    """
    regions = {}
    for a, b in edges:
        for i in (a, b):
            name = mesh.vert_region[i]
            regions[name] = regions.get(name, 0) + 1
    return repr(regions)


def validate_topology(mesh):
    """Raise SystemExit on anything that would ship a broken body.

    Every check here catches a specific, seen failure; none is decorative.
    """
    failures = []

    for i, quad in enumerate(mesh.quads):
        if len(quad) != 4:
            failures.append("quad {:d} has {:d} verts".format(i, len(quad)))
        if len(set(quad)) != 4:
            failures.append("quad {:d} repeats a vertex: {!r}".format(i, quad))

    # Edge use. A boundary edge means a socket was carved but never bridged,
    # which reads in-game as a hole in the armpit; >2 means a bridge was
    # emitted twice.
    edge_faces = {}
    for quad in mesh.quads:
        for a, b in zip(quad, quad[1:] + quad[:1]):
            edge_faces[(min(a, b), max(a, b))] = edge_faces.get((min(a, b), max(a, b)), 0) + 1
    boundary = [e for e, n in edge_faces.items() if n == 1]
    nonmanifold = [e for e, n in edge_faces.items() if n > 2]
    if boundary:
        failures.append("{:d} boundary edges (unbridged socket?) in {:s}"
                        .format(len(boundary), describe_verts(mesh, boundary)))
    if nonmanifold:
        failures.append("{:d} non-manifold edges in {:s}"
                        .format(len(nonmanifold), describe_verts(mesh, nonmanifold)))

    # Bowties. Orientation-agnostic on purpose: winding is fixed globally by
    # recalc_face_normals later, so this compares a quad's two triangles
    # against each other, not against a global normal.
    bowties = []
    for i, (a, b, c, d) in enumerate(mesh.quads):
        va, vb, vc, vd = (mesh.verts[x] for x in (a, b, c, d))
        n1 = (vb - va).cross(vd - va)
        n2 = (vc - vb).cross(va - vb)
        if n1.length < 1e-9 or n2.length < 1e-9:
            bowties.append(i)
        elif n1.normalized().dot(n2.normalized()) < 0.0:
            bowties.append(i)
    if bowties:
        regions = {}
        for i in bowties:
            regions[mesh.quad_region[i]] = regions.get(mesh.quad_region[i], 0) + 1
        failures.append("{:d} bowtied/degenerate quads in {!r}, e.g. index {!r}"
                        .format(len(bowties), regions, bowties[:6]))

    used = {i for quad in mesh.quads for i in quad}
    loose = [i for i in range(len(mesh.verts)) if i not in used]
    if loose:
        failures.append("{:d} loose vertices (compact() not run?)".format(len(loose)))

    if failures:
        for line in failures:
            log("TOPOLOGY FAIL: " + line)
        raise SystemExit("topology validation failed")


def validate_weights(mesh, bones, name, require_all_bones=True, check_distance=True):
    """Raise SystemExit rather than ship a rig that deforms wrong.

    Every check corresponds to a failure that is either silent at export time
    or silent at runtime; none of them is decorative.
    """
    failures = []
    radii = {n: bone_radius(n) for n in spec.WEIGHT_BONES}
    weighted = {n: 0 for n in spec.WEIGHT_BONES}

    unweighted = 0
    bad_sum = 0
    over_influence = 0
    too_far = []
    cross_side = []

    for index, weights in enumerate(mesh.weights):
        position = mesh.verts[index]
        if not weights:
            unweighted += 1
            continue
        if abs(sum(weights.values()) - 1.0) > 1e-4:
            bad_sum += 1
        # glTF exports 4 influences. A 5th is dropped SILENTLY, after which the
        # remaining weights no longer sum to 1 and the mesh creeps toward the
        # origin under animation with no error anywhere. Highest-value check here.
        if len(weights) > spec.MAX_INFLUENCES:
            over_influence += 1
        for bone, weight in weights.items():
            weighted[bone] += 1
            head, tail = bones[BONE_PREFIX + bone]
            # Skipped for rigid props: a top hat's crown is legitimately half a
            # metre from the Head bone, and the check exists to catch an arm
            # bound to a leg, not to police prop size.
            if check_distance and segment_distance(
                position, V(head), V(tail)) > spec.MAX_BIND_DISTANCE_CM:
                too_far.append((index, bone))
            if position.x > spec.SIDE_EPS_CM and bone.startswith("Right"):
                cross_side.append((index, bone))
            if position.x < -spec.SIDE_EPS_CM and bone.startswith("Left"):
                cross_side.append((index, bone))

    if unweighted:
        failures.append("{:d} vertices have no weights".format(unweighted))
    if bad_sum:
        failures.append("{:d} vertices do not sum to 1.0".format(bad_sum))
    if over_influence:
        failures.append("{:d} vertices exceed {:d} influences"
                        .format(over_influence, spec.MAX_INFLUENCES))
    if too_far:
        failures.append("{:d} binds beyond {:.0f} cm, e.g. {!r}"
                        .format(len(too_far), spec.MAX_BIND_DISTANCE_CM, too_far[:4]))
    if cross_side:
        failures.append("{:d} cross-side binds, e.g. {!r}"
                        .format(len(cross_side), cross_side[:4]))

    # A required bone with no weights means a limb the retargeted clips drive
    # but nothing follows -- a partially frozen character, and no error. Only
    # the body is held to this; the face detail is legitimately Head-only.
    if require_all_bones:
        starved = [n for n in spec.REQUIRED_CORE_BONES if weighted.get(n, 0) == 0]
        if starved:
            failures.append("required bones with no weighted vertices: {:s}"
                            .format(", ".join(starved)))

    if failures:
        for line in failures:
            log("WEIGHT FAIL [{:s}]: {:s}".format(name, line))
        raise SystemExit("weight validation failed")

    log("weights [{:s}]: {:d} verts, max {:d} influences, {:d} bones used"
        .format(name, len(mesh.weights),
                max(len(w) for w in mesh.weights),
                sum(1 for n in weighted if weighted[n] > 0)))
    return weighted


def deform_test(obj, armature):
    """Pose the rig and assert the mesh does not explode.

    The rest pose cannot reveal a weighting bug -- this is the cheap in-Blender
    half of what `citizen_capture.gd --shots posed` shows visually.
    """
    rest_mesh = obj.data
    rest = [v.co.copy() for v in rest_mesh.vertices]
    rest_lo = mathutils.Vector((min(p[i] for p in rest) for i in range(3)))
    rest_hi = mathutils.Vector((max(p[i] for p in rest) for i in range(3)))
    rest_size = rest_hi - rest_lo

    edges = [(e.vertices[0], e.vertices[1]) for e in rest_mesh.edges]
    rest_lengths = [(rest[a] - rest[b]).length for a, b in edges]

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    for bone_name, axis, degrees in spec.DEFORM_POSES:
        pose_bone = armature.pose.bones.get(BONE_PREFIX + bone_name)
        if pose_bone is None:
            continue
        pose_bone.rotation_mode = "XYZ"
        setattr(pose_bone.rotation_euler, axis.lower(), math.radians(degrees))
    bpy.ops.object.mode_set(mode="OBJECT")

    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    evaluated = obj.evaluated_get(depsgraph)
    posed = evaluated.to_mesh()
    coords = [v.co.copy() for v in posed.vertices]

    failures = []
    if any(any(math.isnan(c) for c in p) for p in coords):
        failures.append("NaN vertex after posing")
    else:
        lo = mathutils.Vector((min(p[i] for p in coords) for i in range(3)))
        hi = mathutils.Vector((max(p[i] for p in coords) for i in range(3)))
        # Compared as a DIAGONAL, not per axis. The rest pose is only ~0.25 m
        # deep, so bending a knee 90 degrees backward legitimately triples the
        # depth extent -- a per-axis test fires on a correct rig. The diagonal
        # is insensitive to a limb changing which axis it occupies and still
        # catches what this is for: a vertex bound to a distant bone flying off.
        growth = (hi - lo).length / max(rest_size.length, 1e-6)
        if growth > spec.MAX_DEFORM_GROWTH:
            failures.append("posed bounding diagonal grew {:.2f}x".format(growth))
        worst = 0.0
        for (a, b), rest_length in zip(edges, rest_lengths):
            if rest_length < 1e-6:
                continue
            worst = max(worst, (coords[a] - coords[b]).length / rest_length)
        if worst > spec.MAX_EDGE_STRETCH:
            failures.append("an edge stretched {:.2f}x (limit {:.1f})"
                            .format(worst, spec.MAX_EDGE_STRETCH))
        else:
            log("deform test: worst edge stretch {:.2f}x, bounds {:.2f}x, "
                "over {:d} poses".format(worst, growth, len(spec.DEFORM_POSES)))

    evaluated.to_mesh_clear()

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    bpy.ops.object.mode_set(mode="OBJECT")

    if failures:
        for line in failures:
            log("DEFORM FAIL: " + line)
        raise SystemExit("deform validation failed")


def report_counts(mesh):
    counts = mesh.counts()
    total = sum(counts.values())
    log("quads by region:")
    for region in sorted(counts):
        ceiling = spec.REGION_BUDGET.get(region)
        flag = ""
        if ceiling is not None and counts[region] > ceiling:
            flag = "  OVER (budget {:d})".format(ceiling)
        log("    {:<10s} {:5d}{:s}".format(region, counts[region], flag))
    log("    {:<10s} {:5d} quads / {:d} tris".format("TOTAL", total, total * 2))
    return total


# ---------------------------------------------------------------------------
# Scene assembly
# ---------------------------------------------------------------------------

_MATERIALS = {}


def make_material(slot):
    """One Blender material per slot, shared by every mesh that uses it.

    Must be cached. `bpy.data.materials.new("Citizen_top")` does not fail on a
    duplicate name -- it silently returns "Citizen_top.001", ".002", ".003" --
    and those names survive into the GLB. The runtime resolves a slot by
    stripping the "Citizen_" prefix off the material name, so a suffixed
    material resolved to "top.003", matched no slot, and was skipped: only
    whichever garment happened to win the unsuffixed name was ever tintable.
    Every tee and polo rendered its authored default and no colour swatch
    touched them.
    """
    if slot in _MATERIALS:
        return _MATERIALS[slot]
    material = bpy.data.materials.new("Citizen_" + slot)
    _MATERIALS[slot] = material
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    red, green, blue = spec.PALETTES[slot][0]
    bsdf.inputs["Base Color"].default_value = (red, green, blue, 1.0)
    bsdf.inputs["Roughness"].default_value = spec.BASE_ROUGHNESS
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = spec.BASE_SPECULAR
    return material


def shade(data, recalc_normals):
    """Smooth-shade the mesh and mark creases sharp by dihedral angle.

    Sharpness is written into MESH DATA (`face.smooth` / `edge.smooth`, which
    are the `sharp_face` / `sharp_edge` attributes Blender 4.1+ derives corner
    normals from), never into an EdgeSplit modifier. The export runs with
    `export_apply=False` -- as build_police.py's does, and as it must with an
    armature bound -- and modifiers are NOT evaluated on that path, so a
    modifier's creases would silently never reach the GLB and the citizen would
    export fully smooth. The glTF exporter reads corner_normals and splits the
    vertices at the sharp edges by itself.

    Returns the number of edges marked, for the build report.
    """
    limit = math.radians(spec.SMOOTH_ANGLE_DEG)
    bm = bmesh.new()
    bm.from_mesh(data)
    if recalc_normals:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for face in bm.faces:
        face.smooth = True
    marked = 0
    for edge in bm.edges:
        if len(edge.link_faces) != 2:
            edge.smooth = False        # an open border is always a crease
            marked += 1
            continue
        a, b = edge.link_faces
        if a.normal.angle(b.normal) > limit:
            edge.smooth = False
            marked += 1
    bm.to_mesh(data)
    bm.free()
    return marked


def to_object(mesh, name, armature, to_world, recalc_normals=True):
    """Build one Blender object from the accumulated quads and bind it.

    `recalc_normals` must be False for anything that is not a closed volume:
    the operator resolves winding by deciding what is "outside", which is
    meaningless for loose faces.
    """
    # Ordered by spec.SLOTS rather than by first use, so a material's surface
    # index is stable across rebuilds even if the geometry order changes.
    present = set(mesh.quad_slot)
    slots = [s for s in spec.SLOTS if s in present]
    verts = [tuple(to_world @ v) for v in mesh.verts]
    faces = [list(q) for q in mesh.quads]

    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.validate(verbose=False)

    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)

    slot_index = {}
    for slot in slots:
        slot_index[slot] = len(data.materials)
        data.materials.append(make_material(slot))
    for polygon, slot in zip(data.polygons, mesh.quad_slot):
        polygon.material_index = slot_index[slot]

    sharp = shade(data, recalc_normals)

    groups = {}
    for index, weights in enumerate(mesh.weights):
        for bone, weight in weights.items():
            groups.setdefault(bone, []).append((index, weight))
    for bone, entries in groups.items():
        group = obj.vertex_groups.new(name=BONE_PREFIX + bone)
        for index, weight in entries:
            group.add([index], weight, "REPLACE")

    obj.parent = armature
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    log("{:s}: {:d} quads, {:d} slots {!r}, {:d} sharp edges"
        .format(name, len(mesh.quads), len(slots), slots, sharp))
    return obj


def measure_height(obj):
    lo = min(v.co.z for v in obj.data.vertices)
    hi = max(v.co.z for v in obj.data.vertices)
    return lo, hi, hi - lo


def clamp_sole(shell):
    """Flatten a shoe's underside to the same plane as the bare sole.

    A shell offset radially from the foot pushes the sole to about -1 cm, which
    would drop the whole character through the floor: cblock_player.gd grounds
    the rig from its mesh bounds, so a shoe below y=0 moves the feet, not just
    the shoe.
    """
    for index, position in enumerate(shell.verts):
        if position.y < spec.SOLE_Y_CM:
            shell.verts[index].y = spec.SOLE_Y_CM


def validate_heights(parts, crown_y):
    """Keep every part inside the Y envelope _scale_and_align_visual assumes.

    cblock_player.gd measures the union AABB of every MeshInstance3D whether or
    not it is visible, so a tall hairstyle silently shortens every citizen
    wearing any other one. The runtime gets a visibility guard as well; this is
    the build-time half, and it is the half that cannot regress silently.
    """
    failures = []
    for name, shell in parts.items():
        if not shell.verts:
            continue
        top = max(p.y for p in shell.verts)
        bottom = min(p.y for p in shell.verts)
        if name.startswith("Hair_") and top > crown_y + spec.HAIR_HEADROOM_CM:
            failures.append("{:s} reaches y={:.2f}, crown+{:.1f} is {:.2f}"
                            .format(name, top, spec.HAIR_HEADROOM_CM,
                                    crown_y + spec.HAIR_HEADROOM_CM))
        if name.startswith("Shoes_") and abs(bottom - spec.SOLE_Y_CM) > 0.2:
            failures.append("{:s} sole at y={:.2f}, expected {:.2f}"
                            .format(name, bottom, spec.SOLE_Y_CM))
    if failures:
        for line in failures:
            log("HEIGHT FAIL: " + line)
        raise SystemExit("height validation failed")


def report_budget(quads):
    """Report and gate the quad budget.

    Two-sided on purpose. A ceiling alone is how you quietly ship a 1,300-quad
    character when 2,000 were asked for, so the build fails below the floor as
    well as above it.
    """
    visible = quads["body"] + quads["face"]
    chosen = []
    for group, options in spec.PARTS.items():
        default = options[0]
        if default not in quads:
            continue
        chosen.append(default)
        visible += quads[default]
        accent = spec.PART_ACCENT.get(default)
        if accent in quads:
            chosen.append(accent)
            visible += quads[accent]

    total = sum(quads.values())
    log("parts:")
    for name in sorted(quads):
        mark = "  <- default" if name in chosen else ""
        log("    {:<20s} {:5d}{:s}".format(name, quads[name], mark))
    log("budget: visible {:d} quads / {:d} tris  (band {:d}..{:d})".format(
        visible, visible * 2,
        spec.QUAD_BUDGET["visible_min"], spec.QUAD_BUDGET["visible_max"]))
    log("        total   {:d} quads / {:d} tris  (max {:d})".format(
        total, total * 2, spec.QUAD_BUDGET["total_max"]))

    if visible < spec.QUAD_BUDGET["visible_min"]:
        raise SystemExit("visible quads {:d} below the floor {:d}".format(
            visible, spec.QUAD_BUDGET["visible_min"]))
    if visible > spec.QUAD_BUDGET["visible_max"]:
        raise SystemExit("visible quads {:d} over the ceiling {:d}".format(
            visible, spec.QUAD_BUDGET["visible_max"]))
    if total > spec.QUAD_BUDGET["total_max"]:
        raise SystemExit("total quads {:d} over {:d}".format(
            total, spec.QUAD_BUDGET["total_max"]))
    return visible


def write_manifest(quads, height_m, built):
    """The Blender <-> GDScript contract.

    Part names are typed once, in citizen_spec.py, and everything downstream is
    generated from it. Renaming a mesh in the builder then turns
    citizen_smoke_test.gd red instead of silently making a hairstyle
    unreachable from the creator UI.
    """
    # Only advertise options that actually made it into the GLB. The harvested
    # accessories are optional, so a clone without citizen_accessories.json
    # must not ship a manifest promising hats it does not have -- the smoke
    # test checks the manifest against the GLB in both directions and would,
    # correctly, fail.
    groups = {}
    for group, options in spec.PARTS.items():
        present = [o for o in options if o.endswith("_None") or o in built]
        if any(not o.endswith("_None") for o in present):
            groups[group] = present

    manifest = {
        "authored_height_m": round(height_m, 4),
        "slots": spec.SLOTS,
        "groups": groups,
        "defaults": {group: options[0] for group, options in groups.items()},
        "part_slot": {k: v for k, v in spec.PART_SLOT.items() if k in built},
        "part_accent": spec.PART_ACCENT,
        "body_meshes": ["CitizenBody", "Face_Detail"],
        "palettes": {slot: [list(c) for c in colours]
                     for slot, colours in spec.PALETTES.items()},
        "quads": quads,
    }
    OUTPUT_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    log("wrote {:s}".format(OUTPUT_MANIFEST.name))


def main():
    armature, idle_action, authoring_to_world, rest = import_rig()

    absent = missing_bones(rest)
    if absent:
        raise SystemExit("rig is missing weight bones: {:s}".format(", ".join(absent)))

    mesh = QuadMesh()
    landmarks = build_body(mesh, rest)
    detail = build_face_detail(rest)

    # Parts are built against the UNCOMPACTED body: they address it through the
    # Rings, whose indices compact() remaps.
    parts = {}
    sources = {}
    for name, style in spec.PART_BUILD.items():
        shell, source = build_part(mesh, landmarks, name, style)
        if style["kind"] == "shoes":
            clamp_sole(shell)
        parts[name] = shell
        sources[name] = source
    for name, style in spec.ACCENT_BUILD.items():
        shell, source = build_accent(mesh, landmarks, name, style)
        parts[name] = shell
        sources[name] = source

    accessories = build_accessories()

    compute_weights(mesh, rest)
    for name, shell in parts.items():
        inherit_weights(shell, sources[name], mesh)

    crown_y = V(rest[BONE_PREFIX + "Head"][0]).y + spec.HEAD_STATIONS[-1][0]
    validate_heights(parts, crown_y)

    validate_weights(mesh, rest, "body")
    validate_weights(detail, rest, "face", require_all_bones=False)
    for name, shell in parts.items():
        validate_weights(shell, rest, name, require_all_bones=False)
        validate_faces(shell, name)
    for name, prop in accessories.items():
        validate_weights(prop, rest, name, require_all_bones=False, check_distance=False)

    dropped = mesh.compact()
    if dropped:
        log("compact: dropped {:d} socket-interior vertices".format(dropped))

    # The body must be a closed manifold; the face detail and the garments are
    # deliberately loose geometry and are not held to that.
    validate_topology(mesh)
    total = report_counts(mesh)

    obj = to_object(mesh, "CitizenBody", armature, authoring_to_world)
    to_object(detail, "Face_Detail", armature, authoring_to_world, recalc_normals=False)
    # Garments DO get recalc_face_normals. `stack()` winds inward for the
    # standard ring layout -- the body only looks right because the operator
    # flips it -- so a shell exported verbatim renders inside-out and
    # backface-culls to nothing, which is why the jacket's torso vanished and
    # left bare skin between its sleeves. A tube or a dome is connected enough
    # for the operator to resolve; only Face_Detail's four isolated quads are
    # not, and those are wound by hand in build_face_detail.
    for name in sorted(parts):
        to_object(parts[name], name, armature, authoring_to_world)
    # Harvested props keep the winding the source pack shipped. recalc is for
    # geometry this script authored and whose winding it therefore knows is
    # inward; running it on someone else's open-shelled glasses frames is a
    # guess, not a correction.
    for name in sorted(accessories):
        to_object(accessories[name], name, armature, authoring_to_world,
                  recalc_normals=False)

    deform_test(obj, armature)
    low, high, height = measure_height(obj)

    quads = {"body": total, "face": len(detail.quads)}
    for name, shell in parts.items():
        quads[name] = len(shell.quads)
    report_budget(quads)
    if accessories:
        worst = {}
        for name, prop in accessories.items():
            worst.setdefault(spec.PART_SLOT.get(name, "accent"), []).append(len(prop.quads))
        log("accessories: {:d} tris across {:d} props, heaviest {:d}".format(
            sum(len(p.quads) for p in accessories.values()), len(accessories),
            max(len(p.quads) for p in accessories.values())))
    log("body: {:d} verts, {:d} quads, height {:.4f} m (sole {:+.4f})"
        .format(len(mesh.verts), total, height, low))

    if idle_action is not None:
        armature.animation_data_create()
        armature.animation_data.action = idle_action
        bpy.context.scene.frame_start = int(idle_action.frame_range[0])
        bpy.context.scene.frame_end = int(idle_action.frame_range[1])

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT_GLB),
        export_format="GLB",
        use_selection=False,
        export_apply=False,
        export_animations=True,
        export_skins=True,
        export_yup=True,
    )
    log("wrote {:s} ({:.0f} KB)".format(OUTPUT_GLB.name, OUTPUT_GLB.stat().st_size / 1024.0))
    write_manifest(quads, height, set(parts) | set(accessories))
    log("DONE")


main()
