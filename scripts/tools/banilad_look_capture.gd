extends SceneTree
## Screenshots the map from the same viewpoints render_preview.py uses, so the
## in-game look can be compared against the Cycles previews shot for shot.
##
## The deliverable is Godot, not Cycles. The two will never match exactly
## (Cycles Filmic against Compatibility Filmic, sun energy 4.0 against 0.75),
## so this exists to judge the thing that actually ships.
##
## Must run WITH a window -- the headless renderer draws nothing:
##
##   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/banilad_look_capture.gd -- city_overview colon_downtown
##
## Writes .runtime/look_<shot>.png. With no shot names it renders all of them.
##
##   --flat    clear vertex colour on every material -- the A/B against the
##             pre-tint look. It CLEARS rather than skips, because Godot's
##             importer sets the flag on most materials by itself.
##   --nofog   disable the depth fog. Only for `city_overview`, which looks
##             down from 4.5 km and is a QA view, not a gameplay one.

const MAP_SCENE := "res://assets/maps/banilad_map.glb"
const OUT_DIR := "res://.runtime"

## Camera positions are the Blender numbers from render_preview.py verbatim --
## location (x, y, z), rotation in degrees (x, 0, z), lens in mm -- and are
## converted to Godot below. Keeping them in Blender space is deliberate: the
## two files have to stay pointed at the same place to be comparable, and one
## set of numbers cannot drift from itself.
const SHOTS := {
	"city_overview": [Vector3(-950.0, -2150.0, 4500.0), Vector2(0.0, 90.0), 24.0],
	"colon_downtown": [Vector3(-1205.0, -4800.0, 240.0), Vector2(64.0, 0.0), 40.0],
	"fuente_circle": [Vector3(-2022.0, -3120.0, 210.0), Vector2(62.0, 0.0), 40.0],
	"carbon_market": [Vector3(-1391.0, -4980.0, 230.0), Vector2(63.0, 0.0), 40.0],
	"corridor": [Vector3(-30.0, 250.0, 160.0), Vector2(62.6, 2.1), 35.0],
	"street": [Vector3(30.0, 480.0, 26.0), Vector2(80.0, 12.0), 34.0],
	"itpark": [Vector3(-250.0, -1050.0, 260.0), Vector2(68.0, 45.0), 40.0],
	# Close enough to resolve a window band and a shopfront course. The aerial
	# shots above are all 160 m or higher, where a 1 m band is a few pixels and
	# absence is indistinguishable from presence.
	#
	# NOTE render_preview.py's own "street" shot sits at z = 26 m, which was
	# above ground when the map was flat and is now BELOW the ~35 m terrain at
	# that point -- it renders the underside of the ground plane. These two are
	# placed against the current terrain instead.
	"colon_street": [Vector3(-1205.0, -4520.0, 48.0), Vector2(84.0, 0.0), 34.0],

	# --- The hand-authored landmarks (landmarks.py) -------------------------
	# Close, oblique views: these exist to check that each place reads as
	# itself, which a 200 m aerial cannot tell you.
	"fort_san_pedro": [Vector3(-617.0, -4830.0, 96.0), Vector2(58.0, 0.0), 34.0],
	# Ground level, looking north-west at the land gate. rz is measured from
	# north and increases toward west, so a camera south-east of the fort
	# needs POSITIVE rz; a negative one aims it out to sea.
	"fort_gate": [Vector3(-500.0, -4740.0, 26.0), Vector2(82.0, 48.0), 38.0],
	"fuente_rotunda": [Vector3(-2013.0, -2900.0, 78.0), Vector2(66.0, 0.0), 38.0],
	"carbon_stalls": [Vector3(-1373.0, -4900.0, 52.0), Vector2(76.0, 0.0), 36.0],
	# Metro Colon at the Colon x Osmena Boulevard junction, framed like the
	# reference photograph: Metro's billboard wall on the left, the chamfered
	# corner block on the right, near street level.
	# Ground is ~12 m here and the obvious vantage lands INSIDE a footprint;
	# this one is in the open at the north-east approach, 6.5 m up. rx above
	# 90 tilts the camera slightly UP, the way the reference photo looks.
	# Metro Colon at the Colon x Osmena junction. Colon is dense perimeter
	# block: every ground-level sight line to Metro is blocked by the row in
	# front, which is why the reference photo is taken from the junction
	# itself. This clears the neighbouring 2-5 storey roofline instead.
	"metro_colon": [Vector3(-1371.0, -4182.0, 40.0), Vector2(78.7, 139.8), 35.0],
	# Road-focused views: a long gradient, and a close junction where the
	# carriageway / sidewalk / marking layers all meet.
	"osmena_descent": [Vector3(-2206.0, -2380.0, 250.0), Vector2(72.0, 207.0), 40.0],
	"road_junction": [Vector3(-2013.0, -2860.0, 46.0), Vector2(72.0, 0.0), 40.0],
	"road_close": [Vector3(-1205.0, -4430.0, 30.0), Vector2(74.0, 0.0), 40.0],
	"colon_obelisk": [Vector3(-860.0, -4130.0, 34.0), Vector2(80.0, 0.0), 42.0],
	"port_cranes": [Vector3(-348.0, -4820.0, 70.0), Vector2(74.0, 0.0), 38.0],
	"basilica": [Vector3(-1030.0, -4560.0, 46.0), Vector2(76.0, 0.0), 40.0],
	# Ayala Center Cebu -- Cebu Business Park. NOT IT Park; they are 1.4 km
	# apart and Ayala Malls Central Bloc (in IT Park) is a different mall.
	# Ayala Center Cebu, in CEBU BUSINESS PARK. Not IT Park -- the two are
	# 1.4 km apart, and Ayala Malls Central Bloc (which stands in IT Park)
	# is a different mall entirely. Oblique, so The Terraces court on the
	# mall's northern flank is not hidden behind the mass.
	"ayala_center": [Vector3(-900.0, -2120.0, 185.0), Vector2(68.1, -36.8), 34.0],
	# Cebu IT Park, looking north across Garden Bloc at the tower ring.
	"it_park_garden": [Vector3(-625.0, -540.0, 120.0), Vector2(66.5, -0.0), 34.0],
	# Over the infill lattice north of the mall, deliberately clear of UC --
	# the obvious vantage there puts the camera inside the campus facade.
	"banilad_street": [Vector3(150.0, 430.0, 78.0), Vector2(77.0, 22.0), 34.0],
}

