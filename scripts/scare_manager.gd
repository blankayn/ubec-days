extends Node
## ScareManager — UCB Inday
## Orchestrates all jumpscare events, tension tracking, and Inday story beats.
## Attach as a child of the NightShift root node (world.gd creates it).

const HorrorCreaturePropType = preload("res://scripts/horror_creature_prop.gd")
const CREATURE_HALF_HEIGHT := 1.025

signal scare_triggered(intensity: float)   # emitted to HUD for screen flash
signal tension_changed(level: float)        # 0.0 → 1.0
signal creature_spotted()

# ── Tension ──────────────────────────────────────────────────────────────────
var tension: float = 0.0
var _inspections_done: int = 0
var _dark_timer: float = 0.0
var _flashlight_on: bool = false

# ── Animated horror creature ──────────────────────────────────────────────────
var _shadow: HorrorCreatureProp = null
var _shadow_visible: bool = false
var _shadow_timer: float = 0.0

# ── Scare cooldown ────────────────────────────────────────────────────────────
var _scare_cooldown: float = 0.0
const SCARE_COOLDOWN_MIN := 12.0   # seconds between two scares

# ── Scripted scare queue (fires in story order) ───────────────────────────────
# Each entry: { "trigger": Callable, "fired": bool }
var _story_scares: Array = []

# ── References set by world.gd ────────────────────────────────────────────────
var player: CharacterBody3D = null
var hud: CanvasLayer = null
var world_env: WorldEnvironment = null
var caretaker: Node3D = null
var street_lights: Array = []     # Array[OmniLight3D]

# ── Random scares between story beats ─────────────────────────────────────────
var _ambient_scare_timer: float = 0.0
var _next_ambient_scare: float = 35.0
var _intro_creature_done: bool = false
var _pending_noise: Dictionary = {}
var _noise_check_timer := 0.0
var _investigation_active := false
var _investigation_position := Vector3.ZERO
var _investigation_timer := 0.0
var _registered_barricade_doors: Array = []
const HEARING_RANGE := 20.0
const HEARING_THRESHOLD := 3.0
var _proximity_audio: AudioStreamPlayer
var _proximity_playback: AudioStreamGeneratorPlayback
var _audio_phase := 0.0


func _ready() -> void:
	# Build the scripted scare sequence
	_story_scares = [
		{ "tension_gate": 0.0,  "fired": false, "fn": _scare_lullaby_wind },
		{ "tension_gate": 0.15, "fired": false, "fn": _scare_payphone_ring },
		{ "tension_gate": 0.30, "fired": false, "fn": _scare_light_flicker_all },
		{ "tension_gate": 0.45, "fired": false, "fn": _scare_shadow_window },
		{ "tension_gate": 0.55, "fired": false, "fn": _scare_caretaker_gone },
		{ "tension_gate": 0.65, "fired": false, "fn": _scare_shadow_behind_tree },
		{ "tension_gate": 0.75, "fired": false, "fn": _scare_face_in_fog },
		{ "tension_gate": 0.82, "fired": false, "fn": _scare_elevator_bang },
		{ "tension_gate": 0.90, "fired": false, "fn": _scare_lights_die },
		{ "tension_gate": 0.97, "fired": false, "fn": _scare_inday_behind_player },
	]
	_build_shadow_figure()
	_build_proximity_audio()
	_ambient_scare_timer = _next_ambient_scare


# ── Called every frame by world.gd (world passes delta) ───────────────────────
func tick(delta: float) -> void:
	_scare_cooldown = maxf(_scare_cooldown - delta, 0.0)

	# Accumulate tension from darkness
	if not _flashlight_on:
		_dark_timer += delta
		if _dark_timer > 5.0:
			_add_tension(0.004 * delta)
	else:
		_dark_timer = 0.0

	_update_creature_detection(delta)

	# Ambient (random) scares
	_ambient_scare_timer -= delta
	if _ambient_scare_timer <= 0.0 and _scare_cooldown <= 0.0:
		_fire_ambient_scare()
		_next_ambient_scare = randf_range(28.0, 55.0)
		_ambient_scare_timer = _next_ambient_scare

	# Shadow figure timeout
	if _shadow_visible:
		_shadow_timer -= delta
		if _shadow_timer <= 0.0:
			_hide_shadow()

	# Check story scare gates
	for scare in _story_scares:
		if not scare["fired"] and tension >= scare["tension_gate"] and _scare_cooldown <= 0.0:
			scare["fired"] = true
			scare["fn"].call()
			break


