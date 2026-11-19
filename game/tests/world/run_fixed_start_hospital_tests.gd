extends SceneTree

const Fixed = preload("res://game/systems/world/fixed_start_hospital.gd")
const Plans = preload("res://game/systems/world/building_plan.gd")
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

func _run() -> void:
	check(Fixed.start_scene_id() == "hospital_0_3" and Layout.hospital(0, 2) == Fixed.start_scene_id(), "fixed starter first scene is the canonical third-floor ID")
	check(Fixed.scene_id(1) == "hospital" and Fixed.scene_id(2) == "hospital_0_2" and Fixed.scene_id(4) == "hospital_0_4", "preserve historical hospital floor IDs")
	check(Fixed.scene_id(0).is_empty() and Fixed.scene_id(5).is_empty() and Fixed.plan_for_floor(0).is_empty() and Fixed.plan_for_floor(5).is_empty(), "reject unknown floor IDs")
	var fingerprints := {}
	for floor_number in range(1, 5):
		var plan := Fixed.plan_for_floor(floor_number)
		check(not plan.is_empty() and int(plan.floor) == floor_number and Plans.valid(plan), "fixed hospital floor %d has valid physics layout" % floor_number)
		check(plan == Fixed.plan_for_floor(floor_number), "floor %d plan repeat is deterministic" % floor_number)
		check(plan.fixed_start and plan.is_roof == (floor_number == 4), "floor %d has correct roof metadata" % floor_number)
		var signature := str(plan.walls) + str(plan.rooms) + str(plan.doors) + str(plan.furniture)
		check(not fingerprints.has(signature), "floor %d differs physically from other floors" % floor_number)
		fingerprints[signature] = true

	var roof := Fixed.plan_for_floor(4)
	check(roof.rooms.size() == 1 and roof.rooms.has("corridor") and roof.furniture.is_empty() and roof.doors.is_empty(), "fourth floor is a single open roof, not a laboratory floor")
	check(roof.rooms.corridor.rect == Fixed.ROOF_BOUNDS, "roof has its own stable walkable area")
	var existing_fourth := Plans.get_plan("hospital", 4, 0)
	check(roof.rooms.size() != existing_fourth.rooms.size(), "open roof is physically distinct from default v5 lab fourth floor")

	var first := Fixed.plan_for_floor(1)
	first.rooms.erase("corridor")
	check(Plans.valid(Fixed.plan_for_floor(1)), "mutating a caller copy cannot corrupt a cached starter plan")
	for seed_value in [0, 1, 42, 127, Layout.MAX_SEED]:
		var nodes := Layout.build(seed_value)
		check(nodes.has(Fixed.start_scene_id()) and nodes.has("hospital_0_4"), "seed %d has existing third and fourth floor identifiers" % seed_value)
		check(Fixed.plan_for_floor(3) == Fixed.plan_for_floor(3), "starter layout is independent of seed %d" % seed_value)

	print("A2 FIXED HOSPITAL PROTOTYPE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
