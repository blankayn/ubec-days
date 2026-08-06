extends SceneTree
## Headless verification for assets/maps/cebu_road_graph.json.
##
##   Godot_v4.7-stable_win64.exe --headless --path . --script res://scripts/tools/road_graph_smoke_test.gd
##
## The graph is what Phases 6 and 7 drive traffic and pedestrians along. The
## thing that actually matters is not that the JSON parses -- it is that the
## graph agrees with the collision geometry the same build produced. If the
## width or lane count in the graph disagrees with the ribbon that was built,
## traffic drives through kerbs, and nothing else in the pipeline would notice.
##
## So the load-bearing checks here are physical: sampled graph nodes, and the
## lane centrelines derived from them, must land on the flat road-collision
## plane at Z_ROAD_COLLISION.

const LEVEL := "res://banilad_city.tscn"
const GRAPH := "res://assets/maps/cebu_road_graph.json"

const SETTLE_FRAMES := 90

# Z_ROAD_COLLISION in build_map.py: how far the collision surface sits above
# the terrain beneath it. It is no longer an absolute height -- the collision
# plane is draped onto real ground now, so the road at Banilad is near 33 m and
# at Colon near 11 m.
const ROAD_SURFACE_OFFSET := 0.13

# How far the collision surface may sit from the height the GRAPH claims for
# that spot. This is the check that matters after terrain: if the mesh and the
# graph disagree, traffic driven from the graph floats or sinks. Generous
# because ground near a junction is interpolated from several roads at once.
const SURFACE_TOLERANCE := 2.0

# Start every probe above the tallest structure on the map (38 Park Avenue, at
# 124 m) so the ray always descends through clear air. Starting lower can begin
# inside a building and report its interior as the ground.
const RAY_TOP := 300.0

# Classes that carry no entry in Roads_Collision, so nothing may be sampled on
# them. Mirrors FOOT_ROADS in build_map.py.
const FOOT_CLASSES := ["footway", "path", "steps", "pedestrian"]

# build_map.py's ground plane is GROUND_HALF = 1250 m. `out geom` returns whole
# ways that merely clip the Overpass bbox, so a minority of graph nodes sit off
# the end of the map entirely. Those are not sampled.
const GROUND_LIMIT := 1200.0

# Sampling. The graph has ~1800 nodes and ~2200 edges; raycasting all of them
# headless is slow and adds nothing over a spread sample.
const NODE_SAMPLE_STRIDE := 4
const EDGE_SAMPLE_STRIDE := 11

# How far along an incident edge to step before probing a node. See
# _check_nodes_on_road for why probing the node itself is unreliable.
const NODE_INSET := 1.0

# Fraction of sampled probes that must land on the carriageway. Not 100%:
# a node can legitimately sit under the mall walkway, on a bridge deck, or on
# a way whose collision ribbon was dropped for being degenerate.
const MIN_ON_ROAD := 0.90

# The drivable network fragments where the Overpass bbox severs a street whose
# continuation lies wholly outside it. Every disconnected component in the
# current extract touches the bbox edge. This is a regression bound, not a
# purity target -- it should climb as the extent grows.
const MIN_LARGEST_COMPONENT := 0.70

# Spine roads that must exist inside the CURRENT bbox, with a plausible length.
# Gorordo, Osmena and Escario are deliberately absent until the extent moves.
const REQUIRED_ROADS := {
	"Governor M. Cuenco Avenue": 1500.0,
	"Archbishop Reyes Avenue": 400.0,
	"Salinas Drive": 800.0,
}

var _level: Node3D
var _graph: Dictionary
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(GRAPH)
	if text.is_empty():
		_fail("could not read %s" % GRAPH)
		_finish()
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("nodes") or not parsed.has("edges"):
		_fail("%s is not a road graph document" % GRAPH)
		_finish()
		return
	_graph = parsed
	print("[roadgraph] %d nodes, %d edges" % [_graph["nodes"].size(), _graph["edges"].size()])

	# Everything that does not need physics runs before the scene loads, so a
	# structural break is reported even if the map fails to instantiate.
	_check_structure()
	_check_named_roads()
	_check_connectivity()

	var packed := load(LEVEL) as PackedScene
	if packed == null:
		_fail("could not load %s" % LEVEL)
		_finish()
		return
	_level = packed.instantiate()
	root.add_child(_level)


