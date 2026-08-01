extends Node3D
## Banilad free-roam map, built from OpenStreetMap geometry of the real
## Gov. M. Cuenco Avenue corridor. Reuses the CBlock third-person controller.
## Press C in-game to open the character picker.

const MENU_SCENE := "res://main_menu.tscn"
const LANDMARK_DATA := "res://assets/maps/banilad_landmarks.json"
const CharacterRoster := preload("res://scripts/cblock_character_roster.gd")
# Preloaded rather than referenced by class_name: headless `--script` runs load
# this before the global class cache exists, and the bare name fails to parse.
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const DialogueChoiceUIScript := preload("res://scripts/dialogue_choice_ui.gd")
const MuletNpcPropScript := preload("res://scripts/mulet_npc_prop.gd")
const JholoNpcPropScript := preload("res://scripts/jholo_npc_prop.gd")
const EdwardNpcPropScript := preload("res://scripts/edward_npc_prop.gd")
const CBlockEdwardScene := preload("res://assets/npcs/cblock_edward_npc.tscn")
const DrivableVehicleScript := preload("res://scripts/vehicle_body.gd")
const CountryMallAsset := preload("res://assets/buildings/gaisano_country_mall.glb")

# The scanned mall replaces the procedural wings. Its covered walkway is a
# separate object in the map GLB (Mall_Walkway) precisely so it survives this.
const PROCEDURAL_MALL_NODE := "Gaisano Country Mall"
# banilad_map/build_mall.py builds the mall at absolute map coordinates from
# the surveyed OSM footprints, so it instances at the origin: no scale, no
# rotation, and it is already sitting on z = 0 like the rest of the map.
const MALL_CENTRE := Vector3.ZERO
const MALL_SCALE := 1.0
const MALL_YAW_DEGREES := 0.0
# Where to probe for the ground. The asset instances at the origin, but the
# building itself stands over here, so this is the spot that has to be level
# with its base.
const MALL_GROUND_PROBE := Vector2(-104.6, -568.4)

# Gov. M. Cuenco Ave runs at bearing 80.7 degrees, which is this heading in
# Godot: nose down the avenue, away from Gaisano.
const AVENUE_YAW := -0.162
const AVENUE_FORWARD := Vector3(0.161, 0.0, -0.987)

# On Gov. M. Cuenco Avenue, roughly 120 m south of Gaisano Country Mall.
const SPAWN_POSITION := Vector3(12.79, 1.2, -554.24)
# Fallback if a ground ray misses (sidewalk top ≈ 0.30 m).
const NPC_GROUND_Y := 0.28
# Capsule half-height for the Mixamo CharacterBody walker (height 1.8).
const WALKER_BODY_HALF_HEIGHT := 0.9

# Anything below this has fallen through the world.
const FALL_LIMIT := -20.0

# How close the player must be for a landmark to be called out.
const LANDMARK_RANGE := 90.0

@onready var player: CharacterBody3D = $Player
@onready var camera_rig: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var hud: CanvasLayer = $HUD
@onready var prompt_label: Label = $HUD/Prompt
@onready var interact_label: Label = $HUD/Interact
@onready var message_label: Label = $HUD/Message
@onready var help_label: Label = $HUD/TopBar/Help

var _landmarks: Array = []
var _nearest_name := ""
var _message_generation := 0
var _scan_accumulator := 0.0
var _pause_menu: PauseMenuScript
var _dialogue_ui: CanvasLayer = null
var _picker_open := false
var _picker_overlay: ColorRect
var _character_buttons: Dictionary = {}
var _selected_preview_id := ""
var _vehicles: Array = []
var _active_vehicle = null


func _ready() -> void:
	Engine.max_fps = 60
	CharacterRoster.load_saved()
	if hud.has_method("bind_host"):
		hud.call("bind_host", self)
	_load_landmarks()
	if player.has_signal("status_message"):
		player.status_message.connect(_show_message)
	if player.has_signal("prompt_changed"):
		player.prompt_changed.connect(_set_interact_prompt)
	_build_dialogue_ui()
	_build_character_picker()
	_build_pause_menu()
	_refresh_help_text()
	_respawn()
	_set_prompt("")
	_set_interact_prompt("")
	_show_message("BANILAD  //  Gov. M. Cuenco Avenue, Cebu City", 5.0)
	# Wait for the map colliders to register, then plant NPCs on the sidewalk.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _place_country_mall()
	_spawn_street_npcs()
	_spawn_vehicles()


