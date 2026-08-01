extends CharacterBody3D
## CBlock-only Edward pedestrian. Edward keeps his original Tripo skin and
## skeleton while Mixamo Idle/Walk motion is retargeted through an explicit
## semantic bone map with rest-pose correction.

const EDWARD_SCENE := preload("res://assets/npcs/edward.glb")
const IDLE_SCENE := preload("res://assets/characters/gusion/source/Idle.fbx")
const WALK_SCENE := preload("res://assets/characters/gusion/source/Walking.fbx")

const TARGET_HEIGHT_METERS := 1.78
const SOLE_CLEARANCE := 0.018
const WALK_AUTHORED_SPEED := 1.715
const PATROL_OFFSETS := [
	Vector3.ZERO,
	Vector3(24.0, 0.0, 0.0),
]

const BONE_MAP := {
	"Hips": "Pelvis",
	"Spine": "Waist",
	"Spine1": "Spine01",
	"Spine2": "Spine02",
	"Neck": "NeckTwist01",
	"Head": "Head",
	"LeftShoulder": "L_Clavicle",
	"LeftArm": "L_Upperarm",
	"LeftForeArm": "L_Forearm",
	"LeftHand": "L_Hand",
	"RightShoulder": "R_Clavicle",
	"RightArm": "R_Upperarm",
	"RightForeArm": "R_Forearm",
	"RightHand": "R_Hand",
	"LeftUpLeg": "L_Thigh",
	"LeftLeg": "L_Calf",
	"LeftFoot": "L_Foot",
	"LeftToeBase": "L_ToeBase",
	"RightUpLeg": "R_Thigh",
	"RightLeg": "R_Calf",
	"RightFoot": "R_Foot",
	"RightToeBase": "R_ToeBase",
}

@export var patrol_speed := 1.4
@export var acceleration := 7.0
@export var turn_speed := 6.0
@export var endpoint_pause := 2.4

## Optional world-space patrol. When set before add_child / _ready, replaces
## the default offset loop so Banilad (and other maps) can walk the avenue.
var custom_waypoints: Array[Vector3] = []

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model_root: Node3D = $ModelRoot

var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _track_path_prefix := ""
var _rig_scale_factor := 1.0
var _root_motion_scale := 1.0
var _animation_state := ""
var _waypoints: Array[Vector3] = []
var _waypoint_index := 1
var _wait_remaining := 1.5
var _visual_foot_error := INF


