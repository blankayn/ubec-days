extends Node3D
class_name EdwardNpcProp
## Edward — office-worker classmate (`edward.glb`). Uses imported GLB clips for idle / walk.

const CHARACTER_PATH := "res://assets/npcs/edward.glb"

const COLLISION_CENTER := Vector3(0.0, 0.9, 0.0)
const COLLISION_SIZE := Vector3(0.48, 1.78, 0.42)
const DEFAULT_IDLE_CLIP := &"NlaTrack"
const DEFAULT_WALK_CLIP := &"NlaTrack_001"
const RAIL_LEAN_IDLE_CLIP := &"NlaTrack_002"
const InteractScript := preload("res://scripts/uc_kiosk_npc_interact.gd")

signal interaction_requested(id: StringName, message: String)

var dialogue_ui: CanvasLayer = null
var hud: CanvasLayer = null
var _dialogue_generation := 0

const WALK_CYCLE_DISTANCE := 0.72
const HIP_SWING := 0.52
const KNEE_BEND := 0.58
const ARM_SWING := 0.40
const LEG_MESH_THICKNESS := Vector3(1.32, 1.0, 1.32)

@export var build_on_ready := true
@export var target_height := 1.78
@export var collision_enabled := true
@export var nearest_texture_filtering := true
@export var cast_shadow := true
@export var roam_enabled := true
@export var face_courtyard_on_spawn := false
@export var courtyard_look_target: Vector3 = Vector3.ZERO
@export var lean_on_rail := false
@export var lean_on_wall := false
@export_range(4.0, 28.0, 0.5) var rail_lean_pitch_deg := 15.0
@export_range(4.0, 22.0, 0.5) var wall_lean_pitch_deg := 8.0
@export_range(0.0, 0.35, 0.01) var wall_lean_back_offset := 0.18
@export var walk_speed := 1.55
@export var pause_min := 1.4
@export var pause_max := 3.6

var _built := false
var _visual_model: Node3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _animation_player: AnimationPlayer
var _idle_anim := &""
var _walk_anim := &""

var _roam_points: Array[Vector3] = []
var _roam_index := 0
var _pause_left := 0.0
var _moving := false
var _current_anim := &""

# Procedural gait
var _joints: Dictionary = {}
var _base_rot: Dictionary = {}
var _previous_position := Vector3.ZERO
var _smoothed_speed := 0.0
var _walk_cycle := 0.0
var _walk_blend := 0.0
var _idle_time := 0.0
var _gait_sign := 1.0
var _visual_feet_offset := Vector3.ZERO


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	var packed := load(CHARACTER_PATH) as PackedScene
	if packed == null:
		push_error("EdwardNpcProp could not load: %s (reimport edward.glb in Godot)" % CHARACTER_PATH)
		return
	_visual_model = packed.instantiate() as Node3D
	if _visual_model == null:
		push_error("EdwardNpcProp could not instantiate edward.glb")
		return
	_built = true
	name = "Edward"
	_visual_model.name = "EdwardModel"
	# Authored face is +Z; game forward is -Z.
	_visual_model.rotation.y = PI
	add_child(_visual_model)
	_strip_non_character_nodes(_visual_model)
	_prepare_visuals(_visual_model)
	_thicken_leg_meshes(_visual_model)
	_cache_animation_player()
	_cache_joints()
	if collision_enabled:
		_build_player_safe_collision()
	_fit_character_scale()
	_previous_position = global_position
	if face_courtyard_on_spawn and courtyard_look_target != Vector3.ZERO:
		look_at(Vector3(courtyard_look_target.x, global_position.y, courtyard_look_target.z), Vector3.UP)
	elif roam_enabled and _roam_points.is_empty():
		_set_default_plaza_route()
	if lean_on_wall:
		_configure_wall_lean_idle()
		_apply_wall_lean_pose()
		_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)
	elif lean_on_rail:
		_configure_rail_lean_idle()
		_apply_rail_lean_pose()
		_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)
	else:
		# Default standing watch — prefer arms-crossed idle if present.
		_configure_wall_lean_idle()
		_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)


func get_interaction_prompt() -> String:
	return "Talk to Edward"


