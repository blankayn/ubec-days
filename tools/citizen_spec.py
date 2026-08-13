"""Constants for the customizable citizen. Pure data -- deliberately no `bpy`.

`build_citizen.py` imports this, and it also writes the runtime half of it out to
`assets/characters/citizen/citizen_manifest.json` so `scripts/citizen_appearance.gd`
never has to repeat a part name. That is the whole reason this file is separate:
the highest-probability silent failure in this feature is renaming a mesh in the
build script and having GDScript quietly stop finding it, so the names are typed
once, here, and everything downstream is generated.

Being `bpy`-free also means the budget and palette tables can be imported and
checked by a plain `python` without launching Blender.

AUTHORING SPACE (inherited from tools/build_police.py, do not change):
    centimetres, +Y up, +Z the way the citizen faces, +X is the citizen's LEFT.
That is the space the Mixamo armature arrives in, and every dimension below is
measured in it.
"""

# ---------------------------------------------------------------------------
# Topology
# ---------------------------------------------------------------------------

# The socket rule that makes continuous topology work at all:
#
#   delete a k x k patch of quads from a quad grid
#   -> the hole boundary is exactly 4k vertices
#   -> bridge it to a 4k-sided limb ring.
#
# So the side counts are not free parameters. SIDES_LIMB must be 4 * 2 for a
# 2x2 shoulder/hip socket, and SIDES_THUMB must be 4 * 1 for a 1x1 palm socket.
# Changing one without the other opens a hole in the armpit.
SIDES_BODY = 16
SIDES_LIMB = 8
SIDES_THUMB = 4

SOCKET_K_LIMB = 2       # 2x2 quads -> 8 boundary verts -> SIDES_LIMB
SOCKET_K_THUMB = 1      # 1x1 quad  -> 4 boundary verts -> SIDES_THUMB

# ---------------------------------------------------------------------------
# Proportions, in centimetres in the authoring space
# ---------------------------------------------------------------------------

TARGET_HEIGHT_CM = 178.0

# --- Torso -----------------------------------------------------------------
# (name, (anchor bone, dy), rx, rz, dz). The Y of every band comes from a bone
# rest position, never an invented coordinate, so the whole body rescales with
# the rig instead of drifting off it. Only the cross-section radii and the
# forward lean (dz) are authored here: rx is half-width (along X), rz is
# half-depth (along Z).
# Radii are real anthropometry for a 178 cm frame, not eyeballed: an elliptical
# ring of (rx, rz) has perimeter ~= pi*sqrt(2*(rx^2+rz^2)), so chest 96 cm ->
# (17.8, 11.1), waist 82 -> (15.2, 9.8), hips 98 -> (17.6, 11.4), biacromial
# 40 -> shoulder rx 19.2. Getting these wrong is not cosmetic: the seat ring's
# width sets the size of the hole the thigh bridges into, and a limb wider than
# its hole flares into spikes at the joint.
TORSO_STATIONS = [
    ("seat",       ("Hips",   -7.5), 16.8, 11.2,  0.3),
    ("hem",        ("Hips",   -3.0), 17.4, 11.5,  0.2),
    ("hip",        ("Hips",    2.0), 17.6, 11.4,  0.0),
    ("lowwaist",   ("Hips",    7.0), 16.4, 10.4, -0.6),
    ("waist",      ("Spine",   1.0), 15.2,  9.8, -1.3),
    ("navel",      ("Spine",   7.0), 15.0,  9.8, -1.8),
    ("rib",        ("Spine1",  0.0), 15.8, 10.2, -2.6),
    ("underchest", ("Spine1",  6.5), 16.9, 10.8, -3.1),
    ("chest",      ("Spine1", 13.0), 17.8, 11.1, -3.7),
    ("armpit",     ("Spine2",  4.5), 18.4, 10.9, -4.3),
    ("shoulder",   ("Spine2",  9.5), 19.2, 10.4, -4.9),
    ("trap",       ("Spine2", 14.0), 15.4,  9.4, -5.4),
    ("collar",     ("Neck",    0.0), 10.2,  7.8, -5.8),
]

