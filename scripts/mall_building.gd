extends Node3D
class_name MallBuilding
## Two-floor PSX-style Gaisano Country Mall with a traversable interior.

signal message_requested(text: String)

const InteractableType = preload("res://scripts/interactable.gd")
const GroceryAislePropType = preload("res://scripts/grocery_aisle_prop.gd")
const VendingMachinePropType = preload("res://scripts/vending_machine_prop.gd")
const StreetVehiclePropType = preload("res://scripts/street_vehicle_prop.gd")
const PSX_SHADER = preload("res://shaders/psx_surface.gdshader")

const CENTER_X := -4.0
const FRONT_Z := 38.0
const BACK_Z := 64.0
const LEFT_X := -34.0
const RIGHT_X := 26.0
const BASE_Y := 0.24
const UPPER_Y := 4.25

## Shared structural dimensions. A small overlap removes visible daylight
## seams where procedural wall, floor, and roof pieces meet.
const WALL_THICKNESS := 0.42
const SHELL_OVERLAP := 0.18
const SHELL_HEIGHT := 8.2

## Corridor coordinates are derived from OpenStreetMap geometry, while the
## supplied street references guide the deliberately low-poly architectural
## treatment. No map imagery is embedded in the game.
const CAMP_ROAD_X := -20.0
const CAMP_ROAD_WIDTH := 8.0
const CAMP_PORTAL_LEFT := CAMP_ROAD_X - CAMP_ROAD_WIDTH * 0.5
const CAMP_PORTAL_RIGHT := CAMP_ROAD_X + CAMP_ROAD_WIDTH * 0.5

var _player: CharacterBody3D
var _material_cache: Dictionary = {}
var _day_only_nodes: Array[Node3D] = []
var _day_lights: Array[Light3D] = []
var _night_lights: Array[Light3D] = []
var _exterior_lights: Array[Light3D] = []
var _escalator_steps: Array[Dictionary] = []
var _is_night := false


func configure(player: CharacterBody3D) -> void:
	_player = player


func build() -> void:
	_build_courtyard_envelope()
	_build_parking_lot()
	_build_shell_and_facade()
	_build_ground_floor()
	_build_upper_floor()
	_build_escalators()
	_build_mall_lighting()
	_build_inspection_points()
	set_night_mode(false)


func build_async(scene_tree: SceneTree) -> void:
	_build_courtyard_envelope()
	await scene_tree.process_frame
	_build_parking_lot()
	await scene_tree.process_frame
	_build_shell_and_facade()
	await scene_tree.process_frame
	_build_ground_floor()
	await scene_tree.process_frame
	_build_upper_floor()
	await scene_tree.process_frame
	_build_escalators()
	_build_mall_lighting()
	_build_inspection_points()
	set_night_mode(false)


func set_night_mode(is_night: bool) -> void:
	_is_night = is_night
	for node in _day_only_nodes:
		if not is_instance_valid(node):
			continue
		node.visible = not is_night
		for collision_node in node.find_children("*", "CollisionObject3D", true, false):
			var collision := collision_node as CollisionObject3D
			collision.collision_layer = 0 if is_night else 1
			collision.collision_mask = 0 if is_night else 1
	for light in _day_lights:
		if is_instance_valid(light):
			light.visible = not is_night
	for light in _night_lights:
		if is_instance_valid(light):
			light.visible = is_night
	for light in _exterior_lights:
		if is_instance_valid(light):
			light.light_energy = 1.75 if is_night else 0.22


func _build_parking_lot() -> void:
	# The real frontage is an open parking court framed by two arcade wings.
	# Keep a clear drive aisle between Gov. M. Cuenco and the mall entrances.
	# The court stops at the west sidewalk of Camp Lapu-Lapu instead of
	# painting over half the road.
	_box("ParkingAsphalt", Vector3(4.5, 0.13, 24.5), Vector3(40.0, 0.05, 25.0), Color("343638"), false)
	_box("ParkingForecourt", Vector3(4.5, 0.17, 35.0), Vector3(40.0, 0.08, 4.0), Color("77736b"), false)
	_box("MallFrontStoneWallWest", Vector3(11.0, 0.62, 11.7), Vector3(18.0, 1.0, 0.55), Color("77766c"), true)
	_box("MallFrontStoneWallEast", Vector3(-4.0, 0.62, 11.7), Vector3(6.0, 1.0, 0.55), Color("77766c"), true)
	for x in [-14.0, -7.0, 0.0, 7.0, 14.0, 21.0]:
		_box("ParkingStripe", Vector3(x, 0.175, 23.0), Vector3(0.09, 0.025, 5.0), Color("d8cfaa"), false)
	for z in [17.0, 31.0]:
		_box("DriveLaneMark", Vector3(2.0, 0.18, z), Vector3(42.0, 0.025, 0.10), Color("b7ad82"), false)

	var car_positions := [
		Vector3(-12.0, 0.25, 22.5), Vector3(2.0, 0.25, 22.5),
		Vector3(16.0, 0.25, 22.5), Vector3(12.0, 0.25, 30.0),
	]
	for index in car_positions.size():
		var car := _build_car("ParkedCar_%02d" % index, car_positions[index], index, PI / 2.0 if index < 3 else -PI / 2.0)
		if index >= 3:
			_day_only_nodes.append(car)

	for index in range(4):
		var bike := _build_motorcycle("Motorcycle_%02d" % index, Vector3(12.0 + float(index) * 1.45, 0.22, 34.5))
		if index >= 2:
			_day_only_nodes.append(bike)

	for x in [-13.0, 3.0, 19.0]:
		_build_palm(Vector3(x, 0.2, 34.2))
	for x in [-12.0, 0.0, 12.0, 22.0]:
		_build_parking_lamp(Vector3(x, 0.2, 18.0))

	# Motorcycle shelter and bollards near the main entrance.
	_box("MotorcycleShelterRoof", Vector3(16.0, 2.0, 34.4), Vector3(9.0, 0.15, 3.0), Color("7c2f2f"), false)
	for x in [12.0, 20.0]:
		_cylinder("MotorcycleShelterPost", Vector3(x, 1.0, 34.4), 0.07, 1.9, Color("707679"), Vector3.ZERO, true)
	for x in [-7.0, -4.5, 1.0, 3.5]:
		_cylinder("EntranceBollard", Vector3(x, 0.65, 35.7), 0.12, 1.0, Color("6f312b"), Vector3.ZERO, true)


