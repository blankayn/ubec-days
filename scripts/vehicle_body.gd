extends VehicleBody3D
class_name DrivableVehicle
## Physics-sim drivable car / jeepney built on the PSX vehicle GLBs.
##
## The models are authored nose-along local +X with the ground at y = 0, while
## VehicleBody3D drives along -Z, so the visual is yawed a quarter turn on
## build. Their wheels are baked into the body mesh rather than being separate
## nodes, so the VehicleWheel3D positions come from the measured model bounds
## and nothing spins visually -- the suspension moves the body, not the wheels.

const StreetVehicleProp := preload("res://scripts/street_vehicle_prop.gd")

## Emitted when the player interacts with a parked vehicle. The map owns the
## hand-over, since it is the thing that knows about the player and camera.
signal enter_requested(player: Node)
signal exit_requested()

enum Kind { STREET_CAR, JEEPNEY }

## Measured from the GLBs: cars are 4.96 x 1.98 x 2.46 (L x H x W) and jeepneys
## 6.32 x 2.72 x 2.72, both sitting on y = 0.
##
## wheel_y is the suspension anchor. A wheel hangs (rest_length + radius) below
## it when fully extended, so at roughly half compression the body settles with
## its origin near the road -- which is where the model's baked wheels are.
##
## Suspension stiffness is sized for this project's 18 m/s^2 gravity, not the
## 9.8 Godot's defaults assume. Godot's spring force works out proportional to
## stiffness * compression * mass, so holding the car up takes a compression of
## gravity / (4 * stiffness); at the engine default of 5.88 these cars bottom
## out and lose most of their traction with it.
const SPECS := {
	Kind.STREET_CAR: {
		"mass": 1250.0,
		"chassis_size": Vector3(1.95, 0.78, 4.30),
		"chassis_y": 0.74,
		"wheel_radius": 0.35,
		"wheel_y": 0.50,
		"half_track": 0.88,
		"front_z": -1.45,
		"rear_z": 1.45,
		"engine_force": 900.0,
		"max_steer_deg": 32.0,
		"suspension_stiffness": 64.0,
		"suspension_travel": 0.22,
	},
	Kind.JEEPNEY: {
		"mass": 2600.0,
		"chassis_size": Vector3(2.15, 1.05, 5.60),
		"chassis_y": 0.95,
		"wheel_radius": 0.42,
		"wheel_y": 0.60,
		"half_track": 0.95,
		"front_z": -1.90,
		"rear_z": 1.90,
		"engine_force": 1500.0,
		"max_steer_deg": 28.0,
		"suspension_stiffness": 56.0,
		"suspension_travel": 0.26,
	},
}

## The models face +X; this node's nose is -Z, so yaw them a quarter turn.
const MODEL_YAW := PI * 0.5

## Measured, because it is the opposite of what the rest of Godot does: a
## positive engine_force accelerates a VehicleBody3D toward +Z, while -Z is
## "forward" for every other node (cameras, look_at, the model yaw above).
## Godot builds each wheel's drive axis as axle x direction = +Z and never
## flips it. Rather than invert the whole node and leave 2c's chase camera
## looking out of the back window, the throttle is negated here: this node's
## nose stays at -Z like everything else in the project.
const ENGINE_FORCE_SIGN := -1.0

const BRAKE_FORCE := 14.0
const HANDBRAKE_FORCE := 42.0
## Below this the car counts as stopped, so throttle picks a direction instead
## of fighting the current one.
const STOPPED_SPEED := 0.6
const STEER_RATE := 3.4
const STEER_RETURN_RATE := 5.0
## Steering is scaled down as speed rises or the car spins out on a flick.
const STEER_FALLOFF_SPEED := 26.0
const STEER_FALLOFF_MIN := 0.34

## Roll recovery: below this much "up" the car is on its side or roof.
const UPRIGHT_DOT := 0.35
const UPRIGHT_TORQUE := 5.5

## Chase camera. It swings round behind the car rather than snapping, so a
## slide or a spin reads as one.
const CAMERA_HEIGHT := 1.35
const CAMERA_PITCH := -0.18
const CAMERA_FOLLOW_RATE := 3.6
const CAMERA_DISTANCE := 7.4

@export var kind: Kind = Kind.STREET_CAR
@export var variant_index: int = 0
@export var build_on_ready := true
@export var nearest_texture_filtering := true
## Set false to park it: physics still runs, input is ignored.
@export var driver_active := false

var _built := false
var _visual_model: Node3D
var _spec: Dictionary = {}
var _wheels: Array[VehicleWheel3D] = []
var _max_steer := 0.55

