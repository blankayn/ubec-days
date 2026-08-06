extends SceneTree
## Headless guard on the third-person controller's interaction system, the
## UI-lock alias and the pause menu.
##
## Builds a synthetic scene rather than loading a map: the geometry has to be
## predictable for the raycast assertions, and the real maps take a few hundred
## frames to settle.
##
##   .tools/godot/Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/third_person_smoke_test.gd

const PlayerScript := preload("res://scripts/cblock_player.gd")
const InteractableScript := preload("res://scripts/interactable.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")

const SETTLE_FRAMES := 24
const INTERACT_WAIT_FRAMES := 6

var _world: Node3D
var _player: CharacterBody3D
var _target: StaticBody3D
var _pause_menu: PauseMenuScript

var _last_prompt := ""
var _activated_count := 0
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
			_check_prompt_appears()
			_send_action(&"interact")
			_frames = 0
			_stage = 1
		1:
			if _frames < INTERACT_WAIT_FRAMES:
				return false
			_check_interact_fired()
			_check_ui_lock()
			_frames = 0
			_stage = 2
		2:
			if _frames < 2:
				return false
			_check_pause_menu()
			_finish()
			return true
	return false


## ---------------------------------------------------------------------
## Checks
## ---------------------------------------------------------------------

func _check_prompt_appears() -> void:
	print("[3p] player on floor: %s at y=%.2f" % [
		str(_player.is_on_floor()), _player.global_position.y,
	])
	if not _player.is_on_floor():
		_fail("player never landed on the floor collider")
	if _last_prompt.is_empty():
		_fail("no interaction prompt was emitted for a target in view")
		return
	print("[3p] prompt: %s" % _last_prompt)
	if not _last_prompt.ends_with("Read the notice"):
		_fail("prompt text lost the Interactable's own prompt: '%s'" % _last_prompt)
	# The key name is read back out of the InputMap, not hardcoded in the HUD.
	if not _last_prompt.begins_with("[E]"):
		_fail("prompt does not name the bound interact key: '%s'" % _last_prompt)


func _check_interact_fired() -> void:
	print("[3p] activations: %d" % _activated_count)
	if _activated_count != 1:
		_fail("interact action fired %d activations, expected 1" % _activated_count)


func _check_ui_lock() -> void:
	# dialogue_choice_ui.gd and phone_ui.gd only know set_ui_locked().
	if not _player.has_method("set_ui_locked"):
		_fail("controller is missing the set_ui_locked alias")
		return
	_player.set_ui_locked(true)
	if not _player.is_ui_locked():
		_fail("set_ui_locked(true) did not lock the controller")
	if not _last_prompt.is_empty():
		_fail("prompt survived a UI lock: '%s'" % _last_prompt)
	_player.set_ui_locked(false)
	if _player.is_ui_locked():
		_fail("set_ui_locked(false) did not release the controller")


func _check_pause_menu() -> void:
	if _pause_menu.is_open():
		_fail("pause menu started open")
	_pause_menu.open()
	if not _pause_menu.is_open() or not root.get_tree().paused:
		_fail("pause menu did not pause the tree")
	_pause_menu.close()
	if _pause_menu.is_open() or root.get_tree().paused:
		_fail("pause menu did not unpause the tree")

	# The controls list must resolve real bindings, not print "unbound".
	var binding: String = _pause_menu._binding_text(&"interact")
	print("[3p] controls list shows interact = %s" % binding)
	if binding != "E":
		_fail("controls panel shows interact as '%s', expected 'E'" % binding)


## ---------------------------------------------------------------------
## Scene construction
## ---------------------------------------------------------------------

func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "TestWorld"

	_world.add_child(_make_floor())

	# A wide box so the assertion survives small changes to camera pitch.
	_target = InteractableScript.new()
	_target.name = "Notice"
	var target_shape := CollisionShape3D.new()
	var target_box := BoxShape3D.new()
	target_box.size = Vector3(3.0, 3.0, 3.0)
	target_shape.shape = target_box
	_target.add_child(target_shape)
	_target.position = Vector3(0.0, 1.0, -3.0)
	_target.setup(&"notice", "Read the notice", "A parking notice.")
	_target.activated.connect(_on_target_activated)
	_world.add_child(_target)

	# CameraRig is a sibling of Player: the controller reaches it by ../.
	var camera_rig := Node3D.new()
	camera_rig.name = "CameraRig"
	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.spring_length = 5.4
	spring_arm.margin = 0.24
	spring_arm.collision_mask = 1
	spring_arm.rotation.x = -0.24
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	spring_arm.add_child(camera)
	camera_rig.add_child(spring_arm)
	_world.add_child(camera_rig)

	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.collision_layer = 2
	_player.collision_mask = 1
	var player_shape := CollisionShape3D.new()
	player_shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	player_shape.shape = capsule
	_player.add_child(player_shape)
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	model_root.rotation.y = PI
	_player.add_child(model_root)
	_player.position = Vector3(0.0, 1.2, 0.0)
	_player.set_script(PlayerScript)
	_player.prompt_changed.connect(_on_prompt_changed)
	_world.add_child(_player)

	_pause_menu = PauseMenuScript.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.player = _player
	_world.add_child(_pause_menu)


func _make_floor() -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 2.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	return floor_body


## ---------------------------------------------------------------------
## Plumbing
## ---------------------------------------------------------------------

func _on_prompt_changed(text: String) -> void:
	_last_prompt = text


func _on_target_activated(_id: StringName, _message: String) -> void:
	_activated_count += 1


## push_input goes through the viewport rather than the display server, which
## a headless run does not have.
func _send_action(action_name: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = true
	root.push_input(event)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[3p] FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[3p] ALL CHECKS PASSED")
		quit(0)
	else:
		print("[3p] %d CHECK(S) FAILED" % _failures.size())
		quit(1)
