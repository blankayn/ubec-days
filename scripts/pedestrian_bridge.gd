extends Node3D
class_name PedestrianBridge
## Covered PSX-style pedestrian overpass linking the school and mall sides.
##
## The visible stair treads are intentionally non-colliding. Each flight uses one
## continuous collision ramp so the player cannot catch on step edges or seams.

const PSX_SHADER = preload("res://shaders/psx_surface.gdshader")

const CENTER_X := 38.0
const NORTH_LANDING_Z := -5.5
const SOUTH_LANDING_Z := 19.5
const NORTH_GROUND_Z := -15.0
const SOUTH_GROUND_Z := 28.5
const GROUND_Y := 0.20
const DECK_Y := 7.20
const FLOOR_WIDTH := 3.60
const GUARD_X_OFFSET := 1.72
const ROOF_POST_X_OFFSET := 1.95
const ROOF_HALF_WIDTH := 2.60
const ROOF_ROLL := 0.34
## Shared ridge height above the walking surface so deck, stairs, and canopies meet.
const ROOF_CLEARANCE := 3.35
## Pillars sit under the deck fascia, not outside the walkway.
const PILLAR_X_OFFSET := FLOOR_WIDTH * 0.5 - 0.15
const PILLAR_THICKNESS := 0.70
## Even support stations just inside the north/south landings.
const SUPPORT_Z_START := -4.0
const SUPPORT_Z_END := 18.0
const SUPPORT_STATION_COUNT := 5

var _material_cache: Dictionary = {}
var _bridge_lights: Array[OmniLight3D] = []
var _built := false


func build() -> void:
	if _built:
		return
	_built = true
	_build_main_span()
	_build_supports()
	_build_stair_flight("NorthStair", NORTH_GROUND_Z, NORTH_LANDING_Z, GROUND_Y, DECK_Y)
	_build_stair_flight("SouthStair", SOUTH_GROUND_Z, SOUTH_LANDING_Z, GROUND_Y, DECK_Y)
	_build_continuous_walk_collision()
	_build_mall_connection_canopy()
	_build_lighting()
	set_night_mode(false)


func set_night_mode(is_night: bool) -> void:
	for light in _bridge_lights:
		if is_instance_valid(light):
			light.light_energy = 1.65 if is_night else 0.05


func _support_z_positions() -> Array[float]:
	var positions: Array[float] = []
	for i in range(SUPPORT_STATION_COUNT):
		positions.append(lerpf(SUPPORT_Z_START, SUPPORT_Z_END, float(i) / float(SUPPORT_STATION_COUNT - 1)))
	return positions