var _camera_rig: Node3D = null
var _spring_arm: SpringArm3D = null
var _camera_yaw := 0.0
var _restore_spring_length := 0.0


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	_spec = SPECS[kind]
	_max_steer = deg_to_rad(float(_spec["max_steer_deg"]))

	mass = float(_spec["mass"])
	# Well below the chassis box, which is what stops a hard corner rolling it.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -0.28, 0.0)
	# Layer 1 as well as the vehicle layer, so the player's interaction ray
	# (mask 1) can find it and so bodies cannot walk through it.
	collision_layer = 1 | 4
	collision_mask = 1

	_build_visual()
	_build_chassis_collision()
	_build_wheels()


func _build_visual() -> void:
	var path := _resolve_path()
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("DrivableVehicle could not load: %s" % path)
		return
	_visual_model = packed.instantiate() as Node3D
	if _visual_model == null:
		push_error("DrivableVehicle could not instantiate: %s" % path)
		return
	_visual_model.name = "VehicleModel"
	_visual_model.rotation.y = MODEL_YAW
	add_child(_visual_model)
	_strip_non_prop_nodes(_visual_model)
	_prepare_materials(_visual_model)


func _build_chassis_collision() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "ChassisCollision"
	var box := BoxShape3D.new()
	box.size = _spec["chassis_size"]
	shape.shape = box
	# Kept clear of the ground so the wheel rays, not the box, carry the car.
	shape.position = Vector3(0.0, float(_spec["chassis_y"]), 0.0)
	add_child(shape)


func _build_wheels() -> void:
	var half_track := float(_spec["half_track"])
	var front_z := float(_spec["front_z"])
	var rear_z := float(_spec["rear_z"])
	_wheels.clear()
	_wheels.append(_make_wheel("WheelFrontLeft", Vector3(-half_track, 0.0, front_z), true))
	_wheels.append(_make_wheel("WheelFrontRight", Vector3(half_track, 0.0, front_z), true))
	_wheels.append(_make_wheel("WheelRearLeft", Vector3(-half_track, 0.0, rear_z), false))
	_wheels.append(_make_wheel("WheelRearRight", Vector3(half_track, 0.0, rear_z), false))


## All four wheels pull. Rear-wheel drive spins out constantly on OSM geometry
## that is full of kerbs and 13 cm road edges.
func _make_wheel(wheel_name: String, offset: Vector3, is_front: bool) -> VehicleWheel3D:
	var wheel := VehicleWheel3D.new()
	wheel.name = wheel_name
	wheel.position = Vector3(offset.x, float(_spec["wheel_y"]), offset.z)
	wheel.wheel_radius = float(_spec["wheel_radius"])
	wheel.wheel_rest_length = float(_spec["suspension_travel"])
	wheel.wheel_friction_slip = 3.2
	wheel.suspension_stiffness = float(_spec["suspension_stiffness"])
	wheel.suspension_travel = float(_spec["suspension_travel"])
	wheel.suspension_max_force = mass * 22.0
	wheel.damping_compression = 0.86
	wheel.damping_relaxation = 1.1
	wheel.use_as_steering = is_front
	wheel.use_as_traction = true
	add_child(wheel)
	return wheel


func _physics_process(delta: float) -> void:
	if driver_active:
		_apply_driver_input(delta)
		_update_chase_camera(delta)
	else:
		engine_force = 0.0
		steering = move_toward(steering, 0.0, STEER_RETURN_RATE * delta)
		brake = BRAKE_FORCE
	_apply_roll_recovery()


## ---------------------------------------------------------------------
## Chase camera: the map hands over the player's own orbit rig, so there is
## one camera in the scene and no cut when getting in or out.
## ---------------------------------------------------------------------

func attach_camera(rig: Node3D, spring_arm: SpringArm3D) -> void:
	_camera_rig = rig
	_spring_arm = spring_arm
	_camera_yaw = _heading_yaw()
	if _spring_arm != null:
		_restore_spring_length = _spring_arm.spring_length
		_spring_arm.spring_length = CAMERA_DISTANCE
		_spring_arm.add_excluded_object(get_rid())
	_update_chase_camera(1.0)


func detach_camera() -> void:
	if _spring_arm != null:
		_spring_arm.spring_length = _restore_spring_length
		_spring_arm.remove_excluded_object(get_rid())
	_camera_rig = null
	_spring_arm = null


func _update_chase_camera(delta: float) -> void:
	if _camera_rig == null:
		return
	_camera_yaw = lerp_angle(
		_camera_yaw, _heading_yaw(), minf(delta * CAMERA_FOLLOW_RATE, 1.0)
	)
	_camera_rig.global_position = global_position + Vector3.UP * CAMERA_HEIGHT
	_camera_rig.global_rotation = Vector3(0.0, _camera_yaw, 0.0)
	if _spring_arm != null:
		_spring_arm.rotation.x = CAMERA_PITCH


