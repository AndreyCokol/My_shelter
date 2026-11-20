extends SceneTree
## A2-07 direct Godot acceptance for certified static-rectangle routes.
const Reachable = preload("res://game/systems/world/safe_reachable_position.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func inside(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x and point.x <= rect.end.x and point.y >= rect.position.y and point.y <= rect.end.y

# Independent verifier: every vertex and every complete axis-aligned leg
# must be collision-free in an actor-radius-inflated wall model.
func route_valid(result: Dictionary, bounds: Rect2, blockers: Array, radius: float = 9.0) -> bool:
	if not result.get("ok", false):
		return false
	var path: Array = result.get("path", [])
	if path.is_empty() or path.front() != result.anchor or path.back() != result.position:
		return false
	var allowed: Rect2 = bounds.grow(-maxf(Reachable.DEFAULT_MARGIN, radius + Reachable.EDGE_EPSILON))
	for index in range(path.size()):
		var point: Vector2 = path[index]
		if not point.is_finite() or not inside(allowed, point):
			return false
		for blocker in blockers:
			var wall: Rect2 = blocker.grow(radius + Reachable.EDGE_EPSILON)
			if inside(wall, point):
				return false
		if index > 0:
			var previous: Vector2 = path[index - 1]
			if not is_equal_approx(previous.x, point.x) and not is_equal_approx(previous.y, point.y):
				return false
			for blocker in blockers:
				var wall: Rect2 = blocker.grow(radius + Reachable.EDGE_EPSILON)
				if is_equal_approx(previous.y, point.y):
					if point.y >= wall.position.y and point.y <= wall.end.y and maxf(previous.x, point.x) >= wall.position.x and minf(previous.x, point.x) <= wall.end.x:
						return false
				else:
					if point.x >= wall.position.x and point.x <= wall.end.x and maxf(previous.y, point.y) >= wall.position.y and minf(previous.y, point.y) <= wall.end.y:
						return false
	return true

func _run() -> void:
	var floor := Rect2(0, 0, 200, 160)
	var anchor := Vector2(35, 65)
	var goal := Vector2(165, 65)

	var open := Reachable.nearest_reachable(floor, [], goal, anchor)
	check(open.ok and open.position.is_equal_approx(goal) and route_valid(open, floor, []), "empty world reaches exact desired via explicit clear polyline")
	check(open == Reachable.nearest_reachable(floor, [], goal, anchor), "repeated certified route is deterministic")

	# A solid wall separates two walkable rooms. A free goal on the far
	# side must NOT be called reachable.
	var barrier := Rect2(96, -20, 8, 220)
	var separated := Reachable.nearest_reachable(floor, [barrier], goal, anchor)
	check(separated.ok and separated.position.x < barrier.position.x and separated.relocated, "free but disconnected destination relocated to anchor's own room")
	check(route_valid(separated, floor, [barrier]), "relocated route never crosses an intact separating wall")

	# A gap in the same wall permits a detour. The algorithm must be able
	# to reach the originally requested position, not merely its side.
	var partial := Rect2(96, 0, 8, 85)
	var connected := Reachable.nearest_reachable(floor, [partial], goal, anchor)
	check(connected.ok and connected.position.is_equal_approx(goal), "wall with lower doorway permits a real route to target")
	check(route_valid(connected, floor, [partial]) and connected.path.size() > 3, "doorway detour is a certified multi-segment path")

	var blocked_goal := Reachable.nearest_reachable(floor, [Rect2(148, 50, 30, 30)], goal, anchor)
	check(blocked_goal.ok and blocked_goal.relocated and route_valid(blocked_goal, floor, [Rect2(148, 50, 30, 30)]), "occupied return cell is replaced with reachable free location")

	var flooded := Rect2(85, 0, 25, 160)
	var avoid_hazard := Reachable.nearest_reachable(floor, [], goal, anchor, 9.0, [flooded])
	check(avoid_hazard.ok and avoid_hazard.position.x < flooded.position.x and route_valid(avoid_hazard, floor, [flooded]), "registered hazard rectangle blocks unreachable crossing")

	check(Reachable.nearest_reachable(floor, [], goal, Vector2(-10, 65)).code == "INVALID_ANCHOR", "reject anchor outside valid bounds")
	check(Reachable.nearest_reachable(floor, [Rect2(20, 40, 40, 40)], goal, anchor).code == "INVALID_ANCHOR", "reject physically occupied anchor")
	check(Reachable.nearest_reachable(floor, [], goal, anchor, -2).code == "INVALID_ARGUMENT", "reject invalid actor radius")
	check(Reachable.nearest_reachable(floor, [], goal, anchor, 9.0, [], 0).code == "INVALID_ARGUMENT", "reject zero navigation step")
	check(Reachable.nearest_reachable(floor, [Rect2(0, 0, 0, 20)], goal, anchor).code == "INVALID_ARGUMENT", "reject malformed collider")
	check(Reachable.nearest_reachable(floor, [], goal, anchor, 9.0, [], Reachable.GRID_STEP, 1).code == "SEARCH_LIMIT", "tight search budget refuses unverified nearest fallback")

	for seed_value in [0, 42, 127]:
		var world: Dictionary = Layout.build(seed_value, 5)
		for id in ["hospital", "hospital_0_3", "outside", "house_0"]:
			var node: Dictionary = world[id]
			var desired: Vector2 = node.spawn
			var output := Reachable.nearest_reachable(node.bounds, node.obstacles, desired, desired)
			check(output.ok and not output.relocated and route_valid(output, node.bounds, node.obstacles), "actual seed %d scene %s anchor is physically clear" % [seed_value, id])

	# Fixed-seed property tests: success always has a path, rejection always
	# exposes an explicit code. Generated blockers cannot overlap the anchor.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	for case_id in range(80):
		var blocks: Array = []
		for j in range(rng.randi_range(2, 14)):
			blocks.append(Rect2(
				rng.randi_range(50, 145), rng.randi_range(35, 110),
				rng.randi_range(4, 38), rng.randi_range(4, 32)))
		var desired_random := Vector2(rng.randi_range(70, 182), rng.randi_range(20, 142))
		var result := Reachable.nearest_reachable(floor, blocks, desired_random, Vector2(30, 30))
		var repeat := Reachable.nearest_reachable(floor, blocks, desired_random, Vector2(30, 30))
		check(result == repeat and ((result.ok and route_valid(result, floor, blocks)) or (not result.ok and result.code in ["SEARCH_LIMIT", "NO_SAFE_POINT"])), "random maze %d deterministic, verified route or explicit reject" % case_id)

	print("A2 SAFE REACHABLE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
