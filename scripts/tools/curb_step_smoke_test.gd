extends SceneTree
## Headless guard on the third-person controller's step-up (cblock_player.gd
## _try_step_up): walking into a kerb the height of the map's sidewalks must
## carry the player onto it without a jump, while a full-height wall must still
## stop them dead.
##
## Synthetic geometry, not the real map: the kerb has to be at an exact known
## height for the assertions, and Banilad takes hundreds of frames to settle.
##
##   .tools/godot/Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/curb_step_smoke_test.gd

const PlayerScript := preload("res://scripts/cblock_player.gd")

# build_map.py: Z_SIDEWALK 0.15 + KERB_HEIGHT 0.15.
const KERB_TOP := 0.30
const WALL_HEIGHT := 2.5
const SETTLE_FRAMES := 20
const WALK_FRAMES := 400

var _world: Node3D
var _player: CharacterBody3D
var _start_y := 0.0
var _frames := 0
var _stage := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_build_world()
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	match _stage:
		0:
			if _frames < SETTLE_FRAMES:
				return false
			if not _player.is_on_floor():
				_failures.append("Player never settled on the ground plane")
			_start_y = _player.global_position.y
			_frames = 0
			_stage = 1
		1:
			# Drive the body straight at the kerb by hand: Input actions do not
			# arrive in a headless SceneTree, so feed velocity directly and let
			# _try_step_up run off it.
			_player.velocity.x = 0.0
			_player.velocity.z = -_player.walk_speed
			if _frames < WALK_FRAMES:
				return false
			_check_climbed_kerb()
			_reset_for_wall()
			_frames = 0
			_stage = 2
		2:
			_player.velocity.x = 0.0
			_player.velocity.z = -_player.walk_speed
			if _frames < WALK_FRAMES:
				return false
			_check_wall_blocks()
			_finish()
			return true
	return false


## ---------------------------------------------------------------------
## Checks
## ---------------------------------------------------------------------

func _check_climbed_kerb() -> void:
	var climbed := _player.global_position.y - _start_y
	print("[curb] climbed %.3f m, now at z=%.2f y=%.2f" % [
		climbed, _player.global_position.z, _player.global_position.y,
	])
	if climbed < KERB_TOP - 0.05:
		_failures.append(
			"Player did not step onto the %.2f m kerb (rose only %.3f m)"
			% [KERB_TOP, climbed]
		)
	if _player.global_position.z > -4.0:
		_failures.append(
			"Player stalled at the kerb face (z=%.2f, expected past -4.0)"
			% _player.global_position.z
		)
	if not _player.is_on_floor():
		_failures.append("Player is airborne after the kerb — it jumped, not stepped")


func _check_wall_blocks() -> void:
	print("[curb] wall run ended at z=%.2f y=%.2f" % [
		_player.global_position.z, _player.global_position.y,
	])
	if _player.global_position.y > _start_y + 0.2:
		_failures.append(
			"Player climbed a %.1f m wall (y=%.2f) — step height is too permissive"
			% [WALL_HEIGHT, _player.global_position.y]
		)
	if _player.global_position.z < -5.6:
		_failures.append(
			"Player passed through the wall (z=%.2f)" % _player.global_position.z
		)


## ---------------------------------------------------------------------
## Scene
## ---------------------------------------------------------------------

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "CurbStepWorld"

	_add_ground()
	# Kerbed slab: top face at KERB_TOP, front face at z = -5.0.
	_add_box(Vector3(0.0, KERB_TOP * 0.5, -12.5), Vector3(20.0, KERB_TOP, 15.0))

	var camera_rig := Node3D.new()
	camera_rig.name = "CameraRig"
	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.spring_length = 4.0
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	spring_arm.add_child(camera)
	camera_rig.add_child(spring_arm)
	_world.add_child(camera_rig)

	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.set_script(PlayerScript)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	_player.add_child(shape)
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	_player.add_child(model_root)
	_player.position = Vector3(0.0, 0.05, 0.0)
	_world.add_child(_player)


func _reset_for_wall() -> void:
	# Swap the kerb for a wall and put the player back on the ground plane.
	for child in _world.get_children():
		if child.name == "Step":
			child.queue_free()
	_add_box(
		Vector3(0.0, WALL_HEIGHT * 0.5, -12.5),
		Vector3(20.0, WALL_HEIGHT, 15.0)
	)
	_player.global_position = Vector3(0.0, 0.05, 0.0)
	_player.velocity = Vector3.ZERO


func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	collision.shape = box
	collision.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(collision)
	_world.add_child(ground)


func _add_box(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Step"
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	body.position = centre
	_world.add_child(body)


func _finish() -> void:
	if _failures.is_empty():
		print("[curb] ALL CHECKS PASSED")
		quit(0)
		return
	for failure in _failures:
		printerr("[curb] FAIL: " + failure)
	quit(1)