func _process(_delta: float) -> bool:
	if _level == null:
		return true
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	_check_nodes_on_road()
	_check_lanes_on_road()
	_finish()
	return true


# --- Structure --------------------------------------------------------------

func _check_structure() -> void:
	var nodes: Array = _graph["nodes"]
	var edges: Array = _graph["edges"]
	if nodes.is_empty() or edges.is_empty():
		_fail("graph is empty")
		return

	var bad_index := 0
	var bad_endpoint := 0
	var degenerate := 0
	var worst := 0.0
	for edge in edges:
		var a: int = edge["a"]
		var b: int = edge["b"]
		if a < 0 or a >= nodes.size() or b < 0 or b >= nodes.size():
			bad_index += 1
			continue
		var pts: Array = edge["pts"]
		if pts.size() < 2:
			degenerate += 1
			continue
		# An edge must physically start and end at the nodes it names, or the
		# network is a lie and routing will teleport.
		var da := _xz(nodes[a]["p"]).distance_to(_xz(pts[0]))
		var db := _xz(nodes[b]["p"]).distance_to(_xz(pts[-1]))
		worst = maxf(worst, maxf(da, db))
		if da > 0.05 or db > 0.05:
			bad_endpoint += 1

	_check(bad_index == 0, "%d edge(s) reference an out-of-range node" % bad_index)
	_check(degenerate == 0, "%d edge(s) have fewer than 2 points" % degenerate)
	_check(bad_endpoint == 0, "%d edge(s) do not start/end on their nodes" % bad_endpoint)
	print("[roadgraph] worst endpoint/node mismatch: %.4f m" % worst)

	# The graph publishes lane_width = width / lanes, so the lanes tile the
	# carriageway exactly. Anything else would put an outer lane centreline
	# past the kerb.
	var overflow := 0
	var missing_lane_width := 0
	for edge in edges:
		if FOOT_CLASSES.has(edge["cls"]):
			continue
		var lanes: int = edge["lanes"]
		if lanes <= 0:
			continue
		if not edge.has("lane_width"):
			missing_lane_width += 1
			continue
		if float(lanes) * float(edge["lane_width"]) > float(edge["width"]) + 0.05:
			overflow += 1
	_check(missing_lane_width == 0, "%d edge(s) have no lane_width" % missing_lane_width)
	_check(overflow == 0, "%d edge(s) have lanes that overflow their carriageway" % overflow)

	var signals := 0
	var crossings := 0
	for node in nodes:
		if node["signal"]:
			signals += 1
		if node["crossing"]:
			crossings += 1
	print("[roadgraph] %d signals, %d crossings" % [signals, crossings])
	# node["highway"] was absent from the Overpass query until Phase 0. If this
	# is zero again, the query regressed and Phase 6 has nothing to work with.
	_check(crossings > 0, "no pedestrian crossings: node[\"highway\"] is missing from overpass_query.txt")


func _check_named_roads() -> void:
	var length_by_name := {}
	for edge in _graph["edges"]:
		var name: String = edge["name"]
		if name.is_empty():
			continue
		var total: float = length_by_name.get(name, 0.0)
		var pts: Array = edge["pts"]
		for i in range(pts.size() - 1):
			total += _xz(pts[i]).distance_to(_xz(pts[i + 1]))
		length_by_name[name] = total

	for name in REQUIRED_ROADS:
		var want: float = REQUIRED_ROADS[name]
		var got: float = length_by_name.get(name, 0.0)
		_check(got >= want, "%s: expected at least %.0f m of carriageway, graph has %.0f m"
			% [name, want, got])
	print("[roadgraph] %d named streets" % length_by_name.size())