func set_flashlight(on: bool) -> void:
	_flashlight_on = on


func report_noise(position: Vector3, level: float, radius: float) -> void:
	if level <= 0.0:
		return
	if _pending_noise.is_empty() or level > float(_pending_noise.get("level", 0.0)):
		_pending_noise = {"position": position, "level": level, "radius": radius}


func register_barricade_door(door: Node) -> void:
	if door != null and not _registered_barricade_doors.has(door):
		_registered_barricade_doors.append(door)


func _update_creature_detection(delta: float) -> void:
	_noise_check_timer -= delta
	if _noise_check_timer <= 0.0:
		_noise_check_timer = 0.5
		_process_pending_noise()
	if _shadow_visible and is_instance_valid(player):
		var distance := player.global_position.distance_to(_shadow.global_position)
		var proximity := clampf(1.0 - distance / 30.0, 0.0, 1.0)
		_update_proximity_audio(proximity, delta)
		if _flashlight_on and _can_see_flashlight():
			_begin_investigation(player.global_position, 8.0, "The beam catches something watching you.")
	else:
		_update_proximity_audio(0.0, delta)

	if not _investigation_active:
		return
	_investigation_timer -= delta
	if _shadow_visible and _shadow != null:
		var flat_target := _investigation_position
		flat_target.y = _shadow.global_position.y
		var to_target := flat_target - _shadow.global_position
		to_target.y = 0.0
		if to_target.length() > 0.65:
			_shadow.global_position += to_target.normalized() * minf(2.8 * delta, to_target.length())
			_shadow.face_toward(_investigation_position)
		else:
			if is_instance_valid(player) and player.has_method("is_hiding") and player.is_hiding():
				if _investigation_timer > 12.0:
					_investigation_timer = randf_range(8.0, 12.0)
			else:
				_investigation_timer = minf(_investigation_timer, 6.0)
	if _investigation_timer <= 0.0:
		_investigation_active = false
		_hide_shadow()


func _process_pending_noise() -> void:
	if _pending_noise.is_empty():
		return
	var noise_position: Vector3 = _pending_noise["position"]
	var level: float = _pending_noise["level"]
	var creature_position: Vector3 = _shadow.global_position if _shadow_visible and _shadow != null else noise_position + Vector3(0.0, 0.0, 10.0)
	var distance := creature_position.distance_to(noise_position)
	var hearing_score := level * (1.0 - distance / HEARING_RANGE)
	_pending_noise.clear()
	if hearing_score <= HEARING_THRESHOLD:
		return
	_begin_investigation(noise_position, 12.0, "Something heard that.")
	for door in _registered_barricade_doors:
		if is_instance_valid(door) and door.global_position.distance_to(noise_position) < 9.0 and door.has_method("creature_arrived"):
			door.creature_arrived()


func _begin_investigation(target: Vector3, duration: float, message: String) -> void:
	if player != null and player.has_method("is_hiding") and player.is_hiding():
		target = player.global_position + Vector3(2.5, 0.0, 2.5)
	_investigation_position = target
	_investigation_timer = maxf(_investigation_timer, duration)
	if not _shadow_visible:
		_show_shadow_at(target + Vector3(0.0, 0.0, 7.0), duration + 1.0, true)
		creature_spotted.emit()
	if hud != null and not message.is_empty():
		hud.show_message(message, 2.2)
	_add_tension(0.035)


func _can_see_flashlight() -> bool:
	if not _shadow_visible or _shadow == null or player == null:
		return false
	if not player.has_method("get_flashlight_direction") or not player.has_method("is_flashlight_on") or not player.is_flashlight_on():
		return false
	var offset := _shadow.global_position - player.global_position
	var distance := offset.length()
	if distance > 15.0 or distance < 0.1:
		return false
	return player.get_flashlight_direction().normalized().dot(offset.normalized()) > 0.82