# The arm socket spans bands [n, n+SOCKET_K_LIMB), i.e. rings armpit / shoulder
# / trap. The band index is not a style choice: LeftArm's rest head sits at
# y=143.56, and the "shoulder" ring is placed at Spine2+9.5 to land on exactly
# that. Centre the socket anywhere else and the bridge from the torso to the
# first arm ring runs vertically instead of outward, which collapses the
# transported frame and bowties the shoulder.
SHOULDER_SOCKET_BAND = 9

# Seat ring: the bottom of the torso, where the two legs branch off.
CROTCH_INSET_CM = 2.4       # how far off the centreline the medial verts sit
CROTCH_DROP_CM = 2.0        # how far below the seat ring the crotch dips

# --- Neck and head ---------------------------------------------------------
# (dy, rx, rz, dz), relative to the Neck / Head bone rest head.
NECK_STATIONS = [
    (1.6, 7.6, 7.0, 0.5),
    (3.2, 6.7, 6.3, 1.1),
]

# Crown lands at Head(155.36) + 21.0 = 176.36, which is HeadTop_End's rest head
# to the centimetre. Derived from the rig, not eyeballed -- this is what keeps
# _scale_and_align_visual's scale factor at ~1.0.
# Jaw at Head-1.4 = 153.96 and crown at Head+21.0 = 176.36 makes the head 22.4
# cm, i.e. 7.9 heads to the full 176.4. The first pass ran the jaw 6 cm higher
# and came out 8.4 heads tall, which is why it read as a mannequin: the head
# was simply too small for the body.
HEAD_STATIONS = [
    (-1.4, 5.9, 6.3, -0.9),     # 0  neck join, under the jaw
    (0.8,  6.8, 7.6, -0.2),     # 1  jaw angle
    (3.0,  7.4, 8.4,  0.4),     # 2  chin
    (5.3,  7.7, 8.9,  0.7),     # 3  mouth
    (7.6,  7.9, 9.1,  0.7),     # 4  nose base
    (9.9,  8.0, 9.2,  0.6),     # 5  eye line
    (12.1, 8.0, 9.1,  0.4),     # 6  brow
    (14.2, 7.9, 8.8,  0.1),     # 7  forehead
    (16.1, 7.6, 8.4, -0.2),     # 8  upper forehead
    (17.8, 7.1, 7.8, -0.5),     # 9
    (19.2, 6.1, 6.6, -0.8),     # 10
    (20.3, 4.6, 5.0, -1.0),     # 11
    (21.0, 2.6, 2.9, -1.2),     # 12 capped from here
]

# Which HEAD_STATIONS index each relief feature pushes. Indices, not names, so
# the relief moves with the band table if it is retuned.
FACE_CHIN_BAND = 2
FACE_NOSE_BAND = 4

# Face relief, limited to the nose and chin -- the two features that are read
# as SILHOUETTE in profile, where a pushed vertex genuinely works. Eyes and
# brows are read as VALUE head-on, which relief cannot supply at any density,
# so they are the detail mesh's job instead (see below).
NOSE_PUSH_CM = 3.0
CHIN_PUSH_CM = 1.0

