extends CanvasLayer
class_name VHSSystem

## Collectible VHS archive and CRT-style playback overlay.

var _tapes: Dictionary = {}
var player: Node = null
var _overlay: ColorRect
var _menu: VBoxContainer
var _title: Label
var _body: Label
var _playing := false
var _play_time := 0.0


func _ready() -> void:
	layer = 28
	_build_ui()
	set_process(false)


func collect_tape(tape_id: StringName, title: String, content: String) -> bool:
	if _tapes.has(tape_id):
		return false
	_tapes[tape_id] = {"title": title, "content": content}
	return true


func tape_count() -> int:
	return _tapes.size()


func open_archive() -> void:
	if _tapes.is_empty():
		return
	_overlay.visible = true
	_playing = false
	set_process(false)
	_rebuild_menu()
	if player != null and player.has_method("set_ui_locked"):
		player.set_ui_locked(true)


func close() -> void:
	_overlay.visible = false
	_playing = false
	set_process(false)
	if player != null and player.has_method("set_ui_locked"):
		player.set_ui_locked(false)


func _process(delta: float) -> void:
	if _playing:
		_play_time += delta
		if _play_time >= 20.0:
			_playing = false
			set_process(false)
			_title.text = "PLAYBACK COMPLETE"


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color("08090b")
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(910, 610)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("11191a")
	style.border_color = Color("c2ba91")
	style.set_border_width_all(3)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 32
	style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 14)
	panel.add_child(_menu)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color("eee5c7"))
	_menu.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body.custom_minimum_size = Vector2(780, 250)
	_body.add_theme_font_size_override("font_size", 24)
	_body.add_theme_color_override("font_color", Color("cfc9b5"))
	_menu.add_child(_body)
	_overlay.visible = false


func _rebuild_menu() -> void:
	for child in _menu.get_children():
		if child != _title and child != _body:
			child.queue_free()
	_title.text = "VHS ARCHIVE  //  %d / 6 FOUND" % tape_count()
	_body.text = "Select a tape to play it on the faculty-room CRT.\nREC  ●  07.14.1998"
	for tape_id in _tapes.keys():
		var button := Button.new()
		button.text = String(_tapes[tape_id]["title"])
		button.custom_minimum_size = Vector2(620, 42)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func(): _play_tape(tape_id))
		_menu.add_child(button)
	var close_button := Button.new()
	close_button.text = "EJECT"
	close_button.custom_minimum_size = Vector2(160, 38)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	_menu.add_child(close_button)


func _play_tape(tape_id: StringName) -> void:
	var tape: Dictionary = _tapes[tape_id]
	_playing = true
	_play_time = 0.0
	set_process(true)
	_title.text = "REC  ●  %s" % tape["title"]
	_body.text = tape["content"] + "\n\nTRACKING...  [20 SEC PLAYBACK]"
