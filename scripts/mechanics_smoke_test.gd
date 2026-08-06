extends SceneTree

## Headless verification for the story-map wiring (main.tscn / world.gd).
##
##   Godot_v4.7-stable_win64.exe --headless --path . --script res://scripts/mechanics_smoke_test.gd
##
## This is the only regression guard on the 2700-line school_building.gd, which
## Phase 5 moves into the real Cebu map -- it has to stay green.
##
## It used to report with bare assert(). A failed GDScript assert() halts
## _initialize() *before* it can reach quit(), so a real regression hung the run
## at ~0% CPU forever instead of failing it. It had in fact been failing since
## the first commit -- DayLocker stood in the middle of UC's street entrance --
## and nobody saw it, because a hang reads as a slow test. It now reports with
## the _failures/_fail/_finish convention the other smoke tests use, so every
## broken check is listed in one run and the process exits non-zero.

const SchoolBuildingType = preload("res://scripts/school_building.gd")

const BOOTSTRAP_TIMEOUT_FRAMES := 600

var _failures: Array[String] = []


func _initialize() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if not _require(packed != null, "Main scene must load"):
		_finish()
		return
	var world := packed.instantiate()
	root.add_child(world)

	var bootstrap_frames := 0
	while world.get("_bootstrapping") == true and bootstrap_frames < BOOTSTRAP_TIMEOUT_FRAMES:
		await process_frame
		bootstrap_frames += 1
	_check(not world.get("_bootstrapping"),
		"World bootstrap must finish and release player control within %d frames" % BOOTSTRAP_TIMEOUT_FRAMES)

	var player := world.get_node_or_null("Player")
	if not _require(player != null, "Player must exist"):
		_finish()
		return
	_check(player.is_physics_processing(), "Player physics must be enabled after map construction")
	if _require(player.has_method("add_battery"), "Battery controller must be installed"):
		player.set_flashlight_unlocked(true)
		player.add_battery(0.0)
		_check(player.flashlight_unlocked, "Flashlight must unlock")

	# Horror is removed: nothing may re-introduce a stalker, a hiding spot or
	# the barricade chase the creature used to drive.
	_check(not player.has_method("enter_hiding"), "Hiding controller must stay removed")
	_check(world.get_tree().get_first_node_in_group("scare_manager") == null, "Scare manager must stay removed")
	_check(world.get_node_or_null("DeskHideSpot") == null, "Hide spots must stay removed")
	_check(world.get_node_or_null("ClassroomDoorBarricade") == null, "Barricadable door must stay removed")
	_check(world.get_node_or_null("VHSSystem") == null, "VHS system must stay removed")

	_check(world.get_node_or_null("PhoneUI") != null, "Phone UI must be created")
	_check(world.get_node_or_null("FacultyDoorLocked") != null, "Key-locked door must be placed")
	_check(world.get_node_or_null("Battery01") != null, "Battery pickup must be placed")

	# Structural regression checks: closed shells and deliberate routes must
	# survive future map/layout edits.
	var school := world.get_node_or_null("UCSchoolBuilding")
	var mall := world.get_node_or_null("GaisanoCountryMall")
	var bridge := world.get_node_or_null("CoveredBaniladPedestrianBridge")

	await physics_frame

	if _require(school != null, "School building must exist"):
		_check_school_shell(school)
	if _require(mall != null, "Mall building must exist"):
		_check_mall_shell(mall)
	if _require(bridge != null, "Pedestrian bridge must exist"):
		_check_bridge(bridge)

	_check(world.get_node_or_null("CampLapuLapuRoadMesh") != null,
		"Camp Lapu-Lapu road surface must continue north through the mall")

	# The three routes a player has to be able to walk. The first of these is
	# what DayLocker used to block.
	_check(_route_is_clear(world, player, Vector3(12.0, 1.2, 18.0), Vector3(12.0, 1.2, 25.5)),
		"UC's left-side street entrance must stay passable")
	_check(_route_is_clear(world, player, Vector3(4.0, 1.2, -34.0), Vector3(4.0, 1.2, -42.0)),
		"Gaisano's central entrance must stay passable")
	_check(_route_is_clear(world, player, Vector3(20.0, 1.2, -34.0), Vector3(20.0, 1.2, -68.0)),
		"Camp Lapu-Lapu Road must pass through both mall shell openings")

	if school != null:
		_check_school_levels(world, player, school)
		_check_school_stairs(world, player, school)
	if mall != null:
		_check_mall_structure(world, player, mall)
	if bridge != null:
		_check_bridge_support(world, player, bridge)

	# Optimized context buildings still read and collide as closed masses.
	_check(_has_collision(world.get_node_or_null("HouseBody_0")),
		"Foreground house scenery must be a closed collision mass")
	_check(_has_collision(world.get_node_or_null("EastBlock")),
		"Foreground commercial scenery must be a closed collision mass")

	_check_keyed_door(world, player)
	_check_phone(world)

	_finish()


