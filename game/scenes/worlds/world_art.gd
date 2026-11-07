extends RefCounted

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

static func ground(canvas: CanvasItem, kind: String, variant: int) -> void:
	var bounds := Rect2(20, 85, 600, 260)
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
