extends StaticBody3D
## Collision + raycast target for UcKioskNpc (interaction and melee).


func get_interaction_prompt() -> String:
	var host := get_parent()
	if host != null and host.has_method("get_interaction_prompt"):
		return host.get_interaction_prompt()
	return ""


func interact(player: Node) -> void:
	var host := get_parent()
	if host != null and host.has_method("npc_interact"):
		host.npc_interact(player)


func take_hit(amount: float = 1.0, from: Node3D = null) -> void:
	var host := get_parent()
	if host != null and host.has_method("take_hit"):
		host.take_hit(amount, from)
