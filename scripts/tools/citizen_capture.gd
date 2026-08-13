# In-engine capture of the customizable citizen.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/citizen_capture.gd -- --shots body
#
# NOT --headless: this renders, and headless writes black PNGs.
#
# Modes (-- --shots <mode>):
#   body   turnaround + face + hand close-ups in clay grey, skeleton forced to
#          its rest pose. This is the topology read.
#   posed  the same body under the retargeted walk at three phases -- the only
#          picture that can show a skin-weighting bug.
#   parts  one frame per clothing option.
#   crowd  six seeded appearances in a row.
#
# The GLB is loaded by ABSOLUTE PATH through GLTFDocument, exactly as
# metro_capture.gd loads its building: no res:// import step, so the
# Blender -> look -> fix loop is two commands and never goes through Godot's
# importer (which, per PROJECT_STATUS.md, can silently no-op).
extends SceneTree

# Preloaded rather than referenced by its class_name: global class names come
# from the import-time script cache, and this tool is run with --script against
# a project that may never have been imported.
const Appearance := preload("res://scripts/citizen_appearance.gd")

const GLB := "assets/characters/citizen/citizen.glb"

## Capture resolution. Larger than the game's 1280x720 on purpose -- see
## _setup_viewport.
const CAPTURE_WIDTH := 1600
const CAPTURE_HEIGHT := 1000
const WALK_FBX := "res://animation mixamo/Walking.fbx"

# Clay grey, in the spirit of Blender's solid view -- topology reads better
# without a skin tone arguing with the shading. Darker than it looks like it
# should be: under the three-point stage a 0.72 clay clips to white and the
# form stops reading, which is the same failure the exposure comment below
# describes. The dressed shots get away with 0.9 albedo because their colours
# vary; a single flat grey has nowhere to hide.
const CLAY := Color(0.50, 0.50, 0.49)

var _frames := 0
var _shot := 0
var _cam: Camera3D
var _shots := []
var _root: Node3D
var _rig: Node3D
var _accum := 0.0
var _count := 0


func _mode() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--shots" and i + 1 < args.size():
			return args[i + 1]
	return "body"


func _load_rig() -> Node3D:
	var path := ProjectSettings.globalize_path("res://" + GLB).replace("\\", "/")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_error("citizen.glb load failed: " + path)
		return null
	return doc.generate_scene(state) as Node3D


func _skeleton_of(rig: Node3D) -> Skeleton3D:
	return rig.find_child("Skeleton3D", true, false) as Skeleton3D


## Forces the T-pose the body is authored in. The GLB carries a baked Idle, and
## whichever frame the exporter left the skeleton on is not necessarily the
## bind pose -- so for a topology read we reset rather than hope.
func _rest_pose(rig: Node3D) -> void:
	var skeleton := _skeleton_of(rig)
	if skeleton == null:
		return
	for i in skeleton.get_bone_count():
		skeleton.reset_bone_pose(i)


## Clay grey everywhere EXCEPT the eyes and brows, which stay dark. Overriding
## those too was the first version, and it hid the face detail completely --
## the whole reason the detail mesh exists is that an eye needs a dark value,
## not a shape.
func _clay(rig: Node3D) -> void:
	var clay := StandardMaterial3D.new()
	clay.albedo_color = CLAY
	clay.roughness = 0.9
	clay.metallic = 0.0
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.11, 0.10)
	dark.roughness = 0.75
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var src := mesh_instance.mesh.surface_get_material(i)
			var slot := "" if src == null else src.resource_name
			var keep_dark := slot == "Citizen_eyes" or slot == "Citizen_hair"
			mesh_instance.set_surface_override_material(i, dark if keep_dark else clay)


func _report(rig: Node3D) -> void:
	var meshes := 0
	var verts := 0
	var tris := 0
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		meshes += 1
		for i in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(i)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			verts += v.size()
			tris += idx.size() / 3
	var skeleton := _skeleton_of(rig)
	print("CITIZEN meshes=", meshes, " verts=", verts, " tris=", tris,
		" bones=", skeleton.get_bone_count() if skeleton != null else -1)
	var shown: PackedStringArray = []
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).visible:
			shown.append(node.name)
	print("CITIZEN visible=", ", ".join(shown))


## One instance, re-yawed per shot. Four figures in one frame was tried first
## and rejected: at 1280x720 a 1.76 m figure that also has to fit a 1.7 m arm
## span leaves each copy too small to judge, and adjacent arms overlap.
func _spawn_one() -> void:
	_rig = _load_rig()
	if _rig == null:
		return
	_rest_pose(_rig)
	_clay(_rig)
	_report(_rig)
	_root.add_child(_rig)


