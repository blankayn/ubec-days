extends Node3D
class_name StreetVehicleProp
## Wrapper for exported Three.js PSX street cars / jeepneys.
## Models are authored with ground at y=0 and nose facing local +X.

enum Kind { STREET_CAR, JEEPNEY }

const STREET_CAR_PATHS := [
	"res://assets/psx-vehicles/street_car.glb",
	"res://assets/psx-vehicles/street_car_b.glb",
	"res://assets/psx-vehicles/street_car_c.glb",
	"res://assets/psx-vehicles/street_car_d.glb",
]

const JEEPNEY_PATHS := [
	"res://assets/psx-vehicles/jeepney_62.glb",
	"res://assets/psx-vehicles/jeepney_13c.glb",
]

@export var kind: Kind = Kind.STREET_CAR
@export var variant_index: int = 0
@export var build_on_ready := true
@export var collision_enabled := true
@export var nearest_texture_filtering := true

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
	var path := _resolve_path()
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("StreetVehicleProp could not load: %s" % path)
		return
	_visual_model = packed.instantiate() as Node3D
	if _visual_model == null:
		push_error("StreetVehicleProp could not instantiate: %s" % path)
		return
	_visual_model.name = "VehicleModel"
	add_child(_visual_model)
	_strip_non_prop_nodes(_visual_model)
	_prepare_materials(_visual_model)
	if collision_enabled:
		_build_player_safe_collision()


func configure(vehicle_kind: Kind, variant: int = 0, with_collision: bool = true) -> void:
	kind = vehicle_kind
	variant_index = variant
	collision_enabled = with_collision


func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	if is_instance_valid(_collision_body):
		_collision_body.collision_layer = 1 if enabled else 0
		_collision_body.collision_mask = 1 if enabled else 0


func get_visual_model() -> Node3D:
	return _visual_model


func _resolve_path() -> String:
	if kind == Kind.JEEPNEY:
		return JEEPNEY_PATHS[posmod(variant_index, JEEPNEY_PATHS.size())]
	return STREET_CAR_PATHS[posmod(variant_index, STREET_CAR_PATHS.size())]


func _strip_non_prop_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is AnimationPlayer or child is Light3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_non_prop_nodes(child)


func _prepare_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_collision_body = StaticBody3D.new()
	_collision_body.name = "PlayerSafeCollision"
	_collision_body.collision_layer = 1
	_collision_body.collision_mask = 1
	add_child(_collision_body)

	var size := Vector3(4.6, 1.55, 1.9)
	var center := Vector3(0.0, 0.78, 0.0)
	if kind == Kind.JEEPNEY:
		size = Vector3(6.2, 2.15, 2.15)
		center = Vector3(0.1, 1.05, 0.0)

	var shape := CollisionShape3D.new()
	shape.name = "BodyCollision"
	shape.position = center
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_collision_body.add_child(shape)
