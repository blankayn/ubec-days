extends SceneTree
## Renders the Banilad map from the same aerial viewpoint as the reference
## photo, so the built palette can be compared against the real district.
##
##   Godot_v4.7-stable_win64.exe --path . --write-movie .runtime/aerial.png \
##       --fixed-fps 30 --quit-after 12 --script res://scripts/tools/banilad_aerial_capture.gd

const MAP_SCENE := "res://assets/maps/banilad_map.glb"

# Looking north up Gov. M. Cuenco Avenue, Gaisano Country Mall on the left.
const CAMERA_POSITION := Vector3(60.0, 430.0, -140.0)
const CAMERA_TARGET := Vector3(-70.0, 0.0, -660.0)


func _initialize() -> void:
	var packed := load(MAP_SCENE) as PackedScene
	if packed == null:
		push_error("could not load %s" % MAP_SCENE)
		quit(1)
		return
	root.add_child(packed.instantiate())

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.21, 0.45, 0.68)
	sky_material.sky_horizon_color = Color(0.78, 0.86, 0.9)
	sky_material.sky_energy_multiplier = 0.78
	sky_material.ground_bottom_color = Color(0.3, 0.32, 0.32)
	sky_material.ground_horizon_color = Color(0.66, 0.72, 0.74)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.64, 0.7)
	env.ambient_light_energy = 0.36
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1, 0.95, 0.87)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 900.0
	root.add_child(sun)

	var camera := Camera3D.new()
	camera.fov = 58.0
	camera.near = 1.0
	camera.far = 4000.0
	camera.current = true
	root.add_child(camera)
	camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)

	print("[aerial] camera at %s looking at %s" % [CAMERA_POSITION, CAMERA_TARGET])
