extends Node3D
class_name BusStopProp
## Reusable wrapper for the user-supplied low-poly bus shelter.
##
## The FBX is authored at an appropriate real-world scale (roughly
## 2.50 m deep x 2.73 m high x 5.35 m long). Its open passenger side faces
## local +X. Rotate this node +90 degrees around Y to face the opening north.

const BUS_STOP_SCENE: PackedScene = preload(
	"res://assets/abribus-bus-stop-bus-station/source/abribus.fbx"
)

@export var build_on_ready := true
@export var nearest_texture_filtering := true
@export var collision_enabled := true

var _built := false
var _visual_model: Node3D
var _collision_body: StaticBody3D


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	_visual_model = BUS_STOP_SCENE.instantiate() as Node3D
	if _visual_model == null:
		push_error("BusStopProp could not instantiate the bus-stop FBX")
		return
	_visual_model.name = "ShelterModel"
	add_child(_visual_model)
	_strip_non_prop_nodes(_visual_model)
	_prepare_materials(_visual_model)
	if collision_enabled:
		_build_player_safe_collision()


func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	if is_instance_valid(_collision_body):
		_collision_body.collision_layer = 1 if enabled else 0
		_collision_body.collision_mask = 1 if enabled else 0


func get_visual_model() -> Node3D:
	return _visual_model


func get_collision_body() -> StaticBody3D:
	return _collision_body


func _strip_non_prop_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is AnimationPlayer:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_non_prop_nodes(child)


func _prepare_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.get_active_material(surface_index)
				if source_material == null:
					continue
				var material := source_material.duplicate(true)
				if material is BaseMaterial3D:
					var base_material := material as BaseMaterial3D
					if nearest_texture_filtering:
						base_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					base_material.metallic = 0.0
					base_material.roughness = maxf(base_material.roughness, 0.82)
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_prepare_materials(child)


func _build_player_safe_collision() -> void:
	# Simple boxes avoid the sharp triangle seams and paper-thin faces that make
	# imported mesh collision snag a CharacterBody3D capsule.
	_collision_body = StaticBody3D.new()
	_collision_body.name = "PlayerSafeCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 1
	add_child(_collision_body)

	_add_collision_box("BaseSlab", Vector3(0.0, 0.0, 0.0), Vector3(2.50, 0.08, 5.35))
	_add_collision_box("BackWall", Vector3(-0.98, 1.30, 0.16), Vector3(0.18, 2.55, 4.28))
	_add_collision_box("EndPanelNorth", Vector3(0.07, 1.30, -1.95), Vector3(2.10, 2.40, 0.18))
	_add_collision_box("EndPanelSouth", Vector3(0.05, 1.28, 2.28), Vector3(1.55, 2.38, 0.20))
	_add_collision_box("Roof", Vector3(0.05, 2.62, 0.15), Vector3(2.20, 0.22, 4.35))
	_add_collision_box("Bench", Vector3(-0.70, 0.43, 0.53), Vector3(0.65, 0.82, 1.90))


func _add_collision_box(shape_name: String, center: Vector3, size: Vector3) -> void:
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = shape_name
	collision_shape.position = center
	var box := BoxShape3D.new()
	box.size = size
	collision_shape.shape = box
	_collision_body.add_child(collision_shape)
