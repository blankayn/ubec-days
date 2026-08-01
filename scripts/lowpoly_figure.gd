extends RefCounted
class_name LowPolyFigure
## Chunky PS2-style human assembled from low-sided procedural meshes.

const NpcAnimator = preload("res://scripts/npc_animator.gd")


static func build_human(
	parent: Node,
	get_material: Callable,
	shirt: Color,
	pants: Color,
	skin: Color,
	accent: Color,
	pose: String = "stand"
) -> Dictionary:
	var root := Node3D.new()
	root.name = "LowPolyFigure"
	root.set_meta("pose", pose)
	parent.add_child(root)

	# Small deterministic differences keep the cast from sharing one silhouette.
	var variation := absi(hash(parent.name)) % 3
	var head: MeshInstance3D = null
	match pose:
		"sit":
			head = _build_sitting(root, get_material, shirt, pants, skin, accent, variation)
		"crouch":
			head = _build_crouch(root, get_material, shirt, pants, skin, accent, variation)
		_:
			head = _build_standing(root, get_material, shirt, pants, skin, accent, variation)
	var animator := NpcAnimator.new()
	animator.name = "ProceduralAnimator"
	root.add_child(animator)

	return {"root": root, "head": head}


static func add_name_tag(parent: Node3D, display_name: String, y_offset: float = 2.15) -> void:
	var anchor := MeshInstance3D.new()
	anchor.name = "NameTagAnchor"
	anchor.position = Vector3(0.0, y_offset, 0.0)
	parent.add_child(anchor)

	var label := Label3D.new()
	label.text = display_name.to_upper()
	label.pixel_size = 0.0045
	label.font_size = 42
	label.modulate = Color("f2ebe0")
	label.outline_size = 10
	label.outline_modulate = Color("1a1816")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	anchor.add_child(label)


static func add_face_texture(head_part: MeshInstance3D, texture_path: String) -> void:
	var head_pivot := head_part.get_parent() as Node3D
	if head_pivot == null:
		head_pivot = head_part

	var existing := head_pivot.get_node_or_null("RequestedFaceTexture")
	if existing:
		existing.queue_free()

	var face_quad := MeshInstance3D.new()
	face_quad.name = "RequestedFaceTexture"
	var face_mesh := PlaneMesh.new()
	face_mesh.size = Vector2(0.36, 0.40)
	face_quad.mesh = face_mesh
	# PlaneMesh faces +Y; place it just ahead of the faceted head to avoid flicker.
	face_quad.rotation = Vector3(PI / 2.0, 0.0, PI)
	face_quad.position = Vector3(0.0, 0.072, -0.212)

	var face_tex := load(texture_path) as Texture2D
	if face_tex:
		var face_mat := StandardMaterial3D.new()
		face_mat.albedo_texture = face_tex
		face_mat.albedo_color = Color.WHITE
		face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		face_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		face_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		face_quad.material_override = face_mat
	head_pivot.add_child(face_quad)


