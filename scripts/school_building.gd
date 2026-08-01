extends Node3D
class_name SchoolBuilding
## Procedural UC Banilad school — open inner courtyard, blue-white bands,
## open-air corridors, and floor layout from UCB_Building_Layout.md.

signal message_requested(text: String)
signal elevator_activated(id: StringName, message: String)


const ElevatorPanelType = preload("res://scripts/elevator_panel.gd")
const InteractableType = preload("res://scripts/interactable.gd")
const ClassroomChairBuilder = preload("res://scripts/classroom_chair_builder.gd")
const PSX_SHADER = preload("res://shaders/psx_surface.gdshader")

## Ten playable levels. The real building has no "first floor" label: the
## entrance level is Ground, a partial Mezzanine sits above the lobby, then
## 2F-8F stack normally and the ninth level is a reduced roof deck.
enum Level { GROUND, MEZZANINE, F2, F3, F4, F5, F6, F7, F8, ROOF }

const LEVEL_COUNT := 10
## Kept for callers that predate the mezzanine; both names mean "playable levels".
const FLOOR_COUNT := LEVEL_COUNT

const LEVEL_HEIGHTS := [4.6, 3.0, 3.4, 3.4, 3.4, 3.4, 3.4, 3.4, 3.4, 3.2]
## Running sum of LEVEL_HEIGHTS from BASE_Y. Spelled out because GDScript
## constants cannot be computed by a function at parse time.
const LEVEL_ELEVATIONS := [0.24, 4.84, 7.84, 11.24, 14.64, 18.04, 21.44, 24.84, 28.24, 31.64]

const LEVEL_SHORT_LABELS := ["G", "M", "2", "3", "4", "5", "6", "7", "8", "RD"]
const LEVEL_NAMES := [
	"GROUND FLOOR / ENTRANCE",
	"MEZZANINE",
	"SECOND FLOOR",
	"THIRD FLOOR",
	"FOURTH FLOOR",
	"FIFTH FLOOR",
	"SIXTH FLOOR",
	"SEVENTH FLOOR",
	"EIGHTH FLOOR",
	"NINTH FLOOR / ROOF DECK",
]
const LEVEL_SUBTITLES = [
	"LOBBY / QUADRANGLE / SHOPS",
	"ADMIN OFFICES",
	"GENERAL EDUCATION",
	"LIBRARIES",
	"DRAFTING / ED TECH",
	"HOSPITALITY LABS",
	"CRIMINOLOGY",
	"NURSING SKILLS",
	"COMPUTER / SCIENCE LABS",
	"ROOF LABS / OPEN DECK",
]

const FLOOR_HEIGHT := 3.4
const BASE_Y := 0.24
const FLOOR_SLAB_THICKNESS := 0.26
const ROOM_WALL_HEIGHT := FLOOR_HEIGHT - FLOOR_SLAB_THICKNESS
const WALL_JOIN_OVERLAP := 0.08

const OUTER_LEFT := -26.0
const OUTER_RIGHT := 26.0
const FRONT_Z := -22.5
const BACK_Z := -54.0

const COURT_LEFT := -12.0
const COURT_RIGHT := 12.0
const COURT_FRONT := -35.0
const COURT_BACK := -48.0

## South open corridor (front wing) — elevator teleport lands near here.
const CORRIDOR_S_Z := -33.8
const CORRIDOR_N_Z := -49.2
const CORRIDOR_W_X := -13.2
const CORRIDOR_E_X := 13.2
const SOUTH_ROOM_WALL_Z := COURT_FRONT + 2.4
const NORTH_ROOM_WALL_Z := COURT_BACK - 2.4

## Side-wing room walls mirror the front/back ones so all four sides of the
## ring can carry real rooms instead of bare corridor.
const EAST_ROOM_WALL_X := COURT_RIGHT + 2.4
const WEST_ROOM_WALL_X := COURT_LEFT - 2.4
## Rooms stop short of the exterior shell so wall faces never coincide.
const FRONT_ROOM_BACK_Z := FRONT_Z - 0.35
const BACK_ROOM_BACK_Z := BACK_Z + 0.35
const EAST_ROOM_BACK_X := OUTER_RIGHT - 0.35
## The west block is shallow: the outer half of that wing is the stair corridor.
const WEST_ROOM_BACK_X := -18.5
## Both side wings share one bay span so corridors line up on every level.
const SIDE_BAY_FRONT_Z := -34.4
const SIDE_BAY_BACK_Z := -48.6

## Elevator core sits just east of the centred street entrance, matching the
## bottom-centre position on the ground-floor directory.
const ELEVATOR_BANK_LEFT_X := 4.6
const ELEVATOR_BANK_RIGHT_X := 10.6
const ELEVATOR_DOOR_X := (ELEVATOR_BANK_LEFT_X + ELEVATOR_BANK_RIGHT_X) * 0.5
## Where a rider is placed after the car "arrives": the open-air south corridor.
const ELEVATOR_LANDING_Z := -33.9

## Mezzanine void: the opening the mezzanine wraps so it overlooks the lobby.
const MEZZ_VOID_LEFT_X := -11.0
const MEZZ_VOID_RIGHT_X := 4.0
const MEZZ_VOID_BACK_Z := -31.5

## Street doorway sits on the LEFT of the facade (locker / gate side), not
## centred. Approach ramp and lobby opening share this same X.
const ENTRANCE_CENTER_X := -12.0
const ENTRANCE_HALF_WIDTH := 4.5
const RAMP_LEFT_X := ENTRANCE_CENTER_X - 4.5
const RAMP_RIGHT_X := ENTRANCE_CENTER_X + 4.5

const STAIR_HOLE_LEFT_X := -25.5
const STAIR_HOLE_RIGHT_X := -18.5
const STAIR_HOLE_FRONT_Z := -38.0
const STAIR_HOLE_BACK_Z := -46.5

## Architectural surfaces use a finer snap than small props so long floor edges
## keep the PSX shimmer without visibly tearing apart while the camera moves.
const BUILDING_VERTEX_SNAP := 720.0
const SURFACE_LAYER_HEIGHT := 0.012

## Stair geometry is kept inside the rectangular slab opening. Landings meet the
## surrounding slabs and side walk exactly at their edges instead of overlapping.
const STAIR_SIDE_WALK_RIGHT_X := -24.2
const STAIR_ENTRY_DEPTH := 1.4
const STAIR_ENTRY_Z := STAIR_HOLE_BACK_Z + STAIR_ENTRY_DEPTH * 0.5
const STAIR_FLIGHT_BACK_Z := STAIR_ENTRY_Z + STAIR_ENTRY_DEPTH * 0.5
const STAIR_FLIGHT_FRONT_Z := -39.3
const STAIR_MID_DEPTH := 1.3
const STAIR_MID_Z := STAIR_FLIGHT_FRONT_Z + STAIR_MID_DEPTH * 0.5
const STAIR_LANDING_CENTER_X := (STAIR_SIDE_WALK_RIGHT_X + STAIR_HOLE_RIGHT_X) * 0.5
const STAIR_LANDING_WIDTH := STAIR_HOLE_RIGHT_X - STAIR_SIDE_WALK_RIGHT_X
const STAIR_FLIGHT_WIDTH := 2.5
const STAIR_RAMP_TRANSITION := 0.45
const STAIR_RAIL_END_CLEARANCE := 0.45
const STAIR_DOOR_HEIGHT := 2.35

const WALL_WHITE := Color("dce6ec")
const WALL_INNER := Color("d4dce2")
const BLUE_BAND := Color("1a7a8a")
const BLUE_BAND_DARK := Color("0d5c6a")
const CONCRETE := Color("8e908c")
const FLOOR_TILE := Color("7a7c78")
const GLASS_DARK := Color("1a3038")
const BLACK_CHAIR := Color("1c1c1e")
const WOOD_DESK := Color("6a543c")
## Interior finish palette taken from the interior photographs.
const CYAN_TRIM := Color("2b93a8")
const CYAN_DOOR := Color("1d6f82")
const STAINLESS := Color("9aa3a6")
const FIRE_PIPE_RED := Color("8e2b22")
const LOBBY_TILE := Color("a9a79c")
const OPEN_CORRIDOR := Color("5c605c")
const AC_UNIT := Color("c6cac6")

## Front-wing bay edges. Upper levels share one rhythm so the facade columns,
## the elevator core and the courtyard railing posts stay aligned.
const FRONT_BAY_SLOTS := [
	[-25.65, -19.2], [-19.2, -12.6], [-12.6, -6.0], [-6.0, 4.5], [10.6, 17.8], [17.8, 25.65],
]
const GROUND_FRONT_SLOTS := [
	[-25.65, -19.2], [-19.2, -12.6], [-12.6, 4.5], [10.6, 17.8], [17.8, 25.65],
]
const MEZZ_FRONT_SLOTS := [
	[-25.65, -19.2], [-19.2, -15.0], [-15.0, -11.0], [-11.0, 4.0],
	[10.6, 15.2], [15.2, 19.8], [19.8, 25.65],
]