## Yaw of the nose, flattened. Read off the basis rather than global_rotation.y
## so body roll and pitch do not leak into the camera.
func _heading_yaw() -> float:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return _camera_yaw
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


func _apply_driver_input(delta: float) -> void:
	var throttle := Input.get_axis(&"move_back", &"move_forward")
	var steer_input := Input.get_axis(&"move_right", &"move_left")
	var handbrake := Input.is_action_pressed(&"handbrake")

	# Signed speed along the nose, so "forward" while rolling backwards brakes
	# instead of fighting the wheels.
	var speed := linear_velocity.dot(-global_basis.z)

	engine_force = 0.0
	brake = 0.0
	if handbrake:
		brake = HANDBRAKE_FORCE
	elif throttle > 0.01:
		if speed < -STOPPED_SPEED:
			brake = BRAKE_FORCE
		else:
			engine_force = ENGINE_FORCE_SIGN * throttle * float(_spec["engine_force"])
	elif throttle < -0.01:
		if speed > STOPPED_SPEED:
			brake = BRAKE_FORCE
		else:
			# Reverse is deliberately weaker than forward drive.
			engine_force = (
				ENGINE_FORCE_SIGN * throttle * float(_spec["engine_force"]) * 0.45
			)
	else:
		brake = BRAKE_FORCE * 0.18

	var steer_limit := _max_steer * _steer_scale(absf(speed))
	if absf(steer_input) > 0.01:
		steering = move_toward(steering, steer_input * steer_limit, STEER_RATE * delta)
	else:
		steering = move_toward(steering, 0.0, STEER_RETURN_RATE * delta)


## Full lock at parking speed would flip the car at 60 km/h.
func _steer_scale(speed: float) -> float:
	var t := clampf(speed / STEER_FALLOFF_SPEED, 0.0, 1.0)
	return lerpf(1.0, STEER_FALLOFF_MIN, t)


## Nudges the car back over when it ends up on its side or roof, rather than
## leaving it stranded. Does nothing while it is upright.
func _apply_roll_recovery() -> void:
	var up := global_basis.y
	if up.dot(Vector3.UP) >= UPRIGHT_DOT:
		return
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 0.0001:
		return
	apply_torque(axis.normalized() * mass * UPRIGHT_TORQUE)


func set_driver_active(active: bool) -> void:
	driver_active = active
	if not active:
		engine_force = 0.0


## ---------------------------------------------------------------------
## Interaction (Milestone 1b): duck-typed, exactly like interactable.gd, so
## the player's probe picks a parked car up with no special-casing.
## ---------------------------------------------------------------------

func get_interaction_prompt() -> String:
	if driver_active:
		return ""
	return "Drive the jeepney" if kind == Kind.JEEPNEY else "Drive"


func interact(player: Node) -> void:
	if driver_active:
		return
	enter_requested.emit(player)


## Where to stand the player when they get out: alongside the driver's door,
## clear of the body so they do not spawn inside it.
func get_exit_position() -> Vector3:
	var side := float(_spec["chassis_size"].x) * 0.5 + 0.9
	var candidate := global_position + global_basis.x * -side
	return candidate + Vector3.UP * 0.6


## Seat position for hiding the player and for the chase camera's pivot.
func get_seat_position() -> Vector3:
	return global_position + Vector3.UP * float(_spec["chassis_y"])


func get_speed_kph() -> float:
	return linear_velocity.length() * 3.6


func get_visual_model() -> Node3D:
	return _visual_model


## ---------------------------------------------------------------------
## Model plumbing, shared in spirit with street_vehicle_prop.gd
## ---------------------------------------------------------------------

func _resolve_path() -> String:
	if kind == Kind.JEEPNEY:
		var jeepneys: Array = StreetVehicleProp.JEEPNEY_PATHS
		return jeepneys[posmod(variant_index, jeepneys.size())]
	var cars: Array = StreetVehicleProp.STREET_CAR_PATHS
	return cars[posmod(variant_index, cars.size())]


func _strip_non_prop_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is Camera3D or child is AnimationPlayer or child is Light3D:
			node.remove_child(child)
			child.queue_free()
			continue
		_strip_non_prop_nodes(child)


func _prepare_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.get_active_material(surface_index)
				if source_material == null:
					continue
				var material := source_material.duplicate(true)
				if material is BaseMaterial3D:
					var base_material := material as BaseMaterial3D
					if nearest_texture_filtering:
						base_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					base_material.metallic = 0.0
					base_material.roughness = maxf(base_material.roughness, 0.82)
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_prepare_materials(child)
