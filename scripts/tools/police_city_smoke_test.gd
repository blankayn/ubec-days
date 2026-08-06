extends SceneTree
## Guard on the beat cop as he is placed in banilad_city.tscn.
##
## `police_smoke_test.gd` proves the clips are installed and the player is
## running; this proves the officer is actually *in the map* and that the
## animation reaches his bones. Those are different failures: a clip whose
## tracks are re-pathed wrongly still reports `is_playing() == true` while the
## officer stands in the T-pose the model is authored in, with nothing logged.
##
## Collects failures and quits non-zero instead of using assert(), which halts
## _initialize() before its quit() and hangs a headless run.

var _failures: Array[String] = []


func _ground_y_under(world: Node3D, point: Vector3, ignore: Node = null) -> float:
	## Terrain height beneath a point. Starts well above the tallest ground on
	## the map (the hill roads reach 165 m) so it never begins underground.
	##
	## `ignore` must be the subject: coming down from above, the first thing the
	## ray meets is the subject's own collision body at head height, which reads
	## as ground exactly one body-height too high.
	var space := world.get_world_3d().direct_space_state
	if space == null:
		return NAN
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(point.x, point.y + 200.0, point.z),
		Vector3(point.x, point.y - 50.0, point.z), 1)
	if ignore != null:
		var skip: Array[RID] = []
		for body in ignore.find_children("*", "CollisionObject3D", true, false):
			skip.append((body as CollisionObject3D).get_rid())
		if ignore is CollisionObject3D:
			skip.append((ignore as CollisionObject3D).get_rid())
		query.exclude = skip
	var hit := space.intersect_ray(query)
	return NAN if hit.is_empty() else float(hit["position"].y)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _initialize() -> void:
	var packed := load("res://banilad_city.tscn") as PackedScene
	if packed == null:
		print("POLICE_CITY_FAIL: banilad_city.tscn will not load")
		quit(1)
		return
	var world := packed.instantiate()
	root.add_child(world)
	for _i in 90:
		await process_frame

	var police := world.get_node_or_null("BaniladPolice") as Node3D
	_check(police != null, "BaniladPolice did not spawn in the city")
	if police == null:
		_report()
		return

	# --- Placement ---------------------------------------------------------
	# Measured against the ground under his feet, not an absolute band. The old
	# check was `-1.0 < y < 2.0`, which was correct when the map was flat at
	# zero; on real terrain Gov. M. Cuenco Avenue is about 33 m up, so a
	# correctly placed officer failed it.
	var ground := _ground_y_under(world, police.global_position, police)
	_check(
		is_finite(ground) and absf(police.global_position.y - ground) < 1.5,
		"officer is at y=%.2f but the ground under him is %.2f" % [
			police.global_position.y, ground]
	)
	var player := world.get_node_or_null("Player") as Node3D
	if player != null:
		var gap := police.global_position.distance_to(player.global_position)
		_check(gap < 60.0, "officer is %.0f m from spawn — too far to ever be seen" % gap)

	# --- Model -------------------------------------------------------------
	var skeleton := police.find_child("Skeleton3D", true, false) as Skeleton3D
	_check(skeleton != null, "officer has no Skeleton3D")
	if skeleton != null:
		_check(
			skeleton.get_bone_count() == 65,
			"expected the 65-bone Mixamo rig, got %d" % skeleton.get_bone_count()
		)
		for bone in ["mixamorig1_Hips", "mixamorig1_LeftArm", "mixamorig1_RightFoot"]:
			_check(skeleton.find_bone(bone) >= 0, "rig is missing %s" % bone)

	var meshes := police.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() > 0, "officer has no mesh")
	if meshes.size() > 0:
		var mesh_instance := meshes[0] as MeshInstance3D
		_check(
			mesh_instance.mesh.get_surface_count() == 12,
			"expected 12 material surfaces (one per uniform part), got %d"
			% mesh_instance.mesh.get_surface_count()
		)
		# Measured from the bones through the real transform chain, not from
		# the mesh's bind AABB. A skinned mesh follows its skeleton, so the
		# bind AABB reports the authored size no matter what the rig is doing
		# -- it read a healthy 1.76 m while the officer was actually exported
		# at 1/100 scale lying on his back, and the playable copy was being
		# scaled 500x to compensate.
		var skeleton_scale := skeleton.get_global_transform().basis.get_scale()
		var top := -INF
		var bottom := INF
		for bone_index in skeleton.get_bone_count():
			var y: float = skeleton.get_bone_global_rest(bone_index).origin.y
			top = maxf(top, y)
			bottom = minf(bottom, y)
		var height: float = (top - bottom) * skeleton_scale.y
		_check(
			absf(height - 1.80) < 0.12,
			"officer stands %.2f m from crown to sole, expected ~1.80 m" % height
		)

	# --- Animation actually reaching the bones -----------------------------
	# Direct child, not find_child: the GLB carries its own AnimationPlayer for
	# the baked idle, and a recursive search reaches that one first.
	var anim_player := police.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_check(anim_player != null, "officer has no AnimationPlayer")
	if anim_player != null:
		_check(anim_player.has_animation("locomotion/idle"), "idle clip missing")
		_check(anim_player.has_animation("locomotion/walk"), "walk clip missing")
		_check(anim_player.is_playing(), "officer is not playing anything")
		if anim_player.has_animation("locomotion/idle"):
			var idle := anim_player.get_animation("locomotion/idle")
			var unresolved := 0
			for track_index in idle.get_track_count():
				var path := String(idle.track_get_path(track_index))
				if police.get_node_or_null(NodePath(path.get_slice(":", 0))) == null:
					unresolved += 1
			_check(
				unresolved == 0,
				"%d/%d idle tracks resolve to nothing — he will T-pose silently"
				% [unresolved, idle.get_track_count()]
			)

	if skeleton != null:
		var moved := 0
		for bone_name in ["mixamorig1_LeftArm", "mixamorig1_Spine1", "mixamorig1_RightUpLeg"]:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0:
				continue
			var rest_rotation := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			var pose_rotation := skeleton.get_bone_pose(bone).basis.get_rotation_quaternion()
			if rest_rotation.angle_to(pose_rotation) > 0.02:
				moved += 1
		_check(moved > 0, "no bone left its rest pose — the officer is T-posing")

	# --- Interaction -------------------------------------------------------
	var body := police.find_child("InteractBody", true, false) as StaticBody3D
	_check(body != null, "officer has no interaction body")
	if body != null:
		_check(body.collision_layer == 1, "interaction body is off the world layer")
		_check(
			body.get_interaction_prompt().begins_with("Talk to"),
			"interaction prompt is missing"
		)

	_report()


func _report() -> void:
	if _failures.is_empty():
		print("POLICE_CITY_OK")
		quit(0)
	else:
		for failure in _failures:
			print("POLICE_CITY_FAIL: " + failure)
		quit(1)
