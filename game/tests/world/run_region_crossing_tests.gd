extends SceneTree
## A2-04: direct native Godot test for static rectangular seam approaches.
## Does not pretend that real neighbor chunks have been streamed.
const Region = preload("res://game/systems/world/region_seams.gd")
const Crossing = preload("res://game/systems/world/region_crossing_geometry.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + title)

func neighbor(seed: int, x: int, y: int, side: String) -> Dictionary:
	match side:
		"east":
			return Region.manifest(seed, x + 1, y)
		"west":
			return Region.manifest(seed, x - 1, y)
		"north":
			return Region.manifest(seed, x, y - 1)
		"south":
			return Region.manifest(seed, x, y + 1)
	return {}

func check_segment_open(a: Vector2, b: Vector2, walls: Array, actor_radius: float = 9.0) -> bool:
	if not is_equal_approx(a.x, b.x) and not is_equal_approx(a.y, b.y):
		return false
	for wall in walls:
		var rect: Rect2 = wall.grow(actor_radius + Crossing.EDGE_EPSILON)
		if is_equal_approx(a.x, b.x):
			if a.x >= rect.position.x and a.x <= rect.end.x and maxf(a.y, b.y) >= rect.position.y and minf(a.y, b.y) <= rect.end.y:
				return false
		else:
			if a.y >= rect.position.y and a.y <= rect.end.y and maxf(a.x, b.x) >= rect.position.x and minf(a.x, b.x) <= rect.end.x:
				return false
	return true

func _run() -> void:
	for seed in [0, 17, 42]:
		for pair in [[0, 0], [11, -7], [-100, 53]]:
			var x: int = pair[0]
			var y: int = pair[1]
			for side in ["west", "east", "north", "south"]:
				var a := Region.manifest(seed, x, y)
				var b := neighbor(seed, x, y, side)
				var a_before := a.duplicate(true)
				var b_before := b.duplicate(true)
				var crossing: Dictionary = Crossing.seam_crossing(a, b, side)
				check(crossing.ok and crossing.code == "OK",
					"seed %d (%d,%d) %s canonical unblocked seam accepted" % [seed, x, y, side])
				check(crossing.ok and crossing.from_region == a.id and crossing.to_region == b.id,
					"seed %d (%d,%d) %s correct region identity" % [seed, x, y, side])
				check(crossing.ok and Region.gate_apron(side, crossing.source_gate).has_point(crossing.departure),
					"seed %d (%d,%d) %s source is inside the gate apron" % [seed, x, y, side])
				check(crossing.ok and Region.gate_apron(crossing.target_side, crossing.target_gate).has_point(crossing.arrival),
					"seed %d (%d,%d) %s arrival is inside the reverse apron" % [seed, x, y, side])
				check(crossing.ok and check_segment_open(crossing.departure, crossing.source_gate, [])
					and check_segment_open(crossing.target_gate, crossing.arrival, []),
					"seed %d (%d,%d) %s actual approach is axis aligned" % [seed, x, y, side])
				var reverse: Dictionary = Crossing.seam_crossing(b, a, crossing.target_side)
				check(reverse.ok and reverse.departure == crossing.arrival and reverse.arrival == crossing.departure
					and reverse.from_region == crossing.to_region,
					"seed %d (%d,%d) %s reverse route has identical physical anchor pair" % [seed, x, y, side])
				check(a == a_before and b == b_before,
					"seed %d (%d,%d) %s manifests are unchanged by planning" % [seed, x, y, side])

	var origin: Dictionary = Region.manifest(42, 0, 0)
	var east: Dictionary = Region.manifest(42, 1, 0)
	var valid: Dictionary = Crossing.seam_crossing(origin, east, "east")
	check(valid.ok, "known canonical origin+east candidate can cross a free seam")

	var blocked_departure := Rect2(valid.departure - Vector2(5, 5), Vector2(10, 10))
	var blocked_arrival := Rect2(valid.arrival - Vector2(5, 5), Vector2(10, 10))
	check(Crossing.seam_crossing(origin, east, "east", 9.0, [blocked_departure]).code == "BLOCKED_SOURCE",
		"source blockage refuses crossing even when target region is clear")
	check(Crossing.seam_crossing(origin, east, "east", 9.0, [], [blocked_arrival]).code == "BLOCKED_TARGET",
		"target blockage refuses crossing even when source region is clear")
	check(Crossing.seam_crossing(origin, east, "east", 9.0, [], [], [blocked_departure]).code == "BLOCKED_SOURCE",
		"source hazard rectangle is treated as real blocked approach")
	check(Crossing.seam_crossing(origin, east, "east", 9.0, [], [], [], [blocked_arrival]).code == "BLOCKED_TARGET",
		"target hazard rectangle is treated as real blocked approach")

	# Obstacle intersects the *middle of a segment*, while both endpoints
	# remain clear. Endpoint-only validation would incorrectly allow it.
	var mid: Vector2 = (valid.departure + valid.source_gate) / 2.0
	var crossing_wall := Rect2(mid - Vector2(2, 2), Vector2(4, 4))
	check(Crossing.seam_crossing(origin, east, "east", 9.0, [crossing_wall]).code == "BLOCKED_SOURCE",
		"full approach segment is checked, not merely its endpoints")

	var corrupted := east.duplicate(true)
	corrupted.neighbors.west = "region:999:999"
	check(Crossing.seam_crossing(origin, corrupted, "east").code == "INVALID_REGION_SEAM",
		"asymmetric endpoint cannot offer an allegedly valid crossing")
	check(Crossing.seam_crossing(origin, Region.manifest(7, 1, 0), "east").code == "INVALID_REGION_SEAM",
		"two different world seeds cannot be crossed")
	check(Crossing.seam_crossing(origin, east, "sideways").code == "INVALID_DIRECTION",
		"unknown direction cannot be used for a seam crossing")
	check(Crossing.seam_crossing(origin, east, "east", -1.0).code == "INVALID_ARGUMENT",
		"negative collision radius rejected")
	check(Crossing.seam_crossing(origin, east, "east", Crossing.MAX_RADIUS + 1.0).code == "INVALID_ARGUMENT",
		"oversized collision radius rejected")
	check(Crossing.seam_crossing(origin, east, "east", 9.0, [Rect2(0, 0, 0, 5)]).code == "INVALID_ARGUMENT",
		"degenerate blocker geometry refused")
	check(Crossing.seam_crossing(origin, east, "east", 9.0, [], [], [], ["danger"]).code == "INVALID_ARGUMENT",
		"non-rectangular dynamic hazard data refused")
	check(Crossing.seam_crossing(origin, east, "east", 9.0) == Crossing.seam_crossing(origin, east, "east", 9.0),
		"repeat seam crossing is deterministic")

	print("A2 REGION CROSSING TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
