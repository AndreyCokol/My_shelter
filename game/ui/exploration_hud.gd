extends Control

signal panel_requested(id: String)
signal slot_requested(index: int)

const SHEET = preload("res://game/assets/project/hud/night_hud.png")
const TITLE = Rect2(0, 0, 526, 57)
const PORTRAIT = Rect2(0, 59, 131, 106)
const HEART = Rect2(134, 59, 43, 42)
const DODGE = Rect2(179, 59, 42, 43)
const QUEST = Rect2(223, 59, 39, 37)
const BACKPACK = Rect2(265, 59, 55, 56)
const NAV = [
	["inventory", Rect2(0, 166, 175, 56), "Рюкзак [I]"],
	["map", Rect2(180, 166, 134, 56), "Карта [M]"],
	["journal", Rect2(316, 166, 152, 56), "Журнал [J]"],
	["workshop", Rect2(471, 166, 153, 56), "Ремесло [K]"],
]
const INK = Color("f3e4c1")
const GOLD = Color("a48158")
const SHADOW = Color("403024")
const FILL = Color("181511")
const MAP_AREA = Rect2(8, 11, 80, 73)

var app
var items: Array[Dictionary] = []
var location_text := ""
var objective := ""
var tracked_exit := ""
var health := 100
var dodge_charge := 1.0
var load_units := 0
var capacity := 0
var hero_xp := 0
var coins := 0
var shelter_xp := 0
var zoom := 1.0
var map_node: Control
var hotbar: Control
var navigation: Control
var slots: Array[Button] = []
var zoom_in: Button
var zoom_out: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	resized.connect(_layout)
	map_node = _section("Minimap", Vector2(96, 93), _draw_map)
	var full_map := _hitbox(map_node, Rect2(4, 5, 88, 83), "Открыть карту [M]", panel_requested.emit.bind("map"))
	full_map.name = "OpenMap"
	zoom_in = _zoom_button("+", 55, 0.5)
	zoom_out = _zoom_button("−", 71, -0.5)
	zoom_out.disabled = true
	hotbar = _section("QuickSlots", Vector2(152, 37), _draw_hotbar)
	for index in range(4):
		var slot := _hitbox(hotbar, Rect2(index * 38, 0, 36, 36), "", slot_requested.emit.bind(index))
		slot.name = "QuickSlot%d" % (index + 1)
		slot.disabled = true
		slot.mouse_entered.connect(hotbar.queue_redraw)
		slot.mouse_exited.connect(hotbar.queue_redraw)
		slots.append(slot)
	navigation = _section("Shortcuts", Vector2(238, 22), _draw_navigation)
	var left := 0.0
	for entry in NAV:
		var width: float = entry[1].size.x * 0.38
		var target := _hitbox(navigation, Rect2(left, 0, width, 22), entry[2], panel_requested.emit.bind(entry[0]))
		target.name = entry[0]
		target.mouse_entered.connect(navigation.queue_redraw)
		target.mouse_exited.connect(navigation.queue_redraw)
		left += width + 1.5
	var quest := _hitbox(self, Rect2(8, 78, 188, 57), "Задания [Tab]", panel_requested.emit.bind("quests"))
	quest.name = "QuestTracker"
	_layout()


func _section(id: String, dimensions: Vector2, paint: Callable) -> Control:
	var section := Control.new()
	section.name = id
	section.size = dimensions
	section.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(section)
	section.draw.connect(paint)
	return section


func _hitbox(parent: Control, area: Rect2, hint: String, action: Callable) -> Button:
	var target := Button.new()
	var transparent := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled"]:
		target.add_theme_stylebox_override(state, transparent)
	target.focus_mode = FOCUS_NONE
	target.position = area.position
	target.size = area.size
	target.tooltip_text = hint
	target.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	target.pressed.connect(action)
	parent.add_child(target)
	return target


func _zoom_button(caption: String, y: float, step: float) -> Button:
	var target := _hitbox(map_node, Rect2(74, y, 14, 14), "Масштаб мини-карты", _change_zoom.bind(step))
	target.text = caption
	target.add_theme_font_size_override("font_size", 10)
	target.add_theme_color_override("font_color", INK)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = SHADOW if state == "hover" else FILL
		style.border_color = SHADOW if state == "disabled" else GOLD
		style.set_border_width_all(1)
		style.set_corner_radius_all(2)
		target.add_theme_stylebox_override(state, style)
	return target


func _change_zoom(step: float) -> void:
	zoom = clampf(zoom + step, 1.0, 3.0)
	zoom_in.disabled = zoom >= 3.0
	zoom_out.disabled = zoom <= 1.0
	map_node.queue_redraw()


