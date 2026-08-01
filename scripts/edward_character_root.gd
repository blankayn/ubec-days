@tool
extends Node3D
## Open in Godot: double-click `assets/npcs/edward_character.tscn`
## Use the Inspector → Preview Clip to scrub Edward's imported GLB animations.

enum PreviewClip {
	IDLE_NLA_TRACK,
	WALK_NLA_TRACK_001,
	LONG_NLA_TRACK_002,
}

@export var preview_clip: PreviewClip = PreviewClip.IDLE_NLA_TRACK:
	set(value):
		preview_clip = value
		_play_preview()

@export var auto_play_in_editor := true
@export var model_yaw_degrees := 180.0


func _ready() -> void:
	if Engine.is_editor_hint() and auto_play_in_editor:
		_play_preview()


func _play_preview() -> void:
	var model := get_node_or_null("OfficeWorkerModel") as Node3D
	if model != null:
		model.rotation_degrees.y = model_yaw_degrees
	var player := _find_animation_player(self)
	if player == null:
		return
	var clip := _clip_name(preview_clip)
	if clip == &"":
		return
	var animation := player.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	player.play(clip)


func _clip_name(choice: PreviewClip) -> StringName:
	match choice:
		PreviewClip.IDLE_NLA_TRACK:
			return &"NlaTrack"
		PreviewClip.WALK_NLA_TRACK_001:
			return &"NlaTrack_001"
		PreviewClip.LONG_NLA_TRACK_002:
			return &"NlaTrack_002"
	return &""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
