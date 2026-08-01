extends Area3D
class_name HideSpot

## A small raycast-interactable cover location with a fixed, limited-peek camera.

var hide_camera: Camera3D
var description := "Hide"


func build(label_text: String = "Hide") -> void:
	description = label_text
	collision_layer = 1
	collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 1.5, 1.0)
	collision.shape = shape
	collision.position = Vector3(0.0, 0.75, 0.0)
	add_child(collision)

	var cover := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.25, 0.72, 0.8)
	cover.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("342d26")
	material.roughness = 1.0
	cover.material_override = material
	cover.position = Vector3(0.0, 0.36, 0.0)
	add_child(cover)

	hide_camera = Camera3D.new()
	hide_camera.name = "HideCamera"
	hide_camera.position = Vector3(0.0, 0.48, 0.22)
	hide_camera.rotation_degrees = Vector3(-4.0, 180.0, 0.0)
	hide_camera.current = false
	add_child(hide_camera)


func get_interaction_prompt() -> String:
	return "Hide: " + description


func interact(player: Node) -> void:
	if player != null and player.has_method("enter_hiding"):
		player.enter_hiding(hide_camera)
