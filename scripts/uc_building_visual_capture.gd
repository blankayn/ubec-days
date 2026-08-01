extends SceneTree

## Capture the six UC building validation viewpoints after the rebuild.
## Usage:
##   Godot --path . -s scripts/uc_building_visual_capture.gd

const SchoolBuildingType = preload("res://scripts/school_building.gd")
const OUTPUT_DIR := "res://captures/uc_rebuild"

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _camera: Camera3D
var _ready_to_capture := false
var _shots: Array = []
var _shot_index := 0
var _shot_hold := 0


func _school_to_world(local_point: Vector3) -> Vector3:
	return Vector3(-local_point.x, local_point.y, -local_point.z)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var packed := load("res://main.tscn") as PackedScene
	assert(packed != null, "Main scene must load for UC capture")
	_world = packed.instantiate() as Node3D
	root.add_child(_world)

	var mezz_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.MEZZANINE)
	var f4_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F4)
	var f8_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F8)
	var roof_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.ROOF)

	# Absolute world positions/yaws after the school's 180-degree placement.
	# Facade faces +Z; courtyard sits north of that facade at larger +Z.
	_shots = [
		["01_exterior_entrance", Vector3(0.0, 2.2, 12.5), PI, -0.18],
		["02_ground_quadrangle", _school_to_world(Vector3(0.0, 1.9, -41.0)), 0.0, -0.4],
		["03_mezzanine", _school_to_world(Vector3(-16.5, mezz_y + 1.45, -28.0)), PI * 0.5, -0.28],
		["04_typical_upper_floor", _school_to_world(Vector3(-2.0, f4_y + 1.45, -33.5)), -PI * 0.5, -0.1],
		["05_eighth_labs", _school_to_world(Vector3(-16.0, f8_y + 1.45, -31.0)), PI, -0.1],
		["06_ninth_roof_deck", _school_to_world(Vector3(0.0, roof_y + 1.7, -30.0)), 0.0, -0.4],
	]


func _process(_delta: float) -> bool:
	if not _ready_to_capture:
		if _world.get("_bootstrapping") == true:
			return false
		_player = _world.get_node("Player") as CharacterBody3D
		_head = _player.get_node("Head") as Node3D
		_camera = _player.get_node("Head/Camera3D") as Camera3D
		var hud := _world.get_node_or_null("HUD") as CanvasLayer
		if hud != null:
			hud.visible = false
		_ready_to_capture = true
		print("UC_CAPTURE_READY")
		return false

	if _shot_index >= _shots.size():
		print("UC_BUILDING_VISUAL_CAPTURE_PASS")
		quit(0)
		return false

	if _shot_hold == 0:
		var shot: Array = _shots[_shot_index]
		_player.global_position = shot[1]
		_player.rotation = Vector3(0.0, shot[2], 0.0)
		_player.velocity = Vector3.ZERO
		_head.rotation = Vector3(shot[3], 0.0, 0.0)
		print("UC_CAPTURE_%s at %s yaw=%.2f" % [str(shot[0]).to_upper(), str(shot[1]), shot[2]])
	_shot_hold += 1
	if _shot_hold >= 10:
		var image: Image = _camera.get_viewport().get_texture().get_image()
		var shot_name: String = _shots[_shot_index][0]
		var path := "%s/%s.png" % [OUTPUT_DIR, shot_name]
		var err := image.save_png(path)
		print("UC_CAPTURE_SAVED %s err=%s bytes≈approx" % [path, err])
		_shot_index += 1
		_shot_hold = 0
	return false
