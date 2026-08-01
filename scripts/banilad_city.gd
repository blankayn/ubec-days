extends Node3D
## Banilad free-roam map, built from OpenStreetMap geometry of the real
## Gov. M. Cuenco Avenue corridor. Reuses the CBlock third-person controller.

const MENU_SCENE := "res://main_menu.tscn"
const LANDMARK_DATA := "res://assets/maps/banilad_landmarks.json"
# Preloaded rather than referenced by class_name: headless `--script` runs load
# this before the global class cache exists, and the bare name fails to parse.
const PauseMenuScript := preload("res://scripts/pause_menu.gd")

# On Gov. M. Cuenco Avenue, roughly 120 m south of Gaisano Country Mall.
const SPAWN_POSITION := Vector3(12.79, 1.2, -554.24)

# Anything below this has fallen through the world.
const FALL_LIMIT := -20.0

# How close the player must be for a landmark to be called out.
const LANDMARK_RANGE := 90.0

@onready var player: CharacterBody3D = $Player
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


func _ready() -> void:
	Engine.max_fps = 60
	_load_landmarks()
	if player.has_signal("status_message"):
		player.status_message.connect(_show_message)
	if player.has_signal("prompt_changed"):
		player.prompt_changed.connect(_set_interact_prompt)
	_build_pause_menu()
	_respawn()
	_set_prompt("")
	_set_interact_prompt("")
	_show_message("BANILAD  //  Gov. M. Cuenco Avenue, Cebu City", 5.0)


func _build_pause_menu() -> void:
	_pause_menu = PauseMenuScript.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.player = player
	add_child(_pause_menu)


func _physics_process(delta: float) -> void:
	if player.global_position.y < FALL_LIMIT:
		_respawn()

	# Landmark proximity does not need to run every physics tick.
	_scan_accumulator += delta
	if _scan_accumulator >= 0.25:
		_scan_accumulator = 0.0
		_update_nearest_landmark()


func _unhandled_input(event: InputEvent) -> void:
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
	if generation == _message_generation:
		message_label.visible = false
