extends RefCounted

# Visual-only actor silhouettes for the approved strict 90-degree top-down
# pixel-art game. World collision and combat range remain in Player/Enemy.
# Every rectangle uses integer pixel coordinates at the 640x360 design size.
# Avoid sprite billboards and pseudo-isometric geometry.

const EDGE := Color("171f20")
const BOOT := Color("32322d")
const TROUSERS := Color("505746")
const JACKET := Color("495a45")
const JACKET_LIT := Color("778467")
const BACKPACK := Color("596444")
const PACK_LIT := Color("909665")
const SKIN := Color("d0a17a")
const SKIN_LIT := Color("e5b58b")
const HAIR := Color("463329")
const HAIR_LIT := Color("856043")
const STEEL := Color("d9dee1")
const BLOOD := Color("953f38")

static func _block(canvas: CanvasItem, x: float, y: float, w: float, h: float, color: Color) -> void:
	canvas.draw_rect(Rect2(x, y, w, h), color)

static func _outlined(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	canvas.draw_rect(rect.grow(1.0), EDGE)
	canvas.draw_rect(rect, color)

static func _shadow(canvas: CanvasItem) -> void:
	# Render before rotating the figure; no fake circular exit marker.
	canvas.draw_ellipse(Vector2(0, 6), Vector2(11, 5), Color(0.04, 0.07, 0.06, 0.35))

static func hero(canvas: CanvasItem, facing: Vector2, stride: float,
		hurt: bool, dodging: bool, swinging: bool) -> void:
	canvas.draw_circle(Vector2(0, 7), 11, Color(0.04, 0.07, 0.06, 0.25))
	var radians := (facing.normalized() if facing.length_squared() > 0.01 else Vector2.UP).angle() + PI / 2.0
	canvas.draw_set_transform(Vector2.ZERO, radians, Vector2.ONE)
	var swing := sin(stride) * 2.0
	# Boots and legs: independent stride, unmistakably a humanoid from 90°.
	_outlined(canvas, Rect2(-7, 8 + swing, 5, 9), BOOT)
	_outlined(canvas, Rect2(2, 8 - swing, 5, 9), BOOT)
	_block(canvas, -6, 7 + swing, 4, 5, TROUSERS)
	_block(canvas, 2, 7 - swing, 4, 5, TROUSERS)
	# Main torso, jacket shoulders and shaded olive-green rucksack.
	_outlined(canvas, Rect2(-8, -3, 16, 15), Color("364537") if hurt else JACKET)
	_block(canvas, -7, -1, 3, 9, JACKET_LIT)
	_block(canvas, 4, -1, 3, 9, Color("303d34"))
	_outlined(canvas, Rect2(-6, 2, 12, 11), BACKPACK)
	_block(canvas, -4, 4, 9, 3, PACK_LIT)
	_block(canvas, -4, 9, 8, 2, Color("353b2b"))
	_block(canvas, 0, 4, 1, 8, Color("d0bf86"))
	# Hand-drawn arms on either side of the backpack.
	_outlined(canvas, Rect2(-12, -1 + swing, 4, 10), JACKET)
	_outlined(canvas, Rect2(8, -1 - swing, 4, 10), JACKET)
	_block(canvas, -11, 8 + swing, 3, 3, SKIN)
	_block(canvas, 9, 8 - swing, 3, 3, SKIN_LIT)
	# Head in front of torso, several hair pixels and a readable skin outline.
	_outlined(canvas, Rect2(-6, -13, 12, 12), SKIN)
	_block(canvas, -7, -14, 14, 5, HAIR)
	_block(canvas, -6, -10, 3, 3, HAIR)
	_block(canvas, 4, -11, 3, 4, HAIR)
	_block(canvas, -3, -14, 6, 2, HAIR_LIT)
	_block(canvas, -4, -4, 2, 1, Color("624336"))
	_block(canvas, 2, -4, 2, 1, Color("624336"))
	# Blade points in local -Y; rotation makes it follow the real target.
	canvas.draw_line(Vector2(10, 6), Vector2(13, -5), Color("564735"), 3.0)
	canvas.draw_line(Vector2(13, -5), Vector2(11, -21), STEEL, 2.0)
	canvas.draw_line(Vector2(10, -16), Vector2(11, -21), Color("f2f5e4"), 1.0)
	canvas.draw_line(Vector2(8, -4), Vector2(16, -4), Color("4d3d2c"), 2.0)
	if swinging:
		canvas.draw_arc(Vector2.ZERO, 28, -2.5, -0.5, 18, Color("fce7ab"), 2)
		canvas.draw_arc(Vector2.ZERO, 32, -2.25, -0.8, 18, Color(1, 0.87, 0.56, 0.35), 2)
	if dodging:
		canvas.draw_arc(Vector2.ZERO, 16, 0.20, 2.9, 18, Color("b1e3c5"), 2)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func zombie(canvas: CanvasItem, moving: Vector2, stride: float,
		damage_flash: bool, alert: bool, dead: bool) -> void:
	canvas.draw_circle(Vector2(1, 7), 12, Color(0, 0, 0, 0.25))
	var radians := (moving.normalized() if moving.length_squared() > 0.01 else Vector2.DOWN).angle() + PI / 2.0
	canvas.draw_set_transform(Vector2.ZERO, radians, Vector2.ONE)
	if dead:
		_outlined(canvas, Rect2(-10, -4, 19, 11), Color("474a44"))
		_block(canvas, -3, -7, 8, 5, Color("9b9b85"))
		_block(canvas, 6, 2, 4, 4, BLOOD)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var wobble := sin(stride) * 2.0
	var cloth := Color("c5c5b9") if damage_flash else Color("777b70")
	var skin := Color("e0c5b4") if damage_flash else Color("a7a89b")
	# Asymmetrical stagger and torn trousers, forward-reaching limbs.
	_outlined(canvas, Rect2(-8, 8 + wobble, 5, 8), Color("4b514f"))
	_outlined(canvas, Rect2(3, 9 - wobble, 5, 8), Color("51534e"))
	_outlined(canvas, Rect2(-7, -2, 14, 14), cloth)
	_block(canvas, -6, 1, 4, 6, Color("9a9889"))
	_block(canvas, 2, 4, 4, 5, BLOOD)
	_block(canvas, -2, 7, 4, 4, Color("55463f"))
	_outlined(canvas, Rect2(-12, -5 - wobble, 4, 13), cloth)
	_outlined(canvas, Rect2(8, -8 + wobble, 4, 16), cloth)
	_block(canvas, -11, -8 - wobble, 4, 4, skin)
	_block(canvas, 9, -11 + wobble, 3, 5, skin)
	# Pale, decayed head; one dark eye socket and wounds.
	_outlined(canvas, Rect2(-6, -14, 12, 12), skin)
	_block(canvas, -6, -15, 12, 3, Color("666c63"))
	_block(canvas, -4, -9, 3, 3, Color("272c29"))
	_block(canvas, 3, -9, 2, 2, Color("443a35"))
	_block(canvas, -1, -5, 4, 2, BLOOD)
	if alert:
		canvas.draw_rect(Rect2(-2, -21, 4, 4), Color("f6b55d"))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
