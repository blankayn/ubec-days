extends Node3D
class_name OldLockerProp
## Reusable wrapper for the supplied low-poly old locker FBX.
##
## The model is already authored at human scale: approximately 0.55 m wide,
## 2.00 m tall, and 0.47 m deep. Its base sits at local Y = 0. The locker
## door/front faces local +Z, so rotate this wrapper around Y to face a hall.
##
## When this node is parented to a CollisionObject3D (including Interactable),
## the collision shape is attached directly to that parent. This makes an
## interaction ray hit the Interactable instead of a separate prop body.

const LOCKER_SCENE: PackedScene = preload(
	"res://assets/low-poly-old-locker/source/LOCKER_FINAL.fbx"
)
const ALBEDO_TEXTURE: Texture2D = preload(
	"res://assets/low-poly-old-locker/textures/DefaultMaterial_Base_color.png"
)
const NORMAL_TEXTURE: Texture2D = preload(
	"res://assets/low-poly-old-locker/textures/DefaultMaterial_Normal_OpenGL.png"
)
const METALLIC_TEXTURE: Texture2D = preload(
	"res://assets/low-poly-old-locker/textures/DefaultMaterial_Metallic.png"
)
const ROUGHNESS_TEXTURE: Texture2D = preload(
	"res://assets/low-poly-old-locker/textures/DefaultMaterial_Roughness.png"
)
const AO_TEXTURE: Texture2D = preload(
	"res://assets/low-poly-old-locker/textures/internal_ground_ao_texture.jpeg"
)

const RAW_AABB := AABB(Vector3(-0.275, 0.0, -0.225), Vector3(0.55, 2.0, 0.467374))
const COLLISION_CENTER := Vector3(0.0, 0.99, 0.0087)
const COLLISION_SIZE := Vector3(0.52, 1.98, 0.43)

@export var build_on_ready := true
@export var collision_enabled := true
@export var nearest_texture_filtering := true
@export var cast_shadow := true

var _built := false
var _visual_model: Node3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	_visual_model = LOCKER_SCENE.instantiate() as Node3D
	if _visual_model == null:
		push_error("OldLockerProp could not instantiate LOCKER_FINAL.fbx")
		return
	_visual_model.name = "LockerModel"
	add_child(_visual_model)
	_strip_non_prop_nodes(_visual_model)
	_prepare_visuals(_visual_model)
	if collision_enabled:
		_build_player_safe_collision()


func attach_to_interactable(interactable: CollisionObject3D, local_transform := Transform3D.IDENTITY) -> void:
	## Convenience API for quest objects. Call this on a newly-created wrapper.
	## The wrapper visual and its box collider will share the supplied transform.
	if interactable == null:
		push_error("OldLockerProp.attach_to_interactable requires a valid CollisionObject3D")
		return
	if get_parent() != null:
		push_error("OldLockerProp must not already have a parent when attaching")
		return
	build_on_ready = false
	transform = local_transform
	interactable.add_child(self)
	build()


func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	if is_instance_valid(_collision_shape):
		_collision_shape.disabled = not enabled
	if is_instance_valid(_collision_body):
		_collision_body.collision_layer = 1 if enabled else 0
		_collision_body.collision_mask = 1 if enabled else 0


func get_visual_model() -> Node3D:
	return _visual_model


func get_collision_shape() -> CollisionShape3D:
	return _collision_shape


func get_collision_body() -> StaticBody3D:
	return _collision_body


func get_local_bounds() -> AABB:
	return RAW_AABB


func _strip_non_prop_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is AnimationPlayer:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_non_prop_nodes(child)


func _prepare_visuals(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		if mesh_instance.mesh != null:
			var material := _make_locker_material()
			for surface_index in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_prepare_visuals(child)


func _make_locker_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = ALBEDO_TEXTURE
	material.normal_enabled = true
	material.normal_texture = NORMAL_TEXTURE
	material.metallic = 1.0
	material.metallic_texture = METALLIC_TEXTURE
	material.roughness = 1.0
	material.roughness_texture = ROUGHNESS_TEXTURE
	material.ao_enabled = true
	material.ao_texture = AO_TEXTURE
	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if nearest_texture_filtering
		else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	)
	return material


func _build_player_safe_collision() -> void:
	# A single inset box is safer for a CharacterBody3D capsule than triangle
	# collision over the locker's vents, handle, and damaged door edges.
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "LockerCollision"
	var box := BoxShape3D.new()
	box.size = COLLISION_SIZE
	_collision_shape.shape = box

	var parent_collision_object := get_parent() as CollisionObject3D
	if parent_collision_object != null:
		_collision_shape.transform = transform * Transform3D(Basis.IDENTITY, COLLISION_CENTER)
		parent_collision_object.add_child(_collision_shape)
	else:
		_collision_body = StaticBody3D.new()
		_collision_body.name = "PlayerSafeCollision"
		_collision_body.collision_layer = 1
		_collision_body.collision_mask = 1
		add_child(_collision_body)
		_collision_shape.position = COLLISION_CENTER
		_collision_body.add_child(_collision_shape)
