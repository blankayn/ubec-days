# Capture the emotes and the emote box inside the REAL game.
#
#   Godot_v4.7-stable_win64.exe --path . --script res://scripts/tools/citizen_emote_capture.gd
#
# NOT --headless: this renders.
#
# Drives the emotes through the player's own trigger rather than through
# synthesised key events. Neither InputEventKey nor InputEventAction fed to
# Input.parse_input_event reaches the Player's _unhandled_input under a
# `--script` SceneTree run -- the map's own _unhandled_input does receive them,
# so this is a harness limitation rather than a game one. The key bindings are
# covered by input_map_smoke_test.gd and the behaviour by
# citizen_playable_smoke_test.gd; what these shots add is what it LOOKS like.
#
# Emotes are held loops now, which is what makes this tool work at all. It used
# to be unable to photograph one: the clips are ~1.1 s and a frame of the
# streaming city can exceed that, so a timed emote started and finished between
# two _process calls. A hold does not expire, so there is no longer a race.
#
# The last two shots straddle the loop point (0.97 x length, then just after the
# wrap). If those two frames read as continuous motion there is no seam -- the
# visual counterpart to emote_loop_seam_check.gd's number.
extends SceneTree

const MAP := "res://banilad_city.tscn"

var _map: Node3D
var _frames := 0
var _stage := 0


func _initialize() -> void:
	var packed: PackedScene = load(MAP)
	if packed == null:
		push_error("could not load " + MAP)
		quit(1)
		return
	_map = packed.instantiate() as Node3D
	get_root().add_child(_map)
	print("EMOTE map loaded")


func _player() -> Node:
	return _map.get_node_or_null("Player")


func _anim() -> AnimationPlayer:
	return (_player().get_node("ModelRoot")
		.find_child("AnimationPlayer", true, false) as AnimationPlayer)


func _snap(name: String) -> void:
	get_root().get_texture().get_image().save_png("user://%s.png" % name)
	print("CAP ", name, "  playing=", _anim().current_animation)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 70:
		return false

	var player := _player()
	# Emotes require is_on_floor(); the player spawns above the road and takes a
	# moment to settle. Triggering before then is silently refused, which looks
	# exactly like a broken binding.
	if _stage == 0 and (player == null or not player.call("is_on_floor")):
		return false

	match _stage:
		0:
			print("EMOTE available: ", player.call("get_emotes").size())
			_snap("emote_hud")
			player.call("_try_emote", 0)
			_stage = 1
			_frames = 0
		1:
			if _frames < 2:
				return false
			_snap("emote_flair")
			player.call("_try_emote", 1)
			_stage = 2
			_frames = 0
		2:
			if _frames < 2:
				return false
			_snap("emote_moonwalk")
			# Straddle the wrap. seek(t, true) places the pose exactly, so these
			# two frames are a before/after of the loop point rather than
			# whatever the frame rate happened to land on.
			var clip := _anim().get_animation("emote/moonwalk")
			_anim().seek(clip.length * 0.97, true)
			_stage = 3
			_frames = 0
		3:
			if _frames < 2:
				return false
			_snap("emote_wrap_before")
			_anim().seek(0.02, true)
			_stage = 4
			_frames = 0
		4:
			if _frames < 2:
				return false
			_snap("emote_wrap_after")
			# _play_oneshot does NOT go through the jump branch's _cancel_emote,
			# so without this the hold would survive, _update_animation would
			# return early forever, and the LOOP_NONE jump would freeze on its
			# last frame.
			player.call("_cancel_emote")
			player.call("_play_oneshot", "locomotion/jump", 0.1)
			_stage = 5
			_frames = 0
		5:
			if _frames < 2:
				return false
			_snap("emote_jump")
			print("EMOTE_CAPTURE_DONE")
			return true
	return false
