extends Node
## Lightweight procedural animation for the generated PS2-style NPC body.

var _figure: Node3D
var _actor: Node3D
var _parts: Dictionary = {}
var _base_positions: Dictionary = {}
var _base_rotations: Dictionary = {}
var _previous_actor_position := Vector3.ZERO
var _smoothed_speed := 0.0
var _walk_cycle := 0.0
var _idle_time := 0.0
var _walk_blend := 0.0
var _pose := "stand"

# One full cycle contains a left and a right step. Advancing the cycle from
# distance travelled (instead of wall-clock time) keeps the feet matched to
# tweened NPC movement, including the acceleration and slowdown at each end.
const WALK_CYCLE_DISTANCE := 0.76
const FOOT_TRAVEL := 0.17
const FOOT_LIFT := 0.045


func _ready() -> void:
	_figure = get_parent() as Node3D
	_actor = _figure.get_parent() as Node3D
	_pose = str(_figure.get_meta("pose", "stand"))
	if _pose == "stand":
		_build_walk_rig()
	for part_name in [
		"Pelvis", "Torso", "ShirtHem", "ShoulderPivotL", "ElbowPivotL",
		"ShoulderPivotR", "ElbowPivotR", "HipPivotL", "KneePivotL",
		"HipPivotR", "KneePivotR", "FootL", "FootR"
	]:
		var part := _figure.find_child(part_name, true, false) as Node3D
		if part:
			_parts[part_name] = part
			_base_positions[part_name] = part.position
			_base_rotations[part_name] = part.rotation
	_previous_actor_position = _actor.global_position if _actor else Vector3.ZERO


func _process(delta: float) -> void:
	if _actor == null or delta <= 0.0:
		return
	var actor_position := _actor.global_position
	var horizontal_delta := actor_position - _previous_actor_position
	horizontal_delta.y = 0.0
	var travelled := horizontal_delta.length()
	var measured_speed := travelled / delta
	_previous_actor_position = actor_position
	_smoothed_speed = lerpf(_smoothed_speed, measured_speed, minf(delta * 8.0, 1.0))
	_idle_time += delta
	var moving_now := travelled > 0.00001
	var walking := _pose == "stand" and (moving_now or _smoothed_speed > 0.075)
	_walk_blend = move_toward(_walk_blend, 1.0 if walking else 0.0, delta * 10.0)
	if _pose == "stand" and moving_now:
		# Ignore teleport-sized changes while still matching ordinary patrol speed.
		var gait_distance := minf(travelled, 0.25)
		_walk_cycle = fmod(_walk_cycle + gait_distance / WALK_CYCLE_DISTANCE * TAU, TAU)
	_apply_pose()


func _apply_pose() -> void:
	var idle_breath := sin(_idle_time * 1.65)
	var left_step := _step_pose(_walk_cycle)
	var right_step := _step_pose(fmod(_walk_cycle + PI, TAU))
	var left_forward: float = left_step.x * _walk_blend
	var right_forward: float = right_step.x * _walk_blend
	var left_lift: float = left_step.y * _walk_blend
	var right_lift: float = right_step.y * _walk_blend
	var left_z: float = left_step.z * _walk_blend
	var right_z: float = right_step.z * _walk_blend
	var bounce := absf(sin(_walk_cycle)) * _walk_blend
	var idle_weight := 1.0 - _walk_blend

	# Keep the figure root and both planted feet locked to the ground. Body bounce is
	# applied only above the hips so the whole character never appears to float.
	_figure.position.y = 0.0
	var body_bob := idle_breath * 0.004 * idle_weight + bounce * 0.006
	var torso_twist := (left_forward - right_forward) * 0.018
	_pose_part("Pelvis", Vector3(0.0, -torso_twist * 0.45, 0.0), Vector3(0.0, body_bob * 0.35, 0.0))
	_pose_part("Torso", Vector3(0.0, torso_twist, -torso_twist * 0.35), Vector3(0.0, body_bob, 0.0))
	_pose_part("ShirtHem", Vector3(0.0, torso_twist * 0.7, -torso_twist * 0.25), Vector3(0.0, body_bob * 0.72, 0.0))

	# Each complete arm is parented to a shoulder pivot at runtime, so the sleeve,
	# forearm and hand stay connected throughout the counter-swing.
	var left_arm_angle := -left_forward * 0.22 + idle_breath * 0.012 * idle_weight
	var right_arm_angle := -right_forward * 0.22 - idle_breath * 0.012 * idle_weight
	_pose_part("ShoulderPivotL", Vector3(left_arm_angle, 0.0, 0.0), Vector3(0.0, body_bob, 0.0))
	_pose_part("ElbowPivotL", Vector3(maxf(0.0, -left_forward) * 0.10, 0.0, 0.0), Vector3.ZERO)
	_pose_part("ShoulderPivotR", Vector3(right_arm_angle, 0.0, 0.0), Vector3(0.0, body_bob, 0.0))
	_pose_part("ElbowPivotR", Vector3(maxf(0.0, -right_forward) * 0.10, 0.0, 0.0), Vector3.ZERO)

	# During stance the foot travels backward at almost the same rate that the
	# actor travels forward. Hip and knee pivots keep each leg connected; the shoe
	# cancels their combined pitch so its sole stays nearly parallel to the road.
	var left_hip_angle := left_forward * 0.22
	var right_hip_angle := right_forward * 0.22
	var left_knee_angle := -left_lift / FOOT_LIFT * 0.18
	var right_knee_angle := -right_lift / FOOT_LIFT * 0.18
	# The shoe center is slightly ahead of the ankle, so forward and backward hip
	# angles trace different-height arcs. This small fitted correction keeps both
	# contact points on the same ground plane.
	var left_ground_correction := -0.0275 * left_forward * left_forward - 0.0135 * left_forward
	var right_ground_correction := -0.0275 * right_forward * right_forward - 0.0135 * right_forward
	_pose_part("HipPivotL", Vector3(left_hip_angle, 0.0, 0.0), Vector3.ZERO)
	_pose_part("KneePivotL", Vector3(left_knee_angle, 0.0, 0.0), Vector3.ZERO)
	_pose_part("FootL", Vector3(-left_hip_angle - left_knee_angle, 0.0, 0.0), Vector3(0.0, left_lift * 0.65 + left_ground_correction, left_z * 0.35))
	_pose_part("HipPivotR", Vector3(right_hip_angle, 0.0, 0.0), Vector3.ZERO)
	_pose_part("KneePivotR", Vector3(right_knee_angle, 0.0, 0.0), Vector3.ZERO)
	_pose_part("FootR", Vector3(-right_hip_angle - right_knee_angle, 0.0, 0.0), Vector3(0.0, right_lift * 0.65 + right_ground_correction, right_z * 0.35))


