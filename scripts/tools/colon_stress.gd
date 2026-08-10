# Performance stress test: how many textured Colon blocks can this GPU push?
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/colon_stress.gd
#
# Loads the one textured slice, shares its materials across a GRID of instances
# (a fake dense downtown), points a wide camera so ALL of them are visible
# (worst case for draw calls), and reports fps + draw-call count on this GPU.
# The likely bottleneck is not triangles (trivial) but DRAW CALLS: each block is
# 16 material surfaces, so 49 blocks = ~780 draw calls, which is what actually
# hurts on a weak integrated GPU via ANGLE. That finding decides whether the
# multi-material-per-building approach needs material merging + LOD before any
# city-wide rollout.
extends SceneTree

const MANIFEST := "C:/Users/Ariel/AppData/Local/Temp/cebu_slice/slice_manifest.json"
const GRID := 7          # GRID x GRID blocks
const GAP_X := 40.0
const GAP_Z := 40.0

var _frames := 0
var _accum := 0.0
var _count := 0
var _blocks := 0


func _norm(p: String) -> String:
	return p.replace("\\", "/")


func _load_tex(path: String, is_albedo: bool) -> ImageTexture:
	var img := Image.load_from_file(_norm(path))
	if img == null:
		return null
	if is_albedo:
		img.srgb_to_linear()
	return ImageTexture.create_from_image(img)


func _make_materials(manifest: Dictionary) -> Dictionary:
	var texdefs: Dictionary = manifest["textures"]
	var tc := {}
	for key in texdefs.keys():
		var d: Dictionary = texdefs[key]
		var e := {"albedo": _load_tex(d["albedo"], true)}
		if d.has("normal"):
			e["normal"] = _load_tex(d["normal"], false)
		if d.has("rough"):
			e["rough"] = _load_tex(d["rough"], false)
		tc[key] = e
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
			m.albedo_texture = tc["signage"]["albedo"]
		elif d.has("tex"):
			var t: Dictionary = tc[d["tex"]]
			m.albedo_texture = t["albedo"]
			if t.has("normal"):
				m.normal_enabled = true
				m.normal_texture = t["normal"]
				m.normal_scale = 0.5
			if t.has("rough"):
				m.roughness = 1.0
				m.roughness_texture = t["rough"]
			var tint: Array = d.get("tint", [1, 1, 1])
			m.albedo_color = Color(tint[0], tint[1], tint[2])
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			var sc: float = 0.35
			if d["tex"] == "shutter":
				sc = 0.5
			elif d["tex"] == "asphalt":
				sc = 0.2
			m.uv1_scale = Vector3(sc, sc, sc)
		out[name] = m
	return out


# Bake the shared materials onto the mesh surfaces so every instance reuses them.
func _bake_materials(node: Node, mats: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh: ArrayMesh = node.mesh
		for i in range(mesh.get_surface_count()):
			var src := mesh.surface_get_material(i)
			var nm := src.resource_name if src != null else ""
			if mats.has(nm):
				mesh.surface_set_material(i, mats[nm])
	for c in node.get_children():
		_bake_materials(c, mats)


func _initialize() -> void:
	print("STRESS gpu=", RenderingServer.get_video_adapter_name())
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var root := Node3D.new()
	get_root().add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.look_at_from_position(Vector3(-40, 60, -60), Vector3(140, 4, 140), Vector3.UP)

	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(_norm(manifest["glb"]), st)
	var proto := doc.generate_scene(st)
	var mats := _make_materials(manifest)
	_bake_materials(proto, mats)

	for gx in range(GRID):
		for gz in range(GRID):
			var inst := proto.duplicate()
			inst.position = Vector3(gx * GAP_X, 0.0, gz * GAP_Z)
			root.add_child(inst)
			_blocks += 1

	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.far = 2000.0
	root.add_child(cam)
	var mid := (GRID - 1) * 0.5
	cam.look_at_from_position(
		Vector3(-35, 130, -55),
		Vector3(mid * GAP_X, 0.0, mid * GAP_Z), Vector3.UP)
	print("STRESS blocks=", _blocks, " (", GRID, "x", GRID, ")")


func _process(delta: float) -> bool:
	_frames += 1
	if _frames > 20:                     # warm up, then time 60 frames
		_accum += delta
		_count += 1
	if _frames == 25:
		var img := get_root().get_texture().get_image()
		img.save_png("user://stress.png")
	if _count >= 60:
		var ms: float = (_accum / float(_count)) * 1000.0
		var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var prim := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		print("STRESS_RESULT blocks=", _blocks,
			" avg=", "%.1f" % ms, " ms (", "%.1f" % (1000.0 / ms), " fps)",
			" draw_calls=", int(dc), " primitives=", int(prim))
		return true
	return false
