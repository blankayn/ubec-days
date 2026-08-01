extends RefCounted
class_name OrigamiFigure
## Folded-paper human built from thin, angled prism panels.


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
	root.name = "OrigamiFigure"
	parent.add_child(root)

	var head: MeshInstance3D = null
	match pose:
		"sit":
			head = _build_sitting(root, get_material, shirt, pants, skin, accent)
		"crouch":
			head = _build_crouch(root, get_material, shirt, pants, skin, accent)
		_:
			head = _build_standing(root, get_material, shirt, pants, skin, accent)

	return { "root": root, "head": head }


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
	label.position = Vector3(0.0, 0.0, 0.0)
	anchor.add_child(label)


static func _build_standing(
	root: Node3D,
	get_material: Callable,
	shirt: Color,
	pants: Color,
	skin: Color,
	accent: Color
) -> MeshInstance3D:
	# Pelvis / hip fold
	_fold(root, get_material, "Pelvis", Vector3(0.0, 0.78, 0.0), Vector3(8, 0, 0), Vector3(0.42, 0.16, 0.28), pants)
	_crease(root, get_material, Vector3(0.0, 0.78, 0.02), Vector3(0.04, 0.14, 0.24), accent.darkened(0.35))

	# Torso — front & back panels like a folded shirt
	_fold(root, get_material, "TorsoFront", Vector3(0.0, 1.22, -0.06), Vector3(12, 0, 0), Vector3(0.52, 0.72, 0.06), shirt)
	_fold(root, get_material, "TorsoBack", Vector3(0.0, 1.2, 0.08), Vector3(-8, 0, 0), Vector3(0.48, 0.68, 0.05), shirt.darkened(0.12))
	_fold(root, get_material, "TorsoSideL", Vector3(-0.22, 1.18, 0.0), Vector3(0, 18, -6), Vector3(0.06, 0.62, 0.22), shirt.lightened(0.08))
	_fold(root, get_material, "TorsoSideR", Vector3(0.22, 1.18, 0.0), Vector3(0, -18, 6), Vector3(0.06, 0.62, 0.22), shirt.lightened(0.08))
	_crease(root, get_material, Vector3(0.0, 1.35, -0.09), Vector3(0.03, 0.5, 0.02), accent)

	# Arms — two-segment origami limbs
	_limb(root, get_material, "ArmLUpper", Vector3(-0.34, 1.34, -0.02), Vector3(0, 0, 28), Vector3(0.08, 0.34, 0.14), shirt.darkened(0.08))
	_limb(root, get_material, "ArmLLower", Vector3(-0.52, 1.02, -0.08), Vector3(0, 0, -18), Vector3(0.07, 0.32, 0.12), skin)
	_limb(root, get_material, "ArmRUpper", Vector3(0.34, 1.34, -0.02), Vector3(0, 0, -28), Vector3(0.08, 0.34, 0.14), shirt.darkened(0.08))
	_limb(root, get_material, "ArmRLower", Vector3(0.52, 1.02, -0.08), Vector3(0, 0, 18), Vector3(0.07, 0.32, 0.12), skin)

	# Legs — bent paper strips
	_limb(root, get_material, "LegLThigh", Vector3(-0.14, 0.52, 0.02), Vector3(6, 0, 4), Vector3(0.1, 0.42, 0.14), pants)
	_limb(root, get_material, "LegLShin", Vector3(-0.16, 0.18, 0.06), Vector3(-4, 0, 2), Vector3(0.09, 0.38, 0.12), pants.darkened(0.1))
	_limb(root, get_material, "LegRThigh", Vector3(0.14, 0.52, 0.02), Vector3(-6, 0, -4), Vector3(0.1, 0.42, 0.14), pants)
	_limb(root, get_material, "LegRShin", Vector3(0.16, 0.18, 0.06), Vector3(4, 0, -2), Vector3(0.09, 0.38, 0.12), pants.darkened(0.1))
	_fold(root, get_material, "FootL", Vector3(-0.18, 0.02, 0.1), Vector3(0, 8, 0), Vector3(0.14, 0.04, 0.22), accent.darkened(0.5))
	_fold(root, get_material, "FootR", Vector3(0.18, 0.02, 0.1), Vector3(0, -8, 0), Vector3(0.14, 0.04, 0.22), accent.darkened(0.5))

	return _build_head(root, get_material, skin, accent)


