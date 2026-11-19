extends CanvasLayer
## A5 only: visual labels for an isolated A2-08 dual-view prototype.
## This is NOT the game's production HUD or a change to the Apple/PC UI kit.

var mode_label: Label
var help_label: Label
var crosshair: Label

func _ready() -> void:
	_build()
	show_view(false)

func _build() -> void:
	var backdrop := PanelContainer.new()
	backdrop.name = "ModeHelpPanel"
	backdrop.position = Vector2(18, 18)
	backdrop.custom_minimum_size = Vector2(390, 116)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("16252c")
	style.border_color = Color("9db2b1")
	style.border_width_left = 3
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	backdrop.add_theme_stylebox_override("panel", style)
	add_child(backdrop)

	var padding := MarginContainer.new()
	padding.add_theme_constant_override("margin_left", 18)
	padding.add_theme_constant_override("margin_top", 12)
	padding.add_theme_constant_override("margin_right", 18)
	padding.add_theme_constant_override("margin_bottom", 12)
	backdrop.add_child(padding)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	padding.add_child(stack)

	var caption := Label.new()
	caption.name = "Caption"
	caption.text = "A2 / A5   ДВЕ КАМЕРЫ · ОДИН МИР"
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", Color("a1b6b3"))
	stack.add_child(caption)

	mode_label = Label.new()
	mode_label.name = "Mode"
	mode_label.add_theme_font_size_override("font_size", 20)
	mode_label.add_theme_color_override("font_color", Color("e4e8df"))
	stack.add_child(mode_label)

	help_label = Label.new()
	help_label.name = "Controls"
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.add_theme_color_override("font_color", Color("b9c6c4"))
	stack.add_child(help_label)

	crosshair = Label.new()
	crosshair.name = "FirstPersonCrosshair"
	crosshair.text = "+"
	crosshair.custom_minimum_size = Vector2(32, 32)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 25)
	crosshair.add_theme_color_override("font_color", Color("f3e6c6"))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crosshair)

func show_view(first_person: bool) -> void:
	if not is_instance_valid(mode_label):
		return
	mode_label.text = "ПЕРВОЕ ЛИЦО" if first_person else "ВИД СВЕРХУ · 90°"
	help_label.text = "WASD · движение    Caps Lock · камера    Мышь · обзор    Esc · курсор    ЛКМ · проверка стены" if first_person else "WASD / стрелки · движение    Caps Lock · первое лицо    ЛКМ · проверка стены"
	crosshair.visible = first_person
