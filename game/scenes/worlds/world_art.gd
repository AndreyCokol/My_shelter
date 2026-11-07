extends RefCounted

const Plans = preload("res://game/systems/world/building_plan.gd")
const ROOT = "res://game/assets/project/world/"
const HOSPITAL = ["hospital_teal", "hospital_beige", "hospital_blue", "hospital_blue"]
const HOMES = ["parquet", "linoleum", "ceramic", "concrete"]
const COLD := Color("9aa9b5")
const DIM := Color("788895")
const WARM := Color("fff2d4")
static var textures := {}

static func texture(id: String) -> Texture2D:
	if not textures.has(id):
		textures[id] = load(ROOT + id + ".png")
	return textures[id]

static func tile(canvas: CanvasItem, id: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	canvas.draw_texture_rect(texture(id), rect, true, tint)

static func stamp(canvas: CanvasItem, id: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	canvas.draw_texture_rect(texture(id), rect, false, tint)

static func ground(canvas: CanvasItem, kind: String, variant: int, layout: Dictionary) -> void:
	var bounds: Rect2 = layout.get("bounds", Rect2(20, 85, 600, 260))
	if layout.has("floor_plan"):
		plan_ground(canvas, layout.floor_plan)
		return
	if layout.has("roadways"):
		street_ground(canvas, bounds, layout.roadways, layout.aprons, variant)
		return
	match kind:
		"hospital":
			tile(canvas, HOSPITAL[variant], bounds, DIM)
			stamp(canvas, "cracks", Rect2(328, 104 + 24 * variant, 86, 86), COLD)
		"house":
			tile(canvas, HOMES[variant], bounds, DIM)
		"outside":
			tile(canvas, "street_grass", bounds, DIM)
			tile(canvas, "pavement", Rect2(20, 215, 600, 120), COLD)
			tile(canvas, "asphalt_broken" if variant in [1, 2] else "asphalt", Rect2(20, 238, 600, 72), COLD)
			for y in [233, 305]:
				for x in range(20, 620, 60):
					stamp(canvas, "curb", Rect2(x, y - 9, 60, 18), COLD)
			if variant == 0:
				stamp(canvas, "crosswalk", Rect2(398, 239, 63, 69), COLD)
			elif variant == 3:
				for x in range(44, 576, 64):
					stamp(canvas, "road_dash", Rect2(x, 251, 52, 42), COLD)
			elif variant == 2:
				stamp(canvas, "weeds", Rect2(403, 159, 74, 74), COLD)
			stamp(canvas, "puddle", Rect2(167 + 38 * variant, 166, 56, 56), COLD)
		"shelter":
			tile(canvas, "grass", bounds, WARM)
			tile(canvas, "path", Rect2(20, 142, 600, 36), WARM)
			tile(canvas, "flowers", Rect2(448, 211, 157, 116), WARM)
		_:
			tile(canvas, "asphalt_broken", bounds, COLD)
			tile(canvas, "pavement", Rect2(117, 149, 411, 80), COLD)

	if layout.has("rooms"):
		room_ground(canvas, kind, layout.rooms, variant)

static func plan_ground(canvas: CanvasItem, plan: Dictionary) -> void:
	for room in plan.rooms.values():
		var surface := "parquet"
		if plan.kind == "hospital":
			surface = "hospital_blue" if room.kind in ["surgery", "lab", "prep"] else "hospital_teal"
		elif room.kind in ["lobby", "corridor", "storage"]:
			surface = "concrete"
		elif room.kind in ["living", "studio"]:
			surface = "linoleum"
		if room.kind == "bath":
			surface = "ceramic"
		tile(canvas, surface, room.rect, DIM)

static func plan_details(canvas: CanvasItem, plan: Dictionary) -> void:
	for item in plan.furniture:
		var rect: Rect2 = item.rect
		canvas.draw_rect(rect, Color("1f252a"))
		if item.kind in ["bedroom", "ward", "recovery"]:
			canvas.draw_rect(rect.grow(-2), Color("696870"))
			canvas.draw_rect(Rect2(rect.position + Vector2(4, 4), Vector2(rect.size.x - 8, 8)), Color("afb3b1"))
		else:
			tile(canvas, "wood" if plan.kind == "house" else "concrete", rect.grow(-2), DIM)
	for door in plan.doors:
		var point: Vector2 = door.position
		var size := Vector2(door.width, 10) if door.horizontal else Vector2(10, door.width)
		canvas.draw_rect(Rect2(point - size * 0.5, size), Color("686159"))
		if door.from == "corridor" and plan.rooms[door.to].kind == "foyer":
			var unit: Dictionary = plan.units[plan.rooms[door.to].unit]
			canvas.draw_string(ThemeDB.fallback_font, point + Vector2(-17, 4), "Кв. %d" % unit.number, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("eee0bb"))
	for room in plan.rooms.values():
		if room.kind == "foyer":
			continue
		var rect: Rect2 = room.rect
		var label: String = Plans.LABELS[room.kind]
		canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(9, 15), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 14, 10, Color("d9d7c5"))

static func room_ground(canvas: CanvasItem, kind: String, rooms: Array, variant: int) -> void:
	var materials: Array = []
	var tint := DIM
	match kind:
		"hospital":
			materials = [HOSPITAL[variant], "hospital_teal", "hospital_beige"]
		"house":
			materials = [HOMES[variant], "parquet", "ceramic"]
		"shelter":
			materials = ["wood", "path"]
			tint = WARM
		_:
			materials = ["pavement", "asphalt"]
	for index in range(rooms.size()):
		tile(canvas, materials[index], rooms[index], tint)

static func street_ground(canvas: CanvasItem, bounds: Rect2, roads: Array, aprons: Array, variant: int) -> void:
	tile(canvas, "street_grass", bounds, DIM)
	for rect in aprons:
		tile(canvas, "pavement", rect, COLD)
	for rect in roads:
		tile(canvas, "pavement", rect.grow(15).intersection(bounds), COLD)
	for rect in roads:
		tile(canvas, "asphalt_broken" if variant in [1, 2] else "asphalt", rect, COLD)
	for x in [576, 825, 1480, 1765]:
		stamp(canvas, "crosswalk", Rect2(x, 230, 44, 84), COLD)
	for x in [249, 967, 1888, 2248]:
		stamp(canvas, "road_dash", Rect2(x, 245, 72, 50), COLD)
	stamp(canvas, "weeds", Rect2(995, 600, 92, 92), COLD)
	stamp(canvas, "puddle", Rect2(1750 + 38 * variant, 455, 66, 66), COLD)

static func obstacle(canvas: CanvasItem, kind: String, rect: Rect2) -> void:
	var surface := "concrete"
	if kind == "hospital":
		surface = "hospital_wall"
	elif kind == "house":
		surface = "wallpaper"
	canvas.draw_rect(rect, Color("141a1d"))
	if rect.size.x > 4 and rect.size.y > 4:
		tile(canvas, surface, rect.grow(-2), DIM)
	canvas.draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("98a2a1"), 1)


