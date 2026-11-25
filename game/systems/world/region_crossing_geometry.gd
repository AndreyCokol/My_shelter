extends RefCounted
## A2-04: static collision-safe seam entry/exit geometry.
##
## Depends on canonical region_seams.gd; does NOT load/unload chunks,
## move a real player, mutate an actor, persist region deltas, or call
## SceneRouter. A1 must stage both regions before an atomic transition.
const Region = preload("res://game/systems/world/region_seams.gd")
const EDGE_EPSILON := 0.5
const MAX_RADIUS := 24.0
const DEPTH := Region.GATE_DEPTH * 0.5

static func seam_crossing(
		from_manifest: Dictionary, to_manifest: Dictionary, side: String,
		actor_radius: float = 9.0, source_blockers: Array = [],
		target_blockers: Array = [], source_hazards: Array = [], target_hazards: Array = []) -> Dictionary:
	var opposite: String = _reverse(side)
	if opposite.is_empty():
		return _error("INVALID_DIRECTION")
	if not Region.seams_match(from_manifest, to_manifest, side):
		return _error("INVALID_REGION_SEAM")
	if not is_finite(actor_radius) or actor_radius < 0.0 or actor_radius > MAX_RADIUS:
		return _error("INVALID_ARGUMENT")
	var source_forbidden := _forbidden(source_blockers, source_hazards, actor_radius)
	var target_forbidden := _forbidden(target_blockers, target_hazards, actor_radius)
	if not source_forbidden.get("ok", false) or not target_forbidden.get("ok", false):
		return _error("INVALID_ARGUMENT")

	var source_gate: Vector2 = from_manifest.gates[side]
	var target_gate: Vector2 = to_manifest.gates[opposite]
	var source_point := source_gate
	var target_point := target_gate
	match side:
		"east":
			source_point.x -= DEPTH
			target_point.x += DEPTH
		"west":
			source_point.x += DEPTH
			target_point.x -= DEPTH
		"north":
			source_point.y += DEPTH
			target_point.y -= DEPTH
		"south":
			source_point.y -= DEPTH
			target_point.y += DEPTH

	if not Region.gate_apron(side, source_gate).has_point(source_point):
		return _error("INVALID_SOURCE_APRON")
	if not Region.gate_apron(opposite, target_gate).has_point(target_point):
		return _error("INVALID_TARGET_APRON")
	if not _clear_segment(source_point, source_gate, source_forbidden["rects"]):
		return _error("BLOCKED_SOURCE")
	if not _clear_segment(target_gate, target_point, target_forbidden["rects"]):
		return _error("BLOCKED_TARGET")
	return {
		"ok": true, "code": "OK",
		"from_region": from_manifest.id, "to_region": to_manifest.id,
		"source_side": side, "target_side": opposite,
		"source_gate": source_gate, "target_gate": target_gate,
		"departure": source_point, "arrival": target_point,
		"validated_space": "static_rectangles_only",
	}

static func _reverse(side: String) -> String:
	match side:
		"east": return "west"
		"west": return "east"
		"north": return "south"
		"south": return "north"
	return ""

static func _forbidden(blockers: Array, hazards: Array, actor_radius: float) -> Dictionary:
	var rectangles: Array[Rect2] = []
	for obstacle in blockers + hazards:
		if not obstacle is Rect2 or not obstacle.is_finite() or not obstacle.has_area():
			return {"ok": false}
		rectangles.append(obstacle.grow(actor_radius + EDGE_EPSILON))
	return {"ok": true, "rects": rectangles}

static func _clear_segment(a: Vector2, b: Vector2, forbidden: Array[Rect2]) -> bool:
	if not a.is_finite() or not b.is_finite():
		return false
	if not is_equal_approx(a.x, b.x) and not is_equal_approx(a.y, b.y):
		return false
	for obstacle in forbidden:
		if is_equal_approx(a.x, b.x):
			if a.x >= obstacle.position.x and a.x <= obstacle.end.x and maxf(a.y, b.y) >= obstacle.position.y and minf(a.y, b.y) <= obstacle.end.y:
				return false
		else:
			if a.y >= obstacle.position.y and a.y <= obstacle.end.y and maxf(a.x, b.x) >= obstacle.position.x and minf(a.x, b.x) <= obstacle.end.x:
				return false
	return true

static func _error(code: String) -> Dictionary:
	return {"ok": false, "code": code}
