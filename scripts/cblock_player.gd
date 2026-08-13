extends CharacterBody3D
## GTA-style third-person controller for CBlock. Loads the in-game character
## pick (Gusion baked clips or Duterte Mixamo retarget). Camera orbit stays
## independent from body turning.

signal status_message(text: String)
signal prompt_changed(text: String)

const CharacterRoster := preload("res://scripts/cblock_character_roster.gd")
const GUSION_SCENE := preload(
	"res://assets/characters/gusion/gusion_dimension_w_rigged.glb"
)
const DUTERTE_SCENE := preload("res://characters/president_duterte__rig.glb")
const POLICE_SCENE := preload("res://assets/npcs/police.glb")
const CITIZEN_SCENE := preload("res://assets/characters/citizen/citizen.glb")
const IDLE_SCENE := preload("res://animation mixamo/Idle.fbx")
const WALK_SCENE := preload("res://animation mixamo/Walking.fbx")
const SPRINT_SCENE := preload("res://animation mixamo/Sprint.fbx")
const PUNCH_LEFT_SCENE := preload("res://animation mixamo/Punchingleft.fbx")
const PUNCH_RIGHT_SCENE := preload("res://animation mixamo/Punchingright.fbx")
const HIT_SCENE := preload("res://animation mixamo/Hit To Body.fbx")
const JUMP_SCENE := preload("res://animation mixamo/Jump.fbx")
const MOONWALK_SCENE := preload("res://animation mixamo/Moonwalk.fbx")
const FLAIR_SCENE := preload("res://animation mixamo/Flair.fbx")

## Mixamo exports every clip under this one track name.
const MIXAMO_CLIP_NAME := "mixamo_com"

## library -> clip -> source FBX. Adding an emote is one line here plus one
## entry in EMOTES; nothing else needs touching.
const MIXAMO_CLIPS := {
	"locomotion": {
		"idle": IDLE_SCENE,
		"walk": WALK_SCENE,
		"sprint": SPRINT_SCENE,
		"jump": JUMP_SCENE,
	},
	"combat": {
		"punch_left": PUNCH_LEFT_SCENE,
		"punch_right": PUNCH_RIGHT_SCENE,
		"hit": HIT_SCENE,
	},
	"emote": {
		"moonwalk": MOONWALK_SCENE,
		"flair": FLAIR_SCENE,
	},
}

## Only these loop. Everything else is a one-shot that hands the body back to
## locomotion when it finishes.
const LOOPING_CLIPS := ["idle", "walk", "sprint"]
## ...and every emote, whatever it is called. An emote is a HELD performance the
## player switches off, not a clip that runs out. Keyed off the library rather
## than listing clip names so a third emote loops without anyone remembering to
## add it here -- which keeps the "one line in MIXAMO_CLIPS plus one in EMOTES"
## property intact.
const LOOPING_LIBRARIES := ["emote"]

## Emote slots in HUD order. The index is the number key: 1 -> flair.
## Kept here rather than in the HUD so the player owns what it can perform and
## banilad_city.gd only has to render the labels.
const EMOTES := [
	{"action": &"emote_1", "clip": "flair", "label": "Flair"},
	{"action": &"emote_2", "clip": "moonwalk", "label": "Moonwalk"},
]

const CHARACTER_SCENES := {
	"gusion": GUSION_SCENE,
	"duterte": DUTERTE_SCENE,
	"police": POLICE_SCENE,
	"citizen": CITIZEN_SCENE,
}

const EMBEDDED_LOCOMOTION := {
	"idle": "Idle",
	"walk": "Walking",
	"sprint": "Sprint",
}
const EMBEDDED_COMBAT := {
	"punch_left": "PunchingLeft",
	"punch_right": "PunchingRight",
	"hit": "Hit",
}

const WALK_AUTHORED_SPEED := 1.715
const SPRINT_AUTHORED_SPEED := 5.927
const IDLE_THRESHOLD := 0.1
const SOLE_CLEARANCE := 0.018
const TARGET_HEIGHT_METERS := 1.78
const LOCOMOTION_CROSSFADE := 0.18
const ATTACK_CROSSFADE := 0.08
## Emotes ease in more than a punch does -- they are a performance, not a hit.
const EMOTE_CROSSFADE := 0.16
## Turntable rate while the customizer is open, radians per second.
const CUSTOMIZE_SPIN_SPEED := 0.55
## Mesh names that define a rig's height on their own. See _height_reference.
const HEIGHT_REFERENCE_MESHES := ["CitizenBody"]

# How far in front of the body an Interactable can be picked up. The probe
# starts at the camera, which orbits well behind the player, so the camera's
# own distance is added on top of this at query time.
const INTERACT_RANGE := 3.0
# Interactables are plain StaticBody3D on the world layer.
const INTERACT_MASK := 1

# Core Mixamo bone names required by the locomotion clips.
const REQUIRED_CORE_BONES := [
	"Hips",
	"Spine",
	"Spine1",
	"Spine2",
	"Neck",
	"Head",
	"LeftShoulder",
	"LeftArm",
	"LeftForeArm",
	"LeftHand",
	"RightShoulder",
	"RightArm",
	"RightForeArm",
	"RightHand",
	"LeftUpLeg",
	"LeftLeg",
	"LeftFoot",
	"RightUpLeg",
	"RightLeg",
	"RightFoot",
]