# Eyes and brows are a SEPARATE mesh, not relief pushed into the head.
#
# Relief cannot make an eye. A recess with no dark value in it reads as damage,
# and the nose proves the wider point: pushed along +Z it is invisible head-on
# and only shows in profile. build_police.py reached the same conclusion and
# inset flat dark boxes. Keeping them off the body also keeps the body a closed
# manifold, which validate_topology's boundary-edge check depends on.
# Placed by ANGLE on the head ellipse and by FRACTIONAL station height, not by
# ring column. Snapping to the 16-column grid puts the nearest usable column 34
# degrees off the facial midline -- eyes out at the temples -- because the only
# columns closer than that contain the nose vertex, which is pushed 3 cm proud.
# Decoupling costs nothing: the patch still lands exactly on the skull because
# it is evaluated from the same HEAD_STATIONS ellipse the skull is built from.
EYE_ANGLE_DEG = 20.0        # off the facial midline
EYE_HALF_DEG = 11.0
EYE_STATION_LO = 4.15
EYE_STATION_HI = 5.05
BROW_HALF_DEG = 13.0
BROW_STATION_LO = 5.90
BROW_STATION_HI = 6.35
FACE_PATCH_PUSH_CM = 0.22
FACE_PATCH_SEGMENTS = 3     # strip segments across the patch; see build_citizen.patch

# --- Arms ------------------------------------------------------------------
# (segment, t, rx, rz). "upper" lerps LeftArm -> LeftForeArm, "fore" lerps
# LeftForeArm -> LeftHand. In the transported limb frame u is up and v is
# forward, so rx is vertical thickness and rz is front-to-back width -- which
# is why the forearm flattens into the wrist rather than staying round.
# The tight 0.76/0.88/0.97 + 0.06 cluster is the elbow: three loops either side
# of the joint are what let the weight falloff spread a 90-degree bend instead
# of crimping it like a drinking straw.
# The shoulder socket hole measures ~9.5 cm (Y, armpit ring to trap ring) by
# ~8.1 cm (Z), i.e. radius ~4.8 x 4.1. The first arm ring has to be close to
# that or the bridge flares: the first version of this table opened at 8.6 --
# an upper arm twice the width of the hole it came out of -- and put a pair of
# grey spikes on both shoulders. Upper arm 32 cm circumference -> radius ~5.1.
# The deltoid mass belongs to the TORSO's shoulder ring, not to the arm.
ARM_STATIONS = [
    ("upper", 0.08, 5.3, 4.8),
    ("upper", 0.20, 5.1, 4.7),
    ("upper", 0.34, 4.9, 4.6),
    ("upper", 0.48, 4.7, 4.4),
    ("upper", 0.62, 4.5, 4.3),
    ("upper", 0.76, 4.4, 4.2),
    ("upper", 0.88, 4.3, 4.1),
    ("upper", 0.97, 4.3, 4.1),
    ("fore",  0.06, 4.3, 4.2),
    ("fore",  0.22, 4.2, 4.3),
    ("fore",  0.42, 3.9, 4.2),
    ("fore",  0.64, 3.4, 4.0),
    ("fore",  0.85, 2.8, 3.7),
]

# How far INBOARD of the shoulder / hip joint the limb path is seeded.
#
# transport_frames takes its first tangent from points[0] -> points[1]. Seed
# that with the socket centroid and you get a tangent pointing UP the torso
# rather than out along the limb, the seed `up` collapses to zero length, and
# the frame -- and therefore the whole ring correspondence -- is arbitrary.
# Seeding from a point on the limb's own axis makes the first tangent the limb
# axis by construction. The socket centroid is still where the bridge starts;
# it is just no longer what defines the frame.
ARM_ROOT_INSET_CM = 6.0
LEG_ROOT_INSET_CM = 6.0

# (t, rx, rz) along HAND_LENGTH_CM from the Hand bone head. Mixamo's T-pose has
# the palms facing DOWN, so the hand is thin vertically (rx) and wide
# front-to-back (rz). A mitten with a thumb, as in the reference.
HAND_LENGTH_CM = 18.0
HAND_STATIONS = [
    (0.10, 2.5, 4.4),
    (0.28, 2.4, 5.0),
    (0.46, 2.3, 5.2),
    (0.62, 2.2, 5.0),
    (0.78, 2.0, 4.4),
    (0.90, 1.7, 3.4),
    (0.98, 1.3, 2.2),
]

