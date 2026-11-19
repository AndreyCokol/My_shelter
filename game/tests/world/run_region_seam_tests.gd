extends SceneTree

const Region = preload("res://game/systems/world/region_seams.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func within_area(area: Rect2, rect: Rect2) -> bool:
	return area.encloses(rect) and rect.has_area()

func _run() -> void:
	for pair in [[0, 0], [1, -1], [-17, 31], [100000, -100000]]:
		var id: String = Region.region_id(pair[0], pair[1])
		var parsed := Region.parse_region_id(id)
		check(parsed.ok and parsed.x == pair[0] and parsed.y == pair[1], "canonical coordinates round-trip %s" % id)
	for invalid in ["", "region", "region:01:2", "region:+1:2", "region:-0:1", "region:a:b", "region:1:2:3", "Region:1:2"]:
		check(not Region.parse_region_id(invalid).ok, "noncanonical region ID is rejected: %s" % invalid)
	check(Region.manifest(-1, 0, 0).is_empty() and Region.manifest(Region.MAX_WORLD_SEED + 1, 0, 0).is_empty(), "invalid campaign seeds rejected")

	var bounds := Rect2(Vector2.ZERO, Region.REGION_SIZE)
	for seed_value in [0, 1, 42, 777, Region.MAX_WORLD_SEED]:
		for x in [-10, -1, 0, 1, 10]:
			for y in [-10, -1, 0, 1, 10]:
				var a := Region.manifest(seed_value, x, y)
				var east := Region.manifest(seed_value, x + 1, y)
				var west := Region.manifest(seed_value, x - 1, y)
				var north := Region.manifest(seed_value, x, y - 1)
				var south := Region.manifest(seed_value, x, y + 1)
				check(Region.seams_match(a, east, "east") and Region.seams_match(east, a, "west"),
					"seed %d (%d,%d) east/west edge pairs exactly" % [seed_value, x, y])
				check(Region.seams_match(a, south, "south") and Region.seams_match(south, a, "north"),
					"seed %d (%d,%d) north/south edge pairs exactly" % [seed_value, x, y])
				check(Region.seams_match(a, west, "west") and Region.seams_match(a, north, "north"),
					"seed %d (%d,%d) negative direction links" % [seed_value, x, y])
				check(a == Region.manifest(seed_value, x, y), "seed %d region (%d,%d) deterministic" % [seed_value, x, y])
				var safe := true
				for side in ["north", "east", "south", "west"]:
					safe = safe and within_area(bounds, Region.gate_apron(side, a.gates[side]))
				check(safe, "seed %d region (%d,%d) all gate aprons inside area" % [seed_value, x, y])
				check(a.streams.geometry != a.streams.loot and a.streams.geometry != a.streams.enemies,
					"seed %d region (%d,%d) stream fingerprints separated" % [seed_value, x, y])

	var origin := Region.manifest(1, 0, 0)
	check(not Region.seams_match(origin, Region.manifest(2, 1, 0), "east"), "world seed mismatch is rejected")
	check(not Region.seams_match(origin, origin, "south") and not Region.seams_match(origin, origin, "diagonal"), "invalid adjacency does not pass")

	print("A2 REGION SEAM TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