func _build_main_span() -> void:
	var span_center_z := (NORTH_LANDING_Z + SOUTH_LANDING_Z) * 0.5
	var span_length := SOUTH_LANDING_Z - NORTH_LANDING_Z
	var covered_start := NORTH_LANDING_Z
	var covered_end := SOUTH_LANDING_Z
	var covered_center_z := span_center_z
	var covered_length := span_length
	var deck_color := Color("6f6558")
	var floor_color := Color("a99a82")
	var steel_color := Color("5e554a")
	var rail_color := Color("74746c")

	# The slab ends exactly where both continuous ramps reach DECK_Y.
	_box(
		"BridgeSpanFascia",
		Vector3(CENTER_X, DECK_Y - 0.22, span_center_z),
		Vector3(FLOOR_WIDTH, 0.44, span_length),
		deck_color,
		false
	)
	_box(
		"BridgeWalkingSurface",
		Vector3(CENTER_X, DECK_Y + 0.025, span_center_z),
		Vector3(FLOOR_WIDTH - 0.10, 0.05, span_length),
		floor_color,
		false
	)

	# One invisible barrier per side gives smooth, snag-free collision.
	for side in [-1.0, 1.0]:
		var side_x: float = CENTER_X + side * GUARD_X_OFFSET
		_collision_box(
			"BridgeGuardCollision_%s" % ("West" if side < 0.0 else "East"),
			Vector3(side_x, DECK_Y + 0.65, covered_center_z),
			Vector3(0.14, 1.30, covered_length)
		)
		_box(
			"BridgeLowerRail",
			Vector3(side_x, DECK_Y + 0.28, covered_center_z),
			Vector3(0.10, 0.14, covered_length),
			rail_color,
			false
		)
		_box(
			"BridgeUpperRail",
			Vector3(side_x, DECK_Y + 1.02, covered_center_z),
			Vector3(0.10, 0.12, covered_length),
			rail_color,
			false
		)
		for post_index in range(11):
			var post_z := lerpf(covered_start, covered_end, float(post_index) / 10.0)
			_box(
				"BridgeRailPost",
				Vector3(side_x, DECK_Y + 0.56, post_z),
				Vector3(0.11, 1.12, 0.11),
				steel_color,
				false
			)

	# Roof posts share the same Z stations as the ground pillars and reach the ridge.
	var roof_post_height := ROOF_CLEARANCE - 0.15
	var roof_post_center_y := DECK_Y + roof_post_height * 0.5
	for support_z in _support_z_positions():
		for side in [-1.0, 1.0]:
			_box(
				"BridgeRoofPost",
				Vector3(CENTER_X + side * ROOF_POST_X_OFFSET, roof_post_center_y, support_z),
				Vector3(0.16, roof_post_height, 0.16),
				steel_color,
				false
			)
	_build_pitched_roof(
		"BridgeMainRoof",
		Vector3(CENTER_X, DECK_Y + ROOF_CLEARANCE, covered_center_z),
		covered_length + 0.20,
		0.0,
		0.0
	)


func _build_supports() -> void:
	var concrete := Color("8b8375")
	var steel := Color("514d47")
	var pillar_height := DECK_Y - GROUND_Y
	var pillar_center_y := GROUND_Y + pillar_height * 0.5
	var crossbeam_width := PILLAR_X_OFFSET * 2.0 + PILLAR_THICKNESS
	for support_z in _support_z_positions():
		for side in [-1.0, 1.0]:
			_box(
				"BridgeSupportPillar",
				Vector3(CENTER_X + side * PILLAR_X_OFFSET, pillar_center_y, support_z),
				Vector3(PILLAR_THICKNESS, pillar_height, PILLAR_THICKNESS),
				concrete,
				true
			)
		_box(
			"BridgeSupportCrossbeam",
			Vector3(CENTER_X, DECK_Y - 0.48, support_z),
			Vector3(crossbeam_width, 0.42, 0.54),
			steel,
			false
		)