# The thumb hangs off a 1x1 socket (4 boundary verts -> SIDES_THUMB) carved
# from the palm. Its column is found at build time as the palm vertex furthest
# forward in WORLD +Z, which resolves correctly for both hands without a
# per-side index table -- the right arm's transported frame is mirrored.
THUMB_SOCKET_BAND = 0       # base of the palm, not mid-palm
THUMB_LENGTH_CM = 7.5
THUMB_STATIONS = [
    (0.30, 2.3, 2.1),
    (0.65, 2.0, 1.8),
    (0.92, 1.4, 1.3),
]

# --- Legs ------------------------------------------------------------------
# (segment, t, rx, rz). "thigh" lerps UpLeg -> Leg(knee), "shin" lerps
# Leg -> Foot(ankle). The leg frame is seeded forward, so here rx is depth
# (front-to-back) and rz is width (side-to-side). Knee cluster at 0.85/0.95 +
# 0.06/0.20 for the same reason as the elbow.
LEG_STATIONS = [
    ("thigh", 0.06, 9.6, 7.6),
    ("thigh", 0.16, 9.2, 7.6),
    ("thigh", 0.28, 8.6, 7.4),
    ("thigh", 0.42, 8.0, 7.0),
    ("thigh", 0.58, 7.4, 6.6),
    ("thigh", 0.72, 6.9, 6.2),
    ("thigh", 0.85, 6.4, 6.0),
    ("thigh", 0.95, 6.2, 5.9),
    ("shin",  0.06, 6.2, 5.9),
    ("shin",  0.20, 6.4, 6.0),
    ("shin",  0.38, 6.0, 5.5),
    ("shin",  0.56, 5.2, 4.8),
    ("shin",  0.76, 4.3, 4.1),
    ("shin",  0.92, 3.8, 3.7),
]

# (dy, dz, rx, rz) relative to the Foot bone head. The path bends from down to
# forward and the transported frame follows it, so the foot comes out as one
# continuous piece with the shin rather than a box stuck on the ankle.
FOOT_STATIONS = [
    (-3.0,  1.5, 4.4, 5.4),
    (-5.6,  5.5, 4.2, 6.0),
    (-7.6, 10.5, 3.8, 6.2),
    (-8.8, 15.5, 3.2, 5.6),
    (-9.4, 20.0, 2.3, 4.4),
]
SOLE_Y_CM = 0.0             # every shoe option must also land here; see validate_heights

# ---------------------------------------------------------------------------
# Clothing
# ---------------------------------------------------------------------------

# Clothing is generated by duplicating the body's own rings pushed out along the
# smoothed vertex normal. That buys exact fit, and -- because each shell vertex
# copies its source body vertex's weights verbatim -- it makes poke-through
# structurally impossible rather than merely unlikely.
SHELL_OFFSET_CM = 0.9
HAIR_OFFSET_CM = 0.6
SHOE_OFFSET_CM = 1.1

# A hair option taller than this would poison _scale_and_align_visual's union
# AABB in cblock_player.gd, which measures every MeshInstance3D whether or not
# it is visible. Capped rather than trusted: see validate_heights.
HAIR_HEADROOM_CM = 1.5

# ---------------------------------------------------------------------------
# Skinning
# ---------------------------------------------------------------------------

# Bones that may receive weight. Wider than REQUIRED_CORE_BONES (which is the
# 20 the locomotion clips drive) because toes and shoulders deform the mesh even
# though no retargeted clip names them.
WEIGHT_BONES = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
]

# The 20 bones cblock_player.gd hard-fails without. Kept here so the build can
# assert them rather than discovering it in-engine.
REQUIRED_CORE_BONES = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot",
    "RightUpLeg", "RightLeg", "RightFoot",
]

