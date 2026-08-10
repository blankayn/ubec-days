# In-engine capture of the photoreal Colon slice.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/colon_slice_capture.gd
#
# Runtime-loads the glb + procedural PBR textures produced by
# banilad_map/build_colon_slice.py (paths from slice_manifest.json in local
# temp), builds triplanar PBR materials for the tiling surfaces and a UV atlas
# material for the signage, lights it on the Compatibility renderer, measures
# the frame cost on THIS machine's GPU, and saves screenshots. Nothing is
# imported into the project -- every asset is loaded by absolute path.
extends SceneTree

const MANIFEST := "C:/Users/Ariel/AppData/Local/Temp/cebu_slice/slice_manifest.json"

var _frames := 0
var _shot := 0
var _cam: Camera3D
var _t_accum := 0.0
var _t_count := 0
var _shots := []


func _norm(p: String) -> String:
	return p.replace("\\", "/")


func _load_tex(path: String, is_albedo: bool) -> ImageTexture:
	var img := Image.load_from_file(_norm(path))
	if img == null:
		push_error("tex load failed: " + path)
		return null
	if is_albedo:
		img.srgb_to_linear()   # stored as display sRGB; shader wants linear
	return ImageTexture.create_from_image(img)


func _make_materials(manifest: Dictionary) -> Dictionary:
	var texdefs: Dictionary = manifest["textures"]
	var tex_cache := {}
	for key in texdefs.keys():
		var d: Dictionary = texdefs[key]
		var entry := {"albedo": _load_tex(d["albedo"], true)}
		if d.has("normal"):
			entry["normal"] = _load_tex(d["normal"], false)
		if d.has("rough"):
			entry["rough"] = _load_tex(d["rough"], false)
		tex_cache[key] = entry

	var out := {}
	var mdefs: Dictionary = manifest["materials"]
	for name in mdefs.keys():
		var d: Dictionary = mdefs[name]
		var m := StandardMaterial3D.new()
		m.resource_name = name
		m.roughness = d.get("rough", 0.85)
		m.metallic = d.get("metal", 0.0)
		if d.has("solid"):
			var c: Array = d["solid"]
			m.albedo_color = Color(c[0], c[1], c[2])
		elif d.get("signage", false):
			m.albedo_texture = tex_cache["signage"]["albedo"]
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		elif d.has("tex"):
			var t: Dictionary = tex_cache[d["tex"]]
			m.albedo_texture = t["albedo"]
			if t.has("normal"):
				m.normal_enabled = true
				m.normal_texture = t["normal"]
				m.normal_scale = 0.5
			if t.has("rough"):
				m.roughness = 1.0
				m.roughness_texture = t["rough"]
				m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
			var tint: Array = d.get("tint", [1, 1, 1])
			m.albedo_color = Color(tint[0], tint[1], tint[2])
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			# scale = tiles-per-metre; the CC0 sets are ~2-3 m real-world.
			var sc: float = 0.35
			if d["tex"] == "shutter":
				sc = 0.5
			elif d["tex"] == "galv":
				sc = 0.55
			elif d["tex"] == "asphalt":
				sc = 0.2
			m.uv1_scale = Vector3(sc, sc, sc)
		out[name] = m
	return out


func _apply(node: Node, mats: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		for i in range(mesh.get_surface_count()):
			var src := mesh.surface_get_material(i)
			var nm := ""
			if src != null:
				nm = src.resource_name
			if mats.has(nm):
				mi.set_surface_override_material(i, mats[nm])
			else:
				print("  no material for surface ", i, " name='", nm, "'")
	for c in node.get_children():
		_apply(c, mats)


func _initialize() -> void:
	print("SLICE display=", DisplayServer.get_name(),
		" gpu=", RenderingServer.get_video_adapter_name())

	var txt := FileAccess.get_file_as_string(MANIFEST)
	var manifest: Dictionary = JSON.parse_string(txt)
	if manifest == null:
		push_error("manifest parse failed")
		quit(1)
		return

	var root := Node3D.new()
	get_root().add_child(root)

	# --- environment / sky / ambient ---
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skymat := ProceduralSkyMaterial.new()
	skymat.sky_top_color = Color(0.42, 0.55, 0.72)
	skymat.sky_horizon_color = Color(0.78, 0.80, 0.80)
	skymat.ground_horizon_color = Color(0.70, 0.70, 0.68)
	skymat.ground_bottom_color = Color(0.55, 0.53, 0.50)
	skymat.sun_angle_max = 12.0
	sky.sky_material = skymat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ssao_enabled = false            # not available on Compatibility anyway
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	# --- sun ---  (rake across the street-facing -Z facades from front-left-above)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.look_at_from_position(Vector3(-25.0, 35.0, -45.0), Vector3(20.0, 4.0, 6.0), Vector3.UP)

	# --- the slice ---
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(_norm(manifest["glb"]), st)
	if err != OK:
		push_error("glb load failed: " + str(err))
		quit(1)
		return
	var scene := doc.generate_scene(st)
	root.add_child(scene)
	var mats := _make_materials(manifest)
	_apply(scene, mats)

	var run: float = manifest.get("run", 32.0)

	# --- camera ---
	_cam = Camera3D.new()
	_cam.fov = 52.0
	root.add_child(_cam)

	# Street front faces -Z (Blender +y -> glTF -Z); row runs +X, up is +Y.
	_shots = [
		{"name": "slice_eye", "pos": Vector3(1.0, 1.7, -17.0), "look": Vector3(28.0, 5.5, 1.0), "fov": 60.0},
		{"name": "slice_3q", "pos": Vector3(-11.0, 8.5, -28.0), "look": Vector3(18.0, 5.0, 1.0), "fov": 48.0},
	]
	_place(0)


func _place(i: int) -> void:
	var s: Dictionary = _shots[i]
	_cam.fov = s["fov"]
	# look_at_from_position works before the node is inside the tree.
	_cam.look_at_from_position(s["pos"], s["look"], Vector3.UP)


func _process(delta: float) -> bool:
	_frames += 1
	# warm up a few frames per shot so shadows/sky settle, then time + capture.
	var local := _frames - _shot * 14
	if local > 6:
		_t_accum += delta
		_t_count += 1
	if local >= 13:
		var img := get_root().get_texture().get_image()
		var name: String = _shots[_shot]["name"]
		var path := "user://" + name + ".png"
		img.save_png(path)
		var ms: float = (_t_accum / float(max(1, _t_count))) * 1000.0
		print("CAP ", name, " ", img.get_size(), " ~", "%.1f" % ms, " ms/frame -> ",
			ProjectSettings.globalize_path(path))
		_t_accum = 0.0
		_t_count = 0
		_shot += 1
		if _shot >= _shots.size():
			print("SLICE_DONE")
			return true
		_place(_shot)
	return false
