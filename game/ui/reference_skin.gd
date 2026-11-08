extends RefCounted

# VIS-02 — R1..R4: shared reference-inspired pixel frame.
# This is presentation only: no gameplay data or input handlers belong here.
const WARM_PANEL := Color("21190f", 0.93)
const COLD_PANEL := Color("131a20", 0.94)
const GOLD := Color("b99559")
const GOLD_HIGHLIGHT := Color("f4d183")
const GOLD_DARK := Color("493520")
const COLD_TRIM := Color("8c785f")
const TEXT := Color("f5e4bf")
const NEGATIVE := Color("b94137")
const TRACK := Color("0a0a0c", 0.95)

static func is_shelter(scene_id: String) -> bool:
	return scene_id == "shelter"

static func trim(shelter: bool, active: bool = false) -> Color:
	if active:
		return GOLD_HIGHLIGHT
	return GOLD if shelter else COLD_TRIM

static func panel(canvas: CanvasItem, area: Rect2, shelter: bool = true, active: bool = false) -> void:
	var color := trim(shelter, active)
	canvas.draw_rect(area, WARM_PANEL if shelter else COLD_PANEL)
	canvas.draw_rect(area, Color("080807", 0.93), false, 3.0)
	canvas.draw_rect(area.grow(-1), color, false, 1.0)
	var tl := area.position
	var br := area.end
	# Beveled brass corner glints replicate the screenshot hierarchy without
	# stretching textures; all coordinates land on logical integer pixels.
	for x in [tl.x + 2.0, br.x - 6.0]:
		canvas.draw_line(Vector2(x, tl.y + 1.0), Vector2(x + 4.0, tl.y + 1.0), GOLD_HIGHLIGHT if active else color, 1.0)
		canvas.draw_line(Vector2(x, br.y - 2.0), Vector2(x + 4.0, br.y - 2.0), GOLD_DARK, 1.0)

static func gauge(canvas: CanvasItem, area: Rect2, ratio: float, bar_color: Color, shelter: bool = true) -> void:
	panel(canvas, area, shelter)
	var inner: Rect2 = area.grow(-3)
	canvas.draw_rect(inner, TRACK)
	inner.size.x *= clampf(ratio, 0.0, 1.0)
	if inner.size.x > 0.0:
		canvas.draw_rect(inner, bar_color)
		var top: Rect2 = inner
		top.size.y = 2.0
		canvas.draw_rect(top, bar_color.lightened(0.28))