# Falloff radius per bone, in cm. A vertex within `r` of the bone's segment gets
# weight (1 - d/r) ** FALLOFF_POWER. Elbow and knee radii are deliberately
# generous so the two bones either side of the joint overlap across the whole
# 3-band joint cluster -- that overlap is the difference between a smooth elbow
# and a crimped drinking straw.
BONE_RADII = {
    "Hips": 26.0,
    "Spine": 24.0,
    "Spine1": 24.0,
    "Spine2": 24.0,
    "Neck": 12.0,
    "Head": 17.0,
    "Shoulder": 13.0,
    "Arm": 13.0,
    "ForeArm": 11.0,
    "Hand": 10.0,
    "UpLeg": 16.0,
    "Leg": 14.0,
    "Foot": 10.0,
    "ToeBase": 8.0,
}

FALLOFF_POWER = 2.0
MAX_INFLUENCES = 4          # glTF exports 4; a 5th is dropped silently
# Must exceed the largest BONE_RADII entry, or the gate fires on binds the
# solver was told to make: the spine bones reach 24 cm precisely because a hip
# vertex 25 cm off the spine axis still belongs to the torso. This is a cap on
# GROSS errors -- an arm vertex bound to a leg bone is 40 cm+ -- not a
# restatement of the falloff radii.
MAX_BIND_DISTANCE_CM = 30.0
SIDE_EPS_CM = 2.0           # |x| beyond this masks out the opposite side's bones
TOE_LOCK_HEIGHT_CM = 6.0    # above the toe bone, past which a vertex is not a toe
MAX_EDGE_STRETCH = 2.5      # deform smoke-test ceiling
# Garments are not closed manifolds so they cannot go through
# validate_topology, but a twisted socket bridge is just as fatal there. See
# build_citizen.validate_faces for why this is 4 and not 0.
MAX_PART_BOWTIES = 4
MAX_DEFORM_GROWTH = 1.6     # deformed AABB vs rest AABB

# Poses the deform smoke-test drives, as (bone, axis, degrees). A weighting bug
# is invisible in the rest pose -- these are the three joints that show it.
DEFORM_POSES = [
    ("LeftForeArm", "Y", 90.0),
    ("LeftLeg", "X", -90.0),
    ("RightArm", "Z", -45.0),
]

SMOOTH_ANGLE_DEG = 40.0

# ---------------------------------------------------------------------------
# Customization
# ---------------------------------------------------------------------------

# One material slot per tintable region. `accent` is the odd one out: it is not
# a body region but a second colour some tops carry (a polo's collar, a
# jacket's trim), so it exists as its own mesh.
SLOTS = ["skin", "eyes", "hair", "top", "bottom", "shoes", "hat", "glasses", "accent"]

# group -> [mesh node names]. The FIRST entry of each group is the default.
# A `*_None` entry means "wear nothing here" and has no mesh in the GLB.
# The accessory groups all default to *_None, so a bare citizen is unchanged
# and the visible-quad budget below still describes the base character.
PARTS = {
    "hair":    ["Hair_Short", "Hair_Long", "Hair_Cap",
                "Hair_Fringe", "Hair_Swept", "Hair_None"],
    "top":     ["Top_Tee", "Top_Polo", "Top_Jacket", "Top_Puffer"],
    "bottom":  ["Bottom_Jeans", "Bottom_Shorts"],
    "shoes":   ["Shoes_Sneaker", "Shoes_Sandal"],
    "hat":     ["Hat_None", "Hat_Cap", "Hat_Beanie"],
    "glasses": ["Glasses_None", "Glasses_Square", "Glasses_Round"],
    "face":    ["Face_None", "Face_Moustache1", "Face_Moustache2"],
    "gear":    ["Gear_None", "Gear_Headphones"],
}

# Which slot tints each part, and which parts drag an accent mesh along.
PART_SLOT = {
    "Hair_Short": "hair", "Hair_Long": "hair", "Hair_Cap": "hair",
    "Hair_Fringe": "hair", "Hair_Swept": "hair",
    "Top_Tee": "top", "Top_Polo": "top", "Top_Jacket": "top", "Top_Puffer": "top",
    "Bottom_Jeans": "bottom", "Bottom_Shorts": "bottom",
    "Shoes_Sneaker": "shoes", "Shoes_Sandal": "shoes",
    "Hat_Cap": "hat", "Hat_Beanie": "hat",
    "Glasses_Square": "glasses", "Glasses_Round": "glasses",
    # A moustache takes the hair slot so it recolours with the hairstyle, the
    # same reasoning the brows already use.
    "Face_Moustache1": "hair", "Face_Moustache2": "hair",
    "Gear_Headphones": "accent",
}

