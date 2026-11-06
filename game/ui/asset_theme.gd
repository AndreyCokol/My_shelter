extends RefCounted

const ROOT = "res://game/assets/vendor/kibyra_ui/"
const ROLES = ["button_frame", "focus_frame", "panel_frame", "heart", "coin", "inventory", "sword", "quests", "menu", "farm", "rest", "residents", "save", "shelter", "hero_xp", "shelter_xp", "back", "accept"]
const PANEL_ICONS = {"welcome": "shelter", "menu": "menu", "inventory": "inventory", "farm": "farm", "rest": "rest", "residents": "residents", "quests": "quests", "shop": "coin", "save": "save", "new_confirm": "back", "credits": "shelter"}
static var _textures: Dictionary = {}

static func texture(role: String) -> Texture2D:
	if not role in ROLES:
		return null
	# Cache present resources only. Missing art stays a quiet source-checkout fallback.
	if _textures.has(role):
		return _textures[role]
	var path := ROOT + role + ".png"
	if not ResourceLoader.exists(path):
		return null
	var loaded = load(path)
	if loaded is Texture2D:
		_textures[role] = loaded
		return loaded
	return null

static func icon(panel: String) -> Texture2D:
	return texture(PANEL_ICONS.get(panel, ""))

static func textured_style(role: String, inset: float, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var image := texture(role)
	if image == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = image
	style.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, inset)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

static func apply_buttons(theme: Theme) -> bool:
	var normal := textured_style("button_frame", 8)
	if normal == null:
		return false
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", textured_style("button_frame", 8, Color(1.35, 1.25, 1.05)))
	theme.set_stylebox("pressed", "Button", textured_style("button_frame", 8, Color(0.85, 0.80, 0.70)))
	theme.set_stylebox("disabled", "Button", textured_style("button_frame", 8, Color(0.5, 0.5, 0.5)))
	theme.set_stylebox("focus", "Button", textured_style("focus_frame", 8))
	theme.set_color("font_color", "Button", Color("f4e5bd"))
	theme.set_color("font_hover_color", "Button", Color("fff3ce"))
	theme.set_constant("icon_max_width", "Button", 16)
	theme.set_constant("h_separation", "Button", 5)
	return true
