extends SceneTree
## Headless verification for banilad_city.tscn.
##
##   Godot_v4.7-stable_win64.exe --headless --path . --script res://scripts/tools/banilad_smoke_test.gd

const LEVEL := "res://banilad_city.tscn"

# Two points on Gov. M. Cuenco Avenue: the spawn and the Petron station.
const PATH_FROM := Vector3(12.79, 0.5, -554.24)
const PATH_TO := Vector3(-2.68, 0.5, -338.69)

const SETTLE_FRAMES := 90
const NAV_TIMEOUT_FRAMES := 1200

var _level: Node3D
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_fail("could not load %s" % LEVEL)
		_finish()
		return
	_level = packed.instantiate()
	root.add_child(_level)
	print("[smoke] instantiated %s" % LEVEL)


func _process(_delta: float) -> bool:
	_frames += 1
	# Give physics time to drop the player onto the road.
	if _frames < SETTLE_FRAMES:
		return false
	# A 21k-polygon navmesh takes a variable number of frames to synchronise
	# onto the navigation map, so poll for it rather than assume a frame count.
	if _frames < NAV_TIMEOUT_FRAMES and not _navigation_ready():
		return false
	_run_checks()
	_finish()
	return true


func _navigation_ready() -> bool:
	var region := _level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region == null:
		return true
	var map: RID = region.get_navigation_map()
	NavigationServer3D.map_force_update(map)
	return NavigationServer3D.map_get_closest_point(map, PATH_FROM) != Vector3.ZERO


func _run_checks() -> void:
	# A script that fails to parse leaves the node scriptless rather than
	# stopping instantiation, so every other check below would pass on a scene
	# that does nothing. Catch that first.
	if _level.get_script() == null:
		_fail("banilad_city.gd did not attach (check the log for a parse error)")
	if _level.get_node_or_null("PauseMenu") == null:
		_fail("PauseMenu was not built by banilad_city.gd")

	var player := _level.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_fail("Player node missing")
	else:
		var pos := player.global_position
		print("[smoke] player position: (%.2f, %.2f, %.2f)" % [pos.x, pos.y, pos.z])
		print("[smoke] player on floor: %s" % str(player.is_on_floor()))
		if pos.y < -5.0:
			_fail("player fell through the map (y = %.2f)" % pos.y)
		if not player.is_on_floor():
			_fail("player never landed on a collider")

	var region := _level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if region == null:
		_fail("NavigationRegion3D missing")
		return

	var nav := region.navigation_mesh
	if nav == null:
		_fail("navigation mesh not assigned")
		return
	print("[smoke] navmesh polygons: %d" % nav.get_polygon_count())
	if nav.get_polygon_count() <= 0:
		_fail("navigation mesh has no polygons")

	var level_node := region.get_node_or_null("Level")
	if level_node == null:
		_fail("Level instance missing under NavigationRegion3D")
	else:
		var bodies := 0
		for child in level_node.get_children():
			if child is StaticBody3D:
				bodies += 1
			for grandchild in child.get_children():
				if grandchild is StaticBody3D:
					bodies += 1
		print("[smoke] static bodies under level: %d" % bodies)
		if bodies < 50:
			_fail("expected many static bodies, found %d" % bodies)

	var map: RID = region.get_navigation_map()
	print("[smoke] nav map synced after %d frames (%d region(s))" % [
		_frames, NavigationServer3D.map_get_regions(map).size(),
	])
	var path := NavigationServer3D.map_get_path(map, PATH_FROM, PATH_TO, true)
	var straight := PATH_FROM.distance_to(PATH_TO)
	print("[smoke] path points: %d" % path.size())
	if path.size() >= 2:
		var walked := 0.0
		for i in range(path.size() - 1):
			walked += path[i].distance_to(path[i + 1])
		print("[smoke] path length: %.1f m (straight line %.1f m)" % [walked, straight])
		var last: Vector3 = path[path.size() - 1]
		var miss := Vector2(last.x - PATH_TO.x, last.z - PATH_TO.z).length()
		print("[smoke] path endpoint miss: %.2f m" % miss)
		if miss > 15.0:
			_fail("path does not reach the destination (%.1f m short)" % miss)
	else:
		_fail("navigation returned no usable path")


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[smoke] FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[smoke] ALL CHECKS PASSED")
		quit(0)
	else:
		print("[smoke] %d CHECK(S) FAILED" % _failures.size())
		quit(1)