func _build_proximity_audio() -> void:
	_proximity_audio = AudioStreamPlayer.new()
	_proximity_audio.name = "CreatureProximityAudio"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.25
	_proximity_audio.stream = generator
	_proximity_audio.volume_db = -80.0
	add_child(_proximity_audio)
	_proximity_audio.play()
	_proximity_playback = _proximity_audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _update_proximity_audio(proximity: float, delta: float) -> void:
	if _proximity_audio == null or _proximity_playback == null:
		return
	_proximity_audio.volume_db = lerpf(-80.0, -14.0, proximity)
	var frequency := 28.0 + proximity * 28.0
	if proximity > 0.5:
		frequency = 72.0 + proximity * 32.0
	if proximity > 0.72:
		frequency = 900.0 + proximity * 700.0
	var frames := _proximity_playback.get_frames_available()
	for _frame in range(frames):
		var pulse := 1.0
		if proximity > 0.48 and proximity < 0.72:
			pulse = pow(maxf(sin(_audio_phase * 0.055), 0.0), 4.0)
		var sample := sin(_audio_phase) * (0.02 + proximity * 0.09) * pulse
		_proximity_playback.push_frame(Vector2(sample, sample))
		_audio_phase += TAU * frequency / 22050.0
	_audio_phase = fposmod(_audio_phase, TAU)


func on_inspection_complete(count: int) -> void:
	_inspections_done = count
	_add_tension(0.22)
	if count == 1 and player != null and is_instance_valid(player):
		await get_tree().create_timer(1.5).timeout
		var behind := player.global_transform.basis.z
		_show_shadow_at(player.global_position + behind * 7.0, 2.8, true)
		hud.show_message("Something tall moved behind the trees.", 4.5)
		scare_triggered.emit(0.4)
		_start_cooldown(8.0)
	# Story beat messages tied to Inday
	match count:
		1:
			await get_tree().create_timer(2.0).timeout
			hud.show_message("You feel a hum in your teeth. Like someone humming inside the walls.", 5.0)
		2:
			await get_tree().create_timer(1.5).timeout
			hud.show_message("PAYPHONE: No dial tone. A girl's voice: \"Naa ko diri.\"", 6.0)
		3:
			await get_tree().create_timer(1.0).timeout
			hud.show_message("DEAD TREE: Fresh soil. Small barefoot prints lead to the entrance — none lead away.", 6.0)


func _add_tension(amount: float) -> void:
	tension = clampf(tension + amount, 0.0, 1.0)
	tension_changed.emit(tension)


# ── Shadow figure ─────────────────────────────────────────────────────────────

func _build_shadow_figure() -> void:
	# Parent under the world root so global placement is reliable.
	var world_root := get_parent()
	if world_root == null:
		world_root = self
	_shadow = HorrorCreaturePropType.new()
	_shadow.name = "IndayHorrorCreature"
	_shadow.build_on_ready = false
	world_root.add_child(_shadow)
	_shadow.build()
	_shadow.set_scare_visible(false)


func notify_night_started() -> void:
	if _intro_creature_done:
		return
	_intro_creature_done = true
	_add_tension(0.42)
	_schedule_intro_creature()


func _schedule_intro_creature() -> void:
	await get_tree().create_timer(6.0).timeout
	if player == null or not is_instance_valid(player):
		return
	var forward := -player.global_transform.basis.z
	var intro_pos := player.global_position + forward * 9.0
	_show_shadow_at(intro_pos, 3.5, true)
	hud.show_message("There — by the road. It was not there a second ago.", 4.5)
	scare_triggered.emit(0.35)
	_start_cooldown(10.0)


func _show_shadow_at(pos: Vector3, duration: float, ground_to_surface := false) -> void:
	if _shadow == null:
		return
	if ground_to_surface:
		pos = _ground_creature_position(pos)
	_shadow.place_global(pos)
	if is_instance_valid(player):
		_shadow.face_toward(player.global_position)
	_shadow.set_scare_visible(true)
	_shadow.play_scare_animation(randf_range(0.0, _shadow.get_animation_length()))
	_shadow_visible = true
	_shadow_timer = maxf(duration, 2.0)