@export_category("Movement")
@export var walk_speed := 3.2
@export var sprint_speed := 6.3
@export var acceleration := 18.0
@export var turn_speed := 11.0
@export var jump_force := 5.6
## Tallest ledge the body climbs by walking into it. The map's kerbed sidewalks
## top out at 0.30 m (Z_SIDEWALK 0.15 + KERB_HEIGHT 0.15 in build_map.py), so
## this clears a kerb with margin while still leaving real walls unclimbable.
@export var max_step_height := 0.45

@export_category("GTA Camera")
@export var mouse_sensitivity := 0.0022
## Right-stick orbit rate, in radians per second.
@export var pad_look_speed := 2.6
@export var camera_target_height := 0.64
@export var camera_recenter_delay := 0.75
@export var camera_recenter_speed := 2.25
@export var minimum_pitch := -0.85
@export var maximum_pitch := 0.38

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model_root: Node3D = $ModelRoot
@onready var camera_rig: Node3D = $"../CameraRig"
@onready var spring_arm: SpringArm3D = $"../CameraRig/SpringArm3D"
@onready var camera: Camera3D = $"../CameraRig/SpringArm3D/Camera3D"

var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _bone_indices: Dictionary = {}
var _bone_by_core: Dictionary = {}
var _track_path_prefix := ""
var _root_motion_scale := 1.0
var _bone_suffix_regex := RegEx.new()
var _animation_state := ""

var _camera_yaw := 0.0
var _camera_pitch := -0.22
var _time_since_manual_look := 999.0

var _visual_bounds := AABB()
var _has_visual_bounds := false
var _visual_foot_error := INF

var _oneshot_time_remaining := 0.0
## Index into EMOTES of the emote currently held, or -1 for none.
##
## A held emote owns the body with NO timer -- it runs until something in the
## interrupt list cancels it -- which is why it is tracked separately from
## _oneshot_time_remaining rather than folded into it. Knowing WHICH emote is up
## is also what lets the number key toggle: same key stops, other key switches.
##
## Invariant: _emote_index >= 0 implies _oneshot_time_remaining == 0.0.
var _emote_index := -1
var _punch_left_next := true
var _character_id := CharacterRoster.DEFAULT_ID
var _character_label := "Character"
var _controls_enabled := true

## Customizer framing. The pre_* values restore whatever the camera was doing
## before the panel opened, so leaving the customizer does not silently retune
## the player's normal chase camera.
var _customize_view := false
var _pre_customize_spring := 0.0
var _pre_customize_height := 0.0
var _pre_customize_yaw := 0.0
var _model_rest_yaw := 0.0
var _last_prompt := ""
var _interact_key_label := "E"
var _camera_enabled := true
var _stowed := false


func _ready() -> void:
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	up_direction = Vector3.UP
	safe_margin = 0.02
	spring_arm.add_excluded_object(get_rid())
	_model_rest_yaw = model_root.rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_yaw = global_rotation.y
	_camera_pitch = clampf(spring_arm.rotation.x, minimum_pitch, maximum_pitch)
	_update_camera_transform()
	_bone_suffix_regex.compile("_\\d+$")
	_interact_key_label = _action_key_label(&"interact", "E")
	CharacterRoster.load_saved()
	_build_selected_rig()


