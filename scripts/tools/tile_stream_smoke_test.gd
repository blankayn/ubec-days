extends SceneTree
## Headless verification for the 250 m tile streamer.
##
##   Godot_v4.7-stable_win64.exe --headless --path . --script res://scripts/tools/tile_stream_smoke_test.gd
##
## Walks a scripted route across the map and checks the three things that make
## streaming safe rather than merely cheap:
##
##   1. There is solid ground under the player at every point on the route.
##      Ground and the flat road-collision plane ship in banilad_base.glb and
##      are never unloaded, so a car cannot fall through a tile that has not
##      finished loading -- this asserts that stays true.
##   2. No single frame instantiates more than one tile, which is what bounds
##      the hitch when driving fast.
##   3. Tiles genuinely load AND unload, and the resident count stays within
##      budget -- otherwise the streamer is silently doing nothing.

const LEVEL := "res://banilad_city.tscn"

const SETTLE_FRAMES := 20
const FRAMES_PER_WAYPOINT := 12

## Roughly the Banilad spawn, north-east through the corridor, then south-west
## across IT Park and up into Lahug: about 2.6 km of real map.
const ROUTE: Array[Vector2] = [
	Vector2(12.79, -554.24),
	Vector2(0.0, -400.0),
	Vector2(-40.0, -200.0),
	Vector2(-80.0, 0.0),
	Vector2(-200.0, 150.0),
	Vector2(-350.0, 300.0),
	Vector2(-460.0, 419.0),
	Vector2(-560.0, 560.0),
	Vector2(-660.0, 700.0),
	Vector2(-800.0, 820.0),
	Vector2(-950.0, 950.0),
	Vector2(-1100.0, 1050.0),
]

## At a 400 m load radius over 250 m tiles the reachable set is about 5x5, and
## fewer than half the grid cells carry geometry. A ceiling well above that
## still catches a runaway that never unloads.
const MAX_RESIDENT := 60

var _level: Node3D
var _streamer: Node = null
var _player: Node3D = null
var _frames := 0
var _waypoint := 0
var _hold := 0
var _failures: Array[String] = []

var _seen_resident := {}
var _unloaded_any := false
var _prev_keys := {}
var _max_instantiated := 0
var _no_ground := 0
var _probes := 0


func _initialize() -> void:
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_fail("could not load %s" % LEVEL)
		_finish()
		return
	_level = packed.instantiate()
	root.add_child(_level)
	_streamer = _level.get_node_or_null("NavigationRegion3D/TileStreamer")
	_player = _level.get_node_or_null("Player") as Node3D
	if _streamer == null:
		_fail("banilad_city.tscn has no NavigationRegion3D/TileStreamer")
	if _player == null:
		_fail("banilad_city.tscn has no Player")


func _process(_delta: float) -> bool:
	if _streamer == null or _player == null:
		_finish()
		return true

	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false

	if _frames == SETTLE_FRAMES:
		print("[tiles] manifest: %d tiles" % _streamer.tile_count())
		_check(_streamer.tile_count() > 0,
			"tile manifest is empty - run prep_godot.py")
		_check(_streamer.resident_count() > 0,
			"nothing was primed around the spawn; the first frame would be an empty city")
		print("[tiles] primed at spawn: %d resident" % _streamer.resident_count())

	# One waypoint at a time, holding for a few frames so the streamer can work.
	if _hold == 0:
		if _waypoint >= ROUTE.size():
			_report()
			_finish()
			return true
		var p: Vector2 = ROUTE[_waypoint]
		_player.global_position = Vector3(p.x, 1.2, p.y)
		_waypoint += 1
		_hold = FRAMES_PER_WAYPOINT
	_hold -= 1

	_sample()
	return false


func _sample() -> void:
	_max_instantiated = maxi(_max_instantiated, _streamer.instantiated_last_frame())

	var keys := {}
	for key in _streamer_keys():
		keys[key] = true
		_seen_resident[key] = true
	for key in _prev_keys:
		if not keys.has(key):
			_unloaded_any = true
	_prev_keys = keys

	# The load-bearing check: something solid under the player, always.
	var origin := _player.global_position
	var space := _level.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(origin.x, 60.0, origin.z), Vector3(origin.x, -20.0, origin.z), 1)
	query.exclude = [(_player as CollisionObject3D).get_rid()]
	_probes += 1
	if space.intersect_ray(query).is_empty():
		_no_ground += 1
		if _no_ground <= 4:
			printerr("[tiles] no ground under (%.1f, %.1f)" % [origin.x, origin.z])


func _streamer_keys() -> Array:
	var out: Array = []
	for child in _streamer.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			out.append(child.name)
	return out


func _report() -> void:
	print("[tiles] route waypoints: %d, ground probes: %d" % [ROUTE.size(), _probes])
	print("[tiles] distinct tiles made resident over the route: %d" % _seen_resident.size())
	print("[tiles] peak resident: %d (ceiling %d)" % [_streamer.peak_resident(), MAX_RESIDENT])
	print("[tiles] most tiles instantiated in one frame: %d" % _max_instantiated)

	_check(_no_ground == 0,
		"%d of %d route probes had no collision under the player" % [_no_ground, _probes])
	_check(_max_instantiated <= 1,
		"a frame instantiated %d tiles; the per-frame budget is 1" % _max_instantiated)
	_check(_streamer.peak_resident() <= MAX_RESIDENT,
		"peak resident tiles %d exceeds the %d ceiling" % [_streamer.peak_resident(), MAX_RESIDENT])
	_check(_seen_resident.size() > _streamer.peak_resident(),
		"the route never streamed anything new in; the streamer may be inert")
	_check(_unloaded_any, "no tile was ever unloaded over a 2.6 km route")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[tiles] FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("TILE_STREAM_SMOKE_TEST_OK")
		quit(0)
	else:
		print("TILE_STREAM_SMOKE_TEST_FAIL: %d check(s) failed" % _failures.size())
		for message in _failures:
			print("  - %s" % message)
		quit(1)