func _check_connectivity() -> void:
	# Union-find over drivable edges only; footways are a separate network.
	var parent := PackedInt32Array()
	parent.resize(_graph["nodes"].size())
	for i in range(parent.size()):
		parent[i] = i

	var drivable := 0
	var touched := {}
	for edge in _graph["edges"]:
		if FOOT_CLASSES.has(edge["cls"]):
			continue
		drivable += 1
		var a: int = edge["a"]
		var b: int = edge["b"]
		touched[a] = true
		touched[b] = true
		var ra := _find(parent, a)
		var rb := _find(parent, b)
		if ra != rb:
			parent[ra] = rb

	var sizes := {}
	var best := 0
	for node_index in touched:
		var root := _find(parent, node_index)
		var size: int = sizes.get(root, 0) + 1
		sizes[root] = size
		best = maxi(best, size)

	var fraction := float(best) / maxf(float(touched.size()), 1.0)
	print("[roadgraph] drivable: %d edges, %d nodes, largest component %d (%.1f%%)"
		% [drivable, touched.size(), best, fraction * 100.0])
	_check(fraction >= MIN_LARGEST_COMPONENT,
		"largest drivable component holds only %.1f%% of drivable nodes (want >= %.0f%%)"
		% [fraction * 100.0, MIN_LARGEST_COMPONENT * 100.0])


func _find(parent: PackedInt32Array, index: int) -> int:
	var root := index
	while parent[root] != root:
		root = parent[root]
	var walk := index
	while parent[walk] != root:
		var next := parent[walk]
		parent[walk] = root
		walk = next
	return root


# --- Physics: the graph must agree with the collision that was built ---------

func _check_nodes_on_road() -> void:
	## Probe a metre INSIDE the network rather than at the node itself.
	##
	## A graph node is a vertex of the road ribbon, so a ray at its exact
	## position lands on the polygon boundary; at a dead end that boundary is
	## the ribbon's terminal edge and whether the ray registers a hit comes down
	## to floating point. Every miss in the first run of this test was a
	## degree-1 node for exactly that reason. A metre along an incident edge is
	## where a vehicle sitting at that node would really be.
	var incident := {}
	for edge in _graph["edges"]:
		if FOOT_CLASSES.has(edge["cls"]):
			continue
		var pts: Array = edge["pts"]
		if pts.size() < 2:
			continue
		if not incident.has(edge["a"]):
			incident[edge["a"]] = [_xz(pts[0]), _xz(pts[1])]
		if not incident.has(edge["b"]):
			incident[edge["b"]] = [_xz(pts[-1]), _xz(pts[-2])]
	var nodes: Array = _graph["nodes"]

	var sampled := 0
	var on_road := 0
	var misses: Array[String] = []
	var index := 0
	for node_index in incident:
		index += 1
		if index % NODE_SAMPLE_STRIDE != 0:
			continue
		var here: Vector2 = incident[node_index][0]
		var toward: Vector2 = incident[node_index][1]
		var span := here.distance_to(toward)
		if span < 0.2:
			continue
		var point := here + (toward - here) / span * minf(NODE_INSET, span * 0.5)
		if absf(point.x) > GROUND_LIMIT or absf(point.y) > GROUND_LIMIT:
			continue
		sampled += 1
		# The graph's own height for this node, plus the collision offset.
		var expect: float = float(nodes[node_index]["y"]) + ROAD_SURFACE_OFFSET
		var probe := _probe_road(point.x, point.y, expect)
		if probe["hit"]:
			on_road += 1
		elif misses.size() < 6:
			misses.append("(%.0f, %.0f) saw [%s]" % [point.x, point.y, probe["detail"]])

	_report_ratio("graph nodes", sampled, on_road, misses)


