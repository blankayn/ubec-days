extends Node3D
class_name UcKioskNpc
## UC main-entrance NPC — patrol, talk (choice dialogue), fight when hit, fall when defeated.

const CHARACTER_PATH := "res://assets/npcs/uc_kiosk_guy.glb"
const InteractScript := preload("res://scripts/uc_kiosk_npc_interact.gd")

enum State { PATROL, FIGHT, DEFEATED }

@export var build_on_ready := true
@export var nearest_texture_filtering := true
@export var target_height := 1.78
@export var max_health := 5
@export var walk_speed := 1.35
@export var fight_speed := 2.1
@export var roam_enabled := false

var dialogue_ui: CanvasLayer = null
var hud: CanvasLayer = null

var _built := false
var _state := State.PATROL
var _health := 5
var _visual_model: Node3D
var _collision_body: StaticBody3D
var _animation_player: AnimationPlayer
var _idle_anim := &""
var _walk_anim := &""
var _attack_anim := &""
var _defeat_anim := &""

var _roam_points: Array[Vector3] = []
var _roam_index := 0
var _pause_left := 0.0
var _fight_cooldown := 0.0
var _player: Node3D = null
var _dialogue_generation := 0
var _defeat_tween: Tween
var _visual_scale := 1.0
var _pose_frozen := false


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	var packed := load(CHARACTER_PATH) as PackedScene
	if packed == null:
		push_error("UcKioskNpc: missing %s — open project in Godot to import the GLB" % CHARACTER_PATH)
		return
	_visual_model = packed.instantiate() as Node3D
	if _visual_model == null:
		push_error("UcKioskNpc: could not instantiate model")
		return
	_built = true
	_health = max_health
	_visual_model.name = "CharacterModel"
	_visual_model.rotation.y = PI
	add_child(_visual_model)
	_strip_non_character_nodes(_visual_model)
	_prepare_visuals(_visual_model)
	_fit_character_scale()
	_cache_animation_player()
	_sanitize_locomotion_clips()
	_build_interaction_body()
	_roam_points.clear()
	if roam_enabled and _roam_points.is_empty():
		_set_default_entrance_route()
	if dialogue_ui != null and not dialogue_ui.choice_picked.is_connected(_on_dialogue_choice):
		dialogue_ui.choice_picked.connect(_on_dialogue_choice)
	_previous_position = global_position
	if roam_enabled:
		_play_state_animation()
	else:
		_freeze_standing_pose()


var _previous_position := Vector3.ZERO


func get_interaction_prompt() -> String:
	if _state == State.DEFEATED:
		return "Talk (he is down)"
	if _state == State.FIGHT:
		return "He is swinging — talk or fight"
	return "Talk · Kiosk guy"


func npc_interact(player: Node) -> void:
	if dialogue_ui == null:
		if hud != null and hud.has_method("show_message"):
			hud.show_message("KIOSK GUY: \"Reload-Insert-Mechanism broken na sad.\"", 4.0)
		return
	_player = player as Node3D
	_start_dialogue("root")


func take_hit(amount: float = 1.0, from: Node3D = null) -> void:
	if _state == State.DEFEATED:
		return
	# Stationary attendant — no combat chase; just flinch text.
	if not roam_enabled:
		if hud != null and hud.has_method("show_message"):
			hud.show_message("KIOSK GUY: \"Hoy! Easy lang — RIM pa gihapon broken.\"", 2.0)
		return
	if from != null:
		_player = from
	if _state != State.FIGHT:
		_enter_fight()
	_health -= int(maxf(amount, 1.0))
	if hud != null and hud.has_method("show_message"):
		hud.show_message("KIOSK GUY: \"Unsa na!\"", 1.2)
	if _health <= 0:
		_enter_defeated()
	else:
		_play_clip(_attack_anim if _attack_anim != &"" else _idle_anim, false)


func _process(delta: float) -> void:
	if not _built or _state == State.DEFEATED:
		return
	if is_instance_valid(_visual_model):
		_visual_model.position = Vector3.ZERO
	# Default: stand still. Only patrol/chase when roam_enabled is explicitly on.
	if not roam_enabled:
		if _state == State.FIGHT:
			_state = State.PATROL
		_freeze_standing_pose()
		return
	if _state == State.PATROL:
		_update_patrol(delta)
	elif _state == State.FIGHT:
		_update_fight(delta)


