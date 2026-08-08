extends SceneTree
## Throwaway: does the procedural mall come back when its tile streams out and
## back in? Counts visible mall wings before and after a round trip.

const MALL_NODE := "Gaisano Country Mall"
const NEAR := Vector3(12.79, 1.2, -554.24)     # spawn, mall tile resident
const FAR := Vector3(12.79, 1.2, 400.0)        # >520 m away, tile unloaded

var _level: Node3D
var _player: Node3D
var _frames := 0
var _stage := 0
var _fail := false


func _initialize() -> void:
	_level = (load("res://banilad_city.tscn") as PackedScene).instantiate()
	root.add_child(_level)


func _visible_walls() -> int:
	var n := 0
	for node in _level.find_children(MALL_NODE, "", true, false):
		var m := node as Node3D
		if m != null and m.is_visible_in_tree():
			n += 1
	return n


func _report(label: String) -> int:
	var v := _visible_walls()
	var scanned := _level.find_child("GaisanoCountryMallAsset", true, false) != null
	print("[mall] %-22s visible procedural wings: %d   scanned asset: %s"
		% [label, v, str(scanned)])
	return v


func _process(_d: float) -> bool:
	_frames += 1
	if _player == null:
		_player = _level.get_node_or_null("Player") as Node3D
		return false
	# Let _ready()'s awaits finish and the mall swap land.
	if _frames < 120:
		return false

	if _stage == 0:
		if _report("at spawn") != 0:
			print("[mall] FAIL: wings still visible after the initial swap")
			_fail = true
		_player.global_position = FAR
		_stage = 1
		_frames = 0
		return false
	if _stage == 1:
		if _frames < 90:
			return false
		_report("driven away")
		_player.global_position = NEAR
		_stage = 2
		_frames = 0
		return false
	if _frames < 120:
		return false

	if _report("returned") != 0:
		print("[mall] FAIL: wings reappeared with the reloaded tile")
		_fail = true
	print("[mall] %s" % ("FAILED" if _fail else "PASSED"))
	quit(1 if _fail else 0)
	return true
