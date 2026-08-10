# Optimized perf test: the SAME 49-block scene, but each building is ONE material
# (Texture2DArray + custom shader) instead of 16. Compare against colon_stress.gd.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/colon_atlas_stress.gd
extends SceneTree

const MANIFEST := "C:/Users/Ariel/AppData/Local/Temp/cebu_slice/atlas_manifest.json"
const GRID := 7
const GAP_X := 40.0
const GAP_Z := 40.0

const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform sampler2DArray alb_arr : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray nrm_arr : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray rgh_arr : filter_linear_mipmap, repeat_enable;
void fragment() {
	float layer = floor(COLOR.a * 255.0 + 0.5);
	vec3 c = vec3(UV, layer);
	ALBEDO = texture(alb_arr, c).rgb * COLOR.rgb;
	NORMAL_MAP = texture(nrm_arr, c).rgb;
	ROUGHNESS = texture(rgh_arr, c).r;
}
"""

var _frames := 0
var _accum := 0.0
var _count := 0
var _blocks := 0


func _norm(p: String) -> String:
	return p.replace("\\", "/")


func _solid(c: Color) -> Image:
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	img.fill(c)
	img.generate_mipmaps()
	return img


func _load(path: String, linear_albedo: bool) -> Image:
	var img := Image.load_from_file(_norm(path))
	img.convert(Image.FORMAT_RGBA8)
	img.resize(512, 512)
	if linear_albedo:
		img.srgb_to_linear()
	img.generate_mipmaps()
	return img


func _array(layers: Array, kind: String) -> Texture2DArray:
	var imgs: Array[Image] = []
	for L in layers:
		var img: Image
		if kind == "alb":
			img = _load(L["albedo"], true) if L.has("albedo") else _solid(Color(1, 1, 1))
		elif kind == "nrm":
			img = _load(L["normal"], false) if L.has("normal") else _solid(Color(0.5, 0.5, 1.0))
		else:
			img = _load(L["rough"], false) if L.has("rough") else _solid(Color(0.7, 0.7, 0.7))
		imgs.append(img)
	var t := Texture2DArray.new()
	t.create_from_images(imgs)
	return t


func _mat_on(node: Node, m: Material) -> void:
	if node is MeshInstance3D:
		var mesh: ArrayMesh = node.mesh
		for i in range(mesh.get_surface_count()):
			mesh.surface_set_material(i, m)
	for c in node.get_children():
		_mat_on(c, m)


func _initialize() -> void:
	print("ATLAS gpu=", RenderingServer.get_video_adapter_name())
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var layers: Array = manifest["layers"]

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

	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("alb_arr", _array(layers, "alb"))
	mat.set_shader_parameter("nrm_arr", _array(layers, "nrm"))
	mat.set_shader_parameter("rgh_arr", _array(layers, "rgh"))

	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(_norm(manifest["glb"]), st)
	var proto := doc.generate_scene(st)
	_mat_on(proto, mat)

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
	cam.look_at_from_position(Vector3(-35, 130, -55),
		Vector3(mid * GAP_X, 0.0, mid * GAP_Z), Vector3.UP)
	print("ATLAS blocks=", _blocks)


func _process(delta: float) -> bool:
	_frames += 1
	if _frames > 20:
		_accum += delta
		_count += 1
	if _frames == 25:
		get_root().get_texture().get_image().save_png("user://atlas_stress.png")
	if _count >= 60:
		var ms: float = (_accum / float(_count)) * 1000.0
		var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		print("ATLAS_RESULT blocks=", _blocks,
			" avg=", "%.1f" % ms, " ms (", "%.1f" % (1000.0 / ms), " fps)",
			" draw_calls=", int(dc))
		return true
	return false