func _build_courtyard_envelope() -> void:
	# Gaisano is a U-shaped frontage around an open parking court. These two
	# closed arcade wings replace the incorrect full-block slab/roof.
	var cream := Color("d3c5a7")
	var trim := Color("b79e6d")
	var roof := Color("8f3c35")
	var glass := Color("1e3b48")
	_build_arcade_wing("MallWestArcadeWing", 24.5, 25.0, cream, trim, roof, glass)
	_build_arcade_wing("MallEastArcadeWing", -29.5, 25.0, cream, trim, roof, glass)

	# Low forecourt planters and palms reproduce the open, landscaped frontage.
	for x in [-12.0, 3.0, 18.0]:
		_box("ForecourtPlanter", Vector3(x, 0.55, 34.8), Vector3(4.4, 0.65, 2.1), Color("6f7064"), true)
		_box("ForecourtSoil", Vector3(x, 0.9, 34.8), Vector3(3.8, 0.12, 1.5), Color("39352b"), false)


func _build_arcade_wing(
	prefix: String,
	x: float,
	z: float,
	cream: Color,
	trim: Color,
	roof: Color,
	glass: Color
) -> void:
	var width := 9.0
	var depth := 27.0
	var front_z := z - depth * 0.5
	_box(prefix + "Floor", Vector3(x, BASE_Y - 0.10, z), Vector3(width, 0.22, depth), Color("77736b"), true)
	_box(prefix + "OuterWall", Vector3(x, 4.2, z), Vector3(width, 8.0, depth), cream, true)
	_box(prefix + "Roof", Vector3(x, 8.45, z), Vector3(width + 0.5, 0.35, depth + 0.6), roof, true)
	# The parking-facing layer visually reads as a two-storey arcade. Collision
	# remains in the closed backing mass so decorative windows never leak.
	var inner_x := x - signf(x) * (width * 0.5 + 0.08)
	for bay in range(5):
		var bay_z := 14.8 + float(bay) * 5.1
		_box(prefix + "WindowGF", Vector3(inner_x, 2.0, bay_z), Vector3(0.12, 2.5, 3.7), glass, false)
		_box(prefix + "Window2F", Vector3(inner_x, 5.9, bay_z), Vector3(0.12, 2.3, 3.7), glass, false)
		_box(prefix + "Column", Vector3(inner_x - signf(x) * 0.28, 3.9, bay_z - 2.25), Vector3(0.55, 7.3, 0.45), trim, false)
		_arch(prefix + "Arch", Vector3(inner_x - signf(x) * 0.34, 3.2, bay_z), 1.9, trim, 7, PI / 2.0)
	_box(prefix + "Canopy", Vector3(inner_x - signf(x) * 0.48, 4.2, z), Vector3(1.15, 0.22, depth), roof, false)

	# Road-facing end gable. This removes the previous blank-box appearance
	# and uses the same glass, trim and roof hierarchy as every arcade bay.
	_box(prefix + "FrontGlassGround", Vector3(x, 2.0, front_z - 0.22), Vector3(width - 1.2, 2.7, 0.12), glass, false)
	_box(prefix + "FrontGlassUpper", Vector3(x, 5.55, front_z - 0.22), Vector3(width - 1.5, 3.2, 0.12), glass, false)
	for jamb_x in [x - width * 0.5 + 0.42, x + width * 0.5 - 0.42]:
		_box(prefix + "FrontJamb", Vector3(jamb_x, 4.0, front_z - 0.38), Vector3(0.42, 7.2, 0.58), trim, false)
	_arch(prefix + "FrontArch", Vector3(x, 4.25, front_z - 0.42), 3.45, trim, 10)
	_box(prefix + "FrontCanopy", Vector3(x, 4.2, front_z - 0.85), Vector3(width + 0.35, 0.22, 1.7), roof, false)
	var wing_sign := _box(prefix + "FrontSign", Vector3(x, 7.45, front_z - 0.48), Vector3(7.0, 0.65, 0.16), Color("eadfca"), false)
	_add_label(wing_sign, "GAISANO", Vector3(0.0, 0.0, -0.10), 0.010, Color("862d2c"), true)


