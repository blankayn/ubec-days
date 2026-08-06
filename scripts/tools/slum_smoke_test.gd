extends SceneTree
## Headless guard on the informal-settlement district (tools/build_slum.py).
##
## The failure this exists to catch: a house whose footprint straddles an alley
## seals the warren off, and the player walks into a wall where the map shows a
## path. The build script checks that geometrically, but only against its own
## in-memory lots -- this checks the GLB that actually ships, with the collision
## Godot generated from the `-col` mesh suffixes.
##
##   .tools/godot/Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/slum_smoke_test.gd

const SlumAsset := preload("res://assets/buildings/banilad_slum.glb")
const ALLEY_DATA := "res://assets/maps/banilad_slum_alleys.json"

# tools/build_slum.py: ALLEY_HALF 0.7, so the walkable corridor is 1.4 m. Probe
# a little narrower than that; the walls are allowed to sit right on the edge.
const PROBE_RADIUS := 0.42
const PROBE_HEIGHT := 0.9
const SETTLE_FRAMES := 8

var _world: Node3D
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_world = Node3D.new()
	var slum := SlumAsset.instantiate() as Node3D
	slum.name = "BaniladSlum"
	_world.add_child(slum)
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false

	var slum := _world.get_node_or_null("BaniladSlum") as Node3D
	if slum == null:
		_fail("slum asset did not instantiate")
		return _finish()

	var bodies := slum.find_children("*", "StaticBody3D", true, false)
	if bodies.is_empty():
		_fail("no StaticBody3D in the GLB: the `-col` suffix did not import, " +
			"so the houses have no collision and the player walks through them")
	else:
		print("[slum-test] %d collision bodies from -col suffixes" % bodies.size())

	var data := _load_alleys()
	if data.is_empty():
		return _finish()

	var space := _world.get_viewport().world_3d.direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = PROBE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape

	var districts: Array = data.get("districts", [])
	if districts.is_empty():
		_fail("no districts in %s; the alley JSON format changed" % ALLEY_DATA)
		return _finish()

	var probed := 0
	var blocked := 0
	var worst := Vector3.ZERO
	for district in districts:
		var d := district as Dictionary
		var d_blocked := 0
		for alley in d.get("alleys", []):
			for point in alley:
				# JSON stores Godot XZ; districts sit on flat map ground at y=0.
				query.transform = Transform3D(Basis(),
					Vector3(float(point[0]), PROBE_HEIGHT, float(point[1])))
				probed += 1
				if not space.intersect_shape(query, 1).is_empty():
					d_blocked += 1
					worst = query.transform.origin
		blocked += d_blocked
		print("[slum-test] %-16s %d alleys, %d blocked" % [
			d.get("name", "?"), (d.get("alleys", []) as Array).size(), d_blocked])

	print("[slum-test] probed %d alley points, %d blocked" % [probed, blocked])
	if blocked > 0:
		_fail("%d/%d alley points are inside a house (e.g. %s): the warren is " %
			[blocked, probed, worst] + "not walkable there")

	return _finish()


func _load_alleys() -> Dictionary:
	if not FileAccess.file_exists(ALLEY_DATA):
		_fail("missing %s; run tools/build_slum.py" % ALLEY_DATA)
		return {}
	var text := FileAccess.get_file_as_string(ALLEY_DATA)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("%s is not a JSON object" % ALLEY_DATA)
		return {}
	return parsed as Dictionary


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> bool:
	if _failures.is_empty():
		print("SLUM_SMOKE_TEST_OK")
	else:
		for msg in _failures:
			printerr("SLUM_SMOKE_TEST_FAIL: %s" % msg)
	quit(0 if _failures.is_empty() else 1)
	return true
