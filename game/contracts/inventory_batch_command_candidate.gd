extends RefCounted

# A1 / RFC DRAFT ONLY. Canonicalize a possible multi-item command.
# Pure typed payload normalizer; it DOES NOT move, split or create items,
# choose weights, write saves, grant rewards or publish domain events.
const MAX_EXACT_JSON_INT: int = 9007199254740991

static func normalize(value) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	if value.size() != 3 or not value.has("from_id") or not value.has("to_id") or not value.has("entries"):
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var from_id = value.from_id
	var to_id = value.to_id
	var entries = value.entries
	if not from_id is String or not to_id is String or from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	if not entries is Array or entries.is_empty():
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var normalized: Array = []
	var seen: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary or entry.size() != 2 or not entry.has("instance_id") or not entry.has("quantity"):
			return {"ok": false, "code": "INVALID_ARGUMENT"}
		var id = entry.instance_id
		var qty = entry.quantity
		if not id is String or id.is_empty() or seen.has(id):
			return {"ok": false, "code": "INVALID_ARGUMENT"}
		if not qty is int or qty <= 0 or qty > MAX_EXACT_JSON_INT:
			return {"ok": false, "code": "INVALID_ARGUMENT"}
		seen[id] = true
		normalized.append({"instance_id": id, "quantity": qty})
	# A batch is a set of distinct instance IDs; order of clicks is not a
	# semantic operation. A stable sorted payload can safely feed existing
	# CoreSession fingerprint computation once reviewed by A5/A2/A3.
	normalized.sort_custom(func(a, b): return str(a.instance_id) < str(b.instance_id))
	return {"ok": true, "payload": {"from_id": from_id, "to_id": to_id, "entries": normalized}}