func _build_shell_and_facade() -> void:
	var cream := Color("d3c5a7")
	var trim := Color("b79e6d")
	var red_roof := Color("8f3c35")
	var glass := Color("1e3b48")
	var wall_height := SHELL_HEIGHT
	var wall_center_y := BASE_Y + wall_height * 0.5
	var center_z := (FRONT_Z + BACK_Z) * 0.5

	# Floor, roof and outer shell. Front and rear walls retain true walk-through openings.
	_box("MallGroundSlab", Vector3(CENTER_X, BASE_Y - 0.11, center_z), Vector3(60.0, 0.22, 26.0), Color("77736b"), true)
	_box("MallLeftWall", Vector3(LEFT_X, wall_center_y, center_z), Vector3(WALL_THICKNESS, wall_height, 26.0 + SHELL_OVERLAP * 2.0), cream, true)
	_box("MallRightWall", Vector3(RIGHT_X, wall_center_y, center_z), Vector3(WALL_THICKNESS, wall_height, 26.0 + SHELL_OVERLAP * 2.0), cream, true)
	# Rear shell leaves the Camp Lapu-Lapu passage open at ground level.
	_box("MallBackCampWest", Vector3(-29.0, wall_center_y, BACK_Z), Vector3(10.0 + SHELL_OVERLAP, wall_height, WALL_THICKNESS), cream, true)
	_box("MallBackCampEast", Vector3(-11.0, wall_center_y, BACK_Z), Vector3(10.0 + SHELL_OVERLAP, wall_height, WALL_THICKNESS), cream, true)
	_box("MallBackRight", Vector3(12.0, wall_center_y, BACK_Z), Vector3(28.0 + SHELL_OVERLAP, wall_height, WALL_THICKNESS), cream, true)
	_box("CampRearPortalTop", Vector3(CAMP_ROAD_X, 6.3, BACK_Z), Vector3(CAMP_ROAD_WIDTH + SHELL_OVERLAP, 4.2, WALL_THICKNESS), cream, true)
	_box("RearExitTop", Vector3(CENTER_X, 7.15, BACK_Z), Vector3(4.2 + SHELL_OVERLAP, 2.1, WALL_THICKNESS), cream, true)
	_box("MallRoof", Vector3(CENTER_X, 8.55, center_z), Vector3(60.4 + SHELL_OVERLAP, 0.3, 26.4 + SHELL_OVERLAP), red_roof.darkened(0.18), true)

	# Ground facade keeps two deliberate openings: the Camp Lapu-Lapu road
	# portal and the mall's central pedestrian entrance.
	_box("FacadeGroundCampWest", Vector3(-29.0, 2.2, FRONT_Z), Vector3(10.0 + SHELL_OVERLAP, 4.0, WALL_THICKNESS), cream, true)
	_box("FacadeGroundMiddle", Vector3(-12.0, 2.2, FRONT_Z), Vector3(8.0 + SHELL_OVERLAP, 4.0, WALL_THICKNESS), cream, true)
	_box("FacadeGroundRight", Vector3(13.5, 2.2, FRONT_Z), Vector3(25.0, 4.0, 0.4), cream, true)
	_box("FacadeUpper", Vector3(CENTER_X, 6.3, FRONT_Z), Vector3(60.0, 4.2, 0.4), cream, true)

	# Repeated covered arcade bays from the reference facade.
	var bays := [-30.5, -12.0, 6.0, 11.5, 17.0, 22.5]
	for bay_x in bays:
		_box("ArcadeWindow", Vector3(bay_x, 2.15, FRONT_Z - 0.24), Vector3(4.3, 2.45, 0.10), glass, false)
		_box("ArcadeColumnL", Vector3(bay_x - 2.35, 2.0, FRONT_Z - 0.48), Vector3(0.36, 3.6, 0.72), trim, false)
		_arch("ArcadeArch", Vector3(bay_x, 3.05, FRONT_Z - 0.50), 2.2, trim, 7)
	_box("ArcadeCanopy", Vector3(CENTER_X, 4.25, FRONT_Z - 1.05), Vector3(59.0, 0.22, 2.3), red_roof, false)

	# The two-storey connector across Camp Lapu-Lapu is readable as one large
	# glazed arch while retaining a full 8 m collision-clear roadway below.
	_box("CampPortalJambWest", Vector3(CAMP_PORTAL_LEFT - 0.28, 2.2, FRONT_Z - 0.48), Vector3(0.56, 4.0, 0.82), trim, false)
	_box("CampPortalJambEast", Vector3(CAMP_PORTAL_RIGHT + 0.28, 2.2, FRONT_Z - 0.48), Vector3(0.56, 4.0, 0.82), trim, false)
	_arch("CampPortalArch", Vector3(CAMP_ROAD_X, 4.15, FRONT_Z - 0.58), 4.1, trim, 12)
	var portal_sign := _box("CampPortalSign", Vector3(CAMP_ROAD_X, 6.75, FRONT_Z - 0.64), Vector3(7.2, 0.75, 0.18), Color("eadfca"), false)
	_add_label(portal_sign, "CAMP LAPU-LAPU RD", Vector3(0.0, 0.0, -0.12), 0.008, Color("862d2c"), true)

	# Central entrance tower, glass arch and strong landmark sign.
	_box("EntranceTower", Vector3(CENTER_X, 8.2, FRONT_Z + 0.12), Vector3(12.5, 8.0, 1.0), cream, false)
	_box("EntranceGlass", Vector3(CENTER_X, 3.15, FRONT_Z - 0.30), Vector3(8.4, 5.6, 0.15), glass, false)
	_box("EntranceDoorL", Vector3(CENTER_X - 2.15, 1.45, FRONT_Z - 0.48), Vector3(3.4, 2.7, 0.10), Color("142a33"), false)
	_box("EntranceDoorR", Vector3(CENTER_X + 2.15, 1.45, FRONT_Z - 0.48), Vector3(3.4, 2.7, 0.10), Color("142a33"), false)
	_arch("MainEntranceArch", Vector3(CENTER_X, 4.15, FRONT_Z - 0.58), 4.35, trim, 12)
	_box("TowerRoof", Vector3(CENTER_X, 12.45, FRONT_Z + 0.6), Vector3(14.0, 0.55, 4.5), red_roof, false, Vector3(0.10, 0.0, 0.0))
	var sign := _box("MallMainSign", Vector3(CENTER_X, 10.9, FRONT_Z - 0.62), Vector3(11.0, 1.5, 0.18), Color("eadfca"), false)
	_add_label(sign, "GAISANO COUNTRY MALL", Vector3(0.0, 0.0, -0.12), 0.010, Color("862d2c"), true)
	var side_sign := _box("MallSideSign", Vector3(19.0, 6.45, FRONT_Z - 0.64), Vector3(10.0, 1.15, 0.18), Color("e7dac0"), false)
	_add_label(side_sign, "GAISANO", Vector3(0.0, 0.0, -0.12), 0.014, Color("8b3430"), true)

	# Gold upper facade rhythm and red wing roofs.
	for x in range(-30, 24, 4):
		_box("UpperInset", Vector3(float(x), 6.55, FRONT_Z - 0.23), Vector3(2.6, 2.2, 0.10), Color("e4d7bd"), false)
		_box("UpperPilaster", Vector3(float(x) - 1.55, 6.55, FRONT_Z - 0.38), Vector3(0.20, 2.7, 0.32), trim, false)
	_box("LeftWingRoof", Vector3(-21.5, 8.55, FRONT_Z + 1.4), Vector3(25.0, 0.48, 4.8), red_roof, false, Vector3(0.12, 0.0, 0.0))
	_box("RightWingRoof", Vector3(13.5, 8.55, FRONT_Z + 1.4), Vector3(25.0, 0.48, 4.8), red_roof, false, Vector3(0.12, 0.0, 0.0))


