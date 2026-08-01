extends Node
## StoryManager — three-chapter arc for UCB Banilad
## Ch1: Day campus quest → walk home → realize something was left behind
## Ch2: Night return across Cuenco Ave / the bridge
## Ch3: Retrieve the forgotten item inside UC and confront Inday's presence

signal chapter_changed(chapter: int, title: String)
signal objective_changed(text: String)
signal day_night_changed(is_night: bool)
signal story_complete()

const CHAPTER_TITLES := {
	1: "CHAPTER 1 — DAY ERRAND",
	2: "CHAPTER 2 — FORGOTTEN",
	3: "CHAPTER 3 — NA AKO DIRI",
}

var chapter: int = 1
var is_night: bool = false
var _day_tasks: Dictionary = {}
var _night_checks: Dictionary = {}
var _ch3_steps: Dictionary = {}
var _home_zone_ready: bool = false
var _home_triggered: bool = false
var _item_name: String = "USB drive"

# Wired by world.gd
var player: CharacterBody3D = null
var hud: CanvasLayer = null
var scare_manager: Node = null
var phone_ui: CanvasLayer = null
var vhs_system: CanvasLayer = null
var _sent_sms: Dictionary = {}


func _ready() -> void:
	# Day tasks for Chapter 1 — locker (exterior), guard post (GF-102)
	_day_tasks = {
		&"day_locker": false,
		&"day_registrar": false,
	}
	# Night checks for Chapter 2 (existing audit props + bridge)
	_night_checks = {
		&"fuse_box": false,
		&"payphone": false,
		&"dead_tree": false,
	}
	# Chapter 3 retrieval path
	_ch3_steps = {
		&"ch3_bag": false,
		&"ch3_note": false,
		&"ch3_elevator": false,
	}


static var selected_starting_chapter: int = 1
## When true, Playthrough skips the three-chapter story and runs horror/survival only.
static var horror_playthrough: bool = false

var is_horror_mode: bool = false


func start(start_ch: int = 1) -> void:
	if horror_playthrough:
		_start_horror_playthrough()
		return
	is_horror_mode = false
	chapter = start_ch
	match start_ch:
		1:
			is_night = false
			day_night_changed.emit(false)
			chapter_changed.emit(1, CHAPTER_TITLES[1])
			_send_sms("Mama", "Kuha na ang USB sa locker ha. Ingat.")
			_refresh_hud()
			if hud:
				hud.show_message("14:20 // UC BANILAD — Finish your campus errands before the sun drops.", 5.0)
		2:
			is_night = true
			for k in _day_tasks.keys():
				_day_tasks[k] = true
			_home_zone_ready = true
			_home_triggered = true
			day_night_changed.emit(true)
			chapter_changed.emit(2, CHAPTER_TITLES[2])
			_send_sms("Unknown", "Ayaw pag balik.")
			_refresh_hud()
			if hud:
				hud.show_message("19:48 // Night fell. Check the fuse box, payphone, and dead tree.", 6.0)
		3:
			is_night = true
			for k in _day_tasks.keys():
				_day_tasks[k] = true
			for k in _night_checks.keys():
				_night_checks[k] = true
			day_night_changed.emit(true)
			chapter_changed.emit(3, CHAPTER_TITLES[3])
			if phone_ui != null and phone_ui.has_method("set_no_signal"):
				phone_ui.set_no_signal(true)
			_refresh_hud()
			if hud:
				hud.show_message("CHAPTER 3 // Inside UC — USB in locker wing (Ground). Check Floor 8 elevator.", 6.0)
		_:
			start(1)


func _start_horror_playthrough() -> void:
	is_horror_mode = true
	chapter = 0
	is_night = true
	day_night_changed.emit(true)
	chapter_changed.emit(0, "HORROR PLAYTHROUGH")
	_refresh_hud()
	if hud:
		hud.show_message(
			"23:15 // UC Banilad after dark. Flashlight on. Collect VHS tapes, barricade doors, hide when something hunts you.",
			7.0
		)


func refresh_objective() -> void:
	_refresh_hud()


func get_chapter_title() -> String:
	if is_horror_mode:
		return "HORROR PLAYTHROUGH"
	return CHAPTER_TITLES.get(chapter, "UCB INDAY")


