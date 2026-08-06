extends SceneTree

## Story-map guard for main.tscn: the horror systems must stay deleted, the
## systems that survived them must still work, and the three named NPCs must
## stay in the world at night.
##
## Collects failures and quits non-zero rather than using assert(), which halts
## _initialize() before its quit() and leaves a headless run hanging forever.

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _initialize() -> void:
	var packed := load("res://main.tscn") as PackedScene
	var world := packed.instantiate()
	root.add_child(world)
	var frames := 0
	while world.get("_bootstrapping") == true and frames < 900:
		await process_frame
		frames += 1
	_check(not world.get("_bootstrapping"), "world bootstrap never finished")

	var player := world.get_node_or_null("Player")
	_check(player != null, "player missing")

	# --- Horror must be gone ------------------------------------------------
	_check(get_first_node_in_group("scare_manager") == null, "scare_manager group still populated")
	_check(world.get_node_or_null("ScareManager") == null, "ScareManager node still built")
	_check(world.get_node_or_null("VHSSystem") == null, "VHSSystem still built")
	_check(world.get_node_or_null("Caretaker") == null, "Caretaker scare target still built")
	_check(world.get_node_or_null("ClassroomDoorBarricade") == null, "barricade door still placed")
	for spot in ["DeskHideSpot", "ClosetHideSpot", "StallHideSpot"]:
		_check(world.get_node_or_null(spot) == null, "%s still placed" % spot)
	for tape in ["Vhs1", "Vhs2", "Vhs3", "Vhs4", "Vhs5", "Vhs6", "VhsTv"]:
		_check(world.get_node_or_null(tape) == null, "%s still placed" % tape)
	_check(not player.has_method("enter_hiding"), "player still has enter_hiding")
	_check(not player.has_signal("noise_emitted"), "player still emits noise")

	var story := world.get_node_or_null("StoryManager")
	_check(story != null, "StoryManager missing")
	if story != null:
		_check(not ("is_horror_mode" in story), "story manager still has is_horror_mode")
		_check(not ("scare_manager" in story), "story manager still wired to scare_manager")
		_check(not ("vhs_system" in story), "story manager still wired to vhs_system")
		_check(story.get_chapter_title() == "CHAPTER 1 — DAY ERRAND", "unexpected ch1 title: %s" % story.get_chapter_title())
		_check(not story.get_objective_text().is_empty(), "objective text is empty")

	# --- Survivors ----------------------------------------------------------
	_check(world.get_node_or_null("PhoneUI") != null, "PhoneUI missing")
	_check(player.has_method("add_battery"), "battery controller missing")
	_check(world.get_node_or_null("Battery01") != null, "battery pickup missing")

	var door = world.get_node_or_null("FacultyDoorLocked")
	_check(door != null, "keyed faculty door missing")
	if door != null:
		# Chapter 1 is daytime and deliberately unlocks keyed doors; the lock
		# only applies from the night chapters on.
		door.set_chapter_access(true)
		door.interact(player)
		_check(door.door_state == door.DoorState.LOCKED, "keyed door opened without its key")
		player.add_key(&"door_key_5f")
		door.interact(player)
		_check(door.door_state == door.DoorState.UNLOCKED, "keyed door did not unlock with its key")

	var phone = world.get_node_or_null("PhoneUI")
	if phone != null:
		phone.receive_sms("Test", "The inbox is connected.")
		phone.open()
		_check(phone._overlay.visible, "phone UI did not open")
		phone.close()

	# --- Reversed decision: named NPCs survive the night --------------------
	# Each prop renames itself in build(): EdwardNpc -> Edward, and so on.
	var named := ["Edward", "Mulet", "Jholo"]
	for npc_name in named:
		_check(world.get_node_or_null(npc_name) != null, "%s did not spawn" % npc_name)
	world.call("_apply_night_lighting")
	await process_frame
	for npc_name in named:
		var npc := world.get_node_or_null(npc_name) as Node3D
		if npc != null:
			_check(npc.visible, "%s despawned at night" % npc_name)
	# Traffic is still day-only, so the night switch must still be doing work.
	var traffic := world.get_node_or_null("RoadTraffic_00") as Node3D
	_check(traffic != null and not traffic.visible, "day/night switching stopped working on traffic")
	world.call("_apply_day_lighting")
	await process_frame
	for npc_name in named:
		var npc2 := world.get_node_or_null(npc_name) as Node3D
		if npc2 != null:
			_check(npc2.visible, "%s hidden in day" % npc_name)

	if _failures.is_empty():
		print("STORY_MAP_SMOKE_TEST_PASS")
		quit(0)
	else:
		for failure in _failures:
			print("STORY_MAP_SMOKE_TEST_FAIL: " + failure)
		quit(1)