# --- Harvested accessories -------------------------------------------------
#
# Rigid head props lifted from Creative Characters FREE (Superhive, Standard
# Royalty Free) by tools/harvest_accessories.py. Only props weighted 100% to
# `Head` qualify -- see that script for why the rest of the pack cannot be used
# here. `anchor` pins one feature of the accessory to one feature of OUR skull:
# ("min", "brow") means "sit the underside of this hat on the brow line".
PACK_HEAD_WIDTH_CM = 29.9
PACK_HEAD_HEIGHT_CM = 33.0
PACK_HEAD_DEPTH_CM = 29.0
# Their skull is not centred on its own bone: it runs z -13.1..15.9, so the
# centre sits 1.4 cm forward. Accessory Z must be measured against THIS, not
# against the accessory's own centroid -- centring a pair of glasses on the
# skull centre buries them inside the head, which is exactly what the first
# harvest did.
PACK_HEAD_Z_CENTRE_CM = 1.4

# Where the head sits in the authoring space. Mirrors the rig's rest data so
# harvest_accessories.py can place props without launching Blender.
HEAD_ANCHOR_Y = 155.36
HEAD_ANCHOR_Z = -3.93

# `dz` pushes a prop forward off the face. Their skull is nearly as deep as it
# is wide (29.0 vs 29.9); ours is proportionally deeper and narrower (18.5 vs
# 16.0), so a uniform scale that fits the width leaves face-mounted props short
# of our face surface -- glasses and moustaches end up inside the head.
ACCESSORY_IMPORT = {
    "Hat_Cap":         {"src": "Hat_010.glb",        "group": "hat",     "slot": "hat",     "anchor": ("p05", "brow"), "scale": (0.92, 0.55, 0.92)},
    "Hat_Beanie":      {"src": "Hat_057.glb",        "group": "hat",     "slot": "hat",     "anchor": ("p05", "brow"), "scale": (0.92, 0.60, 0.92)},
    "Glasses_Square":  {"src": "Glasses_004.glb",    "group": "glasses", "slot": "glasses", "anchor": ("mid", "eye"), "dz": 2.4},
    "Glasses_Round":   {"src": "Glasses_006.glb",    "group": "glasses", "slot": "glasses", "anchor": ("mid", "eye"), "dz": 2.4},
    "Face_Moustache1": {"src": "Moustache_001.glb",  "group": "face",    "slot": "hair",    "anchor": ("max", "nose"), "dz": 4.6, "dy": -0.8},
    "Face_Moustache2": {"src": "Moustache_002.glb",  "group": "face",    "slot": "hair",    "anchor": ("max", "nose"), "dz": 4.6, "dy": -0.8},
    "Gear_Headphones": {"src": "Headphones_002.glb", "group": "gear",    "slot": "accent",  "anchor": ("mid", "ear"), "dz": -0.5},
    # Hair is rigid too -- Head-only, like the hats -- so it transplants
    # through the same path. It is the most useful thing in the pack for this
    # project: unlike a bunny hood, a hairstyle belongs on a Cebu pedestrian.
    # x/z sit slightly proud of the skull so the cap does not z-fight it, and
    # y is squashed for the same reason the hats are -- our skull is far
    # shallower from brow to crown than theirs.
    # dz on Fringe because its front reached only z=3.4 while our forehead
    # surface is at 4.47 -- the brow poked through and it read as a toupee.
    "Hair_Fringe":     {"src": "Hairstyle_male_010.glb", "group": "hair", "slot": "hair", "anchor": ("max", "crown"), "scale": (1.06, 0.90, 1.06), "dy": 0.4, "dz": 1.8},
    "Hair_Swept":      {"src": "Hairstyle_male_012.glb", "group": "hair", "slot": "hair", "anchor": ("max", "crown"), "scale": (1.04, 0.70, 1.04), "dy": 0.6},
}
PART_ACCENT = {
    "Top_Polo": "Accent_PoloCollar",
    "Top_Jacket": "Accent_JacketTrim",
}