## Swaps the procedural mall wings for the scanned asset.
##
## Nothing here assumes where the asset's origin sits. It is dropped at the
## footprint centre and then shifted by the difference between its own lowest
## vertex and the ground, so it lands on the road surface rather than hovering
## over it or sinking into it, whatever the exporter chose for the origin.
func _place_country_mall() -> void:
	var procedural := find_child(PROCEDURAL_MALL_NODE, true, false) as Node3D
	if procedural == null:
		push_warning("procedural mall '%s' not found; skipping the swap" % PROCEDURAL_MALL_NODE)
		return
	# Hide it *and* take its collision out, or the ground probe below would
	# find the old roof and stack the new mall on top of it.
	procedural.visible = false
	for body in procedural.find_children("*", "StaticBody3D", true, false):
		for shape in body.find_children("*", "CollisionShape3D", true, false):
			(shape as CollisionShape3D).disabled = true
	await get_tree().physics_frame

	var mall := CountryMallAsset.instantiate() as Node3D
	mall.name = "GaisanoCountryMallAsset"
	mall.scale = Vector3.ONE * MALL_SCALE
	mall.rotation.y = deg_to_rad(MALL_YAW_DEGREES)
	add_child(mall)

	var ground_y := _raycast_ground_y(MALL_GROUND_PROBE.x, MALL_GROUND_PROBE.y)
	mall.global_position = Vector3(MALL_CENTRE.x, ground_y, MALL_CENTRE.z)
	var lowest := _lowest_visual_point(mall)
	if is_finite(lowest):
		mall.global_position.y += ground_y - lowest

	for node in mall.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).create_trimesh_collision()

	print("BANILAD_MALL_PLACED ground=%.3f base_offset=%.3f final_y=%.3f" % [
		ground_y, ground_y - lowest, mall.global_position.y,
	])


## Lowest point of every mesh the node owns, in world space.
func _lowest_visual_point(root_node: Node3D) -> float:
	var lowest := INF
	for node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var bounds := mesh_instance.get_aabb()
		var to_world := mesh_instance.global_transform
		for corner in 8:
			lowest = minf(lowest, (to_world * bounds.get_endpoint(corner)).y)
	return lowest


## Parked on the carriageway just down the avenue from the spawn, so the first
## thing in front of the player is something they can drive.
func _spawn_vehicles() -> void:
	var layout := [
		{"kind": DrivableVehicleScript.Kind.STREET_CAR, "variant": 0, "along": 9.0, "side": 2.6},
		{"kind": DrivableVehicleScript.Kind.STREET_CAR, "variant": 2, "along": 26.0, "side": -3.0},
		{"kind": DrivableVehicleScript.Kind.JEEPNEY, "variant": 0, "along": 44.0, "side": 2.4},
	]
	var right := Vector3(cos(AVENUE_YAW), 0.0, -sin(AVENUE_YAW))
	for index in layout.size():
		var entry: Dictionary = layout[index]
		var spot := (
			SPAWN_POSITION
			+ AVENUE_FORWARD * float(entry["along"])
			+ right * float(entry["side"])
		)
		var vehicle = DrivableVehicleScript.new()
		vehicle.build_on_ready = false
		vehicle.kind = entry["kind"]
		vehicle.variant_index = int(entry["variant"])
		# Dropped a little high so the suspension settles it onto the road.
		vehicle.position = Vector3(spot.x, _raycast_ground_y(spot.x, spot.z) + 0.55, spot.z)
		vehicle.rotation.y = AVENUE_YAW
		add_child(vehicle)
		vehicle.build()
		vehicle.name = "BaniladVehicle%d" % index
		vehicle.enter_requested.connect(_on_vehicle_enter_requested.bind(vehicle))
		_vehicles.append(vehicle)


func _on_vehicle_enter_requested(_who: Node, vehicle) -> void:
	_enter_vehicle(vehicle)


func _enter_vehicle(vehicle) -> void:
	if _active_vehicle != null or vehicle == null:
		return
	_active_vehicle = vehicle
	player.set_stowed(true)
	player.global_position = vehicle.get_seat_position()
	vehicle.attach_camera(camera_rig, spring_arm)
	vehicle.set_driver_active(true)
	_set_interact_prompt("")
	_show_message("DRIVING  //  [%s] to get out" % _interact_key_name(), 3.0)


