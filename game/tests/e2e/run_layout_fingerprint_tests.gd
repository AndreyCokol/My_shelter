extends SceneTree

# Issue #44: distinguish real physical layouts, not merely floor numbers,
# scene names, seeds or asset labels. Also validate edge seeds and paired exits.
const Layout = preload("res://game/systems/world/world_layout.gd")
const Plans = preload("res://game/systems/world/building_plan.gd")
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
		push_error(label)

func rect_string(rect: Rect2) -> String:
	return "%s,%s,%s,%s" % [str(rect.position.x), str(rect.position.y), str(rect.size.x), str(rect.size.y)]

# Physical fingerprint intentionally excludes floor number, district, scene ID,
# room names, labels and decorative seed. Sorting avoids counting array order
# as a visual difference. Distinct fingerprints imply distinct actual geometry.
func floor_fingerprint(plan: Dictionary) -> String:
	var walls: Array[String] = []
	var doors: Array[String] = []
	var rooms: Array[String] = []
	for wall in plan.walls:
		walls.append(rect_string(wall))
	for door in plan.doors:
		doors.append("%s:%s:%s" % [str(door.position), str(door.width), str(door.horizontal)])
	for room in plan.rooms.values():
		rooms.append(rect_string(room.rect))
	walls.sort()
	doors.sort()
	rooms.sort()
	return JSON.stringify([walls, doors, rooms])

func street_fingerprint(node: Dictionary) -> String:
	var obstacles: Array[String] = []
	var roadways: Array[String] = []
	for obstacle in node.obstacles:
		obstacles.append(rect_string(obstacle))
	for road in node.roadways:
		roadways.append(rect_string(road))
	obstacles.sort()
	roadways.sort()
	return JSON.stringify([obstacles, roadways])

func connected_and_paired(nodes: Dictionary) -> bool:
	if nodes.size() != 30 or not nodes.has("shelter"):
		return false
	var seen := {"shelter": true}
	var pending := ["shelter"]
	while not pending.is_empty():
		var id: String = pending.pop_back()
		var record: Dictionary = nodes[id]
		for target in record.links:
			if not nodes.has(target) or not record.exits.has(target):
				return false
			var opposite: Dictionary = nodes[target]
			if not opposite.links.has(id) or not opposite.exits.has(id):
				return false
			var forward: Dictionary = record.exits[target]
			var backward: Dictionary = opposite.exits[id]
			if forward.connector_id != backward.connector_id:
				return false
			if str(forward.form).begins_with("stairs"):
				if forward.position != backward.position or forward.form == backward.form:
					return false
			if not seen.has(target):
				seen[target] = true
				pending.append(target)
	return seen.size() == nodes.size()