const SENSOR_MM := 36.0

var _shots: Array = []
var _flat := false
var _nofog := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--flat":
			_flat = true
		elif a == "--nofog":
			_nofog = true
		elif SHOTS.has(a):
			_shots.append(a)
		else:
			push_error("unknown shot '%s'; known: %s" % [a, ", ".join(SHOTS.keys())])
			quit(1)
			return
	if _shots.is_empty():
		_shots = SHOTS.keys()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var packed := load(MAP_SCENE) as PackedScene
	if packed == null:
		push_error("could not load %s -- run prep_godot.py and re-import" % MAP_SCENE)
		quit(1)
		return
	var map := packed.instantiate()
	if _flat:
		# A true before-Stage-1 comparison has to TURN THE FLAG OFF, not merely
		# decline to turn it on: Godot's importer already sets it on 38 of the
		# 39 materials that carry colour, so skipping VertexAlbedo.apply() only
		# suppresses the ground mottling and leaves every building tinted --
		# which produces two near-identical images and a false negative.
		print("[look] --flat: cleared vertex colour on %d materials" % _disable(map))
	else:
		print("[look] vertex-colour materials flagged: %d" % VertexAlbedo.apply(map))
	root.add_child(map)

	_build_environment()
	var camera := Camera3D.new()
	camera.near = 1.0
	camera.far = 12000.0
	camera.current = true
	# Blender fits its 36 mm sensor to the WIDTH at these resolutions, so the
	# lens converts to a horizontal FOV. Godot's fov is vertical unless the
	# camera is told to keep width, which is what makes the two framings match.
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	root.add_child(camera)

	await _render_all(camera)
	quit()


func _disable(node: Node, seen: Dictionary = {}) -> int:
	## Force every material back to ignoring vertex colour, for the --flat A/B.
	##
	## `seen` is passed down explicitly on every recursive call, so the defaulted
	## dictionary is only ever the top-level one -- the same care VertexAlbedo
	## takes, for the same reason.
	var n := 0
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var m = mesh.surface_get_material(i)
				if m is BaseMaterial3D and not seen.has(m.get_instance_id()):
					seen[m.get_instance_id()] = true
					if (m as BaseMaterial3D).get_flag(
							BaseMaterial3D.FLAG_ALBEDO_FROM_VERTEX_COLOR):
						(m as BaseMaterial3D).set_flag(
							BaseMaterial3D.FLAG_ALBEDO_FROM_VERTEX_COLOR, false)
						n += 1
	for c in node.get_children():
		n += _disable(c, seen)
	return n


