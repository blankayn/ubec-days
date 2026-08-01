extends Node3D
class_name HorrorCreatureProp
## Reusable, non-colliding wrapper for the supplied animated PSX creature.
##
## The imported creature is roughly 6.38 m tall. This wrapper scales it to a
## 2.05 m scare silhouette and centers the complete animation envelope around
## this node's origin. That keeps positions authored for the former centered
## capsule placeholder compatible. The creature's face points toward local +X.

const CREATURE_SCENE: PackedScene = preload(
	"res://assets/psx-horror-creature/source/psx_horror_creature.fbx"
)
const CREATURE_TEXTURE: Texture2D = preload(
	"res://assets/psx-horror-creature/textures/psx_horror_creature.png"
)

const ANIMATION_NAME := &"Armature|ArmatureAction"
const ANIMATION_LENGTH := 3.0
const TARGET_HEIGHT := 2.05
const RAW_ANIMATION_BOUNDS := AABB(
	Vector3(-2.094168, 0.080308, -2.124375),
	Vector3(4.007917, 6.384459, 4.639936)
)
const MODEL_SCALE := TARGET_HEIGHT / RAW_ANIMATION_BOUNDS.size.y
const MODEL_CENTER := Vector3(-0.0902095, 3.2725375, 0.195593)

@export var build_on_ready := true
@export var start_visible := false
@export var play_animation_when_visible := true
@export var nearest_texture_filtering := true
@export var cast_shadow := true
@export var scare_light_energy := 2.4
@export var scare_light_range := 7.5

var _built := false
var _visual_model: Node3D
var _animation_player: AnimationPlayer
var _resolved_animation: StringName = StringName()
var _scare_light: OmniLight3D


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	_visual_model = CREATURE_SCENE.instantiate() as Node3D
	if _visual_model == null:
		push_error("HorrorCreatureProp could not instantiate psx_horror_creature.fbx")
		return
	_visual_model.name = "CreatureModel"
	# Scale and translate the whole imported hierarchy together so the skeleton,
	# mesh, and AnimationPlayer retain their authored relative node paths.
	_visual_model.scale = Vector3.ONE * MODEL_SCALE
	_visual_model.position = -MODEL_CENTER * MODEL_SCALE
	add_child(_visual_model)

	_prepare_visuals(_visual_model)
	_animation_player = _visual_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_resolved_animation = _resolve_animation_name()
	_prepare_looping_animation()
	_build_scare_light()
	set_scare_visible(start_visible)


func place_global(world_position: Vector3) -> void:
	if not _built:
		build()
	global_position = world_position


func set_scare_visible(show_creature: bool) -> void:
	if not _built:
		build()
	visible = show_creature
	if is_instance_valid(_scare_light):
		_scare_light.visible = show_creature
	if not is_instance_valid(_animation_player):
		return
	if show_creature and play_animation_when_visible and not _resolved_animation.is_empty():
		_animation_player.play(_resolved_animation)
	else:
		_animation_player.stop()


func face_toward(target_global_position: Vector3) -> void:
	# Keep the creature upright. Godot's look_at can align +Z; the final local
	# quarter-turn aligns the source model's actual +X-facing front instead.
	var flat_target := Vector3(target_global_position.x, global_position.y, target_global_position.z)
	if global_position.distance_squared_to(flat_target) <= 0.000001:
		return
	look_at(flat_target, Vector3.UP, true)
	rotate_object_local(Vector3.UP, -PI * 0.5)


func play_scare_animation(from_time := 0.0) -> void:
	if not _built:
		build()
	if not is_instance_valid(_animation_player) or _resolved_animation.is_empty():
		return
	_animation_player.play(_resolved_animation)
	_animation_player.seek(clampf(from_time, 0.0, get_animation_length()), true)


func stop_scare_animation() -> void:
	if is_instance_valid(_animation_player):
		_animation_player.stop()


func get_visual_model() -> Node3D:
	return _visual_model


