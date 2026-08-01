extends Node3D
## CBlock is a separate Godot-built district with its own third-person controller.
## Press C in-game to open the character picker.

const MENU_SCENE := "res://main_menu.tscn"
const SPAWN_POSITION := Vector3(0.0, 0.94, 0.0)
const CharacterRoster := preload("res://scripts/cblock_character_roster.gd")

@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var prompt_label: Label = $HUD/Prompt
@onready var message_label: Label = $HUD/Message
@onready var help_label: Label = $HUD/TopBar/Help

var _message_generation := 0
var _picker_open := false
var _picker_overlay: ColorRect
var _character_buttons: Dictionary = {}
var _selected_preview_id := ""


func _ready() -> void:
	Engine.max_fps = 60
	CharacterRoster.load_saved()
	if player.has_signal("status_message"):
		player.status_message.connect(_show_message)
	_set_prompt("")
	_build_character_picker()
	_refresh_help_text()
	await get_tree().create_timer(5.0).timeout
	if not _picker_open:
		message_label.visible = false


func _physics_process(_delta: float) -> void:
	if player.global_position.y < -8.0 and player.has_method("reset_character"):
		player.reset_character(SPAWN_POSITION)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_C:
			if _picker_open:
				_close_character_picker()
			else:
				_open_character_picker()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _picker_open:
				_close_character_picker()
				get_viewport().set_input_as_handled()
		KEY_M:
			if _picker_open:
				return
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file(MENU_SCENE)
		KEY_R:
			if _picker_open:
				return
			if player.has_method("reset_character"):
				player.reset_character(SPAWN_POSITION)


func _set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = not text.is_empty()


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
		+ "LMB punch  |  RMB hit  |  C character  |  M menu  |  R reset"
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
	subtitle.text = "Swap skins mid-session without leaving CBlock"
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
	_set_prompt("Choose a character, then Play")


func _close_character_picker() -> void:
	_picker_open = false
	_picker_overlay.visible = false
	_set_prompt("")
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
