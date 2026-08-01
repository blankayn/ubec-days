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
const IDLE_SCENE := preload("res://animation mixamo/Idle.fbx")
const WALK_SCENE := preload("res://animation mixamo/Walking.fbx")
const SPRINT_SCENE := preload("res://animation mixamo/Sprint.fbx")
const PUNCH_LEFT_SCENE := preload("res://animation mixamo/Punchingleft.fbx")
const PUNCH_RIGHT_SCENE := preload("res://animation mixamo/Punchingright.fbx")
const HIT_SCENE := preload("res://animation mixamo/Hit To Body.fbx")

const CHARACTER_SCENES := {
	"gusion": GUSION_SCENE,
	"duterte": DUTERTE_SCENE,
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

var _attack_time_remaining := 0.0
var _punch_left_next := true
var _character_id := CharacterRoster.DEFAULT_ID
var _character_label := "Character"
var _controls_enabled := true
var _last_prompt := ""
var _interact_key_label := "E"


func _ready() -> void:
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	up_direction = Vector3.UP
	safe_margin = 0.02
	spring_arm.add_excluded_object(get_rid())
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
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
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
	if _attack_time_remaining > 0.0:
		_attack_time_remaining = maxf(_attack_time_remaining - delta, 0.0)

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
	if camera_rig == null:
		return
	camera_rig.global_position = global_position + Vector3.UP * camera_target_height
	camera_rig.global_rotation = Vector3(0.0, _camera_yaw, 0.0)
	spring_arm.rotation.x = _camera_pitch


func _update_animation(sprinting: bool) -> void:
	if _attack_time_remaining > 0.0:
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
	_attack_time_remaining = 0.0
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
		_set_prompt("")


## The first-person controller names this the other way round. Shared UI
## (dialogue_choice_ui.gd, vhs_system.gd) calls set_ui_locked on whichever
## player it was handed, so both controllers answer to both names.
func set_ui_locked(locked: bool) -> void:
	set_controls_enabled(not locked)


func is_ui_locked() -> bool:
	return not _controls_enabled


func get_character_id() -> String:
	return _character_id


func switch_character(character_id: String) -> void:
	if character_id == _character_id and _skeleton != null:
		status_message.emit("%s ALREADY SELECTED" % _character_label)
		return
	CharacterRoster.set_selected(character_id)
	_attack_time_remaining = 0.0
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
	_scale_and_align_visual(rig_root)
	_animation_state = ""
	_set_animation("idle")
	set_meta("idle_animation_loaded", _animation_player.has_animation("locomotion/idle"))
	set_meta("visual_foot_error", _visual_foot_error)
	set_meta("player_character", _character_id)
	status_message.emit("%s READY  //  Idle + Walk + Sprint + Combat" % _character_label)


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


## Scales the whole rig to a human-sized height and plants its feet on the
## capsule bottom.
func _scale_and_align_visual(rig_root: Node3D) -> void:
	var pre_scale_bounds := AABB()
	var started := false
	for mesh_node in rig_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
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
		return
	_install_retargeted_mixamo_animations()


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


func _install_retargeted_mixamo_animations() -> void:
	var walk_root := WALK_SCENE.instantiate()
	var idle_root := IDLE_SCENE.instantiate()
	var sprint_root := SPRINT_SCENE.instantiate()
	var punch_left_root := PUNCH_LEFT_SCENE.instantiate()
	var punch_right_root := PUNCH_RIGHT_SCENE.instantiate()
	var hit_root := HIT_SCENE.instantiate()
	var temp_roots: Array = [
		walk_root, idle_root, sprint_root, punch_left_root, punch_right_root, hit_root
	]

	var walk_skeleton := walk_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var walk_player := walk_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var idle_player := idle_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sprint_player := sprint_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var punch_left_player := (
		punch_left_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	)
	var punch_right_player := (
		punch_right_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	)
	var hit_player := hit_root.find_child("AnimationPlayer", true, false) as AnimationPlayer

	var walk_source := walk_player.get_animation("mixamo_com") if walk_player else null
	var idle_source := idle_player.get_animation("mixamo_com") if idle_player else null
	var sprint_source := sprint_player.get_animation("mixamo_com") if sprint_player else null
	var punch_left_source := (
		punch_left_player.get_animation("mixamo_com") if punch_left_player else null
	)
	var punch_right_source := (
		punch_right_player.get_animation("mixamo_com") if punch_right_player else null
	)
	var hit_source := hit_player.get_animation("mixamo_com") if hit_player else null

	if walk_skeleton == null or walk_source == null or idle_source == null or sprint_source == null:
		push_error("Could not find Idle/Walking/Sprint source clips.")
		for temp_root in temp_roots:
			temp_root.free()
		return

	var source_hips_index := walk_skeleton.find_bone("mixamorig1_Hips")
	var source_hips_rest_y: float = (
		walk_skeleton.get_bone_rest(source_hips_index).origin.y
		if source_hips_index >= 0
		else 1.0
	)
	var target_hips_index := _target_bone_index("Hips")
	var target_hips_rest_y: float = (
		_skeleton.get_bone_rest(target_hips_index).origin.y
		if target_hips_index >= 0
		else source_hips_rest_y
	)
	_root_motion_scale = target_hips_rest_y / maxf(absf(source_hips_rest_y), 0.0001)

	var locomotion := AnimationLibrary.new()
	locomotion.add_animation("idle", _retarget_clip(idle_source, Animation.LOOP_LINEAR, true))
	locomotion.add_animation("walk", _retarget_clip(walk_source, Animation.LOOP_LINEAR, true))
	locomotion.add_animation("sprint", _retarget_clip(sprint_source, Animation.LOOP_LINEAR, true))
	if _animation_player.has_animation_library("locomotion"):
		_animation_player.remove_animation_library("locomotion")
	_animation_player.add_animation_library("locomotion", locomotion)

	var combat := AnimationLibrary.new()
	if punch_left_source != null:
		combat.add_animation(
			"punch_left", _retarget_clip(punch_left_source, Animation.LOOP_NONE, true)
		)
	if punch_right_source != null:
		combat.add_animation(
			"punch_right", _retarget_clip(punch_right_source, Animation.LOOP_NONE, true)
		)
	if hit_source != null:
		combat.add_animation("hit", _retarget_clip(hit_source, Animation.LOOP_NONE, true))
	if _animation_player.has_animation_library("combat"):
		_animation_player.remove_animation_library("combat")
	_animation_player.add_animation_library("combat", combat)

	for temp_root in temp_roots:
		temp_root.free()


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
	var full_name := "combat/%s" % clip_name
	if _animation_player == null or not _animation_player.has_animation(full_name):
		return
	var clip: Animation = _animation_player.get_animation(full_name)
	_animation_player.play(full_name, ATTACK_CROSSFADE, 1.0)
	_animation_state = ""
	_attack_time_remaining = clip.length + ATTACK_CROSSFADE
