extends RefCounted

# A1-02/A1-06 PURE CONTRACT CANDIDATE, not a gameplay command.
# Combines typed request canonicalization with trusted mass capacity checks.
# No runtime transaction, item split, durable save, event or domain weight is defined.
const Batch = preload("res://game/contracts/inventory_batch_command_candidate.gd")
const Mass = preload("res://game/contracts/mass_accounting_candidate.gd")

static func fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func prepare(request, snapshot_items, capacities, mass_catalog, reserved_by_instance = {}) -> Dictionary:
	var normalized: Dictionary = Batch.normalize(request)
	if not normalized.ok:
		return fail(normalized.code)
	if not snapshot_items is Array or not capacities is Array or not mass_catalog is Dictionary \
			or not reserved_by_instance is Dictionary:
		return fail("INVALID_ARGUMENT")

	# Source and destination must exist even if the inventory has no items
	# in one of those containers. Capacity is in SYNTHETIC MASS UNITS.
	var known: Dictionary = {}
	for container in capacities:
		if not container is Dictionary or not container.get("id") is String:
			return fail("INVALID_CONTAINER")
		if known.has(container.id):
			return fail("INVALID_CONTAINER")
		known[container.id] = true
	if not known.has(normalized.payload.from_id) or not known.has(normalized.payload.to_id):
		return fail("INVALID_CONTAINER")

	# Validate the ENTIRE pre-state using the same A1 mass/accounting helper,
	# not just the moved objects. Never silently fix an already invalid save.
	var pre: Dictionary = Mass.check_capacity(capacities, snapshot_items, mass_catalog)
	if not pre.ok:
		return fail(pre.code)

	var by_id: Dictionary = {}
	for i in range(snapshot_items.size()):
		var item = snapshot_items[i]
		# Mass.check_capacity already validated the mandatory item shape.
		by_id[item.instance_id] = i
	for id in reserved_by_instance:
		if not id is String or not by_id.has(id):
			return fail("INVALID_RESERVATION")
		var count = reserved_by_instance[id]
		if not Mass.valid_units(count) or count > snapshot_items[by_id[id]].quantity:
			return fail("INVALID_RESERVATION")

	var candidate: Array = snapshot_items.duplicate(true)
	for entry in normalized.payload.entries:
		if not by_id.has(entry.instance_id):
			return fail("NOT_FOUND")
		var index: int = by_id[entry.instance_id]
		var item: Dictionary = snapshot_items[index]
		if item.container_id != normalized.payload.from_id:
			return fail("INVALID_SOURCE")
		if entry.quantity > item.quantity or int(reserved_by_instance.get(entry.instance_id, 0)) > 0:
			return fail("INSUFFICIENT_RESOURCES")
		# A whole-instance preflight deliberately rejects partial quantity
		# rather than inventing a new stable ID for a split stack/whole object.
		# A1/A2/A3 must separately approve stack semantics before live wiring.
		if entry.quantity != item.quantity:
			return fail("PARTIAL_INSTANCE_UNSUPPORTED")
		candidate[index].container_id = normalized.payload.to_id

	# One all-or-none staged preview of the *entire* post-state.
	var post: Dictionary = Mass.check_capacity(capacities, candidate, mass_catalog)
	if not post.ok:
		return fail(post.code)
	return {"ok": true, "code": "OK", "payload": normalized.payload,
		"preview_items": candidate, "mass_before": pre.mass_by_container.duplicate(true),
		"mass_after": post.mass_by_container.duplicate(true)}
