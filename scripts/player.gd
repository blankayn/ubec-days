extends CharacterBody3D

signal prompt_changed(text: String)
signal interaction_feedback(text: String)
signal battery_changed(percent: float)
signal flashlight_changed(is_on: bool)
signal noise_emitted(position: Vector3, level: float, radius: float)
signal phone_toggle_requested()

@export var walk_speed := 4.6
@export var sprint_speed := 7.2
@export var acceleration := 18.0
@export var mouse_sensitivity := 0.0022
@export var jump_force := 5.5
@export var auto_jump_enabled := false
@export var auto_jump_force_scale := 0.82
@export var auto_jump_cooldown := 0.55
@export var jump_buffer_time := 0.12
@export var battery_drain_per_second := 1.5

@onready var model_pivot: Node3D = $ModelPivot
@onready var character_visual: Node3D = $ModelPivot/CharacterVisual
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay
@onready var flashlight: SpotLight3D = $Head/Camera3D/FlashlightPivot/Flashlight

var _pitch := 0.0
var _head_base_y := 1.55
var _bob_time := 0.0
var _last_prompt := ""
var _ignore_mouse_motion_frames := 3
var _auto_jump_timer := 0.0
var _jump_buffer_timer := 0.0
var battery: float = 100.0
var flashlight_unlocked := false
var _flashlight_on := false
var _flashlight_base_energy := 3.2
var _flashlight_flicker_timer := 0.0
var _footstep_noise_timer := 0.0
var _input_locked := false
var _is_hiding := false
var _hide_camera: Camera3D = null
var _hide_camera_base_rotation := Vector3.ZERO
var _keys: Dictionary = {}
var _phone_light: OmniLight3D = null

# Camera shake state
var _shake_trauma: float = 0.0
var _shake_base_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Keep the skinned body for locomotion/melee animation state, but never show
	# it in the first-person eye camera.
	if character_visual != null:
		character_visual.visible = false
	_head_base_y = head.position.y
	_shake_base_pos = camera.position
	_flashlight_base_energy = flashlight.light_energy
	flashlight.visible = false
	_phone_light = OmniLight3D.new()
	_phone_light.name = "PhoneGlow"
	_phone_light.position = Vector3(0.12, -0.12, -0.28)
	_phone_light.light_color = Color("89c9a4")
	_phone_light.light_energy = 0.3
	_phone_light.omni_range = 3.0
	_phone_light.shadow_enabled = false
	_phone_light.visible = false
	camera.add_child(_phone_light)
	floor_snap_length = 0.42
	floor_max_angle = deg_to_rad(52.0)
	floor_constant_speed = true
	floor_stop_on_slope = true
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	safe_margin = 0.015
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if _input_locked:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_jump_buffer_timer = jump_buffer_time
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ignore_mouse_motion_frames = 2
	if not _is_hiding:
		_try_melee()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		phone_toggle_requested.emit()
		return
	if _input_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _is_hiding and _hide_camera != null:
			var hide_rotation := _hide_camera.rotation
			hide_rotation.x = clamp(
				hide_rotation.x - event.relative.y * mouse_sensitivity,
				_hide_camera_base_rotation.x - deg_to_rad(15.0),
				_hide_camera_base_rotation.x + deg_to_rad(15.0)
			)
			hide_rotation.y = clamp(
				hide_rotation.y - event.relative.x * mouse_sensitivity,
				_hide_camera_base_rotation.y - deg_to_rad(15.0),
				_hide_camera_base_rotation.y + deg_to_rad(15.0)
			)
			_hide_camera.rotation = hide_rotation
			return
		if _ignore_mouse_motion_frames > 0 or event.relative.length() > 180.0:
			return
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, -1.35, 1.35)
		head.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F:
				_toggle_flashlight()
			KEY_E:
				if _is_hiding:
					exit_hiding()
				else:
					_try_interact()