func _ready() -> void:
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(48.0)
	floor_stop_on_slope = true
	up_direction = Vector3.UP
	safe_margin = 0.02
	if custom_waypoints.is_empty():
		for offset in PATROL_OFFSETS:
			_waypoints.append(global_position + offset)
	else:
		_waypoints = custom_waypoints.duplicate()
	_build_edward()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= float(
			ProjectSettings.get_setting("physics/3d/default_gravity")
		) * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if _animation_player == null or _waypoints.is_empty():
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	if _wait_remaining > 0.0:
		_wait_remaining = maxf(_wait_remaining - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_set_animation("idle")
	else:
		var target := _waypoints[_waypoint_index]
		var direction := Vector3(
			target.x - global_position.x,
			0.0,
			target.z - global_position.z
		)
		if direction.length() < 0.45:
			_waypoint_index = (_waypoint_index + 1) % _waypoints.size()
			_wait_remaining = endpoint_pause
			velocity.x = 0.0
			velocity.z = 0.0
			_set_animation("idle")
		else:
			direction = direction.normalized()
			velocity.x = move_toward(
				velocity.x,
				direction.x * patrol_speed,
				acceleration * delta
			)
			velocity.z = move_toward(
				velocity.z,
				direction.z * patrol_speed,
				acceleration * delta
			)
			var target_yaw := atan2(-direction.x, -direction.z)
			rotation.y = lerp_angle(
				rotation.y,
				target_yaw,
				minf(turn_speed * delta, 1.0)
			)
			_set_animation("walk")

	move_and_slide()


func _build_edward() -> void:
	var rig_root := EDWARD_SCENE.instantiate() as Node3D
	rig_root.name = "EdwardMixamoRig"
	model_root.add_child(rig_root)
	_skeleton = rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	_animation_player = rig_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton == null or _animation_player == null:
		push_error("CBlock Edward is missing its Tripo skeleton or AnimationPlayer.")
		return
	if not _validate_target_bones():
		return

	var animation_root: Node = _animation_player.get_node(_animation_player.root_node)
	_track_path_prefix = String(animation_root.get_path_to(_skeleton)) + ":"
	_scale_and_ground(rig_root)
	_install_mixamo_library()
	_set_animation("idle")
	set_meta("npc_character", "edward")
	set_meta("uses_mixamo_animation", true)
	set_meta("visual_foot_error", _visual_foot_error)
	print(
		"CBLOCK_EDWARD_NPC_READY bones=%d mixamo=true foot_error=%.5f"
		% [_skeleton.get_bone_count(), _visual_foot_error]
	)


func _validate_target_bones() -> bool:
	var missing: Array[String] = []
	for core_name in BONE_MAP:
		var target_name: String = BONE_MAP[core_name]
		if _skeleton.find_bone(target_name) < 0:
			missing.append(target_name)
	if missing.is_empty():
		return true
	push_error("CBlock Edward is missing Tripo bones: %s" % ", ".join(missing))
	return false


func _scale_and_ground(rig_root: Node3D) -> void:
	var bounds := AABB()
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
					bounds = AABB(point, Vector3.ZERO)
					started = true
				else:
					bounds = bounds.expand(point)
	if not started:
		push_error("Could not calculate Edward mesh bounds.")
		return

	_rig_scale_factor = TARGET_HEIGHT_METERS / maxf(bounds.size.y, 0.001)
	_root_motion_scale = 1.0 / maxf(_rig_scale_factor, 0.001)
	rig_root.scale = Vector3.ONE * _rig_scale_factor
	var scaled_min_y := bounds.position.y * _rig_scale_factor + rig_root.position.y
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		push_error("CBlock Edward requires a capsule collision shape.")
		return
	var collision_bottom := collision_shape.position.y - capsule.height * 0.5
	model_root.position.y = collision_bottom - scaled_min_y + SOLE_CLEARANCE
	var visual_foot_y := model_root.position.y + scaled_min_y
	_visual_foot_error = absf(
		visual_foot_y - (collision_bottom + SOLE_CLEARANCE)
	)


func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D()
	var current := node
	while current != null and current != ancestor:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result


func _install_mixamo_library() -> void:
	var idle_root := IDLE_SCENE.instantiate()
	var walk_root := WALK_SCENE.instantiate()
	var idle_skeleton := idle_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var walk_skeleton := walk_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var idle_player := idle_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var walk_player := walk_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var idle_source := (
		idle_player.get_animation("mixamo_com")
		if idle_player != null
		else null
	)
	var walk_source := (
		walk_player.get_animation("mixamo_com")
		if walk_player != null
		else null
	)
	if (
		idle_skeleton == null
		or walk_skeleton == null
		or idle_source == null
		or walk_source == null
	):
		push_error("Could not load Mixamo Idle/Walk for Edward.")
		idle_root.free()
		walk_root.free()
		return

	var library := AnimationLibrary.new()
	library.add_animation(
		"idle",
		_retarget_clip(idle_source, idle_skeleton)
	)
	library.add_animation(
		"walk",
		_retarget_clip(walk_source, walk_skeleton)
	)
	if _animation_player.has_animation_library("mixamo"):
		_animation_player.remove_animation_library("mixamo")
	_animation_player.add_animation_library("mixamo", library)
	idle_root.free()
	walk_root.free()


func _retarget_clip(source: Animation, source_skeleton: Skeleton3D) -> Animation:
	var result := Animation.new()
	result.length = source.length
	result.step = source.step
	result.loop_mode = Animation.LOOP_LINEAR

	for track_index in source.get_track_count():
		var track_type := source.track_get_type(track_index)
		if (
			track_type != Animation.TYPE_POSITION_3D
			and track_type != Animation.TYPE_ROTATION_3D
		):
			continue
		var source_path: NodePath = source.track_get_path(track_index)
		if source_path.get_subname_count() == 0:
			continue
		var source_bone_name := String(
			source_path.get_subname(source_path.get_subname_count() - 1)
		)
		var core_name := _mixamo_core_name(source_bone_name)
		var target_bone_name := ""
		if track_type == Animation.TYPE_POSITION_3D:
			if core_name != "Hips":
				continue
			target_bone_name = "Root"
		elif BONE_MAP.has(core_name):
			target_bone_name = String(BONE_MAP[core_name])
		if target_bone_name.is_empty():
			continue

		var source_bone_index := source_skeleton.find_bone(source_bone_name)
		var target_bone_index := _skeleton.find_bone(target_bone_name)
		if source_bone_index < 0 or target_bone_index < 0:
			continue
		var source_rest := source_skeleton.get_bone_rest(source_bone_index)
		var target_rest := _skeleton.get_bone_rest(target_bone_index)

		var new_track_index := result.add_track(track_type)
		result.track_set_path(
			new_track_index,
			NodePath(_track_path_prefix + target_bone_name)
		)
		result.track_set_interpolation_type(
			new_track_index,
			source.track_get_interpolation_type(track_index)
		)

		var position_anchor := Vector3.ZERO
		if (
			track_type == Animation.TYPE_POSITION_3D
			and source.track_get_key_count(track_index) > 0
		):
			position_anchor = source.track_get_key_value(track_index, 0)

		for key_index in source.track_get_key_count(track_index):
			var value = source.track_get_key_value(track_index, key_index)
			if track_type == Animation.TYPE_POSITION_3D:
				var motion_delta: Vector3 = (value as Vector3) - position_anchor
				motion_delta.x = 0.0
				motion_delta.z = 0.0
				value = target_rest.origin + motion_delta * _root_motion_scale
			else:
				var source_animated_basis := Basis(
					value as Quaternion
				).orthonormalized()
				var source_rest_basis := source_rest.basis.orthonormalized()
				var target_rest_basis := target_rest.basis.orthonormalized()
				var local_motion := (
					source_rest_basis.inverse() * source_animated_basis
				)
				value = (
					target_rest_basis * local_motion
				).get_rotation_quaternion().normalized()
			result.track_insert_key(
				new_track_index,
				source.track_get_key_time(track_index, key_index),
				value,
				source.track_get_key_transition(track_index, key_index)
			)
	return result


func _mixamo_core_name(bone_name: String) -> String:
	if bone_name.begins_with("mixamorig1_"):
		return bone_name.substr("mixamorig1_".length())
	if bone_name.begins_with("mixamorig_"):
		return bone_name.substr("mixamorig_".length())
	return ""


func _set_animation(state: String) -> void:
	if _animation_player == null or state == _animation_state:
		return
	var full_name := "mixamo/" + state
	if not _animation_player.has_animation(full_name):
		return
	_animation_state = state
	var playback_speed := (
		patrol_speed / WALK_AUTHORED_SPEED
		if state == "walk"
		else 1.0
	)
	_animation_player.play(full_name, 0.2, playback_speed)