func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw = wrapf(
			_camera_yaw - event.relative.x * mouse_sensitivity,
			-PI,
			PI
		)
		_camera_pitch = clampf(
			_camera_pitch - event.relative.y * mouse_sensitivity,
			minimum_pitch,
			maximum_pitch
		)
		_time_since_manual_look = 0.0
		_update_camera_transform()
		return
	if event.is_action_pressed(&"jump") and is_on_floor():
		velocity.y = jump_force
		# The clip is cosmetic -- physics still does the jumping. Cancel any
		# emote first so a flair does not swallow the leap.
		_cancel_emote()
		_play_oneshot("locomotion/jump", LOCOMOTION_CROSSFADE)
		get_viewport().set_input_as_handled()
		return
	for index in EMOTES.size():
		if event.is_action_pressed(EMOTES[index]["action"]):
			_try_emote(index)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _controls_enabled:
		return
	# A click in a released window recaptures the mouse rather than swinging.
	if (
		event is InputEventMouseButton
		and event.pressed
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed(&"attack"):
		var clip_name := "punch_left" if _punch_left_next else "punch_right"
		_punch_left_next = not _punch_left_next
		_trigger_attack(clip_name)
	elif event.is_action_pressed(&"attack_alt"):
		_trigger_attack("hit")


func _physics_process(delta: float) -> void:
	_time_since_manual_look += delta
	if _oneshot_time_remaining > 0.0:
		_oneshot_time_remaining = maxf(_oneshot_time_remaining - delta, 0.0)

	if not _controls_enabled:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= float(
				ProjectSettings.get_setting("physics/3d/default_gravity")
			) * delta
		elif velocity.y < 0.0:
			velocity.y = -0.1
		move_and_slide()
		_update_camera_transform()
		_update_animation(false)
		_set_prompt("")
		return

	_apply_pad_look(delta)

	var input_vector := Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	# Walking out of a performance cuts it. Checked against the raw input rather
	# than velocity, so the emote ends the moment the player asks to move
	# instead of after the body has already slid.
	#
	# Leaving the floor cuts it too, and that clause is load-bearing now: a held
	# emote has no timer to expire, so a citizen who danced off a kerb would
	# otherwise flair all the way down.
	if _emote_index >= 0 and (
		input_vector.length_squared() > 0.01 or not is_on_floor()
	):
		_cancel_emote()

	# Movement comes from the independent orbit yaw, not from a camera transform
	# that can inherit character rotation.
	var orbit_basis := Basis(Vector3.UP, _camera_yaw)
	var camera_forward := -orbit_basis.z
	var camera_right := orbit_basis.x
	var direction := (
		camera_right * input_vector.x
		+ camera_forward * -input_vector.y
	).normalized()

	var sprinting := (
		Input.is_action_pressed(&"sprint")
		and direction.length_squared() > 0.01
	)
	var target_speed := sprint_speed if sprinting else walk_speed
	var target_velocity := direction * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if not is_on_floor():
		velocity.y -= float(
			ProjectSettings.get_setting("physics/3d/default_gravity")
		) * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	_try_step_up(delta)
	move_and_slide()

	if direction.length_squared() > 0.01:
		var target_rotation := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(
			rotation.y,
			target_rotation,
			minf(delta * turn_speed, 1.0)
		)

	_update_camera_recenter(input_vector, delta)
	_update_camera_transform()
	_update_animation(sprinting)
	_update_interaction_probe()


## CharacterBody3D has no built-in step height: a 0.15 m kerb reads as a wall
## and move_and_slide just stops dead against it, which is why walking onto a
## sidewalk used to need a jump. This lifts the body over anything up to
## max_step_height when the path is blocked at foot level but clear above it.
##
## Runs before move_and_slide so the horizontal velocity already queued for this
## frame carries the body forward onto the ledge it was just raised over.
func _try_step_up(delta: float) -> bool:
	if not is_on_floor() or velocity.y > 0.0:
		return false
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length_squared() < 0.000001:
		return false
	# Probe a little further than one frame of travel so the lift happens on the
	# approach rather than after the body is already jammed against the kerb.
	var probe := motion.normalized() * maxf(motion.length(), 0.12)

	var from := global_transform
	if not test_move(from, probe):
		return false  # Nothing in the way; ordinary movement handles it.

	var raised := from.translated(Vector3.UP * max_step_height)
	if test_move(raised, probe):
		return false  # Still blocked a step up: this is a wall, not a kerb.

	# Find the surface the raised body would come down on after stepping across.
	var landing := KinematicCollision3D.new()
	var descent := max_step_height + 0.05
	if not test_move(raised.translated(probe), Vector3.DOWN * descent, landing):
		return false  # Ledge with nothing to stand on — a gap, so refuse.
	if landing.get_normal().angle_to(Vector3.UP) > floor_max_angle:
		return false  # Too steep to count as floor.

	# The raised body sat max_step_height up; whatever of that it fell back
	# through is clearance, and the remainder is the height of the step.
	var rise := max_step_height - landing.get_travel().length()
	if rise <= 0.0:
		return false
	global_position.y += rise
	velocity.y = 0.0
	return true


func _apply_pad_look(delta: float) -> void:
	var look_vector := Input.get_vector(
		&"look_left", &"look_right", &"look_up", &"look_down"
	)
	if look_vector.is_zero_approx():
		return
	_camera_yaw = wrapf(
		_camera_yaw - look_vector.x * pad_look_speed * delta,
		-PI,
		PI
	)
	_camera_pitch = clampf(
		_camera_pitch - look_vector.y * pad_look_speed * delta,
		minimum_pitch,
		maximum_pitch
	)
	_time_since_manual_look = 0.0


func _update_camera_recenter(input_vector: Vector2, delta: float) -> void:
	var has_forward_intent := input_vector.y < -0.25
	var mostly_forward := absf(input_vector.x) < 0.82
	if (
		_time_since_manual_look < camera_recenter_delay
		or not has_forward_intent
		or not mostly_forward
		or not is_on_floor()
	):
		return
	_camera_yaw = lerp_angle(
		_camera_yaw,
		rotation.y,
		minf(camera_recenter_speed * delta, 1.0)
	)


func _update_camera_transform() -> void:
	if camera_rig == null or not _camera_enabled:
		return
	camera_rig.global_position = global_position + Vector3.UP * camera_target_height
	camera_rig.global_rotation = Vector3(0.0, _camera_yaw, 0.0)
	spring_arm.rotation.x = _camera_pitch


func _update_animation(sprinting: bool) -> void:
	# A held emote owns the body outright. Checked BEFORE the one-shot timer
	# because a hold has no timer to run down -- this is the guard that stops a
	# looping emote being crossfaded into idle after exactly one cycle, which is
	# the whole reason flipping the clip to LOOP_LINEAR alone changed nothing.
	if _emote_index >= 0:
		return
	if _oneshot_time_remaining > 0.0:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < IDLE_THRESHOLD:
		_set_animation("idle")
	elif sprinting:
		_set_animation("sprint")
	else:
		_set_animation("walk")


## ---------------------------------------------------------------------
## Interaction: the third-person twin of the first-person controller's
## raycast prompt. Targets are plain Interactable (interactable.gd) bodies,
## picked up by duck-typing so any node exposing the two methods works.
## ---------------------------------------------------------------------

func _update_interaction_probe() -> void:
	var target := _probe_interactable()
	var text := ""
	if target != null:
		var target_prompt: String = target.get_interaction_prompt()
		if not target_prompt.is_empty():
			text = "[%s] %s" % [_interact_key_label, target_prompt]
			if target.get("face_player_on_interact") and target.has_method("face_toward"):
				target.face_toward(global_position)
	_set_prompt(text)


func _try_interact() -> void:
	var target := _probe_interactable()
	if target != null and target.has_method("interact"):
		target.interact(self)


## Aims down the camera's view axis. The orbit camera sits behind the player,
## so the ray has to cover that gap before INTERACT_RANGE starts counting or
## the reach would shrink as the spring arm extends.
func _probe_interactable() -> Node3D:
	if camera == null or not is_inside_tree():
		return null
	var origin := camera.global_position
	var reach := origin.distance_to(global_position) + INTERACT_RANGE
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin - camera.global_basis.z * reach,
		INTERACT_MASK,
		[get_rid()]
	)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider := hit.get("collider") as Node3D
	if collider == null or not collider.has_method("get_interaction_prompt"):
		return null
	return collider


