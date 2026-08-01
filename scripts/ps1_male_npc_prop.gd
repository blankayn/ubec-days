extends Node3D
class_name Ps1MaleNpcProp
## Reusable wrapper for the supplied PS1-style male character FBX.
##
## Source mesh is ~0.74 m wide, 1.91 m tall, 0.32 m deep in bind pose. The
## imported `rig` node carries Blender's unit scale (×100) and −90° X rotation;
## skin bind poses cancel that so the skinned silhouette stands ~1.9 m tall with
## feet near local Y = 0. The authored mesh faces local +Z, so the model is
## rotated 180° here to match the game's −Z forward convention used by patrols.

const CHARACTER_SCENE: PackedScene = preload(
	"res://assets/male-character-ps1-style/source/hero.fbx"
)
const ALBEDO_TEXTURE: Texture2D = preload(
	"res://assets/male-character-ps1-style/textures/man_tex.png"
)
const AnimatorType = preload("res://scripts/ps1_male_npc_animator.gd")

const RAW_MESH_AABB := AABB(Vector3(-0.371339, 0.00067, -0.18576), Vector3(0.742679, 1.909518, 0.320195))
const COLLISION_CENTER := Vector3(0.0, 0.95, 0.0)
const COLLISION_SIZE := Vector3(0.55, 1.88, 0.42)

@export var build_on_ready := true
@export var collision_enabled := true
@export var nearest_texture_filtering := true
@export var cast_shadow := true
@export var animate_walk := true
@export var tint := Color.WHITE

var _built := false
var _visual_model: Node3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _animator: Node


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	_visual_model = CHARACTER_SCENE.instantiate() as Node3D
	if _visual_model == null:
		push_error("Ps1MaleNpcProp could not instantiate hero.fbx")
		return
	_visual_model.name = "CharacterModel"
	# FBX faces +Z; patrol yaw and the animator both assume −Z is forward.
	_visual_model.rotation.y = PI
	add_child(_visual_model)
	_strip_non_prop_nodes(_visual_model)
	_prepare_visuals(_visual_model)
	if animate_walk:
		_animator = AnimatorType.new()
		_animator.name = "ProceduralWalkAnimator"
		add_child(_animator)
	if collision_enabled:
		_build_player_safe_collision()


func set_tint(color: Color) -> void:
	tint = color
	if _built:
		_prepare_visuals(_visual_model)


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


func get_local_bounds() -> AABB:
	return RAW_MESH_AABB


func _strip_non_prop_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is AnimationPlayer or child is Light3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_non_prop_nodes(child)


func _prepare_visuals(node: Node) -> void:
	if node == null:
		return
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
				mesh_instance.set_surface_override_material(
					surface_index,
					_make_character_material(source_material)
				)
	for child in node.get_children():
		_prepare_visuals(child)


func _make_character_material(source: Material) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if source is StandardMaterial3D:
		material = (source as StandardMaterial3D).duplicate(true) as StandardMaterial3D
	material.albedo_texture = ALBEDO_TEXTURE
	material.albedo_color = tint
	material.metallic = 0.0
	material.roughness = 0.92
	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if nearest_texture_filtering
		else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	)
	return material


func _build_player_safe_collision() -> void:
	_collision_body = StaticBody3D.new()
	_collision_body.name = "PlayerSafeCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 1
	add_child(_collision_body)

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "BodyCollision"
	var box := BoxShape3D.new()
	box.size = COLLISION_SIZE
	_collision_shape.shape = box
	_collision_shape.position = COLLISION_CENTER
	_collision_body.add_child(_collision_shape)
