extends Node3D
class_name PlayerCharacterVisual
## Skinned third-person body from testplayer1.glb — idle / walk / run / punch.

const CHARACTER_PATH := "res://assets/player/testplayer1.glb"

const CLIP_IDLE := &"Idle"
const CLIP_WALK := &"Walk"
const CLIP_RUN := &"Run"
const CLIP_PUNCH_CUSTOM := &"Punch"
const CLIP_PUNCH_FALLBACK := &"Hit"

enum Locomotion { IDLE, WALK, RUN }

@export var target_height := 1.78
@export var model_yaw_degrees := 180.0
@export var walk_reference_speed := 4.6
@export var run_reference_speed := 7.2

var _visual_model: Node3D
var _animation_player: AnimationPlayer
var _skeleton: Skeleton3D
var _hip_bone := -1
var _hip_rest_pose := Transform3D.IDENTITY
var _visual_base_position := Vector3.ZERO

var _idle_anim := CLIP_IDLE
var _walk_anim := CLIP_WALK
var _run_anim := CLIP_RUN
var _punch_anim := CLIP_PUNCH_FALLBACK
var _locomotion := Locomotion.IDLE
var _current_anim := &""
var _attacking := false
var _attack_timeout := 0.0
var _built := false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	var packed := load(CHARACTER_PATH) as PackedScene
	if packed == null:
		push_error("PlayerCharacterVisual: could not load %s" % CHARACTER_PATH)
		return
	_visual_model = packed.instantiate() as Node3D
	if _visual_model == null:
		push_error("PlayerCharacterVisual: could not instantiate GLB")
		return
	_built = true
	_visual_model.name = "TestPlayerModel"
	_visual_model.rotation_degrees.y = model_yaw_degrees
	add_child(_visual_model)
	_strip_non_character_nodes(_visual_model)
	_prepare_visuals(_visual_model)
	_cache_animation_player()
	_strip_root_translation_tracks()
	_cache_hip_rest()
	_install_custom_punch_animation()
	_fit_character_scale()
	_visual_base_position = _visual_model.position
	_play_locomotion(Locomotion.IDLE, true)


func is_attacking() -> bool:
	return _attacking


func try_punch() -> bool:
	if _attacking or _animation_player == null:
		return false
	_attacking = true
	_play_clip(_punch_anim, false)
	var punch_clip := _animation_player.get_animation(_punch_anim)
	_attack_timeout = punch_clip.length + 0.2 if punch_clip != null else 0.8
	return true


func update_locomotion(horizontal_speed: float, sprinting: bool, moving: bool) -> void:
	if _attacking or _animation_player == null:
		return
	var next := Locomotion.IDLE
	if moving and horizontal_speed > 0.12:
		next = Locomotion.RUN if sprinting else Locomotion.WALK
	if next != _locomotion:
		_play_locomotion(next, false)
	match next:
		Locomotion.WALK:
			_animation_player.speed_scale = clampf(horizontal_speed / walk_reference_speed, 0.72, 1.2)
		Locomotion.RUN:
			_animation_player.speed_scale = clampf(horizontal_speed / run_reference_speed, 0.78, 1.2)
		_:
			_animation_player.speed_scale = 1.0


func _play_locomotion(mode: Locomotion, force: bool) -> void:
	_locomotion = mode
	var clip := _idle_anim
	match mode:
		Locomotion.WALK:
			clip = _walk_anim
		Locomotion.RUN:
			clip = _run_anim
	if force or clip != _current_anim:
		_play_clip(clip, true)


func _play_clip(anim_name: StringName, loop: bool) -> void:
	if _animation_player == null or anim_name == &"":
		return
	if not _animation_player.has_animation(anim_name):
		return
	_animation_player.active = true
	var anim := _animation_player.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if _current_anim == anim_name and _animation_player.is_playing() and loop:
		return
	_current_anim = anim_name
	_animation_player.speed_scale = 1.0
	var blend_time := 0.04 if anim_name == CLIP_PUNCH_CUSTOM else 0.1
	_animation_player.play(anim_name, blend_time)


func _on_attack_finished(anim_name: StringName) -> void:
	if anim_name != _punch_anim:
		return
	_finish_attack()


func _finish_attack() -> void:
	if not _attacking:
		return
	_attacking = false
	_attack_timeout = 0.0
	_play_locomotion(_locomotion, true)


func _process(delta: float) -> void:
	if not _built or not is_instance_valid(_visual_model):
		return
	_visual_model.position = _visual_base_position
	_pin_hip_translation()
	if _attacking:
		_attack_timeout -= delta
		if _attack_timeout <= 0.0:
			_finish_attack()


