extends RefCounted

# A1-02/G0 CANDIDATE ONLY: pure mass accounting for supplied integer units.
# No production weights, physical units, item categories, or legacy save
# conversions are defined here. No changes to inventory commands or state.
const MAX_EXACT_JSON_INT: int = 9007199254740991

static func valid_units(value, positive: bool = false) -> bool:
	return value is int and value >= (1 if positive else 0) and value <= MAX_EXACT_JSON_INT

static func calculate(items, mass_catalog) -> Dictionary:
	if not items is Array or not mass_catalog is Dictionary:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var seen: Dictionary = {}
	var totals: Dictionary = {}
	for item in items:
		if not item is Dictionary:
			return {"ok": false, "code": "INVALID_ITEM"}
		var instance = item.get("instance_id")
		var type_id = item.get("type_id")
		var container = item.get("container_id")
		var quantity = item.get("quantity")
		if not instance is String or instance.is_empty() or seen.has(instance):
			return {"ok": false, "code": "INVALID_ITEM"}
		if not type_id is String or type_id.is_empty() or not container is String or container.is_empty():
			return {"ok": false, "code": "INVALID_ITEM"}
		if not valid_units(quantity, true):
			return {"ok": false, "code": "INVALID_ITEM"}
		var one_mass = mass_catalog.get(type_id)
		if not valid_units(one_mass, true):
			return {"ok": false, "code": "MISSING_MASS"}
		# Bounds check BEFORE multiplication/summation: never overflow a
		# signed integer or silently lose precision in a JSON checkpoint.
		if int(quantity) > int(MAX_EXACT_JSON_INT / int(one_mass)):
			return {"ok": false, "code": "MASS_OVERFLOW"}
		var group_mass: int = int(quantity) * int(one_mass)
		var prior: int = int(totals.get(container, 0))
		if prior > MAX_EXACT_JSON_INT - group_mass:
			return {"ok": false, "code": "MASS_OVERFLOW"}
		totals[container] = prior + group_mass
		seen[instance] = true
	return {"ok": true, "code": "OK", "mass_by_container": totals}

static func check_capacity(containers, items, mass_catalog) -> Dictionary:
	if not containers is Array:
		return {"ok": false, "code": "INVALID_ARGUMENT"}
	var total: Dictionary = calculate(items, mass_catalog)
	if not total.ok:
		return total
	var caps: Dictionary = {}
	for container in containers:
		if not container is Dictionary or not container.get("id") is String or str(container.id).is_empty() or caps.has(container.id):
			return {"ok": false, "code": "INVALID_CONTAINER"}
		if not valid_units(container.get("capacity_mass_units")):
			return {"ok": false, "code": "INVALID_CONTAINER"}
		caps[container.id] = int(container.capacity_mass_units)
	for key in total.mass_by_container:
		if not caps.has(key):
			return {"ok": false, "code": "INVALID_CONTAINER"}
		if int(total.mass_by_container[key]) > int(caps[key]):
			return {"ok": false, "code": "CAPACITY_EXCEEDED"}
	return total