func _layout() -> void:
	if map_node == null or navigation == null:
		return
	map_node.position = Vector2(size.x - map_node.size.x - 7, 7)
	hotbar.position = Vector2(8, size.y - hotbar.size.y - 19)
	navigation.position = Vector2(size.x - navigation.size.x - 8, size.y - navigation.size.y - 27)


func update_state(state: Dictionary, carried: Array[Dictionary], place: String, quest: String, exit_id: String) -> void:
	items = carried
	location_text = place
	objective = quest
	tracked_exit = exit_id
	health = app.hero.health
	dodge_charge = app.hero.dodge_readiness()
	hero_xp = state.player.xp
	shelter_xp = state.shelter.xp
	coins = state.wallet.system_coins
	load_units = 0
	capacity = 0
	for item in items:
		load_units += int(item.quantity)
	for container in state.inventory.containers:
		if container.id == "player":
			capacity = int(container.capacity_units)
			break
	for index in range(slots.size()):
		var enabled := index < items.size()
		slots[index].disabled = not enabled
		slots[index].tooltip_text = items[index].label if enabled else ""
	queue_redraw()
	map_node.queue_redraw()
	hotbar.queue_redraw()


func _draw() -> void:
	# 640x360 PC-layout anchored to the four approved 1672x941 mockups.
	# Location label is informational; G remains the actual shelter control.
	draw_texture_rect_region(SHEET, Rect2(6, 4, 178, 19), TITLE)
	frame(self, Rect2(7, 23, 46, 48))
	draw_texture_rect_region(SHEET, Rect2(7, 24, 44, 39), PORTRAIT)
	caption(self, Vector2(11, 69), "%d XP" % hero_xp, 9)
	draw_texture_rect_region(SHEET, Rect2(56, 25, 14, 14), HEART)
	draw_texture_rect_region(SHEET, Rect2(56, 40, 14, 14), DODGE)
	draw_texture_rect_region(SHEET, Rect2(57, 55, 13, 13), BACKPACK)
	_bar(Rect2(71, 25, 96, 13), health / 100.0, Color("a72918"), "%d / 100" % health)
	_bar(Rect2(71, 40, 96, 13), dodge_charge, Color("c77c16"),
		"Уклон. %d%%" % roundi(dodge_charge * 100))
	var load_ratio := float(load_units) / maxi(capacity, 1)
	_bar(Rect2(71, 55, 96, 13), load_ratio, Color("486a59"), "%d / %d" % [load_units, capacity])
	frame(self, Rect2(173, 25, 131, 45))
	caption(self, Vector2(180, 38), "Опыт: %d" % hero_xp, 9)
	caption(self, Vector2(180, 51), "Монеты: %d" % coins, 9)
	caption(self, Vector2(180, 64), "Убежище: %d XP" % shelter_xp, 9)

	# The upper-center label is deliberately independent from the G shortcut.
	frame(self, Rect2(192, 4, 212, 19))
	draw_string(ThemeDB.fallback_font, Vector2(196, 17),
		location_text, HORIZONTAL_ALIGNMENT_CENTER, 204, 10, INK)

	frame(self, Rect2(7, 78, 128, 17))
	draw_texture_rect_region(SHEET, Rect2(10, 79, 14, 14), QUEST)
	caption(self, Vector2(28, 91), "Текущее задание", 10, Color("f5cc4d"))
	frame(self, Rect2(8, 96, 188, 39))
	caption(self, Vector2(14, 111), objective, 10)
	caption(self, Vector2(14, 126), tracked_exit if not tracked_exit.is_empty()
		else "E — взаимодействие · G — убежище", 8, Color("b8b9a8"))

	# Actual PC bindings, not the Ctrl=run/Tab=radial mistake in concept art.
	frame(self, Rect2(6, size.y - 19, size.x - 12, 18))
	caption(self, Vector2(12, size.y - 7), "WASD Движение", 9)
	caption(self, Vector2(117, size.y - 7), "ЛКМ Атака", 9)
	caption(self, Vector2(210, size.y - 7), "E Действие", 9)
	caption(self, Vector2(290, size.y - 7), "Space Уклонение", 9)
	caption(self, Vector2(416, size.y - 7), "Левый Ctrl Меню", 9)
	caption(self, Vector2(551, size.y - 7), "G Убежище", 9)


func _bar(rect: Rect2, ratio: float, tint: Color, value: String) -> void:
	frame(self, rect)
	var inner := rect.grow(-3)
	inner.size.x *= clampf(ratio, 0, 1)
	draw_rect(inner, tint)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	caption(self, Vector2(rect.end.x - width - 5, rect.position.y + 10), value, 9)


