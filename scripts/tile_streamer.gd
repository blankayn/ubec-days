extends Node3D

## Distance-streams the 250 m map tiles that banilad_map/prep_godot.py exports.
##
## The safety property this design leans on: ground, the flat road-collision
## plane and the skyline silhouette all live in banilad_base.glb and are NEVER
## unloaded. So the player can always stand, always drive, and always sees a
## horizon, even when not one tile around them is resident. Only visual detail
## streams -- buildings, sidewalks, markings, props, landuse, water.
##
## That is what makes the classic streaming bug -- car falls through a tile that
## has not finished loading -- structurally impossible here rather than a thing
## to be timed carefully.

## Emitted every time a tile becomes resident, including on a reload after the
## player has driven out of range and back. Anything that edits tile contents --
## hiding a mesh, disabling a collider -- has to listen to this rather than
## reach in once at startup: the edit dies with the node when the tile is freed,
## and the reloaded copy arrives untouched.
signal tile_loaded(key: String, node: Node3D)

const MANIFEST := "res://assets/maps/tiles.json"
const TILE_DIR := "res://assets/maps/tiles/"

## Load once the nearest EDGE of a tile comes within LOAD_RADIUS; unload only
## past UNLOAD_RADIUS. The gap is hysteresis -- measuring to the centre, or
## using one threshold for both, makes a player standing on a boundary load and
## free the same tile every frame.
const LOAD_RADIUS := 400.0
const UNLOAD_RADIUS := 520.0

## Instantiating is what costs a frame; the threaded load itself is off-thread.
## Adding one tile per frame keeps the hitch bounded no matter how fast the
## player is driving.
const MAX_INSTANTIATE_PER_FRAME := 1

@export var target_path: NodePath = ^"../../Player"
@export var streaming_enabled := true

var _rects: Dictionary = {}    # key -> Rect2 over Godot (x, z)
var _loaded: Dictionary = {}   # key -> Node3D
var _pending: Dictionary = {}  # key -> true while a threaded load is in flight
var _target: Node3D = null
var _instantiated_last_frame := 0
var _peak_resident := 0


func _ready() -> void:
	_load_manifest()
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_warning("TileStreamer: no target at %s, nothing will stream" % target_path)
		return
	if streaming_enabled:
		# Prime synchronously: the first frame should not be an empty city.
		_refresh(true)


func _process(_delta: float) -> void:
	if not streaming_enabled or _target == null:
		return
	_refresh(false)


func _refresh(blocking: bool) -> void:
	var origin := _target.global_position
	var here := Vector2(origin.x, origin.z)
	_instantiated_last_frame = 0

	for key in _loaded.keys():
		if _distance(key, here) > UNLOAD_RADIUS:
			var node: Node = _loaded[key]
			_loaded.erase(key)
			if is_instance_valid(node):
				node.queue_free()

	for key in _rects:
		if _loaded.has(key) or _pending.has(key):
			continue
		if _distance(key, here) > LOAD_RADIUS:
			continue
		if blocking:
			_instantiate(key, ResourceLoader.load(_tile_path(key)))
		else:
			ResourceLoader.load_threaded_request(_tile_path(key))
			_pending[key] = true

	if not blocking:
		for key in _pending.keys():
			if _instantiated_last_frame >= MAX_INSTANTIATE_PER_FRAME:
				break
			var path := _tile_path(key)
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_pending.erase(key)
				if _instantiate(key, ResourceLoader.load_threaded_get(path)):
					_instantiated_last_frame += 1
			elif status == ResourceLoader.THREAD_LOAD_FAILED \
					or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_pending.erase(key)
				push_warning("TileStreamer: could not load %s" % path)

	_peak_resident = maxi(_peak_resident, _loaded.size())


func _instantiate(key: String, packed: Variant) -> bool:
	if packed == null or not (packed is PackedScene):
		return false
	var node: Node = (packed as PackedScene).instantiate()
	node.name = key
	# Godot's glTF importer does not flag the baked vertex tint as albedo, so a
	# tile renders flat until this runs. Cheap and idempotent: it marks each
	# mesh, and a tile that streams out and back in does no work the second time.
	VertexAlbedo.apply(node)
	add_child(node)
	_loaded[key] = node
	tile_loaded.emit(key, node)
	return true


func _distance(key: String, here: Vector2) -> float:
	## To the nearest point of the tile, not its centre. A 250 m tile measured
	## centre-to-player pops in 125 m late on the near side and 125 m early on
	## the far side.
	var r: Rect2 = _rects[key]
	var nearest := Vector2(
		clampf(here.x, r.position.x, r.end.x),
		clampf(here.y, r.position.y, r.end.y))
	return here.distance_to(nearest)


func _tile_path(key: String) -> String:
	return "%s%s.glb" % [TILE_DIR, key]


func _load_manifest() -> void:
	## A manifest rather than a runtime DirAccess scan of res://: an exported
	## build does not expose .glb files there the way the editor does, and the
	## streamer needs each tile's footprint anyway.
	if not FileAccess.file_exists(MANIFEST):
		push_error("TileStreamer: %s missing - run prep_godot.py" % MANIFEST)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TileStreamer: %s is not a tile manifest" % MANIFEST)
		return
	for entry in parsed.get("tiles", []):
		var lo: Array = entry.get("min", [])
		var hi: Array = entry.get("max", [])
		if lo.size() != 2 or hi.size() != 2:
			continue
		var key := String(entry.get("key", ""))
		if key.is_empty():
			continue
		_rects[key] = Rect2(Vector2(lo[0], lo[1]),
			Vector2(float(hi[0]) - float(lo[0]), float(hi[1]) - float(lo[1])))


# --- Introspection, used by the smoke tests ---------------------------------

func tile_count() -> int:
	return _rects.size()


func resident_count() -> int:
	return _loaded.size()


func peak_resident() -> int:
	return _peak_resident


func instantiated_last_frame() -> int:
	return _instantiated_last_frame


func tile_key_at(point: Vector2) -> String:
	for key in _rects:
		if (_rects[key] as Rect2).has_point(point):
			return key
	return ""


func is_resident(key: String) -> bool:
	return _loaded.has(key)


func force_load_all() -> int:
	## Switch streaming off and make the whole map resident. Only for headless
	## checks that probe points kilometres apart; it defeats the point of the
	## streamer and costs the full 12 MB.
	streaming_enabled = false
	for key in _rects:
		if not _loaded.has(key):
			_instantiate(key, ResourceLoader.load(_tile_path(key)))
	_peak_resident = maxi(_peak_resident, _loaded.size())
	return _loaded.size()
