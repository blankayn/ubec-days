extends CanvasLayer
class_name DialogueChoiceUI
## Bottom dialogue layout: speech box left, reply choices stacked on the right.

signal choice_picked(index: int)

var player: Node = null

var _overlay: Control
var _root_row: HBoxContainer
var _speech_panel: PanelContainer
var _speaker_label: Label
var _body_label: Label
var _button_row: VBoxContainer
var _open := false


func _ready() -> void:
	layer = 28
	_build_ui()
	_overlay.visible = false


func is_open() -> bool:
	return _open


func present(speaker: String, body: String, choices: Array = []) -> void:
	_speaker_label.text = speaker
	_body_label.text = body
	for child in _button_row.get_children():
		child.queue_free()
	for index in choices.size():
		var button := Button.new()
		button.text = str(choices[index])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(320, 52)
		button.add_theme_font_size_override("font_size", 20)
		button.add_theme_color_override("font_color", Color("f2ebe0"))
		button.add_theme_color_override("font_hover_color", Color("ffffff"))
		button.add_theme_color_override("font_pressed_color", Color("d9e8b0"))
		var normal := _choice_style(Color("151a20", 0.96), Color("9aab88"))
		var hover := _choice_style(Color("1e262e", 0.98), Color("c5d89a"))
		var pressed := _choice_style(Color("10141a", 0.98), Color("8a9a7a"))
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("focus", hover)
		var choice_index := index
		button.pressed.connect(func() -> void:
			_close()
			choice_picked.emit(choice_index)
		)
		_button_row.add_child(button)
	_open = true
	_overlay.visible = true
	if player != null and player.has_method("set_ui_locked"):
		player.set_ui_locked(true)


func dismiss() -> void:
	_close()


func _close() -> void:
	_open = false
	_overlay.visible = false
	if player != null and player.has_method("set_ui_locked"):
		player.set_ui_locked(false)


func _choice_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Soft vignette so the world stays visible behind the speech layout.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.05, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	_root_row = HBoxContainer.new()
	_root_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_root_row.offset_left = 36.0
	_root_row.offset_right = -36.0
	_root_row.offset_bottom = -36.0
	_root_row.offset_top = -260.0
	_root_row.add_theme_constant_override("separation", 18)
	_root_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_overlay.add_child(_root_row)

	_speech_panel = PanelContainer.new()
	_speech_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speech_panel.size_flags_stretch_ratio = 2.4
	_speech_panel.custom_minimum_size = Vector2(520, 180)
	var speech_style := StyleBoxFlat.new()
	speech_style.bg_color = Color("10151b", 0.94)
	speech_style.border_color = Color("e8e4da")
	speech_style.set_border_width_all(3)
	speech_style.set_corner_radius_all(2)
	speech_style.content_margin_left = 22
	speech_style.content_margin_right = 22
	speech_style.content_margin_top = 16
	speech_style.content_margin_bottom = 18
	_speech_panel.add_theme_stylebox_override("panel", speech_style)
	_root_row.add_child(_speech_panel)

	var speech_column := VBoxContainer.new()
	speech_column.add_theme_constant_override("separation", 10)
	_speech_panel.add_child(speech_column)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 26)
	_speaker_label.add_theme_color_override("font_color", Color("f4f0e6"))
	speech_column.add_child(_speaker_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("font_size", 22)
	_body_label.add_theme_color_override("font_color", Color("d8d2c6"))
	speech_column.add_child(_body_label)

	_button_row = VBoxContainer.new()
	_button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button_row.size_flags_stretch_ratio = 1.0
	_button_row.size_flags_vertical = Control.SIZE_SHRINK_END
	_button_row.custom_minimum_size = Vector2(300, 0)
	_button_row.add_theme_constant_override("separation", 10)
	_button_row.alignment = BoxContainer.ALIGNMENT_END
	_root_row.add_child(_button_row)
