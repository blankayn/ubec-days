extends Node3D
## Cuenca Ave — World root
## Corrected corridor: UC Banilad is south of Gov. M. Cuenco Avenue,
## Gaisano Country Mall is north, and Camp Lapu-Lapu Road enters the mall block.

const InteractableType = preload("res://scripts/interactable.gd")
const PSX_SHADER = preload("res://shaders/psx_surface.gdshader")
const ScareManagerType = preload("res://scripts/scare_manager.gd")
const SchoolBuildingType = preload("res://scripts/school_building.gd")
const MallBuildingType = preload("res://scripts/mall_building.gd")
const PedestrianBridgeType = preload("res://scripts/pedestrian_bridge.gd")
const BusStopPropType = preload("res://scripts/bus_stop_prop.gd")
const OldLockerPropType = preload("res://scripts/old_locker_prop.gd")
const ElevatorUIType = preload("res://scripts/elevator_ui.gd")
const StoryManagerType = preload("res://scripts/story_manager.gd")
const StreetVehiclePropType = preload("res://scripts/street_vehicle_prop.gd")
const SurvivalDoorType = preload("res://scripts/survival_door.gd")
const HideSpotType = preload("res://scripts/hide_spot.gd")
const PhoneUIType = preload("res://scripts/phone_ui.gd")
const VHSSystemType = preload("res://scripts/vhs_system.gd")
const UcKioskNpcType = preload("res://scripts/uc_kiosk_npc.gd")
const DialogueChoiceUIType = preload("res://scripts/dialogue_choice_ui.gd")
const EdwardNpcPropType = preload("res://scripts/edward_npc_prop.gd")
const JholoNpcPropType = preload("res://scripts/jholo_npc_prop.gd")
const MuletNpcPropType = preload("res://scripts/mulet_npc_prop.gd")

const TREE_PATHS := [
	"res://assets/trees/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_1.glb",
	"res://assets/trees/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_2.glb",
	"res://assets/trees/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_3.glb",
	"res://assets/trees/Retro Tree Pack/Models/Super Low Res/GLB/tree_rt_4.glb",
	"res://assets/trees/Retro Tree Pack/Models/Super Low Res/GLB/dead_tree_rt_1.glb",
]

@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var moon: DirectionalLight3D = $Moon

var _inspected: Dictionary = {}
var _material_cache: Dictionary = {}
var _scare_manager: Node = null
var _story_manager: Node = null
var _caretaker_node: Node3D = null
var _street_lights: Array = []   # Array[OmniLight3D]
var _day_lights: Array = []      # Array[Light3D]
var _ambient_lights: Array = []  # Array[OmniLight3D] — dimmed in day so sun shadows read
var _ambient_light_night_energy: Dictionary = {}
var _night_only_nodes: Array = []
var _day_only_nodes: Array = []
var _quest_glow_targets: Dictionary = {}
var _quest_pulse_time: float = 0.0
var _school_building: Node3D = null
var _mall_building: Node3D = null
var _pedestrian_bridge: Node3D = null
var _bus_stop: Node3D = null
var _elevator_ui: CanvasLayer = null
var _phone_ui: CanvasLayer = null
var _vhs_system: CanvasLayer = null
var _battery_pickups: Array = []
var _survival_doors: Array = []
var _road_traffic: Array = []  # Array[Dictionary] — looping Cuenco Ave vehicles
var _dialogue_choice_ui: CanvasLayer = null
var _bootstrapping := true
var _boot_overlay: CanvasLayer = null
var _boot_fade: ColorRect = null


func _school_point(local_point: Vector3) -> Vector3:
	# The playable UC shell was authored on the north side. A 180-degree
	# transform keeps every story point registered to the relocated building.
	return Vector3(-local_point.x, local_point.y, -local_point.z)


func _place_player_at_entrance() -> void:
	# Start at the left-side street doorway (locker / gate side), facing into UC.
	# The building centre is sealed — do not spawn on the old central axis.
	player.global_position = _school_point(Vector3(
		SchoolBuildingType.ENTRANCE_CENTER_X,
		0.95,
		-20.0
	))
	player.rotation.y = PI


func _mall_point(local_point: Vector3) -> Vector3:
	return Vector3(-local_point.x, local_point.y, -local_point.z)


func _ready() -> void:
	Engine.max_fps = 60
	player.prompt_changed.connect(hud.set_prompt)
	player.interaction_feedback.connect(hud.show_message)
	# Hold control until the procedural campus finishes building across frames.
	player.set_physics_process(false)
	player.set_process(false)
	if player.has_method("set_ui_locked"):
		player.set_ui_locked(true)
	_show_boot_overlay()
	await get_tree().process_frame

	await _build_world_staged()
	_build_scare_manager()
	_build_survival_mechanics()
	_build_phone_and_vhs()
	_build_story_manager()
	player.battery_changed.connect(func(percent: float) -> void: hud.set_battery(percent, player.flashlight_unlocked))
	player.noise_emitted.connect(_on_noise_emitted)
	player.phone_toggle_requested.connect(func() -> void: _phone_ui.toggle())

	_elevator_ui = ElevatorUIType.new()
	add_child(_elevator_ui)
	_elevator_ui.floor_selected.connect(_on_elevator_floor_selected)

	var start_ch: int = StoryManagerType.selected_starting_chapter
	var horror_mode := StoryManagerType.horror_playthrough
	if horror_mode:
		_apply_night_lighting()
		player.set_flashlight_unlocked(true)
		_enable_survival_night_pickups()
		_place_player_at_entrance()
		_story_manager.start(start_ch)
		hud.set_battery(player.battery, true)
	else:
		if start_ch >= 2:
			_apply_night_lighting()
		else:
			_apply_day_lighting()
		_place_player_at_entrance()
		_story_manager.start(start_ch)
		hud.set_battery(player.battery, start_ch >= 2)
	_update_quest_highlights()

	# Let physics / shaders settle behind the blackout before handing control over.
	for _i in 5:
		await get_tree().process_frame
	await get_tree().physics_frame
	await _hide_boot_overlay()
	player.set_physics_process(true)
	player.set_process(true)
	if player.has_method("set_ui_locked"):
		player.set_ui_locked(false)
	_bootstrapping = false


func _show_boot_overlay() -> void:
	_boot_overlay = CanvasLayer.new()
	_boot_overlay.name = "BootOverlay"
	_boot_overlay.layer = 100
	add_child(_boot_overlay)
	_boot_fade = ColorRect.new()
	_boot_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boot_fade.color = Color(0.02, 0.03, 0.05, 1.0)
	_boot_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_boot_overlay.add_child(_boot_fade)
	var label := Label.new()
	label.text = "Entering Cuenca Ave..."
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-160, -12)
	label.custom_minimum_size = Vector2(320, 24)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("d7dee8"))
	_boot_overlay.add_child(label)


func _hide_boot_overlay() -> void:
	if _boot_fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_boot_fade, "modulate:a", 0.0, 0.35)
	await tween.finished
	if is_instance_valid(_boot_overlay):
		_boot_overlay.queue_free()
	_boot_overlay = null
	_boot_fade = null


func _process(delta: float) -> void:
	if _bootstrapping:
		return
	if _scare_manager and _story_manager and (_story_manager.is_night or _story_manager.is_horror_mode):
		_scare_manager.tick(delta)
	if _story_manager:
		_story_manager.tick(delta)
	_update_road_traffic(delta)
	if _story_manager == null or _quest_glow_targets.is_empty():
		return
	if _story_manager.is_horror_mode:
		return
	var active_id: StringName = _story_manager.get_active_quest_id()
	if active_id.is_empty() or not _quest_glow_targets.has(active_id):
		return
	_quest_pulse_time += delta
	var pulse := 1.5 + sin(_quest_pulse_time * 4.5) * 0.55
	var glow_material: StandardMaterial3D = _quest_glow_targets[active_id]["glow_material"]
	glow_material.emission_energy_multiplier = pulse


func _build_story_manager() -> void:
	_story_manager = StoryManagerType.new()
	_story_manager.name = "StoryManager"
	add_child(_story_manager)
	_story_manager.player = player
	_story_manager.hud = hud
	_story_manager.scare_manager = _scare_manager
	_story_manager.phone_ui = _phone_ui
	_story_manager.vhs_system = _vhs_system
	_story_manager.day_night_changed.connect(_on_day_night_changed)
	_story_manager.objective_changed.connect(func(_text: String) -> void: _update_quest_highlights())
	_story_manager.chapter_changed.connect(func(_chapter: int, _title: String) -> void: _update_quest_highlights())
	_story_manager.chapter_changed.connect(_on_story_chapter_changed)
	_story_manager.objective_changed.connect(func(text: String) -> void:
		hud.set_chapter_objective(text)
	)