func stand_still() -> void:
	roam_enabled = false
	_roam_points.clear()
	_pose_frozen = false
	_freeze_standing_pose()


func _freeze_standing_pose() -> void:
	# Stop every clip — this model's idle is a walk cycle, so playing anything looks like walking.
	_roam_points.clear()
	if _pose_frozen:
		return
	if is_instance_valid(_visual_model):
		for node in _visual_model.find_children("*", "AnimationTree", true, false):
			(node as AnimationTree).active = false
		for node in _visual_model.find_children("*", "AnimationPlayer", true, false):
			var ap := node as AnimationPlayer
			ap.stop()
			ap.active = false
		for node in _visual_model.find_children("*", "Skeleton3D", true, false):
			(node as Skeleton3D).reset_bone_poses()
	if _animation_player != null:
		_animation_player.stop()
		_animation_player.active = false
	_pose_frozen = true


func _hold_stand_idle() -> void:
	_freeze_standing_pose()


func _update_patrol(delta: float) -> void:
	if not roam_enabled or _roam_points.is_empty():
		_freeze_standing_pose()
		return
	if _animation_player != null and not _animation_player.active:
		_animation_player.active = true
	if _pause_left > 0.0:
		_pause_left -= delta
		_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)
		return
	var target := _roam_points[_roam_index]
	var flat_self := Vector3(global_position.x, 0.0, global_position.z)
	var flat_target := Vector3(target.x, 0.0, target.z)
	var to_target := flat_target - flat_self
	var dist := to_target.length()
	if dist < 0.35:
		_roam_index = (_roam_index + 1) % _roam_points.size()
		_pause_left = randf_range(1.2, 2.8)
		_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)
		return
	var step := walk_speed * delta
	look_at(Vector3(flat_target.x, global_position.y, flat_target.z), Vector3.UP)
	global_position += to_target.normalized() * minf(step, dist)
	global_position.y = target.y
	_play_clip(_locomotion_clip(), true)


