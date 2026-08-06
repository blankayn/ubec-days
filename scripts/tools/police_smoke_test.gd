extends SceneTree

func _init() -> void:
	var packed := load("res://assets/npcs/police.glb") as PackedScene
	assert(packed != null, "police.glb failed to load")
	var model := packed.instantiate() as Node3D
	assert(model != null, "police.glb instantiate failed")
	root.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(player != null, "police.glb has no AnimationPlayer")
	var names := player.get_animation_list()
	print("GLB animations: ", names)
	assert(names.size() > 0, "police.glb has no animations")
	for name in names:
		var anim: Animation = player.get_animation(name)
		assert(anim.length > 0.0, "animation %s is empty" % name)
		var tracks := anim.get_track_count()
		assert(tracks >= 19, "animation %s has %d tracks, expected >= 19" % [name, tracks])
		print("  %s: %.2fs, %d tracks" % [name, anim.length, tracks])
	var prop := PoliceNpcProp.new()
	root.add_child(prop)
	prop.target_height = 1.8
	prop.build()
	var prop_player := prop.get_node("AnimationPlayer") as AnimationPlayer
	assert(prop_player.has_animation("locomotion/idle"), "prop missing locomotion/idle")
	assert(prop_player.has_animation("locomotion/walk"), "prop missing locomotion/walk")
	assert(prop_player.is_playing(), "idle is not playing")
	print("PoliceNpcProp idle length: %.2fs" % prop_player.get_animation("locomotion/idle").length)
	print("POLICE_OK")
	quit(0)