func get_animation_player() -> AnimationPlayer:
	return _animation_player


func get_animation_name() -> StringName:
	return _resolved_animation if not _resolved_animation.is_empty() else ANIMATION_NAME


func get_animation_length() -> float:
	if is_instance_valid(_animation_player) and not _resolved_animation.is_empty():
		var animation := _animation_player.get_animation(_resolved_animation)
		if animation != null:
			return animation.length
	return ANIMATION_LENGTH


func get_raw_animation_bounds() -> AABB:
	return RAW_ANIMATION_BOUNDS


func get_centered_local_bounds() -> AABB:
	return AABB(
		(RAW_ANIMATION_BOUNDS.position - MODEL_CENTER) * MODEL_SCALE,
		RAW_ANIMATION_BOUNDS.size * MODEL_SCALE
	)


func get_model_scale() -> float:
	return MODEL_SCALE


func _prepare_visuals(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		# Keep the scare readable at street distance — imported LODs can vanish up close.
		mesh_instance.visibility_range_end = 0.0
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material := _make_creature_material(
					mesh_instance.get_active_material(surface_index)
				)
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_prepare_visuals(child)


func _build_scare_light() -> void:
	_scare_light = OmniLight3D.new()
	_scare_light.name = "ScareLight"
	_scare_light.position = Vector3(0.0, 1.35, 0.35)
	_scare_light.light_color = Color("d8e8f0")
	_scare_light.light_energy = scare_light_energy
	_scare_light.omni_range = scare_light_range
	_scare_light.shadow_enabled = false
	_scare_light.visible = false
	add_child(_scare_light)


func _resolve_animation_name() -> StringName:
	if not is_instance_valid(_animation_player):
		push_error("HorrorCreatureProp is missing its supplied AnimationPlayer")
		return StringName()
	var source_library := _animation_player.get_animation_library(&"")
	if source_library == null:
		push_error("HorrorCreatureProp is missing an animation library")
		return StringName()
	var animation_names := source_library.get_animation_list()
	if animation_names.is_empty():
		push_error("HorrorCreatureProp has no imported animations")
		return StringName()
	for animation_name in animation_names:
		if String(animation_name).contains("ArmatureAction"):
			return animation_name
	return animation_names[0]


func _make_creature_material(source: Material) -> StandardMaterial3D:
	var material: StandardMaterial3D
	if source is StandardMaterial3D:
		material = source.duplicate(true) as StandardMaterial3D
	else:
		material = StandardMaterial3D.new()
	material.albedo_texture = CREATURE_TEXTURE
	material.albedo_color = Color(0.88, 0.9, 0.94, 1.0)
	material.metallic = 0.0
	material.roughness = 0.96
	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if nearest_texture_filtering
		else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	)
	material.emission_enabled = true
	material.emission_texture = CREATURE_TEXTURE
	material.emission = Color(0.42, 0.46, 0.5, 1.0)
	material.emission_energy_multiplier = 0.95
	return material


func _prepare_looping_animation() -> void:
	if not is_instance_valid(_animation_player):
		return
	if _resolved_animation.is_empty():
		push_error("HorrorCreatureProp could not resolve a scare animation")
		return
	var source_library := _animation_player.get_animation_library(&"")
	if source_library == null or not source_library.has_animation(_resolved_animation):
		push_error("HorrorCreatureProp is missing %s" % String(_resolved_animation))
		return

	# Imported animation resources can be shared by multiple scene instances.
	# Give this instance its own looping clone instead of mutating the import.
	var runtime_library := AnimationLibrary.new()
	for animation_name in source_library.get_animation_list():
		var source_animation := source_library.get_animation(animation_name)
		var runtime_animation := source_animation.duplicate(true) as Animation
		if animation_name == _resolved_animation:
			runtime_animation.loop_mode = Animation.LOOP_LINEAR
		runtime_library.add_animation(animation_name, runtime_animation)
	_animation_player.remove_animation_library(&"")
	_animation_player.add_animation_library(&"", runtime_library)
