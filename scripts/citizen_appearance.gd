class_name CitizenAppearance
extends Resource
## One citizen's look: which part meshes are visible, and what colour each
## material slot is tinted.
##
## Resource rather than RefCounted so archetype presets (student, vendor,
## jeepney barker) can later be authored as .tres and handed to
## CitizenNpcProp from the inspector, and so duplicate() is free.
##
## Part names are never hardcoded here. They come from
## `citizen_manifest.json`, which tools/build_citizen.py generates from
## tools/citizen_spec.py -- so a rename in the builder turns
## citizen_smoke_test.gd red instead of silently making a hairstyle
## unreachable from the creator UI.

const MANIFEST_PATH := "res://assets/characters/citizen/citizen_manifest.json"

static var _manifest: Dictionary
static var _material_cache: Dictionary

## group name -> chosen mesh name, e.g. {"hair": "Hair_Short"}
@export var parts: Dictionary = {}
## slot name -> Color, e.g. {"skin": Color(...)}
@export var colours: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var text := FileAccess.get_file_as_string(MANIFEST_PATH)
		if text.is_empty():
			push_error("citizen manifest missing: " + MANIFEST_PATH)
			return {}
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			_manifest = parsed
		else:
			push_error("citizen manifest is not a JSON object")
	return _manifest


static func slot_palette(slot: String) -> PackedColorArray:
	var out := PackedColorArray()
	var palettes: Dictionary = manifest().get("palettes", {})
	for entry in palettes.get(slot, []):
		out.append(Color(entry[0], entry[1], entry[2]))
	return out


static func default() -> CitizenAppearance:
	var appearance := CitizenAppearance.new()
	appearance.parts = (manifest().get("defaults", {}) as Dictionary).duplicate()
	for slot in manifest().get("slots", []):
		var palette := slot_palette(slot)
		if not palette.is_empty():
			appearance.colours[slot] = palette[0]
	return appearance


## Deterministic variety for pedestrians. Uses a LOCAL RandomNumberGenerator,
## never the global one, so a crowd is reproducible run to run -- which is what
## makes a bad-looking citizen reproducible from its seed alone.
static func random_from_seed(seed_value: int) -> CitizenAppearance:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var appearance := CitizenAppearance.new()
	var groups: Dictionary = manifest().get("groups", {})
	for group in groups:
		var options: Array = groups[group]
		appearance.parts[group] = options[rng.randi_range(0, options.size() - 1)]
	for slot in manifest().get("slots", []):
		var palette := slot_palette(slot)
		if not palette.is_empty():
			appearance.colours[slot] = palette[rng.randi_range(0, palette.size() - 1)]
	return appearance


func to_dict() -> Dictionary:
	return {"parts": parts.duplicate(), "colours": colours.duplicate()}


static func from_dict(data: Dictionary) -> CitizenAppearance:
	var appearance := CitizenAppearance.default()
	for group in data.get("parts", {}):
		appearance.parts[group] = String(data["parts"][group])
	for slot in data.get("colours", {}):
		appearance.colours[slot] = data["colours"][slot]
	return appearance


func equals(other: CitizenAppearance) -> bool:
	if other == null:
		return false
	return parts == other.parts and colours == other.colours


func describe() -> String:
	var bits: PackedStringArray = []
	for group in ["hair", "top", "bottom", "shoes"]:
		if parts.has(group):
			bits.append(String(parts[group]).get_slice("_", 1).capitalize())
	return " / ".join(bits)


## Materials are SHARED by value, not per instance.
##
## The imported GLB's materials hang off the Mesh resource and Godot caches the
## imported PackedScene, so `mesh.surface_get_material(i).albedo_color = red`
## recolours every citizen in the world AND the player. Overrides are the only
## safe path. Caching them keyed on slot+colour means two pedestrians who roll
## the same blue tee get the SAME material and batch together, and the whole
## city needs at most len(SLOTS) * palette_size materials however large the
## crowd gets.
static func _material_for(slot: String, colour: Color) -> StandardMaterial3D:
	var key := "%s|%s" % [slot, colour.to_html(false)]
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.resource_name = "Citizen_" + slot
	material.albedo_color = colour
	material.roughness = 0.85
	material.metallic = 0.0
	material.metallic_specular = 0.25
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material_cache[key] = material
	return material


func _slot_of(mesh_instance: MeshInstance3D, surface: int) -> String:
	# Keyed on the material's resource_name, the same dispatch metro_capture.gd
	# uses -- so surface INDICES are never hardcoded and a mesh can carry two
	# slots (Face_Detail carries both `eyes` and `hair`).
	var source := mesh_instance.mesh.surface_get_material(surface)
	if source == null or not source.resource_name.begins_with("Citizen_"):
		return ""
	var slot := source.resource_name.substr("Citizen_".length())
	# Defensive: Blender disambiguates duplicate material names with a ".001"
	# suffix and those ride into the GLB, which silently made every garment but
	# one untintable. The build now shares one material per slot so this should
	# never fire -- but a slot that fails to resolve is invisible at runtime, so
	# it is not worth trusting.
	var dot := slot.find(".")
	return slot.substr(0, dot) if dot >= 0 else slot


func apply(rig_root: Node3D) -> void:
	var data := manifest()
	if data.is_empty():
		return

	var by_name := {}
	for node in rig_root.find_children("*", "MeshInstance3D", true, false):
		by_name[node.name] = node

	# Visibility: one option per group, plus the accent its chosen top drags in.
	var wanted := {}
	for name in data.get("body_meshes", []):
		wanted[name] = true
	var accents: Dictionary = data.get("part_accent", {})
	for group in data.get("groups", {}):
		var chosen := String(parts.get(group, ""))
		for option in data["groups"][group]:
			if option == chosen:
				wanted[option] = true
			if accents.has(option):
				wanted[accents[option]] = option == chosen
	for name in by_name:
		var mesh_instance: MeshInstance3D = by_name[name]
		mesh_instance.visible = bool(wanted.get(name, false))

	# Tint every visible surface through an override.
	for name in by_name:
		var mesh_instance: MeshInstance3D = by_name[name]
		if not mesh_instance.visible or mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var slot := _slot_of(mesh_instance, i)
			if slot.is_empty() or not colours.has(slot):
				continue
			mesh_instance.set_surface_override_material(
				i, _material_for(slot, colours[slot]))