func _build_ground_floor() -> void:
	var wall := Color("c4bda9")
	var glass := Color("203c44")
	var floor_color := Color("8d8980")
	_box("GroundInteriorFloor", Vector3(CENTER_X, BASE_Y + 0.01, 51.0), Vector3(58.8, 0.08, 24.8), floor_color, false)

	# West storefront corridor.
	for index in range(4):
		var z := 42.0 + float(index) * 4.2
		_box("WestStoreBack", Vector3(-32.3, 2.05, z), Vector3(0.2, 3.6, 3.7), wall, true)
		_box("WestStoreGlass", Vector3(CAMP_PORTAL_RIGHT + 0.5, 1.8, z), Vector3(0.12, 2.8, 3.4), glass, false)
		var store_sign := _box("WestStoreSign", Vector3(CAMP_PORTAL_RIGHT + 0.65, 3.35, z), Vector3(0.18, 0.62, 3.6), [Color("7a3d36"), Color("385d62"), Color("6a5833"), Color("5e3f60")][index], false)
		_add_label(store_sign, ["CEBU STYLE", "PHOTO CENTER", "BOOKS", "HOMEWARE"][index], Vector3(-0.14, 0.0, 0.0), 0.0065, Color("eee5d4"), false, Vector3(0.0, -PI / 2.0, 0.0))

	# Grocery anchor occupies the east/rear half but remains completely open.
	_box("GroceryDivider", Vector3(4.0, 2.1, 54.5), Vector3(0.25, 3.8, 17.5), wall, true)
	var grocery_sign := _box("GrocerySign", Vector3(5.0, 3.4, 45.2), Vector3(0.2, 0.8, 7.5), Color("aa3d32"), false)
	_add_label(grocery_sign, "GAISANO GROCERY", Vector3(-0.14, 0.0, 0.0), 0.009, Color("fff0d5"), false, Vector3(0.0, -PI / 2.0, 0.0))

	for index in range(4):
		# Pair centers ~4.2 m apart so walkways stay open between back-to-back units.
		var aisle_x := 8.0 + float(index) * 4.2
		# Asset is ~11.4 m long; nudge center slightly rear so produce bins clear.
		_build_grocery_shelf(Vector3(aisle_x, 0.28, 55.5), index)
	for index in range(3):
		_build_checkout(Vector3(8.0 + float(index) * 5.0, 0.28, 46.0))
	# Pixel-art vending machines against the grocery back wall, facing the aisles.
	for index in range(3):
		var vending_x := 9.5 + float(index) * 5.0
		_spawn_vending_machine(Vector3(vending_x, 0.28, 63.1), PI * 0.5)

	# Restrooms and service hallway at rear west, with a clear rear exit.
	_box("ServiceHallWallWest", Vector3(-29.0, 2.05, 59.5), Vector3(10.0, 3.7, 0.25), wall, true)
	_box("ServiceHallWallEast", Vector3(-12.0, 2.05, 59.5), Vector3(8.0, 3.7, 0.25), wall, true)
	_box("RestroomDivider", Vector3(CAMP_PORTAL_LEFT - 0.6, 2.05, 61.7), Vector3(0.25, 3.7, 4.2), wall, true)
	var restroom_sign := _box("RestroomSign", Vector3(-11.5, 2.8, 59.3), Vector3(4.2, 0.65, 0.12), Color("465d63"), false)
	_add_label(restroom_sign, "RESTROOMS", Vector3(0.0, 0.0, -0.10), 0.008, Color("e5e8df"), true)
	_box("RearExitMat", Vector3(CENTER_X, 0.28, 62.8), Vector3(3.8, 0.04, 2.0), Color("292c2b"), false)


