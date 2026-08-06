extends SceneTree
## Can the player actually walk the terrain?
##
##   .tools/godot/Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/slope_smoke_test.gd
##
## curb_step_smoke_test and vehicle_smoke_test both build synthetic FLAT
## scenes, so until now nothing had driven or walked a gradient at all --
## `max_step_height 0.45` and gravity 18.0 had only ever met level ground.
## Phase 2 gave the map a 22.8 m descent down Osmena Boulevard and hill roads
## reaching 165 m, so that gap matters.
##
## Test sites are located from the road graph rather than hardcoded, so this
## keeps testing real gradients as the map grows.

const LEVEL := "res://banilad_city.tscn"
const ROAD_GRAPH := "res://assets/maps/cebu_road_graph.json"

const SETTLE_FRAMES := 90
const PLACE_FRAMES := 30      # after teleporting, before trusting the state
const WALK_FRAMES := 120

# Gradients to look for. Below 3% is not a meaningful test; above 14% is beyond
# what the clamp leaves on drivable roads.
const MIN_GRADE := 0.03
const MAX_GRADE := 0.14
const MIN_EDGE_LENGTH := 45.0
const SITES := 4

const FOOT_CLASSES := ["footway", "path", "steps", "pedestrian"]

# The player must stay within this of the ground under them. A capsule sitting
# on a surface rides about half its height above the contact point.
const GROUND_CLEARANCE := 2.0

var _level: Node3D
var _player: CharacterBody3D
var _sites: Array = []
var _site := -1
var _frames := 0
var _stage := 0
var _walk_dir := Vector3.ZERO
var _start := Vector3.ZERO
var _start_height := 0.0
var _grounded_frames := 0
var _walk_time := 0.0
var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_fail("could not load %s" % LEVEL)
		_finish()
		return
	_level = packed.instantiate()
	root.add_child(_level)
	_player = _level.get_node_or_null("Player") as CharacterBody3D
	if _player == null:
		_fail("no Player in %s" % LEVEL)
		_finish()
		return
	_sites = _find_slopes()
	print("[slope] %d test site(s) found" % _sites.size())
	if _sites.is_empty():
		_fail("no drivable edge between %.0f%% and %.0f%% grade - the map has no testable slope"
			% [MIN_GRADE * 100.0, MAX_GRADE * 100.0])


