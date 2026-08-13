# Capture the citizen creator inside the REAL game.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/citizen_creator_capture.gd
#
# NOT --headless: this renders.
#
# Loads banilad_city.tscn, opens the C-key picker, opens Customize, and
# photographs the panel with the live player behind it -- then cycles a couple
# of parts and shoots again, so the PNGs show that the preview really is the
# citizen standing in the world rather than a separate render.
#
# This is the check the isolated capture cannot make: that the customizer is
# reachable through the game's own UI, that switching to the citizen from the
# picker works, and that the panel leaves the player visible beside it.
extends SceneTree

const MAP := "res://banilad_city.tscn"

var _map: Node3D
var _frames := 0
var _stage := 0
var _shot := 0


func _initialize() -> void:
	var packed: PackedScene = load(MAP)
	if packed == null:
		push_error("could not load " + MAP)
		quit(1)
		return
	_map = packed.instantiate() as Node3D
	get_root().add_child(_map)
	print("CREATOR map loaded")


func _snap(name: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png("user://%s.png" % name)
	print("CAP ", name)
	_shot += 1


func _process(_delta: float) -> bool:
	_frames += 1
	# banilad_city's own _ready awaits physics frames before the player exists.
	if _frames < 60:
		return false

	match _stage:
		0:
			_map.call("_open_character_picker")
			print("CREATOR picker open")
			_stage = 1
			_frames = 0
		1:
			if _frames < 12:
				return false
			_snap("citizen_creator_picker")
			_map.call("_open_citizen_customizer")
			print("CREATOR customizer open, character=",
				_map.get_node("Player").call("get_character_id"))
			_stage = 2
			_frames = 0
		2:
			if _frames < 25:
				return false
			_snap("citizen_creator_panel")
			# Esc must get you out. The panel outgrew the screen once and took
			# Save and Cancel off the bottom with it, so the keyboard route is
			# the one that has to keep working no matter what the layout does.
			var escape := InputEventAction.new()
			escape.action = &"pause"
			escape.pressed = true
			Input.parse_input_event(escape)
			_stage = 3
			_frames = 0
		3:
			if _frames < 8:
				return false
			print("CREATOR esc closed customizer: ", not bool(_map.get("_customizer_open")))
			_map.call("_open_citizen_customizer")
			# Cycle to a different top and hairstyle through the same code path
			# the buttons use, so the shot proves the wiring, not just the layout.
			_map.call("_cycle_part", "top", 2)
			_map.call("_cycle_part", "hair", 1)
			_map.call("_pick_colour", "top",
				CitizenAppearance.slot_palette("top")[2])
			_stage = 4
			_frames = 0
		4:
			if _frames < 25:
				return false
			_snap("citizen_creator_changed")
			_map.call("_save_appearance")
			_stage = 5
			_frames = 0
		5:
			if _frames < 20:
				return false
			_snap("citizen_creator_saved")
			var saved = load("res://scripts/cblock_character_roster.gd").get_appearance()
			print("CREATOR saved look: ", saved.describe())
			print("CREATOR_DONE")
			return true
	return false