func _set_prompt(text: String) -> void:
	if text == _last_prompt:
		return
	_last_prompt = text
	prompt_changed.emit(text)


## Reads the prompt's key name back out of the InputMap so a rebind does not
## leave the HUD advertising the wrong key.
func _action_key_label(action_name: StringName, fallback: String) -> String:
	if not InputMap.has_action(action_name):
		return fallback
	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event == null:
			continue
		var label := key_event.as_text_physical_keycode()
		if label.is_empty():
			label = key_event.as_text_keycode()
		if not label.is_empty():
			return label
	return fallback


func reset_character(position_value: Vector3) -> void:
	global_position = position_value
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	_camera_yaw = 0.0
	_camera_pitch = -0.22
	_time_since_manual_look = 999.0
	_cancel_emote()
	_oneshot_time_remaining = 0.0
	_animation_state = ""
	_set_animation("idle")
	_update_camera_transform()
	status_message.emit("POSITION RESET  //  CENTRAL PLAZA")


func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		velocity.x = 0.0
		velocity.z = 0.0
		# A UI opening mid-dance has to end it here. The controls-disabled
		# branch of _physics_process never reads movement input, so the usual
		# cancel is unreachable from there; that branch does still call
		# _update_animation, which now blends to idle on its own.
		_cancel_emote()
		_set_prompt("")


## The first-person controller names this the other way round. Shared UI
## (dialogue_choice_ui.gd, phone_ui.gd) calls set_ui_locked on whichever
## player it was handed, so both controllers answer to both names.
func set_ui_locked(locked: bool) -> void:
	set_controls_enabled(not locked)


func is_ui_locked() -> bool:
	return not _controls_enabled


## Hands the orbit rig to something else — a vehicle's chase camera — without
## the player fighting it back every physics frame.
func set_camera_enabled(enabled: bool) -> void:
	_camera_enabled = enabled


## Parks the player out of the world while they are driving (Milestone 2c).
## Physics and collision stop so the body cannot be shoved around by the car
## it is riding in, and the mouse stays captured because the vehicle wants it.
func set_stowed(stowed: bool) -> void:
	if _stowed == stowed:
		return
	_stowed = stowed
	_controls_enabled = not stowed
	_camera_enabled = not stowed
	visible = not stowed
	collision_shape.disabled = stowed
	set_physics_process(not stowed)
	if stowed:
		velocity = Vector3.ZERO
		# Cancel AND force idle. set_physics_process(false) above means
		# _update_animation will never run to blend the dance out, so without
		# the explicit _set_animation the hidden rig would keep evaluating 53
		# emote tracks for the whole drive and resume on a stale pose.
		_cancel_emote()
		_set_animation("idle")
		_set_prompt("")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_update_camera_transform()


func is_stowed() -> bool:
	return _stowed


func get_character_id() -> String:
	return _character_id


func switch_character(character_id: String) -> void:
	if character_id == _character_id and _skeleton != null:
		status_message.emit("%s ALREADY SELECTED" % _character_label)
		return
	CharacterRoster.set_selected(character_id)
	# Straight to -1 rather than _cancel_emote(): the rig this emote was playing
	# on is about to be freed, so there is nothing left to blend back to.
	_emote_index = -1
	_oneshot_time_remaining = 0.0
	_animation_state = ""
	_skeleton = null
	_animation_player = null
	_bone_indices.clear()
	_bone_by_core.clear()
	_has_visual_bounds = false
	while model_root.get_child_count() > 0:
		var child := model_root.get_child(0)
		model_root.remove_child(child)
		child.free()
	_build_selected_rig()


