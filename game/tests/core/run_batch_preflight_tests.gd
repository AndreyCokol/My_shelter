extends SceneTree

# A1 technical candidate tests, not mass balance or live multi-item transfer.
const Preflight = preload("res://game/contracts/batch_mass_preflight_candidate.gd")
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

func items() -> Array:
	return [
		{"instance_id": "steel-1", "type_id": "steel", "quantity": 2, "container_id": "player"},
		{"instance_id": "cloth-1", "type_id": "cloth", "quantity": 1, "container_id": "player"},
		{"instance_id": "medicine-1", "type_id": "medicine", "quantity": 3, "container_id": "storage"}
	]

func weights() -> Dictionary:
	# Arbitrary integer test units, NOT kilograms or approved game data.
	return {"steel": 7, "cloth": 1, "medicine": 2}

func caps() -> Array:
	return [{"id": "player", "capacity_mass_units": 15},
		{"id": "storage", "capacity_mass_units": 21}]

func transfer() -> Dictionary:
	return {"from_id": "player", "to_id": "storage", "entries": [
		{"instance_id": "steel-1", "quantity": 2},
		{"instance_id": "cloth-1", "quantity": 1}
	]}

func run() -> void:
	var source: Array = items()
	var original: Array = source.duplicate(true)
	var request: Dictionary = transfer()
	var original_request: Dictionary = request.duplicate(true)
	var c: Array = caps()
	var w: Dictionary = weights()
	var prepared: Dictionary = Preflight.prepare(request, source, c, w)
	check(prepared.ok, "two complete instance stacks pass capacity preflight")
	if not prepared.ok:
		print("BATCH PREFLIGHT TESTS: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(prepared.code == "OK" and prepared.preview_items.size() == 3,
		"preview preserves all three inventory objects")
	check(prepared.mass_before.get("player") == 15 and prepared.mass_before.get("storage") == 6,
		"preflight accounts for unchanged items already in storage")
	check(prepared.mass_after.get("storage") == 21 and prepared.mass_after.get("player", 0) == 0,
		"atomic move fills exactly the trusted destination mass capacity")
	check(prepared.preview_items[0].container_id == "storage"
		and prepared.preview_items[1].container_id == "storage"
		and prepared.preview_items[2].container_id == "storage",
		"all selected instances move together while the unselected item remains")
	check(source == original and request == original_request and c == caps() and w == weights(),
		"planning never modifies request, catalog, capacities or live snapshot")
	var again: Dictionary = Preflight.prepare(request, source, c, w)
	check(again == prepared, "same inputs produce byte-identical deterministic preview")
	var reversed: Dictionary = transfer()
	reversed.entries.reverse()
	var swapped: Dictionary = Preflight.prepare(reversed, source, c, w)
	check(swapped.ok and swapped.payload == prepared.payload
		and swapped.preview_items == prepared.preview_items,
		"click selection order cannot change semantic batch or state preview")
	check(JSON.stringify(swapped.payload) == JSON.stringify(prepared.payload),
		"canonical payload can feed stable existing receipt fingerprint")

	var narrow: Array = caps()
	narrow[1].capacity_mass_units = 20
	var reject: Dictionary = Preflight.prepare(request, source, narrow, w)
	check(reject.code == "CAPACITY_EXCEEDED" and not reject.has("preview_items"),
		"one-unit destination overflow rejects the entire multi-object batch")
	check(source == original, "failed staged capacity check has no partial state")
	var initial_bad: Array = caps()
	initial_bad[1].capacity_mass_units = 5
	check(Preflight.prepare(request, source, initial_bad, w).code == "CAPACITY_EXCEEDED",
		"invalid original inventory cannot be silently repaired by an outgoing move")
	var bad: Dictionary = transfer()
	bad.entries[0].quantity = 1
	check(Preflight.prepare(bad, source, c, w).code == "PARTIAL_INSTANCE_UNSUPPORTED",
		"whole-instance candidate never invents split IDs")
	bad = transfer()
	bad.entries[0].quantity = 3
	check(Preflight.prepare(bad, source, c, w).code == "INSUFFICIENT_RESOURCES",
		"quantity larger than trusted stack rejected")
	bad = transfer()
	bad.entries.append({"instance_id": "unseen", "quantity": 1})
	check(Preflight.prepare(bad, source, c, w).code == "NOT_FOUND",
		"missing later instance cancels entire prepared batch")
	bad = transfer()
	bad.entries[0].instance_id = "medicine-1"
	bad.entries[0].quantity = 3
	check(Preflight.prepare(bad, source, c, w).code == "INVALID_SOURCE",
		"source container is validated for every selected instance")
	bad = transfer()
	bad.entries.append(bad.entries[0].duplicate(true))
	check(Preflight.prepare(bad, source, c, w).code == "INVALID_ARGUMENT",
		"duplicate selected instance rejected before lookup")
	bad = transfer()
	bad.client_mass = 0
	check(Preflight.prepare(bad, source, c, w).code == "INVALID_ARGUMENT",
		"untrusted UI mass cannot bypass catalog mass")
	bad = transfer()
	bad.from_id = "not-a-container"
	check(Preflight.prepare(bad, source, c, w).code == "INVALID_CONTAINER",
		"unknown source container cannot be substituted")
	bad = transfer()
	bad.to_id = "not-a-container"
	check(Preflight.prepare(bad, source, c, w).code == "INVALID_CONTAINER",
		"unknown destination container cannot be created implicitly")
	bad = transfer()
	bad.to_id = "player"
	check(Preflight.prepare(bad, source, c, w).code == "INVALID_ARGUMENT",
		"same source/destination is invalid")
	check(Preflight.prepare(request, source, c, w, {"steel-1": 1}).code == "INSUFFICIENT_RESOURCES",
		"reserved stack cannot be transferred as a whole")
	check(Preflight.prepare(request, source, c, w, {"medicine-1": 1}).ok,
		"unselected reserved stack remains untouched")
	check(Preflight.prepare(request, source, c, w, {"ghost": 1}).code == "INVALID_RESERVATION",
		"unknown reservation owner rejected rather than ignored")
	check(Preflight.prepare(request, source, c, w, {"steel-1": 3}).code == "INVALID_RESERVATION",
		"reservation cannot exceed trusted stack count")
	check(Preflight.prepare(request, source, c, w, {"steel-1": -1}).code == "INVALID_RESERVATION",
		"negative reservation rejected")
	check(Preflight.prepare(request, source, c, w, {"steel-1": 1.0}).code == "INVALID_RESERVATION",
		"float reserved quantity rejected")
	check(Preflight.prepare(request, source, c, w, {}).ok, "empty trusted reservation set accepted")
	var unknown_weights: Dictionary = {"steel": 7, "cloth": 1}
	check(Preflight.prepare(request, source, c, unknown_weights).code == "MISSING_MASS",
		"all original objects need trusted mass, including unmoved items")
	var fake_weights: Dictionary = weights()
	fake_weights.steel = 0
	check(Preflight.prepare(request, source, c, fake_weights).code == "MISSING_MASS",
		"zero catalog mass cannot sneak an item into an allegedly free transfer")
	var duplicate_caps: Array = caps()
	duplicate_caps.append({"id": "player", "capacity_mass_units": 999})
	check(Preflight.prepare(request, source, duplicate_caps, w).code == "INVALID_CONTAINER",
		"duplicate container declarations rejected")
	var corrupted: Array = items()
	corrupted[1].instance_id = "steel-1"
	check(Preflight.prepare(request, corrupted, c, w).code == "INVALID_ITEM",
		"snapshot duplicate instance IDs rejected before planning")
	corrupted = items()
	corrupted[2].quantity = Mass.MAX_EXACT_JSON_INT
	check(Preflight.prepare(request, corrupted, c, w).code == "MASS_OVERFLOW",
		"invalid JSON-safe mass arithmetic rejected without mutation")
	check(Preflight.prepare(request, {}, c, w).code == "INVALID_ARGUMENT",
		"snapshot must be a true item-array")
	check(Preflight.prepare([], source, c, w).code == "INVALID_ARGUMENT",
		"batch request must be a typed dictionary")
	check(Preflight.prepare(request, source, c, w, []).code == "INVALID_ARGUMENT",
		"reservations must be a typed dictionary")
	check(source == original, "negative testing never changes source state")
	print("BATCH PREFLIGHT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