func _build_stair_flight(
	prefix: String,
	from_z: float,
	to_z: float,
	from_y: float,
	to_y: float
) -> void:
	var run := absf(to_z - from_z)
	var rise := to_y - from_y
	var slope_length := sqrt(run * run + rise * rise)
	var direction := signf(to_z - from_z)
	var slope_angle := atan2(rise, run)
	var rotation_x := -slope_angle * direction
	var center_z := (from_z + to_z) * 0.5
	var center_y := (from_y + to_y) * 0.5
	var step_color := Color("887867")
	var step_nose := Color("b09a7c")
	var rail_color := Color("6e706b")
	var frame_color := Color("58544d")

	# Twenty-four shallow treads retain the stair silhouette. Only the smooth
	# ramp beneath them participates in physics.
	var step_count := 24
	var step_depth := run / float(step_count)
	for step_index in range(step_count):
		var progress := float(step_index + 1) / float(step_count)
		var step_height := rise * progress
		var step_z := from_z + direction * step_depth * (float(step_index) + 0.5)
		_box(
			prefix + "Step_%02d" % (step_index + 1),
			Vector3(CENTER_X, from_y + step_height * 0.5, step_z),
			Vector3(FLOOR_WIDTH, maxf(step_height, 0.10), step_depth + 0.018),
			step_color,
			false
		)
		_box(
			prefix + "StepNose_%02d" % (step_index + 1),
			Vector3(CENTER_X, from_y + step_height + 0.018, step_z + direction * step_depth * 0.42),
			Vector3(FLOOR_WIDTH - 0.10, 0.035, 0.055),
			step_nose,
			false
		)
	# Ramp-aligned invisible guard volumes prevent falls without colliding with
	# every rail post individually.
	for side in [-1.0, 1.0]:
		var side_x: float = CENTER_X + side * GUARD_X_OFFSET
		_collision_box(
			prefix + ("WestGuard" if side < 0.0 else "EastGuard"),
			Vector3(side_x, center_y + 0.66, center_z),
			Vector3(0.14, 1.30, slope_length),
			Vector3(rotation_x, 0.0, 0.0)
		)
		_box(
			prefix + "LowerRail",
			Vector3(side_x, center_y + 0.34, center_z),
			Vector3(0.10, 0.14, slope_length),
			rail_color,
			false,
			Vector3(rotation_x, 0.0, 0.0)
		)
		_box(
			prefix + "UpperRail",
			Vector3(side_x, center_y + 1.02, center_z),
			Vector3(0.10, 0.12, slope_length),
			rail_color,
			false,
			Vector3(rotation_x, 0.0, 0.0)
		)
		for post_index in range(7):
			var progress := float(post_index) / 6.0
			var floor_y := lerpf(from_y, to_y, progress)
			var post_z := lerpf(from_z, to_z, progress)
			_box(
				prefix + "RailPost",
				Vector3(side_x, floor_y + 0.57, post_z),
				Vector3(0.10, 1.14, 0.10),
				rail_color,
				false
			)
			var canopy_post_height := ROOF_CLEARANCE - 0.15
			_box(
				prefix + "CanopyPost",
				Vector3(CENTER_X + side * ROOF_POST_X_OFFSET, floor_y + canopy_post_height * 0.5, post_z),
				Vector3(0.16, canopy_post_height, 0.16),
				frame_color,
				false
			)

	# Pitched roof follows the stair with the same clearance as the main deck roof.
	_build_pitched_roof(
		prefix + "Roof",
		Vector3(CENTER_X, center_y + ROOF_CLEARANCE, center_z),
		slope_length + 0.40,
		rotation_x,
		0.0
	)

	# Mid-flight concrete legs so stairs do not look cantilevered over the road.
	var mid_progress := 0.5
	var mid_z := lerpf(from_z, to_z, mid_progress)
	var mid_underside_y := lerpf(from_y, to_y, mid_progress) - 0.08
	var mid_pillar_height := maxf(mid_underside_y - GROUND_Y, 0.8)
	var mid_pillar_center_y := GROUND_Y + mid_pillar_height * 0.5
	var concrete := Color("8b8375")
	for side in [-1.0, 1.0]:
		_box(
			prefix + "MidSupport",
			Vector3(CENTER_X + side * PILLAR_X_OFFSET, mid_pillar_center_y, mid_z),
			Vector3(PILLAR_THICKNESS, mid_pillar_height, PILLAR_THICKNESS),
			concrete,
			true
		)

	# Contrasting threshold pads make both entrances easy to read.
	_box(
		prefix + "GroundThreshold",
		Vector3(CENTER_X, GROUND_Y + 0.025, from_z),
		Vector3(FLOOR_WIDTH + 0.40, 0.05, 1.40),
		Color("b7a98d"),
		false
	)


func _build_mall_connection_canopy() -> void:
	# The south flight continues through the parking corridor under a covered
	# approach, then turns west toward the mall-side pedestrian apron.
	_build_ground_canopy(
		"MallApproachCanopy",
		Vector3(CENTER_X, 0.0, 32.25),
		7.50,
		0.0
	)
	_build_ground_canopy(
		"MallLinkCanopy",
		Vector3(32.50, 0.0, 36.0),
		11.0,
		PI / 2.0
	)
	var sign := _box(
		"MallConnectionSign",
		Vector3(32.6, GROUND_Y + ROOF_CLEARANCE - 0.55, 35.94),
		Vector3(5.0, 0.62, 0.10),
		Color("eadfc5"),
		false
	)
	_add_front_label(sign, "MALL ENTRANCE  <", Color("82352f"))