## ---------------------------------------------------------------------
## Rig construction: instantiate the roster pick, then prefer baked clips
## when present and otherwise retarget Mixamo FBX onto the skeleton.
## ---------------------------------------------------------------------

func _build_selected_rig() -> void:
	var character := CharacterRoster.get_selected()
	_character_id = String(character.get("id", CharacterRoster.DEFAULT_ID))
	_character_label = String(character.get("display_name", "Character")).to_upper()
	var packed: PackedScene = CHARACTER_SCENES.get(
		_character_id,
		GUSION_SCENE
	) as PackedScene
	if packed == null:
		push_error("Missing PackedScene for CBlock character '%s'." % _character_id)
		return

	var rig_root := packed.instantiate() as Node3D
	rig_root.name = "%sRig" % String(character.get("display_name", "Player")).replace(" ", "")
	model_root.add_child(rig_root)
	_skeleton = rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	_animation_player = rig_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton == null or _animation_player == null:
		push_error("Could not find Skeleton3D/AnimationPlayer on %s." % _character_label)
		return

	_bone_indices.clear()
	_bone_by_core.clear()
	for bone_index in _skeleton.get_bone_count():
		var bone_name := String(_skeleton.get_bone_name(bone_index))
		_bone_indices[bone_name] = bone_index
		var core := _core_bone_name(bone_name)
		if not core.is_empty():
			_bone_by_core[core] = bone_name

	if not _validate_required_bones():
		return

	var animation_root: Node = _animation_player.get_node(_animation_player.root_node)
	_track_path_prefix = String(animation_root.get_path_to(_skeleton)) + ":"

	_install_animation_library()
	# Before _scale_and_align_visual, not after: that function measures the
	# union AABB of the VISIBLE meshes, so the wardrobe has to be resolved
	# first or the citizen is grounded against whichever parts happened to
	# ship enabled.
	_apply_appearance(rig_root)
	_scale_and_align_visual(rig_root)
	# Defensive: switch_character already clears this, but any future caller
	# that rebuilds the rig directly would otherwise leave a hold pointing at an
	# AnimationPlayer that no longer exists.
	_emote_index = -1
	_animation_state = ""
	_set_animation("idle")
	set_meta("idle_animation_loaded", _animation_player.has_animation("locomotion/idle"))
	set_meta("visual_foot_error", _visual_foot_error)
	set_meta("player_character", _character_id)
	status_message.emit("%s READY  //  Idle + Walk + Sprint + Combat" % _character_label)


## Applies the saved look to a freshly built rig. A no-op for the three fixed
## characters, which have no part meshes to switch.
func _apply_appearance(rig_root: Node3D) -> void:
	if not CharacterRoster.is_customizable(_character_id):
		return
	CharacterRoster.get_appearance().apply(rig_root)


## Swaps the citizen's look on the live rig. Re-grounds afterwards because a
## taller hairstyle or a thicker sole changes the measured height.
func set_appearance(appearance: CitizenAppearance) -> void:
	if appearance == null or model_root.get_child_count() == 0:
		return
	CharacterRoster.set_appearance(appearance)
	if not CharacterRoster.is_customizable(_character_id):
		return
	var rig_root := model_root.get_child(0) as Node3D
	if rig_root == null:
		return
	# Reset the scale before re-measuring: _scale_and_align_visual multiplies
	# rig_root.scale in, so measuring an already-scaled rig would compound.
	rig_root.scale = Vector3.ONE
	appearance.apply(rig_root)
	_scale_and_align_visual(rig_root)


func get_appearance() -> CitizenAppearance:
	return CharacterRoster.get_appearance()


## The emote roster, for the HUD to label. Only reports clips that actually
## retargeted onto this character, so the box never offers a key that does
## nothing.
func get_emotes() -> Array:
	var available: Array = []
	for entry in EMOTES:
		if _animation_player != null and _animation_player.has_animation(
			"emote/%s" % entry["clip"]
		):
			available.append(entry)
	return available


## Frames the citizen for the customizer: pulls the spring arm in, raises the
## look-at to chest height, and swings the camera around to the front so the
## player is looking at the face rather than the back of the head.
##
## Safe to drive while controls are off -- _physics_process still calls
## _update_camera_transform() when _controls_enabled is false.
func set_customize_view(enabled: bool) -> void:
	if enabled:
		if not _customize_view:
			_pre_customize_spring = spring_arm.spring_length
			_pre_customize_height = camera_target_height
			_pre_customize_yaw = _camera_yaw
		_customize_view = true
		spring_arm.spring_length = 2.3
		camera_target_height = 0.98
		_camera_yaw = rotation.y + PI
		_camera_pitch = -0.08
		set_controls_enabled(false)
	else:
		if _customize_view:
			spring_arm.spring_length = _pre_customize_spring
			camera_target_height = _pre_customize_height
			_camera_yaw = _pre_customize_yaw
		_customize_view = false
		model_root.rotation.y = _model_rest_yaw
	_update_camera_transform()


func _process(delta: float) -> void:
	# Turntable. Rotating ModelRoot rather than the body means nothing in
	# _physics_process fights it and the collision capsule stays put.
	if _customize_view:
		model_root.rotation.y = wrapf(
			model_root.rotation.y + CUSTOMIZE_SPIN_SPEED * delta, -PI, PI
		)