func _build_upper_floor() -> void:
	var slab := Color("6f706b")
	var floor_color := Color("8b8478")
	# Gallery slabs form a ring around the central atrium/escalator opening.
	_box("UpperSlabLeft", Vector3(-21.5, UPPER_Y - 0.12, 51.0), Vector3(25.0, 0.24, 26.0), slab, true)
	_box("UpperSlabRight", Vector3(13.5, UPPER_Y - 0.12, 51.0), Vector3(25.0, 0.24, 26.0), slab, true)
	_box("UpperSlabFront", Vector3(CENTER_X, UPPER_Y - 0.12, 41.0), Vector3(10.0, 0.24, 6.0), slab, true)
	_box("UpperSlabBack", Vector3(CENTER_X, UPPER_Y - 0.12, 59.0), Vector3(10.0, 0.24, 10.0), slab, true)
	_box("UpperFloorLeft", Vector3(-21.5, UPPER_Y + 0.02, 51.0), Vector3(24.6, 0.05, 25.6), floor_color, false)
	_box("UpperFloorRight", Vector3(13.5, UPPER_Y + 0.02, 51.0), Vector3(24.6, 0.05, 25.6), floor_color, false)

	# Atrium railings.
	_box("AtriumRail", Vector3(CENTER_X, UPPER_Y + 0.75, 44.0), Vector3(10.0, 0.12, 0.14), Color("555b5c"), true)
	for x in [-8.8, -6.4, -4.0, -1.6, 0.8]:
		_box("AtriumPost", Vector3(x, UPPER_Y + 0.38, 44.0), Vector3(0.10, 0.75, 0.10), Color("555b5c"), false)
	for x in [-9.0, 1.0]:
		_box("AtriumSideRail", Vector3(x, UPPER_Y + 0.75, 49.0), Vector3(0.14, 0.12, 10.0), Color("555b5c"), true)

	# Food court on the upper east side.
	var food_sign := _box("FoodCourtSign", Vector3(14.0, 7.15, 62.8), Vector3(12.0, 0.9, 0.14), Color("8d4a35"), false)
	_add_label(food_sign, "FOOD COURT", Vector3(0.0, 0.0, -0.10), 0.012, Color("ffe8bd"), true)
	for x in [7.0, 13.0, 19.0]:
		for z in [48.0, 53.0, 58.0]:
			_build_table_set(Vector3(x, UPPER_Y, z))
	for index in range(3):
		var stall_x := 7.5 + float(index) * 7.5
		_box("FoodStall", Vector3(stall_x, UPPER_Y + 1.6, 62.5), Vector3(6.4, 2.8, 1.4), [Color("6f3d32"), Color("4b6250"), Color("705d32")][index], true)

	# Arcade and upper shops on the west side.
	var arcade_sign := _box("ArcadeSign", Vector3(-27.0, 7.1, 61.8), Vector3(10.0, 0.9, 0.14), Color("533b70"), false)
	_add_label(arcade_sign, "ARCADE", Vector3(0.0, 0.0, -0.10), 0.013, Color("e7d4ff"), true)
	for index in range(8):
		var cabinet_x := -31.0 + float(index % 4) * 3.0
		var cabinet_z := 56.0 + float(index / 4) * 3.0
		_build_arcade_cabinet(Vector3(cabinet_x, UPPER_Y, cabinet_z), index)
	for index in range(3):
		var z := 43.0 + float(index) * 4.5
		_box("UpperShopGlass", Vector3(-10.2, UPPER_Y + 1.55, z), Vector3(0.10, 2.7, 3.6), Color("29434b"), false)
		_box("UpperShopSign", Vector3(-10.0, UPPER_Y + 3.05, z), Vector3(0.16, 0.65, 3.8), [Color("754743"), Color("3c6271"), Color("6c5d3b")][index], false)

	# Central kiosk at the back of the gallery.
	_box("UpperKioskCounter", Vector3(CENTER_X, UPPER_Y + 0.75, 58.0), Vector3(5.0, 1.1, 2.4), Color("6a4d38"), true)
	_box("UpperKioskRoof", Vector3(CENTER_X, UPPER_Y + 2.5, 58.0), Vector3(5.6, 0.18, 3.0), Color("8c4337"), false)


