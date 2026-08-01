extends Node3D
class_name MuletNpcProp
## Mulet — classmate on 2F courtyard railing. Won't let anyone copy his work.

const CHARACTER_PATH := "res://assets/npcs/mulet.glb"
const InteractScript := preload("res://scripts/uc_kiosk_npc_interact.gd")

const IDLE_CLIP := &"NlaTrack"
const TALK_CLIP := &"NlaTrack_002"
const FALLBACK_IDLE := &"NlaTrack_001"

signal interaction_requested(id: StringName, message: String)

var dialogue_ui: CanvasLayer = null
var hud: CanvasLayer = null
var _dialogue_generation := 0

@export var build_on_ready := true
@export var target_height := 1.85
@export var collision_enabled := true
@export var nearest_texture_filtering := true
@export var cast_shadow := false
@export var face_look_target: Vector3 = Vector3.ZERO

var _built := false
var _visual_model: Node3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _animation_player: AnimationPlayer
var _idle_anim := &""
var _talk_anim := &""
var _current_anim := &""
var _talking := false
var _visual_base_position := Vector3.ZERO
var _spawn_global_position := Vector3.ZERO
var _skeleton: Skeleton3D
var _hip_bone := -1
var _hip_rest_pose := Transform3D.IDENTITY


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	var packed := load(CHARACTER_PATH) as PackedScene
	if packed == null:
		push_error("MuletNpcProp could not load: %s" % CHARACTER_PATH)
		return
	_visual_model = packed.instantiate() as Node3D
	if _visual_model == null:
		push_error("MuletNpcProp could not instantiate mulet.glb")
		return
	_built = true
	name = "Mulet"
	_visual_model.name = "MuletModel"
	_visual_model.rotation.y = PI
	add_child(_visual_model)
	_strip_non_character_nodes(_visual_model)
	_prepare_visuals(_visual_model)
	_cache_animation_player()
	_strip_root_translation_tracks()
	_cache_hip_rest()
	if collision_enabled:
		_build_player_safe_collision()
	_fit_character_scale()
	_visual_base_position = _visual_model.position
	_spawn_global_position = global_position
	if face_look_target != Vector3.ZERO:
		look_at(Vector3(face_look_target.x, global_position.y, face_look_target.z), Vector3.UP)
		_spawn_global_position = global_position
	_talking = false
	_play_idle()


func get_visual_model() -> Node3D:
	return _visual_model


func get_interaction_prompt() -> String:
	return "Talk to Mulet"


func npc_interact(player: Node) -> void:
	if player is Node3D:
		face_toward((player as Node3D).global_position)
	_talking = true
	_play_talk()
	if dialogue_ui == null:
		if hud != null and hud.has_method("show_message"):
			hud.show_message("Mulet: Dili ko pacopya baya — pagtuon inyo oi.", 3.5)
		get_tree().create_timer(2.4).timeout.connect(_end_talk)
		return
	if dialogue_ui.has_method("is_open") and dialogue_ui.is_open():
		if dialogue_ui.get_meta("dialogue_owner", &"") != &"mulet":
			if dialogue_ui.has_method("dismiss"):
				dialogue_ui.dismiss()
		else:
			return
	if dialogue_ui.has_signal("choice_picked") and not dialogue_ui.choice_picked.is_connected(_on_dialogue_choice):
		dialogue_ui.choice_picked.connect(_on_dialogue_choice)
	_start_dialogue("root")


func face_toward(world_point: Vector3) -> void:
	var flat := Vector3(world_point.x, global_position.y, world_point.z)
	if flat.distance_squared_to(global_position) < 0.0001:
		return
	look_at(flat, Vector3.UP)


func _process(_delta: float) -> void:
	if not _built:
		return
	global_position = _spawn_global_position
	if is_instance_valid(_visual_model):
		_visual_model.position = _visual_base_position
	_pin_hip_translation()
	if _animation_player == null:
		return
	if _talking:
		if not _animation_player.is_playing() or _current_anim != _talk_anim:
			_play_talk()
	elif not _animation_player.is_playing() or _current_anim != _idle_anim:
		_play_idle()