# How each part is generated. Every one is an offset shell of the body's own
# rings, so it fits by construction and -- because each shell vertex copies its
# source body vertex's weights verbatim -- deforms identically to the skin
# underneath it. That is what makes poke-through structurally impossible rather
# than merely unlikely, and it is also why bone-heat weighting is unusable here.
#
#   torso  (lo, hi) inclusive range into TORSO_STATIONS
#   sleeve number of arm rings covered      leg  number of leg rings covered
#   hair   first HEAD_STATIONS ring covered foot number of foot rings covered
#   ankle  extra leg rings a shoe swallows
PART_BUILD = {
    "Top_Tee":       {"kind": "top", "torso": (1, 12), "sleeve": 3,  "offset": 0.90},
    "Top_Polo":      {"kind": "top", "torso": (1, 12), "sleeve": 4,  "offset": 0.95},
    "Top_Jacket":    {"kind": "top", "torso": (0, 12), "sleeve": 12, "offset": 1.45},
    # Puffer: the one garment design worth taking from Creative Characters
    # FREE, rebuilt rather than transplanted. Their mesh is cut for a 63 cm
    # barrel torso and would hang to mid-thigh on our 48.6 cm one; generated as
    # a shell it fits by construction and stays recolourable.
    #   offset 1.9  -- bulkier than the jacket's 1.45, which is the whole point
    #   quilt  0.4  -- alternate rings proud, so it reads as stitched segments
    #   bands  {2,3} -- hip-height contrast stripe on the `accent` slot
    "Top_Puffer":    {"kind": "top", "torso": (0, 12), "sleeve": 12, "offset": 1.50,
                      "quilt": 0.30, "bands": (2, 3)},
    "Bottom_Jeans":  {"kind": "bottom", "torso": (0, 3), "leg": 13, "offset": 1.05},
    "Bottom_Shorts": {"kind": "bottom", "torso": (0, 3), "leg": 5,  "offset": 1.15},
    "Shoes_Sneaker": {"kind": "shoes", "foot": 5, "ankle": 2, "offset": 1.10},
    "Shoes_Sandal":  {"kind": "shoes", "foot": 5, "ankle": 0, "offset": 0.65},
    "Hair_Short":    {"kind": "hair", "hair": 6, "offset": 0.60},
    "Hair_Long":     {"kind": "hair", "hair": 2, "offset": 0.70},
    "Hair_Cap":      {"kind": "hair", "hair": 5, "offset": 1.15},
}

# Accents are a second band on the same shell principle: a polo's collar sits
# on the topmost torso rings, a jacket's trim on the hem.
ACCENT_BUILD = {
    "Accent_PoloCollar": {"torso": (10, 12), "offset": 1.25},
    "Accent_JacketTrim": {"torso": (0, 1), "offset": 1.60},
}

