extends CanvasLayer

@onready var objective_label: Label = $Root/ObjectivePanel/Objective
@onready var prompt_label: Label = $Root/Prompt
@onready var message_label: Label = $Root/MessagePanel/Message
@onready var controls_label: Label = $Root/Controls
@onready var flash_rect: ColorRect = $Root/FlashRect  # NEW — added in main.tscn

var _message_generation := 0
var _flash_tween: Tween = null
var _battery_panel: PanelContainer
var _battery_bar: ProgressBar
var _battery_label: Label


@onready var message_panel: ColorRect = $Root/MessagePanel


func _ready() -> void:
	_apply_readable_text_scale()
	_build_battery_panel()
	set_prompt("")
	set_chapter_objective("CH 1  DAY ERRANDS  00 / 02\nNEXT: Locker · GF · School front (exterior, left of gate)")
	message_panel.visible = false
	message_label.visible = false
	get_tree().create_timer(8.0).timeout.connect(_hide_controls)
	if flash_rect:
		flash_rect.color = Color(0, 0, 0, 0)
		flash_rect.visible = true


func _build_battery_panel() -> void:
	var root := $Root
	_battery_panel = PanelContainer.new()
	_battery_panel.name = "BatteryPanel"
	_battery_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_battery_panel.position = Vector2(-286, -136)
	_battery_panel.size = Vector2(250, 88)
	_battery_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.04, 0.045, 0.88)
	panel_style.border_color = Color("748c72")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 7
	panel_style.content_margin_bottom = 7
	_battery_panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(_battery_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_battery_panel.add_child(column)
	_battery_label = Label.new()
	_battery_label.text = "FLASHLIGHT BATTERY  100%"
	_battery_label.add_theme_font_size_override("font_size", 16)
	_battery_label.add_theme_color_override("font_color", Color("d8e8bd"))
	column.add_child(_battery_label)
	_battery_bar = ProgressBar.new()
	_battery_bar.max_value = 100.0
	_battery_bar.value = 100.0
	_battery_bar.show_percentage = false
	_battery_bar.custom_minimum_size = Vector2(220, 22)
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color("111b1a")
	bar_background.set_corner_radius_all(2)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("b9d970")
	bar_fill.set_corner_radius_all(2)
	_battery_bar.add_theme_stylebox_override("background", bar_background)
	_battery_bar.add_theme_stylebox_override("fill", bar_fill)
	column.add_child(_battery_bar)


func set_battery(percent: float, available: bool = true) -> void:
	if _battery_panel == null:
		return
	_battery_panel.visible = available
	if not available:
		return
	var clamped := clampf(percent, 0.0, 100.0)
	_battery_bar.value = clamped
	_battery_label.text = "FLASHLIGHT BATTERY  %03d%%" % roundi(clamped)
	var fill := _battery_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null:
		fill.bg_color = Color("b9d970") if clamped > 50.0 else (Color("d7a85e") if clamped > 20.0 else Color("d85a54"))


func _apply_readable_text_scale() -> void:
	# Scale HUD copy for the project's 2560x1440 viewport so dialogue stays legible.
	var scale := clampf(get_viewport().get_visible_rect().size.y / 1440.0, 0.85, 1.35)
	objective_label.add_theme_font_size_override("font_size", int(22 * scale))
	objective_label.add_theme_constant_override("outline_size", int(5 * scale))
	prompt_label.add_theme_font_size_override("font_size", int(28 * scale))
	prompt_label.add_theme_constant_override("outline_size", int(6 * scale))
	message_label.add_theme_font_size_override("font_size", int(32 * scale))
	message_label.add_theme_constant_override("outline_size", int(7 * scale))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = not text.is_empty()


func set_objective(current: int, total: int) -> void:
	objective_label.text = "UBEC\nINSPECTIONS  %02d / %02d" % [current, total]


func set_chapter_objective(text: String) -> void:
	objective_label.text = text


func show_message(text: String, duration: float = 5.0) -> void:
	_message_generation += 1
	var generation := _message_generation
	message_label.text = text
	message_label.visible = true
	message_panel.visible = true
	# Give longer lines enough time to read — no typewriter delay.
	var read_time := maxf(duration, float(text.length()) * 0.06 + 3.5)
	await get_tree().create_timer(read_time).timeout
	if generation == _message_generation:
		message_label.visible = false
		message_panel.visible = false


## Flash the screen with a color — used for the day/night transition.
## color.a controls peak opacity; duration is fade-in + fade-out time.
func screen_flash(color: Color, duration: float) -> void:
	if flash_rect == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	flash_rect.color = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_rect, "color:a", 0.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _hide_controls() -> void:
	controls_label.visible = false
