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

# Z_ROAD_COLLISION in build_map.py: how far the drive surface sits above the
# terrain under it. No longer an absolute height -- the collision plane is
# draped on real ground, so the road is near 33 m at Banilad and 11 m at Colon.
const ROAD_SURFACE_OFFSET := 0.13
# Loose, because the graph height at a junction is interpolated from several
# roads at once. Tight enough to catch the plane going missing.
const ROAD_COLLISION_TOLERANCE := 2.0
const ROAD_GRAPH := "res://assets/maps/cebu_road_graph.json"

# The regression this guards is the layer_z-staggered VISUAL ribbons regaining
# collision. build_map.py separates them by LAYER_STEP (2 mm) across up to
# LAYER_SLOTS (16) slots, so the signature is a thick stack of near-identical
# surfaces inside about 3 cm, and a wheel ray flips between them frame to frame.
#
# A pairwise-gap test was the right detector while the map was flat, because
# two collision surfaces within 5 cm could only be that artifact. On terrain it
# no longer separates them: two carriageways crossing at a junction are draped
# from the same continuous field at different tessellations, so they genuinely
# sit millimetres apart. Measured at 5-46 mm, and tessellating the collision
# mesh to 4 m only got that to 19 mm while quadrupling a never-unloaded mesh.
#
# COUNT inside the window still tells them apart: an overlap is a handful of
# surfaces, the artifact is a pile of them. The real fix for the overlap is
# junction fill quads (CITY_MASTER_PLAN.md section 3.2).
const CHATTER_BAND := 0.05
const CHATTER_MAX_SURFACES := 4

# Road junctions that measurably had the bug before Roads_Collision existed:
# (28, -682) presented surfaces 2 mm apart — exactly the layer_z stagger — and
# (40, -696) presented three inside 4.6 cm. The spawn is included as the point
# the player actually lands on.
const ROAD_PROBES: Array[Vector2] = [
	Vector2(12.79, -554.24),
	Vector2(28.0, -682.0),
	Vector2(40.0, -696.0),
	Vector2(26.0, -604.0),
]

var _level: Node3D
var _frames := 0
var _failures: Array[String] = []
var _graph_nodes: Array = []


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
	if _level.get_node_or_null("HUD/CharacterPicker") == null:
		_fail("CharacterPicker was not built by banilad_city.gd")
	if _level.get_node_or_null("DialogueChoiceUI") == null:
		_fail("DialogueChoiceUI was not built by banilad_city.gd")
	for npc_name in ["BaniladMulet", "BaniladJholo", "BaniladEdwardWalker", "BaniladStreetWalker"]:
		if _level.get_node_or_null(npc_name) == null:
			_fail("%s NPC missing" % npc_name)

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

	_check_road_collision_is_flat()
	_check_vehicles()

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

	# The map is streamed. `Level` now holds only banilad_base.glb -- the ground
	# plane and the flat road-collision surface, which are never unloaded -- and
	# the bulk of the collision arrives with whichever tiles the streamer has
	# made resident around the player.
	var level_node := region.get_node_or_null("Level")
	var streamer := region.get_node_or_null("TileStreamer")
	if level_node == null:
		_fail("Level instance missing under NavigationRegion3D")
	else:
		var base_bodies := _count_static_bodies(level_node)
		var tile_bodies := 0 if streamer == null else _count_static_bodies(streamer)
		print("[smoke] static bodies: base %d, streamed tiles %d" % [base_bodies, tile_bodies])
		# Ground and Roads_Collision. Without these the player falls through the
		# world the moment a tile is late, which is the whole point of the split.
		if base_bodies < 2:
			_fail("base map must carry ground and road collision, found %d bodies" % base_bodies)
		if streamer == null:
			_fail("TileStreamer missing under NavigationRegion3D")
		elif tile_bodies < 30:
			_fail("expected substantial collision from streamed tiles, found %d" % tile_bodies)

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


## The parked cars have to land on the carriageway rather than through it or
## on a kerb, and the interaction handover has to survive a round trip.
func _check_vehicles() -> void:
	var vehicles: Array[Node] = []
	for child in _level.get_children():
		if child.get_class() == "VehicleBody3D":
			vehicles.append(child)
	print("[smoke] parked vehicles: %d" % vehicles.size())
	if vehicles.is_empty():
		_fail("no drivable vehicles were spawned")
		return

	for vehicle in vehicles:
		var body := vehicle as VehicleBody3D
		var contacts := 0
		for child in body.get_children():
			var wheel := child as VehicleWheel3D
			if wheel != null and wheel.is_in_contact():
				contacts += 1
		var upright := body.global_basis.y.dot(Vector3.UP)
		print("[smoke]   %s y=%.2f wheels=%d upright=%.2f prompt='%s'" % [
			body.name, body.global_position.y, contacts, upright,
			body.get_interaction_prompt(),
		])
		if contacts < 4:
			_fail("%s settled with %d of 4 wheels on the road" % [body.name, contacts])
		if upright < 0.97:
			_fail("%s did not settle upright (up.y = %.2f)" % [body.name, upright])
		if body.get_interaction_prompt().is_empty():
			_fail("%s offers no interaction prompt when parked" % body.name)

	# Round-trip the handover the way pressing the interact key does.
	var target := vehicles[0] as VehicleBody3D
	var player := _level.get_node_or_null("Player") as CharacterBody3D
	target.interact(player)
	if not target.driver_active:
		_fail("interacting with %s did not start driving it" % target.name)
	if not player.is_stowed():
		_fail("player was not stowed on entering a vehicle")
	_level._exit_vehicle()
	if target.driver_active:
		_fail("exiting %s left it under driver control" % target.name)
	if player.is_stowed():
		_fail("player stayed stowed after exiting a vehicle")
	var gap := player.global_position.distance_to(target.global_position)
	print("[smoke] enter/exit round trip OK; player dropped %.2f m from the car" % gap)
	if gap < 1.0 or gap > 6.0:
		_fail("player exited %.2f m from the car (expected clear of it, not across the road)" % gap)