func get_objective_text() -> String:
	if is_horror_mode:
		var tapes := 0
		if vhs_system != null and vhs_system.has_method("tape_count"):
			tapes = int(vhs_system.tape_count())
		return "HORROR  SURVIVE UC BANILAD\nVHS tapes %d / 6  ·  Tab phone  ·  F flashlight\nStay quiet — noise draws it" % tapes
	match chapter:
		1:
			var done := _count_true(_day_tasks)
			if done < 2:
				var next_hint := _next_day_hint()
				return "CH 1  DAY ERRANDS  %02d / 02\n%s" % [done, next_hint]
			return "CH 1  HEAD HOME\nContinue south along UC · Toward residential houses"
		2:
			var done := _count_true(_night_checks)
			var next_hint := _next_night_hint()
			return "CH 2  NIGHT RETURN  %02d / 03\n%s" % [done, next_hint]
		3:
			var done := _count_true(_ch3_steps)
			var next_hint := _next_ch3_hint()
			return "CH 3  INSIDE UC  %02d / 03\n%s" % [done, next_hint]
		_:
			return "UCB INDAY"


func on_floor_entered(floor: int) -> void:
	if is_horror_mode:
		return
	if chapter == 1 and floor == 3:
		_send_sms("Classmate", "Naa koy nabilin sa 5F, pwede kuha?")
	if chapter == 2 and floor >= 1:
		_send_sms("Unknown", "Ayaw gamita ang elevator.")


func on_creature_spotted() -> void:
	if is_horror_mode:
		return
	if chapter == 2:
		_send_sms("Unknown", "Nakadungog ka?")


func _send_sms(sender: String, body: String) -> void:
	var message_id := sender + "|" + body
	if _sent_sms.has(message_id):
		return
	_sent_sms[message_id] = true
	if phone_ui != null and phone_ui.has_method("receive_sms"):
		phone_ui.receive_sms(sender, body)


func _next_day_hint() -> String:
	if not _day_tasks[&"day_locker"]:
		return "NEXT: Locker · GF · School front (exterior, left of gate)"
	if not _day_tasks[&"day_registrar"]:
		return "NEXT: Registrar · GF · Room 102 (guard post, south wing)"
	return "NEXT: Head home · Leave UC · Continue south"


func _next_night_hint() -> String:
	if not _night_checks[&"fuse_box"]:
		return "NEXT: Fuse box · GF · South facade (left of main entrance)"
	if not _night_checks[&"payphone"]:
		return "NEXT: Payphone · Street · East side, near Banilad flyover"
	if not _night_checks[&"dead_tree"]:
		return "NEXT: Dead tree · Campus · West tree line (near houses)"
	return "NEXT: Enter UC · GF lobby · Retrieve your %s" % _item_name


func _next_ch3_hint() -> String:
	if not _ch3_steps[&"ch3_bag"]:
		return "NEXT: USB · GF · Locker wing (school front, same locker)"
	if not _ch3_steps[&"ch3_note"]:
		return "NEXT: Hallway note · 2F · South corridor (near Room 202)"
	if not _ch3_steps[&"ch3_elevator"]:
		return "NEXT: Elevator · GF · Lobby core (display stuck on 8F)"
	return "NEXT: Floor 8 · Someone is still upstairs"


func on_interactable(id: StringName, message: String) -> bool:
	if is_horror_mode:
		return false
	## Returns true if this interaction was consumed by the story system.
	match chapter:
		1:
			if _night_checks.has(id) or _ch3_steps.has(id):
				if hud:
					hud.show_message("Not now. Finish your errands while it's still light.", 3.5)
				return true
			return await _handle_chapter1(id, message)
		2:
			if _day_tasks.has(id):
				if hud:
					hud.show_message("That was this afternoon. Focus — find your %s." % _item_name, 3.5)
				return true
			if _ch3_steps.has(id):
				if hud:
					hud.show_message("Mang Berting wants the three checks finished first.", 3.5)
				return true
			return await _handle_chapter2(id, message)
		3:
			if _day_tasks.has(id):
				return true
			if _night_checks.has(id):
				if hud:
					hud.show_message("Already checked. Go inside for the USB.", 3.0)
				return true
			return await _handle_chapter3(id, message)
	return false


func tick(_delta: float) -> void:
	if is_horror_mode:
		return
	if chapter != 1 or _home_triggered or not _home_zone_ready:
		return
	if player == null:
		return
	# Gaisano is optional exploration across the road; only the far-south exit
	# beyond UC means the player is taking the residential route home.
	if player.global_position.z > 70.0:
		_trigger_forgot_item()


func _handle_chapter1(id: StringName, message: String) -> bool:
	if not _day_tasks.has(id):
		return false
	if _day_tasks[id]:
		return true
	_day_tasks[id] = true
	if hud:
		hud.show_message(message, 5.0)
	_refresh_hud()
	var done := _count_true(_day_tasks)
	if done == 1 and hud:
		await get_tree().create_timer(5.2).timeout
		hud.show_message("Last errand: Guard post GF-102 (south wing, ground floor). Then leave UC toward the residential route.", 4.5)
	elif done >= 2:
		_home_zone_ready = true
		_refresh_hud()
		if hud:
			await get_tree().create_timer(5.2).timeout
			hud.show_message("Errands done. Leave the UC grounds and continue south toward home.", 5.5)
	return true