func _exit_vehicle() -> void:
	if _active_vehicle == null:
		return
	var vehicle = _active_vehicle
	_active_vehicle = null
	vehicle.set_driver_active(false)
	vehicle.detach_camera()
	player.global_position = vehicle.get_exit_position()
	player.set_stowed(false)
	_show_message("ON FOOT", 2.0)


func _interact_key_name() -> String:
	for event in InputMap.action_get_events(&"interact"):
		var key_event := event as InputEventKey
		if key_event != null:
			var label := key_event.as_text_physical_keycode()
			if not label.is_empty():
				return label
	return "E"


func _build_pause_menu() -> void:
	_pause_menu = PauseMenuScript.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.player = player
	add_child(_pause_menu)


func _build_dialogue_ui() -> void:
	_dialogue_ui = DialogueChoiceUIScript.new()
	_dialogue_ui.name = "DialogueChoiceUI"
	_dialogue_ui.player = player
	add_child(_dialogue_ui)


func _spawn_street_npcs() -> void:
	# Cuenco is ~16 m wide. Parked cars sit ~6.4 m off center; sidewalks center
	# around ~9.3 m. Keep NPCs on the sidewalk strips, not in the lanes.
	const EAST_WALK := 22.0
	const WEST_WALK := 3.4

	# The prop scripts rename themselves inside build() ("Mulet", "Jholo",
	# "Edward"), so every name here is assigned *after* the build call or it
	# gets clobbered and nothing can find these by name.

	# 1) Mulet — standing, talkable (east sidewalk near spawn).
	var mulet_pos := _grounded_feet_position(Vector3(EAST_WALK, 0.0, -550.5))
	var mulet = MuletNpcPropScript.new()
	mulet.build_on_ready = false
	mulet.target_height = 1.9
	mulet.dialogue_ui = _dialogue_ui
	mulet.hud = hud
	mulet.position = mulet_pos
	mulet.face_look_target = SPAWN_POSITION
	add_child(mulet)
	mulet.build()
	mulet.name = "BaniladMulet"

	# 2) Jholo — standing boxing idle, talkable (west sidewalk).
	var jholo_pos := _grounded_feet_position(Vector3(WEST_WALK, 0.0, -548.8))
	var jholo = JholoNpcPropScript.new()
	jholo.build_on_ready = false
	jholo.target_height = 1.85
	jholo.dialogue_ui = _dialogue_ui
	jholo.hud = hud
	jholo.position = jholo_pos
	jholo.face_look_target = SPAWN_POSITION
	add_child(jholo)
	jholo.build()
	jholo.name = "BaniladJholo"

	# 3) Edward — rigged walker on the east sidewalk toward Gaisano.
	var edward_route: Array[Vector3] = [
		_grounded_feet_position(Vector3(EAST_WALK, 0.0, -545.0)),
		_grounded_feet_position(Vector3(EAST_WALK, 0.0, -520.0)),
		_grounded_feet_position(Vector3(EAST_WALK - 0.4, 0.0, -495.0)),
		_grounded_feet_position(Vector3(EAST_WALK, 0.0, -520.0)),
	]
	var edward = EdwardNpcPropScript.new()
	edward.build_on_ready = false
	edward.roam_enabled = true
	edward.lean_on_rail = false
	edward.lean_on_wall = false
	edward.target_height = 1.78
	edward.walk_speed = 1.45
	edward.dialogue_ui = _dialogue_ui
	edward.hud = hud
	edward.position = edward_route[0]
	add_child(edward)
	edward.build()
	edward.name = "BaniladEdwardWalker"
	edward.set_roam_points(edward_route)

	# 4) Mixamo pedestrian — west sidewalk Cuenco stroll (ambient walker).
	var ped_route: Array[Vector3] = [
		_grounded_body_position(Vector3(WEST_WALK, 0.0, -562.0)),
		_grounded_body_position(Vector3(WEST_WALK, 0.0, -530.0)),
		_grounded_body_position(Vector3(WEST_WALK + 0.3, 0.0, -498.0)),
		_grounded_body_position(Vector3(WEST_WALK, 0.0, -530.0)),
	]
	var pedestrian = CBlockEdwardScene.instantiate()
	pedestrian.name = "BaniladStreetWalker"
	pedestrian.position = ped_route[0]
	pedestrian.custom_waypoints = ped_route
	var nameplate := pedestrian.get_node_or_null("Nameplate") as Label3D
	if nameplate != null:
		nameplate.text = "WALKER"
	add_child(pedestrian)