func npc_interact(player: Node) -> void:
	if player is Node3D:
		face_toward((player as Node3D).global_position)
	if dialogue_ui == null:
		if hud != null and hud.has_method("show_message"):
			hud.show_message(
				"EDWARD: \"Lami kaau e Esmeringhoy kay uwan.\"",
				5.0
			)
		else:
			interaction_requested.emit(
				&"edward",
				"EDWARD: \"Lami kaau e Esmeringhoy kay uwan.\""
			)
		return
	if dialogue_ui.has_method("is_open") and dialogue_ui.is_open():
		return
	if dialogue_ui.has_signal("choice_picked") and not dialogue_ui.choice_picked.is_connected(_on_dialogue_choice):
		dialogue_ui.choice_picked.connect(_on_dialogue_choice)
	_start_dialogue("root")


func _start_dialogue(node_id: String) -> void:
	if dialogue_ui == null:
		return
	if dialogue_ui.has_method("is_open") and dialogue_ui.is_open():
		return
	var node := _dialogue_node(node_id)
	if node.is_empty():
		return
	_dialogue_generation += 1
	var choices: Array[String] = []
	for choice in node["choices"]:
		choices.append(str(choice))
	dialogue_ui.present(str(node["speaker"]), str(node["body"]), choices)
	dialogue_ui.set_meta("dialogue_owner", &"edward")
	dialogue_ui.set_meta("dialogue_node", node_id)
	dialogue_ui.set_meta("edward_dialogue_gen", _dialogue_generation)


func _on_dialogue_choice(index: int) -> void:
	if dialogue_ui == null:
		return
	if dialogue_ui.get_meta("dialogue_owner", &"") != &"edward":
		return
	if int(dialogue_ui.get_meta("edward_dialogue_gen", -1)) != _dialogue_generation:
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
				"speaker": "Edward",
				"body": "Lami kaau e Esmeringhoy kay uwan. Craving dayon.",
				"choices": [
					"Unsa man nang Esmeringhoy?",
					"True — rainy days hit different.",
					"Asa ka kasagaran mopalit?",
					"Sige, later.",
				],
				"branches": ["what_is", "agree_rain", "where_buy", "end"],
			}
		"what_is":
			return {
				"speaker": "Edward",
				"body": "Esmeringhoy — kanang crispy-sweet snack near Banilad. Kung uwan, mas lami kay warm pa ang bag. Lami kaau e Esmeringhoy kay uwan, tipik.",
				"choices": [
					"Sounds dangerous for my allowance.",
					"Ngano kay uwan jud?",
					"Back.",
				],
				"branches": ["allowance", "why_rain", "root"],
			}
		"why_rain":
			return {
				"speaker": "Edward",
				"body": "Kay cold ang air, then mutaas imong gana. Plus ang smell sa wet pavement + hot Esmeringhoy — chef's kiss. Lami kaau e Esmeringhoy kay uwan, no joke.",
				"choices": [
					"Okay, I'm sold.",
					"Asa jud na?",
					"Enough food talk.",
				],
				"branches": ["sold", "where_buy", "end"],
			}
		"agree_rain":
			return {
				"speaker": "Edward",
				"body": "Di ba? Especially kung late class ka then mugawas ka, uwan na. Maglakaw padulong Cuenco with Esmeringhoy in hand — soft life jud. Lami kaau e Esmeringhoy kay uwan.",
				"choices": [
					"Unsa pa imong order usually?",
					"Asa ka mopalit?",
					"See you.",
				],
				"branches": ["order", "where_buy", "end"],
			}
		"where_buy":
			return {
				"speaker": "Edward",
				"body": "Duol ra — by the Banilad side toward the flyover / street stalls. Kung heavy ang uwan, wait lang sa covered walk then grab one before mo-cross.",
				"choices": [
					"I'll try after errands.",
					"Unsa imong usual order?",
					"Thanks, Edward.",
				],
				"branches": ["sold", "order", "end"],
			}
		"order":
			return {
				"speaker": "Edward",
				"body": "Ako? Extra sauce kung naa, then slow walk lang — ayaw paspas kay init pa. Kung kauban ka, share jud... unless ako gutom. Haha.",
				"choices": [
					"Noted.",
					"Ngano kay uwan sad?",
					"Bye.",
				],
				"branches": ["sold", "why_rain", "end"],
			}
		"allowance":
			return {
				"speaker": "Edward",
				"body": "Dangerous jud — especially kung everyday uwan season. Budget tip: usa ra ka bag, then tubig from fountain. Survival mode.",
				"choices": [
					"Solid tip.",
					"Where again?",
					"Later.",
				],
				"branches": ["sold", "where_buy", "end"],
			}
		"sold":
			return {
				"speaker": "Edward",
				"body": "Ayos! Remember ha — lami kaau e Esmeringhoy kay uwan. Don't forget.",
				"choices": ["Got it. See you."],
				"branches": ["end"],
			}
		_:
			return {}


