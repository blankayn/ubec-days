extends SceneTree
## Headless guard on the InputMap written by setup_input_map.gd.
##
## Checks that every action exists and that a realistic device event (the kind
## the OS actually delivers, device 0) still matches the stored binding.
##
##   .tools/godot/Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/input_map_smoke_test.gd

const REQUIRED_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"look_left", "look_right", "look_up", "look_down",
	"sprint", "jump", "interact", "attack", "attack_alt",
	"handbrake", "pause", "phone", "flashlight",
	"character_picker", "respawn", "exit_to_menu", "fast_travel",
]

const SECOND_PAD_DEVICE := 3

var _failures: Array[String] = []


func _initialize() -> void:
	for action_name in REQUIRED_ACTIONS:
		if not InputMap.has_action(action_name):
			_failures.append("missing action: %s" % action_name)
	if not _failures.is_empty():
		_report()
		return

	_check_key(KEY_W, "move_forward")
	_check_key(KEY_S, "move_back")
	_check_key(KEY_A, "move_left")
	_check_key(KEY_D, "move_right")
	_check_key(KEY_SHIFT, "sprint")
	_check_key(KEY_SPACE, "jump")
	_check_key(KEY_SPACE, "handbrake")
	_check_key(KEY_E, "interact")
	_check_key(KEY_ESCAPE, "pause")
	_check_key(KEY_TAB, "phone")
	_check_key(KEY_F, "flashlight")
	_check_key(KEY_C, "character_picker")
	_check_key(KEY_R, "respawn")
	_check_key(KEY_M, "exit_to_menu")
	_check_key(KEY_T, "fast_travel")

	_check_mouse(MOUSE_BUTTON_LEFT, "attack")
	_check_mouse(MOUSE_BUTTON_RIGHT, "attack_alt")

	# Device 3 stands in for "not the first controller": pad bindings must be
	# stored as ALL_DEVICES or only player one's gamepad would work.
	_check_pad_button(JOY_BUTTON_A, "jump")
	_check_pad_button(JOY_BUTTON_X, "interact")
	_check_pad_button(JOY_BUTTON_START, "pause")
	_check_pad_axis(JOY_AXIS_LEFT_Y, -1.0, "move_forward")
	_check_pad_axis(JOY_AXIS_RIGHT_X, 1.0, "look_right")

	# A binding must not answer to the wrong action.
	_check_not_action(_make_key(KEY_W), "move_back")
	_report()


func _report() -> void:
	if _failures.is_empty():
		print("INPUT_MAP_SMOKE_OK actions=%d" % REQUIRED_ACTIONS.size())
		quit(0)
		return
	for failure in _failures:
		printerr("INPUT_MAP_SMOKE_FAIL %s" % failure)
	printerr("INPUT_MAP_SMOKE_FAILED count=%d" % _failures.size())
	quit(1)


## Real key events carry a keycode as well as a physical keycode, so build them
## the way the platform layer does. `device` is left at the engine's keyboard
## tag — InputMap compares device IDs, so forcing a different one here would
## test nothing but the constant.
func _make_key(physical_keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.pressed = true
	return event


func _check_key(physical_keycode: Key, action_name: String) -> void:
	_check_action(_make_key(physical_keycode), action_name, "key %d" % physical_keycode)


func _check_mouse(button_index: MouseButton, action_name: String) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	_check_action(event, action_name, "mouse %d" % button_index)


func _check_pad_button(button_index: JoyButton, action_name: String) -> void:
	var event := InputEventJoypadButton.new()
	event.device = SECOND_PAD_DEVICE
	event.button_index = button_index
	event.pressed = true
	_check_action(event, action_name, "pad button %d" % button_index)


func _check_pad_axis(axis: JoyAxis, axis_value: float, action_name: String) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = SECOND_PAD_DEVICE
	event.axis = axis
	event.axis_value = axis_value
	_check_action(event, action_name, "pad axis %d @ %.1f" % [axis, axis_value])


func _check_action(event: InputEvent, action_name: String, label: String) -> void:
	if not InputMap.event_is_action(event, action_name):
		_failures.append("%s does not trigger '%s'" % [label, action_name])
		return
	if not event.is_action_pressed(action_name):
		_failures.append("%s does not read as pressed for '%s'" % [label, action_name])


func _check_not_action(event: InputEvent, action_name: String) -> void:
	if InputMap.event_is_action(event, action_name):
		_failures.append("event wrongly triggers '%s'" % action_name)
