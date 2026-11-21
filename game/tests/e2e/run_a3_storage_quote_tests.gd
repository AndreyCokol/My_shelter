extends SceneTree

# Isolated A3-03 pure quote tests. Godot execution must be recorded separately.
const Quote = preload("res://game/systems/shelter/storage_quote_candidate.gd")
const Mass = preload("res://game/contracts/mass_accounting_candidate.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1
		push_error(message)

func items() -> Array:
	return [
		{"instance_id": "steel:1", "type_id": "material.steel", "quantity": 1, "container_id": "player"},
		{"instance_id": "cloth:1", "type_id": "material.cloth", "quantity": 2, "container_id": "storageA"}
	]

func containers() -> Array:
	return [
		{"id": "player", "capacity_mass_units": 20},
		{"id": "storageA", "capacity_mass_units": 8},
		{"id": "storageB", "capacity_mass_units": 8}
	]

func catalog() -> Dictionary:
	return {"material.steel": 7, "material.cloth": 1}

func run() -> void:
	var source: Array = items()
	var caps: Array = containers()
	var masses: Dictionary = catalog()
	var original_source: Array = source.duplicate(true)
	var original_caps: Array = caps.duplicate(true)
	var original_catalog: Dictionary = masses.duplicate(true)

	var quote: Dictionary = Quote.quote(source, caps, masses, "steel:1",
		["storageA", "storageB"], {})
	check(quote.get("ok", false) and quote.get("to_id") == "storageB"
		and quote.get("from_id") == "player" and quote.get("whole_quantity") == 1
		and quote.get("whole_mass_units") == 7,
		"full steel item uses second storage when first lacks mass capacity")
	check(quote.get("proposed_mass_by_container", {}).get("storageB") == 7
		and quote.get("proposed_mass_by_container", {}).get("storageA") == 2,
		"proposal accounts for post-transfer container mass")
	check(source == original_source and caps == original_caps and masses == original_catalog,
		"quoting leaves inventory, containers and catalog untouched")
	check(Mass.check_capacity(caps, source, masses).ok
		and source[0].container_id == "player",
		"quote never performs the actual movement")

	var wider: Array = containers()
	wider[1].capacity_mass_units = 9
	var preferred: Dictionary = Quote.quote(source, wider, masses, "steel:1",
		["storageA", "storageB"], {})
	check(preferred.get("ok", false) and preferred.get("to_id") == "storageA",
		"first valid explicitly ordered destination wins at exact boundary")
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB", "storageA"], {}).get("to_id") == "storageB",
		"caller-specified order is accepted without a hidden sort policy")
	var reversed: Array = items()
	reversed.reverse()
	check(Quote.quote(reversed, caps, masses, "steel:1", ["storageA", "storageB"], {}).get("to_id") == "storageB",
		"inventory ordering cannot alter chosen destination")

	var crowded: Array = containers()
	crowded[1].capacity_mass_units = 8
	crowded[2].capacity_mass_units = 6
	check(Quote.quote(source, crowded, masses, "steel:1",
		["storageA", "storageB"], {}).get("code") == "NO_CAPACITY",
		"no destination large enough refuses whole-item placement")
	check(Quote.quote(source, caps, masses, "steel:1",
		["player"], {}).get("code") == "NO_CAPACITY",
		"source container alone is not a new storage destination")
	check(Quote.quote(source, caps, masses, "steel:1",
		["storageA", "storageA"], {}).get("code") == "INVALID_POLICY",
		"duplicate configured priority rejected")
	check(Quote.quote(source, caps, masses, "steel:1",
		["unknown"], {}).get("code") == "INVALID_POLICY",
		"unregistered container must not be created implicitly")
	check(Quote.quote(source, caps, masses, "steel:1",
		[], {}).get("code") == "NEEDS_POLICY",
		"no invented default destination preference")
	check(Quote.quote(source, caps, masses, "absent",
		["storageB"], {}).get("code") == "NOT_FOUND",
		"absent inventory instance cannot be routed")

	# Real A1 aggregated reservations are per-instance totals; the map is
	# mandatory and MUST be derived from ALL current reservation rows.
	var held: Dictionary = {"steel:1": 1}
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB"], held).get("code") == "RESERVED_ITEM",
		"one reserved unit blocks whole-instance movement")
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB"], null).get("code") == "INVALID_ARGUMENT",
		"missing reservation snapshot is never treated as empty")
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB"], []).get("code") == "INVALID_ARGUMENT",
		"raw reservation rows cannot be mistaken for A1 aggregated totals")
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB"], {"missing:9": 1}).get("code") == "INVALID_RESERVATION",
		"reservation for removed instance fails closed")
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB"], {"steel:1": 2}).get("code") == "INVALID_RESERVATION",
		"aggregate exceeding item quantity is rejected")
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB"], {"steel:1": 0}).get("code") == "INVALID_RESERVATION",
		"zero aggregate cannot masquerade as a trusted reservation")
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB"], {"steel:1": 1.0}).get("code") == "INVALID_RESERVATION",
		"floating-point reservation total is invalid")
	check(Quote.quote(source, caps, masses, "steel:1", ["storageB"], {"cloth:1": 1}).get("to_id") == "storageB",
		"unrelated valid reservation is preserved without blocking another instance")
	check(Quote.quote(source, caps, masses, "cloth:1", ["storageB"], {"cloth:1": 1}).get("code") == "RESERVED_ITEM",
		"reserved portion of another whole stack also blocks its transfer")

	var missing: Dictionary = {"material.cloth": 1}
	check(Quote.quote(source, caps, missing, "steel:1",
		["storageB"], {}).get("code") == "MISSING_MASS",
		"missing steel mass never falls back to zero")
	var duplicated: Array = items()
	duplicated[1].instance_id = "steel:1"
	check(Quote.quote(duplicated, caps, masses, "steel:1",
		["storageB"], {}).get("code") == "INVALID_ITEM",
		"duplicate instance id rejected by A1 mass validator")
	var malformed: Array = items()
	malformed[0].quantity = -1
	check(Quote.quote(malformed, caps, masses, "steel:1",
		["storageB"], {}).get("code") == "INVALID_ITEM",
		"negative item count rejected by A1 mass validator")
	check(Quote.quote(source, [], masses, "steel:1",
		["storageB"], {}).get("code") == "INVALID_CONTAINER",
		"empty declared container list cannot authorize any placement")

	print("A3 STORAGE QUOTE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