func _build_ground_canopy(prefix: String, center: Vector3, length: float, yaw: float) -> void:
	var walkway_color := Color("b2a78e")
	var post_color := Color("6b6257")
	var local_length_direction := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, yaw)
	var local_width_direction := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, yaw)

	_box(
		prefix + "Paving",
		center + Vector3(0.0, GROUND_Y + 0.018, 0.0),
		Vector3(FLOOR_WIDTH, 0.036, length),
		walkway_color,
		false,
		Vector3(0.0, yaw, 0.0)
	)
	_build_pitched_roof(
		prefix + "Roof",
		center + Vector3(0.0, GROUND_Y + ROOF_CLEARANCE, 0.0),
		length + 0.60,
		0.0,
		yaw
	)
	var canopy_post_height := ROOF_CLEARANCE - 0.15
	for longitudinal_index in range(4):
		var longitudinal_offset := lerpf(-length * 0.5, length * 0.5, float(longitudinal_index) / 3.0)
		for side in [-1.0, 1.0]:
			var post_position := center
			post_position += local_length_direction * longitudinal_offset
			post_position += local_width_direction * ROOF_POST_X_OFFSET * side
			post_position.y = GROUND_Y + canopy_post_height * 0.5
			_box(
				prefix + "Post",
				post_position,
				Vector3(0.16, canopy_post_height, 0.16),
				post_color,
				false
			)


func _build_pitched_roof(
	prefix: String,
	position_value: Vector3,
	length: float,
	pitch_rotation_x: float,
	yaw: float
) -> void:
	var roof_root := Node3D.new()
	roof_root.name = prefix
	roof_root.position = position_value
	roof_root.rotation = Vector3(pitch_rotation_x, yaw, 0.0)
	add_child(roof_root)

	var tile_color := Color("a84d3d")
	var tile_highlight := Color("c66a50")
	for side in [-1.0, 1.0]:
		var roll: float = ROOF_ROLL if side < 0.0 else -ROOF_ROLL
		_box(
			prefix + "Tiles",
			Vector3(side * 1.20, -0.42, 0.0),
			Vector3(ROOF_HALF_WIDTH, 0.16, length),
			tile_color,
			false,
			Vector3(0.0, 0.0, roll),
			roof_root
		)
		var band_count := maxi(int(floor(length / 1.25)), 1)
		for band_index in range(band_count + 1):
			var band_z := lerpf(-length * 0.48, length * 0.48, float(band_index) / float(band_count))
			_box(
				prefix + "TileBand",
				Vector3(side * 1.20, -0.325, band_z),
				Vector3(ROOF_HALF_WIDTH - 0.08, 0.035, 0.065),
				tile_highlight,
				false,
				Vector3(0.0, 0.0, roll),
				roof_root
			)
	_cylinder(
		prefix + "RidgeCap",
		Vector3(0.0, 0.035, 0.0),
		0.15,
		length + 0.12,
		tile_highlight,
		Vector3(PI / 2.0, 0.0, 0.0),
		roof_root
	)


func _build_lighting() -> void:
	# Night fill only — no visible bulb/fixture meshes under the roof.
	for light_position in [
		Vector3(CENTER_X, DECK_Y + ROOF_CLEARANCE - 0.45, -4.0),
		Vector3(CENTER_X, DECK_Y + ROOF_CLEARANCE - 0.45, 7.0),
		Vector3(CENTER_X, DECK_Y + ROOF_CLEARANCE - 0.45, 18.0),
		Vector3(32.5, GROUND_Y + ROOF_CLEARANCE - 0.45, 36.0),
	]:
		var light := OmniLight3D.new()
		light.name = "BridgeWarmLight"
		light.position = light_position
		light.light_color = Color("ffd58c")
		light.omni_range = 7.2
		light.shadow_enabled = false
		add_child(light)
		_bridge_lights.append(light)


