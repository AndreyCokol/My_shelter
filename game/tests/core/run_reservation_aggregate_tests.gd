extends SceneTree

# A1 pure validation of real (instance_id,resident_id,quantity) reservation rows.
# Uses arbitrary mass units; no NPC settlement or save mutations.
const Reservations = preload("res://game/contracts/item_reservation_totals_candidate.gd")
const Preflight = preload("res://game/contracts/batch_mass_preflight_candidate.gd")

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

func items() -> Array:
	return [
		{"instance_id": "steel-1", "type_id": "steel", "quantity": 2, "container_id": "player"},
		{"instance_id": "cloth-1", "type_id": "cloth", "quantity": 1, "container_id": "player"},
		{"instance_id": "medicine-1", "type_id": "medicine", "quantity": 3, "container_id": "storage"}
	]

func caps() -> Array:
	return [{"id":"player", "capacity_mass_units":15},
		{"id":"storage", "capacity_mass_units":21}]

func weights() -> Dictionary:
	return {"steel":7, "cloth":1, "medicine":2}

func batch() -> Dictionary:
	return {"from_id":"player", "to_id":"storage",
		"entries":[{"instance_id":"steel-1", "quantity":2},
			{"instance_id":"cloth-1", "quantity":1}]}

func row(id: String, resident: String, n: int) -> Dictionary:
	return {"instance_id":id, "resident_id":resident, "quantity":n}

func run() -> void:
	var inv: Array = items()
	var old_inv: Array = inv.duplicate(true)
	var assignments: Array = [row("steel-1","resident_1",1),
		row("steel-1","resident_2",1), row("medicine-1","resident_1",1),
		row("medicine-1","resident_2",2)]
	var old_assignments: Array = assignments.duplicate(true)
	var r: Dictionary = Reservations.aggregate(inv, assignments)
	check(r.ok and r.reserved_by_instance.get("steel-1") == 2
		and r.reserved_by_instance.get("medicine-1") == 3,
		"two distinct residents reserving the same item are summed, not last-write-wins")
	check(r.reserved_by_instance.size() == 2,
		"only actually reserved instances appear in canonical map")
	check(JSON.stringify(r.reserved_by_instance) ==
		JSON.stringify({"medicine-1":3, "steel-1":2}),
		"aggregate is ordered canonically by stable item ID")
	check(inv == old_inv and assignments == old_assignments,
		"reservation aggregation never changes snapshots or rows")

	var shuffled: Array = assignments.duplicate(true)
	shuffled.reverse()
	check(Reservations.aggregate(inv, shuffled) == r,
		"reservation row order cannot affect totals")
	check(Preflight.prepare_from_rows(batch(), inv, caps(), weights(), assignments).code ==
		"INSUFFICIENT_RESOURCES",
		"whole selected stack cannot consume NPC-reserved steel from two residents")
	check(Preflight.prepare_from_rows(batch(), inv, caps(), weights(), null).code ==
		"INVALID_ARGUMENT", "missing authoritative rows must fail closed")
	check(Preflight.prepare_from_rows(batch(), inv, caps(), weights(), []).ok,
		"explicitly verified empty reservation rows allow full-instance transfer")

	var other: Array = [row("medicine-1","resident_1",1),
		row("medicine-1","resident_2",2)]
	check(Preflight.prepare_from_rows(batch(), inv, caps(), weights(), other).ok,
		"only unselected reserved item does not block unrelated whole-instance transfer")
	var overflowing: Array = [row("steel-1","resident_1",2),
		row("steel-1","resident_2",1)]
	check(Reservations.aggregate(inv, overflowing).code == "RESERVATION_OVERFLOW",
		"sum exceeding trusted item quantity is rejected before integer addition")
	var invalid: Array = assignments.duplicate(true)
	invalid.append(row("ghost","resident_3",1))
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"reservation referencing a missing item rejects whole aggregation")
	invalid = assignments.duplicate(true)
	invalid.append(row("steel-1","resident_1",1))
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"same resident-item allocation cannot be present twice")
	invalid = assignments.duplicate(true)
	invalid[0].quantity = -1
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"negative quantity rejected")
	invalid = assignments.duplicate(true)
	invalid[0].quantity = 0
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"zero reservation rejected")
	invalid = assignments.duplicate(true)
	invalid[0].quantity = 1.0
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"floating-point quantity rejected")
	invalid = assignments.duplicate(true)
	invalid[0].quantity = "1"
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"string quantity rejected")
	invalid = assignments.duplicate(true)
	invalid[0].resident_id = ""
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"anonymous resident reservation rejected")
	invalid = assignments.duplicate(true)
	invalid[0].instance_id = ""
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"blank item identity rejected")
	invalid = assignments.duplicate(true)
	invalid[0].item_mass = 999
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"untrusted extra item mass field rejected")
	invalid = assignments.duplicate(true)
	invalid[0] = "malformed"
	check(Reservations.aggregate(inv, invalid).code == "INVALID_RESERVATION",
		"malformed row rejected")
	var bad_items: Array = items()
	bad_items[1].instance_id = "steel-1"
	check(Reservations.aggregate(bad_items, assignments).code == "INVALID_ITEM",
		"duplicate source inventory IDs rejected")
	bad_items = items()
	bad_items[1].quantity = 0
	check(Reservations.aggregate(bad_items, assignments).code == "INVALID_ITEM",
		"invalid item quantity rejected")
	check(Reservations.aggregate(inv, {}).code == "INVALID_ARGUMENT",
		"reservation rows must be an array")
	check(Reservations.aggregate({}, []).code == "INVALID_ARGUMENT",
		"snapshot items must be an array")
	check(Reservations.aggregate(inv, []).reserved_by_instance.is_empty(),
		"no reservation rows give an explicit, trustworthy empty aggregate")
	check(Reservations.aggregate([], []).ok,
		"empty, explicitly validated inventory can have no reservations")
	check(inv == old_inv and assignments == old_assignments,
		"all negative test cases leave source objects unchanged")
	print("RESERVATION AGGREGATE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
