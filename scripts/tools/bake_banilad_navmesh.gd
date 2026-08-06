extends SceneTree
## Headless: inspect the imported Banilad map and bake its navigation mesh.
##
##   Godot_v4.7-stable_win64.exe --headless --path . --script res://scripts/tools/bake_banilad_navmesh.gd

const MAP_SCENE := "res://assets/maps/banilad_map.glb"
# The slum is instanced at runtime by banilad_city.gd, not baked into the map
# GLB, but it stands at Godot x 170..265 / z -585..-505, well inside the bake
# volume below. Leave it out and the navmesh lays walkable floor straight
# through 168 houses.
const SLUM_SCENE := "res://assets/buildings/banilad_slum.glb"
const NAVMESH_OUT := "res://assets/maps/banilad_navmesh.res"

# The player capsule in cblock_player.gd is radius 0.38 / height 1.8.
const AGENT_RADIUS := 0.45
const AGENT_HEIGHT := 1.8
const AGENT_MAX_CLIMB := 0.35
# Streets, sidewalks and floors are all flat here, so a tight slope limit costs
# nothing and keeps the ~26 degree hip roofs from being classed as walkable.
const AGENT_MAX_SLOPE := 20.0

# The full map is 2 x 2 km. Baking all of it is wasteful, so the navmesh covers
# the Banilad corridor from Alicia Residences up past Gaisano and the Town Centre.
# The vertical slice is deliberately thin: only ground level is walkable, and
# clipping above head height stops flat commercial roofs becoming navmesh
# islands. Walls still fall inside the slice, so they keep blocking.
const BAKE_ORIGIN := Vector3(-450.0, -6.0, -880.0)
const BAKE_SIZE := Vector3(900.0, 10.0, 760.0)
# Matches the NavigationServer3D default map cell size, otherwise the server
# warns about rasterization mismatches on region edges.
const CELL_SIZE := 0.25
const CELL_HEIGHT := 0.25


var _region: NavigationRegion3D
var _frames := 0


func _initialize() -> void:
	var packed := load(MAP_SCENE) as PackedScene
	if packed == null:
		push_error("could not load %s" % MAP_SCENE)
		quit(1)
		return

	var level := packed.instantiate()
	_report_structure(level)

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"

	var nav := NavigationMesh.new()
	nav.agent_radius = AGENT_RADIUS
	nav.agent_height = AGENT_HEIGHT
	nav.agent_max_climb = AGENT_MAX_CLIMB
	nav.agent_max_slope = AGENT_MAX_SLOPE
	nav.cell_size = CELL_SIZE
	nav.cell_height = CELL_HEIGHT
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav.filter_baking_aabb = AABB(BAKE_ORIGIN, BAKE_SIZE)
	region.navigation_mesh = nav

	region.add_child(level)

	var slum_packed := load(SLUM_SCENE) as PackedScene
	if slum_packed == null:
		push_warning("could not load %s; navmesh will ignore the slum" % SLUM_SCENE)
	else:
		# Same contract as banilad_city.gd: absolute map coordinates, so it goes
		# in at the origin with no transform.
		region.add_child(slum_packed.instantiate())

	root.add_child(region)
	_region = region


# The navigation server can only parse source geometry once the tree is live,
# so the bake waits a couple of idle frames after setup.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_bake()
	return true


func _bake() -> void:
	var region := _region
	print("[bake] baking navmesh over %.0f x %.0f m at %.2f m cells..." % [
		BAKE_SIZE.x, BAKE_SIZE.z, CELL_SIZE,
	])
	var started := Time.get_ticks_msec()

	var nav: NavigationMesh = region.navigation_mesh
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav, source, region)
	print("[bake] source geometry: %d vertices, %d indices" % [
		source.get_vertices().size() / 3, source.get_indices().size(),
	])
	NavigationServer3D.bake_from_source_geometry_data(nav, source)

	var elapsed := (Time.get_ticks_msec() - started) / 1000.0

	var baked: NavigationMesh = nav
	var polys := baked.get_polygon_count()
	var verts := baked.get_vertices().size()
	print("[bake] finished in %.1f s" % elapsed)
	print("[bake] navmesh polygons: %d   vertices: %d" % [polys, verts])

	if polys == 0:
		push_error("navmesh bake produced no polygons")
		quit(1)
		return

	var err := ResourceSaver.save(baked, NAVMESH_OUT)
	if err != OK:
		push_error("could not save navmesh: %d" % err)
		quit(1)
		return
	print("[bake] saved %s" % NAVMESH_OUT)

	var pts := baked.get_vertices()
	if pts.size() > 0:
		var lo := pts[0]
		var hi := pts[0]
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		print("[bake] navmesh bounds: %s .. %s" % [str(lo), str(hi)])

	print("[bake] DONE")
	quit(0)


func _report_structure(level: Node) -> void:
	var meshes := 0
	var bodies := 0
	var shapes := 0
	var no_collision: Array[String] = []

	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			meshes += 1
			var sibling_body := false
			for child in node.get_children():
				if child is StaticBody3D:
					sibling_body = true
			if not sibling_body and node.get_parent() is Node3D:
				for sib in node.get_parent().get_children():
					if sib is StaticBody3D and sib.name.begins_with(node.name):
						sibling_body = true
			if not sibling_body:
				no_collision.append(node.name)
		elif node is StaticBody3D:
			bodies += 1
		elif node is CollisionShape3D:
			shapes += 1
		for child in node.get_children():
			stack.append(child)

	print("[bake] level root: %s (%s)" % [level.name, level.get_class()])
	print("[bake] MeshInstance3D: %d" % meshes)
	print("[bake] StaticBody3D:   %d" % bodies)
	print("[bake] CollisionShape3D: %d" % shapes)
	print("[bake] meshes without collision (%d): %s" % [
		no_collision.size(), ", ".join(no_collision),
	])