func _build_phone_and_vhs() -> void:
	_phone_ui = PhoneUIType.new()
	_phone_ui.name = "PhoneUI"
	_phone_ui.player = player
	add_child(_phone_ui)
	_vhs_system = VHSSystemType.new()
	_vhs_system.name = "VHSSystem"
	_vhs_system.player = player
	add_child(_vhs_system)


func _build_survival_mechanics() -> void:
	# Survival doors stay on upper floors / interior props — GF room doors are open openings.
	var faculty_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F5)
	_add_survival_door("FacultyDoorLocked", _school_point(Vector3(14.2, faculty_y, -32.95)), SurvivalDoorType.DoorState.LOCKED, &"door_key_5f")
	# Ground-floor testing room: the door the player can barricade during a chase.
	_add_survival_door("ClassroomDoorBarricade", _school_point(Vector3(21.7, 0.24, -32.95)), SurvivalDoorType.DoorState.BARRICADABLE)
	_add_hide_spot("DeskHideSpot", _school_point(Vector3(-10.0, 0.24, -27.5)), "Under desk")
	_add_hide_spot("ClosetHideSpot", _school_point(Vector3(14.0, 0.24, -27.5)), "Storage closet")
	_add_hide_spot("StallHideSpot", _school_point(Vector3(0.0, 0.24, -52.0)), "CR stall")

	_add_survival_pickup(&"key_door_key_3f", "Take 3F classroom key", _school_point(Vector3(-6.0, 0.55, -27.0)), Color("d9bc60"), "A brass key labelled 3F.")
	_add_survival_pickup(&"key_door_key_5f", "Take 5F faculty key", _school_point(Vector3(14.2, faculty_y + 0.55, -33.9)), Color("d9bc60"), "A brass key labelled 5F.")
	_add_battery_pickups()
	_add_vhs_collectibles()
	_add_survival_pickup(&"vhs_tv", "Use office CRT / VCR", _school_point(Vector3(14.0, 0.75, -29.0)), Color("748a7d"), "The CRT is waiting for a tape.", false)


func _add_survival_door(door_name: String, position_value: Vector3, state: int, key_id: StringName = &"") -> void:
	var door: StaticBody3D = SurvivalDoorType.new()
	door.name = door_name
	door.position = position_value
	door.configure(state, key_id)
	add_child(door)
	door.build()
	door.message_requested.connect(hud.show_message)
	door.noise_emitted.connect(_on_noise_emitted)
	door.barricade_broken.connect(func(_broken_door) -> void:
		_scare_manager.report_noise(door.global_position, 9.0, 25.0)
		player.add_trauma(0.5)
	)
	_scare_manager.register_barricade_door(door)
	_survival_doors.append(door)


func _add_hide_spot(spot_name: String, position_value: Vector3, label_text: String) -> void:
	var spot: Area3D = HideSpotType.new()
	spot.name = spot_name
	spot.position = position_value
	add_child(spot)
	spot.build(label_text)


func _add_battery_pickups() -> void:
	# Spread over the ground lobby and the two levels above it; heights come
	# from the level table so they follow the mezzanine's odd storey height.
	var mezz_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.MEZZANINE) + 0.31
	var f2_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F2) + 0.31
	var floor_candidates := [
		[Vector3(-17.0, 0.5, -28.8), Vector3(-8.0, 0.5, -25.8), Vector3(19.0, 0.5, -27.0)],
		[Vector3(7.6, mezz_y, -33.9), Vector3(-16.0, mezz_y, -27.0), Vector3(20.0, mezz_y, -40.0)],
		[Vector3(7.6, f2_y, -33.9), Vector3(-22.4, f2_y, -27.0), Vector3(0.0, f2_y, -49.5)],
	]
	var pickup_number := 1
	for candidates in floor_candidates:
		candidates.shuffle()
		for index in range(2):
			var pickup: StaticBody3D = _add_survival_pickup(
				StringName("battery_%02d" % pickup_number),
				"Pick up battery (+35)",
				_school_point(candidates[index]),
				Color("c9d273"),
				"Battery pack.",
				true
			)
			pickup.visible = false
			pickup.disabled = true
			_battery_pickups.append(pickup)
			pickup_number += 1


func _add_vhs_collectibles() -> void:
	var landing_x: float = SchoolBuildingType.ELEVATOR_DOOR_X
	var mezz_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.MEZZANINE) + 0.31
	var f2_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F2) + 0.31
	var f5_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F5) + 0.31
	var f7_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F7) + 0.31
	var data := [
		[&"vhs_1", Vector3(-15.9, 0.55, -26.6), "TAPE 01 // Guard Post", "CCTV 1998: empty corridors. At 02:34, a shadow crosses the frame without opening a door."],
		[&"vhs_2", Vector3(landing_x, mezz_y, -33.9), "TAPE 02 // Lab Interview", "A student whispers about footsteps above Room 204 after midnight."],
		[&"vhs_3", Vector3(landing_x, f2_y, -33.9), "TAPE 03 // Janitor", "Shaky footage from a CR stall: a tall shape waits outside the door."],
		[&"vhs_4", Vector3(landing_x, f5_y, -33.9), "TAPE 04 // News Report", "MISSING STUDENT. Last seen heading toward Floor 8."],
		[&"vhs_5", Vector3(landing_x, f7_y, -33.9), "TAPE 05 // Security", "The creature fills the frame for one second, then the tape tears into static."],
		[&"vhs_6", Vector3(10.0, 0.55, 40.0), "TAPE 06 // Foundation", "Construction footage: workers uncover something beneath the building and cover it again."],
	]
	for index in data.size():
		var tape: Array = data[index]
		var tape_position: Vector3 = _school_point(tape[1]) if index < 5 else _mall_point(tape[1])
		_add_survival_pickup(tape[0], "Collect VHS tape", tape_position, Color("865f58"), tape[2])


func _add_survival_pickup(id: StringName, prompt: String, position_value: Vector3, color: Color, message: String, one_shot: bool = true) -> StaticBody3D:
	var pickup: StaticBody3D = InteractableType.new()
	pickup.name = String(id).to_pascal_case()
	pickup.position = position_value
	pickup.setup(id, prompt, message, one_shot)
	pickup.activated.connect(_on_interactable_activated)
	add_child(pickup)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, 0.28, 0.22)
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.8
	mesh_instance.material_override = material
	mesh_instance.position.y = 0.24
	pickup.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.7, 0.7)
	collision.shape = shape
	collision.position.y = 0.3
	pickup.add_child(collision)
	return pickup


func _on_story_chapter_changed(chapter: int, _title: String) -> void:
	var night_mode := chapter >= 2
	if _story_manager != null and _story_manager.is_horror_mode:
		night_mode = true
	player.set_flashlight_unlocked(night_mode)
	hud.set_battery(player.battery, night_mode)
	for door in _survival_doors:
		if is_instance_valid(door) and door.has_method("set_chapter_access"):
			door.set_chapter_access(night_mode)
	for pickup in _battery_pickups:
		if is_instance_valid(pickup):
			if not pickup.get_meta("collected", false):
				pickup.disabled = not night_mode
				pickup.visible = night_mode


func _enable_survival_night_pickups() -> void:
	for door in _survival_doors:
		if is_instance_valid(door) and door.has_method("set_chapter_access"):
			door.set_chapter_access(true)
	for pickup in _battery_pickups:
		if is_instance_valid(pickup):
			if not pickup.get_meta("collected", false):
				pickup.disabled = false
				pickup.visible = true


func _on_noise_emitted(position: Vector3, level: float, radius: float) -> void:
	hud.show_noise(level, radius)
	if _scare_manager != null and _scare_manager.has_method("report_noise"):
		_scare_manager.report_noise(position, level, radius)


func _on_day_night_changed(is_night: bool) -> void:
	if is_night:
		_apply_night_lighting()
		if _scare_manager and _scare_manager.has_method("notify_night_started"):
			_scare_manager.notify_night_started()
	else:
		_apply_day_lighting()


