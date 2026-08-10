# Capture Metro Colon inside the REAL game map.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/metro_ingame_capture.gd
#
# Loads banilad_city.tscn, walks the player 4.8 km down to Colon so the tile
# streamer brings that end of the city in, then photographs the junction. This
# is the check the isolated prototype cannot make: that the model lands at the
# right world coordinates, sits on the terrain, and that the procedural landmark
# it replaces is actually hidden.
extends SceneTree

const MAP := "res://banilad_city.tscn"
# The "Metro Colon" fast-travel anchor already in banilad_city.gd::TELEPORTS.
const COLON := Vector2(-1423.0, 4215.2)
# Footprint centroid of the model.
const METRO := Vector3(-1442.1, 12.0, 4266.0)

var _map: Node3D
var _cam: Camera3D
var _frames := 0
var _moved := false


func _initialize() -> void:
	var packed: PackedScene = load(MAP)
	if packed == null:
		push_error("could not load " + MAP)
		quit(1)
		return
	_map = packed.instantiate() as Node3D
	get_root().add_child(_map)
	print("INGAME map loaded")


func _process(_delta: float) -> bool:
	_frames += 1

	# Give the map's own _ready (which awaits physics frames) time to finish,
	# then put the player at Colon so the streamer pages that district in.
	if _frames == 45 and not _moved:
		_moved = true
		var player := _map.get_node_or_null("Player") as Node3D
		if player != null:
			var y := 60.0
			var space := _map.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(COLON.x, 400.0, COLON.y), Vector3(COLON.x, -50.0, COLON.y))
			var hit := space.intersect_ray(q)
			if hit.has("position"):
				y = (hit["position"] as Vector3).y + 1.2
			player.global_position = Vector3(COLON.x, y, COLON.y)
			print("INGAME player moved to Colon y=%.2f" % y)
		_cam = Camera3D.new()
		_cam.fov = 58.0
		_cam.far = 4000.0
		_map.add_child(_cam)
		_cam.look_at_from_position(
			Vector3(METRO.x - 62.0, METRO.y + 10.0, METRO.z - 34.0),
			Vector3(METRO.x - 8.0, METRO.y + 4.0, METRO.z + 4.0), Vector3.UP)
		_cam.current = true

	# Tiles load off disk over several frames; give them room before shooting.
	if _frames == 260:
		get_root().get_texture().get_image().save_png("user://metro_ingame.png")
		print("INGAME captured -> ", ProjectSettings.globalize_path("user://metro_ingame.png"))

	if _frames == 300:
		# Second angle, from the street looking along the frontage.
		_cam.look_at_from_position(
			Vector3(METRO.x - 46.0, METRO.y - 6.0, METRO.z + 40.0),
			Vector3(METRO.x - 6.0, METRO.y + 2.0, METRO.z + 6.0), Vector3.UP)

	if _frames == 340:
		get_root().get_texture().get_image().save_png("user://metro_ingame2.png")
		print("INGAME captured2")
		print("INGAME_DONE")
		return true
	return false
