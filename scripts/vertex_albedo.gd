class_name VertexAlbedo
extends RefCounted

## Makes the map's baked vertex colours actually reach albedo in Godot.
##
## build_map.py writes a per-vertex tint (per-building colour jitter, wall-base
## grime, ground and landuse mottling) and the glTF carries it correctly as
## COLOR_0 -- verified end to end: the colours arrive in the imported mesh
## intact, in ARRAY_COLOR, with the right values.
##
## Godot's glTF importer sets `vertex_color_use_as_albedo` for MOST of those
## materials on its own, but not all of them, and the gap is not cosmetic. On
## the current map it flags 38 of the 39 materials that carry colour and misses
## exactly one: `Ground` -- the single largest surface in the world, and the
## one the mottling exists to break up. Left alone it renders flat, which is
## the problem this was supposed to fix.
##
## So this does not assume the importer is either reliable or useless. It sets
## the flag wherever it is missing and leaves the rest alone, which is why
## `apply()` normally reports a very small number: that number is the size of
## the importer's blind spot, not the size of the job.
##
## Why here and not in the .import files: `import_script/path` would do the job,
## but the map is 364 streamed tiles plus a base, and only 10 of those 368
## .import files are tracked by git -- the rest are generated locally and are
## regenerated whenever the extent changes. Patching them would have to be
## redone on every rebuild and would silently miss any newly added tile. This
## runs off the loaded scene instead, so it cannot drift out of sync with the
## geometry.
##
## Cost is a walk of each tile's MeshInstance3D surfaces once at load. The
## material resources are shared per-GLB and mutated in place, so a tile that
## streams out and back in while its PackedScene is still cached does no work
## the second time.

const _DONE_META := &"vertex_albedo_applied"


## Set the flag on every material under `root`. Returns how many it changed.
static func apply(root: Node) -> int:
	if root == null:
		return 0
	var changed := 0
	for node in _mesh_instances(root):
		var mesh: Mesh = node.mesh
		if mesh == null or mesh.has_meta(_DONE_META):
			continue
		mesh.set_meta(_DONE_META, true)
		for i in mesh.get_surface_count():
			# Only surfaces that actually carry colour data. Setting the flag on
			# a mesh without ARRAY_COLOR is harmless -- the shader reads white --
			# but skipping them keeps this honest about what it touched.
			if not (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR):
				continue
			var material := mesh.surface_get_material(i)
			if material is BaseMaterial3D:
				var m := material as BaseMaterial3D
				if not m.get_flag(BaseMaterial3D.FLAG_ALBEDO_FROM_VERTEX_COLOR):
					m.set_flag(BaseMaterial3D.FLAG_ALBEDO_FROM_VERTEX_COLOR, true)
					# COLOR_0 is linear in glTF and the tint is authored linear
					# in Blender, so it must NOT be re-decoded as sRGB here.
					m.set_flag(BaseMaterial3D.FLAG_SRGB_VERTEX_COLOR, false)
					changed += 1
	return changed


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(node, out)
	return out


static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	## Explicit accumulator rather than a defaulted `out` parameter: a default
	## array argument that survives between calls would make every later tile
	## re-walk every earlier tile's meshes.
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, out)
