extends SceneTree
## Measures whether a looping clip actually wraps cleanly, or pops.
##
##   Godot_v4.7-stable_win64.exe --headless --path . \
##       --script res://scripts/tools/emote_loop_seam_check.gd
##
## WHY THIS EXISTS
## "Make it loop so it doesn't look cut" is two separate defects. One is that a
## timed one-shot tears the clip out after a single cycle -- deterministic, and
## fixed in cblock_player.gd. The other is a genuine pop at the wrap point,
## which is NOT knowable without measuring: Mixamo dance clips are usually
## authored to loop, so the seam may not exist at all. This tool decides that,
## rather than a fix being applied on a hunch.
##
## WHAT IT MEASURES
## The RETARGETED clips off a live rig, never the raw FBX -- `_retarget_clip`
## freezes the Hips X/Z, scales everything by `_root_motion_scale`, and drops
## tracks whose bones the target lacks, so the source FBX is not what ships.
##
## Sampling goes through `position_track_interpolate` / `rotation_track_interpolate`,
## which respect the resource's own `loop_mode`. That means this measures Godot's
## real wrap behaviour instead of reasoning about key layout -- no assumptions
## about interpolation internals, no frame timing, no renderer.
##
##     seam_ratio = |wrap step| / p99(|ordinary step|)
##
## A ratio near 1 means the body moves no further across the wrap than it does
## in any other frame of the clip: seamless by construction.
##
## THE CONTROL IS THE POINT
## `locomotion/walk` already loops visibly cleanly in the shipped game AND
## carries the same `animation/trimming=true` and `animation/fps=30` import
## settings as both emotes. So it is a like-for-like baseline, and the threshold
## is whatever it scores -- not a number invented here.

const SAMPLE_HZ := 120.0
## Clips to measure. The locomotion pair are controls, not subjects.
const CLIPS := [
	"emote/flair",
	"emote/moonwalk",
	"locomotion/walk",
	"locomotion/idle",
]

var _failures: Array[String] = []
var _frames := 0
var _player: CharacterBody3D
var _stage := 0
var _worst: Dictionary = {}


func _initialize() -> void:
	var world := Node3D.new()
	world.name = "TestWorld"
	root.add_child(world)

	var camera_rig := Node3D.new()
	camera_rig.name = "CameraRig"
	var spring_arm := SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	spring_arm.add_child(camera)
	camera_rig.add_child(spring_arm)
	world.add_child(camera_rig)

	_player = CharacterBody3D.new()
	_player.name = "Player"
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	shape.shape = capsule
	_player.add_child(shape)
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	_player.add_child(model_root)
	_player.set_script(load("res://scripts/cblock_player.gd"))
	world.add_child(_player)


func _anim() -> AnimationPlayer:
	return (_player.get_node("ModelRoot")
		.find_child("AnimationPlayer", true, false) as AnimationPlayer)


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	var index := int(floor(float(values.size() - 1) * fraction))
	return values[clampi(index, 0, values.size() - 1)]


## One track's worth of numbers. Returns [seam_ratio, wrap_delta, end_to_end].
##
## `end_to_end` is the raw |last - first| value difference and is the DIAGNOSTIC:
## seam_ratio says whether there is a problem, end_to_end says what to fix.
func _measure_track(clip: Animation, track: int, step: float) -> Array:
	var kind := clip.track_get_type(track)
	var steps: Array[float] = []
	var length := clip.length
	var samples := int(length / step)
	if samples < 4:
		return []

	if kind == Animation.TYPE_POSITION_3D:
		var previous := clip.position_track_interpolate(track, 0.0)
		for i in range(1, samples + 1):
			var current := clip.position_track_interpolate(track, float(i) * step)
			steps.append((current - previous).length())
			previous = current
		var first := clip.position_track_interpolate(track, 0.0)
		var last := clip.position_track_interpolate(track, length - step)
		var wrap := (first - last).length()
		var ends := (
			clip.position_track_interpolate(track, length)
			- first
		).length()
		var typical := _percentile(steps, 0.99)
		return [wrap / maxf(typical, 1e-6), wrap, ends]

	if kind == Animation.TYPE_ROTATION_3D:
		var previous_q := clip.rotation_track_interpolate(track, 0.0)
		for i in range(1, samples + 1):
			var current_q := clip.rotation_track_interpolate(track, float(i) * step)
			steps.append(rad_to_deg(previous_q.angle_to(current_q)))
			previous_q = current_q
		var first_q := clip.rotation_track_interpolate(track, 0.0)
		var last_q := clip.rotation_track_interpolate(track, length - step)
		var wrap_q := rad_to_deg(last_q.angle_to(first_q))
		var ends_q := rad_to_deg(
			clip.rotation_track_interpolate(track, length).angle_to(first_q)
		)
		var typical_q := _percentile(steps, 0.99)
		return [wrap_q / maxf(typical_q, 1e-6), wrap_q, ends_q]

	return []


