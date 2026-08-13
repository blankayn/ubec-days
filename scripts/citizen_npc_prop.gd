extends Node3D
class_name CitizenNpcProp
## A pedestrian built from `assets/characters/citizen/citizen.glb`.
##
## Structurally this is `police_npc_prop.gd` -- same skeleton lookup, same
## toe-bone-derived facing, same Mixamo re-path -- with one addition: the look
## is chosen by CitizenAppearance before the rig is scaled, so a street can be
## filled with visibly different people from one GLB.
##
## Deliberately NOT a crowd system. CITY_MASTER_PLAN.md §7.5 specifies a
## pedestrian graph derived from road-graph sidewalk offsets and a pool of ~60
## instances that never allocates at runtime, plus NavigationAgent3D and RVO
## avoidance. None of that exists yet. This is the UNIT that pool will hold:
## the body, the appearance, and a hand-authored waypoint walk, so pedestrians
## can be placed and measured before the graph is built.
##
## Appearance comes from `appearance_seed` unless an explicit `appearance` is
## assigned. Seeded rather than random so a street is reproducible run to run --
## which is what makes a bad-looking pedestrian traceable back to its seed.

const MODEL_PATH := "res://assets/characters/citizen/citizen.glb"
const IDLE_SCENE := preload("res://animation mixamo/Idle.fbx")
const WALK_SCENE := preload("res://animation mixamo/Walking.fbx")

## Mixamo exports every clip under this single track name.
const SOURCE_CLIP := "mixamo_com"
## Rest height of the authored mesh, metres. Matches citizen_manifest.json's
## authored_height_m; used to derive the display scale.
const AUTHORED_HEIGHT := 1.7636

@export var build_on_ready := true
@export var target_height := 1.74
@export var collision_enabled := true
@export var cast_shadow := true
## Any non-zero value picks a deterministic look. 0 means "use the default".
@export var appearance_seed := 0
## Explicit override; wins over appearance_seed when set.
@export var appearance: CitizenAppearance = null

## Walk route in world space. Empty means the citizen stands still.
@export var waypoints: PackedVector3Array = PackedVector3Array()
@export var walk_speed := 1.25

var _visual_model: Node3D = null
var _skeleton: Skeleton3D = null
var _animation_player: AnimationPlayer = null
var _collision_body: StaticBody3D = null
var _built := false
var _target_index := 0
var _walking := false


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("CitizenNpcProp could not load %s (reimport it in Godot)" % MODEL_PATH)
		return
	_visual_model = packed.instantiate() as Node3D
	if _visual_model == null:
		push_error("CitizenNpcProp could not instantiate %s" % MODEL_PATH)
		return
	_built = true
	_visual_model.name = "CitizenModel"
	add_child(_visual_model)

	_skeleton = _visual_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		push_error("CitizenNpcProp: %s has no Skeleton3D" % MODEL_PATH)
		return

	# Before _apply_scale: citizen.glb ships every clothing and hair option as a
	# sibling mesh, and anything that measures the rig has to see the resolved
	# wardrobe rather than all of it at once.
	_resolve_appearance().apply(_visual_model)

	_apply_scale()
	_face_authored_forward()
	_prepare_visuals()
	_install_animations()
	_build_collision()
	if not waypoints.is_empty():
		play_walk()


func _resolve_appearance() -> CitizenAppearance:
	if appearance != null:
		return appearance
	if appearance_seed != 0:
		appearance = CitizenAppearance.random_from_seed(appearance_seed)
	else:
		appearance = CitizenAppearance.default()
	return appearance


func set_appearance(value: CitizenAppearance) -> void:
	if value == null or _visual_model == null:
		return
	appearance = value
	_visual_model.scale = Vector3.ONE
	value.apply(_visual_model)
	_apply_scale()


func get_visual_model() -> Node3D:
	return _visual_model


func set_route(points: PackedVector3Array) -> void:
	waypoints = points
	_target_index = 0
	if _built:
		play_walk() if not points.is_empty() else play_idle()


func play_idle() -> void:
	_walking = false
	if _animation_player != null and _animation_player.has_animation("locomotion/idle"):
		_animation_player.play("locomotion/idle")


func play_walk() -> void:
	if _animation_player == null or not _animation_player.has_animation("locomotion/walk"):
		return
	_walking = true
	_animation_player.play("locomotion/walk")


func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	if is_instance_valid(_collision_body):
		_collision_body.collision_layer = 1 if enabled else 0
		_collision_body.collision_mask = 0