func _build_escalators() -> void:
	_build_escalator("EscalatorUp", -6.6, Vector3(-6.6, BASE_Y + 0.22, 44.5), Vector3(-6.6, UPPER_Y + 0.06, 54.2), true)
	_build_escalator("EscalatorDown", -1.4, Vector3(-1.4, BASE_Y + 0.22, 44.5), Vector3(-1.4, UPPER_Y + 0.06, 54.2), false)


func _build_escalator(prefix: String, x: float, bottom: Vector3, top: Vector3, moves_up: bool) -> void:
	var run := absf(top.z - bottom.z)
	var rise := top.y - bottom.y
	var length := sqrt(run * run + rise * rise)
	var midpoint := (bottom + top) * 0.5
	var angle := atan2(rise, run)
	_box(prefix + "WalkRamp", midpoint, Vector3(1.8, 0.18, length), Color("30373a"), true, Vector3(-angle, 0.0, 0.0))
	for side in [-1.08, 1.08]:
		_box(prefix + "Rail", midpoint + Vector3(side, 0.72, 0.0), Vector3(0.16, 0.22, length), Color("4f5557"), false, Vector3(-angle, 0.0, 0.0))
	for index in range(16):
		var t := float(index) / 15.0
		var point := bottom.lerp(top, t)
		var step := _box(prefix + "Step", point, Vector3(1.65, 0.10, 0.62), Color("555b5e"), false) as Node3D
		var start := bottom if moves_up else top
		var end := top if moves_up else bottom
		var direction := (end - start).normalized()
		_escalator_steps.append({"node": step, "start": start, "direction": direction, "length": length})


func _build_mall_lighting() -> void:
	# Sparse mall fills — GL Compatibility pays per overlapping Omni.
	for x in [-20.0, 0.0, 18.0]:
		for z in [45.0, 57.0]:
			var day_light := OmniLight3D.new()
			day_light.position = Vector3(x, 3.25, z)
			day_light.light_color = Color("fff0cf")
			day_light.light_energy = 1.05
			day_light.omni_range = 12.0
			day_light.shadow_enabled = false
			add_child(day_light)
			_day_lights.append(day_light)
	for x in [-16.0, 10.0]:
		var emergency := OmniLight3D.new()
		emergency.position = Vector3(x, 2.5, 51.0)
		emergency.light_color = Color("6d8b83")
		emergency.light_energy = 0.7
		emergency.omni_range = 10.0
		emergency.shadow_enabled = false
		add_child(emergency)
		_night_lights.append(emergency)
	var upper_light := OmniLight3D.new()
	upper_light.position = Vector3(-4.0, 7.4, 51.0)
	upper_light.light_color = Color("ffe5b7")
	upper_light.light_energy = 1.15
	upper_light.omni_range = 16.0
	upper_light.shadow_enabled = false
	add_child(upper_light)
	_day_lights.append(upper_light)
	var entrance_glow := OmniLight3D.new()
	entrance_glow.position = Vector3(CENTER_X, 4.5, 36.5)
	entrance_glow.light_color = Color("ffd39b")
	entrance_glow.light_energy = 0.2
	entrance_glow.omni_range = 15.0
	entrance_glow.shadow_enabled = false
	add_child(entrance_glow)
	_exterior_lights.append(entrance_glow)


