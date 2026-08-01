extends SceneTree
## Prints the imported albedo of each Banilad map mesh so washed-out surfaces
## can be traced to either the material or the lighting.

const MAP_SCENE := "res://assets/maps/banilad_map.glb"


func _initialize() -> void:
	var packed := load(MAP_SCENE) as PackedScene
	var level := packed.instantiate()

	for child in level.get_children():
		if not (child is MeshInstance3D):
			continue
		var mesh_instance := child as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(surface)
			if mat is StandardMaterial3D:
				var std := mat as StandardMaterial3D
				print("%-26s albedo=(%.3f, %.3f, %.3f)  rough=%.2f  metal=%.2f  unshaded=%s" % [
					mesh_instance.name, std.albedo_color.r, std.albedo_color.g,
					std.albedo_color.b, std.roughness, std.metallic,
					str(std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED),
				])
			elif mat == null:
				print("%-26s NO MATERIAL" % mesh_instance.name)
			else:
				print("%-26s %s" % [mesh_instance.name, mat.get_class()])
	quit(0)
