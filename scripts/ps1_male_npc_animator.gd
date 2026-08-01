extends Node
class_name Ps1MaleNpcAnimator
## Distance-driven procedural walk for the skinned PS1 male skeleton.
##
## The supplied hero.fbx is rigged but ships no animation clips, so this drives
## thigh / shin / arm bone poses from how far the prop root travels — the same
## gait idea as the LowPoly NpcAnimator.

const WALK_CYCLE_DISTANCE := 0.78
const HIP_SWING := 0.42
const KNEE_BEND := 0.55
const ARM_SWING := 0.38
const FOREARM_BEND := 0.18
const SPINE_SWAY := 0.04

var _actor: Node3D
var _skeleton: Skeleton3D
var _bone := {}
var _base_rot := {}
var _previous_actor_position := Vector3.ZERO
var _smoothed_speed := 0.0
var _walk_cycle := 0.0
var _walk_blend := 0.0
var _idle_time := 0.0
var _gait_sign := 1.0


func _ready() -> void:
	_actor = get_parent() as Node3D
	if _actor == null:
		return
	_skeleton = _actor.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton == null:
		push_warning("Ps1MaleNpcAnimator: Skeleton3D not found")
		return
	for bone_name in [
		"pelvis", "spine", "chest",
		"thigh_left", "shin.L", "foot_left",
		"thigh_right", "shin.R", "foot_right",
		"upper_arm_left", "forearm_left",
		"upper_arm_right", "forearm_right",
	]:
		var idx := _skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		_bone[bone_name] = idx
		_base_rot[bone_name] = _skeleton.get_bone_pose_rotation(idx)
	_previous_actor_position = _actor.global_position


func _process(delta: float) -> void:
	if _skeleton == null or _actor == null or delta <= 0.0:
		return
	var actor_position := _actor.global_position
	var horizontal_delta := actor_position - _previous_actor_position
	horizontal_delta.y = 0.0
	var travelled := horizontal_delta.length()
	_previous_actor_position = actor_position
	_smoothed_speed = lerpf(_smoothed_speed, travelled / delta, minf(delta * 8.0, 1.0))
	_idle_time += delta

	var moving_now := travelled > 0.00001
	var walking := moving_now or _smoothed_speed > 0.075
	_walk_blend = move_toward(_walk_blend, 1.0 if walking else 0.0, delta * 10.0)
	if moving_now:
		# Advance the cycle along the actor's facing axis so the feet never
		# run opposite a diagonal patrol or a return leg.
		var local_delta := _actor.global_transform.basis.inverse() * horizontal_delta
		var signed_travel := -local_delta.z
		if absf(signed_travel) > 0.00001:
			_gait_sign = signf(signed_travel)
		var gait_distance := minf(absf(signed_travel), 0.25)
		_walk_cycle = fmod(
			_walk_cycle + _gait_sign * gait_distance / WALK_CYCLE_DISTANCE * TAU,
			TAU
		)

	_apply_pose()


func _apply_pose() -> void:
	var left := _leg_amounts(_walk_cycle)
	var right := _leg_amounts(fmod(_walk_cycle + PI, TAU))
	var idle_breath := sin(_idle_time * 1.7) * (1.0 - _walk_blend)

	# Legs — local +X is the flexion axis for this Blender-exported Y-up bone chain.
	_set_rot("thigh_left", Vector3(left.x * HIP_SWING * _walk_blend, 0.0, 0.0))
	_set_rot("shin.L", Vector3(-left.y * KNEE_BEND * _walk_blend, 0.0, 0.0))
	_set_rot("thigh_right", Vector3(right.x * HIP_SWING * _walk_blend, 0.0, 0.0))
	_set_rot("shin.R", Vector3(-right.y * KNEE_BEND * _walk_blend, 0.0, 0.0))

	# Keep soles from tipping hard as the shin bends.
	_set_rot("foot_left", Vector3(left.y * 0.22 * _walk_blend, 0.0, 0.0))
	_set_rot("foot_right", Vector3(right.y * 0.22 * _walk_blend, 0.0, 0.0))

	# Arms counter-swing opposite the legs.
	_set_rot("upper_arm_left", Vector3(-left.x * ARM_SWING * _walk_blend + idle_breath * 0.03, 0.0, 0.0))
	_set_rot("forearm_left", Vector3(maxf(0.0, -left.x) * FOREARM_BEND * _walk_blend, 0.0, 0.0))
	_set_rot("upper_arm_right", Vector3(-right.x * ARM_SWING * _walk_blend - idle_breath * 0.03, 0.0, 0.0))
	_set_rot("forearm_right", Vector3(maxf(0.0, -right.x) * FOREARM_BEND * _walk_blend, 0.0, 0.0))

	var sway := (left.x - right.x) * SPINE_SWAY * _walk_blend
	var bob := absf(sin(_walk_cycle)) * 0.025 * _walk_blend + idle_breath * 0.012
	_set_rot("pelvis", Vector3(bob * 0.35, sway * 0.5, 0.0))
	_set_rot("spine", Vector3(bob, -sway, 0.0))
	_set_rot("chest", Vector3(bob * 0.6, sway * 0.8, 0.0))


func _leg_amounts(phase: float) -> Vector2:
	# x: hip forward(+)/back(-), y: knee bend amount (0..1, peaks mid-swing).
	var wrapped := fposmod(phase, TAU)
	if wrapped < PI:
		var swing_t := wrapped / PI
		# Swing: move from back contact to forward contact while lifting.
		var hip := lerpf(-1.0, 1.0, swing_t)
		var knee := sin(swing_t * PI)
		return Vector2(hip, knee)
	var stance_t := (wrapped - PI) / PI
	var hip := lerpf(1.0, -1.0, stance_t)
	return Vector2(hip, 0.0)


func _set_rot(bone_name: String, euler_offset: Vector3) -> void:
	if not _bone.has(bone_name):
		return
	var idx: int = _bone[bone_name]
	var base: Quaternion = _base_rot[bone_name]
	var offset := Quaternion(Vector3.RIGHT, euler_offset.x) \
		* Quaternion(Vector3.UP, euler_offset.y) \
		* Quaternion(Vector3.FORWARD, euler_offset.z)
	_skeleton.set_bone_pose_rotation(idx, base * offset)
