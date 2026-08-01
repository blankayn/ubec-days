extends Node3D
class_name GreenJacketNpcProp
## Reusable, stationary wrapper for the supplied rigged green-jacket character.

const CHARACTER_SCENE: PackedScene = preload(
	"res://assets/psx character npc/character-male-greenjacket-rigged/source/Character_Male_GreenJacket.fbx"
)
const ALBEDO_TEXTURE: Texture2D = preload(
	"res://assets/psx character npc/character-male-greenjacket-rigged/textures/Character_Male_GreenJacket_Albedo.png"
)

const COLLISION_CENTER := Vector3(0.0, 0.89, 0.0)
const COLLISION_SIZE := Vector3(0.54, 1.76, 0.40)

@export var build_on_ready := true
@export var collision_enabled := true
@export var nearest_texture_filtering := true
@export var cast_shadow := true

var _built := false
var _visual_model: Node3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _animation_player: AnimationPlayer


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	_visual_model = CHARACTER_SCENE.instantiate() as Node3D
	if _visual_model == null:
		push_error("GreenJacketNpcProp could not instantiate the supplied FBX")
		return
	_visual_model.name = "CharacterModel"
	# The authored character faces +Z; the game treats local -Z as forward.
	_visual_model.rotation.y = PI
	add_child(_visual_model)
	_strip_non_character_nodes(_visual_model)
	_prepare_visuals(_visual_model)
	if collision_enabled:
		_build_player_safe_collision()
	call_deferred("_play_idle_animation")


func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	if is_instance_valid(_collision_shape):
		_collision_shape.disabled = not enabled
	if is_instance_valid(_collision_body):
		_collision_body.collision_layer = 1 if enabled else 0
		_collision_body.collision_mask = 1 if enabled else 0


func get_visual_model() -> Node3D:
	return _visual_model


func get_collision_body() -> StaticBody3D:
	return _collision_body


func _strip_non_character_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is Light3D or child.name == &"Cube":
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
				var material := StandardMaterial3D.new()
				if source_material is StandardMaterial3D:
					material = (source_material as StandardMaterial3D).duplicate(true) as StandardMaterial3D
				material.albedo_texture = ALBEDO_TEXTURE
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


func _play_idle_animation() -> void:
	_animation_player = _find_animation_player(_visual_model)
	if _animation_player == null:
		push_warning("GreenJacketNpcProp: AnimationPlayer not found")
		return
	var animation_name := _choose_animation(_animation_player, ["idle", "mixamo"])
	if animation_name == &"":
		push_warning("GreenJacketNpcProp: no animation clip found")
		return
	var animation := _animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(animation_name)


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
	_collision_body.name = "PlayerSafeCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 1
	add_child(_collision_body)

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "BodyCollision"
	_collision_shape.position = COLLISION_CENTER
	var box := BoxShape3D.new()
	box.size = COLLISION_SIZE
	_collision_shape.shape = box
	_collision_body.add_child(_collision_shape)
