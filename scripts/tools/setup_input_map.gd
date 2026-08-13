extends SceneTree
## One-shot tool that writes the project InputMap into project.godot.
##
## Every control used to be a hardcoded keycode, which locked out gamepads and
## rebinding. This is the single source of truth for the action list: re-run it
## after editing ACTIONS below and commit the resulting project.godot.
##
##   .tools/godot/Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/setup_input_map.gd


func _initialize() -> void:
	var actions := _build_actions()
	for action_name in actions:
		ProjectSettings.set_setting("input/%s" % action_name, {
			"deadzone": float(actions[action_name]["deadzone"]),
			"events": actions[action_name]["events"],
		})

	var error := ProjectSettings.save()
	if error != OK:
		printerr("INPUT_MAP_WRITE_FAILED error=%d" % error)
		quit(1)
		return
	print("INPUT_MAP_WRITTEN actions=%d" % actions.size())
	quit(0)


## Stick axes need a wider deadzone than buttons or they drift.
func _build_actions() -> Dictionary:
	return {
		# --- On foot: movement -------------------------------------------
		"move_forward": _entry([_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)], 0.2),
		"move_back": _entry([_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)], 0.2),
		"move_left": _entry([_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)], 0.2),
		"move_right": _entry([_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)], 0.2),
		"sprint": _entry([_key(KEY_SHIFT), _pad(JOY_BUTTON_LEFT_STICK)]),
		"jump": _entry([_key(KEY_SPACE), _pad(JOY_BUTTON_A)]),

		# --- Camera: keyboard+mouse uses relative motion, pad uses a stick -
		"look_left": _entry([_axis(JOY_AXIS_RIGHT_X, -1.0)], 0.2),
		"look_right": _entry([_axis(JOY_AXIS_RIGHT_X, 1.0)], 0.2),
		"look_up": _entry([_axis(JOY_AXIS_RIGHT_Y, -1.0)], 0.2),
		"look_down": _entry([_axis(JOY_AXIS_RIGHT_Y, 1.0)], 0.2),

		# --- Interaction and combat ---------------------------------------
		"interact": _entry([_key(KEY_E), _pad(JOY_BUTTON_X)]),
		"attack": _entry([_mouse(MOUSE_BUTTON_LEFT), _pad(JOY_BUTTON_RIGHT_SHOULDER)]),
		"attack_alt": _entry([_mouse(MOUSE_BUTTON_RIGHT), _pad(JOY_BUTTON_LEFT_SHOULDER)]),

		# --- Vehicles (Milestone 2) ---------------------------------------
		# Throttle/steering reuse the movement actions; only the handbrake is
		# its own binding so driving code does not read "jump".
		"handbrake": _entry([_key(KEY_SPACE), _pad(JOY_BUTTON_B)]),

		# --- Shell --------------------------------------------------------
		"pause": _entry([_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)]),
		"phone": _entry([_key(KEY_TAB), _pad(JOY_BUTTON_Y)]),
		"flashlight": _entry([_key(KEY_F)]),
		"character_picker": _entry([_key(KEY_C), _pad(JOY_BUTTON_BACK)]),
		"respawn": _entry([_key(KEY_R)]),
		"exit_to_menu": _entry([_key(KEY_M)]),

		# --- Emotes -------------------------------------------------------
		# Numbered so the HUD box can label them 1..N and so adding a fourth
		# emote is a one-line change here plus one in EMOTE_SCENES. The D-pad
		# gives the same two on a gamepad. Jump is deliberately NOT here: it
		# stays on the existing "jump" action (spacebar) and just gained a
		# clip.
		"emote_1": _entry([_key(KEY_1), _pad(JOY_BUTTON_DPAD_LEFT)]),
		"emote_2": _entry([_key(KEY_2), _pad(JOY_BUTTON_DPAD_RIGHT)]),
	}


func _entry(events: Array, deadzone: float = 0.5) -> Dictionary:
	return {"deadzone": deadzone, "events": events}


## Physical keycodes keep WASD in the same place on AZERTY/QWERTZ layouts.
func _key(physical_keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	return event


func _mouse(button_index: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	return event


## Pad events default to device 0, which would bind player one's controller
## only. -1 is InputMap's "any device", and is what the built-in ui_* actions
## use. Key/mouse events keep their defaults (16/32), the engine's own tags for
## the keyboard and mouse.
func _pad(button_index: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button_index
	return event


func _axis(axis: JoyAxis, axis_value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = axis
	event.axis_value = axis_value
	return event
