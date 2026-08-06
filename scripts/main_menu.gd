extends Control
## Clean, razor-sharp HD Main Menu for UBEC.

const UBEC_SCENE := "res://main.tscn"
const CBLOCK_SCENE := "res://cblock_map.tscn"
const BANILAD_SCENE := "res://banilad_city.tscn"
const StoryManagerType := preload("res://scripts/story_manager.gd")
const DEFAULT_PASSWORD := "1994"

var _title: Label
var _subtitle: Label
var _new_game_btn: Button
var _cblock_btn: Button
var _banilad_btn: Button
var _chapter_btn: Button
var _quit_btn: Button
var _hint: Label
var _starting := false

# Modals
var _pwd_overlay: ColorRect
var _pwd_input: LineEdit
var _pwd_status: Label
var _chapter_overlay: ColorRect

var _loading_overlay: ColorRect
var _loading_bar: ProgressBar
var _loading_label: Label
var _target_scene := UBEC_SCENE

func _ready() -> void:
	Engine.max_fps = 60
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	_build_password_modal()
	_build_chapter_modal()
	_build_loading_overlay()
	_play_intro_motion()


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if _pwd_overlay and _pwd_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_close_password_modal()
			get_viewport().set_input_as_handled()
		return
	if _chapter_overlay and _chapter_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_close_chapter_modal()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_accept") or (
		event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER
	):
		_on_new_game_pressed()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_on_quit_pressed()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. Dark Atmospheric Background (Crisp HD, no downsampling shader blurring the UI)
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("080b10")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var subtle_glow := ColorRect.new()
	subtle_glow.name = "SubtleGlow"
	subtle_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	subtle_glow.color = Color(0.06, 0.10, 0.16, 0.5)
	subtle_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtle_glow)

	# 2. Main Center Layout
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	# PASS keeps this layout container transparent while still allowing its
	# child buttons to receive mouse clicks.
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	# High-contrast dark card container
	var main_card := PanelContainer.new()
	main_card.name = "MainCard"
	main_card.custom_minimum_size = Vector2(520, 0)

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.07, 0.10, 0.15, 0.92)
	card_style.border_color = Color(0.22, 0.32, 0.45, 0.8)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(10)
	card_style.content_margin_left = 40
	card_style.content_margin_right = 40
	card_style.content_margin_top = 36
	card_style.content_margin_bottom = 36
	card_style.shadow_color = Color(0, 0, 0, 0.6)
	card_style.shadow_size = 16
	main_card.add_theme_stylebox_override("panel", card_style)
	center.add_child(main_card)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 20)
	main_card.add_child(column)

	# TITLE — Large, Razor-Sharp, High Contrast White
	_title = Label.new()
	_title.name = "Title"
	_title.text = "UBEC"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 72)
	_title.add_theme_color_override("font_color", Color("ffffff"))
	_title.add_theme_color_override("font_outline_color", Color("020617"))
	_title.add_theme_constant_override("outline_size", 12)
	column.add_child(_title)

	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.text = "Days"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 20)
	_subtitle.add_theme_color_override("font_color", Color("94a3b8"))
	_subtitle.add_theme_color_override("font_outline_color", Color("020617"))
	_subtitle.add_theme_constant_override("outline_size", 6)
	column.add_child(_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	column.add_child(spacer)

	# BUTTONS — Large, Sharp, Clear
	_new_game_btn = _make_clean_button("UBEC · Story Map")
	_new_game_btn.pressed.connect(_on_new_game_pressed)
	column.add_child(_new_game_btn)

	_cblock_btn = _make_clean_button("CBLOCK · Urban City Map")
	_cblock_btn.pressed.connect(_on_cblock_pressed)
	column.add_child(_cblock_btn)

	_banilad_btn = _make_clean_button("BANILAD · Real Street Map")
	_banilad_btn.pressed.connect(_on_banilad_pressed)
	column.add_child(_banilad_btn)

	_chapter_btn = _make_clean_button("Chapter Select 🔒")
	_chapter_btn.pressed.connect(_on_chapter_select_pressed)
	column.add_child(_chapter_btn)

	_quit_btn = _make_clean_button("Quit")
	_quit_btn.pressed.connect(_on_quit_pressed)
	column.add_child(_quit_btn)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	column.add_child(spacer2)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "Press Enter to start  ·  Esc to quit"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color("64748b"))
	_hint.add_theme_color_override("font_outline_color", Color("020617"))
	_hint.add_theme_constant_override("outline_size", 4)
	column.add_child(_hint)

	_new_game_btn.grab_focus()


