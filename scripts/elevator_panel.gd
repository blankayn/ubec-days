extends "res://scripts/interactable.gd"
class_name ElevatorPanel

var destination_floor := 1
var destination_position := Vector3.ZERO


func configure(
	panel_id: StringName,
	panel_prompt: String,
	panel_message: String,
	floor_number: int,
	spawn_position: Vector3
) -> void:
	setup(panel_id, panel_prompt, panel_message, false)
	destination_floor = floor_number
	destination_position = spawn_position


func interact(player: Node) -> void:
	if disabled or not player is CharacterBody3D:
		return
	activated.emit(interactable_id, message)
