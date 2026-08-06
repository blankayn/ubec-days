"""Build the Passinho do Jamal dance loop and export it as FBX + GLB.

    "C:/Program Files/Blender Foundation/Blender 4.2/blender.exe" -b -noaudio -P tools/build_passinho_dance.py

Writes `assets/animations/passinho_dance.fbx` and `.glb`.

Passinho is the favela footwork style out of Rio, and the "do Jamal" variant
that went global on TikTok in 2026 off "Toma Botada" is its brega-funk cousin
from Recife. The thing that makes it read as passinho and not as marching:

  * the feet stay LOW and fast - taps, skims and pivots a few cm off the floor.
    Driving the knees up like a march is the single biggest way to get it wrong.
  * the knees twist in and out (the brega/Charleston pinch-and-splay).
  * the hips drive hard side to side; the weight visibly sits on one leg.
  * the rhythm is syncopated - quick runs of taps broken by a held accent,
    not one identical step per beat.
  * the arms scoop ACROSS the body together, and they are not symmetric.

So the legs are not posed by FK. Both feet are IK targets, which is what lets
the footwork be authored as actual foot placements, and the IK pole vectors are
animated to swing the knees in and out. The step pattern is a table of
eighth-notes rather than a sine, because pure sinusoids read as a metronome.

Authored on the Mixamo skeleton that ships inside `assets/npcs/police.glb`, so
bone names and rest orientations are Mixamo's by construction and
`_retarget_animation` in `police_npc_prop.gd` / `cblock_player.gd` can re-path
it the same way it already re-paths Idle and Walking.

The clip animates `Hips` position as well as rotations. That is deliberate and
safe: `_retarget_animation`'s `freeze_horizontal_root` keeps the Y component
and pins only X/Z, so the pelvis bounce survives retargeting while the lateral
weight shift gets frozen out and the dancer cannot drift.

Armature-space axes (probed from the rest pose):
    +X = character's LEFT      -X = right
    -Y = FORWARD (facing)      +Z = up
"""

import bpy, os
from math import sin, cos, pi, radians, acos, floor
from mathutils import Euler, Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "npcs", "police.glb")
OUT_DIR = os.path.join(ROOT, "assets", "animations")
FBX = os.path.join(OUT_DIR, "passinho_dance.fbx")
GLB = os.path.join(OUT_DIR, "passinho_dance.glb")

FPS = 30
SUB = 7                   # frames per eighth note (~128.6 BPM, the Toma Botada pocket)
NSUB = 16                 # eighth notes in the phrase (2 bars)
LOOP = SUB * NSUB         # 112 frames, 3.73 s
B = "mixamorig1:"

# ---- the step pattern. 'L'/'R' = that foot articulates, 'X' = both planted
# for a held accent. Six quick alternating taps then a two-count hold, with the
# lead foot swapping in the second bar. The hold is the syncopation; without it
# the whole thing collapses back into a march.
ACT = ['L', 'R', 'L', 'R', 'L', 'R', 'X', 'X',
       'R', 'L', 'R', 'L', 'R', 'L', 'X', 'X']
AMP = [1.0, .85, .90, .85, 1.0, .90, 0.0, 0.0,
       1.0, .85, .90, .85, 1.0, .90, 0.0, 0.0]
# +1 taps out to the side, -1 crosses the foot in toward the midline
DIR = [1, 1, -1, -1, 1, 1, 0, 0,
       1, 1, -1, -1, 1, 1, 0, 0]
# pelvis weight shift: -1 sits over the right leg, +1 over the left
WT = [-1, 1, -1, 1, -1, 1, .4, -.4,
      1, -1, 1, -1, 1, -1, -.4, .4]
# knees pinch in / splay out, flipping every beat
TWIST = [1, 1, -1, -1, 1, 1, -1, -1,
         1, 1, -1, -1, 1, 1, -1, -1]
# arms scoop to one side then the other; flips in bar 2 so it is not symmetric
ARMS = [1, 1, -1, -1, 1, 1, -1, -1,
        -1, -1, 1, 1, -1, -1, 1, 1]
# the held accent, where the arms throw
ACC = [0, 0, 0, 0, 0, 0, 1, 1,
       0, 0, 0, 0, 0, 0, 1, 1]