func face_toward(target_global_position: Vector3) -> void:
	var flat_target := Vector3(
		target_global_position.x,
		global_position.y,
		target_global_position.z
	)
	if global_position.distance_squared_to(flat_target) <= 0.000001:
		return
	look_at(flat_target, Vector3.UP)


func set_roam_points(points: Array) -> void:
	_roam_points.clear()
	for point in points:
		if point is Vector3:
			_roam_points.append(point as Vector3)
	_roam_index = 0
	_pause_left = 0.0


func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	if is_instance_valid(_collision_shape):
		_collision_shape.disabled = not enabled
	if is_instance_valid(_collision_body):
		_collision_body.collision_layer = 1 if enabled else 0
		_collision_body.collision_mask = 1 if enabled else 0


func get_visual_model() -> Node3D:
	return _visual_model


func _process(delta: float) -> void:
	if not _built or delta <= 0.0:
		return
	if is_instance_valid(_visual_model):
		var lean_back := Vector3.ZERO
		if lean_on_wall and not _moving:
			# Authored face is flipped; local +Z is toward the wall behind him.
			lean_back = Vector3(0.0, 0.0, wall_lean_back_offset)
		_visual_model.position = _visual_feet_offset + lean_back
	if lean_on_wall and not _moving and not roam_enabled:
		_maintain_wall_lean_pose()
		return
	if lean_on_rail and not _moving and not roam_enabled:
		_maintain_rail_lean_pose()
		return
	if roam_enabled and visible and not _roam_points.is_empty():
		_update_roam(delta)
	if not _joints.is_empty():
		_update_gait(delta)


func _update_roam(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		_moving = false
		_set_anim_state(false)
		return

	var target := _roam_points[_roam_index]
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= 0.12:
		global_position.x = target.x
		global_position.z = target.z
		_roam_index = (_roam_index + 1) % _roam_points.size()
		_pause_left = randf_range(pause_min, pause_max)
		_moving = false
		_set_anim_state(false)
		return

	var step := minf(walk_speed * delta, distance)
	var direction := to_target / distance
	global_position += Vector3(direction.x, 0.0, direction.z) * step
	# Face travel direction (−Z is character forward after the model yaw flip).
	rotation.y = atan2(-direction.x, -direction.z)
	_moving = true
	_set_anim_state(true)


func _set_default_plaza_route() -> void:
	var origin := global_position
	_roam_points = [
		origin,
		origin + Vector3(4.5, 0.0, -1.2),
		origin + Vector3(2.0, 0.0, 3.5),
		origin + Vector3(-3.5, 0.0, 2.0),
		origin + Vector3(-4.0, 0.0, -2.5),
		origin + Vector3(1.5, 0.0, -3.0),
	]


func _set_anim_state(walking: bool) -> void:
	if walking and _walk_anim != &"":
		_play_clip(_walk_anim, true)
	else:
		_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)


func _play_clip(anim_name: StringName, loop: bool) -> void:
	if _animation_player == null or anim_name == &"":
		return
	if _current_anim == anim_name and _animation_player.is_playing():
		return
	var animation := _animation_player.get_animation(anim_name)
	if animation != null and loop:
		animation.loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(anim_name)
	_current_anim = anim_name


func _update_gait(delta: float) -> void:
	var actor_position := global_position
	var horizontal_delta := actor_position - _previous_position
	horizontal_delta.y = 0.0
	var travelled := horizontal_delta.length()
	_previous_position = actor_position
	_smoothed_speed = lerpf(_smoothed_speed, travelled / delta, minf(delta * 8.0, 1.0))
	_idle_time += delta

	var moving_now := travelled > 0.00001
	var walking := moving_now or _smoothed_speed > 0.08
	_walk_blend = move_toward(_walk_blend, 1.0 if walking else 0.0, delta * 9.0)
	if moving_now:
		var local_delta := global_transform.basis.inverse() * horizontal_delta
		var signed_travel := local_delta.z
		if absf(signed_travel) > 0.00001:
			_gait_sign = signf(signed_travel)
		var gait_distance := minf(absf(signed_travel), 0.25)
		_walk_cycle = fmod(
			_walk_cycle + _gait_sign * gait_distance / WALK_CYCLE_DISTANCE * TAU,
			TAU
		)
	_apply_limb_pose()


