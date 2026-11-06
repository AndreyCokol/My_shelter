extends SceneTree
func _initialize() -> void:
	var art = load("res://game/ui/asset_theme.gd")
	if art == null:
		push_error("Missing exported asset theme")
		quit(1)
		return
	for role in art.ROLES:
		var texture = art.texture(role)
		if texture == null or texture.get_size() != Vector2(32,32):
			push_error("Missing exported texture: " + role)
			quit(1)
			return
	print("EXPORTED ASSETS: 18 Kibyra textures verified PASS")
	quit()