func _build_inspection_points() -> void:
	# Keep the directory readable from the lobby without blocking the central
	# entrance's straight-through circulation path.
	_add_inspection(&"mall_directory", "Read mall directory", Vector3(3.0, 1.25, 41.2), Vector3(1.2, 2.1, 0.25), "DIRECTORY: Grocery and services downstairs. Food court and arcade upstairs. Escalators stop after closing.")
	_add_inspection(&"grocery_register", "Inspect abandoned register", Vector3(17.8, 1.0, 46.0), Vector3(1.2, 1.1, 0.8), "The register is open. The receipt says 19:94, but the mall clock has no hands.")
	_add_inspection(&"mall_service_door", "Check service door", Vector3(-6.2, 1.25, 63.7), Vector3(0.25, 2.3, 1.2), "A service exit leads south toward home. At night, cold air leaks through the frame.")


func _add_inspection(id: StringName, prompt: String, position: Vector3, size: Vector3, message: String) -> void:
	var object: StaticBody3D = InteractableType.new()
	object.name = String(id).to_pascal_case()
	object.position = position
	object.setup(id, prompt, message, false)
	object.activated.connect(func(_id: StringName, text: String) -> void: message_requested.emit(text))
	add_child(object)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	object.add_child(shape_node)
	_box("InspectVisual", Vector3.ZERO, size, Color("3d4748"), false, Vector3.ZERO, object)


func _build_grocery_shelf(position: Vector3, index: int) -> void:
	# One double-sided aisle: two shelf runs pressed back-to-back, products facing out.
	var pair := Node3D.new()
	pair.name = "GroceryAislePair_%d" % index
	pair.position = position
	add_child(pair)

	var half_depth: float = GroceryAislePropType.RAW_AABB.size.z * 0.5
	var aisle_length: float = GroceryAislePropType.RAW_AABB.size.x
	var aisle_height: float = GroceryAislePropType.RAW_AABB.size.y
	# Small gap so the spine cover can sit between the hollow backs without z-fighting.
	var cover_gap := 0.10
	_spawn_grocery_aisle_half(pair, "Left", Vector3(-(half_depth + cover_gap * 0.5), 0.0, 0.0), -PI * 0.5)
	_spawn_grocery_aisle_half(pair, "Right", Vector3(half_depth + cover_gap * 0.5, 0.0, 0.0), PI * 0.5)

	# Solid spine + end caps hide the open / intersecting backs of the mesh pair.
	var cover_color := Color("cfc6b4")
	var cover_height := aisle_height + 0.08
	_box(
		"AisleBackCover",
		Vector3(0.0, cover_height * 0.5, 0.0),
		Vector3(0.28, cover_height, aisle_length + 0.2),
		cover_color,
		true,
		Vector3.ZERO,
		pair
	)
	var end_width := half_depth * 2.0 + cover_gap + 0.2
	for end_z in [-aisle_length * 0.5, aisle_length * 0.5]:
		_box(
			"AisleEndCover",
			Vector3(0.0, cover_height * 0.5, end_z),
			Vector3(end_width, cover_height, 0.16),
			Color("bdb5a4"),
			true,
			Vector3.ZERO,
			pair
		)


func _spawn_grocery_aisle_half(parent: Node3D, side_name: String, local_position: Vector3, yaw: float) -> void:
	var aisle = GroceryAislePropType.new()
	aisle.name = "GroceryAisle_%s" % side_name
	aisle.position = local_position
	aisle.rotation.y = yaw
	parent.add_child(aisle)
	aisle.build()


func _spawn_vending_machine(position: Vector3, yaw: float) -> void:
	var vending = VendingMachinePropType.new()
	vending.name = "GroceryVending"
	vending.position = position
	# Model front/glass faces local +X; PI/2 aims it into the grocery (-Z).
	vending.rotation.y = yaw
	add_child(vending)
	vending.build()


func _build_checkout(position: Vector3) -> void:
	_box("CheckoutCounter", position + Vector3(0.0, 0.65, 0.0), Vector3(3.6, 0.9, 1.0), Color("6b716b"), true)
	_box("CheckoutBelt", position + Vector3(-0.55, 1.15, 0.0), Vector3(2.2, 0.10, 0.75), Color("222829"), false)
	_box("CheckoutScreen", position + Vector3(1.25, 1.55, 0.0), Vector3(0.15, 0.55, 0.55), Color("213941"), false)


func _build_table_set(position: Vector3) -> void:
	_cylinder("FoodTable", position + Vector3(0.0, 0.75, 0.0), 0.8, 0.12, Color("b49e7a"), Vector3.ZERO, true)
	_cylinder("FoodTablePost", position + Vector3(0.0, 0.38, 0.0), 0.10, 0.65, Color("55585a"), Vector3.ZERO, false)
	for offset in [Vector3(-1.15, 0.42, 0.0), Vector3(1.15, 0.42, 0.0), Vector3(0.0, 0.42, -1.15), Vector3(0.0, 0.42, 1.15)]:
		_box("FoodChair", position + offset, Vector3(0.7, 0.75, 0.7), Color("6f4439"), true)