func _apply_limb_pose() -> void:
	var left := _leg_amounts(_walk_cycle)
	var right := _leg_amounts(fmod(_walk_cycle + PI, TAU))
	var idle_breath := sin(_idle_time * 1.7) * (1.0 - _walk_blend)

	# Leg_L/R pivots: +X flexion swings thigh forward when walking toward −Z.
	_set_joint("Leg_L", Vector3(-left.x * HIP_SWING * _walk_blend, 0.0, 0.0))
	_set_joint("Knee_L", Vector3(left.y * KNEE_BEND * _walk_blend, 0.0, 0.0))
	_set_joint("Leg_R", Vector3(-right.x * HIP_SWING * _walk_blend, 0.0, 0.0))
	_set_joint("Knee_R", Vector3(right.y * KNEE_BEND * _walk_blend, 0.0, 0.0))
	_set_joint("Foot_L", Vector3(-left.y * 0.18 * _walk_blend, 0.0, 0.0))
	_set_joint("Foot_R", Vector3(-right.y * 0.18 * _walk_blend, 0.0, 0.0))

	_set_joint("Arm_L", Vector3(left.x * ARM_SWING * _walk_blend + idle_breath * 0.03, 0.0, 0.0))
	_set_joint("Elbow_L", Vector3(maxf(0.0, -left.x) * 0.22 * _walk_blend, 0.0, 0.0))
	_set_joint("Arm_R", Vector3(right.x * ARM_SWING * _walk_blend - idle_breath * 0.03, 0.0, 0.0))
	_set_joint("Elbow_R", Vector3(maxf(0.0, -right.x) * 0.22 * _walk_blend, 0.0, 0.0))

	var sway := (left.x - right.x) * 0.04 * _walk_blend
	_set_joint("Torso", Vector3(absf(sin(_walk_cycle)) * 0.03 * _walk_blend + idle_breath * 0.01, sway, 0.0))


func _leg_amounts(phase: float) -> Vector2:
	var wrapped := fposmod(phase, TAU)
	if wrapped < PI:
		var swing_t := wrapped / PI
		return Vector2(lerpf(-1.0, 1.0, swing_t), sin(swing_t * PI))
	var stance_t := (wrapped - PI) / PI
	return Vector2(lerpf(1.0, -1.0, stance_t), 0.0)


func _set_joint(joint_name: String, euler_offset: Vector3) -> void:
	if not _joints.has(joint_name):
		return
	var joint: Node3D = _joints[joint_name]
	var base: Vector3 = _base_rot[joint_name]
	joint.rotation = base + euler_offset


func _cache_joints() -> void:
	for joint_name in [
		"Leg_L", "Knee_L", "Leg_R", "Knee_R",
		"Foot_L", "Foot_R",
		"Arm_L", "Elbow_L", "Arm_R", "Elbow_R", "Torso",
	]:
		var joint := _visual_model.find_child(joint_name, true, false) as Node3D
		if joint == null:
			continue
		_joints[joint_name] = joint
		_base_rot[joint_name] = joint.rotation


func _cache_animation_player() -> void:
	_animation_player = _find_animation_player(_visual_model)
	if _animation_player == null:
		return
	_idle_anim = _choose_animation(_animation_player, ["idle", "stand", "nlatrack"])
	_walk_anim = _choose_animation(_animation_player, ["walk", "run", "nlatrack_001"])
	if _animation_player.has_animation(DEFAULT_IDLE_CLIP):
		_idle_anim = DEFAULT_IDLE_CLIP
	if _animation_player.has_animation(DEFAULT_WALK_CLIP):
		_walk_anim = DEFAULT_WALK_CLIP


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


func _thicken_leg_meshes(node: Node) -> void:
	const leg_part_names := [
		"Thigh_L", "Thigh_R", "Shin_L", "Shin_R",
		"Trouser_Crease_L", "Trouser_Crease_R",
		"Shoe_L", "Shoe_R", "Sole_L", "Sole_R",
		"Ankle_L", "Ankle_R",
	]
	if node is MeshInstance3D and node.name in leg_part_names:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.scale = Vector3(
			mesh_instance.scale.x * LEG_MESH_THICKNESS.x,
			mesh_instance.scale.y * LEG_MESH_THICKNESS.y,
			mesh_instance.scale.z * LEG_MESH_THICKNESS.z,
		)
	for child in node.get_children():
		_thicken_leg_meshes(child)


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