static func _build_standing(
	root: Node3D,
	get_material: Callable,
	shirt: Color,
	pants: Color,
	skin: Color,
	accent: Color,
	variation: int
) -> MeshInstance3D:
	var shoulder_width: float = [0.68, 0.72, 0.65][variation]
	var waist_width: float = [0.56, 0.59, 0.54][variation]
	var hem_bottom: float = [0.75, 0.72, 0.78][variation]
	var sleeve_length: float = [0.0, 0.025, -0.02][variation]
	var shirt_top := 1.51
	var torso_bottom := hem_bottom

	# The shorts and shirt overlap slightly at the waist, so no dark hollow gap can
	# appear between separate pieces when viewed from below or under hard lighting.
	_body_part(root, get_material, "Pelvis", Vector3(0.0, 0.665, 0.012), 0.31, 0.47, 0.50, 0.34, 0.36, pants)
	_torso_part(
		root, get_material, "Torso",
		Vector3(0.0, (torso_bottom + shirt_top) * 0.5, 0.0),
		shirt_top - torso_bottom, waist_width, shoulder_width, 0.39, 0.43, shirt
	)
	_marker_part(root, "ShirtHem", Vector3(0.0, hem_bottom, 0.0))

	# Sleeves begin inside the beveled shoulder volume. Their smaller radius and
	# eight-sided profile remove the old triangular fins at the torso seam.
	var sleeve_height := 0.285 + sleeve_length
	var sleeve_y := 1.405 - sleeve_height * 0.5
	var sleeve_x := shoulder_width * 0.53
	var sleeve_l := _body_part(root, get_material, "ArmLUpper", Vector3(-sleeve_x, sleeve_y, 0.0), sleeve_height, 0.18, 0.205, 0.285, 0.335, shirt.darkened(0.035))
	var sleeve_r := _body_part(root, get_material, "ArmRUpper", Vector3(sleeve_x, sleeve_y, 0.0), sleeve_height, 0.18, 0.205, 0.285, 0.335, shirt.lightened(0.015))
	sleeve_l.rotation.z = -0.16
	sleeve_r.rotation.z = 0.16
	_limb(root, get_material, "ArmLLower", Vector3(-sleeve_x, 1.145 - sleeve_length, 0.004), Vector3(-sleeve_x, 0.82, 0.018), 0.102, 0.084, skin)
	_limb(root, get_material, "ArmRLower", Vector3(sleeve_x, 1.145 - sleeve_length, 0.004), Vector3(sleeve_x, 0.82, 0.018), 0.102, 0.084, skin.darkened(0.025))
	_lowpoly_sphere(root, get_material, "HandL", Vector3(-sleeve_x, 0.765, 0.018), 0.102, skin)
	_lowpoly_sphere(root, get_material, "HandR", Vector3(sleeve_x, 0.765, 0.018), 0.102, skin.darkened(0.025))

	# Thicker tapered legs meet the shorts and shoes without disconnected blocks.
	_limb(root, get_material, "LegLThigh", Vector3(-0.14, 0.64, 0.012), Vector3(-0.14, 0.445, 0.018), 0.148, 0.132, pants)
	_limb(root, get_material, "LegRThigh", Vector3(0.14, 0.64, 0.012), Vector3(0.14, 0.445, 0.018), 0.148, 0.132, pants.darkened(0.025))
	_limb(root, get_material, "LegLShin", Vector3(-0.14, 0.445, 0.018), Vector3(-0.14, 0.125, 0.035), 0.126, 0.098, skin.darkened(0.035))
	_limb(root, get_material, "LegRShin", Vector3(0.14, 0.445, 0.018), Vector3(0.14, 0.125, 0.035), 0.126, 0.098, skin.darkened(0.055))
	_foot(root, get_material, "FootL", Vector3(-0.14, 0.055, -0.05), accent)
	_foot(root, get_material, "FootR", Vector3(0.14, 0.055, -0.05), accent.darkened(0.055))

	return _build_head(root, get_material, skin, accent, Vector3(0.0, 1.70, 0.0))


static func _build_sitting(
	root: Node3D,
	get_material: Callable,
	shirt: Color,
	pants: Color,
	skin: Color,
	accent: Color,
	variation: int
) -> MeshInstance3D:
	var shoulder_width: float = [0.66, 0.70, 0.63][variation]
	var waist_width: float = [0.55, 0.58, 0.53][variation]
	_body_part(root, get_material, "Pelvis", Vector3(0.0, 0.525, 0.035), 0.28, 0.46, 0.49, 0.33, 0.35, pants)
	_torso_part(root, get_material, "Torso", Vector3(0.0, 0.92, 0.0), 0.60, waist_width, shoulder_width, 0.39, 0.43, shirt)
	_marker_part(root, "ShirtHem", Vector3(0.0, 0.62, 0.0))

	_limb(root, get_material, "LegLThigh", Vector3(-0.14, 0.51, -0.015), Vector3(-0.14, 0.48, -0.38), 0.148, 0.13, pants)
	_limb(root, get_material, "LegRThigh", Vector3(0.14, 0.51, -0.015), Vector3(0.14, 0.48, -0.38), 0.148, 0.13, pants.darkened(0.025))
	_limb(root, get_material, "LegLShin", Vector3(-0.14, 0.48, -0.38), Vector3(-0.14, 0.15, -0.37), 0.124, 0.096, skin.darkened(0.04))
	_limb(root, get_material, "LegRShin", Vector3(0.14, 0.48, -0.38), Vector3(0.14, 0.15, -0.37), 0.124, 0.096, skin.darkened(0.055))
	_foot(root, get_material, "FootL", Vector3(-0.14, 0.055, -0.46), accent)
	_foot(root, get_material, "FootR", Vector3(0.14, 0.055, -0.46), accent.darkened(0.055))

	var sleeve_x := shoulder_width * 0.55
	var sleeve_l := _body_part(root, get_material, "ArmLUpper", Vector3(-sleeve_x, 1.025, 0.006), 0.255, 0.175, 0.20, 0.28, 0.33, shirt.darkened(0.035))
	var sleeve_r := _body_part(root, get_material, "ArmRUpper", Vector3(sleeve_x, 1.025, 0.006), 0.255, 0.175, 0.20, 0.28, 0.33, shirt)
	sleeve_l.rotation.z = -0.14
	sleeve_r.rotation.z = 0.14
	_limb(root, get_material, "ArmLLower", Vector3(-sleeve_x, 0.91, 0.02), Vector3(-0.34, 0.67, -0.10), 0.10, 0.08, skin)
	_limb(root, get_material, "ArmRLower", Vector3(sleeve_x, 0.91, 0.02), Vector3(0.34, 0.67, -0.10), 0.10, 0.08, skin.darkened(0.03))
	_lowpoly_sphere(root, get_material, "HandL", Vector3(-0.34, 0.645, -0.105), 0.096, skin)
	_lowpoly_sphere(root, get_material, "HandR", Vector3(0.34, 0.645, -0.105), 0.096, skin.darkened(0.03))

	return _build_head(root, get_material, skin, accent, Vector3(0.0, 1.36, 0.02))


