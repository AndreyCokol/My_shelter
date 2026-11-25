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
	var invalid_gate := origin.duplicate(true)
	invalid_gate.gates.erase("east")
	check(not Region.valid_manifest(invalid_gate) and not Region.seams_match(invalid_gate, Region.manifest(1, 1, 0), "east"), "missing gate rejected without index error")
	var invalid_neighbor := origin.duplicate(true)
	invalid_neighbor.neighbors.west = 123
	check(not Region.valid_manifest(invalid_neighbor), "non-string neighbor rejected")
	var invalid_seed := origin.duplicate(true)
	invalid_seed.seed = -1
	check(not Region.valid_manifest(invalid_seed), "invalid source seed rejected")
	check(Region.valid_manifest(origin), "well-shaped complete region manifest passes validation")
	check(Region.valid_canonical_manifest(origin), "exact canonical region manifest derived from seed and coordinates")
	check(Region.manifest(1, Region.MAX_REGION_COORD + 1, 0).is_empty(), "out-of-range signed x is explicitly refused")
	check(Region.manifest(1, 0, -Region.MAX_REGION_COORD - 1).is_empty(), "out-of-range signed y is explicitly refused")
	check(not Region.parse_region_id("region:%d:0" % [Region.MAX_REGION_COORD + 1]).ok, "region ID exceeding representable coordinate is rejected")

	# A0 P0: a single matching side is not enough! Each endpoint MUST
	# acknowledge the other and each entire manifest must be canonical.
	var next_east := Region.manifest(1, 1, 0)
	var forged_east := next_east.duplicate(true)
	forged_east.neighbors.west = "region:999:999"
	check(Region.valid_manifest(forged_east) and not Region.valid_canonical_manifest(forged_east), "one-sided neighbor edit remains structurally shaped but noncanonical")
	check(not Region.seams_match(origin, forged_east, "east"), "one-sided_neighbor_link_must_fail east")
	var forged_west := Region.manifest(1, -1, 0).duplicate(true)
	forged_west.neighbors.east = "region:999:999"
	check(not Region.seams_match(origin, forged_west, "west"), "one-sided_neighbor_link_must_fail west")
	var forged_north := Region.manifest(1, 0, -1).duplicate(true)
	forged_north.neighbors.south = "region:999:999"
	check(not Region.seams_match(origin, forged_north, "north"), "one-sided_neighbor_link_must_fail north")
	var forged_south := Region.manifest(1, 0, 1).duplicate(true)
	forged_south.neighbors.north = "region:999:999"
	check(not Region.seams_match(origin, forged_south, "south"), "one-sided_neighbor_link_must_fail south")

	# Both peers may coordinate a fabricated connection; a seed-derived
	# canonical gate is still required, not merely reciprocal geometry.
	var forged_pair_a := origin.duplicate(true)
	var forged_pair_b := next_east.duplicate(true)
	forged_pair_a.gates.east = Vector2(Region.REGION_SIZE.x, 250)
	forged_pair_b.gates.west = Vector2(0, 250)
	check(not Region.valid_canonical_manifest(forged_pair_a) and not Region.valid_canonical_manifest(forged_pair_b), "mutually forged but non-seed-derived gates rejected")
	check(not Region.seams_match(forged_pair_a, forged_pair_b, "east"), "symmetric forged gate pair cannot pass seam matching")

	var corrupted_side := origin.duplicate(true)
	corrupted_side.gates.north = Vector2(999, 0)
	check(Region.valid_manifest(corrupted_side) and not Region.valid_canonical_manifest(corrupted_side), "even an unrelated side cannot be quietly mutated")
	check(not Region.seams_match(corrupted_side, next_east, "east"), "east seam fails if source north canonical gate was forged")

	var corrupted_stream := origin.duplicate(true)
	corrupted_stream.streams.loot = int(corrupted_stream.streams.loot) + 1
	check(Region.valid_manifest(corrupted_stream) and not Region.valid_canonical_manifest(corrupted_stream), "loot stream must be seed-derived too")
	check(not Region.seams_match(corrupted_stream, next_east, "east"), "neighbor pair with forged RNG stream cannot pass")

	var incorrect_neighbor := origin.duplicate(true)
	incorrect_neighbor.neighbors.south = "region:123:456"
	check(Region.valid_manifest(incorrect_neighbor) and not Region.valid_canonical_manifest(incorrect_neighbor), "canonical validator rejects unrelated neighbor tampering")
	check(not Region.seams_match(incorrect_neighbor, next_east, "east"), "unrelated neighbor tampering poisons source manifest")

	var changed_coords := origin.duplicate(true)
	changed_coords.x = 1
	changed_coords.id = Region.region_id(1, 0)
	check(not Region.valid_canonical_manifest(changed_coords), "changing coordinates without recalculating all derived fields rejected")
	check(not Region.seams_match(origin, Region.manifest(2, 1, 0), "east"), "world seed mismatch is rejected")
	check(not Region.seams_match(origin, origin, "south") and not Region.seams_match(origin, origin, "diagonal"), "invalid adjacency does not pass")

	print("A2 REGION SEAM TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