## The road ribbons are drawn as separate overlapping strips nudged apart by
## 2 mm so they do not z-fight. If those strips carry collision, a junction
## presents a physics ray with a stack of surfaces millimetres apart and
## VehicleWheel3D chatters between them. Only Roads_Collision should answer.
func _check_road_collision_is_flat() -> void:
	var space := _level.get_world_3d().direct_space_state
	var carriageway_hits := 0
	for probe in ROAD_PROBES:
		# The window has to follow the terrain now. It used to run 2.0 m down to
		# 0.02 m, which was right when the map was flat at zero -- on real
		# ground it starts 30 m underground at Banilad and finds nothing at all.
		var expect := _expected_road_y(probe)
		var surfaces := _surfaces_below(space, probe.x, probe.y,
			expect + 6.0, expect - 6.0)
		var above_ground: Array[float] = []
		for y in surfaces:
			above_ground.append(y)
		print("[smoke] road probe (%.2f, %.2f): surfaces above ground: %s" % [
			probe.x, probe.y, str(above_ground),
		])
		# A raised sidewalk well above the road is fine, and so are the couple of
		# draped carriageways that overlap at a junction. A PILE of surfaces
		# inside the band is the stacked-ribbon regression.
		for i in range(above_ground.size()):
			var stacked := 0
			for j in range(above_ground.size()):
				if absf(above_ground[i] - above_ground[j]) <= CHATTER_BAND:
					stacked += 1
			if stacked > CHATTER_MAX_SURFACES:
				_fail("(%.2f, %.2f) has %d collision surfaces within %.0f cm of %.3f - the layer_z stack is back"
					% [probe.x, probe.y, stacked, CHATTER_BAND * 100.0, above_ground[i]])
				break
		var on_drive_plane := false
		for y in above_ground:
			if absf(y - expect) <= ROAD_COLLISION_TOLERANCE:
				on_drive_plane = true
				carriageway_hits += 1
				break
		# Sidewalks are generated along each way's whole length; unclipped they
		# carry their kerb straight over the crossing road, which the car hits.
		if on_drive_plane:
			for y in above_ground:
				if y > expect + ROAD_COLLISION_TOLERANCE:
					_fail(
						"something sits %.2f m above the carriageway at (%.2f, %.2f)"
						% [y - expect, probe.x, probe.y]
					)

	print("[smoke] probes on the drive plane: %d of %d" % [
		carriageway_hits, ROAD_PROBES.size(),
	])
	if carriageway_hits == 0:
		_fail("no probe found the Roads_Collision drive plane")


## Walks a ray down through everything it can hit, restarting just under each
## contact, so coplanar-but-not-identical surfaces are all reported.
func _expected_road_y(probe: Vector2) -> float:
	## Where the road graph says the drive surface is at this spot.
	## The probes sit on junctions, so the nearest graph node is the right
	## reference; taking it from the graph is also what makes this a real
	## cross-check between the mesh and the data traffic will be driven from.
	if _graph_nodes.is_empty():
		var text := FileAccess.get_file_as_string(ROAD_GRAPH)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			_graph_nodes = parsed.get("nodes", [])
	var best := 0.0
	var best_distance := INF
	for node in _graph_nodes:
		var p: Array = node["p"]
		var d := Vector2(float(p[0]) - probe.x, float(p[1]) - probe.y).length_squared()
		if d < best_distance:
			best_distance = d
			best = float(node["y"])
	return best + ROAD_SURFACE_OFFSET


func _surfaces_below(
	space: PhysicsDirectSpaceState3D,
	x: float,
	z: float,
	top: float,
	bottom: float
) -> Array[float]:
	var found: Array[float] = []
	var cursor := top
	while cursor > bottom and found.size() < 24:
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, cursor, z), Vector3(x, bottom, z)
		)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var y := float(hit.position.y)
		found.append(y)
		# Step below this contact by less than the 2 mm visual stagger, so a
		# stack would still be resolved one surface at a time.
		cursor = y - 0.001
	return found


func _count_static_bodies(root: Node) -> int:
	var count := 0
	for child in root.get_children():
		if child is StaticBody3D:
			count += 1
		count += _count_static_bodies(child)
	return count


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