func _apply_day_lighting() -> void:
	var env := world_environment.environment
	env.background_color = Color(0.55, 0.72, 0.88, 1)
	env.ambient_light_color = Color(0.78, 0.82, 0.86, 1)
	env.ambient_light_energy = 0.62
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.82, 0.9, 1)
	env.fog_light_energy = 0.45
	env.fog_density = 0.004
	moon.light_color = Color(1.0, 0.94, 0.82, 1)
	moon.light_energy = 1.30
	moon.rotation_degrees = Vector3(-55, -20, 0)
	for light in _street_lights:
		if is_instance_valid(light):
			light.light_energy = 0.08
	for light in _day_lights:
		if is_instance_valid(light):
			light.visible = true
	for light in _ambient_lights:
		if is_instance_valid(light):
			light.visible = false
			light.light_energy = 0.0
	for node in _night_only_nodes:
		if is_instance_valid(node):
			node.visible = false
			if node is CollisionObject3D:
				(node as CollisionObject3D).collision_layer = 0
				(node as CollisionObject3D).collision_mask = 0
	for node in _day_only_nodes:
		if is_instance_valid(node):
			node.visible = true
			for collision_node in node.find_children("*", "CollisionObject3D", true, false):
				var collision := collision_node as CollisionObject3D
				collision.collision_layer = 1
				collision.collision_mask = 1
	if _mall_building:
		_mall_building.set_night_mode(false)
	if _pedestrian_bridge:
		_pedestrian_bridge.set_night_mode(false)


func _apply_night_lighting() -> void:
	var env := world_environment.environment
	env.background_color = Color(0.009, 0.014, 0.023, 1)
	env.ambient_light_color = Color(0.16, 0.2, 0.25, 1)
	env.ambient_light_energy = 0.55
	env.fog_light_color = Color(0.105, 0.13, 0.14, 1)
	env.fog_light_energy = 0.72
	env.fog_density = 0.012
	moon.light_color = Color(0.46, 0.56, 0.7, 1)
	moon.light_energy = 0.34
	moon.rotation_degrees = Vector3(-48, -28, 0)
	for light in _street_lights:
		if is_instance_valid(light):
			light.light_energy = 2.2
	for light in _day_lights:
		if is_instance_valid(light):
			light.visible = false
	for light in _ambient_lights:
		if is_instance_valid(light):
			light.visible = true
			light.light_energy = float(_ambient_light_night_energy.get(light, 0.35))
	for node in _night_only_nodes:
		if is_instance_valid(node):
			node.visible = true
			if node is CollisionObject3D:
				(node as CollisionObject3D).collision_layer = 1
				(node as CollisionObject3D).collision_mask = 1
	for node in _day_only_nodes:
		if is_instance_valid(node):
			node.visible = false
			for collision_node in node.find_children("*", "CollisionObject3D", true, false):
				var collision := collision_node as CollisionObject3D
				collision.collision_layer = 0
				collision.collision_mask = 0
	if _mall_building:
		_mall_building.set_night_mode(true)
	if _pedestrian_bridge:
		_pedestrian_bridge.set_night_mode(true)
	hud.screen_flash(Color(0.05, 0.08, 0.15, 0.85), 1.4)


func _build_world() -> void:
	# Sync fallback (tests / tools). Gameplay uses `_build_world_staged`.
	_build_ground_and_street()
	_build_school_building()
	_build_banilad_bridge()
	_build_mall_building()
	_build_neighboring_blocks()
	_build_bus_stop()
	_build_street_lights()
	_build_ambient_lights()
	_build_day_sun_spill()
	_build_tree_line()
	_build_road_traffic()
	_build_caretaker_marker()
	_build_uc_entrance_npc()
	_build_edward_npc()
	_build_mulet_npc()
	_build_jholo_npc()
	_add_inspection_points()
	_add_day_quest_points()
	_add_chapter3_points()
	_add_world_boundaries()


func _build_world_staged() -> void:
	_build_ground_and_street()
	await get_tree().process_frame
	await _build_school_building_async()
	await get_tree().process_frame
	_build_banilad_bridge()
	await get_tree().process_frame
	await _build_mall_building_async()
	await get_tree().process_frame
	_build_neighboring_blocks()
	_build_bus_stop()
	_build_street_lights()
	_build_ambient_lights()
	_build_day_sun_spill()
	await get_tree().process_frame
	_build_tree_line()
	await get_tree().process_frame
	_build_road_traffic()
	_build_caretaker_marker()
	await get_tree().process_frame
	_build_uc_entrance_npc()
	await get_tree().process_frame
	_build_edward_npc()
	await get_tree().process_frame
	_build_mulet_npc()
	await get_tree().process_frame
	_build_jholo_npc()
	await get_tree().process_frame
	_add_inspection_points()
	_add_day_quest_points()
	_add_chapter3_points()
	_add_world_boundaries()


func _build_school_building() -> void:
	_school_building = SchoolBuildingType.new()
	_school_building.name = "UCSchoolBuilding"
	_school_building.rotation.y = PI
	add_child(_school_building)
	_school_building.configure(player)
	_school_building.message_requested.connect(hud.show_message)
	_school_building.elevator_activated.connect(_on_interactable_activated)
	_school_building.build()


func _build_school_building_async() -> void:
	_school_building = SchoolBuildingType.new()
	_school_building.name = "UCSchoolBuilding"
	_school_building.rotation.y = PI
	add_child(_school_building)
	_school_building.configure(player)
	_school_building.message_requested.connect(hud.show_message)
	_school_building.elevator_activated.connect(_on_interactable_activated)
	await _school_building.build_async(get_tree())


func _build_banilad_bridge() -> void:
	_pedestrian_bridge = PedestrianBridgeType.new()
	_pedestrian_bridge.name = "CoveredBaniladPedestrianBridge"
	_pedestrian_bridge.rotation.y = PI
	add_child(_pedestrian_bridge)
	_pedestrian_bridge.build()


func _build_mall_building() -> void:
	_mall_building = MallBuildingType.new()
	_mall_building.name = "GaisanoCountryMall"
	_mall_building.rotation.y = PI
	add_child(_mall_building)
	_mall_building.configure(player)
	_mall_building.message_requested.connect(hud.show_message)
	_mall_building.build()


func _build_mall_building_async() -> void:
	_mall_building = MallBuildingType.new()
	_mall_building.name = "GaisanoCountryMall"
	_mall_building.rotation.y = PI
	add_child(_mall_building)
	_mall_building.configure(player)
	_mall_building.message_requested.connect(hud.show_message)
	await _mall_building.build_async(get_tree())


func _build_bus_stop() -> void:
	# User-supplied shelter on the near sidewalk. Its opening faces north toward
	# Cuenco Road and leaves a clear pedestrian channel to the bridge stairs.
	_bus_stop = BusStopPropType.new()
	_bus_stop.name = "CuencoBusStop"
	_bus_stop.position = Vector3(-29.5, 0.265, 21.0)
	_bus_stop.rotation.y = PI / 2.0
	add_child(_bus_stop)
	_bus_stop.build()
	var shelter_light := OmniLight3D.new()
	shelter_light.name = "BusStopWarmLight"
	shelter_light.position = Vector3(-29.5, 2.35, 21.0)
	shelter_light.light_color = Color("e4c58d")
	shelter_light.light_energy = 0.15
	shelter_light.omni_range = 7.0
	shelter_light.shadow_enabled = false
	add_child(shelter_light)
	_street_lights.append(shelter_light)


func _build_day_sun_spill() -> void:
	# Soft daytime warmth near plaza and mall — no under-bridge fill so deck shadows read.
	for pos in [
		Vector3(0.0, 4.0, -14.0),
		Vector3(0.0, 3.0, 20.0),
		Vector3(-4.0, 4.0, 37.0),
	]:
		var sun := OmniLight3D.new()
		sun.position = pos
		sun.light_color = Color("ffe6b0")
		sun.light_energy = 0.35
		sun.omni_range = 14.0
		sun.shadow_enabled = false
		add_child(sun)
		_day_lights.append(sun)


func _build_ambient_lights() -> void:
	# Night-time mood fills. Keep sparse — each Omni taxes GL Compatibility.
	_add_ambient_omni(Vector3(-30.0, 0.6, -5.0), Color("8a7a55"), 0.4, 12.0)
	_add_ambient_omni(Vector3(0.0, 0.6, -5.0), Color("8a7a55"), 0.4, 12.0)
	_add_ambient_omni(Vector3(30.0, 0.6, -5.0), Color("8a7a55"), 0.4, 12.0)

	_add_ambient_omni(_school_point(Vector3(-12.0, 3.5, -20.5)), Color("5566aa"), 0.45, 14.0)
	_add_ambient_omni(_school_point(Vector3(12.0, 3.5, -20.5)), Color("5566aa"), 0.45, 14.0)

	_add_ambient_omni(_school_point(Vector3(0.0, 2.0, -21.0)), Color("cc9955"), 0.7, 8.0)
	_add_ambient_omni(Vector3(0.0, 1.5, 7.0), Color("667788"), 0.25, 25.0)
	_add_ambient_omni(Vector3(0.0, 2.0, 18.0), Color("7788aa"), 0.3, 12.0)
	_add_ambient_omni(_school_point(Vector3(-5.4, 3.0, -16.7)), Color("ccaa77"), 0.5, 6.0)


