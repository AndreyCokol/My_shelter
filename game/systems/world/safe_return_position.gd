extends RefCounted
## A2 spatial-only candidate for safe shelter returns.
##
## This helper never moves the hero or updates authoritative campaign state.
## A1 SceneRouter remains responsible for the durable transition. Coordinates
## are world-local (WorldHost-local when world transforms are identity).
## "Safe" here means inside the floor and clear of rectangular blockers/hazards;
## no claim about faction danger, water simulation, or a reachable walking path.

const EDGE_EPSILON := 0.5
const DEFAULT_MARGIN := 15.0
const MAX_VISITED := 512

static func nearest_walkable(bounds: Rect2, blockers: Array, desired: Vector2, actor_radius: float = 9.0, hazards: Array = []) -> Dictionary:
	if not bounds.is_finite() or not bounds.has_area() or not desired.is_finite() or not is_finite(actor_radius) or actor_radius < 0.0:
		return _error("INVALID_ARGUMENT")
	var margin := maxf(DEFAULT_MARGIN, actor_radius + EDGE_EPSILON)
	var allowed := bounds.grow(-margin)
	if not allowed.has_area():
		return _error("NO_SAFE_POINT")
	var forbidden: Array[Rect2] = []
	for obstacle in blockers + hazards:
		if not obstacle is Rect2 or not obstacle.is_finite() or not obstacle.has_area():
			return _error("INVALID_ARGUMENT")
		forbidden.append(obstacle.grow(actor_radius + EDGE_EPSILON))

	# Fast path: almost every valid return position must remain unchanged.
	var origin := Vector2(
		clampf(desired.x, allowed.position.x, allowed.end.x),
		clampf(desired.y, allowed.position.y, allowed.end.y))
	if _blockers_at(origin, forbidden).is_empty():
		return _ok(origin, desired, 1)

	# Best-first expansion across rectangular obstacle boundaries. Each probe is
	# adjacent to an actual blocking edge, rather than relying on an arbitrary
	# search radius that fails on large buildings or city-sized maps.
	var queue: Array[Vector2] = [origin]
	var visited := {}
	var checked := 0
	while not queue.is_empty() and checked < MAX_VISITED:
		queue.sort_custom(func(a: Vector2, b: Vector2): return _closer(a, b, desired))
		var candidate: Vector2 = queue.pop_front()
		var key := "%.3f:%.3f" % [candidate.x, candidate.y]
		if visited.has(key):
			continue
		visited[key] = true
		checked += 1
		var occupied := _blockers_at(candidate, forbidden)
		if occupied.is_empty():
			return _ok(candidate, desired, checked)
		for obstacle in occupied:
			var x := clampf(candidate.x, obstacle.position.x, obstacle.end.x)
			var y := clampf(candidate.y, obstacle.position.y, obstacle.end.y)
			var probes: Array[Vector2] = [
				Vector2(obstacle.position.x - EDGE_EPSILON, y),
				Vector2(obstacle.end.x + EDGE_EPSILON, y),
				Vector2(x, obstacle.position.y - EDGE_EPSILON),
				Vector2(x, obstacle.end.y + EDGE_EPSILON),
			]
			for probe in probes:
				# Clipping a candidate to the allowed floor is safe, but may
				# remain blocked; the next iteration checks it again.
				var clipped := Vector2(
					clampf(probe.x, allowed.position.x, allowed.end.x),
					clampf(probe.y, allowed.position.y, allowed.end.y))
				var probe_key := "%.3f:%.3f" % [clipped.x, clipped.y]
				if not visited.has(probe_key) and queue.size() < MAX_VISITED * 4:
					queue.append(clipped)
	return _error("SEARCH_LIMIT" if checked >= MAX_VISITED else "NO_SAFE_POINT")

static func _blockers_at(point: Vector2, forbidden: Array[Rect2]) -> Array[Rect2]:
	var found: Array[Rect2] = []
	for blocker in forbidden:
		if blocker.has_point(point):
			found.append(blocker)
	return found

static func _closer(a: Vector2, b: Vector2, desired: Vector2) -> bool:
	var da := a.distance_squared_to(desired)
	var db := b.distance_squared_to(desired)
	if not is_equal_approx(da, db):
		return da < db
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y

static func _ok(position: Vector2, desired: Vector2, checks: int) -> Dictionary:
	return {
		"ok": true, "code": "OK", "position": position,
		"relocated": not position.is_equal_approx(desired), "checks": checks,
	}

static func _error(code: String) -> Dictionary:
	return {"ok": false, "code": code}