func _physics_process(delta: float) -> void:
	if not _walking or waypoints.is_empty():
		return
	var target := waypoints[_target_index]
	var flat_target := Vector3(target.x, global_position.y, target.z)
	var to_target := flat_target - global_position
	if to_target.length() < 0.35:
		_target_index = (_target_index + 1) % waypoints.size()
		return
	var step := to_target.normalized() * walk_speed * delta
	global_position += step
	# Face along the route. -Z is forward for every consumer here, which is what
	# _face_authored_forward corrects the model to.
	look_at(flat_target, Vector3.UP)


func _apply_scale() -> void:
	_visual_model.scale = Vector3.ONE * (target_height / AUTHORED_HEIGHT)


func _face_authored_forward() -> void:
	# The rig faces +Z after Blender's glTF Y-up conversion, but everything here
	# treats -Z as forward. Measured from the rig rather than hardcoded: the toe
	# bone sits in front of the hips, which is all "forward" means for a
	# humanoid.
	var hips := _skeleton.find_bone("mixamorig1_Hips")
	var toe := _skeleton.find_bone("mixamorig1_LeftToeBase")
	if hips < 0 or toe < 0:
		_visual_model.rotation.y = PI
		return
	if _skeleton.get_bone_global_rest(toe).origin.z > _skeleton.get_bone_global_rest(hips).origin.z:
		_visual_model.rotation.y = PI


func _prepare_visuals() -> void:
	for node in _visual_model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)


func _install_animations() -> void:
	_animation_player = AnimationPlayer.new()
	_animation_player.name = "AnimationPlayer"
	add_child(_animation_player)
	_animation_player.root_node = _animation_player.get_path_to(self)

	var library := AnimationLibrary.new()
	var idle := _retarget(IDLE_SCENE, true)
	if idle != null:
		library.add_animation("idle", idle)
	var walk := _retarget(WALK_SCENE, true)
	if walk != null:
		library.add_animation("walk", walk)
	if library.get_animation_list().size() == 0:
		push_error("CitizenNpcProp: no Mixamo clips could be retargeted")
		return
	_animation_player.add_animation_library("locomotion", library)
	play_idle()


## Copies one Mixamo clip onto this citizen's skeleton. Source and target bones
## are named identically -- the body is skinned onto the Mixamo armature itself
## -- so tracks only need their node path swapped. `freeze_horizontal_root`
## pins the hips in X/Z, because the walk cycle's own drift would otherwise
## slide the citizen off the sidewalk on top of the waypoint motion.
func _retarget(scene: PackedScene, freeze_horizontal_root: bool) -> Animation:
	var source_root := scene.instantiate()
	var source_player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if source_player == null or not source_player.has_animation(SOURCE_CLIP):
		source_root.free()
		return null
	var result := _retarget_animation(
		source_player.get_animation(SOURCE_CLIP), freeze_horizontal_root
	)
	source_root.free()
	return result


func _retarget_animation(source: Animation, freeze_horizontal_root: bool) -> Animation:
	if source == null:
		return null
	var prefix := String(get_path_to(_skeleton)) + ":"
	var result := Animation.new()
	result.length = source.length
	result.step = source.step
	result.loop_mode = Animation.LOOP_LINEAR

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
		if _skeleton.find_bone(bone_name) < 0:
			continue

		var new_track := result.add_track(track_type)
		result.track_set_path(new_track, NodePath(prefix + bone_name))
		result.track_set_interpolation_type(
			new_track, source.track_get_interpolation_type(track_index)
		)

		var is_hips := (
			bone_name.ends_with("Hips") and track_type == Animation.TYPE_POSITION_3D
		)
		var anchor_x := 0.0
		var anchor_z := 0.0
		var has_anchor := false
		for key_index in source.track_get_key_count(track_index):
			var time_value := source.track_get_key_time(track_index, key_index)
			var transition := source.track_get_key_transition(track_index, key_index)
			var value = source.track_get_key_value(track_index, key_index)
			if is_hips and freeze_horizontal_root:
				var position_value: Vector3 = value
				if not has_anchor:
					anchor_x = position_value.x
					anchor_z = position_value.z
					has_anchor = true
				value = Vector3(anchor_x, position_value.y, anchor_z)
			result.track_insert_key(new_track, time_value, value, transition)

	return result if result.get_track_count() > 0 else null


func _build_collision() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "CitizenBody"
	_collision_body.collision_layer = 1 if collision_enabled else 0
	_collision_body.collision_mask = 0
	add_child(_collision_body)

	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = maxf(target_height, 0.8)
	shape_node.shape = capsule
	shape_node.position.y = capsule.height * 0.5
	_collision_body.add_child(shape_node)