func _hide_shadow() -> void:
	_shadow_visible = false
	if _shadow:
		_shadow.set_scare_visible(false)


func _ground_creature_position(desired_position: Vector3) -> Vector3:
	# Probe close to the requested point so upper-floor scares land on that
	# floor instead of snapping through it to the ground level.
	if not is_inside_tree():
		return desired_position
	var world: World3D = null
	if is_instance_valid(player):
		world = player.get_world_3d()
	elif get_viewport() != null:
		world = get_viewport().world_3d
	if world == null:
		return desired_position
	var query := PhysicsRayQueryParameters3D.create(
		desired_position + Vector3.UP * 2.5,
		desired_position - Vector3.UP * 12.0,
		0xFFFFFFFF
	)
	query.collide_with_areas = false
	if is_instance_valid(player):
		query.exclude = [player.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var surface_position: Vector3 = hit["position"]
		desired_position.y = surface_position.y + CREATURE_HALF_HEIGHT
	return desired_position


# ── Story scare implementations ───────────────────────────────────────────────

## SCARE 1 — Wind sound, lullaby message at game start ~20s in
func _scare_lullaby_wind() -> void:
	await get_tree().create_timer(18.0).timeout
	hud.show_message("Ili-ili, tulog anay...", 4.0)
	hud.screen_flash(Color(0.8, 0.8, 1.0, 0.12), 0.6)
	_start_cooldown(15.0)


## SCARE 2 — Payphone "rings" (message flash) before player reaches it
func _scare_payphone_ring() -> void:
	if player != null and is_instance_valid(player):
		var side := player.global_transform.basis.x
		_show_shadow_at(player.global_position + side * 10.0, 2.5, true)
	hud.show_message("The payphone is ringing.", 3.0)
	hud.screen_flash(Color(1, 1, 1, 0.18), 0.25)
	scare_triggered.emit(0.3)
	_start_cooldown(20.0)


## SCARE 3 — All street lights flicker rapidly then one stays off
func _scare_light_flicker_all() -> void:
	hud.screen_flash(Color(1, 0.95, 0.8, 0.22), 0.15)
	for light in street_lights:
		_flicker_light(light, 1.4)
	await get_tree().create_timer(1.6).timeout
	# Kill one light permanently
	if street_lights.size() > 0:
		street_lights[0].light_energy = 0.0
	hud.show_message("One of the lights went out.", 3.5)
	scare_triggered.emit(0.45)
	_start_cooldown(18.0)


## SCARE 4 — Shadow figure appears briefly in a second-floor window position
func _scare_shadow_window() -> void:
	# Shadow appears high and far — simulates upper floor window
	_show_shadow_at(Vector3(-5.0, 7.2, -23.5), 3.0)
	hud.screen_flash(Color(1, 0.2, 0.2, 0.28), 0.18)
	scare_triggered.emit(0.55)
	_start_cooldown(22.0)


## SCARE 5 — Caretaker NPC disappears, replaced by a note
func _scare_caretaker_gone() -> void:
	if caretaker != null and is_instance_valid(caretaker):
		caretaker.visible = false
	hud.show_message("The caretaker is gone.", 3.0)
	await get_tree().create_timer(2.5).timeout
	hud.show_message("His post has a note: \"Dili ko mubalik.\"  (I'm not coming back.)", 6.0)
	scare_triggered.emit(0.5)
	_start_cooldown(20.0)


## SCARE 6 — Shadow figure behind the dead tree
func _scare_shadow_behind_tree() -> void:
	_show_shadow_at(Vector3(-35.0, 0.9, -8.8), 2.8, true)
	hud.screen_flash(Color(1, 0.1, 0.1, 0.35), 0.2)
	scare_triggered.emit(0.6)
	await get_tree().create_timer(1.2).timeout
	hud.show_message("Something stood behind the dead tree. Now it's gone.", 4.5)
	_start_cooldown(20.0)


## SCARE 7 — "Face" in the fog — shadow figure close, at head height, briefly
func _scare_face_in_fog() -> void:
	if player == null:
		return
	# Place shadow 6 units in front of player
	var forward := -player.global_transform.basis.z
	var face_pos := player.global_position + forward * 6.0
	face_pos.y = player.global_position.y + 0.65  # head height
	_show_shadow_at(face_pos, 2.8, true)
	scare_triggered.emit(0.75)
	hud.screen_flash(Color(1, 0.0, 0.0, 0.55), 0.12)
	await get_tree().create_timer(0.6).timeout
	hud.show_message("INDAY: \"Naa ko diri.\"", 5.0)
	_start_cooldown(25.0)


## SCARE 8 — Loud elevator bang sound + building shakes (camera shake via signal)
func _scare_elevator_bang() -> void:
	hud.screen_flash(Color(1, 1, 1, 0.65), 0.08)
	scare_triggered.emit(0.85)
	hud.show_message("BANG. Something slammed inside the building.", 4.0)
	await get_tree().create_timer(2.0).timeout
	hud.show_message("The entrance door is open.", 4.5)
	_start_cooldown(20.0)


## SCARE 9 — All lights die, 2 seconds of full darkness
func _scare_lights_die() -> void:
	for light in street_lights:
		light.light_energy = 0.0
	if world_env:
		world_env.environment.ambient_light_energy = 0.05
	hud.screen_flash(Color(0, 0, 0, 0.95), 2.0)
	scare_triggered.emit(0.9)
	await get_tree().create_timer(2.1).timeout
	# Restore dim light
	if world_env:
		world_env.environment.ambient_light_energy = 0.25
	hud.show_message("The lights came back. Most of them.", 4.0)
	_start_cooldown(15.0)


## SCARE 10 — Inday shadow directly behind player, red flash, final whisper
func _scare_inday_behind_player() -> void:
	if player == null:
		return
	var behind := player.global_transform.basis.z   # positive Z = behind
	var pos := player.global_position + behind * 1.4
	pos.y = player.global_position.y + 0.65
	_show_shadow_at(pos, 3.0, true)
	hud.screen_flash(Color(0.85, 0.0, 0.0, 0.7), 0.15)
	scare_triggered.emit(1.0)
	await get_tree().create_timer(0.9).timeout
	hud.show_message("INDAY: \"Tabang ko.\"  (Help me.)", 7.0)
	_start_cooldown(30.0)


# ── Ambient random scares (happen between story beats) ────────────────────────

var _ambient_pool := [
	"_ambient_flicker",
	"_ambient_shadow_far",
	"_ambient_text",
	"_ambient_flash",
]

func _fire_ambient_scare() -> void:
	if tension < 0.1:
		return
	var pick: String = _ambient_pool[randi() % _ambient_pool.size()]
	match pick:
		"_ambient_flicker":
			if street_lights.size() > 0:
				var idx := randi() % street_lights.size()
				_flicker_light(street_lights[idx], 0.8)
		"_ambient_shadow_far":
			var x := randf_range(-30.0, 30.0)
			_show_shadow_at(Vector3(x, 0.9, -30.0), 2.2, true)
			hud.screen_flash(Color(1, 0.3, 0.3, 0.2), 0.12)
			scare_triggered.emit(0.3)
		"_ambient_text":
			var texts := [
				"You heard footsteps behind you.",
				"Something moved at the edge of your vision.",
				"The air smells like sampaguita.",
				"A door creaked inside the building.",
				"You think you heard your name.",
			]
			hud.show_message(texts[randi() % texts.size()], 4.0)
		"_ambient_flash":
			hud.screen_flash(Color(1, 1, 1, 0.22), 0.1)
			scare_triggered.emit(0.25)
	_start_cooldown(SCARE_COOLDOWN_MIN)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _start_cooldown(seconds: float) -> void:
	_scare_cooldown = maxf(_scare_cooldown, seconds)


func _flicker_light(light: Light3D, duration: float) -> void:
	if light == null or not is_instance_valid(light):
		return
	var original_energy := light.light_energy
	var end_time := Time.get_ticks_msec() / 1000.0 + duration
	while Time.get_ticks_msec() / 1000.0 < end_time:
		light.light_energy = 0.0 if randf() > 0.5 else original_energy
		await get_tree().create_timer(0.06).timeout
	light.light_energy = original_energy