func _add_ambient_omni(pos: Vector3, color: Color, energy: float, omni_range: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = omni_range
	light.shadow_enabled = false
	add_child(light)
	_ambient_lights.append(light)
	_ambient_light_night_energy[light] = energy


func _build_scare_manager() -> void:
	_scare_manager = ScareManagerType.new()
	_scare_manager.name = "ScareManager"
	_scare_manager.add_to_group("scare_manager")
	add_child(_scare_manager)
	# Wire references
	_scare_manager.player = player
	_scare_manager.hud = hud
	_scare_manager.world_env = world_environment
	_scare_manager.caretaker = _caretaker_node
	_scare_manager.street_lights = _street_lights
	# Camera shake on scare_triggered signal
	_scare_manager.scare_triggered.connect(func(intensity: float) -> void:
		player.add_trauma(intensity * 0.8)
	)
	_scare_manager.creature_spotted.connect(func() -> void:
		if _story_manager != null and _story_manager.has_method("on_creature_spotted"):
			_story_manager.on_creature_spotted()
	)


func _build_ground_and_street() -> void:
	# Symmetric ground supports the corrected north-mall / south-UC corridor.
	_box("Ground", Vector3(0.0, -0.3, 0.0), Vector3(140.0, 0.6, 190.0), Color("1c211d"))
	_box("Road", Vector3(0.0, 0.02, 7.0), Vector3(120.0, 0.08, 21.0), Color("17191b"), false)
	_box("NearSidewalk", Vector3(0.0, 0.12, 21.0), Vector3(120.0, 0.24, 6.5), Color("3f3e38"))
	_box("FarSidewalk", Vector3(0.0, 0.12, -7.5), Vector3(120.0, 0.24, 7.5), Color("46443e"))
	# Camp Lapu-Lapu Road begins at the north curb and continues through the
	# arched mall connector. Its edge walks remain continuous through the block.
	_box("CampLapuLapuRoad", Vector3(20.0, 0.065, -47.0), Vector3(8.0, 0.09, 87.0), Color("202224"), false)
	_box("CampLapuLapuWestWalk", Vector3(14.8, 0.12, -47.0), Vector3(2.2, 0.20, 87.0), Color("4a4740"))
	_box("CampLapuLapuEastWalk", Vector3(25.2, 0.12, -47.0), Vector3(2.2, 0.20, 87.0), Color("4a4740"))
	for z in range(-85, -6, 8):
		_box("CampRoadCenterMark", Vector3(20.0, 0.12, float(z)), Vector3(0.14, 0.03, 3.6), Color("b7ad82"), false)
	for x in range(-55, 56, 9):
		_box("LaneMark", Vector3(float(x), 0.08, 7.0), Vector3(4.5, 0.03, 0.16), Color("a69b74"), false)
	for x in range(-54, 55, 3):
		var curb_color := Color("b9a72f") if int(x / 3.0) % 2 == 0 else Color("242526")
		_box("CurbPaint", Vector3(float(x), 0.28, -3.9), Vector3(1.5, 0.14, 0.2), curb_color, false)


func _build_commercial_center() -> void:
	var concrete := Color("6b6d6a")
	var dark_concrete := Color("303331")
	var glass := Color("172c35")
	var dirty_white := Color("a4a39a")

	# Visual-only mass — no collision so the entrance is passable
	_box("CenterMass", Vector3(0.0, 12.0, -27.5), Vector3(52.0, 24.0, 9.0), dark_concrete, false)
	_box("LeftTower", Vector3(-24.5, 13.0, -22.75), Vector3(3.0, 26.0, 0.7), dirty_white, false)
	_box("RightTower", Vector3(24.5, 13.0, -22.75), Vector3(3.0, 26.0, 0.7), dirty_white, false)
	_box("RoofLip", Vector3(0.0, 25.2, -23.2), Vector3(52.0, 1.2, 1.0), concrete, false)

	# Only back + side invisible walls so the player can't clip out the back/sides.
	# The entire building FRONT has no collision — player walks freely through the entrance.
	_collision_box("BuildingBack", Vector3(0.0, 6.0, -32.5), Vector3(52.0, 12.0, 0.5))
	_collision_box("BuildingSideL", Vector3(-26.0, 6.0, -27.5), Vector3(0.5, 12.0, 9.0))
	_collision_box("BuildingSideR", Vector3( 26.0, 6.0, -27.5), Vector3(0.5, 12.0, 9.0))

	for floor_index in range(1, 6):
		var y := 5.2 + float(floor_index) * 3.55
		for column in range(12):
			var x := -21.0 + float(column) * 3.82
			_box("Window", Vector3(x, y, -22.91), Vector3(3.3, 2.5, 0.18), glass, false)
		_box("FloorBand", Vector3(0.0, y - 1.55, -22.65), Vector3(47.0, 0.32, 0.65), concrete, false)
		_box("SunShade", Vector3(0.0, y + 0.65, -22.3), Vector3(47.0, 0.16, 1.15), Color("777872"), false)

	for column in range(15):
		var x := -21.6 + float(column) * 3.08
		_box("FacadeFin", Vector3(x, 14.6, -22.15), Vector3(0.12, 17.0, 0.7), Color("777b78"), false)

	_box("GroundFacade", Vector3(0.0, 2.4, -22.7), Vector3(49.0, 4.6, 0.4), Color("202324"), false)


	_box("Entrance", Vector3(0.0, 2.3, -22.15), Vector3(4.8, 4.2, 0.25), Color("0d1618"), false)
	_box("EntranceFrameTop", Vector3(0.0, 4.65, -21.95), Vector3(6.0, 0.35, 0.55), dirty_white, false)
	_box("EntranceFrameLeft", Vector3(-2.8, 2.4, -21.95), Vector3(0.35, 4.8, 0.55), dirty_white, false)
	_box("EntranceFrameRight", Vector3(2.8, 2.4, -21.95), Vector3(0.35, 4.8, 0.55), dirty_white, false)

	var sign_body := _box("CenterSign", Vector3(-19.0, 23.0, -21.95), Vector3(7.0, 2.2, 0.35), Color("243343"), false)
	_add_label_3d(sign_body, "UCB INDAY", 0.015, Color("bec5c5"))


func _build_neighboring_blocks() -> void:
	# Sketch: peaked-roof houses west of UC School (Banilad residential strip)
	var house_spots := [
		Vector3(-36.0, 0.0, 31.0),
		Vector3(-44.0, 0.0, 29.5),
		Vector3(-52.0, 0.0, 32.0),
		Vector3(-40.0, 0.0, 40.0),
		Vector3(-48.0, 0.0, 38.5),
	]
	for i in house_spots.size():
		var p: Vector3 = house_spots[i]
		var w := 5.5 + float(i % 2) * 1.2
		var d := 5.0 + float(i % 3) * 0.4
		var h := 3.2 + float(i % 2) * 0.6
		_box("HouseBody_%d" % i, p + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), Color("8a7a68") if i % 2 == 0 else Color("6e6558"))
		# Peaked roof (two slanted boxes approximated as a ridge)
		_box("HouseRoofA_%d" % i, p + Vector3(0.0, h + 0.9, 0.0), Vector3(w + 0.6, 0.35, d + 0.6), Color("5a3a32"), false)
		_box("HouseRoofPeak_%d" % i, p + Vector3(0.0, h + 1.5, 0.0), Vector3(w * 0.35, 0.9, d * 0.35), Color("4a3028"), false)
		_box("HouseRoofCap_%d" % i, p + Vector3(0.0, h + 0.5, 0.0), Vector3(w + 0.24, 0.16, d + 0.24), Color("4a3028"), false)
		_box("HouseDoor_%d" % i, p + Vector3(0.0, 1.1, d * 0.5 + 0.05), Vector3(1.0, 2.0, 0.12), Color("3a2a22"), false)
		_box("HouseWindow_%d" % i, p + Vector3(-w * 0.28, 1.8, d * 0.5 + 0.05), Vector3(1.2, 1.0, 0.1), Color("88aabc"), false)

	# East commercial mid-rise beyond the flyover
	_box("EastBlock", Vector3(52.0, 5.0, 32.0), Vector3(16.0, 10.0, 14.0), Color("262b2d"))
	for x in [48.0, 54.0]:
		_box("NeighborWindow", Vector3(x, 5.0, 24.9), Vector3(4.5, 2.2, 0.18), Color("14262c"), false)