# sRGB triples, the way build_police.py writes base colours. Eight per slot, so
# the runtime material cache is bounded at 8 * len(SLOTS) = 48 materials for the
# entire city no matter how many pedestrians exist.
PALETTES = {
    "skin": [
        (0.898, 0.706, 0.522), (0.839, 0.639, 0.459), (0.757, 0.553, 0.388),
        (0.647, 0.451, 0.310), (0.529, 0.357, 0.243), (0.416, 0.271, 0.184),
        (0.937, 0.769, 0.612), (0.322, 0.204, 0.141),
    ],
    "eyes": [
        (0.086, 0.075, 0.071), (0.161, 0.106, 0.075), (0.243, 0.161, 0.098),
        (0.180, 0.216, 0.204), (0.204, 0.243, 0.278), (0.129, 0.161, 0.184),
        (0.298, 0.239, 0.161), (0.055, 0.055, 0.063),
    ],
    "hair": [
        (0.129, 0.098, 0.086), (0.208, 0.118, 0.086), (0.286, 0.180, 0.110),
        (0.416, 0.278, 0.169), (0.545, 0.427, 0.271), (0.098, 0.086, 0.094),
        (0.620, 0.596, 0.573), (0.361, 0.145, 0.114),
    ],
    "top": [
        (0.827, 0.831, 0.839), (0.278, 0.427, 0.612), (0.573, 0.184, 0.180),
        (0.208, 0.478, 0.396), (0.898, 0.706, 0.278), (0.361, 0.325, 0.435),
        (0.933, 0.529, 0.322), (0.157, 0.180, 0.216),
    ],
    "bottom": [
        (0.216, 0.271, 0.396), (0.157, 0.184, 0.247), (0.353, 0.365, 0.396),
        (0.463, 0.404, 0.318), (0.271, 0.294, 0.271), (0.184, 0.184, 0.196),
        (0.588, 0.545, 0.475), (0.310, 0.239, 0.212),
    ],
    "shoes": [
        (0.098, 0.098, 0.110), (0.878, 0.882, 0.886), (0.361, 0.243, 0.180),
        (0.204, 0.286, 0.416), (0.545, 0.176, 0.161), (0.239, 0.259, 0.243),
        (0.694, 0.671, 0.620), (0.145, 0.290, 0.278),
    ],
    "hat": [
        (0.157, 0.180, 0.216), (0.573, 0.184, 0.180), (0.216, 0.271, 0.396),
        (0.463, 0.404, 0.318), (0.878, 0.882, 0.886), (0.208, 0.478, 0.396),
        (0.898, 0.706, 0.278), (0.098, 0.098, 0.110),
    ],
    "glasses": [
        (0.098, 0.098, 0.110), (0.361, 0.243, 0.180), (0.157, 0.180, 0.216),
        (0.545, 0.176, 0.161), (0.694, 0.671, 0.620), (0.204, 0.286, 0.416),
        (0.878, 0.882, 0.886), (0.286, 0.180, 0.110),
    ],
    "accent": [
        (0.878, 0.882, 0.886), (0.157, 0.180, 0.216), (0.729, 0.176, 0.145),
        (0.878, 0.573, 0.184), (0.208, 0.478, 0.396), (0.278, 0.427, 0.612),
        (0.545, 0.427, 0.271), (0.361, 0.325, 0.435),
    ],
}

# Material surface properties, matching build_police.py:make_material so the
# citizen sits under the same lighting as the officer without retuning.
BASE_ROUGHNESS = 0.85
BASE_SPECULAR = 0.25

# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------

# Two-sided on purpose. A one-sided ceiling is how you quietly ship a
# 1,300-quad character when 2,000 were asked for, so the build fails BELOW the
# floor as well as above the ceiling.
# `visible` is what a citizen actually costs to draw and is the number that was
# asked for. `total` counts every part option in the GLB, which is a VRAM
# figure only: Godot culls a hidden MeshInstance3D before the render list, so
# the unworn hairstyles cost nothing per frame. Kept as a gate anyway so the
# wardrobe cannot grow without someone noticing.
QUAD_BUDGET = {
    "visible_min": 1850,
    "visible_max": 2000,
    "total_max": 4000,
}

# Per-region ceilings, in quads, for the build report. Advisory: the build warns
# on these but only fails on QUAD_BUDGET above.
REGION_BUDGET = {
    "torso": 190,
    "pelvis": 24,
    "neck": 60,
    "head": 310,
    "arm": 270,
    "hand": 200,
    "leg": 300,
    "foot": 120,
    "hair": 110,
    "top": 220,
    "bottom": 200,
    "shoes": 130,
    "accent": 60,
}
