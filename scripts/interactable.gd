extends StaticBody3D
class_name Interactable

signal activated(interactable_id: StringName, message: String)

var interactable_id: StringName = &"object"
var prompt: String = "Inspect"
var message: String = "Nothing unusual."
var one_shot: bool = false
var disabled: bool = false
var face_player_on_interact: bool = false


func setup(
	new_id: StringName,
	new_prompt: String,
	new_message: String,
	is_one_shot: bool = false
) -> void:
	interactable_id = new_id
	prompt = new_prompt
	message = new_message
	one_shot = is_one_shot


func get_interaction_prompt() -> String:
	if disabled:
		return ""
	return prompt


func interact(player: Node) -> void:
	if disabled:
		return
	if face_player_on_interact and player is Node3D:
		face_toward((player as Node3D).global_position)
	activated.emit(interactable_id, message)
	if one_shot:
		disabled = true


func face_toward(target_global_position: Vector3) -> void:
	var flat_target := Vector3(
		target_global_position.x,
		global_position.y,
		target_global_position.z
	)
	if global_position.distance_squared_to(flat_target) <= 0.000001:
		return
	look_at(flat_target, Vector3.UP)

