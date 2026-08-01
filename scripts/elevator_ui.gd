extends CanvasLayer
class_name ElevatorUI

const SchoolBuildingType = preload("res://scripts/school_building.gd")

signal floor_selected(floor_index: int)
signal closed()

@onready var panel: ColorRect = ColorRect.new()
@onready var container: VBoxContainer = VBoxContainer.new()
@onready var title: Label = Label.new()

func _ready() -> void:
	layer = 100
	visible = false
	
	# Center Container to hold the panel
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	# Background Panel
	panel.color = Color("1a1c1d")
	panel.custom_minimum_size = Vector2(330, 620)
	center.add_child(panel)
	
	# Container
	container.add_theme_constant_override("separation", 10)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(margin)
	margin.add_child(container)
	
	# Title
	title.text = "ELEVATOR DIRECTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("a89f91"))
	container.add_child(title)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	container.add_child(spacer)
	
	# One button per playable level, listed top-down like a real car panel.
	var level_count: int = SchoolBuildingType.LEVEL_COUNT
	for i in range(level_count):
		var level: int = level_count - 1 - i
		var btn = Button.new()
		btn.text = "%s - %s" % [
			SchoolBuildingType.level_label(level),
			SchoolBuildingType.LEVEL_SUBTITLES[level],
		]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func(): _on_floor_pressed(level))
		container.add_child(btn)
		
	# Close button
	var close_spacer = Control.new()
	close_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(close_spacer)
	
	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.add_theme_color_override("font_color", Color("c44f4f"))
	close_btn.pressed.connect(_on_close_pressed)
	container.add_child(close_btn)

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_floor_pressed(floor_index: int) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_selected.emit(floor_index)

func _on_close_pressed() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
