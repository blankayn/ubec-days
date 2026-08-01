extends StaticBody3D
class_name SurvivalDoor

## Interactive classroom door with lock, barricade, and creature-break states.

signal noise_emitted(position: Vector3, level: float, radius: float)
signal barricade_broken(door: SurvivalDoor)
signal message_requested(text: String)

enum DoorState { UNLOCKED, LOCKED, BARRICADABLE, BARRICADED, BROKEN }

var door_state: DoorState = DoorState.UNLOCKED
var configured_state: DoorState = DoorState.UNLOCKED
var required_key: StringName = &""
var _is_open := false
var _base_rotation := 0.0
var _door_collision: CollisionShape3D
var _barricade_elapsed := 0.0
var _barricade_stage := 0


func configure(initial_state: DoorState, key_id: StringName = &"") -> void:
	door_state = initial_state
	configured_state = initial_state
	required_key = key_id


func set_chapter_access(night_mode: bool) -> void:
	if not night_mode and configured_state == DoorState.LOCKED:
		door_state = DoorState.UNLOCKED
	elif night_mode and configured_state == DoorState.LOCKED and not _is_open:
		door_state = DoorState.LOCKED


func build() -> void:
	_base_rotation = rotation.y
	var animation_player := AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	add_child(animation_player)
	var audio_player := AudioStreamPlayer3D.new()
	audio_player.name = "DoorAudio"
	add_child(audio_player)
	var panel := MeshInstance3D.new()
	panel.name = "DoorMesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.25, 2.35, 0.12)
	panel.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4a3828")
	material.roughness = 0.95
	panel.material_override = material
	panel.position = Vector3(0.0, 1.175, 0.0)
	add_child(panel)

	_door_collision = CollisionShape3D.new()
	_door_collision.name = "DoorCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.25, 2.35, 0.18)
	_door_collision.shape = shape
	_door_collision.position = Vector3(0.0, 1.175, 0.0)
	add_child(_door_collision)

	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.12, 0.12, 0.05)
	plate.mesh = plate_mesh
	var plate_material := StandardMaterial3D.new()
	plate_material.albedo_color = Color("c5a052")
	plate.material_override = plate_material
	plate.position = Vector3(0.42, 1.12, 0.09)
	add_child(plate)


func get_interaction_prompt() -> String:
	match door_state:
		DoorState.LOCKED:
			return "Unlock door" if not required_key.is_empty() else "Locked"
		DoorState.BARRICADED:
			return "Unbarricade door"
		DoorState.BROKEN:
			return "Broken door"
		DoorState.BARRICADABLE:
			return "Barricade door" if not _is_open else "Close door"
		_:
			return "Close door" if _is_open else "Open door"


func interact(player: Node) -> void:
	if door_state == DoorState.BROKEN:
		message_requested.emit("The door is splintered beyond use.")
		return
	if door_state == DoorState.LOCKED:
		if required_key.is_empty() or not player.has_method("has_key") or not player.has_key(required_key):
			message_requested.emit("LOCKED  //  Requires %s" % String(required_key).to_upper())
			return
		door_state = DoorState.UNLOCKED
		message_requested.emit("UNLOCKED: %s" % String(required_key).to_upper())
	if door_state == DoorState.BARRICADED:
		_cancel_barricade()
		return
	if door_state == DoorState.BARRICADABLE and not _is_open:
		_start_barricade()
		return
	if _is_open:
		_close()
	else:
		_open()


func creature_arrived() -> void:
	if door_state != DoorState.BARRICADED:
		return
	_barricade_elapsed = 0.01
	_barricade_stage = 0
	message_requested.emit("Something found the barricaded door.")


func _process(delta: float) -> void:
	if door_state != DoorState.BARRICADED or _barricade_elapsed <= 0.0:
		return
	_barricade_elapsed += delta
	if _barricade_stage == 0 and _barricade_elapsed >= 0.1:
		_barricade_stage = 1
		_bang("BANG 1  //  The door shudders.")
	elif _barricade_stage == 1 and _barricade_elapsed >= 3.0:
		_barricade_stage = 2
		_bang("BANG 2  //  Wood cracks under the force.")
	elif _barricade_stage == 2 and _barricade_elapsed >= 7.0:
		_barricade_stage = 3
		_bang("BANG 3  //  The barricade is splintering.")
	elif _barricade_stage == 3 and _barricade_elapsed >= 10.0:
		door_state = DoorState.BROKEN
		_barricade_elapsed = 0.0
		_open()
		message_requested.emit("THE DOOR BREAKS OPEN.")
		barricade_broken.emit(self)


func _open() -> void:
	_is_open = true
	_door_collision.set_deferred("disabled", true)
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", _base_rotation + PI * 0.5, 0.4).set_trans(Tween.TRANS_SINE)
	noise_emitted.emit(global_position, 4.0, 10.0)


func _close() -> void:
	_is_open = false
	_door_collision.set_deferred("disabled", false)
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", _base_rotation, 0.4).set_trans(Tween.TRANS_SINE)
	noise_emitted.emit(global_position, 7.0, 18.0)


func _start_barricade() -> void:
	_is_open = false
	_door_collision.set_deferred("disabled", false)
	door_state = DoorState.BARRICADED
	_barricade_elapsed = 0.0
	_barricade_stage = 0
	message_requested.emit("BARRICADED  //  Press E again to remove it.")
	noise_emitted.emit(global_position, 7.0, 18.0)


func _cancel_barricade() -> void:
	door_state = DoorState.BARRICADABLE
	_barricade_elapsed = 0.0
	_barricade_stage = 0
	message_requested.emit("Barricade removed.")


func _bang(text: String) -> void:
	message_requested.emit(text)
	noise_emitted.emit(global_position, 8.0, 22.0)
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", _base_rotation + deg_to_rad(4.0), 0.08)
	tween.tween_property(self, "rotation:y", _base_rotation - deg_to_rad(3.0), 0.08)
	tween.tween_property(self, "rotation:y", _base_rotation, 0.12)
