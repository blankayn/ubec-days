extends Node3D
class_name GroceryAisleProp
## Reusable wrapper for the user-supplied grocery aisle OBJ.
##
## Raw bounds are approximately 11.41 m long (local X), 2.06 m tall (Y), and
## 0.98 m deep (Z). The mesh is centered near the origin, so this wrapper lifts
## it until the base sits on local Y = 0. Rotate this node +90 degrees around Y
## to align the long shelf run with world Z (mall aisle orientation).
##
## Godot imports .obj files as ArrayMesh (not PackedScene like FBX).

const AISLE_MESH: Mesh = preload(
	"res://assets/grocery-aisle/source/textured_output.obj"
)
const ALBEDO_TEXTURE: Texture2D = preload(
	"res://assets/grocery-aisle/textures/textured_output.jpeg"
)

const RAW_AABB := AABB(Vector3(-5.702, -1.029, -0.48), Vector3(11.405, 2.06, 0.98))
const MODEL_Y_LIFT := 1.029
const COLLISION_CENTER := Vector3(0.0, 1.03, 0.0)
const COLLISION_SIZE := Vector3(11.2, 2.0, 0.85)

@export var build_on_ready := true
@export var collision_enabled := true
@export var nearest_texture_filtering := true
@export var cast_shadow := true

var _built := false
var _visual_model: MeshInstance3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	if AISLE_MESH == null:
		push_error("GroceryAisleProp could not preload textured_output.obj")
		return
	_visual_model = MeshInstance3D.new()
	_visual_model.name = "AisleModel"
	_visual_model.mesh = AISLE_MESH
	_visual_model.position = Vector3(0.0, MODEL_Y_LIFT, 0.0)
	_visual_model.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	var material := _make_aisle_material()
	for surface_index in AISLE_MESH.get_surface_count():
		_visual_model.set_surface_override_material(surface_index, material)
	add_child(_visual_model)
	if collision_enabled:
		_build_player_safe_collision()


func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	if is_instance_valid(_collision_shape):
		_collision_shape.disabled = not enabled
	if is_instance_valid(_collision_body):
		_collision_body.collision_layer = 1 if enabled else 0
		_collision_body.collision_mask = 1 if enabled else 0


func get_visual_model() -> MeshInstance3D:
	return _visual_model


func get_collision_body() -> StaticBody3D:
	return _collision_body


func get_local_bounds() -> AABB:
	return AABB(
		Vector3(RAW_AABB.position.x, 0.0, RAW_AABB.position.z),
		Vector3(RAW_AABB.size.x, RAW_AABB.size.y, RAW_AABB.size.z)
	)


func _make_aisle_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = ALBEDO_TEXTURE
	material.metallic = 0.0
	material.roughness = 0.88
	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if nearest_texture_filtering
		else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	)
	return material


func _build_player_safe_collision() -> void:
	# A single inset box avoids CharacterBody3D snags on dense product geometry.
	_collision_body = StaticBody3D.new()
	_collision_body.name = "PlayerSafeCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 1
	add_child(_collision_body)

	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "AisleCollision"
	_collision_shape.position = COLLISION_CENTER
	var box := BoxShape3D.new()
	box.size = COLLISION_SIZE
	_collision_shape.shape = box
	_collision_body.add_child(_collision_shape)