func _make_clean_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(360, 56)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color("f1f5f9"))
	btn.add_theme_color_override("font_hover_color", Color("ffffff"))
	btn.add_theme_color_override("font_pressed_color", Color("ffffff"))
	btn.add_theme_color_override("font_focus_color", Color("ffffff"))
	btn.add_theme_color_override("font_outline_color", Color("020617"))
	btn.add_theme_constant_override("outline_size", 6)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.16, 0.24, 0.95)
	normal.border_color = Color(0.25, 0.38, 0.55, 0.8)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.26, 0.38, 1.0)
	hover.border_color = Color("38bdf8")
	hover.set_border_width_all(2)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)
	return btn


# ── PASSWORD MODAL ──────────────────────────────────────────────────────────────

func _build_password_modal() -> void:
	_pwd_overlay = ColorRect.new()
	_pwd_overlay.name = "PasswordOverlay"
	_pwd_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pwd_overlay.color = Color(0.0, 0.0, 0.0, 0.8)
	_pwd_overlay.visible = false
	add_child(_pwd_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pwd_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 260)

	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.10, 0.14, 0.22, 0.98)
	pstyle.border_color = Color("38bdf8")
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(10)
	pstyle.content_margin_left = 32
	pstyle.content_margin_right = 32
	pstyle.content_margin_top = 28
	pstyle.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Chapter Select Lock"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f8fafc"))
	title.add_theme_color_override("font_outline_color", Color("020617"))
	title.add_theme_constant_override("outline_size", 6)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "Enter passcode to access chapters:"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color("94a3b8"))
	col.add_child(sub)

	_pwd_input = LineEdit.new()
	_pwd_input.secret = true
	_pwd_input.placeholder_text = "Passcode (e.g. 1994)"
	_pwd_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pwd_input.custom_minimum_size = Vector2(300, 44)
	_pwd_input.add_theme_font_size_override("font_size", 18)
	_pwd_input.text_submitted.connect(func(_t: String): _verify_password())
	col.add_child(_pwd_input)

	_pwd_status = Label.new()
	_pwd_status.text = ""
	_pwd_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pwd_status.add_theme_font_size_override("font_size", 14)
	_pwd_status.add_theme_color_override("font_color", Color("f87171"))
	col.add_child(_pwd_status)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	col.add_child(btn_row)

	var submit_btn := Button.new()
	submit_btn.text = "Unlock"
	submit_btn.custom_minimum_size = Vector2(130, 40)
	submit_btn.add_theme_font_size_override("font_size", 16)
	submit_btn.pressed.connect(_verify_password)
	btn_row.add_child(submit_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(130, 40)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(_close_password_modal)
	btn_row.add_child(cancel_btn)


func _on_chapter_select_pressed() -> void:
	_pwd_status.text = ""
	_pwd_input.text = ""
	_pwd_overlay.visible = true
	_pwd_input.grab_focus()


func _verify_password() -> void:
	if _pwd_input.text == DEFAULT_PASSWORD or _pwd_input.text.to_lower() == "ubec":
		_close_password_modal()
		_open_chapter_modal()
	else:
		_pwd_status.text = "Incorrect passcode"


func _close_password_modal() -> void:
	_pwd_overlay.visible = false
	_chapter_btn.grab_focus()


# ── CHAPTER SELECTION MODAL ────────────────────────────────────────────────────

func _build_chapter_modal() -> void:
	_chapter_overlay = ColorRect.new()
	_chapter_overlay.name = "ChapterOverlay"
	_chapter_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chapter_overlay.color = Color(0.0, 0.0, 0.0, 0.8)
	_chapter_overlay.visible = false
	add_child(_chapter_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chapter_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 360)

	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.10, 0.14, 0.22, 0.98)
	cstyle.border_color = Color("38bdf8")
	cstyle.set_border_width_all(2)
	cstyle.set_corner_radius_all(10)
	cstyle.content_margin_left = 32
	cstyle.content_margin_right = 32
	cstyle.content_margin_top = 28
	cstyle.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", cstyle)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Select Chapter"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("f8fafc"))
	title.add_theme_color_override("font_outline_color", Color("020617"))
	title.add_theme_constant_override("outline_size", 6)
	col.add_child(title)

	var ch1_btn := _make_clean_button("Chapter 1: Day Errand")
	ch1_btn.pressed.connect(func(): _launch_chapter(1))
	col.add_child(ch1_btn)

	var ch2_btn := _make_clean_button("Chapter 2: Forgotten (Night)")
	ch2_btn.pressed.connect(func(): _launch_chapter(2))
	col.add_child(ch2_btn)

	var ch3_btn := _make_clean_button("Chapter 3: Back Inside (UC)")
	ch3_btn.pressed.connect(func(): _launch_chapter(3))
	col.add_child(ch3_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	col.add_child(spacer)

	var back_btn := Button.new()
	back_btn.text = "Back to Menu"
	back_btn.custom_minimum_size = Vector2(160, 40)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.add_theme_color_override("font_color", Color("94a3b8"))
	back_btn.pressed.connect(_close_chapter_modal)
	col.add_child(back_btn)


func _open_chapter_modal() -> void:
	_chapter_overlay.visible = true


func _close_chapter_modal() -> void:
	_chapter_overlay.visible = false
	_chapter_btn.grab_focus()


func _build_loading_overlay() -> void:
	_loading_overlay = ColorRect.new()
	_loading_overlay.name = "LoadingOverlay"
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.color = Color(0.02, 0.04, 0.07, 0.94)
	_loading_overlay.visible = false
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_loading_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 140)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.18, 0.98)
	style.border_color = Color("38bdf8")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	_loading_label = Label.new()
	_loading_label.text = "Loading UBEC..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 20)
	_loading_label.add_theme_color_override("font_color", Color("e2e8f0"))
	_loading_label.add_theme_color_override("font_outline_color", Color("020617"))
	_loading_label.add_theme_constant_override("outline_size", 4)
	col.add_child(_loading_label)

	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(400, 22)
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 100.0
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.12, 0.16, 0.22, 1.0)
	bar_bg.set_corner_radius_all(6)
	_loading_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("38bdf8")
	bar_fill.set_corner_radius_all(6)
	_loading_bar.add_theme_stylebox_override("fill", bar_fill)
	col.add_child(_loading_bar)


