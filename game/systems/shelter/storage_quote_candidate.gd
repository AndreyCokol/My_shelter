extends RefCounted

# A3-03 CANDIDATE: pure household selection of an available destination
# for a WHOLE, already-committed inventory item instance.
# A1 owns item identity, transactional transfer, mass definitions, receipts,
# reservations and save migrations. This function never performs a transfer.
# Destination order is supplied by policy/owner; no invented auto-sort ranking.
const Mass = preload("res://game/contracts/mass_accounting_candidate.gd")

static func failure(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func quote(items, containers, mass_catalog, instance_id, destinations, reservations = []) -> Dictionary:
	if not items is Array or not containers is Array or not mass_catalog is Dictionary:
		return failure("INVALID_ARGUMENT")
	if not instance_id is String or instance_id.is_empty() or not reservations is Array:
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
	# Even a reserved share of a stack cannot be moved under this conservative
	# whole-instance policy; A1 may later define a versioned split API.
	for reservation in reservations:
		if not reservation is Dictionary:
			return failure("INVALID_RESERVATION")
		if reservation.get("instance_id") == instance_id:
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
