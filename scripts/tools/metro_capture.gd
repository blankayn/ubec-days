# In-engine capture of Metro Department Store, Colon x Juan Luna.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/metro_capture.gd
#
# Loads metro.glb + its textures by absolute path from local temp (no res://
# import), builds three material kinds -- triplanar PBR for the tiling surfaces,
# plain UV for the signage panels, solid for glass/slots -- lights it so the sun
# rakes the street elevations, and captures several angles.
extends SceneTree

const MANIFEST := "C:/Users/Ariel/AppData/Local/Temp/cebu_slice/metro_manifest.json"

var _frames := 0
var _shot := 0
var _cam: Camera3D
var _shots := []
var _accum := 0.0
var _count := 0


func _norm(p: String) -> String:
	return p.replace("\\", "/")


func _tex(path: String, linear_albedo: bool, mips: bool = true) -> ImageTexture:
	var img := Image.load_from_file(_norm(path))
	if img == null:
		push_error("tex load failed: " + path)
		return null
	if linear_albedo:
		img.srgb_to_linear()
	# Cut-out signage gets NO mipmaps: mipping averages the transparent ground
	# into the letter edges, and the alpha scissor then cuts that blend into a
	# white speckled fringe around every glyph.
	if mips:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _materials(manifest: Dictionary) -> Dictionary:
	var defs: Dictionary = manifest["textures"]
	var mdefs: Dictionary = manifest["materials"]
	# which texture keys are used by an alpha cut-out material
	var cutout := {}
	for n in mdefs.keys():
		var md: Dictionary = mdefs[n]
		if md.get("alpha", false) and md.has("uvtex"):
			cutout[md["uvtex"]] = true

	var cache := {}
	for key in defs.keys():
		var d: Dictionary = defs[key]
		var e := {"albedo": _tex(d["albedo"], true, not cutout.has(key))}
		if d.has("normal"):
			e["normal"] = _tex(d["normal"], false)
		if d.has("rough"):
			e["rough"] = _tex(d["rough"], false)
		cache[key] = e

	var out := {}
	for name in mdefs.keys():
		var d: Dictionary = mdefs[name]
		var m := StandardMaterial3D.new()
		m.resource_name = name
		m.roughness = d.get("rough", 0.85)
		m.metallic = d.get("metal", 0.0)
		if d.has("solid"):
			var c: Array = d["solid"]
			m.albedo_color = Color(c[0], c[1], c[2])
		elif d.has("uvtex"):
			# signage: mapped straight onto the panel's own UVs
			m.albedo_texture = cache[d["uvtex"]]["albedo"]
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var st: Array = d.get("tint", [1, 1, 1])
			m.albedo_color = Color(st[0], st[1], st[2])
			if d.get("alpha", false):
				# hard cut-out, so channel letters sit on the wall with no
				# signboard behind and no transparency sorting
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = 0.5
		elif d.has("tex"):
			var t: Dictionary = cache[d["tex"]]
			m.albedo_texture = t["albedo"]
			if t.has("normal"):
				m.normal_enabled = true
				m.normal_texture = t["normal"]
				m.normal_scale = 0.45
			if t.has("rough"):
				m.roughness = 1.0
				m.roughness_texture = t["rough"]
			var tint: Array = d.get("tint", [1, 1, 1])
			m.albedo_color = Color(tint[0], tint[1], tint[2])
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			var sc: float = 0.3
			if d["tex"] == "asphalt":
				sc = 0.18
			m.uv1_scale = Vector3(sc, sc, sc)
		out[name] = m
	return out


func _apply(node: Node, mats: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(i)
			var nm := ""
			if src != null:
				nm = src.resource_name
			if mats.has(nm):
				mi.set_surface_override_material(i, mats[nm])
			else:
				print("  unmapped surface: '", nm, "'")
	for c in node.get_children():
		_apply(c, mats)


func _initialize() -> void:
	print("METRO gpu=", RenderingServer.get_video_adapter_name())
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))

	var root := Node3D.new()
	get_root().add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.50, 0.68)
	sm.sky_horizon_color = Color(0.80, 0.82, 0.82)
	sm.ground_horizon_color = Color(0.72, 0.71, 0.68)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.look_at_from_position(Vector3(-90, 70, -70), Vector3(0, 8, 0), Vector3.UP)

	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(_norm(manifest["glb"]), st) != OK:
		push_error("glb load failed")
		quit(1)
		return
	var scene := doc.generate_scene(st)
	root.add_child(scene)
	_apply(scene, _materials(manifest))

	_cam = Camera3D.new()
	_cam.far = 3000.0
	root.add_child(_cam)

	# Blender (x, y) -> Godot (x, -y). Building centroid is the origin, top 26.8 m.
	# The signed elevation is the 45 m edge whose outward normal is (-0.95, 0.32)
	# in Blender = (-0.95, -0.32) in Godot XZ; its midpoint is about (-21.7, 0.5).
	_shots = [
		{"name": "metro_sign_face", "pos": Vector3(-64, 9, -14), "look": Vector3(-21, 13, 0.5), "fov": 55.0},
		# the north-west end wall: normal (-0.45, -0.89) in Godot, midpoint (-6.6, -26.3)
		{"name": "metro_leftface", "pos": Vector3(-24, 8, -60), "look": Vector3(-6.6, 12, -26.3), "fov": 54.0},
		{"name": "metro_corner", "pos": Vector3(-56, 6, 34), "look": Vector3(-16, 14, 2), "fov": 60.0},
		{"name": "metro_over", "pos": Vector3(-78, 52, -62), "look": Vector3(0, 10, 0), "fov": 46.0},
	]
	_place(0)


func _place(i: int) -> void:
	var s: Dictionary = _shots[i]
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
		var nm: String = _shots[_shot]["name"]
		img.save_png("user://" + nm + ".png")
		print("CAP ", nm, " ~", "%.1f" % ((_accum / float(max(1, _count))) * 1000.0), " ms")
		_accum = 0.0
		_count = 0
		_shot += 1
		if _shot >= _shots.size():
			print("METRO_DONE")
			return true
		_place(_shot)
	return false