func _start_dialogue(node_id: String) -> void:
	if dialogue_ui == null:
		return
	if dialogue_ui.has_method("is_open") and dialogue_ui.is_open() and node_id == "root":
		return
	var node := _dialogue_node(node_id)
	if node.is_empty():
		_end_talk()
		return
	_dialogue_generation += 1
	var choices: Array[String] = []
	for choice in node.get("choices", []):
		choices.append(str(choice))
	dialogue_ui.present(str(node["speaker"]), str(node["body"]), choices)
	dialogue_ui.set_meta("dialogue_owner", &"mulet")
	dialogue_ui.set_meta("dialogue_node", node_id)
	dialogue_ui.set_meta("mulet_dialogue_gen", _dialogue_generation)


func _on_dialogue_choice(index: int) -> void:
	if dialogue_ui == null:
		return
	if dialogue_ui.get_meta("dialogue_owner", &"") != &"mulet":
		return
	if int(dialogue_ui.get_meta("mulet_dialogue_gen", -1)) != _dialogue_generation:
		return
	var node_id: String = dialogue_ui.get_meta("dialogue_node", "root")
	var node := _dialogue_node(node_id)
	var branches: Array = node.get("branches", [])
	if index < 0 or index >= branches.size():
		_end_talk()
		return
	var next_id: String = str(branches[index])
	if next_id == "end" or next_id == "":
		if dialogue_ui.has_method("dismiss"):
			dialogue_ui.dismiss()
		_end_talk()
		return
	if dialogue_ui.has_method("dismiss"):
		dialogue_ui.dismiss()
	call_deferred("_start_dialogue", next_id)


func _end_talk() -> void:
	_talking = false
	_play_idle()


func _dialogue_node(node_id: String) -> Dictionary:
	match node_id:
		"root":
			return {
				"speaker": "Mulet",
				"body": "Dili ko pacopya baya — pagtuon inyo oi. Homework, quiz, exam — ako ra akong answers.",
				"choices": [
					"Pahulam lang og answer, bro.",
					"Nganong dili man?",
					"Okay, I get it.",
					"Sige, later.",
				],
				"branches": ["no_copy", "why_not", "respect", "end"],
			}
		"no_copy":
			return {
				"speaker": "Mulet",
				"body": "No. Dili ko pacopya. Kung mag-exam ta, ikaw magtuon. Ayaw ko suroy-suroya og \"borrow answers.\"",
				"choices": [
					"Strict kaayo ka.",
					"Nganong dili jud?",
					"Sige, later.",
				],
				"branches": ["strict", "why_not", "end"],
			}
		"why_not":
			return {
				"speaker": "Mulet",
				"body": "Kay ako nagbuhat. Kung copy ka, ako ma-risk, ikaw ma-pass free. Dili fair. Pagtuon — ayaw copy.",
				"choices": [
					"Pahulam lang og homework?",
					"Okay, respect.",
					"Bye.",
				],
				"branches": ["no_copy", "respect", "end"],
			}
		"strict":
			return {
				"speaker": "Mulet",
				"body": "Strict? Protektahan ra nako akong work. Dili ko pacopya baya — pagtuon inyo oi. Court nako tan-awon, dili inyong cheatsheet.",
				"choices": [
					"Okay, I get it.",
					"Unsa imong review tip?",
					"Later.",
				],
				"branches": ["respect", "tip", "end"],
			}
		"respect":
			return {
				"speaker": "Mulet",
				"body": "Good. Study your own notes. Kung naa kay question on the topic — ask. Pero answers? Dili. Dili ko pacopya.",
				"choices": [
					"Unsa imong review tip?",
					"Sige, later.",
				],
				"branches": ["tip", "end"],
			}
		"tip":
			return {
				"speaker": "Mulet",
				"body": "Tip: basaha imong notes twice, then closed-book recall. Ayaw screenshot sa akoa. Pagtuon inyo oi.",
				"choices": [
					"Salamat, Mulet.",
					"Bye.",
				],
				"branches": ["end", "end"],
			}
		_:
			return {}
	return {}


