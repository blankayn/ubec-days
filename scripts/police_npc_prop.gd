extends Node3D
class_name PoliceNpcProp
## UBEC police officer — standing beat cop built by `tools/build_police.py`.
##
## The model is skinned onto the armature that ships inside
## `animation mixamo/Idle.fbx`, so its rest pose *is* the Mixamo rest pose and
## its bones carry the same `mixamorig1_` names as the clips. Retargeting is
## therefore a straight re-path: bone rotations copy across untouched, with no
## rest-pose correction of the kind `cblock_edward_npc.gd` needs for its
## differently-named rig.
##
## Idle is adopted from the model's own AnimationPlayer when the GLB carries
## one, and otherwise retargeted from `Idle.fbx`; walk always comes from
## `Walking.fbx`. Either way the tracks are re-pathed onto this skeleton.

const MODEL_PATH := "res://assets/npcs/police.glb"
const IDLE_SCENE := preload("res://animation mixamo/Idle.fbx")
const WALK_SCENE := preload("res://animation mixamo/Walking.fbx")
const InteractScript := preload("res://scripts/uc_kiosk_npc_interact.gd")

## Clips are exported by Mixamo under this single track name.
const SOURCE_CLIP := "mixamo_com"
## Rest height of the authored mesh, metres. Used to derive the display scale.
const AUTHORED_HEIGHT := 1.7636

@export var build_on_ready := true
@export var target_height := 1.80
@export var collision_enabled := true
@export var cast_shadow := true
## Officer name, used by the interaction prompt and his one line of dialogue.
@export var officer_name := "PO1 Ramirez"

# Wired by the map script, matching the other NPC props.
var hud: CanvasLayer = null
var face_look_target := Vector3.ZERO
var has_face_look_target := false

var _visual_model: Node3D = null
var _skeleton: Skeleton3D = null
var _animation_player: AnimationPlayer = null
var _collision_body: StaticBody3D = null
var _built := false
var _talking := false


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("PoliceNpcProp could not load %s (reimport it in Godot)" % MODEL_PATH)
		return
	_visual_model = packed.instantiate() as Node3D
	if _visual_model == null:
		push_error("PoliceNpcProp could not instantiate %s" % MODEL_PATH)
		return
	_built = true
	name = "Police"
	_visual_model.name = "PoliceModel"
	add_child(_visual_model)

	_skeleton = _visual_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		push_error("PoliceNpcProp: %s has no Skeleton3D" % MODEL_PATH)
		return

	_apply_scale()
	_face_authored_forward()
	_prepare_visuals()
	_install_animations()
	_build_collision()

	if has_face_look_target:
		face_toward(face_look_target)


func get_visual_model() -> Node3D:
	return _visual_model


func get_interaction_prompt() -> String:
	return "Talk to %s" % officer_name


func npc_interact(player: Node) -> void:
	if _talking:
		return
	_talking = true
	if player is Node3D:
		face_toward((player as Node3D).global_position)
	if hud != null and hud.has_method("show_message"):
		hud.show_message(
			"%s: Padayon lang, 'day. Ayaw pag-park diri sa sidewalk." % officer_name,
			3.5
		)
	get_tree().create_timer(2.6).timeout.connect(func() -> void: _talking = false)


func take_hit(_amount: float = 1.0, _from: Node3D = null) -> void:
	# No health model yet — Milestone 6 owns the wanted level. Until then he
	# just tells you off, so a punch is not silently swallowed.
	if hud != null and hud.has_method("show_message"):
		hud.show_message("%s: Hoy! Ayaw na." % officer_name, 2.5)


func face_toward(world_point: Vector3) -> void:
	var flat := Vector3(world_point.x, global_position.y, world_point.z)
	if flat.distance_to(global_position) < 0.05:
		return
	look_at(flat, Vector3.UP)


func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	if is_instance_valid(_collision_body):
		_collision_body.collision_layer = 1 if enabled else 0
		_collision_body.collision_mask = 0


func _apply_scale() -> void:
	var factor := target_height / AUTHORED_HEIGHT
	_visual_model.scale = Vector3.ONE * factor


func _face_authored_forward() -> void:
	# The rig faces +Z once it has been through Blender's glTF Y-up conversion,
	# but every consumer here treats -Z as forward, so the model is spun to
	# match. Measured from the rig rather than hardcoded: the toe bone sits in
	# front of the hips, which is all "forward" means for a humanoid.
	var hips := _skeleton.find_bone("mixamorig1_Hips")
	var toe := _skeleton.find_bone("mixamorig1_LeftToeBase")
	if hips < 0 or toe < 0:
		_visual_model.rotation.y = PI
		return
	var hips_z := _skeleton.get_bone_global_rest(hips).origin.z
	var toe_z := _skeleton.get_bone_global_rest(toe).origin.z
	if toe_z > hips_z:
		_visual_model.rotation.y = PI


func _prepare_visuals() -> void:
	for node in _visual_model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = (
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
	var idle := _baked_idle()
	if idle == null:
		idle = _retarget(IDLE_SCENE, true)
	if idle != null:
		library.add_animation("idle", idle)
	var walk := _retarget(WALK_SCENE, true)
	if walk != null:
		library.add_animation("walk", walk)
	if library.get_animation_list().size() == 0:
		push_error("PoliceNpcProp: no Mixamo clips could be retargeted")
		return
	_animation_player.add_animation_library("locomotion", library)
	if library.has_animation("idle"):
		_animation_player.play("locomotion/idle")


## Pulls the idle clip baked into the GLB by `tools/build_police.py`.
##
## The exported scene carries its own AnimationPlayer holding the Mixamo Idle
## action, keyed on this same skeleton, so it can be adopted as-is -- no
## re-path, no rest correction. The animation is copied into our player so the
## scene's own player stays inert; two players driving the same bones is how
## NPCs end up with spasms.
func _baked_idle() -> Animation:
	var glb_player := _visual_model.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	if glb_player == null:
		return null
	for animation_name in glb_player.get_animation_list():
		glb_player.active = false
		# Still has to go through the re-path: the baked clip's tracks are
		# written relative to the GLB's own root, and our player is rooted on
		# the prop. Adopted as-is they resolve to nothing and he stands frozen
		# with no error to explain why.
		return _retarget_animation(glb_player.get_animation(animation_name), true)
	return null


## Copies one Mixamo clip onto this officer's skeleton.
##
## Source and target bones are named identically, so tracks only need their
## node path swapped. `freeze_horizontal_root` pins the hips in X/Z: the clip's
## own drift would otherwise slide him off the sidewalk over time, since
## nothing here is driving him from physics.
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


## The re-path itself, shared by the FBX clips and any clip baked into the GLB.
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
	_collision_body.name = "InteractBody"
	_collision_body.set_script(InteractScript)
	_collision_body.collision_layer = 1 if collision_enabled else 0
	_collision_body.collision_mask = 0
	add_child(_collision_body)

	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = target_height
	capsule.radius = 0.28
	shape_node.shape = capsule
	shape_node.position = Vector3(0.0, target_height * 0.5, 0.0)
	_collision_body.add_child(shape_node)


## Standing beat cop by default; call this to send him walking a route later.
func play_walk() -> void:
	if _animation_player != null and _animation_player.has_animation("locomotion/walk"):
		_animation_player.play("locomotion/walk")


func play_idle() -> void:
	if _animation_player != null and _animation_player.has_animation("locomotion/idle"):
		_animation_player.play("locomotion/idle")