func _build_continuous_walk_collision() -> void:
	# Keep both ramps and the level deck in one concave shape. Separate collision
	# shapes expose their border edges to capsule recovery even when their planes
	# meet perfectly; one shared mesh has no artificial landing boundary.
	var body := StaticBody3D.new()
	body.name = "BridgeContinuousWalkSurface"
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	var faces := PackedVector3Array()
	_append_walk_quad(faces, NORTH_GROUND_Z, NORTH_LANDING_Z, GROUND_Y, DECK_Y, FLOOR_WIDTH - 0.12)
	_append_walk_quad(faces, NORTH_LANDING_Z, SOUTH_LANDING_Z, DECK_Y, DECK_Y, FLOOR_WIDTH - 0.12)
	_append_walk_quad(faces, SOUTH_LANDING_Z, SOUTH_GROUND_Z, DECK_Y, GROUND_Y, FLOOR_WIDTH - 0.12)
	shape.set_faces(faces)
	collision.shape = shape
	body.add_child(collision)


func _append_walk_quad(
	faces: PackedVector3Array,
	from_z: float,
	to_z: float,
	from_y: float,
	to_y: float,
	width: float
) -> void:
	var half_width := width * 0.5
	var from_left := Vector3(CENTER_X - half_width, from_y, from_z)
	var from_right := Vector3(CENTER_X + half_width, from_y, from_z)
	var to_left := Vector3(CENTER_X - half_width, to_y, to_z)
	var to_right := Vector3(CENTER_X + half_width, to_y, to_z)
	faces.append_array(PackedVector3Array([
		from_left, to_right, from_right,
		from_left, to_left, to_right,
	]))


func _collision_box(
	object_name: String,
	position_value: Vector3,
	size: Vector3,
	rotation_value: Vector3 = Vector3.ZERO
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position_value
	body.rotation = rotation_value
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _box(
	object_name: String,
	position_value: Vector3,
	size: Vector3,
	color: Color,
	with_collision: bool = true,
	rotation_value: Vector3 = Vector3.ZERO,
	parent: Node3D = self
) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = object_name + "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	if not with_collision:
		mesh_instance.position = position_value
		mesh_instance.rotation = rotation_value
		parent.add_child(mesh_instance)
		return mesh_instance
	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position_value
	body.rotation = rotation_value
	parent.add_child(body)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _cylinder(
	object_name: String,
	position_value: Vector3,
	radius: float,
	height: float,
	color: Color,
	rotation_value: Vector3,
	parent: Node3D
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = object_name
	mesh_instance.position = position_value
	mesh_instance.rotation = rotation_value
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_side_label(
	parent: Node3D,
	text_value: String,
	local_position: Vector3,
	color: Color,
	yaw: float
) -> void:
	var label := Label3D.new()
	label.name = "BannerText"
	label.text = text_value
	label.position = local_position
	label.rotation.y = yaw
	label.pixel_size = 0.0065
	label.font_size = 46
	label.modulate = color
	label.outline_size = 7
	label.outline_modulate = Color("1d2730")
	label.double_sided = true
	parent.add_child(label)


func _add_front_label(parent: Node3D, text_value: String, color: Color) -> void:
	var label := Label3D.new()
	label.name = "MallDirectionText"
	label.text = text_value
	label.position = Vector3(0.0, 0.0, -0.065)
	label.rotation.y = PI
	label.pixel_size = 0.0075
	label.font_size = 44
	label.modulate = color
	label.outline_size = 6
	label.outline_modulate = Color("eadfc5")
	label.double_sided = true
	parent.add_child(label)


func _material(color: Color) -> ShaderMaterial:
	var key := color.to_html(false)
	if _material_cache.has(key):
		return _material_cache[key] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.shader = PSX_SHADER
	material.set_shader_parameter("albedo_color", color)
	_material_cache[key] = material
	return material