func _build_environment() -> void:
	## Mirrors banilad_city.tscn. Any lighting change there has to be made here
	## too or these stop being a preview of the game.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.21, 0.45, 0.68)
	sky_material.sky_horizon_color = Color(0.78, 0.86, 0.9)
	sky_material.sky_curve = 0.14
	sky_material.sky_energy_multiplier = 0.78
	sky_material.ground_bottom_color = Color(0.18, 0.19, 0.18)
	sky_material.ground_horizon_color = Color(0.64, 0.68, 0.68)
	sky_material.ground_curve = 0.08
	sky_material.sun_angle_max = 20.0
	sky_material.sun_curve = 0.1

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# These two must match banilad_city.tscn exactly. Sky ambient plus sky
	# reflections is a materially different look -- it pushes a blue cast into
	# every surface and turns the low-rise fabric pale cyan, which is not what
	# the game renders and would make every judgement made off these shots wrong.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Cool fill against a warm sun. The chalkiness was the two being nearly the
	# same neutral: with a grey ambient at half the sun's energy a lit face and
	# a shadowed face differ only in brightness, so nothing reads as sunlit.
	# Compatibility has no SSAO, so this separation is all the form definition
	# the massing gets.
	env.ambient_light_color = Color(0.52, 0.60, 0.74)
	env.ambient_light_energy = 0.28
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# Aerial perspective -- what gives a city depth, and the honest way to hide
	# the streaming horizon: tiles load at 400 m and unload at 520 m, so without
	# haze the edge of the resident set is a hard line of buildings ending in
	# mid-air.
	#
	# Density is deliberately light, because it has to fade that 400-500 m edge
	# WITHOUT erasing the skyline silhouette -- which is always-resident
	# precisely so the city reads from a distance. 0.0007 leaves roughly 24%
	# haze at 400 m and still lets the towers show through at 2 km as a pale
	# mass, which is how Cebu actually sits against the Busay hills.
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.79, 0.85)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.12
	env.fog_density = 0.0003
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	# Height fog stays OFF. It adds its density PER METRE below fog_height, so
	# even a modest-looking 0.06 dwarfs the 0.0007 depth density across a city
	# whose ground sits between 10 and 40 m -- it washed the whole frame to
	# near-white. Depth fog alone gives the aerial perspective wanted here.
	env.fog_height_density = 0.0
	# `city_overview` looks down from 4.5 km, where 0.0003 density leaves about
	# a quarter of the light and the whole city washes out. That is not a
	# gameplay viewpoint -- the player camera's `far` is 900 m, and at 900 m the
	# haze is the ~24% it is meant to be -- but it does make the km-scale QA
	# shot useless, so that one is rendered with --nofog.
	if _nofog:
		env.fog_enabled = false
	_apply_scene_environment(env)

	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1, 0.94, 0.84)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 900.0
	_apply_scene_sun(sun)
	root.add_child(sun)


func _apply_scene_environment(_env: Environment) -> void:
	## Stage 2 overrides land here.
	pass


func _apply_scene_sun(_sun: DirectionalLight3D) -> void:
	pass


func _render_all(camera: Camera3D) -> void:
	for name in _shots:
		var shot: Array = SHOTS[name]
		var loc: Vector3 = shot[0]
		var rot: Vector2 = shot[1]
		var lens: float = shot[2]

		var pos := _to_godot(loc)
		var dir := _blender_view_direction(deg_to_rad(rot.x), deg_to_rad(rot.y))
		# Straight-down shots have a view direction parallel to UP, which makes
		# looking_at degenerate; use +Z as the up hint there instead.
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3.BACK
		# Assigning `transform` rather than calling look_at(): _initialize()
		# runs before the tree is live, so the global_position setter and
		# look_at() both no-op with an "is_inside_tree" error and leave the
		# camera at the origin -- silently rendering the wrong place.
		camera.transform = Transform3D(Basis(), pos).looking_at(pos + dir, up)
		camera.fov = rad_to_deg(2.0 * atan(SENSOR_MM / (2.0 * lens)))

		# Two frames: the first is where streaming-free geometry and the sky
		# actually get drawn, the second is what gets captured.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var suffix := "_flat" if _flat else ""
		var path := "%s/look_%s%s.png" % [OUT_DIR, name, suffix]
		img.save_png(ProjectSettings.globalize_path(path))
		print("[look] wrote %s" % path)


func _to_godot(blender: Vector3) -> Vector3:
	## 1 BU = 1 m in both; Blender +y north becomes Godot -z, Blender z is up.
	return Vector3(blender.x, blender.z, -blender.y)


func _blender_view_direction(rx: float, rz: float) -> Vector3:
	## A Blender camera looks down its local -Z. Rotation x=0 looks straight
	## down and x=90 looks level; z=0 faces north.
	var b := Vector3(-sin(rz) * sin(rx), cos(rz) * sin(rx), -cos(rx))
	return Vector3(b.x, b.z, -b.y).normalized()
