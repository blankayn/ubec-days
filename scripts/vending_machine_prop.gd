extends Node3D
class_name VendingMachineProp
## Reusable wrapper for the supplied pixel-art vending machine.
##
## Source mesh is authored in pixel units and exported near human scale (~1.85 m).
## The glass/front faces local +X, so rotate this node to aim the front into a room.

const VENDING_SCENE: PackedScene = preload(
	"res://assets/pixel-art-vending-machine/source/vending_machine.fbx"
)
const BODY_TEXTURE: Texture2D = preload(
	"res://assets/pixel-art-vending-machine/textures/VencingMachineTexture.png"
)
const GLASS_TEXTURE: Texture2D = preload(
	"res://assets/pixel-art-vending-machine/textures/VendingMachineGlass.png"
)

const TARGET_HEIGHT := 1.85
const COLLISION_CENTER := Vector3(0.0, TARGET_HEIGHT * 0.5, 0.0)
const COLLISION_SIZE := Vector3(0.70, TARGET_HEIGHT, 1.30)

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
	_visual_model = VENDING_SCENE.instantiate() as Node3D
	if _visual_model == null:
		push_error("VendingMachineProp could not instantiate vending_machine.fbx")
		return
	_visual_model.name = "VendingModel"
	add_child(_visual_model)
	_strip_non_prop_nodes(_visual_model)
	_prepare_visuals(_visual_model)
	if collision_enabled:
		_build_player_safe_collision()


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


func _strip_non_prop_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is AnimationPlayer or child is Light3D:
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
		var node_name := String(mesh_instance.name).to_lower()
		var material := _make_body_material()
		if "glass" in node_name:
			material = _make_glass_material()
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_prepare_visuals(child)


func _make_body_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = BODY_TEXTURE
	material.metallic = 0.05
	material.roughness = 0.9
	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if nearest_texture_filtering
		else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	)
	return material


func _make_glass_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = GLASS_TEXTURE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic = 0.0
	material.roughness = 0.15
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
	_collision_shape.name = "VendingCollision"
	_collision_shape.position = COLLISION_CENTER
	var box := BoxShape3D.new()
	box.size = COLLISION_SIZE
	_collision_shape.shape = box
	_collision_body.add_child(_collision_shape)
