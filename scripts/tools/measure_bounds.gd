extends SceneTree

var _frames := 0
var _results: Array[String] = []
var _paths := [
	"res://assets/npcs/police.glb",
	"res://assets/characters/gusion/gusion_dimension_w_rigged.glb",
]


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	for path in _paths:
		var packed := load(path) as PackedScene
		if packed == null:
			_results.append("%s: LOAD FAILED" % path.get_file())
			continue
		var root_node := packed.instantiate() as Node3D
		root.add_child(root_node)
		var bounds := AABB()
		var started := false
		for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			var relative := Transform3D()
			var current := mesh_instance
			while current != null and current != root_node:
				relative = current.transform * relative
				current = current.get_parent() as Node3D
			for surface_index in mesh_instance.mesh.get_surface_count():
				var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
				if arrays.is_empty():
					continue
				for vertex in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					var point: Vector3 = relative * vertex
					if not started:
						bounds = AABB(point, Vector3.ZERO)
						started = true
					else:
						bounds = bounds.expand(point)
		_results.append("%s: size=(%.2f, %.2f, %.2f) scale_to_1.78=%.3f" % [
			path.get_file(), bounds.size.x, bounds.size.y, bounds.size.z,
			1.78 / maxf(bounds.size.y, 0.001),
		])
		root_node.free()
	for line in _results:
		print(line)
	quit(0)
	return true