static func facade(canvas: CanvasItem, rect: Rect2, kind: String) -> void:
	var front := Rect2(rect.position.x, rect.end.y - 22, rect.size.x, 22)
	tile(canvas, "hospital_wall" if kind == "hospital" else "concrete", front, COLD)
	canvas.draw_line(front.position, Vector2(front.end.x, front.position.y), Color("999487"), 2)
	var center := Vector2(rect.get_center().x, rect.end.y - 34)
	for offset in [-58, 58]:
		var window := Rect2(center + Vector2(offset - 11, 20), Vector2(22, 10))
		canvas.draw_rect(window, Color("1f2d32"))
		canvas.draw_rect(window, Color("718080"), false)
		canvas.draw_line(window.get_center() - Vector2(0, 4), window.get_center() + Vector2(0, 4), Color("586966"))
	if kind == "hospital":
		canvas.draw_rect(Rect2(center - Vector2(12, 10), Vector2(24, 20)), Color("525d61"))
		canvas.draw_rect(Rect2(center - Vector2(7, 2), Vector2(14, 4)), Color("e0c5b3"))
		canvas.draw_rect(Rect2(center - Vector2(2, 7), Vector2(4, 14)), Color("e0c5b3"))

static func exit_fixture(canvas: CanvasItem, portal: Dictionary, floor: Rect2, scene_kind: String, active: bool) -> void:
	var position: Vector2 = portal.position
	var inward: Vector2 = portal.get("inward", Vector2.UP)
	var form: String = portal.get("form", "door")
	var warm := scene_kind == "shelter"
	var edge := Color("ac8a5d") if warm else Color("829497")
	match form:
		"road":
			# Continue the same asphalt to the edge and mark the route with a roadside sign.
			var sign := Rect2(position + Vector2(18 if inward.x > 0 else -106, -35), Vector2(88, 17))
			canvas.draw_rect(sign, Color("35494b"))
			canvas.draw_rect(sign, edge, false)
			canvas.draw_string(ThemeDB.fallback_font, sign.position + Vector2(5, 12), portal.label, HORIZONTAL_ALIGNMENT_LEFT, 78, 10, Color("e4e6cf"))
		"gate":
			for y in [-32, 18]:
				canvas.draw_rect(Rect2(position + Vector2(-10, y), Vector2(20, 14)), Color("3e4546"))
				canvas.draw_line(position + Vector2(-10, y), position + Vector2(10, y), edge, 2)
		"stairs_up", "stairs_down":
			tile(canvas, "concrete", Rect2(position - Vector2(27, 24), Vector2(54, 48)), DIM)
			stamp(canvas, "stairs", Rect2(position - Vector2(21, 21), Vector2(42, 42)), COLD)
			var sign := "↑" if form == "stairs_up" else "↓"
			canvas.draw_string(ThemeDB.fallback_font, position + Vector2(25, -4), sign, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("eee5c6"))
		_:
			var door: Vector2 = portal.get("threshold", position - inward * 17)
			var rect := Rect2(door - Vector2(18, 13), Vector2(36, 26))
			canvas.draw_rect(rect.grow(3), Color("292626"))
			canvas.draw_rect(rect, edge)
			canvas.draw_rect(rect.grow(-3), Color("3f352c") if warm else Color("293638"))
			canvas.draw_rect(Rect2(door + Vector2(9, 0), Vector2(4, 3)), Color("ceb173"))
			stamp(canvas, "threshold", Rect2(position - Vector2(25, 12), Vector2(50, 24)), WARM if warm else COLD)
	if active:
		var text: String = "[E] " + portal.label
		var font := ThemeDB.fallback_font
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var x := clampf(position.x - width / 2, floor.position.x + 6, floor.end.x - width - 6)
		var label := Vector2(x, position.y - 30)
		canvas.draw_rect(Rect2(label + Vector2(-4, -12), Vector2(width + 8, 17)), Color("202828"))
		canvas.draw_string(font, label, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f7e8bb"))
