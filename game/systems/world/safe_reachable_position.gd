extends RefCounted
## A2-07 optional *reachable* fallback alongside safe_return_position.gd.
##
## Guarantees: when ok=true, returns a concrete axis-aligned path from a
## supplied *known-safe* anchor to the chosen free point, whose segments are
## clear of all caller-supplied inflated rectangular walls/hazards.
##
## Limits: approximate grid (18 legacy pixels by default), static rectangles
## only. It does not model stairs, doors, living enemies, water physics, global
## navigation polygons, scene transitions or state persistence. It can fail
## closed (SEARCH_LIMIT) rather than claiming an unproven safe location.
const EDGE_EPSILON := 0.5
const DEFAULT_MARGIN := 15.0
const GRID_STEP := 18.0
const MAX_NODES := 10000
const NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static func nearest_reachable(
		bounds: Rect2, blockers: Array, desired: Vector2, reachable_from: Vector2,
		actor_radius: float = 9.0, hazards: Array = [], grid_step: float = GRID_STEP,
		max_nodes: int = MAX_NODES) -> Dictionary:
	if not bounds.is_finite() or not bounds.has_area() or not desired.is_finite() or not reachable_from.is_finite():
		return _error("INVALID_ARGUMENT")
	if not is_finite(actor_radius) or actor_radius < 0.0 or not is_finite(grid_step) or grid_step <= 0.0 or grid_step > 128.0:
		return _error("INVALID_ARGUMENT")
	if max_nodes <= 0 or max_nodes > MAX_NODES:
		return _error("INVALID_ARGUMENT")
	var margin: float = maxf(DEFAULT_MARGIN, actor_radius + EDGE_EPSILON)
	var allowed: Rect2 = bounds.grow(-margin)
	if not allowed.has_area():
		return _error("NO_SAFE_POINT")
	var forbidden: Array[Rect2] = []
	for obstacle in blockers + hazards:
		if not obstacle is Rect2 or not obstacle.is_finite() or not obstacle.has_area():
			return _error("INVALID_ARGUMENT")
		forbidden.append(obstacle.grow(actor_radius + EDGE_EPSILON))
	if not _inside(allowed, reachable_from) or not _clear_point(reachable_from, forbidden):
		return _error("INVALID_ANCHOR")

	# Lattice centered on the known-safe anchor. Every neighbor step is axis
	# aligned and tested as a complete segment, not just by endpoint occupancy.
	var nodes: Array[Dictionary] = [{
		"point": reachable_from, "ix": 0, "iy": 0, "parent": -1,
	}]
	var seen: Dictionary = {"0:0": true}
	var best_index := 0
	var best_point := reachable_from
	var visited := 0
	var truncated := false
	while visited < nodes.size():
		if visited >= max_nodes:
			truncated = true
			break
		var node: Dictionary = nodes[visited]
		var here: Vector2 = node["point"]
		if _closer(here, best_point, desired):
			best_point = here
			best_index = visited

		# If desired is close to this reachable grid point, join it using
		# only verified orthogonal segments (or the same point).
		if _inside(allowed, desired) and _clear_point(desired, forbidden):
			var connector: Dictionary = _join(here, desired, forbidden, grid_step)
			if connector.get("ok", false):
				var route: Array[Vector2] = _path_to(nodes, visited)
				for extra in connector["tail"]:
					if route.is_empty() or not route.back().is_equal_approx(extra):
						route.append(extra)
				return _ok(desired, desired, reachable_from, route, visited + 1)

		for offset in NEIGHBORS:
			var x: int = int(node["ix"]) + offset.x
			var y: int = int(node["iy"]) + offset.y
			var key := "%d:%d" % [x, y]
			if seen.has(key):
				continue
			var next_point := reachable_from + Vector2(float(x) * grid_step, float(y) * grid_step)
			if not _inside(allowed, next_point) or not _clear_point(next_point, forbidden):
				continue
			if not _clear_segment(here, next_point, forbidden):
				continue
			seen[key] = true
			if nodes.size() >= max_nodes:
				truncated = true
				continue
			nodes.append({"point": next_point, "ix": x, "iy": y, "parent": visited})
		visited += 1

	# If a grid limit was hit, the unvisited component might contain a
	# closer reachable point. Fail closed rather than misstate optimality.
	if truncated:
		return _error("SEARCH_LIMIT")
	return _ok(best_point, desired, reachable_from, _path_to(nodes, best_index), visited)

static func _join(a: Vector2, b: Vector2, forbidden: Array[Rect2], step: float) -> Dictionary:
	if absf(a.x - b.x) > step * 1.5 or absf(a.y - b.y) > step * 1.5:
		return {"ok": false}
	if a.is_equal_approx(b):
		return {"ok": true, "tail": []}
	if is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y):
		if _clear_segment(a, b, forbidden):
			return {"ok": true, "tail": [b]}
		return {"ok": false}
	for pivot in [Vector2(b.x, a.y), Vector2(a.x, b.y)]:
		if _clear_point(pivot, forbidden) and _clear_segment(a, pivot, forbidden) and _clear_segment(pivot, b, forbidden):
			return {"ok": true, "tail": [pivot, b]}
	return {"ok": false}

static func _inside(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x and point.x <= rect.end.x and point.y >= rect.position.y and point.y <= rect.end.y

static func _clear_point(point: Vector2, forbidden: Array[Rect2]) -> bool:
	for obstacle in forbidden:
		if _inside(obstacle, point):
			return false
	return true

static func _clear_segment(a: Vector2, b: Vector2, forbidden: Array[Rect2]) -> bool:
	if not a.is_finite() or not b.is_finite():
		return false
	# Check entire axis-aligned swept segment, not only its endpoints.
	if not is_equal_approx(a.x, b.x) and not is_equal_approx(a.y, b.y):
		return false
	for obstacle in forbidden:
		if is_equal_approx(a.y, b.y):
			if a.y >= obstacle.position.y and a.y <= obstacle.end.y and maxf(a.x, b.x) >= obstacle.position.x and minf(a.x, b.x) <= obstacle.end.x:
				return false
		else:
			if a.x >= obstacle.position.x and a.x <= obstacle.end.x and maxf(a.y, b.y) >= obstacle.position.y and minf(a.y, b.y) <= obstacle.end.y:
				return false
	return true

static func _closer(a: Vector2, b: Vector2, desired: Vector2) -> bool:
	var da: float = a.distance_squared_to(desired)
	var db: float = b.distance_squared_to(desired)
	if not is_equal_approx(da, db):
		return da < db
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y

static func _path_to(nodes: Array[Dictionary], final_index: int) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var index := final_index
	while index >= 0:
		var current: Dictionary = nodes[index]
		path.push_front(current["point"])
		index = int(current["parent"])
	return path

static func _ok(point: Vector2, desired: Vector2, anchor: Vector2, route: Array[Vector2], checks: int) -> Dictionary:
	return {
		"ok": true,
		"code": "OK",
		"position": point,
		"anchor": anchor,
		"path": route,
		"checks": checks,
		"relocated": not point.is_equal_approx(desired),
		"reachability": "axis_aligned_static_rectangles",
	}

static func _error(code: String) -> Dictionary:
	return {"ok": false, "code": code}
