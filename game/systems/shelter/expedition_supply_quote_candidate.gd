extends RefCounted

# A3 pure supply proposal over A1's reservation aggregator. NOT dispatch,
# NPC permission, inventory mutation, mass/capacity preflight or a receipt.
# All inputs must come from trusted A1/A4 and a versioned policy, never UI.
const Reservations = preload("res://game/contracts/item_reservation_totals_candidate.gd")
const MAX_COUNT := 2147483647
const MAX_GROUP := 1024

static func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value == value.strip_edges()

static func _count(value: Variant, minimum: int) -> bool:
	return value is int and value >= minimum and value <= MAX_COUNT

static func _ids(values: Variant, minimum: int, maximum: int) -> bool:
	if not values is Array or values.size() < minimum or values.size() > maximum:
		return false
	var seen: Dictionary = {}
	for value in values:
		if not _id(value) or seen.has(value):
			return false
		seen[value] = true
	return true

static func quote(context: Dictionary, policy: Dictionary, items: Array, reservation_rows: Array) -> Dictionary:
	for key in ["action_id", "expedition_proposal_id", "destination_id", "slot_key", "save_id", "actor_id", "ruleset_version", "policy_version"]:
		if not _id(context.get(key)):
			return _fail("INVALID_CONTEXT")
	var residents: Variant = context.get("resident_ids")
	if not _ids(residents, 2, MAX_GROUP):
		return _fail("INVALID_GROUP")
	for key in ["minute", "requested_departure_minute", "valid_until_minute"]:
		if not _count(context.get(key), 0):
			return _fail("INVALID_CONTEXT")
	if context.minute > context.valid_until_minute or context.minute > context.requested_departure_minute or context.valid_until_minute > context.requested_departure_minute:
		return _fail("INVALID_TIME")
	var revisions: Variant = context.get("revisions")
	if not revisions is Dictionary:
		return _fail("INVALID_CONTEXT")
	for key in ["inventory:player", "inventory:storage", "residents", "world"]:
		if not revisions.has(key):
			return _fail("INVALID_CONTEXT")
	for key in revisions:
		if not _id(key) or not _count(revisions[key], 0):
			return _fail("INVALID_CONTEXT")
	if policy.get("version") != context.policy_version:
		return _fail("NEEDS_SUPPLY_POLICY")
	var per_resident: Variant = policy.get("per_resident")
	var sources: Variant = policy.get("source_containers")
	if not per_resident is Dictionary or per_resident.is_empty() or not _ids(sources, 1, 1024):
		return _fail("NEEDS_SUPPLY_POLICY")
	for source in sources:
		if not revisions.has("inventory:" + source):
			return _fail("INVALID_CONTEXT")
	var canonical_sources: Array = sources.duplicate()
	canonical_sources.sort()
	var type_ids: Array = per_resident.keys()
	var requirements: Array = []
	for type_id in type_ids:
		if not _id(type_id) or not _count(per_resident[type_id], 1):
			return _fail("INVALID_POLICY")
		if int(per_resident[type_id]) * residents.size() > MAX_COUNT:
			return _fail("INVALID_POLICY")
	type_ids.sort()
	for type_id in type_ids:
		requirements.append({"type_id": type_id, "quantity": int(per_resident[type_id]) * residents.size()})
	var aggregated := Reservations.aggregate(items, reservation_rows)
	if not aggregated.ok:
		return _fail(str(aggregated.code))
	var by_id: Dictionary = {}
	for item in items:
		if not _id(item.get("instance_id")) or not _id(item.get("type_id")) or not _id(item.get("container_id")) or not _count(item.get("quantity"), 1):
			return _fail("INVALID_ITEM")
		by_id[item.instance_id] = item
	var instance_ids: Array = by_id.keys()
	instance_ids.sort()
	var selected: Array = []
	for requirement in requirements:
		var remaining: int = requirement.quantity
		for instance_id in instance_ids:
			var item: Dictionary = by_id[instance_id]
			if item.type_id != requirement.type_id or not item.container_id in sources:
				continue
			var free: int = int(item.quantity) - int(aggregated.reserved_by_instance.get(instance_id, 0))
			var used := mini(free, remaining)
			if used > 0:
				selected.append({"instance_id": instance_id, "type_id": item.type_id, "quantity": used, "source_container": item.container_id})
				remaining -= used
			if remaining == 0:
				break
		if remaining != 0:
			return _fail("INSUFFICIENT_RESOURCES")
	var ordered: Array = residents.duplicate()
	ordered.sort()
	return {"ok": true, "code": "SUPPLY_QUOTE_READY", "quote_version": 2,
		"action_id": context.action_id, "expedition_proposal_id": context.expedition_proposal_id,
		"destination_id": context.destination_id, "slot_key": context.slot_key,
		"save_id": context.save_id, "actor_id": context.actor_id, "ruleset_version": context.ruleset_version,
		"policy_version": context.policy_version, "source_containers": canonical_sources, "resident_ids": ordered,
		"requested_departure_minute": context.requested_departure_minute,
		"valid_until_minute": context.valid_until_minute, "quoted_at_minute": context.minute,
		"inventory_revisions_snapshot": revisions.duplicate(true),
		"item_requirements": requirements, "selected_item_instances": selected,
		"reserved_food_excluded": true, "requires_atomic_dispatch_preflight": true}

# Advisory freshness check, not an atomic lock, reservation, permission or receipt.
# prior must be the server-held quote; current_context and all snapshots must
# be independently resolved from trusted state. A1 must repeat validation
# within its commit boundary and own idempotency / durable reservation.
static func revalidate(prior: Dictionary, current_context: Dictionary, policy: Dictionary, items: Array, reservation_rows: Array) -> Dictionary:
	if prior.get("ok") != true or prior.get("quote_version") != 2 or not _count(prior.get("quoted_at_minute"), 0):
		return _fail("INVALID_PRIOR_QUOTE")
	var quoted_at: int = prior.quoted_at_minute
	if not _count(current_context.get("minute"), 0):
		return _fail("INVALID_CONTEXT")
	if current_context.minute < quoted_at:
		return _fail("STALE_SUPPLY_QUOTE")
	var current := quote(current_context, policy, items, reservation_rows)
	if not current.ok:
		return _fail(str(current.code))
	# Only the observation minute may advance; all identity, revision,
	# deadline, requirements and exact allocation evidence must still match.
	current["quoted_at_minute"] = quoted_at
	if current != prior:
		return _fail("STALE_SUPPLY_QUOTE")
	return {"ok": true, "code": "SUPPLY_QUOTE_CURRENT", "requires_atomic_dispatch_preflight": true}
