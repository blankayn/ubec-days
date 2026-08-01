extends CanvasLayer
class_name PhoneUI

## Nokia-inspired SMS inbox. The player injects itself so opening this UI pauses movement.

var player: Node = null
var _overlay: ColorRect
var _inbox: RichTextLabel
var _status: Label
var _messages: Array[Dictionary] = []
var _no_signal := false


func _ready() -> void:
	layer = 30
	_build_ui()


func receive_sms(sender: String, body: String) -> void:
	_messages.append({"sender": sender, "body": body})
	_refresh_inbox()
	if _overlay.visible:
		_status.text = "NEW MESSAGE"


func set_no_signal(enabled: bool) -> void:
	_no_signal = enabled
	_refresh_inbox()


func toggle() -> void:
	if _overlay.visible:
		close()
	else:
		open()


func open() -> void:
	_overlay.visible = true
	_refresh_inbox()
	if player != null and player.has_method("set_phone_open"):
		player.set_phone_open(true)


func close() -> void:
	_overlay.visible = false
	if player != null and player.has_method("set_phone_open"):
		player.set_phone_open(false)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.0, 0.0, 0.0, 0.82)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var shell := PanelContainer.new()
	shell.custom_minimum_size = Vector2(560, 670)
	var shell_style := StyleBoxFlat.new()
	shell_style.bg_color = Color("202b24")
	shell_style.border_color = Color("96a79a")
	shell_style.set_border_width_all(10)
	shell_style.set_corner_radius_all(30)
	shell_style.content_margin_left = 28
	shell_style.content_margin_right = 28
	shell_style.content_margin_top = 34
	shell_style.content_margin_bottom = 28
	shell.add_theme_stylebox_override("panel", shell_style)
	center.add_child(shell)
	var screen := VBoxContainer.new()
	screen.add_theme_constant_override("separation", 12)
	shell.add_child(screen)
	var header := Label.new()
	header.text = "SMART 3G                         12:45"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color("4cff73"))
	screen.add_child(header)
	var rule := HSeparator.new()
	rule.modulate = Color("4cff73")
	screen.add_child(rule)
	_status = Label.new()
	_status.text = "INBOX (0)"
	_status.add_theme_font_size_override("font_size", 24)
	_status.add_theme_color_override("font_color", Color("4cff73"))
	screen.add_child(_status)
	_inbox = RichTextLabel.new()
	_inbox.bbcode_enabled = true
	_inbox.fit_content = false
	_inbox.custom_minimum_size = Vector2(490, 420)
	_inbox.add_theme_font_size_override("normal_font_size", 19)
	_inbox.add_theme_color_override("default_color", Color("61ff87"))
	_inbox.add_theme_color_override("font_outline_color", Color("07160b"))
	_inbox.add_theme_constant_override("outline_size", 3)
	screen.add_child(_inbox)
	var close_button := Button.new()
	close_button.text = "BACK  [TAB]"
	close_button.custom_minimum_size = Vector2(180, 44)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	screen.add_child(close_button)
	_overlay.visible = false


func _refresh_inbox() -> void:
	if _status == null:
		return
	if _no_signal:
		_status.text = "NO SIGNAL"
		_inbox.text = "[center]...static...\n\nMessages cannot be sent.[/center]"
		return
	_status.text = "INBOX (%d)" % _messages.size()
	var lines: Array[String] = []
	for message in _messages:
		lines.append("[b]> %s[/b]\n%s\n" % [message["sender"], message["body"]])
	_inbox.text = "\n".join(lines) if not lines.is_empty() else "No messages."