func _cache_animation_player() -> void:
	_animation_player = _find_animation_player(_visual_model)
	if _animation_player == null:
		push_warning("PlayerCharacterVisual: no AnimationPlayer")
		return
	if not _animation_player.animation_finished.is_connected(_on_attack_finished):
		_animation_player.animation_finished.connect(_on_attack_finished)
	_idle_anim = _resolve_clip([CLIP_IDLE], ["idle"])
	_walk_anim = _resolve_clip([CLIP_WALK], ["walk"])
	_run_anim = _resolve_clip([CLIP_RUN], ["run"])
	if _animation_player.has_animation(CLIP_PUNCH_FALLBACK):
		_punch_anim = CLIP_PUNCH_FALLBACK
	else:
		_punch_anim = _resolve_clip([], ["hit", "attack", "punch"])


func _install_custom_punch_animation() -> void:
	if _animation_player == null or _skeleton == null or not _animation_player.has_animation(CLIP_IDLE):
		return
	var idle := _animation_player.get_animation(CLIP_IDLE)
	var tracked_bones := [
		"Spine01", "Spine02",
		"R_Clavicle", "R_Upperarm", "R_Forearm",
		"L_Clavicle", "L_Upperarm", "L_Forearm",
	]
	var paths: Dictionary = {}
	var base_rotations: Dictionary = {}
	for track_index in idle.get_track_count():
		if idle.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue
		var path := idle.track_get_path(track_index)
		if path.get_subname_count() <= 0:
			continue
		var bone_name := String(path.get_subname(0))
		base_rotations[bone_name] = idle.rotation_track_interpolate(track_index, 0.0)
		if bone_name in tracked_bones:
			paths[bone_name] = path
	if not base_rotations.has("R_Upperarm") or not base_rotations.has("R_Forearm"):
		return

	var windup_rotations := base_rotations.duplicate()
	var windup_spine: Quaternion = windup_rotations.get("Spine02", Quaternion.IDENTITY)
	windup_rotations["Spine02"] = windup_spine * Quaternion(Vector3.UP, deg_to_rad(8.0))
	var strike_rotations := base_rotations.duplicate()
	var spine_rotation: Quaternion = strike_rotations.get("Spine02", Quaternion.IDENTITY)
	strike_rotations["Spine02"] = spine_rotation * Quaternion(Vector3.UP, deg_to_rad(-22.0))
	var punch_direction := Vector3(0.5, -0.42, 1.0).normalized()
	strike_rotations["R_Upperarm"] = _pose_bone_toward(
		_skeleton.find_bone("R_Upperarm"),
		punch_direction,
		strike_rotations
	)
	strike_rotations["R_Forearm"] = _pose_bone_toward(
		_skeleton.find_bone("R_Forearm"),
		punch_direction,
		strike_rotations
	)

	var punch := Animation.new()
	punch.length = 0.46
	punch.loop_mode = Animation.LOOP_NONE
	for bone_name in tracked_bones:
		if not paths.has(bone_name) or not base_rotations.has(bone_name):
			continue
		var track := punch.add_track(Animation.TYPE_ROTATION_3D)
		punch.track_set_path(track, paths[bone_name])
		var base: Quaternion = base_rotations[bone_name]
		var windup: Quaternion = windup_rotations.get(bone_name, base)
		var strike: Quaternion = strike_rotations.get(bone_name, base)
		punch.rotation_track_insert_key(track, 0.0, base)
		punch.rotation_track_insert_key(track, 0.07, windup)
		punch.rotation_track_insert_key(track, 0.16, strike)
		punch.rotation_track_insert_key(track, 0.23, strike)
		punch.rotation_track_insert_key(track, 0.46, base)

	var library := _animation_player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		_animation_player.add_animation_library(&"", library)
	if library.has_animation(CLIP_PUNCH_CUSTOM):
		library.remove_animation(CLIP_PUNCH_CUSTOM)
	library.add_animation(CLIP_PUNCH_CUSTOM, punch)
	_punch_anim = CLIP_PUNCH_CUSTOM