static func _build_crouch(
	root: Node3D,
	get_material: Callable,
	shirt: Color,
	pants: Color,
	skin: Color,
	accent: Color,
	variation: int
) -> MeshInstance3D:
	var shoulder_width: float = [0.64, 0.69, 0.62][variation]
	var waist_width: float = [0.54, 0.57, 0.52][variation]
	_body_part(root, get_material, "Pelvis", Vector3(0.0, 0.525, 0.028), 0.27, 0.45, 0.48, 0.32, 0.35, pants)
	_torso_part(root, get_material, "Torso", Vector3(0.0, 0.92, -0.035), 0.60, waist_width, shoulder_width, 0.39, 0.43, shirt)
	_marker_part(root, "ShirtHem", Vector3(0.0, 0.62, -0.01))

	_limb(root, get_material, "LegLThigh", Vector3(-0.14, 0.50, 0.02), Vector3(-0.19, 0.30, -0.10), 0.148, 0.128, pants)
	_limb(root, get_material, "LegRThigh", Vector3(0.14, 0.50, 0.02), Vector3(0.19, 0.30, -0.10), 0.148, 0.128, pants.darkened(0.03))
	_limb(root, get_material, "LegLShin", Vector3(-0.19, 0.30, -0.10), Vector3(-0.20, 0.11, 0.10), 0.124, 0.094, skin.darkened(0.04))
	_limb(root, get_material, "LegRShin", Vector3(0.19, 0.30, -0.10), Vector3(0.20, 0.11, 0.10), 0.124, 0.094, skin.darkened(0.055))
	_foot(root, get_material, "FootL", Vector3(-0.20, 0.055, 0.02), accent)
	_foot(root, get_material, "FootR", Vector3(0.20, 0.055, 0.02), accent.darkened(0.07))

	var sleeve_x := shoulder_width * 0.55
	var sleeve_l := _body_part(root, get_material, "ArmLUpper", Vector3(-sleeve_x, 1.015, -0.045), 0.255, 0.175, 0.20, 0.28, 0.33, shirt.darkened(0.035))
	var sleeve_r := _body_part(root, get_material, "ArmRUpper", Vector3(sleeve_x, 1.015, -0.045), 0.255, 0.175, 0.20, 0.28, 0.33, shirt)
	sleeve_l.rotation.z = -0.14
	sleeve_r.rotation.z = 0.14
	_limb(root, get_material, "ArmLLower", Vector3(-sleeve_x, 0.89, -0.08), Vector3(-0.33, 0.64, -0.18), 0.10, 0.08, skin)
	_limb(root, get_material, "ArmRLower", Vector3(sleeve_x, 0.89, -0.08), Vector3(0.33, 0.64, -0.18), 0.10, 0.08, skin.darkened(0.03))
	_lowpoly_sphere(root, get_material, "HandL", Vector3(-0.33, 0.615, -0.185), 0.096, skin)
	_lowpoly_sphere(root, get_material, "HandR", Vector3(0.33, 0.615, -0.185), 0.096, skin.darkened(0.03))

	return _build_head(root, get_material, skin, accent, Vector3(0.0, 1.36, -0.04))


static func _build_head(
	root: Node3D,
	get_material: Callable,
	skin: Color,
	accent: Color,
	position: Vector3
) -> MeshInstance3D:
	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = position
	root.add_child(head_pivot)

	_cylinder_part(head_pivot, get_material, "Neck", Vector3(0.0, -0.115, 0.012), 0.19, 0.12, 0.14, skin.darkened(0.07), 8)
	var head := _lowpoly_sphere(head_pivot, get_material, "Head", Vector3(0.0, 0.072, 0.0), 0.22, skin)
	head.scale = Vector3(0.96, 1.06, 0.90)

	# A curved faceted cap follows the skull instead of forming the old square block.
	var hair := _lowpoly_sphere(head_pivot, get_material, "Hair", Vector3(0.0, 0.185, 0.012), 0.222, accent.darkened(0.55))
	hair.scale = Vector3(0.98, 0.58, 0.92)
	return head