## Renders at 1600x1000 with 4x MSAA rather than the game's 1280x720 at
## scaling_3d 0.75. The stress tool is where frame cost is measured; this one
## exists to be looked at, and at 720p with no MSAA the 16-sided silhouette
## crawls with stair-stepping that reads as modelling error.
func _setup_viewport() -> void:
	var window := get_root()
	window.size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)
	DisplayServer.window_set_size(Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT))
	window.msaa_3d = Viewport.MSAA_4X
	window.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	# The project runs at 0.75 to buy frames on the HD 5500. A still frame has
	# no frame budget to protect.
	window.scaling_3d_scale = 1.0


## A studio: gradient backdrop, ground plane, three-point light.
##
## The old rig lit the citizen against flat grey with nothing underneath, so
## every figure floated and the only shading cue was a single key. Contact
## shadow and a rim are what make a low-poly form read as solid.
func _setup_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.20, 0.22, 0.26)
	sky_material.sky_horizon_color = Color(0.42, 0.45, 0.50)
	sky_material.ground_bottom_color = Color(0.16, 0.17, 0.19)
	sky_material.ground_horizon_color = Color(0.38, 0.40, 0.44)
	sky_material.sun_angle_max = 1.0
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Sky ambient carries direction, so it fills the shadow side without the
	# flat wash a constant ambient colour gives.
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Still deliberately short of 1.0. An earlier rig ran ambient 1.1 + key 1.7
	# + exposure 1.0 and clipped the whole figure to flat white, which hid a
	# pair of spikes on both shoulders for an entire iteration.
	env.tonemap_exposure = 0.92
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_root.add_child(world_env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.30, 0.31, 0.33)
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	ground.position.y = -0.002   # under the soles, so it never z-fights them
	_root.add_child(ground)

	# Key: high and off to his left, raking across the form.
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.97, 0.92)
	key.shadow_enabled = true
	# The subject is 1.8 m tall but the camera's far plane is 200 m, and a
	# directional shadow map stretched over that range quantises to centimetres
	# -- which lands as speckled acne on exactly the brightest surfaces (a white
	# tee) and reads convincingly like the garment interpenetrating the body.
	# Confining the shadow range to the subject is the fix; do not "solve" this
	# by thickening the clothing shells.
	# ORTHOGONAL is a single split, so the whole shadow map covers the subject
	# instead of being divided four ways across a range nothing occupies. At
	# 9 m that is roughly a 2 mm texel -- the difference between clean contact
	# shadow and the moire that showed up on the ground plane and read as a
	# crosshatch texture on the trousers.
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 9.0
	# Normal bias pushes the shadow lookup along the surface normal, so a large
	# value distorts small cast shadows into blobs -- at 1.6 the arm's shadow on
	# the chest became an irregular splotch that read as a texture defect. The
	# single split above is what controls acne; this only has to clean up the
	# remainder.
	key.shadow_bias = 0.05
	key.shadow_normal_bias = 0.7
	key.shadow_blur = 1.2
	_root.add_child(key)
	# Kept fairly frontal on purpose. Raked further round (3.6, 5.0, 4.2) the
	# T-pose arm casts a hard blob across the chest, which on a white tee reads
	# as a stain rather than as shading. Frontal-but-high throws that shadow
	# behind the torso and leaves the rim light to do the separation.
	key.look_at_from_position(Vector3(2.3, 5.6, 5.8), Vector3(0, 0.95, 0), Vector3.UP)

	# Fill: opposite side, cool, no shadow -- opens the dark side without
	# competing with the key.
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.78, 0.85, 1.0)
	_root.add_child(fill)
	fill.look_at_from_position(Vector3(-4.5, 2.2, 3.0), Vector3(0, 1.0, 0), Vector3.UP)

	# Rim: behind and above, warm and bright. This is the one doing the real
	# work -- it separates the silhouette from the backdrop, which is exactly
	# what a flat-coloured low-poly character has no texture detail to do.
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.5
	rim.light_color = Color(1.0, 0.92, 0.82)
	rim.light_specular = 0.0
	_root.add_child(rim)
	rim.look_at_from_position(Vector3(-2.2, 3.2, -4.6), Vector3(0, 1.15, 0), Vector3.UP)