func _build_player_safe_collision() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "InteractBody"
	_collision_body.set_script(InteractScript)
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 0
	add_child(_collision_body)

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "BodyCollision"
	_collision_shape.position = Vector3(0.0, target_height * 0.52, 0.0)
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, maxf(target_height, 2.0), 1.2)
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
	_visual_feet_offset = _visual_model.position
	if is_instance_valid(_collision_shape):
		_collision_shape.position = Vector3(0.0, target_height * 0.52, 0.0)
		var box := _collision_shape.shape as BoxShape3D
		if box != null:
			box.size = Vector3(1.2, maxf(target_height + 0.15, 2.1), 1.2)


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


func _configure_wall_lean_idle() -> void:
	# Arms-crossed clip + body tip into the wall.
	if _animation_player != null and _animation_player.has_animation(RAIL_LEAN_IDLE_CLIP):
		_idle_anim = RAIL_LEAN_IDLE_CLIP


func _configure_rail_lean_idle() -> void:
	if _animation_player != null and _animation_player.has_animation(RAIL_LEAN_IDLE_CLIP):
		_idle_anim = RAIL_LEAN_IDLE_CLIP


func _apply_rail_lean_pose() -> void:
	if not lean_on_rail or _visual_model == null:
		return
	_visual_model.rotation.x = deg_to_rad(-rail_lean_pitch_deg)
	if _joints.is_empty():
		return
	if _animation_player != null and _idle_anim == RAIL_LEAN_IDLE_CLIP:
		return
	_pose_arms_on_rail()


func _maintain_rail_lean_pose() -> void:
	if not lean_on_rail or _visual_model == null:
		return
	_visual_model.rotation.x = deg_to_rad(-rail_lean_pitch_deg)
	if _animation_player == null or not _animation_player.is_playing():
		_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)
	if _joints.is_empty():
		return
	if _animation_player != null and _idle_anim == RAIL_LEAN_IDLE_CLIP:
		return
	_pose_arms_on_rail()


func _apply_wall_lean_pose() -> void:
	if not lean_on_wall or _visual_model == null:
		return
	# Tip body into the wall; arms stay on the crossed idle clip.
	_visual_model.rotation.x = deg_to_rad(wall_lean_pitch_deg)
	_visual_model.rotation.z = deg_to_rad(-5.0)
	_visual_model.position = _visual_feet_offset + Vector3(0.0, 0.0, wall_lean_back_offset)


func _maintain_wall_lean_pose() -> void:
	if not lean_on_wall or _visual_model == null:
		return
	_visual_model.rotation.x = deg_to_rad(wall_lean_pitch_deg)
	_visual_model.rotation.z = deg_to_rad(-5.0)
	if _animation_player == null or not _animation_player.is_playing():
		_play_clip(_idle_anim if _idle_anim != &"" else _walk_anim, true)


func _pose_arms_on_rail() -> void:
	var torso: Vector3 = _base_rot.get("Torso", Vector3.ZERO)
	var arm_l: Vector3 = _base_rot.get("Arm_L", Vector3.ZERO)
	var arm_r: Vector3 = _base_rot.get("Arm_R", Vector3.ZERO)
	var elbow_l: Vector3 = _base_rot.get("Elbow_L", Vector3.ZERO)
	var elbow_r: Vector3 = _base_rot.get("Elbow_R", Vector3.ZERO)
	_set_joint("Torso", torso + Vector3(deg_to_rad(-8.0), 0.0, 0.0))
	_set_joint("Arm_L", arm_l + Vector3(deg_to_rad(-32.0), deg_to_rad(-10.0), 0.0))
	_set_joint("Arm_R", arm_r + Vector3(deg_to_rad(-36.0), deg_to_rad(10.0), 0.0))
	_set_joint("Elbow_L", elbow_l + Vector3(deg_to_rad(-58.0), 0.0, 0.0))
	_set_joint("Elbow_R", elbow_r + Vector3(deg_to_rad(-62.0), 0.0, 0.0))