static func _build_sitting(
	root: Node3D,
	get_material: Callable,
	shirt: Color,
	pants: Color,
	skin: Color,
	accent: Color
) -> MeshInstance3D:
	_fold(root, get_material, "Pelvis", Vector3(0.0, 0.55, 0.05), Vector3(0, 0, 0), Vector3(0.4, 0.14, 0.3), pants)
	_fold(root, get_material, "TorsoFront", Vector3(0.0, 0.92, -0.04), Vector3(18, 0, 0), Vector3(0.5, 0.62, 0.06), shirt)
	_fold(root, get_material, "TorsoBack", Vector3(0.0, 0.9, 0.1), Vector3(-12, 0, 0), Vector3(0.46, 0.58, 0.05), shirt.darkened(0.12))
	_limb(root, get_material, "LegLThigh", Vector3(-0.16, 0.42, -0.22), Vector3(72, 0, 0), Vector3(0.1, 0.22, 0.48), pants)
	_limb(root, get_material, "LegRThigh", Vector3(0.16, 0.42, -0.22), Vector3(72, 0, 0), Vector3(0.1, 0.22, 0.48), pants)
	_limb(root, get_material, "ArmLUpper", Vector3(-0.3, 0.86, 0.0), Vector3(0, 0, 22), Vector3(0.07, 0.28, 0.12), shirt)
	_limb(root, get_material, "ArmRUpper", Vector3(0.3, 0.86, 0.0), Vector3(0, 0, -22), Vector3(0.07, 0.28, 0.12), shirt)
	return _build_head(root, get_material, skin, accent, Vector3(0.0, 1.28, 0.12))


static func _build_crouch(
	root: Node3D,
	get_material: Callable,
	shirt: Color,
	pants: Color,
	skin: Color,
	accent: Color
) -> MeshInstance3D:
	_fold(root, get_material, "Pelvis", Vector3(0.0, 0.62, 0.0), Vector3(0, 0, 0), Vector3(0.38, 0.14, 0.26), pants)
	_fold(root, get_material, "TorsoFront", Vector3(0.0, 1.0, -0.08), Vector3(22, 0, 0), Vector3(0.48, 0.58, 0.06), shirt)
	_limb(root, get_material, "LegLThigh", Vector3(-0.18, 0.48, -0.08), Vector3(48, 0, 12), Vector3(0.1, 0.3, 0.14), pants)
	_limb(root, get_material, "LegLShin", Vector3(-0.22, 0.22, 0.18), Vector3(-58, 0, -8), Vector3(0.09, 0.28, 0.12), pants.darkened(0.1))
	_limb(root, get_material, "LegRThigh", Vector3(0.18, 0.48, -0.08), Vector3(48, 0, -12), Vector3(0.1, 0.3, 0.14), pants)
	_limb(root, get_material, "LegRShin", Vector3(0.22, 0.22, 0.18), Vector3(-58, 0, 8), Vector3(0.09, 0.28, 0.12), pants.darkened(0.1))
	_limb(root, get_material, "ArmLUpper", Vector3(-0.32, 0.95, -0.06), Vector3(0, 0, 35), Vector3(0.07, 0.3, 0.12), shirt)
	_limb(root, get_material, "ArmRUpper", Vector3(0.32, 0.95, -0.06), Vector3(0, 0, -35), Vector3(0.07, 0.3, 0.12), shirt)
	return _build_head(root, get_material, skin, accent, Vector3(0.0, 1.38, -0.04))


static func _build_head(
	root: Node3D,
	get_material: Callable,
	skin: Color,
	accent: Color,
	position: Vector3 = Vector3(0.0, 1.72, -0.02)
) -> MeshInstance3D:
	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = position
	root.add_child(head_pivot)

	# Pyramid-like folded head (top + two cheek folds)
	var head_top := _fold(head_pivot, get_material, "HeadTop", Vector3(0.0, 0.12, 0.0), Vector3(0, 0, 45), Vector3(0.28, 0.22, 0.28), skin)
	_fold(head_pivot, get_material, "HeadFace", Vector3(0.0, -0.02, -0.1), Vector3(14, 0, 0), Vector3(0.24, 0.26, 0.06), skin.lightened(0.06))
	_fold(head_pivot, get_material, "HeadCheekL", Vector3(-0.12, 0.0, -0.02), Vector3(0, 24, 8), Vector3(0.06, 0.2, 0.18), skin.darkened(0.08))
	_fold(head_pivot, get_material, "HeadCheekR", Vector3(0.12, 0.0, -0.02), Vector3(0, -24, -8), Vector3(0.06, 0.2, 0.18), skin.darkened(0.08))
	_crease(head_pivot, get_material, Vector3(0.0, 0.18, -0.02), Vector3(0.02, 0.16, 0.16), accent.darkened(0.4))
	return head_top


static func _fold(
	parent: Node,
	get_material: Callable,
	part_name: String,
	position: Vector3,
	rotation_deg: Vector3,
	size: Vector3,
	color: Color
) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = position
	part.rotation_degrees = rotation_deg
	part.material_override = get_material.call(color)
	parent.add_child(part)
	return part


static func _limb(
	parent: Node,
	get_material: Callable,
	part_name: String,
	position: Vector3,
	rotation_deg: Vector3,
	size: Vector3,
	color: Color
) -> MeshInstance3D:
	return _fold(parent, get_material, part_name, position, rotation_deg, size, color)


static func _crease(
	parent: Node,
	get_material: Callable,
	position: Vector3,
	size: Vector3,
	color: Color
) -> MeshInstance3D:
	return _fold(parent, get_material, "Crease", position, Vector3.ZERO, size, color)