func _find_slopes() -> Array:
	## Steepest qualifying edges, spread across the map so one bad junction
	## cannot make the whole test look fine.
	var text := FileAccess.get_file_as_string(ROAD_GRAPH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var nodes: Array = parsed["nodes"]
	var candidates := []
	for edge in parsed["edges"]:
		if FOOT_CLASSES.has(edge["cls"]):
			continue
		var pts: Array = edge["pts"]
		var length := 0.0
		for i in range(pts.size() - 1):
			length += Vector2(float(pts[i][0]), float(pts[i][1])).distance_to(
				Vector2(float(pts[i + 1][0]), float(pts[i + 1][1])))
		if length < MIN_EDGE_LENGTH:
			continue
		var ha := float(nodes[edge["a"]]["y"])
		var hb := float(nodes[edge["b"]]["y"])
		var grade: float = absf(hb - ha) / length
		if grade < MIN_GRADE or grade > MAX_GRADE:
			continue
		# Always walk downhill: the top node first.
		var high: Array = nodes[edge["a"]]["p"] if ha >= hb else nodes[edge["b"]]["p"]
		var low: Array = nodes[edge["b"]]["p"] if ha >= hb else nodes[edge["a"]]["p"]
		candidates.append({
			"grade": grade,
			"name": edge["name"],
			"high": Vector2(float(high[0]), float(high[1])),
			"low": Vector2(float(low[0]), float(low[1])),
			"top": maxf(ha, hb),
			"drop": absf(hb - ha),
		})
	candidates.sort_custom(func(a, b): return a["grade"] > b["grade"])

	# Spread the picks out rather than taking the four steepest, which would
	# all sit on the same hillside.
	var chosen := []
	for candidate in candidates:
		var far := true
		for taken in chosen:
			if candidate["high"].distance_to(taken["high"]) < 400.0:
				far = false
				break
		if far:
			chosen.append(candidate)
		if chosen.size() >= SITES:
			break
	return chosen


func _process(delta: float) -> bool:
	if _player == null or _sites.is_empty():
		_finish()
		return true
	_frames += 1

	match _stage:
		0:
			if _frames < SETTLE_FRAMES:
				return false
			_next_site()
		1:
			# Let the teleport settle before believing anything about it.
			if _frames < PLACE_FRAMES:
				_player.velocity = Vector3.ZERO
				return false
			_start = _player.global_position
			_start_height = _start.y
			_grounded_frames = 0
			_walk_time = 0.0
			_frames = 0
			_stage = 2
		2:
			# Input actions never arrive in a headless SceneTree, so drive the
			# body directly and let the controller's own gravity, floor snap
			# and step-up run off it -- exactly as curb_step_smoke_test does.
			_player.velocity.x = _walk_dir.x * _player.walk_speed
			_player.velocity.z = _walk_dir.z * _player.walk_speed
			if _player.is_on_floor():
				_grounded_frames += 1
			_walk_time += delta
			if _frames < WALK_FRAMES:
				return false
			_judge()
			_next_site()
	return false


func _next_site() -> void:
	_site += 1
	if _site >= _sites.size():
		_finish()
		return
	var site: Dictionary = _sites[_site]
	var high: Vector2 = site["high"]
	var low: Vector2 = site["low"]
	# Drop in from above and let physics seat the capsule: the terrain height
	# here is whatever the map says it is, not something the test should assume.
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(high.x, float(site["top"]) + 1.5, high.y)
	_walk_dir = Vector3(low.x - high.x, 0.0, low.y - high.y).normalized()
	print("[slope] site %d: %s, %.1f%% grade, %.1f m drop" % [
		_site + 1,
		"(unnamed)" if String(site["name"]).is_empty() else site["name"],
		float(site["grade"]) * 100.0, float(site["drop"]),
	])
	_frames = 0
	_stage = 1


func _judge() -> void:
	var site: Dictionary = _sites[_site]
	var label: String = "site %d (%s)" % [
		_site + 1,
		"(unnamed)" if String(site["name"]).is_empty() else site["name"],
	]
	var here := _player.global_position
	var travelled := Vector2(here.x - _start.x, here.z - _start.z).length()
	var descended := _start_height - here.y
	var grounded := float(_grounded_frames) / float(WALK_FRAMES)
	var ground := _ground_under(here)
	var clearance := here.y - ground

	# Measured against how far a walk SHOULD carry in the time that actually
	# elapsed, not a distance guessed from a frame count. _process is the idle
	# callback and does not run at the physics rate, so a fixed metre threshold
	# is really a hidden assumption about frame timing -- which is what made
	# the first run of this test report four false failures.
	var expected: float = _player.walk_speed * _walk_time
	print("[slope]   moved %.1f m of an expected %.1f m in %.2f s, dropped %.2f m, grounded %.0f%%, %.2f m above ground"
		% [travelled, expected, _walk_time, descended, grounded * 100.0, clearance])

	# 1. Did they actually go anywhere? A capsule snagging on the terrain
	#    tessellation would stall here. Downhill costs a little horizontal
	#    distance to the slope, so this is a floor, not a target.
	_check(expected > 0.0 and travelled > expected * 0.5,
		"%s: player moved %.1f m where %.1f m was expected in %.2f s"
		% [label, travelled, expected, _walk_time])
	# 2. Feet on the ground. Some airborne frames are fine over a convex break;
	#    persistently airborne means the floor snap is losing the surface.
	_check(grounded > 0.6, "%s: player was airborne for %.0f%% of the walk"
		% [label, (1.0 - grounded) * 100.0])
	# 3. Still on the surface, not sunk into it or riding above it.
	_check(is_finite(ground) and clearance < GROUND_CLEARANCE,
		"%s: player is %.2f m above the ground under them" % [label, clearance])
	_check(is_finite(ground) and clearance > -0.5,
		"%s: player has sunk %.2f m into the terrain" % [label, -clearance])
	# 4. Walking downhill should lose height.
	_check(descended > 0.0, "%s: walked downhill but gained %.2f m" % [label, -descended])


func _ground_under(point: Vector3) -> float:
	var space := _level.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(point.x, point.y + 100.0, point.z),
		Vector3(point.x, point.y - 60.0, point.z), 1)
	query.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(query)
	return NAN if hit.is_empty() else float(hit["position"].y)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[slope] FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("SLOPE_SMOKE_TEST_OK")
		quit(0)
	else:
		print("SLOPE_SMOKE_TEST_FAIL: %d check(s) failed" % _failures.size())
		for message in _failures:
			print("  - %s" % message)
		quit(1)
