extends SceneTree
## Guards every fast-travel destination in banilad_city.gd.
##
##   Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/fast_travel_smoke_test.gd
##
## Two things can silently break a destination, and both survive a clean build:
##
## 1. **No ground under it.** The anchors store XZ only and resolve height from
##    a ray, so a destination outside the collision surface drops the player
##    past FALL_LIMIT instead of arriving. This is not hypothetical -- the map's
##    original spawn constant put the player 32 m underground the day terrain
##    landed.
## 2. **Ground, but inside a building.** Ten of the fifteen anchors were inside
##    an OSM footprint when first written and had to be nudged into the open.
##    A map rebuild that grows a footprint can put one back inside, and nothing
##    else in the suite would notice.
##
## So this checks both: a ground hit, and a body-sized capsule that fits at the
## arrival point without intersecting the world.
##
## Uses the `_failures` + quit(1) pattern rather than assert(), because a failed
## assert halts _initialize() before quit() and the run hangs at 0% CPU forever.

const CITY_SCENE := "res://banilad_city.tscn"

# Matches the player capsule in banilad_city.tscn (radius 0.38, height 1.8),
# shrunk slightly so a destination legitimately touching a kerb is not failed.
const PROBE_RADIUS := 0.34
const PROBE_HEIGHT := 1.7

var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load(CITY_SCENE) as PackedScene
	if packed == null:
		push_error("could not load %s" % CITY_SCENE)
		quit(1)
		return
	var city := packed.instantiate()
	root.add_child(city)

	# Let the map colliders register before probing anything.
	await physics_frame
	await physics_frame
	await physics_frame

	var teleports: Array = city.get("TELEPORTS")
	if teleports == null or teleports.is_empty():
		_failures.append("TELEPORTS is missing or empty")
		_report()
		return
	print("[travel] %d destinations" % teleports.size())

	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var player: Node3D = city.get_node_or_null(^"Player")
	var clearance: float = city.get("SPAWN_CLEARANCE")

	var shape := CapsuleShape3D.new()
	shape.radius = PROBE_RADIUS
	shape.height = PROBE_HEIGHT

	for entry in teleports:
		var name := String(entry.get("name", "?"))
		var at: Vector2 = entry.get("at", Vector2.ZERO)

		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, 300.0, at.y), Vector3(at.x, -40.0, at.y))
		ray.collision_mask = 1
		if player != null:
			ray.exclude = [player.get_rid()]
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			_failures.append("%s: no ground at (%.1f, %.1f)" % [name, at.x, at.y])
			continue

		var ground := float(hit.position.y)
		# Where the player actually materialises: capsule centre sits half a
		# body above the feet, which are `clearance` above the ground.
		var centre := Vector3(at.x, ground + clearance + PROBE_HEIGHT * 0.5, at.y)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), centre)
		query.collision_mask = 1
		if player != null:
			query.exclude = [player.get_rid()]
		var blocked: Array[Dictionary] = space.intersect_shape(query, 4)
		if not blocked.is_empty():
			var names: Array[String] = []
			for b in blocked:
				var collider = b.get("collider")
				names.append(String(collider.name) if collider != null else "?")
			_failures.append("%s: arrival blocked by %s" % [name, ", ".join(names)])
			continue

		print("[travel]   OK  %-28s ground %6.1f m" % [name, ground])

	_report()


func _report() -> void:
	if _failures.is_empty():
		print("FAST_TRAVEL_SMOKE_TEST_OK")
		quit()
		return
	for f in _failures:
		printerr("[travel] FAIL %s" % f)
	printerr("[travel] %d destination(s) unusable" % _failures.size())
	quit(1)
