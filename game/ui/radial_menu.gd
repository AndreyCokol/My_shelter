extends Control

signal chosen(index: int)
signal cancelled

const HUD = preload("res://game/ui/exploration_hud.gd")
const SEGMENTS := 5
const BACKPACK_SLOT := -1
const NO_SLOT := -2
const RADIUS := 58.0
const HUB_RADIUS := 20.0
const ARC := TAU / SEGMENTS
const GAP := 0.045

var items: Array[Dictionary] = []
var highlighted := NO_SLOT
var _left_pressed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	mouse_exited.connect(_highlight.bind(NO_SLOT))
	resized.connect(queue_redraw)
	hide()


func reveal(carried: Array[Dictionary]) -> void:
	items = carried
	_left_pressed = false
	_highlight(NO_SLOT)
	show()
	queue_redraw()


# PC design viewport 640x360: keep the wheel to the right of the
# shelter construction grid rather than covering its cells and [E] action.
# Reserve the upper-right for the minimap and the lower-right for navigation.
# The wheel and its caption remain viewport-relative at 1280x720 / 1920x1080.
func wheel_center() -> Vector2:
	return Vector2(size.x * 0.74, size.y * 0.64).round()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_highlight(_slot_at(event.position - wheel_center()))
	elif event is InputEventMouseButton:
		accept_event()
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancelled.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed or not _left_pressed:
				_left_pressed = event.pressed
				return
			_left_pressed = false
			var selected := _slot_at(event.position - wheel_center())
			if selected == NO_SLOT:
				cancelled.emit()
			elif selected < items.size():
				chosen.emit(selected)


func _slot_at(offset: Vector2) -> int:
	var distance := offset.length()
	if distance < HUB_RADIUS:
		return BACKPACK_SLOT
	if distance > RADIUS:
		return NO_SLOT
	var angle := fposmod(offset.angle() + PI / 2 + ARC / 2, TAU)
	if absf(fposmod(angle, ARC) - ARC / 2) > ARC / 2 - GAP:
		return NO_SLOT
	return int(angle / ARC)


func _highlight(slot: int) -> void:
	highlighted = slot
	queue_redraw()


func _draw() -> void:
	var center := wheel_center()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.28))
	for index in range(SEGMENTS):
		var angle := -PI / 2 + index * ARC
		var start := angle - ARC / 2 + GAP
		var finish := angle + ARC / 2 - GAP
		var rim := PackedVector2Array()
		for point in range(13):
			rim.append(center + Vector2.from_angle(lerpf(start, finish, point / 12.0)) * RADIUS)
		for point in range(12, -1, -1):
			rim.append(center + Vector2.from_angle(lerpf(start, finish, point / 12.0)) * (HUB_RADIUS + 1))
		var active := highlighted == index and index < items.size()
		draw_colored_polygon(rim, Color("4b361b") if active else Color("201b16"))
		rim.append(rim[0])
		draw_polyline(rim, HUD.SHADOW, 3)
		draw_polyline(rim, HUD.GOLD, 1)
		if active:
			draw_arc(center, RADIUS - 2, start + 0.04, finish - 0.04, 16, Color("f3c946"), 2)
		var item_center := center + Vector2.from_angle(angle) * 40
		if index < items.size():
			draw_texture_rect(items[index].icon, Rect2(item_center - Vector2(10, 11), Vector2(20, 20)), false)
			HUD.caption(self, item_center + Vector2(7, 13), str(items[index].quantity), 9)
		else:
			HUD.caption(self, item_center + Vector2(-3, 3), "·", 13, HUD.GOLD)
	draw_circle(center, HUB_RADIUS, HUD.SHADOW)
	draw_circle(center, HUB_RADIUS - 1, HUD.GOLD if highlighted == BACKPACK_SLOT else HUD.FILL)
	draw_texture_rect_region(HUD.SHEET, Rect2(center - Vector2(11, 11), Vector2(22, 22)), HUD.BACKPACK)
	var caption := "Левый Ctrl — закрыть"
	if highlighted == BACKPACK_SLOT:
		caption = "Рюкзак"
	elif highlighted >= 0 and highlighted < items.size():
		caption = items[highlighted].label
	var width := ThemeDB.fallback_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	HUD.caption(self, center + Vector2(-width / 2, -RADIUS - 7), caption, 10)