func _build_road_traffic() -> void:
	# Cuenco Ave runs along X. Nose of GLBs is +X. When a vehicle leaves the
	# visible road strip it wraps to the other end so traffic never "ends".
	const LOOP_MIN_X := -58.0
	const LOOP_MAX_X := 58.0
	var spawns := [
		# eastbound lane (toward flyover / +X)
		{"kind": StreetVehiclePropType.Kind.JEEPNEY, "variant": 0, "x": -40.0, "z": 3.2, "dir": 1.0, "speed": 9.5},
		{"kind": StreetVehiclePropType.Kind.STREET_CAR, "variant": 2, "x": 8.0, "z": 2.6, "dir": 1.0, "speed": 11.0},
		# westbound lane (toward school / -X)
		{"kind": StreetVehiclePropType.Kind.STREET_CAR, "variant": 1, "x": 42.0, "z": 10.8, "dir": -1.0, "speed": 11.5},
		{"kind": StreetVehiclePropType.Kind.JEEPNEY, "variant": 0, "x": 16.0, "z": 11.6, "dir": -1.0, "speed": 9.0},
	]
	for index in spawns.size():
		var spec: Dictionary = spawns[index]
		var vehicle := StreetVehiclePropType.new()
		vehicle.name = "RoadTraffic_%02d" % index
		vehicle.position = Vector3(float(spec["x"]), 0.08, float(spec["z"]))
		var direction: float = float(spec["dir"])
		vehicle.rotation.y = 0.0 if direction > 0.0 else PI
		vehicle.configure(int(spec["kind"]), int(spec["variant"]), false)
		add_child(vehicle)
		vehicle.build()
		_day_only_nodes.append(vehicle)
		_road_traffic.append({
			"node": vehicle,
			"speed": float(spec["speed"]),
			"dir": direction,
			"min_x": LOOP_MIN_X,
			"max_x": LOOP_MAX_X,
			"lane_z": float(spec["z"]),
		})


func _update_road_traffic(delta: float) -> void:
	if _story_manager != null and _story_manager.is_night:
		return
	for data in _road_traffic:
		var vehicle := data["node"] as Node3D
		if not is_instance_valid(vehicle) or not vehicle.visible:
			continue
		var direction: float = float(data["dir"])
		vehicle.position.x += direction * float(data["speed"]) * delta
		var min_x: float = float(data["min_x"])
		var max_x: float = float(data["max_x"])
		if direction > 0.0 and vehicle.position.x > max_x:
			vehicle.position.x = min_x
		elif direction < 0.0 and vehicle.position.x < min_x:
			vehicle.position.x = max_x
		vehicle.position.z = float(data["lane_z"])


func _build_street_lights() -> void:
	for x in [-28.0, -9.0, 10.0, 29.0]:
		_cylinder("LampPost", Vector3(x, 3.4, -5.5), 0.09, 6.8, Color("454844"))
		_box("LampArm", Vector3(x + 0.65, 6.72, -5.5), Vector3(1.3, 0.1, 0.1), Color("454844"), false)
		var light := OmniLight3D.new()
		light.position = Vector3(x + 1.2, 6.55, -5.5)
		light.light_color = Color("e5d7a4")
		light.light_energy = 2.2
		light.omni_range = 11.0
		light.shadow_enabled = false
		add_child(light)
		_street_lights.append(light)


func _build_tree_line() -> void:
	var positions := [
		Vector3(-35.0, 0.25, -7.0), Vector3(-21.0, 0.25, -7.2),
		Vector3(20.0, 0.25, -7.0), Vector3(34.0, 0.25, -7.1),
		Vector3(-47.0, 0.25, 29.0), Vector3(48.0, 0.25, 30.0),
	]
	for index in positions.size():
		var packed := load(TREE_PATHS[index % TREE_PATHS.size()]) as PackedScene
		if packed == null:
			continue
		var tree := packed.instantiate()
		tree.name = "RetroTree_%02d" % index
		tree.position = positions[index]
		tree.rotation.y = float(index) * 1.73
		tree.scale = Vector3.ONE * (1.15 + float(index % 3) * 0.18)
		add_child(tree)
		for mesh_node in tree.find_children("*", "MeshInstance3D", true, false):
			(mesh_node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_collision_box("TreeCollision", positions[index] + Vector3(0.0, 1.1, 0.0), Vector3(0.65, 2.2, 0.65))


func _build_caretaker_marker() -> void:
	# Night scare target only — Mang Berting is not an interactable anymore.
	var marker := Node3D.new()
	marker.name = "Caretaker"
	marker.position = _school_point(Vector3(-5.4, 0.24, -16.7))
	add_child(marker)
	_caretaker_node = marker
	_night_only_nodes.append(marker)


func _build_uc_entrance_npc() -> void:
	if _dialogue_choice_ui == null:
		_dialogue_choice_ui = DialogueChoiceUIType.new()
		_dialogue_choice_ui.name = "DialogueChoiceUI"
		_dialogue_choice_ui.player = player
		add_child(_dialogue_choice_ui)
	var npc := UcKioskNpcType.new()
	npc.name = "UcEntranceKioskNpc"
	npc.build_on_ready = false
	npc.roam_enabled = false
	npc.dialogue_ui = _dialogue_choice_ui
	npc.hud = hud
	npc.position = _school_point(Vector3(2.5, 0.24, -17.8))
	add_child(npc)
	npc.build()
	npc.stand_still()
	npc.look_at(_school_point(Vector3(2.5, 0.24, -14.0)), Vector3.UP)


func _build_edward_npc() -> void:
	# 2F south corridor by Room 201 — standing at the courtyard railing, watching.
	var floor_2f_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F2)
	var spawn_local := Vector3(-17.2, floor_2f_y, SchoolBuildingType.COURT_FRONT + 0.55)
	var court_look_local := Vector3(-17.2, floor_2f_y, SchoolBuildingType.COURT_FRONT - 8.0)
	if _dialogue_choice_ui == null:
		_dialogue_choice_ui = DialogueChoiceUIType.new()
		_dialogue_choice_ui.name = "DialogueChoiceUI"
		_dialogue_choice_ui.player = player
		add_child(_dialogue_choice_ui)
	var edward := EdwardNpcPropType.new()
	edward.name = "EdwardNpc"
	edward.build_on_ready = false
	edward.roam_enabled = false
	edward.lean_on_rail = false
	edward.lean_on_wall = false
	edward.target_height = 2.15
	edward.face_courtyard_on_spawn = true
	edward.dialogue_ui = _dialogue_choice_ui
	edward.hud = hud
	edward.position = _school_point(spawn_local)
	edward.courtyard_look_target = _school_point(court_look_local)
	add_child(edward)
	edward.build()
	if not edward.get_visual_model():
		push_error("EdwardNpc failed to build — check res://assets/npcs/edward.glb import")
		edward.queue_free()
		return
	_day_only_nodes.append(edward)


func _build_mulet_npc() -> void:
	# 2F south courtyard railing — watching the court, won't share answers.
	var floor_2f_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F2)
	var spawn_local := Vector3(-14.6, floor_2f_y, SchoolBuildingType.COURT_FRONT + 0.55)
	var court_look_local := Vector3(-14.6, floor_2f_y, SchoolBuildingType.COURT_FRONT - 8.0)
	if _dialogue_choice_ui == null:
		_dialogue_choice_ui = DialogueChoiceUIType.new()
		_dialogue_choice_ui.name = "DialogueChoiceUI"
		_dialogue_choice_ui.player = player
		add_child(_dialogue_choice_ui)
	var mulet := MuletNpcPropType.new()
	mulet.name = "MuletNpc"
	mulet.build_on_ready = false
	mulet.target_height = 1.9
	mulet.dialogue_ui = _dialogue_choice_ui
	mulet.hud = hud
	mulet.position = _school_point(spawn_local)
	mulet.face_look_target = _school_point(court_look_local)
	add_child(mulet)
	mulet.build()
	if not mulet.get_visual_model():
		push_error("MuletNpc failed to build — check res://assets/npcs/mulet.glb import")
		mulet.queue_free()
		return
	_day_only_nodes.append(mulet)