## Prop NPCs put their soles at the node origin — plant that on the mesh.
func _grounded_feet_position(xz: Vector3) -> Vector3:
	return Vector3(xz.x, _raycast_ground_y(xz.x, xz.z) + 0.02, xz.z)


## CharacterBody origin sits at capsule center — lift by half-height.
func _grounded_body_position(xz: Vector3) -> Vector3:
	return Vector3(xz.x, _raycast_ground_y(xz.x, xz.z) + WALKER_BODY_HALF_HEIGHT, xz.z)


func _raycast_ground_y(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NPC_GROUND_Y
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 50.0, z),
		Vector3(x, -30.0, z)
	)
	query.collision_mask = 1
	if player != null:
		query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NPC_GROUND_Y
	return float(hit.position.y)


func _physics_process(delta: float) -> void:
	if _active_vehicle != null:
		# The player is stowed and not falling anywhere; watch the car instead,
		# and keep the body with it so getting out lands beside the vehicle.
		if _active_vehicle.global_position.y < FALL_LIMIT:
			_exit_vehicle()
			_respawn()
		else:
			player.global_position = _active_vehicle.get_seat_position()
	elif player.global_position.y < FALL_LIMIT:
		_respawn()

	# Landmark proximity does not need to run every physics tick.
	_scan_accumulator += delta
	if _scan_accumulator >= 0.25:
		_scan_accumulator = 0.0
		_update_nearest_landmark()


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_ui != null and _dialogue_ui.has_method("is_open") and _dialogue_ui.is_open():
		if event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_picker"):
			if _dialogue_ui.has_method("dismiss"):
				_dialogue_ui.dismiss()
			get_viewport().set_input_as_handled()
		return
	# While driving, the player's own input is off, so the map owns the key
	# that gets them back out.
	if _active_vehicle != null:
		if event.is_action_pressed(&"interact"):
			_exit_vehicle()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"character_picker"):
		if _picker_open:
			_close_character_picker()
		else:
			_open_character_picker()
		get_viewport().set_input_as_handled()
		return
	# The picker owns the pause key while it is up, so Esc closes it instead of
	# stacking the pause menu on top.
	if _picker_open:
		if event.is_action_pressed(&"pause"):
			_close_character_picker()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"exit_to_menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(MENU_SCENE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"respawn"):
		_respawn()
		_show_message("Returned to Gov. M. Cuenco Avenue", 2.5)
		get_viewport().set_input_as_handled()


func _respawn() -> void:
	if player.has_method("reset_character"):
		player.reset_character(SPAWN_POSITION)
	else:
		player.global_position = SPAWN_POSITION
		player.velocity = Vector3.ZERO


func _load_landmarks() -> void:
	if not FileAccess.file_exists(LANDMARK_DATA):
		push_warning("landmark data missing: %s" % LANDMARK_DATA)
		return
	var text := FileAccess.get_file_as_string(LANDMARK_DATA)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		push_warning("landmark data could not be parsed")
		return

	for entry in parsed:
		var pos: Array = entry.get("godot_position", [])
		if pos.size() != 3:
			continue
		_landmarks.append({
			"name": String(entry.get("name", "")),
			"position": Vector3(pos[0], pos[1], pos[2]),
			"key": bool(entry.get("key", false)),
		})


func _update_nearest_landmark() -> void:
	if _picker_open:
		return
	var origin := player.global_position
	var best_name := ""
	var best_distance := LANDMARK_RANGE

	for landmark in _landmarks:
		var target: Vector3 = landmark["position"]
		# Compare on the ground plane, building heights are irrelevant here.
		var distance := Vector2(origin.x - target.x, origin.z - target.z).length()
		# Named key landmarks win ties so the HUD favours the big ones.
		if landmark["key"]:
			distance -= 12.0
		if distance < best_distance:
			best_distance = distance
			best_name = landmark["name"]

	if best_name == _nearest_name:
		return
	_nearest_name = best_name
	_set_prompt("" if best_name.is_empty() else "◆  %s" % best_name)


func _set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = not text.is_empty()