func _draw_map() -> void:
	frame(map_node, Rect2(0, 3, 96, 89))
	map_node.draw_rect(MAP_AREA, Color("121510"))
	var world = app.scene_router.current_world()
	if not is_instance_valid(world):
		return
	var floor: Rect2 = world.floor_rect()
	var map_scale := minf(MAP_AREA.size.x / floor.size.x, MAP_AREA.size.y / floor.size.y) * zoom
	var hero_pos: Vector2 = app.hero.position
	var center := floor.get_center().lerp(hero_pos, (zoom - 1.0) / 2.0)
	var origin := MAP_AREA.get_center() - center * map_scale
	_map_shape(floor, origin, map_scale, Color("333a29"))
	for rect in world.layout.get("roadways", world.layout.get("rooms", [])):
		_map_shape(rect, origin, map_scale, Color("505642"))
	if world.layout.has("floor_plan"):
		for room in world.layout.floor_plan.rooms.values():
			_map_shape(room.rect, origin, map_scale, Color("505642"))
	for rect in world.layout.get("obstacles", []):
		_map_shape(rect, origin, map_scale, Color("1a1e17"))
	for portal in world.portals:
		var point: Vector2 = portal.position * map_scale + origin
		if not MAP_AREA.grow(-2).has_point(point):
			continue
		var active: bool = portal.to == tracked_exit
		var marker := Rect2(point - Vector2.ONE * 2.0, Vector2.ONE * 4.0)
		map_node.draw_rect(marker, Color("f4cf55") if active else Color("b5a07a"), not active)
	var here := (hero_pos * map_scale + origin).clamp(MAP_AREA.position + Vector2.ONE * 4, MAP_AREA.end - Vector2.ONE * 4)
	var facing: Vector2 = app.hero.facing
	var arrow := PackedVector2Array([here + facing * 5, here - facing * 3 + facing.orthogonal() * 3, here - facing * 3 - facing.orthogonal() * 3])
	map_node.draw_colored_polygon(arrow, INK)
	for corner in [Vector2(9, 12), Vector2(87, 12), Vector2(9, 83), Vector2(87, 83)]:
		var horizontal := 1 if corner.x < 48 else -1
		var vertical := 1 if corner.y < 46 else -1
		map_node.draw_line(corner, corner + Vector2(horizontal * 5, 0), INK)
		map_node.draw_line(corner, corner + Vector2(0, vertical * 5), INK)
	caption(map_node, Vector2(44, 10), "N", 12)


func _map_shape(rect: Rect2, origin: Vector2, map_scale: float, tint: Color) -> void:
	var mapped := Rect2(origin + rect.position * map_scale, rect.size * map_scale).intersection(MAP_AREA)
	if mapped.has_area():
		map_node.draw_rect(mapped, tint)


func _draw_hotbar() -> void:
	for index in range(slots.size()):
		var x := float(index * 38)
		var accent := Color("f1c478") if slots[index].is_hovered() and not slots[index].disabled else GOLD
		frame(hotbar, Rect2(x, 0, 36, 36), accent)
		frame(hotbar, Rect2(x + 2, 2, 11, 11))
		caption(hotbar, Vector2(x + 5, 11), str(index + 1), 9)
		if index < items.size():
			hotbar.draw_texture_rect(items[index].icon, Rect2(x + 10, 5, 22, 22), false)
			caption(hotbar, Vector2(x + 21, 32), str(items[index].quantity), 9)


func _draw_navigation() -> void:
	var left := 0.0
	for entry in NAV:
		var width: float = entry[1].size.x * 0.38
		var button := navigation.get_node(NodePath(entry[0])) as Button
		var tint := Color(1.2, 1.13, 1.05) if button.is_hovered() else Color.WHITE
		navigation.draw_texture_rect_region(SHEET, Rect2(left, 0, width, 22), entry[1], tint)
		left += width + 1.5


static func frame(canvas: Control, area: Rect2, accent: Color = GOLD) -> void:
	var points := bevel(area, 3.0)
	canvas.draw_colored_polygon(points, FILL)
	points.append(points[0])
	canvas.draw_polyline(points, SHADOW, 2)
	var inner := bevel(area.grow(-1.5), 2.0)
	inner.append(inner[0])
	canvas.draw_polyline(inner, accent, 1)


static func bevel(area: Rect2, inset: float) -> PackedVector2Array:
	var a := area.position
	var b := area.end
	return PackedVector2Array([
		Vector2(a.x + inset, a.y), Vector2(b.x - inset, a.y), Vector2(b.x, a.y + inset),
		Vector2(b.x, b.y - inset), Vector2(b.x - inset, b.y), Vector2(a.x + inset, b.y),
		Vector2(a.x, b.y - inset), Vector2(a.x, a.y + inset),
	])


static func caption(canvas: Control, point: Vector2, value: String, font_size: int, tint: Color = INK) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string_outline(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color("14100d"))
	canvas.draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