func _build_jholo_npc() -> void:
	# 2F Room 201 (first south classroom) — boxing in the room, talk about capstone.
	var floor_2f_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F2)
	# Clear floor near the corridor door (west of the chair block).
	var room_spot := Vector3(-21.2, floor_2f_y, -31.2)
	var door_look := Vector3(-22.4, floor_2f_y, SchoolBuildingType.SOUTH_ROOM_WALL_Z)
	if _dialogue_choice_ui == null:
		_dialogue_choice_ui = DialogueChoiceUIType.new()
		_dialogue_choice_ui.name = "DialogueChoiceUI"
		_dialogue_choice_ui.player = player
		add_child(_dialogue_choice_ui)
	var jholo := JholoNpcPropType.new()
	jholo.name = "JholoNpc"
	jholo.build_on_ready = false
	jholo.target_height = 1.85
	jholo.dialogue_ui = _dialogue_choice_ui
	jholo.hud = hud
	jholo.position = _school_point(room_spot)
	jholo.face_look_target = _school_point(door_look)
	add_child(jholo)
	jholo.build()
	if not jholo.get_visual_model():
		push_error("JholoNpc failed to build — check res://assets/npcs/jholo.glb import")
		jholo.queue_free()
		return
	_day_only_nodes.append(jholo)


func _add_inspection_points() -> void:
	_night_only_nodes.append(_add_inspection_point(
		&"fuse_box", "Inspect fuse box · GF · South facade", _school_point(Vector3(-18.0, 1.2, -21.65)),
		Vector3(0.9, 1.4, 0.25), Color("525b54"),
		"FUSE BOX (Ground / school front): Warm to the touch. The elevator circuit is drawing power — it was decommissioned in 1995."
	))
	_night_only_nodes.append(_add_inspection_point(
		&"payphone", "Check payphone · Street · Near Banilad flyover", Vector3(30.0, 1.25, -8.2),
		Vector3(0.75, 1.4, 0.45), Color("304d50"),
		"PAYPHONE (Street / near flyover): No dial tone. The cord is cut. Something breathes on the other end. A whisper: 'Naa ko diri.'"
	))
	_night_only_nodes.append(_add_inspection_point(
		&"dead_tree", "Inspect dead tree · Campus · West tree line", Vector3(-47.0, 1.15, 29.0),
		Vector3(0.5, 0.55, 0.5), Color("6f5138"),
		"DEAD TREE (Ground / west trees): Died in November 1994. Fresh soil at the roots. Small barefoot prints lead to the entrance — none lead away."
	))


func _add_day_quest_points() -> void:
	# Chapter 1 daytime campus errands
	_add_ground_floor_locker()
	_add_inspection_point(
		&"day_registrar", "Submit clearance · GF · Guard post (front wing)", _school_point(Vector3(-15.9, 1.05, -27.2)),
		Vector3(1.4, 1.1, 0.7), Color("8a7a55"),
		"GUARD POST (Ground / front wing): Clearance stamped. The stamp tray is empty — no one is at the desk."
	)


func _add_chapter3_points() -> void:
	var floor_2f_y := SchoolBuildingType.level_y(SchoolBuildingType.Level.F2)
	var south_corridor_wall_z: float = SchoolBuildingType.SOUTH_ROOM_WALL_Z
	var elevator_x: float = SchoolBuildingType.ELEVATOR_DOOR_X

	var locker := get_node_or_null("DayLocker") as Node3D
	var bag_parent: Node = locker if locker else self
	var bag := _add_chapter3_point(
		&"ch3_bag",
		"Take USB · GF · Locker wing",
		_school_point(Vector3(-12.0, 1.52, -21.60)) if locker == null else Vector3(0.0, 1.28, 0.5),
		Vector3(0.22, 0.12, 0.08),
		Color("2a4a6a"),
		"USB (GF / locker wing): Cold metal. A sticky note stuck to it: \"Inday was here. Floor 8.\"",
		bag_parent
	)
	_night_only_nodes.append(bag)

	_night_only_nodes.append(_add_chapter3_point(
		&"ch3_note",
		"Read note · 2F · South corridor",
		_school_point(Vector3(-5.0, floor_2f_y + 1.35, south_corridor_wall_z - 0.11)),
		Vector3(0.42, 0.5, 0.08),
		Color("d4cbb8"),
		"NOTE (2F / south corridor near 202): \"Dili pa ko ready umuli. Wait for me by the bridge.\" — I."
	))

	_night_only_nodes.append(_add_chapter3_point(
		&"ch3_elevator",
		"Check elevator · GF · Lobby core (stuck on 8F)",
		_school_point(Vector3(elevator_x, 2.55, south_corridor_wall_z - 0.12)),
		Vector3(1.0, 0.55, 0.12),
		Color("1a1c1e"),
		"ELEVATOR (GF / lobby core): Display stuck on Floor 8. Soft ding. The doors breathe open a finger-width, then seal."
	))


func _add_chapter3_point(
	id: StringName,
	prompt: String,
	position_value: Vector3,
	size: Vector3,
	color: Color,
	message: String,
	parent: Node = null
) -> StaticBody3D:
	var object := _add_inspection_point(id, prompt, position_value, size, color, message, false, parent)
	_register_quest_glow(id, object, color)
	return object


func _register_quest_glow(id: StringName, object: Node3D, color: Color) -> void:
	var mesh_instance: MeshInstance3D = null
	for child in object.get_children():
		if child is MeshInstance3D:
			mesh_instance = child as MeshInstance3D
			break
	if mesh_instance == null:
		return

	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = color.lerp(Color("ffd27a"), 0.4)
	glow_material.emission_enabled = true
	glow_material.emission = Color("ffb84d")
	glow_material.emission_energy_multiplier = 2.0

	_quest_glow_targets[id] = {
		"mesh": mesh_instance,
		"base_material": mesh_instance.material_override,
		"glow_material": glow_material,
	}


func _update_quest_highlights() -> void:
	if _story_manager == null:
		return
	if _story_manager.is_horror_mode:
		for quest_id in _quest_glow_targets.keys():
			var entry: Dictionary = _quest_glow_targets[quest_id]
			var mesh: MeshInstance3D = entry["mesh"]
			if is_instance_valid(mesh):
				mesh.material_override = entry["base_material"]
		return
	var active_id: StringName = _story_manager.get_active_quest_id()
	for quest_id in _quest_glow_targets.keys():
		var entry: Dictionary = _quest_glow_targets[quest_id]
		var mesh: MeshInstance3D = entry["mesh"]
		if not is_instance_valid(mesh):
			continue
		mesh.material_override = entry["glow_material"] if quest_id == active_id else entry["base_material"]


func _add_ground_floor_locker() -> StaticBody3D:
	# The supplied locker replaces the old procedural box. Its front faces +Z,
	# toward the entry plaza, and its back sits flush with the school facade.
	var locker: StaticBody3D = InteractableType.new()
	locker.name = "DayLocker"
	locker.position = _school_point(Vector3(-12.0, 0.24, -22.10))
	locker.setup(
		&"day_locker",
		"Check your locker · GF · School front (exterior)",
		"LOCKER (GF / school front): You stash tomorrow's handouts. USB drive stays in the top slot — you'll grab it later.",
		true
	)
	locker.activated.connect(_on_interactable_activated)
	add_child(locker)

	var prop = OldLockerPropType.new()
	prop.name = "OldLockerModel"
	prop.attach_to_interactable(locker)

	var indicator := OmniLight3D.new()
	indicator.name = "LockerIndicator"
	indicator.position = Vector3(0.0, 1.48, 0.42)
	indicator.light_color = Color("a87532")
	indicator.light_energy = 0.45
	indicator.omni_range = 2.2
	locker.add_child(indicator)
	return locker


func _add_inspection_point(
	id: StringName,
	prompt: String,
	position_value: Vector3,
	size: Vector3,
	color: Color,
	message: String,
	with_indicator: bool = true,
	parent: Node = null
) -> StaticBody3D:
	var object: StaticBody3D = InteractableType.new()
	object.name = String(id).to_pascal_case()
	object.position = position_value
	object.setup(id, prompt, message, true)
	object.activated.connect(_on_interactable_activated)
	(parent if parent != null else self).add_child(object)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	object.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	object.add_child(collision)

	if with_indicator:
		var indicator := OmniLight3D.new()
		indicator.position = Vector3(0.0, size.y * 0.35, 0.35)
		indicator.light_color = Color("a87532")
		indicator.light_energy = 0.45
		indicator.omni_range = 2.2
		object.add_child(indicator)
	return object