## Interactable prompts get their own line so a landmark call-out and an
## "[E] Inspect" can be on screen at once.
func _set_interact_prompt(text: String) -> void:
	interact_label.text = text
	interact_label.visible = not text.is_empty()


func _show_message(text: String, duration: float = 4.0) -> void:
	_message_generation += 1
	var generation := _message_generation
	message_label.text = text
	message_label.visible = true
	await get_tree().create_timer(duration).timeout
	if generation == _message_generation and not _picker_open:
		message_label.visible = false


func _refresh_help_text() -> void:
	help_label.text = (
		"WASD move  |  Mouse orbit  |  Shift sprint  |  Space jump  |  "
		+ "E interact / drive  |  Space handbrake  |  Esc pause  |  C character  |  M menu"
	)


func _build_character_picker() -> void:
	_picker_overlay = ColorRect.new()
	_picker_overlay.name = "CharacterPicker"
	_picker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_overlay.color = Color(0.02, 0.04, 0.07, 0.82)
	_picker_overlay.visible = false
	_picker_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(_picker_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_picker_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.11, 0.16, 0.96)
	style.border_color = Color(0.45, 0.78, 0.92, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title := Label.new()
	title.text = "SELECT CHARACTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 1.0))
	title.add_theme_constant_override("outline_size", 6)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Swap skins mid-session without leaving Banilad"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.76, 0.84, 1.0))
	column.add_child(subtitle)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)

	var button_group := ButtonGroup.new()
	_character_buttons.clear()
	for character in CharacterRoster.list_characters():
		var character_id := String(character["id"])
		var card := _make_character_card(character)
		card.button_group = button_group
		card.pressed.connect(_on_character_card_pressed.bind(character_id))
		row.add_child(card)
		_character_buttons[character_id] = card

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	column.add_child(actions)

	var confirm := _make_picker_button("Play as selected", Vector2(220, 46))
	confirm.pressed.connect(_confirm_character_pick)
	actions.add_child(confirm)

	var close_btn := _make_picker_button("Close  (C / Esc)", Vector2(180, 46))
	close_btn.pressed.connect(_close_character_picker)
	actions.add_child(close_btn)


func _make_character_card(character: Dictionary) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(230, 120)
	button.focus_mode = Control.FOCUS_ALL
	button.text = "%s\n%s" % [
		String(character["display_name"]),
		String(character["subtitle"]),
	]
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	button.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 1.0))
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_constant_override("line_spacing", 6)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.16, 0.22, 0.96)
	normal.border_color = Color(0.28, 0.4, 0.52, 0.9)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 18
	normal.content_margin_bottom = 18

	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color(0.55, 0.82, 0.95, 1.0)

	var selected := normal.duplicate() as StyleBoxFlat
	selected.bg_color = Color(0.14, 0.24, 0.32, 0.98)
	selected.border_color = Color(0.45, 0.86, 1.0, 1.0)
	selected.set_border_width_all(3)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("focus", selected)
	return button


func _make_picker_button(text: String, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0, 1.0))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.18, 0.26, 0.96)
	style.border_color = Color(0.35, 0.55, 0.7, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	return button


func _open_character_picker() -> void:
	_picker_open = true
	_selected_preview_id = (
		String(player.get_character_id())
		if player.has_method("get_character_id")
		else CharacterRoster.selected_id
	)
	_refresh_character_card_states()
	_picker_overlay.visible = true
	if player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)
	if _pause_menu != null:
		_pause_menu.set_pause_blocked(true)
	_set_prompt("Choose a character, then Play")


func _close_character_picker() -> void:
	_picker_open = false
	_picker_overlay.visible = false
	_set_prompt("")
	if _pause_menu != null:
		_pause_menu.set_pause_blocked(false)
	if player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)


func _on_character_card_pressed(character_id: String) -> void:
	_selected_preview_id = character_id
	_refresh_character_card_states()


func _refresh_character_card_states() -> void:
	for character_id in _character_buttons.keys():
		var button: Button = _character_buttons[character_id]
		button.set_pressed_no_signal(character_id == _selected_preview_id)


func _confirm_character_pick() -> void:
	if _selected_preview_id.is_empty():
		_selected_preview_id = CharacterRoster.DEFAULT_ID
	if player.has_method("switch_character"):
		player.switch_character(_selected_preview_id)
	_close_character_picker()
