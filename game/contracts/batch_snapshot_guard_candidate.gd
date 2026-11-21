extends RefCounted

# A1 PURE TECHNICAL CANDIDATE. Binds a batch split preview to one
# authoritative source snapshot, mass/policy catalog and relevant revisions.
# The digest is NOT an authorization token: anyone can compute SHA-256.
# Revalidation must occur inside a trusted CoreSession command plan/commit.
const Split = preload("res://game/contracts/batch_stack_split_preview_candidate.gd")
const Mass = preload("res://game/contracts/mass_accounting_candidate.gd")
const Batch = preload("res://game/contracts/inventory_batch_command_candidate.gd")
const Reservations = preload("res://game/contracts/item_reservation_totals_candidate.gd")

static func fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}

static func canonical_catalog(catalog: Dictionary, positive_mass: bool) -> Dictionary:
	var keys: Array = catalog.keys()
	keys.sort()
	var result: Array = []
	for key in keys:
		if not key is String or key.is_empty():
			return fail("INVALID_CATALOG")
		var value = catalog[key]
		if positive_mass:
			if not Mass.valid_units(value, true):
				return fail("INVALID_CATALOG")
		elif not value is String or not value in Split.POLICIES:
			return fail("INVALID_CATALOG")
		result.append([key, value])
	return {"ok": true, "entries": result}

# Identity is trusted CoreSession context, NEVER a player-supplied command field.
static func canonical_identity(identity) -> Dictionary:
	if not identity is Dictionary or identity.size() != 3:
		return fail("INVALID_IDENTITY")
	for key in ["save_id", "actor_id", "ruleset_version"]:
		if not identity.get(key) is String or identity[key].is_empty():
			return fail("INVALID_IDENTITY")
	return {"ok": true, "entries": [identity.save_id, identity.actor_id, identity.ruleset_version]}

static func required_revisions(source_id: String, target_id: String, revisions) -> Dictionary:
	if not revisions is Dictionary:
		return fail("INVALID_REVISION")
	var required: Array = ["inventory:" + source_id, "inventory:" + target_id, "residents"]
	var canonical: Array = []
	required.sort()
	for key in required:
		if not revisions.has(key) or not Mass.valid_units(revisions[key]):
			return fail("INVALID_REVISION")
		canonical.append([key, int(revisions[key])])
	return {"ok": true, "entries": canonical}

static func bind(action_id, request, snapshot_items, capacities, mass_catalog,
		reservation_rows, trusted_divisibility, resource_revisions, trusted_identity) -> Dictionary:
	var plan: Dictionary = Split.prepare(action_id, request, snapshot_items, capacities,
		mass_catalog, reservation_rows, trusted_divisibility)
	if not plan.ok:
		return fail(plan.code)
	var identity: Dictionary = canonical_identity(trusted_identity)
	if not identity.ok:
		return identity
	var revisions: Dictionary = required_revisions(plan.payload.from_id,
		plan.payload.to_id, resource_revisions)
	if not revisions.ok:
		return revisions
	var mass: Dictionary = canonical_catalog(mass_catalog, true)
	if not mass.ok:
		return mass
	var policy: Dictionary = canonical_catalog(trusted_divisibility, false)
	if not policy.ok:
		return policy
	# Split.prepare already checked item fields, capacities, reservation rows.
	var canonical_items: Array = snapshot_items.duplicate(true)
	canonical_items.sort_custom(func(a, b): return a.instance_id < b.instance_id)
	var canonical_caps: Array = capacities.duplicate(true)
	canonical_caps.sort_custom(func(a, b): return a.id < b.id)
	var canonical_rows: Array = reservation_rows.duplicate(true)
	canonical_rows.sort_custom(func(a, b):
		return JSON.stringify([a.instance_id, a.resident_id, a.quantity]) \
			< JSON.stringify([b.instance_id, b.resident_id, b.quantity]))
	var fingerprint: String = JSON.stringify([
		identity.entries, action_id, plan.payload, canonical_items, canonical_caps,
		mass.entries, policy.entries, canonical_rows, revisions.entries
	], "", true, true).sha256_text()
	return {"ok": true, "code": "OK", "binding_fingerprint": fingerprint,
		"payload": plan.payload, "preview_items": plan.preview_items,
		"split_instance_ids": plan.split_instance_ids,
		"mass_before": plan.mass_before, "mass_after": plan.mass_after}

# The caller must re-read *fresh authoritative* inputs. Old preview arrays
# are NEVER consumed; on success return only the freshly computed plan.
# This is snapshot equality, NOT a lock, transaction or secure signature.
static func revalidate(binding, action_id, request, current_items, current_caps,
		current_mass_catalog, current_reservation_rows, current_divisibility,
		current_revisions, current_identity) -> Dictionary:
	if not binding is Dictionary or not binding.get("binding_fingerprint") is String \
			or binding.binding_fingerprint.length() != 64:
		return fail("INVALID_BINDING")
	var now: Dictionary = bind(action_id, request, current_items, current_caps,
		current_mass_catalog, current_reservation_rows, current_divisibility,
		current_revisions, current_identity)
	if not now.ok or now.binding_fingerprint != binding.binding_fingerprint:
		return fail("STALE_SNAPSHOT")
	return now
