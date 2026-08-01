extends SceneTree

## Lightweight runtime verification for the survival-mechanics wiring.

const SchoolBuildingType = preload("res://scripts/school_building.gd")

func _initialize() -> void:
	var packed := load("res://main.tscn") as PackedScene
	assert(packed != null, "Main scene must load")
	var world := packed.instantiate()
	root.add_child(world)
	var bootstrap_frames := 0
	while world.get("_bootstrapping") == true and bootstrap_frames < 600:
		await process_frame
		bootstrap_frames += 1
	assert(not world.get("_bootstrapping"), "World bootstrap must finish and release player control")

	var player := world.get_node_or_null("Player")
	assert(player != null, "Player must exist")
	assert(player.is_physics_processing(), "Player physics must be enabled after map construction")
	assert(player.has_method("add_battery"), "Battery controller must be installed")
	assert(player.has_method("enter_hiding"), "Hiding controller must be installed")
	player.set_flashlight_unlocked(true)
	player.add_battery(0.0)
	assert(player.flashlight_unlocked, "Flashlight must unlock")

	assert(world.get_node_or_null("PhoneUI") != null, "Phone UI must be created")
	assert(world.get_node_or_null("VHSSystem") != null, "VHS system must be created")
	assert(world.get_node_or_null("HUD/Root/ScreenFilter") == null, "Expensive full-screen VHS shader must stay removed")
	assert(world.get_node_or_null("ClassroomDoorBarricade") != null, "Barricadable door must be placed")
	assert(world.get_node_or_null("DeskHideSpot") != null, "Hide spot must be placed")
	assert(world.get_node_or_null("Battery01") != null, "Battery pickup must be placed")
	assert(world.get_node_or_null("Vhs1") != null, "VHS tape must be placed")

	# Structural regression checks: closed shells and deliberate routes must
	# survive future map/layout edits.
	var school := world.get_node_or_null("UCSchoolBuilding")
	var mall := world.get_node_or_null("GaisanoCountryMall")
	var bridge := world.get_node_or_null("CoveredBaniladPedestrianBridge")
	assert(school != null and school.get_node_or_null("SchoolBackWall") != null, "School exterior shell must exist")
	assert(school.get_node_or_null("GroundFrontLeft") != null and school.get_node_or_null("GroundFrontRight") != null, "School entrance wings must be sealed")
	assert(school.get_node_or_null("ModernCurveGlass_F02_B01") != null, "UC street facade must use the joined modern curved skin")
	assert(_has_collision(school.get_node("ModernCurveGlass_F02_B01")), "Visible UC glazing must be collision-backed")
	assert(_has_collision(school.get_node("ModernEndTowerL")), "UC end return must be a closed collision-backed mass")
	assert(is_equal_approx(school.rotation.y, PI), "UC must remain south of Gov. M. Cuenco")
	assert(mall != null and mall.get_node_or_null("MallWestArcadeWingRoof") != null, "West mall arcade wing must close at the roof")
	assert(mall.get_node_or_null("MallEastArcadeWingRoof") != null, "East mall arcade wing must close at the roof")
	assert(_has_collision(mall.get_node("MallWestArcadeWingOuterWall")), "West arcade facade must be collision-backed")
	assert(_has_collision(mall.get_node("MallEastArcadeWingOuterWall")), "East arcade facade must be collision-backed")
	assert(mall.get_node_or_null("CampPortalArch_06Mesh") != null, "Camp Lapu-Lapu connector arch must exist")
	assert(mall.get_node_or_null("FacadeGroundCampWest") != null and mall.get_node_or_null("FacadeGroundMiddle") != null, "Road portal must be bounded by collision-backed facade walls")
	assert(_has_collision(mall.get_node("FacadeGroundCampWest")) and _has_collision(mall.get_node("FacadeGroundMiddle")), "Portal jamb walls must retain collision")
	assert(mall.get_node_or_null("CampRearPortalTop") != null, "Camp Lapu-Lapu passage must remain open through the rear shell")
	assert(is_equal_approx(mall.rotation.y, PI), "Gaisano must remain north of Gov. M. Cuenco")
	assert(bridge != null and bridge.get_node_or_null("BridgeContinuousWalkSurface") != null, "Bridge must retain one continuous walk surface")
	assert(is_equal_approx(bridge.rotation.y, PI), "Pedestrian bridge must remain on the west side")
	assert(world.get_node_or_null("CampLapuLapuRoadMesh") != null, "Camp Lapu-Lapu road surface must continue north through the mall")
	await physics_frame
	assert(_route_is_clear(world, player, Vector3(12.0, 1.2, 18.0), Vector3(12.0, 1.2, 25.5)), "UC's left-side street entrance must stay passable")
	assert(_route_is_clear(world, player, Vector3(4.0, 1.2, -34.0), Vector3(4.0, 1.2, -42.0)), "Gaisano's central entrance must stay passable")
	assert(_route_is_clear(world, player, Vector3(20.0, 1.2, -34.0), Vector3(20.0, 1.2, -68.0)), "Camp Lapu-Lapu Road must pass through both mall shell openings")

	# Ten playable levels: Ground, Mezzanine, 2F-8F and the ninth roof deck.
	# Each must retain one supported, obstruction-free ring corridor.
	assert(SchoolBuildingType.LEVEL_COUNT == 10, "UC must expose ten playable levels")
	assert(_has_collision(school.get_node("FloorSlab_1")), "UC ground slab must retain collision")
	for level in range(1, SchoolBuildingType.LEVEL_COUNT):
		for slab_prefix in ["FloorSlabSouth_", "FloorSlabNorth_", "FloorSlabEast_"]:
			var slab := school.get_node_or_null("%s%02d" % [slab_prefix, level + 1])
			assert(slab != null and _has_collision(slab), "UC level %d is missing collision-backed %s" % [level, slab_prefix])
	for level in range(SchoolBuildingType.LEVEL_COUNT):
		var floor_y: float = SchoolBuildingType.level_y(level)
		assert(_has_support_below(world, player, Vector3(0.0, floor_y + 0.9, 33.8), 1.5), "UC level %d south corridor has no supporting slab" % level)
		assert(_route_is_clear(world, player, Vector3(-8.0, floor_y + 1.1, 33.8), Vector3(8.0, floor_y + 1.1, 33.8)), "UC level %d south corridor is obstructed" % level)
		assert(_has_support_below(world, player, Vector3(0.0, floor_y + 0.9, 49.2), 1.5), "UC level %d north corridor has no supporting slab" % level)
		var call_button := school.get_node_or_null("ElevatorCall_L%02d" % (level + 1))
		assert(call_button != null, "UC level %d is missing its elevator call button" % level)
		var landing: Vector3 = SchoolBuildingType.elevator_landing_local(level)
		assert(_has_support_below(world, player, Vector3(-landing.x, landing.y, -landing.z), 2.0), "UC level %d elevator landing is unsupported" % level)

	# The mezzanine must stay a partial floor wrapped around the lobby void.
	assert(school.get_node_or_null("FloorSlabSouthWest_02") != null, "Mezzanine must wrap the lobby void on the west side")
	assert(school.get_node_or_null("FloorSlabSouthEast_02") != null, "Mezzanine must wrap the lobby void on the east side")
	assert(school.get_node_or_null("MezzVoidRailBackBarrier") != null, "Mezzanine lobby void must be guarded")
	# The ninth level is an open deck: only its back-wing labs are roofed.
	assert(school.get_node_or_null("RoofNorth") != null, "Roof-deck labs must be covered")
	assert(school.get_node_or_null("RoofSouth") == null, "Ninth level must stay an open deck")
	assert(_has_collision(school.get_node("DeckParapetFront")), "Roof deck must be edged by a solid parapet")

	var stair_surface := school.get_node_or_null("StairWalkSurface")
	assert(stair_surface != null and _has_collision(stair_surface), "UC stairs must use one continuous collision surface")
	# Storey heights vary, so each switchback is probed at its own mid-flight height.
	for transition in range(SchoolBuildingType.LEVEL_COUNT - 1):
		var lower_y: float = SchoolBuildingType.level_y(transition)
		var upper_y: float = SchoolBuildingType.level_y(transition + 1)
		var middle_y := (lower_y + upper_y) * 0.5
		assert(_has_support_below(world, player, Vector3(22.75, (lower_y + middle_y) * 0.5 + 0.9, 42.2), 1.8), "UC stair A transition %d has a collision gap" % (transition + 1))
		assert(_has_support_below(world, player, Vector3(19.8, (middle_y + upper_y) * 0.5 + 0.9, 42.2), 1.8), "UC stair B transition %d has a collision gap" % (transition + 1))

	for mall_part in ["MallGroundSlab", "MallLeftWall", "MallRightWall", "MallRoof", "UpperSlabLeft", "UpperSlabRight", "UpperSlabFront", "UpperSlabBack"]:
		var part := mall.get_node_or_null(mall_part)
		assert(part != null and _has_collision(part), "Mall structural part %s must retain collision" % mall_part)
	assert(_has_support_below(world, player, Vector3(-13.5, 5.1, -51.0), 1.5), "Mall upper gallery must retain a supported floor")

	# One concave bridge surface must support both ramps and the level deck.
	assert(_has_collision(bridge.get_node("BridgeContinuousWalkSurface")), "Bridge walk surface must own collision")
	assert(_has_support_below(world, player, Vector3(-38.0, 4.7, 10.25), 2.2), "South bridge ramp must be supported")
	assert(_has_support_below(world, player, Vector3(-38.0, 8.0, -7.0), 1.5), "Bridge deck must be supported")
	assert(_has_support_below(world, player, Vector3(-38.0, 4.7, -24.0), 2.2), "North bridge ramp must be supported")

	# Optimized context buildings still read and collide as closed masses.
	assert(_has_collision(world.get_node("HouseBody_0")), "Foreground house scenery must be a closed collision mass")
	assert(_has_collision(world.get_node("EastBlock")), "Foreground commercial scenery must be a closed collision mass")
	var door = world.get_node("ClassroomDoorBarricade")
	door.interact(player)
	assert(door.door_state == door.DoorState.BARRICADED, "Barricadable door must enter barricaded state")
	door.creature_arrived()
	var phone = world.get_node("PhoneUI")
	phone.receive_sms("Test", "The inbox is connected.")
	phone.open()
	assert(phone._overlay.visible, "Phone UI must open")
	phone.close()
	var vhs = world.get_node("VHSSystem")
	assert(vhs.collect_tape(&"test_tape", "TEST TAPE", "Playback route works."), "VHS tape must collect")
	assert(vhs.tape_count() == 1, "VHS archive must track collected tapes")
	vhs.open_archive()
	assert(vhs._overlay.visible, "VHS archive must still open without animated tracking effects")
	assert(not vhs.is_processing(), "VHS archive menu must remain idle when no tape is playing")
	vhs._play_tape(&"test_tape")
	assert(vhs.is_processing(), "VHS playback timer must run only during playback")
	vhs.close()
	assert(not vhs.is_processing(), "Closing VHS playback must stop its processing")
	print("MECHANICS_SMOKE_TEST_PASS")
	quit()


func _has_collision(node: Node) -> bool:
	if not node is CollisionObject3D:
		return false
	return node.find_children("*", "CollisionShape3D", true, false).size() > 0


func _route_is_clear(world: Node3D, player: CollisionObject3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		push_error("Blocked structural route from %s to %s by %s" % [from, to, hit.get("collider")])
	return hit.is_empty()


func _has_support_below(world: Node3D, player: CollisionObject3D, from: Vector3, depth: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3(0.0, depth, 0.0), 1)
	query.exclude = [player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		push_error("No structural support below %s within %.2f m" % [from, depth])
	return not hit.is_empty()