func _validate_required_bones() -> bool:
	var missing: Array[String] = []
	for core_name in REQUIRED_CORE_BONES:
		if not _bone_by_core.has(core_name):
			missing.append(core_name)
	if missing.is_empty():
		return true
	push_error(
		"%s rig is missing required bones: %s" % [_character_label, ", ".join(missing)]
	)
	return false


## Strips Mixamo prefixes and optional exporter suffixes from source tracks.
func _core_bone_name(name_value: String) -> String:
	var stripped := name_value
	if stripped.begins_with("mixamorig1_"):
		stripped = stripped.substr("mixamorig1_".length())
	elif stripped.begins_with("mixamorig1:"):
		stripped = stripped.substr("mixamorig1:".length())
	elif stripped.begins_with("mixamorig_"):
		stripped = stripped.substr("mixamorig_".length())
	elif stripped.begins_with("mixamorig:"):
		stripped = stripped.substr("mixamorig:".length())
	else:
		return ""
	return _bone_suffix_regex.sub(stripped, "", false)


func _target_bone_index(core_name: String) -> int:
	if not _bone_by_core.has(core_name):
		return -1
	return int(_bone_indices.get(_bone_by_core[core_name], -1))


func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D()
	var current := node
	while current != null and current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


## Meshes that define the rig's height, if it declares any; otherwise every
## visible mesh, which is what the three fixed characters need.
func _height_reference(rig_root: Node3D) -> Array:
	for reference_name in HEIGHT_REFERENCE_MESHES:
		var found := rig_root.find_child(reference_name, true, false)
		if found is MeshInstance3D and (found as MeshInstance3D).visible:
			return [found]
	var visible_meshes: Array = []
	for mesh_node in rig_root.find_children("*", "MeshInstance3D", true, false):
		if (mesh_node as MeshInstance3D).visible:
			visible_meshes.append(mesh_node)
	return visible_meshes


## Scales the whole rig to a human-sized height and plants its feet on the
## capsule bottom.
func _scale_and_align_visual(rig_root: Node3D) -> void:
	var pre_scale_bounds := AABB()
	var started := false
	# A character's height is its BODY, not its hat. Once head-mounted props
	# exist, measuring the union of everything visible means putting on a top
	# hat scales the whole citizen down so the hat fits 1.78 m -- they visibly
	# shrink when you dress them. Rigs that ship such props name their base
	# mesh in HEIGHT_REFERENCE_MESHES; anything else keeps the old behaviour of
	# measuring every visible mesh.
	var reference := _height_reference(rig_root)
	for mesh_node in reference:
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		# Skip meshes that are switched off. citizen.glb ships every clothing
		# and hair option as a sibling mesh, so an unfiltered union AABB is the
		# union of ALL hairstyles and shoes -- which would make every citizen
		# come out slightly short and mis-grounded depending on which options
		# happen to exist. The local flag, not is_visible_in_tree(): ModelRoot
		# is hidden while the player is stowed in a vehicle (set_stowed), and
		# measuring then would skip everything and warn.
		if not mesh_instance.visible:
			continue
		var relative := _relative_transform(mesh_instance, rig_root)
		for surface_index in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			for vertex in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var point: Vector3 = relative * vertex
				if not started:
					pre_scale_bounds = AABB(point, Vector3.ZERO)
					started = true
				else:
					pre_scale_bounds = pre_scale_bounds.expand(point)
	if not started:
		push_warning("Could not calculate %s mesh bounds for grounding." % _character_label)
		return

	var raw_height: float = maxf(pre_scale_bounds.size.y, 0.001)
	var scale_factor: float = TARGET_HEIGHT_METERS / raw_height
	rig_root.scale = Vector3.ONE * scale_factor

	_visual_bounds = AABB(
		pre_scale_bounds.position * scale_factor + rig_root.position,
		pre_scale_bounds.size * scale_factor
	)
	_has_visual_bounds = true
	_align_visual_to_capsule()


func _align_visual_to_capsule() -> void:
	if not _has_visual_bounds:
		push_warning("Could not calculate %s mesh bounds for grounding." % _character_label)
		return
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		push_warning("CBlock player does not have a capsule collision shape.")
		return
	var collision_bottom := collision_shape.position.y - capsule.height * 0.5
	model_root.position.y = (
		collision_bottom
		- _visual_bounds.position.y
		+ SOLE_CLEARANCE
	)
	var visual_foot_y := model_root.position.y + _visual_bounds.position.y
	_visual_foot_error = absf(visual_foot_y - (collision_bottom + SOLE_CLEARANCE))
	print(
		"CBLOCK_%s_GROUNDED foot_error=%.5f model_offset=%.5f"
		% [_character_label, _visual_foot_error, model_root.position.y]
	)


## ---------------------------------------------------------------------
## Animation install: prefer clips baked into the character GLB; otherwise
## retarget Mixamo FBX onto its skeleton by bone-name matching.
## ---------------------------------------------------------------------