static func _foot(parent: Node, get_material: Callable, part_name: String, position: Vector3, color: Color) -> MeshInstance3D:
	return _body_part(parent, get_material, part_name, position, 0.105, 0.195, 0.18, 0.31, 0.275, color)


static func _limb(
	parent: Node,
	get_material: Callable,
	part_name: String,
	from: Vector3,
	to: Vector3,
	start_radius: float,
	end_radius: float,
	color: Color
) -> MeshInstance3D:
	var midpoint := (from + to) * 0.5
	var direction := to - from
	var part := _cylinder_part(parent, get_material, part_name, midpoint, direction.length(), start_radius, end_radius, color, 8)
	if direction.length_squared() > 0.00001:
		part.quaternion = Quaternion(Vector3.UP, direction.normalized())
	return part


static func _cylinder_part(
	parent: Node,
	get_material: Callable,
	part_name: String,
	position: Vector3,
	height: float,
	top_radius: float,
	bottom_radius: float,
	color: Color,
	segments: int
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.radial_segments = segments
	mesh.rings = 1
	part.mesh = mesh
	part.position = position
	part.material_override = get_material.call(color)
	if part_name in ["Neck", "ArmLLower", "ArmRLower"]:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


static func _lowpoly_sphere(
	parent: Node,
	get_material: Callable,
	part_name: String,
	position: Vector3,
	radius: float,
	color: Color
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	part.mesh = mesh
	part.position = position
	part.material_override = get_material.call(color)
	if part_name in ["Head", "Hair", "HandL", "HandR"]:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


static func _frustum_part(
	parent: Node,
	get_material: Callable,
	part_name: String,
	position: Vector3,
	height: float,
	bottom_width: float,
	top_width: float,
	bottom_depth: float,
	top_depth: float,
	color: Color
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = position
	part.mesh = _make_frustum_mesh(height, bottom_width, top_width, bottom_depth, top_depth)
	part.material_override = get_material.call(color)
	parent.add_child(part)
	return part


static func _body_part(
	parent: Node,
	get_material: Callable,
	part_name: String,
	position: Vector3,
	height: float,
	bottom_width: float,
	top_width: float,
	bottom_depth: float,
	top_depth: float,
	color: Color
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = position
	part.mesh = _make_beveled_frustum_mesh(height, bottom_width, top_width, bottom_depth, top_depth)
	part.material_override = get_material.call(color)
	if part_name in ["ArmLUpper", "ArmRUpper"]:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part


static func _marker_part(parent: Node, part_name: String, position: Vector3) -> MeshInstance3D:
	# Animation compatibility marker. The shirt mesh already includes its lower hem,
	# so this intentionally has no second overlapping surface.
	var marker := MeshInstance3D.new()
	marker.name = part_name
	marker.position = position
	parent.add_child(marker)
	return marker


static func _torso_part(
	parent: Node,
	get_material: Callable,
	part_name: String,
	position: Vector3,
	height: float,
	bottom_width: float,
	shoulder_width: float,
	bottom_depth: float,
	shoulder_depth: float,
	color: Color
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.position = position
	part.mesh = _make_shirt_torso_mesh(height, bottom_width, shoulder_width, bottom_depth, shoulder_depth)
	# The world supplies a ShaderMaterial, and Compatibility rendering ignores
	# BaseMaterial-only receive-shadow flags on it. Use a tiny unshaded material
	# for the shirt itself so hard self-shadow maps cannot draw a giant diagonal
	# across its front. Vertex colors retain deliberately stepped PS2 facets, and
	# the MeshInstance still casts a normal silhouette onto the ground.
	var clean_material := StandardMaterial3D.new()
	clean_material.albedo_color = color
	clean_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	clean_material.disable_receive_shadows = true
	clean_material.vertex_color_use_as_albedo = true
	clean_material.roughness = 1.0
	part.material_override = clean_material
	parent.add_child(part)
	return part


static func _make_frustum_mesh(height: float, bottom_width: float, top_width: float, bottom_depth: float, top_depth: float) -> ArrayMesh:
	var y0 := -height * 0.5
	var y1 := height * 0.5
	var bw := bottom_width * 0.5
	var tw := top_width * 0.5
	var bd := bottom_depth * 0.5
	var td := top_depth * 0.5
	var bfl := Vector3(-bw, y0, -bd)
	var bfr := Vector3(bw, y0, -bd)
	var bbr := Vector3(bw, y0, bd)
	var bbl := Vector3(-bw, y0, bd)
	var tfl := Vector3(-tw, y1, -td)
	var tfr := Vector3(tw, y1, -td)
	var tbr := Vector3(tw, y1, td)
	var tbl := Vector3(-tw, y1, td)

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(surface, bfl, tfl, tfr, bfr) # front
	_add_quad(surface, bfr, tfr, tbr, bbr) # right
	_add_quad(surface, bbr, tbr, tbl, bbl) # back
	_add_quad(surface, bbl, tbl, tfl, bfl) # left
	_add_quad(surface, tfl, tbl, tbr, tfr) # top
	_add_quad(surface, bfl, bfr, bbr, bbl) # bottom
	return surface.commit()


static func _make_beveled_frustum_mesh(height: float, bottom_width: float, top_width: float, bottom_depth: float, top_depth: float) -> ArrayMesh:
	var y0 := -height * 0.5
	var y1 := height * 0.5
	var bottom := _beveled_ring(y0, bottom_width, bottom_depth)
	var top := _beveled_ring(y1, top_width, top_depth)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(8):
		var next := (index + 1) % 8
		_add_quad(surface, bottom[index], top[index], top[next], bottom[next])
	var top_center := Vector3(0.0, y1, 0.0)
	var bottom_center := Vector3(0.0, y0, 0.0)
	for index in range(8):
		var next := (index + 1) % 8
		_add_triangle(surface, top_center, top[index], top[next], Vector3.UP)
		_add_triangle(surface, bottom_center, bottom[next], bottom[index], Vector3.DOWN)
	return surface.commit()


static func _make_shirt_torso_mesh(height: float, bottom_width: float, shoulder_width: float, bottom_depth: float, shoulder_depth: float) -> ArrayMesh:
	var y0 := -height * 0.5
	var y_shoulder := height * 0.31
	var y1 := height * 0.5
	var bottom := _beveled_ring(y0, bottom_width, bottom_depth)
	var shoulder := _beveled_ring(y_shoulder, shoulder_width, shoulder_depth)
	var collar := _beveled_ring(y1, shoulder_width * 0.78, shoulder_depth * 0.82)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var facet_values := [1.0, 0.94, 0.86, 0.82, 0.80, 0.83, 0.88, 0.95]
	for index in range(8):
		var next := (index + 1) % 8
		var shade: float = facet_values[index]
		var facet_color := Color(shade, shade, shade, 1.0)
		_add_colored_quad(surface, bottom[index], shoulder[index], shoulder[next], bottom[next], facet_color)
		_add_colored_quad(surface, shoulder[index], collar[index], collar[next], shoulder[next], facet_color.darkened(0.025))
	var top_center := Vector3(0.0, y1, 0.0)
	var bottom_center := Vector3(0.0, y0, 0.0)
	for index in range(8):
		var next := (index + 1) % 8
		_add_colored_triangle(surface, top_center, collar[index], collar[next], Vector3.UP, Color(0.92, 0.92, 0.92, 1.0))
		_add_colored_triangle(surface, bottom_center, bottom[next], bottom[index], Vector3.DOWN, Color(0.78, 0.78, 0.78, 1.0))
	return surface.commit()


static func _beveled_ring(y: float, width: float, depth: float) -> Array[Vector3]:
	var half_width := width * 0.5
	var half_depth := depth * 0.5
	var bevel := minf(width, depth) * 0.115
	return [
		Vector3(-half_width + bevel, y, -half_depth),
		Vector3(half_width - bevel, y, -half_depth),
		Vector3(half_width, y, -half_depth + bevel),
		Vector3(half_width, y, half_depth - bevel),
		Vector3(half_width - bevel, y, half_depth),
		Vector3(-half_width + bevel, y, half_depth),
		Vector3(-half_width, y, half_depth - bevel),
		Vector3(-half_width, y, -half_depth + bevel),
	]


static func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	for vertex in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)


static func _add_colored_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal := Plane(a, b, c).normal
	for vertex in [a, b, c, a, c, d]:
		surface.set_normal(normal)
		surface.set_color(color)
		surface.add_vertex(vertex)


static func _add_colored_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	for vertex in [a, b, c]:
		surface.set_normal(normal)
		surface.set_color(color)
		surface.add_vertex(vertex)


static func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal := Plane(a, b, c).normal
	for vertex in [a, b, c, a, c, d]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)