func _build_arcade_cabinet(position: Vector3, index: int) -> void:
	_box("ArcadeCabinet", position + Vector3(0.0, 1.05, 0.0), Vector3(1.4, 2.0, 1.2), Color("27232f"), true)
	_box("ArcadeScreen", position + Vector3(0.0, 1.35, -0.64), Vector3(0.9, 0.65, 0.08), [Color("385d70"), Color("70405f"), Color("66743c")][index % 3], false)
	_box("ArcadeControls", position + Vector3(0.0, 0.85, -0.78), Vector3(1.0, 0.15, 0.45), Color("4c4555"), false, Vector3(-0.22, 0.0, 0.0))


func _build_car(name_value: String, position: Vector3, variant: int, yaw: float) -> Node3D:
	var car := StreetVehiclePropType.new()
	car.name = name_value
	car.position = position
	car.rotation.y = yaw
	car.configure(StreetVehiclePropType.Kind.STREET_CAR, variant, true)
	add_child(car)
	car.build()
	return car


func _build_motorcycle(name_value: String, position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = name_value
	root.position = position
	add_child(root)
	_box("BikeBody", Vector3.ZERO + Vector3(0.0, 0.75, 0.0), Vector3(0.45, 0.45, 1.4), Color("2d3032"), false, Vector3.ZERO, root)
	for z in [-0.75, 0.75]:
		_cylinder("BikeWheel", Vector3(0.0, 0.38, z), 0.32, 0.12, Color("111214"), Vector3(0.0, 0.0, PI / 2.0), false, root)
	return root


func _build_palm(position: Vector3) -> void:
	_cylinder("PalmTrunk", position + Vector3(0.0, 2.1, 0.0), 0.24, 4.0, Color("6b5437"), Vector3(0.0, 0.0, 0.06), true)
	for index in range(7):
		var angle := TAU * float(index) / 7.0
		var leaf := _box("PalmLeaf", position + Vector3(cos(angle) * 1.15, 4.25, sin(angle) * 1.15), Vector3(0.45, 0.10, 2.7), Color("355d3d"), false, Vector3(0.15, -angle, 0.0))
		leaf.rotation.y = -angle


func _build_parking_lamp(position: Vector3) -> void:
	_cylinder("MallLampPost", position + Vector3(0.0, 2.7, 0.0), 0.09, 5.4, Color("505457"), Vector3.ZERO, true)
	_box("MallLampHead", position + Vector3(0.0, 5.4, 0.0), Vector3(1.1, 0.18, 0.45), Color("6b6f70"), false)
	var light := OmniLight3D.new()
	light.position = position + Vector3(0.0, 5.15, 0.0)
	light.light_color = Color("f1d7a0")
	light.light_energy = 0.2
	light.omni_range = 10.0
	light.shadow_enabled = false
	add_child(light)
	_exterior_lights.append(light)


func _arch(prefix: String, center: Vector3, radius: float, color: Color, segments: int, yaw: float = 0.0) -> void:
	for index in range(segments + 1):
		var angle := PI - PI * float(index) / float(segments)
		var offset := Vector3(cos(angle) * radius, sin(angle) * radius, 0.0).rotated(Vector3.UP, yaw)
		var size := Vector3(maxf(radius * 0.30, 0.35), 0.28, 0.45)
		if not is_zero_approx(yaw):
			size = Vector3(0.45, 0.28, maxf(radius * 0.30, 0.35))
		_box(prefix + "_%02d" % index, center + offset, size, color, false, Vector3(0.0, yaw, angle - PI / 2.0))


func _add_label(parent: Node3D, text: String, local_position: Vector3, pixel_size: float, color: Color, face_north: bool, rotation_value: Vector3 = Vector3.ZERO) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = local_position
	label.rotation = rotation_value
	if face_north:
		label.rotation.y = PI
	label.pixel_size = pixel_size
	label.font_size = 48
	label.modulate = color
	label.outline_size = 7
	label.outline_modulate = Color("251f1b")
	parent.add_child(label)


func _box(
	object_name: String,
	position: Vector3,
	size: Vector3,
	color: Color,
	with_collision: bool = true,
	rotation_value: Vector3 = Vector3.ZERO,
	parent: Node = self
) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = object_name + "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not with_collision:
		mesh_instance.position = position
		mesh_instance.rotation = rotation_value
		parent.add_child(mesh_instance)
		return mesh_instance
	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position
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
	position: Vector3,
	radius: float,
	height: float,
	color: Color,
	rotation_value: Vector3 = Vector3.ZERO,
	with_collision: bool = false,
	parent: Node = self
) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = object_name + "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	if not with_collision:
		mesh_instance.position = position
		mesh_instance.rotation = rotation_value
		parent.add_child(mesh_instance)
		return mesh_instance
	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position
	body.rotation = rotation_value
	parent.add_child(body)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	body.add_child(collision)
	return body


func _material(color: Color) -> ShaderMaterial:
	var key := color.to_html(false)
	if _material_cache.has(key):
		return _material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = PSX_SHADER
	material.set_shader_parameter("albedo_color", color)
	_material_cache[key] = material
	return material