func _on_interactable_activated(id: StringName, message: String) -> void:
	var id_str = str(id)
	if id_str.begins_with("elevator_call_"):
		_elevator_ui.open()
		return
	if id_str.begins_with("battery_"):
		player.add_battery(35.0)
		var battery_pickup := get_node_or_null(NodePath(String(id).to_pascal_case()))
		if battery_pickup != null:
			battery_pickup.set_meta("collected", true)
			battery_pickup.visible = false
		return
	if id_str.begins_with("key_"):
		player.add_key(StringName(id_str.trim_prefix("key_")))
		return
	if id_str.begins_with("vhs_") and id != &"vhs_tv":
		var tape_data := _vhs_tape_data(id)
		if _vhs_system.collect_tape(id, tape_data[0], tape_data[1]):
			hud.show_message("VHS COLLECTED  //  %s" % tape_data[0], 4.0)
		var tape_pickup := get_node_or_null(NodePath(String(id).to_pascal_case()))
		if tape_pickup != null:
			tape_pickup.visible = false
		if _story_manager != null and _story_manager.is_horror_mode:
			_story_manager.refresh_objective()
		return
	if id == &"vhs_tv":
		if _vhs_system.tape_count() <= 0:
			hud.show_message("The VCR is empty. Find a VHS tape.", 3.0)
		else:
			_vhs_system.open_archive()
		return

	# Story chapters own quest interactables
	if _story_manager:
		var story_consumed: bool = await _story_manager.on_interactable(id, message)
		if story_consumed:
			return

	hud.show_message(message, 5.0)
	if id == &"caretaker" or _inspected.has(id):
		return
	_inspected[id] = true


func _vhs_tape_data(id: StringName) -> Array[String]:
	match id:
		&"vhs_1": return ["TAPE 01 // Guard Post", "CCTV 1998: empty corridors. At 02:34, a shadow crosses the frame without opening a door."]
		&"vhs_2": return ["TAPE 02 // Lab Interview", "A student whispers about footsteps above Room 204 after midnight."]
		&"vhs_3": return ["TAPE 03 // Janitor", "Shaky footage from a CR stall: a tall shape waits outside the door."]
		&"vhs_4": return ["TAPE 04 // News Report", "MISSING STUDENT. Last seen heading toward Floor 8."]
		&"vhs_5": return ["TAPE 05 // Security", "The creature fills the frame for one second, then the tape tears into static."]
		_: return ["TAPE 06 // Foundation", "Construction footage: workers uncover something beneath the building and cover it again."]


func _on_elevator_floor_selected(floor_index: int) -> void:
	hud.show_message("ELEVATOR: %s" % SchoolBuildingType.level_name(floor_index), 2.0)

	# Teleport player onto the open-air ring corridor outside the elevator.
	player.global_position = _school_point(SchoolBuildingType.elevator_landing_local(floor_index))
	player.velocity = Vector3.ZERO
	if _story_manager != null and _story_manager.has_method("on_floor_entered"):
		_story_manager.on_floor_entered(floor_index + 1)


func _add_world_boundaries() -> void:
	_collision_box("NorthBoundary", Vector3(0.0, 3.0, -94.0), Vector3(140.0, 6.0, 1.0))
	_collision_box("SouthBoundary", Vector3(0.0, 3.0, 94.0), Vector3(140.0, 6.0, 1.0))
	_collision_box("WestBoundary", Vector3(-69.0, 3.0, 0.0), Vector3(1.0, 6.0, 188.0))
	_collision_box("EastBoundary", Vector3(69.0, 3.0, 0.0), Vector3(1.0, 6.0, 188.0))


func _box(
	object_name: String,
	position_value: Vector3,
	size: Vector3,
	color: Color,
	with_collision: bool = true,
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
		mesh_instance.position = position_value
		parent.add_child(mesh_instance)
		return mesh_instance

	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position_value
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
	rotation_value: Vector3 = Vector3.ZERO,
	with_collision: bool = true
) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	mesh_instance.rotation = rotation_value

	if not with_collision:
		mesh_instance.name = object_name
		mesh_instance.position = position_value
		add_child(mesh_instance)
		return mesh_instance

	var body := StaticBody3D.new()
	body.name = object_name
	body.position = position_value
	add_child(body)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.rotation = rotation_value
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


