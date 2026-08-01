extends SceneTree
## Headless guard on the drivable vehicle: it must settle at the height its
## baked-in wheels are drawn at, pull away under throttle, steer, and stop.
##
##   .tools/godot/Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/vehicle_smoke_test.gd

const VehicleScript := preload("res://scripts/vehicle_body.gd")

const SETTLE_FRAMES := 90
const DRIVE_FRAMES := 150
const BRAKE_FRAMES := 120
const STEER_FRAMES := 200

## The GLBs are authored with their wheels touching y = 0, so the body origin
## has to rest near the road or the car floats or sinks into it.
const REST_HEIGHT_TOLERANCE := 0.12
## Metres the car must cover under full throttle in DRIVE_FRAMES.
const MIN_DRIVE_DISTANCE := 8.0

var _world: Node3D
var _car: VehicleScript
var _jeepney: VehicleScript

var _frames := 0
var _stage := 0
var _drive_origin := Vector3.ZERO
var _drive_end := Vector3.ZERO
var _steer_origin_forward := Vector3.ZERO
var _failures: Array[String] = []


func _initialize() -> void:
	_world = Node3D.new()
	_world.add_child(_make_floor())

	_car = VehicleScript.new()
	_car.name = "TestCar"
	_car.kind = VehicleScript.Kind.STREET_CAR
	_car.position = Vector3(0.0, 0.6, 0.0)
	_world.add_child(_car)

	# Built but never driven: proves the jeepney spec is valid too.
	_jeepney = VehicleScript.new()
	_jeepney.name = "TestJeepney"
	_jeepney.kind = VehicleScript.Kind.JEEPNEY
	_jeepney.position = Vector3(12.0, 0.8, 0.0)
	_world.add_child(_jeepney)

	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frames += 1
	match _stage:
		0:
			if _frames < SETTLE_FRAMES:
				return false
			_check_settled()
			_drive_origin = _car.global_position
			_car.set_driver_active(true)
			Input.action_press(&"move_forward")
			_frames = 0
			_stage = 1
		1:
			if _frames < DRIVE_FRAMES:
				return false
			_check_drive()
			Input.action_release(&"move_forward")
			Input.action_press(&"handbrake")
			_frames = 0
			_stage = 2
		2:
			if _frames < BRAKE_FRAMES:
				return false
			Input.action_release(&"handbrake")
			_check_stopped()
			_steer_origin_forward = -_car.global_basis.z
			Input.action_press(&"move_forward")
			Input.action_press(&"move_left")
			_frames = 0
			_stage = 3
		3:
			if _frames < STEER_FRAMES:
				return false
			Input.action_release(&"move_forward")
			Input.action_release(&"move_left")
			_check_steering()
			_finish()
			return true
	return false


func _check_settled() -> void:
	for label in [["car", _car], ["jeepney", _jeepney]]:
		var body := label[1] as VehicleBody3D
		var height := body.global_position.y
		var upright := body.global_basis.y.dot(Vector3.UP)
		var contacts := 0
		for child in body.get_children():
			var wheel := child as VehicleWheel3D
			if wheel != null and wheel.is_in_contact():
				contacts += 1
		print("[veh] %s settled: y=%.3f upright=%.3f wheels_in_contact=%d" % [
			label[0], height, upright, contacts,
		])
		if upright < 0.98:
			_fail("%s did not settle upright (up.y = %.3f)" % [label[0], upright])
		if contacts < 4:
			_fail("%s has %d of 4 wheels on the ground" % [label[0], contacts])
		if absf(height) > REST_HEIGHT_TOLERANCE:
			_fail(
				"%s rests at y=%.3f; its model's wheels are drawn at 0, so it %s"
				% [
					label[0], height,
					"floats" if height > 0.0 else "sinks into the road",
				]
			)


func _check_drive() -> void:
	_drive_end = _car.global_position
	var travelled := _drive_origin.distance_to(_drive_end)
	# The car is built nose along -Z, so forward progress is -Z.
	var forward := _drive_origin.z - _drive_end.z
	var upright := _car.global_basis.y.dot(Vector3.UP)
	print("[veh] drove %.2f m (%.2f m along the nose) at %.1f km/h, upright=%.3f" % [
		travelled, forward, _car.get_speed_kph(), upright,
	])
	if travelled < MIN_DRIVE_DISTANCE:
		_fail("throttle moved the car only %.2f m in %d frames" % [travelled, DRIVE_FRAMES])
	if forward < MIN_DRIVE_DISTANCE * 0.8:
		_fail("car did not drive along its nose (-Z): %.2f m" % forward)
	if upright < 0.9:
		_fail("car tipped while driving in a straight line (up.y = %.3f)" % upright)


func _check_stopped() -> void:
	var speed := _car.get_speed_kph()
	print("[veh] speed after handbrake: %.2f km/h" % speed)
	if speed > 3.0:
		_fail("handbrake left the car rolling at %.2f km/h" % speed)


## Facing -Z with +Y up, the driver's left is -X, and turning left is a
## positive yaw. Worth asserting rather than assuming: the engine's drive axis
## is already inverted relative to the node's forward (see ENGINE_FORCE_SIGN),
## so the steering sign could just as easily have been backwards.
func _check_steering() -> void:
	var forward := -_car.global_basis.z
	var yaw_delta := _steer_origin_forward.signed_angle_to(forward, Vector3.UP)
	print("[veh] steering left turned the nose %.1f degrees (forward.x %.2f -> %.2f)" % [
		rad_to_deg(yaw_delta), _steer_origin_forward.x, forward.x,
	])
	if absf(yaw_delta) < deg_to_rad(15.0):
		_fail("full left lock barely turned the car: %.1f degrees" % rad_to_deg(yaw_delta))
	elif yaw_delta < 0.0:
		_fail("pressing left steered the car right (%.1f degrees)" % rad_to_deg(yaw_delta))


func _make_floor() -> StaticBody3D:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 2.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	return floor_body


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[veh] FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[veh] ALL CHECKS PASSED")
		quit(0)
	else:
		print("[veh] %d CHECK(S) FAILED" % _failures.size())
		quit(1)
