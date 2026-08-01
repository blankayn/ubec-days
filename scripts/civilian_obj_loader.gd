extends RefCounted
class_name CivilianObjLoader
## Minimal Wavefront OBJ loader for the civilian pack split meshes.


static func load_mesh(obj_path: String) -> ArrayMesh:
	var file := FileAccess.open(obj_path, FileAccess.READ)
	if file == null:
		push_error("CivilianObjLoader could not open: %s" % obj_path)
		return null

	var positions: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var normals: PackedVector3Array = []
	var mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var surface_has_vertices := false

	while file.get_position() < file.get_length():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		match parts[0]:
			"usemtl":
				if surface_has_vertices:
					surface.commit(mesh)
					surface = SurfaceTool.new()
					surface.begin(Mesh.PRIMITIVE_TRIANGLES)
					surface_has_vertices = false
			"v":
				positions.append(
					Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
				)
			"vt":
				uvs.append(Vector2(float(parts[1]), 1.0 - float(parts[2])))
			"vn":
				normals.append(
					Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
				)
			"f":
				surface_has_vertices = true
				var corners: Array[Dictionary] = []
				for index in range(1, parts.size()):
					var tokens := parts[index].split("/")
					var corner := {
						"v": int(tokens[0]) - 1,
						"t": -1,
						"n": -1,
					}
					if tokens.size() > 1 and tokens[1] != "":
						corner["t"] = int(tokens[1]) - 1
					if tokens.size() > 2 and tokens[2] != "":
						corner["n"] = int(tokens[2]) - 1
					corners.append(corner)
				for tri_index in range(1, corners.size() - 1):
					for corner_index in [0, tri_index, tri_index + 1]:
						_add_corner(surface, corners[corner_index], positions, uvs, normals)

	if surface_has_vertices:
		surface.commit(mesh)
	return mesh


static func _add_corner(
	surface: SurfaceTool,
	corner: Dictionary,
	positions: PackedVector3Array,
	uvs: PackedVector2Array,
	normals: PackedVector3Array
) -> void:
	var vertex_index: int = corner["v"]
	if vertex_index < 0 or vertex_index >= positions.size():
		return
	var tex_index: int = corner["t"]
	if tex_index >= 0 and tex_index < uvs.size():
		surface.set_uv(uvs[tex_index])
	var normal_index: int = corner["n"]
	if normal_index >= 0 and normal_index < normals.size():
		surface.set_normal(normals[normal_index])
	surface.add_vertex(positions[vertex_index])