func _step_pose(phase: float) -> Vector3:
	# x: forward amount, y: lift, z: local foot travel. Local -Z is the
	# generated figure's visual forward direction.
	var wrapped := fposmod(phase, TAU)
	if wrapped < PI:
		var swing_t := wrapped / PI
		var foot_z := lerpf(FOOT_TRAVEL, -FOOT_TRAVEL, swing_t)
		return Vector3(-foot_z / FOOT_TRAVEL, sin(swing_t * PI) * FOOT_LIFT, foot_z)
	var stance_t := (wrapped - PI) / PI
	var foot_z := lerpf(-FOOT_TRAVEL, FOOT_TRAVEL, stance_t)
	return Vector3(-foot_z / FOOT_TRAVEL, 0.0, foot_z)


func _build_walk_rig() -> void:
	_build_arm_rig("L")
	_build_arm_rig("R")
	_build_leg_rig("L")
	_build_leg_rig("R")


func _build_arm_rig(side: String) -> void:
	var upper := _figure.find_child("Arm%sUpper" % side, true, false) as MeshInstance3D
	var lower := _figure.find_child("Arm%sLower" % side, true, false) as MeshInstance3D
	var hand := _figure.find_child("Hand%s" % side, true, false) as Node3D
	if upper == null or lower == null or hand == null:
		return
	var upper_box := upper.mesh.get_aabb()
	var lower_box := lower.mesh.get_aabb()
	# The sleeve is a `_body_part()` frustum whose local +Y end meets the torso.
	# Pivot it from that upper end; using the lower AABB end makes the sleeve swing
	# around its cuff and visibly pull away from the shoulder.
	var shoulder_position := upper.position + upper.basis * Vector3(0.0, upper_box.end.y, 0.0)
	var elbow_position := lower.position + lower.basis * Vector3(0.0, lower_box.position.y, 0.0)
	var shoulder := _new_pivot("ShoulderPivot%s" % side, shoulder_position, _figure)
	var elbow := _new_pivot("ElbowPivot%s" % side, elbow_position - shoulder_position, shoulder)
	upper.reparent(shoulder, true)
	lower.reparent(elbow, true)
	hand.reparent(elbow, true)


func _build_leg_rig(side: String) -> void:
	var thigh := _figure.find_child("Leg%sThigh" % side, true, false) as MeshInstance3D
	var shin := _figure.find_child("Leg%sShin" % side, true, false) as MeshInstance3D
	var foot := _figure.find_child("Foot%s" % side, true, false) as Node3D
	if thigh == null or shin == null or foot == null:
		return
	var thigh_box := thigh.mesh.get_aabb()
	var hip_position := thigh.position + thigh.basis * Vector3(0.0, thigh_box.position.y, 0.0)
	var knee_position := thigh.position + thigh.basis * Vector3(0.0, thigh_box.end.y, 0.0)
	var hip := _new_pivot("HipPivot%s" % side, hip_position, _figure)
	var knee := _new_pivot("KneePivot%s" % side, knee_position - hip_position, hip)
	thigh.reparent(hip, true)
	shin.reparent(knee, true)
	foot.reparent(knee, true)


func _new_pivot(pivot_name: String, pivot_position: Vector3, parent: Node3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = pivot_position
	parent.add_child(pivot)
	return pivot


func _pose_part(part_name: String, rotation_offset: Vector3, position_offset: Vector3) -> void:
	if not _parts.has(part_name):
		return
	var part: Node3D = _parts[part_name]
	part.rotation = _base_rotations[part_name] + rotation_offset
	part.position = _base_positions[part_name] + position_offset
