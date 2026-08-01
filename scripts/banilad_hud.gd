extends CanvasLayer
## Banilad HUD helper so NPC props can call show_message().

var _host: Node = null


func bind_host(host: Node) -> void:
	_host = host


func show_message(text: String, duration: float = 4.0) -> void:
	if _host != null and _host.has_method("_show_message"):
		_host.call("_show_message", text, duration)
