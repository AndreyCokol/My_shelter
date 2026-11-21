extends RefCounted

# A3-03 CANDIDATE: pure household selection of an available destination
# for a WHOLE, already-committed inventory item instance.
# A1 owns item identity, transactional transfer, mass definitions, receipts,
# reservations and save migrations. This function never performs a transfer.
# Destination order is supplied by policy/owner; no invented auto-sort ranking.
# Reserved totals: trusted A1 item_reservation_totals_candidate.aggregate(...).
# A1 must revalidate revisions/reservations before atomic durable transfer.
const Mass = preload("res://game/contracts/mass_accounting_candidate.gd")

static func failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func quote(items, containers, mass_catalog, instance_id, destinations, reserved_by_instance) -> Dictionary:
	if not items is Array or not containers is Array or not mass_catalog is Dictionary:
		return failure("INVALID_ARGUMENT")
	if not instance_id is String or instance_id.is_empty() or not reserved_by_instance is Dictionary:
		return failure("INVALID_ARGUMENT")
	if not destinations is Array or destinations.is_empty():
		return failure("NEEDS_POLICY")
	# Never repair or reinterpret an invalid or legacy container state implicitly.
	var baseline: Dictionary = Mass.check_capacity(containers, items, mass_catalog)
	if not baseline.get("ok", false):
		return failure(str(baseline.get("code", "INVALID_ARGUMENT")))

	var item: Dictionary = {}
	for candidate in items:
		if candidate.instance_id == instance_id:
			item = candidate
			break
	if item.is_empty():
		return failure("NOT_FOUND")
	# The reservation map is MANDATORY and must come from the authoritative
	# A1 aggregation of ALL snapshot.inventory.reservations rows, not a caller's
	# optional empty default. Empty {} is permitted ONLY if A1 proves no reservations.
	# This pure selector still cannot authenticate the caller's snapshot or revisions.
	var item_by_id: Dictionary = {}
	for entry in items:
		item_by_id[entry.instance_id] = entry
	for id in reserved_by_instance:
		if not id is String or not item_by_id.has(id) \
				or not Mass.valid_units(reserved_by_instance[id], true) \
				or int(reserved_by_instance[id]) > int(item_by_id[id].quantity):
			return failure("INVALID_RESERVATION")
	# Even a partial reservation blocks movement of the WHOLE item instance.
	# A1 handles separate split/partial stack transactions and authoritative commit.
	if reserved_by_instance.has(instance_id):
		return failure("RESERVED_ITEM")

	var known: Dictionary = {}
	for container in containers:
		known[container.id] = true
	var seen: Dictionary = {}
	for target in destinations:
		if not target is String or target.is_empty() or not known.has(target) or seen.has(target):
			return failure("INVALID_POLICY")
		seen[target] = true

	for target in destinations:
		if target == item.container_id:
			continue
		# Test the exact post-move shape on a deep copy with the A1 mass helper.
		# A3 does not debit, split, mint a new instance or persist this plan.
		var proposed: Array = items.duplicate(true)
		for record in proposed:
			if record.instance_id == instance_id:
				record.container_id = target
				break
		var checked: Dictionary = Mass.check_capacity(containers, proposed, mass_catalog)
		if checked.get("ok", false):
			return {"ok": true, "code": "OK", "instance_id": instance_id,
				"from_id": item.container_id, "to_id": target,
				"whole_quantity": item.quantity,
				"whole_mass_units": int(item.quantity) * int(mass_catalog[item.type_id]),
				"proposed_mass_by_container": checked.mass_by_container.duplicate(true)}
		if checked.get("code") != "CAPACITY_EXCEEDED":
			return failure(str(checked.get("code", "INVALID_ARGUMENT")))
	return failure("NO_CAPACITY")