func _check_school_shell(school: Node3D) -> void:
	_check(school.get_node_or_null("SchoolBackWall") != null, "School exterior shell must exist")
	_check(school.get_node_or_null("GroundFrontLeft") != null and school.get_node_or_null("GroundFrontRight") != null,
		"School entrance wings must be sealed")
	_check(school.get_node_or_null("ModernCurveGlass_F02_B01") != null,
		"UC street facade must use the joined modern curved skin")
	_check(_has_collision(school.get_node_or_null("ModernCurveGlass_F02_B01")),
		"Visible UC glazing must be collision-backed")
	_check(_has_collision(school.get_node_or_null("ModernEndTowerL")),
		"UC end return must be a closed collision-backed mass")
	_check(is_equal_approx(school.rotation.y, PI), "UC must remain south of Gov. M. Cuenco")


func _check_mall_shell(mall: Node3D) -> void:
	_check(mall.get_node_or_null("MallWestArcadeWingRoof") != null, "West mall arcade wing must close at the roof")
	_check(mall.get_node_or_null("MallEastArcadeWingRoof") != null, "East mall arcade wing must close at the roof")
	_check(_has_collision(mall.get_node_or_null("MallWestArcadeWingOuterWall")),
		"West arcade facade must be collision-backed")
	_check(_has_collision(mall.get_node_or_null("MallEastArcadeWingOuterWall")),
		"East arcade facade must be collision-backed")
	_check(mall.get_node_or_null("CampPortalArch_06Mesh") != null, "Camp Lapu-Lapu connector arch must exist")
	_check(mall.get_node_or_null("FacadeGroundCampWest") != null and mall.get_node_or_null("FacadeGroundMiddle") != null,
		"Road portal must be bounded by collision-backed facade walls")
	_check(_has_collision(mall.get_node_or_null("FacadeGroundCampWest")) and _has_collision(mall.get_node_or_null("FacadeGroundMiddle")),
		"Portal jamb walls must retain collision")
	_check(mall.get_node_or_null("CampRearPortalTop") != null,
		"Camp Lapu-Lapu passage must remain open through the rear shell")
	_check(is_equal_approx(mall.rotation.y, PI), "Gaisano must remain north of Gov. M. Cuenco")


func _check_bridge(bridge: Node3D) -> void:
	_check(bridge.get_node_or_null("BridgeContinuousWalkSurface") != null,
		"Bridge must retain one continuous walk surface")
	_check(is_equal_approx(bridge.rotation.y, PI), "Pedestrian bridge must remain on the west side")


func _check_school_levels(world: Node3D, player: CollisionObject3D, school: Node3D) -> void:
	# Ten playable levels: Ground, Mezzanine, 2F-8F and the ninth roof deck.
	# Each must retain one supported, obstruction-free ring corridor.
	_check(SchoolBuildingType.LEVEL_COUNT == 10, "UC must expose ten playable levels")
	_check(_has_collision(school.get_node_or_null("FloorSlab_1")), "UC ground slab must retain collision")
	for level in range(1, SchoolBuildingType.LEVEL_COUNT):
		for slab_prefix in ["FloorSlabSouth_", "FloorSlabNorth_", "FloorSlabEast_"]:
			var slab := school.get_node_or_null("%s%02d" % [slab_prefix, level + 1])
			_check(slab != null and _has_collision(slab),
				"UC level %d is missing collision-backed %s" % [level, slab_prefix])
	for level in range(SchoolBuildingType.LEVEL_COUNT):
		var floor_y: float = SchoolBuildingType.level_y(level)
		_check(_has_support_below(world, player, Vector3(0.0, floor_y + 0.9, 33.8), 1.5),
			"UC level %d south corridor has no supporting slab" % level)
		_check(_route_is_clear(world, player, Vector3(-8.0, floor_y + 1.1, 33.8), Vector3(8.0, floor_y + 1.1, 33.8)),
			"UC level %d south corridor is obstructed" % level)
		_check(_has_support_below(world, player, Vector3(0.0, floor_y + 0.9, 49.2), 1.5),
			"UC level %d north corridor has no supporting slab" % level)
		_check(school.get_node_or_null("ElevatorCall_L%02d" % (level + 1)) != null,
			"UC level %d is missing its elevator call button" % level)
		var landing: Vector3 = SchoolBuildingType.elevator_landing_local(level)
		_check(_has_support_below(world, player, Vector3(-landing.x, landing.y, -landing.z), 2.0),
			"UC level %d elevator landing is unsupported" % level)

	# The mezzanine must stay a partial floor wrapped around the lobby void.
	_check(school.get_node_or_null("FloorSlabSouthWest_02") != null,
		"Mezzanine must wrap the lobby void on the west side")
	_check(school.get_node_or_null("FloorSlabSouthEast_02") != null,
		"Mezzanine must wrap the lobby void on the east side")
	_check(school.get_node_or_null("MezzVoidRailBackBarrier") != null, "Mezzanine lobby void must be guarded")
	# The ninth level is an open deck: only its back-wing labs are roofed.
	_check(school.get_node_or_null("RoofNorth") != null, "Roof-deck labs must be covered")
	_check(school.get_node_or_null("RoofSouth") == null, "Ninth level must stay an open deck")
	_check(_has_collision(school.get_node_or_null("DeckParapetFront")),
		"Roof deck must be edged by a solid parapet")


