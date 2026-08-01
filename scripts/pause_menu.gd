extends CanvasLayer
class_name PauseMenu
## Shared pause overlay for the free-roam maps.
##
## Runs with PROCESS_MODE_ALWAYS so it keeps receiving input on both sides of
## the pause: WHEN_PAUSED would stop it seeing the key that opens it.

signal opened()
signal closed()

const MENU_SCENE := "res://main_menu.tscn"

## Rows in the controls panel, read back out of the InputMap so a rebind is
## reflected here instead of drifting out of date.
const CONTROL_ROWS: Array[Array] = [
	["Move", &"move_forward"],
	["Sprint", &"sprint"],
	["Jump", &"jump"],
	["Interact", &"interact"],
	["Attack", &"attack"],
	["Heavy attack", &"attack_alt"],
	["Character picker", &"character_picker"],
	["Reset position", &"respawn"],
	["Main menu", &"exit_to_menu"],
	["Pause", &"pause"],
]

var player: Node = null

var _overlay: Control
var _controls_panel: PanelContainer
var _resume_button: Button
var _is_open := false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_overlay.visible = false


func is_open() -> bool:
	return _is_open


## Hands the pause key back to the map. The overlay sits below the map root in
## the tree, so it sees unhandled input first; another modal (the character
## picker) has to be able to claim Esc for itself while it is up.
func set_pause_blocked(blocked: bool) -> void:
	set_process_unhandled_input(not blocked)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if _is_open:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	_overlay.visible = true
	_controls_panel.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume_button.grab_focus()
	opened.emit()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_overlay.visible = false
	get_tree().paused = false
	# The player controller owns the mouse again, unless some other UI has it.
	if player == null or not player.has_method("is_ui_locked") or not player.is_ui_locked():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _on_main_menu_pressed() -> void:
	_is_open = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


## ---------------------------------------------------------------------
## UI construction
## ---------------------------------------------------------------------

func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.name = "PauseOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.04, 0.07, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay.add_child(center)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	center.add_child(row)

	row.add_child(_build_menu_panel())
	_controls_panel = _build_controls_panel()
	_controls_panel.visible = false
	row.add_child(_controls_panel)


func _build_menu_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03))
	title.add_theme_constant_override("outline_size", 6)
	column.add_child(title)

	_resume_button = _make_button("Resume")
	_resume_button.pressed.connect(close)
	column.add_child(_resume_button)

	var controls_button := _make_button("Controls")
	controls_button.pressed.connect(func() -> void:
		_controls_panel.visible = not _controls_panel.visible
	)
	column.add_child(controls_button)

	var menu_button := _make_button("Main menu")
	menu_button.pressed.connect(_on_main_menu_pressed)
	column.add_child(menu_button)

	var quit_button := _make_button("Quit game")
	quit_button.pressed.connect(_on_quit_pressed)
	column.add_child(quit_button)

	return panel


func _build_controls_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	column.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)

	for control_row in CONTROL_ROWS:
		var name_label := Label.new()
		name_label.text = String(control_row[0])
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.68, 0.78, 0.86))
		grid.add_child(name_label)

		var binding_label := Label.new()
		binding_label.text = _binding_text(control_row[1])
		binding_label.add_theme_font_size_override("font_size", 15)
		binding_label.add_theme_color_override("font_color", Color(0.93, 0.9, 0.72))
		grid.add_child(binding_label)

	var note := Label.new()
	note.text = "Movement is WASD; the mouse orbits the camera."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(300, 0)
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.55, 0.64, 0.72))
	column.add_child(note)

	return panel


## Keyboard and mouse bindings only: the pad button names read as noise here.
func _binding_text(action_name: StringName) -> String:
	if not InputMap.has_action(action_name):
		return "unbound"
	var labels: Array[String] = []
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var label := key_event.as_text_physical_keycode()
			if label.is_empty():
				label = key_event.as_text_keycode()
			if not label.is_empty():
				labels.append(label)
		elif event is InputEventMouseButton:
			labels.append((event as InputEventMouseButton).as_text())
	if labels.is_empty():
		return "pad only"
	return "  /  ".join(labels)


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 46)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	button.add_theme_stylebox_override(
		"normal", _button_style(Color(0.11, 0.16, 0.22, 0.96), Color(0.28, 0.4, 0.52, 0.9))
	)
	button.add_theme_stylebox_override(
		"hover", _button_style(Color(0.16, 0.24, 0.32, 0.98), Color(0.45, 0.78, 0.92, 0.95))
	)
	button.add_theme_stylebox_override(
		"pressed", _button_style(Color(0.08, 0.12, 0.17, 0.98), Color(0.35, 0.6, 0.75, 0.9))
	)
	button.add_theme_stylebox_override(
		"focus", _button_style(Color(0.16, 0.24, 0.32, 0.0), Color(0.45, 0.78, 0.92, 0.95))
	)
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.11, 0.16, 0.96)
	style.border_color = Color(0.45, 0.78, 0.92, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style
