# Preview raw GLBs from an external asset pack, on their OWN body.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/pack_preview.gd -- \
#       --dir "C:/Users/Ariel/Downloads/Separate_assets_glb/Separate_assets_glb" \
#       --files Body_010.glb,Outwear_029.glb
#
# NOT --headless: this renders.
#
# Exists so a pack can be judged on what it looks like before any argument
# about whether it can be retargeted. Everything is loaded by absolute path
# through GLTFDocument, so nothing has to be imported into the project and
# nothing lands in `assets/` -- which also keeps third-party geometry out of
# the repo while it is only being evaluated.
#
# Files listed together are drawn together in ONE figure: a pack's garments are
# authored in the same bind space as its body, so listing the body first and a
# garment second shows the garment worn. Separate figures come from repeating
# --files.
extends SceneTree

const CAPTURE_WIDTH := 1600
const CAPTURE_HEIGHT := 1000

var _frames := 0
var _cam: Camera3D
var _root: Node3D


func _args() -> Dictionary:
	var out := {"dir": "", "sets": [], "name": "pack_preview"}
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i] == "--dir" and i + 1 < argv.size():
			out["dir"] = argv[i + 1]
		elif argv[i] == "--files" and i + 1 < argv.size():
			out["sets"].append(argv[i + 1].split(","))
		elif argv[i] == "--name" and i + 1 < argv.size():
			out["name"] = argv[i + 1]
	return out


func _load(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path.replace("\\", "/"), state) != OK:
		push_error("load failed: " + path)
		return null
	return doc.generate_scene(state) as Node3D


func _initialize() -> void:
	var args := _args()
	if String(args["dir"]).is_empty() or (args["sets"] as Array).is_empty():
		push_error("need --dir and at least one --files")
		quit(1)
		return

	_root = Node3D.new()
	get_root().add_child(_root)
	var window := get_root()
	window.size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)
	DisplayServer.window_set_size(Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT))
	window.msaa_3d = Viewport.MSAA_4X

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.20, 0.22, 0.26)
	sky_material.sky_horizon_color = Color(0.42, 0.45, 0.50)
	sky_material.ground_bottom_color = Color(0.16, 0.17, 0.19)
	sky_material.ground_horizon_color = Color(0.38, 0.40, 0.44)
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
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
	ground.position.y = -0.002
	_root.add_child(ground)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 9.0
	key.shadow_bias = 0.05
	key.shadow_normal_bias = 0.7
	_root.add_child(key)
	key.look_at_from_position(Vector3(2.3, 5.6, 5.8), Vector3(0, 0.95, 0), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.78, 0.85, 1.0)
	_root.add_child(fill)
	fill.look_at_from_position(Vector3(-4.5, 2.2, 3.0), Vector3(0, 1.0, 0), Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.5
	rim.light_color = Color(1.0, 0.92, 0.82)
	rim.light_specular = 0.0
	_root.add_child(rim)
	rim.look_at_from_position(Vector3(-2.2, 3.2, -4.6), Vector3(0, 1.15, 0), Vector3.UP)

	var sets: Array = args["sets"]
	for i in sets.size():
		var figure := Node3D.new()
		figure.position = Vector3((i - (sets.size() - 1) * 0.5) * 0.95, 0, 0)
		figure.rotation.y = deg_to_rad(20.0)
		_root.add_child(figure)
		for file in sets[i]:
			var node := _load(String(args["dir"]).path_join(String(file)))
			if node != null:
				figure.add_child(node)
				print("PACK loaded ", file)

	_cam = Camera3D.new()
	_cam.far = 200.0
	_cam.fov = 36.0
	_root.add_child(_cam)
	_cam.look_at_from_position(Vector3(0, 1.02, 3.75), Vector3(0, 0.94, 0), Vector3.UP)
	set_meta("name", args["name"])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 14:
		return false
	var img := get_root().get_texture().get_image()
	var name: String = get_meta("name")
	img.save_png("user://%s.png" % name)
	print("CAP ", name)
	print("PACK_PREVIEW_DONE")
	return true
