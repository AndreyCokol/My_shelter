extends RefCounted

# Original prototype balance. Candidate values; UX duration is not yet measured.
static func build() -> Dictionary:
	return {"version": "prototype-v1", "gameplay": true, "minutes_per_real_second": 1.0, "discovery_xp": 5,
		"items": {"seed.basic": {"name": "Семена"}, "crop.potato": {"name": "Картофель"}, "tool.basic": {"name": "Походный нож"}},
		"containers": [{"id": "player", "capacity_units": 30}, {"id": "storage", "capacity_units": 120}],
		"scenes": {"hospital": ["default"], "outside": ["default"], "shelter": ["default"], "louvre": ["default"]},
		"offers": {"seed": {"type_id": "seed.basic", "quantity": 2, "price": 3}},
		"parcels": {"starter": {"type_id": "seed.basic", "quantity": 4, "coins": 10, "eligible": true}},
		"rewards": {"system": {"type_id": "tool.basic", "quantity": 1, "hero_xp": 10, "coins": 8, "eligible": false}},
		"crop": {"grow_minutes": 180, "spoil_minutes": 120, "yield_units": 3},
		"food": {"accepted_food_type_ids": ["crop.potato"], "units_per_resident": 2, "reserve_mode": "reserve"},
		"resource_respawn_minutes": 60, "resource_quantity": 2}

static func validate(rules: Dictionary) -> bool:
	if not rules.get("items") is Dictionary:
		return false
	for key in ["crop", "food"]:
		if not rules.get(key) is Dictionary:
			return false
	for value in [rules.crop.get("grow_minutes"), rules.crop.get("spoil_minutes"), rules.crop.get("yield_units"), rules.get("resource_respawn_minutes"), rules.get("resource_quantity"), rules.food.get("units_per_resident")]:
		if not preload("res://game/state/gameplay_state.gd").integer(value) or value <= 0:
			return false
	if not rules.food.get("reserve_mode") in ["reserve", "consume"] or not rules.food.get("accepted_food_type_ids") is Array or rules.food.accepted_food_type_ids.is_empty():
		return false
	for id in rules.food.accepted_food_type_ids:
		if not rules.items.has(id):
			return false
	return true