func _initialize() -> void:
	print("CITIZEN_CAPTURE gpu=", RenderingServer.get_video_adapter_name())
	var mode := _mode()

	_root = Node3D.new()
	get_root().add_child(_root)

	_setup_viewport()
	_setup_stage()

	_cam = Camera3D.new()
	_cam.far = 200.0
	_root.add_child(_cam)

	match mode:
		"body":
			_setup_body()
		"posed":
			_setup_posed()
		"parts":
			_setup_parts()
		"crowd":
			_setup_crowd()
		"gear":
			_setup_gear()
		"hair":
			_setup_hair()
		"sleeve":
			_setup_sleeve()
		_:
			push_error("unimplemented --shots mode: " + mode)
			quit(1)
			return

	if _shots.is_empty():
		quit(1)
		return
	_place(0)


func _setup_body() -> void:
	# Godot space after export_yup: feet at y=0, crown at y=1.7636, the citizen
	# faces +Z and his LEFT is +X. Hand rest head is (0.677, 1.436, -0.060), so
	# the close-ups are aimed at real coordinates rather than guessed ones.
	_spawn_one()
	_shots = [
		{"name": "citizen_front", "yaw": 0.0, "pos": Vector3(0, 0.88, 3.05),
			"look": Vector3(0, 0.88, 0), "fov": 38.0},
		{"name": "citizen_threequarter", "yaw": 40.0, "pos": Vector3(0, 0.88, 3.05),
			"look": Vector3(0, 0.88, 0), "fov": 38.0},
		{"name": "citizen_side", "yaw": 90.0, "pos": Vector3(0, 0.88, 3.05),
			"look": Vector3(0, 0.88, 0), "fov": 38.0},
		{"name": "citizen_back", "yaw": 180.0, "pos": Vector3(0, 0.88, 3.05),
			"look": Vector3(0, 0.88, 0), "fov": 38.0},
		{"name": "citizen_face", "yaw": 0.0, "pos": Vector3(0.10, 1.62, 0.62),
			"look": Vector3(0, 1.56, 0), "fov": 34.0},
		{"name": "citizen_shoulder", "yaw": 25.0, "pos": Vector3(0.62, 1.62, 0.86),
			"look": Vector3(0.26, 1.42, 0), "fov": 34.0},
		{"name": "citizen_hand", "yaw": 0.0, "pos": Vector3(0.80, 1.70, 0.52),
			"look": Vector3(0.78, 1.43, -0.02), "fov": 30.0},
		{"name": "citizen_foot", "yaw": 30.0, "pos": Vector3(0.45, 0.34, 0.62),
			"look": Vector3(0.09, 0.05, 0.02), "fov": 34.0},
	]


## Dressed shots. Deliberately routed through Appearance rather than
## re-implementing visibility and tinting here -- if this tool dressed the
## citizen its own way, it would stop being evidence about what the game does.
func _spawn_dressed(appearance: Appearance, position: Vector3, yaw: float) -> void:
	var rig := _load_rig()
	if rig == null:
		return
	_rest_pose(rig)
	appearance.apply(rig)
	rig.position = position
	rig.rotation.y = deg_to_rad(yaw)
	_root.add_child(rig)
	if _rig == null:
		_rig = rig
		_report(rig)


func _outfit(hair: String, top: String, bottom: String, shoes: String,
		skin: int, hair_colour: int, top_colour: int) -> Appearance:
	var appearance := Appearance.default()
	appearance.parts = {"hair": hair, "top": top, "bottom": bottom, "shoes": shoes}
	appearance.colours["skin"] = Appearance.slot_palette("skin")[skin]
	appearance.colours["hair"] = Appearance.slot_palette("hair")[hair_colour]
	appearance.colours["top"] = Appearance.slot_palette("top")[top_colour]
	return appearance


func _setup_parts() -> void:
	var outfits := [
		_outfit("Hair_Short", "Top_Tee", "Bottom_Jeans", "Shoes_Sneaker", 0, 0, 1),
		_outfit("Hair_Cap", "Top_Polo", "Bottom_Shorts", "Shoes_Sandal", 3, 1, 0),
		_outfit("Hair_Long", "Top_Jacket", "Bottom_Jeans", "Shoes_Sneaker", 1, 4, 7),
		_outfit("Hair_Swept", "Top_Puffer", "Bottom_Jeans", "Shoes_Sneaker", 2, 1, 3),
	]
	# The puffer's stripe rides the `accent` slot, so it needs its own colour or
	# it is white-on-white and the whole point of the garment is invisible.
	outfits[3].colours["accent"] = Appearance.slot_palette("accent")[0]
	for i in outfits.size():
		_spawn_dressed(outfits[i], Vector3((i - 1.5) * 0.95, 0, 0), 20.0)
	_shots = [
		{"name": "citizen_outfits", "pos": Vector3(0, 1.02, 3.75),
			"look": Vector3(0, 0.94, 0), "fov": 36.0},
		{"name": "citizen_outfit_detail", "pos": Vector3(1.70, 1.34, 1.45),
			"look": Vector3(1.42, 1.05, 0), "fov": 36.0},
	]


