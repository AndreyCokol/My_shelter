extends SceneTree

const SafeReturn = preload("res://game/systems/world/safe_return_position.gd")
const Layout = preload("res://game/systems/world/world_layout.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)

func inside(rect: Rect2, position: Vector2) -> bool:
	return position.x >= rect.position.x and position.x <= rect.end.x and position.y >= rect.position.y and position.y <= rect.end.y

func clear(position: Vector2, blockers: Array, radius: float = 9.0) -> bool:
	for blocker in blockers:
		if blocker.grow(radius + SafeReturn.EDGE_EPSILON).has_point(position):
			return false
	return true

func _run() -> void:
	var area := Rect2(0, 0, 100, 100)
	var unblocked := SafeReturn.nearest_walkable(area, [], Vector2(50, 50))
	check(unblocked.ok and unblocked.position == Vector2(50, 50) and not unblocked.relocated, "clear position is unchanged")

	var wall := Rect2(40, 40, 20, 20)
	var desired := Vector2(50, 50)
	var shifted := SafeReturn.nearest_walkable(area, [wall], desired)
	check(shifted.ok and shifted.relocated and inside(area.grow(-15), shifted.position) and clear(shifted.position, [wall]), "blocked origin relocates to collision-free point")
	check(shifted == SafeReturn.nearest_walkable(area, [wall], desired), "fallback is deterministic across repeats")

	var overlap: Array = [Rect2(35, 35, 19, 31), Rect2(48, 41, 24, 19)]
	var result := SafeReturn.nearest_walkable(area, overlap, Vector2(51, 48))
	check(result.ok and clear(result.position, overlap), "overlapping blockers do not yield false clearance")

	var blocked_water := Rect2(35, 35, 28, 20)
	var avoid_hazard := SafeReturn.nearest_walkable(area, [], Vector2(50, 45), 9.0, [blocked_water])
	check(avoid_hazard.ok and clear(avoid_hazard.position, [blocked_water]), "optional hazard rectangles are excluded")

	var outside := SafeReturn.nearest_walkable(area, [], Vector2(-150, 1000))
	check(outside.ok and outside.position == Vector2(15, 85), "out of bounds target is clipped to safe floor margin")

	var sealed := SafeReturn.nearest_walkable(area, [Rect2(0, 0, 100, 100)], Vector2(50, 50))
	check(not sealed.ok and sealed.code == "NO_SAFE_POINT", "completely obstructed area refuses unsafe spawn")

	var malformed := SafeReturn.nearest_walkable(area, [Rect2(4, 4, 0, 9)], Vector2(50, 50))
	check(not malformed.ok and malformed.code == "INVALID_ARGUMENT", "invalid obstacle geometry rejected")
	check(not SafeReturn.nearest_walkable(area, [], Vector2(INF, 0)).ok, "nonfinite position rejected")
	check(not SafeReturn.nearest_walkable(area, [], Vector2(50, 50), -1.0).ok, "negative actor radius rejected")

	for seed_value in [0, 1, 42, 127, Layout.MAX_SEED]:
		var nodes := Layout.build(seed_value)
		for scene_id in ["hospital", "outside", "house_0"]:
			var node: Dictionary = nodes[scene_id]
			var candidate := SafeReturn.nearest_walkable(node.bounds, node.obstacles, node.spawn)
			check(candidate.ok and inside(node.bounds.grow(-15), candidate.position) and clear(candidate.position, node.obstacles), "seed %d scene %s permits collision-free spawn" % [seed_value, scene_id])
			check(candidate == SafeReturn.nearest_walkable(node.bounds, node.obstacles, node.spawn), "seed %d scene %s repeats identical result" % [seed_value, scene_id])

	print("A2 SAFE RETURN TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