func _install_animation_library() -> void:
	if _try_install_embedded_animations():
		# An embedded rig brings its own locomotion and combat but no emotes,
		# so those still come from the shared Mixamo FBXs. Without this,
		# Gusion would be the one character who cannot dance.
		_compute_root_motion_scale()
		_install_library("emote", MIXAMO_CLIPS["emote"])
		return
	_install_retargeted_mixamo_animations()


## Ratio between this rig's hips height and the source clips', so a retargeted
## vertical bob keeps its proportions on a taller or shorter character.
func _compute_root_motion_scale() -> void:
	var source_hips_rest_y := _mixamo_hips_rest_y(WALK_SCENE)
	var target_hips_index := _target_bone_index("Hips")
	var target_hips_rest_y: float = (
		_skeleton.get_bone_rest(target_hips_index).origin.y
		if target_hips_index >= 0
		else source_hips_rest_y
	)
	_root_motion_scale = target_hips_rest_y / maxf(absf(source_hips_rest_y), 0.0001)


func _try_install_embedded_animations() -> bool:
	for source_name in EMBEDDED_LOCOMOTION.values():
		if not _animation_player.has_animation(source_name):
			return false
	for source_name in EMBEDDED_COMBAT.values():
		if not _animation_player.has_animation(source_name):
			return false

	var locomotion := AnimationLibrary.new()
	for clip_name in EMBEDDED_LOCOMOTION.keys():
		var source_name: String = EMBEDDED_LOCOMOTION[clip_name]
		var clip := _animation_player.get_animation(source_name).duplicate() as Animation
		clip.loop_mode = Animation.LOOP_LINEAR
		locomotion.add_animation(clip_name, clip)
	if _animation_player.has_animation_library("locomotion"):
		_animation_player.remove_animation_library("locomotion")
	_animation_player.add_animation_library("locomotion", locomotion)

	var combat := AnimationLibrary.new()
	for clip_name in EMBEDDED_COMBAT.keys():
		var source_name: String = EMBEDDED_COMBAT[clip_name]
		var clip := _animation_player.get_animation(source_name).duplicate() as Animation
		clip.loop_mode = Animation.LOOP_NONE
		combat.add_animation(clip_name, clip)
	if _animation_player.has_animation_library("combat"):
		_animation_player.remove_animation_library("combat")
	_animation_player.add_animation_library("combat", combat)
	return true


## Pulls one Mixamo clip out of an imported FBX and hands back a copy.
##
## Duplicated before the temporary scene is freed: the Animation is a Resource
## owned by that scene's AnimationPlayer, and retargeting from a source whose
## root has already gone is how you get an empty library and a frozen T-pose.
func _mixamo_clip(scene: PackedScene) -> Animation:
	var root := scene.instantiate()
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip: Animation = null
	if player != null and player.has_animation(MIXAMO_CLIP_NAME):
		clip = player.get_animation(MIXAMO_CLIP_NAME).duplicate() as Animation
	root.free()
	return clip


## Hips rest height of a source FBX, for the root-motion scale.
func _mixamo_hips_rest_y(scene: PackedScene) -> float:
	var root := scene.instantiate()
	var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var value := 1.0
	if skeleton != null:
		var index := skeleton.find_bone("mixamorig1_Hips")
		if index >= 0:
			value = skeleton.get_bone_rest(index).origin.y
	root.free()
	return value


func _install_retargeted_mixamo_animations() -> void:
	_compute_root_motion_scale()
	for library_name in MIXAMO_CLIPS:
		_install_library(library_name, MIXAMO_CLIPS[library_name])

	if not _animation_player.has_animation("locomotion/idle"):
		push_error("Could not retarget the Mixamo locomotion clips.")


## Retargets one table of clip -> FBX into a named AnimationLibrary.
func _install_library(library_name: String, clips: Dictionary) -> void:
	var library := AnimationLibrary.new()
	for clip_name in clips:
		var source := _mixamo_clip(clips[clip_name])
		if source == null:
			push_warning("Missing Mixamo clip '%s' for %s" % [clip_name, library_name])
			continue
		var loops: bool = (
			library_name in LOOPING_LIBRARIES or clip_name in LOOPING_CLIPS
		)
		var loop_mode: Animation.LoopMode = (
			Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		)
		library.add_animation(clip_name, _retarget_clip(source, loop_mode, true))
	if library.get_animation_list().is_empty():
		return
	if _animation_player.has_animation_library(library_name):
		_animation_player.remove_animation_library(library_name)
	_animation_player.add_animation_library(library_name, library)