## Tight on the shoulder, where the tee's sleeve meets the torso shell through
## the socket bridge. Mid-grey rather than white: a white tee clips and hides
## exactly the shading that says whether the seam is geometry or lighting.
func _setup_sleeve() -> void:
	var appearance := Appearance.default()
	appearance.parts["hair"] = "Hair_None"
	appearance.colours["top"] = Color(0.55, 0.57, 0.60)
	appearance.colours["skin"] = Appearance.slot_palette("skin")[0]
	_spawn_dressed(appearance, Vector3.ZERO, 0.0)
	# The citizen's LEFT shoulder is +X; hand rest head is (0.677, 1.436, 0).
	_shots = [
		{"name": "sleeve_front", "yaw": 0.0, "pos": Vector3(0.34, 1.52, 0.86),
			"look": Vector3(0.26, 1.38, 0), "fov": 30.0},
		{"name": "sleeve_above", "yaw": 0.0, "pos": Vector3(0.30, 1.92, 0.34),
			"look": Vector3(0.30, 1.40, -0.02), "fov": 34.0},
		{"name": "sleeve_back", "yaw": 180.0, "pos": Vector3(0.34, 1.52, 0.86),
			"look": Vector3(0.26, 1.38, 0), "fov": 30.0},
	]


## Ours against theirs: the two generated shell hairstyles beside the two
## harvested ones, same head, same lighting, so the difference is the asset and
## not the presentation.
func _setup_hair() -> void:
	var styles := ["Hair_Short", "Hair_Long", "Hair_Fringe", "Hair_Swept"]
	for i in styles.size():
		var appearance := Appearance.default()
		appearance.parts["hair"] = styles[i]
		appearance.parts["top"] = "Top_Tee"
		appearance.parts["bottom"] = "Bottom_Jeans"
		appearance.parts["shoes"] = "Shoes_Sneaker"
		appearance.colours["hair"] = Appearance.slot_palette("hair")[1]
		appearance.colours["skin"] = Appearance.slot_palette("skin")[0]
		_spawn_dressed(appearance, Vector3((i - 1.5) * 0.55, 0, 0), 22.0)
		print("HAIR ", styles[i])
	_shots = [
		{"name": "citizen_hair", "pos": Vector3(0, 1.62, 1.80),
			"look": Vector3(0, 1.54, 0), "fov": 38.0},
	]


## The harvested head props, which is the shot that decides whether a cartoon
## pack's accessory can sit on a realistically-proportioned skull at all.
func _setup_gear() -> void:
	var looks := [
		{"hat": "Hat_Cap", "glasses": "Glasses_Square", "face": "Face_None", "gear": "Gear_None"},
		{"hat": "Hat_Beanie", "glasses": "Glasses_None", "face": "Face_Moustache1", "gear": "Gear_None"},
		{"hat": "Hat_Beanie", "glasses": "Glasses_Round", "face": "Face_None", "gear": "Gear_None"},
		{"hat": "Hat_None", "glasses": "Glasses_None", "face": "Face_Moustache2", "gear": "Gear_Headphones"},
	]
	for i in looks.size():
		var appearance := Appearance.default()
		appearance.parts["hair"] = "Hair_Short" if i != 2 else "Hair_None"
		appearance.parts["top"] = "Top_Tee"
		appearance.parts["bottom"] = "Bottom_Jeans"
		appearance.parts["shoes"] = "Shoes_Sneaker"
		for group in looks[i]:
			appearance.parts[group] = looks[i][group]
		appearance.colours["skin"] = Appearance.slot_palette("skin")[i % 4]
		appearance.colours["hat"] = Appearance.slot_palette("hat")[i]
		_spawn_dressed(appearance, Vector3((i - 1.5) * 0.62, 0, 0), 18.0)
	_shots = [
		{"name": "citizen_gear", "pos": Vector3(0, 1.60, 1.95),
			"look": Vector3(0, 1.52, 0), "fov": 40.0},
		{"name": "citizen_gear_wide", "pos": Vector3(0, 1.00, 3.55),
			"look": Vector3(0, 0.95, 0), "fov": 38.0},
	]


