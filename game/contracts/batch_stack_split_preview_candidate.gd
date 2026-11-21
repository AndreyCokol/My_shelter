extends RefCounted

# A1 PURE CANDIDATE. Full/partial staged batch transfer with authoritative
# reservation rows and explicit synthetic divisibility policy. NOT a command.
const Batch = preload("res://game/contracts/inventory_batch_command_candidate.gd")
const Mass = preload("res://game/contracts/mass_accounting_candidate.gd")
const Reservations = preload("res://game/contracts/item_reservation_totals_candidate.gd")
const POLICIES := ["fungible_stack", "whole_object"]

static func fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func prepare(action_id, request, snapshot_items, capacities, mass_catalog,
		reservation_rows, trusted_divisibility) -> Dictionary:
	if not action_id is String or action_id.is_empty() or not trusted_divisibility is Dictionary:
		return fail("INVALID_ARGUMENT")
	var normalized: Dictionary = Batch.normalize(request)
	if not normalized.ok:
		return fail(normalized.code)
	if not snapshot_items is Array or not capacities is Array or not mass_catalog is Dictionary:
		return fail("INVALID_ARGUMENT")
	# The exact A1/A3 food source is mandatory. Caller supplied empty rows are
	# only acceptable when the authoritative snapshot actually has none.
	var reservations: Dictionary = Reservations.aggregate(snapshot_items, reservation_rows)
	if not reservations.ok:
		return fail(reservations.code)
	var pre: Dictionary = Mass.check_capacity(capacities, snapshot_items, mass_catalog)
	if not pre.ok:
		return fail(pre.code)
	var known_containers: Dictionary = {}
	for container in capacities:
		# Mass.check_capacity has already validated the shape and capacity.
		known_containers[container.id] = true
	if not known_containers.has(normalized.payload.from_id) \
			or not known_containers.has(normalized.payload.to_id):
		return fail("INVALID_CONTAINER")
	var by_id: Dictionary = {}
	var existing_ids: Dictionary = {}
	for i in range(snapshot_items.size()):
		var item: Dictionary = snapshot_items[i]
		if not trusted_divisibility.get(item.type_id) in POLICIES:
			return fail("MISSING_DIVISIBILITY_POLICY")
		by_id[item.instance_id] = i
		existing_ids[item.instance_id] = true

	var candidate: Array = snapshot_items.duplicate(true)
	var new_split_ids: Array = []
	var descriptions: Array = []
	# normalize() sorts entries canonically; hence split slot indices cannot
	# depend on input order, GUI selection order, fps, region or random state.
	for index in range(normalized.payload.entries.size()):
		var entry: Dictionary = normalized.payload.entries[index]
		if not by_id.has(entry.instance_id):
			return fail("NOT_FOUND")
		var source_index: int = int(by_id[entry.instance_id])
		var source: Dictionary = snapshot_items[source_index]
		if source.container_id != normalized.payload.from_id:
			return fail("INVALID_SOURCE")
		var held: int = int(reservations.reserved_by_instance.get(source.instance_id, 0))
		var available: int = int(source.quantity) - held
		if entry.quantity > available:
			return fail("INSUFFICIENT_RESOURCES")
		if entry.quantity == source.quantity:
			# Full-instance move keeps its identity and cannot strand any
			# resident-held food at a different container.
			candidate[source_index].container_id = normalized.payload.to_id
			continue
		if trusted_divisibility[source.type_id] != "fungible_stack":
			return fail("PARTIAL_WHOLE_OBJECT")
		var split_id: String = "split:batch:" + action_id.sha256_text() + ":" + str(index)
		if existing_ids.has(split_id):
			return fail("DUPLICATE_INSTANCE_ID")
		existing_ids[split_id] = true
		var moved: Dictionary = source.duplicate(true)
		moved.instance_id = split_id
		moved.quantity = int(entry.quantity)
		moved.container_id = normalized.payload.to_id
		candidate[source_index].quantity = int(source.quantity) - int(entry.quantity)
		candidate.append(moved)
		new_split_ids.append(split_id)
		descriptions.append({"from_instance_id": source.instance_id,
			"new_instance_id": split_id, "quantity": int(entry.quantity)})
	# Validation of the entire poststate catches overflow, invalid item
	# identity, source/destination stock, and capacity after ALL entries.
	var post: Dictionary = Mass.check_capacity(capacities, candidate, mass_catalog)
	if not post.ok:
		return fail(post.code)
	return {"ok": true, "code": "OK", "payload": normalized.payload,
		"preview_items": candidate, "split_instance_ids": new_split_ids,
		"split_descriptions": descriptions,
		"mass_before": pre.mass_by_container.duplicate(true),
		"mass_after": post.mass_by_container.duplicate(true)}