func _initialize() -> void:
	# 128 consecutive seeds plus the boundary/large-value seeds.
	var legacy_unique_floor_counts := {
		0: 11, 1: 12, 54: 12, 127: 13, 128: 12,
		1023: 14, 65535: 12, Layout.MAX_SEED: 12,
	}
	for seed_value in range(128) + [128, 1023, 65535, Layout.MAX_SEED]:
		var nodes: Dictionary = Layout.build(seed_value)
		check(nodes == Layout.build(seed_value),
			"seed %d reconstructs identical physical world graph" % seed_value)
		var manifest: Dictionary = Layout.manifest(seed_value)
		check(Layout.valid_manifest(manifest) and Layout.from_manifest(manifest) == nodes,
			"seed %d matches persisted layout manifest" % seed_value)
		check(connected_and_paired(nodes),
			"seed %d provides 30 mutually reachable scenes with paired exits" % seed_value)
		# generator_version is distinct from the unchanged campaign schema v4.
		# Existing checkpoints must reconstruct the original historical layout,
		# not be silently remapped to the new 16-slot architecture.
		var old_manifest := {"seed": seed_value, "generator_version": 4,
			"catalog_version": Layout.CATALOG_VERSION}
		var legacy_nodes: Dictionary = Layout.build(seed_value, 4)
		check(Layout.valid_manifest(old_manifest)
			and Layout.from_manifest(old_manifest) == legacy_nodes,
			"seed %d retains the original generator v4 manifest and graph" % seed_value)
		var legacy_geometry_unchanged := true
		for district in range(Layout.DISTRICTS):
			for floor_index in range(Layout.FLOORS):
				var id: String = Layout.hospital(district, floor_index)
				var old_plan: Dictionary = legacy_nodes[id].floor_plan
				var original_plan: Dictionary = Plans.get_plan(
					"hospital", floor_index + 1, old_plan.pattern)
				legacy_geometry_unchanged = legacy_geometry_unchanged and (
					floor_fingerprint(old_plan) == floor_fingerprint(original_plan))
		check(legacy_geometry_unchanged,
			"seed %d v4 uses historical walls, not v5 alcove geometry" % seed_value)
		if legacy_unique_floor_counts.has(seed_value):
			var previous_signatures := {}
			for district in range(Layout.DISTRICTS):
				for floor_index in range(Layout.FLOORS):
					var legacy_id: String = Layout.hospital(district, floor_index)
					previous_signatures[floor_fingerprint(legacy_nodes[legacy_id].floor_plan)] = true
			check(previous_signatures.size() == legacy_unique_floor_counts[seed_value],
				"seed %d v4 retains historical geometry fingerprint cardinality" % seed_value)

		var hospital_geometries := {}
		var hospital_origins := {}
		var house_geometries := {}
		var streets := {}
		var valid_plans := true
		for district in range(Layout.DISTRICTS):
			for floor_index in range(Layout.FLOORS):
				var id: String = Layout.hospital(district, floor_index)
				if not nodes.has(id) or not nodes[id].has("floor_plan"):
					valid_plans = false
					continue
				var plan: Dictionary = nodes[id].floor_plan
				valid_plans = valid_plans and Plans.valid(plan)
				var fingerprint: String = floor_fingerprint(plan)
				if hospital_origins.has(fingerprint):
					print("HOSPITAL DUPLICATE seed=%d first=%s second=%s patterns=%s,%s" %
						[seed_value, hospital_origins[fingerprint], id,
							nodes[hospital_origins[fingerprint]].floor_plan.pattern, plan.pattern])
				else:
					hospital_origins[fingerprint] = id
				hospital_geometries[fingerprint] = true
			for floor_number in [1, 2]:
				var id: String = Layout.house(district, floor_number)
				if not nodes.has(id) or not nodes[id].has("floor_plan"):
					valid_plans = false
					continue
				var house_plan: Dictionary = nodes[id].floor_plan
				valid_plans = valid_plans and Plans.valid(house_plan)
				house_geometries[floor_fingerprint(house_plan)] = true
			var street_id: String = Layout.street(district)
			if not nodes.has(street_id) or not nodes[street_id].has("roadways"):
				valid_plans = false
			else:
				streets[street_fingerprint(nodes[street_id])] = true
		check(valid_plans, "seed %d has structurally valid hospital and apartment plans" % seed_value)
		print("HOSPITAL UNIQUE COUNT seed=%d count=%d" % [seed_value, hospital_geometries.size()])
		check(hospital_geometries.size() == 16,
			"seed %d has 16 physically distinct hospital floors (not labels)" % seed_value)
		check(house_geometries.size() == 8,
			"seed %d has 8 physically distinct house floors" % seed_value)
		check(streets.size() == 4,
			"seed %d has 4 distinct street geometry segments" % seed_value)
	# Diagnostic only: how many unique *valid* hospital plans exist in the
	# current catalog if the generator can choose a wider candidate pattern?
	var all_candidate_geometry := {}
	for floor_number in range(1, 5):
		var floor_candidate_geometry := {}
		for candidate_pattern in range(64):
			var candidate: Dictionary = Plans.get_plan("hospital", floor_number, candidate_pattern)
			if Plans.valid(candidate):
				var signature: String = floor_fingerprint(candidate)
				floor_candidate_geometry[signature] = true
				all_candidate_geometry[signature] = true
		print("CATALOG HOSPITAL CANDIDATES floor=%d unique=%d" % [floor_number, floor_candidate_geometry.size()])
	print("CATALOG HOSPITAL CANDIDATES union=%d" % all_candidate_geometry.size())
	print("LAYOUT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
