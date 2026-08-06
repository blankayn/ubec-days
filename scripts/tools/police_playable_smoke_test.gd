extends SceneTree
## Guard: the police rig is a pickable, switchable CBlock player character.

var _failures: Array[String] = []
var _frames := 0
var _player: CharacterBody3D
var _stage := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _initialize() -> void:
	var packed := load("res://assets/npcs/police.glb") as PackedScene
	_check(packed != null, "police.glb failed to load")

	var world := Node3D.new()
	world.name = "TestWorld"
	root.add_child(world)

	# CameraRig is a sibling of Player, reached by ../ in the controller.
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
	_player.collision_layer = 2
	_player.collision_mask = 1
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	shape.shape = capsule
	_player.add_child(shape)
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	model_root.rotation.y = PI
	_player.add_child(model_root)
	_player.set_script(load("res://scripts/cblock_player.gd"))
	world.add_child(_player)


func _process(_delta: float) -> bool:
	_frames += 1
	if _stage == 0 and _frames < 4:
		return false
	match _stage:
		0:
			var roster := load("res://scripts/cblock_character_roster.gd")
			for entry in roster.list_characters():
				print("roster: %s - %s" % [entry.id, entry.display_name])
			_player.switch_character("police")
			_stage = 1
			_frames = 0
		1:
			if _frames < 4:
				return false
			_check(_player.get_character_id() == "police",
				"character id is %s, expected police" % _player.get_character_id())
			var model_root := _player.get_node("ModelRoot") as Node3D
			var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
			_check(skeleton != null, "police rig has no Skeleton3D")
			if skeleton != null:
				_check(skeleton.find_bone("mixamorig1_Hips") >= 0,
					"police rig missing mixamorig1_Hips")
				# The officer must arrive human-sized. `_scale_and_align_visual`
				# sizes him by measuring raw vertex arrays, so a rig exported at
				# centimetre scale or lying on its back gets measured across the
				# wrong axis and scaled by hundreds -- which is exactly how he
				# once came out 500x too big.
				var crown := -INF
				var sole := INF
				for bone_index in skeleton.get_bone_count():
					var y: float = skeleton.get_bone_global_rest(bone_index).origin.y
					crown = maxf(crown, y)
					sole = minf(sole, y)
				var height: float = (
					(crown - sole) * skeleton.get_global_transform().basis.get_scale().y
				)
				_check(height > 1.4 and height < 2.2,
					"police stands %.2f m as a playable character" % height)
			var anim_player := model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
			_check(anim_player != null, "no AnimationPlayer after switch")
			if anim_player != null:
				for clip in [
					"locomotion/idle", "locomotion/walk", "locomotion/sprint",
					"combat/punch_left", "combat/punch_right", "combat/hit",
				]:
					_check(anim_player.has_animation(clip), "missing clip %s" % clip)
				_check(anim_player.is_playing(), "no animation playing after switch")
				print("playing: %s (%.2fs)" % [
					anim_player.current_animation,
					anim_player.current_animation_length,
				])
			_finish()
			return true
	return false


func _finish() -> void:
	if _failures.is_empty():
		print("POLICE_PLAYABLE_OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("POLICE_PLAYABLE_FAIL: %s" % failure)
		quit(1)
