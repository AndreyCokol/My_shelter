extends SceneTree

# A1 RFC test data ONLY: numbers, item types and divisibility are not game balance.
const Split = preload("res://game/contracts/batch_stack_split_preview_candidate.gd")

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

func inventory() -> Array:
	return [
		{"instance_id": "food-a", "type_id": "food", "quantity": 5, "container_id": "player"},
		{"instance_id": "food-b", "type_id": "food", "quantity": 4, "container_id": "player"},
		{"instance_id": "lamp", "type_id": "whole", "quantity": 2, "container_id": "player"},
		{"instance_id": "stored", "type_id": "misc", "quantity": 1, "container_id": "storage"}
	]

func capacities(storage: int = 17) -> Array:
	return [{"id": "player", "capacity_mass_units": 25},
		{"id": "storage", "capacity_mass_units": storage}]

func masses() -> Dictionary:
	return {"food": 2, "whole": 3, "misc": 1}

func policies() -> Dictionary:
	return {"food": "fungible_stack", "whole": "whole_object", "misc": "whole_object"}

func reservations() -> Array:
	return [{"resident_id": "npc-1", "instance_id": "food-a", "quantity": 1},
		{"resident_id": "npc-2", "instance_id": "food-a", "quantity": 1}]

func request() -> Dictionary:
	return {"from_id": "player", "to_id": "storage", "entries": [
		{"instance_id": "food-a", "quantity": 3},
		{"instance_id": "food-b", "quantity": 2},
		{"instance_id": "lamp", "quantity": 2}
	]}

func prepare(action_id: String, req, items, caps, mass, holds, policy) -> Dictionary:
	return Split.prepare(action_id, req, items, caps, mass, holds, policy)

