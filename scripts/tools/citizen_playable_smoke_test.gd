extends SceneTree
## Guard: the citizen is a pickable, switchable, CUSTOMIZABLE player character.
##
##   Godot_v4.7-stable_win64.exe --headless --path . --script res://scripts/tools/citizen_playable_smoke_test.gd
##
## Modelled on police_playable_smoke_test.gd, plus the checks the wardrobe
## needs: part visibility actually changes, the rig stays human-sized whatever
## it is wearing, tinting one citizen does not tint the rest of the world, and
## a saved look survives a round trip through ConfigFile.
##
## Uses `_failures` + quit(1), never assert() -- PROJECT_STATUS.md records the
## hang that causes in a headless SceneTree.

const Appearance := preload("res://scripts/citizen_appearance.gd")
const Roster := preload("res://scripts/cblock_character_roster.gd")

var _failures: Array[String] = []
var _frames := 0
var _player: CharacterBody3D
var _stage := 0
var _height_by_look: Array[float] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


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

	# A floor, because _try_emote gates on is_on_floor(). Without it every emote
	# assertion below would pass vacuously by never starting one. Top face at
	# y=0; the capsule is centred on the body origin, so spawn just above it.
	var ground := StaticBody3D.new()
	ground.name = "TestGround"
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	ground_shape.shape = box
	ground_shape.position = Vector3(0, -0.5, 0)
	ground.add_child(ground_shape)
	world.add_child(ground)
	_player.position = Vector3(0, 0.95, 0)


func _rig() -> Node3D:
	var model_root := _player.get_node("ModelRoot") as Node3D
	if model_root.get_child_count() == 0:
		return null
	return model_root.get_child(0) as Node3D


## Measured from the BONES through the transform chain, never from the bind
## AABB -- the same reason police_playable_smoke_test.gd does it this way.
func _height() -> float:
	var skeleton := _rig().find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return -1.0
	var crown := -INF
	var sole := INF
	for bone_index in skeleton.get_bone_count():
		var y: float = skeleton.get_bone_global_rest(bone_index).origin.y
		crown = maxf(crown, y)
		sole = minf(sole, y)
	return (crown - sole) * skeleton.get_global_transform().basis.get_scale().y


func _visible_names() -> PackedStringArray:
	var out: PackedStringArray = []
	for node in _rig().find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).visible:
			out.append(node.name)
	out.sort()
	return out


func _check_manifest() -> void:
	var data := Appearance.manifest()
	_check(not data.is_empty(), "citizen_manifest.json failed to load")
	if data.is_empty():
		return

	var in_glb := {}
	for node in _rig().find_children("*", "MeshInstance3D", true, false):
		in_glb[node.name] = true

	# Both directions. A manifest entry with no mesh is a part the UI offers
	# and cannot show; a mesh with no manifest entry is a part nothing can ever
	# reach. Either one is silent without this check.
	var named := {}
	for name in data.get("body_meshes", []):
		named[name] = true
	for group in data.get("groups", {}):
		for option in data["groups"][group]:
			if String(option).ends_with("_None"):
				continue
			named[option] = true
			_check(in_glb.has(option), "manifest lists %s, not in citizen.glb" % option)
	for option in data.get("part_accent", {}):
		var accent: String = data["part_accent"][option]
		named[accent] = true
		_check(in_glb.has(accent), "manifest lists accent %s, not in citizen.glb" % accent)
	for name in in_glb:
		_check(named.has(name), "citizen.glb has %s, absent from the manifest" % name)


## Every surface must name a slot the appearance system knows.
##
## The gap this closes: Blender appends ".001" to a duplicate material name, so
## garments shipped as "Citizen_top.001" and friends. Those resolve to no slot,
## get no override, and render their authored default -- silently, and only for
## the garments that lost the name race. Nothing else here noticed, because the
## meshes were present, visible and correctly weighted; they just ignored every
## colour swatch.
func _check_slots() -> void:
	var slots := {}
	for slot in Appearance.manifest().get("slots", []):
		slots[slot] = true
	var seen := {}
	for node in _rig().find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(i)
			var name := "" if source == null else source.resource_name
			_check(name.begins_with("Citizen_"),
				"%s surface %d has material '%s', expected a Citizen_ slot"
					% [node.name, i, name])
			if not name.begins_with("Citizen_"):
				continue
			var slot := name.substr("Citizen_".length())
			_check(slots.has(slot),
				"%s surface %d resolves to slot '%s', which is not in the manifest "
					% [node.name, i, slot] + "-- it can never be tinted")
			seen[slot] = true
	print("slots in use: ", ", ".join(PackedStringArray(seen.keys())))


