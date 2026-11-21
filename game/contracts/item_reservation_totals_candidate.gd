extends RefCounted

# A1 pure candidate: convert the ACTUAL gameplay reservation-row schema into
# an authoritative per-instance total. Not a save or NPC settlement service.
# Input: snapshot.inventory.items, snapshot.inventory.reservations.
const MAX_EXACT_JSON_INT: int = 9007199254740991

static func _positive_count(value) -> bool:
	return value is int and value > 0 and value <= MAX_EXACT_JSON_INT

static func aggregate(items, reservation_rows) -> Dictionary:
	if not items is Array or not reservation_rows is Array:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var capacities: Dictionary = {}
	for item in items:
		if not item is Dictionary or not item.get("instance_id") is String \
				or item.instance_id.is_empty() or capacities.has(item.instance_id) \
				or not _positive_count(item.get("quantity")):
			return {"ok": false, "code": "INVALID_ITEM"}
		capacities[item.instance_id] = int(item.quantity)
	var sums: Dictionary = {}
	var seen_resident_instance: Dictionary = {}
	for reservation in reservation_rows:
		if not reservation is Dictionary or reservation.size() != 3 \
				or not reservation.get("instance_id") is String \
				or not reservation.get("resident_id") is String \
				or reservation.instance_id.is_empty() \
				or reservation.resident_id.is_empty() \
				or not _positive_count(reservation.get("quantity")):
			return {"ok": false, "code": "INVALID_RESERVATION"}
		var id: String = reservation.instance_id
		var resident_instance_key: String = JSON.stringify([reservation.resident_id, id])
		if seen_resident_instance.has(resident_instance_key):
			return {"ok": false, "code": "INVALID_RESERVATION"}
		seen_resident_instance[resident_instance_key] = true
		if not capacities.has(id):
			return {"ok": false, "code": "INVALID_RESERVATION"}
		var count: int = int(reservation.quantity)
		var prior: int = int(sums.get(id, 0))
		# Bound before addition: never overflow or overbook one trusted instance.
		if count > int(capacities[id]) - prior:
			return {"ok": false, "code": "RESERVATION_OVERFLOW"}
		sums[id] = prior + count
	# Always return canonical key order for deterministic diagnostics.
	var keys: Array = sums.keys()
	keys.sort()
	var canonical: Dictionary = {}
	for key in keys:
		canonical[key] = sums[key]
	return {"ok": true, "code": "OK", "reserved_by_instance": canonical}
