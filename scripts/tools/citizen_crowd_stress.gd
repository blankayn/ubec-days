# What a crowd of citizens actually costs on this GPU.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/citizen_crowd_stress.gd
#
# NOT --headless: draw calls and frame time only mean something with a renderer
# attached.
#
# Patterned on colon_stress.gd, which established that DRAW CALLS -- not
# triangles -- are the ceiling on this Intel HD 5500 under gl_compatibility.
# A citizen is 5-6 visible surfaces, so 20 pedestrians is the same order of
# magnitude as the 49-building block that tool measures. That is a number worth
# having before CITY_MASTER_PLAN.md §7.5's pool of ~60 is designed around a
# guess.
#
# Every citizen is seeded, so the material cache in CitizenAppearance is
# exercised the way the real crowd would exercise it: distinct looks that
# nonetheless share materials whenever two of them roll the same swatch.
extends SceneTree

const Appearance := preload("res://scripts/citizen_appearance.gd")
const GLB := "assets/characters/citizen/citizen.glb"

const COUNTS := [8, 16, 24, 32]
const WARMUP_FRAMES := 10
const MEASURE_FRAMES := 40

var _root: Node3D
var _crowd: Node3D
var _cam: Camera3D
var _step := 0
var _frames := 0
var _accum := 0.0
var _samples := 0
var _results: Array[String] = []


func _load_rig() -> Node3D:
	var path := ProjectSettings.globalize_path("res://" + GLB).replace("\\", "/")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _initialize() -> void:
	print("CITIZEN_STRESS gpu=", RenderingServer.get_video_adapter_name())
	_root = Node3D.new()
	get_root().add_child(_root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.32, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	_root.add_child(sun)
	sun.look_at_from_position(Vector3(8, 12, 10), Vector3.ZERO, Vector3.UP)

	_cam = Camera3D.new()
	_cam.far = 300.0
	_cam.fov = 60.0
	_root.add_child(_cam)

	_crowd = Node3D.new()
	_root.add_child(_crowd)
	_populate(COUNTS[0])


## A rough city block of people: rows deep, so most are on screen at once and
## the measurement is not quietly saved by frustum culling.
func _populate(count: int) -> void:
	for child in _crowd.get_children():
		_crowd.remove_child(child)
		child.free()
	var per_row := 8
	for i in count:
		var rig := _load_rig()
		if rig == null:
			push_error("citizen.glb failed to load")
			quit(1)
			return
		Appearance.random_from_seed(1000 + i * 37).apply(rig)
		var row := i / per_row
		var column := i % per_row
		rig.position = Vector3((column - (per_row - 1) * 0.5) * 1.15, 0.0, -row * 1.6)
		rig.rotation.y = deg_to_rad(180.0)
		_crowd.add_child(rig)
	var depth := 4.5 + (count / per_row) * 1.6
	_cam.look_at_from_position(Vector3(0, 2.2, depth), Vector3(0, 0.9, -1.5), Vector3.UP)


func _process(delta: float) -> bool:
	_frames += 1
	if _frames <= WARMUP_FRAMES:
		return false
	_accum += delta
	_samples += 1
	if _samples < MEASURE_FRAMES:
		return false

	var count: int = COUNTS[_step]
	var ms := (_accum / float(_samples)) * 1000.0
	var draw_calls := Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var line := (
		"CITIZEN_STRESS_RESULT n=%d avg=%.2f ms (%.0f fps) draw_calls=%d primitives=%d"
		% [count, ms, 1000.0 / maxf(ms, 0.001), int(draw_calls), int(primitives)]
	)
	print(line)
	_results.append(line)

	_step += 1
	if _step >= COUNTS.size():
		print("CITIZEN_STRESS_DONE")
		return true
	_populate(COUNTS[_step])
	_frames = 0
	_accum = 0.0
	_samples = 0
	return false