# ---------------------------------------------------------------- setup
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for o in list(bpy.data.objects):          # police.glb ships a stray Icosphere
    if o.type == 'MESH' and o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)

scene = bpy.context.scene
scene.name = "PassinhoDoJamal"            # FBX names the take after the scene
scene.render.fps = FPS
scene.frame_start, scene.frame_end = 0, LOOP

if arm.animation_data:
    arm.animation_data_clear()
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
act = bpy.data.actions.new("PassinhoDoJamal")
arm.animation_data_create()
arm.animation_data.action = act
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'

REST3 = {pb.name: pb.bone.matrix_local.to_3x3() for pb in arm.pose.bones}
HIP_R3_INV = REST3[B + "Hips"].inverted()

LEG = {}
for side in ("Left", "Right"):
    hip = arm.data.bones[B + side + "UpLeg"].head_local
    knee = arm.data.bones[B + side + "Leg"].head_local
    ankle = arm.data.bones[B + side + "Foot"].head_local
    LEG[side] = {
        "L1": (knee - hip).length,
        "L2": (ankle - knee).length,
        # widen the rest stance a touch; passinho sits on a wider base
        "base": Vector((ankle.x * 1.12, ankle.y, ankle.z)),
        "foot3": arm.data.bones[B + side + "Foot"].matrix_local.to_3x3().copy(),
        "toe_off": (arm.data.bones[B + side + "ToeBase"].head_local - ankle).copy(),
    }

ANIM_BONES = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
]


def basis_q(name, rx=0.0, ry=0.0, rz=0.0):
    r3 = REST3[name]
    R = Euler((radians(rx), radians(ry), radians(rz)), 'XYZ').to_matrix()
    return (r3.inverted() @ R @ r3).to_quaternion()


def rot(name, rx=0.0, ry=0.0, rz=0.0):
    arm.pose.bones[name].rotation_quaternion = basis_q(name, rx, ry, rz)


def clamp(v, lo=-1.0, hi=1.0):
    return max(lo, min(hi, v))


def table(arr, sub):
    """Smooth read of an eighth-note table; values sit at subdivision centres."""
    n = len(arr)
    x = sub - 0.5
    i = int(floor(x)) % n
    t = x - floor(x)
    t = t * t * (3.0 - 2.0 * t)
    return arr[i] * (1.0 - t) + arr[(i + 1) % n] * t