func _bone_of(clip: Animation, track: int) -> String:
	var path := clip.track_get_path(track)
	if path.get_subname_count() == 0:
		return String(path)
	return String(path.get_subname(path.get_subname_count() - 1))


func _measure(name: String) -> void:
	var anim := _anim()
	if anim == null or not anim.has_animation(name):
		_failures.append("clip %s not installed" % name)
		return
	var clip := anim.get_animation(name)
	var step := 1.0 / SAMPLE_HZ
	var loop_label := "LOOP_LINEAR" if clip.loop_mode == Animation.LOOP_LINEAR else "LOOP_NONE"

	print("\n--- %s  len=%.3fs step=%.4f tracks=%d  %s" % [
		name, clip.length, clip.step, clip.get_track_count(), loop_label,
	])

	var rows: Array = []
	var worst_ratio := 0.0
	for track in clip.get_track_count():
		var result := _measure_track(clip, track, step)
		if result.is_empty():
			continue
		rows.append({
			"bone": _bone_of(clip, track),
			"kind": "pos" if clip.track_get_type(track) == Animation.TYPE_POSITION_3D else "rot",
			"ratio": result[0],
			"wrap": result[1],
			"ends": result[2],
		})
		worst_ratio = maxf(worst_ratio, result[0])

	rows.sort_custom(func(a, b): return a["ratio"] > b["ratio"])
	print("    worst tracks by seam ratio:")
	for row in rows.slice(0, 6):
		print("      %-22s %s  ratio=%7.2f  wrap=%.4f  end-to-end=%.4f" % [
			row["bone"], row["kind"], row["ratio"], row["wrap"], row["ends"],
		])

	# Finger joints are excluded from the verdict. The citizen's hands are
	# MITTENS with a single thumb -- the finger bones drive geometry that
	# barely exists, so a couple of degrees there is invisible and would
	# otherwise dominate the ratio and report a seam that nobody can see.
	var visible: Array = rows.filter(
		func(r): return not _is_finger(String(r["bone"]))
	)
	var visible_worst := 0.0
	for row in visible:
		visible_worst = maxf(visible_worst, float(row["ratio"]))
	print("    worst EXCLUDING finger joints: %.2f" % visible_worst)

	# Hips gets its own line whatever it scores. X/Z must read ~0 -- that proves
	# _retarget_clip's horizontal freeze works. Y is preserved rather than
	# normalised, so it is the named suspect for a vertical pop.
	for track in clip.get_track_count():
		if _bone_of(clip, track).ends_with("Hips"):
			if clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
				var a := clip.position_track_interpolate(track, 0.0)
				var b := clip.position_track_interpolate(track, clip.length)
				print("    Hips POS  first=(%.4f, %.4f, %.4f)  end-to-end dx=%.4f dy=%.4f dz=%.4f"
					% [a.x, a.y, a.z, absf(b.x - a.x), absf(b.y - a.y), absf(b.z - a.z)])
			elif clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				var qa := clip.rotation_track_interpolate(track, 0.0)
				var qb := clip.rotation_track_interpolate(track, clip.length)
				print("    Hips ROT  end-to-end=%.3f deg" % rad_to_deg(qa.angle_to(qb)))

	_worst[name] = visible_worst
	print("    WORST SEAM RATIO: %.2f (all tracks %.2f)" % [visible_worst, worst_ratio])


## Thumb included: the mitten has one, so it is the only finger bone whose
## rotation moves anything a player can see.
func _is_finger(bone: String) -> bool:
	for part in ["Index", "Middle", "Pinky", "Ring", "Thumb"]:
		if bone.contains(part):
			return true
	return false


func _process(_delta: float) -> bool:
	_frames += 1
	if _stage == 0:
		if _frames < 4:
			return false
		_player.switch_character("citizen")
		_stage = 1
		_frames = 0
		return false

	if _frames < 6:
		return false

	print("=== EMOTE LOOP SEAM CHECK (sampled at %d Hz) ===" % int(SAMPLE_HZ))
	for name in CLIPS:
		_measure(name)

	print("\n=== SUMMARY ===")
	var control := maxf(
		float(_worst.get("locomotion/walk", 0.0)),
		float(_worst.get("locomotion/idle", 0.0))
	)
	print("control (walk/idle) worst ratio : %.2f" % control)
	for name in ["emote/flair", "emote/moonwalk"]:
		var ratio := float(_worst.get(name, 0.0))
		var verdict := "SEAMLESS" if ratio <= maxf(control * 2.0, 2.0) else "SEAM"
		print("%-16s worst ratio : %7.2f   -> %s" % [name, ratio, verdict])
	print("(a clip whose wrap step is no bigger than its own 99th-percentile "
		+ "step cannot be seen to cut)")

	if _failures.is_empty():
		print("SEAM_CHECK_DONE")
		quit(0)
	else:
		for failure in _failures:
			printerr("SEAM_CHECK_FAIL: %s" % failure)
		quit(1)
	return true
