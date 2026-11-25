extends SceneTree
# A1 mass model fixture: arbitrary mass units are test values, NOT product kg.
const Mass = preload("res://game/contracts/mass_accounting_candidate.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)

func run() -> void:
	var objects: Array = [
		{"instance_id": "steel:1", "type_id": "material.steel", "quantity": 2, "container_id": "storage"},
		{"instance_id": "cloth:1", "type_id": "material.cloth", "quantity": 5, "container_id": "storage"}
	]
	var masses: Dictionary = {"material.steel": 7, "material.cloth": 1}
	var old_objects: Array = objects.duplicate(true)
	var old_masses: Dictionary = masses.duplicate(true)
	var total: Dictionary = Mass.calculate(objects, masses)
	check(total.ok and total.mass_by_container.get("storage") == 19,
		"two item types produce mass-weighted total, not quantity count")
	check(objects == old_objects and masses == old_masses, "pure calculation does not alter arguments")
	check(Mass.check_capacity([{"id": "storage", "capacity_mass_units": 19}], objects, masses).ok,
		"exact weighted capacity boundary accepted")
	check(Mass.check_capacity([{"id": "storage", "capacity_mass_units": 18}], objects, masses).code == "CAPACITY_EXCEEDED",
		"capacity one mass unit below boundary rejected")
	check(not Mass.check_capacity([{"id": "storage", "capacity_mass_units": 19}], objects,
		{"material.steel": 7}).ok, "missing mass never gets zero default")
	check(Mass.calculate(objects, {"material.steel": 7, "material.cloth": 0}).code == "MISSING_MASS",
		"zero item mass is not fabricated into free storage")
	var negative: Array = objects.duplicate(true)
	negative[0].quantity = -1
	check(Mass.calculate(negative, masses).code == "INVALID_ITEM", "negative quantity rejected")
	var zero: Array = objects.duplicate(true)
	zero[0].quantity = 0
	check(Mass.calculate(zero, masses).code == "INVALID_ITEM", "zero quantity rejected")
	var duplicate: Array = objects.duplicate(true)
	duplicate[1].instance_id = duplicate[0].instance_id
	check(Mass.calculate(duplicate, masses).code == "INVALID_ITEM",
		"duplicate instance ID cannot double count")
	var unknown: Array = objects.duplicate(true)
	unknown[1].container_id = "unknown"
	check(Mass.check_capacity([{"id": "storage", "capacity_mass_units": 100}], unknown, masses).code == "INVALID_CONTAINER",
		"unknown target container rejected")
	var two: Array = objects.duplicate(true)
	two[1].container_id = "player"
	var caps: Array = [{"id": "storage", "capacity_mass_units": 14},
		{"id": "player", "capacity_mass_units": 5}]
	check(Mass.check_capacity(caps, two, masses).ok, "separate containers validated independently")
	check(Mass.check_capacity([{"id": "storage", "capacity_mass_units": 14},
		{"id": "player", "capacity_mass_units": 4}], two, masses).code == "CAPACITY_EXCEEDED",
		"player overflow rejected independently of storage")
	check(Mass.check_capacity([{"id": "storage", "capacity_mass_units": 0},
		{"id": "storage", "capacity_mass_units": 19}], objects, masses).code == "INVALID_CONTAINER",
		"duplicate container definition rejected")
	check(Mass.check_capacity([{"id": "storage", "capacity_mass_units": -1}], objects, masses).code == "INVALID_CONTAINER",
		"negative capacity rejected")
	check(Mass.check_capacity([{"id": "storage", "capacity_mass_units": 19.5}], objects, masses).code == "INVALID_CONTAINER",
		"fractional mass units rejected until unit scale is defined")
	var huge: Array = [{"instance_id": "huge:1", "type_id": "material.steel",
		"quantity": Mass.MAX_EXACT_JSON_INT, "container_id": "storage"}]
	check(Mass.calculate(huge, masses).code == "MASS_OVERFLOW",
		"overflow rejected before multiplication")
	var near_limit: Array = [
		{"instance_id": "a", "type_id": "material.cloth",
			"quantity": Mass.MAX_EXACT_JSON_INT, "container_id": "storage"},
		{"instance_id": "b", "type_id": "material.cloth",
			"quantity": 1, "container_id": "storage"}
	]
	check(Mass.calculate(near_limit, masses).code == "MASS_OVERFLOW",
		"overflow rejected before aggregation")
	check(Mass.calculate([], {}).ok, "empty inventory has zero mass")
	check(Mass.calculate({}, masses).code == "INVALID_ARGUMENT", "wrong input shape rejected")
	check(Mass.calculate(objects, {"material.steel": "7", "material.cloth": 1}).code == "MISSING_MASS",
		"noninteger catalog weights rejected")
	print("MASS ACCOUNTING TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
