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

# A5 first implementation pass. Nonblocking environmental decals are
# deterministic for the same saved layout and never alter collision/portals.
static func atmosphere(canvas: CanvasItem, kind: String, layout: Dictionary) -> void:
	var identity := str(layout.get("segment", "")) + ":" + str(layout.get("label", "")) + ":" + kind
	var rng := RandomNumberGenerator.new()
	rng.seed = int(abs(identity.hash())) + 1
	if layout.has("floor_plan"):
		var plan: Dictionary = layout.floor_plan
		for room in plan.rooms.values():
			var inside: Rect2 = room.rect.grow(-12)
			if inside.size.x < 25 or inside.size.y < 25:
				continue
			var cold: bool = str(plan.kind) == "hospital"
			var stain := Color(0.11, 0.18, 0.21, 0.32) if cold else Color(0.24, 0.18, 0.12, 0.28)
			for i in range(4):
				var point := Vector2(rng.randf_range(inside.position.x, inside.end.x),
					rng.randf_range(inside.position.y, inside.end.y))
				canvas.draw_line(point,
					point + Vector2(float(rng.randi_range(5, 17)), rng.randf_range(-3.0, 3.0)),
					stain, 1)
			if cold and room.kind in ["lab", "surgery", "recovery", "ward"]:
				var corner := Vector2(inside.position.x + 5, inside.end.y - 6)
				canvas.draw_rect(Rect2(corner, Vector2(17, 2)), Color(0.33, 0.56, 0.58, 0.34))
			elif not cold and room.kind in ["living", "bedroom", "studio"]:
				var corner := inside.position + Vector2(7, 12)
				canvas.draw_rect(Rect2(corner, Vector2(minf(37, inside.size.x - 9), 3)),
					Color(0.43, 0.28, 0.19, 0.35))
		return
	if layout.has("roadways"):
		for road in layout.roadways:
			var pavement: Rect2 = road.grow(-24)
			if pavement.size.x < 30 or pavement.size.y < 30:
				continue
			for i in range(12):
				var point := Vector2(rng.randf_range(pavement.position.x, pavement.end.x),
					rng.randf_range(pavement.position.y, pavement.end.y))
				if i % 3 == 0:
					canvas.draw_circle(point, rng.randf_range(5.0, 11.0),
						Color(0.10, 0.18, 0.21, 0.39))
					canvas.draw_line(point + Vector2(-4, 1), point + Vector2(4, 1),
						Color(0.53, 0.65, 0.69, 0.23), 1)
				else:
					canvas.draw_line(point,
						point + Vector2(float(rng.randi_range(5, 16)), float(rng.randi_range(-5, 5))),
						Color(0.20, 0.22, 0.21, 0.52), 1)
		return
	if kind == "shelter":
		var bounds: Rect2 = layout.get("bounds", Rect2(20, 85, 600, 260))
		var inner := bounds.grow(-18)
		for i in range(55):
			var point := Vector2(rng.randf_range(inner.position.x, inner.end.x),
				rng.randf_range(inner.position.y, inner.end.y))
			var flower := Color(0.96, 0.85, 0.52, 0.57) if i % 3 == 0 else Color(0.76, 0.82, 0.62, 0.49)
			canvas.draw_circle(point, 1.2, flower)
			canvas.draw_line(point + Vector2(0, 1), point + Vector2(0, 3),
				Color(0.26, 0.40, 0.23, 0.43), 1)


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
		furniture_detail(canvas, str(item.kind), item.rect, plan.kind == "hospital")
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

# Top-down prop silhouettes share the exact existing collider rectangles.
# Do not draw tall perspective fronts: furniture belongs to a 90° camera.
static func furniture_detail(canvas: CanvasItem, kind: String, rect: Rect2, medical: bool) -> void:
	var body: Rect2 = rect.grow(-2)
	canvas.draw_rect(rect, Color("151d21"))
	canvas.draw_rect(body, Color("56636b") if medical else Color("765a43"))
	canvas.draw_rect(Rect2(body.position, Vector2(body.size.x, 2)),
		Color("a4afb0") if medical else Color("aa8359"))
	match kind:
		"ward", "recovery", "bedroom":
			# Headboard, pale pillow and darker rumpled blanket are readable
			# at 640x360 even before production sprite sheets are installed.
			canvas.draw_rect(body.grow(-2), Color("73818a") if medical else Color("9c8270"))
			canvas.draw_rect(Rect2(body.position + Vector2(3, 4),
				Vector2(body.size.x - 6, 6)), Color("d9d7c6"))
			canvas.draw_rect(Rect2(body.position + Vector2(3, 12),
				Vector2(body.size.x - 6, maxf(3, body.size.y - 15))),
				Color("657e84") if medical else Color("805b58"))
			if medical:
				canvas.draw_line(body.position + Vector2(2, 2),
					body.position + Vector2(2, body.size.y - 2), Color("d4d8d1"), 1)
		"bath":
			canvas.draw_rect(body.grow(-2), Color("aab8b9"))
			canvas.draw_rect(body.grow(-5), Color("364e56"))
			canvas.draw_circle(body.position + Vector2(body.size.x - 8, 6), 2, Color("e5e1d1"))
		"storage":
			for x in range(3):
				var shelf := Rect2(body.position + Vector2(3 + x * 9, 4), Vector2(6, 9))
				canvas.draw_rect(shelf, Color("8c7b67") if medical else Color("ad8250"))
				canvas.draw_rect(Rect2(shelf.position + Vector2(1, 1), Vector2(2, 3)),
					Color("b5c8bb") if medical else Color("ddbc83"))
			canvas.draw_line(body.position + Vector2(2, body.size.y - 4),
				body.end - Vector2(2, 4), Color("d4b083"), 2)
		"reception", "office":
			canvas.draw_rect(body.grow(-3), Color("75858b") if medical else Color("9f7952"))
			canvas.draw_rect(Rect2(body.position + Vector2(7, 4), Vector2(11, 7)),
				Color("172a30"))
			canvas.draw_rect(Rect2(body.position + Vector2(8, 5), Vector2(9, 5)),
				Color("5a9b9d") if medical else Color("91a1a2"))
			canvas.draw_rect(Rect2(body.position + Vector2(6, 14), Vector2(16, 2)),
				Color("dfdbbc"))
		"lab", "surgery", "triage", "prep":
			canvas.draw_rect(body.grow(-3), Color("859c9d"))
			canvas.draw_rect(Rect2(body.position + Vector2(5, 5), Vector2(13, 7)),
				Color("c3d8d2"))
			canvas.draw_rect(Rect2(body.position + Vector2(body.size.x - 9, 5),
				Vector2(5, 5)), Color("4c8994"))
		"living", "studio":
			canvas.draw_rect(body.grow(-3), Color("98725f"))
			canvas.draw_rect(Rect2(body.position + Vector2(3, 4),
				Vector2(body.size.x - 6, 6)), Color("ad8c71"))
			canvas.draw_rect(Rect2(body.position + Vector2(3, 11),
				Vector2(body.size.x - 6, 4)), Color("58423d"))
		_:
			canvas.draw_rect(body.grow(-3), Color("829498") if medical else Color("ba9069"))


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