func _character_part(
	parent: Node,
	part_name: String,
	position_value: Vector3,
	size: Vector3,
	color: Color,
	rotation_value: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = position_value
	part.rotation = rotation_value
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = _material(color)
	parent.add_child(part)
	return part


func _low_poly_sphere(
	object_name: String,
	position_value: Vector3,
	radius: float,
	color: Color,
	parent: Node
) -> MeshInstance3D:
	var sphere := MeshInstance3D.new()
	sphere.name = object_name
	sphere.position = position_value
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	sphere.mesh = mesh
	sphere.material_override = _material(color)
	parent.add_child(sphere)
	return sphere


func _material(color: Color) -> ShaderMaterial:
	var key := color.to_html(false)
	if _material_cache.has(key):
		return _material_cache[key]
	var material := ShaderMaterial.new()
	material.shader = PSX_SHADER
	material.set_shader_parameter("albedo_color", color)
	_material_cache[key] = material
	return material


func _shop_color(index: int) -> Color:
	var colors := [Color("70332f"), Color("314c52"), Color("4d4b2d"), Color("4c354a"), Color("2f4c39")]
	return colors[index % colors.size()]


func _add_label_3d(parent: Node3D, text: String, pixel_size: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = pixel_size
	label.font_size = 48
	label.modulate = color
	label.outline_size = 8
	label.position = Vector3(0.0, 0.0, 0.25)
	parent.add_child(label)


# ══════════════════════════════════════════════════════════════════════════════
#  BUILDING INTERIOR — Abandoned UCB lobby, pharmacy, hallway, elevator
# ══════════════════════════════════════════════════════════════════════════════

func _build_interior() -> void:
	# Interior bounds: x = -25 to 25, z = -23 to -32, ground floor y = 0 to 4.8
	var floor_y := 0.05
	var ceil_y := 4.8
	var front_z := -23.2   # just behind the facade
	var back_z := -32.0
	var depth := absf(back_z - front_z)     # ~8.8
	var mid_z := (front_z + back_z) / 2.0   # ~-27.6

	var wall_dark := Color("2a2c2b")
	var wall_mid := Color("3a3d3b")
	var floor_tile := Color("2e302d")
	var ceil_color := Color("353733")
	var desk_color := Color("4a3d2c")
	var metal := Color("4e5250")
	var rust := Color("5c3c2a")
	var elevator_color := Color("1a1c1e")
	var blood_stain := Color("3a1515")
	var pharmacy_green := Color("2a4a3a")

	# ── Floor & Ceiling ─────────────────────────────────────────────────────
	_box("LobbyFloor", Vector3(0.0, floor_y, mid_z), Vector3(50.0, 0.1, depth), floor_tile)
	_box("LobbyCeiling", Vector3(0.0, ceil_y, mid_z), Vector3(50.0, 0.12, depth), ceil_color, false)

	# ── Interior back wall (visible, no extra collision — BuildingBack handles it) ─
	_box("InteriorBackWall", Vector3(0.0, ceil_y / 2.0, back_z + 0.1), Vector3(50.0, ceil_y, 0.2), wall_dark, false)

	# ── Interior side walls (visible) ────────────────────────────────────────
	_box("InteriorWallL", Vector3(-25.0, ceil_y / 2.0, mid_z), Vector3(0.2, ceil_y, depth), wall_mid, false)
	_box("InteriorWallR", Vector3(25.0, ceil_y / 2.0, mid_z), Vector3(0.2, ceil_y, depth), wall_mid, false)

	# ── Central hallway divider walls (creates left wing + hallway + right wing) ──
	# Left divider wall: from x = -25 to x = -3 (leaves hallway gap -3 to 3)
	_box("DividerWallL", Vector3(-14.0, ceil_y / 2.0, -27.0), Vector3(22.0, ceil_y, 0.2), wall_mid)
	# Right divider wall: from x = 3 to x = 25
	_box("DividerWallR", Vector3(14.0, ceil_y / 2.0, -27.0), Vector3(22.0, ceil_y, 0.2), wall_mid)

	# ══ LEFT WING — Pharmacy (Inday's workplace) ════════════════════════════

	# Pharmacy counter
	_box("PharmCounter", Vector3(-15.0, 0.55, -25.5), Vector3(8.0, 1.1, 0.7), pharmacy_green)
	_box("PharmCounterTop", Vector3(-15.0, 1.15, -25.5), Vector3(8.4, 0.08, 0.85), Color("3d5248"), false)

	# Pharmacy shelves on back wall
	for i in range(4):
		var sx := -20.0 + float(i) * 3.2
		_box("PharmShelf", Vector3(sx, 2.8, -31.5), Vector3(2.6, 0.12, 0.55), desk_color, false)
		_box("PharmShelf", Vector3(sx, 1.8, -31.5), Vector3(2.6, 0.12, 0.55), desk_color, false)
		# Bottles on shelves (small boxes)
		for j in range(3):
			var bx := sx - 0.7 + float(j) * 0.7
			_box("Bottle", Vector3(bx, 2.0, -31.45), Vector3(0.2, 0.35, 0.2), Color("4a6355"), false)
			_box("Bottle", Vector3(bx, 3.0, -31.45), Vector3(0.18, 0.3, 0.18), Color("5a4a3a"), false)

	# Inday's name tag — on the counter
	var tag := _box("IndayNameTag", Vector3(-15.0, 1.22, -25.25), Vector3(0.6, 0.01, 0.25), Color("d4cbb8"), false)
	_add_label_3d(tag, "INDAY\nPHARMACY", 0.003, Color("2a2a2a"))

	# Knocked-over stool behind counter
	_box("FallenStool", Vector3(-13.0, 0.22, -26.2), Vector3(0.4, 0.4, 0.4), desk_color, false)

	# ══ RIGHT WING — Guard / Reception area ══════════════════════════════════

	# Guard desk
	_box("GuardDesk", Vector3(12.0, 0.45, -25.0), Vector3(3.2, 0.9, 1.4), desk_color)
	_box("GuardDeskTop", Vector3(12.0, 0.95, -25.0), Vector3(3.4, 0.08, 1.55), Color("5a4d3c"), false)

	# Logbook on desk
	_box("Logbook", Vector3(12.3, 1.02, -24.8), Vector3(0.5, 0.04, 0.35), Color("5c4832"), false)

	# Calendar on the wall — frozen on November 1994
	var cal := _box("Calendar", Vector3(18.0, 2.4, -31.7), Vector3(0.55, 0.7, 0.04), Color("c8c0aa"), false)
	_add_label_3d(cal, "NOV\n1994", 0.004, Color("3a2222"))

	# Waiting bench
	_box("WaitBench", Vector3(18.0, 0.35, -24.5), Vector3(3.5, 0.35, 0.6), desk_color)
	_box("WaitBenchBack", Vector3(18.0, 0.8, -24.82), Vector3(3.5, 0.6, 0.08), desk_color, false)

	# Old CRT monitor on guard desk (turned off)
	_box("CRTBody", Vector3(11.2, 1.3, -25.3), Vector3(0.6, 0.5, 0.5), Color("2a2a28"), false)
	_box("CRTScreen", Vector3(11.2, 1.32, -25.02), Vector3(0.48, 0.38, 0.02), Color("0a0c0b"), false)

	# Scattered chairs
	_box("Chair1", Vector3(9.5, 0.35, -25.8), Vector3(0.5, 0.7, 0.5), metal, false)
	_box("Chair2", Vector3(20.5, 0.35, -25.0), Vector3(0.5, 0.7, 0.5), metal, false)

	# ══ CENTRAL HALLWAY — leads to elevator ══════════════════════════════════

	# Hallway floor runner (darker strip)
	_box("HallRunner", Vector3(0.0, 0.08, -29.5), Vector3(4.0, 0.04, 5.0), Color("222420"), false)

	# Numbered doors along hallway walls (decorative)
	for i in range(3):
		var dz := -28.0 - float(i) * 1.6
		# Left door
		_box("DoorL", Vector3(-2.85, 1.2, dz), Vector3(0.08, 2.4, 0.9), Color("4a3828"), false)
		var dl := _box("DoorNumL", Vector3(-2.78, 1.9, dz), Vector3(0.02, 0.2, 0.2), Color("8a7a5a"), false)
		_add_label_3d(dl, str(201 + i), 0.003, Color("c8b888"))
		# Right door
		_box("DoorR", Vector3(2.85, 1.2, dz), Vector3(0.08, 2.4, 0.9), Color("4a3828"), false)
		var dr := _box("DoorNumR", Vector3(2.78, 1.9, dz), Vector3(0.02, 0.2, 0.2), Color("8a7a5a"), false)
		_add_label_3d(dr, str(101 + i), 0.003, Color("c8b888"))

	# Wet floor stain (dark patch — looks ominous)
	_box("FloorStain", Vector3(0.5, 0.07, -29.0), Vector3(1.2, 0.02, 1.5), blood_stain, false)

	# ══ ELEVATOR — at the far end of the hallway ═════════════════════════════

	# Elevator shaft recess (dark alcove)
	_box("ElevShaftBack", Vector3(0.0, ceil_y / 2.0, -31.8), Vector3(2.6, ceil_y, 0.3), elevator_color, false)
	_box("ElevShaftL", Vector3(-1.2, ceil_y / 2.0, -31.0), Vector3(0.15, ceil_y, 2.0), elevator_color, false)
	_box("ElevShaftR", Vector3(1.2, ceil_y / 2.0, -31.0), Vector3(0.15, ceil_y, 2.0), elevator_color, false)

	# Elevator doors (closed, slightly rusted)
	_box("ElevDoorL", Vector3(-0.52, 1.2, -30.05), Vector3(0.98, 2.4, 0.08), rust)
	_box("ElevDoorR", Vector3(0.52, 1.2, -30.05), Vector3(0.98, 2.4, 0.08), rust)

	# Elevator door frame
	_box("ElevFrameTop", Vector3(0.0, 2.55, -30.0), Vector3(2.4, 0.15, 0.12), metal, false)
	_box("ElevFrameL", Vector3(-1.1, 1.2, -30.0), Vector3(0.12, 2.55, 0.12), metal, false)
	_box("ElevFrameR", Vector3(1.1, 1.2, -30.0), Vector3(0.12, 2.55, 0.12), metal, false)

	# Floor indicator above elevator (stuck on "4")
	var elev_indicator := _box("ElevIndicator", Vector3(0.0, 2.85, -30.0), Vector3(0.5, 0.3, 0.06), Color("0a0a08"), false)
	_add_label_3d(elev_indicator, "▲ 4", 0.004, Color("cc5533"))

	# Rubber slippers — on the floor in front of the elevator
	_box("SlipperL", Vector3(-0.15, 0.04, -29.6), Vector3(0.12, 0.03, 0.28), Color("c44a3a"), false)
	_box("SlipperR", Vector3(0.15, 0.04, -29.7), Vector3(0.12, 0.03, 0.28), Color("c44a3a"), false)

	# ══ LIGHTING — dim, flickering, abandoned ═════════════════════════════════

	# Main lobby overhead (dim)
	var lobby_light := OmniLight3D.new()
	lobby_light.position = Vector3(0.0, 4.2, -25.0)
	lobby_light.light_color = Color("d4c89a")
	lobby_light.light_energy = 1.2
	lobby_light.omni_range = 14.0
	lobby_light.shadow_enabled = false
	add_child(lobby_light)

	# Pharmacy area light (greenish, faint)
	var pharm_light := OmniLight3D.new()
	pharm_light.position = Vector3(-15.0, 4.0, -26.0)
	pharm_light.light_color = Color("8aaa8a")
	pharm_light.light_energy = 0.6
	pharm_light.omni_range = 10.0
	pharm_light.shadow_enabled = false
	add_child(pharm_light)

	# Hallway light — flickers (managed by a simple timer tween)
	var hall_light := OmniLight3D.new()
	hall_light.name = "HallwayFlicker"
	hall_light.position = Vector3(0.0, 4.0, -29.5)
	hall_light.light_color = Color("ccbb88")
	hall_light.light_energy = 1.4
	hall_light.omni_range = 8.0
	hall_light.shadow_enabled = false
	add_child(hall_light)
	_start_flicker(hall_light)

	# Elevator alcove — eerie orange glow
	var elev_light := OmniLight3D.new()
	elev_light.position = Vector3(0.0, 3.5, -31.0)
	elev_light.light_color = Color("cc7744")
	elev_light.light_energy = 0.8
	elev_light.omni_range = 5.0
	elev_light.shadow_enabled = false
	add_child(elev_light)
	_start_flicker(elev_light)

	# Ceiling light fixtures (visual tubes)
	for lx in [-8.0, 8.0]:
		_box("CeilFixture", Vector3(lx, 4.6, -25.0), Vector3(1.8, 0.08, 0.12), Color("888880"), false)
	_box("CeilFixtureHall", Vector3(0.0, 4.6, -29.5), Vector3(1.2, 0.08, 0.12), Color("888880"), false)


## Makes a light flicker on and off forever — simple looping approach.
func _start_flicker(light: OmniLight3D) -> void:
	var base_energy := light.light_energy
	var timer := Timer.new()
	timer.wait_time = 0.08
	timer.autostart = true
	light.add_child(timer)
	timer.timeout.connect(func() -> void:
		if randf() < 0.35:
			light.light_energy = 0.0
			timer.wait_time = randf_range(0.04, 0.18)
		else:
			light.light_energy = base_energy * randf_range(0.7, 1.0)
			timer.wait_time = randf_range(0.06, 0.4)
	)