def aim(name, direction, head=None):
    """Point a bone's Y axis along `direction` in armature space, keeping roll."""
    pb = arm.pose.bones[B + name]
    if head is None:
        head = pb.head.copy()
    r3 = pb.bone.matrix_local.to_3x3()
    q = r3.col[1].normalized().rotation_difference(direction.normalized())
    M = (q.to_matrix() @ r3).to_4x4()
    M.translation = head
    pb.matrix = M
    pb.location = (0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def leg_ik(side, target, pole):
    """Two-bone solve placing the ankle on `target`, knee pointed along `pole`."""
    g = LEG[side]
    L1, L2 = g["L1"], g["L2"]
    hip = arm.pose.bones[B + side + "UpLeg"].head.copy()
    v = target - hip
    d = min(v.length, (L1 + L2) * 0.995)      # stay off the extension singularity
    vh = v.normalized()
    A = acos(clamp((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d)))
    pp = pole - vh * pole.dot(vh)
    pp = pp.normalized() if pp.length > 1e-5 else Vector((0.0, -1.0, 0.0))
    thigh = vh * cos(A) + pp * sin(A)
    knee = hip + thigh * L1

    for name, direction, head in ((side + "UpLeg", thigh, hip),
                                  (side + "Leg", target - knee, knee)):
        pb = arm.pose.bones[B + name]
        r3 = pb.bone.matrix_local.to_3x3()
        q = r3.col[1].normalized().rotation_difference(direction.normalized())
        M = (q.to_matrix() @ r3).to_4x4()
        M.translation = head
        pb.matrix = M
        bpy.context.view_layer.update()


GROUND = 0.0075                   # rest height of the toe joint


def toe_clearance(side, target, yaw, pitch):
    """Raise the ankle so a pitched foot pivots on the toe instead of through it.

    Pointing the toe swings it well below the ankle, so a tap or a heel-lift
    authored as ankle height alone buries the toe in the floor.
    """
    R = (Matrix.Rotation(radians(yaw), 3, 'Z')
         @ Matrix.Rotation(radians(pitch), 3, 'X'))
    off = R @ LEG[side]["toe_off"]
    target.z = max(target.z, GROUND - off.z)
    return target


def place_foot(side, target, yaw, pitch):
    """Orient the foot in world space: yaw pivots it, pitch points the toe."""
    pb = arm.pose.bones[B + side + "Foot"]
    R = (Matrix.Rotation(radians(yaw), 3, 'Z')
         @ Matrix.Rotation(radians(pitch), 3, 'X'))
    M = (R @ LEG[side]["foot3"]).to_4x4()
    M.translation = target
    pb.matrix = M
    bpy.context.view_layer.update()
    pb.location = (0.0, 0.0, 0.0)
    pb.scale = (1.0, 1.0, 1.0)


def pose(f):
    sub = f / SUB
    i = int(sub) % NSUB
    frac = sub - int(sub)
    arc = sin(pi * frac)                      # 0 -> 1 -> 0 inside one eighth
    bnc = 0.5 - 0.5 * cos(2.0 * pi * f / SUB)  # dip on every eighth
    wt = table(WT, sub)
    tw = table(TWIST, sub)
    aswing = table(ARMS, sub)
    acc = table(ACC, sub)
    pump = sin(2.0 * pi * f / SUB)
    phrase = sin(2.0 * pi * f / LOOP)

    # ---- pelvis: hard lateral weight shift, twist, and a low bounce.
    # The drop is small because passinho lives close to the floor.
    rot(B + "Hips",
        rx=2.5 * bnc,
        ry=-11.0 * wt,                        # hip hikes over the loaded leg
        rz=9.0 * wt + 4.0 * phrase)
    arm.pose.bones[B + "Hips"].location = HIP_R3_INV @ Vector((
        0.045 * wt,                           # the drive, roughly twice a march
        0.010 * bnc,
        -0.030 - 0.028 * bnc - 0.012 * acc,   # sink into the held accent
    ))

    # ---- torso: loose, counter-rotating against the hips
    rot(B + "Spine",  rx=2.0 + 2.0 * bnc, ry=3.0 * wt,  rz=-5.0 * wt)
    rot(B + "Spine1", rx=1.5 + 1.5 * bnc, ry=2.0 * wt,  rz=-5.0 * wt + 7.0 * aswing)
    rot(B + "Spine2", rx=1.5 + 1.5 * bnc, ry=-2.0 * wt, rz=-3.0 * wt + 5.0 * aswing)
    rot(B + "Neck", rx=-3.0 - 3.0 * bnc, rz=3.0 * wt)
    rot(B + "Head", rx=-5.0 * cos(2.0 * pi * f / SUB) - 2.0,
        ry=4.0 * aswing, rz=-5.0 * aswing + 4.0 * phrase)

    # ---- arms: scooping across the body together, plus a throw on the accent.
    # Aimed along explicit directions rather than Euler angles - once an arm
    # leaves the T-pose the Euler axes stop meaning anything intuitive, and
    # bending the elbow about them flings the arm out sideways like a wave.
    # `lat` is added to both arms in world X, so the pair swings the same way
    # instead of mirroring, which is what makes it a scoop.
    lat = 0.34 * aswing
    rot(B + "LeftShoulder", ry=-6.0 * pump - 5.0 * acc, rz=-4.0 - 3.0 * pump)
    rot(B + "RightShoulder", ry=6.0 * pump + 5.0 * acc, rz=4.0 + 3.0 * pump)
    bpy.context.view_layer.update()

    for side in ("Left", "Right"):
        out = 1.0 if side == "Left" else -1.0
        # the `out *` terms on aswing make the arms alternate rather than
        # mirror - one forearm rides up while the other drops, which is the
        # scoop. Mirrored arms at chest height just read as a boxing guard.
        upper = Vector((out * 0.26 + lat,
                        -0.20 - 0.12 * pump - 0.10 * acc,
                        -0.94 + 0.08 * pump + 0.24 * acc - out * 0.10 * aswing))
        fore = Vector((out * -0.25 + lat * 0.8,
                       -0.92 + 0.14 * pump,
                       0.02 + 0.20 * pump + 0.34 * acc + out * 0.30 * aswing))
        aim(side + "Arm", upper)
        aim(side + "ForeArm", fore)
        rot(B + side + "Hand", rz=(-14.0 if side == "Left" else 14.0) * pump)

    bpy.context.view_layer.update()           # pelvis final; hips are placed

    # ---- feet: low taps and pivots, never a knee lift
    for side in ("Left", "Right"):
        g = LEG[side]
        out = 1.0 if side == "Left" else -1.0   # +X is the character's left
        active = ACT[i] == side[0]
        a = AMP[i] * arc if active else 0.0
        d = DIR[i]

        target = g["base"].copy()
        target.x += out * 0.075 * d * a         # tap out, or cross in
        target.y += -0.030 * a
        target.z += 0.050 * a                   # barely leaves the floor

        yaw = out * 16.0 * d * a
        # keep the tap's toe-point shallow enough that the ankle lift actually
        # clears the ground - at 26 deg the clearance clamp ate the whole tap
        # and glued every toe to the floor. The accent stays steep on purpose:
        # there the foot should pivot up onto the ball, toe planted.
        pitch = 18.0 * a + 24.0 * acc
        target = toe_clearance(side, target, yaw, pitch)

        # knee pinches in / splays out; that twist is the brega signature
        pole = Vector((out * (0.55 * tw + 0.25 * d * a), -1.0, 0.0))
        leg_ik(side, target, pole)
        place_foot(side, target, yaw, pitch)
        rot(B + side + "ToeBase", rx=-10.0 * a - 8.0 * acc)


# ---------------------------------------------------------------- bake
def key(frame):
    for n in ANIM_BONES:
        pb = arm.pose.bones[B + n]
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if n == "Hips":
            pb.keyframe_insert("location", frame=frame)


for f in range(0, LOOP):
    scene.frame_set(f)
    pose(f)
    key(f)
scene.frame_set(LOOP)                         # closing frame == frame 0
pose(0)
key(LOOP)

for fc in act.fcurves:
    for kp in fc.keyframe_points:
        kp.interpolation = 'BEZIER'
        kp.handle_left_type = kp.handle_right_type = 'AUTO_CLAMPED'
act.use_frame_range = True
act.frame_start, act.frame_end = 0, LOOP
act.use_cyclic = True

# ---------------------------------------------------------------- verify
print("###VERIFY###")
st = {k: [] for k in ("toe_min", "hip_z", "hip_x", "foot_lift", "hand_x")}
for f in range(0, LOOP + 1):
    scene.frame_set(f)
    bpy.context.view_layer.update()
    g = lambda n: arm.matrix_world @ arm.pose.bones[B + n].head
    st["toe_min"].append(min(g("LeftToeBase").z, g("RightToeBase").z))
    st["foot_lift"].append(max(g("LeftFoot").z, g("RightFoot").z) - 0.0987)
    st["hip_z"].append(g("Hips").z)
    st["hip_x"].append(g("Hips").x)
    st["hand_x"].append(g("LeftHand").x)
for k, v in st.items():
    print(" %-10s min=%.4f max=%.4f range=%.4f" % (k, min(v), max(v), max(v) - min(v)))
print("###ENDVERIFY###")

# ---------------------------------------------------------------- export
os.makedirs(OUT_DIR, exist_ok=True)
scene.frame_set(0)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = arm

bpy.ops.export_scene.fbx(
    filepath=FBX, use_selection=False, object_types={'ARMATURE', 'MESH'},
    add_leaf_bones=False, primary_bone_axis='Y', secondary_bone_axis='X',
    bake_anim=True, bake_anim_use_all_bones=True, bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=False, bake_anim_force_startend_keying=True,
    bake_anim_step=1.0, bake_anim_simplify_factor=0.0, mesh_smooth_type='FACE',
    path_mode='COPY', embed_textures=True, apply_unit_scale=True, global_scale=1.0,
)
bpy.ops.export_scene.gltf(
    filepath=GLB, export_format='GLB', export_animations=True,
    export_frame_range=True, export_bake_animation=True,
    export_anim_slide_to_zero=False, export_apply=False,
)
print("###DONE### fbx=%d glb=%d" % (os.path.getsize(FBX), os.path.getsize(GLB)))