func _check_lanes_on_road() -> void:
	# The real invariant: a lane centreline computed from the graph's own width
	# and lane count has to land on tarmac. This is what Phase 6 will do every
	# frame for every vehicle.
	var edges: Array = _graph["edges"]
	var sampled := 0
	var on_road := 0
	var misses: Array[String] = []
	for i in range(edges.size()):
		if i % EDGE_SAMPLE_STRIDE != 0:
			continue
		var edge: Dictionary = edges[i]
		if FOOT_CLASSES.has(edge["cls"]):
			continue
		var lanes: int = edge["lanes"]
		if lanes <= 0:
			continue
		var pts: Array = edge["pts"]
		# Midpoint of the longest segment: furthest from junction geometry.
		var best_index := 0
		var best_length := 0.0
		for s in range(pts.size() - 1):
			var length := _xz(pts[s]).distance_to(_xz(pts[s + 1]))
			if length > best_length:
				best_length = length
				best_index = s
		if best_length < 6.0:
			continue
		var from := _xz(pts[best_index])
		var to := _xz(pts[best_index + 1])
		var mid := (from + to) * 0.5
		var normal := (to - from).normalized().orthogonal()
		var lane_width := float(edge.get("lane_width", 0.0))
		if lane_width <= 0.0:
			continue
		# Where the graph says the surface is at this point: the edge is a
		# straight ramp between its two node heights, so interpolate by arc
		# length exactly as terrain.py does when it builds the road field.
		var nodes: Array = _graph["nodes"]
		var run := 0.0
		for s in range(best_index):
			run += _xz(pts[s]).distance_to(_xz(pts[s + 1]))
		var total := run + best_length
		for s in range(best_index + 1, pts.size() - 1):
			total += _xz(pts[s]).distance_to(_xz(pts[s + 1]))
		var t: float = 0.5 if total <= 0.0 else (run + best_length * 0.5) / total
		var expect: float = lerpf(float(nodes[edge["a"]]["y"]),
			float(nodes[edge["b"]]["y"]), t) + ROAD_SURFACE_OFFSET
		for lane in range(lanes):
			var offset := (float(lane) - float(lanes - 1) * 0.5) * lane_width
			var point := mid + normal * offset
			if absf(point.x) > GROUND_LIMIT or absf(point.y) > GROUND_LIMIT:
				continue
			sampled += 1
			var probe := _probe_road(point.x, point.y, expect)
			if probe["hit"]:
				on_road += 1
			elif misses.size() < 6:
				misses.append("%s lane %d at (%.0f, %.0f) saw [%s]"
					% [edge["cls"], lane, point.x, point.y, probe["detail"]])

	_report_ratio("lane centrelines", sampled, on_road, misses)


func _probe_road(x: float, z: float, expect_y: float) -> Dictionary:
	## Walk down through every surface, because a building slab, an awning or a
	## sidewalk above the carriageway would otherwise mask the road underneath.
	## `expect_y` is where the graph says the road surface is; a hit that close
	## to it is the carriageway. Returns {hit: bool, detail: String}, and detail
	## names what was found instead -- the difference between diagnosing a miss
	## and guessing at it.
	var space := _level.get_world_3d().direct_space_state
	var from := Vector3(x, RAY_TOP, z)
	var to := Vector3(x, expect_y - 60.0, z)
	var exclude: Array[RID] = []
	var seen: Array[String] = []
	for _step in range(24):
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var y: float = hit["position"].y
		var collider = hit.get("collider")
		if absf(y - expect_y) <= SURFACE_TOLERANCE:
			return {"hit": true, "detail": ""}
		if seen.size() < 4:
			seen.append("%s@%.1f" % [
				"?" if collider == null else str(collider.name), y,
			])
		# Below the carriageway now; nothing further down can be it.
		if y < expect_y - SURFACE_TOLERANCE:
			break
		if collider == null or not (collider is CollisionObject3D):
			break
		exclude.append(collider.get_rid())
	return {
		"hit": false,
		"detail": ("nothing" if seen.is_empty() else ", ".join(seen))
			+ " (wanted %.1f)" % expect_y,
	}


func _report_ratio(label: String, sampled: int, hits: int, misses: Array[String]) -> void:
	if sampled == 0:
		_fail("%s: nothing was sampled" % label)
		return
	var ratio := float(hits) / float(sampled)
	print("[roadgraph] %s on carriageway: %d/%d (%.1f%%)" % [label, hits, sampled, ratio * 100.0])
	if not misses.is_empty():
		print("[roadgraph]   first misses: %s" % ", ".join(misses))
	_check(ratio >= MIN_ON_ROAD,
		"%s: only %.1f%% landed on the road collision plane (want >= %.0f%%)"
		% [label, ratio * 100.0, MIN_ON_ROAD * 100.0])


func _xz(pair) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[roadgraph] FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("ROAD_GRAPH_SMOKE_TEST_OK")
		quit(0)
	else:
		print("ROAD_GRAPH_SMOKE_TEST_FAIL: %d check(s) failed" % _failures.size())
		for message in _failures:
			print("  - %s" % message)
		quit(1)
