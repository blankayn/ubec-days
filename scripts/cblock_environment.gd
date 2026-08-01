extends Node3D
## A deterministic, exterior-only city district made from Godot primitives.
## No scanned city geometry or generated scan collision is used at runtime.

const MAP_HALF_X := 78.0
const MAP_HALF_Z := 58.0
const ROAD_LEVEL := 0.012
const DETAIL_LEVEL := 0.026
const STORE_711_SCENE := preload("res://assets/7-11-convenience-store/source/7-11.glb")
# Authored footprint of Mesh27 (the real store shell). Used to plant the model
# with its front facing the plaza and its feet on the sidewalk.
const STORE_711_TARGET_WIDTH := 22.0

var _materials: Dictionary = {}
var _ground_root: Node3D
var _road_root: Node3D
var _building_root: Node3D
var _landmark_root: Node3D
var _prop_root: Node3D
var _collision_root: Node3D
var _building_count := 0


func _ready() -> void:
	_create_containers()
	_build_ground()
	_build_road_loop()
	_build_central_plaza()
	_build_city_blocks()
	_build_park()
	_build_parking_lot()
	_build_street_furniture()
	_build_boundaries()
	set_meta("uses_imported_city", false)
	set_meta("building_count", _building_count)
	set_meta("district_style", "modern_low_poly")
	print(
		"CBLOCK_WORLD_READY buildings=%d trees=%d imported_city=false"
		% [_building_count, _tree_positions().size()]
	)


func _create_containers() -> void:
	_ground_root = _container("Ground")
	_road_root = _container("RoadNetwork")
	_building_root = _container("Buildings")
	_landmark_root = _container("Landmarks")
	_prop_root = _container("StreetProps")
	_collision_root = _container("WorldCollision")