## Every level is described here rather than generated from a repeated template.
## "front" bays map onto the slot table in order; the side and back wings are
## split evenly across their wing span. A bay is only emitted with a door when a
## real room stands behind it, so no opening leads into solid structure.
##
## Ground and Mezzanine follow the photographed UC directory. Floors 2-8 and the
## roof deck use generic teaching-space names on purpose.
const LEVEL_SPECS := [
	{
		"slots": GROUND_FRONT_SLOTS,
		"front": [
			{"name": "", "type": "void"},
			{"name": "GUARD POST", "type": "guard"},
			{"name": "MAIN LOBBY", "type": "lobby"},
			{"name": "PCO / BUILDING OFFICE", "type": "office"},
			{"name": "TESTING ROOM", "type": "office"},
		],
		"east": [
			{"name": "ACCOUNTING OFFICE", "type": "office"},
			{"name": "VIP", "type": "office"},
			{"name": "REGISTRAR'S OFFICE", "type": "office"},
			{"name": "GUIDANCE OFFICE", "type": "office"},
			{"name": "CLINIC", "type": "clinic"},
		],
		"west": [
			{"name": "", "type": "void"},
			{"name": "", "type": "void"},
			{"name": "", "type": "void"},
			{"name": "", "type": "void"},
			{"name": "", "type": "void"},
		],
		"back": [
			{"name": "CANTEEN", "type": "canteen"},
			{"name": "CHAPEL", "type": "chapel"},
			{"name": "CAMPUS MINISTRY", "type": "office"},
			{"name": "OFFICE", "type": "office"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
			{"name": "CW LAUNDRY", "type": "service"},
			{"name": "ASPAC BANK", "type": "office"},
			{"name": "LOCKER ROOM", "type": "storage"},
		],
	},
	{
		"slots": MEZZ_FRONT_SLOTS,
		"front": [
			{"name": "CHANCELLOR'S OFFICE", "type": "office"},
			{"name": "PRESIDENT'S OFFICE", "type": "office"},
			{"name": "HRD OFFICE", "type": "office"},
			{"name": "", "type": "void"},
			{"name": "CONFERENCE ROOM", "type": "office"},
			{"name": "CAD OFFICE", "type": "office"},
			{"name": "EXECUTIVE OFFICES", "type": "office"},
		],
		"east": [
			{"name": "NORWEGIAN OFFICE", "type": "office"},
			{"name": "FUNCTION ROOM", "type": "office"},
			{"name": "LINKAGE OFFICE", "type": "office"},
			{"name": "PHOTO STUDIO", "type": "office"},
			{"name": "UC CARES", "type": "office"},
			{"name": "SCHOOL OF LAW", "type": "office"},
			{"name": "CCS DEAN'S OFFICE", "type": "office"},
		],
		"west": [],
		"back": [
			{"name": "M2 / M3", "type": "classroom"},
			{"name": "M4 / M5", "type": "classroom"},
			{"name": "M6 / M7", "type": "classroom"},
			{"name": "M8 / M9", "type": "classroom"},
			{"name": "M10 / M11", "type": "classroom"},
			{"name": "M12", "type": "classroom"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
		],
	},
	{
		"front": [
			{"name": "ROOM 201", "type": "classroom"},
			{"name": "ROOM 202", "type": "classroom"},
			{"name": "ROOM 203", "type": "classroom"},
			{"name": "ROOM 204", "type": "lab"},
			{"name": "READING ROOM", "type": "office"},
			{"name": "FACULTY OFFICE", "type": "office"},
		],
		"east": [
			{"name": "ROOM 205", "type": "classroom"},
			{"name": "ROOM 206", "type": "classroom"},
			{"name": "ROOM 207", "type": "classroom"},
			{"name": "ROOM 208", "type": "classroom"},
		],
		"west": [
			{"name": "ROOM 209", "type": "classroom"},
			{"name": "ROOM 210", "type": "classroom"},
			{"name": "SPEECH LAB", "type": "lab"},
		],
		"back": [
			{"name": "ROOM 211", "type": "classroom"},
			{"name": "ROOM 212", "type": "classroom"},
			{"name": "ROOM 213", "type": "classroom"},
			{"name": "ROOM 214", "type": "classroom"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
		],
	},
	{
		"front": [
			{"name": "GENERAL LIBRARY", "type": "library"},
			{"name": "LIBRARY EXTENSION", "type": "library"},
			{"name": "ROOM 303", "type": "classroom"},
			{"name": "ROOM 304", "type": "classroom"},
			{"name": "READING HALL", "type": "library"},
			{"name": "ROOM 306", "type": "classroom"},
		],
		"east": [
			{"name": "ROOM 307", "type": "classroom"},
			{"name": "ROOM 308", "type": "classroom"},
			{"name": "ROOM 309", "type": "classroom"},
			{"name": "ROOM 310", "type": "classroom"},
		],
		"west": [
			{"name": "ROOM 311", "type": "classroom"},
			{"name": "ROOM 312", "type": "classroom"},
			{"name": "INTERNET AREA", "type": "lab"},
		],
		"back": [
			{"name": "ROOM 313", "type": "classroom"},
			{"name": "ROOM 314", "type": "classroom"},
			{"name": "ROOM 315", "type": "classroom"},
			{"name": "ROOM 316", "type": "classroom"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
		],
	},
	{
		"front": [
			{"name": "DRAFTING ROOM", "type": "lab"},
			{"name": "ROOM 402", "type": "classroom"},
			{"name": "ROOM 403", "type": "classroom"},
			{"name": "ROOM 404", "type": "classroom"},
			{"name": "ED TECH ROOM", "type": "lab"},
			{"name": "FACULTY ROOM", "type": "office"},
		],
		"east": [
			{"name": "ROOM 407", "type": "classroom"},
			{"name": "ROOM 408", "type": "classroom"},
			{"name": "ROOM 409", "type": "classroom"},
			{"name": "ROOM 410", "type": "classroom"},
		],
		"west": [
			{"name": "ROOM 411", "type": "classroom"},
			{"name": "ROOM 412", "type": "classroom"},
			{"name": "ROOM 413", "type": "classroom"},
		],
		"back": [
			{"name": "ROOM 414", "type": "classroom"},
			{"name": "ROOM 415", "type": "classroom"},
			{"name": "ROOM 416", "type": "classroom"},
			{"name": "ROOM 417", "type": "classroom"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
		],
	},
	{
		"front": [
			{"name": "ANATOMY LAB 1", "type": "lab"},
			{"name": "KITCHEN LAB 1", "type": "lab"},
			{"name": "KITCHEN LAB 2", "type": "lab"},
			{"name": "BAR & RESTAURANT", "type": "canteen"},
			{"name": "HRM FACULTY ROOM", "type": "office"},
			{"name": "ROOM 502", "type": "classroom"},
		],
		"east": [
			{"name": "NUTRITION LAB 1", "type": "lab"},
			{"name": "NUTRITION LAB 2", "type": "lab"},
			{"name": "TOURISM LAB", "type": "lab"},
			{"name": "MINI HOTEL", "type": "office"},
		],
		"west": [
			{"name": "HOUSEKEEPING LAB", "type": "lab"},
			{"name": "KITCHEN LAB 3", "type": "lab"},
			{"name": "KITCHEN LAB 4", "type": "lab"},
		],
		"back": [
			{"name": "NURSING SKILLS LAB 1", "type": "lab"},
			{"name": "CONSULTATION ROOM", "type": "office"},
			{"name": "NURSING DEAN'S OFFICE", "type": "office"},
			{"name": "ROOM 519", "type": "classroom"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
		],
	},
	{
		"front": [
			{"name": "CRIM LAB 1", "type": "lab"},
			{"name": "CRIM LAB 2", "type": "lab"},
			{"name": "ROOM 603", "type": "classroom"},
			{"name": "ROOM 604", "type": "classroom"},
			{"name": "CRIMINOLOGY DEAN", "type": "office"},
			{"name": "SSC OFFICE", "type": "office"},
		],
		"east": [
			{"name": "ROOM 605", "type": "classroom"},
			{"name": "ROOM 606", "type": "classroom"},
			{"name": "ROOM 607", "type": "classroom"},
			{"name": "SMART LAB", "type": "lab"},
		],
		"west": [
			{"name": "ROOM 609", "type": "classroom"},
			{"name": "ROOM 610", "type": "classroom"},
			{"name": "PCE / CPE LAB", "type": "lab"},
		],
		"back": [
			{"name": "ROOM 620", "type": "classroom"},
			{"name": "ROOM 621", "type": "classroom"},
			{"name": "ROOM 622", "type": "classroom"},
			{"name": "ROOM 623", "type": "classroom"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
		],
	},
	{
		"front": [
			{"name": "ANATOMY LAB 2", "type": "lab"},
			{"name": "ROOM 702", "type": "classroom"},
			{"name": "ROOM 703", "type": "classroom"},
			{"name": "ROOM 704", "type": "classroom"},
			{"name": "CANTEEN", "type": "canteen"},
			{"name": "ROOM 706", "type": "classroom"},
		],
		"east": [
			{"name": "NURSING SKILLS LAB 2", "type": "lab"},
			{"name": "NURSING SKILLS LAB 3", "type": "lab"},
			{"name": "ROOM 709", "type": "classroom"},
			{"name": "ROOM 710", "type": "classroom"},
		],
		"west": [
			{"name": "ROOM 711", "type": "classroom"},
			{"name": "ROOM 712", "type": "classroom"},
			{"name": "ROOM 713", "type": "classroom"},
		],
		"back": [
			{"name": "ROOM 714", "type": "classroom"},
			{"name": "ROOM 715", "type": "classroom"},
			{"name": "ROOM 717", "type": "classroom"},
			{"name": "ROOM 718", "type": "classroom"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
		],
	},
	{
		"front": [
			{"name": "COMPUTER LAB 1", "type": "lab"},
			{"name": "COMPUTER LAB 2", "type": "lab"},
			{"name": "COMPUTER LAB 3", "type": "lab"},
			{"name": "ROOM 803", "type": "lab"},
			{"name": "CONTROL ROOM", "type": "service"},
			{"name": "AVR 1", "type": "office"},
		],
		"east": [
			{"name": "AVR 2", "type": "office"},
			{"name": "MOOT COURT", "type": "office"},
			{"name": "PHYSICS LAB 1", "type": "lab"},
			{"name": "PHYSICS LAB 2", "type": "lab"},
		],
		"west": [
			{"name": "COMPUTER LAB 4", "type": "lab"},
			{"name": "COMPUTER LAB 5", "type": "lab"},
			{"name": "STOCK ROOM", "type": "storage"},
		],
		"back": [
			{"name": "MEDTECH OFFICE", "type": "office"},
			{"name": "MOLECULAR BIOLOGY", "type": "lab"},
			{"name": "MEDTECH LABORATORY", "type": "lab"},
			{"name": "ELECTRICAL ROOM", "type": "service"},
			{"name": "MALE CR", "type": "cr"},
			{"name": "FEMALE CR", "type": "cr"},
		],
	},
	{
		"front": [],
		"east": [],
		"west": [],
		"back": [
			{"name": "HISTOLOGY LAB", "type": "lab"},
			{"name": "BLOOD BANKING LAB", "type": "lab"},
			{"name": "SEROLOGY LAB", "type": "lab"},
			{"name": "HEMATOLOGY LAB", "type": "lab"},
			{"name": "STOCK ROOM", "type": "storage"},
			{"name": "ELEVATOR MACHINE ROOM", "type": "machine"},
		],
	},
]

var _player: CharacterBody3D = null
var _material_cache: Dictionary = {}
## Lights keyed by floor index for distance culling.
var _floor_dynamic_lights: Array = []  # Array[Array] of Light3D
var _active_light_floor := -999
var _light_cull_timer := 0.0


## Finished-floor height of a level. Index LEVEL_COUNT returns the top of the
## building so roof geometry can be placed without special-casing.
static func level_y(level: int) -> float:
	if level <= 0:
		return LEVEL_ELEVATIONS[0]
	if level >= LEVEL_COUNT:
		return LEVEL_ELEVATIONS[LEVEL_COUNT - 1] + LEVEL_HEIGHTS[LEVEL_COUNT - 1]
	return LEVEL_ELEVATIONS[level]


static func level_height(level: int) -> float:
	return LEVEL_HEIGHTS[clampi(level, 0, LEVEL_COUNT - 1)]


static func level_label(level: int) -> String:
	return LEVEL_SHORT_LABELS[clampi(level, 0, LEVEL_COUNT - 1)]


static func level_name(level: int) -> String:
	return LEVEL_NAMES[clampi(level, 0, LEVEL_COUNT - 1)]


static func building_height() -> float:
	return level_y(LEVEL_COUNT) - BASE_Y


## Where the elevator drops a rider off: the open-air corridor outside the car.
static func elevator_landing_local(level: int) -> Vector3:
	return Vector3(ELEVATOR_DOOR_X, level_y(level) + 0.95, ELEVATOR_LANDING_Z)


## Nearest level at or below a world-space height, used for light culling.
static func level_at_height(y: float) -> int:
	var found := 0
	for level in range(LEVEL_COUNT):
		if y >= LEVEL_ELEVATIONS[level] - 1.0:
			found = level
	return found


func configure(player: CharacterBody3D) -> void:
	_player = player


func build() -> void:
	_floor_dynamic_lights.clear()
	for _i in range(LEVEL_COUNT):
		_floor_dynamic_lights.append([])
	_build_core_shell()
	for level in range(LEVEL_COUNT):
		_build_one_floor(level)
	_build_courtyard_bridge()
	_build_stairwell()
	_apply_floor_light_cull(0)


func build_async(scene_tree: SceneTree) -> void:
	## Spread mesh creation across frames so spawn doesn't hitch for a second.
	_floor_dynamic_lights.clear()
	for _i in range(LEVEL_COUNT):
		_floor_dynamic_lights.append([])
	_build_core_shell()
	await scene_tree.process_frame
	for level in range(LEVEL_COUNT):
		_build_one_floor(level)
		await scene_tree.process_frame
	_build_courtyard_bridge()
	await scene_tree.process_frame
	_build_stairwell()
	_apply_floor_light_cull(0)


func _build_core_shell() -> void:
	_build_entry_plaza()
	_build_entry_gate()
	_build_entrance_ramp()
	_build_courtyard_ground()
	_build_courtyard_fence()
	_build_floor_slabs()
	_build_outer_shell()
	_build_facade()
	_build_modern_street_facade()
	_build_courtyard_parapets()
	_build_chamfered_corners()


func _build_one_floor(level: int) -> void:
	_build_floor_layout(level)
	_build_floor_signage(level)
	_build_floor_lighting(level)
	_build_floor_rooms(level)


func _process(delta: float) -> void:
	if _player == null or _floor_dynamic_lights.is_empty():
		return
	_light_cull_timer -= delta
	if _light_cull_timer > 0.0:
		return
	_light_cull_timer = 0.35
	var floor_index := level_at_height(_player.global_position.y)
	if floor_index != _active_light_floor:
		_apply_floor_light_cull(floor_index)


func _apply_floor_light_cull(floor_index: int) -> void:
	_active_light_floor = floor_index
	for i in range(_floor_dynamic_lights.size()):
		var enabled: bool = absi(i - floor_index) <= 1
		for light in _floor_dynamic_lights[i]:
			if is_instance_valid(light):
				(light as Light3D).visible = enabled


func _register_floor_light(floor_index: int, light: Light3D) -> void:
	if floor_index < 0 or floor_index >= _floor_dynamic_lights.size():
		return
	_floor_dynamic_lights[floor_index].append(light)


func _floor_y(floor_index: int) -> float:
	return level_y(floor_index)


func _room_wall_height(level: int) -> float:
	return level_height(level) - FLOOR_SLAB_THICKNESS


func _building_width() -> float:
	return OUTER_RIGHT - OUTER_LEFT


func _building_depth() -> float:
	return absf(BACK_Z - FRONT_Z)


func _build_entry_plaza() -> void:
	_box(
		"SchoolEntryPlaza",
		Vector3(0.0, 0.12, -17.1),
		Vector3(50.0, 0.24, 11.2),
		Color("4a4943")
	)
	for x in [-12.0, 12.0]:
		_box("Planter", Vector3(x, 0.48, -17.2), Vector3(3.3, 0.7, 1.5), Color("55534a"))
		_box("PlanterSoil", Vector3(x, 0.86, -17.2), Vector3(3.0, 0.08, 1.2), Color("2d241c"), false)


func _build_entry_gate() -> void:
	## Campus gate aligned with the left-side street entrance (not building centre).
	var gate_z := -11.85
	var gate_half_opening := 2.4
	var gate_x := ENTRANCE_CENTER_X
	var fence_color := Color("25282a")
	_build_metal_fence_x("CampusFenceWest", -22.0, gate_x - gate_half_opening, gate_z, BASE_Y, 1.55, fence_color)
	_build_metal_fence_x("CampusFenceEast", gate_x + gate_half_opening, 10.0, gate_z, BASE_Y, 1.55, fence_color)
	for side: float in [-1.0, 1.0]:
		_box("CampusGatePost", Vector3(gate_x + side * gate_half_opening, BASE_Y + 1.35, gate_z), Vector3(0.28, 2.7, 0.28), WALL_WHITE)
	_box("CampusGateHeader", Vector3(gate_x, BASE_Y + 2.62, gate_z), Vector3(gate_half_opening * 2.0, 0.24, 0.3), WALL_WHITE)

	# Two leaves swung toward the plaza
	var leaf_width := 2.05
	var leaf_angle := deg_to_rad(78.0)
	var leaf_z := gate_z - sin(leaf_angle) * leaf_width * 0.5
	var leaf_x_offset := cos(leaf_angle) * leaf_width * 0.5
	_rotated_box(
		"CampusGateLeafL",
		Vector3(gate_x - gate_half_opening + leaf_x_offset, BASE_Y + 0.78, leaf_z),
		Vector3(leaf_width, 1.45, 0.08),
		Vector3(0.0, leaf_angle, 0.0),
		fence_color
	)
	_rotated_box(
		"CampusGateLeafR",
		Vector3(gate_x + gate_half_opening - leaf_x_offset, BASE_Y + 0.78, leaf_z),
		Vector3(leaf_width, 1.45, 0.08),
		Vector3(0.0, -leaf_angle, 0.0),
		fence_color
	)


func _build_courtyard_ground() -> void:
	var court_w := COURT_RIGHT - COURT_LEFT
	var court_d := absf(COURT_BACK - COURT_FRONT)
	var court_cx := (COURT_LEFT + COURT_RIGHT) * 0.5
	var court_cz := (COURT_FRONT + COURT_BACK) * 0.5

	# The full ground-floor slab supplies collision. These thin, visual-only
	# layers sit at distinct heights so their nested faces cannot z-fight.
	_box(
		"CourtyardFloor",
		Vector3(court_cx, BASE_Y + SURFACE_LAYER_HEIGHT * 0.5, court_cz),
		Vector3(court_w, SURFACE_LAYER_HEIGHT, court_d),
		Color("6e706c"),
		false
	)

	# The directory draws the multipurpose ground as a bordered rectangle with a
	# painted X across it; that marking replaces the earlier court lines.
	_box("CourtPaintBorder", Vector3(court_cx, BASE_Y + SURFACE_LAYER_HEIGHT * 1.5, court_cz), Vector3(court_w - 1.6, SURFACE_LAYER_HEIGHT, court_d - 1.6), Color("cfd2cb"), false)
	_box("CourtPaintField", Vector3(court_cx, BASE_Y + SURFACE_LAYER_HEIGHT * 2.5, court_cz), Vector3(court_w - 2.0, SURFACE_LAYER_HEIGHT, court_d - 2.0), Color("6e706c"), false)
	var diagonal_length := sqrt(pow(court_w - 2.0, 2.0) + pow(court_d - 2.0, 2.0))
	var diagonal_angle := atan2(court_d - 2.0, court_w - 2.0)
	for stroke in [-1.0, 1.0]:
		_rotated_box(
			"CourtPaintX%s" % ("A" if stroke < 0.0 else "B"),
			Vector3(court_cx, BASE_Y + SURFACE_LAYER_HEIGHT * 3.5, court_cz),
			Vector3(diagonal_length, SURFACE_LAYER_HEIGHT, 0.35),
			Vector3(0.0, stroke * diagonal_angle, 0.0),
			Color("cfd2cb"),
			false
		)

	# Hoop stand (south end of court).
	_box("HoopPole", Vector3(court_cx - 4.5, BASE_Y + 1.6, COURT_FRONT - 1.8), Vector3(0.12, 3.2, 0.12), Color("c8c8c8"), false)
	_box("HoopBackboard", Vector3(court_cx - 4.5, BASE_Y + 3.1, COURT_FRONT - 2.05), Vector3(1.6, 1.05, 0.08), Color("f0f0f0"), false)
	_box("HoopRim", Vector3(court_cx - 4.5, BASE_Y + 2.75, COURT_FRONT - 2.35), Vector3(0.55, 0.06, 0.55), Color("c45a20"), false)

	# Courtyard trees — scaled to fit neatly inside courtyard without clipping into walkways.
	for tree_pos in [
		Vector3(court_cx + 6.5, BASE_Y, court_cz - 3.0),
		Vector3(court_cx - 5.5, BASE_Y, court_cz + 2.5),
		Vector3(court_cx + 3.0, BASE_Y, court_cz + 4.5),
	]:
		_box("TreePlanter", tree_pos + Vector3(0.0, 0.35, 0.0), Vector3(1.8, 0.7, 1.8), Color("7a7c76"))
		_box("TreeSoil", tree_pos + Vector3(0.0, 0.72, 0.0), Vector3(1.5, 0.08, 1.5), Color("2c241c"), false)
		_box("TreeTrunk", tree_pos + Vector3(0.0, 3.5, 0.0), Vector3(0.28, 6.2, 0.28), Color("4a3828"), false)
		_box("TreeCanopyLow", tree_pos + Vector3(0.0, 5.2, 0.0), Vector3(2.4, 1.8, 2.4), Color("3d6b3a"), false)
		_box("TreeCanopyMid", tree_pos + Vector3(0.0, 6.8, 0.0), Vector3(2.8, 2.0, 2.8), Color("4a7d45"), false)
		_box("TreeCanopyTop", tree_pos + Vector3(0.0, 8.5, 0.0), Vector3(2.2, 1.6, 2.2), Color("5a8d52"), false)

	# Benches + flagpole (assembly area).
	for x in [-6.0, 0.0, 6.0]:
		_box("CourtBench", Vector3(x, BASE_Y + 0.35, COURT_BACK + 1.6), Vector3(2.4, 0.45, 0.55), Color("4d4437"), false)
	_box("FlagPole", Vector3(court_cx + 8.5, BASE_Y + 3.2, COURT_FRONT - 2.0), Vector3(0.1, 6.4, 0.1), Color("b8b8b8"), false)
	_box("Flag", Vector3(court_cx + 9.1, BASE_Y + 5.8, COURT_FRONT - 2.0), Vector3(1.2, 0.7, 0.05), Color("1e4f7a"), false)

	# Guard / reception lean-to on courtyard edge (matches photo notice boards).
	_box("CourtGuardBooth", Vector3(COURT_RIGHT - 3.0, BASE_Y + 1.2, COURT_BACK + 1.7), Vector3(3.2, 2.4, 2.0), WALL_WHITE)
	_box("BulletinBoard", Vector3(COURT_RIGHT - 3.0, BASE_Y + 1.5, COURT_BACK + 2.74), Vector3(2.6, 1.6, 0.08), Color("2a4050"), false)


func _build_floor_slabs() -> void:
	var full_w := _building_width()
	var full_d := _building_depth()
	var center_x := (OUTER_LEFT + OUTER_RIGHT) * 0.5
	var center_z := (FRONT_Z + BACK_Z) * 0.5
	var court_d := absf(COURT_BACK - COURT_FRONT)
	var court_cz := (COURT_FRONT + COURT_BACK) * 0.5

	# Ground floor continuous slab (courtyard painted on top).
	_box(
		"FloorSlab_1",
		Vector3(center_x, BASE_Y - 0.13, center_z),
		Vector3(full_w, 0.26, full_d),
		FLOOR_TILE
	)

	# Upper levels: ring slabs around the open courtyard, with a stair hole on
	# the west wing and (on the mezzanine only) a void over the ground lobby.
	# Node suffixes are level index + 1, so _02 is the mezzanine and _10 the deck.
	for floor_index in range(1, LEVEL_COUNT):
		var y := _floor_y(floor_index) - 0.13
		# South ring (front wing + south corridor).
		if floor_index == Level.MEZZANINE:
			# The mezzanine is a partial floor: it wraps the lobby void instead
			# of duplicating the whole front wing.
			var void_depth := absf(MEZZ_VOID_BACK_Z - FRONT_Z)
			var left_w := MEZZ_VOID_LEFT_X - OUTER_LEFT
			var right_w := OUTER_RIGHT - MEZZ_VOID_RIGHT_X
			_box(
				"FloorSlabSouth_%02d" % (floor_index + 1),
				Vector3(center_x, y, (MEZZ_VOID_BACK_Z + COURT_FRONT) * 0.5),
				Vector3(full_w, 0.26, absf(COURT_FRONT - MEZZ_VOID_BACK_Z)),
				FLOOR_TILE
			)
			_box(
				"FloorSlabSouthWest_%02d" % (floor_index + 1),
				Vector3(OUTER_LEFT + left_w * 0.5, y, (FRONT_Z + MEZZ_VOID_BACK_Z) * 0.5),
				Vector3(left_w, 0.26, void_depth),
				FLOOR_TILE
			)
			_box(
				"FloorSlabSouthEast_%02d" % (floor_index + 1),
				Vector3(OUTER_RIGHT - right_w * 0.5, y, (FRONT_Z + MEZZ_VOID_BACK_Z) * 0.5),
				Vector3(right_w, 0.26, void_depth),
				FLOOR_TILE
			)
		else:
			_box(
				"FloorSlabSouth_%02d" % (floor_index + 1),
				Vector3(center_x, y, (FRONT_Z + COURT_FRONT) * 0.5),
				Vector3(full_w, 0.26, absf(COURT_FRONT - FRONT_Z)),
				FLOOR_TILE
			)
		# North ring (back wing).
		_box(
			"FloorSlabNorth_%02d" % (floor_index + 1),
			Vector3(center_x, y, (COURT_BACK + BACK_Z) * 0.5),
			Vector3(full_w, 0.26, absf(BACK_Z - COURT_BACK)),
			FLOOR_TILE
		)
		# West ring (minus stair hole).
		_box(
			"FloorSlabWestFront_%02d" % (floor_index + 1),
			Vector3((OUTER_LEFT + COURT_LEFT) * 0.5, y, (COURT_FRONT + STAIR_HOLE_FRONT_Z) * 0.5),
			Vector3(COURT_LEFT - OUTER_LEFT, 0.26, absf(STAIR_HOLE_FRONT_Z - COURT_FRONT)),
			FLOOR_TILE
		)
		_box(
			"FloorSlabWestBack_%02d" % (floor_index + 1),
			Vector3((OUTER_LEFT + COURT_LEFT) * 0.5, y, (STAIR_HOLE_BACK_Z + COURT_BACK) * 0.5),
			Vector3(COURT_LEFT - OUTER_LEFT, 0.26, absf(COURT_BACK - STAIR_HOLE_BACK_Z)),
			FLOOR_TILE
		)
		_box(
			"FloorSlabWestOuter_%02d" % (floor_index + 1),
			Vector3((OUTER_LEFT + STAIR_HOLE_LEFT_X) * 0.5, y, (STAIR_HOLE_FRONT_Z + STAIR_HOLE_BACK_Z) * 0.5),
			Vector3(STAIR_HOLE_LEFT_X - OUTER_LEFT, 0.26, absf(STAIR_HOLE_BACK_Z - STAIR_HOLE_FRONT_Z)),
			FLOOR_TILE
		)
		_box(
			"FloorSlabWestInner_%02d" % (floor_index + 1),
			Vector3((STAIR_HOLE_RIGHT_X + COURT_LEFT) * 0.5, y, (STAIR_HOLE_FRONT_Z + STAIR_HOLE_BACK_Z) * 0.5),
			Vector3(COURT_LEFT - STAIR_HOLE_RIGHT_X, 0.26, absf(STAIR_HOLE_BACK_Z - STAIR_HOLE_FRONT_Z)),
			FLOOR_TILE
		)
		# East ring.
		_box(
			"FloorSlabEast_%02d" % (floor_index + 1),
			Vector3((COURT_RIGHT + OUTER_RIGHT) * 0.5, y, court_cz),
			Vector3(OUTER_RIGHT - COURT_RIGHT, 0.26, court_d),
			FLOOR_TILE
		)

	# The ninth level is an open roof deck, so only its enclosed back-wing labs
	# and the elevator machine room receive a roof. The rest stays open to sky
	# behind a parapet built with the deck layout.
	var roof_y := _floor_y(LEVEL_COUNT) - 0.13
	_box(
		"RoofNorth",
		Vector3(center_x, roof_y, (COURT_BACK + BACK_Z) * 0.5),
		Vector3(full_w, 0.26, absf(BACK_Z - COURT_BACK)),
		Color("454844")
	)


func _build_outer_shell() -> void:
	# The shell rises to the roof-deck floor; the deck itself is enclosed by a
	# shorter parapet so the top level reads as an open deck from the street.
	var shell_height := level_y(Level.ROOF) - BASE_Y
	var center_y := BASE_Y + shell_height * 0.5
	var center_z := (FRONT_Z + BACK_Z) * 0.5
	var full_d := _building_depth()

	# Overlap the exterior faces so PSX vertex snapping cannot reveal a daylight
	# seam at any shell corner.
	_box("SchoolBackWall", Vector3(0.0, center_y, BACK_Z), Vector3(_building_width() + WALL_JOIN_OVERLAP * 2.0, shell_height, 0.35), WALL_WHITE)
	_box("SchoolLeftWall", Vector3(OUTER_LEFT, center_y, center_z), Vector3(0.35, shell_height, full_d + WALL_JOIN_OVERLAP * 2.0), WALL_WHITE)
	_box("SchoolRightWall", Vector3(OUTER_RIGHT, center_y, center_z), Vector3(0.35, shell_height, full_d + WALL_JOIN_OVERLAP * 2.0), WALL_WHITE)

	# Roof-deck parapet, tall enough that the player cannot walk off the edge.
	var parapet_h := 1.35
	var parapet_y := level_y(Level.ROOF) + parapet_h * 0.5
	_box("DeckParapetBack", Vector3(0.0, parapet_y, BACK_Z), Vector3(_building_width() + WALL_JOIN_OVERLAP * 2.0, parapet_h, 0.35), WALL_WHITE)
	_box("DeckParapetFront", Vector3(0.0, parapet_y, FRONT_Z), Vector3(_building_width() + WALL_JOIN_OVERLAP * 2.0, parapet_h, 0.35), WALL_WHITE)
	_box("DeckParapetLeft", Vector3(OUTER_LEFT, parapet_y, center_z), Vector3(0.35, parapet_h, full_d + WALL_JOIN_OVERLAP * 2.0), WALL_WHITE)
	_box("DeckParapetRight", Vector3(OUTER_RIGHT, parapet_y, center_z), Vector3(0.35, parapet_h, full_d + WALL_JOIN_OVERLAP * 2.0), WALL_WHITE)

	# Jalousie side windows (louver rhythm on outer walls).
	for floor_index in range(Level.ROOF):
		var y := _floor_y(floor_index) + 1.75
		for z in [-27.0, -34.0, -41.0, -48.0]:
			_jalousie_panel("SideJalousieL", Vector3(OUTER_LEFT + 0.22, y, z), Vector3(0.08, 1.7, 3.2))
			_jalousie_panel("SideJalousieR", Vector3(OUTER_RIGHT - 0.22, y, z), Vector3(0.08, 1.7, 3.2))


func _build_facade() -> void:
	var facade_z := FRONT_Z + 0.12
	var ground_h := level_height(Level.GROUND)

	# Street entrance on the LEFT of the facade — centre mass stays sealed.
	var entrance_x := ENTRANCE_CENTER_X
	var entrance_half_width := 4.1
	var left_lo := OUTER_LEFT
	var left_hi := entrance_x - entrance_half_width
	var right_lo := entrance_x + entrance_half_width
	var right_hi := OUTER_RIGHT
	var left_width := left_hi - left_lo + WALL_JOIN_OVERLAP
	var right_width := right_hi - right_lo + WALL_JOIN_OVERLAP
	_box("GroundFrontLeft", Vector3((left_lo + left_hi) * 0.5, BASE_Y + ground_h * 0.5, facade_z), Vector3(left_width, ground_h, 0.35), WALL_WHITE)
	_box("GroundFrontRight", Vector3((right_lo + right_hi) * 0.5, BASE_Y + ground_h * 0.5, facade_z), Vector3(right_width, ground_h, 0.35), WALL_WHITE)

	_box("EntranceTop", Vector3(entrance_x, BASE_Y + ground_h - 0.18, facade_z + 0.05), Vector3(8.2, 0.35, 0.6), WALL_WHITE)
	_box("EntranceTransom", Vector3(entrance_x, BASE_Y + (2.55 + ground_h - 0.35) * 0.5, facade_z + 0.05), Vector3(8.0, ground_h - 2.9, 0.22), GLASS_DARK)
	_box("EntrancePostL", Vector3(entrance_x - entrance_half_width, BASE_Y + ground_h * 0.5, facade_z + 0.05), Vector3(0.35, ground_h, 0.6), WALL_WHITE)
	_box("EntrancePostR", Vector3(entrance_x + entrance_half_width, BASE_Y + ground_h * 0.5, facade_z + 0.05), Vector3(0.35, ground_h, 0.6), WALL_WHITE)

	var entrance_leaf_width := 3.4
	var entrance_leaf_angle := deg_to_rad(76.0)
	var entrance_leaf_z := facade_z + 0.32 + sin(entrance_leaf_angle) * entrance_leaf_width * 0.5
	var entrance_leaf_x := entrance_half_width - 0.18 - cos(entrance_leaf_angle) * entrance_leaf_width * 0.5
	_rotated_box(
		"EntranceGateLeafL",
		Vector3(entrance_x - entrance_leaf_x, BASE_Y + 1.2, entrance_leaf_z),
		Vector3(entrance_leaf_width, 2.4, 0.12),
		Vector3(0.0, -entrance_leaf_angle, 0.0),
		GLASS_DARK
	)
	_rotated_box(
		"EntranceGateLeafR",
		Vector3(entrance_x + entrance_leaf_x, BASE_Y + 1.2, entrance_leaf_z),
		Vector3(entrance_leaf_width, 2.4, 0.12),
		Vector3(0.0, entrance_leaf_angle, 0.0),
		GLASS_DARK
	)
	_box("EntranceCanopy", Vector3(entrance_x, BASE_Y + level_height(Level.GROUND) - 0.6, facade_z + 1.7), Vector3(10.5, 0.2, 3.5), Color("676b68"), false)

	# Upper floors: white facade + blue slab bands
	for floor_index in range(1, Level.ROOF):
		var floor_base := _floor_y(floor_index)
		for bay in range(8):
			var x := -22.75 + float(bay) * 6.5
			_jalousie_panel(
				"FacadeJalousie_%02d_%02d" % [floor_index + 1, bay + 1],
				Vector3(x, floor_base + 1.7, facade_z),
				Vector3(5.5, 2.3, 0.22)
			)
			_collision_box(
				"FacadeWindowCollision_%02d_%02d" % [floor_index + 1, bay + 1],
				Vector3(x, floor_base + 1.7, facade_z),
				Vector3(5.5, 2.3, 0.18)
			)
		_box(
			"FacadeBlueBand_%02d" % (floor_index + 1),
			Vector3(0.0, floor_base + 0.22, facade_z + 0.2),
			Vector3(_building_width(), 0.42, 0.75),
			BLUE_BAND
		)
		_box(
			"FacadeBlueStrip_%02d" % (floor_index + 1),
			Vector3(0.0, floor_base + 0.48, facade_z + 0.28),
			Vector3(_building_width(), 0.1, 0.82),
			BLUE_BAND_DARK,
			false
		)


func _modern_front_z(x: float) -> float:
	var normalized := clampf(absf(x) / 26.0, 0.0, 1.0)
	return FRONT_Z + 0.85 + 2.7 * (1.0 - normalized * normalized)


func _build_modern_street_facade() -> void:
	var glass := Color("183746")
	var glass_alt := Color("214657")
	var frame := Color("bcc6ca")
	var band := Color("737f83")
	var yellow_banner := Color("e5c21f") # Photo reference yellow department banner
	var red_pharmacy := Color("b82635")  # Rose Pharmacy red
	var green_nprint := Color("1e613b")  # N-Print green
	var blue_accent := Color("1b4f80")   # UC blue accent column

	var segment_count := 12
	var segment_width := (OUTER_RIGHT - OUTER_LEFT) / float(segment_count)

	# Main facade curtain wall
	for segment in range(segment_count):
		var x0 := OUTER_LEFT + float(segment) * segment_width
		var x1 := x0 + segment_width
		var z0 := _modern_front_z(x0)
		var z1 := _modern_front_z(x1)
		var midpoint := Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
		var edge := Vector2(x1 - x0, z1 - z0)
		var panel_length := edge.length() + WALL_JOIN_OVERLAP
		var yaw := -atan2(edge.y, edge.x)

		# Clip ground-floor glass so the left-side entrance stays open; centre seals.
		var entrance_lo := ENTRANCE_CENTER_X - ENTRANCE_HALF_WIDTH
		var entrance_hi := ENTRANCE_CENTER_X + ENTRANCE_HALF_WIDTH
		var ground_x0 := x0
		var ground_x1 := x1
		if ground_x1 <= entrance_lo or ground_x0 >= entrance_hi:
			pass
		elif ground_x0 < entrance_lo and ground_x1 > entrance_hi:
			# Segment straddles the doorway — emit left remnant only here; right
			# remnant is handled when the loop reaches the far side of the gap.
			ground_x1 = entrance_lo
		elif ground_x0 < entrance_lo:
			ground_x1 = minf(ground_x1, entrance_lo)
		elif ground_x1 > entrance_hi:
			ground_x0 = maxf(ground_x0, entrance_hi)
		else:
			ground_x1 = ground_x0
		if ground_x1 - ground_x0 > 0.05:
			var ground_z0 := _modern_front_z(ground_x0)
			var ground_z1 := _modern_front_z(ground_x1)
			var ground_midpoint := Vector3((ground_x0 + ground_x1) * 0.5, 0.0, (ground_z0 + ground_z1) * 0.5)
			var ground_edge := Vector2(ground_x1 - ground_x0, ground_z1 - ground_z0)
			var ground_length := ground_edge.length() + WALL_JOIN_OVERLAP
			var ground_yaw := -atan2(ground_edge.y, ground_edge.x)
			_rotated_box(
				"ModernGroundGlass_%02d" % segment,
				Vector3(ground_midpoint.x, BASE_Y + 2.19, ground_midpoint.z),
				Vector3(ground_length, 3.9, 0.22),
				Vector3(0.0, ground_yaw, 0.0),
				glass.darkened(0.12),
				true
			)

		for floor_index in range(1, Level.ROOF):
			var floor_base := _floor_y(floor_index)
			_rotated_box(
				"ModernCurveGlass_F%02d_B%02d" % [floor_index + 1, segment + 1],
				Vector3(midpoint.x, floor_base + 1.7, midpoint.z),
				Vector3(panel_length, 2.45, 0.22),
				Vector3(0.0, yaw, 0.0),
				glass if (segment + floor_index) % 2 == 0 else glass_alt,
				true
			)
			_rotated_box(
				"ModernCurveBand_F%02d_B%02d" % [floor_index + 1, segment + 1],
				Vector3(midpoint.x, floor_base + 0.32, midpoint.z + 0.16),
				Vector3(panel_length + 0.04, 0.34, 0.72),
				Vector3(0.0, yaw, 0.0),
				band,
				false
			)
			_rotated_box(
				"ModernSunshade_F%02d_B%02d" % [floor_index + 1, segment + 1],
				Vector3(midpoint.x, floor_base + 3.02, midpoint.z + 0.28),
				Vector3(panel_length + 0.08, 0.16, 0.92),
				Vector3(0.0, yaw, 0.0),
				frame,
				false
			)

		# Joined vertical mullions
		_box(
			"ModernFacadeMullion_%02d" % segment,
			Vector3(x0, BASE_Y + building_height() * 0.5, z0 + 0.08),
			Vector3(0.26, building_height(), 0.42),
			frame,
			false
		)
		_rotated_box(
			"ModernRoofCrown_%02d" % segment,
			Vector3(midpoint.x, level_y(Level.ROOF) + 0.55, midpoint.z - 0.10),
			Vector3(panel_length + WALL_JOIN_OVERLAP, 0.75, 1.3),
			Vector3(0.0, yaw, 0.0),
			frame,
			false
		)

	# --- Left Vertical Blue Column (Matches Photo Left Accent) ---
	_box(
		"LeftBlueColumn",
		Vector3(-20.5, BASE_Y + building_height() * 0.5, _modern_front_z(-20.5) + 0.15),
		Vector3(3.2, building_height() + 0.6, 0.35),
		blue_accent,
		false
	)

	# --- Ground Floor Storefronts (Left to Right per Photo) ---
	# Street entrance on the LEFT (locker / gate side) — not building centre.
	var entrance_x := ENTRANCE_CENTER_X
	var ent_half := ENTRANCE_HALF_WIDTH
	var ent_z := _modern_front_z(entrance_x)
	_box("ModernEntranceFrameL", Vector3(entrance_x - ent_half, BASE_Y + 2.1, _modern_front_z(entrance_x - ent_half) + 0.05), Vector3(0.48, 4.2, 0.65), frame, true)
	_box("ModernEntranceFrameR", Vector3(entrance_x + ent_half, BASE_Y + 2.1, _modern_front_z(entrance_x + ent_half) + 0.05), Vector3(0.48, 4.2, 0.65), frame, true)
	_box("ModernEntranceHeader", Vector3(entrance_x, BASE_Y + 4.05, ent_z + 0.05), Vector3(9.4, 0.48, 0.70), frame, true)
	_box("ModernEntranceCanopy", Vector3(entrance_x, BASE_Y + 4.45, ent_z + 1.05), Vector3(10.5, 0.24, 2.7), band, false)

	# Rose Pharmacy stays just west of the doorway.
	var pharmacy_sign := _box("PharmacySign", Vector3(-20.0, BASE_Y + 4.35, _modern_front_z(-20.0) + 0.20), Vector3(6.5, 0.9, 0.28), red_pharmacy, false)
	_add_label(pharmacy_sign, "Rose Pharmacy", Vector3(0.0, 0.0, 0.16), 0.009, Color("ffffff"))

	# N-PRINT sits between doorway and building centre.
	var nprint_sign := _box("NprintSign", Vector3(-5.5, BASE_Y + 4.35, _modern_front_z(-5.5) + 0.20), Vector3(6.5, 0.9, 0.28), green_nprint, false)
	_add_label(nprint_sign, "N-PRINT", Vector3(0.0, 0.0, 0.16), 0.010, Color("ffffff"))

	# 4. 7-ELEVEN (White Fascia with 7-Eleven stripes)
	var seven_sign := _box("SevenElevenSign", Vector3(3.0, BASE_Y + 4.35, _modern_front_z(3.0) + 0.20), Vector3(8.0, 0.9, 0.28), Color("f5f5f0"), false)
	_box("SevenStripeGreen", Vector3(3.0, BASE_Y + 4.65, _modern_front_z(3.0) + 0.35), Vector3(7.8, 0.18, 0.04), Color("1e613b"), false)
	_box("SevenStripeOrange", Vector3(3.0, BASE_Y + 4.45, _modern_front_z(3.0) + 0.35), Vector3(7.8, 0.18, 0.04), Color("e06422"), false)
	_box("SevenStripeRed", Vector3(3.0, BASE_Y + 4.25, _modern_front_z(3.0) + 0.35), Vector3(7.8, 0.18, 0.04), Color("b82635"), false)
	_add_label(seven_sign, "7-ELEVEN", Vector3(0.0, -0.05, 0.16), 0.0095, Color("b82635"))

	# 5. TT BOKI / Copy Trade
	var ttboki_sign := _box("TTBokiSign", Vector3(14.0, BASE_Y + 4.35, _modern_front_z(14.0) + 0.20), Vector3(10.0, 0.9, 0.28), Color("2d3d42"), false)
	_add_label(ttboki_sign, "TT BOKI", Vector3(0.0, 0.0, 0.16), 0.009, Color("f2e2be"))

	# --- Yellow Academic Department Banners (Floors 2 & 3 per Photo) ---
	# Floor 3 Banner (Upper Yellow Strip)
	var f3_base := _floor_y(2)
	var f3_banner := _box("F3YellowBanner", Vector3(3.0, f3_base + 0.35, _modern_front_z(3.0) + 0.35), Vector3(38.0, 0.55, 0.24), yellow_banner, false)
	_add_label(f3_banner, "ELEMENTARY ED  •  SECONDARY ED  •  BUSINESS ADMIN  •  COMP ENG  •  COMP SCI  •  CRIMINOLOGY  •  HEALTH CARE", Vector3(0.0, 0.0, 0.14), 0.0048, Color("111111"))

	# Floor 2 Banner (Lower Yellow Strip)
	var f2_base := _floor_y(1)
	var f2_banner := _box("F2YellowBanner", Vector3(3.0, f2_base + 0.35, _modern_front_z(3.0) + 0.35), Vector3(38.0, 0.55, 0.24), yellow_banner, false)
	_add_label(f2_banner, "HOSPITALITY MGMT  •  IND ENG  •  JURIS DOCTOR  •  MGMT ACCOUNTING  •  MED TECH  •  NURSING  •  PSYCHOLOGY  •  TOURISM MGMT", Vector3(0.0, 0.0, 0.14), 0.0045, Color("111111"))

	# --- Top-Left Roof Crown UC Logo (Matches Photo) ---
	var uc_sign := _box("ModernUCSign", Vector3(-20.5, level_y(Level.ROOF) + 0.2, _modern_front_z(-20.5) + 0.35), Vector3(5.5, 1.8, 0.24), Color("ffffff"), false)
	_add_label(uc_sign, "UC", Vector3(-1.0, 0.25, 0.16), 0.024, blue_accent)
	_add_label(uc_sign, "University of Cebu", Vector3(0.2, -0.4, 0.16), 0.0055, blue_accent)

	# Closed end returns: solid masses where the curved street skin meets the
	# side walls, so players can't slip out through open facade corners.
	var tower_h := building_height() + 0.8
	var tower_y := BASE_Y + tower_h * 0.5
	var tower_depth := 3.4
	_box(
		"ModernEndTowerL",
		Vector3(OUTER_LEFT + 0.9, tower_y, _modern_front_z(OUTER_LEFT) - tower_depth * 0.35),
		Vector3(2.2, tower_h, tower_depth),
		frame,
		true
	)
	_box(
		"ModernEndTowerR",
		Vector3(OUTER_RIGHT - 0.9, tower_y, _modern_front_z(OUTER_RIGHT) - tower_depth * 0.35),
		Vector3(2.2, tower_h, tower_depth),
		frame,
		true
	)


func _build_courtyard_parapets() -> void:
	## Metal pipe railings and protruding slab overhangs with teal fascia bands (matches reference photo).
	var court_w := COURT_RIGHT - COURT_LEFT
	var court_d := absf(COURT_BACK - COURT_FRONT)

	for floor_index in range(1, LEVEL_COUNT):
		var y := _floor_y(floor_index)
		
		# 1. Protruding Slab Overhang & Teal Fascia Band (underneath each floor edge facing courtyard)
		var band_h := 0.38
		var band_y := y - 0.19

		# South overhang fascia
		_box("FasciaSouth_%02d" % (floor_index + 1), Vector3(0.0, band_y, COURT_FRONT - 0.075), Vector3(court_w, band_h, 0.15), BLUE_BAND, false)
		_box("FasciaSouthCap_%02d" % (floor_index + 1), Vector3(0.0, y - 0.02, COURT_FRONT - 0.1), Vector3(court_w, 0.06, 0.2), WALL_WHITE, false)
		
		# North overhang fascia
		_box("FasciaNorth_%02d" % (floor_index + 1), Vector3(0.0, band_y, COURT_BACK + 0.075), Vector3(court_w, band_h, 0.15), BLUE_BAND, false)
		_box("FasciaNorthCap_%02d" % (floor_index + 1), Vector3(0.0, y - 0.02, COURT_BACK + 0.1), Vector3(court_w, 0.06, 0.2), WALL_WHITE, false)
		
		# West overhang fascia
		_box("FasciaWest_%02d" % (floor_index + 1), Vector3(COURT_LEFT + 0.075, band_y, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.15, band_h, court_d), BLUE_BAND, false)
		_box("FasciaWestCap_%02d" % (floor_index + 1), Vector3(COURT_LEFT + 0.1, y - 0.02, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.2, 0.06, court_d), WALL_WHITE, false)
		
		# East overhang fascia
		_box("FasciaEast_%02d" % (floor_index + 1), Vector3(COURT_RIGHT - 0.075, band_y, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.15, band_h, court_d), BLUE_BAND, false)
		_box("FasciaEastCap_%02d" % (floor_index + 1), Vector3(COURT_RIGHT - 0.1, y - 0.02, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.2, 0.06, court_d), WALL_WHITE, false)

		# 2. Metal Pipe Railings along open corridors
		var rail_color := Color("2c3032")
		var rail_h := 1.05
		var post_spacing := 3.0

		# South/North rails leave aligned openings where the 2F bridge lands.
		var bridge_open_half := 1.35
		if floor_index == Level.F2:
			var side_rail_width := COURT_RIGHT - bridge_open_half
			var side_rail_center := (COURT_RIGHT + bridge_open_half) * 0.5
			for side in [-1.0, 1.0]:
				_box("RailSouthTop_%02d_%s" % [floor_index + 1, str(side)], Vector3(side * side_rail_center, y + rail_h, COURT_FRONT + 0.1), Vector3(side_rail_width, 0.06, 0.06), rail_color)
				_box("RailSouthMid_%02d_%s" % [floor_index + 1, str(side)], Vector3(side * side_rail_center, y + rail_h * 0.5, COURT_FRONT + 0.1), Vector3(side_rail_width, 0.04, 0.04), rail_color, false)
				_box("RailNorthTop_%02d_%s" % [floor_index + 1, str(side)], Vector3(side * side_rail_center, y + rail_h, COURT_BACK - 0.1), Vector3(side_rail_width, 0.06, 0.06), rail_color)
				_box("RailNorthMid_%02d_%s" % [floor_index + 1, str(side)], Vector3(side * side_rail_center, y + rail_h * 0.5, COURT_BACK - 0.1), Vector3(side_rail_width, 0.04, 0.04), rail_color, false)
			for jamb_x in [-bridge_open_half, bridge_open_half]:
				_box("RailSouthBridgeJamb_%02d" % int((jamb_x + bridge_open_half) / (bridge_open_half * 2.0)), Vector3(jamb_x, y + rail_h * 0.5, COURT_FRONT + 0.1), Vector3(0.06, rail_h, 0.06), rail_color)
				_box("RailNorthBridgeJamb_%02d" % int((jamb_x + bridge_open_half) / (bridge_open_half * 2.0)), Vector3(jamb_x, y + rail_h * 0.5, COURT_BACK - 0.1), Vector3(0.06, rail_h, 0.06), rail_color)
		else:
			_box("RailSouthTop_%02d" % (floor_index + 1), Vector3(0.0, y + rail_h, COURT_FRONT + 0.1), Vector3(court_w, 0.06, 0.06), rail_color)
			_box("RailSouthMid_%02d" % (floor_index + 1), Vector3(0.0, y + rail_h * 0.5, COURT_FRONT + 0.1), Vector3(court_w, 0.04, 0.04), rail_color, false)
			_box("RailNorthTop_%02d" % (floor_index + 1), Vector3(0.0, y + rail_h, COURT_BACK - 0.1), Vector3(court_w, 0.06, 0.06), rail_color)
			_box("RailNorthMid_%02d" % (floor_index + 1), Vector3(0.0, y + rail_h * 0.5, COURT_BACK - 0.1), Vector3(court_w, 0.04, 0.04), rail_color, false)

		var x_post_count := ceili(court_w / post_spacing)
		for post_i in range(x_post_count + 1):
			var px := lerpf(COURT_LEFT, COURT_RIGHT, float(post_i) / float(x_post_count))
			if floor_index == Level.F2 and absf(px) < bridge_open_half + 0.1:
				continue
			_box("RailSouthPost_%02d_%d" % [floor_index + 1, post_i], Vector3(px, y + rail_h * 0.5, COURT_FRONT + 0.1), Vector3(0.06, rail_h, 0.06), rail_color, false)
			_box("RailNorthPost_%02d_%d" % [floor_index + 1, post_i], Vector3(px, y + rail_h * 0.5, COURT_BACK - 0.1), Vector3(0.06, rail_h, 0.06), rail_color, false)

		# West/east railings use the same post rhythm and terminate at the pillars.
		_box("RailWestTop_%02d" % (floor_index + 1), Vector3(COURT_LEFT - 0.1, y + rail_h, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.06, 0.06, court_d), rail_color)
		_box("RailWestMid_%02d" % (floor_index + 1), Vector3(COURT_LEFT - 0.1, y + rail_h * 0.5, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.04, 0.04, court_d), rail_color, false)
		_box("RailEastTop_%02d" % (floor_index + 1), Vector3(COURT_RIGHT + 0.1, y + rail_h, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.06, 0.06, court_d), rail_color)
		_box("RailEastMid_%02d" % (floor_index + 1), Vector3(COURT_RIGHT + 0.1, y + rail_h * 0.5, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.04, 0.04, court_d), rail_color, false)
		var z_post_count := ceili(court_d / post_spacing)
		for post_i in range(z_post_count + 1):
			var pz := lerpf(COURT_FRONT, COURT_BACK, float(post_i) / float(z_post_count))
			_box("RailWestPost_%02d_%d" % [floor_index + 1, post_i], Vector3(COURT_LEFT - 0.1, y + rail_h * 0.5, pz), Vector3(0.06, rail_h, 0.06), rail_color, false)
			_box("RailEastPost_%02d_%d" % [floor_index + 1, post_i], Vector3(COURT_RIGHT + 0.1, y + rail_h * 0.5, pz), Vector3(0.06, rail_h, 0.06), rail_color, false)

	# Finish the roof-ring cutout with the same attached fascia and cap. The roof
	# is not player-accessible, so no additional railing is needed above it.
	var roof_y := level_y(Level.ROOF)
	var roof_band_y := roof_y - 0.19
	_box("RoofFasciaSouth", Vector3(0.0, roof_band_y, COURT_FRONT - 0.075), Vector3(court_w, 0.38, 0.15), BLUE_BAND, false)
	_box("RoofFasciaSouthCap", Vector3(0.0, roof_y - 0.02, COURT_FRONT - 0.1), Vector3(court_w, 0.06, 0.2), WALL_WHITE, false)
	_box("RoofFasciaNorth", Vector3(0.0, roof_band_y, COURT_BACK + 0.075), Vector3(court_w, 0.38, 0.15), BLUE_BAND, false)
	_box("RoofFasciaNorthCap", Vector3(0.0, roof_y - 0.02, COURT_BACK + 0.1), Vector3(court_w, 0.06, 0.2), WALL_WHITE, false)
	_box("RoofFasciaWest", Vector3(COURT_LEFT + 0.075, roof_band_y, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.15, 0.38, court_d), BLUE_BAND, false)
	_box("RoofFasciaWestCap", Vector3(COURT_LEFT + 0.1, roof_y - 0.02, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.2, 0.06, court_d), WALL_WHITE, false)
	_box("RoofFasciaEast", Vector3(COURT_RIGHT - 0.075, roof_band_y, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.15, 0.38, court_d), BLUE_BAND, false)
	_box("RoofFasciaEastCap", Vector3(COURT_RIGHT - 0.1, roof_y - 0.02, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(0.2, 0.06, court_d), WALL_WHITE, false)


func _build_courtyard_fence() -> void:
	## Ground-level metal fence, inset into the court so the corridor stays clear.
	var fence_color := Color("25282a")
	var fence_h := 1.35
	var inset := 0.45
	var south_z := COURT_FRONT - inset
	var north_z := COURT_BACK + inset
	var west_x := COURT_LEFT + inset
	var east_x := COURT_RIGHT - inset
	var gate_half := 1.8
	var gate_x := clampf(ENTRANCE_CENTER_X, west_x + gate_half + 0.5, east_x - gate_half - 0.5)

	_build_metal_fence_x("FenceSouthL", west_x, gate_x - gate_half, south_z, BASE_Y, fence_h, fence_color)
	_build_metal_fence_x("FenceSouthR", gate_x + gate_half, east_x, south_z, BASE_Y, fence_h, fence_color)
	_build_metal_fence_x("FenceNorth", west_x, east_x, north_z, BASE_Y, fence_h, fence_color)
	_build_metal_fence_z("FenceWest", north_z, south_z, west_x, BASE_Y, fence_h, fence_color)
	_build_metal_fence_z("FenceEast", north_z, south_z, east_x, BASE_Y, fence_h, fence_color)

	for side: float in [-1.0, 1.0]:
		_box("CourtGateJamb", Vector3(gate_x + side * gate_half, BASE_Y + fence_h * 0.5, south_z), Vector3(0.13, fence_h, 0.13), fence_color)

	# Both leaves swing inward, leaving a deliberate 3.6 m passage.
	var leaf_width := 1.55
	var leaf_angle := deg_to_rad(72.0)
	var leaf_z := south_z - sin(leaf_angle) * leaf_width * 0.5
	var leaf_x_offset := cos(leaf_angle) * leaf_width * 0.5
	_rotated_box(
		"CourtGateLeafL",
		Vector3(gate_x - gate_half + leaf_x_offset, BASE_Y + fence_h * 0.5, leaf_z),
		Vector3(leaf_width, fence_h - 0.12, 0.07),
		Vector3(0.0, leaf_angle, 0.0),
		fence_color
	)
	_rotated_box(
		"CourtGateLeafR",
		Vector3(gate_x + gate_half - leaf_x_offset, BASE_Y + fence_h * 0.5, leaf_z),
		Vector3(leaf_width, fence_h - 0.12, 0.07),
		Vector3(0.0, -leaf_angle, 0.0),
		fence_color
	)


func _build_chamfered_corners() -> void:
	## Continuous junction posts close the four courtyard fascia/rail corners.
	var building_h := building_height()
	var center_y := BASE_Y + building_h * 0.5
	var pillar_color := WALL_WHITE
	var pillar_size := Vector3(0.42, building_h, 0.42)

	_box("PillarNW", Vector3(COURT_LEFT, center_y, COURT_BACK), pillar_size, pillar_color)
	_box("PillarNE", Vector3(COURT_RIGHT, center_y, COURT_BACK), pillar_size, pillar_color)
	_box("PillarSW", Vector3(COURT_LEFT, center_y, COURT_FRONT), pillar_size, pillar_color)
	_box("PillarSE", Vector3(COURT_RIGHT, center_y, COURT_FRONT), pillar_size, pillar_color)


func _build_courtyard_bridge() -> void:
	## Metal pedestrian bridge spanning the courtyard, flush with 2F corridor slabs.
	var slab_y := _floor_y(Level.F2) - 0.13  # Match floor slab center height exactly
	var bridge_depth := absf(COURT_BACK - COURT_FRONT) + 1.0  # Overlap corridor slabs by 0.5 on each side
	_box(
		"CourtBridgeDeck",
		Vector3(0.0, slab_y, (COURT_FRONT + COURT_BACK) * 0.5),
		Vector3(2.2, 0.26, bridge_depth),
		Color("6a6e6c")
	)
	var rail_y := _floor_y(Level.F2)
	_build_metal_fence_z("CourtBridgeRailL", COURT_FRONT, COURT_BACK, -1.05, rail_y, 1.0, Color("4a5050"), true)
	_build_metal_fence_z("CourtBridgeRailR", COURT_FRONT, COURT_BACK, 1.05, rail_y, 1.0, Color("4a5050"), true)


func _wing_axis_range(wing: String) -> Vector2:
	## Extent of the wall that faces the ring corridor, in the wing's own axis.
	if wing == "east" or wing == "west":
		return Vector2(SIDE_BAY_BACK_Z, SIDE_BAY_FRONT_Z)
	return Vector2(OUTER_LEFT + 0.35, OUTER_RIGHT - 0.35)


func _wing_bays(level: int, wing: String) -> Array:
	## Resolve a level spec into concrete bays: {name, type, lo, hi}.
	var spec: Dictionary = LEVEL_SPECS[level]
	var entries: Array = spec.get(wing, [])
	var bays: Array = []
	if entries.is_empty():
		return bays
	if wing == "front":
		var slots: Array = spec.get("slots", FRONT_BAY_SLOTS)
		for i in range(mini(entries.size(), slots.size())):
			var entry: Dictionary = entries[i]
			bays.append({
				"name": entry["name"],
				"type": entry["type"],
				"lo": float(slots[i][0]),
				"hi": float(slots[i][1]),
			})
		return bays
	# Side and back wings divide their span evenly, so a floor's room count
	# alone decides the bay rhythm.
	var span := _wing_axis_range(wing)
	var step := (span.y - span.x) / float(entries.size())
	for i in range(entries.size()):
		var entry_even: Dictionary = entries[i]
		bays.append({
			"name": entry_even["name"],
			"type": entry_even["type"],
			"lo": span.x + step * float(i),
			"hi": span.x + step * float(i + 1),
		})
	return bays


func _wing_wall_position(wing: String) -> float:
	match wing:
		"front": return SOUTH_ROOM_WALL_Z
		"back": return NORTH_ROOM_WALL_Z
		"east": return EAST_ROOM_WALL_X
		_: return WEST_ROOM_WALL_X


func _wing_room_back(wing: String) -> float:
	match wing:
		"front": return FRONT_ROOM_BACK_Z
		"back": return BACK_ROOM_BACK_Z
		"east": return EAST_ROOM_BACK_X
		_: return WEST_ROOM_BACK_X


func _wing_interior_sign(wing: String) -> float:
	## Direction from the corridor wall towards the inside of the rooms.
	return 1.0 if (wing == "front" or wing == "east") else -1.0


func _wing_is_side(wing: String) -> bool:
	return wing == "east" or wing == "west"


func _bay_room_center(wing: String, bay: Dictionary, floor_base: float) -> Vector3:
	var along := (float(bay["lo"]) + float(bay["hi"])) * 0.5
	var across := (_wing_wall_position(wing) + _wing_room_back(wing)) * 0.5
	if _wing_is_side(wing):
		return Vector3(across, floor_base, along)
	return Vector3(along, floor_base, across)


func _build_floor_layout(level: int) -> void:
	_build_corridor_decks(level)
	for wing in ["front", "back", "east", "west"]:
		_build_wing_walls(level, wing)
	_build_elevator_bank(level)
	_build_stair_enclosure(level)
	if level == Level.MEZZANINE:
		_build_mezzanine_void_edge(level)
	if level == Level.ROOF:
		_build_roof_deck_features(level)


func _build_wing_walls(level: int, wing: String) -> void:
	var bays := _wing_bays(level, wing)
	var floor_base := _floor_y(level)
	var wall_h := _room_wall_height(level)
	var wall_cy := floor_base + wall_h * 0.5
	var wall_pos := _wing_wall_position(wing)
	var room_back := _wing_room_back(wing)
	var interior := _wing_interior_sign(wing)
	var is_side := _wing_is_side(wing)
	var span := _wing_axis_range(wing)
	var divider_depth := absf(room_back - wall_pos) + WALL_JOIN_OVERLAP * 2.0
	var divider_across := (wall_pos + room_back) * 0.5
	var prefix := "%sWall_L%02d" % [wing.capitalize(), level + 1]

	# Occupied stretches: real bays plus, on the front wing, the elevator core.
	var occupied: Array = []
	for bay in bays:
		occupied.append(Vector2(float(bay["lo"]), float(bay["hi"])))
	if wing == "front":
		occupied.append(Vector2(ELEVATOR_BANK_LEFT_X, ELEVATOR_BANK_RIGHT_X))
	occupied.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	# Rooms only exist where a bay was declared, so every other stretch of the
	# wing is closed with solid wall rather than a door into nothing.
	if not bays.is_empty():
		var cursor := span.x
		for interval in occupied:
			var gap_lo: float = cursor
			var gap_hi: float = (interval as Vector2).x
			if gap_hi - gap_lo > 0.12:
				_wing_wall_segment(prefix + "Fill", wing, gap_lo, gap_hi, wall_pos, wall_cy, wall_h)
			cursor = maxf(cursor, (interval as Vector2).y)
		if span.y - cursor > 0.12:
			_wing_wall_segment(prefix + "FillEnd", wing, cursor, span.y, wall_pos, wall_cy, wall_h)

	var boundaries: Array = []
	for bay_index in range(bays.size()):
		var bay: Dictionary = bays[bay_index]
		var bay_type: String = bay["type"]
		var lo := float(bay["lo"])
		var hi := float(bay["hi"])
		if bay_type != "void":
			boundaries.append(lo)
			boundaries.append(hi)
		var bay_prefix := "%s_L%02d_B%02d" % [wing.capitalize(), level + 1, bay_index + 1]
		match bay_type:
			"void":
				pass
			"lobby":
				# Lobby opening tracks the left-side street doorway — centre stays walled.
				var open_lo := maxf(lo + 0.35, ENTRANCE_CENTER_X - ENTRANCE_HALF_WIDTH + 0.5)
				var open_hi := minf(hi - 0.35, ENTRANCE_CENTER_X + ENTRANCE_HALF_WIDTH - 0.5)
				if open_hi > open_lo + 1.0:
					_wing_wall_opening(
						bay_prefix, wing, lo, hi, open_lo, open_hi,
						wall_pos, wall_cy, wall_h
					)
				else:
					_wing_wall_opening(
						bay_prefix, wing, lo, hi, lo + 1.6, hi - 1.6,
						wall_pos, wall_cy, wall_h
					)
			_:
				_wing_wall_door(
					bay_prefix, wing, lo, hi, (lo + hi) * 0.5,
					wall_pos, wall_cy, wall_h, interior, level != Level.GROUND
				)

	# Perpendicular returns close every room corner.
	for boundary in boundaries:
		var boundary_value: float = boundary
		var divider_name := "%sDivider_L%02d_%d" % [wing.capitalize(), level + 1, int(roundf(boundary_value * 10.0))]
		if is_side:
			_box(
				divider_name,
				Vector3(divider_across, wall_cy, boundary_value),
				Vector3(divider_depth, wall_h, 0.18),
				WALL_INNER
			)
		else:
			_box(
				divider_name,
				Vector3(boundary_value, wall_cy, divider_across),
				Vector3(0.18, wall_h, divider_depth),
				WALL_INNER
			)


func _wing_wall_segment(
	prefix: String, wing: String, lo: float, hi: float,
	wall_pos: float, wall_cy: float, wall_h: float
) -> void:
	var length := hi - lo
	if length <= 0.05:
		return
	var center := (lo + hi) * 0.5
	var unique := "%s_%d" % [prefix, int(roundf(center * 10.0))]
	if _wing_is_side(wing):
		_box(unique, Vector3(wall_pos, wall_cy, center), Vector3(0.18, wall_h, length), WALL_INNER)
	else:
		_box(unique, Vector3(center, wall_cy, wall_pos), Vector3(length, wall_h, 0.18), WALL_INNER)


func _wing_wall_door(
	prefix: String, wing: String, lo: float, hi: float, door_center: float,
	wall_pos: float, wall_cy: float, wall_h: float,
	interior_sign: float, spawn_leaf: bool
) -> void:
	if _wing_is_side(wing):
		_wall_with_door_z(prefix, lo, hi, door_center, wall_pos, wall_cy, wall_h, WALL_INNER, interior_sign, spawn_leaf)
	else:
		_wall_with_door(prefix, lo, hi, door_center, wall_pos, wall_cy, wall_h, WALL_INNER, interior_sign, spawn_leaf)


func _wing_wall_opening(
	prefix: String, wing: String, lo: float, hi: float,
	open_lo: float, open_hi: float, wall_pos: float, wall_cy: float, wall_h: float
) -> void:
	if _wing_is_side(wing):
		_wall_with_opening_z(prefix, lo, hi, open_lo, open_hi, wall_pos, wall_cy, wall_h, WALL_INNER)
	else:
		_wall_with_opening(prefix, lo, hi, open_lo, open_hi, wall_pos, wall_cy, wall_h, WALL_INNER)


func _build_corridor_decks(level: int) -> void:
	## Thin visual walking surfaces on the open-air ring. Collision comes from
	## the structural slab underneath.
	var floor_base := _floor_y(level)
	var tint := LOBBY_TILE if level == Level.GROUND else OPEN_CORRIDOR
	_box(
		"CorridorSouth_L%02d" % (level + 1),
		Vector3(0.0, floor_base + 0.015, (SOUTH_ROOM_WALL_Z + COURT_FRONT) * 0.5),
		Vector3(_building_width(), 0.03, absf(COURT_FRONT - SOUTH_ROOM_WALL_Z)),
		tint,
		false
	)
	_box(
		"CorridorNorth_L%02d" % (level + 1),
		Vector3(0.0, floor_base + 0.015, (COURT_BACK + NORTH_ROOM_WALL_Z) * 0.5),
		Vector3(_building_width(), 0.03, absf(NORTH_ROOM_WALL_Z - COURT_BACK)),
		tint,
		false
	)
	_box(
		"CorridorEast_L%02d" % (level + 1),
		Vector3((COURT_RIGHT + EAST_ROOM_WALL_X) * 0.5, floor_base + 0.015, (COURT_FRONT + COURT_BACK) * 0.5),
		Vector3(EAST_ROOM_WALL_X - COURT_RIGHT, 0.03, absf(COURT_BACK - COURT_FRONT)),
		tint,
		false
	)
	_box(
		"CorridorWest_L%02d" % (level + 1),
		Vector3((COURT_LEFT + WEST_ROOM_WALL_X) * 0.5, floor_base + 0.015, (COURT_FRONT + COURT_BACK) * 0.5),
		Vector3(COURT_LEFT - WEST_ROOM_WALL_X, 0.03, absf(COURT_BACK - COURT_FRONT)),
		tint,
		false
	)


func _build_stair_enclosure(level: int) -> void:
	## West stair enclosure wall, split around a landing-height doorway. The
	## landing touches the west corridor slab at x = STAIR_HOLE_RIGHT_X.
	var floor_base := _floor_y(level)
	var wall_h := _room_wall_height(level)
	var wall_cy := floor_base + wall_h * 0.5
	var stair_door_front_z := STAIR_ENTRY_Z + STAIR_ENTRY_DEPTH * 0.5 + 0.1
	var stair_wall_depth := absf(stair_door_front_z - STAIR_HOLE_FRONT_Z)
	_box(
		"BackStairWall_L%02d" % (level + 1),
		Vector3(STAIR_HOLE_RIGHT_X + 0.1, wall_cy, (STAIR_HOLE_FRONT_Z + stair_door_front_z) * 0.5),
		Vector3(0.18, wall_h, stair_wall_depth),
		Color("87877e")
	)
	_box(
		"BackStairDoorHeader_L%02d" % (level + 1),
		Vector3(
			STAIR_HOLE_RIGHT_X + 0.1,
			floor_base + STAIR_DOOR_HEIGHT + (wall_h - STAIR_DOOR_HEIGHT) * 0.5,
			STAIR_ENTRY_Z
		),
		Vector3(0.18, maxf(wall_h - STAIR_DOOR_HEIGHT, 0.1), STAIR_ENTRY_DEPTH + 0.2),
		Color("87877e")
	)


func _build_mezzanine_void_edge(level: int) -> void:
	## Stainless guardrail around the opening that overlooks the ground lobby.
	var y := _floor_y(level)
	_build_metal_fence_x("MezzVoidRailBack", MEZZ_VOID_LEFT_X, MEZZ_VOID_RIGHT_X, MEZZ_VOID_BACK_Z + 0.12, y, 1.1, STAINLESS)
	_build_metal_fence_z("MezzVoidRailLeft", MEZZ_VOID_BACK_Z, FRONT_Z, MEZZ_VOID_LEFT_X - 0.12, y, 1.1, STAINLESS, true)
	_build_metal_fence_z("MezzVoidRailRight", MEZZ_VOID_BACK_Z, FRONT_Z, MEZZ_VOID_RIGHT_X + 0.12, y, 1.1, STAINLESS, true)
	_add_world_label(
		"MezzVoidSign",
		"MEZZANINE",
		Vector3((MEZZ_VOID_LEFT_X + MEZZ_VOID_RIGHT_X) * 0.5, y + 1.35, MEZZ_VOID_BACK_Z + 0.2),
		0.006,
		Color("d7d2b8")
	)


func _build_roof_deck_features(level: int) -> void:
	## Open deck: water tanks, vent stacks and the machine-room housing.
	var y := _floor_y(level)
	_box("DeckSurfaceSouth", Vector3(0.0, y + 0.015, (FRONT_Z + COURT_FRONT) * 0.5), Vector3(_building_width(), 0.03, absf(COURT_FRONT - FRONT_Z)), Color("6b6a63"), false)
	_box("DeckSurfaceEast", Vector3((COURT_RIGHT + OUTER_RIGHT) * 0.5, y + 0.015, (COURT_FRONT + COURT_BACK) * 0.5), Vector3(OUTER_RIGHT - COURT_RIGHT, 0.03, absf(COURT_BACK - COURT_FRONT)), Color("6b6a63"), false)
	for tank_x in [-20.0, -15.0]:
		_box("DeckWaterTank_%d" % int(tank_x), Vector3(tank_x, y + 1.1, -27.0), Vector3(2.2, 2.2, 2.2), Color("9fa9ab"))
		_box("DeckTankStand_%d" % int(tank_x), Vector3(tank_x, y + 0.1, -27.0), Vector3(2.4, 0.2, 2.4), CONCRETE, false)
	for vent_x in [8.0, 14.0, 20.0]:
		_box("DeckVent_%d" % int(vent_x), Vector3(vent_x, y + 0.55, -28.5), Vector3(0.9, 1.1, 0.9), Color("7c8385"), false)
	_box("DeckAntenna", Vector3(22.0, y + 3.0, -26.0), Vector3(0.12, 6.0, 0.12), Color("9a9a94"), false)
	_add_world_label(
		"DeckSign",
		"ROOF DECK",
		Vector3(0.0, y + 2.2, COURT_FRONT - 0.2),
		0.008,
		Color("d7d2b8"),
		PI
	)


func _build_entrance_ramp() -> void:
	## Approach canopy framing the left-side lobby passageway (not building centre).
	var entrance_x := ENTRANCE_CENTER_X
	var z_front := -17.2
	var z_back := -22.6
	var center_z := (z_front + z_back) * 0.5
	var depth := absf(z_back - z_front)
	var width := 8.6
	var canopy_h := 3.6

	# Paved entrance slab & dark welcome mat
	_box("EntranceDeck", Vector3(entrance_x, BASE_Y + 0.02, center_z), Vector3(width, 0.05, depth), Color("4c4e4c"), false)
	_box("EntranceMat", Vector3(entrance_x, BASE_Y + 0.05, center_z), Vector3(5.2, 0.02, 3.2), Color("1a1b1c"), false)

	# Low stainless kerbs and safety railings along sides
	for side: float in [-1.0, 1.0]:
		var kerb_x: float = entrance_x + side * (width * 0.5 - 0.15)
		_box(
			"EntranceKerb%s" % ("L" if side < 0.0 else "R"),
			Vector3(kerb_x, BASE_Y + 0.12, center_z),
			Vector3(0.25, 0.20, depth),
			CONCRETE,
			false
		)
		_build_metal_fence_z(
			"EntranceRail%s" % ("L" if side < 0.0 else "R"),
			z_back, z_front,
			kerb_x,
			BASE_Y + 0.22, 0.95, STAINLESS, true
		)

	# 4 Modern architectural support columns
	for side_x: float in [-1.0, 1.0]:
		for pos_z: float in [z_back + 0.6, z_front - 0.6]:
			var col_x: float = entrance_x + side_x * (width * 0.5 - 0.22)
			_box(
				"CanopyColBase_%d_%d" % [int(pos_z), int(side_x)],
				Vector3(col_x, BASE_Y + 0.25, pos_z),
				Vector3(0.42, 0.50, 0.42),
				STAINLESS,
				false
			)
			_box(
				"CanopyCol_%d_%d" % [int(pos_z), int(side_x)],
				Vector3(col_x, BASE_Y + canopy_h * 0.5, pos_z),
				Vector3(0.28, canopy_h, 0.28),
				CYAN_TRIM,
				false
			)

	# Sleek modern canopy roof slab & fascia trim
	_box(
		"CanopyRoofSlab",
		Vector3(entrance_x, BASE_Y + canopy_h, center_z),
		Vector3(width + 0.8, 0.24, depth + 0.6),
		Color("24282c"),
		false
	)
	_box(
		"CanopyFasciaTrim",
		Vector3(entrance_x, BASE_Y + canopy_h - 0.05, z_front + 0.32),
		Vector3(width + 0.9, 0.12, 0.08),
		CYAN_TRIM,
		false
	)

	# Illuminated Main Entrance Sign
	_box(
		"EntranceMainSign",
		Vector3(entrance_x, BASE_Y + canopy_h + 0.45, z_front + 0.28),
		Vector3(6.8, 0.70, 0.20),
		Color("1b4f80"),
		false
	)
	_add_world_label(
		"EntranceMainSignText",
		"MAIN ENTRANCE • UC BANILAD",
		Vector3(entrance_x, BASE_Y + canopy_h + 0.45, z_front + 0.40),
		0.0075,
		Color("f0f4f8")
	)



func _wall_with_door(
	prefix: String,
	x0: float,
	x1: float,
	door_center_x: float,
	z: float,
	wall_center_y: float,
	wall_height: float,
	color: Color,
	interior_z_sign: float,
	spawn_door_leaf: bool = true
) -> void:
	var door_width := 1.55
	var door_height := minf(2.35, wall_height - 0.25)
	var floor_y := wall_center_y - wall_height * 0.5
	var gap_left := maxf(x0, door_center_x - door_width * 0.5)
	var gap_right := minf(x1, door_center_x + door_width * 0.5)
	var left_width := gap_left - x0
	var right_width := x1 - gap_right
	if left_width > 0.08:
		_box(prefix + "Left", Vector3(x0 + left_width * 0.5, wall_center_y, z), Vector3(left_width, wall_height, 0.18), color)
	if right_width > 0.08:
		_box(prefix + "Right", Vector3(gap_right + right_width * 0.5, wall_center_y, z), Vector3(right_width, wall_height, 0.18), color)
	_box(
		prefix + "Top",
		Vector3(door_center_x, floor_y + door_height + (wall_height - door_height) * 0.5, z),
		Vector3(gap_right - gap_left, wall_height - door_height, 0.18),
		color
	)
	if not spawn_door_leaf:
		return
	# A hinged leaf swings into its room and stays wholly inside the opening.
	var leaf_width := 1.35
	var leaf_angle := deg_to_rad(72.0)
	var hinge_x := gap_left + 0.08
	_rotated_box(
		prefix + "Door",
		Vector3(
			hinge_x + cos(leaf_angle) * leaf_width * 0.5,
			floor_y + door_height * 0.5,
			z + interior_z_sign * (0.1 + sin(leaf_angle) * leaf_width * 0.5)
		),
		Vector3(leaf_width, door_height, 0.06),
		Vector3(0.0, -interior_z_sign * leaf_angle, 0.0),
		CYAN_DOOR
	)


func _wall_with_door_z(
	prefix: String,
	z0: float,
	z1: float,
	door_center_z: float,
	x: float,
	wall_center_y: float,
	wall_height: float,
	color: Color,
	interior_x_sign: float,
	spawn_door_leaf: bool = true
) -> void:
	## Side-wing twin of _wall_with_door: the wall runs along z at a fixed x.
	var door_width := 1.55
	var door_height := minf(2.35, wall_height - 0.25)
	var floor_y := wall_center_y - wall_height * 0.5
	var gap_lo := maxf(z0, door_center_z - door_width * 0.5)
	var gap_hi := minf(z1, door_center_z + door_width * 0.5)
	var lo_width := gap_lo - z0
	var hi_width := z1 - gap_hi
	if lo_width > 0.08:
		_box(prefix + "Lo", Vector3(x, wall_center_y, z0 + lo_width * 0.5), Vector3(0.18, wall_height, lo_width), color)
	if hi_width > 0.08:
		_box(prefix + "Hi", Vector3(x, wall_center_y, gap_hi + hi_width * 0.5), Vector3(0.18, wall_height, hi_width), color)
	_box(
		prefix + "Top",
		Vector3(x, floor_y + door_height + (wall_height - door_height) * 0.5, door_center_z),
		Vector3(0.18, wall_height - door_height, gap_hi - gap_lo),
		color
	)
	if not spawn_door_leaf:
		return
	var leaf_width := 1.35
	var leaf_angle := deg_to_rad(72.0)
	var hinge_z := gap_lo + 0.08
	_rotated_box(
		prefix + "Door",
		Vector3(
			x + interior_x_sign * (0.1 + sin(leaf_angle) * leaf_width * 0.5),
			floor_y + door_height * 0.5,
			hinge_z + cos(leaf_angle) * leaf_width * 0.5
		),
		Vector3(0.06, door_height, leaf_width),
		Vector3(0.0, interior_x_sign * leaf_angle, 0.0),
		CYAN_DOOR
	)


func _wall_with_opening(
	prefix: String,
	x0: float,
	x1: float,
	opening_left: float,
	opening_right: float,
	z: float,
	wall_center_y: float,
	wall_height: float,
	color: Color
) -> void:
	var opening_height := minf(2.55, wall_height - 0.2)
	var floor_y := wall_center_y - wall_height * 0.5
	var gap_left := clampf(opening_left, x0, x1)
	var gap_right := clampf(opening_right, x0, x1)
	var left_width := gap_left - x0
	var right_width := x1 - gap_right
	if left_width > 0.08:
		_box(prefix + "Left", Vector3(x0 + left_width * 0.5, wall_center_y, z), Vector3(left_width, wall_height, 0.18), color)
	if right_width > 0.08:
		_box(prefix + "Right", Vector3(gap_right + right_width * 0.5, wall_center_y, z), Vector3(right_width, wall_height, 0.18), color)
	_box(
		prefix + "Top",
		Vector3((gap_left + gap_right) * 0.5, floor_y + opening_height + (wall_height - opening_height) * 0.5, z),
		Vector3(gap_right - gap_left, wall_height - opening_height, 0.18),
		color
	)


func _wall_with_opening_z(
	prefix: String,
	z0: float,
	z1: float,
	opening_lo: float,
	opening_hi: float,
	x: float,
	wall_center_y: float,
	wall_height: float,
	color: Color
) -> void:
	var opening_height := minf(2.55, wall_height - 0.2)
	var floor_y := wall_center_y - wall_height * 0.5
	var gap_lo := clampf(opening_lo, z0, z1)
	var gap_hi := clampf(opening_hi, z0, z1)
	var lo_width := gap_lo - z0
	var hi_width := z1 - gap_hi
	if lo_width > 0.08:
		_box(prefix + "Lo", Vector3(x, wall_center_y, z0 + lo_width * 0.5), Vector3(0.18, wall_height, lo_width), color)
	if hi_width > 0.08:
		_box(prefix + "Hi", Vector3(x, wall_center_y, gap_hi + hi_width * 0.5), Vector3(0.18, wall_height, hi_width), color)
	_box(
		prefix + "Top",
		Vector3(x, floor_y + opening_height + (wall_height - opening_height) * 0.5, (gap_lo + gap_hi) * 0.5),
		Vector3(0.18, wall_height - opening_height, gap_hi - gap_lo),
		color
	)


func _build_elevator_bank(level: int) -> void:
	var floor_base := _floor_y(level)
	var wall_h := _room_wall_height(level)
	var door_x := ELEVATOR_DOOR_X
	var elev_z := SOUTH_ROOM_WALL_Z
	var door_width := 2.4
	var door_height := minf(2.4, wall_h - 0.3)
	var side_width := (ELEVATOR_BANK_RIGHT_X - ELEVATOR_BANK_LEFT_X - door_width) * 0.5
	var left_center := ELEVATOR_BANK_LEFT_X + side_width * 0.5
	var right_center := ELEVATOR_BANK_RIGHT_X - side_width * 0.5
	var door_front_z := elev_z - (0.18 * 0.5 + 0.12 * 0.5 + 0.01)
	var frame_front_z := elev_z - (0.18 * 0.5 + 0.25 * 0.5 + 0.01)

	_box("ElevatorWallL_L%02d" % (level + 1), Vector3(left_center, floor_base + wall_h * 0.5, elev_z), Vector3(side_width, wall_h, 0.18), WALL_INNER)
	_box("ElevatorWallR_L%02d" % (level + 1), Vector3(right_center, floor_base + wall_h * 0.5, elev_z), Vector3(side_width, wall_h, 0.18), WALL_INNER)
	_box("ElevatorWallTop_L%02d" % (level + 1), Vector3(door_x, floor_base + door_height + (wall_h - door_height) * 0.5, elev_z), Vector3(door_width, wall_h - door_height, 0.18), WALL_INNER)
	_box("ElevatorDoorL_L%02d" % (level + 1), Vector3(door_x - door_width * 0.25, floor_base + door_height * 0.5, door_front_z), Vector3(door_width * 0.5, door_height, 0.12), Color("484c4c"))
	_box("ElevatorDoorR_L%02d" % (level + 1), Vector3(door_x + door_width * 0.25, floor_base + door_height * 0.5, door_front_z), Vector3(door_width * 0.5, door_height, 0.12), Color("424646"))
	_box("ElevatorFrameTop_L%02d" % (level + 1), Vector3(door_x, floor_base + door_height + 0.08, frame_front_z), Vector3(2.55, 0.16, 0.25), CYAN_TRIM, false)

	# Back and side walls of the shaft so the core never reads as a flat panel.
	_box("ElevatorShaftBack_L%02d" % (level + 1), Vector3(door_x, floor_base + wall_h * 0.5, FRONT_ROOM_BACK_Z), Vector3(ELEVATOR_BANK_RIGHT_X - ELEVATOR_BANK_LEFT_X, wall_h, 0.18), WALL_INNER)

	_create_elevator_call_button(level, door_x + 1.55, elev_z)
	_add_world_label(
		"ElevatorFloorLabel_L%02d" % (level + 1),
		level_label(level),
		Vector3(door_x, floor_base + door_height + 0.32, elev_z - 0.105),
		0.007,
		Color("ddd4b0"),
		PI
	)


func _create_elevator_call_button(level: int, x: float, elev_z: float) -> void:
	var panel: StaticBody3D = ElevatorPanelType.new()
	panel.name = "ElevatorCall_L%02d" % (level + 1)
	panel.position = Vector3(x, _floor_y(level) + 1.25, elev_z - 0.15)
	panel.configure(
		StringName("elevator_call_%d" % (level + 1)),
		"Use Elevator",
		"",
		level,
		elevator_landing_local(level)
	)
	panel.activated.connect(_on_elevator_activated)
	add_child(panel)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.15, 0.3, 0.1)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(Color("2b302f"))
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.15, 0.3, 0.1)
	collision.shape = shape
	panel.add_child(collision)


func _on_elevator_activated(id: StringName, message: String) -> void:
	message_requested.emit(message)
	elevator_activated.emit(id, message)


func _build_floor_signage(level: int) -> void:
	var floor_base := _floor_y(level)
	_add_world_label(
		"FloorDirectory_L%02d" % (level + 1),
		"%s  //  %s" % [level_name(level), LEVEL_SUBTITLES[level]],
		Vector3(-8.5, floor_base + 2.55, SOUTH_ROOM_WALL_Z - 0.105),
		0.0055,
		Color("d7d2b8"),
		PI
	)

	# Every declared room gets a sign over its own door, so signage and
	# geometry can never drift apart.
	for wing in ["front", "back", "east", "west"]:
		var bays := _wing_bays(level, wing)
		var wall_pos := _wing_wall_position(wing)
		var sign_offset := -0.105 * _wing_interior_sign(wing)
		for bay_index in range(bays.size()):
			var bay: Dictionary = bays[bay_index]
			var bay_name: String = bay["name"]
			if bay_name.is_empty():
				continue
			var along := (float(bay["lo"]) + float(bay["hi"])) * 0.5
			var yaw := 0.0
			var position_value := Vector3.ZERO
			match wing:
				"front":
					yaw = PI
					position_value = Vector3(along, floor_base + 2.5, wall_pos + sign_offset)
				"back":
					yaw = 0.0
					position_value = Vector3(along, floor_base + 2.5, wall_pos + sign_offset)
				"east":
					yaw = -PI * 0.5
					position_value = Vector3(wall_pos + sign_offset, floor_base + 2.5, along)
				_:
					yaw = PI * 0.5
					position_value = Vector3(wall_pos + sign_offset, floor_base + 2.5, along)
			_add_world_label(
				"RoomSign_L%02d_%s_%02d" % [level + 1, wing, bay_index + 1],
				bay_name,
				position_value,
				0.0038,
				Color("ddcf9f"),
				yaw
			)


func _build_floor_lighting(level: int) -> void:
	var floor_base := _floor_y(level)
	# Fewer corridor fills; distant levels are culled at runtime.
	for light_index in range(2):
		var x := -12.0 + float(light_index) * 24.0
		_box(
			"CorridorLightFix_L%02d_%02d" % [level + 1, light_index + 1],
			Vector3(x, floor_base + 3.05, CORRIDOR_S_Z),
			Vector3(0.35, 0.12, 0.35),
			Color("d8d3b2"),
			false
		)
		var light := OmniLight3D.new()
		light.name = "CorridorLight_L%02d_%02d" % [level + 1, light_index + 1]
		light.position = Vector3(x, floor_base + 2.75, CORRIDOR_S_Z)
		light.light_color = Color("d7d0aa")
		light.light_energy = 0.85 if level != Level.F8 else 0.6
		light.omni_range = 11.0
		light.shadow_enabled = false
		add_child(light)
		_register_floor_light(level, light)

	# Courtyard flood lights on the lower levels only.
	if level <= Level.MEZZANINE:
		for x in [-8.0, 8.0]:
			var flood := SpotLight3D.new()
			flood.name = "CourtFlood_L%02d_%s" % [level + 1, str(x)]
			flood.position = Vector3(x, floor_base + 2.4, COURT_FRONT + 0.4)
			flood.rotation_degrees = Vector3(-55, 0, 0)
			flood.light_color = Color("f0ead0")
			flood.light_energy = 1.4
			flood.spot_range = 18.0
			flood.spot_angle = 40.0
			flood.shadow_enabled = false
			add_child(flood)
			_register_floor_light(level, flood)


func _build_floor_rooms(level: int) -> void:
	var floor_base := _floor_y(level)
	for wing in ["front", "back", "east", "west"]:
		var bays := _wing_bays(level, wing)
		for bay_index in range(bays.size()):
			var bay: Dictionary = bays[bay_index]
			var bay_type: String = bay["type"]
			if bay_type == "void":
				continue
			var room_id := "L%02d_%s_%02d" % [level + 1, wing, bay_index + 1]
			var center := _bay_room_center(wing, bay, floor_base)
			_build_room_interior(level, wing, bay, room_id, center)
	if level == Level.GROUND:
		_build_lobby_furniture()
	_build_corridor_services(level)


func _room_axes(wing: String) -> Array:
	## Returns [along_axis, into_room_axis] as unit vectors in the XZ plane.
	match wing:
		"front": return [Vector3.RIGHT, Vector3.BACK]
		"back": return [Vector3.RIGHT, Vector3.FORWARD]
		"east": return [Vector3.BACK, Vector3.RIGHT]
		_: return [Vector3.BACK, Vector3.LEFT]


func _build_room_interior(level: int, wing: String, bay: Dictionary, room_id: String, center: Vector3) -> void:
	var axes := _room_axes(wing)
	var along: Vector3 = axes[0]
	var into: Vector3 = axes[1]
	var width := absf(float(bay["hi"]) - float(bay["lo"]))
	var depth := absf(_wing_room_back(wing) - _wing_wall_position(wing))
	var bay_type: String = bay["type"]
	var y := center.y
	# Props thin out with height so the ten-level stack keeps its draw budget.
	var detail := 2 if level <= Level.MEZZANINE else (1 if level <= Level.F4 else 0)

	match bay_type:
		"classroom":
			_build_standard_classroom(room_id, center, along, into, width, depth, detail)
		"lab":
			_build_computer_lab(room_id, center, along, into, width, depth, detail)
		"cr":
			_build_comfort_room(room_id, center, along, into, width, depth)
		"office", "clinic":
			_build_office_room(room_id, center, along, into, width, depth, bay_type)
		"shop":
			_build_shop_unit(room_id, str(bay["name"]), center, along, into, width, depth, wing)
		"canteen":
			_build_canteen(room_id, center, along, into, width, depth)
		"chapel":
			_build_chapel(room_id, center, along, into, width, depth)
		"library":
			_build_library(room_id, center, along, into, width, depth)
		"guard":
			_build_guard_post(center + into * 1.6)
		"storage", "service", "machine":
			_build_service_room(room_id, center, along, into, width, depth, bay_type)
		_:
			pass
	# A ceiling closes every enclosed room; the corridors stay open-air.
	_box(
		"RoomCeiling_%s" % room_id,
		Vector3(center.x, y + _room_wall_height(level) - 0.06, center.z),
		Vector3(
			(absf(along.x) * width + absf(into.x) * depth) - 0.2,
			0.08,
			(absf(along.z) * width + absf(into.z) * depth) - 0.2
		),
		Color("b8bcb6"),
		false
	)


func _build_standard_classroom(
	room_id: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float, detail: int
) -> void:
	var board_center := center + into * (depth * 0.5 - 0.2)
	_box("Whiteboard_%s" % room_id, board_center + Vector3(0.0, 1.75, 0.0), _slab_size(along, into, minf(width - 1.2, 3.6), 0.08, 1.3), Color("f4f4f0"), false)
	_box("TeacherDesk_%s" % room_id, board_center - into * 1.0 + Vector3(0.0, 0.72, 0.0), _slab_size(along, into, 1.7, 0.7, 0.14), WOOD_DESK, false)
	var cols := 3 if detail >= 2 else (2 if detail == 1 else 1)
	var rows := 2 if detail >= 1 else 1
	for row in range(rows):
		for col in range(cols):
			var offset := along * ((float(col) - float(cols - 1) * 0.5) * 1.3) - into * (0.4 + float(row) * 1.15)
			_classroom_chair("Chair_%s_%d_%d" % [room_id, row, col], center + offset)
	_box("FanHub_%s" % room_id, center + Vector3(0.0, 2.55, 0.0), Vector3(0.22, 0.14, 0.22), Color("2a2a2a"), false)
	_box("FanBlade_%s" % room_id, center + Vector3(0.0, 2.5, 0.0), Vector3(1.8, 0.04, 0.25), Color("1a1a1a"), false)


func _build_computer_lab(
	room_id: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float, detail: int
) -> void:
	var board_center := center + into * (depth * 0.5 - 0.2)
	_box("LabWhiteboard_%s" % room_id, board_center + Vector3(0.0, 1.75, 0.0), _slab_size(along, into, minf(width - 1.4, 3.2), 0.08, 1.2), Color("f4f4f0"), false)
	_box("LabAC_%s" % room_id, center - into * (depth * 0.5 - 0.3) + Vector3(0.0, 2.35, 0.0), _slab_size(along, into, 1.2, 0.35, 0.45), AC_UNIT, false)
	var cols := 3 if detail >= 1 else 2
	var rows := 2 if detail >= 2 else 1
	for row in range(rows):
		for col in range(cols):
			var offset := along * ((float(col) - float(cols - 1) * 0.5) * 1.35) - into * (0.5 + float(row) * 1.2)
			var desk_pos := center + offset
			_box("LabDesk_%s_%d_%d" % [room_id, row, col], desk_pos + Vector3(0.0, 0.72, 0.0), _slab_size(along, into, 1.0, 0.55, 0.1), Color("4a5352"), false)
			_box("LabPC_%s_%d_%d" % [room_id, row, col], desk_pos + Vector3(0.0, 1.05, 0.0) + into * 0.16, _slab_size(along, into, 0.42, 0.12, 0.38), Color("1a1c1e"), false)
			_classroom_chair("LabChair_%s_%d_%d" % [room_id, row, col], desk_pos - into * 0.5)


func _build_office_room(
	room_id: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float, room_type: String
) -> void:
	var desk_pos := center + into * minf(depth * 0.25, 1.6)
	_box("Desk_%s" % room_id, desk_pos + Vector3(0.0, 0.72, 0.0), _slab_size(along, into, minf(width - 1.0, 2.2), 0.9, 0.12), WOOD_DESK, false)
	_box("DeskFront_%s" % room_id, desk_pos + Vector3(0.0, 0.35, 0.0) - into * 0.45, _slab_size(along, into, minf(width - 1.0, 2.2), 0.08, 0.7), Color("55483a"), false)
	_classroom_chair("OfficeChair_%s" % room_id, desk_pos + into * 0.85)
	_box("Cabinet_%s" % room_id, center + into * (depth * 0.5 - 0.35) + along * minf(width * 0.3, 1.6) + Vector3(0.0, 0.95, 0.0), _slab_size(along, into, 1.0, 0.5, 1.9), Color("6d7370"), false)
	if room_type == "clinic":
		_box("ClinicBed_%s" % room_id, center - into * 0.6 + Vector3(0.0, 0.5, 0.0), _slab_size(along, into, 0.9, 2.0, 0.18), Color("bfc7c9"), false)


func _build_shop_unit(
	room_id: String, shop_name: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float, wing: String
) -> void:
	var counter_pos := center - into * minf(depth * 0.3, 1.2)
	_box("ShopCounter_%s" % room_id, counter_pos + Vector3(0.0, 0.5, 0.0), _slab_size(along, into, minf(width - 0.8, 3.0), 0.7, 1.0), Color("6a5a44"), false)
	_box("ShopShelf_%s" % room_id, center + into * (depth * 0.5 - 0.35) + Vector3(0.0, 1.1, 0.0), _slab_size(along, into, minf(width - 0.6, 3.2), 0.5, 2.2), Color("7d8280"), false)
	var sign_yaw := PI if wing == "front" else (PI * 0.5 if wing == "west" else -PI * 0.5)
	_add_world_label(
		"ShopSign_%s" % room_id,
		shop_name,
		counter_pos + Vector3(0.0, 1.55, 0.0) - into * 0.05,
		0.0045,
		Color("f0e4c8"),
		sign_yaw
	)


func _build_canteen(
	room_id: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float
) -> void:
	_box("CanteenServing_%s" % room_id, center + into * (depth * 0.5 - 0.5) + Vector3(0.0, 0.55, 0.0), _slab_size(along, into, minf(width - 1.0, 5.0), 0.9, 1.1), Color("8d9391"), false)
	var table_count := clampi(int(width / 2.6), 1, 3)
	for i in range(table_count):
		var offset := along * ((float(i) - float(table_count - 1) * 0.5) * 2.4)
		_box("CanteenTable_%s_%d" % [room_id, i], center + offset + Vector3(0.0, 0.72, 0.0), _slab_size(along, into, 1.6, 0.9, 0.1), Color("9a9488"), false)
		_box("CanteenBench_%s_%d" % [room_id, i], center + offset - into * 0.75 + Vector3(0.0, 0.42, 0.0), _slab_size(along, into, 1.6, 0.32, 0.1), Color("5a5347"), false)


func _build_chapel(
	room_id: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float
) -> void:
	_box("ChapelAltar_%s" % room_id, center + into * (depth * 0.5 - 0.6) + Vector3(0.0, 0.5, 0.0), _slab_size(along, into, 2.2, 0.9, 0.9), Color("8c7554"), false)
	_box("ChapelCross_%s" % room_id, center + into * (depth * 0.5 - 0.2) + Vector3(0.0, 1.9, 0.0), _slab_size(along, into, 0.14, 0.1, 1.1), Color("d8cfae"), false)
	_box("ChapelCrossArm_%s" % room_id, center + into * (depth * 0.5 - 0.2) + Vector3(0.0, 2.05, 0.0), _slab_size(along, into, 0.7, 0.1, 0.14), Color("d8cfae"), false)
	for i in range(3):
		_box("ChapelPew_%s_%d" % [room_id, i], center - into * (0.4 + float(i) * 0.85) + Vector3(0.0, 0.42, 0.0), _slab_size(along, into, minf(width - 1.4, 4.0), 0.3, 0.16), Color("5d4b36"), false)


func _build_library(
	room_id: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float
) -> void:
	var shelf_count := clampi(int(depth / 1.6), 1, 3)
	for i in range(shelf_count):
		_box("LibShelf_%s_%d" % [room_id, i], center + into * (float(i) * 1.5 - depth * 0.2) + Vector3(0.0, 1.05, 0.0), _slab_size(along, into, minf(width - 1.2, 4.0), 0.45, 2.1), Color("6d5f49"), false)
	_box("LibTable_%s" % room_id, center - into * (depth * 0.35) + Vector3(0.0, 0.72, 0.0), _slab_size(along, into, minf(width - 1.6, 2.6), 1.0, 0.1), WOOD_DESK, false)


func _build_comfort_room(
	room_id: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float
) -> void:
	for side in [-1.0, 1.0]:
		_box(
			"CRStall_%s_%d" % [room_id, int(side)],
			center + along * (side * minf(width * 0.25, 0.95)) + into * (depth * 0.25) + Vector3(0.0, 1.0, 0.0),
			_slab_size(along, into, minf(width * 0.42, 1.2), 1.3, 2.0),
			Color("c8c4ba"),
			false
		)
	_box("CRSink_%s" % room_id, center - into * (depth * 0.3) + Vector3(0.0, 0.85, 0.0), _slab_size(along, into, minf(width - 0.8, 2.0), 0.5, 0.15), Color("d8d8d4"), false)


func _build_service_room(
	room_id: String, center: Vector3, along: Vector3, into: Vector3,
	width: float, depth: float, room_type: String
) -> void:
	_box("Shelving_%s" % room_id, center + into * (depth * 0.5 - 0.35) + Vector3(0.0, 1.0, 0.0), _slab_size(along, into, minf(width - 0.8, 2.8), 0.55, 2.0), Color("555c59"), false)
	_box("Panel_%s" % room_id, center - into * (depth * 0.4) + Vector3(0.0, 1.2, 0.0), _slab_size(along, into, 0.8, 0.2, 1.4), Color("3a3f3e"), false)
	if room_type == "machine":
		_box("Winch_%s" % room_id, center + Vector3(0.0, 0.7, 0.0), _slab_size(along, into, 1.8, 1.3, 1.4), Color("6c716f"), false)


func _build_guard_post(slot: Vector3) -> void:
	_box("GuardCctvDesk", slot + Vector3(0.0, 0.5, 0.0), Vector3(2.6, 0.9, 1.2), Color("3a4548"))
	_box("CctvMonitorA", slot + Vector3(-0.6, 1.15, -0.1), Vector3(0.55, 0.4, 0.12), Color("151818"), false)
	_box("CctvMonitorB", slot + Vector3(0.6, 1.15, -0.1), Vector3(0.55, 0.4, 0.12), Color("151818"), false)
	_box("Logbook", slot + Vector3(0.0, 1.0, 0.25), Vector3(0.35, 0.05, 0.45), Color("c9b896"), false)


func _build_corridor_services(level: int) -> void:
	## Exposed fire main and split-type condensers, straight from the photos.
	var y := _floor_y(level)
	var pipe_y := y + _room_wall_height(level) - 0.45
	_box(
		"FirePipeSouth_L%02d" % (level + 1),
		Vector3(0.0, pipe_y, SOUTH_ROOM_WALL_Z - 0.35),
		Vector3(_building_width() - 2.0, 0.14, 0.14),
		FIRE_PIPE_RED,
		false
	)
	_box(
		"FirePipeNorth_L%02d" % (level + 1),
		Vector3(0.0, pipe_y, NORTH_ROOM_WALL_Z + 0.35),
		Vector3(_building_width() - 2.0, 0.14, 0.14),
		FIRE_PIPE_RED,
		false
	)
	for drop_x in [-18.0, -2.0, 16.0]:
		_box(
			"FirePipeDrop_L%02d_%d" % [level + 1, int(drop_x)],
			Vector3(drop_x, y + _room_wall_height(level) * 0.5, SOUTH_ROOM_WALL_Z - 0.35),
			Vector3(0.12, _room_wall_height(level), 0.12),
			FIRE_PIPE_RED,
			false
		)
	if level >= Level.F2:
		for ac_x in [-9.0, 6.0, 19.0]:
			_box(
				"CondenserUnit_L%02d_%d" % [level + 1, int(ac_x)],
				Vector3(ac_x, y + 0.45, COURT_FRONT + 0.55),
				Vector3(0.95, 0.75, 0.45),
				AC_UNIT,
				false
			)
			_box(
				"CondenserBracket_L%02d_%d" % [level + 1, int(ac_x)],
				Vector3(ac_x, y + 0.06, COURT_FRONT + 0.55),
				Vector3(1.05, 0.08, 0.55),
				Color("5f6462"),
				false
			)


func _slab_size(along: Vector3, into: Vector3, along_len: float, into_len: float, height: float) -> Vector3:
	## Build a box size from wing-relative lengths so one prop routine serves
	## rooms on all four sides of the ring.
	return Vector3(
		absf(along.x) * along_len + absf(into.x) * into_len,
		height,
		absf(along.z) * along_len + absf(into.z) * into_len
	)


func _build_lobby_furniture() -> void:
	var y := _floor_y(Level.GROUND)
	var wood := Color("5b4936")
	var green := Color("345047")

	_box("InfoDesk", Vector3(-8.0, y + 0.48, -26.5), Vector3(2.6, 0.95, 1.4), wood)
	_box("ReceptionCounter", Vector3(-2.0, y + 0.45, -30.4), Vector3(6.0, 0.9, 0.75), green)
	for x in [-10.5, -3.5, 2.0]:
		_box("LobbyBench", Vector3(x, y + 0.3, -28.6), Vector3(2.0, 0.5, 0.7), Color("4d4437"), false)
	# Polished lobby floor between the street doors and the quadrangle.
	_box("LobbyTileField", Vector3(-4.0, y + 0.02, -27.6), Vector3(16.0, 0.04, 9.4), LOBBY_TILE, false)

	var directory := _box("LobbyDirectory", Vector3(-13.4, y + 1.6, -32.45), Vector3(4.4, 2.6, 0.16), Color("1e4f7a"), false)
	_add_label(
		directory,
		"UC DIRECTORY\nG   LOBBY / QUADRANGLE / SHOPS\nM   ADMIN OFFICES\n2-8 CLASSROOMS & LABORATORIES\nRD  ROOF DECK LABS",
		Vector3(0.0, 0.0, 0.12),
		0.0032,
		Color("d8d5c5")
	)


func _build_stairwell() -> void:
	var stair_color := Color("686a65")
	var rail_color := Color("3d4343")

	for floor_index in range(LEVEL_COUNT):
		var y := _floor_y(floor_index)
		# The ground slab already forms the first landing. Upper landings bridge
		# only the actual stair opening, touching both adjacent slabs at the seam.
		if floor_index > 0:
			_box(
				"StairEntryLanding_F%02d" % (floor_index + 1),
				Vector3(STAIR_LANDING_CENTER_X, y - 0.13, STAIR_ENTRY_Z),
				Vector3(STAIR_LANDING_WIDTH + 0.2, 0.26, STAIR_ENTRY_DEPTH + 0.1),
				stair_color,
				false
			)
		_box(
			"StairAccessWalk_F%02d" % (floor_index + 1),
			Vector3((STAIR_HOLE_LEFT_X + STAIR_SIDE_WALK_RIGHT_X) * 0.5, y - 0.13, (STAIR_HOLE_FRONT_Z + STAIR_HOLE_BACK_Z) * 0.5),
			Vector3(STAIR_SIDE_WALK_RIGHT_X - STAIR_HOLE_LEFT_X + 0.1, 0.26, absf(STAIR_HOLE_BACK_Z - STAIR_HOLE_FRONT_Z) + 0.1),
			stair_color,
			false
		)
		var access_rail_back_z := STAIR_ENTRY_Z + STAIR_ENTRY_DEPTH * 0.5
		var access_rail_front_z := STAIR_MID_Z - STAIR_MID_DEPTH * 0.5
		_build_metal_fence_x(
			"StairFrontGuard_F%02d" % (floor_index + 1),
			STAIR_HOLE_LEFT_X,
			STAIR_HOLE_RIGHT_X,
			STAIR_HOLE_FRONT_Z - 0.04,
			y,
			1.05,
			rail_color
		)
		_build_metal_fence_z(
			"StairAccessRail_F%02d" % (floor_index + 1),
			access_rail_back_z,
			access_rail_front_z,
			STAIR_SIDE_WALK_RIGHT_X + 0.04,
			y,
			1.25,
			rail_color,
			true
		)
		var stair_light := OmniLight3D.new()
		stair_light.name = "StairLight_F%02d" % (floor_index + 1)
		stair_light.position = Vector3(-22.0, y + 2.6, -42.0)
		stair_light.light_color = Color("d2c89d")
		stair_light.light_energy = 0.9
		stair_light.omni_range = 7.0
		stair_light.shadow_enabled = false
		add_child(stair_light)
		_register_floor_light(floor_index, stair_light)

	# Storey heights differ (tall ground lobby, short mezzanine), so each
	# switchback is sized from its own pair of finished-floor levels.
	for floor_index in range(LEVEL_COUNT - 1):
		var lower_y := _floor_y(floor_index)
		var upper_y := _floor_y(floor_index + 1)
		var middle_y := (lower_y + upper_y) * 0.5
		_build_stair_flight("StairA_F%02d" % (floor_index + 1), -22.75, STAIR_FLIGHT_BACK_Z, STAIR_FLIGHT_FRONT_Z, lower_y, middle_y)
		_build_stair_flight("StairB_F%02d" % (floor_index + 1), -19.8, STAIR_FLIGHT_FRONT_Z, STAIR_FLIGHT_BACK_Z, middle_y, upper_y)
		_box(
			"StairMidLanding_F%02d" % (floor_index + 1),
			Vector3(STAIR_LANDING_CENTER_X, middle_y - 0.13, STAIR_MID_Z),
			Vector3(STAIR_LANDING_WIDTH + 0.2, 0.26, STAIR_MID_DEPTH + 0.1),
			stair_color,
			false
		)
		_build_metal_fence_x(
			"StairMidGuard_F%02d" % (floor_index + 1),
			STAIR_SIDE_WALK_RIGHT_X,
			STAIR_HOLE_RIGHT_X,
			STAIR_MID_Z + STAIR_MID_DEPTH * 0.5 - 0.04,
			middle_y,
			1.05,
			rail_color
		)

	_build_stair_walk_collision()


func _build_stair_flight(
	prefix: String,
	x: float,
	from_z: float,
	to_z: float,
	from_y: float,
	to_y: float
) -> void:
	var step_count := 10
	var run := absf(to_z - from_z)
	var rise := to_y - from_y
	var step_depth := run / float(step_count)
	var direction := signf(to_z - from_z)
	for step_index in range(step_count):
		var progress := float(step_index + 1) / float(step_count)
		var step_height := rise * progress
		var z := from_z + direction * step_depth * (float(step_index) + 0.5)
		_box(
			prefix + "Step%02d" % (step_index + 1),
			Vector3(x, from_y + step_height * 0.5, z),
			Vector3(STAIR_FLIGHT_WIDTH, step_height, step_depth + 0.02),
			Color("686a65"),
			false
		)
	_add_sloped_rail(prefix + "Rail", x + (1.18 if x < -21.0 else -1.18), from_z, to_z, from_y + 0.9, to_y + 0.9)


func _build_stair_walk_collision() -> void:
	## One shared triangle mesh removes the exposed collision edges that occur
	## when separate ramp and landing shapes merely touch one another.
	var body := StaticBody3D.new()
	body.name = "StairWalkSurface"
	add_child(body)
	var faces := PackedVector3Array()
	var half_flight := (STAIR_FLIGHT_WIDTH - 0.1) * 0.5
	var landing_left := STAIR_SIDE_WALK_RIGHT_X
	var landing_right := STAIR_HOLE_RIGHT_X
	var entry_back := STAIR_ENTRY_Z - STAIR_ENTRY_DEPTH * 0.5
	var entry_front := STAIR_ENTRY_Z + STAIR_ENTRY_DEPTH * 0.5
	var mid_back := STAIR_MID_Z - STAIR_MID_DEPTH * 0.5
	var mid_front := STAIR_MID_Z + STAIR_MID_DEPTH * 0.5

	for floor_index in range(LEVEL_COUNT - 1):
		var lower_y := _floor_y(floor_index)
		var upper_y := _floor_y(floor_index + 1)
		var middle_y := (lower_y + upper_y) * 0.5
		# First flight, lower entry to middle landing.
		faces.append_array(_stair_ramp_faces(
			-22.75,
			half_flight,
			STAIR_FLIGHT_BACK_Z,
			STAIR_FLIGHT_FRONT_Z,
			lower_y,
			middle_y
		))
		# Full-depth turnaround platform with both flight edges shared.
		faces.append_array(_quad_faces(
			Vector3(landing_left, middle_y, mid_back),
			Vector3(landing_left, middle_y, mid_front),
			Vector3(landing_right, middle_y, mid_back),
			Vector3(landing_right, middle_y, mid_front)
		))
		# Second flight, middle landing to upper entry.
		faces.append_array(_stair_ramp_faces(
			-19.8,
			half_flight,
			STAIR_FLIGHT_FRONT_Z,
			STAIR_FLIGHT_BACK_Z,
			middle_y,
			upper_y
		))
		# Destination landing; this is also the next story's lower landing.
		faces.append_array(_quad_faces(
			Vector3(landing_left, upper_y, entry_back),
			Vector3(landing_left, upper_y, entry_front),
			Vector3(landing_right, upper_y, entry_back),
			Vector3(landing_right, upper_y, entry_front)
		))

	# Outer side walks share the landing edge and stay inside the slab opening.
	for floor_index in range(1, LEVEL_COUNT):
		var y := _floor_y(floor_index)
		faces.append_array(_quad_faces(
			Vector3(STAIR_HOLE_LEFT_X, y, STAIR_HOLE_BACK_Z),
			Vector3(STAIR_HOLE_LEFT_X, y, STAIR_HOLE_FRONT_Z),
			Vector3(STAIR_SIDE_WALK_RIGHT_X, y, STAIR_HOLE_BACK_Z),
			Vector3(STAIR_SIDE_WALK_RIGHT_X, y, STAIR_HOLE_FRONT_Z)
		))

	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	collision.shape = shape
	body.add_child(collision)


func _quad_faces(left_back: Vector3, left_front: Vector3, right_back: Vector3, right_front: Vector3) -> PackedVector3Array:
	return PackedVector3Array([
		left_back, right_back, left_front,
		right_back, right_front, left_front,
	])


func _stair_ramp_faces(
	x: float,
	half_width: float,
	from_z: float,
	to_z: float,
	from_y: float,
	to_y: float
) -> PackedVector3Array:
	## Flat lead-in/out zones keep the capsule away from a finite sloped edge.
	var faces := PackedVector3Array()
	var direction := signf(to_z - from_z)
	var slope_from_z := from_z + direction * STAIR_RAMP_TRANSITION
	var slope_to_z := to_z - direction * STAIR_RAMP_TRANSITION
	var left := x - half_width
	var right := x + half_width
	faces.append_array(_quad_faces(
		Vector3(left, from_y, from_z),
		Vector3(left, from_y, slope_from_z),
		Vector3(right, from_y, from_z),
		Vector3(right, from_y, slope_from_z)
	))
	faces.append_array(_quad_faces(
		Vector3(left, from_y, slope_from_z),
		Vector3(left, to_y, slope_to_z),
		Vector3(right, from_y, slope_from_z),
		Vector3(right, to_y, slope_to_z)
	))
	faces.append_array(_quad_faces(
		Vector3(left, to_y, slope_to_z),
		Vector3(left, to_y, to_z),
		Vector3(right, to_y, slope_to_z),
		Vector3(right, to_y, to_z)
	))
	return faces


func _add_sloped_rail(
	object_name: String,
	x: float,
	from_z: float,
	to_z: float,
	from_y: float,
	to_y: float
) -> void:
	# Stop the central handrails before each landing so the player has enough
	# room to turn between the switchback flights without catching the capsule.
	var run := absf(to_z - from_z)
	var rise := to_y - from_y
	var direction := signf(to_z - from_z)
	var inset_ratio := STAIR_RAIL_END_CLEARANCE / run
	from_z += direction * STAIR_RAIL_END_CLEARANCE
	to_z -= direction * STAIR_RAIL_END_CLEARANCE
	from_y += rise * inset_ratio
	to_y -= rise * inset_ratio
	run = absf(to_z - from_z)
	rise = to_y - from_y
	var length := sqrt(run * run + rise * rise)
	var angle := atan2(rise, run)
	var rail := StaticBody3D.new()
	rail.name = object_name
	rail.position = Vector3(x, (from_y + to_y) * 0.5, (from_z + to_z) * 0.5)
	add_child(rail)
	var rail_mesh := MeshInstance3D.new()
	rail_mesh.name = "RailMesh"
	rail_mesh.rotation.x = -angle * direction
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, length)
	rail_mesh.mesh = mesh
	rail_mesh.material_override = _material(Color("3d4343"))
	rail_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rail.add_child(rail_mesh)
	var rail_collision := CollisionShape3D.new()
	var rail_shape := BoxShape3D.new()
	rail_shape.size = mesh.size
	rail_collision.shape = rail_shape
	rail_collision.rotation.x = rail_mesh.rotation.x
	rail.add_child(rail_collision)

	# Vertical pickets visually and physically connect the handrail to the ramp.
	var post_count := 4
	for post_index in range(post_count):
		var t := float(post_index) / float(post_count - 1)
		var post_y := lerpf(from_y, to_y, t) - 0.45
		var post_z := lerpf(from_z, to_z, t)
		_box(
			object_name + "Post%02d" % post_index,
			Vector3(x, post_y, post_z),
			Vector3(0.065, 0.9, 0.065),
			Color("3d4343")
		)


func _jalousie_panel(object_name: String, position_value: Vector3, size: Vector3) -> void:
	## Stack of horizontal louvers for natural ventilation look.
	_box(object_name + "Frame", position_value, size, GLASS_DARK, false)
	var slat_count := 6
	var slat_h := size.y / float(slat_count + 1)
	for i in range(slat_count):
		var sy := position_value.y - size.y * 0.4 + float(i + 1) * slat_h
		_box(
			object_name + "Slat%d" % i,
			Vector3(position_value.x, sy, position_value.z + 0.04),
			Vector3(size.x * 0.92, 0.04, size.z + 0.06),
			Color("4a6068"),
			false
		)


func _build_metal_fence_x(
	prefix: String,
	x0: float,
	x1: float,
	z: float,
	floor_y: float,
	height: float,
	color: Color
) -> void:
	var length := absf(x1 - x0)
	if length <= 0.05:
		return
	var center_x := (x0 + x1) * 0.5
	_box(prefix + "Top", Vector3(center_x, floor_y + height - 0.04, z), Vector3(length, 0.08, 0.08), color, false)
	_box(prefix + "Mid", Vector3(center_x, floor_y + height * 0.5, z), Vector3(length, 0.06, 0.06), color, false)
	_collision_box(prefix + "Barrier", Vector3(center_x, floor_y + height * 0.5, z), Vector3(length, height, 0.05))
	var post_count := maxi(1, ceili(length / 0.85))
	for post_index in range(post_count + 1):
		var x := lerpf(x0, x1, float(post_index) / float(post_count))
		_box(prefix + "Post%02d" % post_index, Vector3(x, floor_y + height * 0.5, z), Vector3(0.065, height, 0.065), color, false)


func _build_metal_fence_z(
	prefix: String,
	z0: float,
	z1: float,
	x: float,
	floor_y: float,
	height: float,
	color: Color,
	include_end_posts: bool = false
) -> void:
	var length := absf(z1 - z0)
	if length <= 0.05:
		return
	var center_z := (z0 + z1) * 0.5
	_box(prefix + "Top", Vector3(x, floor_y + height - 0.04, center_z), Vector3(0.08, 0.08, length), color, false)
	_box(prefix + "Mid", Vector3(x, floor_y + height * 0.5, center_z), Vector3(0.06, 0.06, length), color, false)
	_collision_box(prefix + "Barrier", Vector3(x, floor_y + height * 0.5, center_z), Vector3(0.05, height, length))
	var post_count := maxi(1, ceili(length / 0.85))
	# Horizontal runs own the four corner posts, so side runs omit endpoints.
	var first_post := 0 if include_end_posts else 1
	var post_limit := post_count + 1 if include_end_posts else post_count
	for post_index in range(first_post, post_limit):
		var z := lerpf(z0, z1, float(post_index) / float(post_count))
		_box(prefix + "Post%02d" % post_index, Vector3(x, floor_y + height * 0.5, z), Vector3(0.065, height, 0.065), color, false)


func _rotated_box(
	object_name: String,
	position_value: Vector3,
	size: Vector3,
	rotation_value: Vector3,
	color: Color,
	with_collision: bool = true
) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = object_name + "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not with_collision:
		mesh_instance.position = position_value
		mesh_instance.rotation = rotation_value
		add_child(mesh_instance)
		return mesh_instance

	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position_value
	body.rotation = rotation_value
	add_child(body)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _collision_box(object_name: String, position_value: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position_value
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _classroom_chair(object_name: String, position_value: Vector3) -> Node3D:
	return ClassroomChairBuilder.build(self, object_name, position_value, Callable(self, "_material"))


func _box(
	object_name: String,
	position_value: Vector3,
	size: Vector3,
	color: Color,
	with_collision: bool = true
) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = object_name + "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not with_collision:
		mesh_instance.position = position_value
		add_child(mesh_instance)
		return mesh_instance

	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position_value
	add_child(body)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
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
	material.set_shader_parameter("vertex_snap", BUILDING_VERTEX_SNAP)
	_material_cache[key] = material
	return material


func _add_label(
	parent: Node3D,
	text: String,
	position_value: Vector3,
	pixel_size: float,
	color: Color,
	rotation_y: float = 0.0
) -> Label3D:
	var label := Label3D.new()
	label.name = "Label"
	label.text = text
	label.position = position_value
	label.rotation.y = rotation_y
	label.pixel_size = pixel_size
	label.font_size = 48
	label.modulate = color
	label.outline_size = 6
	parent.add_child(label)
	return label


func _add_world_label(
	object_name: String,
	text: String,
	position_value: Vector3,
	pixel_size: float,
	color: Color,
	rotation_y: float = 0.0
) -> Label3D:
	var label := Label3D.new()
	label.name = object_name
	label.text = text
	label.position = position_value
	label.rotation.y = rotation_y
	label.pixel_size = pixel_size
	label.font_size = 48
	label.modulate = color
	label.outline_size = 6
	add_child(label)
	return label
