extends Node3D
class_name CivilianNpcProp
## Stationary wrapper for one character from the PSX Base Civilian pack.
##
## The pack ships as a single People.obj. Split per-character OBJ files live under
## source/characters/ and are parsed at runtime so they do not depend on Godot's
## import cache having run first.

const CivilianObjLoaderType = preload("res://scripts/civilian_obj_loader.gd")

enum CharacterVariant {
	SECRETARY,
	FEMALE_2,
	BLACK_SUIT,
	CASUAL_MALE,
}

const MESH_PATHS := {
	CharacterVariant.SECRETARY: "res://assets/psx-base-civilian-pack/source/characters/civilian_secretary.obj",
	CharacterVariant.FEMALE_2: "res://assets/psx-base-civilian-pack/source/characters/civilian_female_2.obj",
	CharacterVariant.BLACK_SUIT: "res://assets/psx-base-civilian-pack/source/characters/civilian_black_suit.obj",
	CharacterVariant.CASUAL_MALE: "res://assets/psx-base-civilian-pack/source/characters/civilian_casual_male.obj",
}

const TEXTURE_PATHS := {
	CharacterVariant.SECRETARY: "res://assets/psx-base-civilian-pack/textures/secretary_tex.png",
	CharacterVariant.FEMALE_2: "res://assets/psx-base-civilian-pack/textures/WOMAN_2048.jpg",
	CharacterVariant.BLACK_SUIT: "res://assets/psx-base-civilian-pack/textures/Black_Suit.png",
	CharacterVariant.CASUAL_MALE: "res://assets/psx-base-civilian-pack/textures/BodyTexture_(9).png",
}

const FACE_TEXTURE_PATHS := {
	CharacterVariant.BLACK_SUIT: "res://assets/psx-base-civilian-pack/textures/Guyface1.png",
	CharacterVariant.CASUAL_MALE: "res://assets/psx-base-civilian-pack/textures/ManFace_16.png",
}

const TARGET_HEIGHT := 1.72
const COLLISION_SIZE := Vector3(0.52, 1.72, 0.38)

@export var character_variant: CharacterVariant = CharacterVariant.SECRETARY
@export var build_on_ready := true
@export var collision_enabled := false
@export var nearest_texture_filtering := true
@export var cast_shadow := true

var _built := false
var _visual_root: Node3D
var _visual_model: MeshInstance3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D
static var _mesh_cache: Dictionary = {}


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	_built = true

	var mesh := _load_mesh(character_variant)
	if mesh == null:
		push_error("CivilianNpcProp could not load mesh for variant %s" % str(character_variant))
		return

	_visual_root = Node3D.new()
	_visual_root.name = "CharacterPivot"
	add_child(_visual_root)

	_visual_model = MeshInstance3D.new()
	_visual_model.name = "CharacterModel"
	_visual_model.mesh = mesh
	_visual_model.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	for surface_index in mesh.get_surface_count():
		var use_face_texture := surface_index > 0 and FACE_TEXTURE_PATHS.has(character_variant)
		var material := _make_character_material(character_variant, use_face_texture)
		_visual_model.set_surface_override_material(surface_index, material)
	_visual_root.add_child(_visual_model)

	_align_visual_to_ground()

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


func _load_mesh(variant: CharacterVariant) -> Mesh:
	if _mesh_cache.has(variant):
		return _mesh_cache[variant]

	var mesh_path: String = MESH_PATHS[variant]
	var mesh: Mesh = CivilianObjLoaderType.load_mesh(mesh_path)
	if mesh != null:
		_mesh_cache[variant] = mesh
	return mesh


func _align_visual_to_ground() -> void:
	# Pack meshes face -X; rotate that authored forward axis onto the game's -Z.
	_visual_root.rotation.y = -PI * 0.5

	var bounds := _visual_model.mesh.get_aabb()
	if bounds.size.y > 0.01 and bounds.size.y < TARGET_HEIGHT * 0.85:
		var scale_factor := TARGET_HEIGHT / bounds.size.y
		_visual_model.scale = Vector3.ONE * scale_factor
		bounds = AABB(bounds.position * scale_factor, bounds.size * scale_factor)

	_visual_model.position = Vector3(
		-(bounds.position.x + bounds.size.x * 0.5),
		-bounds.position.y,
		-(bounds.position.z + bounds.size.z * 0.5)
	)


func _make_character_material(variant: CharacterVariant, use_face_texture: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var texture_path: String = TEXTURE_PATHS[variant]
	if use_face_texture:
		texture_path = FACE_TEXTURE_PATHS[variant]
	var texture := load(texture_path) as Texture2D
	if texture != null:
		material.albedo_texture = texture
	material.metallic = 0.0
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	_collision_shape.position = Vector3(0.0, COLLISION_SIZE.y * 0.5, 0.0)
	_collision_body.add_child(_collision_shape)
