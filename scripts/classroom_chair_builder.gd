extends RefCounted
class_name ClassroomChairBuilder
## Low-poly PSX classroom chair with cantilever tablet arm.
##
## Student sits facing local +X (toward the whiteboard). Backrest is on -X,
## writing arm on the student's right (-Z). Origin sits on the floor under
## the seat center — match placement with floor Y, not seat Y.

const BLACK_CHAIR := Color("1c1c1e")
const FRAME_METAL := Color("2a2a2c")
const ARM_COLOR := Color("c4b090")


static func build(
	parent: Node,
	object_name: String,
	position: Vector3,
	get_material: Callable,
	rotation_y: float = 0.0
) -> Node3D:
	var root := Node3D.new()
	root.name = object_name
	root.position = position
	root.rotation.y = rotation_y
	parent.add_child(root)

	_add_mesh(root, "ChairFrame", _build_frame_mesh(), get_material.call(BLACK_CHAIR))
	_add_mesh(root, "ChairMetal", _build_metal_mesh(), get_material.call(FRAME_METAL))
	_add_mesh(root, "ChairArm", _build_arm_mesh(), get_material.call(ARM_COLOR))
	return root


static func _add_mesh(parent: Node3D, part_name: String, mesh: ArrayMesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func _build_frame_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(surface, Vector3(0.0, 0.415, 0.0), Vector3(0.46, 0.055, 0.44))
	_add_angled_panel(
		surface,
		Vector3(-0.19, 0.50, 0.0),
		Vector3(-0.23, 0.80, 0.0),
		0.44,
		0.05
	)
	_add_box(surface, Vector3(-0.08, 0.30, -0.22), Vector3(0.035, 0.22, 0.035))
	_add_box(surface, Vector3(-0.10, 0.56, -0.30), Vector3(0.30, 0.028, 0.20))
	_add_box(surface, Vector3(-0.24, 0.64, -0.30), Vector3(0.025, 0.14, 0.20))
	return surface.commit()


static func _build_metal_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for leg in [
		Vector3(-0.17, 0.21, -0.18),
		Vector3(-0.17, 0.21, 0.18),
		Vector3(0.15, 0.21, -0.18),
		Vector3(0.15, 0.21, 0.18),
	]:
		_add_box(surface, leg, Vector3(0.038, 0.42, 0.038))
	_add_box(surface, Vector3(-0.01, 0.24, -0.18), Vector3(0.34, 0.028, 0.028))
	_add_box(surface, Vector3(-0.01, 0.24, 0.18), Vector3(0.34, 0.028, 0.028))
	_add_box(surface, Vector3(-0.19, 0.36, 0.0), Vector3(0.028, 0.30, 0.36))
	return surface.commit()


static func _build_arm_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(surface, Vector3(-0.10, 0.568, -0.30), Vector3(0.26, 0.018, 0.17))
	return surface.commit()


static func _add_box(surface: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var c := center
	var verts := [
		Vector3(c.x - hx, c.y - hy, c.z - hz),
		Vector3(c.x + hx, c.y - hy, c.z - hz),
		Vector3(c.x + hx, c.y - hy, c.z + hz),
		Vector3(c.x - hx, c.y - hy, c.z + hz),
		Vector3(c.x - hx, c.y + hy, c.z - hz),
		Vector3(c.x + hx, c.y + hy, c.z - hz),
		Vector3(c.x + hx, c.y + hy, c.z + hz),
		Vector3(c.x - hx, c.y + hy, c.z + hz),
	]
	_add_quad(surface, verts[4], verts[5], verts[1], verts[0])
	_add_quad(surface, verts[5], verts[6], verts[2], verts[1])
	_add_quad(surface, verts[6], verts[7], verts[3], verts[2])
	_add_quad(surface, verts[7], verts[4], verts[0], verts[3])
	_add_quad(surface, verts[4], verts[7], verts[6], verts[5])
	_add_quad(surface, verts[0], verts[1], verts[2], verts[3])


static func _add_angled_panel(
	surface: SurfaceTool,
	bottom_center: Vector3,
	top_center: Vector3,
	width_z: float,
	thickness_x: float
) -> void:
	var hz := width_z * 0.5
	var hx := thickness_x * 0.5
	var b := bottom_center
	var t := top_center
	var bx0 := b.x - hx
	var bx1 := b.x + hx
	var tx0 := t.x - hx
	var tx1 := t.x + hx
	var verts := [
		Vector3(bx0, b.y, b.z - hz),
		Vector3(bx1, b.y, b.z - hz),
		Vector3(bx1, b.y, b.z + hz),
		Vector3(bx0, b.y, b.z + hz),
		Vector3(tx0, t.y, t.z - hz),
		Vector3(tx1, t.y, t.z - hz),
		Vector3(tx1, t.y, t.z + hz),
		Vector3(tx0, t.y, t.z + hz),
	]
	_add_quad(surface, verts[4], verts[5], verts[1], verts[0])
	_add_quad(surface, verts[5], verts[6], verts[2], verts[1])
	_add_quad(surface, verts[6], verts[7], verts[3], verts[2])
	_add_quad(surface, verts[7], verts[4], verts[0], verts[3])
	_add_quad(surface, verts[4], verts[7], verts[6], verts[5])
	_add_quad(surface, verts[0], verts[1], verts[2], verts[3])


static func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := Plane(a, b, c).normal
	for vertex in [a, b, c, a, c, d]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)