func run() -> void:
	var items: Array = inventory()
	var req: Dictionary = request()
	var caps: Array = capacities()
	var mass: Dictionary = masses()
	var holds: Array = reservations()
	var policy: Dictionary = policies()
	var original_items: Array = items.duplicate(true)
	var original_req: Dictionary = req.duplicate(true)
	var original_holds: Array = holds.duplicate(true)

	var plan: Dictionary = prepare("batch-001", req, items, caps, mass, holds, policy)
	check(plan.ok, "mixed whole-object and two stack splits can pass trusted preview")
	if not plan.ok:
		print("BATCH SPLIT PREVIEW TESTS: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(plan.preview_items.size() == items.size() + 2,
		"two partial resource moves create exactly two new instances")
	check(plan.split_instance_ids.size() == 2
		and plan.split_instance_ids[0] != plan.split_instance_ids[1],
		"distinct partial splits receive unique stable instance IDs")
	check(plan.split_instance_ids[0].begins_with("split:batch:")
		and plan.split_instance_ids[1].begins_with("split:batch:"),
		"batch split IDs inhabit a new explicit namespace, not legacy split:action")
	check(plan.split_instance_ids[0].ends_with(":0") and plan.split_instance_ids[1].ends_with(":1"),
		"split slots follow canonical sorted item selection")
	check(plan.preview_items[0].quantity == 2 and plan.preview_items[1].quantity == 2
		and plan.preview_items[2].container_id == "storage",
		"reserved source food stays at player; whole lamp moves as original ID")
	check(plan.preview_items[4].quantity == 3 and plan.preview_items[4].container_id == "storage"
		and plan.preview_items[5].quantity == 2,
		"both newly split stacks reach destination with correct quantities")
	check(plan.preview_items[4].instance_id == plan.split_instance_ids[0]
		and plan.preview_items[5].instance_id == plan.split_instance_ids[1],
		"preview item identity matches the split manifest")
	check(plan.mass_before.player == 24 and plan.mass_before.storage == 1,
		"all source and existing destination mass accounted for")
	check(plan.mass_after.player == 8 and plan.mass_after.storage == 17,
		"post mass exactly conserves 25 synthetic units and fills destination")
	check(items == original_items and req == original_req and holds == original_holds,
		"successful preview never mutates item, request or NPC reservation rows")
	check(prepare("batch-001", req, items, caps, mass, holds, policy) == plan,
		"repeated pure plan from identical snapshot is exactly deterministic")
	var swapped: Dictionary = request()
	swapped.entries.reverse()
	check(prepare("batch-001", swapped, items, caps, mass, holds, policy) == plan,
		"click selection order cannot affect split IDs or preview")
	var renamed: Dictionary = prepare("batch-002", req, items, caps, mass, holds, policy)
	check(renamed.ok and renamed.preview_items[4].instance_id != plan.preview_items[4].instance_id,
		"distinct action IDs cannot accidentally share new split IDs")
	check(renamed.mass_after == plan.mass_after,
		"action ID affects identity but never resource mass")
	check(plan.split_descriptions.size() == 2
		and plan.split_descriptions[0].from_instance_id == "food-a"
		and plan.split_descriptions[1].from_instance_id == "food-b",
		"source/new ID manifest is stable and omits full-instance move")

	var smaller: Dictionary = prepare("batch-001", req, items, capacities(16), mass, holds, policy)
	check(smaller.code == "CAPACITY_EXCEEDED" and not smaller.has("preview_items"),
		"one-unit overflow rejects entire group without partial proposal")
	var one_lamp: Dictionary = request()
	one_lamp.entries[2].quantity = 1
	check(prepare("batch-001", one_lamp, items, caps, mass, holds, policy).code ==
		"PARTIAL_WHOLE_OBJECT", "whole physical object policy prohibits partial split")
	var overdraw: Dictionary = request()
	overdraw.entries[0].quantity = 4
	check(prepare("batch-001", overdraw, items, caps, mass, holds, policy).code ==
		"INSUFFICIENT_RESOURCES", "cannot move food held by two NPC reservations")
	var excess: Dictionary = request()
	excess.entries[1].quantity = 5
	check(prepare("batch-001", excess, items, caps, mass, holds, policy).code ==
		"INSUFFICIENT_RESOURCES", "overdraw of a free stack is also rejected")
	check(prepare("", req, items, caps, mass, holds, policy).code == "INVALID_ARGUMENT",
		"action ID is mandatory to derive deterministic split identities")
	check(prepare("batch-001", req, items, caps, mass, null, policy).code == "INVALID_ARGUMENT",
		"trusted reservation rows cannot be omitted")
	check(prepare("batch-001", req, items, caps, mass, holds, {}).code ==
		"MISSING_DIVISIBILITY_POLICY", "divisibility must be supplied by trusted catalog")
	var unknown_policy: Dictionary = policies()
	unknown_policy.food = "guess_by_name"
	check(prepare("batch-001", req, items, caps, mass, holds, unknown_policy).code ==
		"MISSING_DIVISIBILITY_POLICY", "unknown policy values fail closed")
	var missing_policy: Dictionary = policies()
	missing_policy.erase("misc")
	check(prepare("batch-001", req, items, caps, mass, holds, missing_policy).code ==
		"MISSING_DIVISIBILITY_POLICY", "all original items must have trusted policy, even unmoved")
	var missing_mass: Dictionary = masses()
	missing_mass.erase("misc")
	check(prepare("batch-001", req, items, caps, missing_mass, holds, policy).code ==
		"MISSING_MASS", "unknown mass on an unmoved item also invalidates full preview")
	var wrong_source: Dictionary = request()
	wrong_source.from_id = "storage"
	check(prepare("batch-001", wrong_source, items, caps, mass, holds, policy).code ==
		"INVALID_SOURCE", "each selected item must originate from request source")
	var nonexisting: Dictionary = request()
	nonexisting.entries.append({"instance_id": "ghost", "quantity": 1})
	check(prepare("batch-001", nonexisting, items, caps, mass, holds, policy).code ==
		"NOT_FOUND", "missing selected instance cancels all tentative moves")
	var duplicate: Dictionary = request()
	duplicate.entries.append({"instance_id": "food-a", "quantity": 1})
	check(prepare("batch-001", duplicate, items, caps, mass, holds, policy).code ==
		"INVALID_ARGUMENT", "duplicate item in a batch rejected by canonical normalizer")
	var extra: Dictionary = request()
	extra.client_mass = 0
	check(prepare("batch-001", extra, items, caps, mass, holds, policy).code ==
		"INVALID_ARGUMENT", "client-supplied mass is not an allowed command input")
	var invalid_reserves: Array = reservations()
	invalid_reserves.append({"instance_id": "food-a", "resident_id": "npc-1", "quantity": 1})
	check(prepare("batch-001", req, items, caps, mass, invalid_reserves, policy).code ==
		"INVALID_RESERVATION", "duplicate resident+item reservation rejected")
	var overbooked: Array = [
		{"instance_id": "food-a", "resident_id": "npc-1", "quantity": 4},
		{"instance_id": "food-a", "resident_id": "npc-2", "quantity": 2}
	]
	check(prepare("batch-001", req, items, caps, mass, overbooked, policy).code ==
		"RESERVATION_OVERFLOW", "overbooked food snapshot invalid before planning")
	var corrupted: Array = inventory()
	corrupted[0].quantity = 0
	check(prepare("batch-001", req, corrupted, caps, mass, holds, policy).code ==
		"INVALID_ITEM", "malformed original stack rejected before preview")
	var colliding: Array = inventory()
	colliding.append({"instance_id": plan.split_instance_ids[0], "type_id": "misc",
		"quantity": 1, "container_id": "storage"})
	check(prepare("batch-001", req, colliding, items, mass, holds, policy).code ==
		"INVALID_CONTAINER", "malformed capacities argument cannot bypass validation")
	check(prepare("batch-001", req, colliding, capacities(19), mass, holds, policy).code ==
		"DUPLICATE_INSTANCE_ID", "existing future split ID collision rejected before committing")
	check(prepare("batch-001", req, items, caps, mass, holds, policy).preview_items == plan.preview_items,
		"failed previews cannot affect later valid planning")
	check(items == original_items and req == original_req and holds == original_holds,
		"all error paths leave source snapshot and reservations unchanged")
	print("BATCH SPLIT PREVIEW TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