func _play_idle() -> void:
	_play_clip(_idle_anim if _idle_anim != &"" else FALLBACK_IDLE, true)


func _play_talk() -> void:
	_play_clip(_talk_anim if _talk_anim != &"" else _idle_anim, true)


func _play_clip(anim_name: StringName, loop: bool) -> void:
	if _animation_player == null or anim_name == &"":
		return
	if not _animation_player.has_animation(anim_name):
		return
	_animation_player.active = true
	var anim := _animation_player.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if _current_anim == anim_name and _animation_player.is_playing():
		return
	_current_anim = anim_name
	_animation_player.play(anim_name)


func _cache_animation_player() -> void:
	_animation_player = _find_animation_player(_visual_model)
	if _animation_player == null:
		push_warning("MuletNpcProp: no AnimationPlayer on mulet.glb")
		return
	_idle_anim = IDLE_CLIP if _animation_player.has_animation(IDLE_CLIP) else &""
	_talk_anim = TALK_CLIP if _animation_player.has_animation(TALK_CLIP) else &""
	if _idle_anim == &"":
		_idle_anim = FALLBACK_IDLE if _animation_player.has_animation(FALLBACK_IDLE) else &""
	if _talk_anim == &"" or _talk_anim == _idle_anim:
		for candidate in [&"NlaTrack_002", &"NlaTrack", &"NlaTrack_001"]:
			if candidate == _idle_anim:
				continue
			if _animation_player.has_animation(candidate):
				_talk_anim = candidate
				break
	if _talk_anim == &"":
		_talk_anim = _idle_anim


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
	_hip_bone = _skeleton.find_bone("Hip")
	if _hip_bone < 0:
		_hip_bone = _skeleton.find_bone("Root")
	if _hip_bone < 0:
		return
	_hip_rest_pose = _skeleton.get_bone_rest(_hip_bone)


func _pin_hip_translation() -> void:
	if _skeleton == null or _hip_bone < 0:
		return
	var pose := _skeleton.get_bone_pose(_hip_bone)
	pose.origin = _hip_rest_pose.origin
	_skeleton.set_bone_pose_position(_hip_bone, pose.origin)


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
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.get_active_material(surface_index)
				if source_material == null:
					continue
				var material := source_material.duplicate(true)
				if material is BaseMaterial3D:
					var base_material := material as BaseMaterial3D
					base_material.metallic = 0.0
					base_material.roughness = maxf(base_material.roughness, 0.88)
					base_material.texture_filter = (
						BaseMaterial3D.TEXTURE_FILTER_NEAREST
						if nearest_texture_filtering
						else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					)
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_prepare_visuals(child)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _build_player_safe_collision() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "InteractBody"
	_collision_body.set_script(InteractScript)
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 0
	add_child(_collision_body)

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "BodyCollision"
	# Push into the corridor so the rail/wall does not eat the interact ray.
	_collision_shape.position = Vector3(0.0, target_height * 0.52, -0.7)
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, maxf(target_height, 2.0), 1.5)
	_collision_shape.shape = box
	_collision_body.add_child(_collision_shape)


func _fit_character_scale() -> void:
	var bounds := _merged_mesh_aabb(_visual_model)
	var height := bounds.size.y
	if height < 0.001:
		return
	var scale := target_height / height
	_visual_model.scale = Vector3.ONE * scale
	bounds = _merged_mesh_aabb(_visual_model)
	var feet_y := bounds.position.y
	if absf(feet_y) > 0.02:
		_visual_model.position.y -= feet_y
	if is_instance_valid(_collision_shape):
		_collision_shape.position = Vector3(0.0, target_height * 0.52, -0.7)
		var box := _collision_shape.shape as BoxShape3D
		if box != null:
			box.size = Vector3(1.5, maxf(target_height + 0.15, 2.1), 1.5)


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