func _check_round_trip() -> void:
	var seeded := Appearance.random_from_seed(4242)
	_check(seeded.equals(Appearance.random_from_seed(4242)),
		"random_from_seed(4242) is not stable across calls")
	_check(not seeded.equals(Appearance.random_from_seed(4243)),
		"two different seeds produced an identical look")
	_check(Appearance.from_dict(seeded.to_dict()).equals(seeded),
		"to_dict/from_dict did not round-trip")

	var path := "user://citizen_round_trip_test.cfg"
	var config := ConfigFile.new()
	config.set_value("citizen", "appearance", seeded.to_dict())
	config.save(path)
	var reloaded := ConfigFile.new()
	reloaded.load(path)
	var restored = Appearance.from_dict(reloaded.get_value("citizen", "appearance", {}))
	_check(restored.equals(seeded), "appearance did not survive a ConfigFile round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The trap this exists for: GLB materials hang off the shared Mesh resource,
## so tinting through them recolours every citizen in the world and the player.
func _check_material_isolation() -> void:
	var packed := load("res://assets/characters/citizen/citizen.glb") as PackedScene
	_check(packed != null, "citizen.glb failed to load as a PackedScene")
	if packed == null:
		return
	var a := packed.instantiate() as Node3D
	var b := packed.instantiate() as Node3D
	root.add_child(a)
	root.add_child(b)

	var body_a := a.find_child("CitizenBody", true, false) as MeshInstance3D
	var shared_before: Color = body_a.mesh.surface_get_material(0).albedo_color

	Appearance.random_from_seed(7).apply(a)
	Appearance.random_from_seed(99).apply(b)

	var body_b := b.find_child("CitizenBody", true, false) as MeshInstance3D
	var mat_a := body_a.get_surface_override_material(0)
	var mat_b := body_b.get_surface_override_material(0)
	_check(mat_a != null and mat_b != null, "apply() did not set surface overrides")
	if mat_a != null and mat_b != null:
		_check(mat_a.albedo_color != mat_b.albedo_color,
			"two differently-seeded citizens got the same skin colour")
	_check(body_a.mesh.surface_get_material(0).albedo_color == shared_before,
		"apply() mutated the SHARED mesh material -- this recolours the whole crowd")

	a.queue_free()
	b.queue_free()


func _process(_delta: float) -> bool:
	_frames += 1
	if _stage == 0 and _frames < 4:
		return false
	match _stage:
		0:
			var ids: PackedStringArray = []
			for entry in Roster.list_characters():
				ids.append(entry.id)
			_check(ids.has("citizen"), "roster does not list the citizen")
			_player.switch_character("citizen")
			_stage = 1
			_frames = 0
		1:
			if _frames < 4:
				return false
			_check(_player.get_character_id() == "citizen",
				"character id is %s, expected citizen" % _player.get_character_id())
			_check(_rig() != null, "no rig under ModelRoot after switch")
			if _rig() == null:
				_finish()
				return true

			var skeleton := _rig().find_child("Skeleton3D", true, false) as Skeleton3D
			_check(skeleton != null, "citizen rig has no Skeleton3D")
			var height := _height()
			_check(height > 1.4 and height < 2.2,
				"citizen stands %.2f m as a playable character" % height)

			var anim := _rig().find_child("AnimationPlayer", true, false) as AnimationPlayer
			_check(anim != null, "no AnimationPlayer after switch")
			if anim != null:
				for clip in [
					"locomotion/idle", "locomotion/walk", "locomotion/sprint",
					"locomotion/jump",
					"combat/punch_left", "combat/punch_right", "combat/hit",
					"emote/flair", "emote/moonwalk",
				]:
					_check(anim.has_animation(clip), "missing clip %s" % clip)
				_check(anim.is_playing(), "no animation playing after switch")

			var emotes: Array = _player.get_emotes()
			_check(emotes.size() == 2,
				"get_emotes() reported %d, expected 2" % emotes.size())
			# The jump keeps the TIMED one-shot path -- asserted here so a
			# change to the emote hold cannot quietly take it with it.
			_check(_player.call("_play_oneshot", "locomotion/jump", 0.1),
				"locomotion/jump would not play")
			_check(_player.get("_oneshot_time_remaining") > 0.0,
				"locomotion/jump played but claimed no duration")

			_check_manifest()
			_check_slots()
			_check_round_trip()
			_check_material_isolation()

			# Switching a part must actually change what is visible, and must
			# not change how tall the citizen is.
			var bare := _visible_names()
			var dressed := Appearance.default()
			dressed.parts["top"] = "Top_Jacket"
			dressed.parts["hair"] = "Hair_Long"
			# A hat is the hard case for grounding: harvested head props stand
			# well above the crown, so if the height reference is the union of
			# visible meshes the citizen visibly shrinks when you put one on.
			if Appearance.manifest().get("groups", {}).has("hat"):
				dressed.parts["hat"] = "Hat_Beanie"
			_player.set_appearance(dressed)
			_stage = 2
			_frames = 0
			_height_by_look.append(height)
			_check(bare.size() > 0, "no meshes visible on a fresh citizen")
		2:
			if _frames < 3:
				return false
			var shown := _visible_names()
			_check(shown.has("Top_Jacket"), "Top_Jacket not visible after set_appearance")
			_check(not shown.has("Top_Tee"), "Top_Tee still visible after switching top")
			_check(shown.has("Accent_JacketTrim"),
				"the jacket's accent did not follow it")
			_height_by_look.append(_height())

			var spread: float = absf(_height_by_look[1] - _height_by_look[0])
			_check(spread < 0.01,
				("height moved %.3f m between outfits -- hidden meshes are"
					+ " polluting the grounding AABB") % spread)
			print("citizen: %.3f m, wearing %s" % [_height_by_look[1], ", ".join(shown)])
			_stage = 3
			_frames = 0
		3:
			# _try_emote refuses unless the body is grounded, so wait for the
			# capsule to settle onto the test floor. A frame budget rather than
			# a fixed count: headless idle frames run far faster than the 60 Hz
			# physics tick, so "wait N frames" is not N frames of physics.
			if not _player.is_on_floor():
				_check(_frames < 600, "player never settled on the test floor")
				if _frames < 600:
					return false
			_check_emotes()
			_finish()
			return true
	return false


## Emotes are HELD loops now, not timed one-shots. Driven through _try_emote
## directly: synthesised input does not reach the Player's _unhandled_input
## under a --script run, and the dispatch itself is three unchanged lines shared
## with the jump and attack.
func _check_emotes() -> void:
	var anim := _rig().find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim == null:
		_check(false, "no AnimationPlayer for the emote checks")
		return

	for clip in ["emote/flair", "emote/moonwalk"]:
		_check(anim.get_animation(clip).loop_mode == Animation.LOOP_LINEAR,
			"%s is not LOOP_LINEAR -- it will play once and stop" % clip)

	_player.call("_try_emote", 0)
	_check(_player.get("_emote_index") == 0,
		"_try_emote(0) did not take the body")
	_check(anim.current_animation == "emote/flair",
		"expected emote/flair, got '%s'" % anim.current_animation)
	# The invariant: a hold has NO timer. This replaces the old
	# "_oneshot_time_remaining > 0.0" assertion, which would still pass while
	# testing a path emotes no longer use.
	_check(_player.get("_oneshot_time_remaining") == 0.0,
		"a held emote must not carry a one-shot timer")

	# The whole point of the change: it must survive past one cycle. advance()
	# alone would not prove it -- the extra real frames are what give a wrong
	# _update_animation guard the chance to steal the body back.
	var length: float = anim.get_animation("emote/flair").length
	anim.advance(length + 0.25)
	_check(anim.current_animation == "emote/flair",
		"emote stopped after one cycle (%.2fs) -- got '%s'"
			% [length, anim.current_animation])
	_check(_player.get("_emote_index") == 0,
		"emote hold was released after one cycle")

	_player.call("_try_emote", 1)
	_check(_player.get("_emote_index") == 1, "the other key did not switch emote")
	_check(anim.current_animation == "emote/moonwalk",
		"expected emote/moonwalk after switching, got '%s'" % anim.current_animation)

	_player.call("_try_emote", 1)
	_check(_player.get("_emote_index") == -1, "the same key did not toggle the emote off")

	# The three cancels that would otherwise strand the rig.
	_player.call("_try_emote", 0)
	_player.call("_trigger_attack", "punch_left")
	_check(_player.get("_emote_index") == -1,
		"attacking did not cancel the emote -- the punch would freeze on its last frame")
	_check(_player.get("_oneshot_time_remaining") > 0.0,
		"the punch did not take the body after cancelling the emote")

	_player.call("_try_emote", 0)
	_player.set_controls_enabled(false)
	_check(_player.get("_emote_index") == -1, "a UI lock did not cancel the emote")
	_player.set_controls_enabled(true)

	_player.call("_try_emote", 0)
	_player.set_stowed(true)
	_check(_player.get("_emote_index") == -1, "getting into a vehicle did not cancel the emote")
	_player.set_stowed(false)
	print("emotes: loop + hold + toggle + switch + 3 cancels OK")


func _finish() -> void:
	if _failures.is_empty():
		print("CITIZEN_PLAYABLE_OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("CITIZEN_PLAYABLE_FAIL: %s" % failure)
		quit(1)
