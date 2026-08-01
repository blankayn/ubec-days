extends SceneTree

## Deterministic visual-regression viewpoints for the UC–Gaisano corridor.
## Run with Godot's --write-movie option; frames 2–5 are daytime and frames
## 6–8 verify the same architectural language and bridge joins at night.

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _frame := 0


func _initialize() -> void:
	var packed := load("res://main.tscn") as PackedScene
	assert(packed != null, "Main scene must load for corridor capture")
	_world = packed.instantiate() as Node3D
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_player = _world.get_node("Player") as CharacterBody3D
		_head = _player.get_node("Head") as Node3D
		var hud := _world.get_node_or_null("HUD") as CanvasLayer
		if hud != null:
			hud.visible = false
		_set_view(Vector3(0.0, 1.05, 19.0), 0.0, 0.0)
	elif _frame == 3:
		# UC street frontage from the mall-side curb.
		_set_view(Vector3(0.0, 1.05, -3.0), PI, -0.08)
	elif _frame == 4:
		# Camp Lapu-Lapu Road looking north through the mall connector.
		_set_view(Vector3(20.0, 1.05, -27.0), 0.0, -0.04)
	elif _frame == 5:
		# Elevated overview proving north/south placement and open parking court.
		_set_view(Vector3(0.0, 31.0, 3.0), 0.0, -0.78)
	elif _frame == 6:
		_world.call("_apply_night_lighting")
		# Night check for the curved UC facade and its entrance seams.
		_set_view(Vector3(0.0, 1.05, -3.0), PI, -0.08)
	elif _frame == 7:
		# Night check for the Gaisano court, wing roofs and central facade.
		_set_view(Vector3(0.0, 1.05, 19.0), 0.0, 0.0)
	elif _frame == 8:
		# West-side pedestrian bridge landing and canopy transition.
		_set_view(Vector3(-38.0, 1.05, 31.0), 0.0, -0.12)
	elif _frame >= 9:
		quit()
	return false


func _set_view(position_value: Vector3, yaw: float, pitch: float) -> void:
	_player.global_position = position_value
	_player.rotation = Vector3(0.0, yaw, 0.0)
	_player.velocity = Vector3.ZERO
	_head.rotation = Vector3(pitch, 0.0, 0.0)