func _show_loading_overlay(status_text: String = "Loading UBEC...") -> void:
	_loading_label.text = status_text
	_loading_bar.value = 0.0
	_loading_overlay.visible = true
	_loading_overlay.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_loading_overlay, "modulate:a", 1.0, 0.2)


func _hide_loading_overlay() -> void:
	_loading_overlay.visible = false


func _begin_scene_transition(scene_path: String = UBEC_SCENE, status_text: String = "Loading UBEC...") -> void:
	if _starting:
		return
	_starting = true
	_target_scene = scene_path
	_close_chapter_modal()
	_close_password_modal()
	_show_loading_overlay(status_text)

	var err := ResourceLoader.load_threaded_request(_target_scene)
	if err != OK:
		_loading_label.text = "Could not start load."
		_starting = false
		await get_tree().create_timer(1.2).timeout
		_hide_loading_overlay()
		return

	_poll_scene_load()


func _poll_scene_load() -> void:
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(_target_scene, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var amount := float(progress[0]) if progress.size() > 0 else 0.0
				_loading_bar.value = amount * 100.0
				_loading_label.text = "Loading map... %d%%" % int(amount * 100.0)
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				_loading_bar.value = 100.0
				_loading_label.text = "Starting..."
				var packed := ResourceLoader.load_threaded_get(_target_scene) as PackedScene
				if packed == null:
					_loading_label.text = "Load failed."
					_starting = false
					await get_tree().create_timer(1.2).timeout
					_hide_loading_overlay()
					return
				await get_tree().create_timer(0.12).timeout
				get_tree().change_scene_to_packed(packed)
				return
			_:
				_loading_label.text = "Load failed."
				_starting = false
				await get_tree().create_timer(1.2).timeout
				_hide_loading_overlay()
				return


func _launch_chapter(ch_number: int) -> void:
	StoryManagerType.selected_starting_chapter = ch_number
	_begin_scene_transition(UBEC_SCENE, "Loading UBEC...")


func _play_intro_motion() -> void:
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_new_game_btn.modulate.a = 0.0
	_cblock_btn.modulate.a = 0.0
	_banilad_btn.modulate.a = 0.0
	_chapter_btn.modulate.a = 0.0
	_quit_btn.modulate.a = 0.0
	_hint.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_title, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_subtitle, "modulate:a", 1.0, 0.55).set_delay(0.12)
	tween.tween_property(_new_game_btn, "modulate:a", 1.0, 0.4).set_delay(0.25)
	tween.tween_property(_cblock_btn, "modulate:a", 1.0, 0.4).set_delay(0.33)
	tween.tween_property(_banilad_btn, "modulate:a", 1.0, 0.4).set_delay(0.41)
	tween.tween_property(_chapter_btn, "modulate:a", 1.0, 0.4).set_delay(0.49)
	tween.tween_property(_quit_btn, "modulate:a", 1.0, 0.4).set_delay(0.57)
	tween.tween_property(_hint, "modulate:a", 1.0, 0.5).set_delay(0.67)


func _on_new_game_pressed() -> void:
	_launch_chapter(1)


func _on_cblock_pressed() -> void:
	_begin_scene_transition(CBLOCK_SCENE, "Loading CBlock city...")


func _on_banilad_pressed() -> void:
	_begin_scene_transition(BANILAD_SCENE, "Loading Banilad street map...")


func _on_quit_pressed() -> void:
	get_tree().quit()