func _trigger_forgot_item() -> void:
	_home_triggered = true
	if hud:
		hud.show_message("Wait— your %s. You left it in the locker wing." % _item_name, 5.0)
	await get_tree().create_timer(5.5).timeout
	_begin_chapter2()


func _begin_chapter2() -> void:
	chapter = 2
	is_night = true
	day_night_changed.emit(true)
	chapter_changed.emit(2, CHAPTER_TITLES[2])
	_send_sms("Unknown", "Ayaw pag balik.")
	_refresh_hud()
	if hud:
		hud.show_message("19:48 // Night fell while you walked. Turn back toward UC Banilad.", 6.0)
	await get_tree().create_timer(6.5).timeout
	if hud:
		hud.show_message("MANG BERTING: Ay, estudyante. Night audit — fuse box (school front), payphone (flyover), dead tree (west). Then inside for your USB.", 7.0)


func _handle_chapter2(id: StringName, message: String) -> bool:
	if id == &"caretaker":
		if hud:
			hud.show_message(message, 6.0)
		return true
	if not _night_checks.has(id):
		return false
	if _night_checks[id]:
		return true
	_night_checks[id] = true
	if hud:
		hud.show_message(message, 5.0)
	if scare_manager and scare_manager.has_method("on_inspection_complete"):
		scare_manager.on_inspection_complete(_count_true(_night_checks))
	_refresh_hud()
	if _count_true(_night_checks) >= 3:
		await get_tree().create_timer(5.5).timeout
		_begin_chapter3()
	return true


func _begin_chapter3() -> void:
	chapter = 3
	chapter_changed.emit(3, CHAPTER_TITLES[3])
	if phone_ui != null and phone_ui.has_method("set_no_signal"):
		phone_ui.set_no_signal(true)
	_refresh_hud()
	if hud:
		hud.show_message("The building lights stutter. Your %s is still inside." % _item_name, 5.5)
	await get_tree().create_timer(5.8).timeout
	if hud:
		hud.show_message("Enter UC Ground / Lobby. USB is in the locker wing (Ground). Watch Floor 8 on the elevator.", 6.0)


func _handle_chapter3(id: StringName, message: String) -> bool:
	if not _ch3_steps.has(id):
		return false
	if _ch3_steps[id]:
		return true
	_ch3_steps[id] = true
	if hud:
		hud.show_message(message, 6.0)
	_refresh_hud()
	if scare_manager and scare_manager.has_method("on_inspection_complete"):
		# Reuse tension bump without advancing night-check count semantics
		scare_manager.call("_add_tension", 0.28)
	var done := _count_true(_ch3_steps)
	if done == 2 and hud:
		await get_tree().create_timer(6.2).timeout
		hud.show_message("Footsteps above you. Same tempo as the elevator indicator.", 5.0)
	elif done >= 3:
		await get_tree().create_timer(6.5).timeout
		_finish_story()
	return true


func _finish_story() -> void:
	if hud:
		hud.show_message("You have the %s. The screen still blinks 8. Someone is still upstairs." % _item_name, 7.0)
	await get_tree().create_timer(7.5).timeout
	if hud:
		var tapes_found: int = int(vhs_system.tape_count()) if vhs_system != null and vhs_system.has_method("tape_count") else 0
		if tapes_found <= 2:
			hud.show_message("BAD ENDING // You escaped, but the footage explains nothing. Floor 8 is still calling.", 8.0)
		elif tapes_found <= 4:
			hud.show_message("NORMAL ENDING // You piece together part of Inday's story from %d tapes." % tapes_found, 8.0)
		else:
			hud.show_message("TRUE ENDING // All six tapes reveal what was buried beneath UC Banilad.", 8.0)
	story_complete.emit()
	_refresh_hud()


func get_active_quest_id() -> StringName:
	if is_horror_mode:
		return &""
	match chapter:
		1:
			for quest_id: StringName in [&"day_locker", &"day_registrar"]:
				if not _day_tasks[quest_id]:
					return quest_id
		2:
			for quest_id: StringName in [&"fuse_box", &"payphone", &"dead_tree"]:
				if not _night_checks[quest_id]:
					return quest_id
		3:
			for quest_id: StringName in [&"ch3_bag", &"ch3_note", &"ch3_elevator"]:
				if not _ch3_steps[quest_id]:
					return quest_id
	return &""


func _refresh_hud() -> void:
	objective_changed.emit(get_objective_text())
	if hud and hud.has_method("set_chapter_objective"):
		hud.set_chapter_objective(get_objective_text())


func _count_true(dict: Dictionary) -> int:
	var n := 0
	for key in dict.keys():
		if dict[key]:
			n += 1
	return n