func _check_school_stairs(world: Node3D, player: CollisionObject3D, school: Node3D) -> void:
	var stair_surface := school.get_node_or_null("StairWalkSurface")
	_check(stair_surface != null and _has_collision(stair_surface),
		"UC stairs must use one continuous collision surface")
	# Storey heights vary, so each switchback is probed at its own mid-flight height.
	for transition in range(SchoolBuildingType.LEVEL_COUNT - 1):
		var lower_y: float = SchoolBuildingType.level_y(transition)
		var upper_y: float = SchoolBuildingType.level_y(transition + 1)
		var middle_y := (lower_y + upper_y) * 0.5
		_check(_has_support_below(world, player, Vector3(22.75, (lower_y + middle_y) * 0.5 + 0.9, 42.2), 1.8),
			"UC stair A transition %d has a collision gap" % (transition + 1))
		_check(_has_support_below(world, player, Vector3(19.8, (middle_y + upper_y) * 0.5 + 0.9, 42.2), 1.8),
			"UC stair B transition %d has a collision gap" % (transition + 1))


func _check_mall_structure(world: Node3D, player: CollisionObject3D, mall: Node3D) -> void:
	for mall_part in ["MallGroundSlab", "MallLeftWall", "MallRightWall", "MallRoof", "UpperSlabLeft", "UpperSlabRight", "UpperSlabFront", "UpperSlabBack"]:
		var part := mall.get_node_or_null(mall_part)
		_check(part != null and _has_collision(part), "Mall structural part %s must retain collision" % mall_part)
	_check(_has_support_below(world, player, Vector3(-13.5, 5.1, -51.0), 1.5),
		"Mall upper gallery must retain a supported floor")


func _check_bridge_support(world: Node3D, player: CollisionObject3D, bridge: Node3D) -> void:
	# One concave bridge surface must support both ramps and the level deck.
	_check(_has_collision(bridge.get_node_or_null("BridgeContinuousWalkSurface")),
		"Bridge walk surface must own collision")
	_check(_has_support_below(world, player, Vector3(-38.0, 4.7, 10.25), 2.2), "South bridge ramp must be supported")
	_check(_has_support_below(world, player, Vector3(-38.0, 8.0, -7.0), 1.5), "Bridge deck must be supported")
	_check(_has_support_below(world, player, Vector3(-38.0, 4.7, -24.0), 2.2), "North bridge ramp must be supported")


func _check_keyed_door(world: Node3D, player: CollisionObject3D) -> void:
	var door = world.get_node_or_null("FacultyDoorLocked")
	if door == null:
		return
	# Chapter 1 is the daytime errand run: world.gd calls set_chapter_access(false)
	# on every survival door during bootstrap, which deliberately opens the ones
	# configured LOCKED. Doors only matter on the night return in Chapter 2.
	#
	# The original test asserted LOCKED right here and would have failed -- it
	# just never got this far, because the assert() above it hung the run first.
	_check(door.door_state == door.DoorState.UNLOCKED,
		"Chapter 1 (day) must leave the keyed faculty door open")

	# Now the half that actually exercises the key.
	door.set_chapter_access(true)
	_check(door.door_state == door.DoorState.LOCKED,
		"Chapter 2 (night) must re-lock the keyed faculty door")
	door.interact(player)
	_check(door.door_state == door.DoorState.LOCKED, "Keyed door must stay locked without its key")
	player.add_key(&"door_key_5f")
	door.interact(player)
	_check(door.door_state == door.DoorState.UNLOCKED, "Keyed door must unlock once the key is held")


func _check_phone(world: Node3D) -> void:
	var phone = world.get_node_or_null("PhoneUI")
	if phone == null:
		return
	phone.receive_sms("Test", "The inbox is connected.")
	phone.open()
	_check(phone._overlay.visible, "Phone UI must open")
	phone.close()


func _has_collision(node: Node) -> bool:
	if not node is CollisionObject3D:
		return false
	return node.find_children("*", "CollisionShape3D", true, false).size() > 0


func _route_is_clear(world: Node3D, player: CollisionObject3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		printerr("[mechanics] blocked route %s -> %s by %s" % [from, to, hit.get("collider")])
	return hit.is_empty()


func _has_support_below(world: Node3D, player: CollisionObject3D, from: Vector3, depth: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3(0.0, depth, 0.0), 1)
	query.exclude = [player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		printerr("[mechanics] no support below %s within %.2f m" % [from, depth])
	return not hit.is_empty()


func _require(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[mechanics] FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("MECHANICS_SMOKE_TEST_OK")
		quit(0)
	else:
		print("MECHANICS_SMOKE_TEST_FAIL: %d check(s) failed" % _failures.size())
		for message in _failures:
			print("  - %s" % message)
		quit(1)