func _update_fight(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	var flat_self := Vector3(global_position.x, 0.0, global_position.z)
	var flat_player := Vector3(_player.global_position.x, 0.0, _player.global_position.z)
	var to_player := flat_player - flat_self
	if to_player.length_squared() > 0.01:
		look_at(Vector3(flat_player.x, global_position.y, flat_player.z), Vector3.UP)
	var dist := to_player.length()
	if dist > 1.15:
		global_position += to_player.normalized() * fight_speed * delta
		_play_clip(_locomotion_clip(), true)
	else:
		_play_clip(_attack_anim if _attack_anim != &"" else _idle_anim, true)
	_fight_cooldown -= delta
	if _fight_cooldown <= 0.0 and dist <= 1.35:
		_fight_cooldown = 1.35
		if _player.has_method("add_trauma"):
			_player.add_trauma(0.22)
		if hud != null and hud.has_method("show_message"):
			hud.show_message("KIOSK GUY swings a receipt roll!", 1.0)


func _enter_fight() -> void:
	_state = State.FIGHT
	_fight_cooldown = 0.4
	if _animation_player != null:
		_animation_player.active = true
	if hud != null and hud.has_method("show_message"):
		hud.show_message("KIOSK GUY: \"Ayaw ko i-hit!\"", 2.0)


func _enter_defeated() -> void:
	_state = State.DEFEATED
	if _defeat_tween != null and _defeat_tween.is_valid():
		_defeat_tween.kill()
	_play_clip(_defeat_anim, false)
	_defeat_tween = create_tween()
	_defeat_tween.set_parallel(true)
	_defeat_tween.tween_property(_visual_model, "rotation:x", deg_to_rad(-88.0), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_defeat_tween.tween_property(_visual_model, "position:y", -0.55, 0.55)
	if hud != null and hud.has_method("show_message"):
		hud.show_message("Kiosk guy collapsed. You can still talk to him.", 3.5)


func _start_dialogue(node_id: String) -> void:
	if dialogue_ui == null:
		return
	if dialogue_ui.is_open():
		return
	var node := _dialogue_node(node_id)
	if node.is_empty():
		return
	_dialogue_generation += 1
	var choices: Array[String] = []
	for choice in node["choices"]:
		choices.append(str(choice))
	dialogue_ui.present(str(node["speaker"]), str(node["body"]), choices)
	dialogue_ui.set_meta("dialogue_owner", &"kiosk")
	dialogue_ui.set_meta("dialogue_node", node_id)


func _on_dialogue_choice(index: int) -> void:
	if dialogue_ui == null:
		return
	if dialogue_ui.get_meta("dialogue_owner", &"") != &"kiosk":
		return
	var node_id: String = dialogue_ui.get_meta("dialogue_node", "root")
	var node := _dialogue_node(node_id)
	if node.is_empty():
		return
	var branches: Array = node.get("branches", [])
	if index < 0 or index >= branches.size():
		return
	var next_id: String = branches[index]
	if next_id == "end":
		return
	call_deferred("_start_dialogue", next_id)


func _dialogue_node(node_id: String) -> Dictionary:
	match node_id:
		"root":
			return {
				"speaker": "Kiosk Guy",
				"body": "Hoy! Naa kay barya? Ang UC payment kiosk sa entrance dili mo-take og load. Reload-Insert-Mechanism (RIM) error na sad.",
				"choices": [
					"What is wrong with the kiosk?",
					"What does RIM mean?",
					"Why are you guarding the entrance?",
					"Leave me alone.",
				],
				"branches": ["kiosk_broken", "rim_explain", "guard", "end"],
			}
		"kiosk_broken":
			return {
				"speaker": "Kiosk Guy",
				"body": "Mo-beep lang siya ug \"INSUFFICIENT FUNDS\" bisan naa nay cash. Last week pa ni — registrar queue naa gihapon sa gawas tungod ani.",
				"choices": [
					"Did you try the Gaisano machines?",
					"Back to the RIM thing.",
					"Good luck with that.",
				],
				"branches": ["gaisano", "rim_explain", "end"],
			}
		"rim_explain":
			return {
				"speaker": "Kiosk Guy",
				"body": "RIM — Reload, Insert, Mechanism. Ang coin slot rim kinahanglan limpyo. Mutuo ko kung imong i-fix, mu-work na ang tuition kiosk. Help lang ko, bay?",
				"choices": [
					"I will wipe the slot later.",
					"I do not have tools.",
					"Fight me instead. (joke)",
				],
				"branches": ["rim_thanks", "rim_sad", "end"],
			}
		"rim_thanks":
			return {
				"speaker": "Kiosk Guy",
				"body": "Salamat! I-save nako imong name sa sticky note sa machine. Kung mo-work, libre ka sa photocopy — sa akong imagination lang.",
				"choices": ["See you around."],
				"branches": ["end"],
			}
		"rim_sad":
			return {
				"speaker": "Kiosk Guy",
				"body": "Sige lang. Mag-stand gihapon ko diri samtang ang line mosagol. Typical UC afternoon.",
				"choices": ["Bye."],
				"branches": ["end"],
			}
		"gaisano":
			return {
				"speaker": "Kiosk Guy",
				"body": "Gaisano vending okay ra, pero ang UC receipt wala gihapon mo-print. Need gihapon nako ang RIM fixed sa entrance kiosk.",
				"choices": ["Got it.", "Tell me about RIM again."],
				"branches": ["end", "rim_explain"],
			}
		"guard":
			return {
				"speaker": "Kiosk Guy",
				"body": "Dili ko guard — volunteer ko nga mag-explain sa error code. Ang tinuod guard naa sa GF-102. Ako ra ang naa sa entrance kay duol sa kiosk.",
				"choices": ["Makes sense.", "Kiosk status?"],
				"branches": ["end", "kiosk_broken"],
			}
		_:
			return {}


func _set_default_entrance_route() -> void:
	_roam_points.clear()
	for local in [
		Vector3(1.5, 0.24, -17.2),
		Vector3(4.5, 0.24, -18.5),
		Vector3(2.0, 0.24, -20.0),
		Vector3(-1.0, 0.24, -18.0),
	]:
		_roam_points.append(local)


func set_world_roam_points(world_points: Array[Vector3]) -> void:
	_roam_points = world_points
	_roam_index = 0


func _locomotion_clip() -> StringName:
	if _walk_anim != &"":
		return _walk_anim
	return _idle_anim


func _fit_character_scale() -> void:
	var bounds := _merged_mesh_aabb(_visual_model)
	var height := bounds.size.y
	if height < 0.001:
		return
	if height < 1.35 or height > 2.35:
		_visual_scale = target_height / height
		_visual_model.scale = Vector3.ONE * _visual_scale
	bounds = _merged_mesh_aabb(_visual_model)
	var feet_y := bounds.position.y
	if absf(feet_y) > 0.02:
		_visual_model.position.y -= feet_y


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


func _sanitize_locomotion_clips() -> void:
	if _animation_player == null:
		return
	for anim_name in [_idle_anim, _walk_anim, _attack_anim]:
		if anim_name == &"":
			continue
		_strip_root_motion_tracks(anim_name)


func _strip_root_motion_tracks(anim_name: StringName) -> void:
	var anim := _animation_player.get_animation(anim_name)
	if anim == null:
		return
	for track_index in range(anim.get_track_count() - 1, -1, -1):
		var track_type := anim.track_get_type(track_index)
		if track_type != Animation.TYPE_POSITION_3D:
			continue
		# Strip every position track — NPC root is moved in code, never by the clip.
		anim.remove_track(track_index)


func _play_state_animation() -> void:
	_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)


func _play_clip(anim_name: StringName, loop: bool) -> void:
	if _animation_player == null or anim_name == &"":
		return
	if not _animation_player.active:
		_animation_player.active = true
	if _animation_player.current_animation == anim_name and _animation_player.is_playing():
		return
	var animation := _animation_player.get_animation(anim_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_animation_player.play(anim_name)


func _cache_animation_player() -> void:
	_animation_player = _find_animation_player(_visual_model)
	if _animation_player == null:
		return
	# Prefer real idle names first — never grab a Mixamo walk as idle.
	_idle_anim = _choose_animation(_animation_player, ["idle", "stand", "nlatrack"])
	_walk_anim = _choose_animation(_animation_player, ["walk", "run", "nlatrack_001", "locomotion"])
	_attack_anim = _choose_animation(_animation_player, ["punch", "attack", "hit"])
	_defeat_anim = _choose_animation(_animation_player, ["death", "die", "fall", "defeat"])
	var names := _animation_player.get_animation_list()
	# If idle still looks like a walk clip, pick a better one.
	if _idle_anim != &"" and _looks_like_walk_clip(_idle_anim):
		for animation_name in names:
			if String(animation_name).to_lower() == "reset":
				continue
			if not _looks_like_walk_clip(animation_name):
				_idle_anim = animation_name
				break
	if _walk_anim == _idle_anim or _walk_anim == &"":
		for animation_name in names:
			var normalized := String(animation_name).to_lower()
			if normalized == "reset" or animation_name == _idle_anim:
				continue
			if _looks_like_walk_clip(animation_name) or normalized.contains("001"):
				_walk_anim = animation_name
				break
		if (_walk_anim == _idle_anim or _walk_anim == &"") and names.size() >= 2:
			for animation_name in names:
				if animation_name != _idle_anim and String(animation_name).to_lower() != "reset":
					_walk_anim = animation_name
					break


func _looks_like_walk_clip(anim_name: StringName) -> bool:
	var normalized := String(anim_name).to_lower()
	return (
		normalized.contains("walk")
		or normalized.contains("run")
		or normalized.contains("jog")
		or normalized.contains("locomotion")
	)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _choose_animation(player: AnimationPlayer, preferred_terms: Array[String]) -> StringName:
	var fallback := &""
	for animation_name in player.get_animation_list():
		var normalized := String(animation_name).to_lower()
		if normalized == "reset":
			continue
		if fallback == &"":
			fallback = animation_name
		for term in preferred_terms:
			if normalized.contains(term):
				return animation_name
	return fallback


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
				var material := StandardMaterial3D.new()
				if source_material is StandardMaterial3D:
					material = (source_material as StandardMaterial3D).duplicate(true) as StandardMaterial3D
				material.metallic = 0.0
				material.roughness = 0.92
				material.texture_filter = (
					BaseMaterial3D.TEXTURE_FILTER_NEAREST
					if nearest_texture_filtering
					else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				)
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_prepare_visuals(child)


func _build_interaction_body() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "InteractBody"
	_collision_body.set_script(InteractScript)
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 1
	add_child(_collision_body)
	var shape := CollisionShape3D.new()
	shape.position = _collision_center()
	var box := BoxShape3D.new()
	box.size = _collision_size()
	shape.shape = box
	_collision_body.add_child(shape)


func _collision_center() -> Vector3:
	return Vector3(0.0, target_height * 0.5, 0.0)


func _collision_size() -> Vector3:
	var radius := maxf(0.45, target_height * 0.22)
	return Vector3(radius * 2.4, target_height * 1.05, radius * 2.2)