func _physics_process(delta: float) -> void:
	_ignore_mouse_motion_frames = maxi(_ignore_mouse_motion_frames - 1, 0)
	_auto_jump_timer = maxf(_auto_jump_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_update_flashlight(delta)
	if _input_locked or _is_hiding:
		velocity = Vector3.ZERO
		_update_camera_shake(delta)
		_update_prompt()
		return

	var attacking: bool = (
		character_visual != null
		and character_visual.has_method("is_attacking")
		and character_visual.is_attacking()
	)
	var input_2d := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	).normalized()
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	var direction := (right * input_2d.x + forward * -input_2d.y).normalized()

	if not is_on_floor():
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity")) * delta
	else:
		velocity.y = -0.1
		if _jump_buffer_timer > 0.0 and not attacking:
			velocity.y = jump_force
			_jump_buffer_timer = 0.0
		elif auto_jump_enabled and _auto_jump_timer <= 0.0 and not attacking and _should_auto_jump(direction):
			velocity.y = jump_force * auto_jump_force_scale
			_auto_jump_timer = auto_jump_cooldown

	var sprinting := Input.is_physical_key_pressed(KEY_SHIFT)
	var target_speed := sprint_speed if sprinting else walk_speed
	if attacking:
		target_speed *= 0.35
	var target_velocity := direction * target_speed if direction.length_squared() > 0.01 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	move_and_slide()
	_emit_footstep_noise(delta)

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var moving := direction.length_squared() > 0.01 and horizontal_speed > 0.15
	if character_visual != null and character_visual.has_method("update_locomotion"):
		character_visual.update_locomotion(horizontal_speed, sprinting, moving)
	if model_pivot != null:
		model_pivot.rotation.y = 0.0

	_update_head_bob(delta, direction.length(), target_speed)
	_update_camera_shake(delta)
	_update_prompt()


func set_flashlight_unlocked(unlocked: bool) -> void:
	flashlight_unlocked = unlocked
	if not unlocked:
		_set_flashlight_on(false)


func add_battery(amount: float) -> void:
	battery = clampf(battery + amount, 0.0, 100.0)
	battery_changed.emit(battery)
	interaction_feedback.emit("BATTERY +%d  //  %d%%" % [roundi(amount), roundi(battery)])


func add_key(key_id: StringName) -> void:
	_keys[key_id] = true
	interaction_feedback.emit("KEY ACQUIRED: " + String(key_id).to_upper())


func has_key(key_id: StringName) -> bool:
	return _keys.has(key_id)


func is_hiding() -> bool:
	return _is_hiding


func is_flashlight_on() -> bool:
	return _flashlight_on


func get_flashlight_direction() -> Vector3:
	return -camera.global_transform.basis.z


func set_phone_open(open: bool) -> void:
	set_ui_locked(open)
	_phone_light.visible = open


func set_ui_locked(locked: bool) -> void:
	_input_locked = locked
	if locked:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func enter_hiding(hide_camera: Camera3D) -> void:
	if _is_hiding or hide_camera == null:
		return
	_is_hiding = true
	_hide_camera = hide_camera
	_hide_camera_base_rotation = hide_camera.rotation
	camera.current = false
	_hide_camera.current = true
	interaction_feedback.emit("HIDDEN  //  Press E to leave")


func exit_hiding() -> void:
	if not _is_hiding:
		return
	if _hide_camera != null:
		_hide_camera.current = false
		_hide_camera.rotation = _hide_camera_base_rotation
	camera.current = true
	_hide_camera = null
	_is_hiding = false
	interaction_feedback.emit("LEFT HIDING SPOT")


func _toggle_flashlight() -> void:
	if not flashlight_unlocked:
		interaction_feedback.emit("FLASHLIGHT: You do not need it until nightfall.")
		return
	if not _flashlight_on and battery <= 0.0:
		interaction_feedback.emit("FLASHLIGHT: BATTERY EMPTY")
		return
	_set_flashlight_on(not _flashlight_on)
	interaction_feedback.emit("FLASHLIGHT: " + ("ON" if _flashlight_on else "OFF"))
	noise_emitted.emit(global_position, 1.0, 3.0)


func _set_flashlight_on(on: bool) -> void:
	_flashlight_on = on and flashlight_unlocked and battery > 0.0
	flashlight.visible = _flashlight_on
	flashlight.light_energy = _flashlight_base_energy
	flashlight_changed.emit(_flashlight_on)
	var scare_manager := get_tree().get_first_node_in_group("scare_manager")
	if scare_manager != null and scare_manager.has_method("set_flashlight"):
		scare_manager.set_flashlight(_flashlight_on)


func _update_flashlight(delta: float) -> void:
	if not _flashlight_on:
		return
	battery = maxf(battery - battery_drain_per_second * delta, 0.0)
	battery_changed.emit(battery)
	if battery <= 0.0:
		_set_flashlight_on(false)
		interaction_feedback.emit("FLASHLIGHT: BATTERY EMPTY")
		return
	if battery > 50.0:
		flashlight.visible = true
		flashlight.light_energy = _flashlight_base_energy
		return
	if battery > 20.0:
		flashlight.visible = true
		flashlight.light_energy = _flashlight_base_energy * 0.6
		return
	_flashlight_flicker_timer -= delta
	if _flashlight_flicker_timer <= 0.0:
		_flashlight_flicker_timer = randf_range(0.08, 0.25)
		flashlight.visible = randf() < 0.7
		flashlight.light_energy = _flashlight_base_energy * randf_range(0.4, 1.0)


