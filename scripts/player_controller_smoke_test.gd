extends SceneTree

## Fast regression test for the standalone first-person controller.


func _initialize() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if not _require(packed != null, "Main scene must load"):
		return
	var test_root := packed.instantiate() as Node3D
	test_root.set_script(null)

	var ground := StaticBody3D.new()
	ground.name = "SmokeGround"
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(40.0, 0.6, 40.0)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	ground.position = Vector3(0.0, -0.3, 0.0)
	test_root.add_child(ground)
	root.add_child(test_root)

	var player := test_root.get_node("Player") as CharacterBody3D
	player.position = Vector3(0.0, 1.2, 0.0)
	player.velocity = Vector3.ZERO
	for _frame in 20:
		await physics_frame
	if not _require(player.is_on_floor(), "Player must settle on the ground"):
		return
	if not _require(absf(player.global_position.y - 0.95) < 0.2, "Player capsule must not hover or sink"):
		return
	if not _require(player.get("auto_jump_enabled") == false, "Auto-jump must stay opt-in"):
		return

	# Current controller is Head/Camera3D first-person.
	var head := player.get_node_or_null("Head") as Node3D
	var camera := player.get_node_or_null("Head/Camera3D") as Camera3D
	var character_visual := player.get_node_or_null("ModelPivot/CharacterVisual") as Node3D
	if not _require(head != null and camera != null, "First-person Head/Camera3D hierarchy must exist"):
		return
	if not _require(absf(head.position.y - 0.65) < 0.08, "First-person camera must stay at eye level"):
		return
	if not _require(camera.current, "First-person camera must be current"):
		return
	if character_visual != null:
		if not _require(not character_visual.visible, "Local player body must stay hidden in first-person"):
			return
	if not _require(player.has_method("add_battery"), "Battery controller must remain installed"):
		return
	if not _require(player.has_method("enter_hiding"), "Hiding controller must remain installed"):
		return

	print("PLAYER_CONTROLLER_SMOKE_TEST_PASS")
	quit(0)


func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PLAYER_CONTROLLER_SMOKE_TEST_FAIL: " + message)
	quit(1)
	return false
