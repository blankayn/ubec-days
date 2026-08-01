extends RefCounted
class_name CBlockCharacterRoster
## Playable CBlock characters and the last chosen id.

const SAVE_PATH := "user://cblock_character.cfg"
const DEFAULT_ID := "gusion"

const CHARACTERS := {
	"gusion": {
		"id": "gusion",
		"display_name": "Gusion",
		"subtitle": "Dimension W · Mixamo combat",
		"scene_path": "res://assets/characters/gusion/gusion_dimension_w_rigged.glb",
		"uses_embedded_clips": true,
	},
	"duterte": {
		"id": "duterte",
		"display_name": "Duterte",
		"subtitle": "President rig · Mixamo retarget",
		"scene_path": "res://characters/president_duterte__rig.glb",
		"uses_embedded_clips": false,
	},
}

static var selected_id: String = DEFAULT_ID


static func list_characters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for character_id in ["gusion", "duterte"]:
		if CHARACTERS.has(character_id):
			result.append(CHARACTERS[character_id])
	return result


static func get_character(character_id: String) -> Dictionary:
	if CHARACTERS.has(character_id):
		return CHARACTERS[character_id]
	return CHARACTERS[DEFAULT_ID]


static func get_selected() -> Dictionary:
	return get_character(selected_id)


static func set_selected(character_id: String) -> void:
	if not CHARACTERS.has(character_id):
		character_id = DEFAULT_ID
	selected_id = character_id
	_save()


static func load_saved() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		selected_id = DEFAULT_ID
		return
	var saved_id := String(config.get_value("cblock", "character_id", DEFAULT_ID))
	selected_id = saved_id if CHARACTERS.has(saved_id) else DEFAULT_ID


static func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("cblock", "character_id", selected_id)
	config.save(SAVE_PATH)