## Rebuilds an Animation with every track's bone re-pathed onto the selected
## skeleton. Rotation keys copy across untouched (rotation is scale-free);
## the Hips position track is rescaled by the two skeletons' height ratio so
## the vertical bob keeps its proportions, and horizontal drift is frozen so
## physics — not the clip — drives movement.
func _retarget_clip(
	source: Animation,
	loop_mode: Animation.LoopMode,
	freeze_horizontal_root: bool
) -> Animation:
	var result := Animation.new()
	result.length = source.length
	result.step = source.step
	result.loop_mode = loop_mode

	for track_index in source.get_track_count():
		var track_type := source.track_get_type(track_index)
		if (
			track_type != Animation.TYPE_POSITION_3D
			and track_type != Animation.TYPE_ROTATION_3D
			and track_type != Animation.TYPE_SCALE_3D
		):
			continue
		var source_path: NodePath = source.track_get_path(track_index)
		if source_path.get_subname_count() == 0:
			continue
		var bone_name := String(source_path.get_subname(source_path.get_subname_count() - 1))
		var core := _core_bone_name(bone_name)
		if not _bone_by_core.has(core):
			continue
		var target_bone_name: String = _bone_by_core[core]

		var new_track_index := result.add_track(track_type)
		result.track_set_path(new_track_index, NodePath(_track_path_prefix + target_bone_name))
		result.track_set_interpolation_type(
			new_track_index, source.track_get_interpolation_type(track_index)
		)

		var is_hips := core == "Hips" and track_type == Animation.TYPE_POSITION_3D
		var has_anchor := false
		var anchor_x := 0.0
		var anchor_z := 0.0
		for key_index in source.track_get_key_count(track_index):
			var time_value := source.track_get_key_time(track_index, key_index)
			var transition := source.track_get_key_transition(track_index, key_index)
			var value = source.track_get_key_value(track_index, key_index)
			if track_type == Animation.TYPE_POSITION_3D:
				var position_value: Vector3 = value
				if is_hips:
					if not has_anchor:
						anchor_x = position_value.x
						anchor_z = position_value.z
						has_anchor = true
					if freeze_horizontal_root:
						position_value.x = anchor_x
						position_value.z = anchor_z
				value = position_value * _root_motion_scale
			result.track_insert_key(new_track_index, time_value, value, transition)
	return result


func _set_animation(state: String) -> void:
	if _animation_player == null or _skeleton == null or state == _animation_state:
		return
	_animation_state = state
	match state:
		"idle":
			_animation_player.play("locomotion/idle", LOCOMOTION_CROSSFADE, 1.0)
		"walk":
			_animation_player.play(
				"locomotion/walk",
				LOCOMOTION_CROSSFADE,
				walk_speed / WALK_AUTHORED_SPEED
			)
		"sprint":
			_animation_player.play(
				"locomotion/sprint",
				LOCOMOTION_CROSSFADE - 0.02,
				sprint_speed / SPRINT_AUTHORED_SPEED
			)


func _trigger_attack(clip_name: String) -> void:
	# Mandatory, not tidiness: a held emote makes _update_animation return early
	# forever, so without this the LOOP_NONE punch would play once and then
	# freeze on its last frame permanently, with nothing left to hand the body
	# back to locomotion.
	_cancel_emote()
	_play_oneshot("combat/%s" % clip_name)


## Plays a clip that owns the body until it finishes, then hands control back
## to locomotion. Punches, the jump and the emotes are all this same thing --
## `_update_animation` simply refuses to run while the timer is live.
func _play_oneshot(full_name: String, crossfade := ATTACK_CROSSFADE) -> bool:
	if _animation_player == null or not _animation_player.has_animation(full_name):
		return false
	var clip: Animation = _animation_player.get_animation(full_name)
	_animation_player.play(full_name, crossfade, 1.0)
	_animation_state = ""
	_oneshot_time_remaining = clip.length + crossfade
	return true


## The looping twin of _play_oneshot: no timer, so the clip runs until
## _cancel_emote(). _update_animation refuses to run on _emote_index instead.
##
## Zeroing the timer matters: starting an emote on the tail of a punch would
## otherwise leave a countdown live under a clip that has no end, and when it
## expired locomotion would steal the body back mid-dance.
func _play_held(full_name: String, crossfade: float) -> bool:
	if _animation_player == null or not _animation_player.has_animation(full_name):
		return false
	_animation_player.play(full_name, crossfade, 1.0)
	_animation_state = ""
	_oneshot_time_remaining = 0.0
	return true


## Emotes are HELD performances. The key that starts one ends it, the other key
## switches to it, and anything the body does for itself -- walking, jumping,
## throwing a punch, getting into a car -- cancels it. They only START standing
## still on the ground, but they can always be STOPPED.
func _try_emote(index: int) -> void:
	if index < 0 or index >= EMOTES.size():
		return
	# Toggle-off is checked before the floor/stow gates on purpose: whatever
	# state the body has ended up in, the key that began the performance always
	# ends it.
	if _emote_index == index:
		_cancel_emote()
		return
	if not is_on_floor() or _stowed:
		return
	# Switching is implicit. Calling play() on the other emote mid-loop blends
	# from the live pose over EMOTE_CROSSFADE, so a switch is a crossfade rather
	# than a cut -- the same bar the wrap itself has to meet.
	if _play_held("emote/%s" % EMOTES[index]["clip"], EMOTE_CROSSFADE):
		_emote_index = index
		status_message.emit(String(EMOTES[index]["label"]).to_upper())


func _cancel_emote() -> void:
	if _emote_index < 0:
		return
	_emote_index = -1
	_oneshot_time_remaining = 0.0
	# Deliberately no stop()/play(): clearing the state is what makes the next
	# _update_animation crossfade into idle/walk rather than cut to it. No
	# status_message either -- this is reached from eight paths and would spam
	# the HUD every time the player stepped out of a dance.
	_animation_state = ""