func _emit_footstep_noise(delta: float) -> void:
	_footstep_noise_timer = maxf(_footstep_noise_timer - delta, 0.0)
	if _footstep_noise_timer > 0.0:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.1:
		return
	var running := horizontal_speed >= walk_speed + 0.4
	noise_emitted.emit(global_position, 6.0 if running else 2.0, 15.0 if running else 5.0)
	_footstep_noise_timer = 0.28 if running else 0.55


func _should_auto_jump(direction: Vector3) -> bool:
	if direction.length_squared() < 0.01:
		return false
	if not test_move(global_transform, direction * 0.18):
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var low_from := global_position + Vector3(0.0, -0.42, 0.0)
	var high_from := global_position + Vector3(0.0, 0.48, 0.0)
	var low_query := PhysicsRayQueryParameters3D.create(low_from, low_from + direction * 0.78)
	var high_query := PhysicsRayQueryParameters3D.create(high_from, high_from + direction * 0.78)
	low_query.exclude = [get_rid()]
	high_query.exclude = [get_rid()]
	low_query.collide_with_areas = false
	high_query.collide_with_areas = false
	var low_blocked := not space.intersect_ray(low_query).is_empty()
	var head_clear := space.intersect_ray(high_query).is_empty()
	return low_blocked and head_clear


func add_trauma(trauma: float) -> void:
	_shake_trauma = clampf(_shake_trauma + trauma, 0.0, 1.0)


func _update_camera_shake(delta: float) -> void:
	_shake_trauma = move_toward(_shake_trauma, 0.0, delta * 1.8)
	if _shake_trauma < 0.001:
		camera.position = _shake_base_pos
		return
	var shake := _shake_trauma * _shake_trauma
	var t := Time.get_ticks_msec() / 1000.0
	camera.position = _shake_base_pos + Vector3(
		sin(t * 47.0) * shake * 0.055,
		cos(t * 31.0) * shake * 0.04,
		0.0
	)


func _update_head_bob(delta: float, movement_amount: float, speed: float) -> void:
	if is_on_floor() and movement_amount > 0.1:
		_bob_time += delta * speed * 1.7
		head.position.y = _head_base_y + sin(_bob_time * 2.0) * 0.025
		if _shake_trauma < 0.001:
			camera.position.x = cos(_bob_time) * 0.018
	else:
		head.position.y = move_toward(head.position.y, _head_base_y, delta * 0.2)
		if _shake_trauma < 0.001:
			camera.position.x = move_toward(camera.position.x, 0.0, delta * 0.2)


func _update_prompt() -> void:
	var text := ""
	if interaction_ray.is_colliding():
		var target := interaction_ray.get_collider()
		if target != null and target.has_method("get_interaction_prompt"):
			var target_prompt: String = target.get_interaction_prompt()
			if not target_prompt.is_empty():
				text = "[E] " + target_prompt
				if target.get("face_player_on_interact") and target.has_method("face_toward"):
					target.face_toward(global_position)
	if text != _last_prompt:
		_last_prompt = text
		prompt_changed.emit(text)


func _try_interact() -> void:
	if not interaction_ray.is_colliding():
		return
	var target := interaction_ray.get_collider()
	if target != null and target.has_method("interact"):
		target.interact(self)


func _try_melee() -> void:
	if _input_locked:
		return
	var started := false
	if character_visual != null and character_visual.has_method("try_punch"):
		started = character_visual.try_punch()
	if (
		not started
		and character_visual != null
		and character_visual.has_method("is_attacking")
		and character_visual.is_attacking()
	):
		return
	if started:
		add_trauma(0.08)
		noise_emitted.emit(global_position, 4.0, 8.0)
		await get_tree().create_timer(0.14).timeout
		_apply_melee_hit()
	else:
		_apply_melee_hit()


func _apply_melee_hit() -> void:
	if interaction_ray.is_colliding():
		var target := interaction_ray.get_collider()
		if target != null and target.has_method("take_hit"):
			target.take_hit(1.0, self)
			add_trauma(0.12)
			return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 1.1, 0.0)
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 2.2)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var target: Object = hit.get("collider") as Object
	if target != null and target.has_method("take_hit"):
		target.take_hit(1.0, self)
		add_trauma(0.12)
