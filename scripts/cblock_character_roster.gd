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
	"police": {
		"id": "police",
		"display_name": "PO1 Ramirez",
		"subtitle": "UBEC beat cop · Mixamo rig",
		"scene_path": "res://assets/npcs/police.glb",
		"uses_embedded_clips": false,
	},
	"citizen": {
		"id": "citizen",
		"display_name": "Citizen",
		"subtitle": "Your look · hair, clothes, colours",
		"scene_path": "res://assets/characters/citizen/citizen.glb",
		"uses_embedded_clips": false,
		"customizable": true,
	},
}

static var selected_id: String = DEFAULT_ID
## The citizen's saved look. Only meaningful for characters marked
## `customizable`; the other three ignore it.
static var appearance: CitizenAppearance = null


static func list_characters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Hardcoded so the picker's card order is deliberate rather than dictionary
	# order -- a new entry in CHARACTERS alone will NOT appear in the UI.
	for character_id in ["gusion", "duterte", "police", "citizen"]:
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


static func is_customizable(character_id: String) -> bool:
	return bool(get_character(character_id).get("customizable", false))


static func get_appearance() -> CitizenAppearance:
	if appearance == null:
		appearance = CitizenAppearance.default()
	return appearance


static func set_appearance(value: CitizenAppearance) -> void:
	if value == null:
		return
	appearance = value
	_save()


static func load_saved() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		selected_id = DEFAULT_ID
		appearance = CitizenAppearance.default()
		return
	var saved_id := String(config.get_value("cblock", "character_id", DEFAULT_ID))
	selected_id = saved_id if CHARACTERS.has(saved_id) else DEFAULT_ID
	# Default {} rather than null: ConfigFile treats a nil default as "no
	# default given" and logs an error every time the section is absent, which
	# it is for every existing save.
	var stored = config.get_value("citizen", "appearance", {})
	appearance = (
		CitizenAppearance.from_dict(stored)
		if stored is Dictionary
		else CitizenAppearance.default()
	)


static func _save() -> void:
	# Writes BOTH sections every time. This used to build a fresh ConfigFile and
	# write only character_id, which meant every switch_character() silently
	# erased the saved citizen look.
	var config := ConfigFile.new()
	config.set_value("cblock", "character_id", selected_id)
	if appearance != null:
		config.set_value("citizen", "appearance", appearance.to_dict())
	config.save(SAVE_PATH)