func _setup_crowd() -> void:
	# Fixed seeds: the crowd has to be reproducible so these PNGs are
	# comparable between runs and a bad-looking citizen can be traced back.
	var seeds := [11, 204, 3007, 41, 590, 6120]
	for i in seeds.size():
		_spawn_dressed(Appearance.random_from_seed(seeds[i]),
			Vector3((i - 2.5) * 0.95, 0, 0), 18.0)
		print("SEED ", seeds[i], " -> ",
			Appearance.random_from_seed(seeds[i]).describe())
	_shots = [
		{"name": "citizen_crowd", "pos": Vector3(0, 0.98, 6.1),
			"look": Vector3(0, 0.95, 0), "fov": 46.0},
	]


## Bends the joints the skin weights actually have to survive. A rest-pose
## capture cannot show a weighting bug -- a crimped elbow, a knee that pinches
## to a straw, or a vertex bound to the wrong side dragging across the crotch
## are all invisible until something rotates.
func _setup_posed() -> void:
	_spawn_one()
	var side := Vector3(1.5, 1.05, 2.1)
	_shots = [
		{"name": "citizen_pose_elbow", "yaw": 25.0, "fov": 30.0,
			"pos": Vector3(1.05, 1.62, 1.30), "look": Vector3(0.52, 1.44, 0),
			"pose": {"LeftForeArm": Vector3(0, -85, 0)}},
		{"name": "citizen_pose_knee", "yaw": 60.0, "fov": 34.0,
			"pos": Vector3(0.30, 0.72, 1.35), "look": Vector3(0.09, 0.44, 0),
			"pose": {"LeftLeg": Vector3(85, 0, 0)}},
		{"name": "citizen_pose_shoulder", "yaw": 20.0, "fov": 40.0,
			"pos": side, "look": Vector3(0, 1.20, 0),
			"pose": {"LeftArm": Vector3(0, 0, -55), "RightArm": Vector3(0, 0, 55)}},
		{"name": "citizen_pose_hip", "yaw": 55.0, "fov": 40.0,
			"pos": side, "look": Vector3(0, 0.85, 0),
			"pose": {"LeftUpLeg": Vector3(55, 0, 0), "RightUpLeg": Vector3(-30, 0, 0)}},
	]


## Mixamo bones arrive as "mixamorig1:LeftArm" or "mixamorig1_LeftArm"
## depending on the exporter, so match on the suffix the way
## cblock_player.gd::_core_bone_name does rather than on a literal name.
func _bone_index(skeleton: Skeleton3D, core: String) -> int:
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		if name == core or name.ends_with(":" + core) or name.ends_with("_" + core):
			return i
	return -1


func _apply_pose(pose: Dictionary) -> void:
	var skeleton := _skeleton_of(_rig)
	if skeleton == null:
		return
	for i in skeleton.get_bone_count():
		skeleton.reset_bone_pose(i)
	for core in pose:
		var index := _bone_index(skeleton, core)
		if index < 0:
			push_error("pose bone not found: " + core)
			continue
		var euler: Vector3 = pose[core]
		skeleton.set_bone_pose_rotation(index, Quaternion.from_euler(Vector3(
			deg_to_rad(euler.x), deg_to_rad(euler.y), deg_to_rad(euler.z))))


func _place(i: int) -> void:
	var s: Dictionary = _shots[i]
	if _rig != null:
		_rig.rotation.y = deg_to_rad(float(s.get("yaw", 0.0)))
		if s.has("pose"):
			_apply_pose(s["pose"])
	_cam.fov = s["fov"]
	_cam.look_at_from_position(s["pos"], s["look"], Vector3.UP)


func _process(delta: float) -> bool:
	_frames += 1
	var local := _frames - _shot * 14
	if local > 6:
		_accum += delta
		_count += 1
	if local >= 13:
		var img := get_root().get_texture().get_image()
		var name: String = _shots[_shot]["name"]
		img.save_png("user://" + name + ".png")
		print("CAP ", name, " ~", "%.1f" % ((_accum / float(max(1, _count))) * 1000.0), " ms")
		_accum = 0.0
		_count = 0
		_shot += 1
		if _shot >= _shots.size():
			print("CITIZEN_CAPTURE_DONE")
			return true
		_place(_shot)
	return false