func _container(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	return node


func _build_ground() -> void:
	# The single physical walking plane has its top exactly at Y = 0. Decorative
	# road and pavement layers are only a few centimetres thick.
	_box(
		"DistrictGround",
		Vector3(0.0, -0.3, 0.0),
		Vector3(MAP_HALF_X * 2.0, 0.6, MAP_HALF_Z * 2.0),
		"ground",
		true,
		_ground_root,
		false
	)

	# Green perimeter verges soften the edge of the compact playable district.
	_box("NorthVerge", Vector3(0, DETAIL_LEVEL, -54), Vector3(154, 0.05, 8), "verge", false, _ground_root)
	_box("SouthVerge", Vector3(0, DETAIL_LEVEL, 54), Vector3(154, 0.05, 8), "verge", false, _ground_root)
	_box("WestVerge", Vector3(-74, DETAIL_LEVEL, 0), Vector3(8, 0.05, 100), "verge", false, _ground_root)
	_box("EastVerge", Vector3(74, DETAIL_LEVEL, 0), Vector3(8, 0.05, 100), "verge", false, _ground_root)


func _build_road_loop() -> void:
	# A simple two-block circulation loop around the plaza.
	_box("NorthAvenue", Vector3(0, ROAD_LEVEL, -19), Vector3(148, 0.024, 10), "asphalt", false, _road_root)
	_box("SouthAvenue", Vector3(0, ROAD_LEVEL, 19), Vector3(148, 0.024, 10), "asphalt", false, _road_root)
	_box("WestConnector", Vector3(-24, ROAD_LEVEL, 0), Vector3(10, 0.024, 28), "asphalt", false, _road_root)
	_box("EastConnector", Vector3(24, ROAD_LEVEL, 0), Vector3(10, 0.024, 28), "asphalt", false, _road_root)

	# Outer sidewalks and the raised-looking plaza curb are decorative, while
	# the physical ground remains continuous so the controller never snags.
	for z_value in [-25.0, -13.0, 13.0, 25.0]:
		_box(
			"HorizontalWalk_%d" % int(z_value),
			Vector3(0, DETAIL_LEVEL, z_value),
			Vector3(148, 0.052, 2.0),
			"sidewalk",
			false,
			_road_root
		)
	for x_value in [-30.0, -18.0, 18.0, 30.0]:
		_box(
			"VerticalWalk_%d" % int(x_value),
			Vector3(x_value, DETAIL_LEVEL, 0),
			Vector3(2.0, 0.052, 28.0),
			"sidewalk",
			false,
			_road_root
		)

	# Warm center lines and short white lane dashes.
	_box("NorthCenterLine", Vector3(0, 0.03, -19), Vector3(146, 0.018, 0.12), "road_yellow", false, _road_root)
	_box("SouthCenterLine", Vector3(0, 0.03, 19), Vector3(146, 0.018, 0.12), "road_yellow", false, _road_root)
	for x_value in range(-68, 69, 10):
		_box(
			"NorthLane_%d" % x_value,
			Vector3(float(x_value), 0.035, -21.5),
			Vector3(4.4, 0.018, 0.11),
			"road_white",
			false,
			_road_root
		)
		_box(
			"SouthLane_%d" % x_value,
			Vector3(float(x_value), 0.035, 21.5),
			Vector3(4.4, 0.018, 0.11),
			"road_white",
			false,
			_road_root
		)
	for z_value in range(-10, 11, 7):
		for x_value in [-24.0, 24.0]:
			_box(
				"ConnectorLane_%d_%d" % [int(x_value), z_value],
				Vector3(x_value, 0.035, float(z_value)),
				Vector3(0.11, 0.018, 3.2),
				"road_white",
				false,
				_road_root
			)

	# Four highly readable pedestrian entries into the central plaza.
	_crosswalk(Vector3(-24, 0.042, -13.9), false)
	_crosswalk(Vector3(24, 0.042, -13.9), false)
	_crosswalk(Vector3(-24, 0.042, 13.9), false)
	_crosswalk(Vector3(24, 0.042, 13.9), false)
	_crosswalk(Vector3(-18.9, 0.042, 0), true)
	_crosswalk(Vector3(18.9, 0.042, 0), true)


func _crosswalk(center: Vector3, stripes_along_x: bool) -> void:
	for index in range(7):
		var offset := (float(index) - 3.0) * 0.78
		var stripe_position := center
		var stripe_size := Vector3(0.48, 0.02, 3.6)
		if stripes_along_x:
			stripe_position.z += offset
			stripe_size = Vector3(3.6, 0.02, 0.48)
		else:
			stripe_position.x += offset
		_box(
			"Crosswalk_%d_%d" % [int(center.x * 10.0), index],
			stripe_position,
			stripe_size,
			"road_white",
			false,
			_road_root
		)


func _build_central_plaza() -> void:
	_box("PlazaSlab", Vector3(0, DETAIL_LEVEL, 0), Vector3(36, 0.052, 26), "plaza", false, _landmark_root)

	# Geometric paving directs the player toward each exit while leaving a
	# generous clear spawn circle in the middle.
	_box("PlazaAxisNS", Vector3(0, 0.057, 0), Vector3(4.0, 0.016, 25.2), "plaza_light", false, _landmark_root)
	_box("PlazaAxisEW", Vector3(0, 0.058, 0), Vector3(35.2, 0.016, 4.0), "plaza_light", false, _landmark_root)
	for corner in [
		Vector3(-13.2, 0.16, -8.4),
		Vector3(13.2, 0.16, -8.4),
		Vector3(-13.2, 0.16, 8.4),
		Vector3(13.2, 0.16, 8.4),
	]:
		_box("PlazaPlanter", corner, Vector3(5.4, 0.28, 3.0), "planter", true, _landmark_root)
		_box("PlazaPlanting", corner + Vector3(0, 0.17, 0), Vector3(4.8, 0.1, 2.4), "grass", false, _landmark_root)

	# A simple sculptural marker sits north of spawn and does not obstruct it.
	_cylinder("PlazaSculptureBase", Vector3(0, 0.32, -8.6), 1.55, 0.6, "stone", true, _landmark_root, 12)
	var sculpture := _box(
		"PlazaSculpture",
		Vector3(0, 2.35, -8.6),
		Vector3(0.65, 3.7, 0.65),
		"accent_coral",
		true,
		_landmark_root
	)
	sculpture.rotation_degrees = Vector3(0, 0, 18)
	_box("PlazaSculptureCross", Vector3(0, 3.15, -8.6), Vector3(2.8, 0.45, 0.45), "accent_gold", false, _landmark_root)

	# Freestanding district identity sign.
	_box("DistrictSignFoot", Vector3(0, 0.26, 9.7), Vector3(8.4, 0.48, 0.55), "charcoal", true, _landmark_root)
	_box("DistrictSignFace", Vector3(0, 1.15, 9.55), Vector3(7.6, 1.3, 0.22), "accent_teal", false, _landmark_root)
	_add_label(
		"DistrictLabel",
		"C  BLOCK",
		Vector3(0, 1.16, 9.41),
		Vector3(0, PI, 0),
		_landmark_root,
		0.012,
		64
	)


func _build_city_blocks() -> void:
	_modern_building(
		"NorthwestOffices",
		Vector3(-51, 0, -39),
		Vector2(30, 22),
		7,
		"concrete_cool",
		"glass_blue",
		"accent_teal",
		Vector3(0, 0, 1)
	)
	_modern_building(
		"NorthApartments",
		Vector3(-15, 0, -40),
		Vector2(24, 20),
		5,
		"warm_white",
		"glass_dark",
		"accent_coral",
		Vector3(0, 0, 1)
	)
	_modern_building(
		"NortheastTower",
		Vector3(20, 0, -40),
		Vector2(26, 21),
		6,
		"concrete_light",
		"glass_teal",
		"accent_gold",
		Vector3(0, 0, 1)
	)
	_modern_building(
		"EastLofts",
		Vector3(58, 0, -39),
		Vector2(22, 20),
		4,
		"brick",
		"glass_dark",
		"warm_white",
		Vector3(0, 0, 1)
	)

	_build_retail_row()
	_modern_building(
		"SouthResidences",
		Vector3(27, 0, 39),
		Vector2(29, 21),
		5,
		"warm_white",
		"glass_blue",
		"accent_teal",
		Vector3(0, 0, -1)
	)
	_build_parking_garage()
	_build_civic_center()


func _modern_building(
	node_name: String,
	center: Vector3,
	footprint: Vector2,
	floors: int,
	wall_material: String,
	window_material: String,
	accent_material: String,
	front: Vector3
) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = center
	_building_root.add_child(root)
	_building_count += 1

	var floor_height := 3.15
	var height := float(floors) * floor_height
	_box(
		"MainMass",
		Vector3(0, height * 0.5, 0),
		Vector3(footprint.x, height, footprint.y),
		wall_material,
		true,
		root
	)
	_box(
		"RoofCap",
		Vector3(0, height + 0.24, 0),
		Vector3(footprint.x + 0.45, 0.48, footprint.y + 0.45),
		accent_material,
		false,
		root
	)

	for floor_index in floors:
		var band_y := 1.42 + float(floor_index) * floor_height
		_box(
			"WindowNorth_%02d" % floor_index,
			Vector3(0, band_y, -footprint.y * 0.5 - 0.055),
			Vector3(footprint.x - 2.0, 1.45, 0.11),
			window_material,
			false,
			root
		)
		_box(
			"WindowSouth_%02d" % floor_index,
			Vector3(0, band_y, footprint.y * 0.5 + 0.055),
			Vector3(footprint.x - 2.0, 1.45, 0.11),
			window_material,
			false,
			root
		)
		_box(
			"WindowWest_%02d" % floor_index,
			Vector3(-footprint.x * 0.5 - 0.055, band_y, 0),
			Vector3(0.11, 1.45, footprint.y - 2.0),
			window_material,
			false,
			root
		)
		_box(
			"WindowEast_%02d" % floor_index,
			Vector3(footprint.x * 0.5 + 0.055, band_y, 0),
			Vector3(0.11, 1.45, footprint.y - 2.0),
			window_material,
			false,
			root
		)

	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			_box(
				"CornerColumn",
				Vector3(
					x_sign * (footprint.x * 0.5 - 0.45),
					height * 0.5,
					z_sign * (footprint.y * 0.5 - 0.45)
				),
				Vector3(0.55, height + 0.08, 0.55),
				accent_material,
				false,
				root
			)

	_add_building_entrance(root, footprint, front, accent_material, window_material)
	_box(
		"RooftopPlant",
		Vector3(footprint.x * 0.18, height + 0.85, -footprint.y * 0.08),
		Vector3(3.4, 1.2, 2.4),
		"charcoal",
		false,
		root
	)


func _add_building_entrance(
	root: Node3D,
	footprint: Vector2,
	front: Vector3,
	accent_material: String,
	window_material: String
) -> void:
	var door_position := Vector3.ZERO
	var door_size := Vector3(2.8, 2.35, 0.14)
	var canopy_position := Vector3(0, 2.65, 0)
	var canopy_size := Vector3(5.2, 0.22, 2.0)
	if absf(front.z) > 0.5:
		door_position = Vector3(0, 1.18, front.z * (footprint.y * 0.5 + 0.08))
		canopy_position.z = front.z * (footprint.y * 0.5 + 0.85)
	else:
		door_position = Vector3(front.x * (footprint.x * 0.5 + 0.08), 1.18, 0)
		door_size = Vector3(0.14, 2.35, 2.8)
		canopy_position.x = front.x * (footprint.x * 0.5 + 0.85)
		canopy_size = Vector3(2.0, 0.22, 5.2)
	_box("EntranceDoor", door_position, door_size, window_material, false, root)
	_box("EntranceCanopy", canopy_position, canopy_size, accent_material, false, root)


func _build_retail_row() -> void:
	# Replace the old three-box "convenience" strip with the real 7-11 GLB.
	var root := Node3D.new()
	root.name = "SouthwestRetail"
	root.position = Vector3(-51, 0, 39)
	_building_root.add_child(root)
	_building_count += 1

	var model := STORE_711_SCENE.instantiate() as Node3D
	if model == null:
		push_error("Could not instantiate the 7-11 convenience store GLB.")
		return
	model.name = "SevenEleven"
	root.add_child(model)
	_strip_store_junk(model, Transform3D.IDENTITY)

	var bounds := _combined_mesh_aabb(model)
	if bounds.size == Vector3.ZERO:
		push_error("7-11 convenience store has no usable mesh bounds.")
		return

	# Scale to a street-facing footprint that fills the old retail pad, then
	# center the shell on the pad with its feet on the ground.
	var scale_factor: float = STORE_711_TARGET_WIDTH / maxf(bounds.size.x, 0.001)
	model.scale = Vector3.ONE * scale_factor
	var scaled_bounds := AABB(bounds.position * scale_factor, bounds.size * scale_factor)
	model.position = Vector3(
		-(scaled_bounds.position.x + scaled_bounds.size.x * 0.5),
		-scaled_bounds.position.y,
		-(scaled_bounds.position.z + scaled_bounds.size.z * 0.5)
	)

	# Collide against the solid shell only (Mesh27), inset so awnings / window
	# glass / curb props don't keep the player a car-length away from the door.
	var shell_bounds := _mesh_aabb_by_name(model, "Mesh27")
	if shell_bounds.size == Vector3.ZERO:
		shell_bounds = bounds
	shell_bounds.position *= scale_factor
	shell_bounds.size *= scale_factor
	var shell_center := shell_bounds.position + shell_bounds.size * 0.5 + model.position
	var collision_size := Vector3(
		maxf(shell_bounds.size.x - 1.2, 8.0),
		shell_bounds.size.y,
		maxf(shell_bounds.size.z - 2.4, 8.0)
	)
	_box(
		"SevenElevenCollision",
		Vector3(shell_center.x, collision_size.y * 0.5, shell_center.z),
		collision_size,
		"concrete_light",
		true,
		root,
		false
	)
	# Hide the collision visual — keep only the StaticBody for physics.
	var collision_visual := root.get_node_or_null("SevenElevenCollision") as MeshInstance3D
	if collision_visual != null:
		collision_visual.visible = false


## Drop the giant zero-height SketchUp ground plane and other degenerate CAD junk
## that inflate the imported AABB to hundreds of meters.
func _strip_store_junk(node: Node, parent_xform: Transform3D) -> void:
	var local_xform := parent_xform
	if node is Node3D:
		local_xform = parent_xform * (node as Node3D).transform
	for child in node.get_children():
		_strip_store_junk(child, local_xform)
	if not (node is MeshInstance3D):
		return
	var mesh_instance := node as MeshInstance3D
	if mesh_instance.mesh == null:
		return
	var aabb := local_xform * mesh_instance.mesh.get_aabb()
	var is_flat := aabb.size.y < 0.05
	var is_huge := aabb.size.x > 100.0 or aabb.size.z > 100.0
	if is_flat and is_huge:
		mesh_instance.visible = false
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _combined_mesh_aabb(root: Node3D) -> AABB:
	var combined := AABB()
	var started := false
	for mesh_node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null or not mesh_instance.visible:
			continue
		var relative := Transform3D()
		var current: Node3D = mesh_instance
		while current != null and current != root:
			relative = current.transform * relative
			current = current.get_parent() as Node3D
		# Skip leftover CAD ground planes even if visibility stripping missed them.
		var local_aabb := relative * mesh_instance.mesh.get_aabb()
		if local_aabb.size.y < 0.05 and (local_aabb.size.x > 100.0 or local_aabb.size.z > 100.0):
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			for vertex in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var point: Vector3 = relative * vertex
				if not started:
					combined = AABB(point, Vector3.ZERO)
					started = true
				else:
					combined = combined.expand(point)
	return combined


func _mesh_aabb_by_name(root: Node3D, mesh_name: String) -> AABB:
	var mesh_instance := root.find_child(mesh_name, true, false) as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return AABB()
	var relative := Transform3D()
	var current: Node3D = mesh_instance
	while current != null and current != root:
		relative = current.transform * relative
		current = current.get_parent() as Node3D
	var combined := AABB()
	var started := false
	for surface_index in mesh_instance.mesh.get_surface_count():
		var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
		if arrays.is_empty():
			continue
		for vertex in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var point: Vector3 = relative * vertex
			if not started:
				combined = AABB(point, Vector3.ZERO)
				started = true
			else:
				combined = combined.expand(point)
	return combined


func _build_parking_garage() -> void:
	var root := Node3D.new()
	root.name = "SoutheastGarage"
	root.position = Vector3(62, 0, 39)
	_building_root.add_child(root)
	_building_count += 1
	var height := 12.6
	_box("GarageMass", Vector3(0, height * 0.5, 0), Vector3(23, height, 22), "concrete_cool", true, root)
	for floor_index in range(4):
		var y_value := 1.75 + float(floor_index) * 3.0
		for z_sign in [-1.0, 1.0]:
			_box(
				"GarageOpening",
				Vector3(0, y_value, z_sign * 11.06),
				Vector3(19.0, 1.65, 0.12),
				"charcoal",
				false,
				root
			)
	_box("GarageRamp", Vector3(0, 0.18, -12.0), Vector3(8.0, 0.2, 4.0), "asphalt", false, root)
	_box("GarageRoof", Vector3(0, 12.9, 0), Vector3(23.5, 0.5, 22.5), "accent_gold", false, root)


func _build_civic_center() -> void:
	var root := Node3D.new()
	root.name = "EastCivicCenter"
	root.position = Vector3(52, 0, 0)
	_landmark_root.add_child(root)
	_building_count += 1
	_box("CivicMass", Vector3(0, 5.0, 0), Vector3(30, 10, 20), "concrete_light", true, root)
	_box("CivicGlass", Vector3(-15.06, 4.7, 0), Vector3(0.12, 5.6, 14), "glass_blue", false, root)
	_box("CivicFrame", Vector3(-15.2, 7.8, 0), Vector3(1.0, 0.7, 17), "accent_teal", false, root)
	_box("CivicCanopy", Vector3(-17.6, 3.3, 0), Vector3(5.4, 0.32, 16), "accent_teal", false, root)
	for z_value in [-6.0, -2.0, 2.0, 6.0]:
		_cylinder(
			"CivicColumn",
			Vector3(-17.3, 1.65, z_value),
			0.22,
			3.3,
			"warm_white",
			false,
			root,
			8
		)
	_box("CivicRoofGarden", Vector3(3.5, 10.4, 0), Vector3(18, 0.45, 14), "grass", false, root)


func _build_park() -> void:
	var park_root := Node3D.new()
	park_root.name = "SouthPark"
	park_root.position = Vector3(-7, 0, 39)
	_landmark_root.add_child(park_root)
	_box("ParkLawn", Vector3.ZERO + Vector3(0, DETAIL_LEVEL, 0), Vector3(30, 0.052, 22), "grass", false, park_root)
	_box("ParkPathNS", Vector3(0, 0.058, 0), Vector3(3.0, 0.016, 21.5), "path", false, park_root)
	_box("ParkPathEW", Vector3(0, 0.059, 0), Vector3(29.5, 0.016, 3.0), "path", false, park_root)
	_cylinder("ParkPavilionRoof", Vector3(0, 3.4, 0), 4.1, 0.45, "accent_coral", false, park_root, 8)
	for angle in range(0, 360, 90):
		var radians := deg_to_rad(float(angle))
		_cylinder(
			"PavilionPost",
			Vector3(cos(radians) * 2.8, 1.65, sin(radians) * 2.8),
			0.14,
			3.3,
			"charcoal",
			false,
			park_root,
			8
		)


func _build_parking_lot() -> void:
	var root := Node3D.new()
	root.name = "WestParking"
	root.position = Vector3(-52, 0, 3)
	_landmark_root.add_child(root)
	_box("ParkingSurface", Vector3(0, ROAD_LEVEL, 0), Vector3(31, 0.024, 19), "asphalt", false, root)
	for x_value in range(-12, 13, 4):
		for z_value in [-8.2, 8.2]:
			_box(
				"ParkingMark",
				Vector3(float(x_value), 0.034, z_value),
				Vector3(0.1, 0.016, 3.4),
				"road_white",
				false,
				root
			)
	_box("ParkingStop", Vector3(0, 0.14, 0), Vector3(30, 0.25, 0.25), "road_yellow", false, root)

	var car_data := [
		[Vector3(-10, 0, -4.8), "car_blue"],
		[Vector3(-2, 0, -4.8), "car_coral"],
		[Vector3(10, 0, -4.8), "car_gold"],
		[Vector3(-6, 0, 4.8), "car_teal"],
		[Vector3(6, 0, 4.8), "car_white"],
	]
	for index in car_data.size():
		_build_car(
			"ParkedCar_%d" % index,
			car_data[index][0],
			String(car_data[index][1]),
			root
		)


func _build_car(node_name: String, position_value: Vector3, color_name: String, parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = position_value
	parent.add_child(root)
	_box("CarBody", Vector3(0, 0.48, 0), Vector3(2.0, 0.65, 4.0), color_name, false, root)
	_box("CarCabin", Vector3(0, 0.95, -0.2), Vector3(1.75, 0.6, 2.1), "glass_dark", false, root)
	for x_value in [-1.02, 1.02]:
		for z_value in [-1.25, 1.25]:
			_cylinder(
				"Wheel",
				Vector3(x_value, 0.32, z_value),
				0.34,
				0.22,
				"rubber",
				false,
				root,
				10,
				Vector3(0, 0, PI * 0.5)
			)


func _build_street_furniture() -> void:
	_build_trees()
	_build_lamps()
	_build_benches_and_bins()
	_build_bus_stop()


func _tree_positions() -> Array[Vector3]:
	return [
		Vector3(-13.2, 0, -8.4), Vector3(13.2, 0, -8.4),
		Vector3(-13.2, 0, 8.4), Vector3(13.2, 0, 8.4),
		Vector3(-19, 0, -29), Vector3(-7, 0, -29), Vector3(7, 0, -29), Vector3(41, 0, -29),
		Vector3(-37, 0, 29), Vector3(-25, 0, 29), Vector3(-17, 0, 34), Vector3(-9, 0, 47),
		Vector3(1, 0, 47), Vector3(9, 0, 34), Vector3(18, 0, 29), Vector3(42, 0, 29),
		Vector3(-70, 0, -46), Vector3(-70, 0, -32), Vector3(-70, 0, 31), Vector3(-70, 0, 45),
		Vector3(70, 0, -46), Vector3(70, 0, -31), Vector3(70, 0, 31), Vector3(70, 0, 46),
	]


func _build_trees() -> void:
	var positions := _tree_positions()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.19
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 3.2
	trunk_mesh.radial_segments = 7
	_multimesh(
		"TreeTrunks",
		trunk_mesh,
		positions,
		Vector3(1, 1, 1),
		Vector3(0, 1.6, 0),
		"tree_trunk",
		_prop_root,
		true
	)

	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.55
	canopy_mesh.height = 2.65
	canopy_mesh.radial_segments = 8
	canopy_mesh.rings = 4
	_multimesh(
		"TreeCanopies",
		canopy_mesh,
		positions,
		Vector3(1, 1, 1),
		Vector3(0, 4.05, 0),
		"tree_leaf",
		_prop_root,
		true,
		true
	)


func _build_lamps() -> void:
	var positions: Array[Vector3] = []
	for x_value in [-60.0, -40.0, 40.0, 60.0]:
		positions.append(Vector3(x_value, 0, -26.5))
		positions.append(Vector3(x_value, 0, 26.5))
	for x_value in [-31.0, -17.0, 17.0, 31.0]:
		positions.append(Vector3(x_value, 0, -11.5))
		positions.append(Vector3(x_value, 0, 11.5))

	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.08
	post_mesh.bottom_radius = 0.12
	post_mesh.height = 4.8
	post_mesh.radial_segments = 8
	_multimesh(
		"LampPosts",
		post_mesh,
		positions,
		Vector3.ONE,
		Vector3(0, 2.4, 0),
		"charcoal",
		_prop_root,
		true
	)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.75, 0.18, 0.42)
	_multimesh(
		"LampHeads",
		head_mesh,
		positions,
		Vector3.ONE,
		Vector3(0, 4.75, 0),
		"lamp",
		_prop_root,
		false
	)


func _build_benches_and_bins() -> void:
	for data in [
		[Vector3(-9, 0, -10.8), 0.0],
		[Vector3(9, 0, -10.8), 0.0],
		[Vector3(-9, 0, 10.8), PI],
		[Vector3(9, 0, 10.8), PI],
		[Vector3(-17, 0, 39), PI * 0.5],
		[Vector3(3, 0, 39), -PI * 0.5],
	]:
		_build_bench(data[0], float(data[1]))

	for position_value in [
		Vector3(-16, 0, -11),
		Vector3(16, 0, 11),
		Vector3(-31, 0, 26),
		Vector3(31, 0, -26),
	]:
		_box("StreetBin", position_value + Vector3(0, 0.55, 0), Vector3(0.65, 1.1, 0.65), "charcoal", true, _prop_root)
		_box("StreetBinTop", position_value + Vector3(0, 1.13, 0), Vector3(0.72, 0.12, 0.72), "accent_teal", false, _prop_root)

	for position_value in [
		Vector3(-17, 0, -12), Vector3(-14, 0, -12),
		Vector3(17, 0, 12), Vector3(14, 0, 12),
		Vector3(-17, 0, 12), Vector3(17, 0, -12),
	]:
		_cylinder("Bollard", position_value + Vector3(0, 0.55, 0), 0.11, 1.1, "charcoal", true, _prop_root, 8)


func _build_bench(position_value: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "Bench"
	root.position = position_value
	root.rotation.y = yaw
	_prop_root.add_child(root)
	_box("Seat", Vector3(0, 0.55, 0), Vector3(2.8, 0.18, 0.66), "wood", true, root)
	_box("Back", Vector3(0, 1.05, 0.28), Vector3(2.8, 0.9, 0.15), "wood", false, root)
	_box("LegL", Vector3(-1.05, 0.28, 0), Vector3(0.16, 0.55, 0.5), "charcoal", false, root)
	_box("LegR", Vector3(1.05, 0.28, 0), Vector3(0.16, 0.55, 0.5), "charcoal", false, root)


func _build_bus_stop() -> void:
	var root := Node3D.new()
	root.name = "CBlockBusStop"
	root.position = Vector3(45, 0, 26.3)
	_landmark_root.add_child(root)
	_box("BusStopPad", Vector3(0, DETAIL_LEVEL, 0), Vector3(14, 0.052, 3.5), "sidewalk", false, root)
	_box("ShelterBack", Vector3(0, 1.7, 1.2), Vector3(11.5, 3.3, 0.16), "glass_teal", false, root)
	_box("ShelterRoof", Vector3(0, 3.45, 0), Vector3(12.2, 0.24, 3.5), "accent_teal", false, root)
	for x_value in [-5.4, 5.4]:
		_cylinder("ShelterPost", Vector3(x_value, 1.7, 1.2), 0.1, 3.4, "charcoal", false, root, 8)
	_box("StopBench", Vector3(0, 0.62, 0.9), Vector3(6.5, 0.22, 0.7), "wood", true, root)
	_cylinder("BusSignPost", Vector3(-6.5, 1.7, 0), 0.09, 3.4, "charcoal", false, root, 8)
	_box("BusSign", Vector3(-6.5, 3.1, 0), Vector3(0.85, 0.95, 0.12), "accent_coral", false, root)


func _build_boundaries() -> void:
	# Physical edge walls are hidden in landscaped retaining walls.
	_box("NorthBoundary", Vector3(0, 1.0, -57.5), Vector3(156, 2.0, 1.0), "retaining", true, _collision_root)
	_box("SouthBoundary", Vector3(0, 1.0, 57.5), Vector3(156, 2.0, 1.0), "retaining", true, _collision_root)
	_box("WestBoundary", Vector3(-77.5, 1.0, 0), Vector3(1.0, 2.0, 116), "retaining", true, _collision_root)
	_box("EastBoundary", Vector3(77.5, 1.0, 0), Vector3(1.0, 2.0, 116), "retaining", true, _collision_root)

	# Construction barriers close the four road ends visibly.
	for position_value in [
		Vector3(-73, 0, -19),
		Vector3(73, 0, -19),
		Vector3(-73, 0, 19),
		Vector3(73, 0, 19),
	]:
		_build_road_barrier(position_value)


func _build_road_barrier(position_value: Vector3) -> void:
	var root := Node3D.new()
	root.name = "RoadClosure"
	root.position = position_value
	_prop_root.add_child(root)
	_box("BarrierBody", Vector3(0, 0.65, 0), Vector3(1.0, 1.3, 7.5), "barrier_white", true, root)
	for z_value in [-2.5, 0.0, 2.5]:
		_box("BarrierStripe", Vector3(-0.52, 0.7, z_value), Vector3(0.06, 0.5, 1.1), "accent_coral", false, root)


func _add_label(
	node_name: String,
	text_value: String,
	position_value: Vector3,
	rotation_value: Vector3,
	parent: Node,
	pixel_size_value: float,
	font_size_value: int
) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text_value
	label.position = position_value
	label.rotation = rotation_value
	label.pixel_size = pixel_size_value
	label.font_size = font_size_value
	label.modulate = Color("f4fbff")
	label.outline_modulate = Color("122027")
	label.outline_size = 8
	label.no_depth_test = false
	parent.add_child(label)
	return label


func _multimesh(
	node_name: String,
	mesh: Mesh,
	positions: Array[Vector3],
	scale_value: Vector3,
	offset: Vector3,
	material_name: String,
	parent: Node,
	cast_shadow: bool,
	vary_scale: bool = false
) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = positions.size()
	multimesh.mesh = mesh
	for index in positions.size():
		var variation := 1.0
		if vary_scale:
			variation = 0.88 + float(index % 5) * 0.055
		var basis := Basis.IDENTITY.scaled(scale_value * variation)
		multimesh.set_instance_transform(
			index,
			Transform3D(basis, positions[index] + offset)
		)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _material(material_name)
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent.add_child(instance)
	return instance


func _box(
	node_name: String,
	position_value: Vector3,
	size: Vector3,
	material_name: String,
	with_collision: bool = false,
	parent: Node = self,
	cast_shadow: bool = true
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.position = position_value
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(material_name)
	mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if cast_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	parent.add_child(mesh_instance)
	if with_collision:
		var body := StaticBody3D.new()
		body.name = node_name + "Collision"
		body.position = position_value
		body.collision_layer = 1
		body.collision_mask = 1
		body.add_to_group("cblock_environment")
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		parent.add_child(body)
	return mesh_instance


func _cylinder(
	node_name: String,
	position_value: Vector3,
	radius: float,
	height: float,
	material_name: String,
	with_collision: bool = false,
	parent: Node = self,
	segments: int = 8,
	rotation_value: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position_value
	instance.rotation = rotation_value
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	instance.mesh = mesh
	instance.material_override = _material(material_name)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	if with_collision:
		var body := StaticBody3D.new()
		body.name = node_name + "Collision"
		body.position = position_value
		body.rotation = rotation_value
		body.collision_layer = 1
		body.collision_mask = 1
		body.add_to_group("cblock_environment")
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		parent.add_child(body)
	return instance


func _material(material_name: String) -> StandardMaterial3D:
	if _materials.has(material_name):
		return _materials[material_name]

	var colors := {
		"ground": Color("7b817d"),
		"verge": Color("47624e"),
		"grass": Color("4f7755"),
		"asphalt": Color("293036"),
		"sidewalk": Color("c6c4bb"),
		"path": Color("d2c4a7"),
		"plaza": Color("9ca39e"),
		"plaza_light": Color("cfd3ca"),
		"planter": Color("5a625e"),
		"stone": Color("6d7775"),
		"road_yellow": Color("efc34f"),
		"road_white": Color("e8ede7"),
		"concrete_cool": Color("76858d"),
		"concrete_light": Color("c5c9c4"),
		"warm_white": Color("ddd8ca"),
		"brick": Color("8b5e50"),
		"glass_blue": Color("37728a"),
		"glass_teal": Color("347b7e"),
		"glass_dark": Color("273d48"),
		"accent_teal": Color("2c9a93"),
		"accent_coral": Color("df6b57"),
		"accent_gold": Color("d7a83d"),
		"charcoal": Color("253038"),
		"retaining": Color("626b67"),
		"tree_trunk": Color("66513c"),
		"tree_leaf": Color("3d7550"),
		"wood": Color("8b6441"),
		"lamp": Color("fff0bd"),
		"rubber": Color("161a1c"),
		"barrier_white": Color("d7d9d5"),
		"car_blue": Color("456d8c"),
		"car_coral": Color("b9564a"),
		"car_gold": Color("ba8931"),
		"car_teal": Color("397d77"),
		"car_white": Color("cfd3d0"),
	}
	var material := StandardMaterial3D.new()
	material.albedo_color = colors.get(material_name, Color.MAGENTA)
	material.roughness = 0.88
	if material_name.begins_with("glass"):
		material.metallic = 0.32
		material.roughness = 0.22
	elif material_name == "lamp":
		material.emission_enabled = true
		material.emission = Color("fff0bd")
		material.emission_energy_multiplier = 0.65
	elif material_name.begins_with("accent"):
		material.roughness = 0.55
	_materials[material_name] = material
	return material