func _pose_bone_toward(bone_index: int, direction: Vector3, pose_rotations: Dictionary) -> Quaternion:
	if bone_index < 0:
		return Quaternion.IDENTITY
	var parent_index := _skeleton.get_bone_parent(bone_index)
	var parent_global := Transform3D.IDENTITY
	if parent_index >= 0:
		parent_global = _bone_global_pose_from_rotations(parent_index, pose_rotations)
	var current_global := _bone_global_pose_from_rotations(bone_index, pose_rotations)
	var target_y := direction.normalized()
	var target_x := current_global.basis.x - target_y * target_y.dot(current_global.basis.x)
	if target_x.length_squared() < 0.001:
		target_x = Vector3.RIGHT
	target_x = target_x.normalized()
	var target_z := target_x.cross(target_y).normalized()
	target_x = target_y.cross(target_z).normalized()
	var desired_global_basis := Basis(target_x, target_y, target_z)
	var desired_local_basis := parent_global.basis.inverse() * desired_global_basis
	var rest_basis := _skeleton.get_bone_rest(bone_index).basis
	return Quaternion((rest_basis.inverse() * desired_local_basis).orthonormalized())


func _bone_global_pose_from_rotations(bone_index: int, pose_rotations: Dictionary) -> Transform3D:
	var bone_name := _skeleton.get_bone_name(bone_index)
	var pose_rotation: Quaternion = pose_rotations.get(bone_name, Quaternion.IDENTITY)
	var local_pose := _skeleton.get_bone_rest(bone_index) * Transform3D(Basis(pose_rotation), Vector3.ZERO)
	var parent_index := _skeleton.get_bone_parent(bone_index)
	if parent_index < 0:
		return local_pose
	return _bone_global_pose_from_rotations(parent_index, pose_rotations) * local_pose


func _resolve_clip(exact: Array[StringName], terms: Array[String]) -> StringName:
	for name in exact:
		if _animation_player.has_animation(name):
			return name
	for animation_name in _animation_player.get_animation_list():
		var normalized := String(animation_name).to_lower()
		if normalized == "reset":
			continue
		for term in terms:
			if normalized == term or normalized.contains(term):
				return animation_name
	return _animation_player.get_animation_list()[0] if _animation_player.get_animation_list().size() > 0 else &""


func _strip_root_translation_tracks() -> void:
	if _animation_player == null:
		return
	for animation_name in _animation_player.get_animation_list():
		var anim := _animation_player.get_animation(animation_name)
		if anim == null:
			continue
		for track_index in range(anim.get_track_count() - 1, -1, -1):
			if anim.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
				continue
			var path := String(anim.track_get_path(track_index)).to_lower()
			if path.contains("hip") or path.contains(":root") or path.ends_with("root"):
				anim.remove_track(track_index)


func _cache_hip_rest() -> void:
	_skeleton = _visual_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		return
	for bone_name in ["Hip", "Root", "pelvis", "mixamorig:Hips"]:
		_hip_bone = _skeleton.find_bone(bone_name)
		if _hip_bone >= 0:
			break
	if _hip_bone < 0:
		return
	_hip_rest_pose = _skeleton.get_bone_rest(_hip_bone)


func _pin_hip_translation() -> void:
	if _skeleton == null or _hip_bone < 0:
		return
	var pose := _skeleton.get_bone_pose(_hip_bone)
	pose.origin = _hip_rest_pose.origin
	_skeleton.set_bone_pose_position(_hip_bone, pose.origin)


func _fit_character_scale() -> void:
	var bounds := _merged_mesh_aabb(_visual_model)
	var height := bounds.size.y
	if height < 0.001:
		return
	var scale_factor := target_height / height
	_visual_model.scale = Vector3.ONE * scale_factor
	bounds = _merged_mesh_aabb(_visual_model)
	var feet_y := bounds.position.y
	if absf(feet_y) > 0.02:
		_visual_model.position.y -= feet_y
		_visual_base_position = _visual_model.position


func _merged_mesh_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var has_bounds := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_aabb := mesh_instance.get_aabb()
		var to_root := root.global_transform.affine_inverse() * mesh_instance.global_transform
		var root_aabb := to_root * local_aabb
		if not has_bounds:
			merged = root_aabb
			has_bounds = true
		else:
			merged = merged.merge(root_aabb)
	return merged if has_bounds else AABB(Vector3.ZERO, Vector3.ONE)


func _strip_non_character_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is Light3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_non_character_nodes(child)


func _prepare_visuals(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.get_active_material(surface_index)
				if source_material == null:
					continue
				var material := source_material.duplicate(true)
				if material is BaseMaterial3D:
					var base_material := material as BaseMaterial3D
					base_material.metallic = 0.0
					base_material.roughness = maxf(base_material.roughness, 0.82)
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_prepare_visuals(child)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
